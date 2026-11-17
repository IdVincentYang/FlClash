# Android 构建身份与系统图标 Result

对应 [Plan](android_package_id_plan.md)。实现评审与 refine 已通过，已本地提交，
完成正常签名 release 构建及 P8 安装／桌面／启动验收。用户已接手测试，不再操作设备。

## 已验证的行为

普通 setup 支持基础 applicationId、显示名称及系统图标开关，通用无参数默认保持；
受管 dev 与官方 CI 的原身份边界不放宽。应用自身菜单使用真实 PackageInfo；
crash 主进程摘要使用 variant 的 BuildConfig.APPLICATION_ID，不暴露原始 package／process。
长期用户 release 配方在 [build guide](android_build_guide.md#当前分支-android-release-默认配置)，
agent 构建入口已要求遵循该配方。

| 验证 | 实际结果 |
| --- | --- |
| pub get／Flutter 覆盖测试 | 成功；setup、应用活动与连接页面共 111 项通过 |
| analyze | 成功，无 error／warning；42 条既有 info |
| Python | 24 项通过；受管 identity intent 记录、CI release 及真实 SDK 的包名拒绝案例 |
| Gradle 配置 | 默认／自定义基础值下 debug、无 release key、candidate 后缀正确；7 个非法／受管覆盖案例按预期拒绝 |
| Android 编译及 Robolectric | 三种配置各 23 项通过：crash 22 项、资源／组件夹具 1 项 |

资源夹具从实际编译资源读取 app_name 和 ApplicationInfo／launcher label，MFC icon 解析为 0；
含中文、`&`、引号、反斜杠及 `@` 前缀的名称保留原文。默认 debug 标签与项目图标仍在。
资源验证未运行 Dart 编译任务，复用既有 Flutter assets，不作为完整 APK 证明；最终 release 将走正常 setup／hooks。

验证中修正了 AGP 资源生成功能开关，以及 debug label 直接内嵌时丢失反斜杠的问题；
debug 显式名称现引用共享资源。两次临时 Gradle 夹具配置错误和一个 crash 保存状态预期错误均已修正，
失败日志保留，不计入通过结果。

## 依据与边界

源码基线 `3901a6d6519d8705a7092bfec0ebae49639a8479`，任务源码差异及文件摘要随交接冻结在
`.buildlog/android-package-id/implementation-01/`；实际命令、日志、资源夹具与 XML 结果在
`.buildlog/android-package-id/checks-02/`。第一批 Python 结果在 `checks-01/python-tests.log`，
其后相关 Python 源码未改变。证据仅保存在本地忽略目录，不纳入 Git。

尚未重跑完整受管 native build、真实云端 CI、其它平台／ABI，也未声称系统 fallback 图标跨设备同形。

## 签名 release 与设备交付

从 `f0b4360645c4aaf0fb7d2b0d9b0a8e1e4d6b0215` 经普通 setup／native hooks 构建 ARM64 release，
Core 为 `7a620b930bdcb85e466450880313d34add46252b`，采用 guide 的三参数配方和现有个人 release key。
真实 APK 的 applicationId 为 `com.idvincentyang.mfc`，label 为 `MFC`，
versionName 为 `0.8.99`，versionCode 为 `2026102301`（pubspec 基础值加 ARM64 split 偏移）。
application icon／banner 为 `@null`，无 roundIcon，launcher 未覆盖 icon；源码组件名未改变，
authorities、自定义 permission／action 均使用新安装身份。

APK 非 debuggable，ZIP 完整，libclash／libapp 与本次 stripped 输出一致；
签名证书 SHA256 为 `5061a3b8a8b4eeb26e122da2d20255e2a274c7612c310c0ccceb4b49a28fabf3`。
制品为 `.buildlog/android-package-id/release/FlClash-0.8.99-android-arm64-v8a.apk`，
55,709,461 bytes，SHA256 为 `a789f2c0179377d6f20bf472fc9d3424d1464a63a556c72166a35c7a8cd8f693`。
实际配置及观察分别记在 `release/release.json`，原临时签名配置已按字节／权限恢复。

首次 USB 安装与只读查询无响应；停止自有挂起客户端后，应用户要求重试，仅重连 P8 的 ADB 通道。
查询恢复并确认新包未安装，再执行 `adb install -r --no-incremental` 返回 `Success`。
设备中 APK SHA256 与本次制品一致；ApplicationInfo 及 launcher 的 icon 解析为 0，
Pixel Launcher 实际显示 `MFC` 和 Android 通用占位图标。冷启动返回 `Status: ok`，
主进程随后仍在且其 crash buffer 无 fatal 记录，未请求启动 VPN。

旧 `com.follow.clash` 保持版本 `2026113106`，安装前后的 APK hash、路径、appId、
首次安装时间与 ce／de data inode 均一致；未卸载或清数据。
设备事实在 `release/device.json`、`device-resolve.txt`、`device-launch.txt` 和
`old-package-{before,after}.json`，桌面观察在本地 `device-app-drawer.png`。
本次交付记录更新只改变文档，与构建源提交的生产源码逐文件一致，不机械重新构建。
未验证本次新包的真实订阅／VPN 代理用例，交由用户接续测试。
