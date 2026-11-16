# R03 测试消费者修复 Plan

任务入口：[R03](android_branch_review_issue.md#r03累计迁移未同步测试消费者)。
基线为 `security/android` 的 `d59f93b`。方案已经 M 评审通过，下述窄生产修复纳入本任务。
已批范围的关联专项及完整根门禁已在本地通过，M 实现评审通过。
交付目标为 `security/android`，按生命周期请求、订阅／分组及 Host routing 的原始引入提交分别创建 fixup，
不执行 autosquash、合入 main 或远端推送；Issue 与任务文档清理由 M 维护。

## 问题与目标

累计迁移留下 1 项 UI import 门禁失败、3 项更新弹窗夹具失败和 19 项过期 schema 断言。
目标是通过真实接口验证现有行为，使专项及根 `flutter test` 如实反映当前实现。
不放宽生产资格、不删除业务断言、不 skip 门禁；不修改 Issue、R04、Core 或远端。

原审查反例保存在本地、未入库的 `.buildlog/review-d2-20261116-01/`；
R01 的额外失败保存在 `.buildlog/r01-group-restore-20261116/`。原日志 Hash 已核对，保持冻结。

## 方案与理由

### 已分派的测试修复

- `bootstrap_test.dart` 改用项目允许的 `material_ui` import，保持 bootstrap 用例及 import 门禁原样。
- `update_dialog_test.dart` 用测试 HTTP adapter 返回合成 release，再调用真实 `request.checkForUpdate()`，
  将返回的原 Map 交给 `CommonAction.checkUpdateResultHandle`。不伪造私有 session 或绕过校验。
  保留分组、中文标题和 bullets 展示；补验有效确认、取消后的释放、克隆结果拒绝、
  弹窗打开后取消／新检查替代旧结果。URL launch 在平台边界记录调用，不打开浏览器。
  adapter、session 和全局测试状态逐例清理，不产生外部请求。
- 5 份 schema 测试使用迁移后实际 `user_version` 对照数据库声明的当前版本，替换 19 项旧预期。
  保留独立的数据、默认值、未知枚举拒绝、规则转换、排序和约束断言；补验新增表／列、
  `foreign_key_check` 和重开幂等，避免只验证版本常量。

### R01 额外四项失败的已批准处置

| 失败 | 分类及依据 | 建议 |
| --- | --- | --- |
| `local_groups_test.dart` 两个旧版本用例缺 `rules` | 夹具失配；schema 17 升级必须给旧 rules 加 `host_binding` | 用完整数据库种子移除版本之后的表／列，再设置 13／14 重开；保留原定义、选择与引用断言 |
| 空数据库备份恢复后 `.single` 无元素 | 产品回归；parser 为零实体 DB 仍提供空 global groups 和默认 App routing，使 restore 越过空输入早退并执行 override 清库 | 在 archive parser 恢复全实体空语义，保持数据保留断言 |
| 33,000 条规则删除超过 SQL 参数上限 | 产品回归；删除已分批，但新增的 Host 判断先使用未分批 `IN` 查询 | 在原事务内分批判断 Host，保留大数据用例 |

空备份修复拟落在 [archive parser](../../../lib/common/backup.dart)：当所有实体集合、全局组和
App routing 的规则／目标都为空时，保留原 Config-only 语义，不把自动初始化的空库值当作替换指令。
revision 属于元数据；禁用但仍存在的 App 规则也属于数据，不能丢弃。
非空备份维持原合并／覆盖语义；直接调用 `Database.restore(globalGroups: [])` 的显式清空契约保持。
验收包括无 DB／有效空 DB、compatible／override、现有 Profile／draft／selection／全局组／App 策略保留，
以及非空全局组备份和显式清空的反例。

规则删除拟在 [RulesDao](../../../lib/database/rules.dart) 原事务内，复用现有 900 参数边界分批判断 Host，
随后沿原分批删除入口执行。只有本次删除含 Host 规则时才更新一次 routing revision；
验证跨批 Host、非 Host、未命中 ID、未删规则及事务失败，不能降低测试数量来回避 SQLite 的合法限制。

### 根测试扩展的已批准边界

- `generated_contract_test.dart` 补齐 nullable Host binding、companion 与 JSON 契约，不手改生成代码。
- `state_run_globals` 及 Android／Proxy／Tray manager 测试先隔离复现。静态输入使用明确的 provider override；
  动态转移经真实 ApplicationInputAction。attach 采用 BootFixture 验证首次／重复／并发只启动一次，
  不以 isAttach 伪造启动，不放松输入 guard。
- DAV 核查真实 Request session、isDAVCurrent、配置及 client 所有权，保持 localhost 的 status／auth／redirect 验证。
  l10n 初始化修正不能替代对原始拒绝或 transport 原因的解释。
- pending timer 区分生产 Owner 的 dispose 义务和测试未卸载／未结束 debounce；不统一多 pump 或吞异常。
  确认生产生命周期缺陷时先交最小复现与方案。
- Home 保留原 1440→380 resize、内容、断言与真实布局。ProfileItem 已稳定复现尾部动作在 106px 约束下溢出 71px，
  M 已批准按卡片实际 constraints，在宽版文字与窄版紧凑图标动作间切换；不改 Home／全局断点。
  切换预算包含 ListItem padding、标题间隔、菜单、实际标签和文本缩放；保留选择／审核禁用条件、回调及进度。
  紧凑动作复用 glyph、完整本地化状态标签和既有点击尺寸，补阈值邻近、语言、缩放和交互测试。
  其它新增生产修改仍待 M 批准。

## 实施与验证

1. 先在当前
   [全局组恢复契约](../proxies/local_groups_design.md#保存许可与并发)明确空 archive 与显式空载荷的区别；
   App／Host 文档沿既有链接引用。不改历史 Plan／Result，不新增平行规范；SQL 边界由回归测试保护。
2. 先在 `d59f93b` 复跑关联专项并独立保存输入版本、配置和结果，再修复测试／获准生产路径。
   按 UI、迁移和额外四例分组验证；扩大至关联 request、backup、database／provider 测试，包含 R01 回归。
3. 最后运行不排除用例的根 `flutter test --reporter expanded --coverage`，以及 pub get、format、analyze。
   使用真实 test assets；widget/root 不采用 `--no-test-assets`。CI 关闭 Go hook 的配置仅临时用于测试并恢复原字节，
   Rust hook 保持启用，编辑器测试所需动态库必须来自同一源码。复用缓存，不复制大型构建树。
4. 根测试若暴露其它失败，集中按测试失配、环境或产品问题向 M 报告，不默认扩大修复。
   已知 macOS Rust loader 问题先核对真实产物与工具链；环境未恢复就明确根门禁未通过，不 skip 该测试。
   成果与日志分别绑定当前快照；本机通过不宣称 Linux CI、APK、设备、VPN 或真实更新服务已验证。

当前本地、未入库的证据位于 `.buildlog/r03-test-consumers-20261116/`：
`before-targeted-summary.json` 记录 65 通过、27 失败；`after-regression-summary.json` 记录关联专项 196 通过。
`root-tests-summary.json` 保留首轮根运行的失败与未完成项；扩展夹具专项 43 通过，Home 17 通过，
新增布局专项 9 通过，widgets／Home／Profile review flow／UI lint 联合回归 713 通过。
这些命令有重叠，不合计为独立用例总数。

最终完整根运行记录在 `root-tests-02.log` 及其 summary：4239 通过、115 个既有环境依赖跳过，
无失败、无未完成用例。Rust hook 与真实 test assets 保持启用，Go hook 按 CI 测试方式临时关闭，
`pubspec.yaml` 原字节已恢复。跳过项依赖未提供的 JVM／Core bridge 或 managed compiler；没有新增 skip。
analyze 无 error／warning，42 条既有 info 与扩展修复前完全一致；Dart format、Markdown lint 和 diff 检查通过。
这证明本地 Flutter 测试门禁通过，不代表 APK、设备、VPN、Linux CI 或真实更新服务已验证。
