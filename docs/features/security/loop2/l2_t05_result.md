# L2-T05 来源接受与轻量追溯验证记录

D-02已实施来源权限、材料提交、provider／inline热采用和连接来源追溯；I1增量已过M复审。
指定AVD已实际运行R4／R5，VPN／protect、后台provider热采用、未知写者实际退出与恢复、R5取消重试及Script输出独立接受均有下文实证。
M对implementation_r5整项评审要求I2修订：原恢复／Start身份在setup排队期间须持续绑定，原身份及准入残留已完成新增影响自验，M1已通过整项实现评审；待本地交付及M收尾。
真实TUN／物理网络及DNS R1未覆盖，Core完整安装日志race仍未解决；host／JVM和受控guest loopback结果均不等于整项安全通过。

需求与方案见[Plan](l2_t05_plan.md)，有效语义见[来源契约](../source_acceptance_design.md)，English入口见[指南](../source_acceptance_guide.md)。
本记录只维护实际证据与限制。

## 受测对象与证据入口

- 父仓库基线：`310b61675f1efec8e9fb4f24659da425db4137af`，工作分支`security/l2-t05-source-trust`；实际WIP由本地实现快照绑定，不能只用基线commit重现。
- Core：`6c6e3e472bb246cc55f2e8577d9eddccc2623afc`，源码及gitlink保持不变；pubspec.lock、Cargo.lock未变。
- 冻结基线为仓库忽略目录`build/verification/l2-t05/implementation_v1/`；I1修订入口为`implementation_i1/`，原v1保持不变。`snapshot.json`绑定实际改动、文档、日志及制品；原design_v5／R3冻结记录不倒改。
- ARM64构建来源核对：I1的`i1-build-source/source.json`记录1,047份构建源码输入，并在构建后重核；I1构建时APK绑定位于`i1-apk-binding/binding.json`；后续R4／R5实际运行与制品绑定见对应增量节。v1的r34记录继续保留。
  host动态库使用本地独立的未strip Rust库，来源及限制保留在快照；它不是APK内的Rust库。
- 所有业务收件、订阅、DNS、代理及恢复数据均为自有loopback／临时目录合成夹具，没有使用用户真实订阅、数据库或设备流量。

## 实际证明的行为

| 消费者／场景 | 已观察结果与边界 |
| --- | --- |
| 真实Dart刷新、导入、Script保存及父Go权限 | 原始用途与实际使用位置同时绑定；确认新identity／Routing不会提前撤销本次下载的旧资格。file＋DB保存后才发布正式grant；拒绝、校验及SQLite失败保护仍适用的旧内容或保留恢复屏障。age正文经原解密器分类，BOM提交正文保持精确字节 |
| SourceUse、撤回与恢复 | 缺失／伪造／过期／跨用途凭据拒绝；Stop automatic maintenance与Stop using this content分开。候选不产生可运行许可，外部恰好一次source失效不能冒充本receipt自己的失效 |
| proxy／rule provider热采用 | 原parser及原消费者使用密封获准正文；旧适配器／规则generation保留。A更新时DIRECT与未变provider B的TCP、UDP关联仍独立收件；普通无写receipt的engineDetach后仍可热采用；退休预算满则延后更新并保原连接 |
| inline COW及R1规则路径 | 只重建受影响代理依赖闭包，未变对象／选择及已有连接保持；已批准的封闭纯规则形状由实际matcher消费。混合结构、固定保护／默认出口变化、unsafe／unknown DNS读者履历与预算超限拒绝自动采用 |
| live之后持久化失败 | runtime fact记录真实新材料并禁止重放；重试仅保存已应用事实，不能重新切live或从pending猜许可 |
| R3.4前端断开与未知写者 | 真实beginCommit耐久确认后丢失complete，旧receipt退休并只增加一次进程拒绝计数；ready可进入解释界面，read／新写／授信／发布／ConfigInput／离线恢复及时拒绝。旧complete只结束自己，保留foreign marker；registry／native epoch变化不能解除 |
| 真实Dart迟到finally与备份restore | 替换client后旧finally不能修改新dataset；Source permissions先核原生未知写者再读DB。真实备份actor分别清理本次与原有屏障，clearRecovery绑定同一receipt及其dataset失效 |
| 真实host进程退出 | writer子进程实际退出后耐久marker仍在；新host进程只经明确离线核对实际文件／行身份／grant恢复，未批准材料不被提升。此项只证明host进程边界，不能冒充Android进程退出验证 |
| Android插件分发 | ServicePlugin.onMethodCall实际分发允许beginCommit／markRecovery／clearRecovery并保持receipt／client及错误响应；publish／block／engineDetach／registerConfigInput／readData等内部动作及未知输入拒绝。Core为Robolectric shadow，没有执行Android JNI |
| 来源追溯 | 真实RuleWrapper.Match到最终tracker冻结规则／RP generation与来源标签，旧连接详情不被新Profile覆盖；SUB-RULE内部作者及无法唯一对账场景保持Unknown，不据标签宣称端到端安全 |

## v1检查与按影响复用

下列v1检查按影响复用；I1新增与受影响复验另列下一节，不把v1全套结果当作新源码已重跑全套。不同选集有重叠，不把下列数字相加当作独立覆盖。输出目录均相对于`build/verification/l2-t05/`。

| 检查 | 实际结果 | 证据 |
| --- | --- | --- |
| Go全套 | PASS，18.883s | `go_all_r34_current_wip.log` |
| Source限定race | PASS，66.894s；包含真实隔离子进程 | `go_source_race_r34_final_wip.log` |
| Go host vet | PASS | `go_vet_r34_current_wip.log` |
| Android ARM64生产源码vet | PASS；NDK28、CGO、with_gvisor／no_zerotier；按go list选取GoFiles＋CgoFiles，未纳入不兼容的host IPC测试夹具 | `go_vet_android_production_r34_wip.log` |
| Dart刷新／备份／DB／UI等受影响选集 | 259 PASS，27s | `flutter_r34_affected_wip.log` |
| 最终真实Dart→Go刷新／恢复整组 | 56 PASS，24s；使用当前Go bridge | `flutter_r34_final_refresh_wip.log` |
| 真实Dart迟到清理；备份两类屏障 | 分别1 PASS、2 PASS；最终刷新整组选集另记录 | `flutter_r34_late_cleanup_wip.log`、`flutter_r34_backup_bridge_fixed_wip.log` |
| 原请求scope／receipt | 34 PASS，12s；来源接受在该路由专用测试中使用明确的合成stub，不作为Go授信证据 | `flutter_request_fixtures_r34_final_wip.log` |
| 其余请求、配置及追溯消费者 | 106 PASS，5s | `flutter_r34_remaining_consumers_wip.log` |
| Android插件分发 | 2 PASS，0失败／跳过，真实插件＋受控Core | `kotlin_request_dispatch_env_r34_wip.log`及JUnit XML |
| JVM生命周期＋Go来源sidecar | 1 PASS；真实ServiceStateMachine，Android环境与Core lifecycle为受控host，非实际Android装配 | `flutter_jvm_source_bridge_r34_wip.log` |
| 依赖／生成／分析 | enforce-lockfile成功；正常build_runner与四语种生成已运行；分析为0错误／0警告、42条既有info | `pubget_r34_wip.log`、`generation_r34_wip.log`、`localization_r34_wip.log`、`analyze_r34_current_wip.log` |

## I1：排队clearRecovery与detach

M1独立复现的v1缺陷：clearRecovery在configMu前检查unknown，排队期间同receipt被detach退休，之后旧调用仍返回ok并删除恢复标记。
D的新增真实control回归也先复现此问题，同时发现failed／未ready receipt同样能清屏障。原v1及`m1_review_v1`红例未修改。

修订将unknown检查放在configMu之后，并在持registry锁时核存活的同registry receipt、begun、未failed／retired、ready client及本receipt的dataset失效，保持到相符marker删除完成。
新增排队detach、六类资格／foreign marker拒绝及合法restore正对照通过；旧complete／重复complete仍只结束自己，不能清旧或successor marker。

| 本轮增量 | 实际结果／证据 |
| --- | --- |
| D新增红／绿反例 | 红例保留；修正后PASS0.826s，`go_i1_clear_red_wip.log`／`go_i1_clear_green_wip.log` |
| M原复现用例在新源码复验 | PASS0.751s，仍为原测试；观察为restart-required、unknown=1、retired=true、marker存在，`go_i1_m1_case_green_wip.log`。不倒改原红例观察 |
| 受影响Go race | PASS13.768s；来源恢复、detach／进程退出、前台限额及本地材料提交选集，`go_i1_affected_race_wip.log` |
| 当前bridge真实Dart恢复／保存／晚到清理 | 6 PASS2s，`flutter_i1_restore_wip.log`；其中包括原合法备份restore两类屏障正对照 |
| vet | host及NDK Android生产源码均通过，`go_i1_vet_wip.log`／`go_i1_android_vet_wip.log` |

同类入口走读：beginCommit与complete先持configMu，后者在退休分支只释放receipt；来源离线恢复在Source RPC的同一configMu范围内核unknown及快照并清相符标记；材料发布在同锁内且正式grant前再次持registry锁核当前receipt／unknown；ConfigInput在取得读锁后重核unknown；provider／inline在configMu内重核scope及真实lease，其registry资格包含unknown拒绝。
未发现另一处仅凭锁前unknown检查继续恢复／发布的同类路径；此为源码边界复核，不冒充全部并发安全证明。清标记锁序为configMu → registry → recovery-marker，既有marker读写不持marker锁反向取得registry。

## ARM64制品

本地APK为`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`；项目打包副本为`dist/FlClash-0.8.99-android-arm64-v8a.apk`，两者摘要相同：
`b93e95d80f0e7900cc3a008e812096d1290a4574bfb2012cb74990c39c75e6c6`。
原v1 APK的`292be2f9fbf85c189a1483d239ca682d64618bb44aa6f6c462e617a80c828600`继续保留在v1冻结包，不覆盖。I1实际10项native库中仅libclash.so摘要改变。

实际包`com.follow.clash.dev`，versionName为`0.8.99`，versionCode为`2026102301`；ARM64 split沿Flutter实际规则给基础`2026100301`加`2×1000`。
ZIP完整性及Android Debug签名验证通过。Go build info为Go1.26.4／CGO／android／arm64，实际tags为`with_gvisor,no_zerotier`；
同tags选择的1,164个依赖package中没有ZeroTier。该结论只覆盖本次制品的构建选择与包检查，不等于设备网络验收。

I1重建日志为`android_arm64_i1_wip.log`；ZIP、签名、ELF及Go build info重新核对。未改Dart／Kotlin生产代码及生成源，按影响复用v1分析、生成和插件分发结果。

构建使用项目专用Gradle目录，关闭匹配的upload／publish任务与工具analytics；没有发布、上传或推送。
命令、Go／ELF及签名输出由本地绑定保存，制品没有安装到指定AVD。

## R4与实际Android增量

R4只在实际preparing／starting的启动构建中先复用已采用材料；正常刷新及停止态材料保存后的重建保持原流程。
初次将全部停止态都设为复用，真实Profile provider刷新bridge暴露旧checkpoint正常失效后被拒绝的回归；
该失败保留，收窄消费者后受影响编排通过。新生产与测试源码、R8、APK及原始设备记录仍在忽略目录等待完整交评，
不能据局部通过提前合入。

| 对象／消费者 | 本次实际结果与边界 |
| --- | --- |
| Go离线复用RPC | 真实preparing读取已采用checkpoint密封正文，独立HTTP收件零且未登记网络lease；来源／dataset／root、声明、损坏、撤权及恢复屏障反例通过。原unsupported action红例与修正后输出保留 |
| Go检查 | 全套PASS 18.708s；本复用消费者race PASS 3.709s，沿原host IPC测试overlay；不覆盖已记录的完整安装日志race |
| Dart与native清理 | 来源／复用／Service channel 28 PASS；setup＋实际JVM／Go bridge 85 PASS、19专项环境未执行。真实状态机原默认abort旧ready返回superseded的红例保留；限定unregistered后保旧ready、结束preparing且不伤新intent/token。实际插件传递及受影响状态机共15 PASS |
| 分析与制品 | analyze无error／warning、42原有info。R4 APK SHA `489642b2790282f3a2b32f210809dd4deac2040969948eaace8e8a8ffbacffe8`；1,050构建输入前后相同、同证书、Android arm64／no_zerotier，较I1仅libapp与libclash改变，DEX／R8另绑定；设备安装后原地sha256sum一致 |
| 真实Start及VPN | PID8587，真实UI通知／VPN许可后native started、protectGeneration=1且ready，Go ready／businessActive=true。preparing期间HTTP记录与Start前相同。首次业务探测过早发生于starting，失败保留；settled后四路收件通过 |
| 无写receipt的实际Activity退出与A更新 | 实际AppLifecycleState.detached／FlutterJNI断开日志后，同PID自动采用A-new及A-new-2；后一组连续发包核DIRECT和B的TCP／UDP四个真实tracker ID、建立时间、chains及provenance均不变，四轮收件成功，B SOCKS独立计数增加；serviceId、token51、owner2及protectGeneration1不变，manifest／checkpoint更新。断言入口`android_device/r4-hot2-assertions.json` |
| 前端返回及追溯UI | 新Activity沿生产setup另行应用，token430／owner3，不能把后台连续性延伸到这次完整应用之后。新业务实际Connection details显示Rule source与Applied revision `47476731a492`，对应实际tracker；旧连接快照不变由上述JNI前后记录证明 |
| 真实Stop | UI Stop后native stopped／userStop、serviceId空／protect none，Go retired且businessActive=false，保持实际token430；不是仅修改按钮文案 |
| 仅代理服务 | 实际UI关闭VPN再Start，PID8587／serviceId更新，native started／protect none，Go ready／businessActive=true；DIRECT／B的TCP／UDP实际四路收件通过，不将其解释为系统接管 |
| SQLite失败与耐久marker | 同UID holder11314实际持事务锁，生产Script保存失败且结束早于detach；DB仍为旧标签，marker保留、普通blocked。这组不计unknown；真实Force stop后target8587与holder均消失，新PID11776保持相同marker，Cancel不清理，Confirm才清理，Script许可仍0 |
| 实际未知写者 | 自有文件lease预检真实阻塞读者400ms，明确释放后读回原15字节并实核holder11908退出。随后同UID holder12589持合成Script文件lease；真实UI Save的durable marker出现，内核观察到实际读者触发lease break，真实engineDetach后readData返回request_restart_required；同PID11776新前端显示Force stop说明。18.691s内实际Force stop，target与holder均消失。核对入口`android_device/r34-actual-unknown-writer.json`；系统lease-break参数不可读，未改参数／安全设置，不靠期限推断退出 |
| 未知写者后的新进程恢复 | 新PID12893保留相同marker SHA `4a28290807be8029b522caff54cd3f1bb8086101a5603ac23aa5558459db13bb`，DB仍为旧Script标签、许可仍0；真实Review incomplete save → Confirm后marker才消失，Go token30／owner1／ready、业务inactive且可恢复。候选同意未被提升为许可 |

R4另有真实顺序红例：在旧marker存在时先尝试Start，原生正确进入failed／setupFailed并结束本次intent；
随后明确离线恢复可以清marker／保旧DB与许可，但附带重建在该failed reason下无可用维护出口，提示request route unavailable。
此红例见`ui-r3-after-explicit-recovery.xml`与`observation-r4-real-unregistered-marker-failure.json`，已据此获审R5修订；
上述fresh initializedIdle先恢复的成功不覆盖它，R5同进程顺序复验见下节，该轮交评时整项仍待M实现评审；最终整项结论见本文开头。

设备业务为guest loopback客户端经实际mixed入口、原Core规则／SOCKS与独立echo收件；已观测实际VpnService和protect状态，
不把这些收件冒充物理网络或真实TUN入站矩阵。默认合成含加密DNS声明，未测试公共解析或宣称DNS R1修复。
原v1／I1、首次Start红例及过早业务探测保持冻结／保留；R5恢复顺序及Script执行／输出增量见下节；整项未提前合入。

## R5实施与设备验证增量

R5沿已审方案接入实际UI Start与两处显式恢复caller，未增加恢复材料库或自动直连许可。
R5 APK SHA `531b8cfa25de5dbab3011bed248dabb588bdf5731b1650b23bd7b6cbe5bcf476`，1,051构建输入前后核同；
仅libapp／libclash较R4改变，DEX与R8映射完全相同，沿已验证同证书helper读取实际native／JNI。设备读回APK hash一致。`r5-apk-binding/binding.json`中的not installed yet是构建时历史；后续实际安装hash与runtime07由`android_device/probe-runtime-07.json`、`r5-recovery-assertions.json`绑定。
首次observer启动被默认user -2拒绝，runtime07明确同一guest user0并正确引用参数后运行；不将observer新进程当Force stop证据。

| 受测边界 | 实际结果 |
| --- | --- |
| Go全量 | `go_r5_all_01.log` PASS 19.801s；含新permit与file／reuse边界 |
| file候选读取与复用 | `go_r5_file_reuse_06.log` PASS：真实read ID等待在途写且释放，marker及marker读取错误／未知写者／nil或noop hook拒绝；当前client／dataset／source／root、物理来源独立purpose撤权、HTTP无session拒绝；候选读取不发布grant。标准空失效引用才是miss，任意其它空checkpoint仍损坏 |
| 单次permit | `go_r5_permit_02.log` PASS：failed／preparing使用真实registry与permit，完整URL变化拒绝、授权一次消费；后续真实publish Stop使已取得lease失效 |
| 窄race | `go_r5_reuse_race_02.log` PASS 4.652s；首轮因异步provider事件混入旧单帧helper失败，日志保留。只将本测试改为按真实response ID核唯一响应，未过滤产品日志或改生产代码；不覆盖扩大完整安装race |
| Dart请求及本地消费者 | `flutter_r5_boundary_02.log` 31 PASS；取消无permit且可重新确认、native已started而Core未ready不引导、本地file不登记session／permit及其原review／bind／lease释放 |
| Start入口 | `flutter_r5_entry_01.log` 16 PASS；新UI请求携带局部引导选项，tile／initialize／prepared／paused不携带，原pause与Stop竞争保护仍通过 |
| 实际编排bridge | `flutter_r5_setup_bridge_01.log` 84 PASS／20 SKIP，其中首次JVM env名错误跳过，`flutter_r5_jvm_bridge_01.log`用正确参数单独补跑1 PASS；其余19项用已有本地managed编译器在`flutter_r5_managed_bridge_01.log`单独补跑19 PASS；首次跳过记录保留，各选集有重叠不相加 |
| Go vet | host全包及Android NDK28实际生产选择56个Go／Cgo文件均通过；后者不冒充Android host IPC测试包通过 |
| 正常生成与分析 | build_runner正常生成，未手改生成文件；`analyze_r5_02.log`无error／warning、42原有info |
| 实际失败顺序恢复 | PID16244／helper runtime07；实际Script保存遇SQLite锁失败，旧DB标签和Script许可0，耐久marker保留；holder16729明确释放。真实Start结束为failed／setupFailed；随后Source permissions显式离线Confirm清marker且不提升候选，B的Direct引导出现。`android_device/r5-recovery-assertions.json` |
| 取消与再次Start | 首次网络Cancel前后完整HTTP收件记录相同，token21未变；新UI Start重新逐B／A询问，确认B后只有B收件，再确认A后实际started、token92／owner2／ready／businessActive=true。没有以按钮代替运行事实 |
| 恢复后真实业务 | guest loopback经mixed／原规则的B与DIRECT TCP／UDP四路回包与独立SOCKS计数通过；`r5-business-assertions.json`。旧fixture在发送数据前检查proxyTCP导致过早失败，原失败保留；只将夹具改为先完成原四路round再检查计数，不改产品或取消收件要求 |
| Script输出独立审查 | 代码已接受后，实际Start仍显示Review source、默认出口REJECT；Cancel不安装新输入、保token92。再次Start接受输出及两provider后实际started、token570／owner3／新input `ff299548362aaf223f7bf0a5d7bf79a1c959cacdba7dfe1a4ca07ad6c2e3cf7a`；guest测试连接EOF且echo／SOCKS计数未增。`r5-script-output-assertions.json` |

Script实测在R4同PID12893完成独立执行对照：导入Throw时首次Cancel不保存，重新导入Accept后保存；
撤回Script用途后Profile选择它，Preview再次Cancel，实际日志没有`L2_T05_EXECUTED_AFTER_PERMISSION`。
再次Preview并接受精确代码后，真实QuickJS抛出同名错误，UI与日志均可见；这只证明执行在授权之后。
证据为`android_device/script-denied-no-execution.log`、`script-accepted-execution.log`及对应UI XML。
另一份返回`MATCH,REJECT`的Script先在R4受请求路由失败影响，原失败保留；R5已完成独立输出审查及真实应用，见上表。

R4／R5完整增量冻结入口为`build/verification/l2-t05/implementation_r5/README.md`；
源码、构建、实际JNI／UI／HTTP／业务断言及保留失败记录由其snapshot绑定。
本地file的物理来源／读屏障覆盖来自host真实父Go入口，尚未将其扩大为Android file I/O可取消或任意外部路径能力的保证。

## 失败、修正与未证明范围

- 指定同一AVD已按授权隔离冷启动并安装I1获审APK；实际English UI完成Profile／最终配置及A、B provider确认。
  Start实际失败于Request.begin → completeProviders的新网络session：原生preparing、Go ready、businessActive=false，
  同一PID6247后续快照仍preparing。日志及两次实际JNI快照位于`android_device/`，R4后续获审并修正，
  不以界面Stop按钮或ready配置记启动／业务验收通过。最终合成包含应用默认加密DNS声明；未向公共目标测试或证明DNS运行。
- 同一实际进程经UI Stop返回stopped／userStop、旧配置ready且businessActive=false。未接入Profile的本地Script
  首次Save显示精确代码并可Cancel；再次Save仍要求Review script，明确接受后保存成功；Source permissions显示
  Accepted revisions: 1，执行Stop using this content后显示0，原配置token41未变。该项只证明保存／撤回入口及JNI状态，
  此早期项只证明保存／撤回；Script执行与输出分开审查的后续实证见R5节。该早期原生readData成功返回并由观察器endRead结束，不冒充恢复完成。
- Source＋AppRequest扩大race曾失败于Core完整安装的log.print／SetLevel并发，原始日志及选定观察文件保持冻结。
  夹具是WIP v2且trace可能参与，未做旧基线对照；不称其为已证明的旧基线问题、无害或已修复。
  长期跟踪见[完整安装日志风险](../deferred_security_items.md#core-完整安装的日志级别并发)。Source限定race通过不覆盖这项失败。
- R3原manual successor真实刷新红例已修正；R3.4旧detach单函数对照仍复现新client无法ready。
  对照只替换原detach逻辑，其余是当前WIP，不称其为完整旧commit复现。
- 原请求测试扩大运行暴露旧Core替身缺少sourceAcceptance、原生屏障文件效果缺失及一个文件信息读取／删除夹具竞态；该轮失败及中止保留。
  补明确合成stub、原生屏障副作用并在初始文件信息可观察后删除，34项再跑通过；没有关闭生产校验或跳过失败测试。
- Kotlin初次验证因Rust工具链PATH选择失败；显式使用既有匹配工具链后通过。Go vet发现新用的标准库API高于项目go1.21声明，已改为等价循环并重新通过。
  Android直接vet全包又遇到host IPC夹具build tag／类型不兼容；生产源码vet与实际ARM64编译分别验证，不将该失败记成全包vet通过。
- 初次只读核实时，用户已创建并启动Pixel_7a_API_34（API34／arm64-v8a），未安装com.follow.clash包；persist.sys.locale为空，当时未断言English。
  原QEMU未在本项进程sandbox内启动，不能追溯约束；用户后续明确授权D按需关闭／隔离启动同一指定实例，现已实际完成并观察English UI。
  SDK版本与allowed／denied本地端口probe均非guest启动证明。
- 已实际观察R4成功启动／protect、无写receipt的前端detach后后台热采用及mixed入口业务收件；
  在途写receipt的detach、同进程拒绝及真正Force stop后显式恢复已有上述实证；Script执行与独立输出许可已补证；真实TUN入站矩阵仍未证明，R4恢复顺序红例与R5修正后记录均保留。
  没有使用用户其它设备、创建／克隆AVD、擦除userdata、重启全局ADB或修改宿主网络。
- DNS共享IP身份R1、全面Script／日志脱敏、其它平台的来源接受，以及物理网络／全设备kill switch不因本项局部验证获得保证。

I1增量已由M1按snapshot `33816b8ff9450812e8413559210b1b68b0a4e6588bcfd32f56224c882029d326`复审通过，沿用v1未变结论。指定设备已隔离运行，当前先处理实际Start红例的R4增量，再补必要设备证据和整项剩余评审。
尚未获得整项实现通过，不进行提交／合入或远端操作。

## I2实现修订与新增验证（实现评审通过）

M确认implementation_r5材料及既有设备事实可沿用，但发现原恢复／Start身份可能在队列窗口被后来native命令替换。
该项由M指出源码可达竞态；本轮真实JVM／Go bridge的受控negative已捕获旧动作清理新命令，不称设备复现或完整旧commit复现。
修订固定原身份到setup队列、来源／Script／provider候选、permit、安装和错误清理；自身新token仅由本次receipt接续，不重认新命令。

I2主机增量：`flutter_i2_affected_01.log` 124 PASS（含真实JVM／Go与managed，选集有重叠不相加）。
真实bridge新增恢复／UI Start各自与tile、alwaysOn、Stop及token竞争的8个明确queue-window反例；
同身份恢复与fresh UI正对照通过。临时丢弃身份约束、保API及屏障观测兼容的`red_02`实际观察到旧调用
向新命令发`failRunIntent(requestId46,token33,unregistered:true)`，反例失败；修正版已恢复。
这不是完整旧commit复现；首个negative移除了同步观测，未进入目标窗口，已中止且不算有效红例。
`flutter_i2_recovery_callers_06.log`另有2 PASS：实际Profile／Script管理入口显示并确认恢复对话框，helper返回后、Setup前受控卡住；
caller传入的epoch／intent／token与确认前完全一致，新tile替代后真实Setup既不读Core配置、不授权网络，也不清理新命令。该2项的marker前提／恢复RPC回复是合成stub，只验证实际UI caller→helper→Setup传递；实际耐久marker及HTTP正对照见下表设备记录。
此前UI夹具缺尺寸／cache目录及FakeAsync调度造成的失败／中止日志均保留，不记产品失败或通过。

I2制品为SHA `1e352457293f80e8294695cade23c81185b6e171bffe7aac75ea2a3863859758`；
1,052份构建输入在构建前后及设备结束后均一致。较R5仅libapp.so改变；libclash、其余native、DEX和R8映射逐字节一致，
因此复用R5冻结的Go/JVM与probe-v4，仅Dart编排重新生成／构建，设备读回APK hash相符。
`analyze_i2_04.log`无error／warning、42原有info；正常build_runner生成，无手改生成文件。

| I2指定AVD实际消费者 | 结果与边界 |
| --- | --- |
| Profile恢复→取消→fresh UI Start | PID19347实际保存失败marker、旧DB与Script许可0；Start failed后通过Profile Source permissions恢复，取消无HTTP增量／无新token。新UI Start逐B／A确认后token90／owner2／实际started、ready、business active，四路独立guest loopback回包。`android_device/i2-profile-retry-assertions.json` |
| Script恢复→同原intent重建 | 第二次真实保存失败后，实际Script Source permissions恢复；原epoch及intent4保持，逐B／A确认后本次receipt把token90接续至281／owner3，Go ready／可重放但业务inactive；native仍failed且intentRunning=false，不创造运行命令，不提升候选。`i2-script-recovery-assertions.json` |
| 恢复后密封启动 | 新UI Start产生intent5／token311／owner4并实际started／business active；在绑定的启动观察窗口，HTTP事件文件完全相同。此0增量不宣称之后正常provider timer不运行。`i2-sealed-start-assertions.json` |
| 结束状态与范围 | 实际UI Stop结束；两个SQLite blocker19663／20607已退出，业务client关闭。并发反例来自真实host JVM状态机及UI-caller窗口测试，设备只复跑受影响正对照／取消；未重跑不变unknown完整矩阵，也不扩大到真实TUN或物理网络 |

I2冻结增量入口为`build/verification/l2-t05/implementation_i2/README.md`，原implementation_r5包保持不变。

### I2复审残留：旧入口不得使较新Dart setup失效（实现评审通过）

上一增量尚未覆盖“较新合法Dart Setup B已经在途，再由旧恢复A晚到同一SetupAction”的窗口。
M指出generation、需求取消及busy副作用早于过期拒绝，可能使B失去current；此处保留前述I2结果，只补新的双Dart任务验证与准入修订。

自查补齐同native身份的旧触发：排序票号须在恢复／fresh UI Start的触发点预留，不能等晚到applyProfile才分配。
首个准入版本ARM64构建成功但未安装／交评，保留为`i2_admission-intermediate-01`；后续制品须绑定原触发票号传递和同身份反例。

准入新增实证：`flutter_i2_admission_red_01.log`在生产Setup hash与原I2冻结完全相同的条件下，
实际较新B在途时被晚到旧恢复A失效，B返回false且收到其自身请求65／token36的unregistered cleanup；
`i2_admission_red_binding.json`记录当时生产／新增测试的hash及独立观测；原生产可由I2冻结包取回，
该次测试输入仅留hash、未单独保存原文件，不能声称原红例输入可逐字恢复。
四组green观测另含同native身份的旧触发、旧UI身份读取跨较晚合法Setup、合法较新调用仍替换旧任务。
仅受控丢弃原票号、改在晚到入口重新分配的`ticket_red_01`中，同native身份下B失败、旧A实际成功，
说明原票号须在恢复／fresh Start触发点而非晚到apply入口分配；该受控变体不是完整旧commit基线。
最终`flutter_i2_admission_affected_02.log`126 PASS，包含四组bridge对照、原8组native替代窗口及两个实际UI-caller传递用例，选集计数不另加内部case。
UI caller在Confirm之前已核一次预留，传入Setup的仍为同票号；marker／恢复RPC前提的stub边界沿原I2说明，实际后端正对照仍以设备记录为准。
原测试中无资格／已失效排队调用也应取消当前合法任务的断言已改为保护当前任务；真实source失效、Stop与合法successor的原检查保留并通过。
正常生成与`analyze_i2_admission_03.log`无error／warning、42原有info；最终制品与设备回归见下文。

最终准入制品SHA `a111899689b0c984bf68f3e1a55d7ee75aff6f115234022f66fbb81e3dd3a1fb`，
1,052构建输入在正常生成／构建前后与设备结束后一致；较I2仅libapp.so变化，Go/JNI其它native、DEX及R8均同。
原地安装hash一致，复用probe-v4的runtime09读取实际PID21979。真实UI Start后native started、token51／owner2、Go ready／businessActive=true；
随后真实UI Stop为stopped／businessActive=false，绑定的密封启动观察窗口HTTP事件文件不变。
`android_device/admission-start-stop-assertions.json`只证明这次受影响启动／停止正对照，不冒充设备并发、真实TUN或物理网络。
原I2设备两恢复caller、取消重试、业务与unknown矩阵按未变消费者及authority复用；本轮并发反例以真实host JVM／Go及实际UI-caller传递用例为准。
完整新增量入口`build/verification/l2-t05/implementation_i2_admission/README.md`；原I2／R5／I1／v1包不改；M1已通过整项实现评审，待本地交付及M收尾。
