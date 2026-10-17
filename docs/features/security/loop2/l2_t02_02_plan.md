# L2-T02-02：Profile 策略草稿、迁移与预览

本项让用户在真实 Profile 页面编辑、保存和恢复一份策略草稿，并用 01 的真实编译器预览生成配置。保存不改变当前运行配置；
本项完成也不表示受管应用已接入。任务范围和归属由[子任务清单](l2_t02_tasks.md#l2-t02-02-profile-策略编辑持久化与迁移)维护。

本文设计已获 M1 通过。实际实现、验证、限制和版本绑定见[本项结果](l2_t02_02_result.md)，当前任务状态由子任务清单维护。
源码基线为父仓库 `12e694c94e94adb197a8637313b735d912b398d9`、Core
`6c6e3e472bb246cc55f2e8577d9eddccc2623afc`；承接 M1 已有三份任务入口改动。
整体目标见[总体设计](l2_t02_plan.md)，封闭策略语义以 [01 设计](l2_t02_01_plan.md)
和[严格模型](../../../../lib/models/managed_policy.dart)为准，本文不另定义一份编译契约。

## 1. 用户场景与交付边界

| 用户操作 | 可观察结果 | 验收出口 |
| --- | --- | --- |
| 从某个 Profile 打开策略草稿 | 域名／IP 条目、两个默认、目标和 DNS 选择可编辑 | 真实菜单、页面及 DB 读写 |
| 添加、删除、排序后保存并重开 | 条目 ID、顺序、选择及未完成内容保留 | 真实 DAO 和重建页面 |
| 从旧配置提取条目 | 显示实际合成顺序、来源和不能迁移的条件 | 生产规则合成与迁移消费者 |
| 预览草稿 | 仅完整且无迁移阻断的策略产生生成 YAML | 实际 01 模型与编译器 |
| 备份并在另一份测试 DB 恢复 | 草稿及敏感材料保真，合并／覆盖含义明确 | 实际备份、解析和恢复事务 |
| 遇到未知版本、冲突或保存失败 | 原内容保留，问题可定位，无默认 DIRECT | UI、持久化及错误路径 |

本项包含结构化编辑、草稿存储、旧材料提取、备份恢复和预览。运行资格、来源撤销、最终 setup／T01 应用及运行控制由 03 接续；动态订阅材料化、Geo、
更多节点和 DNS 协议由 04 接续。本项不增加应用／启用按钮，不修改 Core、gitlink 或 carrier。

## 2. 已核实事实与设计取舍

| 现有位置 | 源码事实 | 本项处理 |
| --- | --- | --- |
| [Profile](../../../../lib/models/profile.dart)、[Profiles DAO](../../../../lib/database/profiles.dart) | 普通编辑和恢复写入完整 Profile；没有策略字段 | 用关联表隔离草稿，保留普通 Profile 写入契约 |
| [Profile action](../../../../lib/providers/actions/profiles.dart) | 普通 Profile 改动可使来源失效或触发当前选择 | 草稿保存使用独立 DAO／action |
| [Overwrite](../../../../lib/views/profiles/overwrite/overwrite.dart) | 退出时调用自动应用 | 草稿从 Profile 菜单进入独立页面 |
| [旧预览](../../../../lib/views/profiles/preview.dart) | 通过 setup 展示传统合成配置，可能执行脚本 | 新增明确命名的生成草稿预览 |
| [setup 数据](../../../../lib/providers/state/profile.dart)、[规则 DAO](../../../../lib/database/rules.dart) | standard、custom、script 的规则来源不同；Profile added 先于 global | 按真实模式和顺序提取，不重新猜规则优先级 |
| [旧合成](../../../../lib/common/task.dart) | custom 空列表回落源规则；added 的 MATCH 可被替换 | 提取现有纯规则组装逻辑，供旧合成和迁移共用 |
| [数据库](../../../../lib/database/database.dart) | schema 11，事务恢复，开启外键，已有带检查的迁移工具 | 升至 12，新建关联表并接入原恢复事务 |
| [备份 action](../../../../lib/providers/actions/backup.dart)、[归档读写](../../../../lib/common/backup.dart) | VACUUM 冻结整库；恢复显式查询模型再写入；ZIP 不加密 | 显式传递草稿，按实际快照确认敏感内容 |
| [Request](../../../../lib/common/request.dart) | mutate 在 Android 可调用 Core lock／complete | 草稿保存直接做 DB 事务，避免引入运行依赖 |

在 Profile 加 nullable JSON 列改动较少，但旧页面持有的 Profile 和完整 upsert 容易覆盖新草稿，
也会把仅保存草稿混入来源变更。独立关联表只增加一个明确的存储对象及 DAO，能复用外键、事务和备份，无需第二套运行状态或通用版本库。独立文件则需要额外处理
DB／文件恢复一致性，本项不采用。

以上是源码调查，不是产品验证结果。拟修改处及消费者均在本文链接的现有模块内，新页面沿用当前 profiles 目录。

## 3. 草稿的存储与版本

### 3.1 一份 Profile 对应一条草稿

新增 `ProfilePolicyDrafts`：`profileId` 为主键，并引用 Profiles.id，删除 Profile 时级联；
`rawContent` 为非空 TEXT。DAO 投影使用简单不可变记录，调试字符串不包含正文。页面按 profileId 读取／观察该表，
未保存编辑归页面所有，DB 是已保存内容的唯一权威。Profile 模型不增加草稿字段，普通元数据编辑、排序、刷新和 overwrite 模式切换不重写关联行。

`rawContent` 存放 JSON envelope：`draftVersion: 1`、部分或完整 `policy`，可选 `labels` 和
`migration`。policy 沿用 01 JSON 形状，labels 只提供稳定资源 ID 的显示名称，不送入严格编译器；migration
保存本次提取的历史材料。没有 persisted ready／accepted／active 字段，验证和迁移问题均从内容重新派生。

- 新草稿没有域名／IP 默认，不隐含 DIRECT；缺必填值和无效引用可保存为未完成草稿。
- 对已知形状允许缺项编辑；未知 envelope／policy 版本、未知字段或不能无损编辑的结构按只读原文保留，不丢字段后回写。
- 非 JSON、结构错误或未来版本在 DB／备份中保持原始字符串；页面显示安全的问题位置和版本，禁止预览。
- 需要替换不可编辑草稿时，用户明确选择重建并确认丢弃旧草稿；不在打开页面、升级或失败时自动清理。
- 不用 Freezed 默认 toString 或异常 source 展示正文；不把 JSON 解析异常、DB 参数和配置文本写入诊断。

### 3.2 迁移和写入契约

schema 11→12 仅建表；已有 Profile、规则及设置保留，不自动创建草稿。沿用 `_createTableIfMissing`，
支持项目已有的版本回退后重复升级场景。schema 版本、draftVersion 和 01 policy schemaVersion 分别解决 DB、编辑
envelope 和编译输入问题，不相互推导接受状态。

保存／删除在单个 DB 事务内核对 Profile 存在，并比较页面载入时的原始字符串 `expectedRaw`（无行用 null）。当前行相同才写入，
完成后返回持久化内容；冲突返回独立结果，保留未保存编辑，提示重新载入，禁止静默覆盖。删除 Profile 后的保存失败，不重建 Profile 或孤儿草稿。

草稿 action 不调用 `putProfile`、request 来源失效、setup、自动应用或 Core RPC。事务写入失败保留原行，
页面保留输入并结束 loading；普通数据库异常转为固定错误类别。删除草稿同样执行比较和确认。DB 异步写入由 action 持有，页面卸载后不更新已释放的
UI。

恢复事务与草稿事务由 SQLite 排序，CAS 只比较当前正文值和关联 Profile 是否存在，不保证检测所有中间操作。先恢复后正文不同或 Profile
已不存在时拒绝；合并保留同值、恢复同值、无行仍无行及同值重建后，比较仍相等且 Profile 存在则允许保存。先保存再恢复时，
由随后明确执行的恢复语义决定最终行。无需新增运行世代或持久化锁。

## 4. 真实编辑入口与状态

### 4.1 页面及资源编辑

在 [Profile 菜单](../../../../lib/views/profiles/profiles.dart)增加“策略草稿”，独立进入编辑页。
域名和 IP 列表支持新增、删除、编辑及排序；行有稳定 ID，重排不改变引用。域名条件限 DOMAIN／DOMAIN-SUFFIX，IP 条件限 01 接受的
CIDR；目标选 DIRECT、REJECT 或静态代理组，DNS 服务按目标要求选择。

两个默认策略分别编辑；非拒绝域名默认和条目需要 DNS，拒绝项不带 DNS。页面明确显示默认 DIRECT 会覆盖未命中域名及其 DNS。
选择所需资源时提供子表单：固定 IP SOCKS5、成对认证、静态 select 组、TLS／TCP／UDP DNS 及 bootstrap；范围和合法性仍由
01 校验，不放宽 DoH、节点 TLS、嵌套组或 provider 能力。

资源使用自动产生且符合 01 约束的稳定 ID；友好名称独立存储。被引用资源不能直接删除，先列出引用位置；不自动替换 DIRECT、首节点或其它 DNS。
认证输入默认遮蔽，可临时显示，但不回显在列表、错误或调试对象中。

预览端口显式可编辑，初始值沿现有 mixed 7890、DNS 1053 的端口习惯；编译器仍固定 loopback 并校验不同端口，不沿用旧
`0.0.0.0` 地址。初始化端口不意味着确认业务默认或启动监听。

### 4.2 草稿状态和离开页面

页面区分未保存修改、已保存草稿、未完成／待迁移和可预览。保存成功显示“已保存草稿，尚未应用”；可预览仅说明本次编辑内容通过校验，不显示已受管、
生效或当前运行安全。打开空草稿、保存和退出均不改变当前 Profile 选择或运行状态。

未保存离开时可继续编辑、放弃或保存；保存失败仍留在页面。载入／迁移／预览的迟到结果以页面内操作序号和当前草稿内容检查，不能覆盖更新的输入；卸载后忽略 UI
更新。编辑和滚动控制器按页面所有权释放。

沿用 UI Work 的 CommonScaffold、AppGlyphs 和 AppShape；表单错误靠近字段，长条目与窄屏可滚动。新增文案进入四份
ARB，沿 Localization 正常生成，不手改生成文件。

## 5. 从旧材料提取条目

### 5.1 捕获保存材料

用户明确选择“从现有配置提取”，先展示这会建立草稿、不能改变当前配置；替换已有草稿需要确认。读取该 Profile 的已保存本地文件和相关 DB 行，
不下载订阅、执行 script、读取真实运行配置或刷新 provider。

捕获直接复用现有 `dataMutations.run` 串行队列和 DB 读事务，与应用内普通写入排序；不经 Request.mutate，不产生 Core
lock／complete 或跨进程 receipt。读取完成且当前页面操作仍有效时才把结果放入未保存编辑状态。使用实际 Profile 路径和 File
只读接口，不调用会创建缺失文件的 `profile.file`。缺文件、解析失败或页面取消时不保存新草稿，迟到结果丢弃。

migration envelope 保留版本化快照：Profile 模式及有关字段、源文件原始字节、相关规则／links／disabled、custom
节点／组／provider 材料和存在的脚本原文；原始字节以 base64 保真。已能确定的有效规则保存有序字符串及来源映射，不能确定的部分标明未知。
快照可能包含凭据，按草稿敏感正文处理。

它只表示当时捕获的本地材料，不是对文件外部并发修改或运行配置的原子证明；后续源变化不自动更新旧快照。03 必须重新捕获、校验实际来源，
不能信任备份中的迁移标记或本项可预览状态。

### 5.2 复用真实组装顺序

从 `common/task.dart` 提取仅处理规则列表和 MATCH 替换的纯函数，旧最终合成与迁移共同调用，保持既有行为。配置合成、脚本执行和 DNS
合并不迁入新 helper。严格迁移 parser 独立检查完整 token，不用宽松 `Rule.parse` 断言陌生输入已被正确理解。

| 保存模式 | 确定规则列表的依据 | 必须展示的区别 |
| --- | --- | --- |
| standard | 本 Profile added、global、源 YAML rules | added／global 按 queryAddedRules 过滤 disabled；前两段按 links 顺序；added 先于源规则 |
| custom 且规则非空 | queryProfileCustomRules 返回的 Profile custom 规则 | 不套用 standard 的 disabled 过滤；不额外叠加 global／added／源 rules |
| custom 且规则为空 | 源 YAML rules | 真实旧合成会回落，不能把空 custom 宣称为拒绝全部 |
| script | 保存脚本与源材料，实际输出未知 | 不执行脚本，不生成“已等价迁移”结论 |

added 的 MATCH target 先使用显式 matchTarget，否则按旧逻辑从源列表末尾逆向找 target 非空的 MATCH；
不能替换时保留原字符串并报问题。来源展示在 helper 组装前保留各段映射，不改变旧行为。该替换只解释旧规则；**两个新默认仍必须由用户明确选择**。

### 5.3 可提取范围与阻断条件

可识别 DOMAIN／DOMAIN-SUFFIX 条目按实际先后提取；受支持的固定 SOCKS5、静态组和 DNS 候选可填入编辑表单，但不从第一节点、
GLOBAL 或旧 MATCH 猜默认。旧 DNS／启动服务必须由用户明确选择，页面说明生成器会接管的字段及保留在快照的旧配置内容。

以下情况保留原始材料和可定位问题，禁止生成可用迁移预览：

- 任何有效目的 IP 条件可能作用于域名连接的已知／解析地址，分表不能证明等价；IP REJECT 尤其不能只改成字面 IP 拒绝后视为已迁移。
- 有效有序列表的非末项出现 MATCH，无法在本项证明其位置能投影成新表末尾默认：保留该行及后续行的位置并阻断迁移，不跳过它而只提取后续域名条目。
- AND／OR、进程、来源、端口、入站、Geo、rule-set、未知条件或未知 token 不能映射到 01 的纯域名／IP 表。
- script 模式、会改变分类的嗅探／别名／特殊配置，以及不能确定实际有效含义的配置或 provider 依赖。
- 目标不存在、组含 DIRECT／嵌套／动态成员、节点或 DNS 字段超出 01 白名单，或材料缺失。

按当前模式的真实消费者确定有效列表，只有确被该消费者排除的行才不参与阻断；standard 的 disabled 过滤仅作用于 queryAddedRules，
不从源 YAML 里删除行。custom 查询不做该过滤，同一 rule ID 另有 disabled link 仍可能有效。所有行及 links
保留在来源材料中。

不裁掉 MATCH 后的行，也不以静态推测宣布它们永不可达：普通代理不支持业务 UDP 时核心可能继续匹配。IP 规则可作为待处理候选展示；中途 MATCH、
IP 或其它快照迁移阻断都不能因删除提取后的行或补齐默认而消失。问题按保存快照和对应模式重算，没有“忽略问题／标记安全”按钮。

用户可明确放弃迁移、确认丢弃该迁移草稿后创建独立新策略；这不表示保留了旧配置的保护。旧 Profile 文件、传统规则和运行配置不随该操作改变。
对支持范围内的提取也只声明已提取条目及明确的新选择，不概括承诺完整旧配置等价。

关键反例：旧顺序 `IP-CIDR,10.0.0.0/8,REJECT` 在域名连接已知目标 IP 时可能先拒绝，随后 DOMAIN 允许并不能覆盖它。
新域名分支若直接允许，会失去原拒绝；即使旧 IP 规则有 no-resolve，也不能证明安全搬到纯 IP 分支。

中途默认反例：`MATCH,REJECT` 后跟 `DOMAIN,secret.test,DIRECT`，旧列表先拒绝；跳过前行而提取后行，即使新两个默认都选
REJECT 也会放行。拟验收要求保留两个位置并持续阻断预览。

模式反例：custom 的 IP REJECT 行同时具有同 ID 的 disabled link，实际 custom 查询仍返回该行，
迁移必须保留其有效影响并阻断；同样的 disabled ID 在 standard 的 added／global 查询中则按既有逻辑排除。

## 6. 生成预览和敏感内容

预览只接受已知结构、完整必填、引用合法且没有迁移阻断的当前草稿快照；调用 `ManagedPolicy.fromJson` 和
`compileManagedProfile`。失败显示安全的字段路径和类别，不回显用户原值、完整异常或 YAML。预览可针对未保存编辑，但标题标明未保存，
且仍不应用。

生成 YAML 先保留内存原文，再从解析结构遮蔽 SOCKS5 username／password，默认以只读
[EditorPage](../../../../lib/pages/editor.dart)展示脱敏版本。不能用全局字符串替换误改其它字段，脱敏 YAML
不作为编译输入、存储或备份来源。

默认复制脱敏预览；另设“复制完整配置”，每次明确提示其中可能有认证和迁移相关敏感配置，由用户确认后才把完整生成 YAML 写入剪贴板。迁移原始材料不混入生成
YAML。页面关闭不主动清空用户可能已改写的剪贴板，也不持久化预览缓存。

现有“预览”继续表示传统合成配置，现有 Profile 导出继续导出原 Profile 文件；新入口明确命名“生成草稿预览”，避免把两者当作当前实际配置。
本项不增加完整草稿的文件导出路径。

## 7. 备份与恢复闭环

### 7.1 显式承接存储对象

为 [MigrationData](../../../../lib/models/state.dart)增加默认空列表的草稿记录，并贯通
`readBackupArchive`、BackupAction、Database.restore
和[应用迁移 store](../../../../lib/common/migration.dart)。归档仍包含整份 DB；解析后显式读取新表，不能依赖原
ZIP 已带 DB 就认为恢复会自动保真。

旧 schema 11 归档在 staging 迁至 12 后读出空草稿；v0 兼容数据和没有 DB 的归档维持原迁移入口。未来 DB schema
在打开迁移前拒绝；当前 DB schema 中未知 draftVersion／无法解析的 rawContent 原样传递，不能自动降级成新空草稿。

### 7.2 合并、覆盖与事务失败

| 操作 | 传入有草稿行 | 传入无草稿行 |
| --- | --- | --- |
| compatible 合并 | 按 Profile ID 替换对应草稿，含未知内容 | 保留目标 DB 原草稿，旧备份不静默清空 |
| override 覆盖 | 仅在既有非空实体替换路径内恢复传入草稿集合 | 该路径内被恢复 Profile 的旧草稿清除，删除 Profile 的行级联 |
| onlyProfiles | 沿现有选项跳过 Config，草稿随 DB 实体恢复 | 按所选 compatible／override 规则处理 |

应用前检查 incoming 草稿 ID 唯一且关联 incoming Profile，不接受仅指向目标 DB 某现存 Profile 的孤儿行；
不静默清洗或把未知 rawContent 当关系错误。草稿列表纳入 Database.restore 的空输入判断、写入和孤儿处理；
非空孤儿草稿在进入事务及空输入判断前拒绝。

沿用既有全部实体为空时调用 beforeCommit 后早退的语义，override 也不因空输入清库。没有 DB、仅含 Config 的归档，与有效 DB
但零 Profile／零草稿且其它实体也全空的归档分别验证：两者都保留目标 DB 实体，只按原 RestoreOption 处理 Config。
若还有其它实体非空，则按现有 restore 路径处理，不新增破坏性空库恢复能力。

在实体恢复路径中，写入与现有规则／Profile 恢复、beforeCommit 文件和 preferences 操作共享原事务及失败补偿；DB
失败不能留下半份草稿。覆盖恢复的 UI 说明非空实体替换会清除备份中没有的草稿，不能因归档来自旧版本而声称仍保留；全部实体为空则沿上述早退边界。
恢复不根据草稿内容激活配置；原恢复已有的来源失效行为继续沿原入口处理。

### 7.3 明文 ZIP 与确认时机

新正文可包含 SOCKS5 认证及旧材料中的秘密，沿现有 DB 目录保存，Android 使用应用私有目录，备份 ZIP 不加密。本项不引入密钥库或加密归档，
不声称桌面目录／导出目标具有 Android 沙箱保护；编辑页说明存储方式，备份涉及草稿时明确提示完整敏感内容会进入本地文件或所选 WebDAV 目标。

所有现有备份入口经同一备份 UI 收集本次明确确认，调用 BackupAction 时传递仅对本次有效的确认值。实际 `VACUUM INTO` 后、打包和
deliver 前，从**冻结的快照 DB**读取是否有草稿；有草稿但没有确认则拒绝本次生成／交付，提示重新确认，不用实时 DB 的旧查询替代。

快照检查复用备份 staging 的明确 DB／temp 路径打开方式，读取后关闭；不调用 path_provider 或连接真实运行 DB。这样 UI
预查后才新增草稿也不能绕过确认。确认后新增但未进入快照的内容留到下次备份，快照内有删除前草稿仍按快照处理。取消不调用 deliver，不上传；临时快照沿原
`_withWorkDir` 清理，失败保留例外沿原恢复规则。

恢复里的地址、配置或草稿字段不构成新的上传授权；只因原配置含 WebDAV 信息也不自动备份。本项验证使用假的 deliver 和目标，不访问实际
WebDAV、真实备份或个人 DB。

## 8. 失败、边界和下游接续

- 页面丢失 Profile、CAS 冲突、损坏内容、资源引用错误和 DB 错误分别给出可行动提示；不补默认、不自动清空、不吞错显示保存成功。
- 敏感正文仅进入明确的 DB、归档、编辑表单及经确认的完整复制；不进入 notifier 异常字符串、普通日志、测试失败快照或报告。
- 草稿没有运行资格；03 不得仅因它可编译、可预览或带迁移材料就绕过实际来源及最终配置复核。
- 01 的协议／解析／RuleHost 限制全部承接，尤其不把 redir-host 的映射域名等同于用户最初输入，不新增运行时 matcher 或 DNS
  安全保证。
- 恢复合并保留旧草稿可能使它与新源材料不同，页面把迁移快照标为历史材料；本项不以自动重迁移覆盖用户编辑。

## 9. 拟实施顺序与验证

设计通过后先完成存储／codec 和 schema，再接备份恢复及敏感确认，随后实现页面、迁移和真实编译预览。规则 helper 的无行为变化单独检查。
最后正常生成、受影响回归和实现交评；不提前启动 03，不为本项构建另一套运行流程。

| 验证对象 | 拟执行用例 | 判断依据 |
| --- | --- | --- |
| 真实菜单和编辑页 | 加／删／排序、两默认、DNS、资源引用、重开、未保存离开和窄屏布局 | 临时 DB、实际 widget 和 DAO；四份语言资源 |
| 持久化与升级 | schema 11→12、表已存在升级、普通 Profile 编辑保留草稿、删除级联 | 实际 SQLite fixture 和生产迁移 |
| 版本及失败 | incomplete、未知版本／字段、非 JSON 原样保存；缺 Profile、CAS、DB 注入失败 | 不丢原文、不默认放行，错误不含合成秘密 |
| CAS 值合同 | 不同原文／缺 Profile 拒绝；恢复同值、merge 保留、无行仍无行、同值重建允许 | 只承诺值比较，不声称检测全部中间恢复 |
| 草稿隔离 | 保存／退出／预览均无 setup、apply、Core 或当前选择变化 | 生产 action 配合明确 spy，非仅模型测试 |
| 规则提取 | Profile→global→源顺序、standard 的 disabled、MATCH 逆向替换、custom 空／非空、script 不执行 | 实际 DAO、共用 helper 和独立期望 |
| 迁移反例 | IP REJECT／no-resolve、custom 同 ID disabled 仍有效、中途 MATCH REJECT、混合／Geo／未知 token、动态组 | 保存材料及位置；删提取行／补默认不解除阻断；不裁掉 MATCH 后行 |
| 预览／复制 | 真实 01 编译、未保存标题、默认遮蔽、完整复制确认及取消 | 解析生成 YAML，假 Clipboard 核对 UTF-8 秘密保真 |
| 备份恢复 | VACUUM→ZIP→readBackupArchive→MigrationData→applyRestore | 两份独立临时 DB，真实文件及事务消费者 |
| 恢复语义 | merge／override／onlyProfiles、旧 v0／schema11、未来 DB、未知草稿、孤儿／重复 | 精确检查恢复后行；注入 beforeCommit 失败检查回滚 |
| 空实体恢复 | 无 DB 仅 Config、有效 DB 全实体为空，分别覆盖 override／compatible | 原 beforeCommit／Config 行为，目标实体和草稿保留；孤儿草稿先拒绝 |
| 备份确认并发 | 预查后新增、快照后删除、确认取消、无确认快照拒绝 | 真快照检查、fake deliver 零交付，无真实上传 |
| 生命周期与回归 | 保存异常 loading 收敛、迟到操作／dispose、旧合成行为和旧备份测试 | 针对受影响 widget／DAO／common 的 Flutter 测试 |

实施阶段按仓库命令运行正常 intl／build_runner 生成、依赖解析、格式与分析，并执行上述必要本地合成测试；不手改生成文件或关闭原 native
hook。01 编译器不变时复用其已审 Core 路由／DNS 证据，新测试补真实 UI／DB／备份消费者，不把旧证据写成本项重新执行。

本设计的验证范围为本地合成消费者；APK、设备、真实订阅、宿主系统代理／TUN 及外部收件不在本项自验范围。实际运行结果、
偏差和版本绑定以[本项结果](l2_t02_02_result.md)为准，计划本身不记为通过。
