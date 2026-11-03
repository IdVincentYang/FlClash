# L2-T02-05 整项验收与能力说明 Plan

任务及归属见[子任务清单](l2_t02_tasks.md#l2-t02-05-整项验收与能力说明)。
输入基线为父仓库 `0e4a8227fc3f8c44fdfbc671e9edd94ba64d4f92`，Core 保持既定版本不变。
design_v4 与 implementation_v1 均已通过，本稿为有界调查、长期风险跟踪及能力说明的交付定稿。

## 问题、最新决定与本轮出口

原目标是把导入/策略编辑、业务和 DNS、材料更新及服务状态串成完整用户闭环。
R1 已证明宿主真实 Core 的 TCP/SOCKS IP 入口会把原 A 请求送到 B 代理；
fake-ip 普通更新/恢复等公开 API 实验也发现身份保持问题，不能靠配置预览或单次新建池通过结案。
实际证据、消费者和未运行部分见[Result](l2_t02_05_result.md)。

用户于 2026-11-03 明确继续不改核心、研究应用层；没有方案则记录问题，后续跟踪核心修复。
旧“等待人类方向”已解除。本轮保留普通 TUN 域名/IP 分流目标，不设计/修改 Core 补丁、
不升级 gitlink/carrier，也不把 normal、统一出口或仅显式域名代理造成的功能收缩当作等价修复。

本轮未找到可论证满足这些条件的窄应用方案，选择用户已批准的调查/能力说明出口。
05 可在完成该范围的两道评审及正常交付后，以“调查与说明已交付，DNS安全验收未通过”结束；
这不是接受错路风险，不升级整个 L2-T02、Loop 2 或整体上网安全，也不无限等待上游。

## 应用侧收敛与理由

保留 ConfigInput/T01 的输入/采用权威和 ServiceState 的运行意图权威。
现有红例、有限生命周期实验及独立来源/备份核实已审，不重复全量矩阵或新建实验来维持活跃。
本轮进一步核对公开边界后的候选判断如下：

| 候选边界 | 可处理部分 | 未形成闭环的关键点 |
| --- | --- | --- |
| 普通 DNS listener gate | 既有 scope/提交前检查 | TUN relay 直接访问 DefaultService |
| 全局 Service decorator | 可在共享 DNS 入口协作 | 委托已发生分配，缺分配前拒绝重用出口 |
| T01 安装前 StoreState | 已验无并发正常缓存对照 | 不等于在线排空/可靠冷恢复/容量失败关闭 |
| TUN 入站检查或规则覆写 | 看见当前 metadata | 已重用别名无法恢复原 A，IP-only 缺身份 |

依据为 `core/config_dns.go`、Core 的 `component/resolver/service.go`、`relay.go`、
`listener/sing_tun/dns.go`、`component/fakeip/pool.go` 和 `dns/enhancer.go`。
普通 listener 的 scope 不能自动约束 TUN；全局 Service 包装虽有覆盖入口的潜力，
但公开 Lookup 不提供原子预留/拒绝重用或写失败返回，安装仍会重建/复制池。
仅事后验证或读取当前反向身份不能恢复旧客户端的原 A；另存别名历史或复制 Core 实现超出窄边界。

因此没有把有条件的 StoreState 成功推广为产品修正。结论限定为本轮/当前公开 API 与约束，
不声称数学上不存在任何应用方案。保留 redir-host 的已证实风险；不引入 unsafe/reflection、
新 matcher、别名 DB 或平行运行状态，不更改 renderer/接受校验/默认。

## 上游信息与当前版本的区别

查询日为 2026-11-03，仅使用公开资源名和官方只读页面，未提交本地反例、代码或日志。
当前定制 Core 从 FlClash fork 公共基线 `8597778` 加既有 carrier 恢复；
不是最新 MetaCubeX tag，也不因官方公告自动更新。

[PR #3283](https://github.com/MetaCubeX/mihomo/pull/3283) 已合并，
[v1.19.33](https://github.com/MetaCubeX/mihomo/releases/tag/v1.19.33) 包含同范围池复制时保留分配状态的修复。
已读 tagged 源码，当前固定源码未含该变化；没有构建/运行上游版本。
[PR #3313](https://github.com/MetaCubeX/mihomo/pull/3313) 查询时仍 Open，涉及持久化重载清表；
[issue #2997](https://github.com/MetaCubeX/mihomo/issues/2997)
仍 Open，涉及真实 IP mapping 与 VLESS 目标改写。
后二者是不同范围的相关线索，不能当作本地 SOCKS 路由错配已被官方完全修复。

## 文档职责与实施顺序

设计通过后先完成长期资料基线，再整理交付验证和实际结果；不再建立平行风险台账。

1. 扩展 `docs/features/security/deferred_security_items.md` 的用途和导航，新增
   `L2-T02-R1 共享 IP 与域名身份` 节，作为持久风险/跟踪的唯一维护位置。
   独立说明已证实 A→B 收件、fake-ip 更新/恢复机制、当前 Core/公共基线、影响与 English 入口、
   未验证 DIRECT/REJECT/UDP/设备、规避条件及代价、最小复现命令和后续判定。
   复现链接正式测试和既有夹具，不依赖日后被删除的本项 Plan/Result，也不复制原始日志。
2. 完成 `docs/features/security/managed_profile_guide.md` 的能力/使用说明，明确草稿/选择/采用/运行
   不等于域名身份安全；支持、不支持、未运行、未解决分列。风险详情引用统一长期记录，删除重复正文。
   不把取消 draft 标记等同验收转绿。`managed_updates_guide.md` 保留绑定/更新专项及正确 English 名称。
3. 在 `docs/features/security/android_network_inventory.md` 和 `flclash_security_plan.md`
   提供同一风险入口；
   `managed_updates_design.md` 仅补配置级保证不涵盖 R1 的必要边界和直达引用，不重定义材料契约。
4. 维护 `docs/features/security/loop2/l2_t02_plan.md`、`l2_t02_tasks.md`、`loop2_tasks.md`
   的活动范围/出口；
   `l2_t02_05_result.md` 维护本轮实证、复用/偏差及交付对象，已结束任务不回写。

长期记录的跟踪触发点为同步/升级 Core、官方相关 issue/commit 有实质变化，或用户重新安排修复。
官方来源同时保留 configured FlClash fork 和 MetaCubeX upstream；记录状态/日期及各自适用范围。
不新建 automation/任务，不发上游 issue/评论，不把未来修复的接口草案写成当前实现。

## 验证、完成及保留范围

采用新的研究/说明完成判据，原受影响设备/新机制矩阵保留未运行，不为证明已知失败重复启动 AVD。
独立 DB/备份/来源与维护消费者按已核版本复用；当前窄测完整重跑10项通过，
首次 `picks SQL` bridge 超时原因未确认，原日志和该偏差继续保留，不称全绿。
T03 服务证据、物理网络/SSID/IPv6/Always-on 未验证范围及历史图库诊断外发未知均不改变。

正式交付保留 `core/managed_identity_test.go` 和 `core/managed_fakeip_lifecycle_test.go`
作为手动门控诊断，
以及最小复现命令/参数；正常选集默认 skip 不冒充修复通过，显式运行的红例维持原身份期望。
原始日志、合成缓存、制品和冻结快照留在 `build/verification/l2-t02/subtask_05/`，不提交这些原始材料。

提交前按影响完成格式/静态引用、正常依赖与分析检查，验证两份手动诊断的默认门控和编译，
复用已审显式红例/生命周期结果，不重跑全量、不改断言接受 B。生产/生成输入不变时核对既有 APK
构建输入后复用，不重建或声称已安装新 APK。

长期状态由“未解决”转变须满足：官方变化实际进入当前源码/依赖和构建制品，原请求/独立收件 R1
及普通更新/恢复/缺失/失败等相关生命周期反例重新通过；若影响 TUN/UDP/DNS出口，还须补相应真实消费者。
release notes、issue 关闭、API 变化、未收到数据或退出码本身均不足以关闭风险。

两道评审已通过；D 按正常 pre-merge 本地合入 `security/android` 并清理临时分支/自有资源；
M 核实际 Details、独立清理合资格任务文档、普通推送个人 fork 并核远端。
完成的是本轮有界调查与能力说明，持续未满足的域名身份需求由长期记录接续，不标整项安全通过。
