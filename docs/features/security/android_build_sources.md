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

实际JNI的CMake记录选择NDK28.2，Native Assets hooks选择29.0；JDK启动器／daemon、SDK/NDK/CMake及不同ABI须分别绑定，不为统一版本盲目升级。
当前Wrapper JAR为忽略的本地输入，自报2.10，distribution指向9.8.0且未配置期望SHA；尚缺Gradle验证／锁定元数据。bootstrap代码和已缓存发行件都需要获取依据。
setup cache核源码内容／target／tag／工具版本等输入，但输出命中以size／mtime为依据，不能当内容身份验证；外层hooks与各第三方缓存也需按实际消费者审查。
本地禁upload／publish前缀任务只覆盖匹配名称，不是完整网络隔离。CI actions／distributor tags、job权限、发布gate和签名材料作用域均需核，不能执行发布来“验证来源”。

后续落点由[Loop5 Tasks](loop5/loop5_tasks.md)维护：工具与工件认证归T02，源码／生成缺口归T03，执行／缓存／CI约束归T04，最终制品验证归T05。
EasyTier固定公开repo的声明commit查询返回422，只说明该repo未解析，不证明其它fork不存在或篡改；此生成缺口不能只靠重写hash关闭。
本项保留关键unknown，不把来源清单完成扩大为整个Loop5、发布身份或运行安全通过。若处置触及no-Core边界，需另交M决定，不在这里降验收或修改依赖源。
