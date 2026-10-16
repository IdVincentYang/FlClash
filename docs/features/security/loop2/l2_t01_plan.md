# L2-T01：最终配置与应用失败时的业务出口

第三份整项设计及控制器补充、完整实现均已获 M 通过，R1–R4 与 I1–I8 已关闭。当前进行已授权的本地收尾与集成，验证和最终交付对应见[验证记录](l2_t01_result.md)。按实际替换边界处理失败：尚未进入 Core 替换时保留真正仍在运行的旧配置；进入替换后失败则暂停本应用业务处理、关闭其入口，不安装默认路由配置。合法 DIRECT 和接受的代理在成功配置中保持原语义。

依据：[Loop 2](loop2_plan.md)、[L2-T01](loop2_tasks.md#l2-t01-最终配置与应用失败时的业务出口)、[共同安全目标](../security_requirements.md)。M 为 Codex，D 为 D-02；父基线 `6c0dbde0aedb9f4fedde3fad9fa0ccbc0a1ff586`，实施分支 `security/l2-t01-config-apply`，复用共享主 checkout。核心从已审 `2b8c0e2e7e437efa9382016765c26883bcdcded4` 起步，起点工作区干净；本项更新完整累积载体，当前绑定见 Result。L1-T03 已结束，L1-T04 仍暂缓，其它 L2 任务未启动。

## 设计评审与补充范围

M 已通过第三份整项设计，包括下面两处冷恢复合同。第一、二份设计原文及绑定保存在本地 design 目录，不改写原反例结果；实现结果另由 Result 记录。

| 项目 | 当前设计状态 | 本轮入口 |
| --- | --- | --- |
| R1–R3 | 已获 M 设计复审关闭 | [业务范围](#普通业务范围与最终开放r1)、[Android 流程](#android-清理完成与新-start-恢复r2)、[输入身份](#不可变输入接收与结果r3)沿用 |
| R4-a | 已获 M 通过：实际服务参数绑定候选输入和真实 mixed 资源，独立 desired 设置保留 | [服务准备参数](#服务准备参数与实际输入r4-a) |
| R4-b | 已获 M 通过：来源撤销与恢复引用最终发布同序，旧快照不得复活 | [恢复引用发布](#来源撤销与恢复引用发布r4-b) |

## 已确认的生产反例

本地设计夹具实际调用 `handleSetupConfig → applyConfig → hub.ApplyConfig`，在应用配置创建的真实 mixed 监听完成 SOCKS5 greeting，先验证代理和合法 DIRECT，再故意让该已接收连接等到配置失败后才发 CONNECT/HTTP。假 HTTP 代理仅为本地受保护目标返回 `viaProxy`，不转发到目标；目标自己记录任何直接到达的请求。所有端点随机绑定 IPv4 loopback，DNS/NTP/TUN/外部 controller 均关闭，无真实订阅、系统代理或设备操作。

| 最终文件输入 | Core 报告错误 | 正常代理连接 | 合法 DIRECT 请求 | 失败后未接受的直连 |
| --- | --- | --- | --- | --- |
| 坏 YAML `proxies: [` | 是 | 1 | 1 | 1，目标返回 `UNACCEPTED DIRECT` |
| 缺文件 | 是 | 1 | 1 | 1，同上 |
| 空文件 | 否，误报成功 | 1 | 1 | 1，同上 |

失败后默认 mixed 监听端口虽已变为 0，之前已接收、尚在等待协议请求的连接仍进入默认 Rule/空规则，命中无规则时的 DIRECT。因此仅检查监听是否关闭、`isRunning` 或错误字符串不能证明安全。Android TUN 走同一普通业务路由，但本次没有启动 TUN，不能将夹具称为真实设备泄漏。

复现材料在本地忽略目录 [design](../../../../build/verification/l2-t01/design/probe_results.json)：Go overlay 只添加测试文件，没有修改工作源码；逐项参数及摘要由该 JSON 保存，夹具为同目录 `business_failure_probe_test.go`，原始输出分别为 `invalid-yaml.log`、`missing.log`、`empty.log`。三个独立 `go test -race` 进程均因上述安全断言按预期 exit 1，未报告 race。

最初把三种输入放在同一测试进程，还暴露 mihomo 原有 `log.SetLevel` 与 GC adapter 终结器 `log.print` 的数据竞争，原始 `business_failure_probe.log` 保留。随后按输入独立运行隔离该继承问题，不通过更改日志实现或关闭 race 检测来隐藏；本任务不顺带修上游日志系统。

## 修改前的最终配置地图与优先级

| 边界 | 修改前的生产行为与优先级 | 本项约束 |
| --- | --- | --- |
| 原始输入 | [getProfile](../../../../lib/providers/actions/setup.dart) 经 Core `getConfig(profileId)` 读取本地订阅/配置 YAML；原始字节由 [handleGetConfig](../../../../core/hub.go) 解码 | 缺失、空文档、解析错误不得变为“可用默认配置” |
| 脚本/覆写选择 | `OverwriteType.script` 先执行所选脚本；standard 提供前置 addedRules；custom 提供规则、节点和分组。三种分支不叠加运行 | 先解释真实选择，不新增脚本引擎/来源接受交互 |
| 应用合成 | [_makeRealProfileTask](../../../../lib/common/task.dart) 在脚本结果上覆盖应用端口、模式、认证、TUN、IPv6、日志、controller、Geo 等字段；认证清空 skip-auth；provider 文件路径收敛到受控目录 | 保留既有应用策略优先级，不能用脚本失败生成空输入 |
| 规则/节点 | custom 非空规则替换原 rules；否则标准 addedRules 前置于原 rules，MATCH 占位按现有 matchTarget/原 MATCH 展开；custom 非空节点/组替换相应列表，注入 provider 仍由原同名定义优先 | 不重排已接受的 DIRECT/代理规则 |
| DNS/NTP/安全模式 | 无启用 DNS 时合并 baseline；指定覆写键覆盖，system DNS 按设置追加；NTP 按覆写键合并；safeMode 清理其已定义的接管/监听能力 | 仅记录本项输入事实，全链 DNS 由 L2-T02 核实 |
| 最终文件 | `_setupConfig` 经 dataMutations，暂存写入并 rename 为 `config.yaml`；当前合成失败使用空字符串，仍调用 setupConfig | 修正合成失败控制流；desired 文件/选择不等于已生效配置 |
| Core 替换 | [applyConfig](../../../../core/common.go) 在 configMu 中先 `newOwner`，再 load；失败仍装默认；随后关闭旧 provider、安装 cfg、选组、更新监听和 Geo | 移除默认回退；明确替换失败后的业务门、资源与结果 |
| 实际连接 | [tunnel](../../../../core/Clash.Meta/tunnel/tunnel.go) 的 Suspend/Inner/Running 管理普通入口；内层加载可服务 C.INNER；无匹配可按接受配置使用 DIRECT | 失败时用 Suspend 阻断普通 TCP/UDP，不只关闭 listener accept |
| 状态消费 | Dart `_setupScheduler`/`_listenerScheduler`、Core configMu、Android [ServiceState](../../../../android/app/src/main/kotlin/com/follow/clash/ServiceStateMachine.kt) 分别拥有其现有职责 | 不建立第二位启停仲裁者；展示实际已应用、保留或阻断结果 |

修改前的 `loadConfig` 用 `os.ReadFile → executor.ParseWithBytes`，没有 `executor.readConfig` 的空字节拒绝；`config.UnmarshalRawConfig` 先放入 DefaultRawConfig 再解码 YAML，空输入会保留默认。原始读取、验证和最终应用需要共享相同的非空文档判据，而非只在 UI 检查长度。

## 候选与推荐

| 候选 | 优点 | 实际代价/不足 | 决定 |
| --- | --- | --- | --- |
| 所有失败都保留 currentConfig 指针 | 表面上不断流 | `newOwner` 已使原 owner/范围失效；解析有临时全局设置，旧 provider 会被关闭；指针不能复原 provider/context/监听/状态。完整候选配置事务还需改变核心解析及 owner 模型 | 不采用 |
| 任意失败都停止服务 | 规则简单，易于证明没有默认放行 | 合成尚未触碰 Core 时也破坏真正可用的旧配置，增加无必要断流 | 不作为统一策略 |
| 进入替换前保留，进入替换后阻断 | 未触碰的旧运行状态确实可用；不可逆阶段不伪装回滚；无需通用事务引擎 | 需要真实区分失败阶段并展示结果；Core 替换失败需要用户修正/重试 | 推荐 |
| 安装默认 MATCH REJECT 配置 | 普通业务可拒绝而不依赖旧规则 | 仍创建并应用另一套配置，覆盖认证/监听/资源；还需解释服务与 UI 的失败状态 | 不采用，直接使用已有 Suspend/入口清理 |

推荐不承诺全设备 kill switch。停止本应用的入口/VPN 后，系统或其它应用可能使用其它网络路径；界面必须说明本应用未接管，不声称设备全局断网。

## 不可变输入、接收与结果（R3）

### 配置输入与身份

新增 `ConfigInput` 是一次实际应用所需的不可变输入，不是来源认证或运行状态台账：

- 原始 YAML 经当前脚本/覆写合成后，保存为本应用私有目录的内容寻址字节对象，`yamlSha256` 对应准确输入字节；保留现有 age 输入兼容时，接收端另外标明解密后解析字节的摘要，不混淆两者。
- 小型输入 manifest 包含格式版本、yamlSha256、profileId/应用时名称、本次实际参与合成的本地来源依赖 key 集合、深复制 selectedMap、testUrl，以及已被 Core 确认的既有 UpdateParams 运行覆写（初始为空）。manifest 的精确 JSON 字节 SHA-256 为 `inputId`。YAML 大对象可被不同选择元数据复用，避免每次选组复制整份订阅。
- Dart 在本次 SetupState/有效 PatchConfig 快照中取得上述输入；不在 YAML 生成后再从当前选择借 selectedMap/名称。发起时创建当前 apply ticket，排队和异步合成后都核对 ticket 与原来源/数据集版本，过时任务不提交 Core。
- 接收方只接受格式受限的 inputId，路径从应用配置输入目录推导，不接受任意绝对路径。读取 manifest 与 YAML 后分别核验摘要，解密/检查非空对象，保存本次独占字节副本；之后解析该副本，不重读共享 config.yaml。摘要证明字节对应，不代表订阅来源可信。
- `config.yaml` 不再是 setup/quickSetup 的可变输入指针；如保留兼容输出，只代表最近提交的文件，不作为成功或生效身份。空/注释/空映射等无可用对象的输入在接触替换前明确拒绝；合法显式 DIRECT 不受影响。

输入文件只承担数据传递。候选由调用方持有至 Core 确认已复制字节，Core 的 pending 输入由当前 Owner 拥有；当前安装/恢复 checkpoint 引用的对象必须保留。队列收敛后只清理该输入目录内不再被这些实际引用保留的对象，不触碰原始 profile、用户文件或独立证据。不能一边删除输入一边声称可直接冷启动复现。

### 接收资格与分阶段接口

Android 对外仍是一次异步 `applyConfig(inputId, expectedRun)`，由现有 ServiceState 流程内部完成下列步骤；不让 Dart 并行调用旧的“Go startListener + native startPrepared”。普通配置更新不产生新运行意图，沿用当前 request；真正新 start 才通过现有 arbiter 准备新意图。

| 步骤 | 接口与所有权 | 可观察结果 |
| --- | --- | --- |
| 接收登记 | `registerConfigInput` 在真实 MethodChannel/JNI 接收边界同步复制输入引用/expectedRun，复用 Go methodCallSeq 产生序号并登记最新 config 操作；先于 worker、startPreparationLock 和任何 home/SDK/ownership/isRunning 写入 | 仅返回 ApplyToken；没有配置或启用副作用 |
| 输入准备 | `prepareConfig(token, init?)` 在 configMu 内先验最新 token、原 native processEpoch/intentRevision、来源/数据集资格；核验并冻结实际字节。拒绝在任何替换前发生。通过后才进行受约束的一次初始化、关闭旧普通业务、切 Owner/建立该 Owner 的 pending 输入 | PreparedReceipt：Owner、inputId、yamlSha256、token、ServiceCoreParams 和必要 mixed 绑定身份；旧 Owner 已退役，不能宣称仍可用 |
| 服务准备 | ServiceState 根据原运行意图和当前所属资源准备/复用服务；Core 耦合字段使用本次 ServiceCoreParams，独立字段保留本次 desired 快照；不为 stopped 应用启动服务。TUN 创建仅准备 INNER 所需网络，不开放普通业务 | PreparedService 的 serviceId/requestId/protectGeneration，或明确失败/过代际 |
| 配置安装 | `installConfig(preparedReceipt)` 在 configMu 验同一 pending Owner/token/输入，解析冻结字节、分阶段安装、选组和构造必要监听；不调用 Running | InstalledReceipt，不是应用已成功或流量已接管 |
| 最终激活 | `activateConfig(installedReceipt, preparedService 或 inactive)` 再验原输入、最新序号、Owner/来源及 native 运行/服务资格和监听结果；一次短内部发布才使该业务范围有效并 OnRunning。inactive 安装只发布已载入/未接管 | ActivatedReceipt 或 InstalledInactive；才允许发布成功/更新缓存与恢复 checkpoint |

Native 在接收入口同步取得 Go 登记的 ApplyToken，再交现有 startPreparationLock 执行；同 run 下的最新配置操作也使用该 Go token，不另设 native 序号权威。Go 只保留当前 Owner 对应的一个 pending 字节快照和已安装对象，沿用 configMu；没有并行候选引擎、回滚日志或另一套启停仲裁。新注册到达可使旧操作过时；旧 prepare/install/activate 必须在各自副作用边界核对同一 token，不能把后续 phase 的普通 RPC 序号误当作新申请。异步旧结果携带原身份，不能借当前最新输入返回成功。

`expectedRun` 绑定 native processEpoch/intentRevision；活动激活还绑定实际 serviceId/protectGeneration。普通业务资格不以每次纯 network revision 变化重新生成配置，不把本项扩大为 L2-T03 的所有网络回调策略。输入来源资格使用已有 dataset/source 代际，不以 MD5 缓存充当来源身份。无 hooks 的上游调用保持原语义；FlClash 非 Android 适配使用现有 Core 生命周期/调用资格完成同样的安装/激活，不增加设备矩阵。

Android 通用 invokeMethod 不得绕开配置流程直接调用内部 prepare/install/activate；已知配置入口路由到 ServiceState，内部 phase 只由其 host 使用。旧 quickSetup 的“goroutine 内初始化再启用”入口由上述流程替换，所有已知 Core.kt/ServiceController/Go JNI 调用方一并迁移，不能留下可绕过登记的旧调用路径。初始化已完成后，相同 home 的生命周期初始化幂等；不允许一个迟到配置请求切换已初始化的 home/重置 ownership。首次 init 也必须在 prepare 的接收/运行资格通过之后。

返回的 `ConfigApplyResult` 是正常 envelope 中的类型化对象，区分 rejected（可保留适用旧配置）、prepared、installed、activated、installedInactive、bootstrapRequired、blocked、superseded、cleanupFailed，包含原 token、Owner、inputId/yamlSha256、profile 身份及实际 Core fact 版本。中间阶段不当成最终成功；过时回调不能写 lastConfigMd5、标签或新 checkpoint。`bootstrapRequired` 只保留所属 prepared 服务和 INNER 用途，Dart 沿既有授权资源流程恢复后重试；重试耗尽或后台无前台恢复能力时按原 token 等待终结清理。Android 停止由原生运行意图同步撤销 Go 业务资格，不再追加无身份 Go stop；桌面停止复用接收序号，旧 stop 不得关闭较新配置。

## 普通业务范围与最终开放（R1）

### 权威与最小核心增量

普通业务需要独立于 L1 应用维护请求的轻量范围。它只引用现有配置 Owner/phase、该次激活的取消 context 和原 native 运行资格，不授予存储提交、不接管 DIRECT/Proxy 选择，也不进入 appRequestRegistry 的 128 个应用请求上限。激活 context 是配置/服务资源寿命，撤销后永不复活；重新启用创建新寿命，旧范围不能借同 Owner 的新 context 继续。

在现有 requestscope 包提供窄 BusinessScope/带范围 Tunnel 适配，由包装层现有 Owner/运行状态派生资格。没有 hooks/没有显式业务接入的上游维持原行为；C.INNER 和已有应用 Lease 仍按原初始化/维护规则处理，不套普通业务的“必须最终就绪”门。

必要的核心增量已纳入本设计，不再假定包装层 Suspend 足够：

- executor/hub 增加显式 staged 应用入口，与原 ApplyConfig 共用安装主体；staged 结束停在 Inner，不调用 OnRunning。原上游入口仍执行原 Running 语义。
- tunnel TCP/UDP 及 packetSender 接受原 BusinessScope，使用其 context/检查及连接跟踪；最终拨号、每次重试、实际发送不能重新取得当前业务范围。
- 业务 listener 使用绑定该次候选范围的 C.Tunnel 适配。替换前关闭并移除旧默认/自定义及 `tunnels` 固定转发 listener，不依赖地址/Config 相等复用旧实例。旧协议处理器即使在新成功后才调用 HandleTCP，也只持有旧范围。
- 默认 mixed/HTTP/SOCKS 等接受点在协议处理前登记原连接的关闭回调并验证范围；监听 Close 和业务撤销共同清理尚未成为 tracker 的接受连接。HTTP keep-alive/upgrade/内部 pipe 沿原 Tunnel 适配传递同一范围。
- 独立 Android TUN 跨配置保留 FD，但每个 TCP flow/UDP packet 在进入队列之前取得当时普通业务范围；核心后续只消费该范围。不会把整个持久 TUN 固定到首次配置，也不会在解析后才借新 Owner。

业务 Scope 的寿命标识和撤销标志属于当前 Owner 的资源，不是第二个 running 模式。只读事实版本不决定流量；授权仍由原 Owner/phase、原运行资格及该寿命是否有效决定。这些增量表达本项新增的普通业务寿命/最终发布能力，包装层没有相应位置能关闭已经越过 isHandle 的工作。核心 carrier 必须更新，包含原 T03 和本项的完整差异；新候选仍以公开 `8597778c7df410ebe88c57e59eaab32d203156df` 为唯一 parent，不能只以未发布 2b8c0e2 为父。

### 在途 TCP/UDP 和有限动作

- TCP 在原接受/flow 范围下进行预处理、嗅探、解析和选择；阻塞操作使用该取消 context。选择配置表时核对原范围，解析返回后、每次实际 DialContext/重试前再次核对，固定本次所选代理对象/目标，不能撤销后从新表取得默认 DIRECT。拨号结果若已过期立即关闭、不进入转发；输入/输出 conn 在产生时就跟踪，不等 statistic tracker。
- 旧 SOCKS 已 greeting 的连接：本次替换时取消其原范围并关闭接受连接；即使其协议 goroutine 延迟到失败后的新成功才提交目标，旧范围仍拒绝。它不被视为新配置下的一条新连接。
- UDP 在 packet 入队前绑定范围，队列、异步 sniff/dial、NAT sender、ResolveUDP、每次 ListenPacketContext/重试、每次 WriteTo 和回包均沿原 context。NAT 会话包含激活寿命的命名空间；撤销关闭旧 pc/sender、丢弃旧队列并删除该会话。新成功后同一客户端端口的新数据报可以创建新会话，旧排队数据报/旧响应不能转入它。
- 资格撤销与 Owner/原 native 状态变更在既有 registry 短临界区生效，先使原寿命不可用，再在锁外 cancel/Close。因此 prepared 尚未 flush/cancel 的窗口同样拒绝，不能只依赖 ctx.Err。
- 每次真实网络动作前的资格核对是有限一次动作的授权点：只允许已经选定的原代理/目标及有界 context；重试/下一次发送重新核对。撤销前已经授权并交给系统的 syscall/字节不能收回，取消和关闭负责终止剩余动作。验收区分“撤销先于授权则目标零新增”与“授权先于撤销的有限旧动作可结束”，不声称按墙钟瞬时清除所有在途字节。
- TCP 转发路径也保留原范围并在发送边界拒绝失效动作；保留受资格检查的 CloseWrite，将 EOF 传给对端后仍可接收响应，撤销则关闭整个连接；不能通过暴露底层 RawConn/ReaderFrom/WriterTo 等快路径绕过保护。只对已接入的业务流做必要适配，验证正常传输与取消；不重写协议或复制路由算法。

### 监听成功与唯一开放点

GetPorts 仅为诊断，不能当作成功证明。增加返回实际构造错误的窄 listener API，原无返回值入口继续适配原调用语义：默认 HTTP/SOCKS/mixed/redir/tproxy 的必要 TCP/UDP 构造结果分别检查；mixed 等成对创建要么全部成功，要么关闭本次部分结果并移除指针。自定义 listener 的 Listen 错误及 `tunnels` 固定 TCP/UDP 构造错误纳入本次安装结果，失败时清理已经成功创建的其它候选入口。staged executor 不提前创建固定转发；包装层绑定原候选 Tunnel，TCP 在 Accept 后、协议 goroutine 前跟踪连接，UDP 从入口保留该范围。停止、退役和 inactive 安装均不留下固定监听。固定入口 key 保留完整代理名称（含斜线），清理不截断名称或遗留映射。不扩为所有可选入站的通用事务。

候选监听可先完成 bind，但其范围尚未激活，接受/业务动作不得提前出站。只有全部必要绑定成功、选组完成、Owner/input/token 和 native 服务资格仍有效，activate 才发布 ready 并 OnRunning。任何安装/绑定错误都不调用该发布，取消候选范围、关闭部分入口及连接，currentConfig 不可被 updateConfig 复活。停止状态仅载入配置，不自动开放业务。

新增真实反例已证明 mixed UDP 占用时 GetPorts 报告请求端口、TCP 却连接失败；详见下方证据。正式验收必须控制此窗口，以及 executor 返回前、包装监听验证前/失败时业务到达的窗口。

## Android 清理完成与新 start 恢复（R2）

### 失败完成契约

现有 failRunIntent 只是登记状态，不能用 true 代表服务/TUN 已清理。改为可等待的类型化失败接口，ServicePlugin 在 coroutine 中等待 ServiceState 结果，不同步回执“已完成”。

1. 输入携带原 expectedRun 和 Go ApplyToken/Owner；ServiceState 同时核对当前运行请求与最新配置操作。过时操作返回 superseded，不能 reset 新意图；同一 run 下有较新配置申请时也不能让旧失败停止它将复用的服务。
2. 当前终结失败先使对应 Core 业务范围失效，登记 setupFailed，然后在现有 transitionLock 中确定旧 serviceId/requestId/protectGeneration 并请求所属资源清理；不在 publicationLock 内等待 Go/JNI/服务。
3. host/ServiceController 增加按所属身份停止并等待结果的操作，ManagedService 接受原身份后才清理，TUN 沿原 generation 的关闭。失败清理路径不能调用按类名停止两种服务的 stopServices，防止系统/新请求创建或接管的服务被旧清理误停。
4. transitionLock 序列化本应用服务的创建/清理/接管；新 prepareRunIntent 可先到达，但实际新服务转换等锁。系统回调仍可能独立创建/接管，底层 stopOwned 必须再次验身份，不能只靠锁假设。
5. await 旧 binding/TUN 释放或确认已由新身份接管后，返回 cleaned/superseded。只有仍为原当前请求时发表最终 failed/停止展示；cleanupFailed 返回真实未完成结果，业务门维持阻断，不能把 runTime 清零等同于物理清理完成。

Dart 的过时配置返回 superseded，外层启动不根据 false 查询并借用最新 token 清理。同一 run 下后续 apply 可继续完成；尚未登记 Go 操作的构建及合成后保存/同步/输入与目录 IO 失败，只使用构建前捕获的 intentRevision/configToken。已有 setup generation 只表示排队替换，不证明继任有效或已经接管。原操作保留按其 request/token 收尾的责任：有排队替换时把收尾放到同一 setup 队列之后，队列期间又增加任务则再次让其先执行；原调用在串行任务之外等待这一责任兑现，避免阻塞继任。无效回调退出后原收尾仍会执行；有效继任已登记的新 token 由 native 拒绝旧清理，不移除原来源回调或新增运行仲裁者。Geo bootstrapRequired 后仅来源撤销而无继任时按原回执终结准备；同 run 继任已排队时保留其接管机会，直到实际接管或按原身份收尾；已登记的新 token 仍由 native 拒绝旧清理。getRequestState 额外暴露的 configToken 只读，不形成新的运行权威。后台 SharedState 缺失或读取异常使用原 request/token 收敛为 failed，新的 start 可重新准备。

旧 Core 清理同样限定原 Owner/ApplyToken，拒绝/过时代际不能取消新 pending/ready 范围。终结处理在当前 setup 操作结束前 await；Core 可恢复 Geo 重试之间不做服务终结，仍允许原 INNER 用途，最终成功后才完成激活。

### 统一新 start 与恢复

初始和普通 `_start` 不再一个走 full apply、另一个先 start 再 debounce。两者在同一 setup 操作中执行：构建/核验 ConfigInput → Core prepare → 所属 native service 准备 → Core install → 原 token 下 activate → 真实结果发布。bool 不再被 `_setCoreRunning` 丢弃，也不在 Go listener 返回 false 后仍盲目调用 startPrepared。

- Core.startTun 只表示 TUN/保护通道准备完成，移除它隐式启动业务 listener/发布业务成功的副作用；此时只允许 INNER 初始化。ProxyService 也只完成所属服务准备。native 阶段保持 starting/preparing，不能提前标 started。
- 服务准备先于 heavy install，因此 provider 初始化所需 protect/bind 已有，不需要持 configMu 等待一个反向取 configMu 的 startRequestListener；不新增并行 preload 的死锁。
- 激活前 ServiceState 在 transitionLock 验原请求/最新配置操作和 prepared service（VPN 要求原保护 generation 已 ready；ProxyService 要求原 serviceId 下的实际准备成功，generation 为 0，不冒充 VPN），再调用有界的 Core activate；Core 再验 receipt/Owner/真实绑定/服务身份。激活成功后 native 才发表 started，Dart 才确认运行。inactive 安装不创建服务。
- 终结失败后的新 start 必须重新验证有效输入并准备真实所属服务，不能仅把 Go 端口重新打开。若旧失败服务仍有物理资源，不按 runTime 非零盲目 adopt；先按身份完成旧清理，失败则明确返回，成功后创建/验证新的 TUN/ProxyService。
- 常规停止仍沿原运行请求；start/SSID/权限/always-on 的 latest intent 继续由原 arbiter 与 transitionLock 决定，不由配置观察状态决定。Go 业务范围会在原运行资格失效时立即失效，取消动作仍在锁外执行。

验证采用真实 Dart SetupAction/CoreLib/Service 请求序列，经测试专用 stdin/loopback 桥接给 JVM 的实际 ServiceStateMachine；host 受控替代 Android OS/物理 TUN，但不直接 mock 一个成功的 native 响应。Go 安装/业务入口另由真实 Go 消费者验证；桥接及各层替身的范围分别记录，不声称真实 MethodChannel/JNI/FD 已运行。必须有 Dart→真实 ServiceStateMachine/host 的可控制回归：终结失败等待清理、新 start 等待/接管、有效输入安装、实际 host.startService/Go 激活重新发生；另外用 JVM identity host 验证旧清理绝不触碰新 generation。它们仍不是设备/JNI/系统回调观察。

## 生效身份：页面、通知与恢复（R4）

### 服务准备参数与实际输入（R4-a）

旧 checkpoint 可与未应用的新 desired 同时存在，因此 `VpnOptions` 不能整体来自 desired，也不能整体退回旧 SharedState。现有 system.dart 用 desired mixedPort/认证状态生成本地代理选项，而 VpnService 在 establish 时把这些值写入系统；本项按字段分开消费。

| 字段/约束 | 本次实际准备的来源 | 核对与保留 |
| --- | --- | --- |
| mixed 端口、监听地址/本机可达性、必要 TCP/UDP 资源身份 | 本次已核验 input 的 RawConfig 加已确认运行覆写；prepare 返回实际持有的 mixed 绑定 | 不读 desired mixedPort，不用 GetPorts 相等代替成功 |
| 本地入站是否需要认证 | 同一冻结输入的认证解码结果，重用与安装相同的纯解码规则；不向 native 返回密码 | install 再与实际 cfg.Users/认证配置比较，inputId 绑定完整认证字节 |
| 是否声明系统 HTTP proxy | 用户 desired 的开关请求，与本次 mixed 实际绑定、本机可达性及认证兼容约束共同决定 | 有认证时沿现有政策不声明无凭据系统代理；没有可用 mixed 入口也不声明。desired 开关本身不被改写 |
| 栈/捕获与其它独立 VPN 设置 | 原运行请求下接收的 desired VPN 快照，例如 enable、access control、allowBypass、bypassDomain、原生地址/路由/IPv6/DNS 捕获及栈偏好 | 不整体回滚；保留现有权限导致的栈回退，并记录实际 effective 选项。它们不被拿来证明 Core 监听已可用，本项不扩 DNS 全链政策 |

SharedState 传递用户原始 `systemProxyRequested` 偏好，不再把已与 desired 认证折叠的 systemProxy 当作请求值；实际服务的 port/effectiveSystemProxy 仅由本次投影填充。保留现有 SDK 支持约束，用户偏好存储不因兼容性关闭而被改写。这是准备入参的区分，不新增偏好系统。

`prepareConfig` 从其独占字节解码并应用同一已确认覆写，形成 `ServiceCoreParams`：inputId、token、Owner、mixed endpoint/bindingId、认证需求及系统代理兼容性。对于本次要启动的服务依赖的 mixed 入口，在 prepare 内完成真实必要 TCP/UDP 构造并持有结果；其普通业务范围仍未激活。这样服务准备先于 heavy install，但系统代理不会先指向一个尚未由本应用拥有、可能被其它本地进程占用的端口。stopped 下纯载入不为系统代理预开业务入口。

install 必须采用同一候选已持有的 mixed 资源，不关闭后按相同端口重新绑定；其它必要入口继续按既定 staged/checked 结果处理。若解析后的端口/认证投影与 prepare 不同、资源已失效或绑定不完整，不能确认 installed/started，应撤销本次准备并走所属失败清理。不会在该窗口换用新 desired 值补齐。

ServiceState 由 desired 独立字段和 ServiceCoreParams 派生不可变 `PreparedVpnOptions`，在 PreparedService 中记录其 fingerprint、原 token/Owner/inputId 和真实 service 身份。实际服务已有的系统代理/准备选项若不同，不能仅凭 runTime 非零或服务类型相同复用：按原身份重建相应 TUN/generation，或确认无需变化的实际选项可用后重新绑定本次 receipt。install/activate 同时验证投影、资源身份和 prepared fingerprint；最终开放只承认本次真实安装结果。

`canStartRequestTun` 原有的 `phase == ready` 不能直接删掉：准备 TUN 时改为核验当前 pending PreparedReceipt 的 token/Owner/inputId/ServiceCoreParams，仍核验原 native processEpoch/intentRevision、starting 状态、serviceId 与非零保护 generation。只在对应服务准备阶段允许 FD；创建后再验相同资格，过时仅清理该身份。此时普通业务保持关闭，最终 ready/Running 仍由 install 成功后的 activate 发布。ProxyService 使用其实际服务准备资格，不冒充 VPN 保护 generation。

### 新增观察事实，保持单一权威

SetupAction.build 当前为 void，没有现成结果 state。明确新增只读 `ConfigStateProvider`/DTO，SetupAction 继续负责流程并向它提交本地构建结果，不能称为“直接复用现有观察 state”。

Core `getConfigState` 与状态事件提供 ConfigFact：runtime/native epoch、Owner、事实版本、ApplyToken/inputId/yamlSha256、应用时 profileId/名称、parsing/installed/ready/failed/retired、是否实际开放业务，以及已有 route/picks 版本。事实在 configMu/registry 的原状态变更处生成，版本仅用于拒绝迟到观察，不参与运行仲裁。原 Owner/phase、isRunning 与业务寿命仍决定权限。

- 只有 final activate 或 stopped 下明确完成的 inactive 安装产生最终成功事实；prepared/installed 不能显示为已接管。
- 替换前拒绝保持真实旧 fact；替换开始后旧 active 身份失效，失败不能显示旧配置仍可用。Core 重启/脱离或 epoch 不一致时显示 unknown/未应用，不能从保存的名称恢复 active。
- 页面观察新选择、构建错误与实际 Core fact：旧配置保留时显示原生效身份和“新配置未应用”；blocked 时不显示旧配置正在保护；新成功必须匹配相同 input/Owner/token，迟到旧结果不能覆盖。
- lastConfigMd5 仅作内容缓存，跳过还须当前 Core fact 对应同一输入且处于有效阶段；不能用旧 MD5 绕过失败后的恢复。

### SharedState 与通知消费

SharedState 继续保存 desired 的 VPN/启动参数、统计偏好及本地化通知样式。desired profile 名称不得作为有效通知标题；旧 currentProfileName 字段不再被 native 当作 applied 身份。页面的“已选择”和“正在使用”分别取 desired 和 Core fact，不把整个 SharedState 回滚为旧快照。

AndroidManager 即使在 Core 应用前同步新 desired 或延迟写入，也不能改 applied。ServiceState.notificationParams 从当前 Core fact 和实际服务阶段派生标题：active 显示实际 profile；preparing/installed 显示应用中；blocked/unknown 显示失败/未接管。准备服务的非零物理 runTime 不能被刷新接口当作业务已 started，Dart 运行展示以激活结果/native 阶段为准。原生 phase 改变本身刷新通知，无须再等待一次流量/SharedState 同步；服务丢失清掉有效标题和运行时间。实际页面身份入口是仪表盘的配置详情，不宣称所有配置/代理页面均已改造。

ServiceController 将现有单一 Core 事件入口复用为 native 事实消费者加可选 Flutter 转发；Flutter engine 脱离只移除 Flutter 消费者，不使仍存活的通知失去事实更新。回调在锁外异步处理，关键 prepare/activate/失败 RPC 完成时主动核对当前 getConfigState，按 epoch/Owner/事实版本拒绝旧回复；不在 Go/原生互持锁时回调等待。

### 持久输入与进程恢复

- 恢复 checkpoint 是 Core 已成功接受的 ConfigInput 引用，不是持久化的 active 状态。它由实际成功接收端维护，和 AndroidManager 保存的 desired SharedState 分开；延迟写 desired 无法覆盖 checkpoint。
- 既有成功热 updateConfig/选组等会改变下一次恢复内容的操作，checkpoint 必须反映已确认的实际结果：同一输入的明确 UpdateParams 覆写、真实选组和 testUrl 形成新的小 manifest，YAML 大对象复用。安装时先按同一已知 UpdateParams 映射合并再用原解析器，不新建策略语言；不能把未确认 desired 直接塞入。用当前 Owner/route-picks/事实版本核对后发布，旧 checkpoint 生成工作过时则丢弃，不覆盖新状态。
- 新 native 进程先为 unknown，不信任旧 active 名称/Owner；读取、核验恢复输入后重新走相同 prepare/service/install/activate 流程，得到新 epoch/Owner 的实际事实才显示运行。没有有效 checkpoint 的旧格式数据不得退到默认配置，应由 Flutter 重建可验证输入并明确提示；不假定升级前 desired 名称就是旧生效身份。
- 前台来源 ticket 和后台 checkpoint 重放分开：前者必须仍是构建时的 source/dataset 代际；后者是在原恢复政策下对未撤销的已接受输入取得新运行/Owner 资格，使用原准确字节，不从当前 source 文件借新内容或假称旧 ticket 仍有效。显式撤销或不完整提交必须先使该 checkpoint 不可重放。
- 系统/通知后台 start 使用最后成功的可用输入；Core 耦合的端口/认证/系统代理约束取本次核验及安装结果，其余独立 desired VPN/启动参数保留；通知显示这次实际恢复的配置。前台用户选择新配置后 start，则必须先构建该选择，不能在其构建失败时暗中把它报告为旧输入成功。
- 删除、恢复/替换数据集或明确撤销恢复来源时，接入已有来源/数据集失效与 mutation receipt：在该操作完成前使对应 checkpoint 不可用于启动；未完成本地提交/恢复标记阻止冷启动借旧 checkpoint。失败前仍实际运行的旧身份可以如实显示，但不得重新发布已失效的持久输入。普通 engine detach 不等同于来源撤销。

热更新与 checkpoint 具体采用已有字段的有限映射：成功的 UpdateParams 形成累计的 acceptedOverrides，选组/testUrl 使用 Core 确认的快照；恢复时先把这些已确认值合并到原 RawConfig，再调用原 ParseRawConfig。源 YAML、派生覆写和实际 route/picks 版本分别记录，不把 base YAML 摘要称为所有热状态的摘要。参数映射需与现有 live update 共享对应关系并有重放一致性用例，不复制任意合成/脚本规则。

`updateConfig` 的必要监听重建也使用 checked 结果与同一失败结果管道；绑定失败不能只被 safeRun 吞掉后保留 active 展示。成功的运行覆写/选组返回或发表新 Core fact；已接受的热参数先归入当前配置的累计值；并发选组使旧候选失效时重新捕获实际选组及累计值，不能把未发布静默当作保存成功。checkpoint 生成先在原锁顺序下取得冻结快照，临时内容可在锁外准备，只有下述共同有序边界通过后才发布最终引用。不能先替换可恢复引用、再靠事后校验/删除补救。这里保存的是既有参数的已确认输入，不新增配置策略引擎。

输入对象的持久保留只覆盖当前 pending/applied/checkpoint 必需对象，不为每个历史成功状态新建常驻日志；清理需保持这些引用及当前读者可用。正式数据全生命周期仍由 Loop 3 接续，本项不将源凭据或实际配置放入版本库。

### 来源撤销与恢复引用发布（R4-b）

每份 ConfigInput 明确其本地依赖 key：自身 `profile:<id>`、所用脚本 `script:<id>` 及本次实际使用的其它本地来源；来源/数据集代际继续使用现有 registry 的 `sources[key]` 与 `dataset`。例如删除 script 只增加该 key 的版本，也必须使依赖它的恢复引用失效，不要求 Owner/route 一同变化。标准覆写额外依赖 `global-rules`；局部 added/custom 规则、组、节点、禁用规则及 overwrite/script/matchTarget 选择变更使用自身 profile key。纯展示改名不撤销自身输入；被其它组作为 provider 使用的名称变化撤销实际受影响 profile。数据库读快照和依赖票据在同一 dataMutations/本地提交段取得，强制刷新缓存 SetupState 并读取已提交行；合成和 Core 调用在该段外进行，后续变更仍须重新核验来源。“使用默认”批量入口由 ProfilesAction.useDefaultCustomConfig 一次读取原始配置，提交前核对同一来源票据，在原 mutation 段先撤销再批量写 nodes/groups/rules；页面不直接写 DB，来源变更后旧采样不能提交。复用既有 key 机制，不另建撤销计数器/授权系统。

后台快照取得 `CheckpointFence`：原已成功输入/Owner、已确认参数与 route-picks/配置事实版本、现有 dataset 代际及全部依赖 key 的 source 版本。仅检查前四项不够。冷启动资格与仍在运行的旧展示事实分开，撤销可使恢复引用无效，但不凭此伪造当前 Core 已停止。

新增一个窄 `checkpointMu` 只序列化最终恢复引用及其资格变更，不存放新的运行意图：

1. 生成方可在锁外写内容寻址对象和临时 manifest，这些尚不能被冷启动选中。
2. 使上述 fence 失效的现有 source/dataset 递增、对应配置输入/成功事实/已确认选组变化，以及最终引用发布/清空，都经同一 checkpointMu 有序边界。需要现有锁时遵守 `configMu → selectMu（如需）→ checkpointMu → registry`；源失效入口可只取 checkpointMu→registry，不反向等待 configMu/selectMu。
3. 发布者取得 checkpointMu 后，核验完整 CheckpointFence 和当前有效引用/目标资格；在 registry 内只读/提交短元数据，随后释放 registry/select 锁，仍持 checkpointMu 执行已准备好的小型引用原子替换和必要持久化。不持 registry/select 锁做磁盘写，不持该锁等网络/JNI/服务。持 checkpointMu 后不得重新请求前序锁。
4. 来源撤销取得同一 checkpointMu，先在 registry 内推进已有 key/dataset 版本及相应配置事实资格，再使依赖它的当前持久引用失效（原子 tombstone 或删除并确认持久化）。只有这些完成才回复撤销成功；Dart 原有删除路径 await 此回复后才删除数据库行/文件。取消连接和事件发表仍在锁外。
5. 两种顺序都有确定结果：旧发布先完成，则之后撤销在返回完成前清掉它；撤销先完成，则旧发布重新入锁时 source/dataset fence 不匹配，在任何最终引用替换前拒绝。Owner/route/picks 即使完全不变也成立。旧临时内容可丢弃/回收，不能重挂旧引用或删除别人的较新引用。

所有能使该 fence 过时的写入在变更前遵守同序，而不是“先增加 source、稍后再抢发布锁”。纯 native 运行/显示观察不是来源撤销；相应观察版本与可重放输入资格不能混作一位权限。engine detach 不撤销来源；attach 的会话代际变化可令旧生成工作过时，但不将其当删除去清空已接受的恢复输入。实际 source invalidate / dataset replacement 则按依赖清空引用。

冷恢复只读取当前已发布的有效引用，不扫描旧 manifest/blob 选择“最近成功”。在 checkpointMu 中读取引用身份和本次 source/dataset fence、确认未完成提交/恢复标记不存在，形成一次恢复票据；释放锁后可读取大字节对象。进入 prepare 的副作用前再次按同序核验实际引用仍相同有效、来源 fence 和提交边界未变。新进程不把上个进程的易失 source 计数当当前许可：先以持久有效引用和恢复标记核验，再为这次明确重放取得当前代际票据；已经被持久撤销的引用绝不能靠重置计数或现存 blob 复活。

撤销/持久化失败不报告成功，删除不能越过失败回复；遇到不能确定的部分提交沿既有恢复标记阻止冷启动。没有另建每个来源的持久撤销台账，当前引用的缺失/tombstone 以及既有提交边界就是恢复端要检查的结果。

## 外部控制器写入边界

M 于 2026-10-16 通过此补充。FlClash 的外部控制器采用同一配置权威；独立运行且没有应用 hook 的核心保留原行为。

- `PUT /configs` 在解析配置、读取路径或下载之前返回 HTTP 409，提示从 FlClash 全量应用。
- `PATCH /configs` 仅允许 mode、ipv6、log-level、find-process-mode、tcp-concurrent、unified-delay、geo-auto-update、geo-update-interval、geox-url；完整解析并校验全部字段后才调用包装层 updateConfig。未知字段或监听/TUN/认证等字段与合法字段混合时整项拒绝，不部分生效。
- `PUT /proxies/{name}`、自动组的 `DELETE /proxies/{name}` 及组延迟查询中的清除强制选择，统一进入包装层选择入口。空对象、空名称或 null 的 PUT 返回 400，保持手动选择、route/picks、事实和恢复引用；只有明确的自动组清除可用空选择。组延迟查询先验证参数；`PATCH /rules/disable` 不属于有限热更新，明确拒绝。
- 写入在 handler 接收时捕获原 Owner/token，实际 configMu 或 selectMu/checkpointMu 锁内再核验；不通过 middleware 保存的旧 proxy 指针修改新 Owner 的同名组。成功热参数/选组沿现有快照发布流程更新恢复引用；自动组保存实际 forced selection（含清除后的空值），不把瞬时最快节点变成恢复后的强制选择。
- 外部面板的完整配置上传、入站修改和规则开关因此不再可用；读取及上述热参数/选组继续提供。其它控制器端点的认证、诊断和来源审计不在本项展开，沿既有应用请求保护及后续任务边界。

## 失败分层、所有权与锁

| 失败位置 | 结果与真实运行状态 |
| --- | --- |
| 构建/内容核验/过时登记在 prepare 替换前失败 | 不写空输入、不切 Owner、不碰当前入口；仅当当前 Core fact 仍 active 才报告 retained。首次无配置显示不可用 |
| prepare 退役旧 Owner 后、install/必要监听失败 | 原范围和候选范围均不可出站；不装默认配置；原/可取得候选 provider、监听、队列与连接按其身份清理，currentConfig 不可复活，native 终结清理 await 完成 |
| 解析返回 nil 的部分对象 | 失败 Owner 阻止其请求/发表；在必要核心解析错误出口关闭已构造的 provider/资源，不能假装包装层拿到 nil 已 Close 全部对象 |
| superseded | 只释放原操作拥有的候选，不停止新操作/新服务，不写成功身份或旧 digest |
| cleanupFailed | 明确物理清理未完成；Go 业务范围仍阻断，不能报告已 stopped/可用旧配置 |
| 有效输入恢复 | 新 token/Owner，真实服务准备、必要监听成功和最终激活后才开放正常代理/合法 DIRECT |

锁顺序沿用 configMu → selectMu → registry；业务快速检查/有限授权不等待外部 IO。Go 只在内部短边界发布资格，再在锁外 cancel/Close/事件通知。ServiceState 的 startPreparationLock 序列化应用准备流程，transitionLock 只保护实际服务转换/有界激活，不持它等待 provider 网络；publicationLock 不等待 Go/JNI/清理。Go 不在 configMu 内经 JNI 反向取得 native transitionLock，不在已持 configMu 的清理中再次调用取同锁 handler。输入 read 与 mutation 仍沿 L1 的读/提交边界，锁忙时先释放读资格再等待，有限本地提交语义不改变。

## 新增反例与验收

本轮新增两个独立真实 Go overlay 反例，未改生产代码：[摘要与命令](../../../../build/verification/l2-t01/design/revision2_probes.json)。

- TCP 可绑定、同端口 UDP 被占用：ReCreateMixed 返回后 GetPorts 仍报告请求端口，而实际 TCP 连接失败。该检查按预期失败，证明不能采用端口相等判据。
- 调用方冻结旧配置（MATCH REJECT）后，在 Go 读之前把共享文件换为新 DIRECT：旧 SetupParams 调用报告成功，真实 mixed HTTP 到达新文件目标；调用方 SHA 与实际 SHA 不同。该检查按预期失败，证明 seq/MD5 本身不绑定字节。

两个最终独立进程 -race 输出均无 race。初始新夹具曾额外触发上游 mixed 关闭标志的重复 Close 竞态和测试自身 hooks 恢复竞态，原始 `*_initial_with_race.log` 保留；前者不再重复关闭已经被 UDP 失败关掉的 TCP，后者移除本反例不需要的应用 hooks fixture，未修改生产代码或禁用 race。第一份三个业务反例及原 GC/log 观察继续复用。

| 必要场景 | 实际消费者与通过条件 |
| --- | --- |
| 成功代理/合法 DIRECT | 同一真实配置/业务 listener，数据完整、各自目标/假代理计数正确；INNER provider/Geo 初始化保持可用 |
| 原三种坏输入 | 原已 greeting 连接与失败后新连接均无未接受 DIRECT；替换前拒绝时旧代理确实可用，替换后失败时业务阻断 |
| 入口通过后的 TCP/UDP | 在实际 sniff/解析、异步 dial/重试/发送前设置可控制屏障；先撤销后放行，验证目标零新增、旧连接/pc/队列关闭；授权先于撤销的有限动作单列真实边界 |
| 提前 Running 窗口 | staged executor 内/返回后、包装绑定验证前及验证失败时发送普通业务，均不能出站；成功 activate 后恢复 |
| 旧 greeting 跨新成功 | 旧 TCP 在失败和下一次成功后仍拒绝；新连接可成功；旧 UDP 排队包/回包不进入新 NAT 会话 |
| 真实绑定失败 | TCP 正常、同端口 UDP 占用；checked 结果失败、部分 TCP 清理、无 active fact/Running；解除占用后同配置成功 |
| Android 清理/再启动 | Dart→实际 ServiceStateMachine，host 可阻塞清理并报告真实归属；旧失败等待/过代际不触碰新服务；新的有效 start 实际重新调用所属服务准备并完成 Go activate |
| 输入读取与 quick 迟到 | 写后读前替换 manifest/字节；旧 handler/旧 quick/旧 phase 延迟；所有拒绝在 init/home/ownership/启用之前，不能改变新配置或标旧 digest 成功 |
| 页面/通知/持久恢复 | 新选择→合成失败仍显示实际旧身份；blocked 无旧保护标签；desired 的 VPN/启动参数不回滚；迟到保存/事实不覆盖新 applied；新进程无旧 active 声明，重新核验并激活才显示真实来源 |
| 旧输入与不同 desired | 后台恢复旧成功输入，desired mixedPort/认证与之不同；核对 PreparedVpnOptions 来自旧输入实际投影、预绑定资源和最终 cfg.Users，系统代理只在兼容且实际拥有入口时声明，独立 VPN 偏好不回滚。新增认证/端口差异导致原 TUN 参数不兼容时实际重建，不误报 started |
| 撤销抢先于旧发布 | 生成依赖 script 的旧快照→脚本撤销与引用失效完成（保持 Owner/route 不变）→放行旧临时写入/发布；最终引用仍无效，冷恢复拒绝旧输入。另验发布先完成再撤销、持久化失败、dataset replacement 与非撤销的 engine detach |
| 来源与部分提交 | 恢复/删除/数据集失效使 checkpoint 不可复用；旧有限本地段边界保留，不借观察事实授新请求 |
| 编译和回归 | 受影响 Go/Dart/JVM 与跨语言 envelope、正常生成/格式/分析、Android ARM64；必要核心完整载体独立恢复及缓存/源码绑定；未变平台证据复用 |

实际对象和结果由 [l2_t01_result.md](l2_t01_result.md) 维护。原始脚本/日志/素材与 APK、未剥离符号和 mapping 保存在本地忽略目录；正式最小合成夹具、正常生成代码和完整核心源码载体随源维护，不上传原始证据。

## 范围与交付终点

核心增量是本项普通业务生命周期、分阶段发布、真实绑定结果和失败资源收敛所必需的功能接入；保持无接入时的上游语义，方便继续同步官方。新核心 commit/tree/blob/gitlink 和载体包含 T03 全部差异，唯一父仍为公开 8597778c7df410ebe88c57e59eaab32d203156df；独立对象目录恢复不能依赖未发布 2b8c0e2。不得推送核心或触发远端 CI。

本项不重做 DNS 全策略、脚本沙箱、来源授权或业务内容审计，不恢复暂缓 L1-T04，不承诺全设备 kill switch。已交给系统的有限动作、真实设备/JNI/系统回调与外部出口仍须如实区分；所有当前夹具为本地受控验证。

M 设计通过后才实施，再交实现评审；通过后自主整理、自验、提交并本地合入 security/android，清理任务临时分支/工作树并保留独立聊天/证据。M 按已授权 carrier 例外普通推送父仓库，其它任务不随本项启动。
