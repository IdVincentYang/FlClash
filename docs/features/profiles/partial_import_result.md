# 关联来源部分失败的订阅导入 Result

已实现新 URL 导入的部分来源失败处理。所有来源尝试完成前不能接受或选择替代导入；
全部成功沿用完整接受，部分失败则提供保存待补齐和单独审核已加载节点。
用户提出的 Domestic 失败场景以本地合成来源复现，未读取、上传或修改用户真实订阅。
方案见 [Plan](partial_import_plan.md)，当前行为见[来源接受指南](../security/source_acceptance_guide.md)。

## 实现与采用

SourceReviewLoading 区分全部尝试结束与全部成功。排队、下载、核验、重试时均不可接受；
业务层同样检查完整材料是否就绪，提前返回接受决定也不会批准来源。部分失败后停止无意义的进度动画，
Final configuration 改为“已解析”，不再让其 Ready 暗示整份订阅可用。

保存待补齐只适用于新 URL 导入：沿原下载会话、当前性检查及文件／数据库提交保存原材料，
不建立使用许可或最终配置许可、不应用配置；卡片继续显示待审核，之后可进入 Review source 补齐。
已有订阅刷新不走这条替代路径，继续保护已接受材料和当前配置。

节点操作取消原候选，将主材料及成功预览的节点材料投影成独立快照；排除原规则、分组、DNS、
监听器、tunnels 和外部来源，只形成内联节点、一个 Selector 和显式 MATCH。
同名且定义不一致的节点、缺失或循环依赖、内置直连／拒绝项不混入代理节点组。
依赖解析使用迭代及结果缓存，10000 项依赖链测试通过，不在每次 UI 重绘中重算快照。

同一导入窗口重新展示快照，用户再次 Accept 才沿原权限／材料／最终配置路径保存。
节点快照不提供“使用来源路由”切换，避免把生成的 MATCH 与原订阅规则混淆；应用自身设置继续参与最终合成。
原 URL 保留，快照关闭自动更新；手动更新从原 URL 取得完整配置后须重新审核。
“已加载”不表示节点已经做过连通性或延迟测试。

## 验证结果

| 检查 | 结果 |
| --- | --- |
| pub get --enforce-lockfile | 成功，锁文件不变 |
| intl_utils、build_runner | 成功；四语文案及对应生成文件同步 |
| analyze --no-fatal-infos | 通过，42 条原有 info，无新增问题 |
| 最终投影／加载／审核 UI／导入 UI／本地化检查 | 24 项通过 |
| 真实 Dart→Go 的新增导入反例及正例 | 4 项通过 |
| 来源与刷新桥接、审核呈现回归 | 61 项通过，23 项按既有环境条件跳过 |
| 扩展回归 | 658 项通过、23 项跳过、5 项既有失败 |
| 400×900 窄屏渲染 | 通过，已查看本地截图，三个操作可见，无布局异常 |
| Android ARM64 debug APK | 构建及签名验证成功；最终确认构建无“修改后须重建”提示 |
| Core carrier --check | 通过；没有改动 Go、Kotlin、gitlink 或数据库模式 |

UI 测试控制 5 个关联来源：第一个失败后，仍有来源排队／在途时不出现替代操作，Accept 保持禁用；
全部结束后才显示替代操作。独立重试再次使终态失效，成功项不会重新下载。
节点投影测试包括去重、冲突、外部依赖、循环、组名冲突、空节点及长依赖链。

真实桥接使用当前 parent Go 编译出的 no_zerotier、CGO_ENABLED=0 测试进程和 localhost HTTP，
通过生产 URL 导入／来源预览／材料提交链路，使用明确的合成用户决定；这是组件集成验证，不是 Android UI 操作：

- 关联尝试尚未开始便返回完整接受，结果被拒绝，既有许可文件及配置 fence 不变。
- Domestic 返回 HTTP 503、节点来源成功后，保存待补齐保留原文件和 URL，状态为待审核；许可文件字节不变。
- 同一失败输入选择节点快照，第二次审核前不批准材料；接受后保存两个来源的节点和显式 MATCH，原分流及外部来源不在文件中。
- 清空本次内存审核缓存后，明确采用快照成功，不再发出关联来源请求或审核回调。
- 手动更新并恢复 Domestic 后，完整来源重新审核，原 URL 内容可正式保存；关联来源各只下载一次。
- 在快照审核阶段取消，文件／数据库不新增订阅，既有权限不变。

桥接回归的 23 项跳过为未提供受管配置编译器的既有用例及 4 项未提供 JVM bridge classpath 的清理用例；
本次标准订阅导入的 4 个新增用例均实际执行。扩展回归对应最终业务层提前接受校验及最后 UI 整理前的快照，
后续直接相关检查与桥接回归已更新至最终行为，不把旧检查写成最终全量通过。
5 个既有失败仍为更新说明夹具 RequestUnavailable 三项、macOS Rust dylib LINKEDIT 加载一项、
未修改的 bootstrap_test.dart Material 导入 lint 一项；基线复现依据见
[前一任务的记录](../network_activity/na_t01_02_result.md#自动化与性能)。

## 版本、证据与边界

基线 3b56a77，2026-11-12 验证。生产文件摘要保存在本地
`build/verification/partial-import/source-binding.json`，其 productionFiles 按键排序、紧凑 JSON 编码的 SHA-256 为
`d58c3821f1404277e8dcf71fbb1c59f4cd90002dee4086ca37396723ee5ed191`。
受测 APK SHA-256 为
`9e6cc5921be8f09c9696618c86fe94b6650f2a6c17689bdaeadd61e1c4d52805`，
Gradle 调试签名 SHA-256 为
`5a7c9cb8db640dfac17b75daba333e285ba76595e6e71b2d7d2d0e851f8849ec`。
本地交付副本为 `~/Downloads/FlClash-partial-import-20261112-arm64-debug.apk`，与构建包摘要相同。

日志在 `.buildlog/android-build/partial-import-*.log`，渲染结果在
`build/verification/partial-import/partial-phone.png`；这些原始证据、夹具二进制及 APK 不入 Git。
测试来源固定在回归用例中，桥接复现需先在 core 下执行
`CGO_ENABLED=0 go test -c -tags no_zerotier -o ../.buildlog/android-build/partial-import-bridge .`，
然后设置 FLCLASH_APPLICATION_INPUT_BRIDGE 为该二进制绝对路径，运行 profile_refresh_bridge_test.dart 的 URL partial import 用例。

本轮没有覆盖安装或操作用户模拟器，没有做真机、Android JNI 端到端、公网订阅或 Release R8 验收；
没有证明用户的 Domestic 具体是地址失效、出口不可用还是服务端异常。
没有放宽来源接受、既有订阅失败保护或路由缺省语义；应用网络后续任务未推进。
同一执行者完成职责／调用链自审，不称为独立评审。Markdown 和引用按增量检查，无新增违规；保留 architecture 的 22 处、source_acceptance_design 的 1 处原有行长问题。
本轮 Plan／Result 作为行为变更与版本证据保留，未产生额外任务清单或权限状态副本。
