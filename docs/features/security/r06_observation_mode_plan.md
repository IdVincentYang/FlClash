# R06 连接模式事实修复 Plan

任务入口：[R06](android_branch_review_issue.md#r06应用规则命中把实际-direct-模式重标为-rule)。
输入基线为 `security/android` 的 `1e962dc`。设计与实现评审通过；本地交付定稿，
R06 由 M 完成交付对账和 Issue 收尾。

## 问题与目标

`connectionObservationStore.bind` 把非空 AppliedRevision＋Rule 当作 Rule 模式证据。
ApplicationRoutingHook 在 Direct 也返回规则，因此真实 App／App＋Host 连接会被误标。
目标是修正冻结的模式事实，不改变实际出口、匹配优先级或冻结后不可回填的规则。

入口保存 `observedConfiguration()`；Tracker 加入时再读取一次，只有 inputId、mode、routeEpoch、
picksVersion 全部一致才保留完整快照。配置读取拿不到非阻塞锁则 unknown；模式变更经既有
`updateConfigOwned` 更新并推进 routeEpoch，不能仅以两次 mode 同名判断没有切换。
matcher／App hook 的追溯另行证明实际使用的 inputId，可能与 Tracker 加入时的当前配置不同。

## 方案与理由

推荐复用既有追溯索引：普通 `sourceTracedRule` 的索引来自主规则列表，为非负值；
App hook 创建的 frame 为 `-1`。`bindSourceTracker` 只有在时限、metadata、实际 rule／payload／chain
核对通过后才传出该索引；默认未知也是 `-1`。保留原 AppliedRevision、非空 Rule 条件，
再要求索引非负，才能由 matcher 追溯推断 Rule 模式。稳定入口快照仍能证明 Direct／Rule／Global。

不直接按 origin 字符串排除 `application-rules`：普通 YAML 中用户添加规则也使用该 origin，
但确实经过 Rule matcher。索引区分实际调用路径，避免新增重复字段或把来源作者当作模式证据。
仅删除赋值会丢掉普通 matcher 在迟到 Tracker 中仍能证明的 Rule；用 bind 时的 tunnel.Mode()
直接补值则会把新模式写给旧连接。均不采用。

| 证据 | 配置事实 |
| --- | --- |
| 入口／加入快照及版本戳一致 | 保留原 inputId、mode 和路由版本 |
| 实际追溯证明另一个 inputId | 只保留该 inputId；清除不属于它的 mode 和路由版本 |
| 有版本的普通 matcher，索引非负且 Rule 非空 | 可证明 Rule；不因此补出 routeEpoch／picksVersion |
| App hook，索引为 -1 | 不推断 Rule；保留已证明的稳定模式，否则 mode 留空 |
| 无稳定快照且追溯缺失、过期或无法证明 inputId | 维持 unknown，不读取当前配置补历史 |

mode 是可选字段，缺失使用空值／省略，不新增字符串状态；status=known 只证明 inputId。
routeEpoch、picksVersion 任一不同，包括 Direct→Rule→Direct 的版本变化，都不能保留完整快照。
Global 原本跳过 App hook；规则／链继续来自实际 Tracker，空 Rule 不伪造 matcher 证据。
首次 bind 后保持只读冻结；迟到配置更新、再次 bind 和 snapshot 均不能重标旧事实。

改动预计仅在 Go 包装层的观测判定及回归，无需改 sourceTrace 协议、上游 Core、Dart 模型或 DB。
若实验证明现有索引不能区分上述真实路径，先带证据复审，不先扩充观测框架。

## 实施与验证

1. 设计通过后先修订当前 [应用网络设计](../network_activity/network_activity_design.md#连接事实与版本)：
   替换“非空规则即 Rule”的过时说明，明确 App hook、索引依据及部分已知配置，标明待实现；
   验证完成再更新为实际状态。架构入口已链接该契约，不回写旧 Result 或增加平行规范。
2. 先在旧生产上运行新增回归并冻结反例，再改判定。复用现有隔离进程、受控配置和 localhost
   echo，走真实 App／App＋Host hook、普通 matcher、`bindSourceTracker` 和观测 bind／snapshot。
   Direct／Rule 下命中 App 或 Host 都保留实际模式；普通 YAML 规则含 `application-rules` origin
   仍能证明 Rule。Global 验证 App hook bypass，实际链／载荷独立证明出口未变。
3. 边界覆盖无入口、配置锁占用、inputId／mode／routeEpoch／picksVersion 各自变化、模式往返、
   未匹配／失效追溯和迟到 Tracker。真实链验证模式切换发生在建连后、Tracker 冻结前时，
   App 追溯只留下 inputId；普通 matcher 仍可证明 Rule。另检验冻结后切换不改记录。
   控制交错使用本地测试门，不靠 sleep 猜时序；超时失败，不能用伪造 mode 作唯一 oracle。
4. 运行 Go 观测／追溯／App／Host 专项与 `CGO_ENABLED=0 go test .`／vet；
   必要时补 Go JSON→Dart 模型／展示专项，修正既有 Android bridge 对 known 必有 mode 的过强断言。
   协议不变则无需 codegen；按项目要求检查 pub get／analyze／覆盖测试，复用未变 Native 证据。

证据保存在本地、未入库的 `.buildlog/r06-observation-mode-20261116/`，绑定前后源码与产物，不改旧证据。
host 合成链不代表实际 JNI、Android 调度或 VPN；仅使用 localhost，不操作 APK／设备、Issue、
R07、main 或远端。设计和实现分别经 M 评审后才进入对应交付阶段。

## 实际结果与复核

生产仅增加非负追溯索引条件，并修正对应注释。Go／Dart 观测字段、上游 Core、Native 和 DB 未改。
同一专项源码的最终旧基线为 `go-before-04.log`：真实 Tracker 14 项中 7 个模式断言失败，
局部 bind 边界 18 项中 5 个失败；修复后两组均全部通过。前两次运行包含夹具与既有后台输入清理
并发造成的准备错误，保留为 setup 记录，不计为产品反例；最终夹具等待其结束，并核对初始配置已知。

真实用例在 Core `DefaultRequestNotify` 已拿到实际 rule／chain、观测 bind 尚未运行的位置设门；
核对 pending trace 的 input／index 及当时 tunnel.Mode，再调用合法模式更新或完整配置应用。
13 项本地 TCP echo 正常，完整 ConfigInput 替换一项的旧 lease 失效、传输终止；超时视失败。
局部 bind 组单独改变入口字段或移除／过期／破坏追溯，只证明观测组合边界，不冒充系统连接交错。
每条真实记录还验证冻结后更新模式、再次 bind／view 不改变原 observation。

Go wrapper 常规测试与 vet 通过：417 个 top-level 通过（含子测试为 640 个 pass 事件），
40 个既有条件 skip 不计通过；本项两个新专项没有 skip。Dart 模型、聚合、连接／应用组件专项
111 通过、2 个既有桥接输入 skip，无失败。新常规模型回归始终验证部分已知模式；本次另加载
`modes-after.json` 的 14 条真实 Core 输出，验证 request 分派、snapshot 和 JSON 往返均不补造 mode。
pub get 锁定离线通过；analyze 的 42 条 info 与 R05 逐条相同，无 warning／error。
Flutter runner 的 Go asset hook 临时关闭，Rust hook／真实资源保留，结束后原样恢复 pubspec；
本次不把它描述为 Android 打包或 JNI 验证。

在 `core/` 运行 `CGO_ENABLED=0 go test -count=1 -run '^TestConnectionMode' -v .` 可重跑专项；
设置 `FLCLASH_CONNECTION_MODE_FIXTURE=<绝对路径>` 可另存真实记录，再将该变量传给
`flutter test test/models/connection_observation_test.dart` 运行实际跨语言消费者检查。
不设置该变量时，部分已知数据的常规回归仍执行，没有增加默认 skip。
完整命令、前后源码绑定及结果在上述本地证据目录的 `before-source.json`、
`implementation-source.json`、`modes-before-04.json`、`modes-after.json` 和对应日志中保存。
