# L6-T01 Geo数据溯源与可信基线 Plan

任务入口：[Loop 6 Tasks](loop6_tasks.md)。M1已通过design_v1及完整实现评审；受影响验证已完成，待本地交付及M收尾。
输入为父仓库`9289ebcea38b7787dcbfba585dcdce2a6923ac5f`、Core `6c6e3e472bb246cc55f2e8577d9eddccc2623afc`。

## 问题与目标

用户在English Resources看到的是文件大小、mtime及Sync／Edit URL，无法据此判断发布身份或实际加载版本。
`CoreController.initGeo`仅在文件不存在时seed，Core路径解析还接受兼容文件名；更新器目前验证格式和请求资格，未绑定获接受的发布。
首项建立可独立交付的随包可信基线及离线核验，运行中缓存迁移／更新保护与界面增强分别留T02／T03。
M明确复用各平台共同的四份固定基线，不复制平台资产；共享seed数据影响其它平台，但只做Android制品交付／验收。

| 随包文件 | 实际提供方及消费者 | 已核实边界 |
| --- | --- | --- |
| GEOIP.metadb | MMDB容器；Core `MMDB()` → `IPInstance`，用于非geodata-mode的GEOIP及相关DNS分类 | 还可能选Country.mmdb／geoip.db；名称不证明格式或发布者 |
| GEOIP.dat | protobuf；geodata-mode的GEOIP loader／matcher | 与metadb是两条加载分支，不能只验其中一个 |
| GEOSITE.dat | protobuf；GEOSITE matcher及DNS geosite消费者 | 分类内容与最终路由目标分开判断 |
| ASN.mmdb | MMDB容器；`ASNInstance`及IP-ASN／源IP-ASN消费者 | 发布资产名可为GeoLite2-ASN.mmdb，须记录精确重命名 |

四份仓库文件与现存APK `a111899689b0c984bf68f3e1a55d7ee75aff6f115234022f66fbb81e3dd3a1fb`的四个Flutter资产逐字相同。
公开FlClash commit `ed7868282a94ba8bd66e31f719349ba12fb16e50`的blob ID也与仓库相同；这证明项目分发对应，尚不证明原数据发布版本或历史未篡改。
本地为浅克隆；MetaCubeX当前release分支的历史截止查询为空，不能把查询不到解释为从未发布。

## 方案与理由

保持原文件名与Core parser，提出接受MetaCubeX/meta-rules-dat为此次分发发布者，并以固定release commit
`4046bac4e064f047210ed43cd187fa32df7bace7`的四份完整资产建立新基线，而不继续用rolling latest作身份。
已下载至忽略目录，四份payload SHA-256均与2026-11-05该次release的具体asset metadata一致；GEOSITE首次读取截断，未保存／提升部分payload，重试成功单独记录。
这两处仍属于同一发布渠道，校验结果不等于独立签名，也不防发布者账户／构建来源本身被攻陷。

正式manifest按资源记录发布者、固定commit／asset ID、原名／随包名、格式、字节数、接受的digest、来源依据及历史结论。
APK核验以获审仓库manifest为参考，不能让APK自带manifest自证payload；替代repo参考必须显式标识。
hash是批准基线的精确约束，不因自行计算就建立发布身份。离线工具只读验证仓库资产、指定APK及显式提供的合成home；
按实际Core路径选择规则列出候选／所选磁盘文件，不凭同名或mtime声称已加载。不扫描用户目录，不自行下载或更新。
格式及代表性分类用现有Core reader／loader核验，不新写matcher；MMDB容器可打开还须核country／ASN语义角色。
旧新以隔离进程避免单例／loader缓存串版，记录类别／记录数和必要差异，不能把样本正确泛化成数据全集准确。

历史文件继续调查可定位的同版本候选；无对应发布证据则保留unknown，不以新基线替历史背书。
[固定workflow](https://github.com/MetaCubeX/meta-rules-dat/blob/4178770badecb1b349fbcd62c737e0d7a2079729/.github/workflows/run.yml)
显示GEOIP来自Loyalsoldier/geoip、metadb由geo转换、GEOSITE合并多个域名源、ASN取自xishang0128/geoip；
部分输入及工具引用可移动分支，且latest被重建、release分支强推。该配方只能说明已观察到的生成方式，不能当成四份payload的已验证构建provenance；
精确输入commit、转换器版本及源数据真实性未闭环的部分明确保留。
相比仅登记旧hash或每次追latest，这个方案提供可提交的固定对象，并诚实区分项目历史、接受的新发布及未知原始生成关系。

## 实施与验证

设计通过后先建立下表文档基线，再制作manifest／工具和替换四份候选资产；生产更新与默认URL不在本项修改。

| 路径 | 内容职责及顺序 |
| --- | --- |
| `docs/features/security/geo_data_design.md`（新增） | 先定义身份等级、文件选择／加载区别、固定基线维护及后续运行期边界；未实施部分标draft |
| `docs/features/security/geo_data_guide.md`（新增） | 先写离线命令及现有English Resources入口的真实限制；不预告未接入的版本UI |
| `assets/data/geo_manifest.json`、`tool/verify_geo_assets.py`（拟新增） | 获审的精确payload基线与离线校验消费者；manifest不复制整份调查日志 |
| `.gitattributes` | Geo protobuf／MMDB显式按二进制维护，保留固定payload字节，不作文本空白修复 |
| `.agents/architecture.md`、`flclash_security_plan.md`、本阶段Plan／Tasks | 仅同步实际受影响的职责及导航；不回写T05历史 |
| `l6_t01_result.md`（验证后新增） | 受测源码／资产／APK、比对与分类结果、失败及unknown证据；本次调查原件留忽略目录 |

正例核四份完整资产与固定发布、仓库及按影响ARM64 APK的对应，使用真实Core reader检查两种GEOIP分支、GEOSITE和ASN。
反例独立改一字节、截断、错资源／格式、缺文件、manifest未知版本或映射冲突必须失败；多兼容文件须报告真实选择，不能只核预期名。
分类变化以固定代表性域名／IP的旧新观察和独立预期列出，不发公共业务流量，也不改变规则以凑通过。
本项不启动应用或设备验收；“运行reader实际用了哪一版”的证明由T02／T03沿真实消费者补齐，不能由离线目录扫描代替。
无基线／旧缓存／自动更新尚未保护的窗口明确留在阶段状态；不因此称Loop6完成。若固定候选格式或分类反例不成立，停止提升该候选，保留原资产并向M交具体差异。

本项实施及受影响自验已完成，M实现评审通过，待本地交付及M收尾；版本、统计变化、失败和制品绑定见[Result](l6_t01_result.md)。
