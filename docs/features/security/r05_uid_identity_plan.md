# R05 共享 UID 候选上限修复 Plan

任务入口：[R05](android_branch_review_issue.md#r05共享-uid-的不完整候选被当作完整集合)。
输入基线为 `security/android` 的 `20ad3f7`。设计与实现评审通过；本地交付定稿，
R05 由 M 完成交付对账和 Issue 收尾。

## 问题与目标

`UidPackageResolver` 按完整集合产生 ambiguous，却只序列化前 64 个包。
Go 对该合法 DTO 执行共同策略检查，未配置或冲突的第 65 个包因此不可见。
原审查已用真实 resolver JSON 证明错误 App 策略；没有测量设备上出现此规模共享 UID 的频率。

目标是只对可完整表示的身份采用 App／App＋Host 策略，保持 64 项资源上限与正常完整集合的行为。
不提高上限、不选首包，不修改上游 Core gitlink／carrier、R06 模式标签或其它路由优先级。

## 方案与理由

推荐复用现有未知结果：Native 最多收集 65 个去重非空候选，第 65 项即返回
`lookupFailed / unknown / []`；只对完整的 0–64 项排序并生成原状态。
lookupFailed 在此表示无法取得符合当前协议上限的完整身份，也继续涵盖查询异常。
即使实际 65 项策略恰好一致，也不采用 App 策略；Native 不读取策略或猜测省略项。

| Native 结果 | 路由资格 |
| --- | --- |
| 0 项 | notFound；无 App 策略 |
| 1 项 | known；原确定包名策略 |
| 2–64 项完整候选 | ambiguous；所有候选针对当前目标决策一致才采用 |
| 超限、异常或未知 | 不提供部分候选；沿无 App 身份路径 |
| otherUser | 不查询当前用户包名；保持原隔离 |

Go `decodeApplicationIdentity` 已把 lookupFailed 归为无候选的未知身份；系统 UID／method 的真实来源保持。
`resolveApplicationRoute` 不会据此取得 App 策略。Direct 回到 DIRECT；Rule 回到原通用 Host／订阅规则路径，
不是一概直连，也不变更 Global。完整身份的原 App／App＋Host 优先级保持。
预计无需修改 Go 生产逻辑；若实现验证发现缺口，先带证据交接。

无需新增 completeness 字段或 incomplete 状态：目前不要求显示部分候选，未知结果已阻止路由和 UI 推断。
新增标志会增加 Native／Go／Dart 的默认值、展示、聚合及兼容规则，却没有本项必须保留的信息。
DTO 字段、observation version、Dart 模型和 DB schema 均不变，不需代码生成或数据迁移。

缺少 status／userScope、错误类型、非法基数、重复／空候选等继续沿现有解码校验；
notFound 的缺省空 packages 等既有合法输入保持。旧纯包名字符串不恢复为成功。
旧 Native 的截断 ambiguous DTO 与完整 64 项在字节上无法区分；沿既有 Native／Go 必须一起构建交付的契约，
不支持混装旧生产者来推导完整性。旧连接事实不追改，新的身份每条连接重新查询。

Dart 的 packageName 只来自 known；ambiguous 才提供共同设置候选。
lookupFailed 保留 UID 的未知聚合，不能借安装目录升级归属，也不提供 App 策略／VPN 范围操作。
身份观测在本次运行内存中冻结，不进入业务 DB／备份；持久 App 策略仍按 package name 保存，不受影响。

## 实施与验证

1. 获准后先更新当前 [应用网络设计](../network_activity/network_activity_design.md#应用身份)中的身份上限、
   lookupFailed 含义及 App／Host 完整集合前提，标明待实现；完成后更新为实际状态。
   其它入口已有该契约链接，不改历史 Plan 或新增平行规范。
2. 扩展 `UidPackageResolverTest`，覆盖 0／1／64／65 个有效候选、重复／空白不占名额、
   用户隔离、查询异常及实际序列化结果。Native 检测超限后不再排序或发送部分列表。
3. 增加 JVM 测试夹具 producer，由真实 `resolve(...).toJson()` 生成小型
   `core/testdata/uid_package_identity.json`，同时保留受控原输入。它是跨语言回归必需的合成文本夹具，
   不是生产包名或临时日志；Native 测试核对 producer 与入库夹具，Go 测试始终消费该夹具，不新增默认 skip。
   生成命令、源码及 Hash 随验证绑定，不能手写理想 DTO 代替实际输出。
4. 新 Go 专项将当前 Native 产物送入真实 decode／App routing 链；对 64／65 项分别安排末项缺失、
   冲突及全体一致策略，涵盖唯一包和共享完整集合。Direct／Rule 采用不同默认出口，
   以受控本地 TCP 实际通过／拒绝验证模式回退，不能仅用 R06 已知有问题的 observation.mode 当 oracle。
   结构畸形／缺字段另做边界单测，不冒充 Native 端到端输出。
5. 先绑定原生产 resolver 的实际产物与失败，再修复并重新生成产物验证；保留前后源与输出，不覆盖旧证据。
   回归身份／App／Host／观测相关 Go 测试，运行 wrapper 的 `CGO_ENABLED=0 go test .`／vet，
   JDK17 的 service JVM／Kotlin 编译及 Dart 模型、聚合和未知身份组件专项。
   现有 Dart lookupFailed 行为若覆盖不足只补回归，不扩展模型或 UI。

新证据放在本地、未入库的 `.buildlog/r05-uid-identity-20261116/`，复用共享工具链和缓存。
上述测试不证明真实 UID 规模频率、PackageManager 安装态、JNI 调度或设备 VPN；
不操作 APK／设备、Issue、R06、main 或远端。

## 实际结果与复核

生产改动仅在 Native resolver：第 65 个去重非空候选返回既有未知结果，完整 0–64 项保持原状态及排序。
Go／Dart 生产代码、DTO、业务 DB、Core gitlink 与 carrier 均未改变。

| 验证 | 原实现 | 修复后 |
| --- | --- | --- |
| 同一 Native resolver 专项 | 9 项中 2 项失败，均为超限 | 9 项全部通过 |
| service JVM 全部回归 | 未重跑全模块旧基线 | 33 项通过，无失败／错误／跳过；Kotlin 编译通过 |
| 真实 Native JSON → Go decode／routing／本地 TCP | 66 个配置中 48 通过、18 超限失败 | 66 个配置全部通过 |
| Go wrapper 常规测试／vet | 未重跑全部旧基线 | 常规测试通过，638 个 pass／40 个既有条件 skip 事件；vet 通过 |
| Dart 模型／聚合／组件 | 复用既有未知身份路径 | 77 项通过，2 项既有桥接条件跳过，无失败 |

66 个配置包括 Direct、Rule 订阅回退、Rule 通用 Host 回退，各自覆盖 App／App＋Host、
完整 64 项及超限 65 项的全一致、末项缺失／冲突。每项同时检查 TCP／UDP 路由决策，
再由真实 Core TCP 入口访问 localhost echo 或被拒绝；超时不能作为拒绝成功。
未执行真实 UDP 传输或 Global 设备验收；本项未改变这些生产路径。
Go 常规测试的 40 个 skip 事件来自既有 Dart CLI／跨语言输入、显式调查或手工夹具条件；
详细名称与条件见本地 `go-regression.jsonl`，本项三个新增 Go 专项没有 skip。

正式夹具由真实 producer 生成；原／新产物的 SHA256 分别为
`07305dffc03c59e715b416db9ba2cd5c787cc09e4865a6958f6edc30f77750d2` 与
`09853190939a2c93b85dd002722953d1567fd5a24ce00e4fef299c5790f0325b`。
前后 Native／Go 断言源码相同。Go 早期两次夹具准备失败保留为 setup 记录，
最终旧基线为 `go-before-03.log`／`matrix-before-03.json`，不能用早期结果判断产品行为。

从仓库根重生成夹具：`cd android && ./gradlew :service:generateUidPackageIdentityFixture`，
可用 `-PuidIdentityFixtureOutput=<绝对路径>` 另存；随后运行 `:service:testDebugUnitTest`。
Go 在 `core/` 执行 `CGO_ENABLED=0 go test .` 和 `CGO_ENABLED=0 go vet .`，默认读取入库夹具；
专项可用 `go test -count=1 -run '^TestNativeUID' -v .`。

Dart 专项为 `test/models/connection_observation_test.dart`、`test/common/application_activity_test.dart`、
`test/widgets/application_activity_test.dart`。两个跳过项分别需要 Go encoder fixture 与 Android JNI event，
本项未提供这些既有外部输入，没有新增 skip。测试使用本地 runner 临时关闭 setup Go asset hook、
保留 Rust hook 和真实资源，结束后恢复 `pubspec.yaml`；不将它描述为完整 Android 打包验证。
`pub get --offline --enforce-lockfile` 通过，analyze 仅有 42 条既有 info，无 warning／error。
本地、未入库的 `before-final-source.json`、`implementation-source.json`、日志及 XML 位于上述证据目录。
