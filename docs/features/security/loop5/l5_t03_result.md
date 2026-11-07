# L5-T03 运行组件与生成来源验证记录

implementation-second的R1／R2／R3技术修订已通过M复审；用户2026-11-07明确延期原EasyTier WASM源码／生成关系后，**T03按调整范围实现评审通过并已本地合入security/android，待M独立远端收尾**。延期对象及恢复条件由[备忘](../deferred_security_items.md#loop5-t03-easytier-wasm-源码与生成对应)维护，原来源／生成未证明的结论不变。
范围与输入基线见[Plan](l5_t03_plan.md)，当前保留决定由[来源契约](../android_build_sources.md#受管原包的源码对应)维护，使用入口见[指南](../../../development/android_build_guide.md#构建来源只读对账)。
本项没有新Android APK、设备运行或行为安全验收；原包、发布接受、源码可审、独立生成和运行使用分别判断。

## 受测对象与新增能力

受测交评对象为`efd0a5fc9d9054627528598ec92ea17f5fcf3270`加当时未提交变更；修订交评文件及证据摘要绑定在本地`build/verification/l5-t03/implementation-second/source-snapshot.json`及`evidence-index.json`。implementation-first源副本、摘要及原失败均保留，不回写。
获审后仅整理表格、记录用户明确范围决定及交付状态；最终提交／tree、文档delta和源码等价绑定见本地`build/verification/l5-t03/delivery-first/final-binding.json`，不重新生成原APK。
实际APK始终是Plan所列T02第五次原包：55,189,483 bytes、401项、10份ARM64 native及1份DEX。原输入为`de0b868`及其同次WIP，不改称由本任务HEAD生成。
Core固定`6c6e3e472bb246cc55f2e8577d9eddccc2623afc`；Core／依赖源／gitlink／carrier、正式工具policy及T02受管profile未改。原失败、冻结包、证据worktree及Loop6 stash保留。

`inspect_android_build_sources.py`新增可选`--build-evidence`，仍由CLI持有显式输入选择及安全读取权限；`android_build_evidence.py`仅解析传入字节，不做I/O或执行命令。
报告区分compiler声明、当前文件身份、外部cwd声明、同run声明匹配和生成／运行证据。缺cwd不猜相对根，未选择路径不读，目录不冒充内容hash；context不是attestation。
退出0仍可为`partial_inventory`，生成保持`not_proven`；实际矛盾退出1，结构／读取边界错误退出2。工具不下载、不构建、不更改输入。

## 实际组件与提供方关系

以下均复用原包和T02接受的工件，不以缓存全量代替实际输入。证据根为`build/verification/l5-t03/`；表中路径均相对此根。

| 对象／消费者 | 实际取得与判断 | 证据入口及限制 |
| --- | --- | --- |
| Dart AOT及构建记录 | 正式CLI读取60份Flutter／CMake／Rust元数据，5740个去重声明中核5729份当前文件、4个目录，6个路径未选择、1个watch marker缺失、0个相对路径未解析。JNI包另核2份CMake记录、3份当前C源。 | `build-evidence-qa-sixth/`、`jni-build-evidence-first/`；同run声明匹配不是历史内容attestation，更不是所有输入最终存活。六个未选路径涉及Git配置／索引等，未为凑覆盖而读取。 |
| JVM提供方及DEX | 新自有Gradle仅解析ARM64 release配置：148组件、713边、111个external artifact记录，按坐标及内容去重为108份，全部与原第五次归档核同。取得104份同坐标sources JAR共4313份Java／Kotlin源条目；两份Flutter工件沿固定engine源，两个ConstraintLayout工件沿2.0.1固定tag源码104份main Java补足。 | `classpath-query-second/`、`jvm-source-materials-second/`、`constraintlayout-source-first/`；新图不是原R8执行，没有app编译／新APK。空sources JAR不当代码来源；DataStore protobuf另见下行。 |
| DataStore重打包protobuf | 发布sources JAR只有metadata；固定DataStore源码配方指向protobuf-javalite4.28.2及package relocation，取得上游159份Java源与AndroidXRepackageImplPlugin配方。 | `jvm-repackaged-source-first/`；保留官方重打包件，未独立执行shadow或重建；同渠道checksum不当独立签名。 |
| 原R8类名对应 | 原mapping的2509个原名对应实际DEX定义：2321个与外部归档或原编译class输出同名，181个余项有R8 synthesized标记，其余7个在原resource class JAR中找到。 | `jvm-provider-correspondence-first/`三份结果；这是名字／提供方对应，不是逐指令生成证明；合并／inline及零命中不能证明代码不存在。 |
| Go／Core与Rust／QuickJS | 原Go build info的120份版本化模块逐一核go.sum、ZIP h1及物化树；Rust锁定119份registry归档与树，target dep-info涉及50个包候选。QuickJS C／头、build.rs及该run的bindgen输出当前身份可审；官方Rust1.98.1标准库源另核接受归档。 | `go-linked-source-identity/`、`rust-android-source-identity/`、`rust-runtime-source/`；归档含未编译平台／测试，host宏不自动算Android运行代码。API35 compiler别名不证明API24设备兼容。 |
| 项目JNI／生成代码 | 原CMake指向项目C++及jni包C源；已提交Freezed／Drift／本地化／FRB等30份实际记录输入另核。现存cgo头及原GoBuilder staging配方可审。两个Git fork对原发布源核增量，本地code_forge按项目裁剪维护源接收。 | `submitted-generated-inputs.json`、`cgo-header-correspondence.json`、`runtime-source-materials/`；cgo staging头未保留，记录中的same_bytes=false是缺副本，不是两份头内容矛盾。未重跑全库codegen／cgo／bindgen。 |
| engine／Dart及运行第三方源 | engine根树19819项和Dart源码58870项保持原绑定；另核18个根DEPS对象及嵌套Vulkan-Headers，合计38350份file条目，逐项区分运行／条件／配方角色。ICU数据与原libflutter在offset824064逐字对应。 | `engine-runtime-deps-first/verified-source-relations.json`及`consumer-scope.json`；下节说明修订范围。不是原完整编译轨迹、独立engine重建或运行观察。 |
| SQLite与AAR JNI | SQLite固定发布配方到3.53.4 amalgamation及source ID；官方raw的独立NDK strip副本与包内SQLite逐字同。Camera／DataStore三个ARM64 AAR JNI成员到包核同；固定AndroidX C++／CMake及Camera manifest所钉libyuv完整源可审。 | `native-strip-qa-first/`、`androidx-native-source/`、`androidx-camera-manifest/`、`camera-libyuv-source/`；保留官方预编译，不称已编译SQLite C或独立重建AndroidX。 |

## R1／R2／R3修订与复验

R1将续行删除改为Make默认的空白折叠，支持LF／CRLF及转义边界；不支持的多反斜杠换行、bare CR和.POSIX明确拒绝。
R2保留原声明、cwd及映射依据，不先normpath；沿SelectedInput原descriptor权限核每个目录，父跳转只回已核父descriptor，越出根或遇symlink拒绝。不存在的中间目录保持unavailable；尾随目录语义不能将普通文件误认作合法输入。
最初保守拒绝全部上跳使原Rust两条合法路径失败，记录在`revision-tool-qa-first/`；最终安全逐段核对支持这些路径，未放宽普通record／archive引用的上跳限制。

最终`revision-tool-qa-fourth/`旧26＋新23项共49项通过；正式60记录和JNI入口重核均通过，覆盖计数与上表一致。
`revision-cli-probes-third/`的12个真实CLI对照覆盖LF／CRLF、escaped space、绝对／相对symlink上跳、合法上跳、缺目录、越出根及文件／目录尾缀；3个续行夹具另用原生make -rRnp只读解析，原反例现在分别核a／b而非ab。拒绝时也保留原声明；未执行记录命令或候选代码。

R3沿113份已核根GN／DEPS／tools配方及外部固定配方补材料：

- Android shell → Skia／txt：取得Skia、ICU、HarfBuzz、FreeType、图像codec、Expat、zlib原源；Dart dart:io另用BoringSSL／zlib。RapidJSON／Abseil对应lib/ui及FML，FlatBuffers对应Impeller runtime_stage，Vulkan backend对应allocator／Headers。
- HarfBuzz根pin `49844c32a7a3f6be371355a1213c952a3f4a44e7`实际为tag对象，原字节核Git hash后指向`6f4c5cec306d31e6822303f5ba248a14293d588e`；没有用别的版本替代。首通用读取器拒绝tag shallow边界及三个带gitlink树，失败保留；后续只读核blob并单列gitlink，未执行submodule init或候选脚本。
- Vulkan-deps的DEPS与gitlink同指Headers `a4f8ada9f4f97c45b8c89c57997be9cebaae65d2`，该源另取并核；其它shader compiler／工具／验证层／playground不冒称Android runtime。RapidJSON/gtest及FreeType/dlg只保留未消费gitlink声明；Brotli默认关闭WOFF2、libtess2独立目标虽取得材料，均不据此断言编入。
- 根树已有tonic／accessibility、Dart double-conversion等不重复下载。release排除Perfetto、Windows Crashpad及其它关闭特性；未机械同步全部DEPS。原源／配方可审不证明历史完整参数、逐文件因果、设备库或独立engine构建。

上述材料、消费者和排除条件由`engine-runtime-deps-first/`的关系记录及recipe副本承载；原Git对象／索引留各自task-owned位置。未改任何源pin、依赖、SDK、Core或T02 profile，也未再搜索／构建WASM。

## WASM未闭合及正常功能影响

原Go模块及包内完整WASM均对应6,850,909 bytes、SHA-256 `8b82f37d62fba2ffe8e256386096fddf448d4261d51c495d5bd97cd11bbb24a0`，声明源为`63519db2b5f2a6a1b9b7f20905f036dab54eb829`。
官方Git对象获取返回not our ref，已标识PR／fork／导入父树的有限调查也未恢复原树；这些是有限负证据，不证明源码不存在或恶意。

获审的一次实验使用未改公开候选`3d0c9c3ca5e2c0b680383dedf5898f6c7eef9253`及原WASI脚本：
已接受Rust1.95.0 host／wasm32-wasip1、Binaryen131、protoc35.1；255份Cargo registry归档及实际target Git依赖在首执行前核对。
自有空环境、固定cargo分派强制`--locked`、绝对WASM_OPT／PROTOC及离线编译；原源码、Cargo.lock和script未改，T02正式profile不变。
退出0但生成7,104,680 bytes、SHA-256 `f6910e5032d7fce1eaa60c278efb82e67aefb18ddc745a42eac2aab7c18f10db`，长度增加253,771 bytes，code／data等段不同，不只是metadata差异。
原Go schema声明亦与所核父树／候选的schema摘要不同，不能只换新blob维持binding兼容。工具接受、实际命令、section差异与独立复核保存在`wasm-compile-first/`及`m-review/`；有限恢复见`source-recovery-next/`、`source-recovery-parent-tree/`。

正常配置使用EasyTier时，TCP DialContext、UDP ListenPacketContext及对应DNS路径可经ensureStarted进入corehost.New，由wazero编译／实例化嵌入模块。
因此替换、升级或禁用会影响EasyTier连接及其TCP／UDP／DNS能力；本项只核源码路径，未发真实流量或证明运行错误。没有以未触发、禁用、静默DIRECT或改变Core边界规避本项。

用户明确选择保持不改Core、延期这一缺口并继续；只调整本次交付出口，不把原来源、独立生成或行为安全记为通过。恢复条件及未来替换所需的新权限见上述备忘，当前不执行新的检索、第二次编译、模块替换或功能删减。T04／T05仍按各自真实前置和验收推进，Loop5尚未完成。

## 验证、失败及复现

- 原43项证据保留于`build-evidence-qa-sixth/`；修后49项及受影响消费者复核见上节。继续覆盖空规则／目录、symlink／越界、不执行shell文本、缺材料、同size／mtime替换context、错误APK／源码／run声明及禁止静默忽略context或覆盖CMake cwd。
- 六个实际CLI材料对照在`material-relationship-cases/`：正常退出0；同size／mtime坏SQLite、错误Camera ABI／角色、错误Go metadata均退出1；缺JNI源退出0但保持partial_inventory／unavailable。未执行坏二进制或将该结果当受管构建反例。
- 迭代中曾将目录依赖当文件、拒绝有效空Flutter规则、错误默认Rust相对cwd；修正后以新QA保留全部旧失败及旧成功，不回写旧结论。首Gradle图未显式ARM64且artifact query失败，不能作原图；第二次用精确target、external component filter及新内部状态取得上述图。
- 首JVM源码收集因同GAV重复artifact记录停止；第二次按坐标与内容去重，复核所复用字节。两个sources JAR的404及DataStore空包保留，通过上述固定原源补足，不编造发布源。公开源下载的截断／checksum拒绝及有限恢复记录保留，未经接受的工具未执行。
- 本次只改Python只读工具／测试及文档，无Dart／Android生产实现、依赖或codegen增量；复用未变T02分析／Flutter验证，不为此重建整个APK或重复旧矩阵。完整CI／跨次缓存资格留T04，最终新APK绑定留T05；两项未启动。

正式只读命令及前提见指南；本机`revision-tool-qa-fourth/commands.json`包含绑定原包、原record及显式输入根的修后CLI，JNI及材料对照目录各有commands.json；合成CLI夹具按results中的case和同名.d恢复输入后复现。
依赖原证据目录的命令不称可任意搬运；新增配置诊断也执行了Gradle及SDK build logic，不能称为纯文本读取。
任务自有进程与退出状态由commands.json记录；无需app／AVD／ADB、用户数据、真实订阅或上传本地材料。
