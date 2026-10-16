# L2-T02-01：静态策略编译与本地消费闭环

本项提供**可独立运行的本地配置编译出口**：一份严格静态策略生成完整 mihomo YAML，再用当前 Core 的真实消费者核对业务与 DNS。M1 已通过 design_v2 和 implementation_v2，I1／I2 闭合；实际结果与本地交付情况见[验证记录](l2_t02_01_result.md)。范围与归属见[子任务清单](l2_t02_tasks.md)，总体语义、残留风险和非目标沿用 [M1 设计](l2_t02_plan.md)。

基线：父仓库 `02cb5546d6cf708587bc28ec655a863e3cb947a6`；mihomo `6c6e3e472bb246cc55f2e8577d9eddccc2623afc`。保留 M1 三份文档改动，不修改核心源码、gitlink 或 carrier。M1 通过本设计后实施本项，整个 L2-T02 完成前不推送。

## 1. 用户场景与交付边界

配置维护者准备一份本地策略，通过命令生成可检查的 YAML；同一条域名策略同时决定业务与真实 DNS 的出口。示例：`work.example.test` 经组 A，`lan.example.test` 直连，`blocked.example.test` 拒绝；Core 当前仍仅有地址的目标使用独立 CIDR 表，两个分支均有显式默认。

本项选择“静态编译器＋可用本地命令”作为最小成果。它能独立生成实际消费的配置并验证关键机制，后续直接复用同一编译器。把全部 UI、DB、订阅和运行状态一并塞入首项会扩大尚未证明的边界；只做无人调用的模型／空 API 则没有可验收出口。

| 本项交付 | 尚未交付 |
| --- | --- |
| 严格策略模型、确定性编译、完整配置输出、本地命令 | 常规 profile 启用入口、页面、DB／备份迁移 |
| 当前 Core 真正应用生成配置；本地业务／DNS 独立收件 | 常规 setup 捕获策略、来源撤销、受管运行状态 |
| 固定节点与封闭 DNS 配置、明确拒绝不支持输入 | 真实订阅导入、动态 provider、Geo 资产、自动刷新 |
| 本地 TCP／UDP 反例及 TLS 身份校验 | Android 设备／TUN／系统代理／物理网络证明 |

不添加“已受管”开关或提前改变普通 profile 行为。结果必须注明仅本地编译入口可用，普通应用链尚未消费策略；不把该项完成记作受管上网已经交付。

## 2. 输入契约与首项支持范围

本地命令读取 UTF-8 JSON，通过应用侧严格模型解析。根对象包含 schemaVersion、domainRules、domainDefault、ipRules、ipDefault、dnsServices、bootstrapDns、proxies、groups、listeners。字段版本为 1；必需字段缺失、额外字段、错误类型和未知枚举均拒绝，不调用现有 Rule.parse／DNS 容错构造器猜测含义。

策略用有序列表；条目、服务、节点和组各有唯一稳定 ID。ID 为 1–64 个 ASCII 字符，限字母开头及字母／数字／下划线／短横线，不接受逗号、括号、片段或核心保留目标。显示名称不参与配置引用；核心名称由生成命名空间与 ID 构成，规则及 DNS 引用同一映射。实际字段和枚举以[严格模型](../../../../lib/models/managed_policy.dart)及[最小合成输入](../../../../test/fixtures/managed_profile/policy.json)为准；域名大小写、CIDR 网络位按等价语义规范化。

| 对象 | 首项接受内容 | 严格失败 |
| --- | --- | --- |
| 域名条目 | id、DOMAIN／DOMAIN-SUFFIX、规范 ASCII 域名、target、dnsService | 空值、通配／keyword／regex／Geo／逻辑／IP／进程等条件 |
| 地址条目 | id、IPv4／IPv6 CIDR、target | 非法地址／前缀、源地址规则、混合条件和额外参数 |
| target | DIRECT、REJECT 或带组 ID 的代理目标 | 缺组、裸节点目标、PASS／REMATCH／COMPATIBLE／GLOBAL |
| 两个默认 | domainDefault 显式 target／dnsService；ipDefault 显式 target | 缺失；从首节点或原 MATCH 推断默认 |
| DNS 服务 | 明确 IP endpoint；DoT（tls）或显式本地 UDP／TCP；单个服务一个接收方 | DoH、域名 endpoint、system／DHCP、接口／#RULES、自带 fragment／参数、ECS、TLS 放宽 |
| bootstrapDns | 明确 IP endpoint、DIRECT；本地 UDP／TCP 或 DoT | DoH、隐含公共默认、域名启动依赖、指定不支持出口 |
| 节点 | 固定 SOCKS5、明确 IPv4／IPv6、端口、可选成对认证、显式 UDP 能力 | 未知协议／字段、域名节点、拨号链／接口／特殊 DNS／动态来源 |
| 组 | 非空 select，成员为本模型内的固定代理 ID | 嵌套组、空组、控制目标、provider／自动补成员 |
| 监听 | listeners.mixedPort／dnsPort；地址固定为 127.0.0.1 | 同端口、通配／外部监听、TUN、系统代理、外部控制和其它入站 |

明文 UDP／TCP 服务仅允许 loopback、RFC1918 私网或 IPv6 ULA 地址，并由输入显式选择；私网地址不会自动使其业务条目变成 DIRECT。跨代理访问私网 DNS 仍保留代理出口。公网服务仅允许 DoT，正常校验服务证书；测试不能靠 skip-cert-verify 通过。

**首项拒绝所有 DoH 输入，包括业务服务与 bootstrap。** 当前 [DoH client](../../../../core/Clash.Meta/dns/doh.go) 将问题放入 GET 查询参数，并使用允许默认重定向的 HTTP client；初始 IP 与证书校验不能限制 Location 的新接收方或禁止 HTTPS→HTTP。指定代理也只约束出站，不限制重定向服务身份。本项不新增转发 sidecar、不改核心；拒绝 DoH 不能记作核心重定向问题已修复，后续恢复支持须先评审能约束接收方与协议的实际机制。

首项节点与 DNS 服务均采用真实 IP，因此不支持启动域名依赖；仍要求显式 bootstrapDns，覆盖核心必需 default-nameserver 字段，不沿用内建服务。每条联网域名策略及联网默认必须引用 DNS 服务，编译器把其 target 作为 DNS 出口；REJECT 不允许带联网服务，生成本地 RCODE。地址条目没有目标域名 DNS 选择字段。

空域名／地址列表合法，只使用各自显式默认。无节点时，全部 DIRECT／REJECT 的策略仍合法；引用代理默认／条目时必须存在非空有效组。域名、地址及服务文本严格验证后才进入输出，不能以分隔符拼入另一条规则。

SOCKS5 认证成对提供，单项 UTF-8 长度须为 1–255 字节；拒绝控制文本及 yaml_writer 无法无损表示的内容，生成后 YAML 回读认证值须与输入一致。错误只报告字段位置／类别，不打印值。SOCKS5 本身不提供链路加密，经代理不代表到节点的传输保密。

本项只接受上述新策略，不接受任意旧 YAML、旧规则或未知透传字段。旧 IP REJECT、AND／OR 或进程限制不会被静默删除：带这些输入将被拒绝；自动迁移由 02 处理，不声称已有旧配置保护已经等价保留。

## 3. 生成规则与失败行为

编译器不执行运行时域名匹配，不查询 DNS、不下载材料，也不维护输入资格或运行状态。纯模型经过验证后，一次生成完整配置对象；由保序 YAML 编码器输出。公开调用只接受经过本模块构造／验证的策略，内部可变输入不能在验证之后改变输出含义。

### 3.1 业务与 DNS 同序

每个域名条目生成独立 inline classical provider，内容只有该条目允许的域名谓词。域名子表顺序引用这些 provider，nameserver-policy 以同序 `rule-set:生成ID` 引用同一对象，不能按 ID 排序或改为普通域名键。精确／后缀重叠的首条优先级由 Core 的真实消费者核验。

主规则固定为以下结构，子表和 provider 名称由编译器生成；下例只展示结构，实际测试消费编译器产物：

```yaml
rules:
  - 'SUB-RULE,(DOMAIN-REGEX,^.+$),fc-managed-domain'
  - 'SUB-RULE,(NOT,((DOMAIN-REGEX,^.+$))),fc-managed-ip'
  - MATCH,REJECT
sub-rules:
  fc-managed-domain:
    - RULE-SET,fc-managed-domain-entry1,fc-managed-group-a
    - MATCH,REJECT
  fc-managed-ip:
    - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
    - MATCH,REJECT
```

IP-CIDR／IP-CIDR6 全部带 no-resolve。当前有效 RuleHost 决定分支，不推断原始 URL；域名分支失败不能进入地址表。redir-host 的已有映射可能把原始 literal 请求恢复为 Host，此时按域名策略处理；只有 Core 仍仅有地址时进入 IP 表。即使域名组不支持业务 UDP、核心继续顶层匹配，也应到最终 REJECT；不能落入允许 loopback 直连的地址规则。

DIRECT 和组目标分别生成显式 `#DIRECT` 或 `#生成组名` 的 DNS 服务。缺名称在当前核心可能被解释为接口，因此不接受任意字符串引用；编译前检查组闭包，输出后核对所有生成目标及服务片段。支持 UDP DNS 时，该组每个固定成员必须有 UDP 能力；TCP／DoT DNS 不据此假定业务 UDP 可用。

### 3.2 完整配置所有权

本地出口从严格模型生成完整最小配置，不与旧 raw YAML merge，也没有空 rules 回退。以下内容由编译器确定：

- Rule 模式、两个子表、末条 REJECT、全部生成 provider、固定节点／组；不产生动态 URL、健康探测 URL 或外部控制入口。
- DNS enable、nameserver、nameserver-policy、bootstrap default-nameserver、direct-nameserver 与 follow-policy、proxy-server-nameserver 及空备用字段。默认服务跟随域名默认；默认拒绝使用 `rcode://refused`。
- direct-nameserver 使用明确 bootstrap DIRECT 服务并启用 follow-policy，保留域名条目优先；域名默认也作为最后的有序生成域名 provider 投影，保证 DirectResolver 不把未命中域名隐含送给自己的默认服务。
- 由于节点／服务都是 IP，proxy-server-nameserver 只使用明确 bootstrap DIRECT 服务，不创建隐藏启动接收方；不允许用户附加其它 nameserver-policy／fallback。
- 首项采用 redir-host、关闭 fake-ip、嗅探、系统 hosts、Geo 自动更新、NTP、外部 controller／UI 和其它入站；无用户 hosts／别名。监听只绑定显式 loopback，关闭 LAN、TUN 及系统操作。

最后的 DNS 默认 provider 为生成的纯域名全匹配条件，业务仍保留显式域名 MATCH。它不改变用户条目顺序，只让主 Resolver 与非空 DirectResolver 都明确接受同一个域名默认 DNS；需要用真实 DirectResolver 反例验证，而不是只检查 follow-policy 字段。

尚未支持 fake-ip、hosts、Geo 或节点自带 DNS 不等于已解决其语义，后续扩展须补相应消费者验证。输出前再次检查生成字段、引用和 DNS 顺序，失败不返回部分 YAML；不增加第二套运行时路由器。

## 4. 本地入口与应用代码边界

| 位置 | 职责 |
| --- | --- |
| [严格模型](../../../../lib/models/managed_policy.dart) | 严格版本化模型、输入错误定位及封闭枚举；不改旧 Rule 语义 |
| [配置编译器](../../../../lib/common/managed_profile.dart) | 引用／能力验证，同序业务及 DNS 生成，完整配置不变量检查 |
| [本地命令](../../../../tool/compile_managed_profile.dart) | 读取策略、调用同一编译器、输出 YAML；不自行维护规则逻辑 |
| Dart 契约测试 | 解析、顺序、非法输入、确定性、失败不替换已有输出 |
| Go wrapper 消费测试 | 读取命令真正生成的文件，沿现有 T01 helper 应用；使用现有核心监听和出站 |

新模块保持纯 Dart 依赖，命令不导入 Flutter／全局 common barrel；YAML 复用现有 yaml_writer，不增加新依赖或自制通用编码器。模型所需正常生成按项目规则执行；采用普通不可变类型时不为无用的 builder 增加 Schema。

纯 Dart 模块不表示仓库根命令只需 Dart。根 pubspec 默认启用 setup／rust_api 的 native hook，`dart run`、测试和本机编译须按[项目工具链与 hook 说明](../../../../.agents/commands.md#building)准备 Flutter／Dart、Go、Rust／Cargo 及当前平台的原生编译工具；已有缓存也不能替代工具链前提。本项沿默认 hook 构建／复用正常资产，不改 hook 架构或临时改写 build_assets，不遗留共享 pubspec 修改。实际触发的构建、缓存复用和依赖在结果中记录，不声称命令已避开 native hook。

在仓库根目录，使用与项目一致的工具链运行以下入口；实际执行环境及结果见验证记录：

```bash
flutter pub get
dart run tool/compile_managed_profile.dart --input policy.json --output managed.yaml
```

命令的业务逻辑不启动核心或应用；native hook 可先构建本地原生资产。先完成读取、解析、验证及编码；新建临时目录后，在 macOS 上先清除其 ACL，再设为 0700，随后新建空文件、清除该文件 ACL 并设为 0600。所有步骤成功后才写认证字节，完成后原子替换目标；ACL／权限处理失败时不写秘密内容。只处理本项新建对象，不更改调用者父目录或旧输出的权限。解析、权限、写入、关闭或替换失败均退出非零，保持旧输出完整并清理自身临时文件。诊断不回显节点凭据或整份输入；目标 YAML 只写用户指定的本地路径，不对外发送。

macOS 的继承 ACL 可授予超出 BSD mode 位的访问，因此只检查 0600 不足以证明私有输出；本项采用系统 chmod -N 清除新建对象 ACL，具体依据见 [Apple 文件权限说明](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemDetails/FileSystemDetails.html)。

本地写入入口当前支持 macOS／Linux，使用私有临时目录及受限文件权限；Windows 尚未实现对应 ACL 保障，命令明确拒绝写入。平台实际验证情况见结果，不从纯 Dart 模块推导所有主机均已验证。

常规 `_getProfile`、`makeRealProfileTask`、ConfigInput、UI、数据库及服务控制本项不改。01 的出口为命令生成的完整 YAML；03 将复用编译器拥有的受管配置部分并接入最终合成，同时保留平台监听／安全模式等约束。届时需要调整编译接口时由 03 设计决定，不在首项预建泛化插件或补丁体系。

## 5. 具体自验与独立依据

本节维护验收方法与通过条件，实际执行和未覆盖项见[验证记录](l2_t02_01_result.md)。最小合成策略固定在正式测试夹具；动态端口由本地消费者提供，测试调用真实命令生成被测 YAML，不能在 Go 中手写或重建待测分流／DNS 输出。

| 用例 | 输入／操作 | 独立消费者观察与通过条件 |
| --- | --- | --- |
| C1 顺序 | 宽后缀 A 在前、精确 B 在后；再交换 | 真实业务与 DNS 同时选择首条；A/B 代理和各 DNS 收件独立记录 |
| C2 正常与默认 | DIRECT、A、B、域名未命中、IP CIDR、IP 默认 | 各目标实际收件符合策略；域名不因地址属于 DIRECT CIDR 改换出口 |
| C3 拒绝与空列表 | 域名 REJECT、域名默认 REJECT、IP REJECT、无节点且默认拒绝 | 业务不能到目标，真实 DNS 本地拒绝；其它 DNS／代理均无对应收件 |
| C4 严格输入 | 未知字段／版本、缺默认、重复 ID、空组、坏引用／条件；业务与 bootstrap DoH | 命令非零，有精确位置，保持旧输出；不得恢复默认 DIRECT |
| C5 UDP 分支 | 域名组 TCP-only，DNS 走 TCP，地址表允许目标 IP DIRECT | 真实 SOCKS UDP 域名请求失败，直连 UDP 目标无收件；纯 IP 的显式 DIRECT 正常 |
| C6 DNS 能力／失败 | UDP DNS 配 TCP-only 组；缺服务；接受服务超时或代理不可达 | 前两者编译拒绝；运行失败不增加其它组／DIRECT／备用服务尝试 |
| C7 两个 resolver | DIRECT 命中／未命中；不同 DNS 服务；默认为代理或拒绝 | 真实业务解析及 DNS listener 使用相同有序域名默认，不借 DirectResolver 默认外发 |
| C8 DoT 身份 | 本地 DoT 正确证书；错误主机／不信任证书 | 正常查询经指定出口；身份失败不降级明文或关闭校验 |
| C9 仅地址／确定性 | 无恢复 Host 的地址、相同策略重复编译及改变条目顺序 | 本次仅地址场景无目标 DNS；相同输入输出相同；调序同时改变两端优先级；已有映射再 literal 不在本次证明范围 |
| C10 认证与输出失败 | 认证边界／控制文本及 YAML 回读；继承 ACL、权限／写入／替换失败 | 字节边界准确，无损或拒绝；诊断无值；写秘密前清除 macOS ACL 并限制 mode，IO 失败保持旧输出 |

真实消费者验证采用现有 Go wrapper 测试入口及 `configTestEnvironment`／`writeTestInput`／`applyTestInput`，隔离 Core home 和配置状态。混合代理、DNS listener、A/B SOCKS5、本地 DNS 与业务目标均绑定 loopback 临时端口；每次查询使用独立合成域名，区分新查询与缓存。

为保持产物真实，先按默认 native hook 前提将命令编译到忽略目录。命令如下，从仓库根执行；本地缓存环境和完整命令另见结果关联的记录：

```bash
mkdir -p build/verification/l2-t02/subtask_01/bin
dart compile exe tool/compile_managed_profile.dart -o build/verification/l2-t02/subtask_01/bin/managed_profile_compiler
env FLCLASH_MANAGED_PROFILE_COMPILER="$PWD/build/verification/l2-t02/subtask_01/bin/managed_profile_compiler" CGO_ENABLED=0 go -C core test . -run '^TestManagedProfile' -count=1
```

Go 消费测试通过该显式环境变量取得可执行文件，启动本地服务后写策略并同步调用它，再直接读取其 YAML 经 T01 应用。编译工具实际需要的资产及运行条件随产物保留、记录，并先在同一环境检查命令可执行；不预先宣称单文件可搬运。缺少变量时仅该集成用例清楚标记 skip；交付验收必须带变量实际运行，不能把 skip 记作通过。不创建测试专用生产 API，不在 Core 里实现第二套编译器。

DoT 的合成 CA 只加入该测试进程自己的核心证书池，测试后恢复；不安装系统证书，不放宽生产证书校验。所有服务／子进程按所持句柄退出，禁止杀名称匹配的用户进程。收件记录包含 DNS qname、类型、服务及出口标识，统计重复尝试；失败观察使用有界等待并先核对测试服务确实可达。

必要静态检查为 Dart format、flutter pub get、flutter analyze；按改动运行模型／编译器／CLI 和相关旧契约窄测，Go 消费测试及 wrapper `go vet`。正常代码生成后复核无关差异。首项不改平台 ABI／服务／生成桥接，默认不重复 APK 构建；若实际实现触及该边界，再按影响补必要构建。

原始输出、合成输入和消费配置保存于忽略目录 `build/verification/l2-t02/subtask_01/`，Result 记录可复现命令和实际 SHA 绑定。正式夹具只含 `.test`、loopback 和合成认证，不含真实节点、凭据或流量。

## 6. 失败、复用与完成判据

模型／编译失败只影响当前本地输出，不能触发运行、修改全局配置或撤销用户现有服务。该项没有后台任务、订阅请求或额外状态权威。命令收到终止时最多留下临时文件；原输出保持可辨认完整版本，正常失败路径清理自身临时文件。

既有 T01 的失败保留／关闭由真实消费测试复用，不重做其运行时协议。配置切换后的旧 DNS、Background、缓存／singleflight、远端代理解析及设备物理网络风险仍沿[总体限制](l2_t02_plan.md#10-残留风险与不再承诺的能力)披露；本项不使用新用途／Owner hook 解决它们。

完成需同时满足：命令可独立生成完整配置；C1–C10 的当前支持范围有真实结果；关键反例证明实际未增加不允许接收方；M1 实现评审通过；正常收尾本地提交并合入 `security/android`、清理首项临时分支。未接入能力和未覆盖环境在结果中明确列出。无此实际交付不能仅以静态通过或代码已写完结束任务。
