# L1-T06 订阅刷新与失败处理验证记录

implementation_v2 已通过 M1 实现评审，I1–I4 全部关闭；本项已本地合入 `security/android`，任务结束，未推送。
提交前仅同步三份 Markdown 的阶段/历史表述和格式，生产源码、测试、生成物及集成基线与获审版本等价。
最终 Git 版本、等价核对及清理结果见[本地交付绑定](../../../../build/verification/l1-t06/delivery/binding.json)。
implementation_v1 的自验不能覆盖本轮新增反例，且 v1 已被 M1 判为未通过；
原[冻结结果](../../../../build/verification/l1-t06/implementation_v1/snapshot/docs/features/security/loop1/l1_t06_result.md)和绑定保留，不回写为通过。
任务、授权和暂缓范围见[任务入口](loop1_tasks.md#l1-t06-修改订阅刷新与失败处理)，
契约及取舍沿用已通过的 [design_v2](l1_t06_plan.md)。本记录描述实际结果，不将设计通过视为实现通过。

## implementation_v2 修订与反例

| 必修项 | 修订及实际观察 |
| --- | --- |
| I1 清理失败的恢复门 | 条件清理的首次 cleanupFailed/异常保留既有持久恢复标记和内存恢复门，不用 dataset 撤销扩大清理，也不重试覆盖第一次未知。真实 JVM 生产 ServiceStateMachine 消费者覆盖 stopOwnedService 返回 false/抛错、其后自身状态改变的 superseded、较新 Owner 以及自动后继零发送；包含材料已保存和 DB 拒绝。保存成功但清理未知返回独立的固定结果，重接客户端仍读到恢复门 |
| I2 内部补文件重复应用 | 内部材料成功后由所属 Setup 继续，取消额外成功 apply。真实 Core 用例在 S1 补文件后 hold 构建，再放行；S1 返回成功、一次 register/install，MD5/groups/providers 完成同步。跨 ID 成功/失败、过期需求及有限提交销毁仍通过 |
| I3 手动优先级 | 调度次序为内部必要材料、普通手动、普通自动；不抢占已经执行的其它 ID。三个 ID 的实际 HTTP 顺序覆盖自动 C 提升和新手动 C 入队，均为 A→C→自动 B |
| I4 关闭中的旧下载误合并 | 在途合并同时要求 session 仍活跃，沿用现有关闭/取消状态及来源登记快照。真实超限下载已关闭、临时文件删除被 hold 时再手动刷新：旧等待者保留超限失败，新操作独立请求并成功，不移交旧许可或字节 |

I1 的 JVM 夹具使用真实生产条件清理状态机，Core 与 OS 资源由受控 host 提供；
HTTP 使用测试 Request 直接访问 loopback，不能据此声称完整 Android 请求权限/JNI/设备链路通过。
对应新增入口为[清理桥接](../../../../test/providers/profile_refresh_cleanup_bridge_test.dart)、
[材料及应用桥接](../../../../test/providers/profile_refresh_bridge_test.dart)和[协调器反例](../../../../test/providers/profile_refresh_test.dart)。

## 实际可观察变化

| 用户场景 | 本轮观察 |
| --- | --- |
| 自动任务排队后删除、关闭、改周期、改 URL 或改成本地文件 | 请求登记前重验当前数据库和来源，过期项不发请求，删除项不被刷新恢复 |
| 重复刷新、自动与手动重叠、提交期间再次编辑刷新 | 兼容任务合并；手动后继独立保留，更新的第三次操作可取代旧等待者；同 ID 材料不并行 |
| 多次唤醒、下载失败或系统时钟跳变 | 自动尝试受单调时间间隔和退避约束；失败等待为 1/2/4/8/16/20 分钟封顶，手动操作仍受原出口许可约束 |
| 下载过慢、过大、断流或正文无效 | 总 HTTP 预算 90 秒、实际解压写入上限 16 MiB；取消和释放所属资源、清理临时文件，保留旧材料 |
| 正文有效但统计头损坏或重复 | 有限解析可选统计，坏统计不阻断有效正文；已有订阅的名称和设置不被响应头改写 |
| 材料已保存，但应用失败、被取代或列表发布失败 | 保存与应用结果分别返回；材料持久化不因发布失败而只回滚文件；真实运行状态继续由 ConfigState 表达 |
| 配置应用等待缺文件，同时另一个订阅保存或失败 | 材料完成先释放 worker，内部需求可继续；旧需求被新 Setup 取代时及时结束，无跨 ID 互等 |
| 非当前订阅被刷新 | 只依据已接受配置的实际来源依赖决定重建；standard/script 休眠引用不重建，受管配置保持已选 policy |

已有订阅仍在订阅列表手动刷新，编辑页维护自动开关和正整数分钟周期；
历史非正周期运行时按一天处理，不静默改写数据库。保存后需要提示时使用固定文案，
不把 Owner、票据或原始异常加入用户操作流程。

## 验证范围与结果

| 检查 | 实际结果与口径 |
| --- | --- |
| 锁定依赖、本地化及代码生成 | pub get、四种语言 intl 生成、正常 build_runner 均完成；锁文件未变 |
| 格式与分析 | 727 个 Dart 文件格式检查通过；分析 0 error、0 warning，保留 42 条既有 test info |
| Flutter 受影响矩阵 | **419 通过、0 失败、0 跳过**；machine 输出中非 hidden 的 testDone 计数，非根目录全量测试 |
| 当前刷新协调与真实 Core 消费者 | 上述 419 中包含协调器 20 项、真实 Dart/SQLite/loopback HTTP/Go Core 刷新桥接 24 项、JVM 清理桥接 4 项；均已计入总数，不另累加 |
| Go wrapper | 复用 v1 的 **335 个具名通过、2 个入口跳过、0 失败**及 vet 通过；Go 生产/测试源码与子模块均未变。本轮当前 Dart→Go 消费者重跑，普通 Go 跳过的 spec/bridge 由其实际执行 |
| Kotlin/JVM | app **82 通过**为本轮重新编译执行，其中 ConfigApplyStateMachine 11、ServiceStateMachine 47；service/common **53 通过**沿用未变的 Gradle UP-TO-DATE 结果。当前 Dart→JVM ConfigApply 和 4 个新增清理消费者均重跑；没有修改原生生产源码 |
| Android ARM64 | dev release APK 构建成功；最终制品及缓存复查结论见下节 |

[Flutter 汇总](../../../../build/verification/l1-t06/implementation_v2/flutter_summary.json)
记录每个 suite、用例名称及计数；[完整命令](../../../../build/verification/l1-t06/implementation_v2/flutter_command.json)
固定本轮环境、真实桥接程序、受管编译器与 JVM classpath。
本轮 JVM 报告与缓存口径见[JVM 结果](../../../../build/verification/l1-t06/implementation_v2/jvm_summary.json)，
Go 未变范围和旧证据摘要见[复用依据](../../../../build/verification/l1-t06/implementation_v2/go_reuse.json)。
受管编译器沿用已交付版本；当前 Dart 合成与实际 Core 消费者已重跑，不宣称全部传递源码均未改变。

### 与设计验收的对应

| 设计用例 | 实际检查入口和观察 |
| --- | --- |
| T1–T4 | [协调器](../../../../test/providers/profile_refresh_test.dart)、[真实桥接](../../../../test/providers/profile_refresh_bridge_test.dart)、[周期 UI](../../../../test/widgets/edit_profile_focus_test.dart)：队列资格、无复活、合并/后继、旧周期与完整退避上限 |
| T5 | 协调器、[请求作用域](../../../../test/common/request_scope_test.dart)、[Setup](../../../../test/providers/setup_action_test.dart)及未变 JVM 证据：停止/暂停许可、恢复、销毁收尾；有限提交销毁后仍返回已保存、应用被取代 |
| T6–T7 | [有界下载](../../../../test/common/profile_download_test.dart)、真实桥接、[统计解析](../../../../test/models/profile_test.dart)、[统计展示](../../../../test/widgets/subscription_info_view_test.dart)：慢头/慢流/断流、chunked/gzip/长度边界、重复与坏统计头、真实正文校验 |
| T8 | [receipt](../../../../test/common/request_receipt_test.dart)、[补偿失败](../../../../test/common/request_file_recovery_test.dart)及真实桥接：DB/发布失败；两种提交入口的释放前失败和释放后 ack 丢失；恢复标记覆盖原 receipt 收尾 |
| T9–T12 | [条件失败桥接](../../../../test/providers/policy_mutation_failure_bridge_test.dart)、[配置输入桥接](../../../../test/providers/application_input_bridge_test.dart)及刷新桥接：旧观察条件清理、较新 inactive Owner 保留、自身 Owner 转换、运行意图/接受事实检查、MD5/groups/providers 迟到投影拒绝 |
| T13 | [接受依赖投影](../../../../test/common/config_input_dependencies_test.dart)及真实桥接：有界 manifest/hash/schema/身份复核、缺失为未知；休眠引用零重建、实际登记重建、受管选项不变 |
| T14 | 真实桥接的跨 ID 保存/DB 失败两例与旧内部需求失效例：材料先完成，所属 Setup 成功且无需重复应用，条件收尾可结束；无须先释放无关 HTTP 才取消旧需求 |
| T15–T16 | 当前请求作用域、请求/下载测试与协调器：Direct/Auto/代理及首次恢复确认、失败不直连回退；合成 URL 用户密码/token 不进入新增错误输出 |
| T17–T18 | 真实桥接、请求作用域及 receipt：auto=false 的 S2/S3 与有限提交后继、UI 旧来源拒绝；普通材料来源使用新许可，显式旧 native 约束仍拒绝，自身 cancelKey 不使普通来源失效 |

旧回归夹具同步了新增检查时点：代理延迟以显式开始信号驱动，较新配置在原 receipt 完成后、
条件失败调用前注入，UI 延迟刷新结束前等待真实串行队列。
修订前失败和中止日志保留作诊断，不计入上述最终通过结果。
既有根目录 service_status／update_dialog 失败属于历史记录，本轮未执行这两组，也未据此宣称根目录全量通过。

## 制品、绑定与复现

受检/集成起点为 `cf66e036eb0e5e7a896e2c814cbb4e6062fbaf3e`，
最终交付位于 `security/android`，任务分支 `security/l1-t06-subscription-refresh` 已清理；Core 子模块为
`6c6e3e472bb246cc55f2e8577d9eddccc2623afc`，生产 Go/Core、Android 原生及 gitlink 未修改；Android 的改动限两份测试 transport/host。

最终源码树、变更快照、命令、日志、工具/产物 SHA-256 与限制统一见
[implementation_v2 绑定](../../../../build/verification/l1-t06/implementation_v2/binding.json)。
该证据目录保留在本地忽略目录，不随提交或推送交付。
测试使用合成内存 SQLite、临时文件/偏好、loopback HTTP/代理/DNS和实际 Core 子进程。
真实桥接的宿主 socket permission 使用 loopback no-op 替身，不是 Android fd protect/JNI 或设备实测。

[Android ARM64 APK](../../../../build/verification/l1-t06/implementation_v2/artifacts/FlClash-0.8.99-android-arm64-v8a.apk)
为 `com.follow.clash.dev`，版本 `0.8.99`、实际 versionCode `2026102301`，minSdk 24、targetSdk 37，
仅 `arm64-v8a`，Android Debug 签名；ZIP 和签名校验通过。
构建命令为 `bash build/verification/l1-t03/android_command.sh build`，工具链与开发环境配置沿用
[Android 构建指南](../../../development/android_build_guide.md)。构建输入与最终 APK 摘要由上述绑定维护。
v1 首次 hook 提示与相同 APK 缓存复查仍作为历史保留；
v2 首次同样出现 hook 提示，1,326 份源码/配置输入哈希前后未变；
冻结输入的 warm 复查无该提示且 APK 相同，摘要见绑定。不沿用旧 APK 作为本次修订产物。

复现需保留命令文件引用的 Rust 动态库、当前 Go bridge、既有受管编译器与 JVM classpath；
并非仅复制 APK 或单一测试程序即可重建整个验证环境。
在仓库根运行命令文件中的 argv/environment 可重跑受影响矩阵；构建命令生成 APK，
本项未安装、启动或操作设备。

## 尚未证明与保留限制

- 未执行实际 Android 设备、VPN 权限、TUN、物理网络变化、安装态或用户应用运行验证；Go/JVM/loopback 结果不替代这些证据。
- 未访问真实订阅、真实用户数据或凭据，未进行外部测试流量、上传或 push。
- 90 秒和 16 MiB 是本轮工程限额，未用真实订阅规模证明适配全部服务；HTTP 预算不包含首次导入的人类确认等待。
- 重试状态和 timer 属于进程内调度，不承诺后台精确定时或跨进程保留退避；未增加后台权限、常驻服务或第二个运行状态权威。
- L1-T04 身份/认证/跳转及 L1-T05 全面脱敏仍暂缓；新增错误分类与合成秘密检查不代表这些风险已解决。
- 受管订阅/集合/Geo 的扩展材料更新仍由 L2-T02-04 接续；本项不改变 selected policy，不启动其它任务。
