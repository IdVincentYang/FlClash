# Android 构建与装包来源

本文说明Android ARM64 dev release的实际内容、构建输入及来源证据边界，供Loop4代码审查和Loop7制品对账使用。
只读工具及其结果含义见下文；任务交付状态见[Loop5 Tasks](loop5/loop5_tasks.md)，操作命令见[构建指南](../../development/android_build_guide.md#构建来源只读对账)。

## 对象与证据分层

T01来源基线对象为父仓库`c45563eb36ebd9a6b7cff9d1802715e7ebb053f1`的ARM64 dev release，APK为55,180,515 bytes、SHA-256 `0550bfd0c8ff710fd409579635592657303611b63844529879a64f97fce2d425`。
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

## 受管原包的源码对应

另一个明确对象是T02第五次受管ARM64 dev release：55,189,483 bytes，SHA-256 `845a3804de290e148ec52c6472ed65ea3b3b81b3389a628ac37c4ccb931c68ff`。
它保留原`de0b868`加同次source_wip的输入身份；后续I1／Python常量整理、文档或新诊断不使其成为新HEAD生成的APK。
下表补充此对象的源码及保留理由，发布接受复用下文工具契约，生成与运行证据仍分层；T03按用户2026-11-07调整范围实现评审通过；只有原EasyTier WASM源码／生成缺口明确延期，其余组件不沿用该例外。

| 组件 | 源码／生成输入与保留依据 | 结论边界 |
| --- | --- | --- |
| engine／Dart | 固定engine `06a2e2a110089dff50fe635cffd2a61e1b24fbcd`根树及DEPS、Dart `1d1a730ef918d602aedafc939a4cf5940e7589ab`原源均可审。另按固定Android GN补Skia、ICU、HarfBuzz、BoringSSL、字体／图像／JSON／Abseil／FlatBuffers及Vulkan相关固定源；ICU数据与原engine内嵌字节对应。保留已接受官方engine及SDK。 | 源码对象和配方支持保留，不称独立重建engine、取得原完整逐文件编译轨迹或实际设备加载。条件及host／test分支单列，不把全部DEPS当运行清单。 |
| JVM／DEX | 新的自有Gradle配置解析取得ARM64 release的实际外部工件；全部108份去重归档均与原第五次缓存字节对应。同坐标sources JAR、ConstraintLayout2.0.1固定源码及DataStore重打包protobuf4.28.2的原源／relocation配方可审。原R8映射另对包内DEX定义及提供方核对。 | 保留已接受官方工件。新配置图不是原R8执行轨迹，source JAR可能为空，类名对应不证明完整生成或运行可达；JNI另按下列关系判断。 |
| SQLite | 默认hook从sqlite3-3.5.1不可变release取ARM64资产；固定源码配方commit `ac40b296e7069c4e83503bcbe4a3b22dfe5431a7`指SQLite3.53.4。官方amalgamation的source ID与原ELF声明对应，pub接受的raw hash与release asset digest一致；已核NDK strip副本与包内库逐字同。 | 保留官方预编译。strip对应已独立核，不称本机编译了SQLite C源码；其它cipher／system／自定义hook分支不由此获准。 |
| Camera JNI／libyuv | 同版本AAR两成员到包的字节链已核；Camera1.6.1的support `987b9ac8585b31424a397206c492196dd163997b`及C++／CMake可审。匹配该support的固定manifest `b12ce2adc0a0bc4501e07067287fafcba8b73e3a`将libyuv固定为`afae031e789e344bfc34c9e763c83f861a1ff3f1`，该完整源对象已核。 | 保留已接受官方AAR JNI，不把Java source JAR当完整JNI源，也不称已独立重建AndroidX。 |
| DataStore JNI | 同版本1.1.7 AAR的shared counter成员到包已核；support `420da5f291449f11801e378c6789a328a06ec6cb`的shared_counter.cc／头及CMake、JNI声明已取得并核Git blob。 | 保留已接受官方AAR JNI；源码／配方及发布对应独立于运行加载。 |
| Go／Core | 包内Go build info的120个版本化依赖与原go.sum、原始module ZIP h1及当前解出树逐文件／成员核同；项目和本地Core另按固定源码／carrier维护。Go SDK含对应标准库源码。 | module归档可能含未编译平台和测试文件，不能把整包都称作运行代码；嵌入WASM须单独判断。 |
| Rust／QuickJS／标准库 | 原Cargo.lock对应119份现存registry源码归档及物化树核同，target dep-info涉及50个包候选。rquickjs-sys0.12.2携带可审QuickJS C／头和build.rs；原target dep-info列出该run目录的bindgen输出，其当前文件身份已记录。官方Rust1.98.1 library source另按发布checksum取得。 | 依赖锁、目标输入和生成配置可审；不把host proc-macro／桌面依赖自动列为Android运行库，不称全部crate源码最终存活。API35别名不证明API24运行兼容。 |
| 项目C++／Dart／提交生成代码 | 原CMake指向项目core及jni包的C源码／SDK头；编译命令、当前输入和生成配置可审。AOT、Freezed／Riverpod／Drift／本地化／FRB按原输入及配置可审，两个Git fork与原发布源的修改另有比对，本地code_forge按项目维护的裁剪源接收。 | 已提交文件作为可审项目源码保留；其生成头和当前generator锁不证明本次重新生成。depfile、R8对应及新配置图各自只支持其记录范围。 |

EasyTier原6,850,909-byte WASM及Go binding均声明`63519db2b5f2a6a1b9b7f20905f036dab54eb829`，已查官方repo、PR已标识fork及固定Git对象仍未恢复该树。
Go host导入前的已知父树和当前公开候选均不是原声明源的替代。一次固定未改候选／原配方局部构建产生不同完整字节；原Go binding的schema声明也与所核父树／候选不一致，不能因此推导恶意或已证运行错误。
正常TCP、UDP或对应DNS请求可沿Core的ensureStarted进入wazero消费者；未触发不等于没有编入。本项不替换payload、不改Core／依赖／gitlink／carrier、不禁正常功能或默认DIRECT。
原来源生成资格未通过；用户仅明确延期这一缺口并继续，范围、风险及恢复条件见[备忘](deferred_security_items.md#loop5-t03-easytier-wasm-源码与生成对应)。没有第二次构建或无限检索许可，不将范围批准当来源信任、风险接受或Loop5完成。

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

### 构建记录与组件来源

只读增量已实现并通过相称正反例；T03按用户明确调整范围实现评审通过。实际APK、编译器记录的输入、源码身份、发布配方、独立再生成与运行加载分别判断；新观察不改写旧APK身份。
通过只读入口的`--build-evidence <input-name>`读取调用者已选择的构建根内已知Flutter depfile、ARM64 CMake记录及Rust target dep-info，复用R8对应；解析器只处理字节，CLI持有唯一读取权限。
声明路径只能映射到显式`--input`根后安全读取，未选择、缺失、不支持格式及矛盾分别显示；不跟随symlink、不读取原绝对路径、不执行记录内命令，不以全部pub／Maven／Cargo缓存替代实际输入。
可选record.build_evidence须包含input、context和source_commit：input为所选目录别名，context沿普通input／sha256引用且仅可省略relation或用source_file，source_commit为40位小写Git ID。原context须含绝对workspace、source_commit和apks摘要列表，用于核APK／workspace／source声明；匹配仅标matched_declarations，不是独立attestation。
depfile不携带cwd；相对路径只有在可选working_directories按flutter_depfile／rust_dep_info分别声明规范绝对路径后才映射读取，否则保留unresolved_relative_path。CMake使用自己的directory，不接受外部覆盖。工作目录仍是外部声明，不是已观察执行；缺同次绑定保持unknown，矛盾失败。使用此record对象须同时传--build-evidence，避免声明被静默忽略。当前材料hash与历史路径相同只说明当前身份；原partial_inventory及source_generation=not_proven边界不变。

发现范围限Flutter build目录的depfile、项目／插件ARM64 CMake compile_commands和rust_api的Android release target dep-info；不是任意build系统的完整闭包。空Flutter依赖规则、目录依赖、未选择引用和缺失watch marker不会产生源码内容身份或生成成功。
depfile按Make默认续行语义折叠LF／CRLF及相邻空白，保留token／转义边界；多反斜杠紧邻换行、bare CR或.POSIX语义明确拒绝，不实现完整Make解释器。
输入保留declared_inputs／declared_path、candidate_path及mapping_basis。含`..`的路径只在已选目录内逐段打开并核目录，用保留的父descriptor返回；不能越出所选根或跳过symlink／缺失组件。mapped_path只在安全打开后给出，文件的尾随`/`或`/.`不能被当作普通文件读取；未选择路径仍不自动解析或读取。
每个运行组件须从包内角色／ABI追到实际提供方、固定源码或已接受官方预编译件及生成配方、merge／strip／装配关系。上节维护当前组件取舍；官方源码／配方与发布对应不能冒称独立重建。
已提交Freezed／Riverpod／Drift／本地化／FRB代码作为可审项目源码，并关联生成输入、配置和版本；没有重跑的不能称本次生成。构建期bindgen／JNI头等仅在同次输入输出有绑定时增加对应，AOT depfile不等于所有输入最终存活。

engine源码范围沿Android flutter_shell_native、Skia／txt、Impeller renderer及Dart libdart／dart:io的固定GN展开；根树已有tonic／accessibility及Dart double-conversion不重复获取。图像／字体库、BoringSSL、RapidJSON、Abseil、FlatBuffers及Vulkan Headers／allocator从DEPS固定对象核原源；HarfBuzz pin为annotated tag，原tag字节及其指向的commit分别核对，不把tag hash冒称commit。
Brotli的WOFF2和libtess2的独立tessellator／测试分支即使取得源码也不自动算作此APK代码。Vulkan-deps仅作为固定配方／gitlink来源，取实际需要的Headers；shader compiler、SDK工具、验证层、playground、其它平台及关闭特性按各自条件排除。未执行DEPS、hooks、完整gclient同步或engine编译；未掌握历史完整构建参数的范围保持明确。

EasyTier原声明源码及生成关系仍未闭合。获审的一次独立WASI比较已经执行，输出与包内模块不同；有限来源恢复亦未取得原树，不再重复搜索或编译。新增工具与T02正式profile分离，实际工具接受、固定cargo分派的`--locked`及绝对WASM_OPT绑定、失败和差异保留在任务结果中。
其它组件按获审范围交付；不得替换模块／Core、伪造旧Git身份或将编译成功当生成闭合。原EasyTier关系的明确延期仅由上述备忘维护，不授予Core、依赖源、gitlink或carrier变更例外，也不扩大到其它Loop5出口。

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

T02验证首次获取／加载及此受管入口；T03追完整生成因果，T04收紧缓存／CI角色约束并明确直接旁路与其它host未获资格的边界，T05才对实际新APK绑定。当前T01只读工具及其partial_inventory语义保持独立。

### 构建执行与发布边界

Native checkpoint获审修订复用原Gradle task的完整注册Android rules，不直接调用未注册的build_hooks；同一Action及实际.last_build_id绑定原SDK执行与当前producer字节，stamp／result／depfile及--build-outputs均不是授权receipt。后者排除.dart_tool中间物，只作诊断；SDK正常重试的每次原task execution使用独占日志／报告目录，保留前次失败，根报告仅标识最后完成的原task。

本节定义T04当前实现；本机受管ARM64及本地合成／loopback消费者的实际结果见[T04 Result](loop5/l5_t04_result.md)。完整实现仍待M评审；不升级历史APK、其它平台运行或真实云端发布结论。

- BuildCache由生产者定义必需输出及私有staging（Helper的Cargo target也归本generation，不从共享target复制待发布文件），v2记录核精确集合／路径／类型／SHA-256；旧schema为miss且保原输出。必需输入缺失失败，optional absence参与指纹，实际工具／target／flags／依赖变化失效。普通记录是完整性材料，不是历史生成证明。
- 同canonical root共享固定outputs.lock及进程锁，从命中检查到record／回滚／backup清理均持有；buildPlatform将Go、Core摘要、Helper、manifest放在同作用域，外层失败恢复旧组。不同key共享路径同样串行；同root非重叠任务也串行，不同root独立。迟到cleanup只处理独占generation，恢复失败保backup并拒绝装包；取得锁后发现遗留generation也拒绝复用，改用新的自有workspace，不从未知中断状态追认记录；不承诺断电原子性或非协作写者／reader保护。
- 受管Native接入从固定SDK实际Flutter Gradle task的ExecSpec action取得完整参数，在该task原action前按同一完整注册Android rules运行两次assemble checkpoint；仅定点失效自有stamp并核同buildDir。实际hook结束时记录本run产出内容，checkpoint与原task后只能对照该期望，不从后来的候选重新授信。固定SDK内部方法改变或上下文不一致须失败；已完成本机原SDK消费者，未验证其它SDK版本。
- Native Assets沿标准user-defines感知有效输入，Go声明真实文件输出，受管入口通过固定SDK原注册Android rules依赖链中的BuildHooks核同真实请求及稳定结果；不能绑定实际上下文则停止受影响入口，不靠存在的库或自算receipt提升资格。raw继续按既有接受依据复用，不导入外来派生cache。
- 本地setup只package，拒绝发布／shell hook配置和Gradle发布任务；保留必要依赖读取及禁遥测设置，不宣称OS网络隔离。CI编译／notes／只读gate无发布secret，签名key限签名step，各目的地凭据分开；含Telegram secret service的job必须先由无发布secret的gate准入；首次授予service凭据／写权限的job条件同时核gate的run／attempt／commit，拒绝下游重跑沿用旧eligible结果，Pages deploy同样适用。
- 生产者受信job outputs提供固定slot的artifact ID／digest；GitHub上下文及API核repo／run／attempt／SHA／producer，candidate manifest只作数据。精确角色、普通文件、允许root及集合检查先于签名／发送；不通配接受、不得用旧attempt补缺。完整rerun保留，下游单独rerun缺同attempt前置则拒绝。
- Release只允许canonical repo的严格push tag并核peeled commit及版本。Android正式identity的开发签名候选只供独立重签，不是发布件；versionName核源码版本，拆分APK的versionCode保留原SDK的基础build number加ABI偏移（arm=1000／arm64=2000／x86_64=4000），签名前后均核同。依据[Android完整版本语义](https://developer.android.com/reference/android/content/pm/PackageInfo#getLongVersionCode())，高32位的versionCodeMajor仅接受缺省或显式整数0，AXML属性名／资源ID须一致，非零、非整数、重复或不支持编码在取得签名凭据前拒绝。Pages独立保留main push／main手动及受信稳定release完成事件，执行main固定源码，不执行上游artifact；只读gate／build先行，deploy才取得pages／OIDC写权限。
- 签名工具沿已接受37.0.0 raw build-tools的跨平台apksigner JAR；JVM小helper用该SDK原AXML parser读package／version、ApkVerifier API核签名及选定证书，不能用自报manifest代替APK事实。Python publisher使用标准库streaming multipart，不再安装requests／pip；容器使用前仍须接受精确digest。
- SSH发布增量替代原cpina的浮动Alpine／apk运行链，使用GitHub-hosted runner预装原生Git／SSH及必要Git-LFS；实际路径／版本／image只作观察。helper只替换固定clone目标（tap根保.git，F-Droid仅tmp），核源及index集合，main缺失／并发变更拒绝，普通push由受控pre-push核真实old ref。私钥／known_hosts只在独占目录、固定GitHub host key、禁继承agent／全局配置／未知hooks；退出探测的PermissionError／其它OS错误标为未知并保留材料，不按仅父进程已退清理；必要LFS绑定origin及对象范围，错误配置拒绝，不能回退普通大文件。原生平台工具非macOS Android profile认证，未执行真实远端SSH／push。
- Pages原外层固定composite内部仍调用浮动upload-artifact@v4；获审增量由项目helper制作同格式未gzip的artifact.tar，直接使用已固定upload-artifact。排除.git／.github但保留普通隐藏资源；归档只含安全相对路径的普通文件／目录，权限可读／可遍历、无主机owner／路径信息；只读gate及部署前按唯一name核受信ID，不向deploy-pages虚构artifact-id输入。
- CI helper只构造固定GitHub API origin／repo的路径，拒绝候选URL；artifact官方302下载跨源不继承Authorization／cookie／发布token，只送签名URL所需请求。错误不输出签名URL、认证或任意响应正文。假token／localhost与静态检查不能当成真实云端证明。

### 现有实现及未决项

实际JNI的CMake记录选择NDK28.2，Native Assets hooks选择29.0；JDK启动器／daemon、SDK/NDK/CMake及不同ABI须分别绑定，不为统一版本盲目升级。
T01基线中的Wrapper JAR是忽略的本地输入，自报2.10，distribution指向9.8.0且没有期望SHA。
受管入口使用正式官方9.8.0 Wrapper、distribution摘要及原生verification配置，并在本次完整委托链核工具／pub／hook选择。
本次setup cache已实现v2内容与精确输出核验、跨key所有权及整组失败恢复，针对性检查通过；本机受管Native／装包及定点篡改／API变化已自验，完整实现已获M评审通过，普通记录不构成历史生成证明，第三方缓存仍须沿其真实消费者判断。
本地禁upload／publish前缀任务只覆盖匹配名称，不是完整网络隔离。CI actions／distributor固定commit，job权限、当前cohort gate及签名材料作用域已有本地消费者／静态反例；没有真实云端job／发布执行证明。

后续落点由[Loop5 Tasks](loop5/loop5_tasks.md)维护：工具与工件认证归T02，源码／生成缺口归T03，执行／缓存／CI约束归T04，最终制品验证归T05。
EasyTier固定公开repo的声明commit查询返回422，只说明该repo未解析，不证明其它fork不存在或篡改；此生成缺口不能只靠重写hash关闭。
本项保留关键unknown，不把来源清单完成扩大为整个Loop5、发布身份或运行安全通过。若处置触及no-Core边界，需另交M决定，不在这里降验收或修改依赖源。
