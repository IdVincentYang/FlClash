# L1-T02：删除 Firebase 采集与构建上传

建议完整删除 Firebase Analytics、Crashlytics/NDK、初始化接口和构建上传链，
直接保留现有本地恢复、日志、符号与 R8 映射。方案已通过设计评审；
实施状态与自验结果见任务交付记录。
任务与阶段要求分别见 [L1-T02](loop1_tasks.md#l1-t02-删除-firebase-及上传路径)和
[采集决定](loop1_plan.md#删除已拒绝采集保留可用的本地证据)。

设计绑定 `ea27239`，该提交相对 `2d96343` 仅登记派工；官方源码基线为 `4b59eca`。
工作分支为 `security/l1-t02-firebase`，最终本地合入 `security/android`。

## 基线事实与取舍

以下描述实施前源码基线 `2d96343`；删除后的实际结果见
[L1-T02 交付记录](loop1_tasks.md#l1-t02-删除-firebase-及上传路径)。

- [GlobalState](../../../../android/common/src/main/java/com/follow/clash/common/GlobalState.kt)
  的 `setCrashlytics(false)` 仍先调用 `FirebaseApp.initializeApp`，只修改 Crashlytics 的采集设置。
  `ServiceStateMachine` 在同步共享状态与原生后台恢复配置时均会调用它。
- Dart 设置默认关闭 Crashlytics，原生 `SharedState` 默认开启；两侧均携带该字段。
  `:app` 与 `:common` 都直接依赖 Analytics、Crashlytics NDK 和 Firebase BoM。
  仅删除开关或改默认值不能删除 SDK、初始化组件和构建上传。
- [BootGuard](../../../../lib/common/boot_guard.dart)依据本地 `BootRecord` 和 Android 退出信息决定恢复。
  Firebase 探针只补充 `crashConfirmed`，不决定失败计数、跳过自动设置或取消当前配置选择。
- `CrashlyticsExtension` 与 release finalizer 配置原生符号上传；插件还提供 R8 mapping 上传。
  CI 在签名步骤注入 `SERVICE_JSON`，签名密钥与 Firebase 配置目前在同一步骤处理。

采用删除现有专用链路的方案，不增加替代上报 SDK、关闭状态、迁移框架或报告存储。
Firebase 的[自动初始化实现](https://github.com/firebase/firebase-android-sdk/blob/main/firebase-common/src/main/java/com/google/firebase/provider/FirebaseInitProvider.java)
和[原生符号上传说明](https://firebase.google.com/docs/crashlytics/android/get-started-ndk)
支持对初始化与构建插件分别清理；本项目的实际入口以上述源码为依据。

## 删除范围与保留契约

### SDK、插件和配置

删除 `android/app`、`android/common` 的 Firebase BoM、Analytics 和 Crashlytics NDK 依赖，
清理版本目录中对应条目。删除 settings/app 中 Google Services 与 Crashlytics 插件声明、
扩展配置和上传 finalizer，以及已跟踪的占位 `android/app/google-services.json`。
CI 只删除 `SERVICE_JSON` 注入，保留 keystore、签名属性和正常构建/发布工作流。
Google Maven 仓库仍供其它 Android/扫码依赖使用。

### 初始化、共享状态与旧配置

删除以下专用提供方和消费者，保持服务生命周期仍由 `ServiceState` 仲裁：

- 原生 `GlobalState.setCrashlytics`、`didCrashOnPreviousExecution`；
  `ServiceStateHost` 的对应接口/实现和 `ServiceStateMachine.applySharedState` 中的采集调用。
- `AppPlugin` 的 crash 探针 method-channel 分支，以及 Dart `App`、`System` 包装方法。
- Dart `AppSettingProps.crashlytics`、`crashlyticsTip`，Dart/Kotlin `SharedState.crashlytics`，
  以及 `sharedStateProvider` 的选择、构造和同步字段。

Dart JSON 生成映射和 Kotlin Gson 只消费保留字段；旧配置或共享状态中的
`crashlytics=true/false`、`crashlyticsTip` 被忽略，新的序列化不再输出它们。
不添加迁移开关，不清除其它偏好、`BootRecord` 或历史 SDK 私有缓存。
SDK 已删除后，旧键和缓存没有重新启用上传的消费者；历史数据生命周期由后续存储审查接续。

### 本地恢复与排障

从 `BootGuard` 删除 `readCrashReport` 注入、`crashlyticsEnabled` 参数及探针调用；
从 `resolveBootDecision` 删除 `crashReported` 参数。
`crashConfirmed` 仍由匹配的 Android 退出原因给出，恢复的其它语义保持：

- Android 平台门、`starting/running` 记录、退出时间匹配与 `handledExitAt` 消费；
- 外部停止原因否决失败计数；首次失败跳过 `initStatus`，连续两次失败才取消当前配置选择
  （`currentProfileId=null`），不删除订阅或配置文件；
- `GlobalState.lastExitInfo`、`getLastExitInfo` 通道及缺失/低 API 时的现有返回语义。

保留 `main.dart` 的本地错误显示/日志、`LogsView` 主动导出和现有偏好保存。
本任务不新增异常/dump 持久保存或管理界面，也不修订 L1-T10 的恢复产品边界。

保持 Go Android 库不使用 `-s/-w`、JNI/CMake 的 `-g`、`:core` 的 `keepDebugSymbols`，
并保留 app release 的 R8、混淆规则和本地 `mapping.txt`。
APK 继续采用正常 strip；构建后在本地忽略目录保留已有未剥离库和映射，绑定 APK 的 Build ID/摘要。
移除 Crashlytics 专用符号生成/上传，不新增符号 SDK 或上传工具。
更新相关注释、[生命周期规则](../../../../.agents/rules.md#lifecycle-rules)、
[符号说明](../../../../.agents/architecture.md#android-crash-symbols)和
[构建指南](../../../development/android_build_guide.md)，使其描述本地排障能力与实际上传边界。

### 界面、文案和生成

删除常规设置中的 Crashlytics 开关、启动数据收集提示及其写回字段。
免责声明删除两张 Firebase 服务卡、专用数据处理段落、Google/Firebase 政策链接与专用 badge；
`disclaimerPrivacyContent` 仅移除末尾宣称 Android 集成两项 Firebase 服务的段落。
其它条款、编号、同意/退出流程保持。清理失去消费者的私有 UI helper 和专用 ARB 键。

四种 ARB 正常执行 `intl_utils:generate`；模型和 provider 正常执行 `build_runner build`，
不手改生成结果。必要调整已有 Dart/Kotlin 测试中的删除接口、fixture 和失效断言，
保留现有本地恢复、通知与服务消费者；不新增或运行自动化测试。

## 扫码与名称相似项的边界

当前 `mobile_scanner 7.4.2` 默认声明 `com.google.mlkit:barcode-scanning:17.3.0`。
本地缓存 `com.google.mlkit:common:18.11.0` 的 POM/manifest 和 `MlKitContext` 反汇编表明：

- ML Kit 使用自己的 `MlKitInitProvider` 与 `MlKitComponentDiscoveryService`；
  已读的 `MlKitContext` 初始化路径通过 `firebase-components` 容器加载 registrar，
  不调用 `FirebaseApp`。
- 它依赖 `firebase-components`、`firebase-annotations`、`firebase-encoders*` 及 DataTransport。
  删除 BoM 可能改变这些共享库的解析版本，实施时必须记录实际版本和消费者链。
- `PackageResolver` 的 `firebase-` ZIP 名称判断是检查其它 APK 的本地分类代码，保留。

不对上述名称做全量排除，也不删除扫码初始化组件。最终验收区分这些组件与
Firebase App、Analytics、Crashlytics、Installations 和 measurement 等原收集链。
若删除后仍解析到原收集 SDK，则追溯实际引入方并处理或交评，不能靠名称白名单放行。
ML Kit 的 DataTransport 和运行时采集尚未观测，完整隐私整改继续归 L1-T09。

本阶段调查证据为本地忽略目录中的
[源码入口](../../../../build/verification/l1-t02/source_inventory.log)、
[缓存 POM/manifest](../../../../build/verification/l1-t02/mlkit_dependency_inventory.log)与
[组件消费者反汇编](../../../../build/verification/l1-t02/mlkit_context_javap.log)。
它们是设计依据，不是修改后依赖图或 APK 的验收结果。

## 实施验收安排

| 对象 | 实际检查与通过条件 |
| --- | --- |
| 源码与旧配置 | 删除链的声明/调用与生成映射同步；旧 JSON/Gson 键无重新启用消费者；保留的本地恢复和服务接口静态有效 |
| Android 依赖 | 使用当前源码解析 `:app:dependencies --configuration releaseRuntimeClasspath`，以 `dependencyInsight` 追溯剩余 Firebase 名称项；收集 SDK 及其专用运行依赖消失，保留项有真实扫码消费者 |
| manifest 与任务 | 检查当前合并 manifest、`:app:tasks --all` 及 release assemble/bundle dry-run；FirebaseInitProvider、收集 registrar/组件和 Google Services/Crashlytics 生成上传任务消失，扫码/服务/签名保留 |
| 当前 APK | 按构建指南生成 ARM64 release APK；记录工具、ABI、环境、签名、源码快照、文件 SHA-256；结合依赖图、R8 mapping、DEX 类、ZIP 资源/原生库及最终 manifest 核对目标 SDK 不进入包，不能只用字符串无命中判定 |
| 本地符号 | 核对未剥离 Go/JNI 库的 debug sections/Build ID，与 APK 内对应库绑定；保存本地 R8 mapping 的摘要和必要运行前提 |

构建采用指南的最小环境、启用的 Native Assets hooks、专用 `GRADLE_USER_HOME` 和
已核实的 upload/publish 任务禁用 init script；关闭 Flutter/Dart 遥测。
优先离线并执行 `pub get --enforce-lockfile`，确需下载时只访问官方/已配置依赖来源。
解析、构建或材料缺失如实保留失败证据，不用现存旧 APK 冒充修改后的包。

常规自验为受影响文件格式、`flutter analyze --no-fatal-infos`、生成差异、Markdown 与引用检查。
不执行测试、不安装/启动应用、不触发 CI 或上传符号、映射、APK；设备功能和实际外发保留未验证限制。
实施交回 M 评审后，按约定本地提交、合入并清理临时分支；本任务不推进 L1-T03。

## 实际结果与剩余边界

实施后的依赖图、任务图、当前 APK、合并/最终 manifest、DEX 与 R8 来源核对、
Go/JNI 符号绑定已生成，版本、结论及本地证据入口统一见上述任务交付记录。
Native Assets 使用 NDK 29.0.14206865，JNI 使用声明的 28.2.13676358；
版本统一仍由 Loop 5 处理。扫码 SDK 的运行时外发由 L1-T09 接续，
本任务没有设备运行证据，不将静态删除核对解释为全应用无外发。
