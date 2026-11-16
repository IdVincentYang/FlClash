# R08 请求 key 生命周期 Plan

任务入口：[分枝 Review Issue R08](android_branch_review_issue.md#r08活动请求有界历史-key-却永久保留)。
基线：`security/android`，`ee6b7f559a921f97232fbd6f40671db9e4ee6c18`。
状态：revision-02 实现复审通过，I1／I2／Q1 闭合；进入行为不变的提交前整理与本地 fixup 交付，Issue 与 Plan 清理由 M 对账处理。

## 问题与目标

[Request](../../../lib/common/request.dart)和[Core registry](../../../core/app_requests.go)
保留所有见过的取消、operation 和 source key。实际的[图标 URL](../../../lib/common/cache.dart)
和[连接出口 key](../../../lib/providers/connection_exits.dart)会持续变化；请求关闭不能回收这些记录。
已有反例在 1000 个不同 operation／source key 后 detach／attach，两表仍各有 1000 项、lease 为零。
这是既有观察，不是本轮重新运行的结果，也没有 OOM／设备内存测量。

目标是历史元信息不再随累计不同 key 数增长，同时保留 cancel、latest intent、来源审核、
材料提交和迟到结果校验。范围仅为这三张版本表及其直接资格消费者；不改路由策略、
Native 生命周期、Core submodule、已接受权限权威或出口结果缓存。

## 方案与理由

推荐保留现有 key／版本协议，将永久计数表改为“活动记录＋有界冷记录”。
冷记录是仍可用于快照比较、但没有在途工作持有的记录；它不是已接受权限。
只在 detach 清表不能覆盖长时间不 detach 的服务；直接删除归零会使旧快照重新有效。
给所有 RequestSource 增加跨语言 retain／release 则需要改造大量持有者，本次不采用；
但已发现的脚本自动应用续接有明确终点，需要专门持有，见下文。

### 版本与资格

每张表拥有一个不回退的高水位。首次创建或淘汰后重建 key，分配大于历次版本且至少跳过一值
的新版本；已有 key 的 begin／invalidate 仍按原语义加一，并推进高水位。
这样保留现有“恰好一次失效”的 `+1` 消费者，同时重建不能伪装成那次失效。
跨 Dart／Go JSON 的版本限制为 `1..9007199254740991`（`2^53−1`），输入超过此范围拒绝，
不依赖 Go uint64 或 Dart VM 的更大整数范围。创建跳号、递增和预测 `+1` 都先检查上限。
Core 任一表耗尽时，两表及 registry 一起拒绝新旧资格；Dart 耗尽亦取消 session。仍执行 cancel／close、释放和
来源／checkpoint 撤销，不能因分配新版本失败而保留旧资格。新 begin／材料写入在资格检查处失败。
高水位及耗尽状态不随 detach 重置，只能随新的 Request／registry 身份生命周期结束；不绕回零。

只有 capture／inspect 或真实 begin 可以创建记录；取消或 invalidate 一个不存在的 key 不记墓碑。
缺项代表旧资格已结束，验证不得用默认零、也不得在验证过程中重新创建记录。
inspect 重建只能发出新快照，不能修复旧 ticket。旧版本无论经过多少轮重建都不匹配。
Client、dataset、native epoch／revision、owner、permit 和 receipt 的现有校验继续保留。

需要审查所有直接读取，而非仅替换 map 容器：来源票据／ConfigInput、checkpoint replay、
provider adoption、material commit 及 Geo completion 均有版本比较。
[来源材料提交](../../../core/source_material_commit.go)和
[策略材料](../../../lib/providers/actions/policy_material.dart)还依赖精确的相邻版本。
[failConfigBuild](../../../core/managed_config.go)的保留旧配置判断必须拒绝缺失来源；
[review bundle](../../../core/source_review_bundle.go)的 LocalEdit 会保存 `source+1`，
须使用同一受检后继规则，不能溢出或把淘汰重建误认成一次本地编辑。
本次不改变普通 `RequestSession.close()` 后仍可完成既有快照比较的时序；已关闭 lease 本身仍不能使用。

### 持有与回收

| 记录 | 活动持有者，期间不可淘汰 | 回收边界 |
| --- | --- | --- |
| Dart cancellation | begin 从入队资格检查到 session 交接的等待；尚未 close 的 session | 等待退出／失败／交接或 close 后转冷 |
| Core operation | 正在建立的 begin、活动 lease、未完成 commit receipt、已交接的 completion hold | 最后一个持有者退出才转冷 |
| Core source | 上述工作，以及仍持有配置资格的 pending／applied 依赖 | 工作退出、配置替换／失败或依赖集合更新后转冷 |

Dart begin 必须在首次异步等待前持有版本及当前 dataset，并在所有返回／异常路径释放或交接；
构造 session 时使用捕获的版本，不能读回最新值让旧 begin 冒充新操作。
detach／dataset 变更也撤销等待中的本地资格；保留其记录到退出仅用于安全释放，不允许继续 begin。
Core begin 在原锁内认领 operation，失败和并发替换只能释放自己持有的版本；
旧 lease 的 Close 不得移除或改写新 lease 的记录。未知写者和 retired receipt 的现有 veto 不变。

### close 后的自动应用

D1 的源码交错成立：[updateScript](../../../lib/providers/actions/scripts.dart)提交后调用 `_applyIfInUse`，
将原 session 的 `lifecycleCurrent(sourceInvalidated:true)` 交给
[applyProfileDebounce／_runSetup](../../../lib/providers/actions/setup.dart)，随后 finally 关闭 session。
[Debouncer](../../../lib/common/function.dart)默认延后 600 ms，执行后还可能等待 setup 队列；
当前没有保证排除这段时间发生无关 key 压力，不能将其当作已结束的 review 快照淘汰。

推荐仅为该续接增加 `RequestCompletion` 资源句柄。updateScript 在 commit 前、lease 仍有效时
取得 hold；它只固定原 operation／source 记录的寿命，不授予请求、提交或新来源资格。
保存失败或当前 Profile 不再使用该 Script 时立即释放；保存成功后移交给 SetupAction。
session 和网络连接仍按原 finally 关闭，receipt 仍按原时机 Complete，不为等待 debounce 延长写入锁。
该回调不读取 Dart cancellation 表，故不额外 pin 本地版本，只保留 Core operation／source；
非 Android 的原 `lifecycleCurrent` 行为沿用，不发新增控制请求。

SetupAction 只保存本实例的一个 pending apply 句柄。所有 `applyProfileDebounce` 调用先释放被替换的
pending 句柄；callback 开始时从 pending 转为本次异步调用所有，try/finally 覆盖 `_runSetup`、
排队、重试和 deferred cleanup。Stop 的既有 debounce cancel 及 provider dispose 释放 pending；
dispose 后晚到 callback 只退出。运行中的旧 callback 到实际退出才释放，不因新 callback 开始而错误释放新句柄。
沿该 tag 现有唯一调度入口维护，无需改变通用 Debouncer API，不为所有已关闭 session 建长期 pin。

Core 为此新增私有 `requestControl` action `retainCompletion`／`releaseCompletion`，复用现有
`id`／`client` 字段：前者仅能从当前有效且未 grant 的 lease 原子取得随机 hold ID，后者按
hold ID／所属 client 幂等释放。不能通过 key／版本重新捕获旧资格。Core hold 表最多 128 项，
沿既有请求并发量级限制；满额在材料写入前明确失败。Dart 只保留实际工作的句柄，Core hold／pin／LRU 一并有界。
释放不经过授予或版本分配 gate，耗尽、失效或重复释放也能结束其资源寿命。
同 key 新 operation、client／dataset、owner 或 native 版本失效会撤销相关 hold；
原提交的一次 source invalidate 允许句柄继续保留原记录，但仍须通过原 `source+1`／operation 等完整比较。
再次 source invalidate 不能借 hold 获得资格；任何自动释放或显式释放均不得保活或升级旧版本。

### 容量与整理成本

每张表最多保留 4096 条冷记录，按最近使用淘汰；这是待评审的容量策略，
参照现有来源实体 1024／来源 key 批处理 4096 的量级，不是内存或性能实测结论。
总项数上界为“当前活动的不同 key 数＋4096”，与整个进程累计见过的 key 无关；
这不等于固定字节上限，也不把已有 lease 128 的限额冒充所有持有者的总上限。
LRU 和持有计数随同一记录释放，不能另留一张无界的历史索引。
容量淘汰仅限冷记录，不取消在途网络、不撤销已接受权限，不使当前配置失去 replay 资格。

长期搁置的外部 RequestSource／review 快照属于冷记录，可以在超过容量后失效。
届时按既有 superseded／cancelled 路径结束该轮，重新捕获才取得新资格；不自动接受或改用 DIRECT。
这是避免增加 retain／release 协议的明确代价，需随本方案一起评审。
当前配置依赖必须受保护，因此大量图标／出口请求不能把已采用配置挤出。
failed pending 即使仍保留对象指针，也不再持有来源资格；在 block／prepare 失败边界撤下其 pin。
已保留的旧 applied 配置则继续保护，不能只因另一个 input 已 register 就释放。
仅清理被判失败的那次 pending；新 prepare 在发布前失败，不因此撤下仍有效的旧配置持有者。

close／取消／Complete 后执行局部冷记录整理；首次创建时保证容量。
detach／attach 和 dataset 失效时清理不再有持有者的记录，仍在服务的配置、内部请求和
未确认结束的 receipt 不随 Flutter detach 删除。高水位不重置，不增加 timer、goroutine 或文件缓存。

版本项用 key map 定位，只有冷项进入独立有序 LRU：Dart 使用 LinkedHashMap，Go 使用
container/list 并由 entry 保存节点。单 key 查找、touch、pin、unpin 和淘汰为均摊 O(1)，
不在每次释放时遍历版本表寻找可淘汰项；原有活动 session 取消遍历不冒充历史表整理。
detach／dataset 的批量撤销和配置依赖差量更新可按其当前集合遍历，不形成永久 owner 历史索引。

Core 表及持有计数由 registry mutex 保护；来源依赖的保护集合沿既有
`checkpointMu → registry.mu` 顺序更新，覆盖 prepare、失败、替换及 inline adoption。
不在持有 registry.mu 时反向取得 checkpointMu，也不在锁内关闭 socket。
Dart 继续使用原 isolate／dataMutations 顺序；回收不能跨 await 先删记录、再判当前资格。

### 兼容与范围

除上述两个私有 action 外，不新增公开 JSON 字段、Spec／ConfigInput schema、数据库或持久文件；
原“无 RPC action 增量”的首轮方案已修正。版本从“缺项零”变为“显式正值”，
因此配套 Dart／Go 实现及夹具必须同步，不能把旧零票据视为新资格；旧 Core 不支持 hold 时应明确失败。
checkpoint 只持久化依赖 key，重放时从当前 registry 取得新版本，不迁移旧计数。
新建 source／operation 的语义会落实到实际 capture／inspect 与 replay 提供方，
验证方统一拒绝缺项。普通非 Android 的来源权限和 ConfigInput v1 边界不扩大。

## 实施与验证

先完成下列当前文档基线，再修改生产和测试；不得将本方案提前写成已实现：

| 文档 | 本次职责 |
| --- | --- |
| 本 Plan | 交评方案、实施与实际验证记录；定稿交付后由 M 按既有流程清理 |
| [source_acceptance_design.md](source_acceptance_design.md) | 请求快照、版本／缺项语义、completion hold、活动保护、冷记录过期及恢复边界 |
| [.agents/architecture.md](../../../.agents/architecture.md) | Request／ConfigInput 所有权和资格表寿命的短摘要，链接长期契约 |

不增新 Spec／Guide／Result，不回写旧 Loop 文档；Issue 处置仍由 M 维护。
实现主要落在 Request／Core registry；ConfigInput、checkpoint、material commit、inline adoption 等
直接读者按缺项检查和配置依赖持有需要作必要协调；scripts／setup 落实 completion 交接，
managed_config／source_review_bundle 落实缺项和相邻版本检查，不重构其它生命周期或外部请求功能。

验收条件按独立可观察条件组织；实际执行结果见文末：

1. 同源码前后反例：批量提交远超 4096 的不同 key，含成功、拒绝、取消、完成，验证活动归零后
   三表达到平台期；同一 attachment 持续多轮也不增长。不能只测固定 key 或 detach 清零。
2. ABA：保留旧 source、operation、lease、permit、completion；淘汰、重建同名 key 后分别尝试
   check／begin／grant／配置提交，旧资格仍失败。保留现有恰好一次 invalidate 的正反例。
3. 并发：begin 等待时取消、旧 Close 晚于新 begin、重复 attach／detach、旧客户端迟到请求、
   receipt 未退出及 Complete 与淘汰交叉；验证最新意图和未知写者屏障。
4. 配置：采用真实 ConfigInput 后施加动态 key 压力，checkpoint、provider adoption 与材料保存
   仍成功；真实 source 失效仍拒绝旧输入。覆盖 failConfigBuild 保留／拒绝、LocalEdit 恰好一次／两次失效，
   prepare 失败后 pending 指针未清也不再 pin，以及 inline 依赖变更的释放。
5. 真实消费者：[CacheManager 扩展](../../../lib/common/cache.dart)通过受控 localhost 下载不同图标并取消订阅；
   [connectionExitsProvider](../../../lib/providers/connection_exits.dart)改变节点／ConfigInput 身份并取消探测。
   比较 Request 与 Go 控制链的记录寿命、迟到结果和实际请求次数，不能只测版本容器。
6. D1：穿过真实 updateScript→commit→debounce→_runSetup，在 session 已 close、callback／setup 队列
   仍等待时施加超过冷预算的图标／出口 key，正例须完成原自动应用；较新同 key 更新、切换 Profile／配置、
   Stop、pending 替换／取消和 provider dispose 仍拒绝旧结果并释放 hold。不能以重新 capture 作为正例修复。
7. 资源与耗尽：检查三表、冷 LRU、pin 和 hold 表的共同上界及单 key 整理路径；强制接近 `2^53−1`，
   覆盖创建跳号、逐次递增、LocalEdit 预测及耗尽后旧资格撤销、close／release 仍可执行。
8. 受影响 Flutter 专项、pub get、analyze，以及 Go wrapper tests／vet；定向并发验证明确原仓库
   CGO 测试标签限制，不能沿用 R07 overlay 结果冒充 R08 已验证。无 APK／AVD／P8 或真实外网测试。

当前依据分层：map 生命周期、直接消费者及 `+1` 约束来自基线源码静态核查；
1000 key 反例来自本地、未入库的 `.buildlog/review-d2-20261116-01/go-review-with-wrapper.log`
及同目录 `review_d2_routing_counterexample_test.go`；本轮运行结果如下。
本轮源码绑定和设计快照保存在本地、未入库的 `.buildlog/r08-request-keys-20261116/`。

## 首轮实施结果与交评边界

三表已接入有序冷 LRU，保护当前配置及在途资源；Dart 将 begin 等待的意图保存在同一有界 entry，
取消或新 begin 不会在旧 await 返回后被覆盖。重复 attach／detach 用独立 attachment revision 拒绝迟到结果，
不更改 Native 的 start／stop 状态机。Android ServicePlugin 白名单已同步放行两条获审私有 action。

本地、未入库的 `.buildlog/r08-request-keys-20261116/implementation-source.json`
绑定源码、原反例、执行命令、产物及全部结果；原两轮设计和失败日志冻结保留。
独立桥接统计在 4096／8192／12288 个不同 key 后，两张 Core 表均为 4096 冷项＋1 持有项，
辅助 entry 数同为 4097；释放后均为 4096，detach 后表、entry、LRU、hold、lease 和 receipt 全部归零。

| 范围 | 实际结果与限制 |
| --- | --- |
| 同源码前后反例 | 原实现两例失败：完成 8192 个不同 key 后仍增长，淘汰预期中的旧快照版本仍相同；修复后两例通过，连续三轮各 4096 key 进入平台期 |
| 保护与并发 | Go wrapper 440 个顶层测试通过，含 679 个 pass event；40 个环境选通用例 skip。真实 ConfigInput／checkpoint、inline provider 采用、材料 receipt 在 8192 无关 key 后仍有效，失败 pending 不再 pin |
| D1 | 真实 updateScript→保存→session close→debounce→setup 正例及新同 key 反例通过；另外 9 例覆盖 Stop、切换 Profile、不再使用、替换／dispose、保存失败、旧 Core 和执行中替换／dispose |
| 真实动态消费者 | 图标 CacheManager 路径实际下载 4097 个不同 localhost URL 并取消慢流；出口 provider 经 4097 个配置身份、持久缓存和 probe mock 完成生命周期；后者未测真实外网 |
| 耗尽与 ABA | birth／successor、两侧相邻版本预测、错误／关闭／已 grant lease、128 hold 满额前置失败、幂等释放、晚旧 Close／client、重复 attach／detach 均有正反例 |
| 并发检测 | 原生 race 因既有 !cgo 测试 helper 不可见而构建失败；仅移除该测试标签的本地 overlay 下，8 个顶层／17 个 pass event 通过，无 race 报告；不是完整 stock race 验证 |
| Flutter 完整回归 | 4916 个成功完成事件、32 个 skip、9 个失败；失败均来自未修改的 policy_mutation_failure_bridge_test.dart。独立 fresh-root 重跑确认首个失败只发生在 teardown 的无 receipt clearPartialCommit；其余失败受恢复标记残留影响，未改此范围之外的夹具 |
| 工具及 Android 桥 | pub get／codegen／Go vet 通过；analyze 只有原有 42 条 info。JDK 17 Kotlin 编译及 ServicePluginRequestControlTest 的 3 例通过；复用既有资源并排除 Flutter 资产构建，没有 APK／AVD／P8 验证 |

完整 Flutter 失败的 fixture 与 clearPartialCommit 方法均与基线相同，源码比较及独立复现另存
`unrelated-fixture-source.json` 和 `flutter-unrelated-fixture-08.log`；未声称已运行完整旧基线。
M 随后授权按 Q1 修复此 teardown 并补隔离回归，结果见文末，首轮失败记录保留。默认 Markdown 行宽检查另报
既有长行，结构检查不含该规则；图源和本地链接只做静态核查，未声称已渲染。

本轮没有修改 Issue、Core submodule／gitlink 或 carrier，没有进入 R09+，也未提交、合 main 或 push。

## 实现 Review 修订范围

I1：cancelProviderOwner／providerStage.retire 在原 mutex 边界释放 lease 自有 pin 并撤销 completion，
关闭 socket 仍在原锁外；未完成 receipt 的独立 pin 和 unknown-writer 屏障不随 lease 退休释放。
I2：guarded shutdown 等到真实 Initial／Close 和全局资源关闭完成后，在丢弃配置指针前释放其 sourcePins；
pending／applied 相同对象只释放一次，不在单纯业务撤销时提前释放仍被保留的配置。
Q1：对未修改的首个失败做原基线生产＋同 bridge 启用条件的 fresh-root 窄对照；
仅修测试夹具的强制资源收尾与隔离目录恢复状态，再重跑整组业务断言，不放松生产 recovery gate。
原实现快照和首轮测试冻结，新证据存入本地、未入库的 `.buildlog/r08-request-keys-20261116/revision-02/`。

### 修订验证结果

| 项目 | 反例／实际验证 |
| --- | --- |
| I1 | 最终同源码回归仅恢复修复前两个清理文件时失败：stage.retire 留下 source／operation 各 3 pin、geo 1 pin，旧 owner 遗留 pin 使新 owner 的持有计数也不正确；修复后四轮退休／Complete／新 owner 交错通过，receipt 自有 pin 不提前释放 |
| I2 | 原 shutdown 四轮 source pin 累计为 3／6／9／12；修复后真实 guarded shutdown→init→apply 四轮均为零，entry 与冷表一致，清冷项后归零。另保留原 Initial／Close 等待、超时隔离与旧到达屏障测试 |
| Q1 | 原基线 Dart／Go 生产与首轮新版在相同未改 fixture、bridge 启用条件及 fresh root 下，均只在无 receipt clearPartialCommit teardown 失败；修夹具的 finally、每用例目录及 AppPath completer 后，整组 10 个业务用例通过，业务断言主体逐字节未改 |
| 完整 Go | 普通 wrapper 441 顶层／680 pass event、40 skip；no_zerotier 452 顶层／703 pass event、40 skip，均通过；两种模式 vet 通过。首轮并行运行有一次 UDP 端口占用，后改串行运行并保留失败日志 |
| 桥接与并发 | no_zerotier Core 的 11 个真实 Script 续接用例通过；更新后的定向 test overlay race 为 14 顶层／23 pass event，通过；不是完整 stock race |
| 复用 | 生产 Dart／Kotlin 与首轮未变，复用其已绑定的 pub get／codegen、Android 编译和其它 Flutter 成功用例；Q1 整组及受清理影响的 Go／Script 消费者已重跑。analyze 仍仅原有 42 info，未重新跑完整 Flutter 根套件 |

扩展 stage 回归顺带补齐测试 checkpoint 的真实依赖，并在测试输入写入／注册期间持有既有 configMu，
避免后台 collector 删除未注册的夹具文件；未修改生产资格或 collector。

实际 shutdown→init 并发检测还发现 collector 的 C.Path.HomeDir 读取与 initializeCore 的 SetHomeDir 写入竞争；
用原基线生产、独立本地 probe 和仅移除 !cgo 测试标签的 overlay 复现了相同竞争。
此问题不由 R08 引入，已另向 M 汇报，本项未修改初始化或子模块。
R08 的 pin 验收在 collector 已退出的受控前提下循环重新初始化；上述原始 race 失败单列保留，
不能把这个限定下的通过写成整个 shutdown／init 已无竞争。

本轮冻结入口为本地、未入库 `.buildlog/r08-request-keys-20261116/revision-02/implementation-source.json`，
原实现快照、设计及首轮结果未覆盖；本轮仍不改 Issue／Core gitlink／carrier，不提交或操作设备。
