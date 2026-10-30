# L1-T12 报告管理与选择导出 Result

M1 已通过 design_v1／implementation_v2，R1/R2 闭合；已合入本地 `security/android` 并清理临时分支。
M 收尾及远端推送尚未完成。
任务及设计见[清单](loop1_tasks.md#l1-t12-增加本地报告管理与选择导出)和[Plan](l1_t12_plan.md)。
当前行为由[报告契约](../crash_reports_design.md)维护，入口与操作见[使用指南](../crash_reports_guide.md)。

## 实际成果

Android 工具页在普通日志关闭时仍可打开报告。列表／详情只读 metadata，显示受控身份、系统原因、原文格式、
缺失／截断／未知状态与占用；读取失败时不把占用显示为零。
Store 签发的快照 token 限定删除和导出对象，未知／损坏占用项也能处理；全部删除保留新项及内部去重记录。
每页 provider 独立持有 generation 和随机 nonce，退出立即撤销，旧结果不能修改新选择。

默认导出白名单 JSON；原文经独立警示／确认，验证长度与 SHA 后通过报告专用 SAF 适配器导出 ZIP。
目标 URI 不交给 Dart，原文不落共享临时目录；准备／保存阶段各两秒返回 UI 截止，picker 最多五分钟。
超时或取消不释放仍执行 I/O 的 Worker 槽；目标不能读回时只报已写入但未核验，失败／取消尽力清理新文档。

2 MiB 为单份导出载荷上限；编码与读回有多份有界副本，并非总堆内存上限，峰值堆未测量。
M1 已接受该口径；R2 已同步 Plan／契约和当前阶段，不新增堆测量门。

## R1/R2 修订

R1 修复已取得的 Go ID 被十六进制筛选器丢弃：管理路径分别筛选 GNU／Go，详情也显示保留的 Go ID。
采集器、原报告和 Core 均未改动；格式规则与理由见当前契约，未将某个真实 ID 写死为产品规则。
R2 清除当前 Plan 的总缓冲表述和 Tasks 的待设计评审状态。

本轮管理 20 项、真实页面 6 项窄测通过。管理用例从生产 metadata 验证 inventory／summary、
JSON 和 ZIP 摘要，对两段／四段合成 ID 及传入的 v1 APK 独立 oracle 逐值核对，覆盖大小写、
斜线、GNU 不变，以及路径、非法／过长值、未知库／种类排除。
页面通过真实 MethodChannel／provider 显示 Go 与 GNU，未知库字段不显示。
新 APK 身份补验 1 项通过，构建的 1000 个输入前后一致；本轮分析仍为 0 error／0 warning／42 既有 info。
实际 Go ID 与 v1 独立 oracle 相同，管理反例使用该真实值的绑定仍有效。
新制品与绑定保存在本地 `implementation_v2/`；`implementation_v1/` 冻结证据不倒改。

## 受测对象与制品

输入 Git 基线沿用 Plan；未提交变更和实际产物由本地
`build/verification/l1-t12/implementation_v2/` 绑定，原始证据不入库。

- 构建输入：1000 文件，前后完全一致；SHA256
  `04113ff83cd2ad6492f460272890d1cf2e9624984785d693d91ed9169d193c25`。
- ARM64 APK：57,311,410 bytes；SHA256
  `1753d276d13d905f599776734da0627e1a6354a70951981fd15d574afbe007b7`。
- 包与签名：`com.follow.clash.dev`，0.8.99／2026102301，release 构建、
  Android Debug 签名，签名与 ZIP 核验通过。
- mapping：SHA256
  `29ebd006d43ba114fea5c2cb0b805039e487fdb90b4690cc0383fe940d6e470c`。

Core gitlink 仍为 `6c6e3e472bb246cc55f2e8577d9eddccc2623afc`，源码干净、未修改。
相对 v1，本轮 9 个原生库逐字节相同，仅 Flutter AOT 的 `libapp.so` 改变。
8 个原生库与 T11 逐字节相同；Flutter AOT 更新。Go 库并非逐字节相同：构建信息的父仓库 revision／time
从 T11 输入变为当前基线，`.text` 相同，差异位于 note、rodata 和 buildinfo；不能据源码相同宣称二进制相同。
当前 APK 的 GNU／Go ID 已由 NDK readelf／go tool buildid 独立提取，再经生产身份读取器核对。
R8 合并了导出类，mapping 保留其来源方法；DEX 中管理／导出／取消入口存在。

## 已核实的 v1 基础验证

| 检查 | 结果与计数口径 |
| --- | --- |
| 原生报告回归 | 主轮 79 通过／1 条件跳过；制品补验 1、管理复验 18 通过，合计 82 个独立用例 |
| 最终 Flutter 定向 | 20 项通过，0 失败／跳过；本项页面／provider 及既有错误／备份／日志排除 |
| 扩大 UI／l10n／lint | 两轮按路径和测试名合并：535 通过、4 项基线失败；本项主轮加载错误已修正并补验 |
| 生成与分析 | 依赖与生成通过；分析 0 error、0 warning，42 项既有 info |
| 构建与身份 | ARM64 完整构建通过；制品输入未变，实际 APK 身份补验通过 |

原生反例使用真实临时目录和受控 DocumentsProvider／流，覆盖摘要不读 raw、合成秘密、未知／损坏／空材料、
根重定向、symlink、快照过期／替换、单删／全部与新采集、部分删除、去重保留、准确原文、取消／迟到／重复回调、
错误 owner、请求码损坏、短写／空 descriptor／读回拒绝、write／flush／close 失败、队列满和阻塞后的物理占槽。
实际 AppPlugin 管理及 activity detach 消费共享 Collector/Store；页面用例核对日志关闭入口、两种导出确认、
删除取消及退出后的迟到结果。
管理复验的 18 项中，16 项此前已覆盖、2 项为最后子文件 I/O 耗尽期限后的父目录保留反例。
原生总覆盖来自三次运行，不是同次 82 项；定向 Flutter 包含本项 9 项及既有错误转交、真实备份／
localhost WebDAV／普通日志排除。生成使用 intl_utils 和 build_runner，未手改生成文件。
本轮只替换受 R1 影响的管理／页面／制品验证；未变的采集、SAF 取消／队列、备份排除等依据沿用 v1。

Robolectric API 24 的 Posix 缺少 open，Linux lstat 会跟随链接；仅测试的 `ReportOsShadow`
用宿主 no-follow 文件操作补齐，生产仍调用 API 24 可用的 Os 接口，另核对该 sandbox 的公开方法／字段。
这不是设备 POSIX／系统 picker 证明。原生单测跳过 Flutter debug 编译任务；另以完整 ARM64 release 构建验证打包。
首次未限定该任务时遇到 armv7 Rust 工具环境失败，保留日志，未计为通过。

4 项基线失败为：旧更新弹窗夹具直接传 Map，被既有会话校验拒绝的 3 项，以及
`test/bootstrap_test.dart` 的既有 Material 导入被 `design_package_test` 报错。
前者的相关方法与已有基线一致，后者源码和 lint 规则与输入 HEAD 一致；均未在本项改动，不能将扩大回归记为全绿。
原始结果、方法绑定和合并计数见本地 `flutter_binding.json` 及上级目录 `unrelated_failures_binding.json`。

## 限制与交接

未安装／启动设备或用户应用，未改变宿主网络，未用真实报告／凭据或外部测试目标。
真实系统选择器、云端提供方同步／撤回、设备故障与断电持久性、完整符号化及总堆峰值仍未验收。
内部限额不能硬中断阻塞 I/O；部分外部副本可能残留。T04/T05 全面风险仍暂缓，本项不表示普通日志已全面脱敏。

本地冻结入口为 `final_binding.json`、`native_binding.json`、`flutter_binding.json`、`apk_inspection.json`，
命令与原始输出就近保留。D-02 已按约定本地提交、合入及清理；
M1 完成 Details／独立文档收尾与远端交付后接续 T13。

## 提交前整理

结构检查覆盖 Store／管理快照、共享 Worker、SAF 会话及页面／provider 边界，未发现需再优化的结构问题。
提交 hook 将英／俄生成本地化文件统一格式；解析后的 Dart token 序列与已审版本完全一致，
未改文案或执行语义。其余差异只更新本项交付状态，原构建及验证继续有效，不因格式或状态重建。
格式对照与最终提交、Tree／parent、源码／制品关系另由本地 `delivery_binding.json` 绑定；不倒改冻结对象。
本项临时分支 `security/l1-t12-report-management` 已删除；共享 checkout、独立聊天及本地证据保留。
Plan／Result 已随交付进入目标分支历史，由 M1 取回核对后再清理当前副本。
