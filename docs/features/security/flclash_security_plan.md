# FlClash Android 安全整改总计划

本文件只管理各 loop 的入口、状态和依赖。共同需求见[安全目标与判定原则](security_requirements.md)，阶段需求、风险和解决方向由子计划维护；阶段计划确定后再拆 tasks。

| Loop | 子计划入口 | 状态 | 前置依赖 |
| --- | --- | --- | --- |
| 1 | [loop1_plan.md](loop1/loop1_plan.md) | 部分完成，含用户暂缓项 | 无 |
| 2 | [loop2_plan.md](loop2/loop2_plan.md) | 进行中 | L1-T03 已完成；本地配置/业务出口可先行，联网身份边界接 Loop 1 实际交付 |
| 3 | [loop3_plan.md](loop3/loop3_plan.md) | 计划待评审，未实施 | 无；与 Loop 1 对齐本地报告边界 |
| 4 | [loop4_plan.md](loop4/loop4_plan.md) | 计划待评审，未实施 | 可先审基线；完整范围接收 Loop 5 清单 |
| 5 | [loop5_plan.md](loop5/loop5_plan.md) | 计划待评审，未实施 | 无；按各 loop 最终修改更新清单 |
| 6 | [loop6_plan.md](loop6/loop6_plan.md) | 计划待评审，未实施 | 来源比对可先做；更新保护使用 Loop 1 |
| 7 | [loop7_plan.md](loop7/loop7_plan.md) | 计划待评审，未实施 | Loop 1–6 的实际交付 |

共用资料入口：[Android 审计基线](android_security_baseline.md)、**[fork 与官方同步约定](../../../CONTRIBUTING.md)**、[Android 构建指南](../../development/android_build_guide.md)。

其它平台待定。
