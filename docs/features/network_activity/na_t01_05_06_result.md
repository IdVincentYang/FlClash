# 05／06 应用控制与默认分流 Result

05／06 已完成实现与设备验收。输入基线为 5a7704d，方案见
[应用分流 Plan](application_routing_plan.md)，当前实现见
[Design](network_activity_design.md#app-默认策略与-vpn-范围)。Host 例外仍属于 07。

## 可体验的闭环

- Tools → Application network：每个应用右侧名称选择策略，下方开关启用／暂停；关闭仍保留选择。
- 独立选择页提供 DIRECT、REJECT、共用应用代理组、已有组及节点；搜索与选中状态不影响 Proxies。
- 应用目标页菜单“纳入 VPN”修改已有 Access control；运行时由 ServiceState 重建，断开时只保存。
- Rule／Direct 采用启用的应用策略，Global 保留原 GLOBAL 行为并显示应用策略暂停。
- 目标失效标红并前排，组内没有可用节点不当作正常 REJECT；设置意图和实际采用分开表示。
- 自建组按稳定 ID 引用，普通订阅目标按订阅保存；切回原订阅恢复其选择，缺失目标不猜测同名替代。
- 共享 UID 从观测身份或安装目录取得完整候选，修改前确认共同影响范围；配置不一致时不假称已生效。

## 已证明的行为

在现有 emulator-5554／Pixel_7a_API_34 上使用两个不同 UID 的受控客户端，只访问本机回声和 SOCKS5 服务。
每个组合执行 TCP、已连接 UDP、未连接 UDP；客户端响应与宿主独立转发记录相互核对。

| 场景 | App A | App B | 结果 |
| --- | --- | --- | --- |
| Rule，分别指定组／DIRECT | 3 次走指定代理组 | 3 次直连 | 符合预期 |
| Direct，分别指定组／DIRECT | 3 次走指定代理组 | 3 次直连 | 符合预期 |
| Global，A 预设 REJECT、B 预设 DIRECT | 3 次走 GLOBAL | 3 次走 GLOBAL | 应用策略被忽略 |
| Rule，A 设 REJECT | 3 次拒绝 | 3 次直连 | 拒绝不影响另一 App |
| 关闭两应用策略，Direct | 3 次直连 | 3 次直连 | 恢复原模式路径 |
| VPN 仅包含 B | A 的 3 次连接可达本地服务且不进入 Core | B 的 3 次连接继续进入 Core 且身份正确 | 排除有效 |

共 30 次路由检查与 6 次范围检查，错误为 0。普通规则、Global、Direct 分支由最小 mihomo hook 的
TCP／UDP 测试覆盖；未知／其它用户／不一致共享身份不取得应用策略。内部请求不采用应用策略。
Go 还覆盖版本／订阅 fencing、目标缺失时 REJECT、checkpoint 与受管来源重放；受管规则图本身不被改写。

文件数据库关闭后重开、删除订阅后的绑定保留／清理、离线预设、采用失败及自建组自动绑定均有对应测试。
原 Proxies 选择页与节点卡片未修改，Dashboard outbound mode 控件未修改。

## 验证与交付

- Flutter 84 项相关专项通过；扩大检查通过 710 项、跳过 1 项，5 项既有失败未计为通过。
  失败分别为设计包 import lint、macOS Rust 编辑器脚本界面、3 项更新说明 fixture；本次未修改这些实现。
  静态检查无错误／警告，保留 42 项基线 info；代码生成及格式检查通过。
- Go 全套测试及 vet、mihomo hook 专项：通过。
- Android common／service 单元检查与触及模块编译通过。app 全套 189 项仍存在 Robolectric 跨 shadow 泄漏：
  当前运行失败于 ServicePluginRequestControlTest，原基线运行失败于 CrashReportsAndroidTest 的 shadow ClassCastException；
  相关 ConfigApplyStateMachineTest、ServiceStateMachineTest、ServicePluginRequestControlTest 分别运行均通过。全套 app 检查未计为通过。
- AVD 页面核对列表、独立选择、搜索和返回；Chrome 的 DIRECT 预设与启用在进程重启后保留。
  断开时保存应用策略和 VPN 范围均成功，服务检查确认没有自动启动 VPN。共享身份完整确认有独立 widget 覆盖。
  选择订阅目标在事务中核对选择页的订阅 ID；无关分组错误不阻塞 DIRECT／REJECT 保存。
- 调试包 0.8.99／2026100311，保留数据覆盖安装；无 Downloads 导出、无新 AVD。
  36 次设备连接检查运行于 2026100310；最终包的 Native 库与其逐字节一致，后续 Dart 保存时序修正专项通过。
  最终安装包与构建包摘要一致，原有数据已恢复、测试客户端已移除，VPN 保持断开。

本地 `build/verification/na-t01-05-06/source-binding.json` 绑定源码摘要、Core gitlink、APK 与打包内容；
设备 report、恢复摘要及截图保存在相同目录，未上传。源码 carrier 按公开 base 完整重建检查，未发布 Core 仓库。
本次自行复核了持久化、Request／Setup、Native hook 和独立选择页的职责边界，未发现需先调整的结构问题。

## 偏差与边界

设备夹具先后修正了命令文件半写入、Android tar 格式兼容及 Core 端口字符串归一问题，已重跑；
仅以最终受控报告为通过依据。
原有 673 个数据文件恢复后逐一核对，摘要无差异。最终重跑与页面检查结束后再次恢复原设置并断开 VPN。

应用目录权限不足、无法识别的系统 socket、节点连通性与系统 lockdown 仍受原平台限制；强调色表示配置已采用，
不表示所有已有连接已重连或远端服务可达。规则保存持久化，连接历史仍只保留在原有有界内存中。
本次不包含 Host 例外、完整 HTTPS URL、跨订阅节点池或真机耗电验证。
