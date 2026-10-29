# L1-T08 Disclaimer 删除增量 Result

本记录仅交接用户明确要求的 Disclaimer 删除，已获 M1 实现评审通过；T08 整体仍活动。
IP 去留、触发和来源仍未决，未实施对应候选。[Task Plan](l1_t08_plan.md)说明范围和后续顺序。
输入为 `4e9f1b3477814b6f199a6ebb413e6a54da6f360c`，获审快照由
`build/verification/l1-t08/disclaimer_implementation_v1/binding.json` 绑定；本地提交、
合入位置与等价性由
`build/verification/l1-t08/disclaimer_delivery_v1/binding.json` 记录。
提交前仅澄清／整理文档，生产、生成与测试内容沿用获审版本，复用 168 项验证；T08 分支与文档保留。

## 实际变化与保护边界

首次启动删除同意／退出流程，工具页删除 Disclaimer 入口，独占页面和 22 个专属 locale key 一并移除。
`AppSettingProps` 不再保存接受状态；正常生成移除 JSON／copyWith 等消费者。
旧 JSON 中 true／false 的 `disclaimerAccepted` 均按未知键忽略，其他设置保持，重新序列化不再输出该键。
没有写死 accepted 或新增替代开关，共用 Agree／Exit 文案、图标、LICENSE、版权及第三方许可保留。

`Request.begin` 仅删除接受状态 gate；未 attach、运行／停止、Auto／DIRECT／Proxy、来源 generation、
队列、取消和不静默回退继续由现有 session／原生权威控制。
`ProfilesAction` 仅删除 consent listener；启动完成后的刷新、appVisible、native started
和既有到期／开关调度保留，
没有增加调度器。公网查询、质量详情及本地 IntranetIP 均无生产修改。

## 已执行验证

| 检查 | 实际结果 |
| --- | --- |
| `flutter pub get --offline`、build_runner、intl_utils | 均成功；两类 native build hooks 临时关闭并在 finally 恢复 pubspec 原字节；锁文件无改动 |
| `flutter analyze --no-fatal-infos --no-pub` | 0 error、0 warning，42 项既有 info |
| config model／provider、通用 dialog、Request scope／receipt、profile refresh、l10n／动态 key | 144 项通过；包含新增的两种旧接受键兼容例；无失败 |
| 当前源码离线编译的 Go bridge → profile refresh consumer | 首轮因未设置 bridge 路径跳过 24 项；设置路径补跑后 24 项全部通过，无跳过／失败。合并不同用例共 168 项通过 |
| 源码／差异核对 | `lib/`、ARB 中无 Disclaimer 符号或 request_not_accepted；测试仅保留旧 JSON 兼容例。核心、IP 查询生产代码、许可证和依赖锁无 diff；`git diff --check` 无问题 |

详细日志和命令在 `build/verification/l1-t08/disclaimer_work/`，交评快照保留其副本及 hash。
测试使用合成数据、内存／临时文件和 loopback，复用本地未变的 Rust library 与 managed profile compiler；
没有使用真实订阅、数据库或凭据。旧 Disclaimer 专属两项 widget 测试已随功能删除，其他测试未删除。

## 体验入口与限制

使用新配置或带旧接受键的配置启动，预期直接进入正常初始化；工具页保留正常信息／许可入口，不再出现 Disclaimer。
旧配置兼容和请求／刷新行为有上述合成验证；启动调用链、工具页入口与许可保留以源码核对，未实际启动应用或操作 UI。
没有 Android 设备／JNI、APK、宿主网络或外部站点验证，未对待定 IP 功能作可用性或安全结论。
本轮不改 mihomo／gitlink／carrier，不 push、上传或改远端状态。
