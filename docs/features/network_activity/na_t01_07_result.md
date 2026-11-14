# 07 Host 覆盖规则 Result

输入基线 e6bb845。批准方案见 [07 Plan](na_t01_07_plan.md)，
当前契约见 [Design](network_activity_design.md#host-覆盖规则)。
实现与自动检查已完成，测试包 2026100316 已安装；本轮 Android 受控路由验收已通过，交付提交绑定本记录所处版本。

## 可体验内容

- Tools → Application network → 某 App → Host item 右侧规则按钮。
  点击 item 主体仍查看连接；右侧只显示新连接的当前策略及采用状态。
- 同一全屏页切换“本 App／通用”，各自创建、编辑和保存草稿；目标复用可搜索的原规则选择 UI。
- 删除当前范围后，另一条存在则切到另一范围，两条皆无则返回 Host 列表。
- 规则保存到原 Rules 库；App 总开关控制本 App 的默认与 Host 例外，通用规则独立。
  只创建 Host 规则不会顺便指定整个 App 的默认策略，也不隐式启动 VPN。
- Rule：本 App＋Host → App 默认 → 通用 Host → 原规则；Direct 不采用通用 Host；Global 保持原全局代理。
- 策略设置入口收敛到对应 item 右侧；目标失效保留绑定并说明原因。
  原 Proxies 页面及 Dashboard 的模式控件保持现状。

## 自动验证

Flutter 144 项相关专项通过，覆盖两范围四种存在组合、草稿保留、创建重试、删除跳转、
应用开关、离线保存、订阅 fencing、升级及 SQLite 文件重开。
既有规则编辑对话框、表单、活动页、连接页和分组采用相关回归通过。
静态检查无错误／警告，42 条 info 与原基线一致；代码生成及变更文件格式检查通过。
结构 lint 扩大检查中的 design_package_test 仍命中原 test/bootstrap_test.dart import，未计为通过。
其它 lint 通过；Markdown 检查沿既有长行边界排除 MD013，空白与注释密度通过。

Go 全套测试与 vet 通过。另用当前编译的真实 Dart managed compiler 运行 Host 专项及受管策略独立性检查，
确认新 Host 设置保留 ManagedPolicy 图及 checkpoint 重放，删除后不复现。
Dart／Go 使用同一固定摘要 fixture；Host 精确匹配、大小写／尾点、IPv4／IPv6、不扩大匹配、
TCP／UDP 优先级、未知／共享身份和缺失目标 REJECT 有覆盖。
桌面 1000 条规则索引 benchmark 约 25–27 ns／次、0 B／0 alloc；这不是 Android 电池测量。
匹配只查内存，不新增逐连接数据库访问、网络探测或后台定时器。

## 制品与设备

Debug ARM64 0.8.99／2026100313 已保留数据覆盖安装到原 emulator-5554／Pixel_7a_API_34。
签名沿原开发证书，SHA256 为 5a7c9cb8db640dfac17b75daba333e285ba76595e6e71b2d7d2d0e851f8849ec。
APK SHA256 为 6d81ee1f73cafcdd512d51efea8be5ef191c0db0d56fb2afd4e172db8da05e93。
包内 Core／Dart 内核与构建暂存逐字节相同，安装后 APK 摘要也相同；未导出 Downloads。

本地 .buildlog/na07-device/source-binding.json 记录输入提交、变更源码摘要、Core gitlink 与制品内容，
installed.json 记录安装后核对。证据仅保留本地，不上传日志、截图、APK 或 Core 子仓库。
构建首次因文件变化由 Flutter 自动重跑，最终成功生成包；只以最终完成产物为据。

## 支持边界

规则限定精确 Host／IP；不采集完整 HTTPS URL 或改变已有连接。
共享 UID 的不同候选需要一致决策，否则回到模式原路径；不会借其它连接猜测身份。
既有复杂规则仍由原编辑器及普通匹配链维护；旧精确覆盖首次转换会重组一次配置。
未运行、待采用、目标失效与保存失败各自反馈；没有宣称远端节点必然可达。
完整跨入口验收、真机耗电与 Release 交付留在 08／09，本次不推进。

## 入口与按钮收敛修订

按用户后续确认，Host 按钮从 112 宽改为 64×56，状态图标在上、策略名在下，最多两行。
长名称省略，完整名称和状态保留 Tooltip。标签在大字体约束内缩放，按钮不把条目撑高。
应用策略只由应用 item 右侧进入，Host 策略只由 Host item 右侧进入；
删除应用页与目标页菜单、连接页和普通规则管理页的重复入口及对应路由参数。
Host 页的应用总开关也移除，关闭时显示状态提示，总开关统一回应用 item 右侧操作。
共用应用组的选择仍作为应用策略页内的选择步骤；VPN 接管设置和普通自定义规则保留原职责。

95 项相关 UI、规则列表、本地化与结构检查通过，包含 64 宽度、竖排、长名称、大字体、四语言窄屏及入口收敛。
静态检查无错误／警告，保留原 42 条 info。
扩大 widget 检查初次的 8 项布局溢出已修正并由相关测试重验；
另有 3 项既有 update_dialog_test fixture 失败，未计为通过。
测试包 0.8.99／2026100314 已保留数据覆盖安装到现有 emulator-5554，签名、包内 Core／Dart 内核及安装后 APK 摘要核对通过。
APK SHA256：936a85aff514fa28a08079b82950bece00694fdaa9845fde11ca34e96b5b827e。
本地 .buildlog/host-policy-compact/source-binding.json 与 installed.json 记录版本绑定；
本次不启停 VPN 或操作模拟器界面。

## Host 项内容去重修订

按用户确认，Host 项只展示目标、连接数／最近活动时间和完整分组链，删除 ProcessName、包名及命中规则描述。
包名／UID 保留在搜索框下方原身份区域，现有单条连接详情不变。
分组链和左侧旗帜取自同一最新活动连接；没有已确认活动连接时取最新历史，多路径显示其它路径数。
右侧保留 64×56 的纯文字按钮：继承应用策略显示“跟随应用”，普通规则路径显示“跟随规则”，
生效的 Host 例外显示目标；只在配置异常时出现警告，完整目标和采用状态保留 Tooltip。
本次不增加进程 Tab 或改变应用身份采集，原始规则与连接事实未修改。

99 项相关专项通过，覆盖重复文本删除、路径及旗帜同源、历史回退、多路径、继承与例外、失效警告和大字体。
扩展 widget 检查 619 项通过，3 项既有 update_dialog_test fixture 失败单列，未计为通过。
静态检查无错误／警告，保留 42 条基线 info；本地化生成、格式、注释密度与 Markdown 检查通过。
Debug ARM64 0.8.99／2026100315 已保留数据覆盖安装到现有 emulator-5554。
签名、包内 Core／Dart 内核与构建暂存、安装后 APK 字节摘要核对通过；
APK SHA256：f37e457413f11dd1f05a3cbc4c9ca674621458251ad9760ea97d6f310684a2cf。
本地 .buildlog/host-item-content/source-binding.json 与 installed.json 记录源码／制品关联；
验证不操作模拟器页面或启停 VPN，未导出 Downloads。

## VPN 通用 Restart 提示收敛

旧 VpnManager 在 VpnProps 或 TUN stack 改变时立即显示 Restart，不等待实际采用，
所以 VPN 应用范围已生效仍会提示。删除该 manager、VpnState 派生状态、lastVpnState 缓存、
快照里的重复字段、节流 tag 和四语言两条废弃文案；Android 的既有服务所有者和真实错误反馈保留。

VPN 设置仍经既有完整应用；Android 配置事务额外比较 VpnOptions，
让协议栈及端口、认证、绕过域名、路由范围等依赖变化使用同一完整应用路径。
Core 返回 configuration_reapply_required 或 config is not applied 时明确禁用来源热采用。
未启动只保存，新 Stop 和 expectedRun 代次保护继续优先；没有新增第二个 VPN 运行所有者。

122 项专项通过，覆盖上述设置、无变化抑制、普通模式热更新、离线保存、失败保留设置、
完整应用回退和 Stop 抢占，包含 Manager Stack、Setup 真实配置流程、本地化和相关结构检查。
组件回归 619 项通过，原有 update_dialog_test 的 3 项 fixture 失败单列，未计为通过。
扩大检查还发现未修改的 AndroidManager 测试有 3 项直接写受保护配置及未清理计时器的失败；
未扩大范围改写这些 fixture。静态检查无错误／警告，保留原 42 条 info。
代码与本地化生成、格式、Markdown、空白及注释密度检查通过。

Debug ARM64 0.8.99／2026100316 已保留数据覆盖安装到现有 emulator-5554。
签名、源码构建前后摘要、包内 Core／Dart 内核和安装后 APK 字节摘要均核对通过。
APK SHA256：4693aa55ecdf04c2485ac40e81c5c708ee5b30ba912a1d23b223a3398b1a2a28。
本地 .buildlog/vpn-auto-apply/source-binding.json 与 installed.json 记录绑定，未导出 Downloads。
本次没有操作模拟器页面或主动启停 VPN；Android 新配置实际重建的交互复测未在本次执行。

## Android 验收与提交收尾

以 2026100316 的实际安装包完成现有 Pixel_7a_API_34／emulator-5554 验收，
源码与该包构建前后摘要一致；不通过换一份 Core／手写规则文本推定产品行为。
两个独立受控客户端在 11 组配置下共执行 66 次请求，覆盖 TCP、connected UDP 和 unconnected UDP。
检查无例外、通用 Host、App 整体优先、本 App＋Host 优先、同目标不同 App 使用不同组、
REJECT、Direct 不采用通用 Host、Global 忽略本地策略，以及删除后的逐级回退。
客户端成功／失败、宿主代理转发记录及 Core 的应用身份／分组链交叉核对，22 组客户端结果均无错误。

结束后恢复原私有数据与 VPN AppOps，1271 个原文件摘要全部一致；移除本次安装的受控客户端，
VPN 断开，临时备份在确认恢复后删除。验收只连接本机测试服务，没有向外部发送订阅、日志或项目内容。
本地证据为 .buildlog/na07-device/acceptance/report.json、restoration.json 和包版本绑定，
不纳入版本库。Flutter 编辑页的草稿、保存、删除、错误与入口交互由对应真实 widget 测试覆盖；
上述系统验收单独证明 Native 路由，不把其中任一部分冒充另一部分覆盖。

提交前结构自查覆盖统一 Rules 存储／派生 Host 视图、控制器事务／原生采用、规则索引和共用编辑器，
未发现本次引入且需额外决策的结构问题；这是作者自查，不声明独立评审。
真机电池、旧 Android 和整个需求的跨入口 Release 验收仍归 09。

提交前补跑 154 项 Host／App 编译、数据库、控制器、分组、编辑器和列表专项，全部通过。
VPN 配置收敛的 122 项专项、619 项组件通过及既有失败，沿上文的有效源码绑定复用。
