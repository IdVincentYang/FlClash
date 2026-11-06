# Android 构建与装包来源

本文说明Android ARM64 dev release的实际内容、构建输入及来源证据边界，供Loop4代码审查和Loop7制品对账使用。
只读工具及其结果含义见下文；任务交付状态见[Loop5 Tasks](loop5/loop5_tasks.md)，操作命令见[构建指南](../../development/android_build_guide.md#构建来源只读对账)。

## 对象与证据分层

来源调查对象为父仓库`c45563eb36ebd9a6b7cff9d1802715e7ebb053f1`的ARM64 dev release，APK为55,180,515 bytes、SHA-256 `0550bfd0c8ff710fd409579635592657303611b63844529879a64f97fce2d425`。
本包有401项、10份native及1份DEX；它与旧T04已安装包不同，无本包设备安装结论。
Core仍为`6c6e3e472bb246cc55f2e8577d9eddccc2623afc`，不改Core、第三方依赖源码、gitlink或carrier。
对本对象的观察记录覆盖401个条目hash，33条材料关系及1680个所选输入身份核同；只有15个包内条目有已核材料关系，其余386个仍未绑定材料。
这份参考记录来自显式选定的获审对象，不是发布认证数据库；完整条目参考覆盖不等于完整来源／生成覆盖。

证据只支持对应层的结论：

- APK条目与选择的记录／本地文件hash一致，证明这些字节对应，不证明发布者可信。
- metadata、Go build info和SDK stamp记录声明的版本／配置，不是独立发布签名或完整构建证明。
- 原库、merge、strip、AOT、DEX/R8及APK是不同对象；转换前后hash不同可能正常，不能省略中间关系，也不能只因两端分别存在而证明构建因果。
- 已有源码归档与锁定摘要相符，证明归档身份；不能直接证明本次用了该源码、未修改缓存，或生成了某份预编译件。
- R8内联／合并会隐藏原名；零计数不证明组件未进入产物。WASM也可能嵌在ELF中，ZIP无独立wasm条目不证明未装入。
- runtime加载、协议启用、联网行为和漏洞可达需要相应验证，本来源基线不代替这些结论。

当前1680个输入身份包含源码候选、hooks声明的依赖、配置和工具／工件metadata。源码候选也可能含测试或其它平台代码，不因被记录就成为本APK实际编译／运行文件。
额外源码身份是在当前工作区观察的，不是旧构建时间点的完整证明。旧hooks列出的4个Git元数据引用未读取，避免把可能含认证信息的配置纳入证据；这类缺口明确保留。

## 实际来源关系

版本权威仍为[pubspec.lock](../../../pubspec.lock)、[Go模块](../../../core/go.mod)、[Cargo.lock](../../../plugins/rust_api/rust/Cargo.lock)、[Gradle版本配置](../../../android/gradle/libs.versions.toml)及实际工具选择。
以下表格是已完成只读调查的关系摘要，机械条目／hash和unknown保留在显式对象的本地证据，不能从依赖树或缓存存在推导装包。

| 对象 | 发布／获取与生成关系 | 实际提供／消费位置与限制 |
| --- | --- | --- |
| libapp.so | Flutter/Dart AOT，输入包含项目Dart、锁定pub依赖、本地插件及已提交生成代码 | Flutter engine加载；只有本地输出字节绑定，完整Dart输入闭包及生成来源仍需核对 |
| classes.dex | 项目Android代码、Flutter embedding及release依赖经过Gradle/R8 | 实际2509 class definitions；原名映射可辅助归因，不能只凭包名认定依赖或运行可达 |
| libclash.so | 项目Go入口及固定Core、锁定Go依赖，Native Assets构建c-shared库 | JNI调用；binary build info有android/arm64、with_gvisor,no_zerotier与父仓库revision；不代表所有输入已认证 |
| EasyTier WASM | 锁定easytier-go模块嵌入6,850,909-byte二进制；与APK内libclash字节相同 | Wazero运行材料；编入不代表启用。声明源码commit及生成关系仍未证明 |
| libcore.so | 项目android/core的C++经NDK/CMake编译，链接libclash | JNI胶水；本地输出与包对应，工具来源及完整构建证据另核 |
| libdartjni.so | pub jni包的C源码、SDK头与Android NDK/CMake | Dart／Java桥；现存输出与包对应，包归档及生成关系不因相同库名自动成立 |
| librust_api.so | 本地Rust crate与Cargo锁定依赖，经FRB Native Assets；Android rquickjs用bindgen／libclang | FFI编辑器／脚本能力；桌面IPC/helper依赖按target裁剪，不由Cargo.lock出现推导装包 |
| libflutter.so | SDK的Android release flutter.jar中预编译engine，与merge／strip／包对应 | 实际SDK元数据声明Flutter3.47.4／Dart3.13.3及固定engine；本地声明不是发布身份认证 |
| libsqlite3.so | sqlite3 Dart包3.5.1的hook从GitHub release选择预编译件，包内hash表与本地文件相符 | SQLite FFI；3.5.1是Dart包版本，不是已证实的SQLite引擎版本，也不是本次从C源码编译 |
| Camera的两份JNI | Maven camera-core1.6.1的libimage_processing_util_jni／libsurface_util_jni | AAR member→merge→strip→包对应；发布认证及JNI源码／生成来源另核 |
| DataStore JNI | Maven datastore-core-android1.1.7的libdatastore_shared_counter | AAR member→merge→strip→包对应；同名库或缓存存在不代替该关系 |
| Geo及其它资产 | Geo沿用[已接受基线](geo_data_design.md)；字体、图标、许可、Flutter资源分别分类 | 资源打包／首次缺失seed与运行加载分开；不恢复Loop6延期更新能力 |

## 构建时执行、下载与运行时输入

`setup.dart`编排环境及distributor；Flutter运行Go／Rust／SQLite等hooks，Gradle/AGP/Kotlin、NDK/CMake、JDK和依赖build scripts在构建机执行。
Pub、Go、Cargo、Maven/Flutter仓库与SDK工具下载属于构建输入获取；SQLite预编译下载也是构建期行为，不应标作本地SQLite源码编译。
Freezed／Riverpod／Drift／本地化等生成文件通常已提交后参与编译，普通装配不等于重新生成；FRB及rquickjs/bindgen等生成关系按实际输入记录。

APK中观察到ELF、DEX、WASM或脚本能力，只证明材料进入包。Core协议、Java/Dart入口及FFI的运行使用仍受配置与生命周期约束。
配置／订阅脚本、Geo等运行时获取材料沿既有来源接受及延期边界处理，不把T01当作新的动态下载许可或信任根。
Android的no_zerotier标签及实际Go模块信息排除本次ZeroTier实现；不能沿旧A-14或缓存中的zerotier-go／planet数据声称已装入。测试依赖、其它ABI、桌面Helper同样须有实际装包证据才列作本APK内容。
ELF的DT_NEEDED还声明libc、libdl、libm、liblog、libandroid、libEGL、libGLESv2、libjnigraphics等未列在APK的库；这里只记录导入名，尚未解析到设备系统，也不以未装包推定漏库或实际加载。

## 只读对账契约

[inspect_android_build_sources.py](../../../tool/inspect_android_build_sources.py)使用Python3.11+标准库，读取命令行显式选择的APK、记录及输入文件／目录。
安全读取依赖POSIX的descriptor-relative open与O_NOFOLLOW；当前在macOS验证，缺少这些能力的平台明确拒绝，不降级为跟随路径读取。
`--input 名称=路径`把名称绑定到一个文件或目录；记录通过该名称及目录内的相对路径引用文件，可指定archive member。不扫描未选择的SDK、缓存或用户目录。
记录内路径不是授权。绝对路径、上级跳转、目录内符号链接、archive越界／重复条目均不能扩大读取范围；源输入不在选择范围内则不读取，不执行被查对象。
输出只到stdout，不修改输入，不执行Gradle／hooks／生成器／下载，也不从APK里的manifest建立接受根。

报告从实际APK枚举出发，分别显示实际条目、参考记录覆盖、已核字节关系、未覆盖／不可读取／unknown及矛盾；额外、删除、空记录都不能掩盖未对账对象。
ELF ABI、DEX定义、Go元信息及WASM magic候选用于描述对象；magic候选不是完整嵌入代码识别，source hash和R8映射也不自动证明生成因果。
每个条目分列reference_status、material_status和unknowns；无记录仍保留实际条目／hash，无法解码的metadata单列，不假装观察到了错误版本。
退出0表示输入结构与已检查声明一致，可以仍是partial_inventory；退出1表示实际hash／ABI／已解码metadata矛盾或期望条目缺失，退出2表示输入结构／读取范围被拒。两类coverage与矛盾分别统计，不能把退出0读成全来源可信。
公开发布身份、完整源码生成及runtime loaded保持独立的未验证状态，不能由工具计算出的hash升级。

所选记录是工具的私有观察格式，不替代版本锁或授权。最小记录包含apk_sha256和objects，每个对象有entry及sha256，可加声明origin、expect及links；不接受未知字段或重复对象／JSON字段。
links及source_inputs通过input名称引用调用者的选择，目录另给path，archive另给member，sha256表示该文件或member的期望hash。具体选择方法和最小示例见构建指南，不从记录中的绝对路径补权限。

| 关系 | 工具实际核对的内容 | 尚不能证明什么 |
| --- | --- | --- |
| same_bytes | 所选材料与期望hash、APK条目字节均一致 | 发布者或生成过程 |
| transform_input | 所选转换前材料的hash一致 | 它确实生成转换后条目、strip／编译过程完整 |
| source_file | 所选源码／输入的hash一致 | 本次被编译、进入包或被运行 |
| embedded_bytes | 所选非空payload完整字节在父条目中命中 | 该payload被执行或扫描穷尽全部嵌入代码 |

`source_inputs`仅断言输入身份，可选r8记录只输出原名与实际class definitions的交集；元信息和这些关系均不能自证构建因果。
重复／越界／symlink archive条目拒绝；ZIP只读取不解包，有大小及条目数量界限。工具不是Android安装有效性、通用反恶意代码或签名认证工具。

## 工具、缓存、CI及未决项

### 工具接受与受管构建

此入口只覆盖macOS ARM64宿主到Android ARM64 dev release，其它host／ABI先拒绝；不能据此升级旧APK结论，action固定不代表CI工具已核。
源码从受信仓库当前HEAD及入口明确允许的任务WIP物化；其它未提交改动拒绝，不把任意工作目录或旧受管source当作已接受输入。
本profile的规范化工作位置（含父路径）须为可打印ASCII，允许空格，但拒绝`:`、`,`及反斜杠。
这是PATH、Gradle路径列表及Java properties的共同序列化前提；不通过引号、改宿主路径或全局工具绕过。

接受锚维护角色、host、固定官方对象及接受依据，版本仍由原配置维护。签名必须绑定接受的完整fingerprint和对象作用域；采用官方HTTPS及固定摘要／精确对象时如实说明依据，不冒称独立签名。候选自带hash、缓存sidecar、HTTP成功或HEAD结果不能自行授信。首次取件也须遵守接受的URL／host／HTTPS及固定对象；缺元信息则保留候选并失败。
Maven配置逐工件保留独立接受的SHA-256；有可核签名时再限定完整signing fingerprint，两项同时约束该工件。
公钥候选可从公开keyserver取得，但必须对已按官方参考接受的精确字节验证；公钥可取得或签名有效本身不建立发布者身份，
不扩大为其它版本／工件的接受。原生解析关闭keyserver发现，公钥材料保存在项目verification keyring；该接受集合不是APK组件清单。

受管入口先核工具与安装payload，再用已核SDK内置pub只取得数据；app沿原锁，flutter_tools／distributor各有唯一标准工具resolution，不另造包管理器或复制app锁。distributor最小consumer pubspec固定原Git对象，复现旧activation的runtime图，不改上游源码或引入其dev依赖。三套将加载的pub文件树、package_config及plugin map对应接受归档／tree，完成前不加载源码或snapshot。其后才在自有SDK生成本次Flutter tool snapshot；生成本身也是首次执行，不借旧SDK／global activation snapshot，不通过事后hash追授许可。
内置pub所需的Flutter版本数据从接受的固定tag派生，完整版本文件再由已核工具正常生成；版本文件只描述已接受对象，不承担执行许可。

同一次profile固定实际Dart、packager、Flutter、Java、SDK、两层NDK、CMake、Go及rustup分派。子环境从空集合构造，工具路径和项目配置优先级必须一致；未知选路／缺必需角色失败。setup继续编排原打包流程，packager改用已核Dart／显式配置及原源码入口，Flutter build使用已准备依赖图；Gradle继续用原生strict验证，不靠PATH继承或再次激活决定版本。
JVM的`user.home`与`ANDROID_USER_HOME`也绑定自有home；只改HOME环境变量不能保证Java采用该目录。
受管入口创建限定的JVM参数，不继承父进程注入；Gradle daemon沿同一选择启动，原用户Android配置和debug keystore不作为输入。
Rust准备还须在自有CARGO_HOME提供指向已核rustup的标准cargo／rustc／rustdoc代理；只验证`cargo --version`不能证明cargo能启动rustc。
代理仍经自有RUSTUP_HOME及固定toolchain分派，不用Homebrew或自动安装补齐。
Native Assets runner过滤环境，两个项目hook不能靠FLCLASH环境变量判断受管身份。
受管workspace通过标准user-defines传固定配置位置，并将本次workspace／配置摘要编译进本地hook；漏传、错根或配置变动失败。
共享入口以同一已核Dart、app package_config和原hook源码重入，从空环境恢复已审选择；子hook在Go／Rust消费前再核实际角色材料。
重入参数和配置只绑定当前选择，不能授信新材料；Rustup查询与Cargo构建都须使用本次home。
原builder成功后输出本次配置的标准metadata及依赖，控制器核两hook真实input／output后才可判profile完成，APK存在本身不足。
受管Cargo构建使用`--locked`，Go使用`-mod=readonly`；取得依赖不能隐式改写当前源码中的接受锁／sum后再执行新代码。
SDK准备同时覆盖主应用Platform37、固定Flutter及已选插件要求的35／36，以及Build Tools36／37。
缺失或替换必需材料在相应SDK消费者前失败，不把AGP安装支路作为补充接受机制；自有Gradle配置关闭SDK自动下载。
Gradle内部验证／hash缓存不能代替字节重核。JVM启动前按接受参考核选定的原始Maven工件；只复用核同的数据，每次使用新建的自有Gradle内部状态，不复制旧验证、hash或transform缓存。原生strict和有限key验证继续约束本次解析；尚未验证的首次取件留在隔离位置。
未复用原始Maven数据时可明确选择空集合，由新Gradle状态按原生strict配置首次取得；不得因此关闭验证或导入旧内部缓存。
实际Gradle工作树的verification metadata及keyring须与受信仓库的对应文件核同，候选工作树不能提供另一套接受根。
受管命令的选择JSON只列本地材料路径，不提供接受摘要、命令或成功receipt。工具锚、三套native锁和Gradle验证配置仍从当前受信仓库读取；
正式launcher在新的独占位置准备SDK、配置和缓存，成功准备与成功APK构建分别报告，不把局部准备状态称作交付完成。

构建工作位置只物化明确源快照及本项WIP，Core保持同一固定tree；不复制用户私有配置、全局pub缓存或旧可执行状态。所有可写bootstrap、HOME及缓存均为子进程自有位置；接受归档和新生输出分开，合法archive link按原结构核实际loader终点，不手改第三方内容适配。
Flutter源码通过原生Git archive物化，在自有导出仓库的Git元数据中关闭属性转换，并全量核对固定commit的原始blob；避免将checkout或默认archive的行尾转换误认成原始字节。缓存只提供显式选定的Git对象，不导入原SDK配置、其它refs或可执行缓存；新SDK的Git元数据由自有固定对象生成，不修改第三方源码或其属性文件。
共享SDK目录按固定Flutter源码的组件顺序合并；同名元数据仅在旧、新内容均对应接受归档时按明确映射替换，不能以解压覆盖接受未知内容。原归档与各组件物化树保留；合并后仍核整个目标payload集合。
互不重叠的Android子树及Dart SDK直接物化到最终位置；已核Gradle树在首次JVM前移动到自有Wrapper目录并再核，
保持原归档和精确payload，同时避免保留两份相同安装。共享目录的组件仍分别物化后合并；不回收有活跃或归属不明写入者的位置。
API37.0还需要标准`package.xml`才能被原生SDK reader识别；该安装元数据由固定官方repository descriptor转换，
随项目bootstrap保存，不改归档payload或SDK源码，不写license接受记录。受管准备复制获审模板后再让SDK消费者读取。
已缓存工具树仅作只读数据：按接受归档逐成员核同，只复制这些成员到新的自有位置，再完整核输出，不携入额外文件或旧可执行状态。
支持时使用独立inode的OS copy-on-write复制，原对象不受后续写入影响；否则复制字节。pub／Flutter snapshot等派生缓存不因此获得跨次复用许可。

只有确认相关自有子进程已退出或放弃访问，并核对象归属，才可清理／恢复。取消、超时、父进程返回或下一次启动都不是退出证明；退出／归属不明就保留原始对象及自有位置、明确失败，不关闭用户进程。不新增权限receipt、平行运行状态机或审计DB。

T02验证首次获取／加载及此受管入口；T03追完整生成因果，T04补跨次派生缓存、直接旁路、其它host及完整CI边界，T05才对实际新APK绑定。当前T01只读工具及其partial_inventory语义保持独立。

### 现有实现及未决项

实际JNI的CMake记录选择NDK28.2，Native Assets hooks选择29.0；JDK启动器／daemon、SDK/NDK/CMake及不同ABI须分别绑定，不为统一版本盲目升级。
T01基线中的Wrapper JAR是忽略的本地输入，自报2.10，distribution指向9.8.0且没有期望SHA。
受管入口使用正式官方9.8.0 Wrapper、distribution摘要及原生verification配置，并在本次完整委托链核工具／pub／hook选择。
setup cache核源码内容／target／tag／工具版本等输入，但输出命中以size／mtime为依据，不能当内容身份验证；外层hooks与各第三方缓存也需按实际消费者审查。
本地禁upload／publish前缀任务只覆盖匹配名称，不是完整网络隔离。CI actions／distributor已固定commit，job权限、发布gate和签名材料作用域仍需按T04核实，不能执行发布来“验证来源”。

后续落点由[Loop5 Tasks](loop5/loop5_tasks.md)维护：工具与工件认证归T02，源码／生成缺口归T03，执行／缓存／CI约束归T04，最终制品验证归T05。
EasyTier固定公开repo的声明commit查询返回422，只说明该repo未解析，不证明其它fork不存在或篡改；此生成缺口不能只靠重写hash关闭。
本项保留关键unknown，不把来源清单完成扩大为整个Loop5、发布身份或运行安全通过。若处置触及no-Core边界，需另交M决定，不在这里降验收或修改依赖源。
