# L6-T04 Android 内置缺失 seed 验证记录

M已通过实现评审，本记录为本地交付定稿；远端交付须由M收尾后独立核实。范围见[Plan](l6_t04_plan.md)，当前状态由[Tasks](loop6_tasks.md)维护。
本次证明Android seed分支在缺失目标写前核对接受参考及精确字节；不证明设备运行、reader加载或全入口更新安全。

## 对象与复现条件

- 父仓库基线：`7f36200d2563c4f2fb057ffc380d57772d57e768`；隔离分支`security/l6-t04-geo-seed`。
- Core：`6c6e3e472bb246cc55f2e8577d9eddccc2623afc`，tree `f08a2ac1a2cd78649b4a144e4c3fb16318f96887`；源码及carrier检查通过，无Core／gitlink／依赖改动。
- 接受参考、四份payload及锁定依赖沿用T01；编译期manifest锚与仓库参考一致。发布来源与历史证据复用[长期契约](../geo_data_design.md)，没有重新声明独立签名或可复现生成链。
- Flutter 3.47.4／Dart 3.13.3、Go 1.26.4、Rust 1.98.1、JDK 17；Android hooks实际使用NDK 29.0.14206865、API 24、arm64。Gradle声明NDK不同的既有限制沿用[构建指南](../../../development/android_build_guide.md)。
- 合成home、AssetBundle及显式平台测试缝驱动真实`CoreController.init`，仅Core interface使用mock；生产gate仍为dart:io平台判断。

## 验证结论

| 检查 | 实际结果与边界 |
| --- | --- |
| `flutter pub get --offline --enforce-lockfile` | 退出0，锁文件未变；正常装配也完成依赖解析，未升级依赖 |
| `flutter analyze --no-fatal-infos` | 最终退出0，42条既有info，无新增warning／error |
| `flutter test test/core/geo_seed_test.dart test/core/controller_test.dart --reporter expanded` | 最终52项通过；使用正常Go／Rust hooks，无关闭build_assets |
| Dart format、差异及文档检查 | 三份Dart文件无格式变化；`git diff --check`通过；Markdown沿用MD013关闭的既有检查口径 |
| ARM64正常release装配 | `dart setup.dart android --arch arm64 --env dev`串行执行成功，assembleRelease 8.3s；无app／AVD启动 |
| 仓库参考 → APK资产 | 离线工具`ok=true`，四份payload及manifest与接受参考逐字对应 |
| Native、源码及制品绑定 | 10份APK native与Gradle strip输出一致；Go／Rust构建输出与对应merged输入一致；2732份构建前源码／配置核对，首次比较时3份MD变化，最终M复核含Tasks共4份MD变化，runtime无差异 |
| 隔离与资源 | 原T02的15份WIP与constraint_status_v1逐一一致；未进入本次源码／构建／提交范围；自有Gradle daemon已停止 |

## 正反例证明的行为

- 四角色合法字节在Core init之前写入；manifest及payload的非零offset／限定length不包含底层buffer的前后字节；写入使用验证后的独立副本。
- 一致修改manifest及四份payload，使内部size／SHA相符，仍被生产锚拒绝；没有文件或Core init。合法manifest下坏长度／摘要同样在对应目标写前失败；前项合法seed可以保留。
- 解析器通过显式不可信测试入口覆盖版本、未知字段、缺失／重复角色、filename／role／asset／format、size类型／零值、错误digest和JSON错误。此层仅检验结构，生产对篡改manifest先按锚拒绝，二者不混算为同一证据。
- 已有未知文件保持原字节；全部已有时，即使bundle不可用也不读取；只有ASN缺失时仅补ASN。先前mutation在payload预取后创建目标，guard内复核会跳过，不读取未使用manifest、不校验坏预取payload。
- 真实文件到同名目录的rename失败保留FileSystemException／OS error、清理stage、不调用Core init；资产读取异常保留原错误对象。没有用helper抛错代替这些消费者验证。
- 显式非Android夹具保持旧路径；宿主真实生产构造在Flutter target override为Android时仍采用dart:io非Android分支，不读取manifest。此为宿主证据，不是Android设备运行。

## 制品、失败记录与保留证据

最终APK为`FlClash-0.8.99-android-arm64-v8a.apk`，55,182,331 bytes，SHA-256：
`d805958b90846d5169ec4e8f7ed224128bd3a60d56d84a82ef946688b73ea8b3`。
Flutter输出与dist副本相同；实际package为`com.follow.clash.dev`、versionName `0.8.99`、versionCode `2026102301`，仅arm64-v8a。
ZIP完整性和本地签名校验通过，使用既有开发签名，不代表正式发布或设备安装。

首次分析有两条测试夹具新增info，已修正并保留原日志。首次装配退出0，但与最终测试重叠，日志出现`File modified during build. Build must be rerun.`；
该次不作最终制品依据。待测试退出后串行重打，退出0且无此提示，源码／配置绑定无runtime变化；首次和最终日志均保留。

稳定证据在原共享checkout的忽略目录`build/verification/l6-t04/implementation_v1/`，包含源码快照、构建输入摘要、完整检查日志、hooks输入／输出、APK及native／资产绑定。
包内旧comparison记录的是首次比较时点；最终M复核的4份差异为geo_data_design、geo_data_guide、l6_t04_plan及loop6_tasks。
获审后只补正文档状态及上述时点说明，复用未变化的源码／制品证据；冻结包和旧日志不回写，最终提交关系另作本地交付绑定。
从上述基线应用本任务源码，在[构建指南](../../../development/android_build_guide.md)环境下运行表中命令及离线`--apk`检查可复现；不需要用户文件或真实业务流量。

## 未证明与接续

只保护Android内置缺失seed，不接受／替换已有私有文件，不覆盖手动／自动／Core内部远端更新、兼容缓存迁移、热重载或正式版本UI。
没有四文件原子事务、跨进程排他、运行reader或路由验收；未执行设备／TUN测试。DNS R1及Core日志并发问题保持未解决。
T02及依赖T03按用户原Core约束暂缓，Loop6未完成；T04设计及实现评审均已通过，本地交付后由M独立收尾及远端核实。
