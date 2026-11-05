# Geo 数据身份与固定基线

固定随包基线及离线核验已交付。任务与后续更新保护的状态见[Loop 6 Tasks](loop6/loop6_tasks.md)。
本契约区分接受的数据发布、精确文件、磁盘选择和运行reader；操作入口见[指南](geo_data_guide.md)。

## 接受对象与证据

本次接受MetaCubeX/meta-rules-dat固定release commit `4046bac4e064f047210ed43cd187fa32df7bace7`的四份完整资产，
对应捕获的GitHub release `434715541`。精确资源身份、原名／随包名、asset ID、大小和SHA-256由
[manifest](../../../assets/data/geo_manifest.json)单一维护，不把rolling `latest`、URL或mtime当版本。
manifest是项目评审接受的参考，不是发布者签名；GitHub同发布渠道的digest与固定Git字节一致不构成独立签名证明，
不能排除发布者账号、构建来源或原始数据自身被攻陷。格式有效与分类准确也分别判断。

| 资源角色 | 原始发布资产 → 随包名 | 格式及消费者 |
| --- | --- | --- |
| MMDB | geoip.metadb → GEOIP.metadb | MMDB容器，Meta country记录；非geodata-mode的GEOIP／DNS分类 |
| GEOIP | geoip.dat → GEOIP.dat | protobuf GeoIP列表；geodata-mode的Core loader／matcher |
| GEOSITE | geosite.dat → GEOSITE.dat | protobuf GeoSite列表；域名规则及DNS geosite消费者 |
| ASN | GeoLite2-ASN.mmdb → ASN.mmdb | MMDB容器，ASN number／organization记录；IP-ASN及源IP-ASN |

格式验证使用既有Core reader／loader。MMDB能打开只说明容器可读，不能把country和ASN角色互换。
代表性样本及数量变化只说明观察到的分类，不能证明整个数据集正确；最终路由还取决于接受的规则及目标。
旧新检查使用独立进程，避免`ipOnce`、`asnOnce`及geodata缓存把旧版结果带入新版。

## 历史与生成关系

替换前四份资产与公开FlClash commit `ed7868282a94ba8bd66e31f719349ba12fb16e50`的blob ID对应，
也与T05交付APK中的文件逐字相同。原数据release、精确生成输入及本地加工关系未证明，历史结论为unknown。
新基线向前生效，不证明旧文件未被篡改。项目为浅克隆，不能把本地历史边界当资产首次引入时间。

观察到的[固定workflow](https://github.com/MetaCubeX/meta-rules-dat/blob/4178770badecb1b349fbcd62c737e0d7a2079729/.github/workflows/run.yml)
从Loyalsoldier取得GEOIP、以geo转换为metadb、合并域名来源生成GEOSITE，并从xishang0128镜像取得ASN。
部分输入及工具使用移动引用，且latest会重建、生成分支会强推；该配方不等于本次payload的已验证构建provenance。
原始输入commit、转换器版本、数据真实性未闭环的部分仍为unknown，不虚构可复现生成链。

## 核验参考与文件选择

[离线工具](../../../tool/verify_geo_assets.py)以获审仓库manifest为参考核仓库及显式指定APK；不能读取APK内的manifest后让它自证payload。
未知schema、重复／缺失角色、错误资源映射、大小或digest不符均失败。明确指定另一个repo时报告替代参考，不能默认称为正式基线。
工具不联网、不下载、不修改文件、不扫描用户目录，只检查明确给出的repo、APK或合成home。

`CoreController.initGeo`只seed不存在的文件，已有私有缓存不会因更新随包资产而自动替换。
Core路径解析可接受大小写变体及Country.mmdb／geoip.db等兼容名，按目录排序取首个匹配的非目录条目。
离线检查应列出兼容候选、真实选择规则下的路径、缺失／冲突及与参考的对应；不能凭文件名、磁盘hash或mtime声称reader已加载。
MMDB与GEOIP.dat是不同mode的候选，不因两者均存在而称二者都已启用。

维护新基线时保留固定发布对象和原始asset到随包名的映射，核完整字节、角色、统计／代表性变化及APK对应，再提交关联manifest和资产。
不能只更新本地hash后称来源已验证。Git将这些protobuf／MMDB显式视作二进制，避免文本转换改变获审字节。

## 共享影响与后续边界

四份Flutter资源由各平台共用，新基线也影响其它平台首次seed；不复制平台资产或新增开关。
本轮仅交付及验收Android APK；其它平台runtime／update保持原路径，不声称其构建、运行保护或消费已验证。

T01仅建立随包基线及离线核验。默认更新URL、手动／自动／Core内部下载、私有缓存迁移、失败保留和实际重载由T02设计实施，
English来源／磁盘／loaded版本可见及真实路由验收由T03补齐，不能将当前Resources的mtime视为版本。
现有格式锁与GrantCommit约束请求资格、互斥和提交，不向父层暴露Core updater的候选bytes，不能据此声称发布校验已覆盖内部路径。
Core／依赖源、gitlink和carrier不改；无法在父层充分覆盖时按实际消费者及缺口交M。
DNS R1及Core完整安装日志并发仍未解决，本契约不升级其结论。
