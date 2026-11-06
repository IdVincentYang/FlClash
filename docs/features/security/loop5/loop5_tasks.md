# Loop 5 任务清单：Android 构建与装包来源

本清单细化[阶段Plan](loop5_plan.md)，只维护一个任务层级。M1负责设计／实现评审与后续远端收尾，D-02负责当前调查、设计和获派任务的实施／自验／本地交付；联系与授权沿用既有独立聊天。
阶段拆解及L5-T01设计／实现经M1评审通过，T01已交付并完成M收尾。用户2026-11-06新授权连续完成Loop5后续任务；T02完整实现及I1复审通过，当前为D本地交付定稿，待M收尾。各项分别经过M设计及实现评审、D本地交付与M远端收尾后接续，不恢复其它Loop或no-Core例外。实际输入及证据边界见[来源基线](../android_build_sources.md)，T01定稿保留在交付提交`6d6387b37cd038a396be36aa62c661deb690ecde`的历史中。

| 编号 | 目标及验收出口 | 依赖 | 当前状态 |
| --- | --- | --- | --- |
| L5-T01 | [实际构建／装包来源基线](../android_build_sources.md)：覆盖执行、获取、生成、装包及未装入对象，交付可复核关系与只读对账入口；unknown显式保留，供Loop4／后续任务使用 | 当前获审APK及其构建证据、锁文件、已交付Core载体及Geo基线 | 已交付、M收尾完成；历史[Plan](https://github.com/IdVincentYang/FlClash/blob/6d6387b37cd038a396be36aa62c661deb690ecde/docs/features/security/loop5/l5_t01_plan.md)／[Result](https://github.com/IdVincentYang/FlClash/blob/6d6387b37cd038a396be36aa62c661deb690ecde/docs/features/security/loop5/l5_t01_result.md) |
| L5-T02 | [工具及发布工件获取校验](l5_t02_plan.md)：实际工具选择、发布身份、固定引用及依赖验证有明确依据，错误工件被拒，正常解析／构建可继续 | T01实际对象及获取链 | M完整实现及I1复审通过；D本地交付定稿，待M收尾 |
| L5-T03 | [运行组件与生成来源闭环](#l5-t03-运行组件与生成来源闭环)：实际Dart／JVM／Go／Rust／JNI及嵌入执行代码各有源码／生成关系和保留依据；关键缺口获处置 | T01装包闭包；身份认证事实复用T02 | 待细化；EasyTier WASM与SQLite预编译件为已知重点 |
| L5-T04 | [构建执行、缓存与CI约束](#l5-t04-构建执行缓存与ci约束)：不合资格缓存不能混入，构建与发布权限分离，正常本地流程不执行未获准上传 | T01真实消费者；T02接受的工具／工件身份 | 待细化；不预先改变脚本／缓存／CI |
| L5-T05 | [最终Android制品对账](#l5-t05-最终android制品对账)：实际源码、工具、生成物、native／DEX／资产及签名绑定正常产物，正反例与剩余限制交Loop4／Loop7 | T01–T04实际成果及未决项处置 | 待前置交付，不以当前APK重跑冒充已完成 |

## L5-T02 工具及发布工件获取校验

输入为T01发现的实际工具与工件，不把pub／Cargo／Go锁或Maven缓存全量清单直接当运行清单。
核Flutter/Dart/engine、Go、Rust、JDK、SDK/NDK/CMake及Gradle/AGP/Maven/AAR的发布者、固定对象、渠道、checksum／signature及证据强度；固定distributor与必要bootstrap/action引用。
区分Wrapper自身、distribution、依赖验证和版本锁，核已缓存输入而非只验证首次下载。包管理器重打包另记，不冒充原始发行件。
出口是可执行的项目范围校验／固定策略及相应正常、错摘要／版本／已缓存工件反例；没有独立签名时明确采用的接受依据，不虚构证明。
不预设工具升级、全源码重建或统一所有NDK版本；不改Core、第三方依赖源码或用户全局工具／缓存。

当前接续出口为按授权提交并本地合入`security/android`，由M完成后续收尾；D不push，M收尾前不接续T03。
I1旧版外部程序选择已重现，新版7项正式CLI反例在workspace创建前拒绝，普通／空格位置均选中预期程序，
当前73项Python检查通过，M独立复核通过，见Result及`i1-path-qa/`。第五次普通路径证据保留。
正式入口、三套pub图、新snapshot、原launcher／packager、有限Maven接受配置及新Gradle状态已有实现和局部正反例；
首跑发现固定Flutter／插件还需SDK36，已补Platform36及Build Tools36角色并关闭SDK现场下载，缺失／替换材料的真实入口拒绝已核。
第四次原入口已产APK，但实际Native Assets runner过滤FLCLASH／RUSTUP_HOME／CARGO_HOME等变量，
两处hook的受管检查未激活且实际Cargo无`--locked`；该次`profile_ready=true`是程序误判，不作为合格构建。
已记录自有进程退出，原输出／APK保留为失败证据。
R1局部实现已使两个原hook通过真实SDK／runner过滤链完成构建；另以消费者前marker及停止夹具核16项正反对照，
漏传／缺失／改配置、跨workspace、错compiler、替换工具及伪重入均按对应条件拒绝，父注入未进入实际消费者。
证据分别见`r1-filtered-positive-second/`及`r1-filtered-counterexamples/`（位于下述证据根）；
第五次全新workspace的正式CLI及完整原入口退出0，两个hook标准输出与本次配置／输入绑定已核，
实际Go／Cargo进程选择、ARM64 APK及进程退出也已对账，见[Result](l5_t02_result.md)，M已完成完整实现及I1增量评审。
现有证据保留于`build/verification/l5-t02/implementation/`，design_v2冻结不回写；组件通过不表示T02已交付。

## L5-T03 运行组件与生成来源闭环

从T01实际native、DEX/R8、AOT及嵌入执行内容追到精确源码、fork增量、生成输入／生成器版本和构建配方；已提交生成代码与构建时生成分开。
优先核EasyTier WASM声明的源码提交、SQLite预编译件与三份AAR JNI，复用已匹配锁定归档，不因模块含相同字节就宣布由该源码生成。
出口逐对象说明保留、验证、必要重建或约束的理由；本轮不预设改Core或依赖源。无法补足且处置触及约束时，明确阻塞对象、影响、可行替代及所需决定，由M处理，不用unknown清单代替关键问题解决。
源码和生成对应供Loop4审查；运行行为、协议安全和漏洞可达不因本项来源核验升级。

## L5-T04 构建执行、缓存与CI约束

审查setup／Native Assets／Rust build scripts／Gradle插件及实际缓存读写，核源码、工具、target／tag变化后的失效和写入；现有size／mtime命中不等于输出内容身份。
沿真实执行入口限制本地上传／遥测，区分必要依赖读取与发布；复核CI action固定、job权限、tag／repository gate、签名材料作用域及产物传递。
出口包含正常命中／必要失效、同size／mtime替换、失败构建保留旧产物及已知上传任务拒绝的针对性证据；不靠删全部缓存、自算hash或禁用几个任务名宣布全面隔离。
只在项目约束内设计，仍须保正常构建／官方同步；不修改宿主网络、全局缓存或读取真实密钥。

## L5-T05 最终Android制品对账

复用未变证据，仅按实际增量构建最小ARM64 dev release，核全部native、DEX/R8、资源、公开签名身份及源输入，区分可解释strip／签名差异与错误工件。
汇总T02–T04的正常及反例，不为报告重跑所有历史矩阵；提供本地复现入口和变更后复核规则。
出口供Loop4与Loop7直接消费；没有设备安装或运行时加载证据的部分明确未验证。关键来源缺口未处置不得以此清单完成宣称全Loop通过。
