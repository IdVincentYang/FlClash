# 02 内存汇总与应用活动只读页 Result

NA-T01-02 已交付 Android 的 Tools → 应用网络入口、第一层只读页和有界内存汇总。
可以搜索应用，切换近期活动／当前活跃／全部应用，展开身份、接管设置、实际规则与出口摘要。
03–09 尚未开始；目标列表／详情和就地修改规则由后续任务分别交付。
有效契约见 [Design](network_activity_design.md)，复现入口见
[Android 验证说明](../../../android/tests/device/network_activity/README.md)。

## 受测版本与实现

实施基线为 7dea604，沿用 01 的 Native 采集，没有修改 Go／Kotlin 或 Clash.Meta gitlink。
本地 `build/verification/na-t01-02/source-binding.json` 绑定变更的生产文件、APK 和 Native 库。
productionFiles 按键排序、紧凑 JSON 编码后的 SHA-256 为
`dbdd49c82bb9f6ce4c2d4da86302de3658b5f455a6aefdb7e4f9bff8edbd34b3`。
最终 ARM64 debug APK SHA-256 为
`b9511bd432c5112c174f064f58a045a9dcfae221b5a6fe19e46be80b29182378`，
Gradle 调试签名 SHA-256 为
`5a7c9cb8db640dfac17b75daba333e285ba76595e6e71b2d7d2d0e851f8849ec`。
提交前核对生产文件摘要，后续整理仅涉及测试、文档和提交信息。

ApplicationActivityStore 合并原 request 事件与完整 getConnections 快照，最多保留 4096 条连接；
App、App＋Host、Host 跨 App 查询使用同一集合，不另存事件文件。首份连接事实保持不变，
快照只更新流量与存活；未知身份、共享 UID、未知规则和观察缺口均显式保留。
根部 CoreManager 保持订阅，页面不拥有观察生命周期，也不调用 Start、来源接受或规则修改。

验证中发现根部观察器提前读取 Native／配置依赖会阻塞 bootstrap，已改为等待 initProvider 就绪；
启动前不触及这些依赖，开始观察时只从既有 Requests 有界缓冲补入同实例事件。
Android 的新安装及保留合成订阅的冷启动均完成，boot_record 为 running／setup，失败计数为 0。
另修正活动排序时展开状态随列表位置转移的问题，按应用身份保留子项及展开状态。

## 自动化与性能

| 检查 | 实际结果 |
| --- | --- |
| flutter pub get --enforce-lockfile | 成功，锁文件不变 |
| build_runner／intl_utils | 成功；生成文件经生成器产出，未纳入无关 action hash 漂移 |
| flutter analyze --no-fatal-infos | 成功；42 条原有 info，无新增错误／警告／info |
| 新增汇总、provider、根部 manager、widget | 32 项通过，包含 195 条实际 JNI 事件回放 |
| 最终定向检查，含 l10n 与动态文案键 | 38 项通过 |
| 启动隔离及既有 bootstrap／CoreManager | 35 项通过 |
| 扩展 Flutter 回归 | 615 项通过、5 项失败；基线对照见下文 |
| Android ARM64 debug APK | 构建成功，最终日志无“修改后须重建”提示；签名校验成功 |
| 本地夹具 Python 编译／Core carrier 检查 | 通过 |

测试覆盖三个查询范围、重复事件、短连接、失败快照、读取期间新增事件、异实例迟到结果、
后台／返回、停止保留、清空边界、旧事实冻结和容量淘汰。完整快照缺失或存在无效条目时失败，
不能把部分结果当成全部连接已结束。原 Requests 和 CoreManager 行为保留。
页面覆盖入口、筛选、搜索、展开、目录加载／失败重试、空态、未知、共享 UID、快照失败，
以及排序后展开身份、320 宽度和两倍字体；既有接管设置与实际 VPN 证据分别显示。

01 的 195 条实际 Android JNI 事件经过生产解码后，汇总为 99 条唯一 UID、96 条共享 UID 记录及 3 个应用身份组。
这属于真实 Native 数据回放，不替代本轮 Android UI 运行。

主机 debug／JIT 下，加入 10000 条连接并保留 4096 条耗时 22.951 ms；
连续 100 轮同时查询三个范围共 164.668 ms，约每轮 1.65 ms。
输入构造及断言计入测试耗时，不能据此推断 Android 长期内存、真机耗电或公网吞吐。

扩展回归的 5 个失败均在 7dea604 对照中复现：

- update_dialog_test 的 3 个用例缺少当前请求来源条件，抛出 RequestUnavailable。
- uncovered_views_test 的脚本编辑用例加载现有 macOS Rust dylib 失败，报 LINKEDIT string pool 未对齐。
- design_package_test 指向未修改的 test/bootstrap_test.dart:10，仍直接导入 Flutter Material。

基线对照使用归档源码和同一主机库，目录中的 tool／plugins 指向未修改的原实现；
诊断副本只关闭自身构建 hooks，未改生产 pubspec。日志分别保存原失败与基线失败，未写成全套通过。
最终本地化整理仅去除本项 ARB 占位符元数据，随后重新生成、构建并通过 38 项直接相关检查；
扩展回归对应整理前相同业务实现，不重复声称为最终生成文件的全量通过。

## Android UI 结果

使用用户允许的当前 emulator-5554／Android 14、API 34 ARM64，不创建专用 AVD。
仅安装开发包和两个受控客户端，通过正常导入界面接受本地合成 Profile；
Access control 只包含这两个客户端。来源关闭 DNS、NTP 及自动测速，只访问主机本地回声／SOCKS5 夹具。
没有读取或使用真实订阅，未上传 APK、日志或截图。

最终业务版本的首次复验中，A／B 各产生 TCP、已连接 UDP、未连接 UDP 各两条，
页面各显示 Active 6／Observed 6。之后两应用各追加 3 条立即关闭的连接，页面各保留 Observed 9。
客户端分别自报 UID 10199／10200、目标及响应成功，页面归属一致；
展开 B 显示 DstPort 64517、Match、DIRECT、fixture.exit → fixture.group，与受控路径一致。
追加 A 的活动使其排序到 B 前面，B 仍展开，A 保持收起。
停止代理后两应用各保留 9 条，活跃状态为待确认，不误报为零。
这组 18 条验证使用 source-binding 中 previousGateBuild；与最终包只差本地化参数生成类型整理。

最终 Gradle 签名包另验证保留订阅的冷启动、重启后的空统计及实际 VPN 就绪后的连接汇总，
两个应用各 6 条受控连接均成功，并各显示 Active 6／Observed 6；全部应用与搜索亦通过。
观察范围限于实际 VPN 就绪后送达的数据；点击 Start 到 Native 可用之间的流量不保证采集。
后台／切回后显示可能存在观察缺口，不宣称后台短连接完整。
客户端立即关闭不保证 Native UDP tracker 同时消失，因此不以客户端关闭瞬间推断所有 Active 应为零。

UI XML／截图、客户端独立事实及主机收包保存在本地 `build/verification/na-t01-02/device/`；
测试日志在 `.buildlog/android-build/na-t01-02-*.log`。原始证据及二进制不纳入 Git，
保留夹具源码、命令入口与本结果，支持后续任务复验。

## 交付边界与整理

本项只提供第一层只读体验及共用汇总。历史仅在当前内存，进程退出或 Core 实例更换允许重置；
清空、停止或目录失败不删除规则。未观测到连接不能推断应用没有联网或当前未接管。
旧 Android、工作资料／多用户真机、长期后台、耗电和 Release R8 未进行本项设备验收。
Go／Kotlin 生产实现未变化，未重复 01 的整套 Native 性能与兼容矩阵。

提交前由同一执行者复核模型、store、provider、Core facade、根部 manager 和 UI 的职责与生命周期；
没有创建第二个采集通道或服务状态所有者。这是自审，不是独立评审。
Markdown 以 120 字符行长、表格／代码块不限制的配置检查，增量违规为零；
原 architecture.md 的 22 处已有行长问题单列。引用与既有 Mermaid 做静态检查，未宣称图形预览。

收尾停止本任务的本地夹具，卸载两个受控客户端，清理开发包的合成订阅与临时诊断 APK／归档；
保留最终调试包、必要本地证据及用户当前模拟器，代理停止。共享构建缓存和其它应用不清理。
02 的 Plan／Result 供尚未开始的 03–09 复用，当前阶段保留；后续整体收尾再按文档规范整理。
