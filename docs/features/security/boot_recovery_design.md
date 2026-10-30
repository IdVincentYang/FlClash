# Android 启动恢复

当前源码已实现，本地合成验证见 [T10 结果](loop1/l1_t10_result.md)，实现仍待评审。
启动未完成只触发本次启动恢复，
不会取消选中的配置、删除订阅文件、重置 autoRun 或清理诊断证据。
BootGuard 决定恢复，ServiceState 决定原生运行意图；本契约不提供堆栈／dump 保存能力。

## 判断与用户行为

BootRecord 的 starting 表示前端初始化尚未完成，running 表示界面初始化完成，closed 表示显式退出。
running 不保证 Core／VPN 已成功运行；运行后发生的崩溃不计为启动失败。
phase 定位 bootstrap、recovery、core、setup，不构成第二个服务状态机。

| 上次记录与退出资料 | 本次处理 |
| --- | --- |
| 无记录、running、closed | 正常初始化，连续失败为零 |
| starting，匹配系统异常退出 | 跳过启动自动配置，说明系统确认的异常类别 |
| starting，匹配外部终止类别 | 不累计失败，正常初始化；不把 signal 等同于用户主动终止 |
| starting，原因未知或资料不可用 | 跳过启动自动配置，说明中断原因未知 |
| 同一原生 processEpoch 的 engine 更替 | 不新增进程失败；旧记录 starting 时仍跳过重复自动配置 |

系统异常类别包括 crash／native crash／ANR／initialization failure。
退出匹配要求旧进程不同、PID／主进程名一致、时间在旧 startedAt 到新进程启动时间之间，且晚于 handledExitAt。
只消费实际匹配的退出资料；时钟调整、API < 30、查询失败或系统记录已淘汰均不构成确认崩溃。
系统原因只能说明退出类别，不能证明选中配置是根因。

同一 profile 连续未完成启动的计数限制在 0–2；换 profile、正常完成或匹配外部终止打断连续计数。
第一次提示本次跳过自动配置，达到两次加强检查／手动重选建议；配置选择和文件始终保留。
恢复期间再次中断按相同规则判断，显示 phase，不升级为自动清理。

## 存储与并发

Android 沿用 FlutterSharedPreferences 的 flutter.boot_record。Schema v1 包含 stage、
phase、profileId、startedAt、
failureCount、lastFailedProfileId、handledExitAt、PID、processEpoch、attempt；时间使用
epoch 毫秒。
旧版 null stage 兼容 closed，无身份的 starting 只能判未知。错误类型、负数、非法枚举、超过 8 KiB 或无法解析的值视为损坏。
损坏值保留，只有用户明确选择重建才替换该 key；未来 schema 保留且不降级覆盖，不升级为整份 preferences 清理。
整体 preferences 不可用时不启动 record IO，退出也不保存 record。
原有确认清理入口仍针对 app 数据目录的 shared_preferences.json；
Android 的 SharedPreferences XML 不属于该路径，不据此承诺修复其整份存储。

AppPlugin 只适配身份与持久化。主线程登记递增 engine generation，在 begin admission 建立一次 attempt；
旧 plugin 的迟到 begin、detach、结果不能接管或撤销新的 engine。status／revoke／close admission 只操作短小
内存状态。
record attempt 的可写性与 engine 的当前性分别判断；IO 失败不要求停止合法活动服务。

进程持有一个 boot-record IO 在途位置，无等待队列；忙即返回 busy，不创建新 worker／重试 begin。
preferences 初始化、read、commit 均在该 worker 内，主线程不等待磁盘锁。
原生 admission／IO 前后及回包时核对 generation、attempt、终止状态和单调 deadline，默认响应预算 1.5 秒，Dart 上
限 2 秒。
commit true 且仍有效才报告成功；超时后 Dart 不恢复该 engine 的记录写许可，迟到成功也不能重新启用自动配置。
已经进入 commit 的操作无法强取消，可能仍落盘；后续磁盘操作不会先于它完成，不声称超时等于已撤销或 closed 已持久化。
显式 close 先终止内存许可，再尽力写 closed；迟到 phase／running 不恢复许可。
SystemAction 在收到退出请求时即调用 close，清理阶段等待同一 Future；
不等托盘等资源清理完成才终止启动许可，迟到 status 响应也不能恢复许可。

BootGuard.evaluate、Bootstrap.attach 各自合并并发 Future。旧 engine／退出使旧 attach aborted，
Application 不继续其刷新唤醒、App Links、shortcuts。记录损坏、busy、false／异常写入只限制本次自动初始化，
界面仍可手动操作；错误提示一次，不包含原始 JSON、description 或异常文本。非 Android guard 无存储 IO。

## 与运行及自动维护协作

Recovery 允许 CoreLib.init／syncState、CoreAction.init／updateGroups 等必要连接与元数据同步，
不因 autoRun、旧本地 running 值或 idle 初始化调用业务 setRunning、applyProfile 或 startListener。
SetupAction 通过 ServiceState 的 expectedRevision recovery initializer 和最新快照同步状态，拒绝
时不覆盖新意图。
runtime 的迟到值核对 processEpoch／revision；既有 started／preparing 和新的 Tile／通知操作由原有所有者继续处
理。

阶段写入完成后，Bootstrap 在显示提示、连接 Core 或初始化状态前复核会话。
恢复的非 started 观察，以及 runtime 查询成功／失败的清理，只能作用于
NativeRequestStateProvider 仍接受的同 epoch/revision/phase，旧观察不清除新运行时。

正常自动维护不属于恢复配置重放：

- stopped／failed／paused／preparing 不进入新自动刷新；候选、下载、post/apply 复用 T06 自动资格和 Request
  ／ConfigInput 所有权。
- 已有合法 started，即使 boot record 不可用，也按订阅开关、到期时间和接受的 RequestMode 正常刷新，并可应用新材料。
- 自动 post 的资格检查须容许本次合法 ConfigInput apply 自己的转换，拒绝外部停止／失败或旧 client/source；手动刷新沿原有
  资格。
- BootGuard 不授予网络权限，record revoke 不代表已撤销网络 IO。Request 的 client、来源、运行状态和 detach 决
  定请求是否仍可执行／提交。

## 覆盖边界

guard 从 migration 读取配置之后开始，不完整覆盖更早 Rust／system／migration 故障。
磁盘断电持久性、设备 ApplicationExitInfo 可用性和 Activity 重建需要设备验收。
新报告保存及用户清理顺序在报告能力接入时复验；本项不能证明跨启动 dump 已保存。
