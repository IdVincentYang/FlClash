# L1-T13 联网用途清单 Result

任务入口：[L1-T13](loop1_tasks.md#l1-t13-增加并核对正式联网用途清单)，方案见 [Plan](l1_t13_plan.md)。
本轮已形成[稳定用途清单](../android_network_inventory.md)，完成源码、初始化/依赖和既有 APK 的交叉核对；
仅修改文档，设计与实现评审均通过，进入本地交付收尾；M 文档收尾/远端交付待完成。
没有据此宣布 Loop 1 或全应用安全完成。

## 实际交付与发现

清单按功能查触发者、执行者、接收方、必要数据、出口和失败行为，区分应用 RequestSession、Core 业务/维护及系统移交。
补入远程图标展示/预取/编辑预览、条件 NTP/控制接口下载、可选协议及原生字体请求，避免仅凭固定 URL 搜索遗漏用途。
Loop 1 plan 的旧 IP 多方 HTTP、Firebase/ML Kit、扫码实施中、只有启动记录等当前描述已同步；审计基线和冻结旧任务未改。
源码、生成、依赖锁、测试及 Core/gitlink/carrier 均未修改，没有重建 APK。

网络根核对记录为 12 个父仓库构造器/拨号候选文件、148 个 Core 文本候选及 14 个补充消费者入口。
已逐类归入用途、共享机制、接口、监听/测试工具或具体运行时缺口；这些是有限发现范围，不是实际接收方数量或全依赖可达性证明。
当前 Android 插件注册根 16 个；实际 releaseRuntimeClasspath 离线解析与最终包同时核对。

新增边界包括：普通请求允许的证书设置/跳转与局部诊断严格规则不同；WebDAV 跨源剥离认证但仍可能重发正文；
EmojiCompat 通过本机提供方查询固定字体而非应用直接 HTTP 下载；REALITY 认证失败会在原连接异步发送带随机 padding 的 GET。
清单分别写已知字段、条件及尚未观察的远端/系统行为，没有把能力存在推定为上传用户数据。

## 实际验证

| 对象与条件 | 结果及证明范围 |
| --- | --- |
| 当前 Go 请求、DNS、站点诊断消费者 | 36 个顶层、55 个子测试通过，0 失败/跳过；本地 HTTP/TLS/DNS、合成代理和权限 seam |
| Dart 作用域 | 26 项通过；真实 Request/提交、bootstrap、DAV 并发/取消、IP TLS、CONNECT、迟到拒绝 |
| WebDAV transport | 3 项通过；脚本化 adapter 核对跨源认证剥离、同源保留与 Digest，非设备实测 |
| 旧独立 dav_client_test | 4 通过、1 断言失败、10 错误；保留首次失败日志，未修无关测试/生产 |
| 离线依赖解析、pub get | 均通过，pub get 使用 offline/enforce-lockfile，锁文件未变 |
| flutter analyze | 0 error、0 warning、42 个既有 info；退出 0 |
| APK/输入 | ZIP、签名、manifest、DEX/R8、10 个 native 库哈希及源输入关系通过；未安装运行 |

Dart 合计为 33 通过、1 失败、10 错误，不能写成整轮通过。独立 DAV 夹具直接构造 DAVClient，
却未 attach/设置当前 Request 的 DAV 来源；
`sourceIsCurrent → isDAVCurrent` 比较空 container 和非空 props，先拒绝请求。
ping 将拒绝转为 false；其它异常的字符串化又触发未加载 AppLocalizations 的断言，形成错误/中断。
生产及这批测试相对 `6aff7f3` 无差异，定位的是现存夹具与当前资格不匹配；不是已证明真实 Android DAV 失败。
已正确装配来源的 request_scope 用例中，真实 DAV IO、隐藏/恢复及并发备份/恢复通过。
本项不借修测试扩大生产修改；后续测试维护交 M 归位。T12 扩大回归的 4 项既有失败也未复跑/修复。

IP 复用核对得到 13 份相关生产/测试文件与 T08 冻结来源完全一致，包括 Request、IP 数据解析、providers、RoutedProbe
及 Go IP/probe。
复用仅支持对应受控 IP 消费者结论，不把原 358 项全部重新计为本轮通过，也不替代公共服务实时兼容或真实设备网络验证。
扫码/报告的既有受控证据沿用未变生产、当前实际包和长期契约所限范围；没有再次诱发真实故障、相册/云导出或报告上传。

## 受检对象与复用关系

- 源码起点：`6aff7f3c7d1ce63d5dbd794349309c25153d9117`；任务分支
  `security/l1-t13-network-inventory`。
  Core 为 `6c6e3e472bb246cc55f2e8577d9eddccc2623afc`，干净；Go 检查使用宿主
  `CGO_ENABLED=0`，不是 Android JNI 运行。
- 复用 T12 APK：
  `build/verification/l1-t12/implementation_v2/artifacts/FlClash-0.8.99-android-arm64-v8a.apk`
  SHA-256 `1753d276d13d905f599776734da0627e1a6354a70951981fd15d574afbe007b7`，
  57,311,410 字节。
  com.follow.clash.dev，0.8.99/2026102301，ARM64 release、Debug 签名；
  不是从 T13 HEAD 新编译。
- 原构建前后 1000 份输入一致；当前为 998 份字节相同及两份 locale 的已审 token 等价格式差异。
  本轮独立复核当前字节与冻结 built/final 哈希、原格式证明；未改 T12 冻结绑定。
  mapping SHA-256
  `29ebd006d43ba114fea5c2cb0b805039e487fdb90b4690cc0383fe940d6e470c`，
  10 库均匹配实际 APK。
- 当前依赖、最终 manifest、R8 原始来源和未混淆 DEX 标识均未发现 Firebase/ML Kit/DataTransport 回流，
  ZXing 3.5.4 保留。
  Photo Picker 只移除确切 required metadata，通用 disabled ModuleDependencies
  service/action 保留。
  首次制品检查误设“整个 service 应不存在”的断言，按既有契约和实际 manifest 修正检查后通过，生产未改。
- Emoji2 1.3.0、AndroidX core 1.19.1 的实际缓存 AAR 已记录 SHA 并本地 javap；
  manifest/R8 来源对应初始化链。
  包名/证书是本机提供方信任检查；content query 的固定投影、selection、字体参数与提供方可能的独立 HTTP 下载分开。

## 未覆盖与接续

| 已知边界/未知 | 当前结论与归属 |
| --- | --- |
| 普通 HTTP/TLS、跨源正文、日志 | 未修，T04/T05 暂缓；局部诊断保护不覆盖全部普通请求 |
| 字体提供方 | 应用固定 query/选择与校验链可知；具体提供方、缓存/下载/网络接收方未观察，Loop 3/7 |
| 远程图标 | 当前缓存/资格/失败逻辑已读；淘汰、预取及编辑预览完整运行矩阵未补测，Loop 7 |
| 动态协议/DNS/NTP | 真实网络、可选协议控制/中继/重连和 REALITY 异步分支未逐项运行，Loop 2/4/5/7 |
| UI/Core 下载及控制面 | scoped hook 拒绝无 lease 下载；更新能力未验收，legacy 控制面归 Loop 2/4 |
| 扫码/本地报告/系统移交 | 应用未发现自行上传调用；真实相册/浏览器/SAF 云端、全量存储/权限及设备覆盖归 Loop 3/7 |

L2-T02-04/05、其它 Loop 和发布签名包整体验收继续未完成。未使用真实订阅、凭据、报告或业务数据；
未安装/启动设备应用、改变宿主 TUN/系统代理、发外部测试流量或上传原始材料。

## 复现与证据入口

原始材料均在本地忽略目录，不随仓库上传；精确命令、环境与逐例结果分别见：

- [制品/源码检查](../../../../build/verification/l1-t13/artifact_source_check.json)及其
  [复现脚本](../../../../build/verification/l1-t13/verify_inventory.py)。
- [Go 命令/选集](../../../../build/verification/l1-t13/go_consumers.command.json)、
  [Dart 命令](../../../../build/verification/l1-t13/flutter_consumers.command.json)
  、
  [实际结果摘要](../../../../build/verification/l1-t13/consumer_results.json)。Dart
  helper 仅在测试期间禁用 native build hooks，原文件已恢复。
- [依赖图](../../../../build/verification/l1-t13/dependencies.log)、
  [字体 AAR/命令](../../../../build/verification/l1-t13/font_provider_inspection.json)
  、
  [候选根归属](../../../../build/verification/l1-t13/candidate_coverage.json)、
  [IP 来源复用核对](../../../../build/verification/l1-t13/ip_reuse_check.json)。

文档格式、文件/锚点和变更范围检查随完整交评快照冻结；静态链接与 Markdown lint 不证明设备或系统提供方行为。
