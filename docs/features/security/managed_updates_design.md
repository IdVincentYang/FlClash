# Managed Profile 材料更新契约

> L2-T05 Android实现评审通过，待本地交付及M收尾：[来源接受契约](source_acceptance_design.md)和[指南](source_acceptance_guide.md)。
> 材料接受、未来维护与实际采用分开；新增grant／候选／ledger为有界私有元信息，不扩大业务数据用途。

Profile 显式绑定的材料经冻结、校验和展开后，由同一严格编译器生成业务/DNS 配置，
使用步骤及本地合成夹具见[更新指南](managed_updates_guide.md)。
Request、来源票据、ConfigInput/T01 与 ServiceState 分别保留下载、来源、实际采用与运行意图权威。
本契约的配置级同源生成不保证 Core 恢复的原域名身份；当前未解决缺陷及跟踪见
[R1 长期记录](deferred_security_items.md#l2-t02-r1-共享-ip-与域名身份)。

## 模板与支持上限

version 1 手工策略不变，不因节点同名授予订阅控制权。version 2 草稿/选择包裹 schemaVersion 2 模板；
展开结果必须重新通过 schemaVersion 1 ManagedPolicy/编译器，Core managed 描述版本不变。
未知版本只读/拒绝采用，不能回退旧配置或旧静态值。原迁移问题不因绑定清空。

模板保留原策略目标、顺序、默认、DNS、监听与手工资源字段，增加以下封闭材料引用：

| 字段/位置 | 含义 |
| --- | --- |
| materialSource | 当前 profileId 与来源指纹；无原始 URL/认证 |
| proxies 的 `{source: name}` | 明确绑定该来源的精确节点名，alias 由用户维护 |
| groups 的 `{source: name}` | 源 select 组，全部成员须为支持的真实代理 |
| collections 的 `{source: name, kind: domain/ip}` | 同源命名 inline provider |
| domainRules/ipRules 的 collection 引用 | 就地展开条件；target/DNS 仍取用户条目 |

来源指纹包括 Profile ID/type/精确存储 URL/overwrite 类型/script ID，不包括 label、刷新时间、
Request route 或周期。指纹不是官方来源认证。改 URL/拓扑须重绑；同名手工节点不自动变绑定。
引用名字、生成命名空间、重复/冲突、悬空关系须明确验证，不能猜测重命名或过滤坏成员。

支持固定 IP SOCKS5 及现有认证/UDP 字段、封闭 select 组；域名集合为 inline classical 的
DOMAIN/DOMAIN-SUFFIX，地址集合为 inline ipcidr 或纯地址 classical。
拒绝域名节点/其它协议、递归/特殊 resolver、控制成员/嵌套组/use/filter/自动组，
以及 http/file/跨 Profile/全局 provider、混合条件、keyword/regex/Geo 与 DoH。
未绑定材料不进入受管闭包；源规则/DNS/定时字段不拥有用户策略控制权。

空组/空集合/重复条件/不支持条目整份失败，不让规则被删后落入默认。
动态组保留仍在组内的已选成员；成员移除后只在该组选择首个合法新成员，不选 DIRECT。
同模板刷新仍拒绝手工组的非法选择。明确采用不同选择时，预检与提交均先清除旧 managed picks，
再按新闭包选择成员；不将旧选择误判成新策略错误。维护目标、picks、manifest 均取实际闭包。

预算在放大前生效：16 MiB 输入/最终文本，已用节点最多 1024、绑定最多 128、展开条目合计最多 10000；
脚本结果在 JSON 解码前检查输出字节预算。达到上限后整份拒绝，不截断。数字是资源预算，不是性能或总堆峰值测量结论。

## 冻结与采用

来源为 UTF-8 YAML/JSON 对象，本项不接受加密封装；先按共享引用遍历预算检查 YAML alias，再交 native 解析。
读入边界捕获同次选择、原材料/脚本字节、允许覆写、有效设置和原来源 tickets。
Core 原文档解析、脚本、网络和展开在 Dart mutation 外执行；仅对有界不可变临时文件调用现有解析路径。
最终受管分支从脚本及允许覆写后的材料展开，跳过传统 provider 文件迁移/下载副作用，编译后不再 patch 规则/DNS。

刷新下载到 RequestFile 后先预检；失败且尚未提交来源时保留旧文件/日期和仍适用输入。
session.commit 重验全部原票据、row、选择与摘要；失效后拒绝候选。
提交沿原 profile 失效及文件/DB 补偿。提交后 setup 重新捕获实际保存材料，不能把预检 YAML 配上新票据。
后续错误由 T01 判定保留适用旧输入或关闭，partial_commit 不恢复旧资格。
ExpectedRun/ServiceState 决定 active；下载或采用不是新的启动意图。

ConfigInput manifest 的材料摘要仅保存有界身份/digest，不含原始 URL、认证、正文或 source 名称中的任意文本。
摘要随 inputId 绑定并同步 Dart/Go 声明，不使用 acceptedOverrides，不新增命令或资格计数。
模板摘要相同只说明模板未改；材料保存、实际 input/receipt 及采用状态必须分别核对。

## 页面、恢复与范围

Policy draft 在现有表单/预览补 Source bindings 与 Load latest material for preview。
后者仅页面暂存，Apply 重验预览 tickets 与 draft/selection CAS 后才采用材料/绑定；Save 不等于采用。
预览开始即冻结草稿，资格绑定该份草稿及材料帧。草稿变化、较新预览或材料变化使旧完成无效，
旧完成不能发布新草稿已预览的提示。页面加载的成功、失败、通知和清理均须仍拥有该次操作，
丢弃 A 后启动 B 时，A 的迟到收尾不能清除 B 的 busy 状态或开放控件。
Discard preview material、离页和较新加载清理临时文件/会话；来源变化使旧预览不可采用，下次加载或离页释放它，不建持久 pending 库。

merge/override/onlyProfiles 备份恢复须保留模板版本/关系及可修复的来源不匹配状态，
不根据同名或相同 ID 静默重绑；未知模板不成为受管生效输入。
真实 URL、凭据继续只在既有私有材料/最终运行 YAML 边界，新增错误/摘要使用固定位置与脱敏说明。

远程 provider、Geo 和协议扩展仍是未覆盖需求；05 仅验收实际已交付能力。
更广来源信任由 L2-T05、Geo 真实性由 Loop 6 处理，T04/T05 暂缓风险仍见
[备忘](deferred_security_items.md)。设备/系统网络和云端未验证不能由本地夹具代替。
