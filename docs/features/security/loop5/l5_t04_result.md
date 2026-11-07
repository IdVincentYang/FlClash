# L5-T04 构建执行与CI边界验证记录

**M已通过review-v3完整实现评审，I1／I2均闭合；本次为D本地交付定稿，M收尾及远端核实待完成**。输入Git／Core基线见[Plan](l5_t04_plan.md)，当前状态见[Tasks](loop5_tasks.md)。
当前契约由[构建来源](../android_build_sources.md#构建执行与发布边界)维护，入口见[指南](../../../development/android_build_guide.md#构建执行与ci发布约束)。
完整交评对象绑定在本机忽略目录`build/verification/l5-t04/review-v3/binding.json`；实际构建快照与最终代码的差异在其中单列，不把旧快照说成全部文件相同。

M复核已闭合v2-final的I1未知组退出保留行为。I2修订后复用同一真实SDK合成包：旧gate接受低位2007／major=1，新gate在无签名凭据时拒绝；真实完整code为4294969303。正常APK在旧／新解析器取得的四项身份事实一致。原冻结及M证据保留。

## 实际证明的内容

本项让BuildCache按生产者的精确输出及内容核验、按canonical root串行并恢复整组失败；让原Native runner与项目checker看到变化，并将本次实际生产的库／头绑定到正常装包。
CI把只读资格检查、编译、签名及各发布角色分开，产物选择来自本run／attempt的受信producer输出及GitHub API；候选inventory不授信。
这些是当前实现与对应本地消费者结论，不是历史生成证明、OS网络隔离或真实云端发布验收。

| 配置／实际消费者 | 结果与边界 |
| --- | --- |
| setup_hooks纯Dart包 | analyze无问题，最终62 PASS；含同进程／双进程、跨key同输出、非重叠输出、不同root、同size／mtime坏物、路径／类型／精确集合、内外层失败恢复、恢复失败保backup并拒绝复用及迟到owner拒绝。旧失败日志保留，不累加重复选集。 |
| 实际Go及Native重复 | 新的受管macOS ARM64→Android ARM64 dev完整入口；原SDK实际task参数／buildDir核同，两次checkpoint后原task执行。Go首轮真实编译，第二轮真实cache hit；第二次无cutoff提示。 |
| 实际Native篡改 | 保持主Go库大小和mtime、翻转一个字节，再定点失效本次build_hooks.stamp；原SDK进入真实cache，重建后精确回到冻结SHA，原生产者期望核同，不接受坏字节。 |
| 实际Native输入变化 | 在原SDK参数中仅把MinSdkVersion 24改25，真实Native input记录target_ndk_api=25；固定API24项目hook明确拒绝，旧产物未被追认。只是受管profile的拒绝反例，不是API25可用性结论。 |
| 根Flutter消费者 | pub get通过且lock未变；analyze最终42项既有info，无新增warning/error；正常Go／Rust hooks开启的setup_test共16 PASS。Dart格式检查通过。 |
| 实际Helper adapter | 自有macOS host小crate以真实Cargo走RustBuilder：私有target、精确复制、Core摘要注入、重复cache hit，继承的共享CARGO_TARGET_DIR未被使用。该测试不代表Windows/Linux Helper或服务运行验收。 |
| 实际Gradle manifest | 默认release为com.follow.clash.dev；显式stable candidate为com.follow.clash；dev混candidate在配置阶段拒绝。只运行manifest消费者，未额外打APK。 |
| 实际Gradle任务图 | 生产init拒绝uploadProbe／publishProbe，marker未执行；prepareLintJarForPublish正常执行。只证明已知前缀守卫，不是其它任务或插件的网络隔离。 |
| CI身份／归档／下载 | 15 PASS，覆盖严格事件/tag/commit、producer／run／attempt、ZIP额外件／链接／上跳／内容、Pages来源／tar、分页、真实localhost 302剥离认证及错误不泄密。 |
| workflow与实际Node消费者 | 4 PASS；从secret service／写权限job反向核当前gate cohort及输出映射、固定actions／独立matrix slot；实际执行Pages inline Node正反例。不是GitHub真实job运行。 |
| 实际SDK签名链 | 最终9 PASS：从接受的原始build-tools ZIP核完整摘要及成员后提取JAR；原SDK AXML／ApkVerifier API、临时三ABI APK／两把合成key、keyless verify→sign CLI、选定证书、版本／ABI／角色／缺件／篡改及失败清理。fixture的split版本规则从固定Flutter源码读取，不从helper生成唯一oracle。major缺省／decimal0／hex0的三ABI正例、显式0重签通过；非零／负值／高位值、重复、string／boolean／reference／float／null类型及resource ID／name／namespace异常均在实际签名有效的APK上拒绝。keyless CLI无签名凭据且不输出候选绑定。 |
| 实际SSH／Git-LFS helper | 10 PASS：本地bare repo的tap根替换／no-change、F-Droid仅clone/tmp、main缺失／并发前移拒绝、父环境隔离、源集合／类型、真实SSH对loopback错误host key拒绝、原生LFS默认GitHub端点保持SSH认证、localhost basic batch真实合成对象上传；新增父已退而零信号组探测EPERM时保留private key／known_hosts反例。没有真实远端SSH或push。 |
| Telegram实际发送消费者 | 3 PASS；localhost实际multipart只含原四份允许附件及notes，额外合成私有文件未发送，错误不回显token／响应正文。未启动Docker或真实Bot API。 |

## 正常制品及JNI对应

唯一正常受管APK为`FlClash-0.8.99-android-arm64-v8a.apk`，55,191,811 bytes，SHA-256：
`9b3026e8cd36e831a1ba7b7f0a962504b3c6eb0d0f0d7e500823a93ea871f825`。
CLI退出0，`android-package` exit0且进程组空；所有权检查另保独立daemon／进程观察，不从父组空推导全部daemon退出。

实际package为`com.follow.clash.dev`、versionName `0.8.99`、versionCode `2026102301`；固定SDK split-per-ABI在基础`2026100301`上加ARM64偏移2000。
原SDK ABI常量为arm=1／arm64=2／x86_64=4（3保留给已移除x86），签名gate按同一规则核拆分APK，不能误按基础code或x86_64=3。
APK公开开发证书已由接受SDK的ApkVerifier核验；不是历史正式发布证书或设备安装证明。

冻结的Go主库／JNI副本、Rust库与实际Gradle merged输入逐字一致；三份libclash／librust_api／libcore的strip输出与APK member逐字一致。
真实C++ compile commands、Ninja依赖含本ABI生成的libclash.h，libcore的DT_NEEDED含libclash.so；JNI使用NDK28.2、Go/Rust hooks使用29.0的既有分工保持。
APK观察到10份native，均为arm64-v8a。这里只完成T04有针对性的复制／include／link／strip消费检查，全部组件／AOT／DEX／来源闭包仍归T05，未执行设备／TUN。
实际对象绑定及只读复核脚本在`implementation-first/apk-native-binding/`。

## 偏差、失败与现场

- 首次`managed-normal-01`沿原SDK调用未注册的build_hooks CLI target，明确失败；经M复审改用原完整注册Android rules。原失败／冻结不倒改。
- `managed-normal-02`首轮checkpoint有File modified during build提示；第二次稳定、原task完成。后续Gradle遇官方Flutter JAR HEAD 503，原SDK自动重试一次后装包成功；没有手动多打APK。首次两个checkpoint／报告在自动重试覆盖旧同名诊断前另行保存，累计packaging日志保留503和retry。当前实现改为每个原task execution独占诊断目录；该纯观察性增量已实际编译Gradle init，不改原请求或生产字节，完整APK证据来自此前相同执行逻辑。
- Native反例前冻结正常result／checkpoint／原protocol及生产字节。篡改案例恢复原观察文件以隔离API25案例；后者保留失败Native配置。**该workspace此后仅作诊断证据，不能用于当前ready判定或重复使用**；原正常APK及其冻结绑定保持。
- 根分析首次有三条新增info，修正后回到42条既有info；一次退出后的killpg零信号检查短暂EPERM，原异常保留，随后kernel ESRCH且无观察成员。最终重跑记录exit0／组空，没有回写首次commands。
- 根测试最初缺rustup代理；补路径后普通hook过滤env使rustup尝试缺target维护并panic。仅涉及任务HOME；原接受toolchain payload成员重核未变，随后COW独立host工具并禁止自动安装的本地wrapper恢复固定rustup执行。它是host测试设置，不是新Android资格profile；依赖源／用户工具／全局cache未改。
- 实际SSH/LFS测试发现空filter.process阻止clean、空LFS URL override关闭默认端点，均修正并保失败。最后私有Cargo target fixture的手写lock被Cargo规范化，输入变化守卫正确拒绝；改在指纹前由真实Cargo生成lock后通过。
- APK比对首次对CMake原始-I字符串未规范化，误拒合法cpp/../cpp；随后检查真实参数解析路径。再由实际APK发现split versionCode偏移并修正CI gate；原SDK源码独立提供三ABI fixture预期。失败／修订日志保留，不把这些错误算成制品异常。
- 完整交评v1后独立检查发现SSH组退出探测的OS错误未标quiescent=false，可能仅凭父已退清理。v2改为未知即保留，并以实际已退的子进程加受控EPERM反例证明材料未被清理；v1冻结保留且被v2替代，未获审交付。
- M独立SDK反例暴露旧Java parser忽略versionCodeMajor；当前按获审profile严格限制缺省／整数0，资源ID另由实际android-35的android.R.attr核实。`i2-regression/result.json`及commands保旧／新对比、正常APK事实和所有自有子组退出；无重打APK。签名测试第07轮仅因断言误期望内部诊断而失败，CLI实际按原设计输出通用错误且拒绝；修正测试期望后第08轮9 PASS，不改生产错误输出。
- 静态检查发现下游rerun可复用旧eligible结果，step检查晚于Telegram service凭据授予。现于job启动前核gate的run／attempt／commit，Pages写角色同样适用；没有执行过带真实秘密的旧WIP job。

## 复核与未覆盖范围

从新位置按[指南](../../../development/android_build_guide.md)运行受管入口；显式材料selections只选择接受的raw，不复制旧SDK snapshot／hooks／Cargo target／Gradle内部状态。
普通包检查入口和fixture前提见[commands](../../../../.agents/commands.md#testing)。原始命令／退出／材料／标准Native协议／源码快照在`implementation-first/`，完整交评绑定在上述review-v3。
不要重跑保留workspace来证明当前资格，也不要修改hash、manifest、stamp或输入JSON绕过错误。

没有真实云端CI、GitHub/Pages/Telegram/tap/F-Droid发布、真实远端SSH／业务私钥、其它平台运行、设备／AVD／ADB、app启动或宿主网络调整。
原12证据worktree、stash及本项新证据保留；Core／依赖源码／gitlink／carrier不改，原EasyTier缺口及其它延期不恢复。
共享cache不提供断电事务、非协作同UID写者或任意并发reader保护，普通hash记录不证明历史生成；runner原生工具路径／版本只是观察，不能当独立平台认证。
M已核review-v3并通过完整实现评审。D按原授权交付本次定稿；正常hooks、格式／链接和相对获审源的等价核对记录在本机忽略目录`build/verification/l5-t04/local-delivery/`。M独立核实际提交、tree及Details后收尾／普通fork推送并核远端；此前不启动T05。
