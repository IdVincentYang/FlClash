# L5-T01 Android 构建来源基线验证记录

M1已通过implementation_v1实现评审；本记录随本地交付提交定稿，远端交付待M收尾。范围见[Plan](l5_t01_plan.md)，任务状态由[Tasks](loop5_tasks.md)维护。
本次交付来源说明及只读工具，证明选定材料与实际APK的字节／metadata关系，明确未覆盖和unknown；不证明全部工件可信、完整源码生成、运行安全或整个Loop5通过。

## 对象及实现

父仓库输入为`c45563eb36ebd9a6b7cff9d1802715e7ebb053f1`，Core固定`6c6e3e472bb246cc55f2e8577d9eddccc2623afc`且clean。
复用该版本ARM64 dev release，55,180,515 bytes、SHA-256 `0550bfd0c8ff710fd409579635592657303611b63844529879a64f97fce2d425`；未重新装配，也不把旧T04安装事实套给本包。
实际来源及限制由[长期基线](../android_build_sources.md)维护，操作见[构建指南](../../../development/android_build_guide.md#构建来源只读对账)，不在本记录复制接口设计。

文档基线先于工具／测试，原边界与顺序记录于本地`implementation/document-baseline.json`。
新增Python标准库工具及最小合成测试；生产修改只有工具，未改应用、生成代码、Core、第三方依赖源码、锁文件、gitlink、carrier或构建配置。
工具只用调用者明确选择的APK、记录及输入，POSIX descriptor-relative open／O_NOFOLLOW约束相对路径，不执行被查对象或网络请求；当前仅macOS实际验证，缺安全读取能力的平台拒绝。

## 实际对账与unknown

| 层次 | 实际观察 | 结论范围 |
| --- | --- | --- |
| APK实际枚举 | 401个条目、10份ELF64 ARM64 native、1份DEX；无参考时仍完整枚举，401项均未覆盖 | 枚举独立于记录，不能删记录掩盖包内对象 |
| 选定条目参考 | 401项hash对应，未覆盖0，APK上下文／条目／来源输入矛盾均0 | 只是完整的条目参考覆盖，不是完整来源／生成覆盖 |
| 材料关系 | 33条核同，涉及10个native和5个Geo相关条目；其余386个包内条目无已核材料关系 | 转换前输入hash、同字节、完整payload嵌入分别报告，不把已核输入当编译因果 |
| 所选输入身份 | 53个显式文件／目录选择，1680个不同路径的输入身份核同，包含配置、源码候选、hooks声明依赖及工具／工件metadata | 这是当前身份观察；可能含测试／其它平台源码，不声称全被旧构建使用或是完整输入闭包 |
| 嵌入与动态导入 | libclash有2个WASM magic候选；核到1份完整6,850,909-byte payload。8个native导入名不列在APK | 候选不是2个已识别模块；导入名不是设备加载或漏装结论 |
| DEX／Go声明 | DEX有2509个class definitions，R8映射交集2509个原名；Go版本／revision／tag与选定期望一致 | R8零计数不证明absence，Go声明不认证工具发布者／来源生成 |

额外源码是在当前工作区观察的，原构建记录只绑定12个本次修改文件，不能补造完整历史因果。
旧hooks列出的4个Git元数据引用未读取，避免潜在认证配置被带入证据；完整构建上下文因此仍有明确缺口。
当前材料足以核本项声明的字节关系并列出缺口；重新装配不能反证旧包来源，因此未为报告或这些unknown重复构建。

来源／生成重点仍为EasyTier声明源码commit未在固定公开repo解析、SQLite预编译件的实际引擎版本与生成链、engine及Maven等发布认证、实际工具／缓存／CI约束，落点见Tasks的T02–T05。
T01不修改它们或启动后继；来源基线与工具的退出0均不升级这些结论。

## 验证与复现

| 检查 | 结果 |
| --- | --- |
| `python3 tool/test_inspect_android_build_sources.py -v` | 最终26个顶层测试通过，另含多组subTest反例；只用最小合成ZIP／ELF／DEX／记录，无编译或设备 |
| 实际只读CLI | 对上述显式APK、外部记录及53个选择执行，退出0／consistent_entry_references；实际覆盖和unknown见上表，无越界或矛盾 |
| `flutter pub get --offline --enforce-lockfile` | 退出0，锁文件未变，未升级依赖 |
| `flutter analyze --no-fatal-infos` | 退出0，42条既有info，无新增warning／error |
| 文档／源范围检查 | 8份Markdown沿用MD013关闭，lint通过；98处本地文件／锚点引用有效，diff检查通过；1份Mermaid仅做静态检查，未验证渲染 |

合成正反例覆盖无记录／空记录／删记录／新增无记录条目、缺期望条目、错APK／条目／材料hash、同名异物、错ABI／已解码版本、转换输入与嵌入字节、DEX/R8、ELF动态导入及无法解码metadata。
范围反例用外部文件inode作为读取tripwire，覆盖未选输入、绝对／Windows／parent路径、目录内文件／目录symlink、单文件选择扩权及archive member越界；APK重复／symlink／越界／损坏条目拒绝。
源码样本若被执行会留下marker，检查后marker不存在；网络调用设tripwire；显式输入树内容／mtime未变。CLI进程分别验证0／1／2退出码和JSON输出。
首轮22项、扩展中25项及最终26项日志分别保留，不把测试数相加；没有声称修复原基线回归。

本次未变Dart／Android产品代码，没有覆盖本Python工具的Flutter运行测试集；未重跑全量UI矩阵，原About五项已证基线失败保持，不顺手清修。
也未执行生成器、Gradle、Native Assets构建、AVD／app／ADB／桌面CU或公共业务测试。

最终窄测及实际CLI输出为本地忽略目录`build/verification/l5-t01/implementation/`的`python-tests-complete.log`及`actual-check-complete.json`。
实际复现使用同目录的`actual-record.json`、`actual-record-context.json`和`check-actual.sh`；冻结包另提供使用冻结工具／记录的`reproduce.sh`。
命令逐个列出调用者选择，记录中的路径不能新增授权；源码候选／hooks路径只在这些选择内读取，不扫描其它用户目录。
原APK／R8 mapping在获审`design_v1`包中保留。后续工具和材料变化会使旧记录失配，须保留原记录另作新绑定，不回写旧冻结证据。

## 交评与限制

完整实现快照存入`build/verification/l5-t01/implementation_v1/`，包含工具／文档源、测试／分析日志、实际选择／观察记录和结果，引用不变的design_v1原APK及原构建证据。
输入身份、metadata、R8、材料对应各自只支持该层关系；发布者认证、完整生成与运行加载保持未验证，386项未绑定材料不能被压成全部通过。
不合资格缓存拒绝、Wrapper／依赖验证、CI及关键生成来源的处置仍属后续任务；Core约束、Loop6结案及延期备忘、DNS R1／Core日志race不变。
M1核同本包10份源与32份文件校验，独立运行冻结工具／记录复现上述实际结果，并复验4个既有顶层测试，未发现必修问题；新观察另存`build/verification/l5-t01/m-review/`，没有回写冻结包。
提交前结构检查覆盖工具及邻近测试的职责、依赖和汇总路径，无需结构调整。获审后仅更新5份任务／索引文档的评审与交付状态，工具及长期契约未变，原窄测／实际对账／分析证据继续有效。
本地交付的最终commit／tree／parent及冻结源码等价绑定留在`build/verification/l5-t01/delivery.json`；M随后独立收尾／推送／核远端，本记录不将本地合入等同远端交付。
