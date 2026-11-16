# R09 JNI failure isolation Result

对象为 `security/android`、`57f85cf` 之上的 R09 实现；I1／I2／Q1／Q2 实现复审通过。
最终交付对象由本地 fixup 与交接记录绑定。
四个新增 export 的同步 panic 返回真实错误，并保留进程 fault veto 与 owner 清理边界；
长期契约见[JNI 同步失败边界](source_acceptance_design.md#jni-同步失败边界)，任务范围见
[Plan](r09_jni_failure_plan.md)。未修改 Core carrier、原 startTUN recovery、F01 或后续任务。

## 已验证

| 配置／对象 | 结果与计数口径 |
| --- | --- |
| host JVM → 生产 JNI C++ → 四个 Go exports | 修复版 19 个独立进程场景通过；原基线四个 export 在对应受控故障下均以 SIGABRT 终止，有 Go panic 记录。 |
| Kotlin 实际消费者及生命周期回归 | 修订后 JDK 17 编译通过；8 个选定测试类共 127 tests，0 failure／error／skip；RequestNativeFailureTest 共 23 项，含此前 18 项与新增 5 项系统启动消费链。 |
| Go root | 444 个顶层 test 通过；含 subtest 的 683 pass events、40 skip。 |
| Go `no_zerotier` | 455 个顶层 test 通过；含 subtest 的 706 pass events、40 skip。两种配置的标准 vet 均通过。 |
| 定向 host race | 3 个 test 通过；仅移除既有 ipc 测试 helper 的 `!cgo` selector，无生产 overlay。 |
| Android ARM64／NDK 28.2 | `with_gvisor,no_zerotier` fresh c-shared／header 生成、生产文件 vet 及生产 JNI 编译链接通过。 |
| Flutter 相关 Request／协议／CoreLib | 6 个文件，67 pass、1 skip；pub get offline 与 analyze 通过，保留既有 42 条 info。 |

JNI 独立预期包括：持锁失败的 veto 先于解锁可见，已排队的 ready／配置注册被拒；部分版本修改后不恢复资格；
GlobalRef 及输入／输出字符串没有重复释放或 test-owned 残留；reader 排空后才替换 callback；
身份对失败回滚，foreign／stale setter 与旧停止请求不影响当前 owner；
Close panic 或普通错误未确认停止时保留所有者，匹配清理仍可结束；真实 receipt 完成只释放自己的未知写者，
不清除 fault 或耐久 recovery marker。
Kotlin 另验证注册异常不逃逸、native 确认前不发布接管身份、正常停止／不匹配／异常，以及启动 catch 保留原失败。

复现 JNI 矩阵见[测试入口](../../../android/tests/jni/README.md)。
本地、未入库的冻结证据位于 `.buildlog/r09-jni-failure-20261116/implementation/`：
`jni-final-03/`、`jni-before-final-02/`、`android-final/`、`native-arm64-final-02/`、
`go-*-final-02.log`、`race-final/` 与 `flutter-*.log`；对象、配置、命令及哈希由交评 source manifest 绑定。

## 偏差与限制

首轮 I1／Q1 已确认：native 停止失败虽然未发 none，stopOwned 仍可让 Controller／machine 误报清理完成；
失败 adopt 还会提前改变公开 requestIdentity，使其与 retained native owner／binding 不一致。
原 84 项 Kotlin 结果没有证明这两条上层收尾链正确。修订前 13 项测试有 6 个业务失败，
包括实际 Controller／machine 把未确认停止报告为 cleaned、destroyed 误报成功、公开／binding 身份不一致；
相同断言在修订后通过，并新增 revoke 及 Go 确认后、Kotlin 发布前销毁的 owner 验证。
ServiceState façade 在测试中只把 bind 调到新建的真实 machine；Controller、binding、VpnService 和 machine 收尾均运行生产实现。
未确认停止现在保留 binding／runtime，程序化 stop 报错、stopOwned 返回 false，系统 callback 捕获失败；
失败 adopt 保持旧实际身份，确认后失败保留新实际身份，Controller 的 finally 保存该身份。
系统 start 不重标已有 owner，完整 restart 在旧 TUN 未确认清理时拒绝建立替代 TUN。
新 attempt 无权清旧 owner 时明确 cleanupFailed；按原 binding 身份可继续清理，迟到旧清理不能撤销新 owner。

Q2 复审核实：onStartCommand 不重标 service 身份后，handleVpnStartRequest 仍提前 bind 新 intent，
使 machine 的 serviceRequestId 与已有 native／binding owner 不同，正常替换也可能 cleanupFailed。
revision-02 的 system start 测试只使用 handler stub，尚未证明这条真实消费链。
本次移除系统 intent 的提前 bind，沿用 Controller 实际 attach／start 时的 bind 和完整身份清理。
内部 handleVpnStartRequest 不再接收 serviceId；跨模块 observer 签名不变，回调本身不授予 service owner。
暂停、退出或 publication 失败仍返回 0 且不 dispatch；原 ServiceExit 回归同步 intent-only 预期。
同 intent／同 options 的 apply 保留实际 binding；系统新 intent 即使 options 相同也必须完成旧 owner 清理及新 start，
不能冒用旧 owner 进入 compatible 分支。配置变化的系统 start 同样能正常替换。
受阻系统 start 被更新 intent 超越后不能认领后者的 service；迟到旧清理和旧 service.onDestroy 不撤销新 owner。

新增真实消费链覆盖 onStartCommand → 转发 handler → handleVpnStartRequest → replay／applyConfig →
ServiceController → ManagedServiceBinding → VpnService，使用实际 ready／retiring／none 回调与身份检查。
Core 的 TUN 结果、Application bind/unbind、Builder／fd 及 notification／network observer 为受控系统叶子；
config receipt 仍使用既有 ConfigServiceTestHost，不冒充实际 Core 配置执行或 Android framework 调度。
补齐 host Builder 的地址／route 叶子后，修订前 22 项有 3 个业务失败：
配置变化时替换失败、同 options 新 intent 错借 compatible、cold start 多余清理；同 intent 复用已通过。
相同断言修订后通过，另加 superseded system intent 回归。
最终 8 类 127 项包含 ConfigApply 与 ServiceExit，证据为本地未入库
`.buildlog/r09-jni-failure-20261116/revision-03/` 的 `kotlin-before-03/` 与 `kotlin-final-01/`。
此前两次 host 叶子失败及一次旧调用方签名编译失败均保留；编译失败没有运行测试，不使用旧 XML。
revision-02 源码与证据冻结；本轮 Go／JNI／runner／carrier 未变，沿用此前有效矩阵。

I2 原入口依赖未暂存 diff。修订后从指定 revision 物化完整旧 Core，
隔离仓库的未暂存、已暂存、干净提交三种状态各运行四个原版终止反例，12/12 符合预期，
三次 raw baseline source 哈希相同，新增 Go 文件均未进入旧源集；共享分枝／index／Core 未改动。
新版 runner 的 after 模式另跑 19 个 JNI 场景通过。
修订证据为本地、未入库 `.buildlog/r09-jni-failure-20261116/revision-02/`，
入口 `kotlin-before-04/`、`kotlin-final-04/`、`runner-isolation/result.json`、`jni-after/`。
此前 Kotlin 夹具编译失败保留；`kotlin-before-03` 的旧 XML 已标为非该次运行证据，不用于验收。
Go／C++／JNI／协议代码和相关测试未变，复用原 Go、native、Flutter 与 race 结果，不扩大验证范围。

标准 Android package vet 在当前实现和 `57f85cf` 均因 CGO 排除既有 `captureFrames` helper 而失败。
`-tests=false` 只关闭 analyzer，不能排除测试包编译；最终 native vet 使用 `go list` 实际选中的生产文件，
不能声称标准 Android package vet 已通过。基线对照保存在 `baseline-native-vet/`。

早期 Kotlin 失败来自 host Builder／FileDescriptor 叶子及重复 Core shadow 夹具；
补齐最小叶子并共用现有 Core shadow 后通过，未调整业务断言或生产 fd 行为。
对应失败 XML／日志仍保留；第一次 Go compile 的 scope 局部变量声明错误也已修正，原失败保留。

host JNI 使用带哈希 overlay 适配 build selector、TUN／UID／fd-pressure／DNS 系统叶子及 fault point；
GOOS／平台 feature 常量仍为 darwin。`-Xcheck:jni` 有 Go／JVM signal handler 共存警告，
不据此宣称 signal handling 已验证。TUN Close 使用受控幂等叶子，不证明任意依赖 Close panic 可重试。
未执行完整 Flutter、完整 stock race、APK、ART、真实 TUN 或设备验证；F01 仍未修复。
这些验证证明同步边界和错误／所有权契约，不证明外部输入能触发原故障，也不覆盖 native fatal／OOM／异步 panic。
