# L2-T02-02：Profile 策略草稿验证记录

本项已实现真实 Profile 草稿页面、独立持久化、旧材料提取、生成预览及备份恢复。本轮修订后的 65 项本项消费者及 46 项既有 01 模型／编译测试通过
；上轮扩大回归为 718 项通过、3 项基线既有失败，未受影响证据沿用，详见下文。M1 已通过 R1／Q1 修订与补证的实现复审，当前进行本地提交和合入，本项尚
未完成本地交付，整个 L2-T02 未结束。

设计与边界见[本项设计](l2_t02_02_plan.md)，状态由
[任务清单](l2_t02_tasks.md#l2-t02-02-profile-策略编辑持久化与迁移)维护。**保存仅产生草稿，不代表生成配置正在运行或应用已
受管。** 最终应用及来源资格仍由 03 接续。

## 1. 已验证的用户入口

| 用例 | 实际观察 | 消费者依据 |
| --- | --- | --- |
| 从 Profile 菜单进入草稿 | 独立页面可编辑，退出不选择或应用 Profile | [真实页面测试](../../../../test/views/policy_draft_test.dart) |
| 保存、重开、排序及资源选择 | 域名／IP 顺序、显式默认、DNS、静态组及认证保留 | 页面、生产 action 和实际 SQLite DAO |
| 不完整、未知版本或冲突 | 不完整可保存；未知结构只读保留；值不同或 Profile 缺失时拒绝覆盖 | [DB 测试](../../../../test/database/policy_drafts_test.dart)、[模型与预览测试](../../../../test/common/policy_draft_test.dart) |
| 提取旧规则 | Profile added→global→源顺序、standard disabled 和 custom 有效列表与真实 DAO 一致 | [捕获测试](../../../../test/common/policy_migration_test.dart) |
| 不兼容迁移 | 中途 MATCH、有效 IP REJECT、custom 同 ID disabled 及不合格资源保持阻断 | 原始字节、行序及关联材料保留；删候选或补默认不解除 |
| 生成预览与复制 | 实际 01 编译器生成；EditorPage／CodeForge 只持脱敏文本；完整复制须确认 | 真 Editor 与 fake Clipboard，UTF-8 认证值核对 |
| 备份并恢复到第二份 DB | 实际 VACUUM→ZIP→解析→MigrationData→applyRestore 保留正文及顺序 | [备份消费者测试](../../../../test/providers/policy_draft_backup_test.dart) |
| 备份确认和失败 | UI 取消不调用 backup；快照含草稿但未确认时不调用 deliver；恢复 SQL 失败回滚且提示不带秘密 | 实际冻结快照、真实事务、fake deliver |

页面显示未保存／已保存、输入未完成／待迁移及预览校验状态。两个默认不从旧 MATCH 推断；旧 DNS 保留在历史材料中，由用户明确配置新服务和
bootstrap。普通 Profile 编辑、传统预览与运行配置继续沿原路径。

## 2. 本项测试矩阵

| 文件 | 通过 | 失败／跳过 |
| --- | --- | --- |
| `test/database/policy_drafts_test.dart` | 9 | 0／0 |
| `test/common/policy_draft_test.dart` | 11 | 0／0 |
| `test/common/policy_migration_test.dart` | 15 | 0／0 |
| `test/providers/policy_draft_backup_test.dart` | 10 | 0／0 |
| `test/views/policy_draft_test.dart` | 20 | 0／0 |
| 本项合计 | 65 | 0／0 |
| 既有 `test/common/managed_profile_test.dart` | 46 | 0／0 |
| 本轮消费者合计 | 111 | 0／0 |

测试使用临时 SQLite DB／归档、合成凭据及 fake Clipboard／deliver。保存、退出和预览的 Core mock 无交互，setup 自
动应用计数为零；当前 Profile 选择不变。真实 WebDAV 传输未执行。

DB 矩阵包括 schema 11→12、表已存在时重复升级、普通 upsert 保留、删除级联、同值 CAS 仍允许写入、merge 缺行保留、
override 非空实体替换、onlyProfiles、未知正文、孤儿／重复拒绝及事务回滚。Config-only 和有效空 DB 归档都沿用全实体空输入保留
语义；v0 经旧转换产生非空实体时仍进入原覆盖路径。

普通保存的 SQL 错误只返回固定失败类别；涉及草稿的恢复错误使用固定提示，保留原有 partial-commit 恢复语义。关联错误在请求 mutation
前拒绝。最终消费者及上轮回归日志中合成秘密标记未出现，不能据此推导所有旧诊断入口都已脱敏。

本轮针对 M1 的 R1，原迁移快照的资源投影直接复用 01 的节点／静态组解析器。原值中的域名地址、缺 server／port、越界 port、认证半对或空值
、非法／null UDP、空组、重复成员及非列表材料共 12 个反例产生资源位置问题，提示不包含名称、认证或解析异常正文。原始字节和快照保持不变；即使修好候选，
或删除候选后保存重开，预览仍被历史材料阻断。真实页面另验证“创建独立草稿”的取消与明确确认；确认后才在待保存的新草稿中放弃迁移材料，不修改原 Profile。

Q1 使用真实 Profile 菜单路由、系统 back／PopScope、页面返回按钮及生产 action／SQLite DAO：取消继续编辑、放弃不落库、保
存成功退出；SQL 失败与 CAS 冲突仍保留输入且 loading 收敛。真实 DB 事务 barrier 挂起保存时，普通编辑和两种返回均不生效。另在离页保
存期间强制销毁旧路由并打开另一 Profile，释放 barrier 后旧保存完成无 disposed 异常，新页面保持自身原选择，并以自己的 raw CAS
成功保存。未因此修改页面生产代码。

## 3. 扩大回归与静态检查

| 检查 | 实际结果 |
| --- | --- |
| 锁定依赖解析 | `flutter pub get --enforce-lockfile` 通过；依赖文件未改 |
| 正常生成 | build_runner 与 intl_utils 通过；未手改生成文件或关闭 native hook |
| 格式与分析 | 变更 Dart 格式通过；分析 0 error、0 warning，保留 42 项既有 info |
| 仓库 lint | 本轮 18 项通过、0 失败、0 跳过 |
| 上轮扩大回归 | 721 项：718 通过、3 失败、0 跳过；本轮未重复运行 |

上轮回归覆盖既有 DB 迁移／DAO、备份与应用迁移、旧配置合成及 DNS／NTP 覆写、Profile provider、Overwrite 相关页面、
widgets、l10n 和 lint。schema 升级测试的当前目标断言同步为 12。

三个失败均来自未修改的 `test/widgets/update_dialog_test.dart`：分组发布说明、分组标题本地化和旧 bullets 回退。旧
用例直接提交构造的 release Map，被现有 `Request.validateVersionResult` 的查询会话校验拒绝。已从 `12e694c`
提取原始 Dart 源码并单独复现：4 项中 1 通过、同样 3 项失败；请求、处理逻辑及该测试的内容与当前源码一致。

这三项没有记为通过或跳过，也未在本项改动它们。基线条件与原始日志见
[基线绑定](../../../../build/verification/l2-t02/subtask_02/implementation_v1/update_dialog_baseline_binding.json)
及
[基线结果](../../../../build/verification/l2-t02/subtask_02/implementation_v1/update_dialog_baseline.jsonl)
。

## 4. 环境、产物与复现

本轮为 macOS 27.0.1／arm64，Flutter 3.47.4、Dart 3.13.3、Go 1.26.4、Rust／Cargo 1.98.1。本项
源码基线为 `12e694c94e94adb197a8637313b735d912b398d9`，Core 仍为
`6c6e3e472bb246cc55f2e8577d9eddccc2623afc`，Core、gitlink 和 carrier 未改。

本机现有 Rust dylib 出现 LINKEDIT 对齐错误。使用项目锁定版本及相同 29 份 Rust 输入，以 locked／offline、
release strip=none 构建可加载的本地测试库；经 dlopen 和真实编辑器用例验证。生产 Rust 源码、pubspec 和打包参数未改。现象
与 [Rust 上游记录](https://github.com/rust-lang/rust/issues/157750)一致；本项没有宣称修复默认
macOS 打包链。本轮继续复用该同源测试库；只提取复用 01 的现有资源解析函数，未改变其校验语义。46 项既有模型／编译测试重新运行，Core／真实 DNS
消费者未重跑。

本地证据位于忽略目录，不随源码提交或上传：

-
  [检查命令与环境](../../../../build/verification/l2-t02/subtask_02/implementation_v2/checks.json)
  、
  [复验脚本](../../../../build/verification/l2-t02/subtask_02/implementation_v2/verify.py)
  。脚本从仓库根执行，可按检查名选择增量范围；本轮只运行记录中的消费者、生成、格式及分析。锁定依赖解析和扩大回归命令沿
  [上轮检查记录](../../../../build/verification/l2-t02/subtask_02/implementation_v1/checks.json)
  ；上轮回归仍因上述三项返回非零。
-
  [本项消费者](../../../../build/verification/l2-t02/subtask_02/implementation_v2/consumers_final.jsonl)
  、
  [扩大回归](../../../../build/verification/l2-t02/subtask_02/implementation_v1/regression.jsonl)
  、
  [汇总](../../../../build/verification/l2-t02/subtask_02/implementation_v2/summary.json)
  。计数按非 hidden 的 testDone，fixture／loading 不纳入，基线复验不并入本项计数。
-
  [Rust 制品绑定](../../../../build/verification/l2-t02/subtask_02/implementation_v1/rust_artifact.json)
  及
  [源码输入](../../../../build/verification/l2-t02/subtask_02/implementation_v1/rust_source_binding.json)
  。直接运行保留库限当前宿主 ABI；其它环境需要从同源重建。测试通过项目已有的
  `FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR` 选择库目录。
-
  [窄屏布局截图](../../../../build/verification/l2-t02/subtask_02/implementation_v1/policy_draft_narrow.png)
  仅作 Flutter test 字体下的几何观察，不代表真机字体效果；临时捕获源保存在
  [capture 绑定](../../../../build/verification/l2-t02/subtask_02/implementation_v1/capture_binding.json)
  ，正式测试保留布局／点击断言。

原实现包保留在 `implementation_v1/`。源文件、相对原受检树的修订、变更快照和证据校验值由
[本轮绑定](../../../../build/verification/l2-t02/subtask_02/implementation_v2/binding.json)
维护；M1 的原三份文档及已审设计快照仍保留。

## 5. 限制与交付阶段

- 结果只证明草稿、迁移和预览消费者；没有最终 setup／T01 受管应用、运行资格或新来源撤销能力。历史迁移材料及“预览已校验”不能成为 03 的运行许可。
- 没有读取真实用户 DB、备份、订阅或凭据；没有安装／启动用户应用、操作设备、修改宿主 TUN／系统代理或发送外部测试流量。未构建 APK，未验证设备 IME
  、真实剪贴板或 WebDAV 上传。
- 01 的协议、RuleHost 和 DNS／路由剩余限制沿[首项结果](l2_t02_01_result.md)及
  [总体设计](l2_t02_plan.md#10-残留风险与不再承诺的能力)承接，没有重复改写为本项重新证明。
- M1 已通过实现复审；当前按约定完成本地提交、合入 `security/android` 与临时分支清理。整个 L2-T02 完成前不推送。
