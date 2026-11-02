# Android 服务与业务接管契约

本契约规定运行意图、配置接受、服务/TUN 身份和界面之间的关系。
以下说明当前实现契约；实际覆盖与未验证边界见[服务指南](android_service_guide.md)，
验收定稿的历史入口由[Loop 2 任务记录](loop2/loop2_tasks.md#l2-t03-服务状态过渡与业务接管范围)维护。
既有配置/业务接受规则沿 [ConfigInput 设计](loop2/l2_t01_plan.md)，
受管材料沿[材料契约](managed_updates_design.md)。

## 权威与请求

ServiceState 的 arbiter/publication 拥有最新运行意图；ServiceController 拥有 binding/run time，
VpnService/ProxyService 拥有服务资源，ConfigInput/T01 拥有配置接受与业务入口资格。
Flutter 发出命令、观察事实，不以计时或成功分配 requestId 推导服务已经启动/停止。

`preparePauseIntent(paused)` 在同一 native publication 内读取当前运行意图、更新 paused，
分配 intentRevision，返回该次实际发布快照。退出或 publication 失败不返回可分派的成功请求；
失败回退同步清理 intentRunning，保留 failed 事实并封闭既有请求门。
Dart 在 await 前登记操作归属，旧响应不得替换较新命令，实际 native 操作仍检查请求身份。
运行请求资格按 processEpoch、intentRevision、intentRunning/paused 和终止事实判断。
同一意图的 network 等普通观察可以推进 publication revision，不能因此吞掉 stop/start 分派。
运行计时等需要精确观察快照的校验仍保留各自用途，不全局放松为意图比较。
有效运行是 intentRunning 且未 paused；暂停保留意图但通过同请求的 stop 清理服务，
离开排除网络只恢复仍有意图的请求。手动 Stop 清除意图，旧 SSID 结果不能恢复它。

故障仅在原 arbiter 已终止的分支同步清理发布意图；健康 retained 配置失败不清除运行意图。
旧实例、主动 retiring 与旧请求回调只处理自己拥有的资源，不能终止较新请求。
stop 清理失败发布 failed，保留未确认释放的所有权；不能发布 Stopped/Suspended 或恢复旧运行计时。

VPN 设置提示的 Restart 提交一次新的运行请求；配置接受按当前 service identity 和
options fingerprint 清理/重建资源。UI 不串联独立的 Stop 与 Start，避免等待中的新 Stop
被旧 Restart 的后半段覆盖。

## 界面依据

控制目标与实际运行分别派生；isStart/run time 保持实际计时含义。
CommonAction/StartButton 使用同一个只读控制事实：有有效运行意图时下一步是 Stop，暂停也能停止；
失败/未知不伪造运行，启动中可以取消。Core status 仅表示 Core 连接。

| 显示 | 必需事实 |
| --- | --- |
| Applying | native 正准备/启动，或配置正在接受 |
| Stopping | 意图已暂停/停止，但服务清理尚未确认 |
| Suspended | paused 且保留意图，native stopped，服务/保护身份已清空 |
| Stopped | native stopped、无服务/保护身份，且没有保留运行意图 |
| VPN active | native started、有当前服务和 ready 保护身份，Core 业务 active |
| Proxy only | native started、有服务但无 VPN 保护，Core 业务 active |
| Service unavailable | failed、清理失败、身份不一致或其它未知事实 |

以上不把 desired VPN/access/bypass 设置当作已应用范围；设置沿现有 ApplicationInput/接受流程生效，
过渡显示 Applying。真实接管范围还受下面的系统规则限制。

## 接管范围与失败边界

- VPN Builder 的 routes、IPv4/IPv6、Access control 确定流量范围；允许 DIRECT 是有效策略。
  Allow apps to bypass VPN 允许应用自行选其它网络，排除应用按系统路径联网。
- Exclude SSIDs 只在 opt-in 观察取得匹配时暂停。无权限/未知 SSID 不等于已确认排除，
  无 Flutter SSID 观察时也不保证 headless 自动识别网络。
  入口为 ConnectivityManager → currentSSID → suspendProvider → AppStateManager → setPaused；
  可控 SSID 读口只证明此应用调用链，不证明设备权限或实际 Wi-Fi 识别。
- RequestNetworkSource 提供物理网络事实/DNS，NetworkObserveModule 订阅更新并在停止时取消。
  protect 防止 Core 出站重新进入本 VPN，不等于将 socket 绑定到某特定物理网络；
  应用维护请求的 Network.bindSocket/Request 资格是另一条已有限制。
- onRevoke 回调到达时 Android 已取消 VPN 接口；应用终止自身资源并撤销资格，
  不保证系统回调之前瞬时阻断所有设备连接。没有全设备 kill switch 承诺。
- 本地 host、JVM 和真实 Core 收件不证明 Android 路由；AVD 也不证明物理 Wi-Fi/cellular 切换。
  未支持材料、DoH、缓存/远端解析等限制沿[总体风险](loop2/l2_t02_plan.md#10-残留风险与不再承诺的能力)。

平台依据：[VpnService](https://developer.android.com/reference/android/net/VpnService)、
[Builder](https://developer.android.com/reference/android/net/VpnService.Builder)。
English 操作与专用 AVD 验证边界见[指南](android_service_guide.md)。
