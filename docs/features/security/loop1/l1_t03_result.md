# L1-T03 本地实现与验证结果

第三轮四点已获 M 复审关闭；第四轮已修订 R6-b-parent：失效 Geo 父范围不能登记绑定新 native 状态的子请求。窄回归与新 ARM64 绑定已获 M 实现复审通过，当前提交前整理/本地集成中；历史版本和结论分轮保留。尚未完成本地提交或合入 `security/android`。首轮版本与结论单独保留为历史事实。范围与失败语义以[设计](l1_t03_plan.md)为准，任务状态见[任务清单](loop1_tasks.md#l1-t03-修改请求出口与生命周期处理)。

## 当前修订状态与接续

D-02 在 `security/l1-t03-requests`、父基线 `75ef510` 上继续首轮反馈；设计与本地合成网络、生成、分析、构建授权持续有效。M 负责获评通过且本地合入后的父仓库普通推送；最终集成须保留 `security/android` 的 `0ce19bf` 及其父 `0551f20`。未安装或启动应用，不改宿主网络，不使用真实订阅或外部测试目标，核心仓库无远端写授权。

| 项目 | 当前处理与结论 | 验证入口 |
| --- | --- | --- |
| R6-b-parent | 第四轮已获 M 实现复审关闭：子 Begin 在登记临界区先验父原资格；prepared 未 flush 与已关闭父申请均不改动较新同 key 范围 | [真实 Geo batch/HTTP 回归](../../../../core/app_request_review4_test.go)：旧源码稳定复现两个目标请求；修复后零请求，五种失效父上下文不能推进操作代际/替换 latest/关闭新连接；新实际 HTTP 完成 |
| R6-a | 已获复审关闭；仅 appDirectProxy 的精确对象身份、明确 DIRECT 范围且非 Strict Proxy 取得配置身份例外；资格、BeforeDial 和 socket 门保留 | [真实配置 Direct 回归](../../../../core/app_request_review3_test.go)：ParseRawConfig 产生并安装独立 DIRECT map，经实际私有认证 HTTP 覆盖运行中显式 Direct、停用手动维护、明确 DIRECT 诊断；配置 Direct/COMPATIBLE/私有 Direct 的 Strict Proxy 及 socket 拒绝仍成立 |
| R6-b | 原通知问题已获复审关闭；单资源捕获原 Completion（Spec、native 版本），批次先登记既有 registry 父范围；通知消费时原版本/操作资格与 epoch 写入同一短内部临界区 | [真实 Geo 交错](../../../../core/app_request_review2_test.go)：同 Owner/URL，仅 stop→resume revision 或 process epoch 变化，单资源及 batch 旧通知不影响新 Auto 实际 IO 范围；同 key 更新操作过代际拒绝，当前有效通知生效；不取消已 grant 本地段来替代通知判断 |
| R6-b-compat | 已获复审关闭；BeginHook 未安装时恢复原有无条件 Geo 路由刷新，不以 Owner{} 拒绝 | [无 hook 回归](../../../../core/app_request_review3_test.go)：真实 HTTP 下载、验证和 MMDB 替换后 epoch 增加；未展开其它平台构建 |
| R9 | 已获复审关闭；票据冻结确认时 processEpoch/revision；开始前、排队后均核对；最终 begin 使用原票据 ExpectedState | [真实编辑页/排队回归](../../../../test/common/request_scope_test.dart)：仅 native stop/SSID/epoch 改变时，旧 timer 零 begin/IO；排队窗口改版本也不借新值，新手动维护成功；[Go 最终申请反例](../../../../core/app_request_review3_test.go)拒绝旧 ExpectedState |

R1–R5、R7、R8、Q1、R6-c、R9 来源/局部字段和 R10 已获审部分沿用；本轮组合回归保留了这些受影响入口。没有宣称设备或全部矩阵通过。

R6-b-parent 已获 M 实现复审关闭，其余已闭合项沿用；当前按收尾规范整理、提交与本地集成。无需要用户决定的阻塞，设备限制保持不变。

本次压缩后误答历史问题并结束，未达到完整交评或真实阻塞出口。已在项目 `AGENTS.md` 及 `.agents/rules.md` 加入恢复时核对任务/交接/实际 checkout、回答插话后续做及结束前检查；未改通用 skill。预防效果须待自然恢复观察，当前尚未验证，不保证模型永不偏离。

## 收尾与本地集成

第四轮冻结父 tree `bf011e434af20d70166cbf9e05cb5f76b144710d`、源码 patch SHA-256 `bcef2e8b0c6a295618b4bd074930c4e2a9a918c829843ad367ec0fcc415ee731` 已获 M 实现复审通过。收尾不改变获审生产代码或生成结果；补充贡献指南的任务专用父推送约定，清理本记录多余空行，并在既有 .gitattributes 对该精确 source.patch 路径关闭源码空白检查（原始 diff 的 context 前缀不是代码缩进，载体字节保持不变）。最终提交、集成结果和源码/制品等价关系在本节接续记录，历史各轮结果保持原对象。

- 结构核对：围绕 Dart Request/Session 与数据提交、Go registry/lease/dialer、Android 网络事实与 ServiceState/socket gate 的职责及调用关系，未发现本任务引入、需要阻止提交的结构问题；没有借收尾增加生产 refactor。
- 格式：Dart 700 文件零改动，注释密度和差异空白检查通过。Markdown 初检有 564 项 MD013 行宽提示及 3 项多空行；多空行已修，保留既有长表格/中文段落行宽，在本地配置排除 MD013 后 7 份手写文档其它规则零问题。不声称默认全规则通过。
- 集成准备：目标 `0ce19bf` 仅新增 `0551f20` 的持续父仓库推送政策及两份 skill 同步文件；贡献指南三方合并保留默认 `--recurse-submodules=check`，并记录本任务完整 carrier/公开基线恢复核验后的 `--recurse-submodules=no` 普通父推送例外。仅 M 推送，核心远端写权限未扩大；两份 skill 与 Meteor 源字节一致。
- 证据保留：正式 carrier/恢复脚本与最小合成 TLS 回归夹具随源码纳入；各轮原始证据、APK、未剥离符号、mapping 和收尾材料继续保存在本地忽略目录 `build/verification/l1-t03/`，不入库。

## 第四轮验证与产物（revision4）

本轮仅改变包装层 [begin](../../../../core/app_requests.go) 的父资格登记边界，新增[窄回归](../../../../core/app_request_review4_test.go)，并同步 Plan/Tasks/本记录。登记锁内先检查调用 context 是否取消，再检查其中已有 lease 的 registry 身份、原 native 版本、登记/关闭、用途及未 grant 资格；不调用会重取 registry 锁的 Check。拒绝发生在任何操作代际推进、latest 替换或关闭较新范围之前；不改变已 grant 有限本地段的完成语义，也不扩展 Completion 的能力。

原始证据保留在本地忽略目录 `build/verification/l1-t03/revision4/`；完整运行参数见[命令记录](../../../../build/verification/l1-t03/revision4/commands.json)。

| 配置与入口 | 实际结果与限制 |
| --- | --- |
| 原源码反例 | 用 Go overlay 仅替换为第三轮父 tree `c2620502ca7ed649b915b77f70567be89015e58b` 的 app_requests.go；[按预期失败](../../../../build/verification/l1-t03/revision4/go_parent_before_fix.log)：同 Owner/started、仅 native/network revision 变化且 prepared 未 flush 的旧 Geo batch 产生 2 个真实 loopback 请求；五种旧父登记也均误成功 |
| 修复后父子边界 | [请求回归](../../../../build/verification/l1-t03/revision4/go_final_suite.jsonl)证明同一窗口旧 batch 的两个子 Begin 拒绝、目标零请求、操作/登记无变化；closed 未 cancel、cancelled、单独 context 取消、prepared 未 flush、granted 五种父范围均不影响已持有真实连接的新同 key 子范围，后者 HTTP 实际完成 |
| Go 受影响组合 `-race` | 请求/诊断 64 顶层、含子用例共 87 通过；独立跳过 Dart 桥接专用 1 例，该例在下行实际运行。[配置/路由 21](../../../../build/verification/l1-t03/revision4/go_config_route.jsonl)、[parser/Geo timer 2](../../../../build/verification/l1-t03/revision4/go_internal.log)通过；父子反例、当前有效 batch 多资源完成/取消继承及原 Completion 交错[另重复三轮](../../../../build/verification/l1-t03/revision4/go_parent_repeat.log)通过，无 race 报告。计数见[摘要](../../../../build/verification/l1-t03/revision4/test_summary.json)，不重复相加 |
| Dart 请求范围 | [24 再次通过](../../../../build/verification/l1-t03/revision4/flutter_request_scope.log)，包括实际 Dart-spec→Go registry 桥接；native 平台为替身、网络为真实 loopback。第三轮 300 组合保留为历史结果，本轮未重跑全组合 |
| ARM64 release | [本轮构建](../../../../build/verification/l1-t03/revision4/apk_release.log)完成，Go/JNI、Kotlin、Flutter、R8 与打包通过，锁定依赖；Go Build ID 相对第三轮已改变。未安装或启动 |

| 对象 | 第四轮绑定 |
| --- | --- |
| 父候选 | 基线 `75ef51024ae543864382f8ced679d38edd53f343`，完整源码 patch、候选 tree、摘要及相对第三轮增量见[review binding](../../../../build/verification/l1-t03/revision4/review_binding.json)；未提交或合入 |
| APK | [本轮 APK](../../../../build/verification/l1-t03/revision4/artifacts/FlClash-0.8.99-android-arm64-v8a.apk)，`com.follow.clash.dev`，实际 `0.8.99` / `2026102301`，dev / release / ARM64、Android Debug 签名；SHA-256 `596f69b2208af9b0d8c64eaf7ef6f81949357d8882486e5d8b80fdfb52b31c5b` |
| 构建输入 | [前](../../../../build/verification/l1-t03/revision4/build_inputs_before.json)/[后](../../../../build/verification/l1-t03/revision4/build_inputs_after.json)完全相同，摘要 `023d74eaf225c2e53dedbcb415583280febcf4d2827052bfdf8ecb4c8ef99080`；交评前再核对输入全集及新增/删除，见 review binding |
| 符号与核心材料 | [产物检查](../../../../build/verification/l1-t03/revision4/artifact_inspection.json)确认 Go/JNI 未剥离库有 debug sections，Build ID 与新包对应，R8 mapping 同目录；[核心复用核对](../../../../build/verification/l1-t03/revision4/core_reuse.json)确认候选 `2b8c0e2e7e437efa9382016765c26883bcdcded4`、tree `28734038b58367ad5e0215a7388b84daea33337e`、所有工作文件及三项恢复材料未变，本轮 `--check` 通过，复用第三轮独立恢复/缓存入口/实际 Native Assets 依赖证据 |

Dart/model/provider/schema、Kotlin、恢复脚本和 hooks 源码均未变，沿用第三轮生成/分析/格式及第一轮 JVM 30/23/71、恢复单测 8、hooks 43 的原对象结果；本轮未重建核心材料、重跑无关平台或远端 CI。真实设备/JNI、外部出口及防复发效果的限制仍保留。

## 第三轮验证与产物（revision3）

以下为第三轮已交评对象与当时结果；完成通知资格等四点已闭合，后续仅申请阶段 R6-b-parent 需修订。本轮证据位于本地忽略目录 `build/verification/l1-t03/revision3/`，各行不重复相加。

| 配置与入口 | 实际结果与证据 |
| --- | --- |
| 正常生成后的 Dart 受影响组合 | [300 通过](../../../../build/verification/l1-t03/revision3/flutter_final_suite.log)，含三种 native 版本变化、排队窗口、新手动 Direct 及既有 source/restore/DAV/生命周期回归；native/Setup 为替身，真实 loopback IO、SQLite 和 UI 动作实际执行 |
| Go 请求/诊断 `-race` | [62 顶层、含子用例共 80 通过](../../../../build/verification/l1-t03/revision3/go_final_suite.jsonl)，独立跳过桥接专用 1 例，该例在 Dart 中实际调用；无 race 报告 |
| Go 配置/路由与核心消费者 | [配置/路由 21](../../../../build/verification/l1-t03/revision3/go_config_route.jsonl)、[parser/Geo timer 2](../../../../build/verification/l1-t03/revision3/go_internal.log)通过；关键组[另重复三轮](../../../../build/verification/l1-t03/revision3/go_concurrency_repeat.log)通过，无 race 报告 |
| 生成、分析、格式 | [正常 build_runner](../../../../build/verification/l1-t03/revision3/codegen.log)、[lib/新增测试分析](../../../../build/verification/l1-t03/revision3/analyze_clean.log)零问题；[全仓库 analyze](../../../../build/verification/l1-t03/revision3/flutter_analyze.log)无 error/warning、既有 42 info；[680 文件格式检查](../../../../build/verification/l1-t03/revision3/format_check.log)通过 |
| ARM64 release | [构建完成](../../../../build/verification/l1-t03/revision3/apk_release.log)，锁定依赖、Go c-shared、Kotlin/JNI、R8 与打包通过；未安装/启动 |

通知资格复用现有 owner、StateVersion、Spec 与 operations map；仅 Geo/geo-batch 的内部固定 key 保存通知所需操作代际。Completion 是通知快照，不授予新网络/保存能力，也不延长 lease/receipt。批次父范围先于子资源登记，撤销其 context 防止同一旧批次在新 native 版本借身份继续。路由依赖在 registry 锁外读取，短内部写区为 selectMu→registry→routeTracker；释放 registry 后才取消 socket/发表通知，没有 registry→selectMu 等待或持锁外部/JNI 调用。

核心候选 `2b8c0e2e7e437efa9382016765c26883bcdcded4`、tree `28734038b58367ad5e0215a7388b84daea33337e`，唯一 parent 仍为公开基线 `8597778c7df410ebe88c57e59eaab32d203156df`。当前[manifest](../../../../core/patches/l1_t03/manifest.json)、完整材料与父 index gitlink 对应此候选；[独立恢复](../../../../build/verification/l1-t03/revision3/independent_recovery.json)重建相同对象，baseline bare 恢复前后均无候选。[缓存入口检查](../../../../build/verification/l1-t03/revision3/source_cache_check.json)通过。

| 对象 | 第三轮绑定 |
| --- | --- |
| 父候选 | 基线 `75ef51024ae543864382f8ced679d38edd53f343`；完整源码 patch、候选 tree、摘要及相对 revision2 增量见[review binding](../../../../build/verification/l1-t03/revision3/review_binding.json) |
| APK | [本轮 APK](../../../../build/verification/l1-t03/revision3/artifacts/FlClash-0.8.99-android-arm64-v8a.apk)，`com.follow.clash.dev`，实际 `0.8.99` / `2026102301`，dev / release / ARM64、Android Debug 签名；SHA-256 `d9979de4ca04cacc537247e1b16c17c867cad8b43116d32ae45986f7f15f470c` |
| 构建输入 | [前](../../../../build/verification/l1-t03/revision3/build_inputs_before.json)/[后](../../../../build/verification/l1-t03/revision3/build_inputs_after.json)完全相同，摘要 `e2748438e222d39c3ab96b9714cfbea941bbc2f66aef29682b6666a850fe5506`；交评前输入全集再比对见 review binding |
| 符号与依赖 | [检查记录](../../../../build/verification/l1-t03/revision3/artifact_inspection.json)确认 Go/JNI debug sections 与包内 Build ID、R8 mapping；实际 Native Assets [依赖声明](../../../../build/verification/l1-t03/revision3/native_asset_dependencies.json)包含本轮材料 |

Kotlin、恢复脚本和 setup_hooks 生产代码未变，继续复用 revision1 JVM 30/23/71、恢复单测 8、hooks 43 的获审绑定；本轮新核心材料独立重建与缓存声明另验，Android wiring 由新 APK 再编译。未观察设备/JNI/实际外部出口，未穷举矩阵，防复发效果仍未自然验证。

M 按人类要求同步了 engineering-delivery 新版入口和 lead-report（提交 `0ce19bf`），D 已重读新版入口；本轮父快照包含这两份更新，归属 M。它们不属于编译输入，运行产物继续复用上述绑定，不据此重建或补跑未变验证。

## 第二轮验证与产物（revision2）

以下为第二轮已交评对象与当时结果；上述四点是其后续复审未闭合项。

### 当时处理记录

| 项目 | 本轮处理 | 真实消费者验证 |
| --- | --- | --- |
| R6-a | URLTest 登记实际节点、所属 provider 引用/版本与组依赖；provider 列表/版本更新与 grant 共用 selectMu 并主动通知。Fallback 选择写入与网络 probe 分开锁段，保留上游 Set 行为 | [Go 回归](../../../../core/app_request_review2_test.go)：手动及 HealthCheck 经真实 HTTP 代理，provider 同名替换后旧 socket 关闭，alive/history/extra/hook 不变；watch 关闭 |
| R6-b | 单资源/批次通知携带原 Owner 与来源 URL；通知与 Owner 更换在同一选择锁下核对 | [Go 回归](../../../../core/app_request_review2_test.go)：部分成功→Owner 切换→真实新 Auto 请求→旧 batch 退出，epoch/新 scope 不变；真实单资源延迟通知同样拒绝，来源过时拒绝，当前有效通知仍推进 epoch |
| R6-c | grant/check 与相关依赖读取统一 selectMu→choiceMu，校验/授予同一边界；只读依赖组，不扫描无关 Selector | [Go 并发回归](../../../../core/app_request_review2_test.go)：真实 IO 后循环 control check、grant 与无关组切换；相关选择撤销及真实 Fallback 回归一并保留 |
| R9 | 确认持久化的同一修改区捕获已有 dataset/key 来源及操作资格；delay 前核对并保留原资格，缺行淘汰 | [真实编辑页回归](../../../../test/common/request_scope_test.dart)：确认→删除/同 ID 同元组 restore/同来源 importFile 后无 begin/IO/复活/覆盖；仅 group/unfold 仍可刷新并保留字段；较新 URL/Proxy/target 和首次导入回归保留 |
| R10 | 同一来源不重建 DAVClient，resume 只重开 ping 与 run ID；来源替换/dispose 保持完整关闭 | [真实 DAV IO 回归](../../../../test/common/request_scope_test.dart)：并行 PUT、GET、ping 经 hide/resume 后旧 ping 取消、新 ping 成功，原业务 scope 未撤销且实际完成 |

本轮证据位于本地忽略目录 `build/verification/l1-t03/revision2/`；各行不重复相加。

| 配置与入口 | 实际结果与证据 |
| --- | --- |
| 正常生成后的 Dart 受影响组合 | [296 通过](../../../../build/verification/l1-t03/revision2/flutter_final_suite.log)，覆盖本轮五项新用例及既有兼容；native/Setup 为替身，真实 IO、SQLite、restore/importFile、UI 确认和队列行为实际执行 |
| Go 请求/诊断 `-race` | [58 顶层、含子用例共 70 通过](../../../../build/verification/l1-t03/revision2/go_final_suite.jsonl)，独立跳过桥接专用 1 例，该例由 Dart 实际调用；无 race 报告 |
| Go 配置/路由及核心消费者 `-race` | [配置/路由 21](../../../../build/verification/l1-t03/revision2/go_config_route.jsonl)、[核心 parser/Geo timer 2](../../../../build/verification/l1-t03/revision2/go_internal.log)通过；关键并发/取消组[另重复三轮](../../../../build/verification/l1-t03/revision2/go_concurrency_repeat.log)通过，无 race 报告 |
| 生成、分析与格式 | [正常 build_runner](../../../../build/verification/l1-t03/revision2/codegen.log)、[lib/新增测试分析](../../../../build/verification/l1-t03/revision2/analyze_clean.log)零问题；[全仓库 analyze](../../../../build/verification/l1-t03/revision2/flutter_analyze.log)无 error/warning、既有 42 info；[680 文件格式检查](../../../../build/verification/l1-t03/revision2/format_check.log)通过 |
| ARM64 release | [构建完成](../../../../build/verification/l1-t03/revision2/apk_release.log)，锁定依赖、Go c-shared、Kotlin/JNI、R8 与打包通过；未安装/启动 |

组合运行曾暴露正向 UI 测试退出时未排空 fake async 的共享写队列，污染后续用例；夹具改为等待可观察的网络提交及队列结束后，上述最终组合全部通过。未重置生产队列或删减断言来处理该问题。

核心候选 `aa43d56b4e953b25aba58a91c874e6c5aebb12e2`、tree `2c0238ec1fcddd2886f07759e8e88f66a2bc2f6a`，唯一 parent 仍是公开基线 `8597778c7df410ebe88c57e59eaab32d203156df`。[第二轮本地 manifest](../../../../build/verification/l1-t03/revision2/core_carrier/manifest.json)及材料保留，原 gitlink 已取代；[独立恢复](../../../../build/verification/l1-t03/revision2/independent_recovery.json)已重建相同对象，候选未进入基线 bare 库。

本轮未修改 Kotlin、恢复脚本或 setup_hooks 生产代码，沿用 revision1 的 JVM 30/23/71、恢复单测 8、hook 单测 43 及其已绑定对象结论；新核心材料单独验证恢复与缓存依赖，Android wiring 由新 APK 再编译。

| 对象 | 本轮绑定 |
| --- | --- |
| 父仓库候选 | 基线 `75ef51024ae543864382f8ced679d38edd53f343`；候选 tree、完整源码 patch 与摘要见[review binding](../../../../build/verification/l1-t03/revision2/review_binding.json)，相对 revision1 的增量 patch 同目录保留 |
| APK | [本轮 APK](../../../../build/verification/l1-t03/revision2/artifacts/FlClash-0.8.99-android-arm64-v8a.apk)，`com.follow.clash.dev`，实际 `0.8.99` / `2026102301`，dev / release / ARM64、Android Debug 签名；SHA-256 `23175d1c06559afd8c8ec237e021f6667c411c8697e6c425b61d3eb57f62869a` |
| 构建输入 | [前](../../../../build/verification/l1-t03/revision2/build_inputs_before.json)/[后](../../../../build/verification/l1-t03/revision2/build_inputs_after.json)完全相同，摘要 `891e26e04a528b989170bad62077a49d34f66b9524f512aae48603a36dbe9159`；交评时输入全集再次比较，结果见 review binding |
| 符号与恢复 | [检查记录](../../../../build/verification/l1-t03/revision2/artifact_inspection.json)核对 Go/JNI debug sections 与包内 Build ID，R8 mapping 同目录；[独立恢复](../../../../build/verification/l1-t03/revision2/independent_recovery.json)与[缓存入口检查](../../../../build/verification/l1-t03/revision2/source_cache_check.json)通过，实际 Native Assets [依赖声明](../../../../build/verification/l1-t03/revision2/native_asset_dependencies.json)包含新材料 |

## 第一轮修订历史（revision1）

以下为上一交评包的真实对象与结果。M 复审认可未受影响部分，同时提出本轮五项未闭合交互；它们不被下列已通过用例覆盖。

### 上轮处理记录

| 项目 | 修订结果 | 实际验证入口 |
| --- | --- | --- |
| R1 | 运行中 ready 的明确 Direct 通过真实资格谓词；停用/暂停自动维护仍拒绝 | [Dart spec→Go 桥接测试](../../../../test/common/request_scope_test.dart)实际调用 `TestAppRequestDartSpec`，覆盖运行中手动/自动与停用手动，停用自动在 Dart 拒绝 |
| R2 | 无显式 scope 的 URLTest 自建范围，Proxy 与延迟 parser 都捕获构造时 owner；取消不写 alive/history/extra/hook | [真实 Fallback.Set](../../../../core/app_request_revision_test.go)等待 HTTP 后撤销、核对历史及旧对象零新请求；[旧 parser owner](../../../../core/Clash.Meta/adapter/provider/request_owner_test.go)回归 |
| R3 | 持有同一 tunLock 核对 owning service 后释放 TUN 并关闭业务 listener，旧服务不能停止新服务 | [真实混合端口清理测试](../../../../core/app_request_revision_test.go)核对 isRunning、业务端口关闭及私有维护端口保留；本轮 APK 已编译实际 Android wiring |
| R4 | native publication revision 与 network source revision 分开，门使用真实 source revision | [状态机测试](../../../../android/tests/app/ServiceStateMachineTest.kt)真实 observeNetwork→gate，覆盖 1→3→2→4 与来源 epoch 重建 |
| R5 | 命名 NTP 使用实际代理 UDP；读完整 datagram 后交给 NTP 解码；缺名失败，撤销关闭关联并拒绝迟到 offset | [SOCKS UDP/NTP 测试](../../../../core/app_request_revision_test.go)真实 UDP-ASSOCIATE、UDP 报文、offset，以及缺失代理零 Direct UDP |
| R6 | 按实际节点、组、provider 依赖失效；固定 Direct/无关节点不受其它组选择影响；Geo batch 结束才发表整体变化；初次错误保留定时器 | [真实路由/Geo notify 测试](../../../../core/app_request_revision_test.go)覆盖相关/无关组、相同配置不撤销和真实来源变化撤销；[定时重试测试](../../../../core/Clash.Meta/component/updater/request_scope_test.go)首次 HTTP 503 后真实后续 tick 成功 |
| R7 | Strict 首次展开触碰/推进一次并固定终端，重复访问同一 scope 不再推进 | [真实 round-robin 测试](../../../../core/app_request_revision_test.go)跨四个 scope A→B→A→B，lazy Touch 恰四次 |
| R8 | 仅首次确实无代理的 Proxy 导入提供一次 Direct 许可，保留 Proxy 偏好；取消无请求，普通运行失败无提示；持久化后仅通知仍存活 provider | [真实 Profile/Script 导入测试](../../../../test/common/request_scope_test.dart)经实际弹窗、loopback IO 与 SQLite 保存，覆盖接受/拒绝/普通失败 |
| R9 | URL 确认先落库，延迟刷新须来源仍匹配；局部 UI 字段在写队列中读取最新 Profile | [真实编辑页测试](../../../../test/common/request_scope_test.dart)保存旧 URL 后排队写较新 URL/Proxy/target 与组字段，确认全部保留且旧延迟刷新零请求 |
| R10 | 隐藏即取消在途诊断、DAV ping 及其 run ID；恢复另开范围；背景订阅保持原政策 | [真实 socket 隐藏/恢复测试](../../../../test/common/request_scope_test.dart)核对旧 IO 关闭、迟到结果不变 fresh、恢复新范围，配合既有诊断和备份回归 |
| Q1 | 明确 CREATE 不含新列的 schema10 表后运行真正迁移，旧记录及旧 DAV 备份默认 Auto | [迁移与旧备份测试](../../../../test/database/request_mode_migration_test.dart)先断言列缺失，再走 Drift 10→11 和真实备份归档读写 |

### revision1 实际验证

以下均针对修订后源码；分批与重叠结果不相加。测试输出和脚本保留在本地忽略目录 `build/verification/l1-t03/revision1/`。

| 配置与入口 | 结果 | 证据及边界 |
| --- | --- | --- |
| 正常生成后的 Dart 受影响套件及生命周期兼容 | 291 通过 | [完整日志](../../../../build/verification/l1-t03/revision1/flutter_generated_final.log)，含实际编辑/导入、HTTP/HTTPS、隐藏诊断/DAV、SQLite/旧备份、路由、action/tile/启动按钮；native 为替身，R1 另桥接真实 Go 谓词 |
| Go 请求与诊断 `-race` | 54 顶层通过，含子用例共 64；独立执行跳过桥接专用 1 例 | [JSONL](../../../../build/verification/l1-t03/revision1/go_final_suite.jsonl)；桥接专用例由上行 Dart 实际调用，未算入本行通过数；无 race 报告 |
| Go 配置与路由兼容 `-race` | 21 顶层通过，无跳过 | [JSONL](../../../../build/verification/l1-t03/revision1/go_config_route.jsonl)，无 race 报告 |
| 核心 parser 与 Geo 定时器 `-race` | 2 顶层通过 | [日志](../../../../build/verification/l1-t03/revision1/go_internal_final.log)，使用父模块实际依赖图，无 race 报告 |
| JVM common / service / app | 30 / 23 / 71 通过，无失败/跳过 | [日志](../../../../build/verification/l1-t03/revision1/jvm_final.log)、[计数](../../../../build/verification/l1-t03/revision1/jvm_test_counts.json)及保留 XML；未变模块由 Gradle 复用结果 |
| 源码恢复与构建 hook | Python 8、Dart 43 通过 | [恢复测试](../../../../build/verification/l1-t03/revision1/source_restore_tests.log)、[hook 测试](../../../../build/verification/l1-t03/revision1/setup_hooks_tests.log)；恢复脚本未改，重新验证新材料的独立还原见下文 |
| 正常生成与分析 | 通过 | [build_runner](../../../../build/verification/l1-t03/revision1/codegen.log)、[lib/新增测试零问题](../../../../build/verification/l1-t03/revision1/analyze_clean.log)、[hook 分析](../../../../build/verification/l1-t03/revision1/setup_hooks_analyze.log)；[全仓库分析](../../../../build/verification/l1-t03/revision1/flutter_analyze.log)无 error/warning，既有测试 42 条未等待 Future 的 info |
| ARM64 release 构建 | 通过 | [构建日志](../../../../build/verification/l1-t03/revision1/apk_release.log)，包括锁定依赖解析、Kotlin、Go c-shared、JNI/C++、R8 与打包；未安装/启动 |

### revision1 源码与产物绑定

核心候选 `568aaa50703b189258be1461e3c4c0ac2fcd15d6`，tree `ba2854f61d06afc4d20e5cd059d4ce61cc276cfa`，唯一 parent 为公开基线 `8597778c7df410ebe88c57e59eaab32d203156df`。[上轮本地 manifest](../../../../build/verification/l1-t03/revision1/core_carrier/manifest.json)、同目录完整 patch 和 commit 材料保留；分支 HEAD 未移动，原 gitlink 已由本轮候选取代。

[独立还原](../../../../build/verification/l1-t03/revision1/independent_recovery.json)使用仅含公开基线的 bare repository 重建相同 tree/commit，基线库恢复前后均无候选对象。[缓存入口检查](../../../../build/verification/l1-t03/revision1/source_cache_check.json)通过真实 GoBuilder 和计数缓存替身证明损坏材料在内层缓存入口前拒绝。

| 对象 | 本轮绑定 |
| --- | --- |
| 父仓库候选 | 基线 `75ef51024ae543864382f8ced679d38edd53f343`，完整 binary snapshot、候选 tree 与 SHA-256 见本地[review binding](../../../../build/verification/l1-t03/revision1/review_binding.json)，覆盖实现、生成物、测试、项目规则和任务文档 |
| APK | [本轮保留 APK](../../../../build/verification/l1-t03/revision1/artifacts/FlClash-0.8.99-android-arm64-v8a.apk)，`com.follow.clash.dev`，实际 `0.8.99` / `2026102301`，dev / release / ARM64、Android Debug 签名 |
| APK SHA-256 | `c4f494507a1cfec77c48276863263922faa33348d70c7227d19ffa847fac74c2` |
| 构建输入 | [前](../../../../build/verification/l1-t03/revision1/build_inputs_before.json)/[后](../../../../build/verification/l1-t03/revision1/build_inputs_after.json)完全一致，文件摘要 `311c874bbe40d7a127034afcdf33dc2cd6fc26668cc8ccf762bf3e459ea97814`；之后仅更新文档，runtime 比对见 review binding |
| 符号 | APK 同目录保留 `libclash.so`、`libcore.so` 和 R8 `mapping.txt`；[检查记录](../../../../build/verification/l1-t03/revision1/artifact_inspection.json)确认 debug sections 与包内 Go/JNI Build ID 匹配 |
| 外层构建依赖 | [实际 Native Assets 输出](../../../../build/verification/l1-t03/revision1/native_asset_dependencies.json)包含 manifest、patch、commit、恢复脚本和 `.gitmodules` |

## 首轮历史记录

### 首轮记录的行为

- 订阅、远程脚本与 WebDAV 的高级设置提供 Auto、Proxy、Direct；旧数据为 Auto，未知模式拒绝解析。首次 URL 导入在请求前显示设置，保存不存在的代理名称也不会改用 Direct。
- Android 每次操作取得私有 loopback 代理凭据，HTTP/HTTPS 使用同一资格；停止、网络或来源变化会关闭旧连接。运行失败不会触发 Direct 回退；缺少首次资源时需接受一次操作的 Direct 恢复许可。
- 原生服务在配置、下载与权限等待前登记意图，同一 token 提交启动。网络事实、服务实例与保护代次进入实际 socket 门；逐次检查保护、物理网络绑定及其后的状态。
- provider、Geo、URLTest、NTP 和 Go 诊断使用捕获的 owner 与操作范围。保存由原生 registry 授予有限本地段，Dart 共用非重入队列并等待文件、数据库和偏好写入；恢复失败会补偿，补偿失败则保留工作目录并禁止继续自动应用。
- 配置和原生偏好读取期间阻止新的前端提交；等待配置锁时释放读取资格。该门只处理本地读取与提交互斥，不延伸为业务配置全资源事务。

### 首轮受测对象与产物

首轮父仓库基线为 `75ef51024ae543864382f8ced679d38edd53f343`，受检对象为该基线上的首轮本地候选快照。首轮核心 commit 为 `2c28a9ff68d0be3d69ad70fbdc5fb494c2d57884`，完整 tree 为 `fbd943996257b48e973c68023ac3052157ac90b8`，唯一 parent 为公开基线 `8597778c7df410ebe88c57e59eaab32d203156df`；已被本轮候选取代。

| 对象 | 本地入口或绑定 |
| --- | --- |
| 首轮源码恢复材料 | [本地历史 manifest](../../../../build/verification/l1-t03/implementation/core_carrier_first/manifest.json)，同目录保留首轮完整 binary patch 与原始 commit；标准恢复入口仍为[恢复脚本](../../../../tool/restore_l1_t03_core.py) |
| APK | [保留 APK](../../../../build/verification/l1-t03/artifacts/FlClash-0.8.99-android-arm64-v8a.apk)，`com.follow.clash.dev`，`0.8.99` / `2026102301`，Android Debug 签名，release / ARM64 |
| APK SHA-256 | `3b2f4155d3f6c38aba58fb18900a0690b4654cee216e2e6922d220a970a7bc2e` |
| 构建绑定 | [构建前输入](../../../../build/verification/l1-t03/implementation/build_inputs_before.json)与[构建后输入](../../../../build/verification/l1-t03/implementation/build_inputs_after.json)完全一致，摘要 `e128d331e1eb609464a36b2f903cf7438b412093584da9bb0d9131398ba1d867`；之后仅增加或调整测试与结果文档 |
| 本地符号 | APK 同目录保留 `libclash.so`、`libcore.so` 和 `mapping.txt`；[检查结果](../../../../build/verification/l1-t03/implementation/artifact_inspection.json)记录未剥离库的 debug sections、与包内库相同的 Build ID 和摘要 |

### 首轮实际验证

各行独立计数，Go 子用例不另算顶层用例；不将分批执行或重叠的旧结果相加。

| 配置与入口 | 结果 | 证明的范围 |
| --- | --- | --- |
| Dart 请求、对象/schema、保存/恢复、路由、诊断 provider、WebDAV 和四语言界面 | 227 通过 | [最终日志](../../../../build/verification/l1-t03/implementation/flutter_final_suite.log)：真实 loopback HTTP/HTTPS、CONNECT 凭据隔离、撤销与有限提交、文件补偿、旧数据与未知模式、实际 SQLite 和界面 |
| Dart action、tile、启动按钮兼容 | 46 通过 | [最终日志](../../../../build/verification/l1-t03/implementation/flutter_lifecycle_final.log)：更新后的异步 API、服务请求与 desktop 既有生命周期用例；测试替身随实际持久化语义调整 |
| Go 请求与诊断，`-race` | 45 顶层用例通过，含子用例共 53；无 race 报告 | [最终 JSONL](../../../../build/verification/l1-t03/implementation/go_final_suite.jsonl)：实际 socket gate、私有 HTTP、真实 HTTP 代理跳点、嵌套/过滤后 Direct 拒绝、provider/Geo 文件、URLTest 历史、NTP UDP/offset、排队/多源探测取消 |
| JVM common / service / app | 30 / 23 / 70 通过，无失败、跳过 | [计数](../../../../build/verification/l1-t03/implementation/jvm_test_counts.json)、[服务回归](../../../../build/verification/l1-t03/implementation/jvm_tests_current.log)、[socket 门回归](../../../../build/verification/l1-t03/implementation/jvm_socket_gate.log)：真实状态机和门算法，平台/JNI 操作使用替身 |
| 源码恢复脚本 | 8 通过 | [日志](../../../../build/verification/l1-t03/implementation/source_restore_tests.log)：完整 binary tree/commit、仅公开基线重建、材料损坏/缺失、错误 gitlink、额外 parent、已有改动与被忽略源码均拒绝 |
| 独立真实核心恢复 | 通过 | [记录](../../../../build/verification/l1-t03/implementation/independent_recovery.json)：只含公开基线的 bare repository 在恢复前后均无候选对象，另一 checkout 从材料重建相同 tree/commit |
| 构建 hook 与缓存 | 43 通过；材料失效在内层缓存入口前拒绝；实际外层依赖含材料 | [hook 日志](../../../../build/verification/l1-t03/implementation/setup_hooks_tests.log)、[内层入口检查](../../../../build/verification/l1-t03/implementation/source_cache_check.json)、[Native Assets 依赖](../../../../build/verification/l1-t03/implementation/native_asset_dependencies.json)；入口检查使用只计数的缓存替身 |
| 静态分析、生成与构建 | 通过 | `flutter pub get --enforce-lockfile`、正常模型/DB/l10n 生成、[lib/新增测试分析](../../../../build/verification/l1-t03/implementation/analyze_clean.log)、[hook 分析](../../../../build/verification/l1-t03/implementation/setup_hooks_analyze.log)、全仓库 `flutter analyze --no-fatal-infos` 无错误/警告；现有测试有未等待 Future 的提示；[ARM64 构建](../../../../build/verification/l1-t03/implementation/apk_release.log)完成 Kotlin、Go c-shared、JNI/C++、R8 与打包 |

## 复现与体验

源码准备及构建前提见 [Android 构建指南](../../../development/android_build_guide.md#构建前准备)。恢复脚本先校验公开基线与材料，再恢复候选 gitlink；不能用普通 recursive checkout 假定未推送对象已可取得。CI 已改为先恢复，再初始化其余子模块，未触发 CI。

原始输出与本机运行脚本保留在 `build/verification/l1-t03/` 忽略目录，当前本轮证据为其 `revision3/` 子目录。测试使用 `flutter_test.py` 暂时关闭本机 Go Native Assets hook，保留 Rust hook，并在退出时恢复 `pubspec.yaml`；Go/JVM 单独验证。正常生成使用同方式的 `dart_command.py run build_runner build --delete-conflicting-outputs`，未手改生成物；生成语言文件随后经 `dart format` 格式化，680 份 lib/test 文件格式检查通过。ARM64 构建使用 `android_command.sh build`，与本地合成测试分开执行。完整命令和产物校验以本地证据目录为准。

APK 尚未安装或启动。获准设备验证后，可在订阅编辑、脚本 URL 导入、WebDAV 表单展开高级设置，分别选择三种模式并观察停止/恢复行为；当前 APK 只作为可检查的编译产物交接。

## 未证明的范围

- 未创建设备 TUN、系统代理或改变宿主网络；未安装、启动 FlClash，未使用真实订阅或外部测试目标，未上传源码、日志、APK 或触发远端构建。
- JVM 替身与 Go loopback 不能证明真实 Android 权限、Always-on、revoke、其它 VPN、lockdown、系统 Network 回调顺序和物理网卡出口已经通过设备观察。编译/链接证明接口可构建，不等于真实 JNI/MethodChannel 并发验证。
- 未运行全部测试、跨平台构建、远端 CI，也未穷举设计矩阵的全部交错、304/失败注入组合和 UI 操作。已执行的精确范围见上表，不将源码检查或相邻用例写成未运行用例通过。
- 已授予的有限本地段可完成或补偿；撤销及 Dart 通知有传播延迟，不承诺瞬时跨文件/数据库/偏好原子取消。崩溃后标记用于停止继续应用并保留恢复依据，不承诺通用跨资源崩溃事务。
- 扫码 SDK 的独立网络路径仍由 L1-T09 处理；本项不证明全应用无外发。TLS/身份、日志脱敏、IP 产品决策与业务规则/DNS 的后续范围保持原阶段分工。
