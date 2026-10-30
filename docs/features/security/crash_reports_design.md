# Android 本地故障报告

当前实现保存 Android 本地故障材料；自动化覆盖与设备限制见文末。
报告用于在本机保存修复线索，不提供自动上传或分享能力。
启动恢复继续由 [BootGuard](boot_recovery_design.md) 决定，运行意图仍属于 ServiceState。

## 采集边界

- Flutter framework、主 zone 和初始化 catch 保存有限异常文本与栈，保留原日志／错误页行为。
  binding 建立前、独立 isolate 未转交及已经被业务处理的错误不保证采集。
- FlClashApplication 的 Java uncaught handler 尽力保存后恰好一次转交原 handler；
  采集／格式化／排队失败不能吞掉原终止。最多等 250 ms，不保证 OS 调度硬时限。
  OOM、安装前、被后装 handler 绕过或进程被立即杀死时可能缺材料。
- API 30+ 每进程启动导入本包最多 8 条主进程历史退出，其他进程不冒充主进程。
  异常／资源终止保留 metadata；明确正常／用户终止且无 trace 时跳过。
  trace 不改变原 reason，可能属于较早已恢复的 ANR。
  API 31+ native trace 是 protobuf，截断前缀不能称完整可解析 dump。
- Go fatal、Rust release abort、JNI native 崩溃主要依靠后续系统退出材料；
  不增 SDK／native signal handler，不改变 Go／Rust 恢复策略。
  系统可能不提供 trace，低 API 没有该退出来源，不保证每次报告或完整内存镜像。

## 所有权、事务与限制

原生 CrashReportStore 独立拥有 `Context.noBackupFilesDir/crash_reports/`。
FlClashApplication／CrashReports 提供错误及系统材料，AppPlugin 只接有限 Dart 错误输入。
调用者不能指定路径、文件名、身份或运行意图。非 Android 不做报告 IO。
BootRecords、preferences、DB、普通日志和报告不共用持久化游标／IO worker。

每份报告为不可变目录：schema 1 的 `metadata.json` 与可选 `raw.bin`。
store 在同根 staging 写入、sync／校验后 rename 发布；失败只清本次 staging，
不先删旧证据腾空间。重开忽略未提交项，拒绝路径或 symlink 越界。
读取／枚举／去重及 ledger 补记每次核对既定根，不继承先前维护的授信；
只读入口不创建、清理或迁移目录，缺失／非法根返回空结果或未保存。
metadata 记录来源、时间、受控类别、进程／版本身份、原始格式、大小／SHA-256、
截断及缺失状态。原始错误／栈／description／系统字节不能出现在可显示摘要中。

初始限额是成本保护，不是性能测量：

| 对象 | 上限 |
| --- | --- |
| 已提交报告 | 20 份、16 MiB、30 天 |
| 每份 metadata／Dart-Java raw／系统 raw | 16 KiB／64 KiB／1 MiB |
| 事务额外空间 | 2 MiB、1 份 |
| IO 调度 | 单 worker、4 个待处理小请求，满即 busy |
| 普通任务／Dart 等待 | 1.5 秒预算／2 秒 |
| 一轮系统导入 | 4 秒／4 MiB 预算 |

预算含排队，过期未开始的工作不写；已进入的阻塞 IO 无法强取消。
caller timeout 不代表回滚，迟到提交按 ID 去重；在途位置直到真实退出才释放。
系统导入逐条调度，身份读取也走同一有界调度，不能新增无界 worker 或阻塞错误页。
未知新 schema 不解释／改写／删除，损坏已提交项不冒充有效报告，均计入配额。
新报告发布后才淘汰已知格式旧项；清理失败时拒绝继续增量写入。
本次新发布项不参与本轮淘汰；不可回收的未知项已占满额度时直接 busy。
期限按保存时间判断，时间回拨不删除未来项，容量保护仍生效。
启动时另调度一次有界维护，即使没有新错误也检查期限；忙／失败时留待后续保存或下次启动，
不把尽力清理称为实时过期保证。

系统去重 ID 使用本包／进程／PID／退出时间／reason／status；已保存 ID 集限 64 项。
先提交报告再原子更新 ID 集，中途退出可从同 ID 已提交项补记。
保存失败不推进成功状态，正常淘汰的系统报告不因重启立即反复导入。
metadata_only 也是已提交的去重项；同一退出后来有 trace 时不自动补齐，
不能将其显示为完整报告或承诺后续会补齐。
实时错误另按进程内有界 fingerprint 去重，不把 Java 与系统来源强行合并。
返回 stored／duplicate／metadata_only 与 busy／io／deadline／unsupported／newer 等明确结果。
null 或零字节系统流都只提交 metadata，不能据空文件声称取得 trace。
失败不能递归进入报告器、打印 raw 或改变启动／服务状态。

## 构建身份与隐私

只保存必要包版本、进程／API／位数、可核实 ABI、APK SHA-256 和可取得的 ELF note ID；
identity.processEpoch 是报告器每进程随机 nonce，与 ServiceState 的 epoch 不共享权威。
不采稳定设备标识、配置、请求内容或任意线程名。异常／栈与原始系统材料可能含秘密，
仅私有 raw 保存，不能声称字符串脱敏能清净 dump。

当前安装 APK 读取限 256 MiB／2 秒，每个固定应用库读取前 256 KiB 的 ELF note。
GNU、Go ID 分开；buildIds 缺某键表示该 ID 未取得，observed 只表示完成 APK 观察，
不承诺所有库都有 ID。未知、split、ABI 不确定及读取未完成时不猜测。
API 30+ 至多两次 setProcessStateSummary 写入不超过 128 bytes 的有版本构建身份；
完整 ID 不适配剩余长度时省略，不截短冒充匹配。
后续退出只从该旧记录／summary 取原版本与进程身份；当前环境只能标为 observer。
缺失／未知 summary 不套当前版本，也不把 Android OS Build.ID 当 GNU Build ID。
正式符号与本地 APK／mapping 的关联见[构建指南](../../development/android_build_guide.md#本地符号与-apk-对应)。
缺匹配材料时不能符号化，不新增符号下载／上传服务，正式留存继续归 Loop 5。

no-backup 按 Android 官方规则排除 cloud backup 与设备迁移；实际设备迁移未验收。
报告不在 filesDir／DB／preferences／temp/share 中，FilesProvider 的 canonical filesDir
边界不允许枚举、直接 ID 或 symlink 读报告。配置 ZIP 的 BackupEntries 白名单、
WebDAV 的同一归档和普通日志导出都不追加报告。
既有错误链仍可能打印原异常；此处只保证新增报告材料不被再次加入这些出口，
不代表 T05 全面日志脱敏已完成。管理／选择导出由后续报告管理能力接续。

## 恢复顺序与验证边界

历史导入独立于 BootGuard 的 handledExitAt；该字段不是报告保存成功凭据。
恢复、显式退出和原 preferences 清理不清报告目录，也不等待报告成功来授予启动许可。
半写／磁盘故障只损失本次尽力记录，不改旧证据或发出补偿 start/stop。
合成后端／JVM／受控进程不能证明设备退出 API、断电持久性或真实系统备份迁移。

官方依据：[退出信息](https://developer.android.com/reference/android/app/ApplicationExitInfo)、
[进程状态摘要](https://developer.android.com/reference/android/app/ActivityManager)、
[备份排除](https://developer.android.com/identity/data/autobackup)。

## 验证入口

- [Dart 错误入口](../../../test/common/crash_reports_test.dart)：framework／zone／初始化转交、
  App 通道、失败不递归、UTF-8 限额及 caller timeout。
- [事务与资源](../../../android/tests/app/CrashReportStoreTest.kt)：真实临时文件重开、
  失败、半写、配额、期限与静默启动维护。
- [系统材料](../../../android/tests/app/CrashReportCollectorTest.kt)：旧身份、重复、
  缺失／空／截断流及阻塞 IO；[构建身份](../../../android/tests/app/CrashBuildIdentityTest.kt)
  对照独立工具输出及合成 ELF。
- [Android 入口](../../../android/tests/app/CrashReportsAndroidTest.kt)：API 24／30／31、
  Application／AppPlugin 和 FilesProvider；JVM 的无关 Core JNI 使用 shadow，非设备证明。
- [终止转交](../../../android/tests/app/CrashUncaughtProcessTest.kt)：独立受控 JVM，
  正常／busy／IO／格式化阻塞或失败／重入都保留原 handler 终止。
- [备份与日志排除](../../../test/providers/crash_report_exclusion_test.dart)：
  生产 ZIP、localhost DAVClient、Logs 导出及合成 picker 边界；保留旧日志的秘密风险。
