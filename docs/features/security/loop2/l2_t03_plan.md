# L2-T03 服务状态过渡与业务接管范围 Plan

任务入口：[Loop 2 Tasks](loop2_tasks.md#l2-t03-服务状态过渡与业务接管范围)。本项由 M1 评审、D-02 执行。
输入基线为 `security/android@ed0f34c2d5ee1f88c8bd121e510dab9a286a620a`。
design_v1 已通过，implementation_v3 的实际覆盖见[Result](l2_t03_result.md)。修复 SSID 暂停及故障意图收敛，
让现有页面从 native 事实区分运行意图、Core 配置和 VPN 接管；设备级结论须依本轮明确的专用 AVD 边界验证，不能推广到物理设备。
v2 首轮实现评审要求 I1 修订，v3 已补同意图普通观察不能吞掉暂停/恢复分派的回归；
Q1 限定诊断外发证据，Q2 补应用 SSID/provider/manager 入口覆盖，v3 已经 M1 复审通过。

## 问题与目标

[ServiceStateMachine](../../../../android/app/src/main/kotlin/com/follow/clash/ServiceStateMachine.kt)
已有请求代际、权限准备、配置分阶段接受、服务身份和撤销/丢失处理；
[ServiceController](../../../../android/app/src/main/kotlin/com/follow/clash/ServiceController.kt)
拥有 binding/run time，`VpnService` 已有 `onRevoke`/`onDestroy`
和 generation-owned TUN 清理。本项复用这些机制。
已确认的调用缺口是：

- `SetupAction.setPaused` 等待旧 `getRequestState` 后，把旧 `intentRunning` 作为新命令提交；
  等待期间的手动 Stop 可能被覆盖。
  `_dispatchRunRequest` 又只按 `running` 分支，暂停仍走 `_start`/inactive 配置安装，
  没有执行 native `requestStop`。
  inactive 安装不清理服务或将 native `stopping` 收敛为 `stopped`；不能据此声称已退出 TUN。
- native 的 revoke/binding-lost/service-lost 等分支将 arbiter 重置为 stopped，却保留发布的 `intentRunning=true`。
  这与普通 `fail()` 的意图清理不一致，会继续被 bootstrap/SSID 消费；实际业务门控仍有 phase 校验，尚未证明发生设备泄漏。
- Dashboard 的 `isStartProvider`/toggle 只看 run time。暂停清除计时后，保留的运行意图不再能从按钮表达/停止；
  只有 Core connection 或已安装配置也不足以解释 VPN 与 Proxy-only 接管范围。
- 实施末轮核实 `buildManagerStack` 实际安装 VpnManager；其 Restart 的 Stop→await→Start
  会将后半段变成新意图，覆盖等待期间的 Stop。改为单次运行请求，由既有 native 接受流程重建服务，
  补真实提示按钮的取消回归；此修订沿原状态权威和本项启停范围，不增加新调度者。

目标是暂停真正退出当前服务、手动 Stop 阻止后续恢复、故障不留下可被误消费的旧运行意图，
并让页面与已有 native/Core 接受事实一致。正常 DIRECT、被排除应用/网络及 Proxy-only 用途保留；
不新增全设备 kill switch，不改 mihomo/gitlink/carrier，不把 L2-T02 的其它协议/资产或 §10 风险记为解决。

## 方案与理由

1. **原子暂停与有效运行分派。** 在 `ServiceState` 的既有 publication/arbiter 边界增加暂停命令，
   仅更新 paused，并在同次操作中取当前运行意图、分配 revision，返回该请求快照。
   Dart 在 await 前登记该次调用归属，只有最新返回才能分派，避免旧响应覆盖本地较新操作。
   它用返回的 requestId 和有效 `intentRunning && !paused` 调用既有 start/stop，不再重写旧意图。
   暂停保留原运行意图、执行同请求的 native stop；离开排除网只恢复仍有意图的请求。
   若返回/清理期间有较新命令，仍由原请求身份检查拒绝旧工作。无新持久状态或调度权威。
2. **故障事实一致。** 只在原代码已经将当前 arbiter 重置为 stopped 的终止分支同步清除发布的运行意图；
   旧实例回调和主动 retiring 的服务仍仅清理其自身身份，不修改较新请求。撤销原因与后续销毁清理不相互冒充新用户意图。
   不增加隐式重试；后续明确 Start/既有获准 autoRun 继续沿正常权限和 ConfigInput 重新接受。
3. **观察与操作分工。** 保留 run time 的实际计时语义；在现有 request-state 层派生只读 UI 状态，
   CommonAction/StartButton 共享其 Start/Stop 目标，暂停时显示 Suspended 并允许 Stop，启动中也可取消。
   Profile detail 的 Android service 状态结合 native phase/service/protect identity
   与 ConfigFact.businessActive：
   区分 Applying、VPN active、Proxy only、Suspended、Stopped/Unavailable。未知或失败不显示 active。
   Core status 仍只表示 Core 连接；不新建可写 UI 状态机，不把 desired 设置当作已应用范围。
   设置经既有 ApplicationInput/配置接受流程生效，过渡显示 Applying；不能仅凭重启提示宣称生效。

只在 Dart 加判断仍有 read/await/write 竞态；自动重试或第二套运行状态反而会绕开既有代际和撤销。
因此采用一个 native 原子暂停入口及已有 stop/start 路径，不重建 service/TUN 管理器。

### 接管与物理网络边界

- VPN 模式由既有 Builder 的 routes、IPv4/IPv6 和 Access control 决定覆盖；
  `Allow apps to bypass VPN` 允许应用自行选其它网络，不能显示为全设备强制代理。
  分应用允许/排除列表沿现有实现，包含应用自身的维护请求另受 Request 资格约束。
- Exclude SSIDs 仅在 opt-in SSID 观察得到匹配时暂停；无权限/未知 SSID 不等于已确认排除。
  没有 Flutter SSID 观察的场景不能推导 headless 自动识别该网络。
- RequestNetworkSource 提供物理网络事实/DNS；NetworkObserveModule 订阅更新，
  Core 的 socket hook 使用 protect。
  protect 防止重新进入本 VPN，不证明绑定特定 Wi-Fi/cellular；不将其与维护请求的显式 Network.bindSocket 资格混同。
  复核变更/丢失/旧回调与 DNS 更新/清理，保留真实物理路径尚未验证的结论，不在本项暗改 DNS 选择策略。
- Android 的撤销回调到达时系统已取消 VPN 接口；应用清理自身资源不能保证回调之前瞬时阻断其它设备流量。
  平台语义依据：[Builder](https://developer.android.com/reference/android/net/VpnService.Builder)、
  [VpnService](https://developer.android.com/reference/android/net/VpnService)。

## 实施与验证

设计通过后先维护文档基线，再修改生产与测试，最后回填 Result。具体文档职责：

- 新增 `docs/features/security/android_service_design.md`：当前服务/接管契约、意图/配置/身份协作和上述范围；
  新增 `android_service_guide.md`：English UI 的 Start/Stop、Network、Access control、
  On demand 及故障观察/限制。
- 修改 `.agents/architecture.md` 的 Android lifecycle/观察职责并直达契约；
  校正当前材料能力仍写 pending review 的失效状态。
  修改 `android_network_inventory.md` 的接管/辅助请求边界与指南入口；`flclash_security_plan.md` 仅补导航，不复制状态权威。
- 维护本 Plan、`loop2_tasks.md`、`l2_t02_tasks.md` 及总体 `l2_t02_plan.md` 的受影响授权/依赖；
  实测后新增 `loop2/l2_t03_result.md`，绑定源码/制品与未运行项。04 冻结记录不改，05 尚未启动。

拟验证矩阵（不是已运行结果）：

- 真实 ServiceStateMachine/JVM：暂停 stop 完成/失败、保留意图与手动 Stop，暂停与 Start/Stop 的交错；
  revoke/loss 的意图/通知，旧实例不影响新服务。
- 真实 Flutter/MethodChannel/native bridge：用现有 ConfigApplyBridge 接入原子暂停；
  屏障覆盖旧读返回/较新 Stop；UI 暂停可 Stop、启动可取消、计时不伪造。
- native publication 与真实 Go/Core：测试专用 host 转发既有分阶段接受/control bridge；
  正常代理/DIRECT 与独立业务/DNS 收件，暂停/丢失后旧入口拒绝且不扩大 DIRECT，恢复走新接受。
- Builder 与网络消费者：验证既有 access/bypass/IPv4/IPv6 参数消费和 DNS 订阅/取消、旧网络回调；
  受控 OS host 不计作系统路由证据。
- Android 编译/制品：JDK 17 编译受影响模块、正常生成/analyze/窄测；
  按 Dart/native 影响重建 ARM64，核对源码/内嵌 Core 与 APK。
- 真实 Android 系统（专用 AVD）：VPN 同意/撤销、销毁/重启、分应用/bypass、网络变化的实际客户端与状态；
  AVD 结果不冒充物理手机切网。

原 pause 单测直接调用 `requestStop`，现有 ConfigApplyBridge 的 prepare 也未传 source/paused；
本项补实际 Dart 调用路径，不能只补已有理想路径断言。回归适用时保留旧失败/新通过；
复用 04 的未变严格编译/业务 DNS 证据，不重复整套矩阵。

M1 已确认本轮持续完成授权包含必要、可逆、仅本地合成的专用 AVD 验证。
使用新建 English AVD、全新合成数据、独立 serial/端口和记录的自有 PID，优先 headless；
可安装/启动本项 APK 与测试客户端、处理 VPN 同意/撤销及必要 guest 设置。
只连接 AVD/宿主本地合成端，不碰现有 AVD/物理设备、真实 DB/订阅/SSID、宿主 TUN/system proxy/防火墙或公共测试流量。
隔离、系统后台行为、清理边界和拓扑先维护在[指南](../android_service_guide.md)，再执行。
AVD 不证明物理 Wi-Fi/cellular；实际限制记入 Result，不能冒充已通过或静默转交 05。

实现交 M1 复审后按 pre-merge 本地提交合入 `security/android`、清理任务分支；
M 完成独立记录清理与普通推送后，才按已授权顺序接 L2-T02-05。
