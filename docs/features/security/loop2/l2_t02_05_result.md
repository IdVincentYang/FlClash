# L2-T02-05 整项验收与能力说明 Result

本项研究/说明已通过两道评审，本文为交付定稿。R1 先行实验已在宿主真实 Core 的 TCP/SOCKS IP 入口复现共享 IP
跨代理错路；DNS 安全验收未通过，受影响 TUN 能力未继续验收。
用户已明确保持不改核心，未找到可行窄应用方案时记录问题、后续跟踪上游；design_v4已通过，当前落实说明交付。
任务、输入基线与实验判断出口见[Plan](l2_t02_05_plan.md)，当前状态由[Tasks](l2_t02_tasks.md)维护。
不能把本结果写成 DIRECT 外发、REJECT 绕过或 Android 设备已经复现。

## R1 实际证明与范围

测试使用真实策略编译器生成完整 YAML，经现有 ConfigInput prepare/install/activate，进入当前
Core 的 DNS middleware、mapping、TCP tunnel 和两路独立 SOCKS 收件端。
这是编译/接受/消费层实验；未经过实际页面、DB 选择、材料刷新或 Android ServiceState/OS。
没有改生产实现、Core 源码、gitlink 或 carrier，也没有构建/安装 APK。

| 原请求与条件 | 预期 | 实际 |
| --- | --- | --- |
| 显式域名 SOCKS A / B | A / B 代理分别收件 | 分别返回 A / B |
| 未解析前，连接共享 IP | 显式 IP default REJECT | 拒绝，无业务响应 |
| A 后 B 的真实 DNS 查询 | 各自 DNS 接收，答案同一地址 | DNS A/B 各1次，均答共享地址 |
| 保存 A 地址，B 解析后发 A 的新 TCP 请求 | A 代理收件 | B 响应，A增0/B增1 |

原域名 `a.identity.test` 配置代理组 A/DNS A，`b.identity.test` 配置组 B/DNS B。
两个真实 DNS 服务返回同一 `192.0.2.123`、TTL 60；它满足 `IsGlobalUnicast`，
实际 DNS middleware 依次写入 A/B mapping，未手工插入。
反查仅确认夹具命中该路径；预期由原 A 请求及预先配置的策略确定。

错误收件的客户端请求为：

```http
GET /original-a-after-b HTTP/1.1
Host: a.identity.test
Connection: close
```

SOCKS CONNECT 使用该客户端先前取得的共享 IP；最终 body 为收件端 B 的独立标记，
其新增连接为1，A新增为0。只依据 Core 最后恢复的 B 域名无法发现这次错误，
因此“DNS 与业务从同份规则生成”不足以证明原域名流量始终使用接受的出口。

## 本地隔离与未运行部分

共享文档地址仅作 DNS/mapping/代理目标标记；没有连接该地址。
两个 SOCKS 服务只在 loopback 监听，收到该固定标记后本地返回 A/B，不向目标转发。
其可转发白名单仅含本地 DNS 端点；Core socket guard 在传输前拒绝非 loopback 地址，
记录中没有被拦截的非本地 socket 尝试。DIRECT 合成目标收件为0。
这些事实不是全系统流量审计，也不能证明其它场景无外发。

遵守“发现即交”出口后未继续 AVD、UDP、A=代理/B=DIRECT、切换后 REJECT、
旧 mapping 和完整用户流程矩阵；它们均未运行，不能计为通过。
源码中 TCP/UDP 共用恢复逻辑是进一步调查依据，不能代替实际设备/UDP 收件。
未启动 AVD/私有 ADB，无设备或宿主网络资源需要清理；短命 Go/编译器进程已结束。

## 版本、命令与复现

受测父基线 `0e4a8227fc3f8c44fdfbc671e9edd94ba64d4f92`，Core 为既定
`6c6e3e472bb246cc55f2e8577d9eddccc2623afc` 且干净；增量为手动门控测试
[managed_identity_test.go](../../../../core/managed_identity_test.go)。
沿用 04 的真实编译器，经制品 Hash 和4个源/lock输入比对后复用；不是重新构建编译器的结果。
正常分项测试默认跳过本调查；下列显式运行在当前实现预期失败，以原域名期望暴露缺陷。

```bash
compiler="$PWD/build/verification/l2-t02/subtask_04/implementation_v1/artifacts/managed_profile_compiler"
evidence="$PWD/build/verification/l2-t02/subtask_05/new_identity_run"
CGO_ENABLED=0 GOTOOLCHAIN=local GOTELEMETRY=off GOPROXY=off \
  FLCLASH_MANAGED_IDENTITY_INVESTIGATION=1 \
  FLCLASH_MANAGED_PROFILE_COMPILER="$compiler" \
  FLCLASH_MANAGED_PROFILE_EVIDENCE="$evidence" \
  go -C core test -run '^TestManagedProfileSharedIPInvestigation$' \
    -count=1 -v -timeout 60s .
```

本次运行 exit 1、1项失败：`original domain A expected receiver A, actual receiver B`。
日志还包含测试没有宿主消息连接的 `send conn nil`，不作为路由断言；
真实业务/DNS socket 对照和错误收件已独立完成。

冻结包位于忽略目录 `build/verification/l2-t02/subtask_05/r1_v1/`，含命令/环境、退出码、
生成 policy/YAML、identity.json、编译器复用、变更快照及源码副本。
snapshot SHA256 为 `aa88fdf1d62d24fa08489244e7a7171b264bea678b9e301c66b01a9b361e159a`，
checksums SHA256 为 `c3606ce1793eb7113b350afb571386ad5ae7f02df71aecfb8c043845d469208f`。
该快照绑定实际运行时的文档和测试；本次结果/状态回填不改变受测代码，不倒改冻结包。

## fake-ip 公开 API 生命周期机制实验

design_v3 限定通过后，本轮机制验证已完成。新增
[生命周期调查测试](../../../../core/managed_fakeip_lifecycle_test.go)，只调用公开
Pool/Enhancer/Resolver/Executor API。手工 fake-ip 配置只用于 Executor 机制，未经过受管 descriptor
或真实产品 Apply，也未改变生产 renderer、接受校验及默认。

| 条件 | 已发 A 后的新分配/恢复 | 旧 A 别名实际身份 |
| --- | --- | --- |
| 同一内存池持续使用 | A=.4，B=.5 | A |
| 内存新池 CloneFrom | A=.4，B=.4 | B |
| 真实 Executor 普通更新 | 旧表先保留 A，随后 B=.4 | B |
| 持久化自动重建，无 StoreState | 重建先丢 A，B=.4 | B |
| 持久化重建前 StoreState | B=.5 | A（有条件对照） |
| 无 Shutdown 的进程恢复 | 新进程先丢 A，B=.4 | B |
| 显式 StoreState 后无 Shutdown 恢复 | B=.5 | A（有条件对照） |
| 同一内存池 CloneFrom 自己 | 进入调用后3秒仍未返回 | 自有子进程截止回收 |
| LRU size=2，第三个名称 | C=.6，地址空间未耗尽 | A 别名不存在 |
| /29 小地址空间，第四个名称 | D=.4 | D，分配无错误返回 |
| 专用 DB 公开 Close 后再分配 | 返回 .5，但反向身份不存在 | Lookup/StoreState 无错误返回 |

常规范围为 `198.18.0.0/24`，内存 size=1000；表中 `.4` 为 `198.18.0.4`。
LRU 与 /29 单独缩小参数以隔离机制，不能据此声称生产环境第三/第四次查询即耗尽。
真实 Executor 对照通过两次 ParseRawConfig/ApplyConfigStaged 及 DNS Service A 查询取得别名；
更新后、分配 B 前还可反查 A，分配 B 后同一地址反查为 B，故不是仅推测 cursor 行为。

持久化正对照在无并发、临时缓存正常写入、显式 StoreState 完成后，
通过新池/新进程的 A/B 别名及反向查询验证结果。没有读取内部键或修改私有字段。
冷恢复是两个测试子进程间的恢复，seed 未调用 Shutdown；没有模拟任意写入时刻断电。
这不能证明 live DNS 排空、并发/异常写原子性、丢失/损坏状态或生产安装协议已经安全。
关闭 DB 案例先核正常写读，再确认公开 Close 成功，实际得到无反向身份的新地址并有数据库关闭日志；
它不是磁盘满等所有 I/O 故障的证明，也未执行该别名的业务连接。

本轮仅有 alias→host API/真实 DNS Service 身份观察，没有新业务收件、UDP 或 AVD 证据。
原 R1 的独立收件红例保持不变。父调查命令 exit 1、1项调查失败，含5个身份保持失败断言；
13次子进程调用中12次正常结束，1次预期超时终止，不应汇总为产品测试通过。
每次正常完成的子进程记录中 Core network socket attempt 均为空，测试 guard 拒绝网络 socket；
所有数据均为合成私有缓存，无对外目标、真实数据或宿主网络变更。

```bash
evidence="$PWD/build/verification/l2-t02/subtask_05/new_lifecycle_run"
CGO_ENABLED=0 GOTOOLCHAIN=local GOTELEMETRY=off GOPROXY=off \
  FLCLASH_FAKEIP_LIFECYCLE=1 \
  FLCLASH_FAKEIP_LIFECYCLE_EVIDENCE="$evidence" \
  go -C core test \
    -run '^TestManagedFakeIPLifecycleInvestigation$' \
    -count=1 -v -timeout 45s .
```

冻结证据为 `build/verification/l2-t02/subtask_05/lifecycle_v1/`，含13次子进程命令/PID/日志、
results.json、专用 cache、基线及源快照；snapshot SHA256 为
`64fb92e08327a0d3ca9cf4d85c1000ee9f7d513ba84a6b9a698ff655c7b3d597`，
checksums SHA256 为
`3d9a9cba5530083a7d0a3ed5be19dc4f49849e9bc8d3ded4179a191c4bd2b27c`。
全部子进程 Wait 完成，记录 PID 已不存在；死锁进程仅按其自有 PID 截止回收。
未启动 AVD/私有 ADB，冻结包及合成缓存保留，不覆盖 R1 或 design_v3。

## R1 局部暂停期间的独立证据

本节记录曾等待用户方向期间完成的独立核实。用户随后已明确继续不改核心，
无应用方案则记录跟踪；旧等待已解除，不据此自动开展 Core 修改或新机制实验。

独立核实以 04 交付 `0ea9bb293bd8e9c1a2e9bcde1457d07397081a6f` 为对照：

| 范围 | 当前依据 | 适用边界 |
| --- | --- | --- |
| DB/model/common、备份/选择/材料/刷新及相关测试 | 142文件中141一致 | 唯一新增为T03服务状态辅助文件 |
| 四种语言旧 ARB 项 | 旧值全部相同 | 新服务状态文案不作旧源同一声明 |
| Go生产/module输入 | 36文件一致，Core gitlink干净 | 新增测试不改变生产消费实现 |
| 既有DB/备份与维护默认/Owner消费者 | 原运行日志Hash与冻结记录相符 | 不算本项重新执行 |
| 当前来源撤销失败补偿桥接 | 窄测重跑10项通过 | 首次1项超时原因尚未确认 |

T03 的 Setup/Service/原生状态增量并非与04整体等价；旧分项有效证据按各自范围复用。
当前窄测使用真实 Go bridge、临时 DB/偏好及当前 Dart Setup/Service 入口，覆盖设置/SQL失败、
补偿失败与较新 Owner 保留。桥接二进制和测试入口与 T03 冻结内容一致，编译器为已核04制品，
仅复制到新的独立目录以提供同级编译器，不修改旧证据。

首次该测试文件9项通过、`picks SQL` 场景在桥接等待10秒后超时；同次日志有
`File modified during build. Build must be rerun.`。未修改代码，单独重跑该场景1项通过，
再完整重跑10项通过且无该构建警告。首次超时根因未定位，不能据重跑把它删除或宣称已修复。
本项没有新增补偿行为，全部源测试保持原内容；失败/两次重跑日志均保留。

此处只核来源资格和失败后的保留/关闭；不证明 R1 域名分流、新 fake-ip 共享 DNS、
Android OS 实际维护路径或完整用户闭环。旧维护请求的 URL/状态/本地收件条件仍按原记录理解。
未重跑全量测试、未构建 APK，也未恢复暂停部分。
独立核实证据位于 `build/verification/l2-t02/subtask_05/independent_v1/`；
含文件/旧文案比对、旧日志Hash校验、命令/环境及三次测试日志。
当前专用 bridge 产物路径已无残留进程；测试临时数据由既有 fixture 释放，证据及制品副本保留。

## 本轮应用侧收敛与交付决定

用户于2026-11-03明确继续不改核心，应用层无可行方案时记录问题、后续跟踪核心修复。
按此决定再收敛一轮现有边界，未增加运行实验或生产修改：普通 DNS binding 的 scope 只包监听入口，
TUN 通过 resolver relay 访问 DefaultService；公开 Service decorator 可以增加协作入口，
但不提供 Pool 分配前原子拒绝重用或可靠恢复 allocator 的能力。
事后反查只能看到当前 B，不能恢复旧客户端的原 A；入站 IP-only metadata 同样缺原身份。

结论为当前版本/本轮约束下未找到可论证的窄应用闭环，不宣称所有应用方案均不可能。
不以有条件 StoreState、normal、统一出口或仅显式域名代理作为既定 TUN 需求的等价修复，
不另造 matcher、别名 DB、平行状态或复制 Core 实现。

官方公开只读查询日为2026-11-03：
[PR #3283](https://github.com/MetaCubeX/mihomo/pull/3283) 已合并，
[v1.19.33](https://github.com/MetaCubeX/mihomo/releases/tag/v1.19.33) 包含其池分配状态复制改动，
tagged 源码可见，但当前固定 Core 未含此变化。
[PR #3313](https://github.com/MetaCubeX/mihomo/pull/3313) 和
[issue #2997](https://github.com/MetaCubeX/mihomo/issues/2997) 查询时仍 Open，分别为持久化重载及相关真实IP/VLESS线索。
本次未构建/运行上游制品或同步源码到工作树，未把它们当作全部 R1 已修复；
未向上游提交本地内容或创建 issue/评论。

design_v4 已通过，现由[R1长期记录](../deferred_security_items.md#l2-t02-r1-共享-ip-与域名身份)
承接唯一长期风险/复验入口，使用指南、网络清单及总体入口均引用；能力说明和有效证据分层对账。
在 M 设计/实现评审及正常交付后，05 的本轮研究/说明可以结束，缺陷仍未解决、DNS安全验收仍未通过；
不因该条件出口把 L2-T02、Loop2 或用户风险接受状态升级。实际本地/远端版本由 Git 历史和最终交接核实。

## 研究与说明实现自验

已落实统一长期风险记录、English 使用指南、配置级保证边界及当前任务条件出口。
长期资料不依赖本项 Plan/Result 才能理解风险、复现或跟踪；本轮不修改生产行为/生成结果，
只交付资料和两份手动门控诊断。研究/说明自验与 M 实现评审均通过；不是 DNS 安全验收通过。

| 检查 | 本轮实际结果 |
| --- | --- |
| flutter pub get --offline --enforce-lockfile | exit 0，lockfile不变 |
| flutter analyze --no-fatal-infos | exit 0；0 error/0 warning，42条既有info |
| 两诊断文件/子入口默认门控与编译 | 3个入口SKIP；package命令exit 0 |
| CGO_ENABLED=0 go vet . | exit 0 |
| Go格式及diff检查 | 无格式差异，无diff错误 |
| 既有APK输入 | 1029项Hash全部相同，复用T03制品 |

默认 SKIP 仅验证编译与门控，不计为 R1 修复通过。显式 R1、生命周期失败结果、
独立窄测10项重跑及首次未定位超时均按前文冻结证据复用，不重跑/改断言掩盖偏差。
未启动AVD、未重建或安装APK，未修改Core/gitlink/carrier或用户默认。

复用 APK 为 T03 的 `FlClash-0.8.99-android-arm64-v8a.apk`，
SHA256 `77f9a379174a579d282099faaea68cf13e8268d23a89d6f5a2754133e9601075`，57,360,482字节。
它绑定未变的应用构建输入，不把05新增文档/诊断说成新设备安装版。
本轮正常检查、文档基线及输入复用依据保存在忽略目录
`build/verification/l2-t02/subtask_05/implementation_v1/`；完整冻结信息随实现交评提供。
本定稿随交付提交进入目标分支历史；正常 pre-merge、本地集成及 M 远端收尾按既有约定完成并核实。
