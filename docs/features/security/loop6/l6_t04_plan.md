# L6-T04 Android 内置缺失 seed 精确核验 Plan

任务入口：[Loop6 Tasks](loop6_tasks.md)。M1设计通过，D-02在隔离工作树实施；输入父仓库`7f36200d2563c4f2fb057ffc380d57772d57e768`、固定Core`6c6e3e472bb246cc55f2e8577d9eddccc2623afc`。
本任务只保护Android缺失seed，T02／T03按用户原约束暂缓。原checkout的4Go和T02草稿保留，不进入本任务源码／构建／提交。

## 问题与方案

CoreController.init在initGeo后才调用Core init，但initGeo直接复制rootBundle，消费点不核T01参考；源码构建／同步时漏跑离线检查可能seed未接受字节。
在`lib/core/geo_seed.dart`集中保存派生锚和严格四角色参考解析／payload核验，由`lib/core/controller.dart`实际调用，不新增依赖、网络、权限DB或生成框架。
锚固定为`f721cff1e61a5b72c0d38ae57005d6064df33b7a2ba3dc8cdda7607b2ca85f30`，测试与仓库manifest核一致，资产仍是唯一来源；不能动态信任随包manifest自算的expected hash。
保留原payload预取，Android在原mutation guard内复核目标缺失后才加载manifest并使用／核验payload，按固定角色／filename／asset_name／format和正整数size／SHA校验；manifest每次seed调用至多解析一次。
ByteData仅取自身offset／length，payload使用验证后的自有字节沿原staged／flush／rename落盘，finally按原规则清理。已有／等待期间出现的目标跳过；全部已有时不读bundle。
生产gate固定使用system.isAndroid（dart:io），非Android保原路径。controller仅增加合成home／AssetBundle／平台的显式测试构造缝，正式启动不依赖Flutter target override。

## 失败与范围

坏锚、manifest映射／类型、payload长度／摘要在对应目标写前失败；init不继续调用_interface.init，核验错误只含角色／原因，不泄漏原材料。I/O原异常与清理传播保留。
允许前项合法seed已落盘而后项失败，不承诺bundle原子性、跨进程排他、已有缓存可信或reader加载。Core／依赖源码／gitlink／carrier不改；不修改自动更新、规则、DIRECT、运行生命周期或UI。
解析器反例通过独立测试入口覆盖，明确区别于生产锚先拒绝；一致篡改manifest＋payload仍须被锚拒绝，不能用同一材料自证。

## 文档先行、验证与交付

先新增本Plan并更新`loop6_tasks.md`、`loop6_plan.md`、`flclash_security_plan.md`、`geo_data_design.md`／`geo_data_guide.md`，明确draft与暂缓事实；再写controller／reference及`test/core/geo_seed_test.dart`。实际结果另建`l6_t04_result.md`，不提前写通过。
真实controller.init正反验证四角色、坏锚／一致篡改、结构parser分支、非零ByteData范围、已有／全部已有、guard内复核、真实文件I/O失败／stage清理／错误及非Android。合成测试缝不冒Android设备证据。
运行pub get、Flutter分析／相关controller测试，必要ARM64装配并绑定源码、内置参考／四payload／native／制品；无需app／AVD／业务流量。复用T01来源事实，不重跑其矩阵。
完整实现交M评审后才按pre-merge正常本地交付security/android，D不push。原dirty checkout不切换／覆盖；交付隔离seed增量，不夹带T02纯构件或草稿。M收尾前保可读目标checkout，不写后继任务。
