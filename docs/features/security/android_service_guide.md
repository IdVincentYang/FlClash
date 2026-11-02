# Android 服务状态与接管范围指南

本指南对应[服务契约](android_service_design.md)。
JVM/Core、专用 AVD 与物理设备证据分别判断；范围和限制见下文，
受测对象及详细结果可从[Loop 2 记录的历史入口](loop2/loop2_tasks.md#l2-t03-服务状态过渡与业务接管范围)取回。

## English UI

1. Dashboard 使用 Start/Stop；准备启动时可以 Stop 取消。
2. Tools → Advanced configuration → Network 配置 VPN、IPv6 和 Allow apps to bypass VPN。
   运行中修改后，按提示 Restart，或 Stop 后重新 Start，才采用新的 VPN Builder 设置。
   VPN 关闭时仅有代理服务，不代表其它应用自动经过代理。
3. Tools → Access control 决定哪些应用进入 VPN；被排除应用不受该 VPN 的分流保证。
4. Tools → General → On demand → Exclude SSIDs 仅在已授权且可观察的 SSID 匹配时暂停。
   Suspended 表示意图保留且当前服务已经停止；可以 Stop 取消离网后的恢复。
5. Profile detail 的 Android service 状态区分 Applying、Stopping、Suspended、Stopped、
   VPN active、Proxy only、Service unavailable。Stopping 尚未确认清理；
   Service unavailable 也不等于 VPN 仍接管。
   Core connected 与 Configuration loaded 分别说明连接和配置，不能代替 VPN active。

故障后先查看实际状态；明确 Start 仍走 VPN 权限/配置接受。Android 系统撤销 VPN 后，
未被应用接管的流量由系统及其它应用处理；本功能不是全设备断网开关。

## 专用 AVD 的本地验证边界

本轮获准在新建、专用、全新合成数据的 English AVD 内验证，不操作用户已有 AVD/物理设备。
复用已安装的官方 system image/工具。AVD 名、serial、端口和进程 PID 单独记录；
AVD 数据和证据均位于本地忽略目录 `build/verification/l2-t03/`。
优先 headless，使用独立 ADB server 端口，不重启全局 ADB，不关闭他人进程。

拓扑是测试客户端 → 专用 AVD 的 VPN/Core → AVD/宿主本地合成 SOCKS5、DNS 和业务收件端。
所有名称、节点、认证、配置和客户端均为合成值；端点限制在 guest/host 本地，不访问公共测试站点。
安装/启动本项 APK 与测试客户端、VPN 同意/撤销、服务重启和必要 guest 设置切换在本次范围。
不使用真实 DB/备份/订阅/ouo/SSID，不改宿主 TUN/system proxy/防火墙或系统网络。
关闭本应用的可选诊断、远程图标及自动外部维护；系统镜像自身后台行为与本项测试请求分开记录，
不把系统后台行为当作已隔离或本应用发起的流量。

AVD 已观察正常代理/DIRECT、代理失败与恢复、Stop、系统撤销、进程终止、分应用、
bypass、Proxy only 和模拟 cellular 断开/恢复。
该镜像扫描不到 Wi-Fi AP，真实 SSID 暂停/恢复尚未运行；受控暂停回归不能代替该系统证据。
隔离条件无法成立时停止相应设备步骤，记录具体缺口，其它本地工作继续；不将 AVD 写成物理手机切网证明。
结束后只停止自有进程/端口、清理自己新建的数据，保留必要证据；共享 checkout/用户设备不动。

## 本地复现

以下命令在仓库根目录运行。需要已安装的 Android SDK、JDK 17、Python 3，
以及单独创建的专用 English AVD。serial/ADB port 必须替换为自己的实例；先核对 AVD 名。
不要将命令指向用户日常使用的设备。

```bash
python3 android/tests/device/local_fixture.py
python3 android/tests/device/build_probe.py
adb -P 5041 -s emulator-5580 emu avd name
adb -P 5041 -s emulator-5580 install -r \
  build/verification/l2-t03/avd/client/local-probe.apk
```

fixture 仅绑定 `127.0.0.1`，输出各端口；guest 使用 `10.0.2.2` 访问宿主。
从其 HTTP port 的 `/profile` 导入合成 Profile，并选中。
它使用固定本地 SOCKS5、TCP DNS 和业务端，非本地规则默认 REJECT；没有真实订阅或秘密。
需要复用既有端口时可传 `--http-port`、`--socks-port`、`--dns-port`、
`--proxy-target-port` 和 `--direct-target-port`，端口必须属于自己的 fixture。

Start 后按实际系统对话框同意 VPN。下面将端口替换为输出的 proxyTargetPort：

```bash
adb -P 5041 -s emulator-5580 shell am start \
  -n com.follow.clash.testclient/.ProbeActivity \
  --es mode normal --es case vpn-proxy \
  --es url http://10.0.2.2:52695/probe
adb -P 5041 -s emulator-5580 shell run-as \
  com.follow.clash.testclient cat files/result.json
```

每次使用独立 case，并等到同名结果落盘；比较宿主 `/status` 的前后计数。
normal 显式禁用 Java HTTP proxy，观察 TUN/default 路径；bypass 使用显式非 VPN Network；
proxy 只连接 guest 的 `127.0.0.1:7890`，用于 Proxy only；dns 只查询显式 VPN Network
上的 `avd.service.test`，没有 VPN 时直接失败，不回退系统 DNS。
客户端 HTTP 目标固定为 `10.0.2.2`，禁止跳转；fixture 从不转发到外部。

- 正常代理：proxyConnections 与 proxyTarget 各增加；DIRECT 端只增加 directTarget。
- 宿主访问 `/proxy/off` 后，代理请求失败且业务收件不增加；`/proxy/on` 后恢复。
- 在 Network 设置中切换 bypass、在 Access control 排除/恢复测试客户端后，
  保存并 Stop/Start，再比较收件；desired 设置本身不是已生效证据。
- 系统 Settings → VPN → FlClash → Disconnect 后，查看 Start 和 Service unavailable；
  普通流量已回到系统路径。明确 Start 后再核对恢复。
- Proxy only 下，显式 proxy 请求仍经 Core，普通请求不会自动经过它。

Profile detail 从 Dashboard 的 Profiles 卡片打开。普通使用可经 Edit → Add → Profiles → Save 添加。
本地合成验证入场前必须避开 Add gallery、Service status 和远程图标入口，
保持 automatic outbound IP 关闭，不点击 Check exit IP；配置中不放远程 icon/provider。
Add gallery 会实例化其它卡片并可能触发公共诊断；本地 REJECT 规则或失败文案不能证明零外发。
本项一次图库预览的历史诊断是否实际外发未知；缺少当次逐请求审计，未将其计为网络隔离证明。
若专用测试布局尚无 Profiles 卡片，跳过 detail 的设备观察并记录限制，
不要为读取状态临时打开 gallery。系统镜像后台行为不在 fixture 计数范围。
