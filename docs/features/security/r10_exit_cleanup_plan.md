# R10 exit cleanup Plan

任务入口：[Android branch review Issue](android_branch_review_issue.md#r10android-退出前置失败跳过保存与-bootguard-收尾)。
设计基线 `82c61eb`，D1／Q1 修订设计通过；实施父基线为仅修正文档的 `5d16bb9`。
首轮实现证据已冻结；实现评审 I1 已复现、修订并自验，M 实现复审通过，当前进入本地 fixup 收尾。

## 问题与目标

实际入口为窗口／tray／快捷键 → [SystemAction.handleExit](../../../lib/providers/actions/system.dart)
→ [SystemExitCoordinator](../../../lib/providers/actions/system_exit.dart)。cleanup 内 prepareRunIntent(exit)
或 Request.detach 异常会跳过保存、tray 及后续并发收尾；外层仍可 close Core／exit，却补不了内部动作。
目标是失败后继续尝试独立收尾，保留错误、正常提交资格、退出一次及 watchdog。
不改退出调度框架、Core 生产／JNI、R11 或 F01，不声称已复现用户数据丢失。

有两点须纠正现状前提：handleExit 已提前发起 BootGuard.markClosed，缺口是 cleanup 跳过等待，
并非整个退出链完全没有关闭尝试；Request.detach 会先清空 Dart 的 client，
localCommit 随后进入无 client 路径。Core 虽允许原 client 的 lock，但 detachFrontend 已将
clientReady 置 false，[beginRequestCommitMarker](../../../core/source_commit_marker.go)还要求 clientReady；
故仅保留 Dart client 也不能正常保存。退出保存必须完成整个 lock → beginCommit → complete，
不能以 lock 成功或无 receipt 写入代替。

## 方案与理由

| 候选 | 取舍 |
| --- | --- |
| 只增加独立 catch，或保留 detached client | 前者保留无 receipt 路径，后者仍被 beginCommit 拒绝，均不可用。 |
| 直接将保存搬到完整 detach 前 | 提交条件成立，但等待保存时 Dart 会话和新请求入口仍未撤销。 |
| detach 后增加 Core local-only 提交契约 | 须另定义 ready 以外的 admission、receipt 寿命和放行用途；现有提交边界可满足需求，不增加该许可。 |
| 先撤销 Dart 请求入口，保存后再 native detach | 推荐；沿用既有 Core 条件，不新增 retained 状态，也不恢复 ready。 |

SystemAction 内采用局部错误收集，顺序明确为：**Dart quiesce → prepare exit → qualified save → native detach**。
从 Request.detach 提取本地 quiesce：撤销 container／listener、取消会话并推进 attachment／dataset revision，
阻止新 begin；暂不丢弃本次原 client，也不向 Core 发送 detach。保存结束或失败后仍执行完整 detach，
清空 client 并撤销 native clientReady。prepare 失败不跳过保存，保存失败不跳过 detach。
needSave=false 不申请保存资格，直接进入 detach，其余资源收尾不省略。

quiesce 返回只供本次退出使用的 commit closure，捕获原 client 与 attachment revision，不存入 Request 字段。
该 closure 在串行写队列内、原生授予后及写动作之前核对同一 attachment／client；
Android 必须有原 client 并通过原 lock／beginCommit，缺失、fault、未知写者、替换或迟到调用均失败，
不能落入 localCommit 的无 client 分支。它只收紧退出保存，不改变其它无 client 调用者的既有行为。
新 attach 或完整 detach 推进 revision 后 closure 失效；已进入物理 IO 的写不能伪称撤回，
仍由自己的 receipt 完成并保留未知写者／marker 责任。桌面维持既有本地保存。

tray／BootGuard 等独立资源收尾在本地撤权后启动，不依赖前置或保存完成；window／Core 仍待正常 cleanup 返回。
每一步捕获同步／异步异常，记录步骤名和额外失败，向外层保留首次捕获的原 error／StackTrace，不新增汇总异常。
退出保存使用该边界；最小化窗口的 best-effort 保存不变。

BootGuard 继续在 handleExit 同步撤销内存许可，并尽早发起关闭；为返回的 Future 接上错误观察，
cleanup 独立等待同一个幂等关闭结果，不能因前置失败跳过。其内部 IO 失败仍按
[BootGuard 契约](boot_recovery_design.md)处理，不把 close 尝试写成成功持久化。
coordinator 的 Future 合并、closeWindow → closeCore → exit 顺序和三秒 watchdog 不变。
保存挂起时不提前 native detach 使在途写失去边界；watchdog 仍可退出一次，
不能把 emergency exit 当作保存／detach 已完成，不重试或另启动第二轮收尾。

不留下 post-detach 保存资格：重复退出合并一次；重复 detach 不产生 closure；
attach 失败后再退出或从未成功 attach 的 Android 保存明确失败、写动作零次，needSave=false 仍正常收尾。
旧 closure 跨新 attach 在写前被拒绝，旧已开始 receipt 只处理自己的完成，不撤销新 owner。

### I1：存储准备与实际写入口

Bootstrap 在进入应用前已等待 preferences 初始化，但 saveConfig 中再次 await 已完成的 Future
仍可能让出执行权；action 入口检查不能覆盖其后、setString 之前发生的新 attach。
先沿实际 savePreferences 消费者，以已完成的 preferences Future 验证该交错，不把人造未初始化当作生产前提。
存储句柄的异步准备移至提交 closure 之前，closure 内读取最新 Config 并同步调用已准备好的 setString 写入口，
从 owner 检查到存储调用之间不再 await；现有 saveConfig 消费者复用同一存储准备能力。
不增加权限框架、Request 字段或新的提交资格。写入口调用后的 Future 仍归原 receipt 完成，
新 attach 不能让旧 final detach 撤销新 owner。补证覆盖准备期间替换和已开始写后的替换，保留首轮证据。

## 实施与验证

获审后先同步文档基线，再写生产与测试，最后回填实际证据：

- `.agents/architecture.md`：更新 Application exit 的失败继续、错误与顺序边界。
- `docs/features/security/source_acceptance_design.md`：补退出保存的 pre-detach admission 与 attachment fence。
- 本 Plan 随进展维护；实测后新增 `r10_exit_cleanup_result.md`。BootGuard 现有契约继续引用；
  Issue 和完成文档清理由 M 负责，不回写历史任务。
- I1 修订同步上述长期契约并保留文档基线，再修改 `Preferences` 存储准备、退出消费者与针对性测试；
  新修订证据另存，未变 Go／JNI 证据沿用。

在现有 SystemAction 测试中走真实 handleExit／cleanup／savePreferences／coordinator，
只在 service／Request 原生调用、BootGuard IO 和 tray／DNS／proxy／窗口／Core／进程出口注入叶子。
可为 SystemAction 提供受保护的 service、Request 依赖入口，使用实际 Request.scoped 与 BootFixture。
正常提交及资格拒绝须将 requestControl 转发到既有 PolicyCoreBridge／TestApplicationInputBridge 的真实 Go registry，
只扩充测试 fault／writer 控制点，不更改或复制 production admission；不以总成功 mock 或覆盖整个 cleanup 验收。

| 场景 | 独立预期 |
| --- | --- |
| prepare、detach 分别失败及同时失败 | 纯控制异常且资格有效时成功保存；其它收尾仍尝试，原 error／stack 和多个失败事实保留。 |
| 正常退出／needSave=false | 正常保存真实 config；opt-out 不写 preferences；BootGuard 关闭及资源收尾仍执行。 |
| 真实 Core admission | 保存先完成 lock／beginCommit／complete，后 native detach；反序的 beginCommit 确认 request_cancelled。 |
| fault／未知写者／无 client／替换 attachment | 保存被尝试但写动作零次；ack 失败保留恢复责任，旧 client 不借新 client，独立收尾继续。 |
| 其它收尾也失败 | 各独立步骤仍被尝试，多个失败按步骤记录，不覆盖前置失败。 |
| 重复退出／前置或后置挂起 | 合并同一退出，保存和 native close 各至多一次；watchdog 与正常完成共享同一次应用 exit。 |

先用相同业务断言取得当前实现反例，再验证修订。运行覆盖的 SystemAction、Request receipt／scope、
BootGuard、Bootstrap 与 action 回归，以及 pub get、analyze／format；编译真实 Go bridge、运行新增 gate 反例与相关 host vet。
保留原失败、最终源码／命令／输出绑定。真实 Go registry 证明提交条件，平台叶子仍为受控替代，
不等于真实 Android IO／设备验收；不要求 APK、设备或重跑未变 JNI 矩阵。
