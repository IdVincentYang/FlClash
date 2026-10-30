# L1-T10 本地启动恢复验证

T10 implementation_v2 已获 M1 实现评审通过，I1/I2 闭合。
本地交付目标为 `security/android`；M 的任务文档收尾与远端推送尚未执行。
恢复保留选中的配置和文件，区分系统确认异常与原因未知，
已有服务的正常自动维护继续使用原有资格。行为契约见
[启动恢复](../boot_recovery_design.md)，增量与决定依据见 [Plan](l1_t10_plan.md)。

## 对象与结论

输入基线为 `b88cb452b683ec762d7fcfa91bc9102963060a54`，
受审工作分支为 `security/l1-t10-boot-recovery`。受测对象为本任务实现快照，
完整文件校验由本地 [implementation_v2_snapshot.json][snapshot] 绑定。
APK 构建前后 982 个输入文件的校验一致，输入摘要为
`cc0b675aec2ea6ce981140fe665a1a77ded61cc126470560f4ff49500cbe97e5`。
Core gitlink 保持 `6c6e3e472bb246cc55f2e8577d9eddccc2623afc` 且干净。

| 验证对象 | 实际结果 | 判断范围 |
| --- | --- | --- |
| 本轮 Flutter 消费者 | 119 通过，0 失败／跳过 | 启动、恢复、setup、退出及真实刷新 bridge |
| 本轮 Flutter record/guard | 28 通过，0 失败／跳过 | 共享夹具改变后的 parser 与 guard 回归 |
| 复用 v1 Flutter | 49 通过，0 失败／跳过 | 未变的 preferences、App 通道、刷新策略及 l10n |
| 复用 v1 JVM | 60 通过，0 失败／错误／跳过 | 原生源码未变；store 11 项、ServiceStateMachine 49 项 |
| 根分析 | 0 error、0 warning，42 info | 与 T09 最终基线相比无新增；不称零问题 |
| 依赖与生成 | pub get、l10n、build_runner 成功 | 四种 ARB 源，生成代码正常回填 |
| ARM64 release | 构建、签名及包完整性检查成功 | dev 环境，Android Debug 签名；未安装／运行 |

本轮两组 Flutter 计数分别排除 14／2 条 hidden 事件，0 error，done 为 true。
复用对象和 10 个新增用例的对应见 [验证范围][scope]；v1 原始证据保持不变。
原始结果见 [消费者][flutter]、[record/guard][common]、
[v1 Flutter][v1-flutter]、[JVM 摘要][native]、[分析][analyze]、
[分析增量][analyze-delta]、[构建日志][build] 和 [制品核对][apk-check]。
早期测试夹具缺少 ProviderScope／尺寸、原生默认多架构依赖未缓存的失败日志保留在本地，
修正夹具及使用 ARM64 后的最终结果才计入上表。

## 评审修订与反例

- I1：Bootstrap 在阶段记录写入完成后、显示恢复提示／连接 Core／执行 setup 前复核会话；
  record 重建与 preferences 初始化后的提示也受相同终态约束。
  生产 Bootstrap 的 6 个 barrier 用例覆盖 recovery/core/setup × 关闭／新 engine 接管，
  旧 attach 返回 false，不产生后续副作用。已经进入的操作不承诺强取消或回滚。
- I2：SetupAction 只按 provider 仍接受的 epoch/revision/phase 更新运行时。
  旧 stopped／failed 观察，以及旧 runtime 查询的成功或异常均不能清除新状态。
  4 个新增真实消费者用例覆盖旧非 started 回包和同 epoch／新 epoch 的迟到失败。
- 将这 8 个可直接结束的新增反例运行于冻结 v1 的两份生产文件，
  得到预期的 4 failure＋4 error，done 为 false；修复后的对应测试全部通过。
  recovery 提示的两个用例只计入修复后验证，未计入此反向运行。
  对象校验及原始结果见 [反向运行][before]；不把预期失败计为正常回归失败。

## 真实消费者观察

- BootRecord／BootGuard 验证进程、时间、游标、阶段和有界计数；
  旧格式仅判未知，损坏／未来格式不自动覆盖。用户明确重建才写入新记录，
  write false、busy 和 timeout 不恢复写许可；ready／close 的迟到结果不重新启用自动配置。
- `bootstrap_test.dart` 运行生产 Bootstrap 和真实恢复对话框。
  保留／重建两种选择均保留 currentProfileId 与 autoRun；并发 attach 合并；
  Core 连接等待中退出、engine 更替会中止 setup 和 Application 后续启动动作。
  SystemAction 在退出请求入口即终止启动许可；资源清理等待和迟到 status 不恢复许可。
- `boot_recovery_setup_test.dart` 运行生产 SetupAction，
  stopped／failed／preparing／started 只观察原生状态，不 prepare/start/stop；
  新 start 胜过 initializer 的旧 revision，迟到 runtime 不恢复已停止的显示。
  JVM 生产 ServiceStateMachine 同时验证 pristine idle 才能初始化 recovery，
  preparing／started／新 stop 不被覆盖。
- `profile_refresh_bridge_test.dart` 使用生产 ProfilesAction、Request、SetupAction、
  当前源码编译的 Go bridge，以及 localhost 合成订阅。
  attach／visible／started／timer 四类唤醒下，记录不可用仍保留合法 started 服务的刷新与新材料应用；
  正常应用可改变自身 Owner／revision。材料保存后发生外部 failed／stop 则不注册新配置；
  预定 timer 在 stopped／failed 时不下载。既有手动刷新、client/source 失效及提交异常用例同次通过。
- JVM 直接运行 AppPlugin 使用的 BootRecordStore.handle。
  受控 worker／回包队列和真实阻塞 commit 分别验证旧 begin、旧回包、deadline、
  detach、close、commit false、busy 无额外排队，以及 IO 释放前 status／revoke 已返回。
  进入 commit 的旧快照仍可落盘，结果必须 stale；测试没有把撤销说成磁盘强取消。

整体 preferences 不可用时不启动 record IO，退出不带 record 保存。
原有确认清理目标是数据目录的 shared_preferences.json，Android SharedPreferences XML 不在该路径内；
本项不扩展其清理对象，不宣称已验证 Android 整份 preferences 修复。

## 制品与复现

保留 [ARM64 APK][apk] 及 [R8 mapping][mapping]；包名 `com.follow.clash.dev`，
版本 `0.8.99`／`2026102301`，57,266,794 bytes。
APK SHA-256 为
`3d47575bb4a249f793de5ba11a0828869b1f9c2ec39bd99c5b9d186011bceb90`。
最终包只有 arm64-v8a，DEX 含既有 boot_record key，mapping 含本次实际使用的原生 store。
这些检查证明编译及纳包，不证明设备启动成功。

本地复现入口为 [run_checked.py][checked-script]、[run_native.py][native-script]、
[run_build.py][build-script] 和 [inspect_apk.py][inspect-script]。
Flutter 完整命令、临时关闭两项 build hook／恢复原 pubspec 的安排见
[命令记录][flutter-command]；不把临时 hook 设置纳入源码。
Go bridge 由当前 `core` 运行 `CGO_ENABLED=0 GOPROXY=off GOSUMDB=off go test -c` 构建；
两个需要 managed compiler 的消费者复用 L2-T02 已有 CLI，相关源码在本项未变，最终未跳过。
JVM 使用 JDK 17、ARM64 目标及 `-x :app:compileFlutterBuildDebug`；
release 构建使用正常 hooks，执行依赖锁校验及 `dart setup.dart android --arch arm64 --env dev`。

## 交付定稿

M1 已核对受审快照、实际源码、构建输入与 APK，并通过实现评审。
提交前整理仅更新本 Plan／Result／Tasks 的评审及交付状态；
生产、生成、测试源码与受审快照一致，复用上述验证与 APK，不重复构建。
25 份变更 Dart 文件格式检查无变化，当前文档 lint、引用、增量检查与 diff check 通过。
最终提交、目标分支和临时分支清理的实际结果由 Git 历史及 D 的最终交接绑定；
本任务 Plan／Result 定稿保留在交付提交内，供 M 收尾取回和清理。

## 尚未证明

未安装或启动设备／AVD，未使用真实订阅、配置、凭据或用户备份，未改变宿主 TUN／代理。
Android SharedPreferences 磁盘适配已编译，JVM 注入的是合成后端；
设备 ApplicationExitInfo、Activity 重建、磁盘满／断电持久性仍未验收。
也未覆盖 guard 之前的 Rust／system／migration 故障，未证明 Core／VPN 每次都成功启动。
本项没有新增 dump 保存或外发能力；T11 接入后再验证报告保存与清理顺序。
T04／T05 暂缓及设备限制继续保留，不据此宣称全 Loop 1 或全应用安全完成。

[snapshot]: ../../../../build/verification/l1-t10/implementation_v2/implementation_v2_snapshot.json
[flutter]: ../../../../build/verification/l1-t10/implementation_v2/flutter_final.jsonl
[native]: ../../../../build/verification/l1-t10/native_summary.json
[analyze]: ../../../../build/verification/l1-t10/implementation_v2/analyze_final.log
[analyze-delta]: ../../../../build/verification/l1-t10/implementation_v2/analyze_delta.json
[build]: ../../../../build/verification/l1-t10/implementation_v2/android_build.log
[apk-check]: ../../../../build/verification/l1-t10/implementation_v2/apk_inspection.json
[apk]: ../../../../build/verification/l1-t10/implementation_v2/artifacts/FlClash-0.8.99-android-arm64-v8a.apk
[mapping]: ../../../../build/verification/l1-t10/implementation_v2/artifacts/mapping.txt
[checked-script]: ../../../../build/verification/l1-t10/implementation_v2/run_checked.py
[native-script]: ../../../../build/verification/l1-t10/run_native.py
[build-script]: ../../../../build/verification/l1-t10/implementation_v2/run_build.py
[inspect-script]: ../../../../build/verification/l1-t10/implementation_v2/inspect_apk.py
[flutter-command]: ../../../../build/verification/l1-t10/implementation_v2/flutter_final.command.json
[common]: ../../../../build/verification/l1-t10/implementation_v2/common_final.jsonl
[scope]: ../../../../build/verification/l1-t10/implementation_v2/validation_scope.json
[v1-flutter]: ../../../../build/verification/l1-t10/flutter_final.jsonl
[before]: ../../../../build/verification/l1-t10/implementation_v2/regression_before.jsonl
