# L1-T09 Android 本地 QR 实现验证

implementation_v3 的本地自验、M1 实现评审及 ARM64 静态核对已通过。
本地提交/合入信息以本任务交付提交及 M1 最终对账为准；设备验收仍未执行。
真实入口仍为 Profiles → Add profile → QR code，相册在扫描页右上角。
当前行为与资源契约见 [QR design](../qr_scanning_design.md)，增量理由见 [Plan](l1_t09_plan.md)。
本记录仅证明下列对象与条件，不代表设备、光学效果、低端机性能或全局零外发已通过。

## 对象与复现

源码起点为 `security/android@0666e4931cd0f776021c4b9e8758beac6450e50a`，
受测对象为 `security/l1-t09-local-qr` 的本任务变更快照，
完整交评文件绑定见 [implementation_v3 snapshot](../../../../build/verification/l1-t09/implementation_v3_snapshot.json)。
979 个构建相关源码/声明/锁文件（含局部插件，排除 Markdown 与忽略输出）的构建前后摘要均为
`691fc24ecd48c43256ccf9ac5905e75345e1a43a71e10f2483020699cc8d1cb5`；
逐文件绑定在 [before/after 输入](../../../../build/verification/l1-t09/after_v3_delivery.json)。
核心 submodule 为 `6c6e3e472bb246cc55f2e8577d9eddccc2623afc`，源码未修改。

使用 Flutter 3.47.4/Dart 3.13.3、JDK 17、Robolectric 4.16.1 native graphics（sdk 34），
仅合成图片/URL/token 和临时 provider 文件。依赖来自项目配置的公开来源；没有真实用户数据或外部测试流量。
正式复现入口为 [plugin README](../../../../plugins/mobile_scanner/README.md)与
[Android build guide](../../../development/android_build_guide.md)。原始输出均在本地忽略目录
[`build/verification/l1-t09/`](../../../../build/verification/l1-t09/)，不会随提交上传。

## 自动化结果与证明范围

| 检查 | 实际结果 | 能证明的范围 |
| --- | --- | --- |
| 锁定 pub 解析 | 通过；仅 mobile_scanner 从 hosted 改为本地 path | 锁文件选择与包接入 |
| Root analyze | 0 error、0 warning；42 条继承 info | 本次无新增静态问题 |
| Plugin analyze | 0 issue | 局部 Dart plugin 静态检查 |
| Flutter 相关选集及 lint | 79 通过，0 失败/跳过 | 页面、URL consumer、channel 和项目 lint |
| JVM/Robolectric | 60 通过，0 失败/跳过 | 真实 decoder、转换及原生受控消费者 |
| ARM64 release | 构建与静态核查通过 | 当前源码可打包及下节包内事实 |

Flutter 通过集为 ScanPage、QrImageOperation、QR method channel、
link/picker、AddProfileView 与 test/lint，并补 QR 导入消费者；
[合并输出](../../../../build/verification/l1-t09/flutter_v2_all.jsonl)含实际计数。
覆盖相册双击、选图期间来帧、返回后等 resumed、解码中后台、离开后迟到 handle、只完成一次；
相机启动中关闭及迟到 permission/native-start 回复不会留下旧 texture。
取消确认不回复的 fake native 仍不能拖住 Dart 的 5 秒 timeout。
原有拒权/settings/重试、route、布局和 URL/安装链接筛选回归保留；非法 query 编码不泄漏 QR 文本。

原生选集为 36 个继承 lens selector、5 个 scanner/额度、6 个 decoder、13 个 gallery 用例；
[最终输出](../../../../build/verification/l1-t09/native_v3_final.log)与
[计数](../../../../build/verification/l1-t09/native_tests_v3.json)可复核。
独立 Python qrcode 8.2 writer 的固定普通 HTTPS、安装链接、UTF-8、2048 字符 URL、文本、
多码和 EXIF 2/6 样本全部识别；不共用 ZXing writer 作为唯一 oracle。
字面像素 oracle 覆盖 stride、crop 与四种 rotation，真实分析器覆盖窗口外同码移入、去重及帧恰好关闭一次。

真实 ContentResolver/provider 完成选图关联与解码，覆盖 A 取消/B 重入/A 迟到、helper 更换、
handle 单次消费/过期、非 content URI、声明超限/截断及编号持久递增/损坏/耗尽。
忽略 interrupt 的 open provider 实际经 ContentResolver 阻塞；read/close 则经注入 opener 的受控流阻塞，
用以隔离清理与额度时序，不能把这两项写成任意真实 provider 的行为。
三者取消/timeout 后都保持 album busy，直到真实工作/清理退出；camera 额度独立可取得。
这不证明任意 provider、文件系统 sync 或 CPU 可被强停。

Flutter 测试按项目允许方式临时关闭 build hooks，复用源码匹配的既有 Rust 库，
脚本 finally 恢复 pubspec 原字节；release 构建使用两项 `build_assets: true`。
首轮 plugin relocation 导致 Kotlin 增量缓存错误；非增量编译后通过，没有修改权限源码或扩大工具链配置。
本次构建使用 `-Dorg.gradle.project.kotlin.incremental=false`，精确命令/环境见
[build.command.json](../../../../build/verification/l1-t09/build.command.json)。

## 最终 APK、依赖及声明

合格制品为本地
[FlClash-0.8.99-android-arm64-v8a.apk](../../../../build/verification/l1-t09/artifacts/FlClash-0.8.99-android-arm64-v8a.apk)，
SHA-256 为 `d6defca6babc0982a17942b0a8435c3c8153361e97d7f58b06a3149d08aa3a24`，
57,244,854 bytes；与 Flutter 输出和 dist 包字节一致。
包为 `com.follow.clash.dev`、versionName 0.8.99、versionCode 2026102301，
仅 arm64-v8a，ZIP 完整且 Android Debug/v2 签名验证通过。
这是 dev 环境构建；不是正式签名或已安装验收的发布版本。

[核查摘要](../../../../build/verification/l1-t09/apk_inspection.json)绑定：

- 实际 release graph 选择 ZXing core 3.5.4；JAR SHA 与已审工件一致，image_picker_android 仍在图中。
  未发现 ML Kit、play-services-mlkit、DataTransport 或 Firebase 坐标。
- R8 mapping 的原名及内联记录保留 ZXing reader 与本地
  QrDecoder/QrFlight 消费链；
  未发现 ML Kit/internal-mlkit、DataTransport 或 Firebase 类族，不能只靠最终混淆类名搜索。
- 最终 Manifest 无 ML Kit 初始化、registrar 或 transport 调度组件；无 Photo Picker 安装 metadata。
  通用 ModuleDependencies service（disabled）/action、
  ImagePickerFileProvider、camera/INTERNET 权限仍保留。
- ZIP 无原 ML Kit 模型/TFLite/barhopper；最终 Flutter NOTICES
  含 mobile_scanner BSD 及 ZXing 的许可/notice。
  没有新增 decoder JNI；CameraX 仍有既有 native 图像处理消费者。
- R8 mapping SHA 与包一并保存；Go/JNI 的 packed/unstripped Build ID 对应，未剥离库含 debug_info，
  Go 的关键 ELF sections 与本次 libclash 源码构建输出一致。符号材料仅留本地忽略目录。

### R3 实测勘误

旧 selector 规则虽然使 merger 拒绝 image_picker 节点，却在最终 APK 留下 app 的同名空 metadata。
该失败包 SHA 为 `1c512ed49150dab06788e0838523641428da8f88343a1771bf705727c19c46b2`，不作合格交付；
[旧最终 XML](../../../../build/verification/l1-t09/r3_selector_final_manifest.txt)、
[旧 report](../../../../build/verification/l1-t09/r3_selector_merge_report.txt)和
[blame](../../../../build/verification/l1-t09/r3_selector_blame.txt)保留失败事实。

M1 已批准只对确切名称使用不带 selector 的 node removal。当前 merged/final Manifest 均无该节点，
保留 service/action/provider；report 的低优先级 REJECTED 只作来源依据，最终节点消失另经 APK 核实。
当前唯一来源为 image_picker_android；依赖升级如出现其它来源，仍须溯源/复审。

## v2 修订与补证

- 非 Android：新增 stop/epoch 撤销仅对 Android 生效。channel 对照验证其它 backend
  保留上游 pending-permission 行为；没有扩做 Apple 原生生命周期整改。
- I1：先 openRead 恢复备份；仅 base/.bak/.new 均不存在才首次初始化。
  已复现旧代码在 .bak-only 时错误返回 FIRST 的红例，修复后通过；孤立 .new 失败关闭。
  写入失败可 rollback，finishWrite 开始后不再 rollback，读回、校验或关闭异常只失败关闭。
  API24 的 finishWrite/failWrite/openRead 已按官方源码核对；运行矩阵仍为 sdk34。
  故障注入 AtomicFile 替身模拟 API24 的备份/提交/回滚语义，在提交后 read-back 和异常两种情形下
  检查没有 rollback，下一次仍从已提交 high-water 分配，不能把替身说成 API24 设备执行。
- I2：`qr_import_test.dart` 从真实 MethodChannel/StandardMethodCodec 和 Barcode.fromNative
  接收合成 Android gallery payload，经过 QrImageOperation 得到安装链接中的 URL。
  实际 addProfileFormURL/NamedUrlDialog 显示该候选，确认前与取消均为零 HTTP/零新 DB 行；
  再次扫码并确认后，仅向 loopback 合成服务 GET 一次，生产 Request/refresh/file transaction
  保存相同 URL、数据库行与下载字节。测试使用显式 direct 路由、独立 Request 与临时 SQLite/文件，
  Core 仅有 validation 替身；没有启动实际 Core、设备或系统网络代理。
  新 channel 的取消与错误 envelope 也经真实 codec 验证，错误只到固定用户提示。

I1 红例为 [atomic_recovery_red.log](../../../../build/verification/l1-t09/atomic_recovery_red.log)，
绿例见 native_v2_final，消费者链见 flutter_v2_all；
v1 的旧自验结论不替代这些增量证据。

## v3 pending-start 回复所有权

已有 A pending 时 B 只得到一次 busy，不替换 A 的 reply 或其 provider/lease。
新增真实 handler 回归通过受控 camera completion 证明 A 仍可正常成功/失败；
stop 或 dispose 撤销 A 后再接收 C，A 的迟到成功/失败既不再回复 A，
也不清除/完成 C，C 随后正常完成且各自只回复一次。
相机 completion 在测试中受控，不把这些结果冒充真实 CameraX 设备时序。

## 未执行与限制

没有安装/启动设备或 AVD，没有实际 CameraX 预览、系统权限/Photo Picker 三种可用性、
Activity/进程重建、低端设备内存/时延、模糊/倾斜/弱光光学集或 UID 运行流量证据。
已完成的是受控本地 decoder/channel/page 与包静态核对；不能宣称替代方案在所有场景等同 ML Kit。
header/采样上限、未知长度 EOF 和不可中断资源边界也不能由少量夹具推导为所有恶意图片均已验证。

已用主机合成 native endpoint 接续真实 Dart codec、URL consumer、生产确认与 Request 下载/保存，
但未实际执行 Android JNI/OS 选图或相机全链，也未证明通用跳转/日志风险已解决。
设备许可及这些验收缺口由后续安排处理，不以短时无外发或库移除证明整个 app/OS 零联网。

## 收尾检查

文档先建立 draft 基线，再实现与回填验证；当前契约、项目接入及任务状态已同步。
新增 QR 夹具及生成源是必要回归资产，APK、日志和符号均忽略；未纳入用户数据或临时预览。

vendor 原文保留；73 个可检查源码文件与官方 archive 字节一致，23 个有修改的 vendor 文件
按对应原文件计算本次新增行，均满足原 5%/20 行注释门限。全新代码与 app 增量默认 gate 通过，
提交前仅另清理 4 份继承源的空白行/末尾空白，已逐份核对规范化前后相同、无多行字面量影响，
故复用已审 v3 的构建/检查；字节差异与等价证明见
[whitespace_equivalence.json](../../../../build/verification/l1-t09/whitespace_equivalence.json)。
注释增量证据为 [vendor_delta.json](../../../../build/verification/l1-t09/vendor_delta.json)。
M1 已批准首次 vendor 导入若因继承注释被自动 gate 误报，可仅该提交使用 `SKIP=comment-density`；
其它 hooks 不跳过，不改全局门限或永久豁免目录。交付提交仅在默认 gate 因继承原文误报时使用该例外，执行结果见提交 Details。
