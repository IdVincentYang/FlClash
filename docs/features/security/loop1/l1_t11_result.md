# L1-T11 本地故障证据验证

implementation_v2 已获 M1 实现复审通过，I1 闭合，S1 限制已确认。
本地交付目标为 `security/android`；M 的任务文档收尾与远端推送尚未执行。
当前可私有保存有限异常与系统退出材料，跨 store 重开可读取；不承诺每次都有 trace／dump。
有效契约见[本地报告](../crash_reports_design.md)，本次增量与理由见 [Plan](l1_t11_plan.md)。

## 对象与结果

输入 `security/android@41dcd9aec3bc4d752b9e935e610195e4316c035d`，
受审分支为 `security/l1-t11-local-crash-evidence`；本任务实现快照由
[implementation_v2_snapshot.json][snapshot] 绑定。
993 个构建输入在构建前／后及最终实际文件一致，摘要为
`35f8f8fb093451f1063afaed5112230f0679befd67a5a2891adf145a8dc2cec7`。
Core 保持 `6c6e3e472bb246cc55f2e8577d9eddccc2623afc` 且干净。

| 验证 | 实际结果 | 范围 |
| --- | --- | --- |
| 复用 v1 Flutter | 114 成功，0 失败／跳过／error | Dart 及其测试源码未变；原结果保持 |
| 本轮 JVM／Robolectric | 32 成功，0 失败／错误／跳过 | store 17、collector 6、Android 9 |
| 复用 v1 本项原生 | 6 成功，0 失败／错误／跳过 | 身份 5、独立进程 1，源码与有效输入未变 |
| T10 原生回归 | 60 成功，0 失败／错误／跳过 | 本项较早选集中执行；未改的 boot store 与 ServiceState 验证复用 |
| 分析 | 0 error／warning、42 info | 与 T09 最终基线无新增 |
| ARM64 release | 构建、签名、ZIP 与包内容核对成功 | dev、Debug 签名；没有安装／运行 |

Flutter 排除 17 条 hidden 加载／fixture 事件，done 为 true。
原始结果及分 suite 证据见 [Flutter][flutter]、[原生摘要][native]、
[分析增量][analyze]、[构建日志][build] 和[制品核对][apk-check]。
pub get 使用正常锁定依赖；没有 model／provider／schema／ARB 输入变化，未手改生成文件。

## 评审修订

I1：read／ids／savedSystem 统一校验当前根，子项解析／枚举与 ledger 写入也复核该根。
校验不创建、清理或迁移目录；缺失根维持 null／空／false，正常重开、去重与补记保持。
四个 store 场景覆盖初始 symlink／维护后替换 × 有／无 ledger，
另验证只读缺失根不创建目录；collector 的真实导入不再把外部 ledger 当成本地成功。
目标合成文件逐项摘要不变，未向模拟 filesDir 补写 ledger。

同组反例在 v1 生产源码上重现 2 个 store 假成功及 1 个 collector 误判；
修复后对应 32 项选集全部通过，见[反向 store][before-store]、
[反向 collector][before-collector]及[本轮原生][after-native]。
反向预期失败不计入正常回归失败，未据此宣称实际发生过用户数据外传。

S1：metadata-only 提交后也去重，同一退出不会自动补齐后来出现的 trace；
当前契约已明确该限制，没有新增重试或扩展报告管理。

## 消费者与反例

- Dart 的实际 framework dispatch、guarded zone 和 startupError 展示回调进入 ErrorReports，
  App MethodChannel 传递有限 source／raw／truncated；格式化或保存失败不递归，
  展示回调不等 IO，四个 pending 及 UTF-8 byte cap 生效。
  Android Application／AppPlugin 到真实 store 的链在 Robolectric 中另行执行；
  两侧验证不冒充设备 FlutterEngine／JNI 联调或错误页画面验收。
- 真实临时文件 store 重开得到相同 raw／摘要与版本；sync／rename 注入故障、
  半写、未知／损坏项、容量／期限、时间回拨、静默启动维护及队列满／deadline 均有反例。
  未知材料占用不可回收额度时返回 busy；当前新报告不被本轮淘汰，避免假报 stored。
  故障注入不是实际磁盘满／断电证明。
- 系统适配保留旧记录自己的版本／API／位数及 ID，缺失时不套当前身份；
  当前查询 API 单独标为 observer。不同 PID 同 timestamp 分开保存，重复不重写，
  保存成功状态与 BootGuard.handledExitAt 分离。
  null／空流仅存 metadata，超限 protobuf 前缀明确 truncated，阻塞 IO 不释放在途位置。
- 独立受控 JVM 启动六种模式：正常保存、busy、IO 失败、格式化阻塞／失败、重入。
  原 handler 每次留下一次转交标记并以预定非零码终止，正常路径重开 raw 成功。
  合成 OutOfMemoryError 不代表实际内存耗尽已验证。
- API24/30/31 共 9 个 Robolectric 观察验证真实 Application／AppPlugin 与私有目录，
  FilesProvider 枚举／直接 ID／symlink 不能读取报告；报告根 symlink 也不能把采集改写到 filesDir。
  无关 Core JNI 使用 shadow，未加载 Android 原生库到宿主 JVM。
- 生产 BackupAction 生成 ZIP、DAVClient 上传到 localhost、Logs 导出到合成 picker，
  都未夹带报告 sentinel，原私有材料仍在。
  另证实已存在普通日志中的同一文字仍可导出；没有据目录排除宣称全应用日志脱敏。

测试入口由[当前契约](../crash_reports_design.md#验证入口)维护。
早期 Robolectric 夹具／assets 依赖错误的日志保留，不计入最终通过。
独立工具对照曾暴露 ELF 的 Android note 阻断后续 ID 的错误，已以合成反例及真实 APK 修复验证。

## 制品与复现

最终 [APK][apk] 为 `com.follow.clash.dev`、`0.8.99`／`2026102301`，57,278,362 bytes，
SHA-256 为
`4d31d2626bc04804b47982e84636e04c72239bac77925bf846ed751b77c1cc81`。
[R8 mapping][mapping] SHA-256 为
`2dd6763e07ca8bbbbd34084beb46f978900aca342af9613cb72f98de63996308`。
包内有报告入口与原生 store，无合成报告材料、Robolectric 或受控进程 probe。

未改的生产 CrashBuildIdentity 在 v1 APK 的读取与独立工具输出一致；
v2 的全部原生库逐字节与 v1 相同，身份验证据此复用，见[复用绑定][reuse]。
见 [身份对照][identity] 和[原始运行][identity-run]。
Go／JNI／Dart／Flutter 的可用 ID 匹配；Rust 未取得 GNU note，未造 ID。
此结果不保证所有平台／库都有 ID 或所有历史退出都能符号化。

复现入口为本地 [run_checked.py][checked]、[run_native.py][native-script]、
[run_build.py][build-script] 与 [inspect_apk.py][inspect-script]；Flutter 完整命令见
[命令记录][flutter-command]，暂关两项 build hook 并恢复原 pubspec 的安排仅用于本地测试／分析。
release 使用正常 hooks 和 `dart setup.dart android --arch arm64 --env dev`。
带真实 APK 的原生身份测试需设置 `FLCLASH_REPORT_IDENTITY_FIXTURE` 指向本地独立对照 JSON；
本次已提供 fixture、实际执行，未计为跳过。原生 suite 证据文件及配置见原生摘要。

## 交付定稿

M1 已核对受审文件、构建输入及 APK，并通过实现复审。
提交前整理仅更新 Plan／Result／Tasks 状态，生产、生成和测试与受审快照一致，
因此复用上述验证和制品，不重复构建／全量回归。
变更 Dart 格式、当前文档 lint／引用、diff check 与 comment density 通过。
最终提交、目标分支及临时分支清理的实际结果由 Git 历史和 D 的最终交接绑定；
本任务 Plan／Result 定稿进入交付提交，供 M 取回后收尾。

## 尚未证明

未安装／启动设备或 AVD，未用真实数据、凭据、订阅或原始用户报告，未改宿主代理／TUN。
Robolectric 与合成流不证明真实 ANR／native tombstone 的系统可用性、杀进程、断电持久性，
也不证明真实系统 cloud backup／D2D 迁移；目录排除依据平台规则及局部消费者验证。
binding／handler 之前、未转交 isolate、不可恢复 OOM／SIGKILL 或系统缓存缺失时仍可能无报告。
Go 已恢复业务错误不新增采集，报告浏览／选择导出留 T12；完整 Dart／Rust／Flutter 符号与正式留存留 Loop 5。
T04／T05 全面治理及 Loop 3 边界仍保留，不据本项宣称全应用安全完成。

[snapshot]: ../../../../build/verification/l1-t11/implementation_v2/implementation_v2_snapshot.json
[flutter]: ../../../../build/verification/l1-t11/flutter_final.jsonl
[native]: ../../../../build/verification/l1-t11/implementation_v2/native_summary.json
[analyze]: ../../../../build/verification/l1-t11/analyze_delta.json
[build]: ../../../../build/verification/l1-t11/implementation_v2/android_build.log
[apk-check]: ../../../../build/verification/l1-t11/implementation_v2/apk_inspection.json
[apk]: ../../../../build/verification/l1-t11/implementation_v2/artifacts/FlClash-0.8.99-android-arm64-v8a.apk
[mapping]: ../../../../build/verification/l1-t11/implementation_v2/artifacts/mapping.txt
[identity]: ../../../../build/verification/l1-t11/identity_final_expected.json
[identity-run]: ../../../../build/verification/l1-t11/native_final_identity.log
[checked]: ../../../../build/verification/l1-t11/run_checked.py
[native-script]: ../../../../build/verification/l1-t11/implementation_v2/run_native.py
[build-script]: ../../../../build/verification/l1-t11/implementation_v2/run_build.py
[inspect-script]: ../../../../build/verification/l1-t11/implementation_v2/inspect_apk.py
[flutter-command]: ../../../../build/verification/l1-t11/flutter_final.command.json
[before-store]: ../../../../build/verification/l1-t11/implementation_v2/native_before_store.xml
[before-collector]: ../../../../build/verification/l1-t11/implementation_v2/native_before_collector.xml
[after-native]: ../../../../build/verification/l1-t11/implementation_v2/native_after.log
[reuse]: ../../../../build/verification/l1-t11/implementation_v2/reuse_binding.json
