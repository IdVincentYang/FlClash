# L2-T02-04 订阅、集合与资产更新 Plan

任务入口：[04](l2_t02_tasks.md#l2-t02-04-订阅集合与资产更新)。推荐把当前 Profile 中明确绑定的材料冻结、
展开成既有严格策略，再走 ConfigInput/T01；不改 mihomo，不开放 Core 独立更新受管闭包。
以下支持上限与新增交互待 M1 设计评审，不是已实现能力。

## 问题与目标

[刷新队列](../../../../lib/providers/actions/profile_refresh.dart)已经下载、保存材料并安排实际应用；
但 [SelectedPolicy](../../../../lib/common/policy_selection.dart)只从已保存选择解出静态策略，
最终 [managedFinalProfile](../../../../lib/common/policy_selection.dart)不读取订阅节点。
因此 Sync 成功不证明节点地址、认证或组成员更新到达受管运行配置。简单按同名覆盖手工节点又会凭空授予来源控制权。

目标是受支持材料 A→B 沿真实导入/刷新、冻结、编译及 Core 采用闭环，用户的目标、顺序、默认和 DNS 接收方由策略维护。
普通已绑定更新无逐次确认；无效/越界候选保留仍适用旧输入或安全失败，不启动已停止服务。
本项不承诺兼容任意订阅，更广来源委托归 L2-T05，Geo 内容真实性归 Loop 6。

## 推荐支持边界与交付顺序

| 材料 | 本项支持 | 明确不支持 |
| --- | --- | --- |
| 节点 | 固定 IP SOCKS5，现有严格字段/认证 | 域名节点、其它协议、特殊 resolver、额外传输字段 |
| 组 | 手工引用或源 select，仅支持的真实代理 | 控制成员、嵌套/use/filter、自动选择组 |
| 域名集合 | 当前材料的 DOMAIN/DOMAIN-SUFFIX | keyword/regex/GEOSITE、混合条件/action |
| 地址集合 | 当前材料的纯 IP-CIDR/IP-CIDR6 | GEOIP/IP-ASN、混合域名/地址、隐式解析 |
| 外部资产 | 真实引用入口先拒绝，不读取 | http/file provider、跨来源、Geo 条件/自动更新 |
| DNS | 沿用 01–03 明确接收方与传输白名单 | DoH、system/DHCP 或新增 DIRECT/系统 DNS 回退 |

集合仅接受 inline classical 或纯地址 inline ipcidr；跨来源指其它 Profile/全局 provider。
组不得含 DIRECT/PASS 等控制成员；所有最终材料仍须经过既有严格编译校验。
先交节点/组来源绑定与真实刷新闭环，再接同一材料中的 inline 集合，最后核对拒绝/资产入口及恢复矩阵，合为一次 04 交付。
Geo/远程 provider/协议扩展不计入本项已支持成果，也不由 05 自动补做；未来扩展另行派工/设计。
支持表与完整闭环共同构成本项拟出口，请 M1 核定；不以单个编译或节点演示结案。

## 来源、模板与冻结

保留 version 1 手工策略原语义，不自动关联订阅。新增 version 2 草稿/选择模板，在节点、组及规则位置显式引用材料；
解析/展开后仍交给 version 1 `ManagedPolicy` 与同一个编译器，Core managed 描述/白名单不扩展。
旧版和未知版本继续明确区分；未知版本只读/拒绝采用，备份恢复验证关系，不能落回手工值或旧非受管配置。
选择模板+纯展开而非刷新时改写手工策略，保留用户值与来源委托的区别；也不采用 Core provider 热更新绕过最终编译。
代价是模板版本、预检/最终重编译及少量绑定交互，换取不维护第二套已采用材料状态。

- 绑定由用户在 Policy draft 中明确选择。
  来源身份为 Profile ID、类型、精确存储 URL、overwrite 类型及 script ID 的指纹；
  不含 label、刷新时间或 Request route/周期，hash 只是身份/完整性线索，不是官方真实性。
- 每个绑定保留用户自己的稳定 alias，与该来源内精确节点/组/provider 名相连；不按同名或相同地址猜测手工绑定。
  来源 URL/拓扑改变需重绑；改显示名称不解绑。相同来源重复名称、生成 ID 冲突整份拒绝。
- 源名称改变/移除不猜替代项，不回用旧节点；可显式重绑或把当前预览值转换为手工值。
  源 select 成员增减在已绑定范围内自动展开；保留仍有效选择，已移除选择只在该动态组内选首个合法新成员，绝不选 DIRECT。
  空组、坏成员或不支持成员拒绝整份候选，不过滤后伪装成功；手工非法选择仍报错。
- 集合按引用所在位置展开，保留条目 target/DNS 与顺序；生成条目 ID 与 alias/条件稳定关联并检查冲突。
  空集合、重复/不支持条目整份拒绝，不让规则消失后落入默认。未绑定的源规则/DNS 仍不拥有策略控制权。

复用 Request 的读入/来源版本边界，捕获选择、原始材料/脚本字节、允许覆写及 application-config 的同次快照。
文件复制为有界临时快照；释放 mutation 后，通过现有 Core 原文档解析接口读取临时路径，执行冻结脚本及允许覆写，
从最终材料提取绑定，再严格编译。Core 解析/脚本/网络不放在 Dart mutation 内等待，避免重开 03 锁环。
受管路径不执行传统 provider 文件迁移/注入的副作用，不在编译后 patch 路由/DNS。

只增加一个纯材料展开边界（拟 `lib/common/managed_material.dart`），返回封闭策略和来源摘要，
不建运行时 matcher、第二套刷新/运行状态机或持久 pending 台账。
ConfigInput 沿原不可变 manifest 增加有界材料摘要字段，Dart/Go 声明同步，记录原始/已用材料及绑定身份；
YAML 包含实际采用值。摘要随 inputId 绑定、仅用于追溯，资格仍由原 source tickets/T01 检查，不能给旧 map 配新票据。
不借 acceptedOverrides 承载材料，不新增 Core 命令、managed 描述版本或运行资格。
初始资源预算为 16 MiB 输入/最终文本、1024 个已用节点、128 个绑定、10000 个展开条目；
限制重复引用放大，超限整份拒绝而不截断，不把这些预算当作性能实测。

## 刷新、采用与失败

现有 Profiles → Add → Obtain a profile from a URL → Import from URL 路径保留，
以及 Edit、Sync、Request route 和 Auto update。
普通刷新仍使用原队列、调度及 Auto/Proxy/Direct，不另发 provider 下载，不改代理失败策略。

1. 原 RequestSession 下载到 RequestFile。受管候选先用冻结选择/脚本/设置做材料预检与最终闭包校验；
   预检仅复用同一解析/编译路径，不是运行成功。错误发生在来源提交前时保留文件/日期和仍合格的旧输入。
2. 原 session.commit 内重验全部原票据、row、选择及摘要，失效后整体退出；
   一次 mutation 失效 profile 来源再替换材料/保存元数据。
   来源已经失效后的保存/补偿错误继续走 partial_commit/T01，不能把旧资格恢复为 true。
3. 提交后沿原 setup 重新捕获已保存材料与票据并编译、写 ConfigInput、prepare/install/activate；
   不把预检 YAML 贴新 ticket。脚本若两次输出不同，最终路径仍须重新校验，失败按实际资格保留旧输入或关闭。
   ExpectedRun/ServiceState 继续决定 active；
   Sync 成功、materialSaved、installed/activated 分别显示。

为了坏更新保留 A 后仍能修复重命名，在现有 Policy draft 的 Source/Preview 内增加最少操作：
Manual/This profile 选择绑定来源；Load latest material 仅暂存并预览，不覆盖 A；Apply 明确采用预览材料及绑定。
页面拥有 RequestFile/会话和预览票据，取消、离页、停止失效或较新操作使其不可采用并清理。
既有草稿 Save 不等于采用；Apply 重验预览、draft/selection CAS，
在同一 mutation 通过现有文件替换补偿及 DB transaction 保存该材料/选择，再交原 setup。
没有持久 pending 队列，不要求自动更新每次弹窗。
UI 只显示来源/成员、缺项及保存/实际采用差别，凭据沿现有预览遮罩，不把原始 URL/异常写进新提示。

实际 provider/Geo 入口必须核对：本项绑定不读取远程、任意文件或全局 Geo 文件；受管最终输出不重新带入这些引用/定时字段。
未被受管配置使用的传统 Geo 维护不改写本项 inline 快照。若发现实际旁路，先限定本项边界并交 M，不修改 mihomo。

## 文档先行与实施落点

设计通过后先新增 `docs/features/security/managed_updates_design.md`（模板/来源/失败契约）及
`docs/features/security/managed_updates_guide.md`（English UI 操作/限制，未可用处标 draft）；
同步 `loop2/l2_t02_plan.md` §7.2 的当前支持边界，
以及 `.agents/architecture.md` 的材料/ConfigInput 协作，
再改模型/草稿/选择解析、材料展开、setup/刷新、现有页面及 ARB，正常生成，随后验证与构建。
不回写冻结的 01–03 Plan/Result；共同需求/暂缓备忘不改，联网用途清单只更新受影响刷新说明并引用长期契约。
最终新增 `loop2/l2_t02_04_result.md`，回填实际覆盖和 Tasks；本轮设计仅改本 Plan、状态清单和总体计划的实际授权段。

## 拟验收与交付

| 用户场景/反例 | 必须观察的真实出口 |
| --- | --- |
| URL 导入 A，绑定后手动/自动刷新 B | UI→刷新→真实 Core 收件到 B 地址/认证/成员；用户 target/DNS 不变 |
| 成员移除/同名/重命名、URL 改变、解绑 | 稳定 alias/选择按上文处理，未绑定手工节点不被覆盖；重绑采用与 Save 分开 |
| inline 集合 A→B | 两端同序展开、固定 target/DNS；空/混合/远程/Geo/超限拒绝且无新接收方 |
| 预检失败、提交/编译/应用失败 | 来源提交前保留合格 A；之后依据原 T01 判适用旧输入或安全关闭，不落默认直连 |
| 阶段间取消/删源/改源/停止/并发 | barriers 验原 ticket/快照，迟到无效、不重启已停止服务、不续旧材料 |
| 脚本/覆写、选择变更、冷恢复/备份、旧/未知版本 | 使用最终消费者；不改写用户规则/DNS，迁移问题不因绑定清空，未知输入不回退 |

barriers 覆盖下载、预检、来源提交、Input 写入至 prepare/activate 的关键交错。
扩展既有 profile_refresh/policy_selection/widget 与真实 Core bridge 测试，
用独立 loopback SOCKS5/HTTP/TLS/DNS 收件核对 A→B，
不只比较生成 YAML、返回值或 Sync 文案；覆盖三种 Request route、失败、拒绝和并发。新增最小合成材料与可复现收件 fixture 随源，
原始日志/制品留忽略目录。正常生成/pub get/analyze、受影响测试及最终 ARM64 APK 绑定后交实现评审；未变证据按来源/条件复用。
交付后指南给本地 A/B fixture 与 English UI 手动步骤（含 AVD 的主机地址），用户自行安装/启动；D 不操作设备/宿主网络。
真实 `ouo` 未拉取，URL/凭据不入设计或夹具；不变的真实订阅不能替代 A→B，兼容未测如实说明。
04 完成不等于 05、整个 L2-T02 或设备/物理网络保证完成；两道评审后按约定本地合入，由 M 收尾并普通推送。
