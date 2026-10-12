# Android APK 本机构建指南

本指南用于在 macOS Apple Silicon 主机从当前仓库源码构建 Android ARM64 APK，保留依赖下载能力并关闭已知的构建上传任务。构建、APK 和日志复用固定目录，不为每次编译新增结果文档。

ARM64 release 打包流程已验证可用；设备运行、其它 ABI 和网络安全验收由相应 loop 完成。开始安全整改时使用[总计划](../features/security/flclash_security_plan.md)，工具及工件来源问题见[审计基线](../features/security/android_security_baseline.md)与 [Loop 5](../features/security/loop5/loop5_plan.md)。

## 工具前提与版本入口

以下是当前源码已验证可构建的组合。升级或同步官方代码后，先检查版本入口，再调整本地环境。

| 工具 | 当前组合 | 仓库中的版本或配置入口 |
| --- | --- | --- |
| Flutter / Dart | 3.47.4 / 3.13.3 | [发布 CI](../../.github/workflows/build.yaml)的 FLUTTER_VERSION；Dart 随 Flutter 提供 |
| Go | 1.26.4 | 发布 CI 的 GO_VERSION、[核心 go.mod](../../core/go.mod) |
| Rust | 1.98.1，包含 aarch64-linux-android target | [rust-toolchain.toml](../../plugins/rust_api/rust/rust-toolchain.toml) |
| JDK | 17 | [Android Gradle 配置](../../android/app/build.gradle.kts)；本机可用 java_home 选择 |
| Android SDK / Build Tools | 主应用 Platform 37、插件需要 Platform 35；Build Tools 37.0.0 | [Android 版本目录](../../android/gradle/libs.versions.toml)及各插件配置 |
| Android NDK | Gradle 声明 28.2.13676358 | Android 版本目录；Native Assets 实际编译器选择另需核对 |
| Gradle | Wrapper 指向 9.8.0 | [gradle-wrapper.properties](../../android/gradle/wrapper/gradle-wrapper.properties) |

本机已有 Android Studio，可提供 SDK 管理和 JBR；本指南为 Gradle daemon 指定 JDK 17。Flutter 选择的 Gradle 启动器仍可能使用 Android Studio 的 JBR，应分别检查启动器和 daemon。

Native Assets 曾选用本机 NDK 29.0.14206865，与 Gradle 声明不同。每次变更工具环境后检查 hook 日志的实际 C 编译器路径；统一版本与来源校验由 Loop 5 处理。

## 构建前准备

在仓库根目录操作。

1. 按 [fork 同步约定](../../CONTRIBUTING.md)选择工作分支，确认当前改动和需要构建的源码。
2. 执行 `git submodule update --init --recursive`，获取锁定的 Clash.Meta 源码。
3. 确认 Flutter、Go、Rustup 和 JDK 已可调用，并安装 Rust 工具链文件中的 Android target。
4. 保持 [pubspec.yaml](../../pubspec.yaml) 中 setup 与 rust_api 的 `build_assets: true`。Go/Rust 由 Native Assets hooks 构建；关闭 hooks 会使产物来源不完整或复用旧库。
5. 保持 pubspec.lock 与 Cargo.lock 的锁定版本。以下流程使用 `--enforce-lockfile`；解析失败时处理版本或缓存原因，不为绕过错误重新生成锁文件。

`setup.dart` 会生成忽略的 env.json，并激活其中指定的 flutter_distributor Git 版本。依赖和工具来自项目配置的数据源；来源核验及进一步固定版本见 Loop 5。

### 限定 Gradle 目录并关闭上传任务

当前 Crashlytics 插件会把 mapping 上传加入 release 任务图；正式签名配置还会加入原生符号上传。先创建本项目专用的 Gradle init script：

```bash
mkdir -p .buildlog/android-build/gradle-home/init.d
cat > .buildlog/android-build/gradle-home/init.d/disable-uploads.gradle <<'GRADLE'
gradle.taskGraph.whenReady { graph ->
    graph.allTasks.each { task ->
        def name = task.name.toLowerCase(java.util.Locale.ROOT)
        if (name.startsWith('upload') || name.startsWith('publish')) {
            task.enabled = false
            task.onlyIf { false }
            logger.quiet('Local build: disabled transfer task ' + task.path)
        }
    }
}
GRADLE
```

使用前缀匹配；按名称包含 publish 来匹配会误停 `prepareLintJarForPublish` 等本地准备任务。此规则覆盖上述 Gradle 任务，不提供构建脚本的网络隔离；依赖下载仍使用网络。变更构建插件时重新检查其传输行为和任务图。

## 构建 ARM64 APK

示例使用本机常见 SDK 与工具路径；工具安装位置不同时调整 PATH 和 SDK 路径。Rust 版本读取仓库配置，实际编译器目录优先于 Homebrew，避免 Cargo 调用没有 Android 标准库的另一份 rustc。

```bash
set -euo pipefail
build_java="$(/usr/libexec/java_home -v 17)"
build_rust_version="$(awk -F'"' '/^channel = / {print $2}' plugins/rust_api/rust/rust-toolchain.toml)"
build_rust_bin="$(dirname "$(rustup which rustc --toolchain "$build_rust_version")")"

env -i \
  HOME="$HOME" \
  PATH="$build_rust_bin:$HOME/.local/bin:$HOME/.pub-cache/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" \
  TMPDIR="${TMPDIR:-/tmp}" LANG=en_US.UTF-8 TERM=dumb SHELL=/bin/bash \
  CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}" \
  RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}" RUSTUP_TOOLCHAIN="$build_rust_version" \
  PUB_CACHE="${PUB_CACHE:-$HOME/.pub-cache}" \
  ANDROID_HOME="$HOME/Library/Android/sdk" \
  ANDROID_SDK_ROOT="$HOME/Library/Android/sdk" \
  JAVA_HOME="$build_java" GRADLE_OPTS="-Dorg.gradle.java.home=$build_java" \
  GRADLE_USER_HOME="$PWD/.buildlog/android-build/gradle-home" \
  FLUTTER_SUPPRESS_ANALYTICS=true \
  /bin/bash -c '
    set -euo pipefail
    dart --disable-analytics
    flutter --suppress-analytics pub get --enforce-lockfile
    dart setup.dart android --arch arm64 --env dev
  ' > .buildlog/android-build/build.log 2>&1
```

最小环境减少构建脚本继承的无关环境变量。Dart 禁用 analytics 会保存本机工具偏好；Flutter 的环境变量和命令参数同时禁止构建遥测。HOME 和缓存仍是本机原有目录，脚本访问本地文件的权限维持当前用户权限。

项目入口默认构建 release，`--env dev` 选择应用环境。没有完整的正式 keystore 配置时，Gradle 使用 Android Debug 签名和 `.dev` 应用 ID。正式签名由 [app/build.gradle.kts](../../android/app/build.gradle.kts) 决定；正式密钥、google-services 配置和 local.properties 留在本地。

## 判断是否成功

命令退出码为 0，且存在以下产物，表示编译与打包完成：

- Flutter 输出：`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`。
- 项目打包输出：`dist/FlClash-<version>-android-arm64-v8a.apk`，版本取自当前项目。
- 最终日志：`.buildlog/android-build/build.log`，构建上传任务应显示禁用，依赖下载和本地准备任务应正常完成。

可在本地检查 APK 摘要、包信息与签名：

```bash
build_apk="$PWD/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
build_tools="$HOME/Library/Android/sdk/build-tools/37.0.0"
shasum -a 256 "$build_apk"
"$build_tools/aapt2" dump badging "$build_apk"
"$build_tools/apksigner" verify --verbose --print-certs "$build_apk"
unzip -t "$build_apk"
```

这些检查说明受检 APK 的包信息、签名和 ZIP 完整性；运行兼容性、SDK 外发和实际网络出口还需要 Android 验收。SDK、Flutter Engine 和 Maven 中的预编译运行依赖仍属于来源审查范围。

## 排查与维护

| 现象 | 检查和处理 |
| --- | --- |
| Rust 找不到 Android 标准库 | 查看日志实际 rustc 路径和版本；检查被选中的 Rust 工具链 target。仅设置 RUSTUP_TOOLCHAIN 或安装 Rustup target，不能保证 PATH 中的另一个 rustc 有对应 sysroot |
| Go/Rust hook 失败或疑似使用旧库 | 查看 `.dart_tool/setup_build_cache/hook.log`；核对源码、目标、编译器和指纹。需要重建时按 [.agents/commands.md](../../.agents/commands.md)删除对应 hook 缓存 |
| Gradle JDK 不匹配 | 检查 JAVA_HOME、GRADLE_OPTS 和 daemon 的实际 Java 版本 |
| SDK Platform 缺失 | 检查主应用与插件 compileSdk，通过 Android Studio 或官方 sdkmanager 安装所需版本 |
| 依赖解析或下载失败 | 核对项目配置的数据源、版本与锁文件；保留失败原因，避免以第三方预编译核心替换源码构建 |
| 上传任务执行或安全门未生效 | 停止该构建，确认专用 GRADLE_USER_HOME 和 init script 是否被加载；检查新增插件的任务与网络行为 |

构建日志、缓存和 APK 保存在忽略目录，后续构建可覆盖同名文件。需要保留某项安全验收证据时，在所属 tasks 文档记录受测源码、配置、命令及结果摘要，原始证据留在本地；无需另建单次编译文档。

当前 Wrapper JAR 与发行包版本不一致、NDK 选择不一致及资产来源未闭环的发现统一维护在审计基线。官方更新改变工具链或构建行为时，更新本指南并重新验证受影响步骤。
