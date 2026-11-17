# F01 collector 生命周期 Plan

任务入口：[F01](android_branch_review_issue.md#f01配置-collector-与重新初始化并发访问-homedir)。
基线 `security/android`／`65fd20e`，Core gitlink 为 `7a620b930bdcb85e466450880313d34add46252b`。
方案、checkpoint 入口澄清及实现均已获 M 通过，自验完成；按约定进行本地 fixup 交付。
R01–R11 保持完成，其它延期事项不在本次范围。实际结果见 [Result](f01_collector_lifecycle_result.md)。

## 问题与目标

原 queueInputCollection 同时由配置采用与 accepted checkpoint 发布调用，后者只用原子标记合并任务，并捕获旧 home。
goroutine 尚未执行或正在等读资格时，guarded shutdown 可先完成并允许 Init 修改全局 HomeDir。
collector 在 lockConfigInputRead 取得 configMu 前又经 beginRequestDataRead 读取全局 HomeDir，形成数据竞争。
目标是让关闭覆盖它实际启动的异步回收工作：旧任务真正退出后，才允许关闭完成和新目录初始化。
保留读／提交资格、引用 pin、回收目标及原 shutdown 超时隔离，不把逻辑取消当作实际退出。

R08 revision-02 的旧证据已核验：34 个 overlay 输入及 probe 摘要匹配；真实 apply→shutdown→init
八次循环报告上述 HomeDir 读与 SetHomeDir 写的竞争。config_inputs 与当时基线相同；
provider_lifecycle 的后续变化仅为退休配置释放 source versions，没有加入 collector 等待。
这是原基线 race 证据，不是当前版本通过记录，也未证明误删、丢数据或设备故障。

## 方案与理由

| 候选 | 判断 |
| --- | --- |
| 只把捕获的 home 传入读屏障 | 可避开这一全局读取，但旧 goroutine 仍可越过关闭／同目录重启，且旧队列占位可能影响新轮次；不足以闭合退出所有权。 |
| 在 activate 内同步回收，或持 configMu 等回收 | 前者将文件 IO 串入配置采用，后者使需要 configMu 的 worker 无法退出；不采用。 |
| 登记异步回收并由既有 guarded shutdown 等其退出 | 推荐；复用现有生命周期 admission，保持后台回收，只补实际完成边界，不新增目录镜像或生命周期状态机。 |

在 FlClash 包装层为已排队 collector 增加完成登记，例如 sync.WaitGroup；保留现有合并标记和捕获目录。
queue 的两个生产调用点均在 configMu 内：activateConfig，以及 publishCheckpointCandidate。
后者由持锁的 handleChangeProxy／updateConfigOwned 经 saveAcceptedConfigChanges 到达。
明确共享 queue 的持锁契约；成功占位后、派生 goroutine 前登记，
worker 的所有返回／错误／panic 展开路径均释放登记，不提前把未退出 IO 当作完成。

guarded shutdown 的既有 admission 先阻止新 activate／Init；关闭 worker 取得并释放 configMu 后，
在不持 configMu、stagedCore、checkpoint 或 registry 锁时等待已登记 collector，随后才做物理清理和发布关闭成功。
登记与关闭 fence 的锁顺序保证不会在 Wait 期间出现新轮次 Add；不得在 goroutine 内迟到登记。
collector 的顺序仍是读／提交屏障 → configMu → 原 checkpoint／registry／stage 引用核对，不反转其锁。
目录切换及同目录重启均不能越过该退出条件；挂起时沿原超时返回未完成，保留 isInit／隔离，不放行新 Init。
失败回收只按既有错误语义结束，不能移除活引用、绕过恢复 marker 或把关闭返回解释为回收成功。
checkpoint 候选须处于 ready 且核相同 version／owner；shutdown 在 configMu 内置 retired 并推进 version，
fence 前成功发布的登记被包含，fence 后的新候选／旧候选不能再发布并排队。
同步 releaseConfigInput 及其它请求资格入口不引入新授权；本次修复限配置采用与 accepted checkpoint 发布的共享异步回收。
未采用 no_zerotier 的旧生命周期路径、Core 子模块／gitlink／carrier 和设备行为不改。

## 实施与验证

方案获审后先同步长期文档：`.agents/architecture.md` 的生命周期所有权、
`business_data_design.md` 的全局生命周期与就地重建、`source_acceptance_design.md` 的 collector 引用寿命。
再改包装层登记／关闭消费者及针对性 Go 测试；实测后新增本任务 Result，Issue 与最终任务文档清理由 M 负责。

保留旧 R08 证据，针对当前父基线取得修复前反例，再走同一真实 apply→shutdown→init 链验证：
不在 shutdown／init 前由测试等待 collector；覆盖同目录连续重启、目录切换、迟到 worker、取消／关闭重叠，
并断言旧目录自有垃圾回收、活引用保留、新目录文件不被旧任务触及及正确初始化／关闭结果。
补实际 checkpoint 消费者排队后的关闭交错，以及 fence 后新／旧候选均不能新增回收；生产两条调用链的锁覆盖一并核对。
另覆盖读资格或文件 IO 失败的登记释放，保留现有 shutdown／请求资格回归。

race 使用 no_zerotier、CGO 与实际生产 registry／Apply／shutdown／Init。
若因 fakeConn 等测试 helper 的 !cgo 标签不能编译，最小 overlay 只移除该测试文件标签并绑定原文，
不改生产；确定性迟到场景如需 gate，仅 test-only 暂停点并记录精确 diff，与无 gate 的真实循环分开。
gate 不预先排空 collector、不替代修复，也不省略原资格或回收实现。
运行受影响 Go race／普通回归、host vet、格式／密度及文档检查，按实际影响决定是否补 Flutter 消费者；
不将局部 race 选集称为全仓通过，不无理由重跑未变 JNI／设备矩阵。不 main／push／autosquash 或操作设备。
