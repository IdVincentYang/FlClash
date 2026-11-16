# R07 来源追溯热路径优化 Plan

任务入口：[R07](android_branch_review_issue.md#r07规则追溯在逐条匹配中重复扫描全局表)。
输入基线为 `security/android` 的 `d493418`。设计与实现评审通过；本地交付定稿，
R07 由 M 完成交付对账和 Issue 收尾。

## 问题与目标

每个 `sourceTracedRule.Match` 都在全局锁内扫描 active／pending，并预建 provider map；
未命中链的成本随规则数与待建连数相乘。Issue 的 host 局部测量说明该增长，不是设备耗电结论。
目标是移除逐规则重复维护与无用分配，保留实际 matcher、版本资格、过期拒绝和有界追溯。

## 方案与理由

推荐在现有锁内增加一个共享的下次清理时间，普通 Match 和 App hook 写入前共同调用维护函数。
函数在已取得锁后采样当前时间；未到期只比较时间，到期扫描两表并将下次维护推后一秒。
不创建后台 goroutine。持续活动时过期项在后续维护删除；空闲时可留到下一次调用，但表仍有界。
相比只在满额时清理，这一方案在正常流量下也能回收过期引用，时限与维护成本更容易解释。

一次扫描仍为 O(A＋P)，active／pending 各保留现有 2048 门限，每次最多检查 4096 项，
全局最多每秒一次；未到维护点的 R 次尝试只有 O(R) 的维护判断。单次最坏扫描成本没有消失，
普通 Match 的入场／完成及 provider 回调仍使用原锁，不声称锁次数减少。
原 frame 的起始时间和 bind 的一分钟拒绝条件保持；延迟物理删除不延长证据有效期。

provider map 改为首次有效 provider 命中时才分配；普通非 provider／未命中路径不建空 map。
frame 仍按原调用建立，不引入复用或池，避免迟到回调、嵌套匹配持有同一对象的问题。
nil map 的读取／遍历保持原含义；首次写入仍在同锁内，保留 parent、材料 digest 和最多 16 项的校验。

| 阶段 | 所有权及释放 |
| --- | --- |
| 普通 Match 执行中 | active 持有当前 frame；回调只能修改该 metadata 下的当前 frame |
| 未命中／panic | 释放本次 active；panic 继续传播，原清理 defer 不吞异常 |
| 命中／App hook | pending 持有实际 rule／payload／target 与版本快照，等待 Tracker |
| Tracker bind | 移除 pending；过期或最终匹配不一致则 Unknown；复制为最多 4096 条冻结标签 |

保留同 metadata 重入／并发时的 frame 身份比较；旧完成不能提交新 frame 的追溯。
满额时仍执行原业务匹配／转发，只缺少追溯，不能借另一条记录补齐。
静态检查还发现：仅入场检查不足以限制多个 active 同时转 pending，例如 2047 条 pending 后
两个已准入 Match 都命中。拟在转入点复核相同 pending 门限，允许替换同 key，但不增加条数；
App hook 沿用同一维护和限额。这是对原容量目标的落实，不提高上限或放松版本资格。

## 实施与验证

1. 获准后先更新当前 [来源接受设计](source_acceptance_design.md#轻量连接追溯)及其有界保存表，
   明确 active 工作表／pending 暂存各 2048、60 秒证据有效期、清理频率和满额降级，标明待实现；
   [应用网络设计](../network_activity/network_activity_design.md#连接事实与版本)的 provenance 入口
   引用该契约，不把入口身份缓存的清理规则混作规则追溯规则。完成验证再更新实际状态。
2. 先保留旧生产失败与基准，再实现维护门、懒分配和转入限额。确定性测试直接控制维护时间参数，
   验证一次清理后同窗口不再扫描、下一窗口回收；集成检查普通 Match／App hook 共用维护门。
   清理尚未运行时仍向真实 bind 提交过期 frame，必须被拒绝；不使用绝对耗时阈值作功能测试。
3. 覆盖 fresh／expired active 和 pending、满额拒新与恢复、两个 active 并发转入、未命中、panic、
   同 metadata 重入、不同 metadata 并发、provider parent／材料不一致及 sub-rule 的保守来源。
   用测试门控制交错；原 wrapper 的 disabled／统计／Unwrap 等消费者保持。
   复用真实 Tracker 的 provider 更新／PASS／sub-rule 冻结回归与 R06 的 32 个模式事实用例；
   实际链与 localhost 载荷证明追溯维护不改变路由，不改冻结事实。
4. 同机同 Go 工具链、相同测试源码对照：pending 为 0／128／1024／2047，
   每轮 100 次未命中 parser wrapper Match；另测不同规则对象的长链、命中／provider 及并发负载。
   setup／填表不计热路径，记录每轮 ns/op、B/op、allocs/op，至少 5 次样本并报告中位数及范围。
   稳态与一次到期扫描分别测量，说明维护相位、active／pending 数及基准校验条件，
   不把摊销改善写成单次最坏延迟或 Android 性能保证。
5. 运行 Go 追溯／App／观测专项、完整 `CGO_ENABLED=0 go test .`／vet，
   并以 host `CGO_ENABLED=1 go test -race` 运行本项确定性并发专项；若环境不支持则如实记录，
   保留实际可执行的并发检查而不称为 race 通过。按项目要求核对 pub get／analyze／相关 Flutter 消费者，
   未变 Native 验证可复用，不重建 APK。生产预计只改 Go 包装层，无 DTO／DB／codegen 或 Core carrier 变化。

证据保存在本地、未入库的 `.buildlog/r07-source-trace-20261116/`，绑定前后源码、工具链和原始样本；
不改历史证据、Issue、R08、main 或远端，不操作 APK／设备。实际结果在下节记录，不作设备性能保证。

## 实际结果与复核

生产仅修改 Go 包装层：共享维护门、provider 懒分配及两处 pending 发布共用的容量判定。
原 frame 时间／bind 过期条件、版本／材料校验、冻结 DTO、路由目标与 Core carrier 均未改。

旧生产上两个新增回归失败：空 provider map 已被分配；2047 pending 加两个已准入匹配的完成
实际达到 2049。相同兼容测试源码修复后通过；新增维护窗口／满表／迟到回调专项也通过。
这些包含 9 个新 top-level、7 个子项；维护函数的新增时间参数专项只在新实现上运行，
不冒充旧实现已能编译该新接口。真实 provider／PASS／sub-rule 和 R06 的 32 项模式事实回归通过。

同机 Go 1.26.4 darwin/arm64，14 个基准配置各 5 个样本，原始样本及中位数／范围保留。
下表为同一个 wrapper 连续 100 次未命中，时间单位为 µs，括号内为 5 次范围；setup 不计时。

| pending | 原中位数（范围） | 新中位数（范围） |
| --- | --- | --- |
| 0 | 13.480（13.475–13.593） | 13.625（13.489–13.672） |
| 128 | 87.217（85.921–87.893） | 13.758（13.740–13.774） |
| 1024 | 631.013（616.602–640.737） | 14.172（14.151–14.185） |
| 2047 | 1272.984（1265.482–1284.498） | 13.887（13.883–13.946） |

该组每轮分配由 27200 B／200 次变为 22400 B／100 次。100 个不同规则对象的长链得到同样的
分配变化；空表中位耗时增加约 1–2%，保留这项维护判断成本，不表述为所有路径更快。
并发 100 次未命中、pending=1024 的中位数由 835.723 µs 变为 41.515 µs；锁次数未减少。
单条命中无 provider 为 173.4→151.0 ns，分配 2→1；provider 命中为 248.6→240.9 ns，仍为 4 次分配。

单次到期清理在每个子项的独立新进程中以 `-benchtime=1x -count=1` 取样；两表各 2048 条过期项时
中位数 368.625→351.208 µs，范围分别为 310.750–476.292／183.792–445.458 µs。
该冷测量波动大，仍有全表扫描成本，不能当作稳态或手机延迟保证。冷基准有运行条件检查，
须分别选中 `BenchmarkSourceTraceCold/each_0`、`each_1024`、`each_2048`，不能把三项当作同一新进程。
完整样本、命令及其维护相位说明在本地 `bench-before-metadata.json`、`bench-after-metadata.json`、
`bench-comparison.json`；相同基准与兼容测试源码 Hash 已核对。

完整 Go wrapper 测试／vet 通过：426 个 top-level，含子项 656 个 pass 事件、40 个既有条件 skip。
普通 CGO=1 race 首次构建因既有 `ipc_test.go` 的 `!cgo` 标签排除共享 helper 而失败，尚未执行测试；
本地 overlay 仅去除此测试文件的标签，不改生产或入库文件，定向 race 随后 9 个 top-level／16 个事件
全部通过，无 skip／data race。不是完整仓库的原生 race 通过；原失败与 overlay 源绑定保留。
Flutter 模型／聚合／连接及应用组件 111 通过、2 项既有桥接输入 skip；生产 Dart／模型未改。
锁定离线 pub get 通过，analyze 与 R06 相同 42 条 info，无 warning／error。Flutter runner 临时关闭
Go asset hook、保留 Rust／真实资源并恢复原 pubspec，未变 Native 复用有效证据，没有 APK／设备验收。

Go 专项可运行 `CGO_ENABLED=0 go test -run '^TestSourceTrace|^TestConnectionMode' .`；
常规基准使用 `go test -run '^$' -bench '^BenchmarkSourceTrace(Chain|Matched|Parallel)$' -benchmem -benchtime=200ms -count=5 .`。
本地证据目录另含 `before-source.json`、`implementation-source.json`、Go 完整 JSONL、race 的原失败及
overlay JSONL、Flutter 日志；历史证据保持冻结，不将这些 host 结果推导为 Android 耗电收益。
