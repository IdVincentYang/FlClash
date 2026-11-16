# R09 JNI failure isolation Plan

任务入口：[Android branch review Issue](android_branch_review_issue.md) R09。
基线 `57f85cf`；设计与实现复审通过，I1／I2／Q1／Q2 已闭合；按约定交付 security/android 本地 fixup。

修订保持既有 owner 契约：程序化 stop／stopOwned 的未确认清理须传到 Controller／machine，
不能 clearBinding、清零 runtime 或报告 cleaned；onDestroy／onRevoke 才捕获并记录失败，start catch 保留原错误。
已有 TUN 的公开 requestIdentity 在 native adopt 确认前保持旧值，Controller 在失败时也保存服务实际保留的身份；
新 attempt 身份不匹配时只能报告 cleanupFailed，不能绕过 owner 检查，原 binding 仍可按原身份收尾。
回归入口将从指定 Git revision 物化完整旧 Core 源集，独立于 index／working tree；
在隔离仓库验证未暂存、已暂存和干净提交三种状态，不提前提交共享分枝。

Q2 沿用意图与资源 owner 分离：系统 start 仅产生新 intent，不调用 bindService 提前改写
machine 的 serviceRequestId。已有 owner 保留到 runConfigApply 按完整旧身份清理，
Controller 实际 attach／start 时才进入既有 bind 流程。
compatible 继续要求同一 request owner 和 options fingerprint；系统新 intent 不冒用旧 owner 复用资格。
验证实际 onStartCommand → handler → machine → config → Controller／service，
覆盖旧 TUN 正常替换、同 intent compatible、cold start 和迟到旧清理。

## 问题与目标

四个新增 [Go exports](../../../core/lib.go) 直接由
[JNI](../../../android/core/src/main/cpp/core.cpp) 调用，没有 recovery。
已确认内部不变量故障可逃逸，尚未证明外部输入可触发。
目标是隔离同 goroutine 的 Go panic、返回真实失败，并保证锁、字符串、GlobalRef 和 TUN 身份可解释；
不扩入原有 `startTUN`、R10/R11、F01 或 Core carrier。

仅在 export 外层 recover 不足：`requestControl` 的可达临界区存在手动 Unlock，
callback 替换涉及 GlobalRef 转移，TUN Close 不可回滚；Kotlin 还可能先发布身份、先清空停止状态。
不采用“恢复后继续当作正常运行”的方案。

## 方案与理由

各 export 直接设置 deferred recovery；可达的 FlClash 自有临界区先发布失败 veto，再 unwind 解锁，
最外层才转换结果。沿现有锁顺序改为局部 defer，不在 recovery 猜测／强制解锁。
新增一个进程寿命的 atomic fault 位，不复用未知写者计数：panic 可能已部分修改资格或 receipt，
无法证明安全回滚。它接入现有资格／writer 检查和 `businessAllowed`，拒绝新请求、授信、ConfigInput 和 TUN start；
旧 lease／BusinessScope 也不能继续获得网络／提交资格。attach、Init、Service 重建不能复位。
保留 cancel、endRead、releaseCompletion、complete、detach、block／flush 及身份匹配的停止清理；
它们仍校验原 owner，不清空未知写者或未完成 receipt，不新增自动重试／恢复调度。

| Export | 结果与所有权 |
| --- | --- |
| `requestControl` | panic 返回现有 JSON `error: request_restart_required`；部分写入不伪装回滚或成功。审计 control 及其可达 helper 的锁与临时持有，现有清理只释放自己的资源。 |
| `setRequestSocketListener` | write lock 排空旧 reader，串行完成旧引用脱离／释放及新引用发布；defer 只释放本调用仍拥有的引用。失败保持无可用 callback，不能由迟到清理删除后来注册的引用；`null` 注销仍合法。 |
| `setTunRequestIdentity` | 持 `tunLock → handler.mu` 更新整个身份对；panic 在解锁前恢复捕获对象的旧身份，不触碰替换后的对象。无 handler 是显式失败，不能假成功。 |
| `stopTunRequest` | 正常区分匹配停止与身份不匹配；先隔离捕获对象的 hook／callback，再 Close。Close 未确认时保留资源所有者、禁止新 start；已释放的 callback 不重复释放，不把不确定关闭当作 stopped。 |

输入 C string 仍由 Go 消费并释放一次，输出 C string 仍由 JNI scoped cleanup 释放；
本地 GlobalRef 在发布前归当前调用，发布后归注册对象。
Close 失败保留的对象不参与新工作，后续清理只能按捕获身份处理；若依赖内部锁已损坏，不承诺重试可修复，需结束进程。

保持 Kotlin external 签名与 JSON envelope。两个 void setter 的私有 C ABI 改为 status，
stop 的私有 C ABI 用 `1/0/-1` 区分 stopped／不匹配／失败；负值由 JNI 返回前抛出稳定的 Java exception，
不携带原始 panic 内容，不经过 Kotlin callback，也不改变 callback exception 清理规则。
生成 header 与 JNI 同步，不手改生成文件。

真实消费者同步：Application 的 observer 注册捕获失败，仍能进入已有错误处理而非初始化崩溃；
`VpnService.attachRequest` 在 Go 确认后才发布 Kotlin TUN 身份，失败不报 ready；
停止仅在确认后清空对应身份／发布 none，异常保留失败或 retiring，旧调用不撤销新身份；
错误须在实际消费者处理，不逃逸 Android 初始化／生命周期 callback 再次终止应用。
`ServicePlugin`、`ServiceStateHost` 与 Dart 继续消费 error／exception，不能把错误 JSON 当作成功。
不修改 Dashboard 或增加第二个 service 状态权威。

## 实施与验证

1. 设计通过后，先在 [来源契约](source_acceptance_design.md) 补 JNI 失败／进程恢复边界，
   [.agents architecture](../../../.agents/architecture.md) 仅补接入与链接；
   [.agents rules](../../../.agents/rules.md) 只澄清主动返回 Java exception 与 callback exception 清理的区别。
   再实施 Go／JNI／Kotlin 及回归，最后按实测回填证据；Issue 和完成 Plan 清理由 M 负责。
2. 在隔离子进程通过实际 Kotlin `Core` declarations → 生产 C++ JNI → 四个生产 Go exports 注入故障，
   覆盖入口、持锁、修改后及释放前后；原版相同故障须暴露缺边界，修复版须存活并得到规定错误。
   host CGO/JVM harness 仅用带哈希 overlay 适配 Android build selector、TUN／UID 系统叶子和注入点，
   不复制 export／recovery／锁／状态实现。记录字符串／GlobalRef 的取得、转移、释放，核一次释放；
   不在 free／DeleteGlobalRef 内假设“已释放还是未释放”的模糊 panic。
3. 独立预期覆盖：panic 后锁可取得、cleanup 可结束、新业务明确 request_restart_required、新进程健康路径正常；
   callback reader／replacement 交错、错误 service／generation、身份更新失败与 Close 部分失败均不得影响新 owner。
   Kotlin consumer 窄测另核初始化、ready／none 及 MethodChannel／Dart 错误处理，不以 handler 测试替代 JNI 边界。
4. host Go root／`no_zerotier` 回归与 vet，受影响的 Flutter Request／协议测试及 analyze；
   JDK 17 编译受影响 Android 模块，ARM64 NDK 以实际 Android tags（含 `no_zerotier`）构建 fresh c-shared／header，
   编译链接生产 JNI，核 status ABI。必要的并发窄测记录 overlay 差异，不把既有 F01 算作已解决。

host JVM 验证 JNI 调用与内存所有权，Android 编译验证真实平台布局；均不替代 ART、真实 TUN、APK 或设备验证。
C／ART abort、runtime fatal、OOM 和异步 goroutine 的 panic 不属于这四个同步 recovery 的保证。
语言依据：[Go panic/recover](https://go.dev/ref/spec#Handling_panics)、
[JNI exception handling](https://docs.oracle.com/en/java/javase/17/docs/specs/jni/design.html#exceptions-and-error-codes)。
实现与验证结果见 [R09 Result](r09_jni_failure_result.md)；未进行 APK／ART／设备验证。
