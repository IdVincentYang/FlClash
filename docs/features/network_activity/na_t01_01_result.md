# 01 应用身份与连接信息采集 Result

NA-T01-01 已实现连接观测基础，并在 Android 14／API 34 ARM64 模拟器上完成本项验证。
无 App 规则、find-process-mode=off 时，受控 TCP、已连接 UDP、未连接 UDP 均取得正确的应用归属；
真实共享 UID 保留歧义。未交付 App／Host 汇总或新页面，02–08 尚未开始。
实现契约见 [Design](network_activity_design.md)，复现步骤见
[Android 验证说明](../../../android/tests/device/network_activity/README.md)。

## 受测版本与条件

2026-11-11 验证，输入基线 048e99b，加本任务变更；Clash.Meta gitlink 保持
6c6e3e472bb246cc55f2e8577d9eddccc2623afc，未新增子模块修改。
提交时逐文件核对生产源码与受测快照一致，后续整理只涉及测试和文档。

本地 `build/verification/na-t01-01/source-binding.json` 保存生产文件 SHA-256、APK 与库摘要。
对 productionFiles 对象按键排序、紧凑 JSON 编码后的 SHA-256 为
`6827193b4745845bc220d1a9484b28b7835d73991df4653edfe97bdd57114490`。
受测 APK 为构建 APK 的调试重签副本，其 SHA-256 为
`f988a21b2ebc3094c14e738bfadb590c69f1518146141dd981a23838855b1519`；其中 libclash.so 为
`c665cba8e4422cfae83f259cc7fecd127d7a0055d16ed08453e5690620c78abd`。

基线对照使用同一最新 Kotlin／Dart APK 模板，仅将 libclash.so 替换为 048e99b 的 parent Go 构建，
两份 APK 的 classes.dex 摘要相同。双方均为 ARM64、API 24、c-shared、
with_gvisor,no_zerotier、保留符号的 debug 库；不将旧正式 APK 与新开发包混作性能对照。

按用户许可使用当前 emulator-5554／Pixel_7a_API_34，清理开发版数据后测试。
四个受控客户端自报 UID 和 socket，宿主的独立回声／SOCKS5 服务记录收到及转发的数据。
只访问本地服务，不使用原订阅或外部测试站点。instrumentation 调用正式原生接口、
接受合成来源并使用实际 VPN，不启动 Flutter UI，也不添加生产测试后门。

## 系统级结果

最终 candidate 与 baseline 各运行 195 条受控 socket、各产生 195 条 Core request 事件。
以下计数指受控 socket／Core association，不代表 HTTP 请求次数或任意流量的完整审计。

| 场景 | 数量 | candidate 结果 |
| --- | ---: | --- |
| Rule／Global／Direct，无 App 规则 | 每种 48，共 144 | TCP、已连接 UDP、未连接 UDP 均可用；唯一 UID 归属正确 |
| shareda／sharedb，真实共享 UID | 48 | ambiguous，包含两包候选；不把任一包填成 process |
| 512 KiB 回声及配套 UDP | 3 | 成功，唯一 UID 归属正确 |
| 唯一 UID 的全部记录 | 99 | 均已识别，未知 0，误归属 0 |
| 共享 UID 的全部记录 | 96 | 均保留歧义，误归属 0 |
| 立即关闭的短连接 | 48 | 均进入事件；其中 16 条 TCP 在采样快照时已结束，事件仍存在 |
| 实际直连／受控代理路径 | 195 | 客户端响应、宿主收包、Core rule／chains 对照无错误 |
| 同 ID 的事件／快照及切换后的旧连接 | 全部适用记录 | observation 一致，旧身份、版本及出口不被改写 |
| 配置版本 | 已知 184，未知 11 | 所有已知 inputId／模式均与原生实际状态相符；三种模式都取得已知版本 |

11 条未知配置来自非阻塞读取时配置边界忙或上下文不完整，仍保留正确应用身份、接管证据和实际出口。
未用当前配置回填旧记录。未知配置是本项实际限制，不能向后续汇总层声称所有连接都有精确版本。
基线对照流量同样无失败、195 条事件，其中 16 条短 TCP 只在事件中保留；它没有新增 observation。

全部 195 条真实 JNI 事件还经过主机上的 Dart `CoreEventManager` 分发与模型解码，
核对 UID、候选、接管及配置字段保留原值。快照协议另由同一 Dart Core facade 的测试覆盖。
这是实际 Native 数据加 Dart 消费验证，不是新 UI 的 Android 端到端验收。

## 性能观察

每种模式 48 条连接，双方采用相同客户端、配置和负载。P95 是客户端 socket 开始到回声完成，
含模拟器调度及建连；CPU 是该阶段 Native 进程累计 CPU 时间，PSS 是阶段后的采样。

| 指标 | Rule 基线 → 新版 | Global 基线 → 新版 | Direct 基线 → 新版 |
| --- | ---: | ---: | ---: |
| 回声 P95，ms | 1506.24 → 1503.44 | 1501.78 → 1556.88 | 1001.81 → 999.63 |
| Native CPU，ms／48 条 | 722 → 847 | 744 → 997 | 751 → 873 |
| PSS，KiB | 101841 → 102968 | 113540 → 114111 | 117218 → 118345 |

512 KiB TCP 单向有效负载回声吞吐：基线 1.752 MiB/s，新版 2.008 MiB/s。
实际生产 UID／包名查询函数对一条仍存活的 TCP socket 重复 100 次：
UID 查询 p50／p95 为 0.350／0.948 ms，包名 JSON 查询为 0.176／0.538 ms。
这组查询微测不代表 UDP、全部应用或设备的耗时分布。

本轮没有新增流量失败；新版的 Native CPU 用量增加，PSS 增加约 0.56–1.10 MiB。
这是单次小规模模拟器对照，不能据吞吐数字声称性能提升，也不能推断公网吞吐、长期内存或真机耗电。
自动化测试另证明不是逐包／逐快照重复查询，入口关联和冻结缓存分别保持 2048／4096 上限；
没有进行长期累计连接压力测试。

## 自动化与构建

| 检查 | 实际结果 |
| --- | --- |
| flutter pub get --enforce-lockfile | 成功，锁文件不变 |
| build_runner | 成功，模型及相关生成文件由生成器产出 |
| flutter analyze --no-fatal-infos | 成功；保留已有 42 条 info，无新增错误／警告 |
| Flutter 定向回归 | 69 项通过，含真实 Go 编码、195 条 Android JNI 事件、模型、协议、原事件与 CoreManager 行为 |
| CGO_ENABLED=0 go test . ./platform | 通过；最后新增的并发观测测试另行通过 |
| CGO_ENABLED=0 go vet .；Linux platform vet | 通过 |
| 观测与身份生产文件＋对应测试的 go test -race | 通过，包含并发 join／snapshot |
| Android NDK 生产文件集 vet | 通过；不包含不适用 CGO 的旧 host 测试辅助文件 |
| service 单元测试 | 29 项通过，其中新增解析器 6 项，失败／跳过均为 0 |
| service／core release Kotlin 编译 | 通过；JNI JSON 使用显式字段构造，不依赖混淆后的反射字段名 |
| Android ARM64 debug APK | 构建成功，实际用于本项设备验证 |
| 客户端／instrumentation 构建、Python 编译及本地回声 smoke | 通过 |
| Core carrier --check | 通过，gitlink 与登记载体一致 |

针对性测试覆盖 UID 映射变化、不同 Android 用户、无候选、异常与畸形 JSON、UID 0、
共享 UID、UDP metadata 克隆、TCP 端口重用、不借用另一 socket 身份、配置忙时未知、
旧事实冻结、缓存上限、未知协议版本以及 Tunnel 能力转发。
用户范围、重装映射、失败分支和旧 procfs 解析由替代输入测试覆盖，不写成真实设备实测。

扩展检查仍存在两个基线问题，均在 048e99b 加同一 gitlink 的对照中复现：

- no_zerotier tagged suite 中 `TestZeroTierDisabledRejectsConfigMaterials/checkpoint` 与
  `TestProviderStageRetirementJoinsTrackedNetworkClose` 失败，分别涉及 superseded checkpoint
  和已清理的候选 YAML。普通必需 Go suite 通过；本项没有修改这些资源生命周期模块。
- 整包 CGO race／Android vet 编译旧 host 测试时找不到 captureFrames／captureSingleFrame，
  因其辅助定义带 !cgo 条件。没有把失败写成整包通过；本项改用实际生产文件集 vet 及定向 race，
  APK 的生产 Native 编译和设备运行也已完成。

日志保存在本地 `.buildlog/android-build/na-t01-01-*.log`；设备依据在
`build/verification/na-t01-01/device-candidate/`、`device-baseline/`。
原始日志、设备数据和 APK 不纳入 Git；保留夹具源码与本记录作为复现和评估入口。
文档按本轮 120 字符换行、表格及代码块不限制行长的配置运行 Markdown lint，新增内容无违规；
两份既有 .agents 文档保留 29 处原有行长问题。另做引用与 Mermaid 静态文本检查，
未启动图形渲染器，不宣称预览已验证。
提交前由同一执行者审查所改 Kotlin／Go／Dart 的职责、调用关系、生命周期与有界状态；不是独立评审。

## 支持边界与清理

系统级证据限于上述 Android 14 模拟器。旧 Android、工作资料／多用户、真机、
系统代发连接、长时间后台运行、重装导致的真实 UID 回收和 Release R8 整包均未做设备验收。
识别失败或缺失入口事实时保留未知，不能把未观测到流量推断为未联网或未接管。
连接失败、拒绝及监听器断开期间的短连接不保证进入本项事件；详见 Design 的覆盖边界。

结束时已停止测试服务，卸载四个受控客户端与 instrumentation，清理开发版的合成配置，
重新安装原 Gradle 调试签名的新版 APK；没有启动代理。保留用户当前模拟器及其它包。
后续任务继续使用本项 Design 与验证入口，不自动推进 02。
