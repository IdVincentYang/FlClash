# L1-T03：应用请求的出口与生命周期

本设计已获 M 通过，第三轮固定 Direct、Geo 完成通知/无 hook 兼容与 R9 票据四点已获复审关闭，第四轮已修订失效 Geo 父范围的子申请登记边界，并完成窄回归与新 ARM64 绑定，已获 M 实现复审通过，当前本地收尾；实际状态、结果与下一交付见[验证记录](l1_t03_result.md#当前修订状态与接续)。获审设计 SHA-256 为 `f0849056e085ed62c078d9b6c4c060fe94bcce49233ccbe62fb16b2395062344`，原文保留在本地忽略证据目录。方案在现有请求入口增加一次用途的生命周期：固定出口，撤销时取消连接/后续请求，保存前取得资格。Dart、Go探测和核心下载分别接入真实通道；Android服务仍由ServiceState仲裁。

依据为[共同安全目标](../security_requirements.md)、[Loop 1 范围](loop1_plan.md#核实应用自身联网的完整范围)和 [L1-T03](loop1_tasks.md#l1-t03-修改请求出口与生命周期处理)。源码起点 `be9bc7d`，派工基线 `75ef51024ae543864382f8ced679d38edd53f343`，核心子模块 `8597778c7df410ebe88c57e59eaab32d203156df`。D 为 D-02，M 为 Codex；任务分支为 `security/l1-t03-requests`，复用共享 checkout，在该基线上实施。

## 本项要形成的能力

- 首次导入、手动维护及已接受的 DIRECT 请求仍可工作。
- 已按核心路由发起的请求不因暂停、启动失败、断开或重试而自行改用 DIRECT。
- 自动刷新经过初始化和用途许可；后台可以执行已接受的订阅刷新，后台本身不代表可以改变出口。
- 改变配置、停止服务、删除订阅、关闭自动刷新或替换 WebDAV 凭据时，取消受影响的旧请求；旧结果不覆盖当前文件或状态。
- 核心 provider、Geo 和节点探测有真实边界；原生扫码 SDK 的通道和未覆盖能力明确记录。

TLS、认证和跳转完整整改归 L1-T04，全面日志脱敏归 L1-T05，订阅调度和诊断产品语义归 L1-T06/07，IP 与扫码选择归 L1-T08/09，业务规则/DNS 合成归 Loop 2。本项包含消费者接入、取消和保存时的必要调整，不重建这些功能。

## 已核实的消费者与差异

以下是基线事实，不是整改后的验证结果。`DIRECT` 表示直连目标；“核心路由”表示交给接受的规则或指定节点，规则合法选中 DIRECT 时也属于正常路径。

| 消费者 | 当前入口与通道 | 已确认的生命周期问题或约束 |
| --- | --- | --- |
| 订阅导入、手动/自动刷新、缺失文件恢复 | [Profile.update/saveFile](../../../../lib/models/profile.dart)、[ProfilesAction](../../../../lib/providers/actions/profiles.dart)、[SetupAction](../../../../lib/providers/actions/setup.dart) → `Request._clashDio` | 未 attach 时 DIRECT；`isStart=false` 或排除 SSID 时 DIRECT。响应后还经历临时写入、Core 校验和文件复制，没有贯穿保存过程的撤销检查。自动/手动/初始化恢复可以重叠 |
| 脚本下载/更新 | [Script.update](../../../../lib/models/common.dart)、[ScriptsAction](../../../../lib/providers/actions/scripts.dart)、[配置页面](../../../../lib/views/config/scripts.dart) → 同一 `_clashDio` | 取得正文后保存并应用；未绑定来源变化、删除或被较新操作替代的情况 |
| 手动版本检查 | [About](../../../../lib/views/about.dart) → `Request.dio` | 独立 Dio 的默认 IO adapter 在首次使用时创建客户端，依赖全局 HttpOverrides；没有操作内固定出口。安装/下载按钮经外部浏览器处理，不是应用内下载 |
| WebDAV ping/备份/恢复 | [DAVConnectionController](../../../../lib/common/dav_client.dart)、[DAVTransport](../../../../lib/common/webdav.dart)、[备份动作](../../../../lib/providers/actions/backup.dart) | 独立 Dio；多次 OPTIONS/MKCOL/PUT/GET、认证重试和跳转不是一条请求。controller 的 requestId 只丢弃旧 ping 显示，不关闭旧连接；恢复下载完成后仍有解包和应用窗口 |
| 远程分组图标 | [icon.dart](../../../../lib/widgets/icon.dart)、[cache.dart](../../../../lib/common/cache.dart) → DefaultCacheManager → HttpFileService → http.Client | 全局 cache manager 可以在 HttpOverrides 安装前创建 IOClient；配置变更会预取图标。不能假定请求全部使用 `_clashDio` |
| IP 质量 | [ipQuality provider](../../../../lib/providers/ip_quality.dart) → `Request.dio` → [分波查询](../../../../lib/common/ip_quality.dart) | 现有 CancelToken 与 provider dispose 关联；出口变化不必然 dispose。同一查询包含后续波次；成功 keepAlive 不能代替出口/用途校验。功能去留、来源和触发不在本项选择 |
| 站点和出口 IP 探测 | [ServiceStatus](../../../../lib/providers/service_status.dart)、[OutboundIpProbe](../../../../lib/providers/outbound_ip.dart) → [probe.go](../../../../core/probe.go) | 停止/排除 SSID 时 provider 明确传 DIRECT；否则传规则或节点。未知节点失败，不回退 DIRECT。RouteTracker/RoutedProbe 已丢弃过期答案，但旧 Go 工作仍可继续；`claimService` 只取消同站点较旧检查 |
| 手动节点延时 | [ProxiesAction](../../../../lib/providers/actions/proxies.dart) → [handleTestDelay](../../../../core/hub.go) → Proxy.URLTest | 有两段超时和明确节点；UI 取消不等于 Go 上下文取消，URLTest 内部仍更新节点测量记录 |
| proxy/rule provider 下载 | [HTTPVehicle](../../../../core/Clash.Meta/component/resource/vehicle.go)、[Fetcher](../../../../core/Clash.Meta/component/resource/fetcher.go) → [核心 HTTP](../../../../core/Clash.Meta/component/http/http.go) | `proxy` 可为空、DIRECT 或指定组；指定名称缺失在 tunnel 中报错。HTTP helper 在 inner 通道没有初始化/地址构造失败时尝试普通拨号；定时循环与 listener 停止分离，读取后还有解析、写入和 onUpdate |
| Geo 首次缺失下载和手动/定时更新 | [geodata/init.go](../../../../core/Clash.Meta/component/geodata/init.go)、[update_geo.go](../../../../core/Clash.Meta/component/updater/update_geo.go)、[包装层](../../../../core/hub.go) | 初次解析可早于 inner 初始化；更新用 Background 上下文，停止 updater 的调度上下文不取消已经开始的下载。首次下载直接写目标路径，更新读取后还有校验、mmap 关闭和写入窗口 |
| 核心节点健康检查与 NTP | [healthcheck.go](../../../../core/Clash.Meta/adapter/provider/healthcheck.go)、[Proxy.URLTest](../../../../core/Clash.Meta/adapter/adapter.go)、[NTP service](../../../../core/Clash.Meta/ntp/ntp/service.go) | 不经过核心 HTTP helper。健康检查固定真实节点；NTP 无 dialer-proxy 时明确直连，有名称时使用严格 ByName，缺失名称报错。都有各自的配置生命周期，需要核对取消后的记录/offset，不改正常规则和 DNS |
| REST 更新入口 | [Android embed patch](../../../../core/Clash.Meta/hub/route/patch_android.go)、[upgradeRouter](../../../../core/Clash.Meta/hub/route/upgrade.go)、[UIUpdater](../../../../core/Clash.Meta/component/updater/update_ui.go) | Android embed 模式不注册 core/Geo 升级、配置写入及 restart；UI 升级仍注册。默认 controller 关闭，生成配置清空 external-ui/url，但原配置 external-ui-name 未清空，不能仅凭没有按钮宣称该下载绝不可达 |
| 本机 Helper/IPC | [helper_client.dart](../../../../lib/core/desktop/helper_client.dart) | 明确本机 DIRECT/Unix socket，不能被外部请求策略误拦；本项平台为 Android，保持已有桌面契约 |
| 原生扫码 SDK | mobile_scanner 7.4.2 + bundled barcode-scanning 17.3.0；L1-T02 的最终 manifest | ML Kit 初始化 provider、组件注册和 DataTransport 在 Dart main 之前可存在；Dart/Go 请求策略无法约束它们。模型随包不等于 SDK 无网络，实际采集未观察 |

[启动顺序](../../../../lib/bootstrap.dart)目前先启动自动订阅刷新，再处理偏好失败、免责声明、恢复提示、Core start 和 initStatus；[main](../../../../lib/main.dart)在 bootstrap.init 返回后才安装 HttpOverrides 和 attach Request。`coreStatus=connected` 只表示调用通道已建立，`isStart` 来自运行时间，Android `start/stop` 返回值是乐观命令结果，都不能独自证明实际服务和应用请求出口就绪。

核心解析配置可触发 Geo 下载；executor 在 apply 中先安装代理/规则，进入 Inner 后加载 provider，再进入 Running。listener 停止不销毁这些配置对象，不能把 `isRunning=false` 理解成所有内部任务已经取消。配置应用失败还会回滚到内建默认配置；本项必须阻止旧的“按已选配置请求”在该窗口被当作正常 DIRECT，业务流量的回滚语义留在 Loop 2。

## 已接受的出口与用途边界

当前没有逐订阅或全局的“始终直连/必须代理”请求设置，不能声称已读取了这样的偏好。已有输入是免责声明、手动用途、autoUpdate/autoRun、运行命令、所选配置、排除 SSID、明确探测目标和核心 provider 的 proxy 字段。

人类已确认对象级Auto/代理/直连方案，默认及旧数据为Auto。此前停用下仅手动维护DIRECT、自动刷新暂停和缺失订阅/Geo本次提示许可继续有效，不把autoUpdate改成false。下表描述Auto默认语义；新增模式的有限技术增量见下节，三态模型、迁移、界面与严格出口随本项实施，尚未完成实现验收。

| 情形 | 推荐出口/行为 | 依据与取舍 |
| --- | --- | --- |
| 未 attach、未接受免责声明、正在退出 | 禁止外部请求；本机协议单独按本机范围使用 | 没有可判断的用途与状态，缺少 reader 不是接受 DIRECT 的理由 |
| 已核实initializedIdle、明确stop或已接受paused下的手动订阅/脚本/更新/WebDAV维护 | 手动操作可登记DIRECT；状态改变取消旧范围，新用途重新登记 | 包含此状态下首次手动导入；新对象ID只确定登记key，不另授出口许可 |
| 明确停止或排除SSID后的自动订阅刷新 | 暂缓，不开始下一项/定时重试，不改autoUpdate=false | 原设置保留；恢复到有效native运行与配置后，沿原周期/到期判断继续，不补发已取消旧操作 |
| 正在启动/重启、autoRun 尚未收敛、曾要求运行但启动失败/服务丢失 | 需要核心的用途等待本次初始化完成或返回可识别的不可用错误，不自动改 DIRECT | 实际故障不能冒充用户主动停止；不永久等待、不重试直连，已有文件保留 |
| ready且native started，目的为跟随当前配置 | 通过绑定本次scope的mixed入口按接受的核心规则；首次新增订阅/URL脚本也遵守此条件 | 新对象不默认DIRECT；合法规则DIRECT保留，端口/认证无效时失败 |
| 用户配置的排除 SSID 命中 | 手动维护可登记DIRECT，自动维护暂停；旧范围取消 | 由人类明确选择；后台可接受的自动刷新仅在运行/配置条件恢复后继续 |
| 核心探测明确选 DIRECT 或具体节点 | 保留该明确选择；未知节点失败，规则目标要求有效配置 | 真实消费者已有意图，不把诊断节点测试统一改成当前业务规则 |
| provider 指定 DIRECT / 节点 / 空名称 | 分别固定 DIRECT / 该节点 / 当前接受的规则；移除隐式 raw dial 回退 | DIRECT 配置合法；名称消失、配置退化或未就绪时失败。内部通道可用与 listener 是否开放分别判断 |
| 尚未有可用配置时恢复缺失订阅/Geo | 提示后由用户选择本次DIRECT恢复；拒绝/取消时保留已有状态并返回bootstrap_required | 许可仅绑定本次所选对象和来源，不能据此给启动失败/服务丢失自动备用出口 |

引导提示说明对象、用途、来源接收方和本次DIRECT，提供接受/拒绝/取消。接受后登记内存许可`(对象key, 来源代际, 本次operation, native/config版本)`，仅该范围可开始引导DIRECT；URL/认证/选择/意图变化、较新操作、完成或退出使它失效，重试不换来源。不写全局开关或共享偏好，不从原许可派生新的Geo/订阅下载；解析发现另一个缺失对象需另一个明确选择。后台自动路径不弹恢复提示，标记需要用户恢复，避免隐藏界面获得许可。正常已接受刷新不逐次询问。

## 请求生命周期与所有权

### Dart：Request 管理连接，动作管理业务结果

在 [Request](../../../../lib/common/request.dart) 内集中创建操作范围；attach 接收可订阅、可释放的容器，而不是只能读取的 reader。每个范围只持有用途、固定出口、开始时的版本、取消令牌和实际客户端，不保存另一份服务期望状态。

- 普通 `dio` 和 `_clashDio` 改为由操作创建的 Dio/IO adapter；同一用途的重试、跳转、WebDAV 多步骤和 IP 查询各波次共享范围。
- 固定 DIRECT 或单一 PROXY，代理失败时没有 `; DIRECT` 候选；显式设置 findProxy，避免读取主机代理环境。保留 UA 和当前 TLS 设置，本项不改变证书接受政策。
- 操作间不复用旧连接池；取消时同时取消 CancelToken 和强制关闭该操作 HttpClient/adapter。关闭的 adapter 不再使用，新操作重新创建；不能仅换 findProxy 回调后保留旧池。
- 网络读取完成不立即结束范围。下载、校验、临时文件、保存、数据库更新和显示结果都在范围内；取消后不继续下一波、认证重试、跳转或保存。
- `HttpOverrides` 的无范围外部请求默认拒绝；本机 Helper 保留明确的本机工厂。已发现的独立消费者显式接入，不依赖全局 overrides 在正确时间创建客户端。
- 图标保留 CacheManager 的本地缓存接口，把远程下载交给 Request，下载成功且范围有效后写入缓存；避免 DefaultCacheManager 的长期 HttpFileService 绕过请求范围。旧缓存仍可读取。

取消令牌只能控制网络，不能保证已经返回的正文不会写文件。[Dio 关闭语义](https://github.com/cfug/dio/blob/main/dio/lib/src/adapters/io_adapter.dart)及本地锁定 dio 5.11.0 源码表明 adapter 持有缓存 HttpClient，close 后不能重新请求；[HttpClient.close(force)](https://api.dart.dev/dart-io/HttpClient/close.html)会关闭活动连接。[abort](https://api.dart.dev/dart-io/HttpClientRequest/abort.html)在 request.done 已完成后无效，因此仍须做业务提交校验。公开文档版本不同于本地 SDK，实施以 Flutter 3.47.4 / Dart 3.13.3 的实际实现核对。

ProfilesAction/ScriptsAction 接入下文的对象代际和提交资格；UpdatingKeys 仍只表达 loading，不作为网络/保存权威。自动刷新没有 loading token，初始化缺失文件恢复和首次脚本 URL 导入也必须登记同样的对象代际。文件、DB 和偏好不具有天然的跨资源原子性，资格授予后的有限提交及失败边界由下文定义。

WebDAV controller 替换/删除设置和 dispose 时关闭其旧 ping；备份/恢复各有完整范围，包含打包后的 PUT 和下载后的解包/恢复提交。ping 的显示 ID 和网络取消分别处理。更改凭据撤销旧操作，不把原始归档自动改传给新的服务。

IP 质量接入取消和有效性检查，取消后停止后续波次及 keepAlive；不增加/删除来源，不改变是否触发查询。手动更新结果在显示对话框前检查；外部浏览器的后续下载在说明中保留边界，不承诺其服从本应用通道。

### Android：观察并使用 ServiceState 的真实结果

[ServiceStateMachine](../../../../android/app/src/main/kotlin/com/follow/clash/ServiceStateMachine.kt)保留最新意图仲裁、STARTING/STARTED/STOPPING/STOPPED 和权限失败处理。请求层需要区分明确停止、启动中、启动失败和服务丢失；单独读取 runTime 或 coreStatus 不足。

推荐给现有 ServicePlugin 增加下文定义的只读请求状态快照及变化通知。来源、原因与实际阶段由 ServiceState 一次发布；不把 runTime、Token 和 MutableStateFlow 在读取时临时拼接，不调用会修改状态的 refresh。恢复时先读取原生快照，避免已有后台服务被 Flutter 初始的 `isStart=false` 解释成 DIRECT。

现有 UI 命令在发出前可以先使旧请求失效，但命令返回 true 不能开放需要核心的请求。Quick Settings、Always-on、系统 revoke、服务断开和无 Flutter engine 的路径在 ServiceState 内同步撤销 Go 请求范围；Flutter 通知接到后关闭 Dart 范围。Go 撤销必须先于相关异步服务清理，不依赖 UI 已挂载。

原生到 Dart 通知存在调度延迟。设计不宣称一个 UI callback 能在用户点击的同一瞬间关闭所有 Dart socket；受控验证须记录“意图进入权威、通知到达、连接关闭、资格授予/拒绝”的实际顺序。已经发送的字节不能收回，已到达服务器的 WebDAV PUT 也不能保证远端回滚。新操作向权威申请范围，保存前申请一次提交资格，不能用一次快照读取冒充提交门。Dart mixed 请求仍需关闭其真实连接，Go 探测/下载范围不自动覆盖这些 socket。若要求原生意图发生瞬间拦截仍未到达 Dart 的旧连接，需要另选具备该执行位置的传输方案，不能冒称当前通知足够。

### Go：包装层拥有请求范围，核心 HTTP 提供接入点

Go 请求范围按用途绑定当前接受的配置/原生生命周期；拥有 cancel context、已打开连接和结果提交资格。配置开始替换、应用关闭、原生撤销、明确取消或来源变化时，先取消旧范围。它是资源所有权，不是第二个 service 状态机；不取消全设备连接。

- 包装层的 probe/service/outbound IP/手动延时使用现有请求关联 ID 绑定范围，并提供对应取消入口。父上下文贯穿排队、拨号、重试、读 body；关闭持有的连接，避免只取消 DialContext 而留下已连 pipe。
- RoutedProbe 继续使用 RouteTracker 的 stamp 判定答案，不新增路由权威。路由结构变化、隐藏/解除用途、较新同目标操作及 dispose 时发送取消；节点选择变化按既有链判定，不用每秒 picks 变化盲目重启全部探测。
- 节点健康检查保持按实际节点拨号；配置对象关闭时取消，对取消结果不更新为节点“不通”。明确节点与合法 DIRECT 不被统一改成规则请求。
- 核心 HTTP 的现有 WithDialer 只能由调用方注入；provider/Geo 的内部调用及调度器不暴露完整的包装层上下文。仅改 `core/probe.go` 或 DefaultSocketHook 无法覆盖其 raw fallback、body 读取和写入。

因此推荐在子模块增加最小的可选“应用请求范围”接入能力，由 FlClash 包装层安装一次策略实现：开始范围、提供固定拨号器/上下文、验证/提交和释放。没有 FlClash hook 时保持上游默认行为；有 hook 时不再允许 helper 的隐式普通拨号。策略、Android 状态、版本和取消注册表都留在 `core/`，子模块只承接 HTTP 与其真实消费/保存点。

该能力需要穿过 HTTPVehicle/Fetcher、Geo 初始化与 updater 的读取—解析—提交边界；不能只在 HttpRequest 返回前校验。请求范围保存到本次读取结果，写入及 onUpdate 前由同一范围提交校验，不能用共享 vehicle 的一个可变“最近请求”字段造成并发串用。Geo 初始化下载改为临时文件，成功后受范围保护替换；取消/失败保留可用旧数据，旧 updater 不关闭新 mmap 或写新配置的路径。ETag、mtime、成功事件也属于提交结果。提交锁只保护本地结果切换，不在拨号/读取期间持有；不占用 configMu 等待网络取消，也不改变既有 configMu → selectMu 锁顺序。

内部 provider 初始化进入 Inner 后可以使用本次接受配置的路由，具体节点不可用时失败；暂停配置解析时不以 raw dial 绕过。初次 Geo 按已接受的本次提示许可处理。更新/重新配置不能借内建默认回滚重新获得 DIRECT 资格。

这是为 FlClash 增加核心内部请求控制能力，属于[核心补丁预算](../../../../.agents/rules.md#core-api-safety)中“没有边界外实现位置的功能”候选，不是未经说明修改任意上游缺陷。若 M 不接受此接入点，应选能覆盖同一实际消费者的等效方案；不能改用包装层入口拦截后声称内部任务已覆盖。

本地交付推荐子模块窄提交、父 gitlink 及父仓库内的完整恢复载体；具体内容等价、干净 checkout、标准构建/CI 和冲突处理契约见下文。普通远端 recursive checkout 不能取得未推送的新 gitlink，当前不把它写为可用发布方式。

NTP 无指定节点时的 DIRECT、有节点时严格 ByName 是独立配置用途；不把它误算成 HTTP 回退。配置撤销/关闭时保证所属任务取消和迟到 offset 不生效，包装层 shutdown 显式使用已有 ReCreateNTPService 的关闭入口，因为 executor.Shutdown 当前只清理 listener/IPTables/假 IP 池，没有停止 NTP。健康检查取消不发布为节点失败；配置重建释放旧 provider/healthcheck，而不是等待 GC finalizer。正常 DNS/NTP/节点路由配置不在本项重新合成。

Android embed 模式已拒绝 core/Geo REST 升级，保持该约束；对仍注册的 UI 下载，推荐在 FlClash 接入策略下拒绝没有已接受用途的请求，并清理生成配置遗漏的 external-ui-name 触发入口。这里只关闭无实际产品用途的下载入口，controller 的认证/暴露整改仍属 Loop 4；不因此改其它 REST 控制能力。桌面非 embed 的升级入口如受共享 HTTP 改动影响，保留平台差异，不能把 Android 的不可达结论推广到桌面。

### 初始化、后台与恢复顺序

1. 读取本地偏好、数据库、BootGuard 决定；未 attach 期间没有外部请求能力。
2. attach Request，连接真实生命周期观察，但保持外部用途入口关闭；完成偏好失败处理和免责声明。
3. 读取 Android 服务快照，启动 Core 通道，按既有 SetupAction 收敛配置和运行意图。`coreStatus` 连通不代表配置成功；配置失败按本项阻止旧应用请求，不改业务回滚职责。
4. 缺失订阅/Geo 如需先下载，遵守明确的引导许可；没有许可时失败并保留旧状态，不循环等待一个必须靠下载才能建立的代理。
5. 初始化收敛后开放对应请求策略，再启动自动订阅刷新和已有 20 分钟任务。BootGuard 恢复不把跳过自动运行解释成接受 DIRECT 刷新。
6. 普通后台保留已接受的订阅刷新；界面诊断和 ping 生命周期按真实用途关闭。恢复前读取权威变化，再按现有调度重试，不复活旧客户端或应用旧答案。
7. 退出在 SystemExitCoordinator 的清理入口先关闭新请求并取消旧范围，再保存/关闭现有资源；不新建退出流程。

## 原生快照、意图与请求开放契约

此节细化 R1。`ServiceStateMachine` 是原生意图与原因的唯一写入者。`RunIntentArbiter.Token` 扩展为同进程内有 ID/版本的不可变 token，仍按对象身份/当前 token 仲裁；`resetToStopped` 不再丢弃产生失败的意图信息。增加一个不可变 `RequestState`，由短的原生 publication 锁保护修改并通过 AtomicReference 一次替换；runState flow 作为该记录的投影，不再并行维护请求原因。

```text
RequestState {
  processEpoch: 进程建立时的随机字符串，重启后改变
  revision: 此 epoch 内每次有效发布严格递增的整数
  intentRevision: 最近被接受的新意图的 revision
  intentRunning: 用户/系统显式要求的运行值，故障不伪装为用户 stop
  paused: 原生已接受的SSID停用值；不丢弃被暂停的运行意图
  serviceId: 当前绑定服务实例身份；无实际服务时为空
  source: ui | tile | notification | alwaysOn | ssid | bootstrap | exit
  phase: stopped | preparing | starting | started | stopping | failed
  reason: none | initializedIdle | userStop | excludedSsid | permissionDenied |
          setupFailed | serviceLost | vpnRevoked | recovery | exiting
}
```

processEpoch/revision 用于所有快照、事件、请求范围和资格检查；intentRevision 标识同一意图的后续阶段。token保存运行要求与paused这一个复合意图，实际服务要求为running且未paused。SSID变化只由ServiceState推进paused，不把用户运行要求改成false；若用户在暂停期间明确stop，则恢复SSID也不自动start，保留userStop原因。失败/服务丢失可以使现有arbiter控制值收敛为stopped，但快照保留原意图source/intentRunning和失败原因。较旧token或较旧serviceId的准备/权限/服务回调不能更新phase/reason。初始stopped/none是尚未核实，不据此允许维护DIRECT；bootstrap完成同意流程、确认无当前服务/恢复/autorun后，以期望revision登记initializedIdle；较新Always-on/start已进入时拒绝这个旧初始化结果。

`getRequestState` 只返回同一个 immutable record，不取 ServiceController 锁、不调用 refresh、不据 runTime 重写 phase。ServicePlugin 附加 engine 后先读该记录再订阅全量快照事件；收到的同 epoch 小于等于当前 revision 的事件丢弃，epoch 变化使所有旧范围失效。重复读和观察只读，不产生新的意图。读/订阅竞态通过订阅后再读一次当前记录收敛，不依赖“每个事件均送达”。

| 实际入口 | 意图/失效先后位置 | 何时允许需要核心的新请求 |
| --- | --- | --- |
| UI start、bootstrap autorun | SetupAction 在下载/配置 setup/权限等待前，经 ServicePlugin `prepareRunIntent` 向 ServiceState 登记；返回原生 token，后续 start 只提交此 token，不再创建第二个意图 | token 仍当前、有效配置 ready 且 native started；乐观 true、Core通道连接、Go listener 先启动均不开放 |
| tile/notification/Always-on | ServiceState 在转交 TileGateway 或 loadPreferencesAndStart/setupCore 之前登记 token；转交事件携带同一 token，Flutter 不改为新 UI 意图 | 同一 token 的 setup 与服务启动都成功；无 engine 时也按此路径 |
| 明确 stop、exit | 原生登记新原因并同步撤销旧 Go 范围后，再调度 stopService/TUN/listener 清理；UI先关闭本地入口是早期资源取消，不能改写原生原因 | 明确stop仅手动维护DIRECT；exiting始终关闭 |
| SSID停用/恢复 | AppStateManager 发送显式 ssid 意图，经同一 ServiceState 入口；不直接调用 Core.start/stopListener 再由 runTime 推断 | 停用仅手动维护DIRECT；恢复原运行要求且等待native/config收敛 |
| 权限/setup失败 | `fail(token, reason)` 在检查当前 token 后发布 failed，保留对应 source | 失败不转换为 DIRECT；下一次有效意图才重新开放 |
| 服务断开 | ServiceController回调先按发布记录的serviceId/token同步调用observeLost，再调度原有锁内清理；不在同步路径等待binding Mutex | 当前意图失败即关闭；迟到旧binding身份不能盖掉新状态 |
| VPN revoke | VpnService.onRevoke的stop() **之前**调用common同步观察入口，携带本实例serviceId/启动token；FlClashApplication在原生初始化时绑定到ServiceState | 当前实例同步vpnRevoked失效，无Flutter也成立；旧实例事件拒绝，后续广播只清理、不新建迟到stop |

common层只定义窄观察接口，service不反向import app；应用注册同步handler，不依赖Activity/Flutter。ServiceController在实际start/bind成功时向ServiceState发布本实例serviceId和启动token，并将它们交给对应ManagedService的实例；revoke/lost只提交自己持有的身份，不在回调时借用“最新token”。未注册/初始化失败时Core请求门保持默认关闭，service的revoke先调用Core同步关闭兜底。onStartCommand的Always-on显式入口也先登记；普通onCreate/onDestroy不自动当作用户start/stop。

原生 publication 在同一短锁内先通过专用 JNI `publishRequestState(epoch, revision, …)` 更新 Go 请求门，再发布 AtomicReference/flow/event。JNI 直接调用 Go 导出函数，**不经过 invokeMethod/普通异步派发，不等待 configMu**。它只更新策略版本、标记并移出失效范围；放开 registry/publication 锁后 cancel context/关闭连接，不持锁执行网络 Close 或回调。状态资格已同步失效，连接释放完成有调度边界，不冒称零延迟关闭。JNI失败则原生发表 failed/关闭入口，不使用旧开放状态。

Go配置owner的generation/phase由实际parse/apply落点发布，独立于上述服务记录；开放条件同时检查native record与配置owner，不把两个来源字段临时拼成可混用token。普通维护要求ready与native started；本次配置Inner初始化provider是单独用途，只在本次有效start/setup意图、该owner的Inner阶段且未paused/失败时允许必要路由，不能借给Dart普通请求/旧provider interval。明确bootstrap许可是另一个对象范围，故障状态不会自行产生该例外。

RouteTracker在Android观察原生记录与核心配置资格，映射到现有hostEpoch/proxied；requestAvailability的blocked/direct/routed表达真实通道资格，proxied只是路由投影。自动维护另检查trigger，停用下即使手动通道为direct也不启动自动刷新。ServiceStatus/OutboundIpProbe不再用乐观!isStart决定DIRECT，blocked不探测，routed保留规则/指定节点；已有诊断/IP用途的触发选择不在此改变。现有Core route epoch/picks/chains仍是route stamp权威。Go收到探测再验证期望native/config版本，通知迟到也不能把新探测当当前DIRECT。

## 提交资格与跨资源失败契约

此节细化 R2。采用**一次资格授予**，没有“native撤销瞬间所有Dart磁盘写入原子停止”的承诺。Go 的请求 registry 是服务/配置资格的授予和撤销执行位置，Dart 的数据修改串行区是文件/DB/偏好修改的执行位置；两者的职责不同。

1. 网络、解析、校验及写入操作独有暂存文件发生在资格授予前，没有写正式文件/DB/偏好。范围取消立即关闭网络，清理暂存。
2. Dart 进入数据修改串行区，核对当前对象/数据集代际，调用 ServicePlugin 的同步 JNI `grantRequestCommit(scopeId, expectedVersion)`。Go 在 registry 短锁内比较原生/配置版本及 scope 状态，置为一次已授予，返回 receipt；这一处是授予与原生撤销的先后点。读快照不授予资格。
3. 撤销先到：拒绝 receipt，正式资源保持原值。授予先到：receipt允许完成**已下载结果的有限本地提交**，后续 stop/失效仍关闭网络，不能重试、跳转或继续 PUT。receipt不授权新联网、重新应用旧Core配置或显示过期诊断。
4. 本地提交期间，新对象登记、编辑/删除/恢复和偏好保存排在同一数据修改串行区之后；网络阶段不占用此区。复用SerialTaskScheduler类建立一个独立共用的数据修改队列，与SetupAction的_setupScheduler/_listenerScheduler分离。该future-tail队列非重入：公开修改入口只入队一次，区内await的persist/saveConfig等leaf直接执行、不再次run此队列；observer/debounce可后续入队，区内不能await排在自身之后的任务。receipt在finally释放，不能二次提交。
5. 新来源的修改完成后再登记新代际；因此一个已获资格的本地提交可先完成，随后编辑/删除生效，不会让旧网络结果在新来源已经提交之后覆盖它。原生撤销不会等待这个队列。源变更排队时可以先取消旧网络；已经获得receipt的本地段按既定顺序结束。

Profiles/Scripts 网络提交不调用原有 void optimistic put 当作完成。为本项增加 awaited persist 入口，正式文件先以同目录暂存/备份替换，DB操作await完成，最后发布网络产出的时间/订阅信息并触发必要应用。对象其余字段在串行区从前序已完成持久化的当前值合并，不从optimistic显示值或下载开始时整个旧模型覆盖label/selectedMap/order。不同来源编辑/删除也经同一修改入口，loading独立。DB失败回退文件并保留/恢复模型；Core应用只在提交结束且运行/config资格仍当前时请求，不通过旧receipt开放网络。

WebDAV恢复在私有workDir完成下载/解析后进入共用数据修改区，等前序正式写入结束，再查询当前目标并取得本次替换文件/偏好的补偿快照；不能用下载开始时P0补偿覆盖已经提交的P1。保留BackupAction._copyStagedFiles目前检查实际正式目标的含义，快照/备份可以在grant前做，正式修改只在grant后开始。在区内用一层DB事务完成记录修改；文件替换及必要awaited saveConfig安排在该事务提交前，失败补偿到此提交前状态。database.restore复用或拆成事务内leaf，区内leaf不再次入同一队列。外层commit及文件/偏好步骤成功后才writeConfig/发布完成，缓存清理不在旧补偿中删新数据。

全量restore的数据集代际只使旧网络登记失效，不代表下载期间每个对象编辑都被检测或禁止。恢复的replace/merge语义按既有restoreStrategy作用于进入修改区时的当前数据；下载期间已提交的本地编辑属于该当前基线，override可由用户选择的恢复覆盖，merge沿现有DB合并行为。补偿回这份当前基线，不能回下载前状态。恢复之后排队的新编辑再生效；实施验证需区分对象冲突和dataset失效，不泛称二者等价。

偏好 debounce/exit保存必须经过同一数据修改入口；恢复中的中间配置不触发并行旧值保存。receipt之后配置发布可能导致请求策略变化，这是本次已获准恢复本地段的结果，新请求等重新收敛，不借旧receipt立即恢复订阅调度。

| 失败/取消时点 | 保留与可声明的结果 |
| --- | --- |
| grant之前，包括await grant被native拒绝 | 正式文件/DB/偏好不修改，无成功状态；暂存删除 |
| grant之后，仅发生生命周期撤销 | 完成本次有限本地段；不再联网，不应用旧出口，不显示该结果为当前诊断。成功意味着本地段已完成，不意味着撤销之后“没有发生任何磁盘写入” |
| 文件替换失败、DB事务失败、偏好保存false/抛错 | 正常错误路径补偿文件/偏好，DB事务回滚，恢复先前模型；失败结果明确返回，不能发成功事件 |
| DB最终commit失败或补偿本身失败 | 尝试补偿已完成本地步骤；仍失败则报告部分提交，保留私有workDir/替换备份，关闭受影响自动请求和自动apply，避免当前finally直接删除恢复材料 |
| 进程在多资源提交期间死亡/断电 | 本项不新增跨文件/SQLite/SharedPreferences的崩溃事务系统，不承诺全有或全无；原子rename只保护单文件，DB事务只保护DB。该限制单独交评，不能写成“旧状态必定完整保留” |

已有普通数据库Stream可在外层DB提交后观察新记录；不承诺DB Stream与偏好provider在同一时钟瞬间发布。契约是成功返回前各步骤已经await，网络元数据没有optimistic提前发布；本项不改变所有UI编辑的显示模型，只收拢会和这些网络结果冲突的持久修改。

## 对象代际与所有入口的接入

此节细化 R3。Request持有内存中的active范围索引，键为`(kind, objectId)`，另有数据集代际和每key单调operation序号。kind包括profile/script/dav/icon/ipQuality/versionCheck/restore；已有对象用稳定ID，首次导入先分配已有snowflake ID，UI未保存也有明确key。来源版本来自该key的已提交变更代际；URL/必要认证/自动用途变化和正式内容替换推进它，不记录完整秘密作为key。来源字段由现有模型持有，不新增持久Schema。

登记发生在任何网络/校验await之前的短数据修改区：捕获数据集代际、key代际和新operation序号，替代并取消同key较旧未获receipt的范围。结束只按自身序号移除，旧finally不能删除新范围。删除保留小的内存tombstone代际到当前session结束，避免同ID复用。网络完成后数据修改区再核对三个值；数据集恢复/清理会使所有旧登记失效。UpdatingKeys可以同时表示多个loading，完全不参与这个比较。

| 入口 | 登记/来源变化落点 |
| --- | --- |
| autoUpdateProfiles、更新全部、手动单项、编辑URL后刷新 | 全部进入ProfilesAction统一更新入口，showLoading只影响显示；URL编辑先提交来源版本，再为新来源登记下载 |
| SetupAction缺失文件恢复 | 调用ProfilesAction的ensureFile/恢复入口，不再直接profile.checkAndUpdateAndCopy；与其它更新共用key/来源代际，提示后的本次DIRECT许可绑定此登记 |
| 首次URL/二维码/app link/粘贴导入 | 分配Profile ID后登记，再取得响应；二维码/链接解析本身不另造请求资格 |
| Profile编辑页本地文件导入、首次文件导入、putProfile/setProfileAndAutoApply/deleteProfile | 经ProfilesAction的本地修改入口推进代际并取消旧网络，再保存/删除；不绕过profile.saveFile在view直接写正式文件 |
| 已有Profile的label/order/selectedMap等独立字段 | 持久写入经同一修改区，与下载元数据合并；仅改变这些非来源字段不重启下载、不用旧整模型回写 |
| Script URL更新、首次URL导入、editor保存、文件导入、删除 | 收拢到ScriptsAction的download/import/save/delete入口；首次URL流程不在view先getText再_handleImport.save；已有脚本来源和内容改写都推进代际 |
| WebDAV设置替换/删除、ping、备份、恢复 | 设置内容代际推进后取消旧范围；ping与备份/恢复用不同kind子key，同一设置来源版本。恢复登记数据集代际；实际applyRestore也检查并在成功后推进数据集代际 |
| 本地备份恢复、StoreAction.handleClear、数据库/配置替换 | 不需要网络receipt，但必须走数据修改区，推进数据集代际并取消所有旧网络；不让本地恢复绕过撤销 |
| 图标/IP质量/版本检查及provider dispose | 使用目标key和所属来源代际，真实用途解除就cancel；旧完成不得keepAlive/缓存或发表成功。选择IP产品来源仍归L1-T08 |

provider/配置观察是安全补充，不能代替入口登记。已有database notifier中相关put/update/delete/setAndReorder/restore的持久动作接入同一数据修改入口，网络结果使用awaited入口，避免绕过动作层的source写入。初始数据库加载设定基准代际，不把每次Stream回显误算成新用户来源变更；只在真实修改入口推进。

## 核心请求范围的有限接口与消费点

此节细化 R4。新增低依赖的`component/requestscope`接入包，只依赖context/net、constant的Dialer等底层类型；不import配置/adapter/resource或FlClash的main。策略实现只在`core/`，安装一次BeginHook；子模块调用方向为config/resource/http/adapter/ntp → requestscope，不能反向依赖core。

```go
// 接口草图，不是本轮已编译的API。
type Owner struct { ID uint64 } // opaque；app session、明确bootstrap或配置构造时绑定
type Spec struct {
    Owner Owner
    Kind, Trigger, Key, URL, Proxy string
    SourceRevision, Operation uint64
}
type Lease interface {
    Context() context.Context
    Dialer() constant.Dialer
    TrackConn(net.Conn) error
    Check() error
    LockCommit(context.Context) (unlock func(), err error)
    GrantCommit() (Receipt, error)
    Close()
}
type Receipt interface { Complete(); Fail(error) }
var BeginHook func(context.Context, Spec) (Lease, error)
```

BeginHook无hook时保留既有public Read/Write/HttpRequest行为；有hook时缺Owner/用途或版本无效返回可识别的request_blocked/request_cancelled。Owner分别是已完成同意/初始化的app session、一次明确bootstrap许可或candidate配置，不要求手动DIRECT必须有已运行配置。Trigger区分manual/automatic/bootstrap；automatic维护在停止/排除SSID下拒绝，bootstrap须匹配该对象/来源/operation许可。URI跳转也检查当前scope；bootstrap只允许同一origin的跳转，不把原许可借给另一接收方，完整认证/TLS整改仍归L1-T04。

HTTP helper新增WithScope(lease)，使用lease.Context/Dialer，TLS/认证留现有实现；Dialer注册实际conn/pipe端，TrackConn发现撤销即关连接并失败，不回退普通拨号。scope接口不读configMu/currentConfig可变字段等待apply，使用包装层已发布owner记录/现有tunnel快照。没有相应scope的有hook调用不能借nil Dialer返回旧fallback。新scope替代同Owner/key的旧未提交scope，子请求继承父operation而不是每页重建代际；service多页面/重试和IP多源不互相误取消。

### 到达规则解析与真实出站

基线inner.HandleTcp和probeDialer只建立pipe，再调用HandleTCPConn；tunnel的真实拨号/重试和规则ResolveIP/rematch使用Background。关闭pipe不证明这些工作停止。因此新增仅供应用请求的可选`HandleAppTCPConn(ctx, conn, metadata, lease)`入口，inner的scoped分支和probe使用它；原C.Tunnel.HandleTCPConn及普通业务流量保留。缺少该能力的有scope调用失败，不回到旧入口。

该入口复用同一handleTCPConn/resolveMetadata/match算法，传入scope上下文和Owner校验，不复制规则匹配。规则解析在现有tunnel.configMux读锁下核对当前安装Owner及scope资格，DIRECT/GLOBAL/SpecialProxy/规则分支均不能读到新配置再替旧scope路由；executor替换前已撤销旧Owner，Inner实际安装点关联新Owner。解析后、每次真实DialContext/重试前再次检查；规则ResolveIP和rematch改用此父context，拨号超时由scope父context派生，不重新Background。配置读锁只沿现有匹配范围使用，不在真实出站拨号/重试期间持有，registry从不反向等待该锁。

实际proxy.DialContext返回的remoteConn在握手/早期数据写入与relay之前TrackConn；若它迟到返回时scope已撤销，立即关闭、无后续握手/relay/重试。scope取消context并关闭实际remoteConn和pipe/inbound两端，进入relay后也受同一范围控制。已进入的拨号是可取消的在途工作，不能承诺撤销前已发字节可收回；必须验证撤销后不重新拨号、不借新Owner继续，并验证迟到conn被关闭，而非只观察HTTP本地端报错。

Dart mixed同样需要真实绑定，不能只force-close HttpClient。由现有私有JNI范围申请返回仅本次操作使用的随机proxy-only凭据；它在Go registry中绑定scope/Owner及原有代理用户语义，发行仍遵守当前本机代理认证条件，内部命名空间不能挤占已配置用户名。它走Dart已支持的Proxy-Authorization，不放Origin Authorization或业务header。listener/http在loopback入站、普通认证之前用可选hook识别/验证内部凭据，绑定HTTP/CONNECT子连接到同一scope，再使用scoped tunnel入口。过期/无效内部凭据即拒绝，认证关闭也不能退成普通请求；普通用户走原流程，内部标识不发表为InUser/日志，原有IN-USER/进程规则语义保留。

HTTP普通转发的newClient、CONNECT和upgrade均传该scope/context并登记实际出站；只认证一次不能让keepalive连接在范围撤销后继续下一请求。proxy-only凭据只到本机proxy，保留既有删除Proxy-Authorization的转发规则和HTTPS内层不附proxy认证的SDK行为。取消/完成删除凭据并关关联连接，不能因请求池存旧凭据转入无scope通道。无hook的普通代理流程不变。Dart明确DIRECT没有mixed内层，仍关闭自己真实socket并遵守原生资格/提交边界；不能据此宣称强制VPN绕过或整个设备出口已证明。

LockCommit为实际目标资源提供跨配置对象共用的修改锁：文件按规范目标路径，Geo按资源，节点记录按真实proxy实例，NTP offset为单个全局目标；不把ownerID拼进锁key而隔离同一路径。等待该锁不持registry，context失效可以取消等待。GrantCommit 在现有 selectMu 内核对相关路由依赖，再进 registry 短锁完成资格授予；选择写入与校验/授予在同一边界线性化。顺序为 selectMu→choiceMu，释放 choiceMu 后取 registry；已持 selectMu 的拨号/刷新调用 locked 版本，不递归加锁。调用者已持 LockCommit/自己的结果锁；不会再递归取同一资源锁。receipt不是持registry的回调。读取/重建同一Geo mmap也用该资源锁的本地读区，避免grant后旧替换与新实例读取并行；不同资源/网络不被这个锁串行。

HTTP消费者先Begin、后HttpRequest。Body.Close关闭HTTP body和本次transport空闲连接，**不释放保存资格**；外层消费者在解析/提交/失败结束后defer Lease.Close。取消关闭tracked连接且context终止；lease有效性不由Body是否已经读完决定。HttpRequest遇错误由调用者接住同一lease，普通失败可在资格仍当前时登记backoff，取消/策略拒绝不把旧对象更新为普通下载失败。

HTTPVehicle增加ScopedRead可选接口，返回不可变的`ReadResult{Bytes, Hash, Status, Headers/ETag候选, Lease, Error}`；每次读取有自己的Lease，304也有独立结果。P.Vehicle原接口保持兼容，File/inline/bundle的本地路径保持；FlClash有hook的HTTP消费走ScopedRead并拒绝遗留无scope网络写法，不在HTTPVehicle存“最后一次请求”。inRead的subscription-userinfo候选不再在headers到达时写入：HTTPVehicle只保留候选，由Fetcher本次已授权提交调用原callback，更新cachefile与provider字段。

| 实际消费/状态点 | 资格与提交规则 |
| --- | --- |
| HTTPVehicle body/错误/ETag | ScopedRead读取和计算候选，不写ETag/inRead；body释放后结果仍持同一lease |
| Fetcher.Update/loadBuf | loadBufMutex串行解析结果切换，解析/临时文件在grant前；正式Write、inRead、hash、updatedAt、backoff reset及onUpdate在同一receipt本地段内完成。普通失败的AddAttempt也须当前资格；取消不推进backoff/updatedAt |
| 304/same-hash/SideUpdate竞争 | 在loadBufMutex里重新比较当前hash/对象版本，不能用读开始时的oldHash覆盖较新读取；mtime/Chtimes、订阅头/ETag、成功结果也必须grant。SideUpdate本地输入走同一对象修改锁并推进来源代际 |
| provider.Initial/loaded | Initial继承构造时Owner，读取订阅缓存/连接收敛的结果也按其资格；DefaultProviderLoadedHook附Owner/操作结果版本，只有当前owner的已完成Initial可发表成功，不因Initial返回nil就无条件发name |
| Geo初始化 | 隐式parse期间缺失下载返回bootstrap_required，且不先删除可用/错误旧文件。包装层向Dart交所需对象/来源，取得本次明确许可再下载、验证、暂存/替换并重新parse；不把全局“当前在parse”借给其它并行下载 |
| GeoUpdate/304/相同内容 | 读取Lease传到每资源更新函数，验证完再grant；同一资源锁内重新核对当前文件/来源版本。mtime、mmap close、正式替换、reload/cache clear在receipt本地段完成；不关闭Begin时保存的旧reader来误伤新reader，也不在失败时发Geo成功 |
| URLTest | 在Proxy.URLTest入口取得context里的scope或绑定Owner，保持明确节点拨号；defer中的UrlTestHook、alive/history/extra记录移到成功/普通失败的资格段。取消/过代际不写节点不通。现有UrlTestHook只有结果通知，不能控制私有记录，故需这个小guard |
| NTP | Service构造绑定Owner，Exchange使用lease/context并跟踪其实际UDP net.Conn，不能只取消context；SetOffset只在成功receipt内执行。service.Stop取消租约；旧loop defer仅在它仍是offset owner时归零，不清除新service offset。包装层关闭用已有ReCreateNTPService空参数，内部加owner guard |
| Geo/loaded/URLTest结束通知 | receipt的结果带native/config/对象版本；释放修改锁后发通知。释放旧loading/registry bookkeeping可以执行，但旧成功不能修改新scope或刷新当前route |

URLTest 在真实入口登记实际节点、组与 provider 依赖，并在拨号和提交前核对；provider 替换列表/版本与提交检查共用 selectMu，更新自身 mutex 内的数据后放锁，再在原选择锁段通知包装层，后台无前台 route watch 也可撤销旧测速。Fallback 的选择写入仍在 selectMu 内，其返回的网络 probe 在放锁后执行，普通上游 Set 仍同步完成原有测速语义。Geo 单资源结束通知携带原 lease 的 Completion（原 Spec 与 native processEpoch/revision）；批次先登记现有 registry 的父范围，所有资源继承其取消 context，结束通知携带该父范围的原版本，不在通知时读取新身份。子登记在同一 registry 临界区先检查父 context，以及其已有 lease 的原 owner/native 版本、登记/关闭和用途资格；拒绝须早于推进 operation、替换 latest 或关闭较新范围。已撤销但尚未执行 cancel 的父范围也不能借当前 native 状态申请子范围。Geo/geo-batch 的内部操作使用现有 operations map 的独立命名空间保存代际，关闭范围不删除该代际，以识别迟到通知；没有新调度器或状态权威。包装层先在 registry 锁外读取路由依赖和核对来源 URL，再在 selectMu→registry→routeTracker 的短内部临界区核对 Owner、原生版本、来源/操作资格并写 epoch；放开 registry 后才取消连接或发表通知。已 grant 的有限本地段仍可完成，完成通知独立验资格。未安装请求策略（BeginHook 为 nil）时保留原有无条件 Geo 刷新路径。

正式结果提交不包含网络。Go中receipt允许已获资格的有限本地段完成，与Dart相同；配置撤销后已授予的旧文件段按资源修改锁先结束，新资源写入随后执行。重建读取同一资源也使用该资源锁，避免在旧mmap更换期间读取。失败补偿与部分提交明确返回，不把文件写和cachefile/内存记录说成一个事务。

确认 URL 编辑时，在同一 dataMutations 修改区完成持久化并捕获已有 key 的本地取消代际、dataset、client、原生 owner/sourceRevision/operation 和原生 processEpoch/revision 的不可变票据。300ms 延迟回调只消费该次资格；对象缺失、删除、同 ID 同元组恢复或同来源文件替换均淘汰，不在延迟后借新代际；begin 排队后再次核对原生版本，最终原生申请仍携带票据原版本供 ExpectedState 校验。用户停用后新发起的手动操作使用其新接受版本。仅 group/unfold 等局部 UI 字段不推进来源资格；真正首次导入仍走原有新操作。DAV 可见性只取消/重建 ping scope 和运行身份，同一来源的业务 client/PUT/GET 保留；来源替换与 dispose 才完整关闭。

### 配置阶段、异步 Initial 与锁顺序

包装层在取得configMu后创建candidate Owner(ID)，先使旧owner范围失效；解析用新增ParseWithRequestOwner入口把同一个Owner传给proxy/rule provider构造、健康检查和代理测量对象，Config保留该Owner。旧provider内部interval不在运行时捕获“现在的candidate”，所以不会借新许可继续旧URL。

Owner阶段为parsing→inner→ready，或failed/retired。parsing只允许本地读取/构造，Geo引导另取明确许可。executor安装本次proxies/rules、OnInnerLoading和initInnerTcp后用一个可选phase hook发布inner，再派发provider.Initial。这些goroutine和后续pull loop一直持该Owner；loadProvider的限流channel会等待前面任务腾出slot，scope Begin/Grant绝不尝试configMu等待apply结束。executor返回不代表全部Initial完成；inner允许这些本次provider的必要路由/保存，Dart普通维护仍要等待ready与native started。apply成功后发布ready；失败/回滚使candidate failed并显式Close本次构造的providers/NTP，内建默认回滚不得取得旧应用请求资格。较旧Owner回调只释放自身记录。

锁约定：

- configMu → selectMu保持；应用请求解析沿tunnel.configMux读锁→registry短检查，registry永不反向取configMu/selectMu/tunnel.configMux。config替换先失效Owner再安装，真实拨号/重试不持这些配置锁。
- Fetcher loadBufMutex → 目标资源 LockCommit → selectMu → choiceMu/registry 短锁（Grant）；Geo先取该资源LockCommit，不再叠取同key锁。registry释放后才执行文件/mmap/内存切换，网络阶段不持这些提交锁。
- registry撤销只改版本/摘取取消列表；释放锁后Cancel/Close，不能持registry等网络或执行关闭回调。provider.Close/HealthCheck.Close等显式释放放在不会持configMu/selectMu等待commit的落点。
- onUpdate 中的 provider 列表/版本更换在有限本地段内，沿资源锁→selectMu→provider mutex 更新，释放 provider mutex 后在同一选择锁内失效相关范围；没有 selectMu→资源锁的反向等待。其余 rule callback、provider-loaded、Geo 结束通知在释放 loadBufMutex/资源锁后调用，带归属让迟到通知可判定；这些 callback 不取 configMu。
- Native publication/JNI只进registry短锁，不能获取loadBufMutex/资源锁。因此apply持configMu派发Initial、Initial在等待网络时，native revoke仍能立即撤销资格；连接关闭随后释放其slot。

有限修改范围：新增低层requestscope接入；component/http、resource/vehicle+fetcher、geodata/init、updater/update_geo、adapter/adapter+provider构造/健康检查、rules/provider构造、ntp/service、config/config与executor的owner/phase/loaded接入；补inner/tcp、tunnel/tunnel及listener/http的proxy/client/upgrade应用scope分支。策略/私有入站凭据绑定、取消、probe/hub/common/lib和事件结果版本留core包装层。UI updater维持无用途拒绝；仅传递应用scope上下文，不复制DNS/规则算法或改变普通业务流量。JNI/Core/ServicePlugin/ServiceState及Dart真实消费者正常接入/生成；若发现新所有权/接口层越过这些文件族，先交增量设计。

## 核心源码恢复与官方同步契约

此节细化 R5。父仓库保留`core/patches/l1_t03/`的三项正式源码恢复材料：基线manifest、git二进制文本patch，以及新核心提交的原始commit object文本。manifest记录可从项目配置来源取得的base commit、base tree、新tree/gitlink、patch摘要及修改文件blob摘要；commit object文本只含Git提交元数据/消息/parent/tree，不含凭据、日志或编译物。现在不生成这些待实施材料，也不新增第二套源码树。

第一份新核心commit必须直接以这个可取得的公开base为唯一parent，不引用其它未公开parent；若以后必须使用其它未公开祖先，载体必须包含完整所需对象闭包，否则恢复检查失败。空子模块由脚本先初始化其Git目录、按已配置来源取得manifest指定base，再应用材料/重建新gitlink；不能先普通submodule update去请求未公开gitlink。

增加任务用途的恢复脚本，过程为：检查子模块工作区/对象→按`.gitmodules`已配置来源取得base(已存在则离线使用)→在干净隔离临时index/worktree对base应用patch→git write-tree验证新tree和文件blob→git hash-object -t commit -w写入随源码提供的原始commit对象并验证新gitlink→将干净子模块checkout到该对象。Git tree/commit可由材料重建，**不需本机先前私有Git对象**。如commit有签名，保存其完整公开commit bytes，不重新签名；绝不读取签名私钥。脚本有check模式；已有他人修改/冲突/摘要不符则失败并保留，不reset或自动覆盖。

公开base尚不能取得、patch不适用、tree/gitlink不能重建，均是源码恢复失败，不能用本机有对象掩盖。交付的等价检查以全tree/hash为主，修改文件blob为定位依据；独立临时Git对象目录重建一次，不能通过从原仓库copy新commit对象“验证”。该恢复是实际核心差异的载体，不做通用patch插件/升级框架。

标准本地构建：先恢复脚本/check，再按现有setup.dart/Native Assets构建；GoBuilder构建前检查内容，缺材料/源码不符时失败而不是复用旧libclash。除内层fingerprint，还把patch、manifest、commit bytes、恢复脚本及实际采用的来源配置(.gitmodules等)加入BuildReport.inputs，经build.dart聚合到CoreBuilder.run的output.dependencies，缓存命中也返回完整inputs。Native Assets外层runner因此在材料改变/缺失时重跑hook；hook在编译或返回内层缓存旧库之前校验。使用到的本地来源覆盖配置同样是依赖，凭据不进入材料/报告。入口在实施时补入现有android_build_guide与CONTRIBUTING，不把普通recursive初始化写作等效恢复。

当前workflow中带submodules:true/recursive的checkout不能直接取得未推送gitlink。若保留父gitlink方案，相关CI checkout改为先不递归，再执行同一个源码恢复脚本，最后初始化其余子模块；正常静态/Go/桌面/Android步骤复用恢复后的准确源码。只修改必要步骤，不触发CI、不上传任何源码或产物。未实施/未在远端运行的workflow不能标为CI通过。未经这些步骤的普通remote recursive checkout仍不可用，明确保留这个限制；未来使用子模块fork/远端发布仍需单独授权。

同步官方时先更新可取得的base，再把窄patch应用在新base上；冲突由D按官方行为和本项契约解决，M评审受影响接口/行为，再重新生成tree/commit材料、父gitlink和摘要。不得保留失效patch同时仅改gitlink，不选择ours/theirs掩盖生命周期约束。重建新的gitlink对象不重写既有父仓库共享历史，也不推送子模块或父仓库。

## 三态出口的有限增量设计

本节产品需求已确认，三态及R6有限增量设计已获M评审通过，随公共scope/原生/取消/提交接入实施。本项不改节点分组功能，也不添加全局继承层或新的下载RPC框架。

### 模型、迁移与入口

Profile、远程Script和DAVProps各增加requestMode(auto/proxy/direct)及可空requestProxy名称；默认Auto，Proxy未指定名称时明确使用现有GLOBAL组，界面展示该默认及其当前选择，绝不暗选其它节点。用户可改为现有具体节点或可解析的组；来源/配置更换后名称消失保留原设置并失败，不能退DIRECT/另一目标。GLOBAL只是目标组，最终DIRECT同样拒绝。

Profiles/Scripts表各加带Auto默认值的模式列和可空目标列，数据库schemaVersion从10升11，沿已有_addColumnIfMissing兼容降级后列残留；DAO读写/模型JSON同步，旧行及旧JSON缺字段为Auto。未知模式字符串拒绝导入/恢复，不能把未知严格选择吞成Auto；空目标仅在Proxy下解释为已展示的GLOBAL默认。Freezed/JSON/Drift用正常生成。DAV随现有Config JSON持久化，没有独立表或全局新偏好。

订阅URL导入/编辑、远程脚本URL导入/编辑与WebDAV连接编辑在高级区展示模式与条件目标选择；链接/二维码自动填入入口默认Auto，导入前仍可在已有表单展开高级选项，已存在对象保持自己的值。文件对象不使用联网模式，转为远程来源时默认/保留值清楚呈现。脚本保存流程不得在UI直接绕过scope。旧备份数据库迁移及DAV JSON同样得到Auto；新备份自然包含列/字段，恢复按既有merge/override保存，目标缺失报不可用、不自动改模式。模式/目标变化进入同一数据修改区，推进来源策略代际，取消旧scope。

### 实际执行位置

| 模式 | 同一次用途的执行与失败语义 |
| --- | --- |
| Auto | 使用上文真实状态默认：正常运行沿核心规则，可合法DIRECT；明确idle/stop/paused仅手动维护DIRECT，自动刷新暂停；未收敛/故障不默认DIRECT |
| 代理 | 必须有效核心/配置和所选目标；在真实DialContext前展开目标至非DIRECT实际节点并固定该次选择，拒绝DIRECT/兼容直通/Pass/不可证明终端的目标，无直连备用；失效或不支持时失败 |
| 直连 | 由Go实际DIRECT拨号；Android在每个实际socket连接前核验原生网络/保护资格并绑定已核实的非VPN Network，自身VPN还须protect成功；其它VPN、未知、转换中或保护/绑定不可用则失败，不改用规则或Dart备用 |

应用固定 Direct 仅在传入对象严格等于私有 appDirectProxy、范围明确指定 DIRECT 且不为 Strict Proxy 时跳过配置对象身份比较；资格检查、BeforeDial 与原生逐 socket 门仍执行。配置中的同名对象、任意命名 direct 和 COMPATIBLE 不取得该例外。

Strict Proxy复用现有Proxy.Unwrap与节点协议，不复制规则/协议。Selector/URLTest/Fallback/LoadBalance等可展开组按请求metadata取得当时终端，循环/不可展开/实际直通终端在任何目标拨号前失败；组下一次选择不是同scope备用出口。检查实际adapter而非名字：任意命名type:direct和NewCompatible返回的*Direct同样拒绝，嵌套/正则空组的COMPATIBLE fallback也不能拨号。捕获实际非DIRECT节点引用后，每次真实拨号/重试仍检查Owner/路由资格，不能事后用chains兜底。不能证明终端的组/特殊adapter报不支持严格出口，Auto及普通规则组原有DIRECT/空组语义不在本项修改，普通空组fallback风险归Loop2。

固定DIRECT及严格节点复用scope的private proxy-only凭据和真实Go拨号。在Go增加一个仅供本应用、随机端口绑定真实loopback、拒绝所有无有效scope请求的HTTP/CONNECT入口；它不依赖用户业务mixed listener是否已启动。Dart继续用成熟IO adapter/TLS/流式传输，绑定固定实际loopback endpoint，不把数据搬入RPC。Scope发行返回端口/凭据，原有mixed沿规则的入口仍可复用；每进程仅一个私有listener，各scope复用端口并各自跟踪连接，不逐请求创建服务。私有入口不开放LAN/REST，不使用普通trusted黏住逻辑，取消/完成关闭该scope连接，应用退出关闭入口，初始化失败不保留半开放端口。

### Direct 的系统网络核验（R6）

Direct的成功结果要求实际HTTP出站socket走非VPN网络，无法兑现则在连接前失败。`activeTunHandler == nil`只说明没有自身保护句柄，不是无系统VPN的证据；也不把一次较早的非VPN快照作为后续裸拨号许可。这里判断的是系统提供给本进程的网络，不能据此宣称设备或其它应用没有VPN。

| 原生事实 | 本次Direct的连接前处置 |
| --- | --- |
| 默认Network明确有NOT_VPN且无TRANSPORT_VPN，自身VPN没有处于建立/释放阶段 | 固定这个Network及networkRevision；仍须对每个新socket绑定它，不能直接使用进程默认路由 |
| 自身VPN已建立，同一serviceId/保护代际有效，准备权仍属于本应用 | 取得现有网络观察选出的有效非VPN底层Network；匹配当前TunHandler身份，调用该服务protect并绑定该Network，两项成功且版本仍相同才允许connect |
| 默认Network为VPN但不能证明是当前自身实例，包括准备权已撤销、可见ownerUid不匹配 | 不可用；不借可见物理网络绕过其它VPN，不进入目标connect |
| 默认/底层Network为空、能力未知或相互矛盾、被阻止、正在切换，服务/句柄正在建立或释放 | 不可用；等待后续真实状态后由新操作重新登记，旧操作不改出口/网络继续 |

**事实来源与版本。** 将现有`NetworkObserveModule`的非VPN观察、网络优先级和DNS列表采集复用为common层的应用生命周期观察源，由`GlobalState.init`/`FlClashApplication`注册一次；原服务模块订阅这个源继续已有DNS更新，不另保留第二套候选列表或选择算法。这样业务服务停止时手动维护仍可取得事实。仅补`registerDefaultNetworkCallback`观察本进程默认Network，并接收能力、丢失及平台支持的blocked变化；沿现有ACCESS_NETWORK_STATE，不申请新的位置/设备权限，不调用requestNetwork或bindProcessToNetwork。回调用自身参数更新事实，onAvailable只登记待核实，不在回调内同步查询能力替代后续onCapabilitiesChanged。退出注销观察，注册失败保持未知/关闭。

这些只是ServiceState的输入，不产生运行意图。ServiceState沿同一publication入口发布完整RequestState，增量字段为`networkRevision`、默认网络分类/身份、选中非VPN网络身份和`protectGeneration/protectPhase`；真实Network/服务引用只留native，不传到URL、日志或Dart配置。任何有效网络/保护变化先同步撤销Go旧scope，再发表新快照；scope同时绑定原生revision、networkRevision、serviceId和保护代际。原生快照字段不是另一位运行仲裁者。首次没有完整事实时Direct关闭；读快照不改变事实或意图。

**自身服务先后。** 同一serviceId/token在`Builder.establish`之前发表protect starting并失效旧资格；establish返回有效fd、Core.startTun实际成功且同一实例仍当前后才发表ready。stop、revoke、服务丢失及启动失败在关闭fd/移除TunHandler之前发表retiring并撤销scope，旧实例不能清除新实例的保护状态；实际释放完成才清除保护身份并转none，Direct重新开放还须新的默认网络事实已核实为非VPN。保护回调携带这个实例的serviceId/代际，Go的TunHandler同步保存并核对相同身份。VPN准备权核查只读取`VpnService.prepare`结果，不发起权限UI；API30及以上可见VPN ownerUid作为交叉核对，不以API24–29缺此字段允许无身份保护：旧平台仍要求本次有效establish来源、当前准备权和实际protect成功。自身可见lockdown启用时Direct不可用；平台不能证明可用或保护/绑定被系统拒绝时同样失败。

**实际socket门。** 固定DIRECT的Go dialer向现有dialer传入窄的逐socket control，捕获scope和上述版本；TCP的ControlContext与需要实际发送的UDP control均不能丢掉这个绑定。它取代该socket的普通保护分支，复用现有保护回调/错误处理；未携带Direct scope的业务socket仍走原有DefaultSocketHook，静态hook保持一次安装、不清空、不修改原签名。HTTP/CONNECT/upgrade及连接池创建的每个实际出站都进入此门，不能靠Dart PAC或响应后的chains证明。

1. Go在registry短锁内检查scope并取得期望版本，放锁后通过已有Core/JNI通道调用native的窄`prepareRequestSocket`入口；不持registry/configMu锁调用native，避免publication→Go的反向死锁。native先核对当前ServiceState记录和对应Network/服务引用，snapshot不符或未知立即拒绝。
2. 对需要自身保护的socket核对当前TunHandler和服务身份，调用该实例的protect；句柄缺失、false或异常均失败。native用`ParcelFileDescriptor.fromFd`临时复制Go提供的未连接fd，通过选定`Network.bindSocket(FileDescriptor)`绑定非VPN网络，关闭的只是副本，原fd始终由Go所有；绑定异常没有裸拨号备用。
3. protect/绑定不持publication锁等待系统调用。调用后再次核对原生/网络/保护代际、scope和仍有效的非VPNNetwork；任何变化都返回错误，由Go关闭socket。native门之外补一次Go资格检查；只有全部成功才让底层connect继续。新IP尝试/重试逐次执行，不换到新Network继续同一scope。
4. 系统变化可能早于回调送达，不能承诺瞬时获知或收回已发送字节。因此每个socket都显式绑定非VPNNetwork；默认网络随后变成VPN时，已经绑定的socket不会改沿VPN路由，原Network丢失则连接失败，不自动采用新默认网络。收到变化后按已有同步失效和实际资源取消关闭旧socket；不能仅靠观察事件或较早protect结果维持资格。

本契约依据Android官方[protect](https://developer.android.com/reference/android/net/VpnService#protect(int))、[网络能力](https://developer.android.com/reference/android/net/NetworkCapabilities)、[默认网络观察](https://developer.android.com/reference/android/net/ConnectivityManager#registerDefaultNetworkCallback(android.net.ConnectivityManager.NetworkCallback))、[NetworkCallback](https://developer.android.com/reference/android/net/ConnectivityManager.NetworkCallback)及[未连接fd的Network绑定](https://developer.android.com/reference/android/net/Network#bindSocket(java.io.FileDescriptor))。minSdk24覆盖默认网络观察和fd绑定所需API；实际Android厂商/lockdown行为仍需设备核证，不能将文档/替身写成已观察。域名解析沿接受的DNS机制复用，不把该操作的HTTP出口承诺扩成全设备/全部DNS同出口。

出口偏好与触发资格分开：Direct不授权停用/SSID暂停后的自动刷新；自动维护仍等待实际运行/初始化条件，故障也不自动调度。手动显式Direct可以不依赖业务代理节点，但仍需同意/初始化、原生请求范围与可兑现的保护通道。Proxy首次导入确实缺配置/节点时，进入原有本次引导提示，说明对象原设置为代理、当前例外为仅这一次DIRECT；拒绝保持未完成，接受后不修改对象的Proxy设置。普通节点故障不能自动弹许可或回退，用户主动恢复才使用该有限例外。

### 相对公共设计的增量与验证

核心增量限于现有scope Spec/registry的模式、目标、前置终端校验与仅应用loopback入口，复用listener/http/inner/tunnel/实际Dialer；R6补原生网络事实、保护身份和逐socket绑定门，并复用原网络观察/DNS职责。没有新的服务仲裁者/SDK/RPC下载层；源码恢复载体和两层缓存覆盖这些新增文件。模型/DB/DAO、现有高级表单、备份迁移和生成物为必要新增范围，增量获评前不修改它们。

Loopback验证增加：三对象旧JSON/旧DB/旧备份Auto；保存/恢复及模式变化取消旧操作；Auto规则DIRECT合法，Proxy下DIRECT/任意命名direct/COMPATIBLE/嵌套正则空组在目标接收计数零时拒绝，非DIRECT节点/组通过假代理，目标删除/循环/缺失失败；私有入口在业务listener停止时工作，错误/过期/非loopbackscope拒绝。Direct沿真实逐socket control/JNI gate替身核对：明确非VPN的绑定成功、自身VPN保护和绑定都成功才接收；自身保护缺失/拒绝、句柄身份过期、其它VPN/unknown、绑定失败及门前/保护后/绑定后服务或网络版本改变均为目标接收零。默认网络变化不能借旧快照裸拨号，UDP/重试也逐次进入门，取消追到实际socket；同时核对native fd副本释放/Go原fd所有权与publication/registry锁顺序。设备未授权，替身/源码/APK只证明执行位置与失败闭环，不能宣称真实VPN/其它VPN/lockdown实际绕过观察通过。

## 验证安排与真实限制

首轮实施及本轮修订分别完成 loopback 自验与 ARM64 构建，第四轮父子申请边界修订与新 ARM64 绑定已获 M 实现复审通过，当前本地收尾，旧产物不代表修订后版本。实际对象、结果、偏差与未验证范围见[验证记录](l1_t03_result.md)。本节保留获审验证安排，不能据此将未执行矩阵写为通过；原始证据留 `build/verification/l1-t03/` 忽略目录。L1-T02 APK 仅支持既有 SDK 初始化事实，不作本项产物。

本项需要以下行为出口，不能以 PROXY 字符串、编译或代码搜索代替：

| 消费者/场景 | 应取得的证据 |
| --- | --- |
| 订阅/脚本 DIRECT 与核心路由 | 本地合成目标记录实际接收连接，拒绝代理时目标未收到直接备用连接；合法规则 DIRECT/指定节点可用 |
| 初始化/失败/未 attach | 网络能力关闭；自动任务不会抢先请求。带 autorun/原生后台运行的初始状态不误选 DIRECT；缺失数据按获准引导策略运行 |
| 旧池、认证重试、跳转、body 读取 | 策略切换前后连接身份与关闭记录；同一操作不换出口，撤销后不发送后续步骤 |
| 订阅/脚本保存 | 延迟校验、删除/换URL/关闭自动刷新与新操作时核对代际；撤销先于grant拒绝全部正式写入，grant先于撤销只完成有限本地段；文件/DB失败补偿和部分失败分别核对 |
| WebDAV/图标/IP 质量 | ping 替换关闭；PUT/恢复取消不改传新服务，恢复迟到不应用；缓存和 keepAlive 不接受撤销结果，后续波次不启动 |
| Go 探测/核心 provider/Geo | 排队/已连可取消，缺失节点无DIRECT回退；撤销先于grant的结果不写文件、订阅头、ETag、mtime、mmap/成功事件；grant先到的提交与新来源修改严格排序，覆盖内部调度 |
| 规则真实出站与Dart mixed | 卡住旧scope的规则/拨号→撤销→安装新配置→放行旧工作；目标/假代理不接到旧scope新拨号/请求。真实迟到remoteConn关闭，重试不继续；HTTP/CONNECT本机认证绑定和凭据失效都走真实tunnel路径 |
| 恢复与两层构建缓存 | 下载期间P0→本地编辑P1→restore进入区→失败只补偿P1；队列leaf不重入。内/外缓存热态后破坏材料/来源依赖，hook重跑并在旧库返回前失败；空对象目录从公开base重建相同tree/gitlink |
| Android 系统入口 | Quick Settings、Always-on、VPN 拒绝/revoke、服务丢失和 Flutter detach 有同一权威撤销顺序；该项需要真实设备/平台，静态证据不能证明 |

获准范围仅本机loopback合成HTTP目标/假代理和真实请求代码，不启动FlClash、不安装设备、不创建TUN/系统代理、不改变系统网络、不使用真实订阅/节点、不向外部发送测试请求或遥测。实施时采用窄Dart/Go/Kotlin入口，启动前审查测试的socket/DNS/Geo/NTP默认行为，测试目标和假代理随机绑定loopback端口，外部地址在进入真实拨号前拒绝；不能直接跑含未核实外部调用的全套测试。

验证入口计划为：Dart真实Request/adapter与动作的本地文件/SQLite暂存；Go真实registry/http/ScopedRead/Fetcher/Geo本地提交与探测；原生纯JVM的真实ServiceStateMachine配本地host/JNI gate替身。断点控制grant前/后、body后/DB前、较新登记/旧finally、candidate Inner并发Initial、资源锁/registry撤销顺序和源码独立Git对象恢复，保留本地接收计数与资源摘要。JNI/MethodChannel替身只能证明约定调用与状态序列，不能写成真实Android跨线程/系统revoke已验证；APK编译补类型/链接证据。真实Android系统入口仍未获设备运行许可，不能据loopback结果宣称这些全部通过。

## 交评事项与接续

1. 公共能力及三态/R6 有限增量设计均已获 M 评审通过；既有闭合项与有效证据沿用，第四轮 R6-b-parent 申请边界、本地窄回归与新 ARM64 绑定已完成，已获 M 实现评审通过，当前整理/本地集成中。
2. R1–R5对应本Plan的原生快照、提交资格、对象代际、核心有限接口和源码恢复契约；请M复核其可实现性和最小充分范围。
3. 资格先授予后撤销的有限本地段、跨资源补偿/崩溃限制及Dart通知延迟是明确的实现边界，不冒称瞬时全资源原子取消。真实设备系统行为仍未授权，交付如实区分。

IP/扫码的产品选择仍由 L1-T08/09 决定。L1-T03 可以独立交付受控请求边界；原生 SDK 当前没有该通道，保留其初始化事实和剩余风险，并由 L1-T09 验证/处置，不能据本项宣称全应用外发已受控。设计通过后实施，再单独交实现评审，获评通过后本地提交、合入 `security/android` 并删除本任务临时分支；独立聊天、共享目录和必要证据保留。
