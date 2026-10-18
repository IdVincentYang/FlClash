# L2-T02-03 受管应用与恢复结果

本项把已保存草稿接入明确选择、最终合成、T01 应用和恢复保护。M1 已通过 implementation_v3；源码已本地快进合入 `security/android`，本项临时分支已删除，未推送。设计及 A1–A19 验收意图见[获审设计](l2_t02_03_plan.md)，归属和阶段见[任务清单](l2_t02_tasks.md#l2-t02-03-最终合成受管应用与恢复)。

首轮问题涉及维护默认与 Owner 的同次观察、DNS 端口 0、设置补偿异常标记，以及来源失效后的条件清理；首轮还要求明确冷重建后的导入选择，并补恢复占位后的失败消费者。v1、v2 原始绑定和 APK 均保留，历史评审结论不回写。各轮实际修订及增量验证单列如下；最终实现通过不回写旧轮的失败结论。

## 1. 实际能力与使用入口

| 用户操作 | 实际行为 |
| --- | --- |
| 保存、修改或删除策略草稿 | 只修改草稿，不改变已选快照或启动代理 |
| 在策略页请求应用 | 选择可选维护代理目标，再确认；重验草稿和选择记录，生成独立的已选快照 |
| 在停止状态请求应用 | 载入 inactive 配置，保持停止；接受状态以实际 Core fact 为准 |
| 修改有效网络设置或测试 URL | 原 `application-config` 来源先失效，再发布、持久化设置；受管配置重新合成 |
| 规则、DNS 或覆写与受管策略冲突 | 最终编码从编译器闭包重新构造；受管编辑入口导向策略页，非法热写在真实 Core 写入口拒绝 |
| 应用失败或候选过期 | 最多重捕获一次；保留仍合格旧输入，否则仅清理匹配的原身份，较新任务不受旧失败影响 |
| 导入 Profile | 只保存材料；从未选择或删除后冷重建均保持未选择，需通过 picker 明确选择 |
| 删除当前 Profile、切回原模式或恢复旧备份 | 删除后停止并清空选择，不自动改选首项；退出受管需确认；恢复时保护全部原受管存活项 |
| 查看最终生成或实际接受配置 | 两个入口分别标注；默认脱敏且只读，完整复制每次确认，复制同一冻结快照 |

首版仅 Android 开放受管应用。桌面保留草稿和预览，应用入口禁用，读到受管选择也明确拒绝应用。
schema 13 的选择记录区分“无行”和“有行但正文不可用”；后者保持受管阻断，不解释为原模式。
草稿仍沿 02 的 raw CAS；新的选择 CAS 核对行存在性和原文。

## 2. 验收覆盖与真实消费者

| 设计编号 | 已执行路径与观察 | 主要依据 |
| --- | --- | --- |
| A1–A2 | 真 SQLite DAO、选择 action 和菜单确认；区分 absent/null，过时草稿冲突不覆盖，显式选择只重置本 Profile 的受管 picks，保留其它 Profile | `policy_selections_test`、`policy_selection_action_test`、`policy_draft_test` |
| A3–A4 | `makeRealProfileTask` 的真实最终 YAML→ConfigInput→Go T01 prepare/install/activate；原订阅的 direct/rules/DNS/controller/provider 冲突被闭包替换，独立 A/B SOCKS、直连业务和 DNS 收件验证 A/B/DIRECT/REJECT | [最终合成](../../../../test/common/policy_selection_test.dart)、[真实跨语言消费者](../../../../test/providers/application_input_bridge_test.dart)；01 的顺序、两个默认、地址及 UDP 反例继续有效 |
| A5–A6 | 真实 General 的 TestUrlItem 在 final write 后改设置，旧 prepare 被拒绝；相反顺序接受后再失效，实际输入不被伪装成新输入；直接 notifier 写入及微任务继承权限均拒绝 | `application_input_test`、真实 Dart→Go 桥接、既有来源和 route/picks fence 测试 |
| A7–A9 | Core 真实条件保留/阻断，来源撤销后合法热写不恢复 replay；Dart 连续 stale 仅重试一次，较新 Setup 不被旧失败清理；native fake-host 覆盖原 run/token 清理和新意图 | [Core 条件处理](../../../../core/managed_config_test.go)、[SetupAction](../../../../test/providers/setup_action_test.dart)、Kotlin 两组 StateMachine 测试 |
| A10–A12 | 混合非法热写整项拒绝、普通选组限固定成员并核对 owner/token、provider 更新和侧载拒绝；维护 Proxy 使用显式目标，缺失/旧目标零发送；原 Auto/Direct 路径保留 | Go 真实业务、维护请求与收件方；既有 Request/路由桥接回归 |
| A13 | 选择/退出确认与冲突，Dashboard picker 真 DB 切换，删除/失踪不首项回退；两处 picker 使用统一 action | 选择 action、Profile/策略页、Dashboard 与 request_scope 回归 |
| A14–A15 | schema 12→13 和表已存在升级保留未知正文；真实 VACUUM→ZIP→解析→第二 DB，选择秘密确认；旧归档保护原受管非当前项，保留原空输入及补偿边界 | DB 升级、`policy_draft_backup_test`、既有 BackupAction 回归 |
| A16 | 磁盘 checkpoint reader→prepare/install/activate，受管闭包、合法 hot 参数与实际 A 业务保留；application-config 撤销后不可重放 | `TestManagedCheckpointReplayKeepsClosureAndRevocation`，既有 checkpoint/native 冷恢复夹具 |
| A17–A18 | desired、selected、accepted 分别显示；端口消费接受事实，safe mode 关闭 TUN/DNS；实际预览不持明文编辑内容，取消不复制、每次确认复制同一快照 | 最终合成、投影、预览、策略页及 native DTO 测试；宿主集成使用替身 |
| A19 | 真 TCP/UDP DNS 在安装未激活、active、inactive、失败、停止、替换和同端口重用时核对 socket 与上游计数；停止后唯一新查询零上游，旧关闭不关新 owner | [DNS 所属资源](../../../../core/config_dns_test.go)、实际最终合成桥接与 Go 受管消费者 |

Go 的新普通 DNS listener 同时管理原模式和受管模式。安装时抑制 mihomo 的普通 DNS Listen，由当前 preparedConfig 持有已检查的 TCP/UDP socket，激活前 gate 拒绝转发，停止时先关闭入口，再在锁外异步收敛 server。
内部维护端点和全局 DefaultService 保留原职责，未修改 mihomo 或增加 matcher。

## 3. 实现复审修订

| 问题 | 实际修订与消费者 |
| --- | --- |
| I1 维护默认与 Owner 混合观察及锁环 | v2 同次观察已修复跨代混合，但新增 registry/configMux 锁环；v3 在复制后释放 registry，再计算 hasProxy，见下节真实并发反例 |
| I2 原模式 DNS 监听 | 沿原 server 语义，空地址、端口 0/空及 SplitHostPort 失败均不创建 socket；实际 active legacy 输入验证，正常 TCP/UDP 正反例继续通过 |
| I3 设置补偿异常 | 首次保存及回退发布/保存完整包围，false 或抛异常保留 partial-commit；实际 action、shared_preferences 委托与恢复标记验证成功补偿、不确定补偿和回退发布异常，错误不包含合成秘密 |
| I4 失效后的条件清理 | 失效前捕获 Core fact、Native run 和原注册 token，失败后走既有 failConfigBuild；真实 selection INSERT、picks UPDATE 和设置持久化失败关闭旧业务/DNS；新 Owner 抢先时旧失败 superseded，新资源继续可用；Kotlin 验证新 run/token 在调用前抢先 |
| Q1 删除与冷导入 | 删除最后受管项后关闭并重开磁盘 DB、重建 provider，导入唯一原 Profile 仍不选中或启动；显式选择才更新 currentProfileId |
| Q2 恢复占位后失败 | 在真实事务内确认 null 占位、替换实体/选择和文件已写入，再令 preferences 首次保存失败；补偿成功/false/throw 均恢复 DB、原选择、实体和文件；不确定持久化保留标记，Config 与 setup 零发布 |

### 3.1. I1 锁环的 v3 修订

v2 的 inspect 持 registry 等待 AllProxies 的 configMux read；旧 matcher 持 configMux read 等待租约 Check 的 registry，而排队的配置 writer 阻止新 reader。v3 保留 select/checkpoint 下的同次身份快照，复制返回字段后释放 registry，再计算代理提示；全部锁释放后才 flushCleanup。

- 实际反例：`HandleAppTCPConn` 进入真实 `matchScoped` 持 read，现有 lease.Check 在该点暂停；真实 `prepareConfig` 撤销旧租约，再调用 `installConfig → executor → UpdateProxies` 排队 writer。随后真实 inspect 到达 AllProxies 的 read 等待，释放 matcher 的屏障后，旧 Check、安装与 inspect 均能结束。
- 边界观察：测试从实际 goroutine 栈确认 UpdateProxies writer 和 AllProxies reader 已阻塞；没有改 mihomo、注入另一组 mutex 或用串行调用替代冲突。反例隔离在有时限的自有测试子进程，避免回归死锁拖住其它测试。
- 对照：Go overlay 仅将 app_requests.go 替换为冻结 v2 原文，同一真实测试复现旧 Check 无法结束及 8 秒超时；overlay 不修改工作区或 v2 快照。修订源码通过；原 A/B 默认与 Owner 的真实收件测试继续通过。

## 4. 检查与产物

### 4.1. v3 增量

| 检查 | 实际结果 |
| --- | --- |
| Go wrapper | 335 个具名测试/子测试通过，2 个环境入口跳过；vet 通过。新增真实锁环测试及既有 A/B 默认测试通过 |
| v2 对照 | 同一新增测试对冻结 v2 的单文件 overlay 失败，观察到真实 writer/read 等待及旧 Check 阻塞；这是预期反例，不计为通过 |
| Android ARM64 | 正常构建与固定源码后的复查均成功，APK 哈希相同；85 项构建输入前后一致，相对 v2 只改变 core/app_requests.go。首次构建报告测试文件变化，复查无该提示；Manifest、ZIP CRC、ARM64 ABI 均已核对 |
| 证据复用 | Dart、DB、Kotlin、生成与依赖源码未变，复用 v2 的 153 Flutter、58 Kotlin、分析和格式结果；未重复全量运行 |

可复用的 Go 测试程序对新增锁环与既有 A/B 收件用例连续 5 轮全部通过。准确命令、当前源码和产物关系见 [v3 绑定](../../../../build/verification/l2-t02/subtask_03/implementation_v3/binding.json)。[v3 APK](../../../../build/verification/l2-t02/subtask_03/implementation_v3/artifacts/FlClash-0.8.99-android-arm64-v8a.apk) SHA-256 为 `6f07e42248a70c81a62931ffe252c38b4e818685eec83c1f68674f7b6a822319`，60690859 字节；包名、实际版本和 SDK/ABI 与 v2 相同。v2 的已关闭问题和未变消费者证据继续有效；下列记录保留各轮原始对象与结果。

### 4.2. 冻结 v2

| 检查 | 实际结果 |
| --- | --- |
| 正常生成与分析 | build_runner、全目录 Dart format 检查通过；两份生成文案由 formatter 整理。分析 0 error、0 warning，42 项既有 info；intl 与依赖未变，沿用 v1 正常生成，APK 构建另正常解析锁定依赖 |
| 受影响 Flutter 回归 | 最终合并运行 153 通过、0 失败：ApplicationInput、selection、cold import、backup、ProfilesAction、Setup、JVM ConfigApply 、request_scope 及真实桥接 |
| 真实最终合成与失败桥接 | 上述 153 中的 11 个桥接通过：General/finalTask 与 10 个 mutation 失败用例，真实 SQLite、shared_preferences 和 Go T01/业务/DNS 消费者 |
| Go wrapper | 334 个具名测试/子测试通过，2 个环境触发入口跳过；实际 Dart 桥接另行执行，vet 通过 |
| Kotlin | ConfigApplyStateMachine 11、ServiceStateMachine 47，共 58 通过 |
| Android ARM64 | 初次与格式整理后正常构建均成功，无文件变动提示；最终产物重新核对；85 项构建输入哈希前后一致。包名 `com.follow.clash.dev`，0.8.99 / 实际 versionCode 2026102301，minSdk 24、targetSdk 37，仅 ARM64；Manifest、ZIP CRC 通过 |

准确命令、当前源码与测试/制品的对应关系见 [v2 实现绑定](../../../../build/verification/l2-t02/subtask_03/implementation_v2/binding.json)。[v2 APK](../../../../build/verification/l2-t02/subtask_03/implementation_v2/artifacts/FlClash-0.8.99-android-arm64-v8a.apk) SHA-256 为 `e96025bb66139731487a485750d8862cad300568484b33fbcb0801b027e32835`，60693739 字节；本地保存，不上传。以下 v1 扩大回归继续作为未受影响范围的历史证据，不计作 v2 全量重跑。

### 4.3. 冻结 v1

以下计数分别对应各条实际命令，不把重叠回归相加为唯一用例总数。

| 检查 | 当前实际结果 |
| --- | --- |
| 依赖、生成与分析 | 正常依赖解析、build_runner、intl_utils 通过；分析 0 error、0 warning，保留 42 项既有 info |
| Flutter 扩大回归 | 冻结回归 1818 通过、1 个失败：已复现的 service_status 基线错误。后续仅调整 widgets 观察/等待夹具及冗余 const，产品源码未变；受影响夹具补测单独记录 |
| widgets 与夹具补验 | `test/widgets`＋request_scope＋policy_draft_backup：530 通过、3 个既有 update_dialog 失败；重复覆盖夹具已修正并通过，相关请求和备份用例通过 |
| 新最终合成桥接 | 1 通过；真实 General 竞争及最终 YAML 的业务/DNS消费者，停止后新查询无上游 |
| Go wrapper | 325 个具名测试/子测试通过，2 个环境触发的桥接入口跳过；实际 Dart 桥接另单独执行通过；vet 通过 |
| Kotlin | ConfigApplyStateMachine 9、ServiceStateMachine 47，共 56 通过；未修改获测 Kotlin 源码 |
| Android ARM64 | 本轮构建和同命令缓存复查均成功，产物 SHA256 相同。`com.follow.clash.dev`，0.8.99，实际 versionCode 2026102301，minSdk 24／targetSdk 37，仅 arm64-v8a；ZIP CRC 及 Manifest 已核对 |

本地证据根为 `build/verification/l2-t02/subtask_03/implementation_v1/`，[实现绑定](../../../../build/verification/l2-t02/subtask_03/implementation_v1/binding.json) 关联实际源码快照、命令、日志及制品 SHA256；该目录被忽略，不随 Git 推送。
`design_v1/`、`design_v2/` 保留获审设计，不回写成实现证据。

## 5. 复现前提

使用仓库固定 Flutter/Dart、Go、JDK 17 和 Android ARM64 工具链；正常 native hook 保持开启。
Flutter 编辑器测试复用 02 从未改 Rust 源码生成的 `strip=none` 测试库，设置 `FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR` 指向其目录。该前提不表示默认 macOS dylib 的 LINKEDIT 问题已修复。

实际桥接先用 `dart compile exe tool/compile_managed_profile.dart` 构建编译器，以 `CGO_ENABLED=0 go -C core test -c` 构建 `application_input_bridge`；将 `FLCLASH_APPLICATION_INPUT_BRIDGE` 指向后者，再运行 `flutter test test/providers/application_input_bridge_test.dart`。编译器默认放在桥接程序同目录，也可用 `FLCLASH_MANAGED_PROFILE_COMPILER` 指定。
Go 全套测试设置相同编译器变量；未设置时 01 的真实编译消费者会跳过，不能沿用本次计数。
Kotlin/JVM 桥接沿用 T01 的本地 classpath 与受检原生编译结果。准确命令和当前路径由本地绑定保存。

## 6. 失败、限制与交付边界

- widgets 另有 3 项 `update_dialog` 既有失败，沿用 [02 的基线结论](l2_t02_02_result.md#3-扩大回归与静态检查)，未改相关生产或测试源码。
- `service_status_test` 中 route 改变后的重问用例缺少本地化初始化；在保留的 `12e694c` 基线复现相同单项失败，相关源码和测试在 02 后未变。未为本项顺手修正它。
- 曾中止包含旧夹具写入方式、异步等待缺失及编译错误的回归；这些日志保留诊断用途，不算通过。native hook 在完整构建中报过文件变化提示，受检产品源码哈希未变；随后单独缓存复查成功、APK 哈希一致，分别保留日志。
- 宿主集成、Android VPN 权限、Always-on、真实设备安装/运行、进程冷启动和物理网络切换未执行；Go/JVM/scoped 结果不替代设备证据。
- 未使用真实 DB、备份、订阅或凭据；仅合成数据与 loopback 收件方。未启动宿主 FlClash、改变 TUN/系统代理、上传、push 或使用外部测试流量。
- 关闭 DNS 新入口不证明已收取在途查询、后台工作或缓存的强撤回；这些限制沿原设计和 01 结果保留。
- 04–05、其它 Loop、暂缓的 L1-T04 未启动。整项 L2-T02 未完成，D-02 不操作远端。

## 7. 收尾与本地集成

M1 于 2026-10-18 通过 v3 实现评审，关闭 I1；I2–I4、Q1/Q2 沿用 v2 已关闭结论。
获审 tree 为 `f32e5033e950c422629a9c103966726e140f40ec`，v3 绑定 SHA-256 为
`57aed85badbfd84e2bf447f9198ca586daa9ea7f892f6406c394decd6123e886`。

本地收尾只更新五份 Markdown 的阶段、引用与空行；产品、生成文件、测试及 85 项 APK 输入保持获审内容。
代码结构检查覆盖选择与草稿职责、设置 receipt、失败收敛、受管闭包和 DNS 资源所有权，未发现需额外重构的问题。
Markdown 检查沿现有中文长行和表格风格关闭 MD013；图源未改，不据 lint 声称目标环境预览通过。
本次源码和本地制品的最终对应关系由[交付绑定](../../../../build/verification/l2-t02/subtask_03/delivery/binding.json)记录。

源码提交为 `648d968783c5a12e1e4f94873f007ff21d355d3b`，已从任务分支快进合入本地 `security/android`。
`security/l2-t02-03-managed-apply` 已删除；未创建独立临时 worktree，共享 checkout、独立聊天及冻结证据继续保留。
文档收尾随该源码提交的 fixup 维护，最终提交与 tree 见交付绑定。
04–05 与其它任务未启动，整个 L2-T02 未完成，不推送。

实际体验入口为 Android 的 Profile 策略页：保存草稿后明确请求应用，再查看实际配置状态和只读预览。
停止状态下请求应用保持停止；导入只保存 Profile，需要在 picker 明确选择。
上述入口与便携验证均不替代真实设备、VPN 权限和物理网络测试。
