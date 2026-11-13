# 04 目标逐连接详情 Result

NA-T01-04 已交付 Host／IP → 逐连接列表和内联排查详情，默认限定当前 App，可明确切换全部应用范围。
不合并不同连接，不采集 URL／HTTP 请求，应用接管与规则修改仍在 05–07。
实施基线 `a0c1197`；当前有效行为见 [Design](network_activity_design.md)。

## 交付与受测对象

条目直接显示连接 ID、最后观测流量和冻结的规则／出口链，活动样式沿第二层共用。
上方目标地址信息来自已有连接元数据，没有搜索框或重复汇总卡片。
国家图标按用户修订表示代理服务器所在国家／最近有效 DIRECT 本机公网检测的国家，
不是目标网站所见出口。缺失、私网、域名、DIRECT 无既有检测或数据库不可用时留空。
离线批量 RPC 使用现有 MMDB，不触发下载、公网检测或连接建立热路径查询。
父 Go wrapper 和 Dart 协议新增 lookupIpCountries；mihomo gitlink 未修改，无新依赖或锁文件改动。

本地 `build/verification/na-t01-04/source-binding.json` 绑定源码、检查、安装摘要及提交。
最终 ARM64 debug APK SHA-256：
`982b10ddedf6b7355372a939dba3fe650a234e147cb0da1a5b7835949ee29ade`。
签名 SHA-256：`5a7c9cb8db640dfac17b75daba333e285ba76595e6e71b2d7d2d0e851f8849ec`。

## 验证结果

| 检查 | 实际结果 |
| --- | --- |
| 锁定依赖、intl_utils／build_runner | 成功，锁文件不变；本地化由生成器生成 |
| 静态分析 | 无错误／警告／新增 info，保留 42 项原有 info |
| 应用网络验收组合 | 101 项通过、2 项既有环境开关跳过，覆盖三层页面、汇总／观察生命周期、国家 provider、协议与本地化 |
| 本地预览 | 英语及中／日／俄窄屏大字体通过，国旗使用实际 emoji 字体渲染；预览是合成连接 |
| Native | CGO_ENABLED=0 go test . 和 go vet . 通过；新增国家及 RPC 测试单独复核通过 |
| 整套 widgets | 584 项通过、4 项原有失败，说明见下文 |
| UI lint／观察器定向组合 | 63 项通过，1 项既有导入规范失败，说明见下文 |
| 源码 carrier | --check 通过，未改 mihomo 源码载体 |
| Android 安装 | 最终构建无重建提示；签名有效，现有 emulator-5554 保留数据覆盖安装，已安装 APK 摘要与构建一致 |

覆盖：同 IP 多 ID 分开显示、跨 App 范围、顺序与更新、展开状态隔离、最后观测字节、停止／失败／清空／实例切换、
复制失败重试、返回保留搜索、数据库失败仍保留内容、非公网／目标 IP／节点名称误用反例。
国家查询覆盖独立只读数据库、缺失／坏库、128 项上限及多批次、三种记录结构和多国家歧义。
DIRECT 仅消费已有、时间与路由均有效的直接检测缓存，不对当前连接发起新出口查询。

4 项 widget 失败延续已有记录：3 项 update_dialog_test 的人工 release 结果被正式版本校验拦截；
1 项 uncovered_views_test 无法加载本机 macOS Rust dylib（LINKEDIT 未对齐）。
lint 的原有 test/bootstrap_test.dart 仍直接导入 flutter/material.dart；本项未修改相关文件。
未将这些失败记为全套通过，也未扩展本任务修复无关功能。

## 设备与能力边界

安装仅使用 adb -s emulator-5554 install --no-incremental -r，未清空数据、另建 AVD 或导出 Downloads 副本。
本轮没有操作用户真实订阅、Start／Stop、规则或来源接受，也没有产生外部国家查询。
页面状态和预览由受控连接覆盖，离线 GeoIP 使用实际随项目提供的数据库；
本轮未在设备上重新生成真实代理流量来实测每种代理协议的 remoteDestination 字段，不能据安装成功宣称该覆盖完成。
部分 UDP／代理协议可能只报告域名或缺失远端地址，此时不补查 DNS，图标留空。
GeoIP 结果仅是数据库对地址的归属；不承诺节点地理位置准确或站点实际看到同一出口。
