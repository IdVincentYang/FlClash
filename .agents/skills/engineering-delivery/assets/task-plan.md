# Task Plan

用于说明一项任务是否有必要、方案为何成立，以及怎样交付并证明完成。
按[文档规范 §3.2](../references/documents.md#32-任务方案)裁剪；使用时替换提示，
可合并或细分正文，任务身份与状态引用已有权威记录。

~~~markdown
# <任务标识／标题> Plan

任务入口：<权威任务链接>。<用一两句概括问题、推荐方案和主要未决项。>

## 问题与目标

<用具体场景说明当前行为或能力缺口、依据、目标、范围及完成标准。
Bug 解释触发条件和原因证据；Feature 解释现有做法为何不足；未知事实标为待核实。>

## 方案与理由

<说明修改后的行为及关键实现机制，以必要示例或流程解释职责、契约和协作。
解释方案怎样解决上述问题、为何选择它，以及真正影响选择的替代方案与代价。
所有权、生命周期、失败、兼容和迁移等按实际影响展开；相关未决事项说明影响及解除方式。>

## 实施与验证

<说明可交付增量、依赖、消费者及出口；文档变化遵循文档规范 §4。
将关键完成标准和风险对应到验证条件、方法及预期观察，说明重要反例和验证限制。
实际结果在实施后关联 Result 或既有证据，不预写通过结论。>
~~~

结构参考：[Microsoft Task Design Review](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/templates/template-task-design-review/)、
[Fuchsia RFC](https://fuchsia.googlesource.com/fuchsia/+/refs/heads/main/docs/contribute/governance/rfcs/TEMPLATE.md)和
[Swift Evolution](https://github.com/swiftlang/swift-evolution/blob/main/proposal-templates/0000-swift-template.md)。
