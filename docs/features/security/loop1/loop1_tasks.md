# Loop 1 可执行任务与验收

本文件将 [Loop 1 计划](loop1_plan.md)拆成单层任务，维护归属、依赖、方案入口和验收证据。当前处于规划待 review，全部任务尚未实施；本次只编写文档，不修改应用、不运行安全测试或重新编译。

本轮 M 为 Codex；D 尚未分派，启动任务时在表内填写具体负责人。产品选择以阶段计划的[建议表](loop1_plan.md#待-review-的产品建议)为准，推荐项尚未等同于已批准决策。方案入口先使用本文件对应章节；确有独立设计需要时再补任务 plan 并更新入口。

## 任务顺序与状态

| ID | 可独立交付的目标 | M / D | 前置依赖 | 方案及验收入口 | 状态 |
| --- | --- | --- | --- | --- | --- |
| L1-T01 | 外发清单完整，产品策略和验收口径确定 | Codex / 待分派 | 无 | [T01](#l1-t01) | 待评审，未实施 |
| L1-T02 | 请求授权和出口在传输边界强制执行 | Codex / 待分派 | T01 | [T02](#l1-t02) | 待评审，未实施 |
| L1-T03 | 移除 Firebase 外发，保持本地崩溃恢复 | Codex / 待分派 | T01 | [T03](#l1-t03) | 待评审，未实施 |
| L1-T04 | 启动、探测和后台调度遵守隐私设置及迁移规则 | Codex / 待分派 | T02 | [T04](#l1-t04) | 待评审，未实施 |
| L1-T05 | 订阅、远程下载和 WebDAV 不泄漏凭据或数据 | Codex / 待分派 | T02、T04 | [T05](#l1-t05) | 待评审，未实施 |
| L1-T06 | 相机和图片扫码离线可用，无 SDK 采集外发 | Codex / 待分派 | T01 | [T06](#l1-t06) | 待评审，未实施 |
| L1-T07 | 请求及错误日志不含敏感凭据与内容 | Codex / 待分派 | T01 | [T07](#l1-t07) | 待评审，未实施 |
| L1-T08 | Android 产物、实际外发和同步回归完成验收 | Codex / 待分派 | T01–T07 | [T08](#l1-t08) | 待评审，未实施 |

建议顺序为 T01 → T02 → T04 → T05，在依赖满足后处理 T03、T06、T07，最后执行 T08。顺序说明不授予创建执行者或并行委派权限。每项任务包含必要实现和定向验证，不把代码与测试拆成相互等待的任务。

## 已核实的源码起点

规划依据为主仓库 `7f80434e6adfd5b2c4f46ee991e39a78474ee451`，应用源码与审计基线 `4b59eca853778d4e7be3de26589252889c899bc5` 一致；Clash.Meta 锁定为 `8597778c7df410ebe88c57e59eaab32d203156df`。实施前按实际集成分支重新核对调用链。

| 入口 | 当前行为与规划依据 |
| --- | --- |
| [main.dart](../../../../lib/main.dart)、[request.dart](../../../../lib/common/request.dart)、[http.dart](../../../../lib/common/http.dart) | 主入口设置全局 HttpOverrides；普通 Dio 也可能继承它。未 attach 的请求及未启动/暂停状态有 DIRECT 分支，代理日志打印完整 URL；不能按 Dio 类型判断真实出口 |
| [bootstrap.dart](../../../../lib/bootstrap.dart)、[application.dart](../../../../lib/application.dart)、[config.dart](../../../../lib/models/config.dart) | 启动时自动刷新订阅、检查更新早于免责声明；后台定时刷新存在，autoCheckUpdate 默认开启 |
| [outbound_ip.dart](../../../../lib/providers/outbound_ip.dart)、[service_probe.dart](../../../../lib/common/service_probe.dart)、[ip_quality.dart](../../../../lib/common/ip_quality.dart)、[IpQualityText](../../../../lib/features/ip_quality/ip_quality_text.dart) | Core 路由未启用时 IP 探测可选择 DIRECT；来源含 HTTP；显示 IP 触发质量查询并向多家服务传入 IP，hideIp 仅遮罩显示 |
| [profile.dart](../../../../lib/models/profile.dart)、[profiles action](../../../../lib/providers/actions/profiles.dart)、[webdav.dart](../../../../lib/common/webdav.dart)、[远程脚本](../../../../lib/views/config/scripts.dart) | 订阅默认允许自动更新；下载共用请求入口，WebDAV 独立创建 Dio，已有同源鉴权保护，仍需核实重定向时 PUT 数据与出口 |
| [app Gradle](../../../../android/app/build.gradle.kts)、[common Gradle](../../../../android/common/build.gradle.kts)、[GlobalState](../../../../android/common/src/main/java/com/follow/clash/common/GlobalState.kt)、[BootGuard](../../../../lib/common/boot_guard.dart) | app/common 均依赖 Analytics/Crashlytics；Crashlytics 与服务共享状态、启动恢复有关。已有构建的合并 manifest 含 Firebase 自动初始化组件，Dart 设置默认 false 不足以证明原生初始化前无采集 |
| [pubspec.yaml](../../../../pubspec.yaml)、[scan.dart](../../../../lib/pages/scan.dart)、[picker.dart](../../../../lib/common/picker.dart) | mobile_scanner 用于相机和图片 QR 扫描；已解析依赖及合并 manifest 引入 ML Kit。厂商说明存在设备、应用和诊断采集，当前版本实际外发待核实 |

SDK 的公开依据：[Firebase 初始化前采集控制](https://firebase.google.com/docs/analytics/android/configure-data-collection)、[ML Kit 数据披露](https://developers.google.com/ml-kit/android-data-disclosure)。厂商说明与本项目实际请求分别核实；目前未证实二维码图片或内容被上传。

## L1-T01

目标：建立完整外发清单，确定阶段计划中的产品选择，使后续实现遵守同一安全边界。

### T01 执行

1. 沿功能到传输扫描 Dart 请求、HttpClient/overrides、Go 包装层探测、原生 SDK/ContentProvider、后台 worker、浏览器调用和插件依赖；覆盖主进程及 VPN/服务进程。
2. 在本节补齐外发清单：功能、接收方或动态目标来源、触发时机、数据/凭据、传输/TLS、路由依据、授权、取消/重试、后台行为、源码/版本和未知项。包括 IP/质量/服务探测、更新、订阅/自定义 provider、远程脚本、WebDAV、Geo 下载及 SDK；业务流量/规则/DNS记录跨 loop 接口。
3. 核对 release 合并 manifest、依赖树、SDK 文档和已有产物；确认是否绕过 Dart、由系统服务代发或在 UI 前初始化，区分模型下载与采集上传。
4. review 产品建议，确定默认值、迁移、授权粒度/有效期、严格代理要求及显式直连例外，回写阶段计划；未知采集/出口列出补证方法与归属。

### T01 验收出口

- 每个网络入口对应清单或明确的后续 loop；抽查冷启动、后台调度、刷新、IP详情、扫码、恢复备份，无孤立客户端。
- 核心未就绪、规则 DIRECT、代理组 DIRECT/fallback、VPN状态变化均有确定的阻止或授权语义，区分接入核心与最终出口。
- 新旧数据策略、SDK 去留及兼容影响已确定，T02–T07 不必猜测产品选择。
- 清单与策略可独立评审；设备观察项保留待验证，不宣称已经完成流量审计。

## L1-T02

目标：每条应用外部请求在连接前强制检查用途、目标、授权和出口，代理失败不静默直连。

### T02 执行

1. 在现有 Request/HTTP 和 Core 请求边界设计窄改动，给用途明确策略；处理独立 Dio、重定向、重试的绕过路径。内部通信限定自有目标/端口，不把任意 localhost 或动态跳转当作授权。
2. 对缺少 reader/隐私状态、启动未完成、核心故障、暂停、SSID 排除、代理不可达拒绝/等待；直连例外仅对允许用途、目标和有效期生效，后台/重试不扩权。
3. 验证最终节点/组的 DIRECT/fallback，不能只返回 localhost PROXY 字符串。需要 Core 支持时在现有路由/拨号边界窄扩展；小响应探测 API 不直接承担订阅下载。
4. 保持 ServiceState 为服务状态权威，复用路由 epoch/最新意图。授权撤销或路由失效时取消请求、关闭可复用连接、丢弃迟到结果，明确连接与状态切换竞态。
5. 外部请求强制证书/主机名校验；重定向重新检查 scheme/origin/出口，拒绝不安全 HTTP 和降级。检查连接前 DNS 行为，HTTP 代理选择不能替代 DNS 保护判断。

### T02 验收出口

- 覆盖 [http_test](../../../../test/common/http_test.dart)、[request_test](../../../../test/common/request_test.dart)及路由测试；用可观察本地传输证明拒绝时无直连连接/敏感字节。
- 核心失败/停止/重启、代理组切 DIRECT、VPN 撤销、SSID 排除、取消竞态符合策略；旧连接、重试、重定向不绕过检查。
- 无效证书/主机名、HTTP 降级拒绝；显式直连的成功与作用域均可验证。
- 明确公共 overrides 对内部通信的影响，保持原有生命周期所有权。

## L1-T03

目标：移除 Android Firebase Analytics/Crashlytics 的外发与自动初始化，保持本地崩溃恢复。

### T03 执行

1. 清理 app/common 依赖、版本目录、Google Services/Crashlytics 插件配置；追踪 installations/sessions/transport 等传递依赖，区分仍被扫码 SDK 使用的部分。
2. 处理 GlobalState、ServiceStateHost、Dart MethodChannel/BootGuard、设置和共享状态中的 Firebase 调用；保留 BootRecord 与 ApplicationExitInfo，明确 API 24–29 的本地恢复降级。
3. 兼容读取旧 crashlytics 设置，避免升级/恢复/服务启动重新启用 SDK；同步隐私披露及本地诊断入口，按仓库流程生成受影响模型/本地化文件。
4. 清理发布 workflow 的 Firebase 配置注入和 mapping/symbol 上传依赖，保持正常 APK 构建；不修改远程项目、secrets 或其它外部状态。

### T03 验收出口

- release 依赖树、合并 manifest 和 APK 无 Analytics/Crashlytics 采集实现、初始化和广告标识权限残留；T06 后再核对共同依赖。
- 新安装、旧 crashlytics=true 升级/恢复、主/服务进程启动、崩溃后重启无 Firebase 外发尝试。
- [boot_guard_test](../../../../test/common/boot_guard_test.dart)、[boot_record_test](../../../../test/common/boot_record_test.dart)、[ServiceStateMachineTest](../../../../android/tests/app/ServiceStateMachineTest.kt)验证本地恢复与服务，旧配置可读。
- 本机构建无需 Firebase 配置或上传任务，原始配置/日志/符号不外传。

## L1-T04

目标：启动、探测和后台调度遵守用途授权，用户关闭或撤销后停止外发。

### T04 执行

1. 在现有设置/迁移入口保存授权，区分单次操作与持续后台允许，绑定接收方/用途/出口；旧默认 true 和恢复备份不自动取得新授权。
2. 调整 bootstrap，先加载/迁移隐私状态和必要披露，再调度请求；覆盖 Application 定时器、更新查询及通知/服务启动。
3. 为仪表盘 IP、质量、节点/服务探测及详情页明确触发和停用，限制并发/重试并减少接收方，采用 HTTPS；渲染/provider 订阅不自动取得权限。
4. 关闭设置、退出详情、后台切换、路由变化时取消任务并处理旧结果；复用 RoutedProbe 新鲜度/取消逻辑，说明 hideIp 与外部查询开关各自语义。
5. 覆盖新安装、升级、恢复、设置保存失败及未知版本，保守处理外发，保留订阅/节点/编辑数据；同步 UI 和本地化。

### T04 验收出口

- 免责声明未处理/拒绝、未授权冷启动/仪表盘、旧 autoCheckUpdate/autoUpdate=true 不发送可选请求。
- 主动操作只触发允许服务/数据，撤销后 provider 重建、定时器、后台恢复和重试不能重启请求。
- [migration_test](../../../../test/common/migration_test.dart)、[ip_quality_test](../../../../test/providers/ip_quality_test.dart)、[routed_probe_test](../../../../test/providers/routed_probe_test.dart)、[network_detection_test](../../../../test/views/dashboard/network_detection_test.dart)及启动/调度夹具覆盖默认、迁移与取消。
- UI 区分未允许、代理不可用、传输失败、有效结果；迁移失败不误开外发或清空配置。

## L1-T05

目标：订阅/远程文件与 WebDAV 在授权下完成，失败和跳转不泄漏凭据或备份体。

### T05 执行

1. Profile.update、远程脚本、自定义 provider 应用侧下载、更新查询、DAVTransport 及清单中下载接入 T02；Core provider/Geo 自主下载边界明确交接对应 loop。
2. 一致处理 URL scheme、userinfo、目标域、TLS、重定向；保留 WebDAV 同源鉴权保护，补齐跨 origin 的 PUT/body、Cookie、Authorization、URL token 转发限制。
3. 合法同源跳转保留兼容性，跨源重新检查接收方和授权，拒绝 HTTPS→HTTP；有限重试/超时不能直连或重新发送给未允许目标。
4. 拒绝、取消、TLS失败或下载失败时保留原订阅文件、元数据和更新时间；错误可辨识，不以失败页/半包覆盖配置，WebDAV 未获准时不发送备份体。

### T05 验收出口

- 本地 HTTPS 夹具覆盖成功、401/403、超时、同/跨源跳转、降级、证书错误、取消、路由失效；接收端检查实际 header/path/body，使用合成凭据。
- 未授权方无 token、Basic/Digest、Cookie、备份体，合法订阅/WebDAV 流程仍可用。
- [webdav_test](../../../../test/common/webdav_test.dart)、[profile_save_test](../../../../test/models/profile_save_test.dart)、[backup_action_test](../../../../test/providers/backup_action_test.dart)和请求测试覆盖数据保持。
- Core 下载未闭合项明确到 Loop 2/6，并提供接续条件，不据此宣称整个核心无外发风险。

## L1-T06

目标：相机和图片二维码识别离线可用，避免遗漏 ML Kit 等 SDK 的采集。

### T06 执行

1. 核实锁定 mobile_scanner/ML Kit 的采集、初始化、模型安装、GMS 代发与关闭能力；比较无网络采集的可审查源码离线实现，随包模型不足以证明无遥测。
2. 按确定方案实现 [scan.dart](../../../../lib/pages/scan.dart)和 [picker.dart](../../../../lib/common/picker.dart) 的离线 QR 识别；覆盖权限、前后台、图片、旋转、重复结果和资源释放。
3. 移除 Android 扫码路径的 ML Kit/采集/transport/自动初始化残留；新依赖记录官方源码、固定版本/摘要、许可证、构建方式和本轮可达功能，避免来源不明的预编译 SDK。
4. 解码结果保持不可信输入，经现有预览/导入处理，不自动请求订阅 URL。

### T06 验收出口

- 断网、无 Google Play 服务的 Android 中相机与图片 QR 均可用，无首次模型下载需求。
- 合成二维码/文本、拒绝权限、关闭或后台切换后不占相机/发请求，未确认结果不触发下载。
- release 依赖/manifest/APK 无该采集初始化；扫码与图片识别无 SDK 外发尝试，验证实际使用功能与源码对应。
- 无法证明采集受控的候选不通过；保留扫码与隐私要求不能兼得时，带具体差距交用户决定。

## L1-T07

目标：请求、SDK/核心错误及诊断展示保护凭据和内容，同时保留故障信息。

### T07 执行

1. 从 [http.dart](../../../../lib/common/http.dart)完整 URL、[print.dart](../../../../lib/common/print.dart)compactError、Flutter 全局异常、WebDAV/下载错误和核心回传追至日志存储、UI、复制/导出及 logcat。
2. 在最早可控记录边界隐藏 userinfo、query、敏感 path、Authorization/Cookie、代理/WebDAV 密码和请求/响应体；默认保护未知敏感字段，不依赖有限 token 名单。
3. 保留用途、脱敏目标、错误类型/状态码和路由阶段；检查编码、嵌套 URL、堆栈及服务端消息，保留已有 Dio 类型摘要保护。
4. 处理应用请求相关核心消息；业务连接历史及长期保存交 Loop 3，UI 遮罩不能替代日志源头保护。

### T07 验收出口

- 合成唯一 canary 覆盖 userinfo/path/query/header、嵌套/编码、成功/失败/重定向/全局异常；日志、logcat、UI、复制/导出无 canary、配置和备份正文。
- 覆盖非 Dio 错误与服务端消息；错误类型/状态码和来源仍可定位。
- 正式凭据不进入夹具、提交或外部证据。

## L1-T08

目标：验收集成后的 Android 产物与真实请求，形成上游同步后可重复的回归入口。

### T08 执行

1. 按 [Android build guide](../../../development/android_build_guide.md)构建 ARM64 release，记录主/核心提交、锁文件、工具、应用 ID/签名及 APK 摘要；交叉核对依赖树、最终 manifest、DEX/JNI 和 SDK 配置。
2. 在独立 Android 环境用合成订阅/二维码/凭据、本地代理/受控服务执行下表；记录规则/实际出站、核心/VPN/SSID/网络状态、进程和时间，断言与抓包/接收端证据对应。
3. 服务和代理使用 localhost 或 192 开头局域网；公网由测试网关阻断并记录尝试，真实订阅/备份/采集数据不发公开服务。观察系统服务代发并区分 OS 噪声；设备路由/VPN变更及工具操作按当时用户授权安排。
4. 本轮初始化/网络边界覆盖 API 24 和 API 37 条件，注明真机/模拟器及 GMS；完整设备/ABI/业务流量矩阵归 Loop 7。有限时段无流量观察配合源码/产物核对。
5. 保留最小回归入口：默认静默、未就绪、DIRECT/fallback、SDK 重引入、日志 canary、跳转、迁移。用最小故意破坏确认断言能失败并撤销；CI 使用合成数据和可控网络。
6. 按 [同步约定](../../../../CONTRIBUTING.md)保持窄提交/生成范围，记录冲突敏感入口、必跑场景与实质冲突取舍；评审通过后合入 security/android，远端操作依据有效授权。

### 验收场景

每行是验收场景，包含必要状态组合，不作为新的任务层级。

| 场景 | 操作/条件 | 预期观察 | 归属 |
| --- | --- | --- | --- |
| V01 | 冷启动、免责声明未处理/拒绝、默认仪表盘、后台恢复 | 无可选探测、更新/订阅刷新或 SDK 采集尝试 | T03、T04、T06 |
| V02 | 旧 autoUpdate/autoCheckUpdate/crashlytics=true、恢复、迁移失败 | 未确认外发暂停，数据保持，SDK 不重启 | T03、T04 |
| V03 | 允许并触发 IP/质量/服务探测，再关闭/撤销 | 仅允许来源/数据/出口，HTTPS，取消后不重试或显示迟到结果 | T02、T04 |
| V04 | 未 attach、核心未就绪/故障、VPN撤销、SSID排除、端口失效 | 停止/等待，无直连连接或凭据字节 | T02、T05 |
| V05 | 规则 DIRECT、组内 DIRECT/fallback、切节点、单次直连 | 严格代理拒绝 DIRECT，例外仅允许目标/用途/期限 | T02 |
| V06 | HTTP、证书过期/主机名不符、HTTPS 降级 | 拒绝不安全传输，原因准确，原数据保持 | T02、T05 |
| V07 | 同/跨源跳转、WebDAV PUT 跳转、循环、重试 | 合法功能可用，未授权方无凭据/备份体，次数受限 | T05 |
| V08 | URL/header/path、编码/嵌套值、异常消息 canary | 日志/logcat/UI/复制/导出无 canary/正文，可定位错误 | T07 |
| V09 | 主/服务进程、允许联网但阻断采集目标、崩溃重启 | Firebase 采集实现和尝试均无，本地恢复有效 | T03 |
| V10 | 断网/无 GMS、相机/图片扫码、权限拒绝、后台切换 | QR 可用，无下载模型/诊断上传，未确认不请求订阅 | T06 |
| V11 | 刷新中停止核心/撤销、超时/401/403、迟到结果 | 不直连，不覆盖订阅，更新时间准确，无无限重试 | T04、T05 |
| V12 | 上游改初始化/请求/SDK/默认值后回归，故意破坏验证 | 断言能发现边界丢失，冲突解决后关键场景通过 | T08 |

### 验收出口与记录方式

- 区分通过、失败、跳过、未验证，记录条件/计数/限制；缺少覆盖不默认为通过。
- 单元测试、编译成功、某次无外发观察分别说明证明范围；存在 SDK 采集、未授权直连、凭据泄漏或关键未验证路径时，本轮不完成。
- 摘要持续写在本节下方，引用场景 ID/本地路径并绑定受测提交/配置/APK。新运行追加简短摘要，保留旧结论的版本范围，不为每次构建新增 result。
- 日志/抓包/依赖树/manifest/APK 留在忽略的 `.buildlog/security/loop1/`；只提交无敏感摘要及最小夹具，源码变化后补受影响验证。
- 本轮通过后为 Loop 2/6 提供已验证请求边界；全设备流量、DNS、全部三方源码结论仍由所属 loop 完成。

当前验收记录：未执行。当前成果仅为源码核对后的任务规划。
