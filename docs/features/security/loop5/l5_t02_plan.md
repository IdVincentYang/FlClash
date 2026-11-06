# L5-T02 工具及发布工件获取校验 Plan

任务与归属见[Tasks](loop5_tasks.md)。本项在执行工具／解析依赖前核对接受的发布对象，覆盖首次获取及已有安装。M1已通过design_v2、R1 Native Assets局部修订及完整实现／I1复审；文档先行、实施与自验已完成，当前为D本地交付定稿，待M收尾。获审冻结及原始证据不回写。
父仓库`de0b86814b5021f2b4ea361aa37271abf25c53c7`，Core固定`6c6e3e472bb246cc55f2e8577d9eddccc2623afc`且clean；不重审未变T01或升级旧APK结论。

## 问题与目标

版本声明不能拒绝同版本异物。现有Wrapper JAR未跟踪且自报2.10，distribution9.8.0无期望SHA；SDK／工具目录及Maven缓存也不能凭stamp获信。
[Gradle官方说明](https://docs.gradle.org/current/userguide/gradle_wrapper.html)指出distribution下载校验不重核已有安装；[verification bootstrap](https://docs.gradle.org/current/userguide/dependency_verification.html)信任当时取件及自动发现的key，不能直接作为接受依据。

本次公开只读观察留`build/verification/l5-t02/investigation/`：Go1.26.4原归档与官方SHA-256核同，Flutter3.47.4公开tag对应现有framework commit；Rust固定日期manifest完整可解析，Temurin17.0.19+10有发行元数据。
distributor annotated tag剥离后对应现用`7fea25d4c531ce6e778db14e3c47f076027a1008`；14种action引用已查询，tag object与commit分开。
Flutter bundle／release manifest端点本次404，固定engine的Android及Dart组件HEAD为200；另有不完整文档、HTML伪装摘要及空正文，均不当接受根。HEAD不证明payload身份，404也不证明发布不存在。

## 接受依据与方案

采用现有版本配置加最少发布接受锚，拟增`tool/android_artifacts.toml`保存固定来源、角色／host、强摘要及接受依据；版本仍由原workflow／toolchain／Gradle配置维护，锚与消费者不符即失败，不建平行版本锁或审计数据库。受管入口只取当前受信仓库的锚，不允许候选或外部record替换接受根。
每个对象明确采用已接受key的签名，或固定官方HTTPS发布对象及另行取得的发布摘要／精确字节，经项目评审固定。当前缓存自算hash、候选自附摘要或任意有效签名不能授信；官方HTTPS／项目接受不冒称独立签名，也不保证发布者自身未被攻陷。
只有SHA-1的Google SDK元数据保留弱摘要事实，另固定新取官方payload的SHA-256；没有可核来源则不接受。SHA-256不能被描述成Google提供的签名或强摘要。

| 消费对象 | 拟处置与保留边界 |
| --- | --- |
| Flutter／Dart／engine | 保持3.47.4及原engine，按接受的bundle或固定官方源码／组件准备自有SDK；首次执行前还须完成下述pub及snapshot准备，不能把初次加载推给T04。完整生成因果归T03，后续派生缓存重用归T04 |
| Go／Rust／JDK | 核接受归档／组件与真实安装payload，使用绝对路径。Rust选1.98.1，不借PATH的Homebrew1.98.0；Temurin17与Studio JBR分别判断，显式选接受的JDK；重打包不能冒充原件 |
| SDK／NDK／CMake | 按实际package ID／revision／host核Platform35／36／37、Build Tools36／37、CMake3.22.1及两层NDK；保留JNI28.2与hooks29.0，不盲目统一或静默接受缺包 |
| Wrapper／distribution | 采用官方9.8.0 Wrapper JAR及启动脚本作为正式项目bootstrap，绑定官方JAR摘要及固定来源脚本；distribution仍9.8.0并加官方SHA。已有解压目录也与接受归档核同，不凭`.ok`复用；CI不再用SDK旧JAR覆盖 |
| Gradle／AGP／Kotlin／Maven／AAR | 原生`android/gradle/verification-metadata.xml` strict验证plugin classpath、POM／module及工件。先核官方依据再纳入摘要／限定key，不能整批授信bootstrap结果；该集合不是APK组件清单 |
| distributor／actions | distributor固定上述实际commit及其pub闭包，以已核Dart、显式package_config和原`bin/main.dart`调用，不走global activate／全局snapshot。必要action固定剥离后的完整commit；发布权限及完整CI约束归T04 |

本项首个受管profile只覆盖macOS ARM64宿主到Android ARM64 dev release，原setup的`--arch arm64 --env dev`及APK打包语义保留。Linux／Windows、其它ABI及整个CI尚未获同等验证；其缺失角色不能借本机材料满足，受管入口在任何目标工具启动前拒绝不支持的profile。固定action commit只证明引用固定。

## 核验和真实入口

拟增Python标准库`tool/verify_android_inputs.py`，默认只读。调用者显式选归档及安装根，锚内路径不扩权；先核角色／版本／来源，再流式核强摘要及安装payload，不执行被查文件、下载或自动接受新版本。缺任何必需角色／证据均不能成功，和T01允许partial inventory的退出0分开。受信项目源码、Python和OS是bootstrap前提，不自证解释器可信。
缓存中的程序／JAR／运行库及搜索目录额外执行内容也须核对；大SDK归档按获审大小和展开量设界，不沿用T01的256 MiB上限。合法archive link必须精确对应并始终在选定根内，不跟随任意本地link；不读取私有配置、凭据或无关用户目录。
需要写入的SDK bootstrap／packager cache使用项目自有忽略目录；既有全局工具／缓存只作显式只读材料，不覆盖或清理。缺少归档或不匹配时保留旧材料并失败，不能把unknown改为matched。

### 单次执行的唯一工具选择（R1）

Python入口先解析一个完整profile，固定目标及每个角色的真实路径；在本次消费前重新核验，不把环境标志、路径JSON或旧成功输出当许可。它只准备输入、配置和环境，构建／打包仍由原setup→distributor→Flutter→Gradle／hooks编排，不接受record指定任意命令。
实现首审I1证实含冒号的workspace会被拆成额外PATH成员并选中外部无害rustup。初始化须先解析完整父路径并核实际将创建的位置，
在创建workspace及启动目标工具前拒绝本host PATH分隔符、Gradle列表分隔符逗号、Java properties转义符反斜杠及不支持的控制／非ASCII字符。
首个profile支持可打印ASCII及空格；不能只验leaf或给PATH成员加shell引号。其它归档选择路径作为数据读取，不因此扩大限制到全部输入。
此为原路径与配置契约的窄修，不改工具接受锚、委托或绑定；第五次普通路径真实链可按代码影响复用，不把新路径输入套回旧APK。
入口从空字典构造子环境，PATH仅为已核工具目录及明确受信OS目录，不继承个人bin、选路变量、JVM／Dart参数注入或镜像配置；HOME、XDG_CONFIG_HOME、PUB_CACHE、GRADLE_USER_HOME、RUSTUP_HOME和CARGO_HOME均指向本次项目自有位置，首次启动前即禁用Dart／Flutter analytics及版本巡视。setup／packager／Flutter／Gradle沿这份选择执行；Native Assets runner过滤环境，两个项目hook须按下节显式恢复绑定。packager的variables／hooks与项目覆写配置不能再次改变工具根；未知选择即失败。

| 实际消费者 | 选择绑定及拒绝点 |
| --- | --- |
| setup／distributor／Flutter | setup由已核Dart VM及显式app package_config启动；其Android分支用`Platform.resolvedExecutable`和显式packager package_config／源码入口，替代裸`dart`及全局激活器。两者不经`dart run`隐式解析／预编译。`FLUTTER_ROOT`固定为已核自有SDK，packager据此调用同一`bin/flutter`；build加入`--no-pub`，不另解依赖 |
| Java／Gradle／SDK | 自有Flutter settings中的`jdk-dir`优先绑定已核Temurin17，`android-sdk`绑定选定SDK；自有local.properties同绑flutter.sdk／sdk.dir／cmake.dir。Gradle daemon Java home、工具链搜索及配置优先级也限定该JDK，用户Gradle home／init／daemon状态不进入本次执行；不能只检查JAVA_HOME或只看版本报告 |
| Native Assets／Go／CMake | JNI继续用原配置NDK28.2／CMake3.22.1；Flutter的NDK配置及环境明确选29.0。两处本地hook在启动Go／Rust前核实际cCompiler、archiver及libclang均对应其已核NDK角色；缺失或fallback到其它根拒绝。本地setup_hooks的PATH补齐在受管模式下不追加Homebrew／个人目录，Go使用已核绝对路径，且GOTOOLCHAIN=local、GOENV=off，不借用户go env改选 |
| Rust dispatch | rustup本身也属于须核的工具。自有RUSTUP_HOME只安装接受的1.98.1及目标组件，`RUSTUP_AUTO_INSTALL=0`；native_toolchain_rust原有`rustup run 1.98.1 cargo`因而只能分派此树。CARGO_HOME／rustc配置及linker选择受控，用户override／wrapper／其它channel不进入执行；不能把PATH中的rustc核同当作rustup分派已核 |

[Gradle daemon criteria](https://docs.gradle.org/current/userguide/gradle_daemon.html)优先于JAVA_HOME和org.gradle.java.home；不同或未接受的criteria拒绝。自有配置显式关闭Java installation auto-detect／auto-download，paths只列接受JDK，不让新daemon从其它安装或下载URL选取。

为避免读取或覆盖原私有配置及旧可执行缓存，按M反馈优先使用本次自有工作位置：从明确的当前源快照物化独立构建工作树，只加入本项源码WIP，Core仅物化同一固定tree，不改原Core／gitlink／carrier。原checkout的local.properties、.dart_tool及用户缓存不复制或交换；自有位置生成local.properties、plugin map、env.json及配置缓存，SDK／pub也在自有树准备。只给子进程配置自有home，不改当前shell或用户持久配置。
工作位置须独占；只有确认所有可能写该位置的自有子进程已退出或已放弃访问，才可收回自有对象／清理。取消、超时或父进程返回不等于后代已退出，不能用下一次启动猜测恢复；退出或归属不明就明确失败并保留工作位置和原对象，不关闭用户进程。若确需临时保存原对象，须不读内容地保留并在上述退出及归属核实后才恢复，不能仅靠finally中的路径字符串。这只是资源所有权，不新增运行状态机或宣称OS隔离。

#### Native Assets传递局部修订（设计已通过）

第四次`managed-normal-fourth`原入口退出0并产出APK，但固定Flutter的`native_assets.dart`使用标准
`UserDefines(workspacePubspec: ...)`，hooks_runner1.5.0随后以环境白名单和`includeParentEnvironment=false`启动hook。
实际Rust stdout缺FLCLASH／RUSTUP_HOME／CARGO_HOME，Cargo命令无`--locked`，因此程序的`profile_ready=true`是误判。
该次原输出及APK保留，不计为正常受管验收；直接给完整环境的旧hook窄例仅保留各自局部结论。
原始轨迹及独立审计见`build/verification/l5-t02/implementation/managed-normal-fourth/r1-environment-audit.json`。

选择标准user-defines传本次配置位置，并在同一已核Dart VM重入原hook。Rust builder的
`extraCargoEnvironmentVariables`只用于cargo build，覆盖不到此前无显式环境的`rustup show active-toolchain`，
仅给该参数补变量不足；不改SDK／runner／Rust依赖源，也不借白名单变量夹带额外选路数据。
两处本地hook共享`tool/android_hook_environment.dart`；它使用app已有的crypto依赖，不新增包或版本锁。
其伴随`tool/android_hook_binding.dart`在仓库默认保存空绑定，受管工作树中仅生成本次workspace绝对根和配置摘要两个常量。
编译进hook的绑定使“受管身份”不再取决于被过滤的环境：绑定非空时即使user-define完全漏传，也必须失败；
非受管源码的空绑定只保留原行为，不能凭外加环境／user-define自行变成已核受管构建。

1. **准备归属。** Python物化本项源码后，只在自有`source/pubspec.yaml`的setup／rust_api标准user-defines中加入
   `flclash_android_environment`，值固定为本次`workspace/hook-environment.json`。仅插入这两个配置项，
   原依赖声明、build_assets、锁文件及三套pub图不变；随后正常pub准备并核图。配置在最终package_config就绪后生成，
   不从候选pubspec取得接受根。
2. **绑定当前对象。** 配置只含固定schema／profile、workspace及source根、从空构造的完整运行环境、
   已审工具角色的原归档与本次安装根、原源码及本次生成的package_config／pubspec等必要文件摘要。
   工具接受依据仍是受信仓库`android_artifacts.toml`及原生锁；路径／摘要配置不能增补接受对象、命令或权限。
   Python将配置精确字节摘要写入伴随Dart文件，并把配置、两个标准user-defines及生成绑定纳入原有same-run generated重核。
   绑定文件本身不放入配置摘要表，避免自引用；Python在原入口前另核其实际生成字节。
3. **读取边界。** 两个hook都在build_assets判断、builder调用、Rust锁及任意Go／Rust消费前调用共享入口。
   根据编译绑定先核`input.packageRoot`确为同一source下的`plugins/setup`或`plugins/rust_api`，
   `Platform.resolvedExecutable`确为该workspace的已核Dart。user-define只能等于固定配置位置；先拒绝错根、
   链接或非正规文件，再按绑定摘要核精确字节，之后才解释配置。未知key、错schema／profile、
   跨workspace／过期选择、工具根或源码／package_config变化均拒绝，不扫描父目录或用户配置。
4. **同VM重入。** 外层只以固定`Platform.resolvedExecutable`、固定app package_config及原本地hook源码重入，
   不执行配置指定的entrypoint。保留runner的同一原生args；config和可选resources只能落在本次该hook的runner目录，
   不接受任意VM参数。子环境从空字典按严格schema重建，不合并父环境；唯一私有重入参数只控制一次重入。
   子入口再次核绑定、精确环境及源码，私有参数不授信：仍须通过下一步内容重核；错误环境立即失败而不递归重入。
   外层等待并转发子stdout／stderr后以同一退出码结束，退出发生在外层builder写output之前，避免双执行及覆盖子输出。
   macOS自动加入的`__CF_USER_TEXT_ENCODING`只作为OS附加项处理，不作为工具选择或转发来源。
5. **消费前重核。** 子hook使用配置绑定的既定Python解释器调用固定项目checker的只读hook-context检查模式。
   checker及其本地模块的精确字节在启动前核对；不接受配置提供命令。复用已有read_archive／compare_tree和Rust安装映射，
   以canonical接受锚重新核原材料及实际将用的Go、rustup／Rust组件、NDK工具树和代理／本次rustup设置，
   不依赖旧输出或候选自算hash。setup只核其实际角色，Rust核其实际角色；任何不符都在Go／Rust marker前退出。
   随后原hook检查实际cCompiler／archiver／linker及libclang路径，原builder消费恢复后的环境，Go保留readonly，
   Rust的show和cargo共同使用本次RUSTUP_HOME／CARGO_HOME并带`--locked`。
   Rust依赖现有API35 compiler别名仍属于已核NDK29；不由输入API24声称已完成API24运行兼容验证。
6. **输入与失效。** 只用本次新source／pub／runner目录，不带第四次hook kernel、输出或Gradle内部状态。
   user-defines是标准runner输入；配置及伴随绑定、相关本地checker源加入原生output.dependencies，
   同一已核package_config和transitive Dart source也由runner跟踪。配置更改必须重新生成当前绑定；
   不能假设被过滤的环境变化会使runner失效。跨次派生缓存仍归T04，不在此新增缓存接受机制。
7. **完成判定。** 两hook在内容重核和原builder成功后，将本次配置及已核native input精确摘要写入标准output metadata并声明配置依赖。
   Python在APK成功之外核真实runner input的两处user-defines、当前packageRoot、输出metadata和依赖均绑定本次对象，
   缺任一项即失败，不能再仅凭APK置ready。metadata是已核源码本次执行的对账信息，不能让调用者提供或授权其它材料，
   也不代替T03／T05的源码到APK因果及运行证明。

配置属于当前控制器刚生成的选择数据；编译绑定用于检测漏传和改变，不是新的发布信任根或可跨次使用的授权receipt。
当前受信源码／Python／OS这一bootstrap前提不变，不宣称防御能同时改写受信控制器与全部源码的同用户攻击者。
读取原始材料限于本次显式选择，工具树限于本次workspace；不探查原私有cache或全局安装。

局部实施前先更新来源基线中环境传递的覆盖说明、draft构建指南中的配置／失败观察及architecture的hook职责，
保留旧设计冻结；具体生产改动限于现有profile／checker、两个本地hook入口及上述共享helper／伴随绑定和邻近测试。
不改变Core／第三方SDK或依赖源／gitlink／carrier，也不提前开始T03。

先以同一已核官方Flutter／hooks_runner的真实user-defines读取、编译和过滤调用链串到两个项目hook，
设置父PATH及选路变量marker，核正常工具实际路径、Go readonly、rustup及cargo两阶段home、实际compiler／linker／libclang和`--locked`。
对照漏传整个key、配置缺失／同size及mtime改写、跨workspace旧配置、错工具／compiler及父环境注入；
前者在对应首个消费者marker前拒绝，父注入不被合并。伪造重入参数且环境错误或材料被替换也须在消费者前拒绝。
复用真实工具的既有小编译正例，但不以人工带完整环境直接调用hook替代过滤链。
这些出口通过后才再跑完整原入口，核两hook本次标准输出及APK；局部设计／实施／完整profile分别报告，不预写通过。

### 首次取得到首次加载的顺序（R2）

1. **先有接受输入。** Python／OS作为既定bootstrap根；先核framework源码、Dart VM及SDK内置pub／compiler、固定engine的全部本profile必要组件、工具及配置。组件集合按固定Flutter artifact声明和本目标确定，不能只填Dart与Android两个archive；缺host compiler／patched SDK等材料就不启动。engine.version／stamp／realm须与接受对象对应，禁止继承FLUTTER_STORAGE_BASE_URL、FLUTTER_PREBUILT_ENGINE_VERSION、FLUTTER_REALM等覆盖；HEAD及新取件自算hash不授信。
2. **pub只做数据取得。** 分别覆盖flutter_tools、app（含setup和本地hooks）及distributor三套实际pub图。app沿原pubspec.lock；其余没有上游受跟踪lock时，只新增各工具唯一的标准pub resolution lock：`tool/android_bootstrap/flutter_tools.pubspec.lock`和`distributor.pubspec.lock`，绑定原pubspec／固定Git源码，不复制app锁或在TOML再列包版本。现存SDK／global lock只能作候选，须逐项核pub.dev已接受版本的archive hash、固定Git tree及同树path包，不能直接授信或更新到latest。使用已核SDK内置pub在自有quarantine以`get --enforce-lockfile --no-precompile --no-example`取得数据，不global activate／upgrade或运行包；固定Dart3.13.3对应pub源码已确认此路径不预编译。新解出／缺依据的包保留在quarantine，失败不进入加载阶段。

   distributor用项目自有最小`tool/android_bootstrap/distributor.pubspec.yaml`消费固定Git包，复现原activation的runtime依赖图；这是标准pub输入，不改上游pubspec、不引入其开发依赖或复制app依赖表。其Git ref成为唯一消费声明，setup从已准备配置调用原源码，不再另列一份ref。
3. **核内容与解析产物。** 对所有将加载的hosted／Git／path／SDK包核实际文件树与接受归档／tree；不信可改的pub cache hash sidecar。标准pub生成的package_config必须逐名、唯一、完整对应锁及接受来源，rootUri／packageUri／SDK路径只能落到这些树；未知override、额外包或换根失败。再以同一已核Dart进行offline enforce get并复核配置，不手工改写第三方源码或伪造解析成功。app需要的标准Flutter pub准备仅在flutter_tools闭包已核后进行，其plugin map也须对应接受包根；setup的args／path／yaml在首次启动setup前已完成核验。
   固定Dart内置pub通过`bin/cache/flutter.version.json`识别Flutter SDK；首次数据解析可从已接受tag派生最小版本数据，不借旧SDK文件，不生成执行snapshot／stamp或据此授信。完整版本信息随后由已核Flutter工具按固定Git对象正常生成。
4. **首次snapshot也是首次执行。** 不复用全局或旧SDK的flutter_tools.snapshot、global activation snapshot及app旧.dart_tool。工具配置／上述pub闭包／全部组件就绪后，才用原shared.sh定义的Dart snapshot命令在自有SDK生成本次flutter_tools.snapshot；app-jit可能执行入口，同样不能提前。成功后才生成对应revision／空VM覆写参数stamp，lock须新于pubspec.yaml，engine／Dart版本戳须与接受对象一致；并核本次snapshot和package_config，满足原shared.sh的全部失效判断，之后原bin/flutter才不会先走pub upgrade／Dart下载分支。缺条件就失败；不通过修改SDK脚本或手工改源码适配。
5. **再走原构建链。** 以同一环境和显式配置调用原setup及packager源码，使用已准备app图及`--no-pub`；正常构建不把下载新组件当作接受步骤。构建前若必要artifact集合、lock、路径或配置变化，回到准备／核验，不能在未核代码已加载后补记hash；真实轨迹出现准备集合外的取件或选路就是profile未闭合、验收失败。首次自有pub／snapshot输出与不可变接受归档分开保留；T03继续追完整生成因果，T04才设计其跨次重用，不能追授本次首次执行资格。

原生Gradle strict verification及有限PGP key策略不变。该受管入口的普通顺序选路、pub及首次snapshot已纳入T02；直接旁路、其它host、跨次派生输出缓存、全CI及更广并发边界仍由T04接续，T05再绑定新APK。
原生消费者已暴露同长度／mtime的缓存替换可复用旧验证结果；实施须在JVM首启前重核选定原始Maven工件，仅将核同数据带入新建的自有Gradle内部状态，不复用旧验证／hash／transform缓存。这落实本项已有缓存重核，不将当前普通入口的缺口递延至T04；反例保留，保护未接入前不声明通过。
首跑还发现SDK准备集漏项：固定Flutter的`FlutterExtension.compileSdkVersion`及已选插件要求Platform36，
AGP随之需要Build Tools36.0.0。两者按已有官方固定对象方法接受，不升级插件或改其源码；原35／37准备集不足以构建。
必需角色缺失或材料被替换须在SDK消费者前拒绝，不能依靠AGP现场安装发现缺项。原首跑失败现场保留。
补齐后，原生SDK reader仍不能仅从API37.0 ZIP识别目标；需要官方SDK Manager同类的标准安装元数据。
新增`tool/android_bootstrap/android_platform37.package.xml`，只从固定官方repository2-4 descriptor投影对应localPackage及license声明，
不改SDK源码／payload或接受license记录，先以实际SDK reader核缺元数据与正规元数据对照。
保留失败现场所需空间由只读工具树重核后复制解决：复制仅含接受归档成员，OS支持时用独立inode的copy-on-write；
不复用旧snapshot或Gradle内部状态，不把缓存目录或旧成功输出当许可。

## 文档先行与验证

M通过方案后先完成以下文档基线，再编写代码／配置及测试；未可用入口标draft，不在设计交评时修改生产消费者。

| 文档路径 | 具体增量和职责 |
| --- | --- |
| `docs/features/security/android_build_sources.md` | 接受依据、角色、实际覆盖与未证明部分，不复制机械摘要 |
| `docs/development/android_build_guide.md` | 首次准备、缓存再核、受管构建命令、失败观察及基线更新，替换未经来源核验的直接构建示例 |
| `.agents/architecture.md` Build System | 核验、原setup编排与后继缓存／CI责任及入口链接 |
| `android/gradle/wrapper/README.md`／`LICENSE` | 正式bootstrap资产的官方来源、许可、接受锚入口及更新方法 |
| Loop5 Plan／Tasks／安全总索引 | 有效授权、单层任务状态及依赖 |
| 实施后新增`loop5/l5_t02_result.md` | 实际对象、正反例、限制和新旧产物绑定，不预写通过 |

实现范围含锚、checker及邻近测试、标准tooling pub locks、Wrapper／verification配置、setup及本地hooks必要的选路绑定、必要workflow引用；不改第三方SDK／pub包源码。正式小型Wrapper JAR是必要bootstrap工具资产，附官方来源、许可、摘要及更新方法；其它工具包、日志、APK不入库。

验收走真实消费者，不只断言helper返回值：

- 首次准备和正确缓存可用；同版本替换、错版本／角色／来源／摘要、解压后同size／mtime替换及额外执行内容，均在目标工具执行前拒绝，旧材料保留。
- 损坏／重复metadata、HTML／空正文、越界及未选择目录拒绝，外部inode不被读取；正常官方archive link可用。获取流程拒绝降级／未接受接收方，离线checker不自行联网。
- 原生Gradle用最小本地repository验证正常解析、错工件、缺记录和旧缓存再用；同一有效签名先以限定key作正对照，移除接受key后失败，不能只测伪造key字段。
- R1从真实委托链核已执行路径：将伪dart／flutter_distributor／flutter／go／rustup／java放入父PATH及其它选择位置并带marker，正常受管执行只能到已核树；再使packager variables、Flutter settings、local.properties或hook cCompiler指向未核树，须在对应首个消费者前拒绝。不能仅比较入口返回的路径字符串。
- R2分别在首次与已有材料放入改动pub包、换根package_config、未接受新依赖及可执行旧snapshot／activation marker；不得加载，旧原始对象不读内容且原样恢复。首次正规pub解析→核内容／配置→本次snapshot→setup／packager有正对照；缺组件／stamp不符不能触发未核下载或pub upgrade。合法archive symlink／hardlink按原结构物化并核最终loader目标，不把它们改成手工修补源码。
- 复用T01未变证据；按修改跑Python／Dart setup窄测、pub get、analyze及文档检查。必要工具依据成立后最多一次相称ARM64 dev正常装配，核受管入口可持续；新包另绑定，不复跑设备／业务矩阵。

发布接受方式及Flutter同版本源码／组件bootstrap取舍已获M设计通过，不从404推导升级。首次数据取得同样限定接受的HTTPS URL／host／固定对象；下载、解压或lock候选都不等于加载许可。必要工件仍不可取得或来源无法成立时，只暂停受影响对象交M，不用unknown清单关闭T02或整个Loop5。Core／依赖源码／gitlink／carrier不改，T03不提前实施。
