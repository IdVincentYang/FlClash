# R04 ConfigFact 镜像并发修复 Plan

任务入口：[R04](android_branch_review_issue.md#r04configfact-的版本检查与赋值可并发失序)。
输入基线为 `security/android` 的 `74d937d`。设计、实现评审及本地自验已通过。
交付目标为 `security/android` 的本地 fixup，定稿随交付提交保存；Issue 处置及任务文档清理由 M 维护。

## 问题与目标

Core 事件经 Default dispatcher 调用 `observeConfigFact`；配置应用的 prepare／install／activate／abort
及失败回执直接调用同一入口。当前比较、赋值及通知投影没有共同串行边界，`@Volatile` 只保证引用可见性。
原审查在复制字节码中插入调度 latch，展示同 epoch 的 v3→v2 回退；它不是未修改生产类的执行证据。
通知还可能在较旧投影延迟发布后覆盖新标题，或多次读取不同 fact 的字段。

目标是在 Native 镜像内保持已接受版本的顺序，使通知与 refresh 消费一致的已接受事实。
Go 配置权威、请求／业务资格、epoch 协议及 R02 exiting 契约不变；不改事件 dispatcher 或 Flutter 消费者。

## 方案与理由

由现有 `ServiceStateMachine.publicationLock` 同步执行 epoch／版本判断、镜像替换及通知发布。
所有 `applySharedState` 路径也使用同一 monitor，在锁内各取一次 request state、ConfigFact 和 SharedState
快照，生成并提交 NotificationParams；迟到的 phase／SharedState 刷新读取当时最新 fact。
`refresh` 在同一锁内检查 phase／businessActive，保留原运行时间含义。
返回给配置调用方的单个 fact 引用仍可沿既有 volatile 读取，不增加第二个镜像或 Owner。

保留现有接受规则，不把版本用于业务授权：

| 输入 | 处理 |
| --- | --- |
| 空 runtimeEpoch | 拒绝，不更新或投影 |
| 初始镜像为空且收到有效事件／回执 | 接受首个 epoch |
| 同 epoch，version 较小 | 拒绝，authoritative 也不例外 |
| 同 epoch，version 相等或较大 | 接受并投影；同版本不强制去重 |
| 不同 epoch | 只有 authoritative 回执可切换，之后拒绝原 epoch 的普通迟到事件 |

authoritative 仍仅来自现有 Go 调用回执，普通 ServiceController 事件不获此资格。
不比较随机 epoch 的大小、不新增 retired-epoch 集合或 Native 推测的进程排序。
同版本保持可更新：Go `configStateSnapshot` 会补充 route/picks 或实际业务状态，不能把 version 相等一概当作无变化。
本项不新增跨运行实例的回执资格；既有调用／token 校验及 Go 进程生命周期继续负责回执来源。

只锁写入或 CAS 不能约束迟到通知，单独串行事件也覆盖不了直接回执；复用 monitor 能同时覆盖这些路径。
现有 `transitionLock` 可以进入 publicationLock，反向不取得 transitionLock／startPreparationLock。
新增临界区不调用 Go/JNI、不等待 I/O 或 suspend，只提交现有 ServiceConfig StateFlow；
同线程的已有投影调用可重入 monitor。异常保持原传播方式，monitor 自动释放，不吞异常或新增异步队列。
比较与投影为固定大小字段处理，锁等待不扩大到 provider 下载或配置应用过程。

## 实施与验证

1. 设计通过后，先在当前 [服务契约](android_service_design.md)补充镜像接受、统一投影边界和锁顺序，
   明确为待实现增量，再修改实现与测试；实现后移除待实现标记。
   现有 architecture／guide 已链接该契约，且本项不改 UI 操作，不复制平行规则或回写历史 Loop Plan。
2. 新增 `android/tests/app/ConfigFactStateMachineTest.kt`，复用现有 host，直接运行生产状态机。
   在 host 的通知提交边界用 latch 暂停旧投影，让新事件／直接 apply 回执并发进入；
   断言最终真实 ServiceConfig StateFlow 标题、镜像版本与 refresh，稳定暴露原实现通知回退，验证修复后的顺序。
   镜像版本只读反射核对，不新增生产测试钩子或公开 getter；主要断言落在现有投影消费者。
   latch、线程和 scope 有界回收，不靠 sleep、概率压力或改写生产类作为唯一 oracle。
   原复制字节码证据单独保留，不宣称它证明了原生产类的测试覆盖。
3. 矩阵覆盖同 epoch 的旧／新／重复与同版本更新、空 epoch、初始接受、authoritative 新 epoch 切换及旧 epoch
   迟到；覆盖真实 apply 调用与事件交错、SharedState／phase 重新投影、refresh 的 active／inactive，
   以及通知提交异常后继续接受与同线程重入。直接回执不通过公开事件入口伪装为 authoritative。
4. 先在未改生产基线上运行可兼容反例，再修改后运行专项；回归既有 ConfigApply、ServiceState、Pause、Exit、
   ServicePluginRequestControl 与 RunIntentArbiter suites，守住 R02 的 token／退出行为。
   使用已有 JDK 17、ARM64 配置及共享 Gradle cache，执行 app Kotlin 编译与 host JVM 测试；
   Flutter 依赖／analyze 结果按未变输入复用，不默认重跑全量 Flutter 或构建 APK。

本地、未入库的新证据放在 `.buildlog/r04-config-fact-20261116/`，按原实现／修复后分别绑定源快照、命令和结果，
不覆盖 R02／R03 或原审查日志。host JVM 能证明状态机及 StateFlow 投影，不证明 JNI 事件时序、
Android 通知显示或设备 VPN；本项不操作设备、APK、Issue、R05、main 或远端。

## 实际验证

未修改生产代码时，新专项 12 例中 5 通过、7 失败：6 项显示较旧通知覆盖新投影，
1 项显示 refresh 未等待正在提交的事实。与原复制字节码中的镜像版本回退分开报告，
不把新的通知反例说成直接复现了比较／赋值之间的插入点。

相同专项在修复后 12 通过；8 组关联 JVM 回归共 112 通过、0 失败／错误／跳过，
包含 R02 全部 96 例及 ServiceConfig 的 4 例。ARM64 配置的 app Kotlin 编译通过。
等待断言同时核对 monitor 身份、持有线程及生产方法栈，超时和未调度不计作成功；
实际 StateFlow collector 验证同线程重入，所有测试线程与 scope 有界回收。

证据为上述本地目录中的 `before-02-summary.json`、`after-01-summary.json`、
`after-regression-results.json` 及对应日志／XML；原反例日志及设计副本保持冻结。
本项未修改 Dart／依赖／分析配置，复用 R03 已通过的依赖与 analyze 结果，不重复全量 Flutter。
当前文档 lint、diff 与 comment-density 检查通过；此结论仍限 host JVM／StateFlow／Kotlin 编译。
