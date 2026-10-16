# L2-T02：DNS 接收方、出口与失败回退设计

本方案让被 FlClash 接管的业务域名查询跟随业务分流，同时限定节点及解析服务的启动解析。在实际解析、路由和拨号入口传递查询用途与已确定的出口；仅开启 `respect-rules` 无法满足要求。本文已通过 M 整项设计评审，本轮仅交付设计；尚未实现，也没有运行本文的 V1–V10 验收矩阵。

依据：[任务与当前状态](loop2_tasks.md#l2-t02-dns-接收方出口与失败回退)、[阶段目标](loop2_plan.md)、[共同安全目标](../security_requirements.md)。调查对象为父仓库 `1eeaf2c353dc7916b18025b9ed14d1c69032bf7a`、核心 `6c6e3e472bb246cc55f2e8577d9eddccc2623afc`。归属和授权由任务清单维护；本次仅交付设计。

## 目标、约束与可见范围

- DIRECT 业务域名向接受的解析服务直连查询；代理业务域名经对应代理策略查询，或交给代理端解析；明确配置的局域网域名只交给对应本地解析服务。
- 失败、名称失配、备用、并发、重试、刷新和网络变化均不能新增直连许可或解析接收方。合法 DIRECT 继续可用。
- DNS 接收方指收到问题的解析服务；DNS 出口指到该服务的传输路径。代理节点能看到转发目的地址，明文 DNS 的节点还能看到问题；DoH 服务仍能看到问题。客户端不能控制递归解析器之后的查询行为。
- 保留现有业务规则、DNS 接收方配置、ServiceState、Owner、应用请求 lease 和 L2-T01 的配置开放点。不得复制一套域名分流规则，也不得以 DNS 监听存在判断业务已获准。
- 默认保证同一代理策略／分组，**不保证同一物理节点**。自动选择、负载均衡或两次请求之间的健康变化可能选择不同节点；要求同节点需要进一步固定业务连接，属于另一个产品选择。

## 已核实的源码事实

下列事实只说明当前机制及可达风险，不是设备泄漏的观察结论。

| 入口 | 当前事实 | 对设计的影响 |
| --- | --- | --- |
| [Dart 合成](../../../../lib/common/task.dart)、[覆写键](../../../../lib/models/clash_config.dart) | DNS 缺失或未启用时只补 enable、fake-ip、nameserver；用户覆写按键集合应用；可另加 `system://` | Dns 全模型默认不等于最终发给核心的配置 |
| [核心配置](../../../../core/Clash.Meta/config/config.go) | 未覆盖字段继承核心默认；default-nameserver 有四个公网地址；主解析器也有默认服务；启用 DNS 时 nameserver 不能为空 | 最终配置必须显示有效来源和启动解析服务，不能把隐含默认当作用户新选项 |
| [DNSDialer](../../../../core/Clash.Meta/tunnel/dns_dialer.go) | `RULES` 用 DNS 服务地址构造 INNER metadata；不存在的 `#名称` 会转为接口选项 | `respect-rules` 并非按业务域名选组；名称失配不能继续当接口解释 |
| [普通路由](../../../../core/Clash.Meta/tunnel/tunnel.go) | 共用规则顺序；IP 规则可经 helper 先解析业务域名；普通未命中最终选 DIRECT | IP 前置解析存在先后循环；解析失败不能仅当 IP 规则未命中继续 |
| [入站附加信息](../../../../core/Clash.Meta/listener/inbound/base.go)、[RuleHost](../../../../core/Clash.Meta/constant/metadata.go)、[嗅探](../../../../core/Clash.Meta/component/sniffer/dispatcher.go) | 入站可设置 SpecialProxy／SpecialRules；RuleHost 优先 SniffHost；OverrideDest=false 也会写 SniffHost | 独立问题的 qname 及缺省主规则表不足以证明未来业务分流 |
| [独立 DNS](../../../../core/Clash.Meta/dns/server.go)、[TUN DNS](../../../../core/Clash.Meta/listener/sing_tun/dns.go) | 查询进入 ServeMsg，没有未来业务连接的完整端口、进程、入站及网络元数据；监听服务使用 Background | DNS 报文来源和端口不能冒充未来业务流 metadata |
| [DNS 中间件](../../../../core/Clash.Meta/dns/middleware.go) | hosts、fake-ip、映射、真实解析依次处理；fake-ip 的非跳过 A/AAAA 可只返回合成地址；过滤域名及其它类型仍可能真实查询 | fake-ip 可延后部分解析，不能据此宣称所有 DNS 都不外发 |
| [解析器](../../../../core/Clash.Meta/dns/resolver.go)、[客户端选择](../../../../core/Clash.Meta/dns/util.go) | 缓存和 singleflight 以 question 为键；过期缓存刷新及共享查询新建 Background；同组服务并发，非 lazy 备用可提前并发 | 接收方、出口和取消必须约束所有尝试；仅约束胜出响应不足 |
| [UDP/TCP](../../../../core/Clash.Meta/dns/client.go)、[DoH](../../../../core/Clash.Meta/dns/doh.go)、[DoQ](../../../../core/Clash.Meta/dns/doq.go) | UDP 截断后重发 TCP；DoH 可由 H3 探测转 H1/H2，并重建连接；DoQ 可重试连接 | 协议重试本身不等于直连或明文降级，须检查每次实际拨号和接收方 |
| [DIRECT](../../../../core/Clash.Meta/adapter/outbound/direct.go)、[拨号器](../../../../core/Clash.Meta/component/dialer/dialer.go)、[解析器全局入口](../../../../core/Clash.Meta/component/resolver/resolver.go) | DIRECT 可用 DirectHostResolver；节点拨号默认用 ProxyServerHostResolver；指定 resolver 不可用时全局入口可用 SystemResolver | 用途必须由真实消费者给出，不能只靠 initiator 标签或传入非 nil resolver |
| [系统解析](../../../../core/Clash.Meta/dns/system.go)、[Android 更新](../../../../core/Clash.Meta/dns/patch_android.go) | 全局 SystemResolver 的空列表可用 114.114.114.114／8.8.8.8；普通 `system://` 新客户端没有该默认列表 | 只阻断实际进入此回退的路径，不能泛称所有 system 查询都会回退公网 |
| [网络来源](../../../../android/common/src/main/java/com/follow/clash/common/RequestNetworkSource.kt)、[观察模块](../../../../android/service/src/main/java/com/follow/clash/service/modules/NetworkObserveModule.kt)、[Core 更新](../../../../core/lib.go) | DNS 发布采用 preferred 物理网络的列表，只传字符串；direct selection 另有默认网络判断；停止发布空列表；Go 序号只拒绝已排队的旧更新 | DNS 地址和实际绑定网络可能没有同一来源证明；应复用 sourceEpoch／revision／directNetworkId |
| [FD 控制](../../../../core/Clash.Meta/component/dialer/dialer.go)、[应用 lease](../../../../core/app_requests.go) | Android DefaultSocketHook 分支忽略接口名；现有应用 DIRECT 请求另有带状态核验的 ScopedSocketControl | `#接口` 和 protect 成功都不证明绑定到 DNS 所属物理网络 |
| [组选择](../../../../core/Clash.Meta/adapter/outboundgroup/loadbalance.go)、[已有路由绑定](../../../../core/app_requests.go) | 负载均衡可按目标、来源或入站用户选节点；现有严格代理 lease 已可校验选择链、provider 版本并固定叶节点 | 可复用一次查询的绑定，不能据同组名称推导 DNS 与业务同节点 |
| [选择保存](../../../../core/config_checkpoint.go)、[观测选择](../../../../core/route.go)、[恢复](../../../../core/common.go) | selector 的 Now 进入 SelectedMap，恢复后 ForceSet；未记录是否源于人工操作 | 若拒绝自动 DIRECT，需要当前选择来源随保存／恢复保持，不能信任恢复后的 fixed 外形 |
| [ECH](../../../../core/Clash.Meta/adapter/outbound/ech.go)、[WireGuard](../../../../core/Clash.Meta/adapter/outbound/wireguard.go) | ECH 可查独立 query-server-name／TLS ServerName 的 HTTPS 记录；WG 可用节点 dns 经该适配器解析 TCP／UDP 业务名 | 启动依赖不只节点 server；节点专用业务解析也必须受用途约束 |
| [配置事实](../../../../core/config_apply.go)、[UI 消费](../../../../lib/providers/config_state.dart)、[配置详情](../../../../lib/views/dashboard/widgets/profile_detail.dart) | 已有 inputId／Owner／版本与当前配置查询和事件；当前没有 DNS 决定字段 | 可扩展现有事实，不另建待办权威；旧 UI 缓存不能审批新输入 |
| [DnsView](../../../../lib/views/config/dns.dart)、[不可变输入](../../../../lib/common/config_input.dart) | DNS 页面修改全局 patch；manifest 有 acceptedOverrides | 配置级确认必须单独限域，不能把全局编辑或源 YAML 当用户同意 |

## 候选与推荐

| 候选 | 可行范围 | 取舍 |
| --- | --- | --- |
| 仅开启 respect-rules、重写 nameserver-policy | DNS 服务连接分流；少量纯域名规则可人工复制 | 无法复用进程、端口、IP 及动态 provider 语义，形成第二份规则；不采用 |
| 全部先 fake-ip，业务端统一解析 | 常见 A/AAAA 能推迟到完整业务 metadata 出现 | 过滤域名、非地址记录、显式 DNS 服务和 redir-host 仍需处理；不能单独交付 |
| 查询携带用途和路由结果，信息不足时拒绝或使用明确的前置代理 | 完整业务路径复用真实 matcher；独立 DNS 使用保守的同源判定；覆盖重试、缓存和资源归属 | 需核心入口与规则依赖能力增量，部分旧配置会被拒绝；推荐 |
| 始终先固定一个物理节点，再统一 DNS 和业务拨号 | 可加强已知业务流的同节点要求 | 改变自动组、负载均衡、协议重试和 DNS 缓存语义，独立 DNS 仍缺未来流信息；本项不选 |

方案的保守性是明确的兼容代价：规则不能从现有问题中确定出口时，不把缺失字段当作“不匹配”；默认没有前置解析许可。按[配置级延后确认](#配置级延后确认与请求拦截)让用户稍后选择前置代理，不要求现在决定，也不在未确认时默认选组。该产品契约已经评审通过，尚未实现。

## 查询用途与唯一权威

只增加 DNS 执行所需的请求描述，不新增配置状态机或独立权限注册表。描述包含：父 BusinessScope／应用 lease、原始业务目标及可用字段、用途、已确定策略、允许的解析服务、网络快照和截止时间。调用者持有的 scope、真实出站对象和不可变配置派生该描述，外部 DNS 报文不能声明自己是启动解析。

| 用途 | 由谁创建 | 可查询什么、经哪里 |
| --- | --- | --- |
| 业务解析 | tunnel 已确定路由或 DIRECT／L3 出站真实解析入口 | 原始业务域名及必要别名；使用该业务 DIRECT 或代理策略 |
| 独立问题 | DNS listener／TUN hijack 的 ServeMsg 入口 | question 指定域名；先做保守路由判定，无法判定按前置解析约束处理 |
| 规则前置解析 | 实际 matcher 的 ResolveIP helper | 当前待判规则所需业务域名；只走显式前置代理，不能借节点启动许可 |
| 节点启动解析 | 真实出站适配器的 endpoint／ECH 消费者 | 该节点的 endpoint 或批准的 ECH 查询名；按 proxy-server-nameserver／policy；受父用途限制 |
| DNS 服务启动解析 | DNS 传输客户端 | 当前允许的解析服务域名；按 default-nameserver，仅供连接该服务 |

应用维护请求继续受 L1-T03 lease 管理；其后代 DNS 不得扩大父策略。普通 DNS 的派生、身份和预算按下一节新增内部契约，**不能直接调用当前 begin 并换一个 kind**：现实现只接受应用 lease 父，共用 128 上限，并按 kind:key 替换上一请求。DNS 子资格无配置／文件提交权，也不能取得任意应用请求或私有代理登录凭据。

父请求的许可须明确包含连接其代理／解析服务所必需的启动依赖。该狭窄依赖可以允许 endpoint 的 DIRECT 查询，却不授权父业务域名直连解析；没有被父资格与接受配置共同覆盖的启动服务仍然拒绝。不得把所有进入 ProxyServerHostResolver 的字符串直接加入允许集合。

T01 prepare 解析配置并生成不可变 DNS 派生信息，不发送查询；install 不开放独立 DNS。DNS 入口绑定在创建时捕获对应 activation 的 service、scope 与 writer 资格，activate 只是开放这份绑定；输入进入 ServeMsg 时不重新认领“当前 activation”。启动健康检查如已有应用 lease，沿其获准生命周期执行，不能借未激活的 DNS listener 提前开放普通业务。

### 内部派生、并发身份与预算

复用同一 appRequestRegistry 的 Owner／state／路由及 FD 校验和撤销，增加只供 Go 内部调用的 DNS 派生入口。它接受不可由 RPC 构造的父引用：当前 BusinessScope 或当前有效应用 lease；在 registry 的短边界核对父 activation／Owner／状态，关联父取消后才发表子资格，发表前再检查未失效。不得在 registry 锁内调用会反向取得同锁的 BusinessScope.Check；按已有锁顺序读取其内部资格。外部 begin／check／grant、requestOperationContext 及私有代理绑定都不得把 DNS ID 当作维护请求使用。

- 每个输入问题创建随机事务 ID，独立于 qname 和 kind:key；不进入 `latest`，同名同时到达互不替换。每个 TCP 连接可包含多个事务，但它们共享原连接 activation，不共享事务身份。普通／维护资源类只从可信父引用派生，不能由 kind、qname 或“启动解析”标签取得维护预算。
- 一次 LookupIP 的 A／AAAA、main／fallback 和协议重试是同一事务的分支；不同入站问题即使 qname 相同，也有独立事务。endpoint／ECH 及 DNS 服务启动子问题继承根事务及其预算，不递归申请新根名额；事务内的同一必要子问题可合并，不能跨根合并取消归属。
- 维护操作本身仍用原 128 个维护 lease 配额，普通业务 DNS 不占这个计数。维护 DNS 子问题也不重复占一个维护名额；其父操作继续受原上限约束。registry 内为资源类维护分别计数，不能继续对全部 map 条目用 `len(leases)` 实施原上限。
- 首版普通 DNS 上限为进程内 64 个活动根事务、256 条并行尝试链额度；维护 DNS 单独保留 32 个根事务、64 条额度。两类不可互借，因此普通 DNS 洪峰不会占满订阅／WebDAV 的维护配额。每根最多 4 条并行尝试链，其余在原截止时间内排队，服务集合不会因上限被偷偷删去。链上启动依赖复用同一额度，具体进展合同见下文，不能每层重取一个槽。
- 这些数值是初始资源上限，不是实测吞吐结论：64 根×每根 4 路给普通尝试设 256 上限，维护另有 32 根但最多 64 路，以限制辅助流量并行。后续实施可据本地资源观察调整数值，不能取消隔离、有界和失败反馈。复用现有 5 秒 DNS 事务截止时间并服从更短父截止时间；启动依赖栈最多 8 层，循环提前终止，避免只限制根而允许无界 goroutine／别名递归。
- 根名额用尽时不创建后台等待队列，入站给受控繁忙失败，维护父返回解析繁忙；新的独立尝试链在事务内有界等待且可取消。根／链额度只在对应任务退出、连接关闭或受控清理完成后释放一次，Owner 切换不会提前清零以突破进程上限。

计数和连接归属是同一 registry 中的资源管理，不判断运行意图或选择网络；不增加第二个状态权威。实现需同时调整 close／撤销／ID 查询消费者，使旧 DNS ID 既不能借新 Owner 权利，也不会误减维护计数。拟验收包括同名并发、A/AAAA／备用归属、配额饱和时维护功能及撤销后的名额回收。

#### 启动依赖的进展合同

每条获准尝试链只从根／资源类取得一次额度令牌。DNS 服务地址、代理 endpoint 或 ECH 的必要解析在该链内同步借用这个令牌；父暂停，子成为唯一可运行的网络尝试，**不等待另一个同根或全局槽**。返回后把执行权交回父，额度仍由原链持有；子不能释放父令牌，也不能换根／维护资源类。令牌只管理并发资源，查询资格仍分别按用途校验。

- 依赖中的 A/AAAA、多个启动服务及主／备用用这个借用令牌依次尝试，不能持令牌等待另一条需要额外槽的并行分支。首版不为启动依赖抢占或预留额外名额；普通根的四条主／备用链仍可并行，依赖内部的并发改为串行是明确的性能取舍。
- 优先在打开父连接前完成已知地址／ECH 依赖；若协议在握手中才请求依赖，父连接只可暂停，不再发送，子借令牌执行。每层最多保留一个暂停连接，最多 8 层（含当前层），所以一条链最多拥有 8 个活动／暂停传输连接；256／64 是尝试链上限，不能冒称等于 socket 数量上限。对应最坏连接上界分别为 2048／512，实际 client 还须遵守每层一个传输连接的限制。
- 一层需要协议探测、重连或 UDP→TCP 时先结束／关闭被替代的本层连接，不并存第二条；无法满足单层边界的 client 明确拒绝，不能无计数开旁路。共享 WG device 等既有节点资源不是事务新建的传输连接，不因借令牌关闭；本次经 stack 建的 DNS 流计入本层。
- 依赖访问栈和截止时间随令牌传递，循环／第九层失败；root 取消会取消栈上全部子问题、关闭活动和暂停连接。子失败直接返回父失败，不再排队为自己申请额度。完成／取消收敛后由唯一链拥有者释放一次，根等待所有链退出再释放根名额。

因此同根四个域名 DoH 服务各占一条链时，它们的启动 DNS 各借自己的令牌即可到达 IP 叶服务；即使该资源类的全局额度已满，也不依赖第五条链才能进展。网络自身超时仍可失败，但不能由自己的额度等待形成假超时。V9 覆盖四路全部需要启动解析的成功、全局饱和时依赖仍进展、依赖超时／取消与额度／连接回收。

### 输入与回复绑定原 activation

| 输入入口 | 冻结时点 | 后续资格与清理 |
| --- | --- | --- |
| 独立 DNS TCP listener | accept 时，将该 listener 的不可变 service／scope 绑定到连接 | keepalive 所有问题沿原绑定；旧 activation 退役即关闭连接，不从新 Server.service 取资格 |
| 独立 DNS UDP listener | 包被读出、进入异步 handler 前，随 listener 绑定一起入队 | handler、缓存、错误及 socket writer 使用该包的绑定；不在 ServeDNS 时加载全局当前 service |
| TUN DNS TCP hijack | NewConnection 判断 hijack、开始 relay 前，从这个 TUN 入口绑定取得原 scope | relay 每条问题沿原连接资格；旧 flow 不借后来替换的 DefaultService |
| TUN DNS UDP／packet connection | 每包读取／交付给 NewPacket 后、启动 relay goroutine 前 | 包、事务、writer 共用入口的原 scope；旧 packet connection 不升级绑定 |

同地址重配也生成新的不可变 DNS 入口代际，关闭旧连接／监听并有界排空旧 reader，不能沿当前 `SetService` 原地换指针。创建期间的协程捕获自己的 Server／binding 对象，不能稍后写入全局新 server。新入口可以按 T01 在 install 准备，但 scope 未 active 时不处理问题；物理监听失败沿原失败契约处理。TUN 旧 TCP／packet flow 随原资格清理，后续新 flow 才使用 B；可能需要应用重建 TCP DNS 连接，不能为了维持 keepalive 把 A 升级为 B。本契约以应用已 accept／已读取的数据为边界，不声称能从尚未读取的内核 UDP 数据辨认发送方当时使用的配置代际。

全局 ServeMsg 仅做带资格分派：必须使用输入已携带的 binding，不允许没有绑定的旧输入改取新的 DefaultService。正常、fake-ip／hosts、cache、REFUSED／SERVFAIL 和解析失败回复，以及库层自动错误回复，最终 TCP／UDP 写路径均经过原 writer 的资格检查；旧资格失效后关闭／丢弃，**不额外发一个错误回复**。TUN writer 在实际 WritePacket 前同样核对，保护原 writer 生命周期并只释放一次 buffer。已经进入内核的回复仍遵守既有不可撤回边界。

## 路由和解析的先后

### 已有完整业务流

1. 沿生产流程还原 fake-ip 对应域名、处理 hosts 和已完成的 TCP／UDP 嗅探，再使用实际入站、业务端口、进程、Network、SpecialProxy／SpecialRules 及 RuleHost 调用现有 `resolveMetadataScoped`／`matchScoped`。不能在嗅探前用 qname 冻结一个与后续实际路由不同的业务策略。
2. matcher 不需要 IP 即可选出 REJECT 时立即结束，不真实解析。选出 DIRECT／代理后才创建相应用途。能够把域名交给代理端的 TCP／UDP 协议继续远端解析；必须拿到真实 IP 的 DIRECT、L3 或协议路径使用受约束的客户端查询。
3. IP 规则实际调用 ResolveIP 时，使用「规则前置解析」，完成后在同一次匹配中继续；保留已匹配规则的顺序和 `no-resolve` 语义，不把整个规则集重跑成另一套规则。
4. 当前 helper 返回 void，解析失败会缺少可用 IP。实现时需在 matcher 所在调用边界传播终止错误；失败不得作为 IP 不命中而继续落到后续 DIRECT。NOT、逻辑规则、子规则中的失败也必须终止该次决策。
5. 规则确定后，后续确需 DNS 的出站拿到同一用途描述。默认 resolver、DirectHostResolver、ProxyServerHostResolver 只作为服务选择入口，不拥有把业务用途变成启动用途的权力。

### 独立 DNS 问题

DNS 的目的端口 53、来源应用和 UDP/TCP 类型不是未来业务流的对应字段，不能据此匹配业务规则。保守资格覆盖实际路由的**入口、预处理、规则匹配、控制流及代理展开**，不只是规则对象。每项输入区分「已知值」「已知为空」「未知」；qname 是已知的查询名，未来业务 RuleHost、SpecialProxy／SpecialRules 默认未知。

1. **先证明路由入口。** 从当前 activation 的普通业务入口绑定读取相同的不可变入口描述。只有所有可接收后续普通业务的入口都能证明有效 SpecialProxy／规则表入口相同，才把这些值视为已知；都没有覆盖时才是“已知为空”。某入站用子表 B、主表为 A，或存在专用 proxy 时，独立 DNS 不能选择主表假装未知入口不存在。入口插件无法描述其附加信息时也未知。首版不枚举不同入口求“恰好同结果”，而是进入信息不足路径。
2. **判断业务 RuleHost 是否已知。** 真实 RuleHost 优先 SniffHost。当前嗅探配置及所有可能的未来协议／端口若可能改变它，凡依赖 RuleHost 的路由判定均未知；OverrideDest=false 不足以证明不改变匹配。首版只有嗅探关闭／没有可能参与的 sniffer，或同源预处理能力能在已知输入上证明绝不替换时，才把 qname 当已知业务 RuleHost。不能用过滤“被嗅探出的域名”的 skipDomain 规则猜未来 SNI。已知的、与域名无关的固定入口／模式决定仍可沿真实入口返回，不必额外模拟嗅探。
3. **共用实际 matcher。** 给其入口及分支增加所需字段查询；满足后仍调用同一规则对象的 Match，沿 SpecialProxy 优先、SpecialRules 选表、模式、原规则顺序及末尾 DIRECT 处理。纯 DOMAIN／GEOSITE／domain RULE-SET 只有在本节入口和 RuleHost 资格已满足后才可判定。AND／OR／NOT、SUB-RULE 和 classical RULE-SET 用实际解析对象的依赖并集；不足即整条未知，不另写三值 matcher、不重解析 Payload。
4. **包含命中后的能力分支。** 真实 matcher 会在业务 UDP 且候选不支持 UDP 时继续下一规则。未来 Network 未知时，只有真实候选及可能选择链能证明 TCP／UDP 都不会因能力发生不同控制流，才可继续；否则立即信息不足。例如 `DOMAIN,example,A`、`MATCH,DIRECT` 且 A 不支持 UDP，不能按 TCP 选择 A 对这个独立问题外发。DNS 自己选择 DoH／TCP 不会补齐未来业务 Network。
5. **包含代理展开与控制适配器。** PASS-RULE、REMATCH、选择器、自动组和负载均衡沿现有实现消费同一字段资格；按来源／入站用户的负载均衡缺字段就未知。展开可能触发 pass／rematch、依赖未知业务 metadata 或能力不明确时，不能先伪造 metadata 选一个叶节点。未知 rematch 不试拨号；禁用规则保持原语义。显式入站 proxy 不因 Rule 模式而忽略，Global 也先服从真实 SpecialProxy 优先级。
6. **规则数据同源。** RuleProvider 当前没有 ProxyProvider 那样的 Version 接口。依赖描述与不可变 strategy 同次发布，通过窄快照接口供 Match／依赖共同消费；入口、嗅探及组的能力描述也来自当前实际对象，不另存按名字猜测的规则表。变更使旧证明失效，新查询重取快照。

在第一次可能影响结果但资格不足的位置返回信息不足，不能继续找后面的 DOMAIN、REJECT 或 MATCH，也不以“没有匹配”返回 DIRECT。该策略的可用性影响比首稿更广：即使规则全是域名，启用可改变 RuleHost 的嗅探、入口使用不同子表，或某候选不支持未知的业务 UDP，也会阻止独立真实查询。fake-ip 的本地地址回答仍可延后到完整业务流；normal／redir-host、fake-ip filter 和非地址记录可能需要经批准的前置例外，否则明确失败。

若 fake-ip 允许本地回答 A/AAAA，先校验 scope；可证明 REJECT 时返回拒绝，其余可返回合成地址且不外发，最终分流留给真实业务流。hosts 中已有 IP 同样不外发，但不作为绕过业务 REJECT 的授权。fake-ip filter、真实记录类型、redir-host／normal 模式进入上述真实查询判定；不能静默改 DNS 模式。

正常正例：入口、RuleHost 及候选能力资格已充分，已接受的 [GEOSITE](../../../../core/Clash.Meta/rules/common/geosite.go) 集合可直接按域名匹配，无需先查目标 IP。按原顺序命中指向 DIRECT 的域名／GEOSITE 规则，DNS 使用适用的 DIRECT 服务；命中代理 A 则查询经 A，或由适用协议交给代理端。域名／GEOSITE 均未命中，但没有更早 IP／未知条件阻挡、继续到明确 `MATCH,A` 时，也正常使用 A 的 DNS 策略，不需要前置解析许可。它减少常用配置对 IP 前置查询的需求，但不跨越早先的 IP 规则、嗅探或入口歧义；不自动重排，不把 GEOIP 替换成 GEOSITE，也不复制规则集。

### 需要 IP 或信息不足时

用户可为当前配置显式选择已有代理／代理组作为前置解析出口；有效配置用 `dns.pre-route-proxy` 展示该派生值，不新增解析接收方清单。默认未确认且无值，不能在业务出口未确定前查询。用途仍分为规则前置解析，以及本设计约束下不能确定未来业务出口的独立真实 DNS 问题；后者的缺端口／入口／嗅探等原因不能被改称“只差 IP”。

指定后，查询仍使用已接受的 nameserver-policy／main／fallback 接收方，但传输固定在该代理策略内；system／明确本机意图的解析服务及 DIRECT 不能成为前置代理的替代。远端私网服务可按兼容的代理标记访问，不能只按私网 IP 拒绝。代理组或节点不存在、循环依赖、UDP 能力不足或选到 DIRECT／COMPATIBLE／PASS 时失败。该字段需要在最终配置身份和有效配置说明中可见，普通订阅变更不能自行获得新的前置解析授权。

授权来自当前配置详情中的显式确认，按下一节进入 T01 acceptedOverrides／新不可变输入；不加入全局 DnsOverrideKey 或 baseline。现有 DnsView 是全局覆写入口，只复用其展示组件，为此增加明确绑定 profile／当前输入的独立区块。源 profile、订阅、脚本及全局 DNS 快速编辑中的同名键均不能创建用户同意；原始 YAML 的派生字段也不作为许可。组内容仍受当前节点／来源信任边界限制，来源委托的完整交互由 T05 接续。

这是一个**前置代理例外**：最终业务可能匹配 DIRECT、另一个代理组，或 IP 规则 REJECT。客户端在拿到 IP 前无法知道该结果，前置代理及所选 DNS 会先看到域名；不得把它描述成总能跟随最终分组。未设置时相关访问明确失败；用户可改用能提前决定的规则、代理端解析或 fake-ip 等适用路径。不得为了提高成功率默认选 GLOBAL 或第一节点。

明确的 LAN 域名应在 IP／其它未知规则之前有可判定的 DIRECT 路由和本地 nameserver-policy；否则拒绝该真实查询并说明缺少确定策略，不能先把 LAN 名称发给公网前置代理。

## 配置级延后确认与请求拦截

人类允许把运行策略的选择延后到应用内，并授权复杂时采用推荐方案。本项据此保留原 matcher、规则顺序及其权威，不提供“GEOSITE 另行优先”或“仅 DNS 用另一套 GEOSITE 分类”的路由模式。前者需要显式改变规则语义并处理被跨越的 REJECT／未知条件，后者会使直连 DNS 先发生而最终业务走代理；为此维护两种语义超出最小充分方案。用户仍可稍后为当前配置选择一个前置代理，或者暂不处理并保持相关请求被拒绝。

### 规则语义与用户实际选择

| 场景／操作 | DNS 与业务的有效语义 |
| --- | --- |
| 原规则顺序先命中 DOMAIN／GEOSITE，必要入口／RuleHost／能力已充分 | 原 matcher 同时决定 DNS／业务策略；后面的 GEOIP 不再执行 |
| GEOSITE 未命中，先到明确 MATCH 代理，前面无 IP／未知条件 | 正常按该代理处理，无需前置许可 |
| 原顺序需 IP，且当前没有可合法使用的地址、确实需要前置查询 | 不能跳去找后面的 GEOSITE；未确认时拒绝，确认后经指定前置代理取得 IP，再继续原 matcher |
| 当前配置显示“选择代理并确认”，用户提交有效代理／组 | 允许该配置绑定范围内的前置问题经此代理；最终 GEOIP 可以选择 DIRECT、另一组或 REJECT，这个前置接收范围在确认页明确披露 |
| “稍后处理”、返回、关闭通知或无选择直接关闭 | 保持未确认，不创建许可，也不挂起／重放请求 |

选择器不预选 GLOBAL、第一节点、DIRECT 或上次另一配置的值。提交前展示当前配置、待确认原因、可能使用的已接受解析服务／政策摘要及前置代理、允许的用途与上述最终出口可能不同的例外，不展示真实待访问域名。许可明确覆盖规则 IP 前置和按前文独立 DNS 资格仍需例外的真实问题；缺端口／入口等未知不被“确认”成已知，实际查询仍需通过各用途限制。选择组表示接受其本次已列明成员范围内的自动选点，并非承诺固定节点。

GEOSITE 使用本次接受配置所引用的资产／类别及规则顺序；数据库本身不自动决定 DIRECT。较早的 REJECT、原入口／嗅探／能力未知、本机意图及组内自动 DIRECT 禁止均继续生效；确认前置代理也不能补造缺失的业务 metadata、把 GEOSITE 结果写成新的 SpecialProxy，或重跑含 GEOIP 的“默认路由”解析前置服务。

### 受影响请求与确认前的零相关外发

前置许可只控制确实需要的前置查询／独立问题例外，不是所有目的 IP 规则的额外运行许可。受影响与否由同一真实入口／matcher 的实际信息需求派生：

- 完整业务入口、RuleHost、Network 等已经充分时，当前真实目标 IP、接受配置中的 hosts，或本次用途／activation／网络／政策键均合法的已有地址，可作为数据按原顺序匹配 IP-CIDR／GEOIP／REJECT／DIRECT；无需先选一个不会使用的前置代理。地址不授予路由许可，仍由真实 matcher 决定，实际目标还受已审固定／WG 最终 IP 校验约束。
- 只有实际缺少所需地址、ResolveIP helper 确需发出前置查询时，才在查询前检查本配置决定；未确认即失败，不把失败当规则未命中。`no-resolve` 保持原语义：有合法 IP 就匹配，没有且按原语义不解析就跳过。不得为绕过拒绝清除原域名、隐藏地址或改变规则顺序。
- 旧 activation、跨用途、失效网络／政策或错误 cache 键的答案不算当前合法数据；不能凭一个“缓存命中”标签补地址资格。若因此仍缺地址且需要查询，回到未确认拦截。独立 DNS 缺未来入口／Network／RuleHost 时仍未知，一个 hosts／缓存 IP 不能补出这些字段；仍需按前文资格处理其独立问题例外。
- 确定合法 DIRECT／代理／本地服务、已有合法 IP 的拒绝及不消费此决定的纯 IP 访问照常处理。fake-ip 仅按既有边界推迟实际业务判定，不放行后续业务；需要独立真实问题例外而未确认时，不先发系统、节点或 DNS 服务启动查询，也不返回不满足当前资格的本地答案伪装已获准。
- 接管入口只有真实 IP、无可恢复域名时，不能凭历史猜它对应哪个被拒域名；按该真实输入处理，不宣称此前域名已获准。fake-ip 还原、hosts／映射及客户端可控制的解析路径必须保留原业务域名资格，不能利用内部转换制造这种信息丢失。

门位于第一次相关外发前，先于业务出站初始化及其 endpoint／ECH／解析服务的启动依赖。未确认返回受控 `dns_policy_confirmation_required` 原因；DNS wire 对策略缺许可用 REFUSED，业务失败并释放连接、buffer、事务和名额，不加入挂起连接或逐域名队列。确认后只接受新输入／新业务请求，旧失败请求不自动重放；客户端自行重试属于新请求并重新核验。

零目标 DNS 正例：完整上下文充分，合法 hosts 为 `example.test → 203.0.113.10`，首条 `IP-CIDR,203.0.113.0/24,DIRECT,no-resolve` 时可直接按该地址走 DIRECT；改为 REJECT 时直接拒绝。二者不要求前置确认、不发该目标 DNS。若删除地址、对应规则允许解析且确需查询，则未确认时相关外发为零；若只保留 `no-resolve`，继续按原 matcher 跳过，不自行增加查询。

### 待确认事实、入口与隐私

当前 Core 从实际接受输入、规则／入口依赖和生效 acceptedOverrides 派生 DNS 决定事实，通过现有 config_state／getConfigState 返回：配置身份、基础语义键 `decisionKey`、`unconfirmed`／`confirmed`、前置代理及其定义摘要（如已生效）、有限原因码及“部分请求需确认”标记。原因仅分目的 IP 前置和独立问题上下文不足等固定类别；不含 qname、URL、用户请求内容或逐项历史。

prepare／恢复时可从当前依赖计算是否存在需要决定的路径；没有这类路径时不显示待确认项，无需先等一次用户访问，更不持久化访问列表。当前请求在更细条件下遇到该门时返回同一事实入口，不创造另一份审批状态。重启和 Flutter 重新连接时从 Core 当前输入／恢复引用重取；事件遗漏时 `getConfigState` 补齐。Flutter 缓存、旧通知和本地展示不决定许可。

`confirmed` 只表示选择与当前绑定匹配，不表示每个请求必定可用。所选组此刻选到 DIRECT、节点失效、协议能力不足或 DNS 服务与用途冲突时仍按已审合同失败，展示实际失败原因，不能靠重复确认放行；组仍存在且绑定未改变的暂时网络失败不清除用户选择。

依赖事实从与 matcher 同次发布的不可变 strategy／资产／组内容摘要读取，实际改变时沿现有 configFact 版本序列发布新事实，不另设运行意图计数器。获取／发表前核对同一当前输入和依赖快照，不能把旧摘要拼进新 Owner；不在包装层锁内读取大文件或等待网络。依赖未就绪或无法证明同一快照时为未确认／不可用，不能按上次 confirmed 乐观显示。

配置详情显示当前实际应用配置的待确认项；DnsView 复用一个明确标注“仅此配置”的区块，与原有全局 DNS 覆写分开。当前选中 profile 与实际 Core profile 不一致时不能批准另一输入；没有可核验 Core 输入时仅可保留临时界面草稿，不构成许可。通知只给通用入口，例如“有配置的 DNS 策略待确认”，不含域名／URL清单、令牌或会被全文记录的请求内容；关闭通知不改变事实。无需新增待办文件、数据库任务表、后台审批服务或必达通知承诺。

### 确认提交与 T01 应用结果

打开页面读取并展示当前 `{runtimeEpoch, Owner, inputId, profileId, configFactVersion, decisionKey}` 和有效代理候选。只有当前已完成应用／加载、可核验的接受输入才可提交，parsing／install／替换过程显示应用中并禁用确认；不能对暂态候选批准。提交携带这份预期身份、所选组及其定义摘要；现有受控客户端／数据来源资格和 Core 的短边界一起核验它仍是展示的当前输入。仅名称相同、UI仍显示相同 profile 或候选列表未刷新不足以通过；过期提交返回“配置已变化，请重新查看”，无副作用、无自动套用到新输入。

确认以窄的配置变更入口生成候选，复用当前已接受的不可变 YAML／manifest，不能为此重新拉订阅或运行脚本再把用户点击套到新内容。选择和绑定证明进入受控的 `acceptedOverrides.dns-policy-choice`，再经现有 T01 新输入、prepare／install／activate；Core 对 expected-old-input／来源及依赖内容摘要再次核验。动态 provider 在此期间变化则拒绝这次确认，不把 B 的点击用于 C。不能由普通热参数、源 YAML、全局编辑器或订阅字段制造这份 choice；`dns.pre-route-proxy` 仅展示该 choice 派生的有效值。

候选期间 UI 显示“正在应用”，没有激活确认前不宣称新策略生效。成功后 config_state 的新 inputId 和 confirmed 事实才是结果；profile 偏好只作带成功身份的可丢弃缓存，按下一节核验写入，不能直接作为下一输入的授权来源。仅新 activation 的新请求获得许可，旧包／旧 TCP／旧回复沿已审原 binding 退役，不能借确认复活。

确认只是该输入的配置变更，不是启停意图；沿现有 ServiceState／ExpectedRun 资格保持当时启用／暂停状态，不因点击确认自动启动已停止服务。并发 stop、配置切换或来源撤销使候选过期时不重放确认，也不替新操作恢复旧运行意图。

失败沿 T01：旧输入仍适用时保留旧有效配置及它原有的未确认／已确认语义；否则按原失败契约关闭受影响入口，不安装默认策略。记录接受输入／checkpoint 的权威写失败不能只改 UI 为成功。用户以后可改选或撤销，仍形成新 T01 输入；撤销成功后新的确需前置查询失败，已有合法 IP 的正常匹配不因此被禁止，旧在途范围按原资格撤销。

#### 成功回执与偏好缓存的有限提交

Core 成功结果带当前 `{runtimeEpoch, Owner, inputId, configFactVersion, profileId, choice状态及绑定}`，对应实际接受的 T01 receipt／checkpoint；撤销也有成功身份和明确的无许可状态。不能只用历史 K 判断写入先后：A、B 各自合法不意味着迟到 A 仍是当前意图。

- profile 缓存更新复用 Request.mutate 和现有有限 data-commit receipt，新增该用途的 expected-success 核验。Core 按既有锁顺序在实际授予缓存写的短边界检查原成功 receipt 与当前已接受身份／状态完全一致，再登记既有有限提交；不是 UI 先 getConfigState、任意 await 后直接写库。旧回执、旧 epoch、已撤销或已被 B 替代的 A 一律不授予写。
- 这段有限提交与 T01 输入读取沿既有 data-reader／commit 互斥：A 获准时先完成其有界本地写再允许后续确认／撤销进入新的 prepare；若 B 已先成为当前接受结果，A 在授予边界失败。Core 锁不跨异步 DB IO 持有，写完成／失败及时结束 receipt，崩溃与不明完成沿现有 partial-commit／恢复边界，不另建事务日志或审批状态机。
- 实际 DB 更新仍以 profile 与预期旧缓存身份作条件写，保存当前成功身份和选择值；撤销保存带该新身份的空选择，不能裸删除后丢掉防迟到覆盖的当前标记。迟到 A 不得覆盖已保存 B／撤销。跨进程不简单比较数值版本，必须有当前 Core 授予和缓存条件同时成立；条件失败丢弃旧写并重取当前事实。
- 缓存条件写只更新该 profile 的非权威 DNS 偏好字段，不把旧 Profile 整行写回，不改 URL／源类型或覆盖 B 的其它编辑。该缓存不属于来源身份或原始配置内容，不因缓存维护自身撤销刚确认的来源；实际来源编辑仍按来源失效合同执行。
- 缓存写失败不回滚已经成功的 Core 决定，不把失败缓存重试成旧许可：UI 仍以当前 config_state 为准，提示偏好需刷新；恢复、重连或重试时从当前接受 checkpoint／receipt 重新读取并重建缓存，不能继续提交捕获的旧 A 载荷。权威 checkpoint 写失败则仍按上一节 T01 失败契约处理，二者分开。
- 后续组合只可在可信边界从当前 Core 接受输入取得选择，核验同 profile、当前成功身份及 B／G 后承接；profile 缓存和旧不可变 manifest 中“曾有效”的 K 不能反向覆盖当前 Core 的 B 或撤销。旧 epoch 的缓存、缺当前权威恢复证明时只显示草稿／未确认。

首版不为非当前 profile 建立另一份授权历史库。切回其它 profile 时，若只有旧偏好而没有当前权威可核验的该配置决定，保持未确认，偏好仅可帮助展示候选；不能自动升权。相同当前配置的无关更新、正常重启／恢复仍可由当前 T01 权威承接，不要求重复确认。

V10 设置 A 成功后缓存写暂停、随后 B 或撤销成功并保存，再释放 A 的交错，断言当前 Core、profile 缓存及后续新输入均不能回到 A；并覆盖 A 在有限提交中先线性化、B 随后完成的顺序、缓存失败后重连／崩溃恢复、旧 epoch 回执、撤销空状态的迟到覆盖保护。所有检查仍为未来计划。

### 确认范围、保留与失效

区分严格的提交身份、基础语义键 B 与确认绑定键 K。`decisionKey=B` 从当前相关输入派生，排除 choice 本身及其派生的 pre-route-proxy，避免自引用；提交另带选中组的定义摘要 G，Core 成功核验后保存 `K=H(策略版本, profile范围, B, 所选组, G)`。提交必须匹配展示的精确当前事实；已确认选择的保留比较同一相关内容绑定，不能直接用整个 inputId／parsedSHA 或进程内递增 dataset 计数要求每次重确认。B／K 是接受输入中的内容指纹，不是第二套分流规则。

B 覆盖逻辑来源身份、规则／子表顺序和匹配选项、路由入口／嗅探资格、DNS 有效服务／政策及启动依赖、引用 rule-provider／Geo 内容和相关路由定义；G 覆盖所选前置组、成员及其出站／递归依赖的规范化定义。profile范围沿本地受控 profile 身份和 T01 来源／恢复资格，不把进程内计数当成永久身份。摘要仅本地生成并保存比较值，不以单纯组名、指针或瞬时 Now 充当内容身份。源身份改变或同名服务／组换定义不能承接旧同意。相关引用沿现有解析对象取得，不复制 matcher；首次待确认不需要先假造一个已选组才能计算 B。

H 采用现有内容寻址同类的 SHA-256，对 Core 规范化语义作确定性序列化；规则、DNS policy 和候选顺序有意义时保序，无序对象才排序键，不直接用 YAML 排版或注释作比较。逻辑来源包括本配置依赖资源与接受的订阅／provider／Geo／脚本来源身份；敏感地址／节点选项只参与本地摘要，不写进通知或待确认清单。

#### 逻辑来源快照的可信采集与承载

当前 manifest 的 dependencies 和 source ticket 只有资源 key／版本，不能证明 DB 中的订阅 URL／源类型。新增最小版本化 `sourceOrigins` 到同一不可变 ConfigManifest；它来自受控组合边界，不从最终 YAML 或脚本返回值读一个自报的“来源证明”。不建立新的来源审批平台。

| 来源材料 | 身份从哪里取得与冻结 |
| --- | --- |
| 主 profile 及被注入的 profile 依赖 | 可信 DB 记录的 profileId、file／subscription 类型及真实订阅 URL；本地文件按受控 profile 资源身份，远端 URL 含影响来源的组成参与本地摘要 |
| 被采用的脚本 | DB 的 scriptId、local／remote 类型、真实脚本 URL，以及本次实际执行的脚本文本摘要；不接受脚本声称自己的来源 |
| app 管理的 clash-provider／本地规则依赖 | setupState 实际采用的管理 ID、类型、URL／本地资源和关联关系；不是相同 label 就可替代该管理记录 |
| 源 YAML／脚本输出中的 provider、Geo 及 DNS／节点依赖 | 绑定所属已冻结 profile／脚本根来源及最终实际使用的地址／类型；Core 对同一接受配置派生部分复核，资产内容另按实际加载摘要绑定；不能自报成一个 app 管理 ID |

最小记录包含 resourceKey、kind／逻辑资源标识和规范化身份摘要，必要时有实际输入材料摘要及依赖关联；不额外持久化一套 URL／凭据明文。sourceRevision 用来证明同一轮采集仍有效，不作为跨重启的稳定身份。由上述实际元数据变化计算不同身份摘要，因此同 profileId 从订阅 A 改 B，即使生成字节完全相同也会改变 B／K。

采集在现有 [setup 组合](../../../../lib/providers/actions/setup.dart) 的 Request.mutate／数据读写边界进行：读取实际 DB 记录、取得全部被采用的 RequestSource，并复制本次原始配置／脚本文本及来源元数据为一个不可变组合材料包。生成配置只消费这份材料，不在 await 后重读旧 id 下的新 URL 或新脚本。必要的大文件读取可以在受控读资格下完成，来源变更后不得把旧文本与新元数据拼接。

生成后、ConfigInput.write 前对每个捕获来源运行现有 configSourceCurrent 并核对采用集合；任何 key／版本／所用材料不再一致就放弃整个候选并重新捕获，不只替换证明字段。`ConfigInput.write` 接收可信采集函数产生的冻结 origins／关系对象作为独立参数，不能从 YAML map 反序列化成这种可信材料；随 YAML 摘要、dependencies 和来源票据绑定到同一内容寻址 manifest，不把来源字段混入 handleEvaluate 的可写返回对象。普通 YAML／订阅／脚本中的同名键忽略或拒绝，不能填充这个参数。

初次来源快照还记录捕获轮的 client／dataset／各 sourceRevision 向量；fresh prepare 同时核对它与请求票据及当前 registry 一致，不能在旧 origins 上随便换一份当前票据。来自当前已接受输入的确认／热更新可由 Core 在已有 CAS 边界证明复用同一 origins 摘要及材料，不需伪造一次新 DB 采集；新 manifest 仍包含完整快照，不建立需要遍历的授权历史链。

Core prepare 校验新版本 schema、每个被采用来源的覆盖／关联、manifest 内容摘要及上述 fresh capture／受控承接资格；对最终解析对象实际存在的 provider／Geo 地址等再次核对绑定，不能为缺失的 DB 元数据猜一个 URL。通过时把冻结 origins 留在 prepared input 及已接受 manifest 中，确认生成的新输入和后续 checkpoint 也承接同份材料，不只保存 B／K 而丢掉其必要来源依据。

改变 profile URL／类型、脚本 URL／内容或相应 provider 管理来源的受控写入，必须沿现有 invalidate／来源版本与 checkpoint 撤销边界先持久失效旧恢复引用，再提交材料变更；字节未变也不能省略。Core 未连接或撤销写失败时，也不能只改 DB 而保留旧可恢复许可，应使本次源编辑失败／进入既有不明提交恢复边界。冷恢复只从 T01 当前仍有效 checkpoint 所绑定、带有完整 origins 的接受输入重取，检查内容完整性和恢复资格，再复算 Core 可核验的派生内容；不把重启后的新计数贴到任意旧材料上冒充 fresh capture。恢复资格不明或来源已撤销时不能承接许可。

旧格式／缺 origins／覆盖不全的输入保持前置未确认；确定合法、无需前置的业务仍可按原合同工作。要取得前置许可，先由可信组合路径形成带完整来源快照的新输入，再展示其当前确认页；不能读取“现在的 URL”补签过去无法证明来源的旧 YAML。此补齐不增加网络拉订阅或完整来源委托机制，T05 的身份／委托／高影响变化审查仍未被替代。

| 变化 | 已确认选择如何处理 |
| --- | --- |
| 同一配置重启／恢复、Flutter 关闭再打开，T01 来源核验和 K 均相同 | 从同一已确认输入恢复，不重复确认；旧 runtimeEpoch 不可用于新的提交／请求 |
| profile 改名、日志／显示／统计参数等与 K 无关的更新 | 保留决定，正常生成新输入；打开中的旧表单提交仍因精确事实变化被拒绝并刷新 |
| 换到另一 profile、复制／导入或删除后重建配置 | 不跨 profile 复制确认；切回只有旧偏好而无当前权威证明时也不升权；来源 YAML／全局设置不带许可 |
| 来源身份、规则顺序／入口／嗅探、DNS接收方／启动服务或前置组定义改变 | 相关 K 改变，未确认；确定合法路径继续，受影响请求在外发前失败 |
| 引用 rule-provider／Geo 内容改变 | 内容绑定改变则失效；首版对整个被引用资产摘要保守处理，不按未证明的类别等价继续；未引用资产不影响 |
| provider 重载／同名对象替换但相关内容和来源身份完全相同 | 新输入可在可信组合边界核验后承接同一 K；不能仅因版本号或名称相同承接，旧在途对象仍按原规则撤销 |
| 已确认组的健康切换／明确选组，仍在本次已接受成员范围内 | 不为瞬时叶节点重复确认；前置始终拒绝 DIRECT／COMPATIBLE，原在途及手动 DIRECT 来源契约不变 |
| 节点端点／协议／凭据／成员范围／递归代理定义改变，或已选组消失 | 相关定义摘要改变即失效／显示不可用；不得把同名新组、默认 GLOBAL 或接口当替代 |

sourceRevision／运行对象变化仍影响 T01 来源资格和在途取消；只有相关内容和逻辑来源均可证明未变时，后续新输入才可承接当前选择，不以“用户以前点过”跳过核验。无关变化不强制重复确认；无法证明等价的相关变化保守失效并说明原因。profile 删除／数据集撤销时清除对应偏好引用；导入／恢复不能把别的配置的元数据当作用户点击。

每次消费许可和相关外发都核对当前 B／G 与已确认绑定，不能只因 profileId／Owner 未变就继续。绑定失效使尚未完成前置解析／拨号的相关事务取消，旧答案不发表；新请求重新判定是否受影响。已建立业务连接继续服从T01 与本文在途生命周期，不把这项延后确认扩展为新的全设备接管保证。

## 接收方、出口与配置兼容

### 使用现有接收方配置

| 已确定用途 | 接收方来源 | 传输出口 |
| --- | --- | --- |
| DIRECT 业务 | direct-nameserver 非空时用该集合，follow-policy 开启才优先匹配 policy；为空时沿当前主 resolver 的 policy／main／fallback | 已接受 DIRECT，通过当前合法物理网络；不因主解析失败另用 SystemResolver |
| 代理业务 | 一般为 nameserver-policy，未命中时 main／fallback；选中 WG 且启用节点专用 DNS 时按下节消费合同 | 业务选中的代理策略；DNS 连接不再按解析服务域名重新选业务组 |
| 本机 LAN 域名 | system 源或明确标记 `#DIRECT` 的域名政策，并能证明 DIRECT | 对应该解析器的物理网络；不添加公网备用 |
| 代理可达的远端私网域名 | 接受的域名政策，例如 `10.20.0.53#CorpProxy` | CorpProxy；私网 IP 不自动变成本机 LAN／DIRECT |
| 前置解析 | nameserver-policy／main／fallback | 显式 pre-route-proxy；没有此许可即失败 |
| 节点 endpoint | proxy-server-nameserver-policy／proxy-server-nameserver；为空可承接当前 main 服务集合，但仍限定 endpoint 用途 | 按这些启动服务已接受的出口；无显式代理选择时允许启动 DIRECT |
| DNS 服务 endpoint | default-nameserver；只允许已接受的 IP 服务或显式 system 源 | 已接受的启动出口；仅解析当前 DNS 服务地址 |

DIRECT 的 direct-nameserver 非空且不 follow policy 时，若某个 LAN 域名需要另一解析服务，应明确开启 follow policy 并提供匹配政策，或使用该集合内对应本地服务；不能宣称写了 nameserver-policy 就必然覆盖 direct-nameserver。

本机意图的可执行判据为：`system://` 固有地使用当前物理网络 DNS；对固定地址服务，域名政策中**显式 `#DIRECT` 加上已证明的业务 DIRECT** 才声明本机直连意图，私网地址再决定它属于 LAN 服务。`#DIRECT` 与代理业务冲突即拒绝。裸私网 IP 没有本机意图标签，按已确定业务出口传输；代理标记 `#CorpProxy` 表示远端可达性，不能因 RFC1918／ULA 地址而强制 DIRECT。本地政策识别用于防止外送已声明本机的域名，不用于把所有私网 DNS 禁止经代理。

例如 `DOMAIN-SUFFIX,corp.example,CorpProxy` 配合 `+.corp.example → 10.20.0.53#CorpProxy`：该业务及问题经 CorpProxy，接收方为远端 10.20.0.53，不绑定本机 LAN DNS 网络。若把标记改为 `#DIRECT`，与业务代理冲突而失败；若使用 `system://`，也不能悄悄从本机网络取 DNS 并直连发问题。没有标记时继承业务 CorpProxy。只看到私网答复、域名含 `lan` 或一个私网服务地址，都不能补造本机意图。`.local` 多播发现不转成公网 DNS；没有明确可用本地路径时失败。

接收方选择与出口分别约束：现有 `#组`／`#DIRECT` 作为额外出口约束，只有与已决定用途兼容才执行；不悄悄忽略它。缺失名称、接口写法或不兼容组在 prepare 可识别时拒绝候选配置；依赖动态选择的冲突在发送前失败，不回退其它接收方。任意接口别名不再作为 DNS 代理名字失配的兼容解释。

`respect-rules` 保留为旧配置输入，但业务查询的出口由业务策略约束；它不能改变已确定的业务出口。最终配置说明明确这一语义变化。与业务用途冲突的旧 DNS 服务规则不会静默胜出；无法兼容时给出错误。纯启动查询若显式配置 RULES，可按该服务地址的真实规则决定其启动路径，同时保留用途限制和循环检查。

### 默认值和冲突

- 不把 Dart 全模型写回以“统一”DNS；沿现有覆写键合成，记录哪些服务来自源配置、用户覆写、baseline 或核心默认。未指定 pre-route-proxy 不继承任何默认组。
- `appendSystemDns` 保持一个可见的本地来源选择。代理／前置用途遇到混入 system 的接收方集合，作为冲突失败；不先并发 system 再声称最终答案来自代理，也不默默删掉它。可在 prepare 静态发现的冲突先拒绝，迁移说明指导将 system 放到明确的本地政策。
- 已接受节点、解析器域名可进行必要启动解析。仅允许该配置快照中的 endpoint、绑定传输的 ECH 查询名及响应中的必要别名续查；普通业务域名不能因为调用了 ProxyServerHostResolver 就升级为启动用途。对别名续查继承父用途、出口和截止时间，重新检查接收方政策，冲突即失败。
- 启动依赖沿当前请求记录访问栈，重复的「用途／endpoint／代理链」终止为循环错误；不通过换系统 DNS 或其它代理打破循环。IP endpoint 不需启动查询。
- DNS 被关闭、resolver 缺失或系统 DNS 空时，受约束路径返回明确错误，禁止穿透到全局 SystemResolver 的隐含公网列表。显式 default-nameserver 中已接受的公网 IP 仍可用于 DNS 服务启动，二者不能混同。
- 最终配置冲突沿 T01 prepare／失败契约处理：保留仍适用的旧配置或关闭相应入口。运行中的单次解析失败只影响相关事务，不主动把整个设备断网。

TLS 身份、`skip-cert-verify`、明文服务和 EDNS Client Subnet 的既有选择必须在有效配置中可见，不在本项偷偷更改信任根或删除已接受配置。T02 不因重试自动增加明文服务或 ECS，不将“经过代理”描述成服务身份安全；后续来源委托和高影响变化接受接 T05，认证／信任根整体审查接仍暂缓的 L1-T04。

### ECH 与 WireGuard 的真实消费合同

**节点 ECH 是受批准的独立启动依赖。** prepare 时从该出站的规范化传输配置生成允许集合：启用 ECH 且没有静态 config 时，优先使用 query-server-name，否则使用该传输实际配置的 TLS ServerName／SNI（及协议现有确定性缺省）。它不要求等于节点 server；节点 IP＋另一个 ECH 名是合法正例。分离传输／下载支路各绑定自己的已接受 TLS 配置，不能把运行时任意 serverName 加入集合。

回调必须携带节点对象／该传输支路和父资格，所查名称属于该集合才可创建 ECH 启动子问题；服务沿 proxy-server-nameserver-policy／proxy-server-nameserver，问题类型为所需 HTTPS 记录及必要别名。缓存键区分 endpoint A/AAAA 与 ECH HTTPS。静态 ECH config 不发这类查询；实际 TLS 名无法从接受配置确定时，拒绝该 ECH 查询，要求明确 query-server-name 或静态配置，不能接受某个业务域名后以回调参数为由晋升。查询错误／撤销也不自动关闭原来要求的 ECH 或新增系统解析；TLS 能否继续按接受配置的显式失败语义处理。

**WireGuard 的 remote-dns-resolve＋节点 dns 是客户端业务解析。** 保留它的现有专用接收方优先级：业务实际选中 WG 叶节点、remote-dns-resolve=true 且 dns 非空时，TCP DialContext 和 UDP ResolveUDP 使用该节点接受的 dns 集合，经这个具体 WG 隧道发问题；不先替换成全局 main／nameserver-policy。它不属于节点 endpoint 启动许可，也不是把域名交给一个不可见的远端代理进程解析。

- 从选中的 WG 对象取得不可变专用服务描述，在当前事务创建受约束 client，覆盖现有 w.resolver 优先消费点；不能保留无用途的旧专用 resolver 旁路。remote-dns-resolve=false 或列表空时才走全局业务 DNS 服务选择，并保持已选策略的出口。
- 专用列表的 `#WG`／无标记与该隧道兼容；`#DIRECT`、另一个组、system／DHCP 等没有等价隧道内约束的服务明确失败，不忽略标记也不退回全局服务。私网 DNS 地址合法，经 WG 到达，不套本机 LAN 判据。
- 连接 DNS 服务时复用该 WG 实际 stack 和所选叶，不用一个会再次触发业务域名解析的 WireGuard.DialContext 递归解析 DNS 服务本身。服务名需要地址时创建 DNS 服务启动子问题，遵守父配置接受的 default-nameserver 与循环／预算；若没有合法启动路径则失败。UDP／TCP／加密重试仍受本次事务约束。
- 每事务 client 只拥有经 WG stack 创建的 DNS 连接／流；事务结束不 Close 共享 WG device。节点对象替换、Owner 退役时旧请求失效。缓存还绑定专用 dns 配置和 WG 节点对象，不能与全局 main 或其它节点共用许可。
- 保留 Host 存在时节点专用 DNS 的接收优先级及必要二次解析；即使 metadata 已有前置解析 IP A，专用 DNS 也可能返回 B，两次按各自用途计数。但 B 不能直接覆盖 DstIP 后拨号，必须通过下述实际目标校验；纯 IP literal 沿 literal 快路径，无该业务名查询。

专用 DNS 服务发生错误时，相关 WG 业务失败，新请求在配置／节点修复后恢复。若某协议分支无法带入上述父资格、定向传输和可取消 client，则明确拒绝该专用解析功能并提示迁移到受约束的全局解析；不能让它静默继续旧实现。未来验证须通过真实 WG TCP／UDP 消费者和受控 stack／服务收件来区分业务名、WG endpoint 与 DNS 服务名；设备上的实际隧道与 FD 仍需相应平台证据。

#### WG 实际目标与 IP 规则的一致性

采用一次有限的最终地址校验，保留专用 DNS 优先级，不允许客户端二次解析绕过 IP 规则。真实业务首次路由时捕获相同配置／规则快照、完整入口及嗅探后的业务 metadata 和已选 WG 策略／节点绑定。WG 专用解析从答案按既有地址偏好选出此次准备连接的单个 IP B；在向业务目标建 TCP 连接或发送首个 UDP 包前，以 B 替换克隆 metadata 的 DstIP，保留原 RuleHost、来源、业务端口等，复用同一真实入口／matcher 做一次无新网络查询的校验。本次不做多地址竞速或因连接失败再换另一个答案，牺牲该路径的地址重试可用性来固定此次校验对象。

- 校验从同一管线的“预处理已完成、实际地址已确定”边界进入，锁定 DstIP=B；不能重新执行会用 hosts／fake-ip 映射覆盖 B 的原始预处理，再拿另一个地址代验。ResolveIP helper 不得再次外发；进程／入口等读取使用已捕获事实。使用原 SpecialProxy／SpecialRules 和真实规则顺序，包含 `no-resolve` IP 条件；不是额外增加一张“所有IP拒绝”的全局表，也不是一律忽略原入口覆盖。
- 替换 A→B 前失效 A 的全部目的 IP 派生事实：克隆后的 `DstGeoIP=nil`（不能用非 nil 的空 slice）、`DstIPASN=''`，按 B 重算。Metadata.Clone 是浅复制，不能把 A 的目的 GeoIP 可变切片带入或就地清空修改原对象；源 IP／源分类、真实入口、RuleHost、进程和端口保持原值，需要可变切片时独立复制。MMDB GEOIP 会直接复用非 nil DstGeoIP，因此必须清除；ASN 当前按 DstIP 重查，清空用于记录一致，不把它误报为同类已证实匹配漏洞。
- B 命中实际入口下的 REJECT 即失败；B 改变原决策为 DIRECT、其它代理策略／组或不可兼容控制适配器，也失败。只有仍选择原已批准 WG 策略，且原具体 WG 节点仍为该选择链允许的有效对象，才通过。不能通过校验开始新组选取、健康探测、第二次 DNS 或反复 rematch；无法无新外发地确定结果的组合明确拒绝。
- 若快照／选组／节点在二次解析期间改变，按旧事务撤销失败，不用当前新规则替旧结果补许可。该检查是最终目标的一次确认；前置 A 与最终 B 不同但都选择原 WG 可以正常连接 B，不能仅披露地址不同而跳过确认。
- 通过后生成请求内的已校验目标 `{B, port, 原决策绑定}`，供 WG TCP／UDP 直接调用 stack。业务元数据可保留 Host 作记录／规则依据，但实际拨号参数必须使用这个数值地址，不调用以 Metadata.String／RemoteAddress 的 Host 再解析的路径。普通重试仍用同一固定 B；本次业务不因失败重新选地址／重查。只重新核验资格及快照，不重复最终路由或产生循环。
- 缓存命中同样要校验最终 B，缓存只省 DNS，不省规则。WG DNS／隧道启动握手在业务目标授权前可能已发生，仍按用途观察；真正业务目标 B 收件必须为零，不能把隧道控制包误作业务成功。

V8 分别准备 A 为前置答案、B 为 WG 专用答案：B 落入较早的 IP-CIDR REJECT 时，TCP／UDP 实际目标均收件零；MMDB 模式下 `GEOIP,US,REJECT`、`MATCH,WG`，A 非 US 已缓存而 B 为 US 时也均零收件，覆盖 A 的分类为空 slice 的情况；A≠B 且 B 仍按相同规则选择 WG 时正常到达 B。另验证 B 改为另组／DIRECT 或快照变更时失败、校验后固定 B 无第三次查询、源事实未被修改，以及 `no-resolve`／已有缓存路径。该保证限于本客户端控制的 WG 本地二次解析，不宣称能检查代理进程内部不可见的远端解析结果。

## 一次查询、并发和失败的执行规则

1. 从父 scope 派生有截止时间的事务；获取同一份规则／配置、选组及网络快照，决定用途、接收方集合和传输。每次读缓存、建连接、发问题、接收答案和发布结果前校验父资格与快照。
2. 代理 DNS 在事务内复用严格代理选择能力；使用业务目标 metadata 选组，独立问题只提供已知字段，不把 DNS 服务地址当作业务负载均衡键。事务内记录选择链和叶节点；不要求随后的独立业务连接采用这个叶节点。
3. 解析服务 client 和连接由该事务拥有。首版不跨事务／尝试链共享 DoH／DoT／DoQ 连接，链内顺序重试可复用；同根 A/AAAA 若分为两条并行链则分别拥有 client。H3／H2 等探测按本层一个传输连接的预算串行，不借探测额外打开连接。为受约束 client 提供确定关闭能力，不能把 ResetConnection 等同于取消所有在途查询；结束或撤销关闭客户端、流、UDP socket 和连接，不依赖 finalizer。增加 TLS 握手开销，优先保证归属；缓存仍复用。
4. 保留已接受服务集合、过滤条件和 lazy 选项；根的 main／fallback 可在四条链额度内并发，启动依赖内部按进展合同串行，其余候选有界等待。所有候选在启动前检查用途兼容，任一不兼容不能先发送再丢弃答案。胜出后取消并关闭其余尝试；已发出的查询无法撤回，必须计入接收方观察。
5. UDP 截断转 TCP、DoH H3 转 H2/H1、DoQ 重连均沿同一事务、接收方身份和出口。H3 转 H2 仍为 HTTPS，不允许换 HTTP／UDP 服务、组或系统 DNS。代理不支持所需 UDP 时返回错误，用户可明确选择已接受的 TCP／加密服务。
6. DoH 使用固定 origin；拒绝 HTTP 重定向，避免问题通过 query／body 送到另一服务。TLS 名称仍校验原服务身份，不以连接 IP 替代名称。已有 TLS 放宽选择不由重试新增。
7. 超时、无节点、名称失配、能力不足、系统 DNS 空、循环及撤销分别返回受控原因；DNS wire 端对策略拒绝用 REFUSED，执行失败用 SERVFAIL，业务端返回失败。不能将拒绝冒充 NXDOMAIN，也不能触发错误后的 Background 重查。

传输必须带着父 lease 的取消和 socket 控制到所有 client。普通业务 DNS 的 DIRECT／启动 DIRECT 子 lease 复用现有 Android 注册和 FD 状态核验机制；需把该 kind 接到真实 JNI 消费者，不以 Go 假 hook 代替。代理 DNS 的 underlay 沿代理实际拨号／protect 机制；不据 protect 成功声称已绑定特定物理网络。特殊 resolver（DHCP、Tailscale、EasyTier 等）只有提供等价用途、取消和出口约束才可在受约束路径使用，否则给出不支持错误；不透传到其私有直连解析路径。

锁沿 [T01 所有权与锁](l2_t01_plan.md#失败分层所有权与锁)：configMu → selectMu → registry；资格发布与撤销后在锁外 cancel／Close／通知，不持包装层锁等 DNS 或 JNI。规则和 provider 的不可变快照在短读边界取得，IP helper 暂停解析时保留匹配位置，在继续／发布前检查快照仍有效；不得持 tunnel configMux 再反向回调包装层取得外层锁。实现需让完整业务 matcher 和独立问题共同消费这份快照，不复制规则循环。有限发送／回复沿父资格的检查边界执行，不向 DNS 子 lease 开放文件 GrantCommit 权利。

## 缓存、在途查询和变更

### 缓存不授予查询许可

沿现有总容量受限的 DNS cache，扩充键为规范化 question（含 qclass／qtype）＋影响响应的 EDNS 参数＋用途＋有效接收方政策＋出口绑定＋activation／网络身份。出口绑定包含当前选择链／叶对象与 provider 版本，不能只用组名。禁止跨 DIRECT、两个代理组、前置解析和启动解析复用。

缓存命中仍先确定本次用途、校验当前路由和网络；不能用以前一次业务流的答案证明独立问题可以直连。只使用未过期答案；首版取消过期值先答和后台刷新，过期后由当前事务重新查询。失败缓存若保留，限制在相同键和现有短 TTL 内；策略拒绝、撤销和缺许可不写成可复用域名不存在。

受约束路径首版不做跨请求 singleflight，去除“第一个请求拥有后续所有请求”的取消问题，也不另造引用计数调度器。单个事务内可合并相同子问题；A／AAAA 共享事务资格但有各自 question。更高并发成本待真实数据后再评估，不能恢复 Background 作为优化。

fake-ip 与 redir-host 映射只提供地址／域名关联，不能携带旧路由许可。可保留池的地址稳定性，但每个新业务流重做当前匹配；旧真实 DNS cache 不通过 enhancer 的 PatchFrom 跨 activation 继承。

### 变更与撤销

- 新配置／服务 Owner／数据来源撤销继续使旧 BusinessScope 或应用 lease 失效。旧查询取消、连接关闭，迟到答案不回填新缓存、不回复新客户端。已有可用旧配置继续运行时，其查询仍以旧 activation 的实际资格判断，不凭“收到新候选”自行撤销。
- 用户选择器变化、模式切换、节点 provider 替换和所依赖规则 strategy 发布，在现有实际修改入口通知／校验受影响 DNS 事务；读同一快照并在发布前复核。不能仅靠 routeStamp 的定时观察实现即时保证。自动组健康选择变动按「同策略」契约处理：已开始事务可完成原节点的查询；新事务重新选择，明确不保证物理节点相同。
- DNS 缓存和客户端在变更后以新绑定创建；旧条目可按原 LRU 逐出，但新键不命中旧数据。用户显式换组／节点、provider 内容更换、网络来源改变时，在途事务取消且不自动用新策略重发，等待新请求，避免一次访问同时暴露给旧、新策略。
- 发送动作与撤销存在现实边界：撤销前已经进入内核／已到服务的查询不能撤回。保证的是失效检查后的新动作不获准、取消收敛和迟到结果不被使用；不声称系统回调尚未抵达时已有预知能力。

### Android 系统 DNS 与物理网络

RequestNetworkSource 继续是网络事实来源。把 DNS publication 改为同一 selection 下的 `{sourceEpoch, revision, directNetworkId, servers}` 快照，使用被选中的网络条目，不能继续用另一套 preferred 选择拼列表。source 不可用、default 类型未知或无合法 selection 时发布不可用／空列表；不是退回“看起来最好”的网络。

NetworkObserveModule 只转发快照及 active 资格；Go 原子发布不可变系统 DNS 客户端快照，核对来源身份并拒绝旧发布。复用已有网络 source 的 revision 和服务／进程身份，不以独立计数器证明网络新旧；同地址列表但网络身份改变也必须发布。保留 Go 排队更新序号用于队列顺序，二者职责不同。

系统／LAN DNS 每次事务捕获快照，DIRECT socket 通过已有 native FD gate 验证并绑定该 directNetworkId，IPv6 link-local 地址保留 scope。只 protect 而未绑定不满足此契约；绑定失败直接失败。网络更新、stop 或源重建撤销旧事务并关闭 socket，空列表不进入全局公网默认分支。200ms 发布延迟期间旧事务要经当前网络事实检查；不能认为旧字符串仍在就可继续发。

普通代理 underlay、Android 回调迟到、排除应用、Always-on／系统接管的全面行为由 T03 继续核对。T02 独立交付只承诺本项 DNS 消费者接受到事实后的约束；JNI／真实绑定需要真实设备证据，不能由本地替身证明。

## 用户场景与预期行为

表内均为拟实现行为。验证标识对应下一节；“不发”仅指本次受控解析，不包括访问代理节点／DNS 服务所必需且单独标记的启动问题。

| 输入／操作 | 业务出口 | DNS 接收方与出口 | 失败／恢复、例外 | 可观察验证 |
| --- | --- | --- | --- | --- |
| 入口／RuleHost／能力资格充分，域名规则选 DIRECT | DIRECT | direct 服务或适用政策，直连 | 该集合失败即失败；纯域名文本本身不是资格证明 | V1：服务 D 收到标记名，代理 A/B 为零 |
| 资格充分，域名选代理 A／B | 对应组 | 接受的服务经对应组；可远端解析 | A 失败不改 B／DIRECT；新请求可在同组按政策选可用节点 | V1/V2：分别记录代理 CONNECT／UDP 和 DNS 收件 |
| 资格充分，域名／GEOSITE 先命中 DIRECT 或 A | 按该条规则 DIRECT／A | 对应 DIRECT 服务直连或经 A 查询 | 不需要先查目标 IP；原服务失败不扩大出口 | V1/V4：合成集合命中，零 IP 前置查询 |
| 域名／GEOSITE 未命中，按原顺序到明确 MATCH,A | A | 适用服务经 A，或适用协议代理端解析 | 前面无 IP／未知条件才成立；不重排跳规则 | V1/V4：未命中集合仍正常同组，无前置许可 |
| 自动／负载均衡组 | 当前业务选组 | 同策略，可与业务用不同叶节点 | 事务内固定 DNS 叶；不保证两条连接同物理节点 | V2：同组两叶的选择与缺失字段场景 |
| 组内手选 DIRECT／组内默认或自动 DIRECT | 真实 user 手选才可 DIRECT | 合法手选使用 DIRECT DNS；默认／自动不发该业务查询 | default-selected: DIRECT 不是手选；明确 DIRECT 的业务规则仍正常 | V2/V5：手选及恢复正例，默认／自动恢复拒绝 |
| 用户切选择器到另一节点／组 | 新请求用新选择 | 旧事务取消；新事务用新绑定 | 旧答案不回填；不替旧访问自动重发 | V5：延迟旧响应，检查新旧计数和缓存 |
| 明确 LAN 域名＋可提前 DIRECT | DIRECT／本地服务 | 对应本地 DNS，经其网络 | 本地不可用即失败，无公网备用；多播未覆盖 | V3：LAN 服务收到，公网／代理接收零 |
| corp.example 经 CorpProxy，政策为 10.20.0.53#CorpProxy | CorpProxy | 远端私网 DNS，经 CorpProxy | 私网 IP 不强制 DIRECT；改为 #DIRECT 形成冲突时失败 | V3：企业代理／私网 DNS 收件，本机 DNS 为零 |
| 域名可提前 REJECT | 不拨业务 | 不发真实 DNS，返回拒绝 | 不以失败域名写负缓存；依赖 IP 的拒绝见下行 | V1：业务、DNS 收件均零 |
| 先遇到 IP 规则且确需前置查询 | 按取到 IP 后的真实规则 | 显式前置代理＋接受服务 | 未授权／前置失败即失败；最终 DIRECT／REJECT 仍可能已前置查询 | V4：前置组独有收件，错误后不落 DIRECT |
| 独立 DNS 缺端口／进程等信息 | 等真实业务时再定 | fake-ip 可本地答；真实查询需前置许可 | 不跳过未知规则；未许可返回 REFUSED | V4：进程／端口／NOT／子规则反例 |
| DOMAIN→A、MATCH→DIRECT，A 不支持 UDP，业务 Network 未知 | TCP 可 A、UDP 可继续后续规则 | 独立问题不能先按 TCP 发给 A | 信息不足；fake-ip 延后或依获准前置策略 | V4：DNS 自身 TCP／DoH 不能冒充业务 TCP |
| 主表 A、某入站 SpecialRules／SpecialProxy 为 B | 实际未来入站决定 | 独立问题未知入口，不能默认主表 A | 相同域名规则仍不足；真实业务走自身入口 | V4：两个真实入站，独立问题按未知处理 |
| 嗅探可把 RuleHost 从查询名换为另一名 | 以真实 RuleHost 决定 | 独立问题不能提前按 qname 的 DOMAIN 规则外发 | OverrideDest=false 也可能未知；fake-ip 延后 | V4：不同 SNI／HTTP Host 与查询名 |
| 节点或 DNS 服务为域名 | 业务仍按原策略 | endpoint 启动服务，可能明确允许 DIRECT | 仅 endpoint／必要别名；循环或不支持失败 | V3：仅 bootstrap 标记名可达直连服务 |
| 节点 IP＋独立 ECH query-server-name／TLS名 | 原业务策略 | 批准的 ECH HTTPS 启动问题，不需节点 A/AAAA | 任意运行时业务名不能晋升；静态 ECH config 不查 | V8：分别记录 ECH、endpoint 与业务问题 |
| WG remote-dns-resolve＋节点 dns | WG 实际 IP 校验通过后连接 | 客户端业务查询到节点专用 DNS，经该 WG | B 命中 REJECT／改变原决策即失败，不直接覆盖前置 A 拨号 | V8：A/B 双答案、TCP／UDP 目标收件与专用 DNS |
| 目标 IP literal／hosts／有效缓存 | 当前规则决定 | 按真实消费者决定；一般无目标新查询，WG 专用解析有上述例外 | 仍可能查询节点地址；旧组／旧网络答案不能授予许可 | V1/V5/V8：缓存、WG 重查与收件分别核对 |
| 完整上下文＋合法 hosts／当前 IP，首条 IP-CIDR DIRECT／REJECT,no-resolve | 按原规则直连／拒绝 | 不发目标 DNS，不要求无用途的前置确认 | 缺地址且允许解析时才触发门；独立问题缺上下文不因此变充分 | V10：203.0.113.10 的 DIRECT／REJECT 正例与缺地址反例 |
| 代理支持传目标域名 | 对应代理 | 客户端不查业务名；代理端解析 | 节点服务地址仍可能启动解析；不能证明代理端具体 DNS 服务 | V2：代理收到域名，客户端 DNS 零 |
| 无节点／名字失配／代理无 UDP | 不成功连接 | 不改直连、接口或系统服务 | 返回相应失败；修正配置／明确服务后新请求恢复 | V2/V6：直连黑洞收件零 |
| system DNS 空或网络来源未知 | 相关请求失败 | 不使用隐含公网默认 | 显式已接受 IP 启动服务不受此空列表替代 | V3/V6：空列表注入后公网默认收件零 |
| 主／备用并发；UDP 截断／H3 失败 | 原业务策略 | 所有尝试同用途；重试保持服务身份及出口 | 可能已向多个已接受服务发出，胜出后取消余者；无明文新增 | V6：记录全部收件和协议，无只看胜出者 |
| 配置／网络／provider 变化、停止 | 有效 activation 才可工作 | 旧事务撤销，新请求重新判定 | 迟到不可回填／回复；已发查询不能撤回 | V5/V7：受控栅栏触发变化并释放旧答复 |
| 旧 TCP keepalive／已接收 UDP 包在 B 激活后才处理 | 原 activation A 资格已失效 | 仍绑定 A，丢弃／关闭，不能用 B 解析或回复错误 | B 只接受新入口输入；正常／缓存／错误 writer 同样受限 | V5/V7：accept／入队前后屏障跨激活 |
| 同名问题并行或普通 DNS 配额满 | 各业务沿自身事务 | 同名不替换，A/AAAA／备用归同根 | 普通 DNS 繁忙不取消另一同名事务，不占维护配额 | V9：饱和时订阅／WebDAV DNS 仍有独立预算 |
| 同根四路域名 DoH 都需要启动 DNS，尝试链槽已满 | 原业务策略 | 各子依赖借各自父令牌串行进展 | 不等第五槽；超时／取消关闭整条依赖链并释放一次 | V9：合法无环正例、全局饱和与回收 |
| 真实 matcher 缺必要 IP、确需前置查询，用户未确认 | 已有合法数据可确定的路径正常；确需查询者失败 | 前置及其相关启动依赖外发前拒绝 | 错用途／过期 cache 不补数据资格；不挂起旧请求 | V10：确需前置零收件，合法已有 IP 不被误拦 |
| 为当前配置选定代理并确认，T01 成功应用 | 仅新请求用新输入 | 前置问题经指定代理，最终业务仍按原顺序 | 明确可能与最终 GEOIP 出口不同；不自动重放旧请求 | V10：前置／业务分别收件，新旧 scope 分离 |
| 表单打开后换配置／相关 provider 或组定义变化 | 不应用过期选择 | 不向新定义发旧许可的查询 | 返回需刷新；同名不承接，旧回复不激活新范围 | V10：过期提交零副作用，旧结果不可发表 |
| 确认候选应用失败，旧配置仍合法 | 原有效配置按其既有状态工作 | 确需前置且未确认者仍拦；合法已有 IP 照常匹配 | UI 显示失败／实际保留输入，不提前成功 | V10：T01 失败／保留与恢复正反例 |
| A 确认成功但偏好写迟到，B／撤销已成功 | 服从当前接受结果，不复活 A | 旧写在有限提交／缓存条件边界丢弃 | 缓存失败重取当前 checkpoint，旧 K／profile 不作为许可 | V10：A/B、A/撤销交错及崩溃恢复 |
| 同 profile 把订阅 URL A 改 B，生成相同 YAML | 正常无需前置路径仍可用；前置决定失效 | 新来源快照摘要不同，不承接旧确认 | 捕获与生成之间改来源则整候选过期；旧格式未知 | V10：URL／类型／脚本来源同字节变化与篡改自报字段 |
| 重启／Flutter 不在前台；无关或相关更新 | 从 Core 当前输入重新派生 | 同 K 保留；相关改变仅受影响路径待确认 | 不跨 profile；全局 DNS 编辑／订阅不制造同意 | V10：恢复、日志变化、Geo／规则／同名组变化 |
| 应用内置 DoH／DoT／DoQ | 作为该加密服务的普通业务连接分流 | 应用所选服务；查询内容对客户端通常不可见 | 不做 TLS MITM；端口 53 hijack 不代表接管加密 DNS | V7：普通隧道到合成 TLS 目标及设备接管观察 |

### 代理组内 DIRECT 的已确认语义

人类已确认：代理组内只有用户手动选择 DIRECT 才允许直连，自动选到 DIRECT 时失败；DNS 和受影响业务采用相同判定。源配置／订阅的 default-selected、列表首项或健康选择不等于用户手动操作。业务规则本来明确选择 DIRECT 的正常分流继续工作，不属于本节的组内自动回退。现有严格代理 lease 拒绝所有 DIRECT，仍需在共同边界先区分合法 DIRECT 用途。

| 真实选择链／来源 | 分类 | 业务与 DNS 行为 |
| --- | --- | --- |
| 接受的业务规则／固定入口直接指定 DIRECT，未经过组选择 | 正常 DIRECT 分流 | 沿已有 DIRECT 契约可用 |
| 用户明确将 selector 选到 DIRECT，当前实际遵从 | user／手动 | 允许合法 DIRECT；随保存／恢复保留已确认来源 |
| selector→未强制的自动组→DIRECT | 自动 | 两者均失败，不增加直连查询 |
| 用户明确 ForceSet DIRECT，当前真实选择仍遵从该强制对象 | user／手动 | 允许；仅调用过 ForceSet 或看到 fixed 不是证明 |
| selector→用户强制 DIRECT 的自动组，当前实际遵从 | user／手动的 DIRECT 分支 | 允许；强制失效后自动落 DIRECT 则失败 |
| 配置／订阅 default-selected: DIRECT；无手选的首项／Now 为 DIRECT | config-default／自动／未知，均非 user | 两者均失败；接受配置不把组内默认升级为手动选择 |
| 用户选代理／子组，实际未遵从而回退 DIRECT | 不是用户选择 DIRECT | 两者均失败 |

选择来源不能从当前 fixed、SelectedMap 或 `Now()==DIRECT` 反推。现 checkpoint 把 selector 的 Now 放入 SelectedMap，恢复时又 ForceSet，可能把自动结果写成固定值；以下来源合同随同一输入／checkpoint 保持，不追加操作历史或另建运行状态权威。

#### 选择来源与恢复

- 在同一版本化 accepted ConfigManifest 保存 `selectionIntents`，每组当前 `{target, origin}`；origin 区分 user、config-default、auto／unknown。default-selected 从当前接受配置取得，但不授予组内 DIRECT 手动许可；不能由 profile YAML／订阅填写 user 元数据。来源绑定当前组类型及配置输入。
- 只有明确用户选组／ForceSet 操作经受控写入口核验、实际应用成功并与 checkpoint 同步发表后，才记录 user；Dart 乐观 selectedMap、UI 展示、route observer、默认初始化和恢复过程不得创建 user。下一次 ConfigInput 的持久用户偏好也保留已确认来源，不从 selectedMapProvider 观察值重建。
- 无关热更新保留意图；readPicks／健康／provider 变化只更新观察。checkpoint 将请求 target／来源与实际 SelectedMap 分开序列化，同一原子接受／恢复引用绑定二者。格式升级保留来源，不能丢字段后仍按手动恢复。
- 新格式恢复已确认的当前选择及来源：user 恢复其请求 target，当前真实展开仍遵从用户 DIRECT 分支才允许；config-default 可保留配置默认，但若实际落 DIRECT 仍非 user、仍失败。auto／unknown 不凭某次 Now 强制出人工许可，不能对观测 SelectedMap 无差别 ForceSet 后再反推 user。
- 旧 version 1 manifest／旧 profile 只有 SelectedMap 时，缺失的用户来源为 unknown；能识别原配置 default-selected 的也仅为 config-default。即使兼容恢复后 fixed=DIRECT，仍非 user，下一次 checkpoint 不晋升。组内 DIRECT 需重新明确选择后才获许可；本来明确 DIRECT 的业务规则不受这项迁移限制。
- 清除 forced selection 同次删除对应 user 意图，回到配置默认或 auto／unknown；空值不作为手动 DIRECT。target 消失、类型不符或强制分支实际失效时，不把 fallback DIRECT 改记为用户 target；保存／恢复保持失效或清除状态，名字重现不凭旧观察复活许可。COMPATIBLE 等实际 Direct 类型同样处理。

V2/V5 覆盖未手选首项 DIRECT、default-selected DIRECT 经无关热更新／冷恢复仍拒绝；明确用户 DIRECT 保存／恢复仍合法；用户仅选代理／子组而自动落 DIRECT 仍拒绝；强制失效、清除与旧格式不升级来源。

共同业务选择／DNS 派生边界按来源创建合法 direct 子资格，其余代理用途继续严格检查，自动 DIRECT 在业务拨号前一并失败。显式前置代理（若获准）必须是真代理，不因手动 DIRECT 放宽。固定选择变更、缓存和撤销仍沿原机制执行。

## 拟验收方法与交付出口

本轮只提出方法，未创建测试代码、运行测试、构建、安装应用或操作宿主网络。现有 [DNS 记录测试](../../../../core/dns_query_test.go)、[解析记录测试](../../../../core/Clash.Meta/dns/patch_test.go)和 [T01 真实配置／业务入口测试](../../../../core/config_apply_test.go)可作为后续扩展入口，不把只测记录字段当作出口证据。

后续使用本地合成 DNS 服务 D/P/L、代理 A/B 及不同叶节点，所有目标绑定 loopback／明确受控局域网，不用真实订阅、账号或外部网站。每次访问使用唯一 qname（包含用例、用途、序号），服务记录完整收件序列；代理记录目标、传输及字节，业务服务确认实际到达。分别标记业务问题、节点 endpoint 和 DNS endpoint，避免把正常启动查询当业务泄漏或把业务查询藏在启动计数中。

| 编号 | 实际生产消费者与操作 | 正向／反向断言 |
| --- | --- | --- |
| V1 | 实际 prepare/install/activate、mixed TCP／UDP 与 ServeMsg／DNS listener | DIRECT／代理／拒绝、hosts／fake-ip／cache 正常；GEOSITE 命中与未命中后 MATCH 代理正例均无需 IP 前置许可 |
| V2 | 真实代理出站、selector／url-test／fallback／负载均衡、域名传输协议 | A/B 收件独立；组内仅真实 user DIRECT 允许，config-default／自动／未知拒绝；普通 DIRECT 规则仍正常 |
| V3 | 实际系统 resolver、endpoint helper、DNS 服务启动、默认入口及远端私网 policy | 允许的节点／服务名正常；任意业务名不能伪装启动；空 system 不进公网默认；10.20.0.53#CorpProxy 经代理，#DIRECT 冲突失败 |
| V4 | 同一完整路由入口／matcher／组展开，含 GEOSITE、IP／no-resolve／逻辑／三类 rule-set | GEOSITE 提前决定与 MATCH 代理正例；更早 IP／未知条件不得跳过；TCP/UDP、入站覆盖和 SniffHost 反例不变 |
| V5 | 实际取消、选组、模式、provider 发布、配置替换、cache、writer 和 checkpoint 冷恢复 | 旧输入不借新资格；首项／default-selected DIRECT 经热更新／冷恢复仍非 user，明确手选仍合法，强制失效／清除与旧格式不晋升 |
| V6 | 生产 UDP/TCP、DoT、DoH H2/H3 和 DoQ client 的受控服务 | 截断／握手失败／超时／重定向时枚举全部尝试；无额外服务、组、明文和 Background 重发 |
| V7 | Android 真正 NetworkSource→JNI→FD gate→系统／LAN DNS；TUN hijack／加密业务流 | 网络同地址换来源、IPv6 scope、stop／回调乱序；TUN TCP flow／UDP 包跨激活仍沿 A；真实绑定及绕过范围需设备证据 |
| V8 | ECH 实际回调、WG DialContext／ResolveUDP 和隧道内 DNS client | WG 前置 A／专用 B：IP-CIDR 及 MMDB GEOIP（A 非 US／空分类，B 为 US）REJECT 时 TCP／UDP 目标零收件；B 固定无第三次查，正常同决策及 ECH 正反例保留 |
| V9 | 同一 registry 的 DNS 内部派生、真实并发 DNS 输入及维护消费者 | 同名不替换／维护隔离；四路域名 DoH 启动依赖在同根／全局饱和时仍进展；子超时／取消后连接与额度回收，旧 ID 无提交或新 Owner 权 |
| V10 | 真实事实／确认／T01 输入与 DNS／业务入口、有限缓存提交及来源组合；配置详情／DnsView 消费 | 合法已有 IP 的 DIRECT／REJECT 无目标 DNS；确需前置未确认零相关外发；A迟到不覆盖B／撤销；同字节来源变化失效；确认后新请求与过期／恢复／无关更新合同保持 |

现有 QueryRecord 只给胜出 upstream／缓存记录，不能枚举所有失败、并行和迟到尝试；验收以独立收件与连接观察为准。V10 还检查通知／事实／持久输入无真实请求列表、关闭通知不批准、全局 UI／源字段不制造 choice。来源专项采用同 profile 的 URL A→B／源类型／脚本 URL 变化但生成同字节，以及捕获后变更、脚本自报 origins、旧格式缺证明，核对 manifest／K 不承接旧许可；不需实际联系这些合成来源。已有地址正例与旧 activation／错用途 cache、独立问题缺上下文的反例分开，不通过清域名伪造充分信息。实际版本、命令、计数与设备缺口在未来 Result 维护，不设“已通过”占位。

未来 T02 实施的独立出口：上述真实 DNS／业务消费者、配置合成及错误展示形成闭环；更新必要核心窄补丁与同一累积 carrier，沿既有公开父来源恢复约定交付；正反用例有接收方证据。需要设备才能确认的 JNI／物理绑定不能用 Go hook 或 JVM 替身冒充，若缺设备，成果必须保留该未验证边界，由 M 判断是否达到获准的实施出口。

## 职责边界与改动成本

| 位置 | 拟承担的增量 | 保留的权威 |
| --- | --- | --- |
| Dart 最终配置／说明 | 配置级待确认入口与结果、派生前置值；原全局覆写不创建许可 | Core config_state 与 T01 input identity；profile 仅缓存已确认偏好 |
| Go 包装层／requestscope | DNS 子 lease、绑定事实／确认 CAS、T01 候选与变更通知 | 现有接受输入／Owner／应用注册／BusinessScope，无新待办或运行状态权威 |
| mihomo matcher／规则／provider | 同源依赖描述、缺字段判定、IP 失败终止 | 原顺序、原 Match 语义、真实 strategy 发布 |
| mihomo resolver／client／出站消费点 | 用途传递、严格出口、cache 键、取消与受控重试 | 原 DNS 服务配置与实际代理对象 |
| Android 网络来源及 JNI | 带来源 DNS 快照，DNS DIRECT FD 核验与绑定 | RequestNetworkSource／ServiceState／现有请求 FD 注册 |

包装层单独改 YAML 无法修复已经丢失的 metadata、Background context 和协议内部重试，因此需要必要核心增量；实现时只在上述汇合点扩展，不复制完整解析器或分流引擎。首版取消跨请求查询合并、连接池和后台刷新，换取较少生命周期状态；代价是缓存未命中时握手和并发查询可能增加，应在未来本地验收记录延时与次数，不以性能为由恢复无归属任务。

T03 负责完整服务过渡、排除应用和系统接管范围；T02 的 DNS 网络快照／FD 消费不等它来实现。T02 同时交付本项最小配置级前置确认，不能把未确认拦截留给 T05；T05 接续更广的来源委托及持续更新接受，不得由订阅自行开启本项许可。L1-T04 仍暂缓，信任根／认证风险继续披露。应用 SDK 独立 DNS、多播和全部加密 DNS 识别不包含在通用解析保证中，分别接 Loop 1 及 T03／T04。

## 产品收敛与本次交付

已确认同策略／分组、不额外承诺同物理节点；[组内 DIRECT](#代理组内-direct-的已确认语义)仅真实手动允许，正常明确 DIRECT 规则仍可用。按人类允许延后选择及复杂时采用推荐的授权，收敛为[配置级延后确认](#配置级延后确认与请求拦截)：保留原规则顺序，不新增 GEOSITE／GEOIP 优先模式；运行时用户显式选前置代理或保持未确认。受影响请求不先外发，确定合法路径继续；前置与最终业务出口可不同，确认页说明此例外。

system／选择器迁移及前文未知资格／取消／资源合同均已纳入通过的设计。运行时选择由配置级确认承载，设计交付不要求提前指定真实代理，也不替用户预选。

本轮仅交付已审设计文档，提交、本地合入及 M 远端交付的实际状态由[任务清单](loop2_tasks.md#l2-t02-dns-接收方出口与失败回退)维护。设计通过不授予生产实施、测试、构建或设备操作。
