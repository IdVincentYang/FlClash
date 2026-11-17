# Android 构建身份与系统图标 Plan

任务入口：FLClash Review 向 FlClash D2 的“Android 构建基础包名参数与 P8 release 交付”派工。
基线为 security/android `3901a6d`；设计、实现评审与 refine 已完成，签名 release 已安装 P8。
实际结果与验证限制见 [Result](android_package_id_result.md)，用户接手测试，不再操作设备。

## 问题与目标

Android app 的 namespace 与 applicationId 目前都是 `com.follow.clash`，
后者还按原有 buildType／签名条件追加 `.dev`。用户需要构建基础包名为
`com.idvincentyang.mfc` 的 release，与旧应用独立安装；不迁移旧数据，也不卸载旧应用。
仅修改 Gradle 的固定值会丢失默认行为，且应用自身身份判断仍会认错，因此采用显式构建参数。

## 方案与理由

`setup.dart android --android-package-id <base>` 接收基础 applicationId，
经现有 `env.json` → `dart-defines` 链路传递 `ANDROID_PACKAGE_ID`，由 app Gradle 设置
`defaultConfig.applicationId`。未传时保持 `com.follow.clash`，不新增环境隐式覆盖。
参数只用于 Android；至少两段，各段以 ASCII 字母开头，其余为字母、数字或下划线；
空值、空段、空白与标点明确失败。setup 在执行打包前校验，Gradle 同样校验直接 Flutter 入口。
`.dev` 仍由原 buildType／签名分支追加，APP_ENV、candidate 与签名条件不变。

应用流量菜单使用已有 PackageInfo 的实际安装包名判断自身；crash report 主进程摘要使用
当前 variant 生成的 BuildConfig.APPLICATION_ID，保持摘要不输出原始 package／process 文本。
namespace、Kotlin／Java 路径、JNI、MethodChannel 与其它平台不变。
Manifest 已有 `${applicationId}` authorities／权限占位符按实际产物验证，不进行批量字符串替换。

官方 CI 的 `com.follow.clash` 产物校验继续固定；受管 dev profile 保持原身份，拒绝自定义身份，
并在构建记录中明确其基础与最终 applicationId。通用本地 setup 支持自定义身份，
不把参数扩展成发布入口或为受管 profile 增加新的配置面。

## 实施与验证

先更新 [Android build guide](android_build_guide.md)、[架构 build 段落](../../.agents/architecture.md#build-system)
和[受管构建来源契约](../features/security/android_build_sources.md#工具接受与受管构建)的相关说明；
再完成参数、Gradle、实际身份消费者及邻近测试，[Result](android_package_id_result.md)只记录实测结果。

- Flutter setup 测试覆盖默认、指定基础值、非法值、非 Android／受管拒绝，以及 candidate／APP_ENV 保持。
- Gradle 配置检查覆盖默认／指定值下的 debug、无 release key、candidate；签名 release 由实际 APK 验证，
  同时确认非法 define 失败。复用现有 Gradle home，不复制大缓存或构建多套受管 workspace。
- 邻近 Flutter／Kotlin 测试验证实际包名的自身排除与 crash 主进程判断；Python 测试保护受管记录和官方 CI 身份约束。
- 执行 pub get、analyze 和覆盖变更的测试；完成实现评审及 refine 后本地提交到 security/android。
- 从已审代码用现有个人 release key 构建 ARM64 APK，核验包名、版本、证书、非 debug 与源码来源，
  安装到 USB P8 并验证启动；对照旧应用的安装状态，保留旧包及数据，不自动启动 VPN。

## 用户新增范围：显示名称与系统图标

用户经 FLClash Review 明确新增：该分支今后的用户 Android release 默认采用基础包名
`com.idvincentyang.mfc`、名称 `MFC` 和系统／launcher 通用占位图标；本次最终安装须包含三项。
通用入口的无参数默认仍兼容原项目，分支配方是构建时显式选用的参数组合。

新增 `--android-app-name <name>` 和 `--android-system-icon`，沿同一 env.json 链路传
`ANDROID_APP_NAME`／`ANDROID_SYSTEM_ICON=true`。名称非空、不能只含空白或控制字符；
支持 Unicode 和正常标点，Gradle 输出资源时正确处理 Android string／XML 转义。
未传名称保留原 release app_name 与 debug 硬编码标签；显式传入时 app_name、应用 label、
debug label、磁贴、VPN session 和文件提供器统一使用给定名称。notification channel 固有说明不做品牌替换。

系统图标开关将 application 的 icon／banner Manifest 值设为 `@null`，debug 同样沿用参数；
launcher Activity 不另设图标，实际 ApplicationInfo／ActivityInfo 不能仍解析到 FlClash 图标。
未传时保留原图标。此开关不删除图片资源，不改变应用内 UI、磁贴图标和独立 splash 资源；
fallback 由系统／launcher 渲染，外观不保证跨设备一致。它不是自定义图标上传或素材生成功能。
新参数只允许 Android，受管 dev profile 拒绝名称／系统图标覆盖，官方 CI 维持原外观和身份。

长期默认配方放在 [build guide](android_build_guide.md)，唯一维护上述取值、覆盖规则、
可复制命令及 APK／设备验收方式；[commands](../../.agents/commands.md#building)增加强制阅读链接，
架构与来源契约只链接参数边界，不复制配方取值。
增量验证覆盖参数默认／非法／非 Android／受管拒绝，默认与自定义 merged Manifest／资源对照、
特殊字符名称资源编译、实际 release label／icon=0／组件解析，以及 P8 桌面的名称／占位图标与启动。
保留第一阶段未变的包名和 CI 证据，新增部分另记 Result；不推送远端，不导出 Downloads。
