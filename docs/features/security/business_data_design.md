# Android 业务数据处理与覆盖边界

**L2-T04 实现评审已通过，交付收尾中；Android 禁用增量已实施并完成本机验证与 ARM64 构建，未做设备安装验证。** 本文维护业务正文、连接 metadata、统计和日志的当前处理说明及覆盖边界。
共用链已做源码审查和本机 DIRECT／SOCKS5 合成验证；其它 adapter 主要为入口及选定分支走读。
这些证据不等于 Android TUN 实测或整个安装包的安全结论，不据“没有观察到”排除其它路径。
正常用途的判定依据是[共同安全目标](security_requirements.md)，联网功能入口见[用途清单](android_network_inventory.md)。

## 数据类别与正常接收关系

业务应用产生正文、URL、Cookie／Authorization 和目标；FlClash 接收被接管连接，完成路由、协议和转发。
合法目标、所选节点和 DNS 是不同接收方：未加密 HTTP 的节点可读取业务内容，端到端 TLS 通常使节点只能看到密文和必要连接信息。
这不代表节点、控制／发现服务、日志或本地消费者可以无用途地得到其它数据。
节点认证、代理入口 username、业务认证与域名标签分别判断，不能混称为一种秘密。

| 类别 | 处理用途 | 当前审查状态 |
| --- | --- | --- |
| 请求／响应正文和 datagram | 转发、协议封装及必要瞬时缓冲 | 本机 TCP／UDP 正反例通过；ZeroTier 的条件副本见后文 |
| HTTP Host／TLS SNI／DNS 问题 | 域名识别、解析与路由 | HTTP／TLS 提取与可选失败已实测；DNS 沿既有边界，R1 未解决 |
| 源／目标、UID／process、规则／chains、时间 | 连接显示、统计、路由诊断 | 原始 Go envelope 已经真实 Dart parser／provider／页面消费；JNI 为源码核对 |
| 字节计数 | 速率、累计流量与通知 | tracker 计数层次已核对，累计数值实际进入 Traffic usage；不是整机线上字节 |
| 日志／错误／故障材料 | 本机诊断和用户显式导出 | stdout／事件／内存与文件有不同控制；显式导出含 metadata，失败可残留临时文件 |

## 正文与 metadata 的交接

[Android TUN](../../../core/tun/tun.go)把 fd 交给 sing-tun；
[sing-tun handler](../../../core/Clash.Meta/listener/sing_tun/dns.go)区分 DNS 与普通连接，
[sing handler](../../../core/Clash.Meta/listener/sing/sing.go)构造 Core metadata。
[HTTP 入站](../../../core/Clash.Meta/listener/http/proxy.go)会解析和重新发送普通请求，CONNECT 交接流；
[SOCKS 入站](../../../core/Clash.Meta/listener/socks/tcp.go)与 UDP 入站分别处理握手和 datagram。
已走读 fd／handler／metadata 交接和本机入站处理；实际流量验证使用 host 本机代理，不能冒充 Android TUN 证据。

[Core tunnel](../../../core/Clash.Meta/tunnel/tunnel.go)执行 metadata 处理、可选 sniffing、选路和出站，
TCP 经 [Relay](../../../core/Clash.Meta/common/net/sing.go)，UDP 经 [packet sender](../../../core/Clash.Meta/tunnel/connection.go)。
TCP Relay 把读取交给双向复制，UDP sender 按关联转发；所读共用函数未发现将正文交给独立审计／上传消费者。
这一源码事实与有限运行反例相互印证，不能覆盖所有包装和依赖。
[sniffer](../../../core/Clash.Meta/component/sniffer/dispatcher.go)从初始缓存提取域名，TCP read-ahead 上限为 64 KiB；
缓存继续交给后续转发，不是新增正文档案。可选 sniffing 失败可继续原目标，不能把它视为必须拒绝的边界。
协议必要加密、压缩、重发和 multiplexing 会产生封装、缓存或控制包，须按配置与接收方解释。

[Tracker](../../../core/Clash.Meta/tunnel/statistic/tracker.go)与 manager 提供连接和计数，
[wrapper hub](../../../core/hub.go)提供 getConnections／traffic 及 request event。
Go [Metadata](../../../core/Clash.Meta/constant/metadata.go)还包含 `inboundUser`、`sniffHost` 等字段；
[Dart 模型](../../../lib/models/common.dart)仅接收部分字段，页面未显示不能证明它未过 bridge。
本机验证区分正文、URL、Cookie／Authorization、节点认证和 Host／SNI 标记：
预期端点收到正文，原始事件／连接 RPC／累计流量 RPC 未包含该组业务正文或认证标记。
这只适用于受测配置和标记，错误文本、其它协议及节点凭据全面脱敏仍不能据此通过。

tracker 的 upload／download 是其连接层 read／write 计数，不是正文长度，也不是全部协议控制包或设备 NIC 字节。
[manager](../../../core/Clash.Meta/tunnel/statistic/manager.go)同时维护总量与非 DIRECT 量，每秒换出速率样本；
连接 Close 移出活动表，累计数值须由 reset 操作清零，不能用连接消失推断历史计数已删除。
`notifyProbeRoute` 只把匹配的既有 probe metadata 的 rule／chains 回填，不因普通业务事件另发一次探测。

本地事件经 Go envelope／JNI、[ServiceController](../../../android/app/src/main/kotlin/com/follow/clash/ServiceController.kt)、
[ServicePlugin](../../../android/app/src/main/kotlin/com/follow/clash/plugins/ServicePlugin.kt)、
[Dart Service](../../../lib/plugins/service.dart)与 [CoreManager](../../../lib/manager/core_manager.dart)到达 provider。
ServiceController 保留消费 configState 的 native 回调，Flutter detach 与 native listener 是否存在不是同一条件。
Go [message queue](../../../core/message.go)按类各容纳 256 条，最多 32 条／16 ms 一批；满队列可能丢弃或淘汰，
因此事件不是无遗漏的业务历史。JNI 复制序列化数据，Kotlin 将本地事件交 MethodChannel；所读转交函数未见新增文件或网络接收方。
Flutter listener dispose 停止其消费，但 native 的 configState 回调仍可能使 Go 编码 metadata；detach 不能当作全链停采开关。
本项运行以实际 Go JSON 驱动 Service、CoreLib、CoreManager、provider 与页面，测试替代了 MethodChannel/native 转交；
没有执行 JNI／Android 服务。没有增加第二个路由或运行资格权威。

## 保存、输出与关闭范围

| 接收／保存位置 | 触发、内容与生命周期 | 已核实的边界 |
| --- | --- | --- |
| Core stdout | [log](../../../core/Clash.Meta/log/log.go)按 level 输出 metadata／诊断／错误文本 | `startLog`／`stopLog` 只订阅／退订 wrapper 的事件流；不关闭 stdout，Android 实际 OS 收集范围未实测 |
| Flutter 内存 | [Logs／Requests／Traffics](../../../lib/providers/app.dart)分别保留 5000／2000／30 条；暂停页面另可保留 10000／4000 条头部记录 | 这些 provider 不自动写业务数据库；fullSetup 的重置与普通 Stop 不同，Stop 不保证清除历史记录 |
| 显式日志导出 | Logs 把当前文本写临时文件，再交 [Picker](../../../lib/common/picker.dart) 及用户选择的目的地 | 成功保存或返回取消后删除临时文件；picker 抛异常时当前实现未执行删除，合成反例保留了含 metadata 的临时文件；不是隐式网络上传 |
| preferences／SQLite／备份 | 保存配置、节点材料与用户资产；[backup](../../../lib/common/backup.dart)按 BackupEntries 白名单写 archive | 实际新库 10 个用户表均无业务记录；真实备份消费者只写 config.json 与 database.sqlite，不含显式导出的日志。此空库观察不能排除其它配置／错误路径 |
| Core cache／ConfigInput 文件 | [cachefile](../../../core/Clash.Meta/component/profile/cachefile/cache.go)可保存 selected、fakeip／fakeip6、etag、subscriptioninfo、storage；T01 保存接受的 YAML 与描述符 | storage 可由控制接口写任意值，不是证明自动保存正文；本项关闭 selected／fakeip 保存的临时根只有配置材料，不能据此证明全局不持久化 |
| 诊断报告 | [故障报告契约](crash_reports_design.md)维护 noBackupFilesDir 私有 raw 材料与显式导出 | 原始异常／系统 trace 可能含秘密；沿既有契约，未新增逐包采集或自动上传，未在本项重跑设备故障 |
| Android 通知 | NotificationsModule 查询 getTraffic 并格式化上下行速率 | 源码消费者是计数，不含业务正文；实际通知／权限／锁屏展示未在本项设备验证 |

显式导出的普通连接日志含目标、chains 等 metadata；节点材料本来就在配置／备份中，与新保存业务正文须分别判断。
当前无法宣称日志全面脱敏。失败导出的临时保留是已观察到的清理缺口，尚未修复；不能因导出失败声称本地没有副本。
用户选择系统云文件提供方可能产生后续同步，应用不能保证所选目的地只在本机。

## 协议覆盖与待审边界

以下覆盖绑定 Core `6c6e3e472bb246cc55f2e8577d9eddccc2623afc` 及其 module pin。
本次 Android 构建保留基础 `with_gvisor` 并追加 `no_zerotier`，使用既有拒绝工厂；其它平台保留原 tags。下表的 ZeroTier 能力证据来自禁用前的源码与独立依赖实验。
[ParseProxy](../../../core/Clash.Meta/adapter/parser.go)与后续 AutoClose／smux 包装是配置入口。
“入口走读”表示已读构造、Dial／ListenPacket 和选定包装／控制分支，不表示整个外部依赖已审；下列未注明运行的协议均未进行真实通信。

| 路径与源码入口 | 已覆盖的数据交接／额外接收关系 | 仍未证明 |
| --- | --- | --- |
| [DIRECT](../../../core/Clash.Meta/adapter/outbound/direct.go)／[SOCKS5](../../../core/Clash.Meta/adapter/outbound/socks5.go) | 共用层深入走读；普通／受管 TCP、UDP、本机 HTTP／CONNECT／SOCKS 与 HTTP／TLS sniffing 实测；节点握手与业务 header 分开 | Android TUN／实际外部节点与物理网络 |
| [HTTP](../../../core/Clash.Meta/adapter/outbound/http.go) | 出站 CONNECT、配置认证与 TLS 握手入口；本机 HTTP 入站解析重发另有实测 | HTTP 出站节点、全部非标准 header／错误组合 |
| [SS](../../../core/Clash.Meta/adapter/outbound/shadowsocks.go)／[SSR](../../../core/Clash.Meta/adapter/outbound/shadowsocksr.go) | 加密／地址／UDP 封装；obfs、v2ray／gost plugin、shadowtls、restls、jls、kcptun 的选择与包装；obfs HTTP Host 是已有节点连接上的字段 | 全部插件 runtime、密码实现和重传／复用边界 |
| [VMess](../../../core/Clash.Meta/adapter/outbound/vmess.go)／[VLESS](../../../core/Clash.Meta/adapter/outbound/vless.go)／[Trojan](../../../core/Clash.Meta/adapter/outbound/trojan.go) | 协议目标、UOT／XUDP／packetaddr 入口；ws／http／h2／grpc、mkcp／mekya／xhttp 选定分支；VLESS download-settings 可指定独立下载 Server／Port | 稀有 transport 的全部依赖与 runtime；不能概括为只联系一个节点 |
| [TLSMirror](../../../core/Clash.Meta/adapter/outbound/tlsmirror.go)／[REALITY](../../../core/Clash.Meta/adapter/outbound/reality.go) | TLSMirror 存在 cover 请求／enrollment 控制与隐藏加密通道；REALITY 认证失败可对配置 SNI 作回退 GET；ECH 可触发 HTTPS DNS record 查询 | cover／认证／重试整个时序及取消保证；名字含 mirror 不等于复制业务明文 |
| [Snell](../../../core/Clash.Meta/adapter/outbound/snell.go) | header、池复用、obfs、UDP transport 入口 | 深层 pool 与协议 runtime |
| [Hysteria](../../../core/Clash.Meta/adapter/outbound/hysteria.go)／[Hysteria2](../../../core/Clash.Meta/adapter/outbound/hysteria2.go) | packet dialer／QUIC；Hy2 可配置 realm HTTP／STUN／token 控制接收方，使用配置的 dialer | realm 与 QUIC 底层完整走读及运行；不能仅列所选节点 |
| [TUIC](../../../core/Clash.Meta/adapter/outbound/tuic.go)／[ShadowQUIC](../../../core/Clash.Meta/adapter/outbound/shadowquic.go) | QUIC client、配置 server／认证、控制／keepalive 入口 | 完整底层 client 与协议运行 |
| [WireGuard](../../../core/Clash.Meta/adapter/outbound/wireguard.go)／[OpenVPN](../../../core/Clash.Meta/adapter/outbound/openvpn.go)／[MASQUE](../../../core/Clash.Meta/adapter/outbound/masque.go) | IPStack、peer、封装、远端 DNS 与必要保活入口；WireGuard 的 debug tag 可把 IPC 配置交日志 | 加密栈、VPN runtime；默认 with_gvisor 不启用该 debug 分支，不代表全部日志已脱敏 |
| [SSH](../../../core/Clash.Meta/adapter/outbound/ssh.go) | 私钥文件／认证、缓存连接和目标通道；缺少 HostKey 配置时的验证限制已识别 | SSH 身份安全及实际节点，仍受 L1-T04 限制 |
| [Mieru](../../../core/Clash.Meta/adapter/outbound/mieru.go)／[AnyTLS](../../../core/Clash.Meta/adapter/outbound/anytls.go)／[Sudoku](../../../core/Clash.Meta/adapter/outbound/sudoku.go) | 懒启动、注入 dialer／resolver、session／UOT／mux／HTTP mask 与配置目标的入口交接 | 外部库的完整 framing／状态／runtime |
| [GOST relay](../../../core/Clash.Meta/adapter/outbound/gost_relay.go)／[TrustTunnel](../../../core/Clash.Meta/adapter/outbound/trusttunnel.go) | relay 目标与控制 flags；HTTP／QUIC pool 和 healthcheck 入口 | 外部库与池／控制包全部执行路径 |
| [DNS](../../../core/Clash.Meta/adapter/outbound/dns.go)／[REJECT](../../../core/Clash.Meta/adapter/outbound/reject.go)／[REMATCH](../../../core/Clash.Meta/adapter/outbound/rematch.go) | DNS 复制查询交 resolver；REJECT 本地拒绝／丢弃；REMATCH 修改 metadata 后重选路 | DNS 全链新验收未运行，沿 R1 未决边界 |
| [smux](../../../core/Clash.Meta/adapter/outbound/singmux.go)／[AutoClose](../../../core/Clash.Meta/adapter/outbound/base.go) | 包装选定 adapter，复用／封装与关闭入口 | mux 底层完整运行与组合能力 |
| [Tailscale](../../../core/Clash.Meta/adapter/outbound/tailscale.go) | 状态目录、tsnet 注入、懒启动和 overlay DNS；控制／DERP／STUN 接收方另于业务目标 | tsnet 底层完整审查、控制运行与状态文件实际内容；未启动 |
| [EasyTier](../../../core/Clash.Meta/adapter/outbound/easytier.go) | 配置 TOML／安全状态目录、host services、实例启动和 ID 保存入口 | 全部 peer／发现／DNS 服务依赖；未启动 |
| [ZeroTier](../../../core/Clash.Meta/adapter/outbound/zerotier.go) | adapter 接入、状态／控制与 trace 字段；pinned dependency 的签名配置＋frame 纯内存正反例见下节 | 实际 overlay 和全部依赖未运行；Android 采用下述禁用边界，不保留该出站能力 |

managed 只接受受控 SOCKS5 等既有范围，不能由此推导普通配置其它能力不可达或不存在。
ConfigInput／T01、ServiceState、Request 的现有所有权保持不变。
[R1 共享 IP 与域名身份](deferred_security_items.md#l2-t02-r1-共享-ip-与域名身份)仍未解决；
本项不重新研究 Core 修复、不更改源／gitlink／carrier，也不将审查完成等同 DNS 安全通过。

## ZeroTier 的额外 payload 接收能力与 Android 禁用

当前 pinned `github.com/metacubex/zerotier-go` 为 `v0.0.0-20260813124750-13fa6f45da5f`，
由 [Core module](../../../core/go.mod)绑定；以下能力已由源码及纯内存公开 API 实验相互印证，尚未启动真实 overlay。
它不是已经发生用户泄漏或恶意实现的断言，也不能只按正常站点／所选节点的可见范围省略。

- [ZeroTier adapter](../../../core/Clash.Meta/adapter/outbound/zerotier.go)把本地 `remote-trace-target`／level
  交给 runtime；runtime 还接受网络配置中的 trace target／level 和规则。
- dependency 的 `traceTargetsLocked` 同时采用全局与 network 配置。
  level 达到 rules（15）时，`traceNetworkFilterLocked` 把 frame payload 前至多 256 bytes
  放入 `frameData`，编码为 `VerbRemoteTrace`，发给相应 target；并非只有连接计数。
- `Node.SendFrame` 及入站 frame 处理还执行规则的 TEE／WATCH；
  `sendRuleFrameWithFlowLocked` 可把 payload 的指定前缀或整帧复制给另一 ZeroTier member，
  普通目标的正确收件不能排除该副本。

是否包含明文取决于该 frame 承载的业务协议；TLS ciphertext 与明文 HTTP／UDP 不能混为一谈。
用户已决定在 Android 版禁用该出站支持，不接受 controller 镜像能力作为本轮出口；
增量已按 M1 通过的设计在父包装层实施，实际验证与制品绑定见[本项结果](loop2/l2_t04_result.md#android-禁用增量的实际验证)；实现评审已通过，交付收尾中，不沿用 R1 的记录许可结案。
仅删除本地 YAML trace 字段不足以排除 controller 的 network trace／TEE。
采用现有 `no_zerotier` tag，使新 Android Core 使用拒绝工厂；实际解析到该节点的候选不再可用。
基础 tags 与其它平台保持原行为；普通节点、provider、动态材料、旧缓存仍须经过真实接受边界，
失败不得因空 provider 静默回退 DIRECT。旧 APK 当前仍不能给已禁用／无额外正文接收方的通过结论。

获准的纯内存实验已通过公开 Node、MemoryStore、WireSender 和真实协议握手／签名配置形成闭环。
原定 peer 与额外 target 使用独立合成身份解码实际 wire 输出；输入为含明文 UDP marker 的 376-byte IPv4 frame。
网络配置为 public，controller／原 peer／额外 target 均预置为自定义 Planet roots；
这是明确的公共 API 信任设置，不能无条件推广到任意私有网络或普通 member 权限。

| 配置 | 原定 peer | 额外 target 的 payload |
| --- | --- | --- |
| 无 trace／TEE／WATCH | 完整 frame | 无 |
| global trace rules level | 完整 frame | 前 256 bytes |
| 本地 target 关闭，仅 controller trace | 完整 frame | 前 256 bytes |
| 本地 target 关闭，controller TEE／WATCH | 完整 frame | 376 bytes；TEE 指定长度时为前 64 bytes |
| 损坏签名／错误签名者／错误 issued-to | 配置未就绪，SendFrame 拒绝 | 不采用该配置 |

首轮配置已接受但 peer 路径未认证，未生成帧；补实际 HELLO／匹配 OK 后才得到上述输出，未注入依赖私有状态。
三个无效配置反例未执行同样的 peer 握手，只证明给定输入被拒绝／网络未就绪；
不以错误字符串单独归因各项认证校验，或概括完整认证安全性。
实验没有 socket、wireTransport、真实 overlay、Core adapter 实例或 Android 执行；
`192.0.2.x` 仅是内存路由标签。它证明该 pin 的条件能力，与 adapter 可达性作源码对应，
不证明用户实际泄漏，也不自动决定保留、禁用或接受 controller 镜像。
最小复现入口为 [手动诊断](../../../core/zerotier_data_test.go)，仅在显式提供证据目录时运行。

### Android 接受与初始化边界

当前 Core 异步启动 provider Initial，ApplyConfigStaged 返回不表示初始化完成；空组默认 COMPATIBLE 是 DIRECT。
父 wrapper 设置 staged 初始化完成边界，不靠日志、界面字段或源文件字符串推断成功。
本配置的 file／HTTP proxy 与 rule provider 必须实际完成 Initial，且 Apply 已退出，
在重新核对相同 receipt、owner、来源／运行资格后才可 installed／activate；等待期间业务 scope 不激活。
重复 install 共享同次结果，提前 activate 被拒绝，不能用 `cfg != nil` 推导安装完成。

采用 30 秒整体初始化预算，覆盖前一工作退出等待、Apply 与全部必要 Initial；
等待在 configMu 外，Stop、替换和来源／运行失效同步关闭本候选资格，不等 ready 重试来满足接受条件。
成功后撤除初始化 deadline，保留 provider 的原 lifetime；动态坏材料继续保留旧合法集合，不能接受部分解析结果。
原 provider 集合身份、Owner／Proxy／JSON 与更新接口保持；RequestContext 保留原 context 并关联配置退出。
路由 lease 比较同一原 provider，必要 rule Initial 返回前的 Strategy 视为未就绪（nil），返回后直接委托，避免快照读取正在替换的指针。
来源／dataset revision 改变时唤醒原 changed 通知，等待者重核资格并关闭失效候选。

兼容变化是：此 Android 构建不再允许 file／HTTP proxy 或 rule provider 初始化失败／未完成时先运行候选。
有效 cache 可离线成功；缺失／坏 cache 按原声明尝试材料来源，最终无成功结果则失败关闭。
必要请求沿既有 inner／provider-initial 路由与引导资格，不新增自动 DIRECT 或 bootstrap 授权。
原解析阶段真正产生 bootstrapRequired 时仍由已有显式引导／重新提交处理，初始化超时不自动取得该许可。
显式 filter／exclude-type 原本排除的节点与真正进入 parser 的不支持节点不同，不能声称任何来源含 ZeroTier 字符串就必拒绝。

取消不等于底层工作已退出。Close 请求与原 Close 分开：封闭新的 Initial，
在 appRequests 内匹配原 owner 同步撤销 lease／取消 context，禁止新 dial／迟到 commit，把可能阻塞的关闭移出锁，
在 Apply 退出、已进入原 Initial 全部返回后才于 configMu 外幂等清理，避免 watcher 建立与 Close 并发。
同一时刻只允许一个全局应用／初始化／退休工作持有进入许可；旧 Initial 会按 provider 名关闭连接，
新候选须等旧工作及清理实际退出后才能进入 Apply，不能只禁止旧集合 commit 就让新业务先运行。
不响应取消的工作留在隔离中；Stop／RPC 不等待其原 Initial／Close 无界退出，后续候选取不到许可便失败关闭，
不无限派生 worker。
这不承诺强制终止 goroutine；恢复要求旧工作实际退出或按现有所有权重新启动 Core 所在进程，不新增杀进程操作。

### 全局生命周期与就地重建

上述进入许可也覆盖真正的 Go Shutdown 和 Init，包括 prepareConfig 携 InitParams 的直接初始化。
逻辑 Stop 只关闭本 owner 的业务／维护资格，不证明全局清理完成；
Android `Service.shutdown()` 实际经 ServicePlugin／ServiceController 解绑，也不能当作 Go handleShutdown。
Go Init 的实际应用调用方是 CoreController.init／CoreAction.initCore，不能绕过同一关闭边界。

在关闭请求到达时封闭新 prepare（分配 owner 前）、install、activate 和 Init，取消所捕获 owner 的请求，
在 configMu 外等原 Apply／Initial／provider 清理真正退出，再独占执行原 Go 全局清理。
原 worker 未退出或物理关闭仍未返回时，不提前 isInit=false；currentConfig 即便因逻辑失效被撤下，原 cfg 仍归退出工作持有，
内部初始化值只随真实 Init／Shutdown 结果改变，关闭期间 RPC 通过现有 MethodError 表达生命周期不可用，
避免应用把 getIsInit 的捷径或 init 的 bool 结果当成重建许可。
只有清理成功并重核本关闭工作的所有权后才报告成功，随后新的 Init 才能创建资源。

关闭期间排队的 Init／旧 registration 不在关闭完成后自动执行；利用现有 RPC 到达顺序限定其资格，
迟到 Shutdown 回调只完成原工作，不能清新 owner。重复关闭共享同次结果，
超时／不响应取消仍保留关闭 fence 和资源隔离，逻辑 Stop 不等待原工作无界退出；不自动强杀或无限再派生清理。
正常同目录 warm Init 保持幂等，默认未采用 no_zerotier 的构建仍沿原路径。
非 Android cgo 的退出清理原有 3 秒预算属于尽力清理；真正进程退出才销毁地址空间，
不能把解绑、超时或调用返回等同进程已退出。Android cgo 不编入该 exit.go 路径，本项不增加进程退出行为。

## 用户观察入口与限制

以下是既有 English UI 入口，尚不是本项完成的设备体验记录：

1. **Start** 后正常访问站点；**Dashboard → Live connections** 可打开当前连接，
   **Traffic usage** 展示累计数值。导航 **Live connections** 用于查看连接信息。
2. **Tools → General → Logs and diagnostics → Logcat** 控制日志相关入口／订阅；
   不据入口隐藏推导 stdout、原生日志、已经缓冲的记录或报告全部消失。
3. 导航 **Logs → Export logs** 是显式文件操作；目标可能由系统文件提供方承接，
   用户选择云目的地可能产生系统同步，不能宣称导出保证只在本机。

后续以真实输出和源码说明每个开关实际停止什么、保留什么；本项不会代用户导出、上传或分享。
