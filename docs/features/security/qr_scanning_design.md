# Android QR scanning design

Android 扫码在本地解码，输入来自 CameraX 或用户主动选择的图片。二维码只产生候选 URL；
用户确认导入后才进入已有订阅 Request。当前实现已完成本地交付，设备验收仍未完成。
共同判定依据为[安全要求](security_requirements.md)。

## 实现边界与职责

| 对象 | 职责与边界 |
| --- | --- |
| `plugins/mobile_scanner` | 保留上游 UI、CameraX、permission 和 Activity binding |
| `QrDecoder` | 本地 QR 解码；输出原始文本及固定 QR/text 类型 |
| `QrCameraWork` | 相机分析 executor 的进程范围额度；旧工作实际退出前不创建替代 worker |
| `QrGallery` / `QrFlight` | 系统选图关联、一次性 handle、provider 读取、deadline、撤销和实际资源占用 |
| `QrImageOperation` | Dart 调用与接收期限、局部撤销、候选筛选及固定用户错误 |
| `ScanPage` | 页面、前台和 camera/gallery 互斥意图；只完成当前 route 一次 |
| `profileUrlFromQrCodes` / `addProfileFormURL` | 筛选 URL/安装链接；原有确认、持久保存和下载出口 |

来源、许可证、支持子集和升级步骤见 [plugin README](../../../plugins/mobile_scanner/README.md)。
Android 不再依赖 ML Kit、模型或网络 decoder；不用 `ResultParser` 导航，不自动打开 URL。
只支持显式 QR format，拒绝其它 format、`returnImage` 和 ML autoZoom。
不提高应用 minSdk 24 或 JDK 17 要求，不增加 JNI。非 Android backend 保留原平台实现。
本项不清理旧 image_picker cache，也不解决 T04/T05 的全部身份、跳转与日志风险。

## 相机与图像转换

分析器读取 Y plane，按 buffer position、row/pixel stride 和 ImageProxy crop 取样，
再按 0/90/180/270 度转为正向像素。scanWindow 使用正向图的归一化边界，先裁剪再解码及去重，
避免窗口外第一次识别抑制后来移入窗口的同码。输入最多 16 MP；帧在所有路径恰好 close 一次。

CameraX 使用 `STRATEGY_KEEP_ONLY_LATEST` 和单分析 worker。NORMAL 按 detectionTimeout 节流，
NO_DUPLICATES 按可交付文本集合去重；结果采用单槽合并，main 不积压每帧回调。
已有 pending start 时第二次 start 返回 busy，保留原调用；stop/dispose 才撤销原意图。
stop/dispose 清空去重与待交付结果，递增 epoch；旧 provider、permission 或启动回复不得恢复已撤销的意图。
Android 的 Dart channel/controller 同时在异步边界拒绝旧启动结果，
避免旧 texture 阻止新会话；新增 stop 撤销仅在 Android 生效，保留其它 backend 的原行为。
保留 preview、torch、zoom、camera direction 和权限提示/settings 的既有消费者。

帧、Bitmap 和图片字节不送入 Dart，不保存快照或识别历史。相册与相机使用独立 decoder 和 worker，
不共享 reader 实例；相册阻塞不占用 camera 的分析额度。

## 系统选图及安装声明

Android QR 相册路径直接调用 AndroidX activity 1.12.4 的 `PickVisualMedia(ImageOnly)`，
不经 image_picker 的私有 cache 复制和 FileUtils 错误日志。无 camera 权限也可选图；
不申请整库 storage 权限，不持久保存 grant，只接受本次返回的 content URI。
其它平台仍走 image_picker/analyzeImage。

该版本 contract 的 createIntent 顺序为系统 `ACTION_PICK_IMAGES`、可解析的已安装
system fallback picker、`ACTION_OPEN_DOCUMENT`。fallback 只匹配 system/default handler，
没有单独 GMS picker 分支。[Photo Picker 官方契约][photo-picker]说明系统选择能力；
本项目按固定版本源码维护实际顺序，升级时重新核对。

image_picker_android 仍因其它平台依赖而被注册并合并 Android Manifest。
app 的 [Manifest](../../../android/app/src/main/AndroidManifest.xml)
使用不带 selector 的
`tools:node="remove"`，仅删除 ModuleDependencies 下确切名称
`photopicker_activity:0:required` 的 metadata。当前唯一来源已核实为
`io.flutter.plugins.imagepicker`。本版 merger 会保留带 selector 的 app 空 marker，
因此不使用该形式。保留通用 ModuleDependencies service/action、
ImagePickerFileProvider 和其它合法消费者。升级时检查 release graph、merge report/blame、
合并及最终 Manifest，防止其它来源重新加入该安装请求。

本 app 不为这项用途显式请求安装模块。OS/Play Services 的独立更新、其它 app 的请求、
用户选择的 cloud provider 下载均不由本 decoder 控制，不能据此承诺 OS 或整个 app 零联网。

## 关联身份与一次性交付

接口为 `pickQrImage(clientId) → handle?`、`decodeQrImage(handle) → capture`、
`cancelQrImage(clientId)`。clientId 在 Dart engine 内单调递增；native helper 绑定当前 engine/Activity。
handle 是不含 URI 的一次性 native requestCode，只有当前前台页面可以接续解码。
重复在途请求返回 busy；取消/过期/结束的 handle 不可复用，未知撤销幂等。

native 从保留区间 `0x6F000000..0x6FFFFFFF` 分配 raw Android requestCode，永不回绕。
在 [noBackupFilesDir][no-backup] 的 `qr_launch_sequence` AtomicFile 内保存下一编号；
worker 同步写入、sync 并核对成功后才在 main launch，未 launch 的编号也不回收。
读取先经 AtomicFile.openRead 恢复平台备份；不能只看 base 是否存在就重置编号。
仅 base/.bak/.new 均不存在时首次初始化，孤立残留、损坏、写入失败或耗尽均失败关闭。
提交开始后只核验并失败关闭，不再调用未提交写入的 rollback；
避免旧 AtomicFile 的 failWrite 删除已提交且无备份的进度。
文件不含 URI、clientId、图片或识别历史，
不恢复任务或进入用户导出。当前插件集合的其它 requestCode 不占用该区间。

Android result listener 先按 code、当前 helper/flight/phase 及撤销状态核对，再解析返回内容。
取消 A 后 B 使用新 code；A 的迟到返回被丢弃。Activity/engine detach 清除旧 callback 并撤销；
新 helper 不继承 URI/handle。进程重建只保留分配进度，旧 code 未知且不会分给新调用。
外部 picker 未返回不要求 app 强制关闭；无实际工作后可安全再次选择。

## Deadline、I/O 与资源所有权

| 阶段 | 期限与限制 |
| --- | --- |
| 编号保留和 launch 准备 | 5 秒；过期准备结果不能 launch |
| 用户等待选择 | 不计入解码时间，不占线程等待 |
| 返回后的 handle | 5 秒内由 resumed/current 页面接续，否则过期 |
| decode | 从 Dart 发出前计 monotonic 5 秒，覆盖排队、I/O、转换、解码和接收 |
| 图片输入 | 最多 32 MiB；header ≤64 MP，采样 ≤4 MP |

读取使用带 CancellationSignal 的 `openAssetFileDescriptor`。不为文件名/尺寸另做 provider 查询。
短 read 继续累计到正常 EOF；零进展、异常、取消、超限或已声明长度不匹配时不解码前缀。
未知长度的正常 EOF 只说明 provider 结束该流，不能证明其提供了原文件全部内容。
关闭外部资源后才把完整内存字节交给 Bitmap、EXIF 方向/镜像转换和 ZXing，Bitmap 在 finally recycle。

每个进程至多一个 album flight 的工作和一个异步清理任务，跨页面/handler/engine 共用额度。
不排重试队列，不因 timeout 创建替代线程。worker 只持 application context；撤销清除 URI、
prepared launch 和接收 callback。资源通过原子交接关闭，
slot 等工作及清理实际退出才复用；
关闭异常使相册保持 unavailable，避免假装资源已释放。

[CancellationSignal][cancel-signal]、interrupt 和 close
都不能强制终止任意 provider 或同步 CPU 调用。
取消立即撤销交付并回复，不在 main/camera worker 或控制锁内等待关闭/join；
Dart 也不等待 native 取消确认。若底层不返回，album 保持 busy，而相机、手工 URL 和文件导入仍可用。
资源占用不超过上述额度，但不承诺立即擦除 retained 输入或强停。强隔离需另评审可终止进程方案。

VM/OS 冻结会延迟 timer，恢复后再按 elapsed time 拒绝过期结果；timeout 不等于物理退出。
页面离开、解码中后台及 Activity/engine detach 都撤销。外部 picker 导致的 inactive/resumed
不误取消等待选择；选择返回后等待 resumed 再 decode。camera 只在 current/resumed 且未完成/未选图时恢复。
短期候选引用随结束清除，不承诺 GC 安全擦除；确认后进入原订阅保存契约。

## 错误与验证边界

取消返回 null，无 QR 返回空 capture；读取/超限/格式/资源错误只用固定 code。
Dart 映射为 localized busy/timeout/read-failed 或无效二维码提示；不把 URI、路径、二维码文本、
平台异常 message/details 交给 safeRun 或日志。安装链接的非法 query 编码按无效候选处理。

回归使用独立 Python writer 的固定合成 QR、真实 ZXing、ImageProxy/provider 消费者、Dart channel 和页面；
fake UI 结果仅证明协作。原生受控 open 与注入的 read/close 阻塞分别标识，不能推导任意 provider 可被停止。
设备 CameraX、权限、真实 Photo Picker、进程重建、光学困难集/低端机性能及 UID 运行观测
由 [Loop 7 整体验收](loop7/loop7_plan.md)接续，执行前须取得相应设备运行许可；
最终包静态核查不替代这些运行证据。

[photo-picker]: https://developer.android.com/training/data-storage/shared/photo-picker
[cancel-signal]: https://developer.android.com/reference/android/os/CancellationSignal
[no-backup]: https://developer.android.com/reference/android/content/Context
