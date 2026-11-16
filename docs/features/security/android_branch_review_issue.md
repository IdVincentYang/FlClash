# Android 分枝累计改动 Review Issue

本文汇总 Android 专用分枝相对 `main` 的已确认问题，供后续修复使用。
评审者为 [R] FLClash Review（M），每项均与 FlClash D2（D）讨论核验后收录。
R01–R09 已修复并完成本地交付；R10–R11 尚未解决，按序由 D 修复、M 评审后更新处置。
下文问题事实绑定原评审基线；修复版本与验证边界见对应条目的处置记录，不升级整体阶段验收状态。
原评审收录 11 项：3 项 P1、7 项 P2、1 项 P3。修复中另确认 F01（P2），作为独立未解决跟进记录，
不并入 R08 已解决声明，也不改变本轮 R09–R11 的修复顺序。

## 对象与覆盖

评审日期为 2026-11-16。实际 checkout 是 `security/android`，本地不存在用户所称的
`feature/android`，以下结论绑定实际分枝。

| 对象 | 基线 |
| --- | --- |
| Android HEAD | `aadfcd955da72b55e0c5254dbf2d8ee64ca2e10f` |
| main／共同基线 | `4b59eca853778d4e7be3de26589252889c899bc5` |
| 累计差异 | `git diff main...HEAD`：904 文件，188725 行新增、12692 行删除 |
| Core gitlink | `7a620b930bdcb85e466450880313d34add46252b` |
| Core tree | `9df3b9d4fc95bff70a8ef60651e6b9e191ed23e0` |

按完整文件清单划分领域，检查设计、生产调用链、失败／并发边界和直接消费者。
生成文件、完整源码 carrier 和 scanner vendor 主要核对来源、同步关系与本地修改边界，
不声称逐行重新证明上游代码，也不把局部夹具等同于 Android 安装态整体验收。

| 领域 | 分枝主要工作与评审入口 |
| --- | --- |
| Android 联网与服务 | 删除自动应用更新检查、Firebase 和免责声明；RequestSession 用途／出口资格、Native 最新意图和 ConfigInput 接受链；见[联网清单](android_network_inventory.md)、[服务设计](android_service_design.md) |
| 本地分流与来源 | 受管路由／DNS、草稿／迁移、材料更新、来源权限／规则追溯、部分及仅节点导入；见[受管设计](business_data_design.md)、[来源设计](source_acceptance_design.md) |
| 应用网络 | UID 身份、连接观测／汇总、出口缓存、全局自建组、App／Host 策略与 Dashboard 入口；见[应用网络设计](../network_activity/network_activity_design.md)、[自建组设计](../proxies/local_groups_design.md) |
| 恢复与诊断 | BootGuard、本地故障报告与主动导出、ZXing 本地扫码、IP／站点检测；见[启动恢复](boot_recovery_design.md)、[报告](crash_reports_design.md)、[扫码](qr_scanning_design.md)、[IP 查询](ip_lookup_design.md) |
| 构建与资料 | Geo seed 核验、Android 输入／缓存、CI 发布权限及制品核验、Core 精确恢复、生成／测试和 delivery skill；见[构建来源](android_build_sources.md)、[Geo 设计](geo_data_design.md) |

阶段状态以[安全总计划](flclash_security_plan.md)和[应用网络计划](../network_activity/network_activity_plan.md)为准。
已有风险沿用[延期事项](deferred_security_items.md)，不重复登记为新发现；
未实施的 loop 和应用网络 09 整体验收也未因本次 Review 升级为完成。

## 已确认问题

P1 为建议优先修复的功能／门禁缺陷；P2 为有明确条件的正确性或资源问题；
P3 为影响使用或复核的文档问题。优先级不替代项目排期。

| ID | 优先级 | 问题 |
| --- | --- | --- |
| R01 | P1 | 备份合并后 App／Host 策略保留旧全局组 ID |
| R02 | P1 | 等待中的运行意图可覆盖 exiting |
| R03 | P1 | 测试消费者未同步，根测试门禁失败 |
| R04 | P2 | ConfigFact 并发检查与赋值允许版本回退 |
| R05 | P2 | 共享 UID 候选截断使策略一致性判断失真 |
| R06 | P2 | Direct 模式的应用规则被记录为 Rule 模式 |
| R07 | P2 | 每条规则匹配重复全表清理，放大热路径成本 |
| R08 | P2 | 请求历史 key 没有回收边界 |
| R09 | P2 | 新增 JNI export 缺少独立 panic recovery |
| R10 | P2 | Android 退出前置失败跳过独立收尾 |
| R11 | P3 | 当前文档未同步 Core、节点 fallback 和 VPN 重建行为 |

### R01：备份合并未同步所有全局组引用

位置：[全局组迁移](../../../lib/common/global_proxy_groups.dart)的 `migrateGlobalGroups`、
[数据库恢复](../../../lib/database/database.dart)的 `restore` 与
[目标解析](../../../lib/common/application_routing.dart)的 `resolveApplicationTarget`。

复现：已有组 ID 8，导入备份含定义相同但 ID 为 9 的组；Profile 绑定、共用 App 目标、
独立 App 目标、Host 目标均引用 9。D 的实际 `Database.restore` 内存数据库夹具显示：
合并后的组和 Profile 快照均为 8，后三类目标仍为 9，解析为 `missing`。

预期全部导入引用随同一映射迁移。实际 `importedIds` 只用于 Profile 的组快照，
恢复应用设置与 Rules 中的 `HostRuleBinding.targets` 时未消费映射。
恢复显示成功后，相关策略仍失效，Core 对缺失目标使用 REJECT，可能导致连接失败。
本问题由分枝新增的全局组及应用策略恢复组合引入。

处理目标：在恢复事务中同步三类目标引用，保留已有合并语义；覆盖不同 ID 的等价定义、
共用／独立 App 目标、Host 目标及恢复后的真实解析。契约见[自建组设计](../proxies/local_groups_design.md)
和应用网络设计的备份／稳定 ID 约束。

处置：2026-11-16 已解决，D 实现并 refine，M 评审及本地交付对账通过。
修复提交 `e344c45f3cad37df16a20056501a902b3c1e3b47` 位于 `security/android`；
新版全局映射及旧版按 Profile 区分的映射共同供导入引用使用，既有保留目标不套用导入映射。
[恢复回归](../../../test/database/global_group_restore_test.dart)与
[迁移回归](../../../test/common/global_proxy_groups_test.dart)共 13 项通过；
相同恢复测试在旧实现为 3 通过、6 失败。覆盖生产目标解析／wire、冲突、重复恢复、
未导入数据保持、事务回滚及文件数据库重开。

验证由 D 执行，M 读取代码、测试与绑定日志，没有代跑编译或测试。
扩展回归 86 通过、4 项基线失败；未验证 APK、设备或 VPN。
本地、未入库证据为 `.buildlog/r01-group-restore-20261116/implementation-review.json`
及同目录 `pre-merge-01/delivery.json`；后者记录的 `6cf2ad7` 仅由 M amend 提交说明，
最终修复提交的 Tree、父提交及 6 个文件与已审对象保持一致。
可用 `flutter test --no-pub test/database/global_group_restore_test.dart test/common/global_proxy_groups_test.dart`
复跑直接专项；四项既有失败留待 R03 核对，不计入 R01 已解决范围。

### R02：退出检查与运行意图发布不在同一临界区

位置：[ServiceStateMachine](../../../android/app/src/main/kotlin/com/follow/clash/ServiceStateMachine.kt)
的 `prepareRunIntent`；调用方包括原生 Tile Start 和前端退出。

复现交错：旧 Tile Start 通过 `reason != exiting` 检查，在取得 `publicationLock` 前等待；
退出先取得锁并发布 `exiting`；旧 Start 随后发布 `preparing`、`intentRunning=true`、`reason=none`。
D 用未修改的已编译 JVM 类复现，并确认 Core publication 接受后续 revision。

预期退出终态拒绝后续运行请求。实际检查在锁外，锁内没有重新核对；
同文件 `preparePauseIntent` 则在发布闭包内检查。分枝新增的意图协议因而允许退出状态被旧操作覆盖。
本结论限于原生状态及退出意图，没有证明 Go 业务 scope 保护被绕过或设备必然重建 VPN。

处理目标：让终态判断与意图创建／发布具有同一线性化边界，覆盖等待中的 Tile Start、
Stop、重复退出和过期请求，保持 Native 为唯一服务意图所有者。

处置：2026-11-16 已解决，D 实现并 refine，M 评审及本地交付对账通过。
修复提交 `82be1097eeee1b3b310f6d95368088ee2d3181b7` 位于 `security/android`。
终态判断、token 创建和 publication 共用既有锁；公开异常协议保持，原生动作正常消费拒绝，
Always-on 拒绝返回 0 且不继续 bind／dispatch。契约见[服务设计](android_service_design.md#权威与请求)。

[退出专项](../../../android/tests/app/ServiceExitStateMachineTest.kt)包含 15 项生产状态机测试；
旧实现兼容用例实际执行 10 项，4 通过、6 失败。修复后相关 6 suites 共 96 通过、0 失败、0 跳过，
受影响 app Kotlin 编译通过。验证由 D 执行，M 核对代码、测试及绑定证据，没有代跑。
覆盖 host JVM 和生产 Always-on owner；未验证 APK、设备、VPN、系统 callback 注册或 JNI／Go 端到端。

本地、未入库证据为 `.buildlog/r02-exit-intent-20261116/implementation-review.json`
及同目录 `pre-merge-01/delivery.json`，前者保存可复跑命令与源码／日志／XML Hash。
后者的交付版本 `1a8945e` 仅由 M amend 提交说明，最终修复提交的 Tree、父提交及 4 个文件保持一致。
原有 R03 门禁失败不纳入本项通过范围。

### R03：累计迁移未同步测试消费者

位置：[bootstrap 测试](../../../test/bootstrap_test.dart)、
[设计库导入检查](../../../test/lint/design_package_test.dart)、
[更新弹窗测试](../../../test/widgets/update_dialog_test.dart)、
[更新结果资格](../../../lib/common/request.dart)和 [CI 根测试入口](../../../.github/workflows/build.yaml)。

已复现三组失败：

- 新增 `test/bootstrap_test.dart:10` 导入 `package:flutter/material.dart`，违反扫描 test 的既有设计库检查；
  实际 lint 失败，唯一违规项为这处导入。main 没有该文件。
- 更新弹窗前三例自建 release Map；生产新增 `validateVersionResult` 要求它是 `checkForUpdate` 保存的
  精确结果且仍有 session，因此三例均被 `request_cancelled` 拒绝。补齐测试 assets 后实测 1 通过、3 失败，
  空结果的手动检查反馈例通过。
- schema 已从 main 的 10 升为 17，但 [v1 迁移测试](../../../test/database/migration_v1_to_v2_test.dart)
  有 13 项仍期待 14；另外 [request mode](../../../test/models/request_mode_test.dart)、
  [request mode 迁移](../../../test/database/request_mode_migration_test.dart)、
  [policy draft](../../../test/database/policy_drafts_test.dart)、
  [policy selection](../../../test/database/policy_selections_test.dart) 共 6 项期待 11／14。
  D 最小运行共复现 19 项过期版本断言；这不等于数据库迁移本身失败。

预期实现迁移后测试仍经有效边界验证业务，根 `flutter test` 可通过；实际 CI 仍运行这些失败用例。
先前任务已知这些失败，不改变相对 main 的累计引入归因；本结果也不证明正式手动更新功能本身失效。

处理目标：使用允许的 UI 导入，更新夹具及 schema 预期，保留数据迁移、成功、取消及资格失效的独立断言；
不得放宽生产资格检查或跳过门禁来消除失败。

处置：2026-11-16 已解决，D 实现并 refine，M 评审及本地交付对账通过。
修复在 `security/android` 分为三个 fixup：`346f445` 同步生命周期请求消费者，
`8d4dd47` 修复空备份与卡片布局，`2eed93544697a173c3b850972fb4fce0cd29fc42` 完成 Host 删除、
schema 消费者和任务定稿。更新弹窗通过真实 Request 获取合格结果；迁移保留数据／约束断言，
DAV、Bootstrap 和 manager 夹具匹配实际所有权，没有放宽生产资格或新增 skip。

关联回归中另外确认并修复三处生产缺陷，均先由 M 与 D 核验并批准范围：

- 合法空数据库备份被解析成显式空组／默认 routing，override 因而删除已有数据。
  parser 在完整解析和关系校验后恢复 Config-only 语义；禁用 App、shared／Host 等非空数据仍保留，
  显式 `Database.restore(globalGroups: [])` 清空契约不变。见
  [空备份回归](../../../test/common/empty_backup_archive_test.dart)及[恢复契约](../proxies/local_groups_design.md#保存许可与并发)。
- 删除 33,000 条规则时，删除前的 Host 查询使用未分批的 IN 参数而失败。
  同一事务内按既有 900 参数边界查询和删除，仅命中 Host 时更新一次 revision；
  [分块回归](../../../test/database/rule_delete_chunks_test.dart)覆盖跨批命中和数据／revision 一起回滚。
- Home 从 1440 缩至 380 时，ProfileItem 尾部文字动作在 106px 约束下溢出约 71px。
  按卡片实际空间、标签宽度和字体缩放切换文字／图标动作，保留选择、审核禁用、菜单和进度；
  [布局回归](../../../test/widgets/profile_action_layout_test.dart)覆盖阈值、俄语、2 倍文字及交互，
  原 Home resize 条件和异常断言保持。

D 完整运行根 Flutter 测试：4239 通过、115 个既有环境依赖跳过，0 失败、0 未完成；
真实 test assets 与 Rust hook 启用，仅 Go setup hook 按 CI 测试方法临时关闭并恢复原配置字节。
跳过项依赖未提供的 JVM／Core bridge 或 managed compiler，不计通过。analyze 无 error／warning，
42 条 info 与基线一致；format、文档 lint、diff 及提交 hooks 通过。
M 审阅代码、测试方案及绑定证据，未代跑编译或产品测试。
未验证 APK、设备、VPN、Linux CI、真实更新服务或全部 bridge，不升级整体 Android 验收。

本地、未入库证据为 `.buildlog/r03-test-consumers-20261116/implementation-source.json`、
`root-tests-02.log`、`root-tests-02-summary.json` 和 `delivery-summary.json`。
最终 25 文件与获审快照的唯一差异为 Plan 状态；`delivery-summary.json` 中的 `832326f`
仅由 M amend Details，Tree 与父提交保持不变。R01 所列四项基线失败已在本项处理；
各专项存在重叠，不与完整根计数相加。定稿 Plan 保存在上述最终交付提交的历史中，
可用 `git show 2eed935:docs/features/security/r03_test_consumers_plan.md` 取回复核方案、命令及验证限制。

### R04：ConfigFact 的版本检查与赋值可并发失序

位置：[ServiceStateMachine](../../../android/app/src/main/kotlin/com/follow/clash/ServiceStateMachine.kt)
的 `observeConfigFact` 和 [ServiceController](../../../android/app/src/main/kotlin/com/follow/clash/ServiceController.kt)
的 Core 事件投递。

同 epoch 下，旧 v2 读取 previous=v1 并通过比较，新 v3 先写入，随后 v2 写入，最终保留 v2。
事件经 `GlobalState.launch` 在 Default dispatcher 执行，配置应用也直接调用此方法，没有共同串行保证。
D 在复制类中仅加入调度 latch，复现合法交错 v3→v2；生产源码未改。

预期 Native 镜像接受同 epoch 的单调版本。实际 `@Volatile` 不能让比较与赋值原子化。
回退的配置名、ready／businessActive 镜像可能影响通知及 refresh 判断。
这是分枝新增镜像的并发缺陷，结论不扩大到 Go 配置权威或业务授权失守。

处理目标：串行执行 epoch／版本判定、更新及投影；回归乱序事件、直接应用并发及新 epoch 的权威切换。

处置：2026-11-16 已解决，D 实现并 refine，M 评审及本地交付对账通过。
修复提交 `fb92a1cc3576ee71fe404f03f2770cd538e143f3` 位于 `security/android`。
既有 publicationLock 覆盖事实接受、替换与通知提交；phase／SharedState 的独立投影和 refresh
也在同锁内读取快照。原 epoch、authoritative、同版本接受规则及 R02 exiting 契约保持，
Go 仍拥有业务资格。当前规则见[事实镜像契约](android_service_design.md#配置事实镜像与投影)。

[生产状态机回归](../../../android/tests/app/ConfigFactStateMachineTest.kt)使用真实 ServiceConfig StateFlow，
控制通知提交交错，并核对竞争线程的 monitor、持有线程和生产方法栈；超时或未调度不算成功。
同一专项在未改生产上为 5 通过、7 失败，其中 6 项显示旧通知覆盖新投影，1 项显示 refresh
绕过尚未结束的提交；这与原复制字节码的比较／赋值反例分开，不声称直接测到了该两行间的插入点。
修复后专项 12 通过；含 R02 全部 96 项及 ServiceConfig 4 项的关联 JVM 回归共 112 通过，
0 失败／错误／跳过。JDK 17、ARM64 目标配置的 app Kotlin 编译通过。

验证由 D 执行，M 审阅源码、测试方案及绑定日志，未代跑编译或产品测试。
覆盖同 epoch 乱序／同版本更新、真实 apply 回执、新 epoch／旧事件、通知异常释放与同线程重入。
范围限 host JVM／StateFlow／Kotlin 编译；未验证真实 JNI 调度、Android 通知显示、APK、设备或 VPN。
Dart、依赖与分析配置未变，复用 R03 的已审验证，没有重复全量 Flutter。

本地、未入库证据为 `.buildlog/r04-config-fact-20261116/implementation-source.json`、
`before-02-summary.json`、`after-regression-results.json` 及对应日志／XML。
`delivery-summary.json` 中的 `89fe4a9` 仅由 M amend Details，Tree、父提交保持不变；
四文件交付与获审快照仅有 Plan 状态差异，源码、测试和服务契约逐字节一致。
定稿可用 `git show fb92a1c:docs/features/security/r04_config_fact_plan.md` 取回，包含复跑命令与限制。

### R05：共享 UID 的不完整候选被当作完整集合

位置：[UidPackageResolver](../../../android/service/src/main/java/com/follow/clash/service/UidPackageResolver.kt)
的 `resolve`、[身份解码](../../../core/application_identity.go)和
[应用分流](../../../core/application_routing.go)。

原生按完整列表计算 `ambiguous`，再发送排序后的前 64 个包，没有候选溢出标志。
D 用未修改 resolver 输入 65 个包，DTO 实际只有 64 个；Go 将该 DTO 当作完整集合。
前 64 个均为 DIRECT、第 65 个未配置时，消费者仍错误判定 App 策略一致并采用 DIRECT。
另一个使用 resolver 实际 DTO 的反例在 Direct 模式给前 64 个包配置 REJECT、末项未配置：
截断后采用 REJECT；完整超限列表按现有保守解码回到 Direct，实际出口行为不同。

预期所有候选决策一致才采用 App 策略；省略的包可能有不同目标或没有策略。
实际截断把未知冲突变成确定结论，同 UID 的全部流量可能得到错误策略。
该能力由本分枝新增。夹具证明身份及决策错误，没有测量真实设备出现此规模共享 UID 的频率。

处理目标：保留 DTO 上限，但显式表达不完整／未知，Core 不用不完整集合授予共同策略；
覆盖 64／65 候选及末项未配置或冲突，不能以选首包解决。

处置：2026-11-16 已解决，D 实现并 refine，M 评审及本地交付对账通过。
修复提交 `0c297aa59b50914decc5a97212a7a33883abd818` 位于 `security/android`。
Native 第 65 个去重非空候选返回既有 lookupFailed／unknown／空列表；完整 0–64 项保持原状态与排序。
未知身份不取得 App／App＋Host 策略，保留 Direct 与 Rule 通用 Host／订阅回退；不扩 DTO，
不改 Go／Dart 生产代码、DB、Core gitlink 或 carrier。边界见[身份契约](../network_activity/network_activity_design.md#应用身份)。

[Native 专项](../../../android/tests/service/UidPackageResolverTest.kt)在原实现 9 项中 2 项超限失败，
修复后专项 9 项及 service 全部 33 项通过，0 失败／错误／跳过，Kotlin 编译通过。
[真实 producer](../../../android/tests/service/UidPackageIdentityFixture.kt)生成入库合成夹具，
Native 常规测试校对，Go 常规测试消费；可用 `:service:generateUidPackageIdentityFixture` 重生成。
[跨语言回归](../../../core/application_identity_native_test.go)的同一测试源码消费实际旧／新 Native 产物：
66 个配置由 48 通过、18 超限失败变为全部通过，覆盖完整／超限、末项缺失／冲突／一致、
App／App＋Host 及 Direct／Rule 回退。TCP／UDP 均验证路由决策，TCP 另经真实 tunnel 访问 localhost；
超时不算拒绝成功，UDP 未做真实传输。

Go wrapper 常规测试与 vet 通过，415 个 top-level 通过（含子测试共 638 个 pass 事件），
40 个既有条件 skip 事件不计通过；新增三专项没有 skip。Dart 模型／聚合／组件 77 通过，
2 项既有桥接输入跳过；analyze 只有与 R03 相同的 42 条 info。
验证由 D 执行，M 审阅代码、测试方案和绑定证据，未代跑编译或产品测试。
上述结果不证明真实 UID 规模频率、PackageManager 安装态、JNI、APK、设备或 VPN。

本地、未入库证据位于 `.buildlog/r05-uid-identity-20261116/`，入口为 `implementation-source.json`、
`before-final-source.json`、`matrix-before-03.json`、`matrix-after.json` 及 `delivery-summary.json`。
早期 Go 夹具准备失败保持冻结，不用作产品反例。交付与获审十文件仅 Plan 状态不同；
`delivery-summary.json` 中的 `c5d75d9` 仅由 M amend Details，Tree 与父提交不变。
定稿可用 `git show 0c297aa:docs/features/security/r05_uid_identity_plan.md` 取回复跑命令及限制。

### R06：应用规则命中把实际 Direct 模式重标为 Rule

位置：[连接观测](../../../core/connection_observation.go)的 `bind`、
[应用规则](../../../core/application_routing.go)和[来源追溯](../../../core/source_rule_trace.go)。

Direct 模式命中 App 规则后，实际 tracker 带有 `application-rules` provenance。
D 的 Core 消费链夹具中 `tunnel.Mode()` 为 `direct`，冻结的 `observation.configuration.mode` 却为 `rule`。

原因是 `bind` 将“AppliedRevision 存在且 Rule 非空”直接视为 Rule 模式证据；
后续新增 ApplicationRoutingHook 在 Direct 也生成规则及 provenance，旧假设已不成立。
连接详情与复核会得到错误模式；没有证明实际路由目标被改错。

处理目标：区分普通 matcher 和应用规则来源，保留可证明的实际模式；覆盖 Direct／Rule 的
App＋Host、App 默认和普通规则，继续禁止用新配置回填旧连接事实。

处置：2026-11-16 已解决，D 实现并 refine，M 评审及本地交付对账通过。
修复提交 `081e235d829c186d7ad731c483132a791ab66594` 位于 `security/android`。
仅有 AppliedRevision、实际非空 Rule 和非负 matcher 索引时才补 Rule 模式；App hook 索引为 -1，
保留稳定快照证明的 Direct，否则不猜模式。同名 application-rules 来源的普通 YAML 规则仍可证明 Rule。
实际路由、DTO、Native、DB、Core gitlink 和 carrier 不变，契约见
[连接事实与版本](../network_activity/network_activity_design.md#连接事实与版本)。

[模式回归](../../../core/connection_mode_test.go)包括 14 项真实 Core TCP Tracker 和 18 项局部 bind 边界。
同一测试源码在原生产有 7 项真实模式断言、5 项局部边界失败，修复后两组全部通过。
真实组以 Tracker 已包含 rule／chain、观测尚未 bind 的门控制合法配置更新；
13 项 localhost echo 成功，完整 ConfigInput 替换一项确认旧 lease 失效并终止载荷，超时不计成功。
覆盖 App／App＋Host、普通规则、Global bypass、模式往返及冻结后再次更新；
局部组的入口版本与追溯失效夹具仅证明事实组合边界，不冒充真实网络交错。

Go wrapper 测试与 vet 通过：417 个 top-level 通过（含子测试 640 个 pass 事件），
40 个既有条件 skip 不计通过；新增两专项无 skip。Dart 四专项 111 通过、2 个既有桥接输入跳过，
实际消费 14 条新 Core JSON；常规测试始终覆盖 mode 缺省，request／snapshot／JSON 往返不补造模式或路由戳。
analyze 保持 42 条既有 info。验证由 D 执行，M 审阅源码、测试与绑定证据，未代跑编译或产品测试。
范围限 host Core／Dart，不证明真实 JNI、Android 调度、APK、设备或 VPN。

本地、未入库证据位于 `.buildlog/r06-observation-mode-20261116/`，入口为 `implementation-source.json`、
`before-source.json`、`modes-before-04.json`、`modes-after.json` 及 `delivery-summary.json`。
前两次 Go 夹具准备错误保留为 setup 记录，最终旧基线为 `go-before-04.log`。
五文件交付与获审对象仅 Plan 状态不同；`delivery-summary.json` 的 `be8eee3` 仅由 M amend Details，
Tree 与父提交不变。定稿可用 `git show 081e235:docs/features/security/r06_observation_mode_plan.md` 取回。

### R07：规则追溯在逐条匹配中重复扫描全局表

位置：[来源追溯](../../../core/source_rule_trace.go)的 `sourceTracedRule.Match` 与 `sourceTracedRules`。
Android v2 配置中的原规则 wrapper 被加上追溯包装；每尝试一条规则都取得全局互斥锁，
遍历 pending／active 清理一分钟前的记录，另为 frame 和 provider map 分配内存。
pending 会保留到出站建连后的 tracker 绑定，慢连接可让它长时间非空。

预期有界追溯不会让过期维护成本随“规则数 × 并发待建连数”相乘。
实际同一连接匹配 R 条规则、已有 P 条 pending 时，清理部分为 O(R×P)，并串行争用同一把锁；
2048 容量限制只限制表大小，没有限制重复扫描频率。这是本分枝新增追溯的热路径成本。

D 使用与配置 parser 相同的 wrapper 构造方式，在本机对同一 wrapper 连续调用 100 次未命中 Match：
pending 为 0／128／1024／2047 时，每轮约 14／88／643／1275 µs；每轮约 200 次分配、27200 bytes。
夹具证明成本随 pending 增长，不能换算为 Android 吞吐、耗电或已发生的卡顿。

处理目标：降低逐规则重复过期维护及分配，保持准确 provenance、容量和过期边界；
回归高 pending、长规则链及真实 tracker 消费，不以关闭追溯换性能。具体实现尚未决定。

处置：2026-11-16 已解决，D 实现并 refine，M 评审及本地交付对账通过。
修复提交 `122c2e4db6f3fce85c31d88f3af1730e869d21a7` 位于 `security/android`。
普通 Match 和 App hook 共用原锁内的一秒维护门，provider map 在首个合格回调时创建；
pending 发布时复核 2048 上限，修复两个已准入匹配完成后可从 2047 增至 2049 的窗口。
满额仍执行实际匹配，frame 起始时间、bind 的一分钟有效期和冻结事实不变；
空闲过期引用等待下一次维护，两表各保持有界。当前契约见[轻量连接追溯](source_acceptance_design.md#轻量连接追溯)。

[生命周期与容量回归](../../../core/source_trace_work_test.go)在旧生产有提前分配、pending=2049 两项失败，
修复后通过；配合[维护门回归](../../../core/source_trace_maintenance_test.go)，新专项共 9 个 top-level、
含子项 16 个 pass 事件，覆盖迟到回调、满表恢复、共享时间门及过期拒绝。
真实 Tracker 的 provider 换代、PASS、sub-rule 和 R06 模式事实回归继续通过。
[基准](../../../core/source_trace_bench_test.go)前后各 14 配置、每配置 5 个样本；
同一 wrapper 每轮 100 次未命中、pending=2047 时，中位耗时 1272.984→13.887 µs，
分配 200→100 次。空表中位耗时增加约 1–2%，单次清扫仍为 O(active＋pending)，锁次数未减少。
这些 host 数据不证明 Android 吞吐、耗电或最坏延迟。

Go wrapper 测试与 vet 通过：426 个 top-level、含子项 656 个 pass 事件，40 个既有条件 skip。
原仓库 CGO=1 race 在构建阶段因既有 IPC 测试 helper 标签失败；仅移除该测试文件标签的本地 overlay
下，新专项定向 race 为 9 个 top-level／16 个 pass 事件，无 skip，不是原仓库完整 race 通过。
Flutter 四专项 111 通过、2 个既有桥接输入 skip，analyze 保持 42 条既有 info；本次未重新生成桥接输入。
验证由 D 执行，M 审代码、测试方案及绑定日志，未代跑编译或产品测试；未覆盖 APK、JNI、设备或 VPN。

本地、未入库证据位于 `.buildlog/r07-source-trace-20261116/`，入口为 `implementation-source.json`、
`before-source.json`、`bench-comparison.json`、`race-overlay-source.json` 及 `delivery-summary.json`。
八文件交付与获审对象仅 Plan 状态不同，55 个绑定证据未变；交付记录中的 `eca4420` 仅由 M amend Details，
Tree 与父提交不变。定稿可用 `git show 122c2e4:docs/features/security/r07_source_trace_plan.md` 取回。

### R08：活动请求有界，历史 key 却永久保留

位置：[Request](../../../lib/common/request.dart)的 `_cancellations`／`cancelKey`、
[Core 请求注册表](../../../core/app_requests.go)的 `operations`／`sources`；
实际动态消费者包括[图标缓存](../../../lib/common/cache.dart)和[连接出口检测](../../../lib/providers/connection_exits.dart)。

Request 对每个取消过的 key 保存版本；Core 为每个 begin／invalidate 的 key 保存计数，
lease 结束以及 detach／attach 都不回收这些项。图标 key 含 URL，出口检测 key 含节点、入口、
ConfigInput 身份等，随实际来源及配置变化持续产生新值，不是固定的小枚举。
D 向真实 Core registry 提交 1000 个不同 operation key 和 1000 个 source key，
detach／attach 后两表仍各有 1000 项，活动 lease 为零。

预期长期服务的历史元信息也有寿命边界。实际 128 个活动 lease 限额及出口缓存自身的淘汰
不能约束这几张历史表，内存随进程生命周期中的不同 key 数持续增长。
这是分枝新增 Request 协议及动态消费者的资源问题；没有 OOM 或真机内存峰值实测。

处理目标：在来源、客户端或请求生命周期结束时安全回收，或使用有界且不会重用旧资格的代次方案；
不能简单删计数后归零，让旧 ticket 再次有效。验证长时间多 key、反复 attach 及迟到旧请求拒绝。

**处置：已修复，M 复审通过并完成本地交付（2026-11-16）。**
修复提交为 `3f92145b9a9f5efc3d733ec29b7d702764a8efbd`，目标分枝为 `security/android`。
[Dart 版本表](../../../lib/common/request_versions.dart)与[Core 版本表](../../../core/request_versions.go)
保留活动持有及每表至多 4096 个冷项；有序 LRU 同时限制辅助记录，不再按历史 key 数永久累积。
高水位不随 detach 回退，重建跳过一值、已有版本仍递增一；缺项拒绝旧资格。
超过 JSON 精确整数上限时终止资格授予，取消、Complete 和释放仍可执行。
这约束历史元信息，不是进程物理内存上限保证；无活动持有的旧审核快照可在压力下失效并需重新获取。

在途 begin／session、lease／receipt 和有资格的配置依赖分别持有版本记录。
[Script](../../../lib/providers/actions/scripts.dart)在写入前通过私有 retainCompletion 获取有限续接持有，
交给 [SetupAction](../../../lib/providers/actions/setup.dart)直到 debounce／队列中的真实回调结束；
替换、Stop、dispose 和失败释放，网络及写入资格仍按原 session／receipt 收尾。
[provider 退休](../../../core/provider_stage.go)释放 lease／completion，receipt 独立保留到 Complete；
[guarded shutdown](../../../core/provider_lifecycle.go)在真实初始化／关闭及物理资源关闭后、丢弃配置指针前释放配置持有。
源码契约见[请求版本与续接寿命](source_acceptance_design.md#请求版本与续接寿命)。

D 的反例与回归覆盖 ABA、冷项平台期、迟到 begin／Close、配置及材料持有、真实图标下载和出口检测 churn。
退休反例原先遗留 source／operation 各 3 pin、geo 1 pin；四轮 shutdown 的配置 pin 原先累积为
3／6／9／12，修复后每轮归零，未用替换 registry 掩盖残留。
普通 Go 441 个 top-level／680 个 pass 事件、40 skip；no_zerotier 452／703／40，两种 vet 通过。
定向 helper-overlay race 为 14／23，真实 Script 续接 11 个业务用例通过；复用未变源码的
Android 控制编译／3 测试、pub get／codegen 及其它 Flutter 成功证据，analyze 保持 42 条既有 info。

首轮完整 Flutter 记录为 4916 个成功、32 skip、9 个错误完成事件，原失败记录保留。
旧版与新版的相同未改夹具、独立临时目录对照，均在无 receipt 的 clearPartialCommit teardown 失败；
仅修夹具的 finally 清理及目录隔离后，整组 10 个业务用例通过，业务断言主体未改。
未重新跑完整 Flutter 根套件；stock race 仍有既有 CGO helper 标签构建限制。
本项 pin 的定向并发回归在 collector 已退出后受控重新初始化；独立竞争见 F01，不能据此声明
完整 shutdown／init 无竞争。无 APK／设备验收；编译和测试均由 D 执行，M 只审代码、测试方案与证据。

本地、未入库证据位于 `.buildlog/r08-request-keys-20261116/`，首轮与设计记录冻结；修订入口为
`revision-02/implementation-source.json`，最终绑定为 `revision-02/refine/delivery-summary.json`。
54 文件与已审快照仅 Plan 状态行不同；D 提交 `45922def` 仅由 M amend Details，Tree 与父提交未变。
完成 Plan 已从当前树清理，定稿可用
`git show 3f92145:docs/features/security/r08_request_keys_plan.md` 取回。

### R09：新增 JNI 入口绕过既有 panic 隔离

位置：[Core JNI exports](../../../core/lib.go)的 `requestControl`、`setRequestSocketListener`、
`setTunRequestIdentity`、`stopTunRequest`；要求见[Core API 安全规则](../../../.agents/rules.md#core-api-safety)。

这四个分枝新增 `//export` 直接进入 Go 逻辑，没有自己的 recovery，也不经过
`handleMethodCall`／`safeGo`。Kotlin 的 `runCatching` 不能接住跨入 Go 后逃逸的 panic。
D 在隔离子进程注入 nil-map 内部不变量故障，实际 `handleRequestControl` 没有拦截，子进程退出码 2。

预期按项目规则在 JNI 导出边界隔离失败；实际处理链的 panic 可以越过该边界，
Android 上可能终止整个应用。这里确认的是缺少恢复边界，未证明外部输入能触发该故障，
也没有 JNI 设备运行证据。main 原有 `startTUN` 的同类缺口不归入这四个新增入口。

处理目标：为新增入口建立符合现有错误协议的恢复／清理边界，不能把失败伪装为成功或
保留半完成的身份／回调状态；回归注入故障及后续正常调用。具体实现尚未决定。

**处置：已修复，M 复审通过并完成本地交付（2026-11-16）。**
修复提交为 `1f242fd73b1780e6becb6fc02cb625b0e0d4b67b`，目标分枝为 `security/android`。
四个实际 export 隔离同步 Go panic，按既有 JSON error 或私有 C status 返回 `request_restart_required`；
[JNI](../../../android/core/src/main/cpp/core.cpp)将 setter／停止失败传为 Java exception，Kotlin external 签名与 envelope 不变。
[局部锁 scope](../../../core/request_native.go)只追踪当前调用持有的锁，在 panic 解锁前发布独立进程 fault。
故障进程拒绝新请求及旧资格续用；attach、Init、Service 重建和 receipt Complete 均不能复位。
原 owner 的取消、释放和真实写者收尾仍可执行，不清空未知写者计数或耐久恢复责任。

callback 替换排空 reader，并按当前所有者释放 GlobalRef／字符串；身份更新拒绝 foreign／stale generation，
整对字段失败回滚；Close 未确认时保留捕获的 TUN owner。
[VpnService](../../../android/service/src/main/java/com/follow/clash/service/VpnService.kt)的停止失败传到
[Controller](../../../android/app/src/main/kotlin/com/follow/clash/ServiceController.kt)和
[状态机](../../../android/app/src/main/kotlin/com/follow/clash/ServiceStateMachine.kt)，保留 binding／runtime，
程序化调用不误报 cleaned，系统 lifecycle callback 捕获失败，启动原错误不被清理异常覆盖。
实际 adopt 确认前保留旧身份，确认后失败保留新实际 owner；系统启动只提交 intent，不提前重标 owner。
替换按旧完整身份清理，同 intent／同 options 的正常复用仍保留。
长期边界见[JNI 同步失败契约](source_acceptance_design.md#jni-同步失败边界)。

[JNI 回归入口](../../../android/tests/jni/README.md)通过编译的生产 Kotlin declarations、生产 JNI 和 Go export
验证 19 个独立进程场景；原四入口在受控故障下均以 SIGABRT 终止。
旧版输入从指定 Git revision 完整物化，隔离仓库未暂存、已暂存、干净提交三态共 12 个原版反例符合预期，
不依赖交付时仍有 dirty diff。Kotlin 最终 8 类 127 项通过，其中 23 项覆盖 native failure 与系统消费链。
修复前分别有 6 个所有权／清理业务失败及 3 个系统启动业务失败；修复后覆盖真实 machine→Controller→service
失败反馈、正常替换、cold start、同 intent 复用及迟到旧请求隔离。

Go root 444 个 top-level／683 个 pass 事件、40 skip；no_zerotier 455／706／40，两种 host vet 通过。
定向 helper-overlay race 3 项通过；Android ARM64／NDK 28.2 的 fresh c-shared／header、生产文件 vet 与
生产 JNI 链接通过。Flutter 6 文件 67 pass、1 skip；pub get offline／analyze 通过，保留 42 条既有 info。
标准 Android package vet 在原基线和本项均因既有 CGO helper 排除而失败，不能写成该标准命令通过。
host JNI 有 Go/JVM signal-handler 共存警告；系统叶子和 config receipt 为受控夹具，未覆盖
ART、真实 Android 调度、TUN、APK、设备、完整 stock race 或完整 Flutter。
此修复不保证 native abort、runtime fatal、OOM、异步 panic 或依赖内部锁损坏可恢复；
也不证明外部输入可触发原故障。原 startTUN 缺口与 F01 未修复。

编译和测试由 D 执行，M 审代码、方案和绑定证据，未代跑。
本地、未入库证据位于 `.buildlog/r09-jni-failure-20261116/`，设计、首轮与各修订记录冻结；
最终通过对象为 `revision-03/source.json`，交付绑定为 `delivery/source.json`。
26 文件交付与获审对象仅 Plan／Result 状态文字不同；D 的 `a799bcb8` 仅由 M amend Details，Tree 与父提交未变。
完成任务文档已从当前树清理，定稿可用
`git show 1f242fd:docs/features/security/r09_jni_failure_plan.md` 和
`git show 1f242fd:docs/features/security/r09_jni_failure_result.md` 取回。

### R10：Android 退出前置失败跳过保存与 BootGuard 收尾

位置：[退出资源清理](../../../lib/providers/actions/system.dart)的 `cleanupExitResources`、
[服务桥](../../../lib/plugins/service.dart)的 `prepareRunIntent`、[Request.detach](../../../lib/common/request.dart)
和 [SystemExitCoordinator](../../../lib/providers/actions/system_exit.dart)。

触发条件是 Android 前置 `prepareRunIntent(source: exit)` 或 `request.detach()` 返回异常。
两次 await 都位于创建退出保存操作和 cleanup 内等待 BootGuard 关闭之前，且没有独立错误收集；
其中任何一步失败都会跳过保存、tray 及后续并发收尾。`handleExit` 已提前发起幂等的
`startupGuard.markClosed()`，因此不能将缺少等待写成完全没有关闭尝试。
外层 coordinator 把整个 cleanup 当作一步，捕获后继续尝试关闭 Core 和退出，无法补上内部步骤。

预期控制通道失败仍尝试相互独立的必要收尾。实际最后一次退出保存及部分收尾等待会被跳过；
数据是否受影响取决于此前自动保存是否完成。本轮只确认源码控制流缺口，未复现用户数据丢失，
不表示正常退出必然保存失败，也没有据此推断网络资源泄漏。
新前置调用来自本分枝。设计复核还确认：Dart detach 清空 client 后，localCommit 走无 receipt 路径，
不能声称当前退出保存已通过 Core 提交资格检查。只保留原 client 也不足以修复：Core detach
置 clientReady 为 false，虽可取得 lock，[beginCommit](../../../core/source_commit_marker.go)
仍会拒绝。保存顺序和提交资格须一起修订。

处理目标：分别记录前置失败并尝试其它允许的收尾，保留原错误反馈和退出 watchdog；
保存仍须遵守现有提交资格，不能为收尾绕过权限。覆盖两处前置异常及后续步骤执行顺序。

### R11：当前文档与已实现契约不同步

三个差异均经 D 核实，影响当前使用／复核；已冻结 Plan／Result 的原版本事实继续保留。

| 当前资料 | 预期与实际差异 | 复核依据 |
| --- | --- | --- |
| [延期事项](deferred_security_items.md)的“当前固定 Core”“Core 仍为” | 仍声明 `6c6e3e472bb246cc55f2e8577d9eddccc2623afc`，当前 gitlink／carrier 实为本文基线的 `7a620…` | [carrier manifest](../../../core/patches/l1_t03/manifest.json)及精确恢复检查 |
| [来源接受设计](source_acceptance_design.md)的节点快照 | 无例外地说同名冲突不纳入；实际明确批准了“结果为空时保留首个独立节点，再精确审核”的例外 | [投影实现](../../../lib/common/profile_import_projection.dart)、[专项测试](../../../test/common/profile_import_projection_test.dart)、提交 `62401ee6ee6489cf192ef9a29bc6444b6e05bb99` 的决定 |
| [服务操作指南](android_service_guide.md)的 English UI 第 2 步 | 仍要求修改 Network 后按提示 Restart；现在实际 VpnOptions 改变走自动完整应用，原盲目提示已移除 | [应用输入事务](../../../lib/providers/application_input.dart)的实际 VpnOptions 比较及[应用网络设计](../network_activity/network_activity_design.md) |

前者会使风险复核绑定错误对象；后两者使维护者误判合法节点行为、用户等待不存在的提示或重复启停。
节点 fallback 是已批准且再次精确审核的行为，不登记为“未授权导入”；Core 更新也不意味着既有风险已经解决。

处理目标：只同步仍有效的当前陈述，解释 Core 新旧证据适用边界、节点 fallback 的条件及当前 VPN 操作。
旧基线的冻结证据不改写；修正文档不授予修改 Core、取消保护或提升验收状态的许可。

## 修复中确认的独立跟进

### F01：配置 collector 与重新初始化并发访问 HomeDir

**状态：已确认，未修复；P2，独立于本轮 R01–R11 的修复范围。**
D 在 R08 生命周期回归中发现，M 核对原基线生产 overlay 与竞争堆栈后确认。
复现基线为 `ee6b7f559a921f97232fbd6f40671db9e4ee6c18`；R08 未修改此竞争的读写路径。

正常 activate 会调用 [queueInputCollection](../../../core/config_inputs.go)启动异步材料回收。
随后实际 guarded shutdown 返回并重新 init 时，collector 可仍在进入
[lockConfigInputRead](../../../core/config_apply.go)：它在取得 configMu 之前调用
[beginRequestDataRead](../../../core/app_requests.go)读取 `C.Path.HomeDir()`。
另一侧 guardedInitClash 虽持有 configMu，initializeCore 仍会直接调用 `C.SetHomeDir`；
[底层 getter／setter](../../../core/Clash.Meta/constant/path.go)没有同步，关闭流程也未等待该 collector 完成。
因此 init 的锁不能保护锁外先行读取。

预期旧回收任务与新初始化之间具有一致的目录所有权和同步关系；实际旧 collector 的读取与新 init 写入存在数据竞争。
D 在原生产代码上运行真实 apply→shutdown→init 循环，race detector 报告这两个具体访问竞争；
未证明文件被误删、用户数据丢失或设备崩溃，不将这些可能后果写成已发生事实。

后续应在 FlClash 侧明确 collector 的目录快照／生命周期和同步边界，避免把等待条件仅放在测试中；
保留现有请求资格、回收锁顺序与 shutdown 隔离，不直接扩大到修改 Core 子模块。
验收应包含无需测试预先等待 collector 的真实循环、迟到旧任务及目录切换，具体方案尚未决定。
本地证据位于 R08 的 `revision-02/`：`baseline-home-race-source.json`、
`baseline-home-race-probe_test.go`、`baseline-home-race-overlay.json` 和 `go-race-home-baseline.jsonl`。
overlay 恢复原基线生产，只增加独立 probe 并移除 IPC 测试 helper 的 `!cgo` 标签；不是原仓库完整 race。

## 验证证据与限制

M 的证据目录 `.buildlog/review-android-20261116/` 与 D 的
`.buildlog/review-d2-20261116-01/` 均为**本地、未入库**；不是干净检出的正式链接。
各自 baseline.json 绑定上面的源码对象。正文保留最小输入与交错，不以日志路径代替复现说明。

下表路径均相对于 D 的上述本地目录；每份日志对应同目录的夹具输入，不属于已入库回归测试。

| 条目 | 本地证据文件 |
| --- | --- |
| R01 | `flutter-harness/q1_with_rule_link_test.dart`、`q1-with-rule-link.log` |
| R02／R04 | `jvm/ReviewD2.java`、`jvm/ReviewD2Gate.java`、`jvm/jvm-proof-fixed.log` |
| R03 | `q4-fixed-harness.log`、`q14-update-dialog-with-assets.log`、`q15-migrations.log`、`q15-request-mode.log`、`q15-other-migrations.log` |
| R05／R06 | `review_d2_routing_counterexample_test.go`、`go-routing-counterexample.log`、`jvm/uid65.json` |
| R07 | `review_d2_with_wrapper_test.go`、`go-review-with-wrapper.log` |
| R08／R09 | `review_d2_with_wrapper_test.go`、`go-review-with-wrapper.log` |
| 全部核验结论 | `review-results.json`，含基线、源码定位、命令和 9 份关键日志的 SHA-256；M 已独立核对摘要一致 |

| 验证 | 实际结果及范围 |
| --- | --- |
| `python3 -m unittest discover -s tool -p 'test_*.py'` | 177 项中 168 通过、9 跳过；跳过项缺 Android 签名夹具，不计通过 |
| `python3 tool/restore_l1_t03_core.py --check` | 精确提交／tree 通过；不是 APK 打包／运行采用验证 |
| `python3 tool/verify_geo_assets.py` | 四类 seed 与 reference 一致；runtime loaded version 为 not_observed |
| `flutter pub get --offline` | 成功，未改锁文件 |
| `flutter analyze --no-fatal-infos` | 退出码 0，42 条 info，无 error／warning |
| D 的数据库、JVM、Go 夹具 | 支持各条目的局部复现，具体限制见正文 |

未运行新 APK 构建、安装、VPN／系统权限操作或物理网络矩阵。
真机耗电、旧 Android、跨入口整体验收及既有延期事项仍按各自计划保留。
本轮没有推送、发布、上传本地材料或修改远端状态。
