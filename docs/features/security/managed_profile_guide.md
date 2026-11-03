# Managed profile 使用指南

本指南说明已实现的受管编辑、存储、应用和材料更新，以及实际使用前须区分的保护边界。
共享 IP 的原域名身份缺陷仍未解决，**DNS 安全验收未通过**；
不能把生成配置、Apply 或 VPN active 当作域名分流安全证明。
缺陷、规避条件及上游跟踪统一见[R1 长期记录](deferred_security_items.md#l2-t02-r1-共享-ip-与域名身份)。

## 何时使用

受管策略让用户明确维护业务条件、出口和 DNS，由应用一起生成最终配置。
原始订阅提供允许的节点/组/集合材料，不直接决定受管规则。
材料支持、限制及更新语义由[更新契约](managed_updates_design.md)定义，
服务与排除范围由[服务契约](android_service_design.md)定义。
普通配置路径不自动获得本模式的配置生成保证。

## 从导入到实际采用

以下为现有 English UI 路径；完整受管设备闭环尚未验证，按步骤操作不等于身份保护已通过。

1. Profiles → Add → Import from URL，选择订阅来源及 Request route。
   首次无配置的手动导入可能要求确认此次 Direct 恢复用途；它不改变持久 Proxy 偏好。
2. 打开该 Profile 的 Policy draft，设置 Domain rules、IP rules、两个显式默认及 DNS 服务。
   Default for unmatched domains 为 DIRECT 时，未命中域名的 DNS 也使用指定直连服务。
3. More → Source bindings，明确绑定需要的源节点/select 组及 inline 集合。
   [绑定与更新步骤](managed_updates_guide.md#绑定与更新)说明名称、来源及重绑条件。
4. Generated draft preview 查看脱敏结果。Save 只保存草稿。
   Save and request application 保存明确选择并请求采用；它不启动已停止的服务。
5. Profile detail → Actual accepted configuration 核对实际接受内容和状态。
   草稿、保存源文件、Sync 完成和实际采用是不同事实；坏候选可能保留仍合资格的旧输入，
   也可能关闭已失效输入，详见[失败与重绑](managed_updates_guide.md#失败与重绑)。
6. 使用 Start 请求运行，按 Android service 查看实际接管状态。
   [服务操作指南](android_service_guide.md)解释 Suspended、VPN active、Proxy only、故障和 Stop；
   服务状态不证明 DNS/业务已送达预期接收方。
7. Sync 或合资格 Auto update 取得新材料并重新构建受管配置。
   自动更新无需每次重新确认同一来源，但源或绑定变化不能按同名静默重绑。

备份可能包含节点凭据，使用既有未加密 ZIP 及确认流程。恢复保留草稿/选择的版本和来源身份；
相同 ID 不等于同一来源。未知版本不可采用，原始规则不能等价迁移时保持阻断，
不能用新建独立草稿冒充旧 IP REJECT 等保护已保留。

## 当前能力与验收边界

“支持”指已有分项实现及受检范围，不替代未完成的用户/设备闭环或域名身份安全验收。
未覆盖的完整需求仍由[总体设计](loop2/l2_t02_plan.md)维护。

| 分类 | 能力或限制 | 依据/后续位置 |
| --- | --- | --- |
| 支持子集 | 固定 IP SOCKS5、封闭 select、精确/后缀、inline 域名/地址集合 | 更新契约 |
| 支持子集 | 显式默认、草稿/选择、最终生成、受管材料更新 | 更新契约及本指南 |
| 不支持 | Geo、其它协议/自动组、远程 provider、keyword/regex、DoH | 总体设计及更新契约 |
| 不支持 | 受管 fake-ip、静态 hosts | 总体目标尚未交付，不由05自动扩展 |
| 未运行 | 完整导入/编辑/运行/更新设备闭环 | 不能作为安全通过 |
| 未解决 | redir-host 共享 IP/旧 mapping 可能改变原域名分类 | R1 长期记录 |
| 保护范围外 | 代理内部 DNS/实际远端 IP、应用自带加密 DNS 的内层域名 | 总体设计 §10 |
| 未验证 | 物理网络绑定及未运行设备条件 | 服务指南及总体设计 §10 |

Geo/资产身份接 Loop 6，来源信任接 L2-T05；协议/组/provider 等扩展仍需另行设计和授权。
拒绝不支持输入不表示原需求已经完成。维护请求继续使用自己的 Auto/Proxy/Direct 与运行资格，
不能由普通业务规则推导其实际出口。

## 使用前应了解的身份边界

当前编译器生成 redir-host。字面 IP 也可能被 mapping 归入域名表，
地址规则不等于覆盖所有域名最终目的 IP。显式携带域名的代理入口与只有 IP 的 TUN 条件不同。
[R1 长期记录](deferred_security_items.md#l2-t02-r1-共享-ip-与域名身份)
维护已证实收件、版本、规避条件、未验证范围和未来复验标准；本指南不另定义一套风险状态。
