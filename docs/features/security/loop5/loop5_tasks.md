# Loop 5 任务清单：Android 构建与装包来源

本清单细化[阶段Plan](loop5_plan.md)，只维护一个任务层级。M1负责设计／实现评审与后续远端收尾，D-02负责当前调查、设计和获派任务的实施／自验／本地交付；联系与授权沿用既有独立聊天。
阶段拆解及L5-T01／T02设计和实现均经M1评审通过，已交付并完成任务记录收尾；T02由M普通fork推送并独立核实远端`efd0a5fc9d9054627528598ec92ea17f5fcf3270`。用户2026-11-06授权连续完成Loop5后续任务，用户2026-11-07明确延期[原EasyTier缺口](../deferred_security_items.md#loop5-t03-easytier-wasm-源码与生成对应)后，T03按调整范围实现评审通过并已本地合入，待M独立远端收尾。各项分别经过M设计及实现评审、D本地交付与M远端收尾后接续，不恢复其它Loop或no-Core例外。实际输入及证据边界见[来源基线](../android_build_sources.md)，T01定稿保留在交付提交`6d6387b37cd038a396be36aa62c661deb690ecde`的历史中。

| 编号 | 目标及验收出口 | 依赖 | 当前状态 |
| --- | --- | --- | --- |
| L5-T01 | [实际构建／装包来源基线](../android_build_sources.md)：覆盖执行、获取、生成、装包及未装入对象，交付可复核关系与只读对账入口；unknown显式保留，供Loop4／后续任务使用 | 当前获审APK及其构建证据、锁文件、已交付Core载体及Geo基线 | 已交付、M收尾完成；历史[Plan](https://github.com/IdVincentYang/FlClash/blob/6d6387b37cd038a396be36aa62c661deb690ecde/docs/features/security/loop5/l5_t01_plan.md)／[Result](https://github.com/IdVincentYang/FlClash/blob/6d6387b37cd038a396be36aa62c661deb690ecde/docs/features/security/loop5/l5_t01_result.md) |
| L5-T02 | [工具及发布工件获取校验](../android_build_sources.md#工具接受与受管构建)：实际工具选择、发布身份、固定引用及依赖验证有明确依据，错误工件被拒，正常解析／构建可继续 | T01实际对象及获取链 | 已交付、M记录收尾完成；历史[Plan](https://github.com/IdVincentYang/FlClash/blob/ff0a7e0be259dad941306699b59c82529ce3be54/docs/features/security/loop5/l5_t02_plan.md)／[Result](https://github.com/IdVincentYang/FlClash/blob/ff0a7e0be259dad941306699b59c82529ce3be54/docs/features/security/loop5/l5_t02_result.md) |
| L5-T03 | [运行组件与生成来源闭环](l5_t03_plan.md)：实际Dart／JVM／Go／Rust／JNI及嵌入执行代码各有源码／生成关系和保留依据；关键缺口获处置 | T01装包闭包；身份认证事实复用T02 | 按用户调整范围实现评审通过；[原EasyTier缺口明确延期](../deferred_security_items.md#loop5-t03-easytier-wasm-源码与生成对应)，已本地合入security/android，待M独立远端收尾；实际验证见[Result](l5_t03_result.md) |
| L5-T04 | [构建执行、缓存与CI约束](#l5-t04-构建执行缓存与ci约束)：不合资格缓存不能混入，构建与发布权限分离，正常本地流程不执行未获准上传 | T01真实消费者；T02接受的工具／工件身份 | 待细化；不预先改变脚本／缓存／CI |
| L5-T05 | [最终Android制品对账](#l5-t05-最终android制品对账)：实际源码、工具、生成物、native／DEX／资产及签名绑定正常产物，正反例与剩余限制交Loop4／Loop7 | T01–T04实际成果及未决项处置 | 待前置交付，不以当前APK重跑冒充已完成 |

## L5-T03 运行组件与生成来源闭环

从T01实际native、DEX/R8、AOT及嵌入执行内容追到精确源码、fork增量、生成输入／生成器版本和构建配方；已提交生成代码与构建时生成分开。
优先核EasyTier WASM声明的源码提交、SQLite预编译件与三份AAR JNI，复用已匹配锁定归档，不因模块含相同字节就宣布由该源码生成。
出口逐对象说明保留、验证、必要重建或约束的理由；本轮不预设改Core或依赖源。无法补足且处置触及约束时，明确阻塞对象、影响、可行替代及所需决定，由M处理，不用unknown清单代替关键问题解决。
源码和生成对应供Loop4审查；运行行为、协议安全和漏洞可达不因本项来源核验升级。
原EasyTier源码／生成对应仅按用户2026-11-07明确决定延期，恢复及权限由上述备忘维护；不自动延期其它组件、完成Loop5或启动T04共享后继。

## L5-T04 构建执行、缓存与CI约束

审查setup／Native Assets／Rust build scripts／Gradle插件及实际缓存读写，核源码、工具、target／tag变化后的失效和写入；现有size／mtime命中不等于输出内容身份。
沿真实执行入口限制本地上传／遥测，区分必要依赖读取与发布；复核CI action固定、job权限、tag／repository gate、签名材料作用域及产物传递。
出口包含正常命中／必要失效、同size／mtime替换、失败构建保留旧产物及已知上传任务拒绝的针对性证据；不靠删全部缓存、自算hash或禁用几个任务名宣布全面隔离。
只在项目约束内设计，仍须保正常构建／官方同步；不修改宿主网络、全局缓存或读取真实密钥。

## L5-T05 最终Android制品对账

复用未变证据，仅按实际增量构建最小ARM64 dev release，核全部native、DEX/R8、资源、公开签名身份及源输入，区分可解释strip／签名差异与错误工件。
汇总T02–T04的正常及反例，不为报告重跑所有历史矩阵；提供本地复现入口和变更后复核规则。
出口供Loop4与Loop7直接消费；没有设备安装或运行时加载证据的部分明确未验证。关键来源缺口未处置不得以此清单完成宣称全Loop通过。
