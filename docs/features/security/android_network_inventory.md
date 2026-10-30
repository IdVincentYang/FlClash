# Android 联网用途清单

本清单说明应用、Core 和系统移交分别因何联网、接收方能看到什么，以及实际保护和验证边界。
共同判据见[安全目标](security_requirements.md#正常联网与额外暴露的判定)；接收必要请求不等于额外采集。
范围是当前 Android 实现及受检 ARM64 dev/release APK；不记录用户实际地址、凭据或访问历史。

## 阅读与执行归属

- 应用请求：UI/调度发起，RequestSession 和相应 Core/native 边界管理资格、出口和取消。
- Core：正常业务转发、DNS、协议及内部维护，按配置与作用域判断，不能从 Dart 请求规则推导全部行为。
- 系统移交：浏览器、相册/SAF、字体提供方的后续网络由外部应用或提供方执行，与应用自身上传分开。

源码能力、配置启用、受控运行观察是三层事实。默认/候选来源不代表一次全部访问；代理节点、DNS 服务和最终站点
看到的数据也不同。以下 HTTP 请求即使经代理，接收方仍能看到请求内容及代理出口；明文段还可被沿途观察。

## 用途索引

| 用途 | 触发/执行者 | 接收范围 |
| --- | --- | --- |
| [订阅](#订阅刷新) | 手动或合资格调度→Request/Core | 配置的订阅服务器及允许的跳转目标 |
| [脚本](#脚本下载与执行) | 编辑/更新→Request；Rust 本地执行 | 脚本 URL；变换后的配置可能引出其它用途 |
| [远程图标](#远程图标) | 展示/预取/编辑预览→缓存→Request | 配置图标 URL，无统一公共默认主机 |
| [WebDAV](#webdav-备份与恢复) | 页面连通性检查、用户备份/恢复→DAVClient | 配置的 DAV 服务器及跳转目标 |
| [手动更新](#手动检查版本) | About→Request；接受后浏览器 | GitHub API；浏览器后续另算 |
| [站点/延时](#站点与延时诊断) | 可见基本卡片/手动操作→Core | 本节列出的站点或配置测试 URL |
| [IP/分类](#公网-ip-与分类) | 手动；明确开启后有限自动→Dart/Core | Cloudflare；显式分类为 Proxycheck |
| [业务/DNS](#业务流量dns-与节点协议) | 已接受配置与业务→Core | 实际节点、解析服务、最终目标 |
| [Core 维护](#provider规则geo-与健康检查) | 配置周期/初始加载/用户操作→Core | 配置 provider、Geo、检查 URL |
| [条件能力](#ntp控制接口及可选协议) | 配置、作用域和构建条件→Core | NTP、控制接口下载、协议控制/中继服务 |
| [本地与移交](#原生插件及系统移交) | 初始化/权限/用户选择→原生或提供方 | 本地处理；外部应用/提供方按各自行为联网 |

## 应用请求的共同边界

[Request.begin](../../../lib/common/request.dart)
把用途 key、数据集/来源版本、操作和生命周期关联到原生/Core 授权；
[ServiceState](../../../android/app/src/main/kotlin/com/follow/clash/ServiceState.kt)
拥有服务运行意图。
停止、暂停、来源修改、同 key 替换等使旧会话失效；提交前重查，不能把迟到成功当作当前结果。
取消不撤回已被远端接收的数据；本地提交已准入片段与新的网络资格也分别管理。

- Auto：运行且就绪时交当前 Core 规则选择；特定空闲/用户停止/SSID 排除状态的手动维护可选 Direct，自动请求没有该空闲豁免。
- Proxy：使用明确节点/组；managed 配置使用受控维护目标，缺少目标或代理失败时拒绝，不静默重试 Direct。
- Direct：是显式请求模式，仍须原生可用物理网络、socket/protect 与用途资格，不是绕过服务状态的裸 socket。
- 首次导入/Geo 恢复的 bootstrap：仅特定手动入口，经一次用途/主机确认及版本绑定许可；不改持久 Proxy 偏好，不授权自动重试。
- Android 未接入 Request 的普通非 loopback Dart HTTP 会被全局 override 拒绝；
  这不约束所有 native/第三方独立网络实现。

普通请求 UA 来自 global-UA、请求 UA 或应用包名/版本；HTTP URL、认证、查询参数的必要性由各用途决定。
普通 Dio 默认允许跳转，TLS 受 `checkCertificate` 设置影响；该开关默认 true，关闭后可接受不受信任证书。
局部诊断的固定 UA、严格 TLS 和跳转约束不能推广到这些请求。
[HTTP override](../../../lib/common/http.dart)及调用处仍可能记录 URL、证书信息或错误；
T04/T05 通用整改暂缓。

## 订阅刷新

入口为[订阅动作](../../../lib/providers/actions/profiles.dart)和
[刷新队列](../../../lib/providers/actions/profile_refresh.dart)。
手动导入/编辑/刷新，以及启动、可见性/服务状态、周期唤醒后的合资格自动刷新，均使用订阅的模式与来源版本。
自动刷新还检查逐项开关、到期时间、运行且未暂停；20 分钟唤醒不是每 20 分钟必定向每个订阅发送请求。

GET 到用户配置 URL；服务器看到 URL 中令牌、普通 UA 和请求出口。没有把整个配置或报告作为下载请求体发送。
HTTP/HTTPS 均被下载器接受，普通跳转与证书设置按共同边界；服务器响应可包含订阅用量/文件名等信息。
下载/内容接受失败保持既有材料；保存新材料与将其安装成活动配置是不同结果，后者受配置接受链约束。
来源变化或取消拒绝旧结果；同源任务合并/串行，不因 UI 连点无限并行。
网络失败自动间隔为 1/2/4/8/16/20 分钟，资格拒绝等待相关状态变化，取消不计作网络失败；这些重试状态不持久化。

## 脚本下载与执行

[脚本动作](../../../lib/providers/actions/scripts.dart)在新建/编辑来源或用户更新时，从配置的脚本 URL
GET 文本，
使用该脚本的 Auto/Proxy/Direct；没有独立自动更新定时器。UA、HTTP/TLS/跳转沿普通请求。
失败不替换原脚本；成功也须当前来源和提交资格，使用中的脚本随后可触发配置重新接受。

[Rust QuickJS](../../../plugins/rust_api/rust/src/script/mod.rs)执行是本地配置变换，项目注册
console 等本地能力，
未注册 HTTP/socket host API；这不是把脚本文本上传执行。输出 YAML 仍可能声明节点/provider/远程图标等，
这些后续请求按相应消费者归类，不能由“本地脚本执行”推导输出配置没有网络能力。

## 远程图标

[常规图标展示/预取](../../../lib/widgets/icon.dart)和
[图标编辑预览](../../../lib/views/profiles/overwrite/custom/icon.dart)
均调用 [getFileStreamV2](../../../lib/common/cache.dart)。来源为代理组/用户配置的图标字符串；
空值用本地图标，base64 本地解码，
URL 没有统一默认接收方。显示、预取及编辑 URL 可触发 GET，服务器看到该 URL、普通 UA 和出口。

缓存先回显；有效缓存直接返回，否则通过 `automatic:true` 的 RequestSession 下载并在当前资格下写缓存。
新文件缓存有效期为 7 日，内存缓存/磁盘淘汰、URL 变化和未命中仍可触发请求，不能解释成固定七日零请求。
流订阅取消会关闭会话；旧缓存更新失败时仍可显示，首次失败显示替代图标/错误。
HTTP/TLS/跳转按普通请求；预取失败日志可含原 URL，T05 尚未统一处理。

## WebDAV 备份与恢复

[DAVClient/连接控制器](../../../lib/common/dav_client.dart)把配置的地址、认证和模式交给
RequestSession，
再把会话 Dio 注入 [DAVTransport](../../../lib/common/webdav.dart)；并非另建绕过会话的默认客户端。
页面初始化/凭据变化、隐藏后恢复可发 OPTIONS 连通性检查；隐藏/离页取消 ping，不把同时进行的显式备份/恢复一并取消。
文件名变化不重复 ping。备份/恢复由用户操作，分别发送 MKCOL/PUT 或 GET；没有常驻自动备份上传任务。

接收方为配置服务器，路径含备份目录和文件名；Basic 或受支持的 Digest 认证发送给同源，普通 UA 与证书设置仍适用。
PUT 正文是[备份动作](../../../lib/providers/actions/backup.dart)选定的配置、数据库、订阅/脚本
/provider 文件归档，可能包含秘密；
不是脱敏报告摘要。报告私有目录不在这些备份项内，配置了 WebDAV 不表示授权上传崩溃报告。

401 可接受一次 Digest 挑战，支持的重定向最多 5 次；跨源不转发 Authorization，但方法和已有正文仍由循环重新发送，
没有通用禁止 HTTPS 降级/跨源正文的独立规则。HTTP 地址、普通证书开关及备份体转发是 T04 的明确剩余风险。
连接 8 秒、发送/接收各 60 秒；错误返回失败，不另换服务器/直连。来源失效拒绝结果；本地恢复失败及补偿另由恢复机制处理。

## 手动检查版本

[About](../../../lib/views/about.dart)→`Request.checkForUpdate` GET
`https://api.github.com/repos/chen08209/FlClash/releases/latest`，仅用户手动发起。
公开固定目标、普通 UA、无应用设置的 GitHub 登录凭据；普通 TLS/跳转仍适用。
结果保留会话身份，接受前再验证，取消/旧结果不能替换当前结果；失败不自动换源或下载 APK。
同意打开发布页后交给浏览器访问 `https://github.com/chen08209/FlClash/releases/latest`，
后续下载/登录按外部应用处理。
启动/后台自动检查入口及旧开关已删除；这不删除订阅自动刷新。

## 站点与延时诊断

[站点卡片](../../../lib/views/dashboard/widgets/service_status.dart)→
[ServiceStatus](../../../lib/providers/service_status.dart)
→[Core service checker](../../../core/service_check.go)。
可见的已选基本卡片可自动请求，列表批量/高级诊断由用户操作；
高级详情仅 watch 不自动探测。禁用项、可见性/生命周期、路由版本和同目标任务替换约束调度；
[RoutedProbe](../../../lib/providers/routed_probe.dart)按目标最短 30 秒、结果最长 5 分钟，
过期和失败不冒充当前可用结果。

基本目标为 HTTPS：Google/YouTube 的 `generate_204`，以及 GitHub、ChatGPT、Claude、Gemini、
Netflix、Disney+、
Prime Video、Spotify、TikTok、Bilibili 的注册站点。每个选中目标基本检查至多一个匿名请求，不读登录 Cookie；
302/403 等是实际 HTTP 观察，不全部折算成不可达。高级候选接收方如下，确切路径及条件由
[诊断规则](../../../core/service_rules.go)维护：

| 高级用途 | 候选主机/数据 |
| --- | --- |
| YouTube、Claude、Gemini、Prime、Spotify、TikTok | 各注册站点；固定页面/trace/API 参数 |
| ChatGPT | ios.chat.openai.com、chat.openai.com、api.openai.com；分步观察 |
| Netflix | api.fast.com、www.netflix.com；公开固定 API 参数及节目/地区页面 |
| Disney+ | disney.api.edge.bamgrid.com；公开客户端认证、匿名设备/令牌及临时会话 |
| Bilibili | api.bilibili.com；固定公开视频/剧集查询参数 |

这些不是用户浏览器登录态；Disney+ 等仍有认证字段/匿名会话交换，不能笼统写成“高级诊断不发任何认证或设备字段”。
所有站点诊断使用固定浏览器 UA、严格 HTTPS 身份验证，删除 Cookie/Referer。
[service transport](../../../core/service_transport.go)限定用途和候选，基本不跟跳转；
高级 GET 仅有限同主机 HTTPS 跳转，
POST 不转发，整轮发送数/读取量/时限有界。代理失败不回退 Direct，未运行代理时明确的 Direct 探测与代理结果分开。
某步失败可继续该高级规则允许的其它步骤，不是切换任意新来源；结果只解释本次请求，不证明播放、登录或整机流量安全。

[节点延时动作](../../../lib/providers/actions/proxies.dart)按用户选择的节点/组和 test-url 调用
Core URLTest，
默认 `https://www.gstatic.com/generate_204`，可由配置改变，数据为测试 URL/普通 Core HTTP 头及出口，
不等同于上述固定站点 allowlist。队列有界，取消/路由变更拒绝旧结果；Core 自动健康检查另见下节。

## 公网 IP 与分类

当前完整规则见 [IP 查询设计](ip_lookup_design.md)，本节仅给用途对应关系。
[OutboundIp](../../../lib/providers/outbound_ip.dart)经 RequestSession 和 Core 请求
`https://www.cloudflare.com/cdn-cgi/trace`；该服务据请求出口返回 IP/国家，不附被查 IP 参数。
默认手动；开启自动后还要求前台仪表盘有相应卡片、运行且未暂停；隐藏/离开取消，包括详情里的手动请求。

[IP 分类](../../../lib/providers/ip_quality.dart)只在详情显式点击后查询
`https://proxycheck.io/v3/{ip}?tag=0`，路径向 Proxycheck 披露已展示的公网 IP；
显示 IP、进入详情、预览不触发分类。
两类均固定浏览器 UA，无 API key、Cookie、Referer、应用版本 UA/设备 ID；严格 TLS，不跳转、不换源、不在代理失败后重试
Direct。
缓存绑定 IP/来源/路由，最短 30 秒、通常 5 分钟；403/429/服务拒绝按错误和有界 Retry-After 冷却，届满不自行重试分类。
hideIp 只隐藏界面显示，不改变已授权请求的出口或服务可见 IP。

## 业务流量、DNS 与节点协议

Core 接收 TUN/本机代理入口中的业务数据；节点、解析服务和最终站点由已接受配置及实际路由决定，没有固定总站点清单。
接收数据可包括目标地址/域名、DNS 问题、协议认证与业务载荷；节点能见到的明文取决于代理及端到端加密，不能称为应用遥测。
业务 HTTP 的 Cookie/Authorization 由业务应用产生，不能与本应用诊断“不用浏览器 Cookie”混为一谈。

[配置应用](../../../core/config_apply.go)、[业务 DNS](../../../core/config_dns.go)、
Core dialer 与 Android socket gate
共同约束 owner/服务资格；停止后新准入与已准入请求的结束分别处理。managed 当前只接受受控 SOCKS5 节点、选择组及生成规则，
拒绝多种任意外部入口/自动功能；legacy/unmanaged 能力更广，不能把 managed 的限制推广到所有导入配置。
路由、DNS 和节点协议的正式工作继续归 [Loop 2](loop2/loop2_plan.md)，04/05 子项未完成。

DNS 接收方由实际配置的 default/proxy/direct nameserver、policy、fallback、系统/网络 DNS 等决定；
UDP/TCP DNS 可明文，DoH/DoT/DoQ、DHCP/system 和代理解析按各自实现，TLS/重试/缓存不是 RequestSession
的 Dio 设置。
[应用 DNS 模型](../../../lib/models/clash_config.dart)的初始 default-nameserver 候选为
114.114.114.114、223.5.5.5、8.8.8.8、1.0.0.1，初始 nameserver 为 doh.pub 与
dns.alidns.com 的 HTTPS 服务。
Core 原始默认还含 `tls://223.5.5.5:853`；managed 编译及覆盖会改变最终值，模型/编辑器建议不等于运行中的解析接收方。
缓存、并发 fallback、节点解析和 bootstrap 可产生多次/多类查询，不据此认定复制全部访问历史，也未完成所有协议实网验证。

## provider、规则、Geo 与健康检查

[Core hub](../../../core/hub.go)及 mihomo
[resource](../../../core/Clash.Meta/component/resource/fetcher.go)
承接初始/周期 provider、规则集和手动维护。
HTTP vehicle 发送配置 URL、可配 header、Core/global UA、URL 认证及条件 ETag；
file/inline provider 是本地来源。失败使用可用旧内容/退避，来源/owner 失效不能提交旧内容；首次无可用内容可能使配置失败。
managed 禁止任意 proxy-provider 和就地 mutation，不意味着 legacy 的 provider 能力不存在。

[Core HTTP](../../../core/Clash.Meta/component/http/http.go)
在已安装 BeginHook 时拒绝缺少 lease 的调用，
有 lease 时绑定其 dialer/Context，每跳检查 URL，最多 10 跳；TLS 还受 Core CA/请求选项影响。
这比裸客户端多一层资格检查，但不是站点诊断的固定接收方规则或普通认证/降级整改的替代品。

[Geo 动作](../../../lib/providers/actions/geo_resource.dart)、缺失数据恢复与
[Core updater](../../../core/Clash.Meta/component/updater/update_geo.go)分别有手动、
特定 bootstrap 及配置周期路径。
公开默认为 GitHub 的 `MetaCubeX/meta-rules-dat/releases/download/latest/` 下
MMDB/ASN/GEOIP/GEOSITE；
实际 URL 可由配置改变，GitHub/CDN 跳转接收方不是每次固定的另四家。
GET 含 Core UA/必要 URL，下载经现有格式/可解析性检查后写入；失败保留旧数据，周期任务可在后续重试。
这些检查不代替 Loop 6 的官方版本/内容真实性核对。
启用 scoped hook 后缺失 Geo 不通过旧的无 scope 下载兜底；managed 禁止 geo-auto-update，
手动维护仍按实际资格判断。

[HealthCheck](../../../core/Clash.Meta/adapter/provider/healthcheck.go)及
URLTest/fallback/load-balance 组
可按配置启动、周期或 lazy touch 自动检查节点；可向同一检查 URL 经多个节点发请求。
接收方为配置检查 URL（常用默认 gstatic generate_204），看到各节点出口；间隔、lazy、过滤与有效节点决定实际请求数。
requestscope/owner 与上下文约束停止和撤销；失败更新健康结果/组选择，不等价于应用维护请求静默降为 Direct。
Core URLTest 的 TLS、跳转及协议实现仍须按消费者判断，不套用高级站点诊断规则。

## NTP、控制接口及可选协议

- NTP：Core 默认关闭，默认候选 `time.apple.com:123`、30 分钟；启用后初次/周期发送时间协议数据，
  使用配置 dialer-proxy 或明确 Direct，经 requestscope 资格等待/检查。不是 HTTP，Dio
  UA/TLS/redirect 不适用。
  managed 拒绝 NTP；Android 不具备任意系统时间写入权限时不会凭配置取得该权限。
- 外部控制/UI/Core 更新：legacy 配置可建立控制入口或声明 UI 下载；公共 UI 默认是 MetaCubeX/metacubexd 的
  GitHub ZIP，
  Core updater 候选为 MetaCubeX/mihomo GitHub release。源码中的这些 URL 不等于每次启动必发请求。
  当前 wrapper 安装的 BeginHook 使 UI/Core updater 的无 lease HTTP 调用在发送前被拒绝；
  managed 另拒绝外部控制/UI。
  不把被阻断的源码能力当成成功更新证据；控制面及其它 legacy 入口继续归 Loop 2/4。
- 可选节点/传输：当前 APK Go buildinfo 为 `with_gvisor`；Tailscale 工厂条件满足，Easytier 未设禁用
  tag，
  配置须实例化相应 legacy adapter，并经 Dial/相应 overlay DNS 等路径进入 ensureStarted，
  才可能建立其控制、发现、DNS、STUN/中继或 peer 流量；不能只按 UI 是否选中该节点判断。
  managed 仅允许 SOCKS5，不能因此声称可选协议从包中不存在。
  [Tailscale adapter](../../../core/Clash.Meta/adapter/outbound/tailscale.go)
  注入系统 dialer/解析，显式设置 NoLogsNoSupport，
  并把 hostname/auth-key/control-url 等交给 tsnet；这不证明控制服务完全没有必要设备/协议元数据。
  [Easytier adapter](../../../core/Clash.Meta/adapter/outbound/easytier.go)交付
  peers、network secret 等配置到其运行时。
  配置校验拒绝 peers/listeners 均空时隐式使用 public.easytier.top，不据此保证底层发现协议无其它默认来源。
  精确动态接收方、协议字段、重连和取消覆盖尚未逐协议运行验证；归 Loop 2/4/5/7，不作整包无额外外发保证。
- REALITY：配置采用该传输且握手后认证未通过时，
  [fallback](../../../core/Clash.Meta/component/tls/reality.go)会异步在已有连接上按配置
  SNI 构造 HTTPS GET，
  UA 为指纹 client 名，Cookie 为随机零填充的 padding，不是用户浏览器 Cookie；不是无条件后台站点诊断。
  此失败分支的运行时/取消与响应跳转未独立验收，归 Loop 2/4；不从一般 RequestSession 取消推导其已验证。

## 原生、插件及系统移交

当前 Android 插件注册根共 16 个：android_file_picker、app_links、connectivity_plus、
device_info_plus、dynamic_color、
flutter_plugin_android_lifecycle、image_picker_android、jni、jni_flutter、
mobile_scanner、package_info_plus、
path_provider_android、shared_preferences_android、sqflite_android、
url_launcher_android、wifi_ssid。
注册名不是上传证据；Dart/原生源码、初始化和实际包同时核对。

- 网络事实/权限：ConnectivityManager 注册 callback 并读取 LinkProperties DNS 等本地事实，VPN
  protect/绑定网络服务于实际出口，
  未在这些监听代码中发现独立公网探测。INTERNET、网络/Wi-Fi/位置、CAMERA 等权限表明能力/系统门，不证明发生数据上传。
  Android 系统自己的连通性检查不归本应用的诊断接收方清单，实际设备未观察。
- 扫码：[本地 ZXing 方案](qr_scanning_design.md)保留相机/相册，应用内解码不自行上传图片/结果。
  扫码结果后续导入订阅会进入订阅请求。相册/文件提供方可能先取回云文件；图片解码与该提供方行为分开。
  image_picker 的通用 disabled ModuleDependencies service/action 保留，确切 Photo
  Picker required metadata 已移除，
  不能写成整个 image_picker 或所有 GMS 声明被删除。
- 恢复/报告：[恢复契约](boot_recovery_design.md)、[报告契约](crash_reports_design.md)与
  [使用指南](crash_reports_guide.md)定义私有保存、容量/期限、摘要及显式原文导出。
  原生写 no-backup 私有目录，普通备份/FilesProvider 不夹带原文；应用没有自动上传报告调用。
  用户导出才把摘要/明确选择的原文通过专用 SAF URI 写给提供方；云提供方可能随后上传，取消也不能撤回其已收取数据。
- 外链/文件：[openUrl](../../../lib/common/dialog.dart)、更新发布页、About 链接交给
  url_launcher/浏览器；
  app_links 是接收用户 URI 的入口，后续动作各自归类。浏览器可能携带自己的 Cookie、使用自己的代理/DNS、继续跳转/下载，
  不受本应用 RequestSession 的取消/TLS 保证。SAF、相册、系统设置移交也不据 UI 测试宣称完整系统网络已验收。
- 本地桥接/存储：Rust IPC、JNI/MethodChannel、数据库、偏好、路径/包信息、动态颜色等服务本机调用。
  扫描到 database 中 SocketException 分类、desktop helper HTTP 和编辑器 URL 建议不是新的
  Android 公网请求生产者。

### 自动字体提供方

最终 manifest 的 AndroidX Startup 仍注册 EmojiCompat、ProcessLifecycle、
ProfileInstaller。
离线依赖与 AAR 字节码确认 Emoji2 1.3.0 的初始化在生命周期恢复后延时安排加载；它按
`androidx.content.action.LOAD_EMOJI_FONT` 查询已安装提供方，选择带系统 application flag 的候选，
取其 authority/package/签名构造 FontRequest，校验提供方包名和证书，再经 FontsContractCompat 获取字体。
固定 query 为 `emojicompat-emoji-font`，提供方缺失/加载失败走失败回调，不改查用户订阅/图片/报告。

提供方包名/证书是本机选择与校验条件，不是上传签名。实际内容查询到选定 authority 的 content URI，
使用固定字体列投影、`query = ?` 和上述字体查询串对应参数，随后读取提供方返回的字体 URI；系统调用身份对提供方可见。
这条链没有把应用配置/图片/报告或浏览内容作为查询参数/HTTP 请求体。
已有缓存或本地字体可能直接返回；提供方也可能独立下载，是否发生、远端地址、HTTP 字段、缓存/重试和路由取决于设备/提供方，
本次未安装启动设备，不能确定为 Google、每次联网或已经上传用户内容。
该自动初始化不经过 RequestSession，列入 Loop 3/7 的设备提供方核对；没有把未知写成零外发。
ProcessLifecycle 是生命周期通知，ProfileInstaller 是本地 baseline profile 安装；未因同属 Startup
树推定它们也下载字体。

## 证据与尚未闭合边界

本轮核对的源码基线为 `6aff7f3`，生产/生成/测试未改；复用的 T12 APK SHA-256 起始为 `1753d276d13d`，
包名 com.follow.clash.dev、0.8.99/2026102301、ARM64 release、Debug 签名。
1000 份构建输入中 998 份与当前字节相同，2 份 locale 为已核实 token 等价的格式差异；不是从本清单提交重新构建的包。

- 已静态核对：入口正查与网络根反查；当前离线依赖/插件注册、最终 manifest、R8 原始类来源、DEX 和 10 个 native 库。
  未发现 Firebase/ML Kit/DataTransport 依赖/初始化回流；ZXing 及保留的 Emoji 初始化已分别列出。
  自动应用检查无调用入口；扫码/报告处理链没有应用上传生产者。依赖缺席不证明其它 SDK/协议所有条件都无外发。
- 已受控观察：真实 Dart Request 与提交边界中的成功、拒绝、取消/迟到，DAV 资格/并发 IO、TLS/CONNECT；
  Core 请求授权、provider 撤销、DNS 准入/停止、站点匿名基本请求及高级跳转/正文/认证隔离。
  这些使用本地 HTTP/TLS/DNS 和合成代理/权限 seam，不能证明 Android JNI/protect、真实节点和系统提供方行为。
- 明确保留失败：旧独立 dav_client 测试未装配当前 DAV 来源资格，出现 ping 失败和异常本地化缺失；
  不能用它宣称真实 Android WebDAV 已验收。当前 scoped DAV 消费者的本地结果与此旧夹具分别记录。
- 尚未运行/未知：远程图标缓存淘汰的完整运行矩阵、外部服务实时协议、全部可选传输的控制/中继数据、
  真实设备网络切换、系统字体/相册/SAF 云端行为及发布签名包。
  对应 Loop 2/3/4/5/7；Geo 内容/分发信任另归 Loop 6。T04/T05 和 L2-T02-04/05 未闭合，
  本清单不以短时零流量、部分通过或完成任务数宣布 Loop 1/全应用安全完成。
