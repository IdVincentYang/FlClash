# L1-T08 IP 查询用途与披露范围 Plan

任务入口：[L1-T08](loop1_tasks.md#l1-t08-确定并修改-ip-查询行为)。推荐保留出口识别和按需 IP 分类，拆开触发并收窄来源；
以下是候选，产品决定仍由
[Loop 1 未决表](loop1_plan.md#功能决定与待细化事项)维护。源码调查基线为
`4e9f1b3477814b6f199a6ebb413e6a54da6f360c`；IP 设计阶段未运行测试或探测。新增 Disclaimer
删除的实际结果见
[Result](l1_t08_result.md)。

## 问题与目标

本项新增的 Disclaimer 删除已获用户明确要求，由 M1 交接后独立实施；design_v2 的 IP 技术方案已通过，产品选择仍未决。

| 范围 | 当前决定与边界 |
| --- | --- |
| Disclaimer | 删除首次启动同意／退出流程、工具页入口、专属页面、接受状态及仅依赖它的 gate/listener；保留 LICENSE、版权与第三方许可证 |
| 公网 NetworkDetection／IpQualitySheet | 下述去留、触发和来源候选待定；含 grade/type/flags/org/ASN/source/retry/hide/copy，不随 Disclaimer 删除改动 |
| IntranetIP／localIpProvider | 独立本地卡片，不是公网查询；本项不调整 |

Disclaimer 增量先在 `loop1_plan.md` 记录当前决定，移除 `.agents/rules.md` 中过时的启动对话示例，
再删除专属代码与四种 locale 文案并正常生成。
旧配置中的 `disclaimerAccepted` 按未知键忽略，不写死 accepted、不新增开关。Request
的其它路由／来源／取消资格及订阅刷新到期、开关、ServiceState 继续有效；
保留启动完成、started、appVisible 的现有刷新触发，不增加调度器或 IP 查询。既有专属测试删除、夹具失效字段移除；M1
已澄清删除所需的局部合成验证属于本次明确指令，不能扩大为待定 IP 候选验证。
该独立增量交实现评审，不代表 T08 整体完成，不提交／合入独立设计里程碑。

用户需要判断某次请求从哪里出去，以及某个 IP 被第三方怎样分类。目前默认仪表盘的
[NetworkDetection](../../../../lib/views/dashboard/widgets/network_detection.dart)
自动观察
`routedOutbound`；得到 IP 后渲染
[IpQualityText](../../../../lib/features/ip_quality/ip_quality_text.dart)
便会查询质量，打开详情不是必要触发。`hideIp` 只遮罩文字和 Tooltip；详情的复制动作仍取原 IP。
移除卡片后，打开“添加组件”仍会构建同一真实卡片；IgnorePointer 只禁用点击，不阻止其 watch。
不调整时，查看地址会连带向更多接收方查询，HTTP 还允许中间方观察或修改内容；这些事实不证明服务恶意。

### 当前两条请求链

| 用途 | 触发、数据与接收范围 | 出口、失败与展示 |
| --- | --- | --- |
| 公网 IP／国家代码 | 挂载卡片、相关路由变化、失败后 retry／resume；[9 个固定来源](../../../../lib/common/service_probe.dart)不带被查 IP，Go 先发 1 个，800 ms 错峰、最多 3 个并发，失败可立即补位，最多尝试 9 个；首个可用回答后取消其余 | 运行时按各目标的规则选出口；未代理时显式 `DIRECT`。6 s 总期限、4 KiB body；失败卡片统一显示 Timeout。只显示胜出 IP 与国家旗帜，不能代表其它网站或全设备出口 |
| IP 分类／风险标记 | 上述文字、详情均 watch [ipQuality(ip)](../../../../lib/providers/ip_quality.dart)；首波 3 个、随后每 1 s 或前波结束推进，最多 6 个；取首个明确类型，否则用推断结果 | 使用独立 RequestSession，按质量域名当前规则路由，可能与被查 IP 不同；成功按 IP 保留到 provider container 销毁，失败临时 keepAlive 5 min，到期只释放保留，不主动重试；详情 invalidate 可重查，仍标为 automatic |

出口来源依序是 `www.cloudflare.com/cdn-cgi/trace`、`api.ip.sb/geoip`、`ipinfo.io/json`、
`ipwho.is`、`http://ip-api.com/json`、`get.geojs.io/v1/ip/geo.json`、
`api.country.is`、
`api.ipquery.io/?format=json`、`ident.me/json`；除显式 HTTP 项外均为 HTTPS。
质量来源的[实际 URL](../../../../lib/common/ip_quality.dart)与必要数据为：

| 波次 | 接收方／路径 | 被查 IP 如何发送 |
| --- | --- | --- |
| 1 | `https://ident.me/json` | 不附 IP，查询自身请求出口；响应 IP 不匹配则拒绝 |
| 1 | `http://ip-api.com/json/{ip}?fields=…`、`https://api.ipquery.io/{ip}?format=json` | URL path |
| 2 | `https://iplocate.io/api/lookup/{ip}` | URL path |
| 3 | `https://api.ipapi.is/?q={ip}` | URL query |
| 4 | `https://proxycheck.io/v3/{ip}` | URL path |

两条链均使服务器看到请求出口；后五个质量来源还得到被查 IP，能关联二者。
出口查询发送固定 browser User-Agent；质量查询继承配置的 globalUa 或应用 UA。
未发现这两条调用主动附加订阅、登录 Cookie 或设备稳定 ID。Go 普通 probe 默认跟随 redirect；
Dart 质量调用也未设置专用 redirect 限制，且继承 `checkCertificate`。现有 request lease 约束生命周期和路由，
不能代替本用途的接收方／TLS 校验。失败日志还包含被查 IP。
上述数量是来源数，redirect 可增加实际请求及接收方；质量 begin 中的 `ipwho.is/{ip}` 和出口 begin 中的
`diagnostic.invalid` 是准入标记，本身未被请求，不能再计作接收方。
当前分类的 `.timeout(8 s)` 逐来源作用于 Future，不主动取消底层请求，也不是整轮期限。
`_fromIpApiIs` 未核对响应 `json.ip`，直接把输入 IP 写入分类结果，因此类型有效也可能归错地址。

[OutboundIpProbe](../../../../lib/providers/outbound_ip.dart)目前仅有仪表盘这一生产 watch
入口；
节点参数和把回答写入出口节点缓存的能力仍存在，但未找到节点 UI 消费者。
T07 服务诊断已不消费 IP provider，不能由此推断仪表盘也已整改。
卡片离开、隐藏、路由失效会通过 RoutedProbe 调用取消；等待 begin 时的撤销窗口尚未验证。
质量 provider 在 dispose／原生请求状态失效时关闭 session，
没有自己的 appVisible 取消规则。卡片自动查询却沿用 `withSession` 默认 manual 标记，Android 闲置时可进入允许的
DIRECT 分支；
质量始终标 automatic，闲置时被阻止。真实设备时序尚未验证。

## 方案与理由

### 需要人类确认的选择

| 选择 | 推荐候选及价值 | 真正影响选择的替代项／代价 |
| --- | --- | --- |
| 公网 IP／国家代码 | 保留，默认手动；可明确开启前台仪表盘自动刷新，默认不替旧用户开启 | 删除会失去实际出口观测；维持默认自动更省操作，但持续产生已披露的第三方请求 |
| IP 分类 | 保留详情中的显式单次查询，展示来源、被查 IP、时间及分类；地址文字不再启动查询 | 删除可完全避免这类外发；自动查询保留现有便利，但即使不看详情也要接受额外接收方 |
| 来源与兼容 | 出口仅用现有 Cloudflare HTTPS trace；分类仅用现有 `api.ipapi.is`，不自动换源 | 单源故障降低可用性；保留多个 HTTPS 来源须明确选择接收集合和失败顺序，不能继续隐式竞速 |
| 归属数据 | 复用出口回答中的国家代码，暂不引入本地查询 | 本地 Geo 可减少后续归属查询，但不能发现 NAT／代理公网 IP，不能替代实时风控分类；现无 Dart 查询 API，数据准确性／来源仍接 Loop 6 |

来源推荐仅依据现有 HTTPS 端点及 parser 所需字段，不表示已验证当前协议、配额、准确性或服务可信度。
旧版已有卡片和 `hideIp` 不等于接受新增自动查询设置。若选择删除，先调整任务范围和消费者；若接受自动质量或多源，先修订本方案再实施。

### 推荐候选的技术边界

复用 `RoutedProbe`、`RouteTracker`、`RequestSession`，不增加第二套队列。出口由 Go 现有
`outboundIp` 执行，分类保留 Dart 受管 session；不新增旁路 client。手动／自动标记必须与真实动作一致：
手动且闲置时明确显示 DIRECT，禁止故障静默切 DIRECT。出口自动用途须同时满足 `appVisible`、当前导航为仪表盘、
已配置正常卡片、服务运行且已开启自动；滚出 viewport 或弹窗遮挡不改变资格，不承诺遮挡检测。
沿用现有 schedule 能力：同用途／来源至少间隔 30 s，出口自动结果 TTL 5 min；手动模式只标 stale、不自动重查。
分类缓存按 IP／来源记录观测时间，不把旧 IP 的结果标成当前出口。
添加组件的预览使用无请求展示，不持有自动观察；正常卡片才拥有已选择的自动用途。

分类仅由显式查询／重试 action 创建一次请求意图，并在等待 begin 前固定 IP、来源和 generation。
provider build／watch 只读状态；打开详情、native provider 重建、retry 状态重建均不产生新意图。
失败、取消、路由失效或详情关闭后不重放旧意图；再次发送须有新的显式 action。

每轮只访问选定 HTTPS 端点，拒绝 redirect，强制 TLS 验证，固定通用 UA，不附 Cookie／Referer／应用标识；
不受全局关闭证书检查影响。候选出口／分类的整轮期限分别为 6 s／8 s，从受理起覆盖等待 begin、排队、DNS／TLS、
发送、body 读取和结果接受；到期实际取消请求与 stream，不只让 Future 提前返回。晚到的 session 立即关闭，不能继续发送或回填。
出口 body 上限沿用 4 KiB；分类在接收流中累计 parser 输入字节，上限 64 KiB，超限立即取消，不先无界读成 String。
仅在完整 EOF、无读取错误且未过期时解析，截断响应即使含有效字段也失败。

查询输入与分类响应 `json.ip` 均须为合法公开 IP literal；按规范化地址字节比较，IPv6 压缩／展开及大小写等价，
IPv4-mapped IPv6 统一为 IPv4，拒绝 zone ID、URL 片段、私网和畸形地址。缺失／畸形／不匹配的响应 IP 均失败，
不把输入 IP 填入结果来掩盖身份缺失。取消、离开／隐藏、路由失效以及等待 begin 期间撤销，均在发送前复查资格，
取消在途并丢弃迟到结果。

结果只证明指定端点本次看到的地址，不再把回答推广为节点对所有目标的出口。
分类缺字段为 unknown，不再把未声明 hosting／mobile 推断成 residential；已有类型和风险标记分别展示，
去掉 Good 等安全暗示。`hideIp` 标为显示设置，复制原值保持显式动作。错误区分取消、超时、拒绝、限额和解析失败，
本用途日志不记录 IP、完整 URL 或 body。以上局部身份／跳转／日志保护是独立完成 T08 的条件，04/05 全面整改仍暂缓。

## 实施与验证

先完成设计评审和上述产品选择，再交付真实受影响的文档基线，然后才写生产代码及对应测试：

1. 修改 `loop1_plan.md` 的 IP 两行决定及相关当前解释；新增
   `../ip_lookup_design.md`，维护获准触发、接收方、数据、路由、失败／缓存契约和使用限制，标明未实现部分；
   从 `../flclash_security_plan.md` 链接该稳定主题。修改 `.agents/architecture.md` 的 IP
   消费／缓存说明并引用它，
   不复制另一份规则。共同需求无需改写，不回写 T07 等历史 Plan／Result，不提前做 T13 联网总清单。
2. 对齐 `OutboundIpParams/Result`、`IpInfo/IpQuality` 及 provider 的必要契约注释、配置迁移和四种
   locale 的 UI 文案，
   随 schema 变化正常生成。实现卡片／详情、来源策略、局部 transport 保护，再做对应验证；不手改生成物。
3. 实际验证后新增 `l1_t08_result.md`，记录被测版本、结果和限制；本 Tasks 只维护归属、状态、验收入口。
   D 保留任务定稿至合入，由 M 按新规范做交付 Details 和任务文档清理。

拟验收使用合成数据、可控时钟、fake adapter 和 loopback HTTP/TLS；须由 M 核实本项新增／运行测试的人类许可，
T07 许可不沿用。以下均为待执行：

| 真实消费者／风险 | 方法与预期反例 |
| --- | --- |
| 默认仪表盘、添加卡片预览、IP 文字／详情 | 手动默认、仅打开详情／切 hideIp 均零额外查询；自动关闭／移除卡片、退出仪表盘或应用后台后不再发送；滚出 viewport／弹窗遮挡仍按前台仪表盘语义处理；预览永不请求 |
| OutboundIpProbe → RequestSession → Go handler | 使用真实 begin 队列与 Go consumer，分别卡住 begin、dial、body 后撤销；旧任务零新增发送、无迟到写回；DIRECT／规则路由分别核对，故障不降级 |
| 分类 provider → session.dio → 详情 | 被查 IP 与请求出口故意不同，URL 只含所选被查 IP；即使类型有效，错 IP／缺 IP／畸形 IP 也失败，IPv6 等价形式可接受，截断响应失败；旧缓存有时间／来源；429、缺字段、字段矛盾无“缺风险即安全” |
| 单次 action 与实际期限 | native provider／retry 状态重建、重开详情均不增加发送，新的显式重试才多一轮；卡住 begin、慢 header／body、持续分块越限，整轮到期／越限时接收端观察到取消且无后续发送／回填 |
| transport 与现有消费者回归 | 错误证书、跨源／降级 redirect、Cookie／UA 与日志秘密反例；每轮仅一个获准来源，失败不换源；回归 RoutedProbe、RouteTracker、T07 不外查 IP；按影响选择 generation、analyze、Go vet 与必要 ARM64 build |

上述 IP 候选设计仅有源码和既有测试内容的只读证据，未为该候选复跑测试。外部站点兼容／真实性、第三方分类准确性、Android JNI／设备、
宿主 TUN 与全设备流量均未验证；本地夹具不能替代这些结论。不改 mihomo／gitlink／carrier，不启动其它任务，不 push 或上传。
