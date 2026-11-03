# L2-T04 业务数据审查结果

**实现评审已通过，交付收尾中，整项未结束。** 本机普通／受管 DIRECT／SOCKS5 的收件与应用消费已核对；
ZeroTier 在给定 controller 配置下生成额外 payload 副本的能力已由纯内存公开 API 验证。
按用户禁用 Android ZeroTier 的决定和已通过的 design_android_v3，父包装层增量已实施，
新增时序矩阵、应用错误消费及 ARM64 构建已完成，implementation_v1 已由 M1 评审通过，进入本地合入与 M 交付收尾。
未修改 Core、依赖源码、gitlink 或 carrier；不宣称全部协议、Android TUN 或整个安装包已安全通过。
行为与逐协议覆盖由[长期说明](../business_data_design.md)统一维护，设计与授权见 [Plan](l2_t04_plan.md)。

## 对象与方法

输入基线为父仓库 `75d31f8e4c7e09be89dd8607304990e7fe79afb5`，Core 为
`6c6e3e472bb246cc55f2e8577d9eddccc2623afc`。原审查使用文档与显式门控诊断：
[Core 本机诊断](../../../../core/business_data_test.go)、
[Dart 消费诊断](../../../../test/manager/business_data_flow_test.dart)、
[ZeroTier 内存诊断](../../../../core/zerotier_data_test.go)。不提供相应环境变量时跳过。新增 `provider_stage_test.go` 在 no_zerotier 构建自动运行，
覆盖真实 ConfigInput／provider／生命周期消费者，独立子进程只使用自有临时目录与 loopback。
实际源文件及输入冻结在下述 source_binding.json，不能仅以 HEAD 代表尚未提交的诊断。

本地证据根为忽略目录 `build/verification/l2-t04/`；文档基线 `document_baseline/` 先于诊断实现建立，
design_v1 的原冻结材料保留。正文、认证、身份、DB／preferences、备份和接收方均为自有合成材料。
未使用真实订阅、用户应用数据或设备，未改系统代理／DNS／TUN，未联系公网或上传材料。

Core 经过实际 ConfigInput 注册、prepare／install／activate 后访问 mixed 本机入站；
受管输入由既有真实 Dart 编译器生成，核对旧制品和四项源码 Hash 后复用，不手写受管 YAML。
socket hook 记录并拒绝其覆盖路径中的非 loopback 拨号，不是系统所有网络调用的监视器。
独立 HTTP／TLS／UDP 接收端核对正文；TLS 分别记录线上密文与端点解密正文。

## 实际结果

完整 Core 运行 `runtime_v6/` 与新增独立 proxy target 断言的 `runtime_v7/` 均退出 0；
v7 的 12 个代理场景各有一条正确 proxy 收件记录，13 个 DIRECT／UDP 取消场景无 proxy 收件。
`tcp.json` 沿用文件名，实际含 TCP、UDP、失败、取消和受管事实。
计数为 24 个正常场景＋1 个 UDP 取消场景；3 个失败场景和 TCP 取消／恢复对象另列。

| 条件／实际消费者 | 数量与观察 | 结论边界 |
| --- | --- | --- |
| 普通 DIRECT／认证 SOCKS5 × sniff off／on × SOCKS／HTTP／CONNECT | 12 个 TCP；POST、业务认证与响应到达预期端点，CONNECT 承载 TLS | TLS wire 不含该组正文／认证 marker；端点解密成功不等于代理解密 |
| 普通 DIRECT／认证 SOCKS5 × sniff off／on | 4 个 UDP；association、封装／解封装及独立 echo 收件一致 | 仅本机 datagram，不覆盖 Android TUN |
| 真实受管输入，DIRECT／固定代理组 | 2 次实际 policyVersion=1 active fact，6 个 TCP＋2 个 UDP | 不推广其它普通协议 |
| 节点认证／目标拨号失败 | 各 1 例，业务 handler 收件 0，客户端 EOF；错误带 metadata | 不是所有失败分支的穷尽 |
| 截断 HTTP／可选 sniff 失败 | 1 例，原目标返回 400，业务 handler 收件 0 | 可选 sniff 失败继续原目标，不要求必须拒绝 |
| TCP Stop／新准入／恢复 | origin 先收请求；Stop 后 held response 送达 0 bytes，新准入 connection refused；新 owner 恢复收件 | 已发送请求不可撤回；不承诺系统回调前瞬时阻断 |
| UDP Stop | origin 先收 datagram；Stop 后释放 echo，客户端超时、0 bytes | 受控时点／单条关联，未穷尽全部生命周期 |
| 原始 Go event／connections／total traffic | 25 个场景；该组正文、Cookie／Authorization、节点密码 marker 未进入这些通道 | 检查原始 envelope，不以 Dart 字段子集代替；不是通用脱敏证明 |
| Service parser→CoreLib→CoreManager→provider→页面 | `consumer_v5/` 消费实际 runtime_v6 JSON，25 条请求、62 条日志；Live connections／Traffic usage／Logs 正常消费 | MethodChannel 和 native 一行转交由测试替换，未执行 JNI／Android 服务 |
| 显式 Export logs | 实际编码／Picker 消费，自有目标接收 7600 bytes，含 metadata，不含该组业务正文／认证 marker | 文件选择器由本地接收端替换，未操作用户文件提供方 |
| 保存与备份 | 新 SQLite 的 10 个用户表读出 0 行；真实 VACUUM／archive 消费者写 config.json、database.sqlite，日志不在 ZIP | 空库不证明所有已有用户数据无秘密；配置／节点认证本就可能在备份 |
| 导出失败 | picker 抛错后留 1 个含 metadata 的临时日志文件 | 既有清理缺口，未修复；不是新增自动上传，也不能称失败后无副本 |

v6 记录 51 次 Core socket-hook 调用，均在允许的 loopback／bind 范围；下面保存检查绑定 v6，Dart v5 同样消费 v6。
逐字节检查自有配置根的 14 个最终文件，以及 Core stdout、显式导出，未发现该组业务正文／认证 marker；
配置仍可合法含合成节点凭据。每文件 Hash 与范围见 `retention_checks.json`，不覆盖其它文件或全部 cache 模式。
配置材料与正文收件证据分别保留，不能把测试证据文件本身误当产品采集。

### ZeroTier 额外接收方

pin 为 `github.com/metacubex/zerotier-go v0.0.0-20260813124750-13fa6f45da5f`。
adapter 可达性和源码事实冻结于 `zerotier_source_v1/`；`zerotier_memory_v3/` 退出 0，
6 个正／对照场景与 3 个无效配置反例均通过，矩阵见[长期落点](../business_data_design.md#zerotier-的额外-payload-接收能力与-android-禁用)。

公开 Node／MemoryStore／有界 WireSender 使用自定义合成 Planet 和四个身份，经真实 HELLO／匹配 OK 建立路径，
再提交签名且已被接受的 controller 配置。发送含明文 UDP marker 的 376-byte IPv4 frame，接收身份独立解码实际 packet。
无副本配置只有原定帧；trace 给额外 target 256 bytes，TEE／WATCH 给整帧或 TEE 指定的 64 bytes 前缀。
三类无效配置均报 invalid packet，网络未就绪，SendFrame 拒绝。
这些反例未执行正例的 peer 握手，只报告输入未被采用，不单凭错误字符串分别归因签名／身份校验。
网络为 public，controller／原 peer／observer 均是自定义 Planet roots；不能推广至任意私有网络或普通 member 权限。

配置、签名输入、setup wire、公开 peer 状态、原始输出及解码结果均保留；
0600 的 synthetic_identities.json 仅含生成的测试身份，供本地独立复核。
`192.0.2.x` 仅为内存路由标签，没有 socket、wireTransport、真实 overlay、Core adapter 实例或 Android 执行，
没有依赖私有字段注入。它证明 pin 的条件能力，不证明用户实际外发或 HTTPS 明文被解密。
该纯内存证据早于 Android 禁用增量；用户后续明确授权禁用，实际边界见下节。不能用 R1 的记录许可结案。

## Android 禁用增量的实际验证

已审源码冻结于 `implementation_v1/source/`；855 项 **Core／harness 构建输入**的 Hash 为
`android_build_v4/production_inputs.json`，交评时逐项匹配。它不是整个 Flutter／Android APK 的全部输入清单。
收尾仅修正文档和补充非显然契约注释；去除 Go 注释后的语法 token 与已审源码一致，复用已审运行和制品证据。
`android_race_v10.log` 运行实际 no_zerotier 工厂与包装层，`go_tagged_suite_v2.log` 为完整 tagged suite；
默认 suite 和 default／tagged vet 见 `go_default_v2.log`、`go_default_vet_v2.log`、`go_tagged_vet_v2.log`。
完整 tagged suite_v2 后只补退休／bootstrap 交错保护及测试，最终增量由 race_v10 覆盖；
inspection fixture 的默认路径另在 go_inspection_default_v2 通过。

| 实际条件 | 观察与出口 |
| --- | --- |
| HTTP Initial 未返回；相同 receipt 并发 install | 安装等待，提前 activate 被拒绝，mixed 握手不能成为业务；释放后两个 install 共享成功并可正常收件 |
| 多个 file／HTTP proxy provider 加迟到 HTTP rule provider | 迟到材料返回前不能 installed；真实成功后 metadata／JSON／rule SideUpdate 可用；真实解析失败则关闭候选 |
| ZeroTier 节点、inline／file／HTTP cache、HTTP 初始材料 | 实际 parser／工厂返回不支持，候选不 installed、不开放业务，不新增 checkpoint；不删除条目或接受部分集合 |
| 动态坏 proxy 材料、原组路由 lease | SideLoad 报错并保留合法集合；同一原 provider 的路由仍被判为当前 |
| provider 显式排除 ZeroTier；有效 HTTP 离线 cache | 原过滤先于工厂；剩余合法节点正常安装。有效缓存可在所声明 HTTP 源不可达时初始化成功 |
| 合成旧格式 checkpoint 的真实 replay 入口 | 重放重新经过工厂并拒绝 ZeroTier；不续期 replay 资格。这是合成历史材料，不是旧设备实测 |
| Initial 失败、Stop、超时、新 registration、来源失效 | 等待者退出，业务保持关闭；旧工作实际释放后新 owner 可正常接受 |
| 已跟踪 socket 的 Close 受控未返回 | Stop 退出但保留原 admission；迟到 bootstrap abandon 不能跳过已退休资源的关闭，后续 install 有界失败直到实际 Close 返回 |
| Apply 在真实 inner PhaseHook 尚未返回 | Stop 仍能退出；新 install 有界失败且不能抢先 Apply；释放原工作后恢复 |
| 原 Initial 的真实 AfterUpdate 回调尚未返回 | Shutdown 的有界等待可失败，但保留 isInit 和关闭 fence；重复关闭共享旧工作，不能重新 Init；真实返回并清理后才能恢复 |
| Go Shutdown／Init 与迟到请求 | 关闭期间 GetIsInit／Init RPC 返回结构化生命周期错误；旧 Init 不能在关闭后自动重建，旧 Shutdown 不清新初始化 |

30 秒是协调等待预算；测试以短预算验证边界，不等于已强制中断任意构造器或 OS 调用。
受控回调的延迟不代表公网故障或设备 API 的退出时长；隔离中的旧工作实际未退出前不计资源已释放。

`runtime_no_zerotier_v1.log` 在本次 tags 下重跑真实本机业务审查（早于最终退休／bootstrap 小修正，该路径不调用 abandon），25 个普通／受管 TCP／UDP 场景及失败／取消检查通过，
仍由独立 origin 与 SOCKS5 proxy 接收方核对目标。旧消费者、保存和 ZeroTier 内存证据按上文绑定保留，不重复运行。
`lifecycle_response_v1.json` 由真实 Go 关闭窗口的 GetIsInit／Init RPC 生成，
`flutter_affected_v1.log` 通过 Service 替身交 CoreLib／CoreAction，验证错误抛出而非走已初始化捷径；
它与受影响 protocol／action 检查共 59 项通过，不冒充 JNI 或 Android service 执行。
`flutter_pub_get_v1.log` 离线解析成功，`flutter_analyze_v2.log` 为 0 error／warning、42 条既有 info；setup_hooks 的 45 项检查在精确文件依赖修订后再次通过（setup_hooks_tests_v2.log）。

生产命令为 `dart setup.dart android --arch arm64 --env dev`，未关闭 build_assets。
`android_build_v4/build.log` 与 `hook.log` 确认真实 Go 重建使用 `with_gvisor,no_zerotier`；
`cache_probe.json` 确认后续同输入 cache hit，855 项 Core／harness 输入包含 build_config.yaml，
同 effective tags 的实际 go list 不含 zerotier-go。旧 fingerprint 与新 fingerprint 不同；外层始终声明精确配置文件依赖。
`config_dependency_probe.json` 用当前 Flutter tools 实际 hooks_runner 的 hash 消费者核对缺失状态与创建／内容／删除／再创建失效，
仅改写自有临时文件；不改仓库配置。`incremental_build.log` 为随后同输入的第二次完整生产构建，退出 0。

本地 APK 为 `android_build_v4/artifacts/FlClash-0.8.99-android-arm64-v8a.apk`，
56,919,894 bytes，SHA256 `33743cbaa769a9c5375a77ca66364f773a76ec287687977e0482dc81decfe3bb`。
ZIP 完整性检查通过；包内与未裁剪 Core 的 Go Build ID 一致，build info 含本次 tags，链接模块不含 zerotier-go。
完整详情见 `android_build_v4/artifact_verification.json`，没有安装、启动设备或 overlay 测试。
Go 测试文件仍直接导入 ZeroTier 依赖用于原审查诊断，因此测试二进制的模块列表不能替代上述生产 APK 证明。

## 失败、调整和复用

新版本不覆盖旧目录，原失败保留：

- Android 初次材料缺少必填 network，未到工厂；补合法合成 network 后才计禁用反例。
  Shutdown 最初使用可正常取消的 HTTP 读取，不能稳定保持 Initial 未返回；改在真实公开 AfterUpdate 回调控制返回。
- race_v1 发现测试恢复全局 hooks 与异步尾部并发，后改独立子进程一次安装真实 registry hooks；
  race_v3／v4 曾缺少 host 上默认不安装的 Android request hooks，不计有效资格验证，race_v5 起已纠正。
  新矩阵随后暴露来源变更没有唤醒、旧失败 CloseProviders 越过协调者，以及初始化 strategy 被路由快照并发读取；均在父包装层修复。
  最终复核还禁止已退休工作进入 bootstrap abandon 快捷路径，原 tracked network Close 必须真正返回。
  rule fixture 最初误用 parser 可接受为空集合的输入；以真实 ErrNoPayload 输入单独隔离失败条件后复验。
- APK 首次构建通过，v2 的二次构建暴露根目录 hook dependency 引发 Gradle implicit dependency。
  先修订 Plan，再改为精确配置文件依赖；v3 被旧生成 depfile 阻挡，备份并删除两个自有旧 depfile 后，v4 与随后同输入增量构建均成功。
  未关闭 Gradle 校验或绕过 Native Assets；失败与生成材料保留。
- tagged suite_v1 的旧 inspection fixture 在 apply 后才发布新 process epoch，按新取消契约退休了该配置。
  将合成初始运行状态移到 apply 前，保留原 matcher／inspect／queued install 断言，suite_v2 通过。
  Dart 新增的多余 import 已删除，analyze_v2 回到 42 条既有 info。

- `runtime_v1` 的 HTTP fixture Host 与 absolute URL 不一致，触发禁用 DNS 下的解析失败，修正目标后通过。
  v2 尾部回调超出 capture，后续在 capture 内 settle／Stop；未以删除输出隐藏失败。
  v3 错将可选 sniff 失败预期为必须拒绝，实际返回 400；改正断言，未改生产行为。
  v4 普通矩阵通过，v5 加真实受管输入，v6 增 UDP Stop，v7 增独立 proxy 目标断言。
  Dart／保存的 v6 证据继续有效：v7 只增加诊断字段和断言，未改变生产代码／消费者 envelope。
- `consumer_v1` 的 widget fake-async 文件读取挂起；记录自有进程后只结束所启 runner，改同步读取／runAsync。
  v2 的标签 Connections 与实际 Live connections 不符，修正 fixture；v3 通过，v4 增真实 DB／备份／失败导出，v5 消费新增 UDP Stop。
  Drift 多 Database 调试提示来自全局 lazy DB 与隔离测试 DB，未打开用户库。
- `zerotier_memory_v1` 接受配置但 peer 路径未认证、wire 为空；补真实公开 HELLO／OK 后 v2 通过，v3 加三反例和完整绑定。
  首次为空不能解释为没有副本能力。
- analyze 初次发现新增的两个多余 import，删除后复查为 0 error／warning、42 条既有 info。
  导入整理未改变 consumer_v5 逻辑／输入，实际运行源另有冻结。

旧受管编译器和四项源码绑定见 `compiler_reuse.json`，未重建或替换。
旧 ARM64 APK 的 1029 项生产输入逐项匹配，大小 57,360,482 bytes，SHA256 为
`77f9a379174a579d282099faaea68cf13e8268d23a89d6f5a2754133e9601075`，核对见 `apk_reuse.json`。
这是禁用前审查的旧制品复用，不是 ZeroTier 新保护的构建或安装证明；增量制品已在上节单独重建与绑定。

## 复现、检查与限制

Core 命令在 `core/`，Flutter 命令在仓库根执行。下列变量须指向新的自有绝对目录及已按 compiler_reuse.json 核对的编译器；
省略编译器不计受管范围，不把跳过写成通过。

```bash
CGO_ENABLED=0 GOTOOLCHAIN=local GOTELEMETRY=off GOPROXY=off \
  FLCLASH_BUSINESS_DATA_EVIDENCE="$review_root" \
  FLCLASH_MANAGED_PROFILE_COMPILER="$verified_compiler" \
  FLCLASH_MANAGED_PROFILE_EVIDENCE="$review_root" \
  go test -run '^TestBusinessDataReview$' -count=1 -v -timeout 75s .

CGO_ENABLED=0 GOTOOLCHAIN=local GOTELEMETRY=off GOPROXY=off \
  FLCLASH_ZEROTIER_DATA_EVIDENCE="$zerotier_review_root" \
  go test -run '^TestZeroTierPayloadReview$' -count=1 -v -timeout 45s .

FLUTTER_SUPPRESS_ANALYTICS=true DART_SUPPRESS_ANALYTICS=true CI=true \
  GOPROXY=off GOTELEMETRY=off FLCLASH_BUSINESS_DATA_JSON="$review_root/tcp.json" \
  FLCLASH_BUSINESS_CONSUMER_EVIDENCE="$consumer_review_root" \
  flutter test --no-pub test/manager/business_data_flow_test.dart --reporter expanded
```

持久 provider 回归与完整 tagged suite 在 `core/` 执行，不需要上述诊断环境变量。
本机需 Go 1.26.4 和已缓存的锁定模块；下列 CGO_ENABLED=0 命令在本次 Darwin ARM64 主机运行，
包含 Go race detector；它不代表 Android native runtime 测试。子进程只建立自有临时目录和 loopback 接收端。

```bash
CGO_ENABLED=0 GOTOOLCHAIN=local GOTELEMETRY=off GOPROXY=off \
  go test -tags=with_gvisor,no_zerotier -count=1 -timeout=100s .

CGO_ENABLED=0 GOTOOLCHAIN=local GOTELEMETRY=off GOPROXY=off \
  go test -race -tags=with_gvisor,no_zerotier \
  -run '^(TestProviderStage|TestZeroTierDisabled)' -count=1 -timeout=120s -v .
```

若要复现 Go 错误到 CoreAction 的跨语言消费，在上述 race 命令上额外设置
`FLCLASH_PROVIDER_LIFECYCLE_RESPONSE` 为自有可写绝对文件路径（父目录须已创建），
Go 的真实 Shutdown 窗口将写入两份 RPC 错误；随后在仓库根使用同一路径运行：

```bash
FLUTTER_SUPPRESS_ANALYTICS=true DART_SUPPRESS_ANALYTICS=true GOTELEMETRY=off \
  FLCLASH_PROVIDER_LIFECYCLE_RESPONSE="$lifecycle_response" \
  flutter test --no-pub test/core/lib_test.dart test/core/protocol_contract_test.dart \
  test/providers/action_test.dart
```

未设置该变量时仅跨语言证据消费用例跳过，持久 Go 时序用例仍运行。
构建遵循[ARM64 构建指南](../../../development/android_build_guide.md)，使用本机工具链和原 build_assets=true 入口；
本地 APK 与完整依赖图来自该实际环境，不把 host race binary 当作 Android 制品。

offline／锁定 pub get、analyze、Go vet、本项默认跳过和协议消费者检查已运行，输出随交评快照绑定。
历史默认 tags 的一次 Android ARM64 `go list -deps -tags=with_gvisor` 因当时 shell 的 module cache 缺 6 个 Linux／Android 依赖，
在 `GOPROXY=off` 下退出 1，该部分列表仍不计通过。本次实际生产构建环境使用自己的已缓存依赖，
`with_gvisor,no_zerotier` 的完整 go list 已退出 0，并与两份 ELF build info 及包内 Core 对账；二者不是同一构建对象。
真实 Android TUN、JNI／系统回调／通知、物理网络、其它协议 runtime、overlay 和依赖的完整审计未完成；
未走读依赖详见长期覆盖表，不以测试数替代边界。
L1-T04 来源身份／跳转、L1-T05 全面日志脱敏仍暂缓；R1 未解决、DNS 安全未通过，不接做其它 Loop。
