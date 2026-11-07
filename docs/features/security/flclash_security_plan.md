# FlClash Android 安全整改总计划

本文件只管理各 loop 的入口、状态和依赖。共同需求见[安全目标与判定原则](security_requirements.md)，阶段需求、风险和解决方向由子计划维护；阶段计划确定后再拆 tasks。

| Loop | 子计划入口 | 状态 | 前置依赖 |
| --- | --- | --- | --- |
| 1 | [联网用途与已交付能力](android_network_inventory.md) | 本轮已收尾；[T04/T05 暂缓备忘](deferred_security_items.md)保留 | 无 |
| 2 | [loop2_plan.md](loop2/loop2_plan.md) | 进行中 | L1-T03 已完成；本地配置/业务出口可先行，联网身份边界接 Loop 1 实际交付 |
| 3 | [loop3_plan.md](loop3/loop3_plan.md) | 暂缓，未实施 | 无；与 Loop 1 对齐本地报告边界 |
| 4 | [loop4_plan.md](loop4/loop4_plan.md) | 计划待评审，未实施 | 可先审基线；完整范围接收 Loop 5 清单 |
| 5 | [loop5_plan.md](loop5/loop5_plan.md) | 进行中：T01／T02已完成M远端收尾；T03按用户调整范围已完成M远端收尾，T04完整实现评审通过、本地交付定稿待M收尾；原EasyTier缺口转[备忘](deferred_security_items.md#loop5-t03-easytier-wasm-源码与生成对应) | 复用已交付源码／构建／Geo证据；保持不改Core |
| 6 | [loop6_plan.md](loop6/loop6_plan.md) | 按用户2026-11-06调整范围完成；T01／T04已交付，T02／T03转[备忘](deferred_security_items.md#loop6-t02t03-geo-更新与实际采用)等待Core修复 | T05已交付；运行期剩余保护未实现，不因阶段结案升级结论 |
| 7 | [loop7_plan.md](loop7/loop7_plan.md) | 计划待评审，未实施 | Loop 1–6 的实际交付 |

共用资料入口：[Android 审计基线](android_security_baseline.md)、**[fork 与官方同步约定](../../../CONTRIBUTING.md)**、[Android 构建指南](../../development/android_build_guide.md)。

其它平台待定。

当前能力契约：[IP 查询设计](ip_lookup_design.md)（触发、接收方、数据及失败边界）；
[受管使用指南](managed_profile_guide.md)及
[R1 未解决风险](deferred_security_items.md#l2-t02-r1-共享-ip-与域名身份)；
[受管材料更新](managed_updates_design.md)（见[使用指南](managed_updates_guide.md)）；
[服务与接管范围](android_service_design.md)及[操作指南](android_service_guide.md)。

现有 Loops 过完一轮后再细化的新增需求：[网络活动与规则管理](../network_activity/network_activity_plan.md)。

[来源接受与轻量追溯](source_acceptance_design.md)及[指南](source_acceptance_guide.md)：L2-T05 Android已完成本地交付与M对账；剩余风险保留。
