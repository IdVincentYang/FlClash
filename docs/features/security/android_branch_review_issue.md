# Android 分枝累计改动 Review Issue

本文汇总 Android 专用分枝相对 `main` 的已确认问题，供后续修复使用。
评审者为 [R] FLClash Review（M），每项均与 FlClash D2（D）讨论核验后收录。
R01–R05 已修复并完成本地交付；R06–R11 尚未解决，按序由 D 修复、M 评审后更新处置。
下文问题事实绑定原评审基线；修复版本与验证边界见对应条目的处置记录，不升级整体阶段验收状态。
共收录 11 项：3 项 P1、7 项 P2、1 项 P3。

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

### R10：Android 退出前置失败跳过保存与 BootGuard 收尾

位置：[退出资源清理](../../../lib/providers/actions/system.dart)的 `cleanupExitResources`、
[服务桥](../../../lib/plugins/service.dart)的 `prepareRunIntent`、[Request.detach](../../../lib/common/request.dart)
和 [SystemExitCoordinator](../../../lib/providers/actions/system_exit.dart)。

触发条件是 Android 前置 `prepareRunIntent(source: exit)` 或 `request.detach()` 返回异常。
两次 await 都位于创建退出保存操作、调用 `startupGuard.markClosed()` 之前，且没有独立错误收集；
其中任何一步失败都会使这些后续操作根本未被调用。外层 coordinator 把整个 cleanup 当作一步，
捕获后继续尝试关闭 Core 和退出，无法补上已跳过的内部步骤。

预期控制通道失败仍尝试相互独立的必要收尾。实际最后一次退出保存及关闭记录会被跳过；
数据是否受影响取决于此前自动保存是否完成。本轮只确认源码控制流缺口，未复现用户数据丢失，
不表示正常退出必然保存失败，也没有据此推断网络资源泄漏。
新前置调用来自本分枝；普通成功 detach 后 local commit 仍可按 client 身份保存，不属于本问题。

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
