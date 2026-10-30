# L1-T11 本地崩溃证据 Plan

任务入口：[L1-T11](loop1_tasks.md#l1-t11-增加本地崩溃证据保存)。
输入基线为 `security/android@41dcd9aec3bc4d752b9e935e610195e4316c035d`。
design_v1 与 implementation_v2 已获 M1 通过，I1 闭合，S1 限制已确认；
本地交付定稿，
实际结果与设备边界见 [Result](l1_t11_result.md)。
方案是在 Android 应用进程内私有保存可取得的异常和系统退出材料，
保留原错误处理与启动恢复；报告管理及选择导出由 T12 接续。

## 问题与目标

当前 [main.dart](../../../../lib/main.dart) 把 framework／zone 错误交给
[CommonPrint](../../../../lib/common/print.dart)，只保留内存日志；初始化 catch 显示错误页。
[Application](../../../../android/app/src/main/kotlin/com/follow/clash/FlClashApplication.kt)
没有 uncaught handler，
[GlobalState](../../../../android/common/src/main/java/com/follow/clash/common/GlobalState.kt)
只查询最近一次主进程退出的有限字段，不读取 trace。
因此重启后通常无法取得原异常，BootGuard 的记录也不能替代修复证据。

目标是形成“真实错误／系统退出 → 有限私有持久保存 → 下次启动仍能重开”的闭环。
不新增采集 SDK、旁路进程、运行状态机、遥测或普通日志持久化框架；
不修改 mihomo、Go／Rust 错误恢复策略或桌面平台。

| 来源 | 实际入口与拟保存内容 | 限制 |
| --- | --- | --- |
| Dart framework | FlutterError.onError 的类型、异常及 stack | 不等于进程 fatal |
| Dart zone／启动 | runZonedGuarded 转交点及初始化 catch | 独立 isolate 未转交的错误不保证捕获 |
| Java／Kotlin | Application 的 uncaught handler | OOM／安装前／后装 handler 可能绕过 |
| 系统退出 | API 30+ 最多 8 条主进程退出记录 | 低 API 无此来源，环形缓存可能缺失 |
| ANR／native | 同一记录的原始 trace stream | ANR 可先前已恢复；API 31+ native 为 protobuf |
| Go／Rust／JNI | fatal 后的系统材料；未处理 Dart 错误 | 不保证 fatal 时能回调；非完整 dump |

当前 app／VPN／Proxy／JNI 没有独立 `android:process`，上述系统采集限定本包主进程；
其他进程条目不套用主进程身份，不引入多进程存储协议。
Android 官方说明 trace 可以为 null；缺失时保存退出 metadata 与缺失状态，不伪造 dump。
Go wrapper 已恢复的 panic 或转为普通日志／业务失败的错误不新增采集；
Rust release 的 `panic=abort` 和 Go fatal 主要依靠后续系统线索。
依据见 [退出 API][exit-api]、[历史查询][activity-api]、[Flutter 错误入口][flutter-errors]。

## 方案与理由

### 采集与恢复分工

新增 app 模块的 CrashReportStore／CrashReports，前者负责事务、限额及去重，
后者对接 Application、Android API 和 AppPlugin；Dart 的窄 capture helper 只向
`lib/plugins/app.dart` 的内部保存入口提交有限错误材料，不接受目录、文件名或运行意图。
不把报告写入 BootRecords 的 preferences／IO worker，也不依赖 Dart config／DB 可读。

Application 先安装异常转交，再异步初始化报告存储及导入历史退出；
同一进程最多调度一轮导入。每条系统记录独立提交，让实时错误能在条目之间获得执行机会。
只保存异常／资源终止等诊断退出；明确的正常退出／用户终止无 trace 时跳过，
有 trace 时保留其真实 reason，不改称确认崩溃。
Flutter binding 建立后、Rust／system／migration 之前装入 capture；
framework／zone 只记录一次，原日志转交与初始化错误页继续执行，不等磁盘成功才显示。
沿用现有 zone，不增加 PlatformDispatcher 处理链；非 Android 不做报告 IO。
capture 失败只返回固定状态，不再 reportError／打印原始异常，防止递归。

Java handler 仅在取得原 default handler 时安装，重入立即转交；
尽力提交有限栈，最多等待 250 ms，然后在 finally 中恰好一次调用原 handler。
不把记录失败变成异常被吞或进程继续运行，也不承诺 OOM／SIGKILL 时完成写入。
该等待仅用于已经 uncaught 的终止路径，普通 channel／启动不在主线程等磁盘。

系统导入与 BootGuard 独立进行：恢复可以继续，不以保存成功授予启动权限。
`handledExitAt` 仍仅是恢复判定游标；保存成功由报告事务确认。
系统去重使用包／进程／PID／timestamp／reason／status 的稳定 ID，
仅提交成功后更新有界的已保存 ID 集；崩溃发生在提交与 ID 更新之间时，
重启先核验同 ID 的已提交报告，再补记，不重复生成。
同一次 Java 异常与系统退出可关联进程／时间，但不强行合并不同来源。
启动恢复及原有 preferences 清理不接触报告目录。

### 私有事务与资源边界

目录选 `Context.noBackupFilesDir/crash_reports/`，只由原生 store 访问。
每个已提交报告是不可变目录，含 schema 1 的 `metadata.json` 和可选 `raw.bin`；
原始 Dart／Java 文本也按 raw 处理。先在同目录写 staging、flush／sync、核对大小与摘要，
最后 rename 发布；失败只清本次 staging，不先删旧报告腾空间。
重启只枚举已提交目录，半写入不冒充成功；文件名由 store 生成，拒绝路径与 symlink 越界。

初始限额用于约束诊断成本，并非设备实测结论：

- 最多 20 份、已提交内容共 16 MiB、保留 30 天；metadata 每份 16 KiB，
  Dart／Java raw 64 KiB，系统 trace 1 MiB，截断与格式独立标记。
- 一个 IO worker、最多 4 个待执行小请求；溢出即 busy，不继续创建线程／Future 队列。
  重复 live 异常按进程内有界 fingerprint 去重，不反复收集日志。
- 普通写入／单条导入预算 1.5 秒，Dart 等待上限 2 秒；全轮系统导入预算 4 秒、4 MiB。
  预算含排队，未开始的过期工作不写；已进入的阻塞 read／sync 不能强取消。
  caller timeout 不等于已回滚，迟到提交仍按 ID 去重，不能产生启动副作用。
- staging／一次发布额外预留最多 2 MiB、1 份；新报告完整发布后才按已知格式淘汰最旧项。
  清理失败导致超出稳态上限时拒绝新写，物理使用不继续累加。
  到期清理按明确保留策略执行，不作为故障恢复动作。
- 未知新 schema 不解释、不改写或自动删除，并计入配额；损坏已提交项隔离为不可读并计费。
  遇目录／权限／磁盘故障明确返回 io；无 trace 返回 metadata_only，
  busy／deadline／unsupported／newer 等结果不写成“已保存”。

已保存 ID 集另有 64 项上限，采用原子替换且计入总配额；
保存失败不推进它，也不借用时间游标跳过其它同 timestamp 的退出。
正常淘汰后的系统条目不因重启立即反复导入。

### 身份、秘密与符号

metadata 记录来源、时间、类型／fatal 或退出 reason/status、主进程名／PID、
包及实际版本、API／进程位数、可核实 ABI、材料大小／SHA-256／截断及缺失原因。
可显示摘要只含受控类别与这些必要身份，不含异常 message、description、栈、URL、
配置／请求内容、凭据、设备稳定标识或任意线程名；任意原始文字与系统流只留私有 raw。
不声称字符串脱敏能清净 dump，也不把普通 ZIP 当加密。

当前包身份在独立有界 IO 中读取安装 APK：最多 256 MiB／2 秒，计算 APK SHA-256；
对匹配 ABI 的 `libclash`、`libcore`、`librust_api`、`libapp`、`libflutter`
读取有限 ELF note，分别记录可取得的 GNU／Go Build ID。
只解析支持的 ELF32/64 note 范围（每库前 256 KiB），未知／超界／缺失明确标记，
不把 Go ID、GNU ID、包版本或 Android OS Build.ID 相互冒充。
多 ABI 无法确定实际进程 ABI、split APK 或未完成身份读取时保留缺失状态，不猜测。
只读核对 T10 已审 APK：上述范围可读到 Go／JNI／Dart／Flutter 的 ID，
Rust 库未取得 GNU note；Go ID 为 83 bytes，不能强塞进系统的 128-byte 摘要。
这是现有制品调查，不是 T11 实现验证；缺失项与摘要省略必须保留。

API 30+ 至多两次使用 `setProcessStateSummary` 写入无秘密的版本／ABI／APK 摘要及
可容纳的核心库 Build ID；格式有 magic／版本／长度，总计不超过 128 bytes，
完整 ID 放不下就省略并标记，绝不截短后宣称可匹配。
后续退出从该记录自己的 summary 取原版本，不能套当前安装版本。
设置失败、旧版本未设置或未知 summary 时标为 unknown；原始 native trace 仍保留。
这只是报告身份，不能用于恢复 UI／运行状态；依据见 [系统状态摘要][activity-api]。

本地符号匹配继续沿用[构建指南](../../../development/android_build_guide.md#本地符号与-apk-对应)：
Go／JNI 未剥离库和 R8 mapping 与实际 APK 核对；可用 Build ID／APK 摘要提供关联，
缺旧 APK／匹配符号则明确无法符号化。T11 不内置符号上传／下载／解析服务，
不把现有构建材料扩大成完整 Dart／Rust／Flutter 符号保证；正式留存仍归 Loop 5。

### 备份、文件入口与本项出口

报告根与 `filesDir`、DB、preferences、temp／cache 分离。
Android [自动备份与设备迁移规则][backup-api]均排除 no-backup；
不通过关闭全应用备份来代替本项目录隔离，不新增 BackupAgent。
[FilesProvider](../../../../android/service/src/main/java/com/follow/clash/service/FilesProvider.kt)
已用 canonical path 限定 filesDir，不能枚举或伪造路径读报告。
[配置 ZIP](../../../../lib/common/backup.dart)仅收集配置、DB 与 BackupEntries 白名单，
[WebDAV 入口](../../../../lib/views/backup_and_restore.dart)复用该归档，
[普通日志导出](../../../../lib/providers/app.dart)只编码 logsProvider。
上述入口都不追加报告，不把原始材料暂存到 picker／share 的可分享路径。
T12 之前仅提供内部保存／受限重开能力及可复现验证，无浏览／导出 UI。

## 实施与验证

设计通过后先建立当前文档基线，再改生产与测试，实际结果最后填 Result：

1. 新增 `docs/features/security/crash_reports_design.md` 维护当前采集、格式、限额、隐私及覆盖契约；
   更新 `.agents/architecture.md`、`.agents/rules.md` 的报告所有权／路径约束，
   `boot_recovery_design.md` 的独立保存顺序、`android_build_guide.md` 的身份／符号限制；
   `loop1_plan.md`／`loop1_tasks.md` 仅维护入口及状态。实现前说明标为 draft，
   不修改 T10 已冻结记录或复制一份安全需求。
2. 落实原生 store、Application 采集、AppPlugin 保存边界与 main.dart 三个真实错误消费者；
   保持错误页、原 handler 终止及 T10／ServiceState／Request 行为。
3. 使用合成材料、临时目录与受控时钟，验证写入后新建 store 重开、raw 摘要及版本一致；
   半写／rename／sync／磁盘失败、大小／容量／期限、重复、同时间不同 PID、未知 schema，
   并发／排队满／重入／deadline／迟到提交及清理失败不破坏旧证据。
4. Dart 运行真实 framework／zone／初始化错误转交与 App channel，断言保存一次、原展示仍执行，
   capture 自身失败不递归。JVM／Robolectric 运行生产 Application／store 适配与
   合成 ExitInfo/trace，覆盖低 API、API30 ANR、API31 native、null／oversize／阻塞流、
   其它进程、旧包 summary／无 summary；独立 JVM 受控进程核对未捕获异常保存及原 handler 终止。
5. 把合成报告 sentinel 放在 no-backup，实际生成普通 ZIP／localhost WebDAV 备份并检查内容，
   普通日志导出不含 sentinel；FilesProvider 的枚举、直接 document ID 与 symlink 均不能越界。
   核对最终 merged manifest 的 backup／provider 行为，不以字符串扫描替代消费者验证。
6. 合成 ELF note／真实本地 APK 检验 ID 与 ABI 匹配及缺失分支，
   pub get、正常生成、根分析、受影响 Flutter／原生选集及 ARM64 构建；
   以最终源码／APK／mapping 绑定结果到 `loop1/l1_t11_result.md`。

本轮不安装／启动设备或 AVD，不读取真实异常／用户数据，不访问外部测试目标，
不改宿主 TUN／代理。真实系统 trace 可用性、进程被杀与磁盘断电持久性仍列设备限制；
受控进程或合成后端不能写成真实 Android 崩溃／备份迁移已验收。
T04／T05 全面治理继续暂缓，既有日志可能包含秘密的风险保留；
本项新增路径不再复制 raw 到普通日志或网络。T12 管理／导出和 Loop 3／5 不抢跑。

[exit-api]: https://developer.android.com/reference/android/app/ApplicationExitInfo
[activity-api]: https://developer.android.com/reference/android/app/ActivityManager
[flutter-errors]: https://docs.flutter.dev/testing/errors
[backup-api]: https://developer.android.com/identity/data/autobackup
