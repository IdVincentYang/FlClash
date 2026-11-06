# L5-T02 工具及发布工件获取校验 Result

2026-11-07，D-02完成本项实现及本地自验，M1已通过完整实现及I1复审；本文件为D本地交付定稿，M远端收尾尚未完成。
M首审独立复现I1：含冒号的工作位置使PATH出现workspace外的目录并选中无害假rustup；D完成窄修及自验后，M独立复核其拒绝与普通／空格位置正对照通过。
普通路径下第五次构建仍是有效证据，但不能据此覆盖I1。
任务入口见[Tasks](loop5_tasks.md)，方案及R1局部修订见[Plan](l5_t02_plan.md)。
本次证明macOS ARM64到Android ARM64 dev release的受管原入口可完成，并在对应消费者前拒绝已测错误输入；
不升级旧APK、其它host／ABI、完整CI、跨次派生缓存、源码到APK因果或设备运行结论。

## 版本与实际入口

父仓库基线为`de0b86814b5021f2b4ea361aa37271abf25c53c7`加本项WIP；Core保持
`6c6e3e472bb246cc55f2e8577d9eddccc2623afc`，原仓库和本次Core工作树均clean。
Loop6原stash `423169d0d30446cbf9fe15dbff3df1e96851131b`保留。
设计依据为原design_v2及`r1-native-assets-design-first`冻结，后者snapshot SHA-256为
`64b335f689cdf30c3b089dce38beac1188b7c9db8d08a6bcf556aaaf5fc684de`。
以下证据路径均相对`build/verification/l5-t02/implementation/`；正式用法见[构建指南](../../../development/android_build_guide.md#发布工件接受与受管构建)。

正式CLI从`managed-build-selections-third.json`选择原始材料，在不存在的`managed-normal-fifth`创建自有source、SDK、pub及Gradle状态，
再调用原setup → distributor源码 → Flutter → Gradle／Native Assets。命令、PID及退出由
`managed-normal-launch-fifth/commands.json`和`managed-normal-fifth/commands.json`保留，两层均退出0且对应process group为空。
Gradle single-use daemon PID84105已退出，未见剩余本次workspace进程引用；工作位置继续保留。

| 本次产物／绑定 | 实际结果 |
| --- | --- |
| APK | `managed-normal-fifth/source/dist/FlClash-0.8.99-android-arm64-v8a.apk`，55,189,483 bytes；ZIP native ABI仅arm64-v8a |
| APK SHA-256 | `845a3804de290e148ec52c6472ed65ea3b3b81b3389a628ac37c4ccb931c68ff` |
| hook配置SHA-256 | `d723ae4f2534032d0a410a18e70b4aecb1cea6bd0e324ba7c53408abf1192937` |
| 标准hook输出 | setup／rust_api均成功，metadata绑定本次配置及精确native input，配置／绑定依赖齐全；不是只凭APK置ready |
| 实际Go进程 | 选定绝对Go；GOFLAGS=`-mod=readonly`、GOENV=`off`、GOTOOLCHAIN=`local`，home／modcache／buildcache均为本次自有位置，CC来自已核NDK29的API24别名 |
| 实际Cargo进程 | `--locked`；RUSTUP_HOME／CARGO_HOME为本次自有位置，toolchain1.98.1，libclang及compiler／linker／archiver均来自已核NDK29 |

`managed-normal-fifth/result.json`记录原始成功输出；`post-build-audit.json`是D额外文件／源码／进程自查，不是独立M Review。
`managed-normal-launch-fifth/live-consumer-environments.json`直接观察实际Go及Cargo进程，不从版本报告或.so存在反推选择。
父PATH八个假程序及旧snapshot／home／Flutter覆写候选未被采用，marker未触发。
启动源码与本次source WIP逐项核同，全部same-run生成文件在原入口后重新核同；source仅额外生成两处标准pubspec hook配置及本次Dart绑定。
本结果及最后文档状态在构建后整理，不改变该次执行代码或材料。

## 已证明的接受与拒绝

工具接受锚、原生锁与verification配置分别保持各自唯一维护位置，职责及依据见[来源契约](../android_build_sources.md#工具接受与受管构建)。
52个安装材料根加framework固定Git对象对应53个工具角色；三套pub图另核，helper成功均不授予whole-profile ready。
三图package_config含self分别为app228、flutter_tools102、distributor65，app plugin map核87项；
287份唯一hosted归档及固定Git对象逐项核原生锁与实际文件树。
首次工具snapshot由已核SDK及完整pub闭包生成，未复用旧SDK／activation snapshot。

Maven的2204份原始工件逐项按固定官方参考接受；1903份签名在已接受精确字节上验证，301份无可核官方签名。
有限fingerprint及SHA-256共同约束签名工件；公开key候选本身不证明发布者身份。
本次JVM前重核4107个原始数据／签名文件，并使用全新Gradle内部状态。
Google部分metadata只有SHA-1的事实保留，固定官方payload的项目接受SHA-256不冒称发布者独立签名。
Gradle9.8.0正式Wrapper／distribution及15个唯一action commit引用已固定；未运行远端CI。

| 真实消费者／验证 | 实际结论与证据 |
| --- | --- |
| 正常完整入口 | 第五次完成本次双hook核对及APK；`managed-normal-fifth/`和对应launch目录 |
| SDK36缺失／替换 | 正式CLI在SDK消费者前拒绝；`sdk36-rejection/results.json`。SDK37正规localPackage由同一官方record派生，真实sdkLib reader缺元数据失败／正规元数据成功；`native-sdk37-reader-third/results.json` |
| Native Assets过滤链 | `r1-filtered-positive-second/results.json`：同一已核官方runner读取标准defines、编译并过滤环境后，两个未插桩原builder成功；捕获选择及`--locked`，默认Rust home未生成 |
| hook消费者边界 | `r1-filtered-counterexamples/results.json`：16项含2个正对照和14个反例。两hook各测漏define、缺配置、同size／mtime改配置、跨workspace、错compiler、替换Go／Rustup及伪重入；反例均在marker前拒绝，未执行被替换程序 |
| Gradle原生缓存反例 | `gradle-native-fixture/cache-corruption-bindings.json`保留同size／mtime坏JAR仍命中旧验证的红例；外层原始字节重核在JVM前拒绝，正确数据在新状态下可解析，不靠旧验证记录 |
| 有限PGP及强摘要 | `gradle-artifact-pgp-and-sha-second/results.json`：同一测试key的正确字节通过；有效签名的错误字节仍被SHA-256拒绝，未进入消费marker |
| pub／首次snapshot | `pub-consumer-guards/cases.json`、`flutter-bootstrap-guard/results.json`及`rejected-profile-selections/results.json`：正常原launcher／packager有正对照；包改字节、换根／额外包、错plugin根、缺组件／坏stamp、调用者命令／旧receipt等在相应消费者前拒绝 |
| Python／Dart检查 | R1冻结时`r1-final-unit-static/`的70 Python检查通过；I1当前`i1-path-qa/`为64+9=73通过。未变4个Dart文件format0changes／生成绑定非空analyze0issues及标准offline pub／图复核后的13项Flutter setup测试继续复用 |

边界夹具仅在原project guard之后、原builder之前加marker并停止，用于隔离拒绝点；原builder正常执行由未插桩正例及完整原入口另证。
伪重入夹具向guard提供私有参数，仍由真实runner过滤环境，不能靠该参数跳过核验。
较早人工带完整环境的hook选择窄例及Rust／Go小编译仅保留局部意义，不被计为过滤链已闭合的证据。
未变的setup_hooks45项及原材料／Git／pub／Maven测试证据按其原版本范围复用，不以测试数量替代以上消费者出口。

## 保留的失败与限制

I1原始反例保留于`build/verification/l5-t02/m-review/implementation-first-workspace-path-separator.json`（仓库相对路径）。
它实际调用生产构造器／prepare_environment及无害程序，证明裸名分派选中了workspace外的程序；不是另一次完整构建。
窄修在生产构造器创建任何workspace之前检查规范化完整位置，保留空格，拒绝PATH／配置分隔符及当前不支持的非ASCII／控制字符。
`i1-path-qa/results.json`用首冻结生产代码再次复现outside marker；新版正式CLI对冒号leaf、父路径及解析后的父alias，
以及逗号、反斜杠、换行、非ASCII位置共7项均退出2、无workspace创建且外部程序marker未触发。
生产构造器／prepare_environment的普通及带空格位置正对照均通过实际`/usr/bin/env rustup show active-toolchain`选择selected marker；
它们仅使用本地无害synthetic程序，证明搜索范围，不冒称发布工件接受或完整构建。
`i1-path-qa/impact.json`核仅生产构造器AST变化，prepare_environment、委托及绑定方法均未改变；第五次位置已规范化且满足新前提。
因此复用其正常真实链、消费者观察及APK证据；没有默认重跑旧材料或全部历史矩阵，也不更改第五次输入身份与APK记录。

提交前结构自查将固定NDK路径常量归到hook模块，由profile引用，消除checker对编排层的循环依赖；路径值及已审行为不变。
整理后73项Python检查通过，当前checker对第五次原材料的setup／rust_api只读复核通过；没有重新构建或改写原APK身份。
增量命令、材料复核及结构结论见`pre-merge-qa/`。

五次完整原入口均保留，不覆盖旧结论：

| 尝试 | 实际结果及处理 |
| --- | --- |
| managed-normal-first | 缺Platform36／Build Tools36；补固定官方材料及必需角色，不改插件源或现场自动安装 |
| managed-normal-second | SDK37.0仅有ZIP不能被原生reader识别；补官方同类标准安装metadata，不写license接受记录 |
| managed-normal-third | Cargo分派时找不到rustc；补指向已核rustup的标准代理，另以正确homes下的小编译及原hook验证分派；该次本身仍未证明R1环境传递 |
| managed-normal-fourth | 退出0并有APK，但runner过滤受管变量，Cargo无`--locked`；原`profile_ready=true`无效，单独审计为不合格，不安装／交付或追认 |
| managed-normal-fifth | 完整原入口及双hook绑定通过，M已通过完整实现及I1复审；普通路径证据按影响复用 |

R1第一份真实runner正例因错误假设shared输出目录带配置后缀而在消费者前失败，修正为官方runner实际目录后通过；
`r1-filtered-positive-first/`保留原配置、绑定、helper及整个失败runner目录。
新QA最初只复制package_config而缺package_graph，Flutter测试在加载前失败；随后用标准pub准备并复核图，13项通过。
其它原始调查／夹具准备失败继续保留在对应目录，不把失败尝试计入通过数，也不为报告重跑未受影响的旧矩阵。

首次Go hook仍出现SDK的`File modified during build. Build must be rerun.`提示，原架构已记录其输出目录依赖会使后续cache失效；
本次SDK返回成功、两个builder及原入口均完成，源输入和本次生成绑定在入口后核同。此结果不声称跨次hook cache已验收，留L5-T04继续。
Rust依赖现有实现使用NDK的API35 compiler别名；它属于已核NDK29，但不由Native Assets输入API24推导API24运行兼容已通过。
未安装／启动设备或应用，没有APK运行加载、DNS／业务收件或全组件生成因果证明。
Python／OS及受信仓库源码仍为bootstrap前提；本项不是OS隔离或对所有同用户并发改写的保证。
完整源码／预编译组件生成关系留L5-T03，跨次派生缓存／完整CI和执行约束留L5-T04，最终Android制品对账留L5-T05；本次不提前交付它们。
