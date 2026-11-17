# F01 collector 生命周期 Result

对象为 `security/android`／`65fd20e` 之上的 F01 本地 fixup，实现已获 M 通过。
最终版本由包含本文件的提交标识；Issue、Details 及任务文档清理由 M 完成。
范围与方案见 [Plan](f01_collector_lifecycle_plan.md)，长期退出边界见
[全局生命周期与就地重建](business_data_design.md#全局生命周期与就地重建)。

## 结果与实际边界

共享 queueInputCollectionLocked 在 configMu 内、派生 goroutine 前登记完成责任；
worker 在文件回收及队列占位清理后才 Done。配置采用和 accepted checkpoint 发布均使用该入口。
guarded shutdown 在不持 collector 所需锁时 Wait，再继续既有物理清理与关闭成功发布。
没有改变读／提交资格、引用核对或回收规则，也未新增 HomeDir 镜像或修改 Core 子模块。

| 验证 | 实际结果及口径 |
| --- | --- |
| R08 原基线证据核验 | 34 个 overlay 输入匹配；26 个原文件等于旧基线，8 个后来新增文件为空 package；probe 与 helper 摘要匹配，原 race 记录保留。 |
| 当前父基线、原无 gate probe | 真实 apply→shutdown→init 八轮，race detector 报 collector 的 HomeDir 读与 SetHomeDir 写竞争，测试失败。 |
| 修复后相同原 probe | 最终版本通过八轮相同链，无 race；仅测试 helper 标签／probe overlay，无生产 gate。较早另有三次通过，保留为中间记录。 |
| 确定性父基线反例 | 同一迟到测试在父生产代码上失败：collector 尚暂停，shutdown 已报告成功；这项 gate 反例与数据 race 反例分开。 |
| 确定性受控 race 选集 | 3 个测试组、11 个子场景，14 个含组的 test pass events，0 fail／skip；不是 14 个独立业务场景。 |
| 无生产 gate 的生命周期 race 选集 | 5 个顶层 test、7 个含子场景的 pass events，0 fail／skip；包含新同目录／切换循环和原关闭／退休／版本引用回归。 |
| 普通 Go wrapper 回归 | CGO_ENABLED=0，444 顶层 test、683 含 subtest 的 pass events，40 个既有 skip，0 fail；没有启用 race。 |
| 静态检查 | host vet（默认及 no_zerotier）、gofmt、默认 5% comment-density、diff 检查通过；五份 Markdown 无问题，119 个本地引用、15 个锚点有效。 |

原 probe 与新无 gate 循环均不在 shutdown／Init 前预先等待 collector。
同目录及两个目录交替各走八轮，确认 shutdown 返回后队列已清、旧自有 hash 垃圾回收、checkpoint 活引用保留，
新生命周期的 hash 文件不被迟到旧任务清除，Init 及最终关闭成功。

受控迟到场景分别经真实 activate、updateConfigOwned 和 handleChangeProxy 到达共享队列，
各覆盖同目录与目录切换。两个 checkpoint 场景只等待初始 fixture 的采用回收完成，再触发待测发布；
不预先等待待测 collector，不用该准备步骤替代无 gate 的真实循环。
暂停待测 worker 后，关闭超时返回 false，isInit 与占位保留，新 Init 被拒绝；
新 checkpoint candidate 不产生、旧 candidate 不发布。重复到达的 shutdown 共用原 work，
释放 worker 后才成功，队列清理完成，之后新 Init／新 collector 可继续使用。
资格 fault、真实候选文件 IO 错误及 panic 展开均释放完成登记，活文件保留，不能把关闭成功写成垃圾已回收。

## 证据与复现

本地、未入库证据位于 `.buildlog/f01-collector-lifecycle-20261117/implementation-01/`，
源码／依赖、命令和日志由同目录 manifest 绑定，R08 原记录和本次失败均保留。
`go-race-before.jsonl` 与 `go-race-original-final.jsonl` 对应相同原 probe 的修复前后；
`go-before-gated.jsonl` 与 `go-gated-02.jsonl` 对应迟到断言的父基线反例及最终受控选集。
普通回归与无生产 gate 的 race 分别为 `go-root-final.jsonl`、`go-race-lifecycle-final.jsonl`。

race 必须启用 CGO。既有 ipc_test.go 将 fakeConn 等 helper 限为 !cgo；overlay 只去掉该测试标签，
没有修改 IPC 生产。原 probe 以虚拟测试文件加入；确定性选集另在队列清理 defer 之后增加一个测试暂停调用，
由 test-only gate 控制，原回收、资格、完成登记和 shutdown 均运行生产实现。
父基线确定性反例恢复四个已改生产文件至父版本，再加入同一个 gate；没有带入修复代码。
overlay 的精确差异和 SHA 与实际命令绑定，不能将确定性 gate 当作无插桩 race 证据。

需使用 manifest 绑定的源码、Go 1.26.4、已配置依赖及保留的本地输入，在仓库根目录重放。
下面先运行受控选集，再运行只替换测试 helper、没有生产暂停点的实际循环：

```bash
f01_evidence_root="$PWD/.buildlog/f01-collector-lifecycle-20261117/implementation-01"
CGO_ENABLED=1 GOPROXY=off GOSUMDB=off GOTELEMETRY=off \
  FLCLASH_COLLECTION_GATE_OVERLAY=1 \
  go -C core test -race -tags no_zerotier \
    -overlay "$f01_evidence_root/gate-overlay.json" \
    -run '^TestInputCollection' -count=1 -timeout=90s .
CGO_ENABLED=1 GOPROXY=off GOSUMDB=off GOTELEMETRY=off \
  FLCLASH_COLLECTION_GATE_OVERLAY=0 \
  go -C core test -race -tags no_zerotier \
    -overlay "$f01_evidence_root/ipc-only-overlay.json" \
    -run '^TestInputCollectionRestartCycle$' -count=1 -timeout=90s .
```

overlay 保存原工作区的绝对路径；迁移时另建映射并核对输入摘要，不覆盖冻结证据。

早期一次命令因输出相对路径错误未启动测试；首次收尾编译暴露遗漏的 checkpoint 排队调用，未进入测试。
该编译失败保留为 `go-race-after-cycle.jsonl`。随后核对两条 checkpoint 消费链，获 M 澄清通过后
先修正文档，再同步私有调用名；未覆盖旧失败或冻结 design-01。

## 收尾自验

获审生产代码、测试和 162 个 root Go 输入均未改变；收尾仅更新 Plan／Result 状态及补充上述重放命令。
提交前结构检查未发现需调整的职责、重复状态或多余抽象，原 Go 结果按相同源码复用。
补做 offline pub get、Flutter analyze 和协议／退出／Bootstrap 三个文件选集：39 pass，0 fail／skip；
analyze 保留原 42 条 info，无新增 error／warning／info。
这些消费者检查不等于设备上的 Go 生命周期验证；实际目录与退出保证仍以上述 host Go 证据为准。
收尾格式、引用、纳入范围及提交对应保存在本地、未入库目录
`.buildlog/f01-collector-lifecycle-20261117/delivery/`，获审 evidence 保持冻结。

## 限制

只覆盖 no_zerotier guarded 生命周期及配置采用／accepted checkpoint 发布的共享异步回收，
不宣称所有 HomeDir 读取或旧非 guarded 路径均已同步。
collector 挂起时保留原关闭 fence，不保证终止 goroutine；IO／资格失败也不承诺清理成功。
原观察只证明 race，本轮没有证明既有用户曾被误删、丢数据或设备崩溃。
没有修改 Core 子模块／gitlink／carrier、JNI／RPC envelope、其它延期事项或 R01–R11 完成状态。
未运行全仓 race、APK／真实 Android 存储或设备验收；host race 编译不等于 Android 产物或设备通过。
