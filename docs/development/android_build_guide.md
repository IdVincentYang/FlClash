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
| Android SDK / Build Tools | 主应用 Platform 37、固定Flutter及插件需要 Platform 35／36；Build Tools 36.0.0／37.0.0 | [Android 版本目录](../../android/gradle/libs.versions.toml)、固定Flutter的FlutterExtension及各插件配置 |
| Android NDK | Gradle 声明 28.2.13676358 | Android 版本目录；Native Assets 实际编译器选择另需核对 |
| Gradle | Wrapper 指向 9.8.0 | [gradle-wrapper.properties](../../android/gradle/wrapper/gradle-wrapper.properties) |

本机已有 Android Studio，可提供 SDK 管理和 JBR；本指南为 Gradle daemon 指定 JDK 17。Flutter 选择的 Gradle 启动器仍可能使用 Android Studio 的 JBR，应分别检查启动器和 daemon。

Native Assets 曾选用本机 NDK 29.0.14206865，与 Gradle 声明不同。每次变更工具环境后检查 hook 日志的实际 C 编译器路径；统一版本与来源校验由 Loop 5 处理。

### 构建来源只读对账

构建记录只读增量已实现并经验证；T03按用户调整范围实现评审通过；交付状态见[Loop5 Tasks](../features/security/loop5/loop5_tasks.md)。原EasyTier源码／生成缺口的明确延期及恢复条件见[备忘](../features/security/deferred_security_items.md#loop5-t03-easytier-wasm-源码与生成对应)。显式选择构建根及可读材料后增加`--build-evidence build`，不会执行Gradle／生成器或自动读取记录中的旧路径。范围和证明限制见[来源契约](../features/security/android_build_sources.md#构建记录与组件来源)。
实现Review发现的续行拼名及路径上跳隐去symlink问题已修正并通过M限定复审。旧报告不追认相关输入；修后会保留原声明和映射依据，含上跳路径逐段核对，不能安全读取时拒绝或报告不可用。

```bash
python3 tool/inspect_android_build_sources.py \
  --apk /absolute/path/to/original.apk \
  --record /absolute/path/to/observation.json \
  --input build=/absolute/path/to/run/source \
  --input pub=/absolute/path/to/run/pub-cache \
  --input sdk=/absolute/path/to/run/flutter \
  --input cargo=/absolute/path/to/run/cargo \
  --input run=/absolute/path/to/run/result.json \
  --build-evidence build --abi arm64-v8a
```

观察record可选`build_evidence`对象：`input`为构建根别名，`context`为原run文件的普通input／sha256引用，`source_commit`为该run源码提交。缺绑定保持unknown，声明矛盾失败。它们不授予发布信任或生成成功。
CMake记录直接声明cwd；depfile没有cwd，相对输入默认`unresolved_relative_path`。确有依据时在`working_directories`中分别声明`flutter_depfile`／`rust_dep_info`的绝对cwd；这仍是外部声明，不能填当前HEAD或猜目录追认历史。目录依赖只报告目录，不计算不存在的内容身份。

实际对象、来源关系与unknown由[来源基线](../features/security/android_build_sources.md)维护，不另复制工具版本表。

先只枚举一个显式APK，或用已选择的观察记录及材料进行对账；`--input`可选一个文件或一个目录，优先选必要的最小范围：

```bash
python3 tool/inspect_android_build_sources.py --apk /absolute/path/to/app.apk
python3 tool/inspect_android_build_sources.py \
  --apk /absolute/path/to/app.apk \
  --record /absolute/path/to/build-record.json \
  --abi arm64-v8a \
  --input compiled=/absolute/path/to/libexample.so \
  --input sources=/absolute/path/to/source-directory
```

观察记录的最小形状如下；零hash是占位，须替换成选择的参考对象／材料摘要，不能仅由待检查包自算一遍就称来源可信：

```json
{
  "apk_sha256": "0000000000000000000000000000000000000000000000000000000000000000",
  "objects": [{
    "entry": "lib/arm64-v8a/libexample.so",
    "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
    "links": [{
      "input": "compiled",
      "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
      "relation": "same_bytes"
    }]
  }]
}
```

记录只能引用已选择的名称：文件选择不允许path扩成兄弟文件；目录选择可加相对path；archive可加member。选择入口自身及目录内symlink均拒绝，不因旧证据含绝对SDK／缓存路径而自行读取。
`objects`只记录部分条目时，输出仍枚举全部APK并标未覆盖；删记录或给空集合不能产生完整覆盖。source_inputs只核所选输入身份，r8只核已选择mapping文件／class定义关系；四种links及限制见来源基线。
工具只输出JSON、不执行构建或下载。需要保存结果时重定向到新的本地证据文件，不覆盖APK或参考输入。退出0可能仍是partial_inventory；退出1为实际绑定矛盾，退出2为非法／越界输入，均不代表发布认证或源码生成结论。
版本／hash／工具选择变化时重新绑定实际对象；新构建不能反证旧APK来源。保留完整显式输入／记录与结果于本地忽略目录，不保存密钥或用户数据作为证据。

### 发布工件接受与受管构建

受管入口提供本节限定的工具／工件校验及构建选择。下述直接构建流程不提供同等校验保证；原T01只读对账的退出0仍可有来源缺口。

受管入口的首次准备须明确选择接受归档和安装payload，核URL／host／版本／角色及摘要；SDK工具、三套pub图及新生snapshot全部在首次加载前完成核验。候选、下载成功、解压完成或lock候选都不能直接成为许可，缺材料应报告具体对象并保留旧材料，不改hash绕过失败。
SDK准备集同时包括Platform35／36／37及Build Tools36／37；只准备主应用声明的37会遗漏固定Flutter与插件消费者。
受管入口在这些材料缺失或不匹配时拒绝进入SDK消费者，不通过伪造license记录或现场安装未知组件补齐。

受管执行只支持本机macOS ARM64到Android ARM64 dev。它在自有构建位置调用原setup／packager，使用自有配置和缓存，不读取或替换原local.properties、.dart_tool或用户全局安装；确认相关子进程退出及对象归属后才清理，退出不明保留该位置并报告失败。发布接受及责任边界见[来源契约](../features/security/android_build_sources.md#工具接受与受管构建)。

入口为`tool/verify_android_inputs.py`。默认只读，单材料检查不会执行被检查的程序：

```bash
python3 tool/verify_android_inputs.py \
  --check-material go \
  --archive go=/absolute/path/to/go1.26.4.darwin-arm64.tar.gz \
  --tree go=/absolute/path/to/go
```

退出0只表示这一材料对应当前接受参考，输出仍为`profile_ready=false`；默认整体检查缺材料时退出1，非法或矛盾输入退出2。
接受锚由[android_artifacts.toml](../../tool/android_artifacts.toml)维护，输入文件不能提供另一套摘要、签名key、policy或命令。

先确保需要构建的应用／依赖改动已进入当前HEAD；入口仅容许有限任务WIP，未允许的未提交改动会在目标工具启动前拒绝。
从原仓库入口运行，不在以前生成的`source/`子目录中重复调用受管构建。
新工作位置及其解析后的父路径只支持可打印ASCII和空格，不能含`:`、`,`、反斜杠或控制字符；
不支持的位置在创建workspace及启动目标工具前拒绝，不自动改名或迁移宿主目录。

实际装配必须明确选择材料并给一个不存在的新位置：

```bash
python3 tool/verify_android_inputs.py \
  --build-from /absolute/path/to/android-inputs.json \
  --workspace "$PWD/build/android-managed-001"
```

选择JSON的字段如下。路径仅选择材料，不是成功凭据；所有接受依据仍从受信仓库读取。

| 字段 | 路径形状与用途 |
| --- | --- |
| `archives` | 每个工具role到归档／独立文件的路径；framework选择固定对象的安全bare Git仓库，必需role不能省略 |
| `trees`（可选） | role到已缓存payload目录；仍先核对应归档，只把核同成员复制到新位置，不在原树执行或携入额外文件 |
| `pub_archives` | 三套标准lock中每个hosted `name-version`到原始tar.gz；不填包版本或候选hash |
| `git_repositories` | 标准lock的`URL@resolved-ref`到对应固定Git对象仓库；不继承原仓库配置或全局activation |
| `maven_root`／`maven_files` | 显式原始数据根，以及`group/path/module/version/filename`到根内相对文件的映射；不是旧Gradle home。无原始数据复用时选择自有空目录和空映射，由native strict首次取得 |

hosted／Git key由app及[两份工具lock](../../tool/android_bootstrap/)确定；未知、缺失或多余选择均拒绝。
API37.0的标准安装元数据来自[受信模板](../../tool/android_bootstrap/android_platform37.package.xml)，不由候选SDK自行提供，也不写license接受记录。
原setup继续编排打包，受管分支用同一已核Dart和显式package_config调用packager源码，Flutter使用`--no-pub`。
控制器仅在新工作树生成`hook-environment.json`、本地hook编译绑定及两处标准user-defines；不要手工创建或复制这些对象来取得执行资格。
Native Assets过滤环境后，两个项目hook通过固定同VM重入恢复当前选择；缺配置、摘要不符、错workspace／工具根或漏传user-define时失败。
失败定位先看对应`source/.dart_tool/hooks_runner/setup`或`rust_api`下的input、stdout／stderr及output，再核本次配置；
仓库默认空绑定保留普通入口行为，不能用环境变量或私有重入参数升级为受管验收。

正常命令结束还须确认两个原builder成功的本次标准metadata及配置依赖，不能只凭APK存在或旧`profile_ready=true`判断通过。
JSON记录实际APK路径／大小／SHA-256；`managed_android_build_completed`只覆盖这个受管profile，
不代替完整源码生成对账或设备运行验收。失败读取新位置的`result.json`、`commands.json`及`logs/`；保留失败现场和原材料，
不要改hash消除错误或把旧结果当执行许可。工作位置保持保留；取消或父进程返回不证明后代已退出，不能据此回收或复用目录。

## 构建前准备

在仓库根目录操作。

1. 按 [fork 同步约定](../../CONTRIBUTING.md)选择工作分支，确认当前改动和需要构建的源码。
2. 安装 Python 3.12 或兼容的 Python 3，执行 `python3 tool/restore_l1_t03_core.py`，再执行
   `git submodule update --init --recursive`。Windows 使用 `python`。
   [源码载体](../../core/patches/l1_t03/manifest.json)从项目配置来源取得公开基线，重建并核对核心 tree/commit；
   新 gitlink 未推送，普通 recursive 初始化不能代替恢复。已有不匹配的本地修改会被保留并报错。
   `--check` 仅在临时对象目录核对现有源码，不下载或覆盖工作区。
3. 确认 Flutter、Go、Rustup 和 JDK 已可调用，并安装 Rust 工具链文件中的 Android target。
4. 保持 [pubspec.yaml](../../pubspec.yaml) 中 setup 与 rust_api 的 `build_assets: true`。Go hook 在编译或返回内层缓存前执行源码检查，载体和实际来源配置同时进入内外层缓存依赖。Go/Rust 由 Native Assets hooks 构建；关闭 hooks 会使产物来源不完整或复用旧库。
5. 保持 pubspec.lock 与 Cargo.lock 的锁定版本。以下流程使用 `--enforce-lockfile`；解析失败时处理版本或缓存原因，不为绕过错误重新生成锁文件。

`setup.dart`会生成忽略的env.json。旧直接入口按项目唯一[distributor声明](../../tool/android_bootstrap/distributor.pubspec.yaml)进行global activation；
受管分支消费已经核验的源码／配置。直接入口与其它host尚未因此获得本profile的验证结论。

### 核心源码恢复与官方同步契约

当前父仓库携带未单独发布的核心 gitlink，其源码通过
[`core/patches/l1_t03/`](../../core/patches/l1_t03/manifest.json)
中的 manifest、Git 二进制文本 patch
和原始 commit bytes 重建。manifest 记录公开 base commit/tree、目标 tree/commit、patch 摘要及变更 blob；
材料不包含编译库、凭据、日志或签名私钥，不维护另一套源码树。

[`restore_l1_t03_core.py`](../../tool/restore_l1_t03_core.py) 从项目配置的来源取得 base，
在隔离临时 index/对象中应用 patch，逐一核对 tree/blob，按原始 commit bytes 重建并核对 gitlink。
不依赖本机已有的私有 commit 对象；保留签名 bytes 而不重新签名。当前核心以公开 base 为唯一 parent，
若以后增加未公开祖先，载体必须提供完整对象闭包。已有修改、缺材料、base 不可取得或摘要不符时失败并保留现场，
不 reset、覆盖或以旧二进制代替源码。

Go 构建 hook 在编译或使用内层缓存前检查恢复内容；patch、manifest、commit bytes、恢复脚本及实际来源配置
同时进入 Native Assets 的外层依赖，缓存命中也保留这些输入。先恢复/check，再初始化其它子模块并按正常步骤构建；
普通 recursive checkout 不能直接取得未发布 gitlink。现有 workflow 已接入恢复命令，源码步骤存在不等于远端 CI 已验证。

同步官方时，先选择可取得的新公开 base，再重放窄 patch、解决实际接口/行为冲突，重新生成 commit/tree/blob 材料和父 gitlink。
不得只改 gitlink 留下失效载体，也不通过选择 ours/theirs 丢弃保护；更新对象不授权改写共享历史或发布核心仓库。
普通父分支推送的既有 carrier 例外与同步步骤由[贡献指南](../../CONTRIBUTING.md#l1-t03-core-source-carrier)维护。

### 限定 Gradle 目录并关闭上传任务

本地构建禁止上传或发布。Firebase 构建上传插件已移除；仍使用本项目专用的 Gradle init script，
在任务图生成后禁用名称以 `upload` 或 `publish` 开头的任务执行。创建或核对以下脚本：

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

使用前缀匹配；按名称包含 publish 来匹配会误停 `prepareLintJarForPublish` 等本地准备任务。
此规则仅限制匹配名称的任务执行，任务仍可注册或进入任务图。
它不提供构建脚本的网络隔离；其它名称的任务、插件及依赖下载仍可联网。
变更构建插件时重新检查其传输行为和任务图。

## 构建 ARM64 APK

Android Core 禁用 ZeroTier；该增量已完成本机验证和 ARM64 构建，未作设备安装验证。
由 Native Assets 的 GoBuilder 按 Android Target 保留基础 tags 并追加 `no_zerotier`，
build、依赖 list 和缓存 fingerprint 使用同一 effective tags；其它平台不跟随追加。
此决定使实际解析到 ZeroTier 节点的配置不再受支持；显式 provider 过滤仍按原语义执行。
provider 初始化完成不能以 Apply 返回判断；等待全部必要 Initial 成功后才接受，失败／超时须关闭候选，
不能静默回退 DIRECT；有效 cache 仍可离线成功。取消后旧工作未退出时不允许新 Core 应用抢先进入。
同一进入契约覆盖 Go Shutdown／Init：关闭未确认完成时不得就地重新初始化；解绑服务不证明 Go 全局关闭或进程退出。
实际规则与兼容边界见[业务数据说明](../features/security/business_data_design.md)，
实际制品及本机验证见[任务定稿入口](../features/security/loop2/loop2_tasks.md#l2-t04-业务数据处理与额外传输审查)；旧 APK 不能据此当作已禁用。

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

项目入口默认构建 release，`--env dev` 选择应用环境。没有完整的正式 keystore 配置时，Gradle 使用 Android Debug 签名和 `.dev` 应用 ID。正式签名由 [app/build.gradle.kts](../../android/app/build.gradle.kts) 决定；签名密钥和 local.properties 留在本地。

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

## 本地符号与 APK 对应

当前构建保留 Go 的调试信息和 JNI 的 `-g`，app release 打包仍剥离 APK 中的库。
用于本地排障的未剥离库来自
`build/app/intermediates/merged_native_libs/release/mergeReleaseNativeLibs/out/lib/arm64-v8a/`
中的 `libclash.so`、`libcore.so`；Java/Kotlin 的 R8 映射为
`build/app/outputs/mapping/release/mapping.txt`。

需要保留时，在下一次构建或清理前将上述文件与对应 APK 复制到本地忽略证据目录，
记录源码快照、ABI、工具/环境与各文件 SHA-256。
使用已安装 NDK 的 `toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-readelf -S` 核对
未剥离库的 `.debug_*` sections；用 `llvm-readelf -n` 比较它与 APK 中同名库的 GNU Build ID，
Go 库还可用 `go tool buildid` 比较 Go Build ID。
APK 中的库可用 `unzip -p <apk> lib/arm64-v8a/<库名>` 写入本地证据目录再检查。
剥离后文件摘要可以不同，Build ID 应对应；仅文件名相同不能证明符号匹配。

这些路径覆盖现有 Go/JNI 和 R8 本地排障材料，不保证完整 Dart、Rust 或 Flutter 符号。
符号、mapping 与 APK 均不自动上传；长期留存及工具来源审查继续由 Loop 5 处理。

本地报告的[构建身份契约](../features/security/crash_reports_design.md#构建身份与隐私)
用 APK 摘要与有限 ELF note 关联本地材料，缺失不猜测；设备行为尚未验收。
历史退出只读其自身身份，不能套用升级后的包版本；Rust 或截断 trace 不保证取得 ID。

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
