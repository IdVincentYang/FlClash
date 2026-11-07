# L5-T03 运行组件与生成来源闭环 Plan

任务及归属见[Tasks](loop5_tasks.md)。本项从实际APK及同次构建输入追到可审源码、生成配方和预编译保留依据；不把锁文件全图当运行清单，不重做T02发布接受。
设计与R1／R2／R3技术修订均经M评审通过；用户2026-11-07明确延期原EasyTier WASM源码／生成关系后，T03按[调整范围](../deferred_security_items.md#loop5-t03-easytier-wasm-源码与生成对应)实现评审通过，已本地合入`security/android`，待M独立远端收尾。实际结果见[Result](l5_t03_result.md)。输入基线为`efd0a5fc9d9054627528598ec92ea17f5fcf3270`，Core固定`6c6e3e472bb246cc55f2e8577d9eddccc2623afc`且clean；T02已由M普通fork推送并核实远端同基线。

## 问题与目标

开发者需要知道安装包中的代码来自哪里，才能审查正确版本并在升级时复核。T01的字节关系及T02的工具／工件接受不能证明完整源码生成关系。
调查复用T02第五次原APK：55,189,483 bytes，SHA-256 `845a3804de290e148ec52c6472ed65ea3b3b81b3389a628ac37c4ccb931c68ff`；当前只读枚举为401项、10份ARM64 native及1份DEX。
它由原第五次输入生成，不是本任务基线的新构建；旧T01 APK仍保留自己的身份。原始观察位于`build/verification/l5-t03/investigation/`，不回写T02冻结及失败证据。

关键缺口是嵌入WASM的声明源码未解析，以及SQLite／AAR JNI只能追到预编译件。将“模块与包字节相同”写成“由声明源码生成”，会让后续审查落到错误代码。
本项出口是逐类形成有依据的保留／验证／必要局部再生成决定、可复查的提供方和消费者关系，以及实际相关的错误输入对照；关键未知未处置则本项不能结案。
用户明确批准的唯一例外是上述备忘中的原EasyTier源码／生成对应；该风险和原功能保留，不将例外推广到其它组件或后继任务。
行为安全、漏洞可达、设备加载及最终APK交付继续分别由Loop4／后续任务验证。

## 方案与理由

### 从包内对象追到实际输入

沿[现有来源契约](../android_build_sources.md)和只读对账入口处理下列六类关系。版本继续由原生锁／工具policy维护；来源解释归现有契约，不另建resolver、组件版本锁或审计数据库。

| 对象及消费者 | 拟补足的关系与决定依据 |
| --- | --- |
| Dart AOT → engine；JVM／DEX → Android／插件入口 | 用第五次Flutter depfile、package_config、源码snapshot、R8 mapping及实际class输入追提供方；编译记录的输入不等于树摇后全部存活。Maven source JAR按同坐标核，不能凭类名计数反推完整闭包。确实缺失的classpath记录在新的自有验证位置采集，不从全部Maven缓存补作实际输入。 |
| libclash → JNI；librust_api → FRB FFI | 用Go build info、实际tags／编译参数、Core carrier、Cargo target依赖／dep-info及hook输出绑定本地和锁定源码。C/C++／bindgen／QuickJS沿实际build script、头文件、编译输出追踪，不把桌面或测试依赖列作Android运行组件。Rust原API35 compiler别名与输入API24分别报告，不推导设备最低版本兼容。 |
| libcore／libdartjni → JNI | 读取同次CMake compile_commands／Ninja和生成头；绑定项目C++及获审jni包C源码、SDK头、NDK版本，再核本地输出→merge／strip→包。不能只凭库名或现存缓存认定生成。 |
| libflutter → Dart运行平台 | 复用已接受engine发布及flutter.jar成员；补固定engine源码、DEPS所选Dart及实际相关第三方源和官方配方。接受官方预编译engine，不默认重建引擎，不把源码可得称为独立复现。 |
| SQLite／Camera／DataStore预编译JNI | 按下节固定发布、源码／配方、ABI及条目逐对象作保留决定，核原件→转换→APK。复用T02 Maven及工具接受；同版本Java source JAR不替代JNI源。 |
| 已提交生成代码／构建期生成 | 用实际编译输入定位Freezed、Riverpod、Drift、本地化、FRB等源码及生成配置／版本；已提交文件按受信项目源码接收并保留可审内容，普通构建未重跑的不能标为本次生成。构建期bindgen／JNI头等另绑同次输入输出；仅对存在具体缺口者在独立副本再生成比较，不默认全库codegen或改提交生成物。 |

固定Git依赖及本地vendor／fork沿现有来源说明和原归档核实际差异，区分维护者提交、已知裁剪与未证明的上游对应；不为统一表格升级依赖。
系统DT_NEEDED只记录导入及提供平台，不宣称已取得或验证设备系统库。

### 预编译件与WASM的处置

SQLite已读到固定tag `ac40b296e7069c4e83503bcbe4a3b22dfe5431a7`对应的不可变release `364675648`。
其ARM64 Android asset `501022915`的官方digest与获审pub包hook表对应；原hook使用默认预编译分支，包版本3.5.1与ELF声明引擎3.53.4分开。
实施核[固定源码下载配方](https://github.com/simolus3/sqlite3.dart/blob/ac40b296e7069c4e83503bcbe4a3b22dfe5431a7/tool/download_sqlite.dart)、amalgamation版本／source ID和[构建配方](https://github.com/simolus3/sqlite3.dart/blob/ac40b296e7069c4e83503bcbe4a3b22dfe5431a7/tool/build_sqlite.dart)，以及默认编译选项／Android target，再以实际raw payload及strip前后对照核包。
保留官方预编译需这些关系均成立；发布recipe和二进制自报不冒称独立源码重建或发布者签名。无需为了证明本包来源改用自定义SQLite。

Camera1.6.1／DataStore1.1.7复用已接受AAR，分别核两个camera JNI及shared counter的ARM64 member、merge／strip与APK。
从[Camera发布记录](https://developer.android.com/jetpack/androidx/releases/camera#1.6.1)所指`987b9ac8585b31424a397206c492196dd163997b`及[DataStore发布记录](https://developer.android.com/jetpack/androidx/releases/datastore#1.1.7)所指`420da5f291449f11801e378c6789a328a06ec6cb`取得C/C++、CMake及实际依赖源；Camera还须追libyuv，不能在JNI胶水处截断。
同一发布及可审官方源码／配方支持保留官方预编译，不默认重建整个AndroidX；若版本、成员或源码关系矛盾则不能以官方名称放行。

原设计的EasyTier独立关口现按用户明确决定延期；以下保留获审的一次试验安排，实际失败见Result，不授予新的检索／编译。第五次libclash中完整命中6,850,909-byte模块WASM，但只证明编入。
其声明源码`63519db2b5f2a6a1b9b7f20905f036dab54eb829`在官方repo查询422，公开commit搜索无结果；不据此断言不存在或恶意。
固定Go模块对应的官方完整repo commit `3d0c9c3ca5e2c0b680383dedf5898f6c7eef9253`及Rust树可取得，仍不能擅自替代原声明。
推荐在设计通过后，先核可恢复的原源码对象；不能恢复时，以未改的固定完整公开树作候选，沿原`script/build-wasi-core.sh`进行一次独立局部再生成比较。
工具前提为原Rust1.95系列／wasm32-wasip1、Cargo.lock及build scripts所需工具、Binaryen131；Go生成器涉及的protobuf另核其原protoc35.1／protoc-gen-go1.36.11和schema，不因不执行proto生成而声称其已复现。
新增工具仅属本项独立复现，不改T02正式Android profile或版本权威。首执行前固定实际patch、host／target、官方精确对象／接受依据及payload，核Cargo.lock和实际参与的build scripts／生成工具，包括Rust脚本真正调用的protoc；不为齐表执行无关生成。
原WASI脚本没有`--locked`，Binaryen bootstrap也会复用仅查version的已有程序；采用task-owned固定cargo分派强制`--locked`和从空环境显式提供的WASM_OPT，将其绑定到已核固定归档成员。上游source及script字节不改，记录窄适配及完整实际命令；不以version或缓存存在授信。
复用T02接受原语，自有HOME／target／cache，不现场补装全局工具；选定有依据的一组后记录差异，不穷举版本／flags。
原feature、source remap、epoch和优化参数均记录，Cargo保持`--locked`；WASM已无producers custom section，不能从本体独立恢复精确compiler patch，所选固定版本及其依据须另记。不改源码或伪造旧Git身份来追求一致。
只有与包内完整WASM逐字相同的独立输出才能新增这一源码生成对应，且不反证旧构建过程；不同则保留差异，及时交M具体缺口、可行替代及必要权限，停止受影响交付，不替换模块WASM／Core，不以unknown表结案。

### 工具职责与写入边界

复用`inspect_android_build_sources.py`的显式APK／record／input选择、descriptor安全读取和现有字节关系，保持退出0仍可能partial_inventory。
拟增加可选`--build-evidence <input-name>`，只读一个已通过`--input`选择的构建根，解析已知Flutter depfile、CMake记录、Rust dep-info及已有R8关系；独立helper `tool/android_build_evidence.py`只将字节解析为声明，CLI沿用现有SelectedInput负责读取和范围核对，helper不反向依赖CLI。不执行记录中的命令、生成器或候选代码。
元数据中的绝对路径必须映射到调用者显式选择的输入根；越界／不支持格式／缺材料分别报告，不自动读取原路径或扫描全局cache。
输出English JSON分列recorded input、声明的生成器／参数、已核字节关系、未解析范围及原APK／构建身份；不以解析成功授予source-generation或whole-profile成功。
原record仍是私有观察格式，不能覆盖T02接受根；不把手写来源决定转成可自签的成功receipt。
记录可选build_evidence引用显式选择的原run context及其摘要，并声明source commit；depfile相对路径缺cwd时保持未解析，可用working_directories显式声明各格式的绝对cwd，仍不视作实际执行证明；核APK、workspace和source声明矛盾时失败，缺同次绑定时保持unknown。即使当前文件hash与历史路径对应，也只报告当前材料身份；原record／context本身不是生成证明。

正常调查与正式只读工具只输出报告。受控再生成或必要局部任务只在新建的task-owned位置写入，显式选择未改源码及获审材料，复用现有进程所有权机制；取消／退出不明保留原对象，不向旧证据目录写入、不处理用户进程。
工具或完整classpath记录确需新执行时，先完成材料接受及适用的自有环境准备，不把读取Gradle报告误称为不执行构建脚本。
完整CI、跨次缓存资格与上传权限仍归T04；本项不启动AVD／app／ADB／CU，不改Core／依赖源／gitlink／carrier，不恢复其它Loop。

## 实施与验证

完整实现Review要求的R1／R2／R3技术修订已通过M限定复审；原WASM关系按用户明确决定延期，调整后的实现范围通过并已本地合入，待M远端收尾。原implementation-first／second保持冻结；修订前的文档基线保留在revision-first/document-baseline.json，技术修订范围如下：
depfile的LF／CRLF续行必须保留输入边界，不能拼接名字；不支持的Make语义明确拒绝。compiler路径保留原声明及cwd依据，不在安全读取前用normpath消去上跳；含上跳的路径若不能沿既有descriptor权限准确映射则拒绝，不跟随symlink或猜另一个文件。
engine根树与DEPS pin不等于外部运行源码已取得；沿固定Android release GN及Dart VM消费者补实际需要的固定第三方源，区分根树已含、host／test／其它平台及未选特性。仅取官方固定对象并核身份，不执行DEPS／hooks或重建engine；具体不可取得对象交M，不用笼统递归限制掩盖缺口。

文档顺序：设计期维护本Plan及现有`loop5_tasks.md`／`loop5_plan.md`／总入口；M通过后先更新`docs/features/security/android_build_sources.md`的组件决定、输入分层及新只读契约，`docs/development/android_build_guide.md`的用法／前提，必要的`.agents/architecture.md`工具职责，再写helper／CLI与`tool/test_inspect_android_build_sources.py`的相关测试。
`l5_t03_result.md`仅在实际实施／验证后建立，绑定本任务受测snapshot、原包及新增输出；不重建T02 Plan／Result或另建并行组件台账。

验收以真实消费者关系和可区分的对照为出口，不预写通过：

1. 对原第五次APK运行正式只读入口，逐一核10份native、DEX／AOT与嵌入WASM；给出实际编译记录范围、外部源码／配方及残缺项，不把401条hash齐全当生成闭合。
2. 用同版本官方SQLite／AAR原件正对照及错误版本／ABI／同大小改字节／缺JNI源反例，核真实archive member到包关系；必要时对副本运行获审strip工具比较，不能以新材料证明旧包来源。
3. 用实际Flutter／CMake／Rust记录及有限合成反例，检查空格转义、遗漏输入、跨根路径、symlink、不同run／源码／记录不匹配；工具须区分不可读取、矛盾与未知，不能将未知变成成功。复用T01未变安全读取测试。
4. 对WASM核原embed／Wazero消费者、独立原配方输出及错误／截断／替换payload；未得到可审源与足够生成关系时明确不满足T03出口，并按上述边界交M处理。局部失败不撤销其它独立组件事实。
5. 对实际进入编译的fork／已提交生成代码与构建期生成分别核源及配置。版本或输入变化应使旧关系失效，旧缓存的存在不能补证；跨次cache执行行为本身留T04。无需为文档或提交历史改变重建整个APK。

各再生成输入／原recipe／工具／命令／PID／输出冻结在`build/verification/l5-t03/`，只登记实际取得和执行的证据；完整来源审查与剩余未验证边界交M实现Review，再按现有本地交付及M远端收尾流程接续T04。
