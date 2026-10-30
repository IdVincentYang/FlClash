# L1-T10 本地启动恢复 Plan

任务入口：[L1-T10](loop1_tasks.md#l1-t10-修改本地启动恢复与证据处理边界)。
输入基线为 `security/android@b88cb452b683ec762d7fcfa91bc9102963060a54`；design_v2 已通过。
本项 implementation_v2 已获 M1 实现评审通过，I1/I2 闭合；
本地交付定稿及未验收边界见 [Result](l1_t10_result.md)。
恢复限制本次启动时的自动配置，保留配置选择、文件及已有证据；已获准活动服务的正常自动维护沿用既有资格。
BootGuard 判断启动记录，ServiceState 继续裁决运行意图。

## 问题与目标

已核实的行为及缺口：

- [resolveBootDecision](../../../../lib/common/boot_record.dart) 在上次仍为
  `starting` 时计数，
  缺少、过期或已消费的退出资料也会计数。达到两次后，
  [Bootstrap](../../../../lib/bootstrap.dart) 在提示前清除 `currentProfileId`，并使用崩溃文案；
  这只取消选中，不删除订阅文件，也不能证明配置导致崩溃。记录尚未关联进程身份或当前选中的配置。
- [BootGuard](../../../../lib/common/boot_guard.dart) 无单次执行／写入归属保护；
  `markRunning`、`markClosed` 重新读取后写入。Bootstrap.attach 只在异步初始化结束后设置已完成标志。
  并发调用或 engine 更替时存在旧完成覆盖新记录的路径，尚无设备复现，不能写成已发生的故障。
- [Preferences](../../../../lib/common/preferences.dart) 忽略 `setString` 的
  false/null，
  解析异常直接拼入日志。损坏记录被当成无记录，无法区分首次启动与保护不可用。
-
  [原生退出查询](../../../../android/common/src/main/java/com/follow/clash/common/GlobalState.kt)
  返回主进程最近一条退出，但未提供 PID。Flutter recovery 跳过 initStatus；现有
  [ServiceState](../../../../android/app/src/main/kotlin/com/follow/clash/ServiceState.kt)
  已用 revision 保护初始化，不能用启动保护覆盖正在运行、准备中的请求或后来的 Tile 操作。

目标是正常启动不变，启动失败后仍可进入界面手动处理；区分确认异常、外部终止及未知中断，
记录阶段和有限次数，恢复自身失败、持久化失败都有可解释结果。T10 不保存堆栈／dump、不建设报告仓库，
不恢复 T04/T05，不修改 Core、业务出口或原生运行状态所有权。

## 方案与理由

### 1. 启动记录与退出资料

沿用 `boot_record`，新增 schema version、PID、processEpoch、attempt 标识及 phase。
`processEpoch` 复用 ServiceState 已有的进程标识，不建立第二个 service session。
stage 继续表达 `starting`、`running`、`closed`；phase 仅定位启动工作：`bootstrap`、`recovery`、
`core`、`setup`。
`running` 表示本次前端初始化完成，不等于 Core 连接或 VPN 业务已启动；这些状态仍由原有消费者判断。

原生返回本进程身份和启动时间（由 Process 的启动 elapsed time 与当前时钟换算），
并按旧记录 PID 查询主进程退出资料，返回 reason、PID、processName、timestamp。
仅在旧进程不同、名称和 PID 一致、`startedAt <= exitAt <= 本次进程启动时间`、
`exitAt > handledExitAt` 时采用；只消费实际匹配的时间，不让无关或未来时间污染游标。
系统时间调整导致区间不成立时按未知处理，不能反推崩溃。API < 30、查询超时／异常及缓冲中已无记录同样是未知。
系统资料能确认退出类别，不能确认具体根因或配置责任。

Android 的退出记录来自有限 ring buffer，API 30 起可按 PID 查询；timestamp 是 epoch 毫秒。
依据：[ActivityManager](https://developer.android.com/reference/android/app/ActivityManager#getHistoricalProcessExitReasons(java.lang.String,%20int,%20int))、
[ApplicationExitInfo](https://developer.android.com/reference/android/app/ApplicationExitInfo)。

| 旧记录／匹配资料 | 本次行为与计数 |
| --- | --- |
| 无记录、已 running 或 closed | 正常初始化，连续失败为 0；运行数小时后的 crash 不制造启动失败 |
| starting，匹配异常退出 | 跳过自动配置，显示系统确认的异常类别；连续失败加 1 |
| starting，匹配外部终止 | 不计失败，正常初始化；不声称用户主动终止或确认崩溃 |
| starting，资料不足或 unknown／other | 跳过自动配置，显示原因未知；连续中断加 1 |
| 同一 processEpoch 的 engine 更替 | 不算一次进程失败；旧 starting 时本次仍跳过自动配置，避免重复初始化 |
| recovery 尚未完成就再次退出 | 按相同身份／退出规则处理，展示失败 phase；不升级为清配置或删证据 |

异常类别包括 crash、crashNative、anr、initializationFailure；外部终止沿用
isExternalStop 分组，包括 user stop、low memory、signal、package change 等。

次数仅描述同一选中 profile 的连续未完成启动，取值 0–2，达到 2 后饱和；配置不同、正常完成或匹配外部终止打断连续计数。
配置改变时仍可因旧启动未完成进入本次 recovery，但新配置不继承旧配置的次数或责任。
不以任意小时数判断崩溃；时间仅用于资料匹配和校验。恢复界面成功进入可用状态也标记 running，结束这一段连续失败。

### 2. 分级恢复与用户入口

删除启动过程中自动清除 `currentProfileId` 的分支；保留次数阈值用于提示强度。
一次中断说明本次未执行自动配置；连续两次补充建议到配置列表检查或重新选择。
提示明确“配置选择和文件已保留”，原因未知与系统确认异常分别表述，不展示未经处理的系统 description。
用户确认后进入现有界面，可从配置列表选择／取消配置，或主动运行；不在恢复对话框中写配置或模拟一次运行请求。
不增加正常启动确认，不改写用户 autoRun 设置。

这个取舍保留跳过自动初始化这一实际防循环措施，取消无法证明与失败有关的配置变更。
若在提示里直接清选择，还需与并发原生 start 原子协调，会扩展 ServiceState 的职责；使用现有手动入口无需新增这套事务。

Recovery 下仍执行必要的 Core 连接和前端初始化，但不因 autoRun、旧本地 running 值或 idle 初始化主动
applyProfile／start／stop。
CoreLib.start 的 Service.init／syncState、CoreAction 的 init／updateGroups 属于连接及元数据同步
，
不等同于 SetupAction.setRunning 或 CoreLib.startListener 的业务运行请求；验证分别记录这些调用。
在 SetupAction 既有初始化入口增加 recovery 分支：读取原生快照，调用带 expectedRevision 的既有 recovery
initializer，
再读最新快照并同步 runtime。initializer 拒绝时接受最新状态，不重试覆盖；runtime 的迟到值继续检查
processEpoch/revision。
已有活动服务保持原状态，preparing 请求由其原有执行路径完成；恢复期间新 Tile/通知操作仍由 ServiceState 和
preparedRequestId 路径处理。
重连不成为新的用户意图，也不自动重放旧配置。

### 3. 启动后自动维护的边界

“跳过自动配置”约束本次 Bootstrap 的 autoRun／initStatus，不等于禁用正常自动刷新。
[Bootstrap](../../../../lib/bootstrap.dart) 和
[Application](../../../../lib/application.dart) 在 attach 前后各有刷新唤醒，
[ProfilesAction](../../../../lib/providers/actions/profiles.dart)
另有 visible／started／timer 入口；
它们统一经
[T06 refresh queue](../../../../lib/providers/actions/profile_refresh.dart) 和
Request，不因 recovery 改 RequestMode 或申请额外直连许可。

| 本次情形 | 同步、启动与自动维护 |
| --- | --- |
| recovery，尚无活动服务 | 仅连接与同步；不发起业务 start／apply，不新增自动下载 |
| recovery，已有合法 started | 保留服务；按既有开关、周期和 RequestMode 刷新并应用新材料 |
| 用户有效 start／stop | 原生最新意图优先；started 后唤醒刷新，stop／paused 撤销不合格请求 |
| 新 engine／显式退出 | attach aborted，Application 不继续旧启动动作 |

尚无活动服务涵盖 stopped／failed／paused／preparing。
自动队列 `_automaticRunEligible` 要求 started、intentRunning、非 paused；已有请求仍由 Request 校验
。
已有合法服务即使 boot record 不可用也正常维护，不因记录错误停止、重放或改路由。
成功刷新经 `_finishRefreshPost` → `applyRefreshedProfile` 应用新材料，不是恢复重新启动服务。
aborted 后不继续旧 post-frame 的刷新唤醒、App Links 或 shortcuts。

准确边界：`_automaticRunEligible` 在 Android 取原生状态，查询抛错则当前收集停止；
无 native client 返回 null 时不能仅靠该 helper 宣称有权限，Request 的 inspect/begin 仍检查
clientReady、来源与实际运行状态。
既有 [Request](../../../../lib/common/request.dart) 及
[Core registry](../../../../core/app_requests.go) 约束 client／dataset／source／
operation、
自动 DIRECT 与其他维护请求的运行资格，并在 detach／新 client／退出时拒绝旧操作；T10 不修改这些产品契约。

自动任务在 material 阶段已有资格复核，但 `_finishRefreshPost.current` 目前只对比来源和 intent 等信息，未复核
phase。
本项在该自动任务 post/apply 的提交前资格回调复用 `_automaticRunEligible`，
避免材料已保存后状态变为 failed／stopped、但 intent 尚未改变时继续自动应用；手动刷新路径不套自动资格。
更新 state／source 后的迟到 apply 与失败清理由现有 ConfigInput／expectedRun 所有权处理，不用 BootGuard 取
代 Request。

attach 的 completed／aborted 结果由 Bootstrap 单次 Future 返回；Application 仅在 completed 且
仍是当前会话、未退出时执行后续启动动作，
跨 await 后复核。启动记录不可用只禁本次自动配置，不等于整个 engine 会话失效；前端完成后可返回 completed 并保留合法维护。
会话更替则 aborted，并清理旧前端持有的监听／请求生命周期。boot record 写入 token 失效本身不冒充网络请求已取消；
已获准请求的取消及提交仍沿现有 Request detach/client/source 检查，不能承诺撤销已完成的材料写入。

### 4. 持久化、旧记录及并发

BootGuard 仍是 Dart 决策方。Android AppPlugin 提供窄的 record read/claim 与有归属校验的 write，
读写现有 `FlutterSharedPreferences` 的 `flutter.boot_record`；
仓库
[sharedState 读取](../../../../android/app/src/main/kotlin/com/follow/clash/Ext.kt)
已使用这一文件约定。
不另建数据库、报告目录或原生 recovery 状态机；Android boot record 不再经 Dart SharedPreferences 缓存读写。

归属与 IO 分开，采用以下有限机制，不用 coroutine cancellation 代表磁盘取消：

1. `onAttachedToEngine` 在主线程登记递增 engine generation，使旧 generation 失效；
   begin admission 同步校验调用来自当前已登记 plugin，只为其建立一次 attempt，不在 IO 完成时重新授予归属。
   因而 A 的旧 begin 即使迟到排到 B 后，也不能成为 writer。detach 只撤销自己的 generation，不能撤销较新的 B；
   普通 Activity 临时 detach 不等于 engine 销毁。
2. status／revoke／close admission 只读改短小的内存状态，不获取 preferences、不等待 IO 锁。
   revoke、退出、engine detach／更替对该 attempt 不可逆；close 先终止内存许可，再尽力写 closed。
   每个请求绑定 generation、attempt 和单调时间 deadline；原生默认预算 1.5 秒，Dart 等待上限 2 秒，
   admission 和开始 IO 前均检查有效性／deadline，过期请求不进入磁盘操作。这是响应预算，不是磁盘强终止保证。
3. 进程内只允许一个 boot-record IO 在途，无待执行队列；worker 归进程而非 plugin scope，detach 不以 cancel
   替代其结束。
   忙时立即返回 busy，调用方按保护不可用继续，
   不重试 begin、不新增 worker。持久化对象的创建、read 与 commit 都在这个串行 IO worker 内；
   main admission 不持有它的锁。A 的 IO 已开始而 B attach 时，B 可立即接管内存 generation，但 B 的
   read/write 返回 busy，
   不在 A 之前提交新记录；因此 A 的旧 commit 不会覆盖 B 已提交的记录。系统 IO 真正挂住只占该一个在途位置，不能阻塞新界面的失败退路。
4. IO 开始前／完成后复核 generation、attempt、deadline、终止状态，回包也受同样校验；
   commit true 且仍有效才报告成功，false／异常报告有限错误类别，内存已更新不冒充磁盘成功。
   已进入不可中断 commit 后发生 timeout／detach／重建失效，磁盘可能仍写入旧快照，不能撤销；
   后续 IO 只能等此操作真正结束，迟到结果不恢复许可。下次启动按实际读出的记录和退出信息重新判断，不声称 closed 已持久化。

Dart 的 evaluate／attach 合并 Future，phase／ready／close 串行；任一 boot IO 超时后，本 engine 的记
录写入永久停用，
主动向 native 发不等磁盘的 revoke，忽略旧回包；native deadline 也能拒绝尚未开始的过期工作。
rebuild 同样受该 attempt 约束，无迟到成功触发重新初始化的路径。记录超时只限制本次自动配置；
会话是否仍有效通过无磁盘 status 判断，新 engine／退出时停止旧 Bootstrap 和 Application 后续动作。
status 分别表达 engine generation 是否仍当前、record attempt 是否仍可写；超时停用后者不会误报已有服务必须退出。
显式退出或整体 preferences 失败处理转入退出后，不继续 Core／setup。
SystemAction.handleExit 立即终止 BootGuard attempt；cleanup 等待同一个 close Future。
isCurrent 在异步 status 返回后再次检查本地终态，防止退出期间的旧 true 响应放行后续工作。
实现评审 I1/I2 修订：每次 phase write 后、新启动副作用前复核会话；
恢复观察和 runtime 成功／失败按 provider 当前 epoch/revision/phase 判断归属，
不让被忽略的旧非 started 观察或旧异常清理较新运行时。
保护不可用提示一次，保留手动操作及已有服务；不因记录失败停止服务、清配置，不记录原始 JSON／异常文本。

旧版合法记录按旧 stage／时间／profile 读取，兼容其 null stage 表示 closed，旧非负次数按新上限截断；
缺少进程身份只能判未知中断，不拿最近退出补成确认崩溃。
负数／错误类型／非法 stage、超过 8 KiB 或无法解析的记录视为损坏，不用默认值冒充有效记录。
本次进入 recovery，保留原值；提示明确仅重建启动保护记录，用户选择重建后才覆盖此 key，
选择保留则本次不写记录、仍可进入界面。未来未知 schema 保留原值，不提供降级覆盖。
重建写入失败继续按保护不可用处理，本次也不恢复自动运行。
其它配置、订阅文件、日志和报告均不在此操作范围。
原有 SharedPreferences 整体无法打开时的用户确认清理入口仍单独处理，不将局部记录损坏升级为整份配置清理。
实施核查补充：整体 preferences 不可用时不启动 record IO，退出不保存 record。
原有清理目标为 app 数据目录的 shared_preferences.json，并非 Android 的 SharedPreferences XML；
本项保留其确认入口及对象，不扩展为整份 Android preferences 修复。
非 Android 的 guard 方法继续无 IO 返回，不把桌面关机当成失败启动。

## 实施与验证

设计通过后按以下顺序交付；本节为拟实施安排，尚无通过结果：

1. 先建立文档基线：新增 `docs/features/security/boot_recovery_design.md`，维护有效分类、record 契约、
   用户行为和所有权；
   修订 `.agents/rules.md` 的 BootGuard／分级恢复规则及 `.agents/architecture.md` 中受影响的启动职责
   说明；
   `loop1_plan.md` 的本地恢复说明链接长期设计，`loop1_tasks.md` 只维护本项归属、状态与入口。
   未实现部分标为 draft；接口声明／注释按实际契约补充，不复制整篇 Plan。
2. 实施 record parser／decision、AppPlugin 持久化与退出身份接口、BootGuard／Bootstrap、
   SetupAction 的 recovery 消费路径，
   同步 `lib/application.dart` 的 attach 结果消费与
   `lib/providers/actions/profile_refresh.dart` 的自动 post 资格复核。
   `lib/providers/actions/system.dart` 在退出入口立即 close，清理阶段等待同一 Future。
   按 localization skill 同步 `arb/intl_en.arb`、`arb/intl_zh_CN.arb`、
   `arb/intl_ja.arb`、`arb/intl_ru.arb` 文案源并正常生成 l10n。
   不手改 generated 文件，不改 ServiceState 的运行意图算法；发现需改变所有权时先回交设计。
3. 用现有 boot_record／boot_guard 单测验证分类及阈值、配置改变、同进程重建、PID 重用／时间不符、旧／损坏／未来 schema、
   写入失败、并发 evaluate、close 后迟到 ready。原生 JUnit 通过真实 boot channel admission/store 调
   用链及受控 IO barrier，
   覆盖 A begin 尚未入 IO 时 B attach、A commit 已进入后 B attach、Dart timeout 后旧完成、detach
   后迟到 rebuild、commit false；
   断言旧 generation 不重获归属、busy 无排队、status/revoke 无需释放 IO barrier、在途数不超过 1。
   合成存储后端不等于设备断电恢复；Dart channel tests 同时覆盖 timeout latch 和迟到回包不能恢复自动许可。
4. 验证真实消费者：App MethodChannel 的输入输出与错误；Bootstrap 提示／保留与重建选择、attach 合并和恢复期间退出；
   SetupAction 使用 Service 快照验证 stopped、started、preparing、更新 revision 的 Tile
   start/stop、迟到 runtime，
   断言保留 currentProfileId／autoRun，Bootstrap recovery 不产生隐式 apply/start/stop。复用原生
   ServiceStateMachine fixture 核对 initializer 拒绝后不覆盖新意图。
   在现有 `profile_refresh_bridge_test.dart` 真实 ProfilesAction／Request／SetupAction／
   Core bridge 中，分别唤醒 attach、visible、started、timer：
   stopped/failed 无自动下载／应用；已有 started 即使 record 不可用仍允许到期刷新、按接受的 RequestMode 下载并应
   用；
   material 已保存到 post 前转 failed/stop、更新 client/source、退出均不能迟到重启；手动刷新仍使用既有资格。
   Application 消费 attach aborted 与 timeout 后失效结果，验证不继续旧启动动作；只观察／同步 metadata 不记成业
   务启动或网络请求。
   未覆盖生产入口的替身不计为完整消费者验收。
5. 正常依赖解析、生成、相关 Flutter suites、静态分析、受影响 Android 模块编译与按影响 ARM64 构建；
   用临时 SharedPreferences／文件／DB、合成配置及受控时钟，不安装／启动设备，不访问真实订阅，不改宿主代理／TUN，不做外部测试流量。
   实际结果及设备限制再写 `docs/features/security/loop1/l1_t10_result.md`，不预写成功。

边界：guard 仍在 migration 读取配置之后开始；Rust／system／migration 更早失败不因本项获得完整捕获能力。
CoreAction 当前把部分错误转为断连／toast，UI 可用完成也不是 Core 启动成功证明。
设备 ApplicationExitInfo 的实际可用性、Activity 重建及磁盘持久性需列为未执行设备验收；
T11 接入报告后再复验其保存与恢复／用户清理顺序，不把本项完成等同于跨启动 dump 保存。
