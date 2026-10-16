# L2-T01 验证与交付记录

2026-10-16，Codex（M）已通过完整实现评审，I1–I8 均闭合。D-02 正按既有授权收尾、提交并本地集成；远端由 M 核对后普通推送。沿用已通过的[任务设计](l2_t01_plan.md)及控制器补充，其它 L2 任务未启动，L1-T04 继续暂缓。

## 本轮修订与实际观察

| 问题 | 修订后消费者与结果 |
| --- | --- |
| I1 固定转发 | `tunnels` TCP/UDP 由包装层按候选业务范围 checked 绑定。真实固定入口正常到达目标各 1 次；旧接受/包跨新激活后目标各 0。占用任一必要端口使安装失败并清理部分入口，stop 和 inactive 安装后两种端口均可重新绑定。合法代理名 `node/a` 的 TCP/UDP 正向、stop、replace、部分安装失败清理及重试均通过；key 按最多三段无损解析 |
| I2 热参数与选组 | 已接受参数保留在当前配置累计值中；候选失效重新捕获实际选组。实际 mode/IPv6 热更新卡在 manifest 写入时并发选择 REJECT，两项成功后真实重放保持 Rule、IPv6 和 REJECT；原 Direct 正向请求 1，重放后目标 0 |
| I3 旧启动清理 | 先前登记前失败、Geo 来源撤销及有效继任用例保持通过。本轮真实 Dart→JVM 桥接新增无效回调入队、入队后才失效、无效任务之后/检查期间又来有效继任、登记前取消的收尾；无有效接管时原准备最终 failed/intentRunning=false 并可新 start，有效接管时不增加物理停止 |
| I4 本地来源 | 真实 Drift/生产 notifier 覆盖全局和局部规则增删改、节点/组编辑删除、overwrite/script 选择；旧票据失效。生产 SetupAction 清掉缓存旧 SetupState，在提交锁内读已提交数据并取得票据。Go 对 global-rules/profile 撤销后拒绝旧冷恢复，新完整应用恢复资格；不伪造仍在运行的旧业务已停止。页面“使用默认”调用正式 ProfilesAction：一次读取原始配置，提交段核对原票据、撤销 profile 来源并批量替换；新快照得到真实 nodes/groups/rules，采样期间来源变更则拒绝旧重置 |
| I5 TCP 半关闭 | 真实 mixed HTTP CONNECT 的客户端发送后 CloseWrite，目标读到 EOF 后返回完整响应；撤销同类旧连接后迟到响应交付 0。保护包装保持检查，不暴露绕过发送检查的解包/复制快路径 |
| I6 无效选组 | 真实 HTTP PUT 的空对象、空名称、null 均返回 400；手动 REJECT、事实版本、route/picks 及 checkpoint 引用不变。合法选组与自动组显式清除保持原契约 |
| I7 通知 | 实际 JVM 状态机进入 started 后，仅 phase 变化即将 Applying 刷为实际 Applied，无额外 SharedState/流量事件；服务丢失后标题和运行时间失效 |
| I8 冷启动读取失败 | SharedState 缺失及读取抛错两种情况均进入 failed、intentRunning=false、运行时间 0，不启动物理服务；修正读取后新 start 成功 |

当前实际身份展示入口为仪表盘配置详情和 Android 通知。没有宣称全部配置/代理页面均已更新。输入身份、失败分层、来源及清理契约详见设计，任务归属与进度由[任务清单](loop2_tasks.md#l2-t01-最终配置与应用失败时的业务出口)维护。

## 验证范围与结果

Go 消费者运行真实生产配置、监听及路由，所有目标均为合成 loopback TCP/UDP/HTTP。Dart 桥接运行实际 SetupAction、CoreController、CoreLib、Service 与 JVM ServiceStateMachine；Core 及 Android OS/物理服务由受控 host 替代。该桥接未运行真实 JNI、VPN FD 或 Android MethodChannel 引擎。

| 本轮检查 | 结果与本地证据 |
| --- | --- |
| 已通过的 Go 全套 | 沿用第三轮 `CGO_ENABLED=0 go -C core test .` [通过](../../../../build/verification/l2-t01/revision3/go_all.log) |
| 已通过的窄竞态与固定转发 | 第三轮普通固定范围/绑定、profile 冷恢复撤销共 3 项独立 `-race` 通过，见[摘要](../../../../build/verification/l2-t01/revision3/verification_summary.json)；新增斜线名称的完整真实消费者 [非竞态通过](../../../../build/verification/l2-t01/revision3/go_slash_lifecycle_final.log)，race 结果见下节 |
| Dart 受影响回归 | 本轮 [165 项通过](../../../../build/verification/l2-t01/revision4/flutter_final.log)，含扩展后的真实状态机桥接；[命令与环境](../../../../build/verification/l2-t01/revision4/flutter_command.json)已设置，无 skip。第三轮 292 项中的未变数据库/迁移与来源消费者证据复用 |
| Android JVM | 沿用第三轮 [131 项通过](../../../../build/verification/l2-t01/revision3/jvm_final2.log)，失败/错误/跳过均 0；app/service/common 分别 78/23/30，见[计数](../../../../build/verification/l2-t01/revision3/jvm_test_counts.json) |
| 工程检查 | 正常[生成](../../../../build/verification/l2-t01/revision4/codegen.log)、[格式](../../../../build/verification/l2-t01/revision4/format.log)及锁定依赖解析通过；789 文件格式无变化；[分析](../../../../build/verification/l2-t01/revision4/analyze.log)无错误/警告，保留 42 条既有测试 info |
| ARM64 与来源恢复 | 本轮 [release 构建](../../../../build/verification/l2-t01/revision4/android_arm64_build.log)通过，构建输入前后完全一致。Core/载体与[已审独立恢复](../../../../build/verification/l2-t01/revision3/independent_recovery.json)未变，直接承接；见[当前输入/缓存/输出核对](../../../../build/verification/l2-t01/revision4/delivery_checks.json) |

I2、I5–I8 已获第二轮 M 通过，I1/I4 已获第三轮 M 通过，其语义未重开；其中 Go 热状态/半关闭/控制器及业务范围 race 继续引用第二轮受审证据。未修改的 setup hook/cache/恢复工具 24 个输入与首轮一致，复用首轮 [43 项 hook 测试](../../../../build/verification/l2-t01/implementation/build_hooks_tests.log)，不称为本轮重跑。其它未受影响平台继续保留原验证边界。

I3 本轮保留原收尾责任，沿同一 setup 队列等继任处理后按原 request/token 兑现；登记的新 token 会拒绝旧清理。generation 变化后不把队列位置当作已接管，队列后续增加任务时先让其执行。桥接分别观察无效回调最终清理，以及有效同 run/较晚有效继任完成、stops 不增加；没有移除来源回调。完整契约见[设计](l2_t01_plan.md#失败完成契约)。

### 失败与修复记录

- 第二轮原控制器组合用例的功能断言通过，但 `-race` 再次捕获未改的 `log.SetLevel` 与 GC adapter finalizer `log.print` 竞态，[原始失败](../../../../build/verification/l2-t01/revision2/TestConfigControllerWritesUseAcceptedAuthority.log)保留。I6 的独立实际 HTTP [用例通过](../../../../build/verification/l2-t01/revision2/TestConfigControllerRejectsEmptyManualPick_final.log)，不能据此声明组合用例或全仓 race 干净。首轮 invalid-rule 同类日志竞态及自动测延队列观察继续保留，不顺带重写上游日志/轮询。
- 新测试夹具曾重复初始化全局字段，断言代码曾有可比较性/HTTP 包适配及 nullable 编译错误，均已修复，初始日志保留于 revision2。现有 SetupState 释放回归还发现等待 DB 后访问失效 ref，已将依赖读取提前，夹具改为实际已提交 profile；保留[失败](../../../../build/verification/l2-t01/revision2/flutter_source_consumers.log)和上述最终通过输出。

- 第三轮新增斜线固定转发的 race 运行也捕获上述既有日志/GC 竞争，功能断言与 Go 全套/独立非竞态均通过，[原始 race 输出](../../../../build/verification/l2-t01/revision3/go_slash_lifecycle_race2.log)保留。初次该夹具遗漏候选 marker，与已启用的输入 GC 交错；已按生产候选方式保护，未修改 GC/日志实现。
- 第三轮第一次打包期间补充分离了 setup generation 与可选来源校验，构建输入比对发现仅 setup.dart 改变，[拒绝绑定记录](../../../../build/verification/l2-t01/revision3/superseded-build/binding_rejection.json)与日志保留，那个包不交付。随后正常生成、292 项回归与分析重跑，最终构建前后输入一致。

## 源码与制品绑定

父基线为 `6c0dbde0aedb9f4fedde3fad9fa0ccbc0a1ff586`，任务分支 `security/l2-t01-config-apply`，目标 `security/android`。获审父 tree、补丁 SHA 与源码对应见[评审绑定](../../../../build/verification/l2-t01/revision4/review_binding.json)。构建后只更新文档与本地证据，运行输入无变化。

| 对象 | 本轮绑定 |
| --- | --- |
| 累积 Core | commit `6c6e3e472bb246cc55f2e8577d9eddccc2623afc`，tree `f08a2ac1a2cd78649b4a144e4c3fb16318f96887`；唯一父为公开 `8597778c7df410ebe88c57e59eaab32d203156df` |
| 恢复材料 | [载体](../../../../core/patches/l1_t03/manifest.json)覆盖 T03 与本项全部源码差异，patch SHA-256 `ac046f82c5c9d719bbad7c4958f7eabe0573f7b769536a93e76e5900a71a181e`；独立基线库不含 2b8c0e2、7adf5fc、f11d33c 或本轮候选，恢复精确 commit/tree 后 check 通过 |
| ARM64 APK | [本地 dev APK](../../../../build/verification/l2-t01/revision4-artifacts/FlClash-0.8.99-android-arm64-v8a.apk)，`com.follow.clash.dev`，`0.8.99` / `2026102301`，Android Debug 签名；SHA-256 `76c243aa8cb219fb163f9581dbc21625b3989afd7c6b2990e0c2b245ce381652` |
| 符号与 mapping | 未剥离 Go/JNI 库及 R8 mapping 在同一制品目录；两库均有 debug_info/debug_line，Build ID 与 APK 相应库一致，详见[制品核对](../../../../build/verification/l2-t01/revision4/artifact_inspection.json) |

Flutter 3.47.4 / Dart 3.13.3、Go 1.26.4、Rust 1.98.1、Gradle 9.8.0；JVM 测试和 Gradle daemon 使用 JDK 17，Flutter 的 Gradle launcher 使用 Android Studio JBR 25.0.3。Go Native Assets 使用 NDK 29.0.14206865，JNI 沿用 NDK 28.2.13676358。最终构建 setup/Rust assets 均启用，当前固定转发源码及载体进入依赖，Go 输出与 JNI 复制一致，quickSetup 导出不存在。本轮仅有 setup.dart 及其正常生成 hash 两个运行输入变化；Core、Android/harness 和构建工具与第三轮一致，两份 native 库与已审制品完全相同，独立恢复/Go/JVM 证据复用。

### 历史受审对象

首轮父 tree `5af50195ea211d91decf00dc115b117cab66f1db`、Core `7adf5fc9983b42ca237b83bbe8177cb3cae61027` 和 APK SHA-256 `0d6af85426517c6fbf213b5662e77f3e306d159e23336efdb22b2a951e6e3673` 已由 M 核对一致，行为评审未通过。其 [161 项 Dart /129 项 JVM 等证据](../../../../build/verification/l2-t01/implementation/verification_summary.json)与原 implementation/artifacts 目录继续保留，不能作为本轮新运行输入的 ARM64 证明。

第二轮父 tree `f72fae75356b79a88c179ef96c24f1504a983974`、Core `f11d33c54d809b6d50968e7d0d40dff0decb89f0` 及 APK SHA-256 `102ccca685595dbf85499d99f5d20a96b07c4a54b4d0e261f8fe45f4afc0a4e1` 的绑定已获 M 核对；I2、I5–I8 通过，其 I1/I3/I4 剩余问题由后续修订处理。原 [revision2 摘要](../../../../build/verification/l2-t01/revision2/verification_summary.json)及制品保持原样。

## 收尾与本地集成

M 通过的父候选 tree 为 `47a2474bbe83e0df414e9e67699b9fd544d17a87`。提交前结构检查覆盖输入、Go 安装/恢复、原生服务所有权、Dart 调度及只读显示边界，未发现达到仓库 skill 门槛的结构性问题，保持获审代码不变。当前只对账文档状态；实际提交、目标推进、清理和第四轮产物等价性由[本地交付记录](../../../../build/verification/l2-t01/final/local_delivery.json)维护。

## 复现与未覆盖范围

- 随源夹具为 `core/config_apply_test.go`、`core/config_review_test.go`、`core/config_udp_test.go`、核心 `tunnel/business_test.go`，以及 Android 配置状态机、Dart 配置桥接和来源测试。本轮命令和输出见[验证摘要](../../../../build/verification/l2-t01/revision4/verification_summary.json)及[命令](../../../../build/verification/l2-t01/revision4/verification_commands.json)。
- 桥接先运行本地 Gradle classpath 任务编译实际状态机，再按 `flutter_command.json` 设置 Java/classpath。ARM64 可沿[构建指南](../../../development/android_build_guide.md)与保留的 `build/verification/l1-t03/android_command.sh build` 复现；新 checkout 需恢复 Core 并配置同版工具/依赖。本地缓存绝对路径不能视为可搬运工程。
- 原始脚本、日志、APK、未剥离库、mapping、独立恢复 checkout 均在忽略目录 `build/verification/l2-t01/`，未上传。没有安装或启动应用/设备/模拟器、操作宿主 TUN/系统代理，也没有真实订阅/凭据或外部测试目标。
- 真实 JNI/FD、Android 权限/Always-on/撤销/系统回调和设备出口仍未验证；本项证明列出的本地消费者和受控状态机，不承诺全设备 kill switch，不能收回撤销前已交给系统的有限动作。
- 旧安装没有可核验 checkpoint 时，后台首次启动需在 Flutter 前台重建输入，本项不提供无感迁移。来源身份/跳转仍受暂缓的 L1-T04 限制，本地内容身份与出口检查不证明远程来源可信。
