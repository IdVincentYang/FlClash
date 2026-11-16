# R11 当前文档同步 Plan

任务入口：[Android branch review Issue R11](android_branch_review_issue.md#r11当前文档与已实现契约不同步)。
基线为 `security/android`／`c6cd9a5`；方案及三份正式文档均已获 M 通过，自验完成。
本 Plan 随三份正式文档纳入本地 fixup；Issue、Details 最终对账和本 Plan 清理由 M 负责。

## 问题与目标

三处当前说明与源码不符，会使维护者绑定错误的 Core、误判节点 fallback，或使用户等待不存在的 Restart 提示。
只修订有效文档，不修改生产／测试、Core／carrier、权限和验收状态，也不处理 F01 或回写冻结历史。

已核实 gitlink、Core checkout 与 carrier commit 均为 `7a620b930bdcb85e466450880313d34add46252b`，
tree 与 carrier 一致；公开 base 仍为 `8597778c7df410ebe88c57e59eaab32d203156df`。
旧 `6c6e3e4` 至当前版本的 DNS／resolver／fakeip／profile cache、Geo 组件及 log/log.go 无差异；
这只是相关源码对照，不是当前版本已重跑旧反例，更不能证明暂缓问题消失。

节点投影先剔除同名异义与缺失／循环 dialer 依赖；仅常规结果为空且已有首个独立节点时，
保留该节点作为 fallback，独立指 dialer-proxy 缺省、空字符串或 DIRECT。
专项测试和已批准提交 `62401ee6ee6489cf192ef9a29bc6444b6e05bb99` 明确包含此取舍。
来源接受消费者仅在新导入、全部关联来源尝试结束且原部分配置不可用时形成节点候选，仍重新精确审核及正式提交。

Network 控件通过 ApplicationInputAction 保存配置；初始化且有运行意图时，实际 VpnOptions 改变会请求完整应用／重建 VPN。
未启动时只保存，后续 Start 使用新设置；应用失败或被新 Stop 取代不等于已经生效。
这与应用网络设计一致，不再要求用户按旧提示手动 Restart。

## 修订方案

- `deferred_security_items.md`：集中说明当前 Core／carrier 和旧证据版本；将 R1、日志并发、Geo 暂缓及
  EasyTier 原对象的旧版本明确标为当时对象，保留原日志／摘要、风险与恢复条件，不做全局 SHA 替换。
- `source_acceptance_design.md`：补全节点快照的空结果 fallback 条件，明确不保留冲突依赖闭包、不放宽
  来源接受；只对投影生成的具体正文再次审核。其它同名冲突规则保持原义。
- `android_service_guide.md`：改正 English UI 与相应复现步骤中的 VPN 设置采用说明，区分自动重新应用、
  离线保存、失败后的手动 Stop／Start；保留系统 VPN 权限、撤销、Proxy only 和设备证据边界。

当前消费者包括来源审核／部分订阅导入、应用网络设计、Geo 设计／指南、构建来源和服务契约。
其入站引用不改路径或锚点；当前正文三处修正即可，既有阶段 Plan／Result 及本地冻结证据不回写。
不新建平行规范或产品机制，也不为纯文档任务增加测试平台。

## 实施与验证

方案获审后修订上述三份正式文档，并维护本 Plan 的真实阶段；无需另建 Result。
实际内容、源码对照及校验输出保存在本地忽略目录，交评及交付报告关联版本和证据。

验收逐项核对 Core gitlink／manifest／tree 与新旧证据措辞、投影源码／专项断言／实际审核消费者、
Network 写入口／VpnOptions 比较／运行意图与完整应用分支。检查受影响 Markdown、链接与引用，
并核对最终差异仅含本任务文档，没有更新风险或阶段完成结论。
本轮不运行产品编译、Flutter／Go 完整测试或设备操作；操作说明按源码核查，不宣称新增运行验收。
实现文档获审后按 skill refine，沿既有约定本地 fixup 交付；Issue、Details 最终对账和任务文档清理由 M 完成。

本轮自验：已对照上述实际源码和既有专项断言；四份 Markdown 无格式问题，相关本地引用目标 88 个、
其中锚点 41 个均有效。原日志摘要、旧 AVD 边界和暂缓状态保留，差异仅为三份当前文档与本 Plan。
未运行产品测试或设备验证，未修改生产／测试或冻结证据。
