# FlClash Android 安全审计基线

本记录整理 2026-10-12 静态审查的 Android 发现，供各 loop 引用。主仓库基线为 `4b59eca853778d4e7be3de26589252889c899bc5`，Clash.Meta 为 `8597778c7df410ebe88c57e59eaab32d203156df`。表中的发现尚未整改；构建成功不能代替运行时安全验证。

| 编号 | 发现 | 已确认边界与待核实部分 |
| --- | --- | --- |
| A-01 | 默认仪表盘触发第三方 IP 查询，普通 Dio 请求不等于应用代理路径，含明文 HTTP；隐藏 IP 只影响显示 | 源码路径已确认；实际出口需运行验证 |
| A-02 | Android 集成 Firebase Analytics，CI 注入的正式发布 Firebase 项目不能从公开仓库核验 | 依赖与披露已确认；发布包外发待核实 |
| A-03 | 更新和订阅自动刷新产生外部请求，订阅 URL 可能含令牌 | 静态路径已确认；核心停止时出口和日志脱敏待核实 |
| A-04 | 导入配置决定路由、DNS、节点和 DIRECT 选择 | 不可信配置可改变网络信任与流量去向 |
| A-05 | Go 1.26.4、x/net 0.35.0 命中 HTTP/2 公告，核心包含相关调用 | 版本与调用线索已确认；Android 可达性及配置影响待验证 |
| A-06 | Rust 锁定依赖版本命中 OSV 公告 | 需结合 Android 目标、feature、符号和调用路径判断 |
| A-07 | GEOIP、GEOSITE、ASN 与审查日官方 rolling latest 不同，客户端缺少发布者签名或固定摘要校验 | 新旧不同已确认，篡改未证实；旧文件历史来源未闭环 |
| A-08 | Gradle Wrapper 无发行包 SHA-256，缺 Gradle 依赖验证元数据，CI actions 使用可移动标签 | 构建配置已确认；需建立来源和完整性约束 |
| A-09 | Flutter Engine、NDK、Gradle 插件及 Maven AAR/JAR 属于源码外的预编译平台依赖 | 工具与库的官方版本、实际工件完整性及发布物对应关系需核实 |
| A-10 | Android loopback 代理默认无认证，同设备其它应用可能访问 | 架构行为已确认；影响取决于应用、权限和运行模式 |
| A-11 | QuickActionActivity 与 MainActivity 接受外部 action/URI | 导出声明已确认；输入校验与实际可利用影响待核实 |
| A-12 | 源 manifest 没有显式 backup/data extraction 策略，应用保存订阅与代理凭据 | 合并后的 release manifest、备份范围与凭据保护待核实 |
| A-13 | 默认 DNS 使用第三方服务，其能看到收到的查询 | 默认配置已确认；系统 DNS/TUN/DoH 的实际 Android 路径待验证 |

主要源码入口：[请求路径](../../../lib/common/request.dart)、[IP 查询](../../../lib/common/ip_quality.dart)、[配置与 DNS](../../../lib/models/clash_config.dart)、[Android 应用配置](../../../android/app/build.gradle.kts)、[Gradle 配置](../../../android/settings.gradle.kts)、[发布工作流](../../../.github/workflows/build.yaml)。

漏洞基线参考：[GO-2026-6603](https://pkg.go.dev/vuln/GO-2026-6603)、[GO-2026-4918](https://pkg.go.dev/vuln/GO-2026-4918)。这些是审查时的版本匹配线索，不是已证实的远程利用结论；Loop 4 开始时需重新核实公告。

完整依赖归档、原始漏洞查询和官方资产比对证据保留在仓库外的本地审计材料中，未提交到 Git。此表是可共享的发现索引，不声称逐行审查了全部三方源码或验证了官方发布 APK。

代理、DNS、订阅服务仍可看到各自需要处理的网络元数据。整改目标是减少未告知的数据暴露并建立可验证的来源关系，不能承诺匿名上网或对抗被攻陷的操作系统。
