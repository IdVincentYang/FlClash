# L2-T02-04 订阅、集合与资产更新：验证记录

implementation_v2 已完成 I1–I3 修订、受影响消费者自验及 ARM64 构建。
implementation_v1 未通过 M1 实现评审；implementation_v2 已通过复审，当前完成提交前整理与本地交付。
旧版冻结材料保留，未变范围复用其证据；下文区分本轮增量与复用结果。
本项交付受支持材料子集，不代表整个 L2-T02、05 或设备环境已验收。
支持契约见[材料更新设计](../managed_updates_design.md)，体验与夹具见[使用指南](../managed_updates_guide.md)。

## 受测对象与复现入口

输入基线及获审边界沿[任务方案](l2_t02_04_plan.md)。受测对象为该基线上的当前任务分支变更，
本轮源码/测试摘要映射位于本地忽略目录
`build/verification/l2-t02/subtask_04/implementation_v2/tested_sources.json`，
SHA-256 为 `eaac9a1f6773b07a2dfe93050fad67fcb58f9cc44790c8258d888e56a952b6d2`。
v2 的 `snapshot.json`、`review.patch` 和源码副本绑定本次交评对象；
`changes_from_v1.patch` 仅表达本轮增量。design_v1 与 implementation_v1 冻结内容未重写。

证据根为 `build/verification/l2-t02/subtask_04/`；本轮命令、结果与制品校验位于
`implementation_v2/`，未变的 bridge/compiler/Rust 复用 `implementation_v1/artifacts/`。
桥接程序需要本仓库的测试 fixture，按现有消费者从 `core/` 工作目录运行；不是脱离源码的安装包测试。

```bash
fixture_dir=build/verification/l2-t02/subtask_04/implementation_v1
fixture_dir="$PWD/$fixture_dir/artifacts"
FLCLASH_APPLICATION_INPUT_BRIDGE="$fixture_dir/application_input_bridge" \
  FLCLASH_MANAGED_PROFILE_COMPILER="$fixture_dir/managed_profile_compiler" \
  FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR="$fixture_dir" \
  flutter test test/providers/profile_refresh_bridge_test.dart \
  --name 'v2 |I1 |I3 '
```

命令须在仓库根启动 Flutter；测试内部为桥接子进程指定 `core/`。更广的最终选集、命令及环境见
`implementation_v2/commands.json`；旧选集见 `implementation_v1/commands.json`。
所有 URL、认证、节点及收件端均为本地合成输入，真实 ouo 未读取。

## 实际证明

| 用例 | 实际观察 |
| --- | --- |
| 明确来源与 version 1 | 真实表单保存 version 2 来源组/集合；原手工节点不自动绑定；Save 不新增选择 |
| 同模板 A→B | 模板摘要不变，inputId/材料摘要改变；业务从 A 转至认证 B，DNS 仍由指定服务收件 |
| 域名/地址集合变化 | 新域名条件把 DNS 从默认服务切到条目指定服务；新地址条件把合成 IP 从拒绝切到 B |
| 顺序与严格范围 | 保持条目位置、target/DNS/default；重复/混合/空/远程/Geo/坏引用及超限整份拒绝 |
| Request 路由/自动刷新 | Auto、Proxy、Direct 经既有 Request；自动刷新采用 B，不要求新选择确认 |
| 来源提交前失败 | 坏候选不改旧文件或日期；仍合资格 A 继续由真实 Core 提供业务 |
| 来源提交后失败 | 最终解析重新读取保存材料；候选失败时旧输入不再 replayEligible/active |
| 预览与采用 | 暂存/丢弃不改文件、日期或选择；同模板显式 Apply 采用精确暂存 B，并失效一次 |
| 并发/锁边界 | 下载取消、较新加载、CAS 冲突和原票据变化拒绝旧候选；解析等待期间可完成 mutation |
| 脚本/覆写 | 冻结的脚本文本经真实 Rust 执行器提供 B；改字节使预览过期；custom select 覆写参与两次构建 |
| 恢复/未知选择 | merge/override 的 onlyProfiles ZIP 保留版本/原身份；不匹配拒绝、草稿可修；未知选择可明确修复 |

业务结果来自独立 SOCKS5 的 A/B 响应及认证，DNS 来自独立 TCP DNS 收件计数；不是只比较 YAML 或 Sync 返回值。
新增原文档检查拒绝 YAML alias 放大和循环引用；脚本输出在 JSON 解码前检查字节预算。
最终 YAML、组选择、维护目标及材料 receipt 来自同次展开闭包。ConfigInput/T01 和 ServiceState 仍分别拥有接受与运行意图。

## 评审修订的增量验证

- **I1 选择变更**：旧手工组选择 A 时，将成员改为 B 后真实 action 采用成功，业务由 B 收件，无关 picks 保留。
  同模板刷新仍拒绝非法手工选择，动态组移除旧成员后采用新成员。
  旧版在显式采用、提交之前抛出 `PolicyDraftProblem(selectedMap)`。
- **I2 迟到加载**：真实页面 Discard A 后加载 B；A 迟到失败时 B 仍忙碌、Preview/Apply 禁用、无旧错误通知。
  B 完成才提示；日期/选择未写入，Discard 和离页使候选失效。
  旧版在 B 尚未完成时清除忙碌状态，并发布旧错误通知。
- **I3 预览资格**：末次来源核对等待中改稿，旧预览被拒绝、两稿均未获资格；重新预览得到新稿拒绝 DNS。
  真实页面解析等待中编辑后，旧完成不开 Editor、不更新已预览提示；新预览文本及资格对应新稿。
  旧版 action 返回旧预览，页面打开旧 Editor。

四个新增反例在冻结 v1 的三份生产文件上均因上述语义失败，在修订后均通过；
`action_red.log`、`widget_red.log` 保留失败，`action_race_tests.log`、`widget_race_tests.log`
及最终受影响选集保留通过结果。反例运行后已恢复 v2 文件。
页面测试使用可控 capture 返回屏障及真实临时文件/DB，隔离 UI 的完成归属；
下载会话取消及迟到来源的真实 Core/action 证据沿用原选集，不把屏障当作实际下载验证。
S1 已将指南中的控件名对齐实际 English UI：`Generated draft preview`。

## 命令、结果及环境限制

- 本轮六个受影响 Flutter suite 共 106 项通过，含四个新增反例；`implementation_v2/affected_tests.log`。
  范围为材料/选择模型、选择 action、刷新 Core bridge 及两个真实页面 suite。
  新增测试格式整理后，其页面 suite 再次 2 项通过；`widget_final.log`。
- v1 选集 229 项通过；随后只增加集合接收方用例，增量 1 项通过。
  原共 230 个不同用例，含真实 UI、DB/ZIP、刷新与 Core 桥接；未受影响的证据继续有效。原日志分别为
  `affected_tests_final.log`、`collections_consumer_tests.log`。
  新增 version 2 实际 Core 用例共 15 项。
- Go 源码/测试、严格编译器及 Rust 输入未变，复用 v1 的构建与验证。
  Go 42 个顶层测试通过，含子用例共 76 项通过，0 失败；`go_tests_final.jsonl`。
  Go 单独运行时跳过交互 bridge 与手动 fixture 两个 opt-in 入口；前者由 Flutter 实际驱动，后者另做 HTTP 阶段 smoke。
- `flutter pub get --offline` 和构建时 `--enforce-lockfile` 成功；
  v2 正常 build_runner 生成；ARB 未变，沿用 v1 的 intl 生成。
  `flutter analyze --no-fatal-infos` 成功，无 error/warning；42 个既有测试 info 保留。
- 默认 hook 的 macOS Rust 动态库出现既有 `mis-aligned LINKEDIT string pool`，
  首次 EditorPage 验证失败。
  核对旧产物的 29 个 Rust/配置输入均未变化后，指定可加载、同源码的库完成最终 UI 与真实脚本验证；
  `rust_reuse.json` 保留原始路径、原因及校验，制品目录另有同字节副本。未修改 Rust 源码或工具链。
- 首次迭代有来源 UI 尚未等待文件操作、全局 mutation 队列未退出测试 zone，以及旧刷新 fixture 清理目录竞态。
  最终用例等待控件/存储事实并清理队列；目录已被异步清除只忽略 PathNotFound，其他错误仍失败。
  断言未删除；诊断/失败日志保留，不计入最终通过。
- 手动夹具已启动并验证 A/B/bad/rename 四种 HTTP 材料和零收件初态；`manual_fixture_smoke.json`。
  没有借该 smoke 声称设备流量已通过。

## ARM64 制品与未覆盖项

最终 APK 为 `implementation_v2/artifacts/FlClash-0.8.99-android-arm64-v8a.apk`，
SHA-256 `5f7ebba3bafe58b496e2f68c7224a42febcb50ffedbb29950c32599d9d72c45c`，
57,358,098 bytes。正常构建/打包成功，上传任务禁用；`implementation_v2/android_arm64.log`。
1,027 个源码/构建上下文文件在构建前后摘要一致；APK ZIP 完整、只有 arm64-v8a 原生库，
Core build ID 与构建输出一致。与 v1 相比仅四个应用构建输入变化，APK 的 Dart 制品已变化，
Core 摘要未变；校验集中在 `implementation_v2/artifacts.json`，复用依据见 `reuse.json`。
v1 APK 保留在冻结目录，仅代表旧版。

`core/Clash.Meta` 及载体没有修改；未安装/启动设备、宿主 FlClash、TUN 或 system proxy，未做外部测试流量。
远程 provider、Geo、其它协议/组类型、DoH、真实 ouo、设备/物理网络仍未覆盖；
旧解析器/缓存/远端解析等限制沿[总体设计](l2_t02_plan.md#10-残留风险与不再承诺的能力)，不因本项通过而结案。

## 收尾与本地集成

M1 已通过 implementation_v2 的 I1–I3 与 S1；获审快照 SHA-256 为
`7988432d9b4e13ab3f01149c44e20ea357dff6884b66bee685b1a5043d2412ab`。
提交前结构检查覆盖材料展开、Candidate/Setup/Selection/Refresh 协作及页面操作归属，未发现须调整的结构问题。
两份生成的 English/Russian locale 文件仅由正常 Dart formatter 整理；
获审源文件经同一 formatter 后与最终内容逐字节一致，未改变逻辑或字符串。
其余增量仅为本轮评审/交付状态与此说明；原测试、构建与 APK 继续适用，不因纯格式整理重建。

本地集成目标为 `security/android`，最终 commit/Tree、52 文件映射及实际分支清理结果由最终交接绑定，
本地证据放在 `build/verification/l2-t02/subtask_04/delivery/`。
Plan/Result 随任务定稿保留，后由 M1 取回核对后独立清理；共享活动 Tasks、长期契约、共享 checkout、聊天及有效证据继续保留。
D-02 不推送；M1 按贡献指南完成任务收尾与授权的普通父分支推送。
