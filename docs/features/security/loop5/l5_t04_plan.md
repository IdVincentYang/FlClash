# L5-T04 构建执行、缓存与CI约束 Plan

任务及归属见[Tasks](loop5_tasks.md)。本项让获审构建入口只采用与当前输入／工具／目标相符的派生物，失败保留旧有效输出，并分开编译、签名和发布权限。
输入基线为`44ff3ddffce549cc4d570ef63697cd5883ba8d5d`，Core固定`6c6e3e472bb246cc55f2e8577d9eddccc2623afc`且clean；M已通过design-second设计及review-v3完整实现评审，I1／I2均闭合；文档baseline先于实现。本次为D本地交付定稿，后续M收尾及远端核实待完成。
T03定稿从`041c39d`历史复用；[原EasyTier源码／生成延期](../deferred_security_items.md#loop5-t03-easytier-wasm-源码与生成对应)不扩展为本项缓存或权限例外。

## 问题与目标

开发者换源码、工具或构建配置后，需要拿到相应新产物；相同输入的合法重复构建应复用，坏缓存不能因size／mtime相同被装包。编译或提交失败时，旧库、JNI副本、头文件和有效记录不能被半次更新破坏。本地打包不应取得发布凭据；CI发布只能消费本次受控生产链的指定产物。

静态调查已确认以下机制，原始版本及位置绑定在`build/verification/l5-t04/investigation/source-observations.json`，不是本项实测：

- `Fingerprint.addFiles`会丢弃缺失文件，Go依赖枚举又过滤Core目录外路径；`BuildCache`虽有进程／file lock，输出只核size／mtime，记录还可决定读取路径。Go安装先清头目录、替换多份文件，最后才写记录，缺整组回滚。非lib的Go与Helper输出路径不含arch，cache key却含goarch，不同key会写同一路径；Android lib／headers有ABI目录，不能混称。
- Native Assets先比较实际input JSON及依赖hash，编译hook不因普通env改变而失效。Go将输出目录列为输入，目录只反映名字；post-cutoff修改记严重提示但runner仍返回Success。Rust库本身是CodeAsset输出。只修内层BuildCache不足以覆盖外层命中。
- 受管入口已分配新SDK／Gradle等状态并重核raw材料；T02原生Gradle同size／mtime坏JAR红例及其外层拒绝继续有效。其upload／publish task前缀禁用不是完整发布边界或网络隔离。
- CI未统一声明最小token权限，checkout凭据持久化未关闭；Android私钥在编译前出现，发布job主要依赖build状态；远端缓存含已编译hooks。Telegram镜像／Python依赖仍浮动，Pages还要单独核workflow_run来源和tag身份。

范围为Android实际入口、共享缓存实现及现有CI调用链。保持一个受管macOS ARM64→Android ARM64 dev profile、原生锁和工具policy；不改Core／依赖源码、gitlink、carrier、native tags或正常功能。其它host和真实远端执行的证据边界分别说明。

## 方案与理由

### 缓存由生产者定义，校验与提交在同一所有权内

`BuildCache.run`增加生产者预先声明的精确输出计划和私有staging回调：Go定义主库、JNI副本及两处生成头集合；Helper适配同一API并将Cargo target放入本generation私有work目录，避免迟到编译器改写后续run待复制的共享target文件；不改变功能，合法BuildCache命中仍跳过编译。记录升级schema，旧记录成为miss，保留原文件；candidate record不能自选绝对路径、上跳或漏掉必需输出。读写核实际类型／链接、受控root及内容SHA-256，拒绝未拥有的目录。

沿现有Fingerprint补全必需输入及缺失状态，optional配置显式记absence；使用原生Go依赖图及锁定材料、实际命令／target／tags／config，以及现有hook binding中已核的工具选择。缺失必需项失败，工具version文本不单独授信。构建前后重核输入身份；变化、取消或未知退出不提交。
锁改按canonical `rootDir`共享一个进程锁及固定的`.dart_tool/setup_build_cache/outputs.lock` file lock，不再按cache key隔离写者；锁路径不随record schema变化，禁止输出plan越出该root及通过链接另指共享目录。相同root的不同key全部串行，包括非重叠输出；这是保留现有目录／消费者、避免新增逐路径锁集合的保守取舍。不同root仍可独立构建。不声称旧版本未采用此协议的写者也受保护。

`BuildCache.run`直接调用时，从指纹／命中检查前持锁，到staging验证、替换、record、回滚及backup清理完成后才释放。`buildPlatform`使用同一个root锁作用域覆盖Go→读取Core摘要→Helper→manifest和最终输出核对，内部cache调用复用该私有作用域，不重复取锁；否则逐次run加锁仍会在Core／Helper之间混入另一target。外层作用域保留各run的旧文件／record backup直到Helper及manifest成功，外层失败按反序恢复已安装项；manifest也走该staging／恢复机制，不在作用域外裸写，不另建持久化状态机。key继续区分记录与指纹：第二个key获锁后必须重核实际输出，旧key不能以自己的记录跳过已被替换的字节。

每次构建使用独占创建的staging／backup generation，commit、恢复和目标目录清理均同步／await在锁内完成，不派出解锁后仍能改live路径的任务。失败先恢复旧组及旧record，再放行下一writer；恢复失败保留backup、使对应记录不可命中并拒绝本次装包。迟到子进程只能写自己的staging；锁外cleanup只可删其独占generation，不能按输出路径、key、PID或目录前缀恢复／删除live文件。状态不明保现场并失败，不按旧PID杀进程。
此处不是跨目录断电事务，也不把返回路径承诺成永久版本快照；协作写者的cache／整组发布受上述公共锁保护。受管装包另用自有snapshot及打包前后身份核对，不将其串行前提替代共享cache的锁规则；未协作外部reader同时读取半组的行为不在保证内。

记录用于本地完整性与失效判断，不能证明历史生成。受管入口不导入外来BuildCache、GOCACHE／Cargo target、Flutter／Native／CMake／Gradle派生状态；继续复用T02接受的raw材料。新状态由本次实际生产后才加入既有`bind_generated/check_generated`的内存期望，不从候选自身计算“可信”回执。普通未受管入口的缓存一致性改进不升级为受管来源证明，也不抵御已控制同UID／OS的写者。

### 外层真实消费者也必须看到变化

沿既有hook bridge及标准user-defines加入影响构建的受管输入摘要，包含实际工具选择、配置和有效flags，仅写自有profile快照，不改共享checkout或全局配置，驱动Native Assets input变化；子hook仍核真正的C compiler／ABI／API字段，不靠手工env或库存在作通过。Go改声明实际输出文件依赖，Rust保持原CodeAsset及builder，均不修改第三方runner。

受管controller从固定SDK实际Flutter Gradle task的classloader取得原ExecSpec Action及完整注册Android rules，核executable／cwd／source／output及TargetFile／TargetPlatform／BuildMode／DartDefines／ABI／API，保留原参数运行两次assemble checkpoint。首轮允许同时产生正常AOT；从SDK实际写出的.last_build_id定位本次buildDir，只删除本次build_hooks.stamp进入第二次原依赖检查，保留内层合法缓存。第二次须稳定、两hook实际生产者metadata及输出字节须与首轮期望核同；原Gradle task随后照常执行及装包，前后再次核同。每个原task execution最多两次checkpoint；SDK正常网络retry的新execution保留独占日志／报告，不手动重复打包来凑通过。

SDK的BuildHooks是原注册Android rules的内部依赖，不是可单独选择的CLI target。--build-outputs排除.dart_tool中间物，只作诊断；实际.last_build_id、SDK在该目录产生的stamp／result／depfile及metadata均不是授权receipt。资格仍来自本次干净输入、实际原SDK执行、已核工具和生产者字节；不手算buildDir、不改SDK、不导入外来派生状态。首次未注册target失败及网络retry等实际偏差留[Result](l5_t04_result.md)，不倒改旧冻结。

已实际产出的Go／Rust输出及头在打包前后与本run期望核同；同size／mtime坏物、跨run伪记录、错误输出清单不被追认。C++／JNI／Gradle继续原消费者和新内部状态，不重开T02坏raw缓存结论，也不以清所有全局缓存解决问题。

### 发布意图与凭据分开

本地`setup.dart`维持package入口、受管干净env和既有正常下载；拒绝不合资格的publisher／release配置、pre/post shell hook及Gradle发布任务，改为清楚失败，不能静默跳过后称全成功。核实际distributor命令、配置和SDK遥测开关的消费路径，依赖GET与上传分开。目标是获审入口的已知调用链和受控收件；不宣称前缀、env或此方案构成所有子进程的OS网络隔离。

CI保留普通检查、正式签名及既有发布目的地；默认`contents:read`，需要读取Actions API／制品的gate及消费者另加`actions:read`，所有checkout关闭凭据持久化。编译run内派生cache保留，跨run只复用有原生锁／接受依据的raw材料，不恢复外来已编译hook／target或可执行SDK快照。

#### Release job、首个凭据消费者与资格次序

CI helper固定GitHub API origin、repo及构造路径；官方artifact 302跨源下载必须剥离Authorization／cookie／其它发布token，不接受候选URL，不打印签名URL或响应正文。实际重定向／错误路径纳入假token及localhost反例。

下面是对现有build.yaml的职责拆分；gate仅使用只读GITHUB_TOKEN，没有发布secret或secret service。签名／发布job须在job-level `if`同时满足canonical repo／push／tag基本条件、对应gate成功及eligible输出，才可启动；不使用`always()`放行失败／缺失依赖。

| job／角色 | 前置及信任输入 | 首个权限／凭据消费者 |
| --- | --- | --- |
| release_gate | GitHub事件上下文、固定repo及Git ref API | 只读计算；成功只表示严格release资格成立 |
| build matrix／notes | release_gate；原检查通过；绑定的源码SHA | 仅编译、产物及notes上传，无发布secret |
| sign_gate | Android producer成功，实际artifact ID及API／字节检查 | 只读；失败不启动签名job |
| sign_android | sign_gate成功；下载及复核其确切ID | 仅apksigner step注入keystore及密码 |
| publish_gate | sign／其它平台／notes成功，精确ID集合及重新核tag | 只读；在任何发布secret service之前完成 |
| publish_telegram | publish_gate通过，允许pre／stable | job service才取得API_ID／API_HASH；发送step才取得BOT_TOKEN |
| publish_github／tap／fdroid | publish_gate通过，且stable | GitHub为contents:write／actions:read；其它目的地contents:read／actions:read，SSH key仅对应push step |

release_gate只接受`chen08209/FlClash`的非deleted push、`github.ref_type=tag`及完整`refs/tags/…`，tag按`v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-pre\.[1-9][0-9]*)?`作fullmatch。用固定repo的Git refs／tag对象解析peeled commit，须等于`github.sha`，并核源码pubspec版本等于tag去除v及pre后缀的版本。gate输出仅固定字段：eligible、stable、version、tag、commit、run_id、attempt；缺字段、错误类型或API失败不得给eligible。sign_gate／publish_gate在临近相应角色启动前再核tag绑定与当前run／attempt，保持原commit，不随移动tag改选输入。

Telegram的API_ID／API_HASH确实在`services.env`，不能等服务启动后的第一step才做授权检查；publish_gate及该job的条件在服务创建前生效。该job取得的是已获准发布角色；实际下载／发送前仍复核固定产物，不把服务已取得凭据描述成尚未授权。其它发布secret不放workflow／job级env，也不传给编译、notes、gate或setup。这里保留GitHub自身GITHUB_TOKEN／artifact上传机制所需的受限能力，不称编译绝对没有任何token。

Android setup增加`--android-release-candidate`，仅Android pre／stable可用：Gradle消费env配置，保持正式package identity、只用开发签名，保留原distributor命名。候选不是发布件，和现有dev profile混用先拒绝；未选择该意图时保持原行为。sign_android先无secret下载／核候选，再在唯一签名step取得key、apksigner重签并核选定证书／版本／ABI，之后清理临时key并上传final角色；不执行APK，不据此证明历史正式证书身份。

versionName为源码版本，versionCode沿固定SDK原split-per-ABI规则：基础build number加arm=1000／arm64=2000／x86_64=4000。依据[Android完整版本语义](https://developer.android.com/reference/android/content/pm/PackageInfo#getLongVersionCode())，versionCodeMajor是高32位；本profile仅接受其缺省或显式整数0。I2在无secret的AXML解析中同时识别属性名／Android资源ID，拒绝非零、非整数、重复及不支持或身份不一致的编码，保持四行事实接口及原ABI偏移。实际aapt2／JAR签名覆盖缺省／0正例和异常AXML反例，并复用M独立major=1包作拒绝回归，不重打正常APK。

#### 产物身份来自生产job与GitHub，不来自候选声明

保留七个原平台／arch matrix slot，每slot固定唯一输出名。upload-artifact的`artifact-id`／digest由各slot映射到各自job output，Android、其它六slot、notes、sign各自有独立字段，不将矩阵最后一个通用ID当全部产物。其它matrix子项不写同一输出名，gate核七slot齐全及无重复ID；GitHub若无法提供确定的slot输出，则设计复审，不退回通配查询。role由workflow的固定producer→slot映射定义，签名final只从`needs.sign_android.outputs`取得；manifest的producer／SHA／run声明仅作待比对数据。

gate以`github.repository_id`、`github.run_id`、`github.run_attempt`、`github.sha`和`needs.*.result/outputs`建立期望，再用固定repo的artifact-by-ID API核ID、精确name、未过期、digest和`workflow_run.id/repository_id/head_repository_id/head_sha`。API的artifact元数据没有producer job／attempt授权字段，不能凭其或name自证；producer来自上述受信job outputs，并以本run本attempt jobs API核对应固定slot及上传step成功。artifact名含run_id／attempt／role／slot，使用v4不可变ID、关闭overwrite，不从任意URL或候选manifest选择下载对象。

首个secret service或写权限job启动前，其job-level if还须将所依赖gate输出的run_id／attempt／commit逐项与当前GitHub上下文核同；不能只信eligible=true，因为仅重跑下游可保留旧gate结果。Pages的部署角色同样要求当前Pages run／attempt／main SHA；缺输出或旧attempt在授予角色前拒绝。

同一次发布只接受同attempt生产链：重跑时旧attempt output／artifact不得混入；若只重跑下游导致前置产物来自旧attempt，清楚拒绝并要求rerun all jobs，不回退旧run。完整rerun继续支持，不要求新tag。所有gate及消费者均沿具体ID，不恢复`artifact-*`或merge-multiple通配采用。

下载先存runner自有临时目录的独立ZIP，核GitHub及producer给出的archive digest，再在解压前检查：仅允许`inventory.json`和`payload/`下预期basename的普通文件及必要目录；拒绝绝对／上跳／反斜杠路径、重复或大小写冲突、链接／特殊文件及超出预期大小，拒绝缺件／额外件。解压后重核实际类型、精确集合、大小及digest，最后复制到新建且只含该消费者允许文件的目录；payload不能覆盖checkout／helper／env或被执行。

预期集合由获审workflow slot、固定版本、setup的targets及原distributor命名规则产生，candidate inventory不能扩大它：Android为三ABI APK，Windows每arch为setup.exe及zip，Linux每arch为deb／AppImage／rpm，macOS每arch为dmg，notes只含release.md／telegram.md。所有包前缀为`FlClash-{version}-`，ABI／arch取固定slot，精确格式沿原命名消费者核实。GitHub stable发布只取最终三APK、六桌面slot及本job生成的SHA256SUMS；Telegram仅取原四项（Windows amd64 setup、Android arm64 final、两macOS dmg）及telegram.md；tap只生成两macOS摘要对应的cask，F-Droid只取Android arm64 final。SSH发布原cpina固定action仍在key消费者处构建alpine:latest及浮动apk工具；按M通过的窄增量，改`tool/ci_push.py`调用runner固定原生Git／SSH／必要LFS，空配置／受控唯一hook、GitHub官方host key、独占0700／0600材料及退出确认后清理；零信号退出探测的PermissionError或其它OS错误一律标为未知，保留目录，不以父进程已退推导组空。tap的原“/”映射clone根且保.git，F-Droid原“/tmp/”只映射clone/tmp；源／index精确集合、普通push及pre-push的实际old ref核对禁止越界、main缺失新建或覆盖并发更新。LFS按实际attributes／配置作为待核数据，默认端点绑定固定GitHub origin，禁未知filter／transfer／环境及错误收件方，必要正常对象传输不静默跳过；工具路径／版本／runner image仅观察，不冒独立认证。
各发布前重复核该目录／角色及gate绑定，失败不进入带secret的发送step；publisher只接受显式路径清单，不再枚举dist按substring选件。

辅助容器固定digest，Python publisher改用标准库streaming multipart，移除requests及浮动pip安装；容器精确对象须实施前只读接受，不执行浮动工具。CI事件和文件名按数据解析，不拼入shell；错误只给English原因，不回显token、密钥或任意响应正文。job权限／secret才是授权边界，候选manifest及hash不是独立生成证明，不引入并行resolver、版本DB或签名回执。

#### Pages 保留三种正常用途，单独决定受信checkout

Pages不套用release的仅tag规则。先由无pages／OIDC写权限的pages_gate判定，再由pages_build以contents:read构建并上传本站静态产物，pages_deploy_gate以contents:read／actions:read核该产物，最后独立pages_deploy仅取得pages:write／id-token:write；pages_gate的API核验仅另加actions:read。各job以gate成功及eligible条件拒绝缺失／失败依赖。

| 事件（均须canonical repo） | 接受／拒绝 | 构建脚本与checkout来源 |
| --- | --- | --- |
| main push（保留既有paths过滤） | 仅refs/heads/main；其它分支拒绝 | 固定该事件的main commit SHA |
| workflow_dispatch | 保留main上的手动发布；非main ref拒绝，防止任意分支脚本取得站点发布角色 | 固定该事件的main commit SHA |
| workflow_run completed | 只接受原build workflow的canonical repo push／success稳定release；pre、PR、fork、失败或同名其它workflow拒绝 | 当前Pages默认main上下文的固定SHA；不checkout source run的head SHA |

workflow_run的payload只作查询线索：pages_gate用固定repo API核source run的workflow ID／path为build.yaml、head repo、event、conclusion、head SHA及具体attempt；严格stable tag→peeled SHA必须对应head SHA。再核该attempt的release_gate及publish_github job实际成功，证明源workflow已通过原始`ref_type=tag`条件，不能仅凭名为vX.Y.Z的分支恰好有同SHA tag放行。当前Pages的`github.sha/ref`属于默认分支上下文，与source run身份分开保存和核验；默认分支不是main则拒绝并重新配置，不静默切换信任根。

pages_build只运行上述main快照的build_site脚本；CHANGELOG／公开release metadata按原用途作为数据读取，不执行source run artifact／脚本。自有_site核普通文件／目录、无链接／越界后，原固定upload-pages-artifact仍在内部使用浮动upload-artifact@v4；按M通过的窄增量，由项目helper沿相同未gzip的artifact.tar格式打包，直接调用已接受固定upload-artifact@ea165f8…，取得本Pages run／attempt唯一name、ID及digest。保留.git／.github排除及普通隐藏资源，tar成员拒绝链接／特殊／重复／越界并统一可读文件及可读／执行目录权限。只读部署gate在授予deploy角色前核本站producer及确切artifact身份；deploy-pages按唯一name选择，同run API须只有一个且ID等于受信output，不拿上游build artifact直接部署，不执行checkout或制品代码。保留原github-pages environment和并发顺序；不改远端environment设置，也不把配置静态检查当云端部署证明。

依据：[job条件／service env／matrix outputs](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)、[workflow_run默认分支与权限](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_run)、[artifact API](https://docs.github.com/en/rest/actions/artifacts)、[attempt jobs API](https://docs.github.com/en/rest/actions/workflow-jobs#list-jobs-for-a-workflow-run-attempt)、[artifact ID传递](https://github.com/actions/upload-artifact#using-outputs)、[Pages独立部署职责](https://github.com/actions/deploy-pages#usage)。静态／合成证据不等于真实远端运行，不声称OS网络隔离。

## 实施与验证

M通过设计后先建立文档baseline，再改实现：[android_build_sources.md](../android_build_sources.md)维护raw／派生物、命中／生产与发布权限契约；[android_build_guide.md](../../../development/android_build_guide.md)维护正常入口、失败／恢复及CI候选限制；[.agents/architecture.md](../../../../.agents/architecture.md)记录Cache／hook／controller所有权，必要时[.agents/commands.md](../../../../.agents/commands.md)补检查命令。上述新增能力先标为获审draft／未可用，验证后再回填。Tasks／阶段Plan／总入口只维护当前状态，延期备忘仅引用；本目录新增`l5_t04_result.md`，仅在实际验证后记录结果；不删除／迁移既有文档。

实现沿现有setup_hooks的cache／fingerprint／Go及Helper适配、CoreBuilder与两个项目hook、`tool/android_build_profile.py`／hook bridge及`setup.dart`；CI边界落`android/app/build.gradle.kts`、两个workflow及新增`tool/ci_release.py`统一资格／产物消费检查、`tool/ci_push.py`负责固定目的地的Git／SSH／LFS消费，`tool/ci_android_manifest.java`调用已接受SDK apksigner JAR中的原AXML parser及ApkVerifier API（不从版本化CLI文案解析证书）；临时签名由sign_android使用该已接受37.0.0 raw SDK的跨平台JAR，不执行其中macOS native工具，不另造签名协议；`release_telegram.py`改显式文件清单及其实际凭据／错误路径。Pages仍用`tool/build_site.sh`，只调整受信输入／产物边界所需部分。固定辅助工具的精确身份须在使用前绑定；不能接受时带具体对象及影响交M，不以未验清单关闭目标。

| 验收窗口（实际结果见[Result](l5_t04_result.md)） | 独立预期与边界 |
| --- | --- |
| cache真实入口 | 不变输入命中；源码／工具／配置／target变化失效或在不支持时先拒绝；同size／mtime坏输出、缺文件、错误清单／路径／symlink拒绝；普通hash记录不获source-generation资格。 |
| 提交与所有权 | 真实cache／Go安装夹具覆盖编译、第二文件替换、record／回滚失败；下述共享锁正反例核不同key、整组及迟到cleanup，退出不明保现场。 |
| Native／打包 | 通过原Native runner证明输出篡改和有效输入变化可到达project checker，稳定重复命中保留；最少一次正常受管ARM64 dev完整入口及有针对性的checkpoint／JNI检查。不要将全部真实消费者推给T05或为报告反复重打APK。 |
| CI候选／签名 | 合成意图及最小真实Gradle manifest消费证明正式identity与dev默认分开；临时合成key／APK证明重签、错误证书／角色／ABI／缺件拒绝，不读取真实keystore。未执行真实远端job。 |
| 上传／权限 | 合成GitHub／API事实、假token、localhost及真实CLI核上述job／产物／Pages矩阵正反例；静态检查service前gate、secret位置及slot独立ID。无真实云端或外部发布。 |

共享锁用固定等长A／B字节和barrier驱动真实cache／安装路径，同时覆盖同进程及两个自有Dart子进程：不同key、同输出时B不得在A的清理完成前进入命中／build；A成功后B发布，随后再请求A必须核实际字节而非误命中旧record。A安装失败时先恢复旧组再让B发布，故意触发A迟到cleanup后B及其record仍完整；回滚失败则本请求拒绝装包。另核同root非重叠输出的串行／互不损坏与正常重复命中、不同root独立，以及Helper／manifest失败能恢复同作用域Core／记录，不能只测单次run的锁。

CI合成拒绝覆盖错repo、ref_type、tag→SHA、旧run／attempt、伪producer／角色、缺／额外件及ZIP路径／链接；静态断言应从含secret service／step反向核其job gate依赖，不能只检查helper返回false。Pages分别核main push／main手动／稳定workflow_run正例，以及非main手动、PR／fork／失败／同名其它workflow和v分支反例；核checkout固定在相应main快照。正常合成发布只向localhost发送各目的地的精确清单，异常不泄密。

复用未变化的T02获取／Gradle红例和T03来源证据；具体失败与未覆盖项按对象记录。共享Dart缓存实现用现有setup_hooks测试验证跨平台公共语义，Android受管路径才作本项真实消费者结论，Windows／其它host运行不虚报。
不触用户全局cache、秘密、真实订阅、app／AVD／ADB／CU、宿主TUN／proxy／防火墙；自有进程按记录PID及退出处理。M完整实现审后D正常本地交付，M远端收尾后才接T05；整轮仍未完成。
