# L2-T03 服务状态与接管验证

原子暂停、故障意图收敛、共享控制状态及 Restart 竞态已实现并自验，
implementation_v3 已经 M1 复审通过，I1 关闭，Q1 以准确披露关闭，Q2 以合成入口证据关闭。
当前进入本地交付，M 后续独立收尾与普通推送；本地目标核实结果另绑定 `integration.json`。
服务契约见[Design](../android_service_design.md)，English UI 和复现入口见
[Guide](../android_service_guide.md)。本项不改变 mihomo 源码或 gitlink。

## 受测对象与条件

输入基线见[Plan](l2_t03_plan.md)。本次未提交改动绑定本地
`build/verification/l2-t03/implementation_v3/snapshot.json` 及 `review.patch`；
该目录的 `checksums.json` 绑定证据。不要把输入 HEAD 当作已包含本项实现的受测提交。
原始输出保留在忽略目录，不随源码上传。

- Flutter 3.47.4、Dart 3.13.3、JDK 17；Android API 34 ARM64 专用 English AVD。
- APK 为 `FlClash-0.8.99-android-arm64-v8a.apk`，SHA-256：
  `77f9a379174a579d282099faaea68cf13e8268d23a89d6f5a2754133e9601075`。
  `apk.json` 记录内嵌 Core 的 SHA/Build ID、ZIP 完整性和当前构建输出匹配；
  `apk_build_sources.json` 的 1029 项输入构建后未变。
  v3 未再次安装 AVD；v2 的设备安装 SHA 记录保留在其 `avd/installed_apk.json`。
- Core 源码为 `6c6e3e472bb246cc55f2e8577d9eddccc2623afc`，无本项改动。
  二进制携带父仓库 VCS 信息，因此不要求与 04 APK 的字节 Hash 相同。
- AVD 为 `FlClash_L2_T03_D02` / `emulator-5580`，私有 ADB port 5041。
  仅使用新建合成数据、本地业务端/SOCKS5/TCP DNS，不操作已有 `emulator-5554`。
  `avd/ownership.json` 记录实例、镜像和 PID；测试客户端不采用系统 HTTP proxy。
- AVD 使用普通合成 Profile，未选择 managed policy；这是系统接管证据，
  不能代替 L2-T02 整项 managed 能力验收。业务、DNS 收件由独立本地端点观察。

v1 提供暂停/故障/UI 实现及较广 AVD 矩阵，v2 补单次 Restart 请求及实际提示入口。
v3 修复暂停分派的观察 revision 竞态，并增加 manager 的平台测试入口；Android 默认分支不变。
native 生产代码和 Core 未变；正常生成仅更新 SetupAction debug source hash，未改模型或接口。
复用 v1 的 66+17 项 native 检查及 v1/v2 AVD 结果；
各次受测 APK 分别绑定其 `apk.json`。v3 重跑完整选集及 I1/Q2 消费者，不重跑未受影响的设备矩阵。
所有冻结版本的快照、patch 和 checksums 分别保留，不覆盖旧证据。

## 实际证明的范围

| 层次 | 结果 | 不代表的范围 |
| --- | --- | --- |
| Dart → MethodChannel → JVM | 暂停/恢复、Stop、迟到响应通过 | Android OS 仍为受控 host |
| SSID/provider/manager | opt-in、未知、停止后不恢复 | 读口/平台/端点受控 |
| native → Go/Core | 暂停/丢失关闭旧业务/DNS，恢复重新接受 | Linux Core 不证明 Android FD |
| 专用 AVD APK | VPN、TUN、排除、bypass、撤销等实测 | 不证明物理 Wi-Fi/cellular |

同一状态机和正式配置消费者参与前两层，没有用返回字符串代替业务收件。
JVM host 只替代 OS 服务/权限操作；Core 的 Linux features 与 Android 路由证据明确分开。

### 暂停、故障与交错

- 真实 Flutter/native bridge 覆盖暂停 stop、保留恢复意图、离开暂停后重新接受，
  以及手动 Stop 阻止后续恢复。
- 四个独立 Dart action 回归覆盖：旧暂停响应晚于手动 Stop；外部 native 新命令先到；
  publication 的 failed 响应；退出响应。当前四项通过，原基线四项均失败。
  基线替换仅用于验证，当前文件已按字节恢复，未提交基线覆盖。
- native stop 屏障确认清理完成前仍为 Stopping；失败为 failed，
  不发布 Suspended/Stopped，不恢复旧计时；新 Start 不被旧清理回调终止。
- publication 失败、退出、revoke/binding/service loss 清除失效运行意图；
  旧身份不得清除新请求。真实 Core 在暂停或丢失后拒绝旧业务/DNS，DIRECT 计数不增加。
- 控制/页面回归确认暂停仍可 Stop，启动可取消，服务身份未清空不显示 Suspended。
  长状态文案的按钮宽度已约束；现有桌面 tooltip 断言保留。
- 真实 VpnManager 提示按钮回归在 Restart 等待期间手动 Stop。
  原 Stop→await→Start 恢复了运行计时；单次 Start 请求修复后保持停止。
  该项旧失败/新通过单独保存；OS 重建仍由原 native 接受机制负责。

### 同意图观察更新（I1）

在真实 MethodChannel 的 native 方法返回和 Dart 分派间设置屏障，实际调用
`ServiceStateMachine.observeNetwork`。先确认 Notifier 收到较高 publication revision，
而 processEpoch/intentRevision/运行意图未变，再释放旧方法响应。

| 场景 | v2 判断下的反例 | v3 |
| --- | --- | --- |
| 暂停 | Stopping、服务未清、stop +0 | Stopped、身份清空、stop +1 |
| 恢复 | Preparing、start +0 | Started、重新接受、start +1 |

暂停结果记录后，用同请求 native stop 独立准备恢复前提；这个测试补救不计为暂停完成，
表中暂停结果采样在补救前。两个窄测及真实 bridge 在精确 v2 SetupAction 下均失败，
当前通过；`i1_red_context.json` 绑定旧实现与测试来源，并核实当前源码按字节恢复。
较新本地/外部意图、错误进程、failed/exiting 的正反例继续通过。
精确 revision/phase 校验仅从暂停分派移开，计时等已有用途的检查未放松。

### 用户 SSID 入口（Q2）

既有 `test/manager/connectivity_manager_test.dart` 的 13 项测试覆盖可控读口、opt-in、
currentSSID、未知/失败、过期读取和 disposal，未覆盖 AppStateManager 的 Android 分派。
v3 新增组合测试实际挂载 ConnectivityManager 和 AppStateManager，使用真实 currentSSID、
excludeSSIDs、suspendProvider 及 SetupAction；仅替代平台判定、SSID/native service 端点和无关 IO。

- 未配置排除列表时不读取 SSID、不发 pause；首个排除值使已连接的合成 SSID 触发 pause。
- 读口模拟无权限返回 null，或有权限但未知时，不宣称命中排除；观测变化使保留意图走恢复。
- 再次匹配后手动 Stop，随后离开排除网仍调用新 pause 命令，但返回意图已关闭，不再 build/start。

变化通过受控 connectivity 事件送入，不表示真实 OS 权限切换会立即通知。
这补齐 provider/manager 到新命令的联系；I1 另以真实 MethodChannel/JVM 证明下游。
真实 AP/SSID/headless、Location permission UI 和物理切网仍未运行，不转交 05 默补。

### AVD 的业务与系统观察

每项 JSON 保存 before/after，计数按本次请求差值判断；不同阶段不累加成测试总数。
下表使用最终客户端的 NO_PROXY/default、显式 Network 和本机 proxy 模式。

| 场景 | 业务/界面观察 |
| --- | --- |
| 首次 VPN Cancel / OK | 拒绝提示 VPN permission required；同意后可运行 |
| VPN 正常代理 | SOCKS5 与 proxyTarget 各 +1，界面 VPN active |
| VPN 正常 DIRECT | directTarget +1，SOCKS5 不增加 |
| 显式 VPN DNS | `avd.service.test` → `10.0.2.2`，本地 DNS +1 |
| 代理端关闭/恢复 | 失败时收件不增；恢复后代理正常，无 DIRECT 回退 |
| bypass 开/关 | 开时显式物理请求绕过 SOCKS5；关且重启后请求失败 |
| 排除/恢复客户端 | 排除时收件 +1、SOCKS5 不增；恢复后经 SOCKS5 |
| 手动 Stop | 无 VPN、显示 Stopped；普通请求回到系统路径 |
| 系统 Disconnect | 无 VPN、Start、Service unavailable；明确 Start 后恢复 |
| 模拟 cellular 断开/恢复 | 断开超时且收件不增；恢复后代理正常 |
| VPN 关闭并重新启动 | Proxy only；显式代理经 SOCKS5，普通请求走系统路径 |
| 进程终止及重新打开 | VPN/代理入口关闭，重新打开保持 Start，无自动复活 |
| v2 提示中的 Restart | 新 bypass 设置实际生效，代理正常，页面 VPN active |

系统撤销与 Stop 后的普通直连是系统路径，未记为应用的 fail-closed 保证。
被排除客户端仍可能枚举 VPN Network；枚举结果本身不能证明该 UID 的默认流量经过 VPN。
排除后的显式 DNS 观察到缓存/fake IP，未新增上游收件，未计为独立 DNS 传输证明。
UI 的新状态已通过 widget 检查，并检查了 AVD 的 Proxy only 显示；截图仅保存在本地。

AVD 原始 JSON/XML、fixture 端口与清理结果位于 `build/verification/l2-t03/avd/`。
v2 新 APK 的 Restart 补验在 `implementation_v2/avd/`，包含设备安装 SHA；
更新后实际处理了 VPN 同意框，并清除镜像 Bluetooth crash 对话框后继续。
初轮 Java 默认 HTTP proxy 用例不用于 TUN 证明；最终 normal 明确使用 NO_PROXY。
初轮 SOCKS5 仅接受 IP，DNS 反查关联到合成域名后被夹具拒绝；夹具现接受该固定合成名，
最终代理拒绝/恢复与 DNS 后代理均复验通过，没有因此修改生产代码。

## 自动诊断的证据限制（Q1）

“未主动打开公共 URL”只描述显式 probe 操作，不能覆盖 Add gallery 触发的自动 Google 诊断。
此前报告的“没有公共测试站点”不能作为整个应用零公共诊断的结论。

实际触发链是 [ServiceStatusCard](../../../../lib/views/dashboard/widgets/service_status.dart)
在 gallery 中构建并 watch Google basic →
[ServiceStatus.probe](../../../../lib/providers/service_status.dart) →
[Request.withSession](../../../../lib/common/request.dart) →
[checkServices](../../../../lib/common/service_probe.dart)/Core RPC →
[Google checker](../../../../core/service_check.go)。公开目标为 Google 的 `generate_204`。
withSession 包含 begin/session.check 请求资格检查。
本轮保留的 gallery XML 显示 This request could not establish a response 与 Route unknown。

前者对应 `connect-failed` 的文案；后者由 `check.node` 为空派生。
[serviceErrorReason](../../../../core/service_transport.go) 会把多种错误归为 connect-failed，
下层 RoundTrip 可能在 dial 前被拒，也可能已尝试连接后失败。文案不能区分这两种情况；
它也不能证明 Dart 请求资格已在 transport 前拒绝。
缺少当次逐请求 transport/dial 审计，**是否实际外发未知，不能证明零外发**。
本轮不重现公共诊断，不扩大抓包或宿主权限；后续合成验证入场前避开 gallery、
Service status、Check exit IP 和远程 icon/provider，具体约束见 Guide。

## 检查、失败与构建偏差

下列选集有重叠，不相加声称独立总数。未全绿的选集保留真实结论。

| 检查 | 实际结果 |
| --- | --- |
| native 状态机，复用 v1 | 66 通过，0 失败/跳过 |
| service 配置与 route 地址，复用 v1 | 17 通过，0 失败/跳过 |
| v3 完整 UI/l10n/lint/bridge/action/SSID | 552 通过，4 个既有失败 |
| 格式整理后 I1/Q2 窄复验 | 12 通过，0 失败/跳过 |
| 较大受影响选集，v1 | 115 通过，6 个既有 manager 失败 |
| pub get / v3 analyze | 成功；0 error/warning，42 条既有 info |
| 代码生成/ARM64 包装 | 正常生成及 v3 包装成功；偏差见下文 |

6 个 manager 失败已在原基线复现。初轮全 UI 的一项失败来自正常 hook 生成的 Rust dylib
加载错误；使用 04 已核验、同源的 dylib 后该项通过，v3 完整选集沿用此运行依赖。
剩余 4 项为三个旧 update dialog
Request 资格失败和旧 `test/bootstrap_test.dart` 的 design library import 扫描失败，
原基线复查结论相同。本项未修改这些无关测试或生产行为。

正常包装首先因重复从 Git 激活 flutter_distributor 的 HTTPS 连接失败而中断。
已安装缓存 checkout 与固定 tag `v0.6.11-flclash.2` 的
`7fea25d4c531ce6e778db14e3c47f076027a1008` 相同；本地忽略副本仅跳过重复激活，
其余正常 setup/依赖/构建命令保留，仓库 `setup.dart` 未改。
`cached_tool.json`、失败日志和成功日志保留该偏差。没有上传或发布制品。

一次最终 bridge 复跑遗漏 compiler 环境变量，导致 fixture 提前退出和超时；
补齐既有编译器变量后 11 项通过。测试现在显式声明该运行依赖，未削弱断言。
初轮 Gradle 的 Rust PATH 和按钮测试夹具/文案宽度问题也保留诊断输出，不计为成功。

## 尚未证明与交付状态

- AVD Wi-Fi 已启用，但扫描不到 AP；真实 SSID 命中/离开、权限变化、
  headless SSID 自动观察未运行。受控暂停回归通过不能升级这些项。
- 物理 Wi-Fi/cellular 切换、IPv6 系统路由、Always-on VPN、系统回调送达前的瞬时行为，
  以及 protect 到指定物理网络的绑定均未证明。没有全设备 kill switch。
- 系统镜像自身后台行为与应用 fixture 分开；关闭镜像 GMS/Play/captive portal 不等于
  完成全镜像网络隔离。自动 Google 诊断是否外发未知，详见 Q1；未点击 Check exit IP。
- DoH、缓存、远端解析及材料支持上限沿[总体风险](l2_t02_plan.md#10-残留风险与不再承诺的能力)。
  L2-T02-05 尚未启动，不能由本项推导整项完成。
- 两轮自有 emulator、fixture、私有 ADB server 已停止。M 复核后已清理自建 AVD 登记、
  运行数据和私有 home；`cleanup_final.json` 记录最终清理，原两轮 cleanup_review 保留当时暂留事实。
  APK、冻结证据、最小夹具和复现入口保留；用户 AVD、宿主网络、共享 SDK/image 未操作。
  本机另存的 `premerge_v1/repro/create_avd.py` 使用独立新输出目录，避免覆盖冻结证据。

本地按现有约定提交、合入 `security/android` 与清理，D 不操作远端。
`build/verification/l2-t03/integration.json` 仅在实际目标 HEAD/Tree 核实后生成，
给出交付提交、父提交及与 v3 源码/制品的对应；后续 M 完成收尾、普通推送再交接 05。
