# Android APK 本机构建验证记录

2026-10-12 验证结果：Android ARM64 release 编译与项目打包入口通过，APK 签名及 ZIP 完整性检查通过。未安装或运行应用；安全整改尚未开始。

## 受测对象与产物

- 主仓库：`4cc09e0ee6e489bb3288db77b34e9f6d36a3ecd2`。本轮只修改文档和忽略规则，应用源码与审计基线 `4b59eca853778d4e7be3de26589252889c899bc5` 一致。
- Clash.Meta：`8597778c7df410ebe88c57e59eaab32d203156df`。
- 构建入口：`dart setup.dart android --arch arm64 --env dev`。
- 构建模式：release；无正式签名配置，按项目规则使用 Android Debug 签名和 `.dev` 应用 ID。
- 本地产物：`dist/FlClash-0.8.99-android-arm64-v8a.apk`，61,283,998 字节。
- APK SHA-256：`0fa4e46282714eb8af496579c28af306b517b3037fc5e23aa7e7c696a7c09769`。

| 项目 | 实际结果 |
| --- | --- |
| 应用 ID | com.follow.clash.dev |
| versionName / APK versionCode | 0.8.99 / 2026102301 |
| minSdk / targetSdk | 24 / 37 |
| ABI | 仅 arm64-v8a |
| 签名 | apksigner 验证通过，v2，Android Debug，RSA 2048 |
| 包完整性 | ZIP 全部条目完整性检查通过 |
| 原生库 | 包含 libapp.so、libflutter.so、libclash.so、libcore.so、librust_api.so；共 15 个 ARM64 原生库 |

## 已验证的流程

| 步骤 | 结果与依据 |
| --- | --- |
| 依赖解析 | `flutter pub get --enforce-lockfile` 通过；项目锁文件未变更 |
| Go 核心 | CGO c-shared 的 Android ARM64 编译通过；库构建信息显示 Go 1.26.4 |
| Rust API | aarch64-linux-android release 编译通过，生成 librust_api.so |
| Flutter | release AOT 编译通过，生成 ARM64 app.so |
| Gradle / APK 打包 | assembleRelease 与 flutter_distributor package 通过 |
| 最终重跑 | Gradle 约 34.1 秒；复用同一源码输入生成的原生库缓存 |
| 上传保护 | 最终任务图仅禁用 uploadCrashlyticsMappingFileRelease；本地准备任务正常执行 |

## 工具与环境问题

使用 Flutter 3.47.4 / Dart 3.13.3、Go 1.26.4、Rust 1.98.1、Gradle 9.8.0、JDK 17.0.19 和 Android Build Tools 37.0.0。Gradle 启动器使用 Android Studio 的 JBR 25.0.3，daemon 使用指定的 JDK 17。

首次尝试在 Rust 阶段失败：Cargo 虽由 Rustup 启动，但从 PATH 调用了 Homebrew Rust 1.98.0，其 sysroot 没有 Android 标准库。把 Rustup 1.98.1 的编译器目录放到 PATH 前面后通过。复现时必须保留这一工具选择，不能仅凭 Rustup target 已安装就认为 Cargo 会使用对应 rustc。

Gradle 为部分插件补齐了官方 Android SDK Platform 35 revision 2；主应用使用已安装的 Platform 37。Gradle 声明 NDK 28.2.13676358，Native Assets 实际选用了本机 NDK 29.0.14206865。该差异已归入 [Loop 5](../features/security/loop5/loop5_plan.md)，本轮没有统一工具选择。

## 来源核对

- Gradle 9.8.0 all ZIP 的 SHA-256 为 `46ac66d47f30f3dacfdf306e0b714a91a34fb94a22ba0a744b280933f47bc0cf`，与[官方摘要](https://services.gradle.org/distributions/gradle-9.8.0-all.zip.sha256)一致。
- 仓库 Wrapper JAR 的 SHA-256 为 `16caeaf66d57a0d1d2087fef6a97efa62de8da69afa5b908f40db35afc4342da`，对应[官方 checksum 列表](https://gradle.org/release-checksums/)中的 Gradle 2.10，未升级到 9.8.0 对应 Wrapper。
- setup.dart 指定的 flutter_distributor 标签解析为 `7fea25d4c531ce6e778db14e3c47f076027a1008`，与此前保存的审计源码提交一致。

这些核对不等于全部 Maven 工件、第三方 SDK 和嵌入资产都已完成安全审查；来源与完整性整改见 [Android 审计基线](../features/security/android_security_baseline.md)。

## 复现本次构建

在仓库根目录创建 `.buildlog/android-build/gradle-home/init.d/disable-uploads.gradle`，写入以下内容。Gradle 用户目录限定在本项目，日志与缓存不提交到 Git。

```groovy
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
```

以下命令针对本次 Apple Silicon 主机的 Android SDK 路径。构建使用最小环境，避免三方构建脚本继承无关凭据和个人环境变量。

```bash
dart --disable-analytics
FLUTTER_SUPPRESS_ANALYTICS=true flutter --suppress-analytics pub get --enforce-lockfile
build_java="$(/usr/libexec/java_home -v 17)"
build_rust_bin="$(dirname "$(rustup which rustc --toolchain 1.98.1)")"
env -i \
  HOME="$HOME" \
  PATH="$build_rust_bin:$HOME/.local/bin:$HOME/.pub-cache/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" \
  TMPDIR="${TMPDIR:-/tmp}" LANG=en_US.UTF-8 TERM=dumb SHELL=/bin/bash \
  CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}" \
  RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}" RUSTUP_TOOLCHAIN=1.98.1 \
  PUB_CACHE="${PUB_CACHE:-$HOME/.pub-cache}" \
  ANDROID_HOME="$HOME/Library/Android/sdk" \
  ANDROID_SDK_ROOT="$HOME/Library/Android/sdk" \
  JAVA_HOME="$build_java" GRADLE_OPTS="-Dorg.gradle.java.home=$build_java" \
  GRADLE_USER_HOME="$PWD/.buildlog/android-build/gradle-home" \
  FLUTTER_SUPPRESS_ANALYTICS=true \
  dart setup.dart android --arch arm64 --env dev
```

本机脚本保存在 `.buildlog/android-build/run.sh`。Flutter 构建输出为 `build/app/outputs/flutter-apk/`，项目打包输出为 `dist/`；以后重建可能覆盖同名 APK，应重新核对摘要。

## 证据与限制

本地保留最终日志 `.buildlog/android-build/build.log`、Rust 编译器混用失败日志 `.buildlog/android-build/build-rust-path-failure.log` 和原生核心日志 `.dart_tool/setup_build_cache/hook.log`。这些日志及 APK 未上传；本记录只提交结果摘要和复现步骤。

本次只证明选定工具环境下的 ARM64 release 构建与打包流程通过。没有安装到设备、验证 Android API 24–37 的运行兼容性、执行网络行为验收、编译其它 Android ABI，或比较官方发布 APK 的可复现性。Firebase、Geo 数据、配置与请求路径等安全发现仍按各 loop 处理。
