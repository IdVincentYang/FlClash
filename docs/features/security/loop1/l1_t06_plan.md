# L1-T06：订阅刷新与失败处理

本项保留订阅自动/手动刷新、逐订阅开关、周期及已接受的 Auto/代理/直连选择，解决旧队列越过用户修改、重复触发、无界下载及保存/应用结果混淆。design_v2 已获 M1 通过；implementation_v2 已通过实现评审，I1–I4 全部关闭。本文保留设计基线的事实、方案与拟验收，实际结果及本地交付见[验证记录](l1_t06_result.md)；design_v1 与 implementation_v1 的未通过冻结记录保留。

归属与授权见[任务入口](loop1_tasks.md#l1-t06-修改订阅刷新与失败处理)。设计基线为父仓库 `cf66e036eb0e5e7a896e2c814cbb4e6062fbaf3e`、Core `6c6e3e472bb246cc55f2e8577d9eddccc2623afc`。共同目标沿[安全要求](../security_requirements.md)、[Loop 1](loop1_plan.md)；请求与应用机制复用 [L1-T03](l1_t03_plan.md)、[T01](../loop2/l2_t01_plan.md) 和 [L2-T02-03](../loop2/l2_t02_03_result.md)。后者已结束，不重开交付。

## 1. 范围、依赖和用户结果

用户于 2026-10-18 授权先交设计，经 M1 通过后连续实施、自验、实现交评、本地合入 `security/android` 和清理。L1-T03 已交付；暂缓的 L1-T04/05 不作为本项整体前置，也不据此声称身份、跳转或全面日志脱敏已完成。

| 场景 | 拟达到的结果 |
| --- | --- |
| 正常自动刷新 | 按当前开关和周期执行，保留既有出口选择，不逐次确认 |
| 批次排队时删除、停用或改周期 | 请求登记前重验，取消失去资格项；删除项不重新插入 |
| 多处唤醒或手动重复点击 | 仅合并来源与约束兼容的请求；新来源的手动意图独立保留，自动触发不取消它 |
| Setup(A) 等材料而 B 保存后要重建 A | 材料可先完成/失败，应用或条件清理不能阻塞 A 所需材料 |
| standard/script 留有休眠 custom use B | 刷新 B 不因此重建 A；按已登记的实际输入来源决定影响 |
| 慢、大、中断或无效正文 | 有界失败、释放网络和临时文件，其他订阅继续；旧材料不变 |
| 正文有效、统计头损坏 | 接受正文，损坏的可选统计项为未知，不拖垮刷新 |
| 下载成功而应用失败/被取代 | 显示材料已保存，并区分实际应用失败、保留旧输入或较新输入接管 |
| 停止/SSID 暂停、切换、删除或恢复 | 保留已有运行意图和来源约束；旧失败不清理较新 Owner/run |
| 受管 Profile 刷新 | 只更新原材料，不改变已选 policy；必要重建仍消费原选择副本 |

不实施 L1-T04 全量 TLS/认证/重定向整改、L1-T05 全面日志脱敏、L2-T02-04 的受管材料冻结/节点协议/集合/Geo 更新。新路径不记录完整 URL、响应体、凭据或原始异常。Android 常驻、精确定时、Doze 豁免和新增后台权限不在范围内；Dart 未运行时不承诺继续刷新。

## 2. 已核实的源码事实

以下为 design_v2 基线的静态核查，不代表交付版本仍存在这些问题，也不代替运行验证结果。

| 入口 | 设计基线事实与影响 |
| --- | --- |
| [ProfilesAction](../../../../lib/providers/actions/profiles.dart) | 自动批次先取旧列表；`updateProfile` 缺行回退传入对象，缺行也可通过来源检查，保存又 upsert，不能区分新增导入与已有刷新 |
| [bootstrap](../../../../lib/bootstrap.dart)、[Application](../../../../lib/application.dart)、[Request](../../../../lib/common/request.dart) | 启动、20 分钟 timer、native started 与手动入口各自触发；同 key 的 `begin` 会取消前 session，没有刷新业务合并/退避 |
| [编辑周期](../../../../lib/views/profiles/edit.dart) | validator 只检查可解析整数，0 能进入总到期路径；默认周期在 constant 中为一天 |
| [下载与临时文件](../../../../lib/common/request.dart)、[RequestFile](../../../../lib/common/request_file.dart) | bytes response 整包进内存后再 stage；没有订阅总 deadline/实际字节上限；replace 已有文件回退和 partial-commit 机制 |
| [保存](../../../../lib/providers/actions/profiles.dart)、[Profiles.persist](../../../../lib/providers/database.dart) | 文件/DB 先写，之后来源失效仍可能抛错；DB 写入与列表发布也须按提交阶段区分 |
| [SetupAction](../../../../lib/providers/actions/setup.dart) | 下载 session 的 `lifecycleCurrent` 固定旧 revision/Owner；`result.succeeded` 后仍检查它，可能漏掉本次成功后的 MD5、groups 和 providers 同步 |
| [SubscriptionInfo](../../../../lib/models/profile.dart) | `split('=')[1]` 可因空段或尾分号抛错；该可选头在文件替换前解析，能拒绝有效正文 |

`Request.configSourceCurrent` 已能只核对 client/dataset/来源版本而不绑定 Owner；`sourceCurrent` 则含 native revision/Owner/operation。两者不能混用。已有有限提交、文件补偿、ConfigInput 来源票据、Setup 串行 generation 和原身份条件失败足够承载本项，不另建运行许可或持久任务库。

## 3. 调度与任务资格

### 3.1. 选择与职责

| 方式 | 取舍 |
| --- | --- |
| 各入口继续扫描，靠 Request 同 key 取消 | 无法表达排队资格、合并及退避，不采用 |
| ProfilesAction 内有限队列、按来源资格合并和一个唤醒 timer | 采用；只协调刷新，运行/网络资格仍归原权威 |
| 通用调度框架、持久 job 表或多个并行下载 worker | 当前不需要；增加状态、恢复和资源成本，且配置切换会撤销其他旧 Owner 的请求 |

由 keepAlive 的 ProfilesAction 持有按 profile ID 分组的材料任务、优先队列、退避记录和一个可释放 timer。单材料 worker 只持有下载、校验、有限提交和不依赖 Setup 的文件/DB补偿，不持槽等待应用或条件清理。普通后继的网络阶段最多 90 秒；手动批次转为队列调度，显示等待/进行中，不保存 URL/正文副本作为权威。

启动、native started、前台恢复/解除暂停、DB/订阅设置变化和 timer 都只向该入口发 wake。移除 Application 的独立递归 timer；Request 的 started 路径只发 wake。重复 wake 合并，失败按项隔离。

材料处理与 Setup 收尾采用以下固定顺序，成功和失败相同：

| 步骤 | 槽位/Future 的推进 |
| --- | --- |
| 1. 形成材料结果 | 文件/DB结果或本地回退已知；必要恢复标记已保留，不等待 Setup/条件清理 |
| 2. 登记后处理，再释放槽 | 同步登记 pending apply/cleanup（若需要），完成 material Future 并释放材料槽，随后才调度后处理 |
| 3. 应用或条件收尾 | receipt 外交给既有 Setup 串行/延后清理入口；application Future 等其最终结果，material Future 不依赖它 |
| 4. 推进后继 | 普通 auto/manual 在 Setup 执行或后处理 pending 时等待；现有 Setup 自身的 ensureFile 材料请求可受限越过此门 |

Setup 的执行/完成通知只投影已有串行任务生命周期，不是运行许可或第二个 Setup 队列。`ensureFile` 通过窄的内部 require-material 入口申请高优先材料；它可提升同资格的排队任务，或提交当前仍有效的新材料请求，仍受单 worker、来源/DB和 Request 网络许可约束。过期 Setup 的材料请求及时以取消完成，不等较新 Setup 执行才通知它。优先级不授予额外网络权限。

这也防止普通下一项在本次 reapply 时反复取得旧 Owner 又被撤销：普通项等既有 Setup/后处理完成；仅为解除 Setup 材料等待允许上述受限接续。ensureFile 成功由所属 Setup 继续应用，不再为同一材料重复 enqueue 一个自等应用；外部等待者的最终应用结果与材料结果分开。

R1 交错的具体出口：B 的材料成功或失败后先完成自身 material Future、释放槽，再排 A 的重建或原身份条件清理；旧 Setup(A) 正等的 ensureFile(A) 越过普通等待门取得材料或及时失败，使旧 Setup 退出，之后排队的重建/清理可完成。Core 清理 pending 时不宣称业务已关闭，material 失败的通知也不能以等清理为前置条件。

### 3.2. 按资格合并与手动优先

ID 仅分组，不是合并充分条件。材料资格包含 target 类型、client/dataset、profile 材料版本、URL/出口/auto/周期等已接受字段，以及显式 expectedSource 的有无和完整约束。材料版本与请求取消 generation 分开比较：native sourceRevision/dataset 与 DB 字段不得混成 ID 等价，自己的 begin 取消推进只由本次登记证明解释。同 ID 不允许并行材料任务；旧任务的 application Future 可以仍在收尾，而新的、来源不同的材料任务按本节及受限接续规则排队。

- 排队阶段只合并同来源/dataset/字段及兼容约束的请求，auto 可提升为 manual；不同显式票据不能因 ID 相同而共享成功结果。
- 下载/校验中的合并还要求真实 session 的本次登记仍有效。使用 Request 保存的 post-cancel generation/实际 grant 验证其存活，不把自己的 cancelKey 当作外部来源修改。显式请求只能与同一已接受约束的在途工作共用，不能用普通材料资格代替原 native 意图条件。
- 兼容的在途 manual 不被后来 auto 取消；manual 接续 auto 时仍只在提交前取消旧下载、清理旧文件再开始，不移交旧字节或许可。
- 一旦进入有限提交或应用，新 manual 保留为独立接续，不以旧结果满足新点击；同资格的接续可合并。每 ID 至多保留一个当前有效的新手动接续；S3 取代已经失效的 S2 时，S2 等待者得到 superseded，而不是被悄悄转交给 S3。
- URL/出口、来源或 dataset 已变化时，旧可取消任务关闭；旧有限提交不可打断。新手动接续带自己的来源/expectedSource，独立于 auto 开关、到期与自动退避；后续 auto wake 不得覆盖或清掉它。
- 旧等待者保留自己的 materialSaved 与应用结果；新等待者只收到新资格工作或其明确取消/失败，不能把 S1 的已保存当作 S2 成功。
- require-material 与普通 UI 的应用等待语义不同：只在材料资格兼容时共用材料结果，不能令 Setup 等外部 application Future；不兼容时按当前来源产生高优先材料接续。
- manual 排在普通 auto 前面，不抢占另一个 ID 已开始下载；加载指示由实际 job 的 UpdatingKeys operation token start/stop，合并等待者不各自清掉状态。
- dispose 取消 timer、排队材料和可取消 session并通知等待者；已获准的有限提交按原机制收尾，不能 dispose 后继续读写 ref。

R2 的 S1/S2 场景：auto=false 的 S1 已提交，用户保存新 URL/出口并带 S2 expectedSource 请求手动刷新；S2 必须单独保留，在旧提交/收尾后按 S2 条件登记，不能依赖自动 wake。若之后真实 native 意图改变使 S2 显式票据过期，应明确拒绝且零请求；不能为“保证刷新”放宽该票据。

### 3.3. 两次资格核对与导入分离

1. 排队只登记 ID、触发类型和既有 RequestSource/显式 expectedSource；在当前 DB 确认记录后捕获来源。旧批次保存的是有限工作意图，不是日后仍可访问旧 URL 的许可。
2. 真正 dispatch 重新查 DB：必须存在、仍是 URL 类型；auto 还须启用、已到期且通过退避门。更改周期/关闭/删除/restore 后原排队来源或 dataset 失效，取消旧项，由后续新 wake 重新判断。
3. `Request.begin` 的登记回调在现有 dataMutations/receipt 内再次核对该行、URL/模式/目标/auto/周期/lastUpdateDate 以及排队材料资格；回调不直接对被本次 cancelKey 推进的旧本地 token 调 configSourceCurrent，具体接缝见下节。已有刷新绝不接受 previous/current 均缺失。
4. 排队来源只约束材料来源/dataset；网络还未开始时，可以由真正 begin 按当前有效 Core/run 发放新请求身份。不得给已经下载的旧结果重新 begin 换票。A 正常应用改变 Owner 不应使尚未开始的 B 永久失去刷新资格。
5. 每项结束或失效后按当前 DB 重算后继与最早 timer，丢弃旧票据，不反复重排同一个过期 closure。网络进行中，编辑、停止、暂停、删除和恢复仍消费现有 cancel/session/来源规则；提交时再次查行并更新当前记录的网络结果字段，不覆盖较新的 picks、标签或其它设置。

新增 URL 导入使用明确的 import target，只有此路径可在预期仍无该 ID 时插入；碰到同 ID 新记录则冲突。已有手动/自动刷新、编辑后刷新和 ensureFile 使用 existing target，只能更新存活行，不用 upsert 恢复删除项。编辑先保存用户选择，再使用其 expectedSource 刷新；新导入继续沿原首次恢复/出口确认，不自动选择 Profile 或启动。

#### 3.3.1. Request.begin 的两类输入与自失效边界

当前 begin 先 cancelKey，再在登记回调核资格。保留该取消与 native begin 权威，但区分两类互斥输入，不加入泛化的“忽略 Owner”开关：

| 请求类型 | begin 前及登记时的核对 |
| --- | --- |
| 普通排队材料（queuedMaterialSource） | cancelKey 前核对原本地来源、client/dataset；同步推进自己的取消 generation，登记时验证该 post-cancel generation 未再变化、相同 client/dataset/native sourceRevision，并重查 DB。网络 Owner/run 使用这次 begin 的当前权威发放 |
| 编辑确认的显式 expectedSource | 保留原本地预检及两次完整 native 约束，包括 processEpoch/revision、Owner、dataset、sourceRevision、operation；不降为普通材料来源，不重采新 Owner 使过期显式操作继续 |

post-cancel generation 来自 Request 自身现有计数，并作为本次 session 登记证明只读保存；不修改旧 RequestSource，不给它机械加一，也不让后续 callback 再检查一个已被自身取消的本地 token。DB callback 只核冻结字段/行资格；普通材料的来源证明由 begin 按上述阶段校验。共同本地/DB登记检查须覆盖非 native 路径，不能沿现有 desktop early return 跳过；native 再加原 Core grant。

普通 B 的源未变时，A 合法应用造成 Owner/revision 改变不阻止尚未联网的 B 取得当前许可；相同情形若 B 携显式旧 expectedSource，则必须按原约束失败。两者分别拟验收，不能靠放松同一个谓词通过。

### 3.4. 周期与重试

- UI 只接受正整数分钟；保留所有正常正周期与一天默认。旧的非正周期仅在运行调度时按一天解释，不静默改写 DB；编辑保存时需修正非法值并显示原因。历史正值即使短于一分钟也受最小自动尝试间隔约束，不静默重写。
- 自动实际尝试最小间隔为 1 分钟。下载/校验/保存失败后使用 `min(20分钟, 1分钟 × 2^(n−1))`，指数封顶以避免溢出，即 1/2/4/8/16/20 分钟；n 是同一来源连续失败次数。这是本项工程策略，不是上游保证。
- 成功保存更新 lastUpdateDate 并清空下载失败计数；应用失败不能立刻再次下载已保存的同一材料。手动可绕过自动退避，但仍通过来源和网络许可。
- 用户取消、删除、暂停或来源过期不算网络故障；实际发起过请求仍受最小自动间隔约束。未取得许可的自动项等待可恢复事件，不用到期为零的 timer 自旋。
- 周期使用持久 lastUpdateDate 与当前时间；退避/最小间隔用单调经过时间。单一 timer 取最近候选，长等待最多每 20 分钟重算，兼顾时钟变化；started/wake 不重置门限。
- 内存退避随 provider/进程结束清理；重启按已有成功时间判断，不承诺持久失败重试次数。Android 暂停或进程不在时不作准时保证。

## 4. 有界下载与可选统计

采用 HTTP 流写入 RequestFile 临时文件，不再先累计整包 Uint8List。订阅限制初值为 **90 秒 HTTP 总时限、16 MiB 实际写入文件上限**；单 worker 约束同时解析/下载的材料数。这是为未受限路径建立有限资源预算的工程取舍，没有真实订阅样本支持“所有合法订阅都小于该值”的结论。超限或过慢会明确失败并保留旧材料，阈值集中维护，不加入新配置系统。

- 时限从实际 HTTP 发起前开始，覆盖连接/响应头/全部正文，不因持续分块而续期；等待用户原有 bootstrap 确认不计作 HTTP 超时。
- 以实际流入临时文件的解压后字节累计，Content-Length 只能提前拒绝，不能决定唯一上限；无长度、虚假长度、chunked、gzip 均要验收。
- 超时、超限、取消、流中断或写盘失败须取消 stream subscription、CancelToken 和本 session/所属 HttpClient，删除未提交的临时文件；只用 Future.timeout 返回而放任后台继续下载不合格。
- 沿原 request route/TLS/redirect 配置，不扩大接收方或切换出口；代理失败不回退直连。共享 bytes helper 的两个订阅消费者纳入调用清单：ProfilesAction 走流式临时文件；保留的 Profile.update 也应接入同一有界 primitive，不留无界订阅旁路。不改变 WebDAV、Geo 等其它业务的下载限额。
- 正文校验复用当前 Core validator，不把可选统计头当正文校验条件。本项不宣称解决所有恶意 YAML 解析复杂度或 Loop 2 内容信任问题。

统计头解析限定已知 upload/download/total/expire，空段、尾分号、无等号、额外等号、未知键、负数、溢出和越界日期均不抛到正文流程。只接受安全可显示的非负整数，未知项沿既有 0 语义；重复项采用首个合法值。头值超过 8 KiB 或超过 32 段时视为统计未知，正文继续校验；不把旧统计冒充本次有效统计，不新增持久统计状态。

## 5. 文件、DB 与失效失败

保持 download → 临时文件 → Core 校验 → 有限提交的边界。提交前捕获原 ConfigFailureObservation；在同一 receipt 中重验资格，再先撤销 profile 来源，然后替换文件/持久化，避免新材料已提交后才首次尝试失效。

刷新网络结果持久化使用窄的 existing-only UPDATE：从当前行合并本次 lastUpdateDate、统计等网络结果，保留当前 label/picks/设置；Content-Disposition 只供新导入填充空标签，已有刷新不借服务器头改变依赖名称，标签去重继续复用既有规则。文件 replace 的 persist 回调覆盖真实 DB 事务提交；列表 provider 发布在文件/DB 成功后进行。不能将“DB 已提交后的列表发布异常”伪装成 DB 未提交，再仅回退文件，造成两者不一致。正常用户编辑的 persist 仍沿原所有权，不为复用引入通用事务框架。

| 失败阶段 | 原材料/运行与处理 |
| --- | --- |
| 资格、下载或正文校验失败 | 未撤销来源；旧文件/DB 不动，按固定分类报告；可选头本身不拒绝正文 |
| 来源失效抛错、尚未写文件 | 不提交新材料；用失效前原 fact/run/token 在 receipt 外条件收敛；不能假定旧业务仍合格 |
| 文件替换或 DB 事务失败 | 原 RequestFile 回退与真实 DB 回滚；来源版本不回滚；随后原身份条件清理 |
| 文件/DB 补偿失败或提交状态不确定 | 保留临时证据与 partial-commit/recovery-required，阻止后续自动工作，固定错误不含秘密 |
| 已保存后的 provider 发布/应用调度失败 | 记录材料已保存，不撤销已提交文件；重读 DB 恢复投影，必要条件清理，不报成下载未保存 |
| 原身份 cleanupFailed/恢复状态不明 | 保留恢复标记并显示需恢复，不清标记伪装成功 |

共享提交 primitive 的 complete 回执异常也按真实阶段处理：材料已提交时不伪装下载失败或仅回退文件，恢复标记须覆盖最终 ack。该异常在原 receipt/所属 ID 的收尾中处理，不能退出后再等待自己的未决 commit；不新增协议或提交权威。

条件收敛复用 Setup 原观察、串行/延后清理入口及 failConfigBuild 的 retained/blocked/superseded。已有较新 setup 时在队列锁外衔接其处理，再按原身份收尾，不从失败时的新 fact 采样清理目标，不无条件 setRunning(false)，不复活旧版本。若需判断非当前订阅的影响时，使用下述实际来源过滤；来源未影响当前输入则保持它，不因候选引用重建或盲停业务。

### 5.1. 候选引用与实际输入来源

providerUsers/profilesReferencing 是保存的 custom use 候选，包含 standard/script 下的休眠数据，不能作为 reapply 判据。候选至多用于定位，没必要为刷新遍历所有 Profile。判定使用捕获的 Core fact 所对应的已接受 ConfigInput 来源合同：

- 从该 fact 的 inputId 定位不可变 `config-inputs/<id>.json`，在现有 ConfigInput 边界补只读的校验投影：manifest 字节的 SHA-256 必须等于 inputId，version 使用既有 schema 1、profileId 等于 fact.profileId、dependencies 为合法来源 key 列表；只读取该 manifest，不解析 YAML 猜依赖。复用 Core 的 4 MiB manifest 读取边界，不扫描其它旧对象、不新建依赖表或缓存、不扩 Core 协议。
- 只投影与原 runtimeEpoch/Owner/token/inputId 绑定的来源；在失效/决定后处理前再核身份仍匹配，不能用另一个配置的依赖集解释当前输入。manifest 缺失/损坏是未知，不当作空集合或盲用候选图；对原身份走条件收敛并明确报告，retained 不改 Owner，blocked 不碰较新输入。
- 刷新当前目标本身按原第 6 节衔接。对非当前 B，仅当实际接受的同一当前 Profile A 的 dependencies 包含 `profile:B` 才请求 A 重建；已接受 Profile 与当前选择已不同则不重建旧 Profile，衔接已有切换，并按原身份收尾。
- standard/script A 的休眠 custom use B 不在其 Setup 源集合中，因此 B 刷新不 apply A、不更换 Owner；实际 custom 注入 B 且已登记 `profile:B` 则是正例。来源登记沿现有 getProfile 注入分支和 _setupConfig keys 规则，不从 DB 的任何 use 推导实际消费。
- 受管模式沿已登记来源合同：若既有 custom 源仍登记 B，必要重建只消费原 selected policy；若未登记 B，不因存档 use 触发。不会导入 B 的新节点/规则/DNS或恢复原订阅闭包，也不解析任意脚本/裸文件路径新建依赖图。

## 6. 从材料保存到实际应用

| 阶段 | 有效性依据 | 完成含义 |
| --- | --- | --- |
| 下载/提交 | 原 RequestSession、来源/operation、有限 receipt | 旧响应不能换新票据；保存前可取消 |
| 已保存、尚未提交 ConfigInput | receipt 内捕获的保存后来源/dataset、原用户运行意图及目标 ID | 文件/DB 已提交，不等于生效 |
| 构建/提交前 | 现有 Setup generation、来源检查和 ConfigInput 原票据 | 用户停止/切换/来源变化可取代，不制造 start |
| 本次返回 activated/installedInactive | 本次 inputId/receipt token/Owner/runtimeEpoch，与当前 Core 同一身份；来源、dataset、目标及原 intent 仍合格 | 允许自身 Owner/服务 phase/revision 更新，不能继续要求下载旧 Owner/完整 revision |
| 完成同步 | 仅当前 Setup generation，消费同一本次接受事实 | 更新 MD5、实际 groups/providers；较新结果不被旧投影覆盖 |

保存后来源可用既有 configSourceCurrent 检查，不把旧下载完整 native revision/Owner 贯穿 setup。运行约束比较 processEpoch、intentRevision、intentRunning、paused；它们区别用户新停止/重启与本次服务 phase 更新。后置身份只能与本次 apply 返回 receipt 比较，不能把 freshly sampled Owner 当作自己；必要 fresh fact 仅用于验证是否仍是本次身份，失败清理始终用原观察。

保留 Setup 串行 generation、T01 source/fact fences、一次 stale 重捕获及 ServiceState 所属资源清理。对 activated 后才发生的取代，结果应为“已保存，应用已被取代/实际状态以当前事实为准”，不能说配置必未生效或必断网。

刷新结果分别表达 materialSaved 与 application outcome（不涉及当前输入、queued、activated、installedInactive、retained、blocked、superseded、failed）。这是内存操作结果，不是第二套 Core 状态；界面真实运行状态仍看 ConfigState。用户文案只表达“已保存/未应用/仍用旧配置/被较新操作取代”等结果，不把 Owner/token 等实现字段加入产品流程。现有 bool apply API 可保留适配，新增窄的返回结果入口供刷新消费，不另立通用运行框架。

ensureFile 仅等待材料 Future，同时以内部材料需求越过普通等待门；该 Future 的成功/失败都先于 Setup 后处理。材料槽不等待应用、条件清理或所属 Setup 结束，原 Setup 继续构建/失败退出；外部最终等待者可等 application Future，但不能反向成为材料完成的条件。所有 Setup 后处理在 dataMutations 退出后进入，按第 3.1 节跨 ID 时序验收。

## 7. 拟修改范围与验证

预计涉及 ProfilesAction 及其私有协调单元、Application/bootstrap/Request 的 wake 接入、Request/RequestFile 流式资源边界、Profiles notifier/DAO 的网络结果提交、Setup 应用完成结果、Profile 统计解析、ConfigInput 已接受来源的只读投影和周期编辑/刷新反馈。需要变更 provider/model 时正常生成，新增文案进入 en/zh_CN/ja/ru。不修改 mihomo、gitlink、carrier 或 Android 后台权限。

以下均为拟验收；不得把本表当作通过记录。

| 编号 | 正常/失败/并发条件 | 真实消费者与观察 |
| --- | --- | --- |
| T1 | A hold，队列 B 被删/关闭/改周期/改 URL/变 file | 真实 SQLite、协调队列、Request.begin；B 无过期请求、无复活 |
| T2 | UI 旧对象刷新已删行；新导入 ID 冲突 | existing-only UPDATE 与显式 import；无隐式 upsert |
| T3 | 多 wake、同资格重复 manual、auto/manual 交错及不兼容约束 | 实际协调器与 Request 登记；只合并兼容任务，同 ID 不并行，auto 不取消 manual |
| T4 | 0/负旧周期、正常周期、失败退避、频繁 started、时钟跳变 | 注入时钟驱动实际调度器；无零 timer/请求应用反馈环，不用真实长 sleep |
| T5 | 停止/SSID暂停/运行恢复、provider dispose | 既有 Request/native/JVM seam、队列与 timer 释放；自动零流量，手动保持已交付许可 |
| T6 | 慢头、持续慢流、断流、缺/假 Content-Length、chunked、gzip 膨胀 | loopback HTTP＋真实 Request/文件；总期限和实际字节上限、连接/临时文件收尾 |
| T7 | 有效正文与坏/重复/超长/溢出统计头；坏正文 | 实际 Core validator、DB/文件与统计 widget；统计不阻断正文，坏正文保旧 |
| T8 | 文件/DB/发布/补偿失败，ack 释放前失败与释放后丢失 | RequestSession.commit 与 localCommit 两个真实入口；DB/文件一致，标记覆盖 ack，不在退出 receipt 后等自己的 commit |
| T9 | 来源失效的 checkpoint IO 失败；新 Owner/run 抢先 | 真实 Dart→Go 条件失败消费者；旧 ineligible 入口关闭，新资源不被旧失败关闭 |
| T10 | 真实刷新→ConfigInput→prepare/install/activate 自换 Owner | loopback正文、真实 Core/T01＋native bridge；MD5/groups/providers 完成同步，不因旧下载身份误拒 |
| T11 | apply 前/中/后停止、切换、删行、restore dataset 或新请求 | 原票据/fence/Setup generation；迟到结果不盖新状态，已保存与已应用分别断言 |
| T12 | 保存成功但 setup retained/blocked/superseded；inactive 成功 | 操作结果与实际 ConfigState/UI；无隐式 start，不以重下载掩盖应用失败 |
| T13 | standard/script A 存休眠 use B；实际 custom 注入 B；受管的登记/未登记 B | 真实 SetupState、ConfigInput manifest与 Core；休眠零 apply/Owner变更，实际登记应 apply，selected policy不变；缺/坏 manifest不作空集合 |
| T14 | Setup(A) 先占队列等缺文件，worker B 为 A 的实际 provider；B 保存成功或失效后失败/需条件收尾 | 真实跨 ID 协调、provider来源、Setup与Request；B先释放材料槽/Future，A取得高优先材料或及时失败，旧Setup退出后重建/清理结束；无互等 |
| T15 | Auto/固定代理/Direct、代理拒绝和取消、首次导入恢复确认 | 复用 T03 独立 loopback 收件；代理故障零直连回退，正常自动不弹框 |
| T16 | 包含合成 token/用户密码的 URL、头与异常 | 新结果/日志/显示不暴露合成秘密；不据此宣称全面日志/TLS整改完成 |
| T17 | auto=false，S1提交/应用中编辑URL或出口并显式触发S2；另加S3/restore与旧等待者 | 真EditProfile保存/expectedSource、协调器、SQLite/HTTP；S2有效则独立请求、等待者结果分离，失效接续明确superseded，auto wake不能吃掉manual |
| T18 | 普通B排队后A换Owner；begin自身cancelKey；显式旧票据B | 实际Request.begin两类输入：普通B来源未变可登记且不自失效；真正外部修改/显式旧native约束均拒绝，不把旧响应换票 |

实施阶段按影响执行正常依赖解析、生成、格式、分析及相关 Flutter/Go/JVM/真实桥接测试，并重新绑定 Android ARM64 制品。复用未变 T03/T01/03 证据，不把它们作为 T06 已通过。既有 service_status/update_dialog 基线失败继续分列，是否受本项影响以实际差异核对。

设计阶段仅分析与编辑本设计、任务入口。通过设计后才进行合成 DB/文件/SharedPreferences、loopback HTTP/代理/DNS与 Core 消费者验证；不访问真实订阅、真实用户数据/凭据，不安装/启动用户应用，不改变宿主网络，不上传或 push。此段保留设计阶段的授权边界；获审/最终源码、实际制品、验证结果与限制见[本项验证记录](l1_t06_result.md)。
