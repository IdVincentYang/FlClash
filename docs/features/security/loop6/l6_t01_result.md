# L6-T01 Geo固定基线验证记录

已建立获审的四份随包基线、离线工具及真实Core reader检查，并构建核验Android ARM64 APK；**M实现评审通过，待本地交付及M收尾**。
方案及输入Git基线见[Plan](l6_t01_plan.md)，当前契约见[设计](../geo_data_design.md)，使用步骤见[指南](../geo_data_guide.md)。
本项不启动应用或AVD，不证明运行中reader版本，也不等于Loop6更新保护完成。

## 数据身份与处置

精确参考由[manifest](../../../../assets/data/geo_manifest.json)维护：MetaCubeX固定release commit
`4046bac4e064f047210ed43cd187fa32df7bace7`的四份完整payload，与捕获release `434715541`的指定asset metadata SHA-256一致。
仅按原名→随包名复制，无筛选、重新生成或格式转换；仓库与最终APK四份字节相同，APK附带manifest也与外部参考相同。
工具以仓库参考判APK，攻击者同时替换APK payload及内嵌manifest不能自证通过。

替换前四份文件的公开FlClash历史blob对应成立；原数据release及精确生成输入仍为unknown。
固定workflow只能解释观察到的源与转换关系，未证明本次构建provenance。此次向前接受不证明旧文件未篡改，
同发布渠道的digest也不等于独立签名或发布者自身安全保证。

## 真实reader与分类变化

新旧分别在独立子进程中读取自己的完整资产，隔离MMDB／ASN once及geodata缓存。
使用Core `IPInstance`／`ASNInstance`、standard与默认memconservative loader及原router matcher；不调用可能触发公共下载的Init入口。
MMDB角色为Meta-geoip0，ASN角色为GeoLite2-ASN；容器可以打开但角色互换仍被拒绝。

| 观察 | 旧随包文件 | 新固定基线 |
| --- | --- | --- |
| GEOIP类别／CIDR总数 | 260／1,273,140 | 260／1,056,580 |
| GEOIP cn／us／private CIDR数 | 19,175／496,650／18 | 9,647／259,483／28 |
| GEOSITE集合／条目总数 | 1,417／229,729 | 1,565／223,323 |
| GEOSITE cn／google条目数 | 117,507／1,095 | 110,177／1,080 |
| MMDB内标build epoch（UTC） | 2025-09-05 22:37:23 | 2026-11-05 02:38:43 |
| ASN内标build epoch（UTC） | 2025-09-03 08:15:47 | 2026-10-28 15:07:47 |

内标日期不是发布身份。记录数明显变化，不能据几个样本相同声称规则覆盖或行为全部不变。
独立预期样本在新旧均通过：8.8.8.8为us／AS15169，114.114.114.114为cn，1.1.1.1为AS13335，
127.0.0.1命中private，baidu.com命中cn、google.com命中google，保留负域名与cn负IP反例。
ASN organization由GOOGLE／CLOUDFLARENET变为Google LLC／Cloudflare, Inc.；样本ASN号未变。
这些IP／域名只用于本地数据查询，没有网络解析或业务访问，不证明全集准确或最终出口。

## 验证与计数

| 选集／消费者 | 实际结果与边界 |
| --- | --- |
| Python离线工具测试 | 13 PASS；含自洽伪造APK、错误payload、未知schema／字段、重复JSON／角色、错误映射、缺失／截断／同长度坏digest／symlink、显式替代参考及兼容名冲突 |
| 真实Core新旧reader | 两次隔离运行均PASS；每次是一个Go测试，内部四角色／两种loader不额外计数；缺文件、坏protobuf、截断MMDB、角色互换反例无公共下载 |
| Go全套及vet | `CGO_ENABLED=0 go test .`最终复跑PASS 20.270s，`go vet .` PASS；没有宣称完整race通过 |
| Flutter CoreController／GeoResourceAction | 33 PASS；保留现有Geo操作消费者，不证明新运行校验已接入 |
| 分析／依赖 | flutter pub get通过，无依赖变更；analyze无error／warning，42项原有info |
| 仓库／APK工具 | 实际CLI退出0，四payload与外部参考匹配；不是安装／运行验收 |
| 显式合成home | 匹配文件退出0；加入旧Country.mmdb后按Core排序优先选择该路径、报告冲突／不匹配并退出1；均标not_observed而不称已加载 |

首次候选Go检查因执行工作目录错误而缺文件，未取得reader结论；修正后新旧检查通过，失败log保留。
GEOSITE首次公开下载截断，部分字节未写入／提升，固定URL重试后完整digest相符；原失败及重试记录分别保留。
Git将GEOSITE protobuf误判成文本而报空白问题，未删改数据；`.gitattributes`明确二进制后文本差异检查通过。
Go全套一次复跑18.700s失败于TestConfigTCPHalfCloseAndRevocation的loopback UDP端口占用；其未改动的freeConfigPort只探测TCP端口后释放，
该例使用MATCH,DIRECT且不读Geo。保留失败log，未修改端口测试或声称争用已修；该例独立连续3次通过后，全套最终复跑通过。

## Android制品与复核

正常arm64 dev构建通过，APK SHA-256为`469ab5c2273552829a2e5eb1c2ffda293d10ea0dc4ac24d7b7f23878d213e9e2`，55,171,823 bytes。
构建前绑定1,577个版本库文件输入（保守含测试及host工具，不含文档／agent说明）；之后`.gitattributes`变为Geo二进制属性，
离线host工具另补严格boolean及Unicode兼容名反例，Core测试补实际Unicode路径选择；13项、最终新旧reader和工具对实际APK重核通过。
这些工具／测试不参与APK编译／打包，实际资产与运行代码未改变，未将四份非runtime输入差异冒充输入全同。工具链／依赖缓存及Core固定gitlink另沿既有构建记录，不称复制了全部外部SDK输入。
与T05相比DEX及其它native相同，libapp.so及libclash.so不同；Go build info的VCS revision／time随输入基线更新，
Core／父包装层生产Go源及依赖未修改，保留两份build info供核对，不用hash不同推导实现变更或篡改。

本地证据根为`build/verification/l6-t01/`：公开捕获与固定payload在`public/`，原文件在`historical-assets/`，
新旧观察为`current-reader-final-02.json`／`historical-reader-final-02.json`，制品及绑定在`apk-binding/`，
完整实现交评入口为`implementation_v1/README.md`。CLI可按指南复核该APK，原始日志不入库。

共享Flutter资产也影响其它平台首次seed；本项不验证它们的构建或runtime/update路径。
已有私有缓存不自动替换，全部入口可信更新、磁盘失败保留及实际重载由T02处理，loaded版本／真实路由证明由T03处理。
Core内部updater候选bytes未向父层暴露的接入缺口保留，不以已有格式锁／receipt代替发布验证；DNS R1及Core日志race仍未解决。
