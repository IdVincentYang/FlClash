# L1-T08 IP 查询与 Disclaimer 整改 Result

IP 整改已完成实现、自验及 ARM64 构建，implementation_v2 已通过 M1 实现评审。
本次 IP 增量已本地合入 `security/android`；实际提交、源码等价性与清理记录由
`build/verification/l1-t08/ip_delivery_v1/binding.json` 绑定，M1 另行完成 Details 核实和任务文档收尾。
本次范围及输入基线见 [Task Plan](l1_t08_plan.md)，有效契约见 [IP 查询设计](../ip_lookup_design.md)。
受测对象是 `security/l1-t08-ip-disclosure` 的工作树快照，由
`build/verification/l1-t08/ip_implementation_v2/binding.json` 绑定源码、验证和最终 APK；原始材料留在本地忽略目录。

## 实际能力与消费者

正常仪表盘默认不查询公网 IP；手动刷新访问单一 Cloudflare HTTPS trace，旧配置不会自动开启新用途。
卡片设置可明确启用前台仪表盘自动刷新。公网回答仅显示本次端点的观测，不写入节点通用 IP 别名。
点击 IP 打开详情仍不查询；显式分类按钮才向单一 Proxycheck v3 发送该 IP，展示来源、时间、类型和独立标记。
未知字段保持 unknown，Wireless 不冒充 Mobile，compromised 不冒充 Abuse，也不再显示 Good 等安全等级。

UI 只持有观察和用户动作；`RoutedProbe` 管理意图、来源限频、缓存和路由有效性，`RequestSession` 管理请求资格与取消。
出口经现有 Go consumer，分类经 session.dio；没有新增队列或路由权威。全局关闭证书检查不能放宽这两种查询。
预览、文字展示、隐藏设置和 provider 重建均不启动分类；离开／后台／关闭详情及等待 begin 时撤销，会取消请求并丢弃迟到结果。
公网卡片移除也撤销手动意图，即使自动设置仍开着；基础站点诊断允许手动工作脱离卡片完成的既有行为保留。

## 已执行验证

- 锁定依赖、build_runner、intl_utils：成功；正常生成模型／provider／四种 locale。测试期间临时关闭 native
  hooks，finally 恢复原 pubspec；最终构建两类 hooks 均开启
- Flutter 受影响矩阵：23 个 suite、352 项通过，无失败／跳过；包含 3 项真实 Dart→Request scope→Go bridge
  用例
- 最终观察者生命周期增量：7 个 suite、122 项通过，无失败／跳过；其中 3 项新增、119 项复验。与前行合并为 355 个不同用例，
  不将重复执行相加
- JSON 解码增量：83 项通过、无失败／跳过；其中 3 项新增。重复地址键（含转义）与 status 拒绝；三轮去重共 358 项
- Go wrapper、probe、route 与站点诊断回归：75 个顶层用例和 61 个 subtest 通过，无失败／跳过；
  最后的公开地址校验修订另复验 7 个顶层、14 个 subtest，替换对应旧结果
- `go vet .`：成功
- `flutter analyze --no-pub --no-fatal-infos`：0 error、0 warning；42 项既有 info，
  均在未改动的其它测试中
- ARM64 release、APK 检查：构建、ZIP 完整性、包信息、仅 ARM64 原生库与签名验证通过；最终构建输入逐文件摘要前后一致

关键反例与消费者覆盖如下；具体用例和去重结果见冻结包内 `verification_summary.json`，命令与输出随日志保存。

- 卡片、组件预览、详情与配置：默认／旧配置零自动请求；进入详情零分类，显式按钮才发送；隐藏仅遮罩，预览无 watch；provider 重建不重放，
  后续显式查询可用
- 公网 Go HTTP/TLS consumer：单一固定接收方；所有 redirect 拒绝；坏证书、错误主机名及代理失败无直连回退；完整 EOF、4
  KiB 限额、超时和 scope 取消有真实连接关闭观察
- Dart 分类 consumer：唯一规范化地址 key 匹配；错 IP、等价重复／冲突条目和非公开 IP 拒绝；类型与 flags 独立，缺失／畸形保持
  unknown；外部链接不被访问
- HTTP 与 Proxycheck API 状态：403／429、HTTP 200 denied／error 拒绝；warning
  仅接受有效匹配结果并保留提示；Retry-After 秒数／HTTP date 有界且按来源退避，到期不自动重试
- Request scope 与完整 body：真实 begin/session；6 s／8 s 网络轮含 begin／slot 等待，不含 UI 来源间隔；
  越限、截断、读取错误不成功，超时实际撤销；全局 TLS 放宽不影响本用途
- 路由、触发与共享调度：手动／自动标记、闲置 DIRECT、30 s 来源间隔、5 min 自动 TTL、路由失效不重放；已有站点诊断与请求
  scope／receipt 行为回归通过

调试阶段曾发现 diagnostic header map 操作异常、卡片高度溢出，以及 notifier 复用时的取消／计时生命周期问题，均已修正后复验。
最后补齐自动设置开启时移除卡片的手动取消，以及 JSON 重复地址／status 键的覆盖反例；最终记录不包含未解决失败。

## APK 与源码绑定

最终 APK：`build/verification/l1-t08/ip_implementation_v2/artifacts/FlClash-0.8.99-android-arm64-v8a.apk`。
包身份、签名、文件摘要及构建输入集合见冻结包的 `apk_inspection.json`；`binding.json` 绑定最终构建与评审快照。
工具组合沿用[构建指南](../../../development/android_build_guide.md)，确切版本保存在 `tool_versions.log`。
实际包为 `com.follow.clash.dev`、`0.8.99`／`2026102301`，Android Debug 签名。
distributor 元数据报告 `0.8.99+2026100301`，与实际 Manifest code 不同；按 APK 实检身份绑定，不用打包元数据代替包身份。

首次成功构建出现 Native Assets 的 “File modified during build” 提示，已成功暖重跑；
最终观察者修订后再次构建最终制品，所有尝试日志均保留，不沿用先前源码的 APK。
Go hook 记录本次重编译；APK 内 Go 库的 `.text`、Go Build ID 与 GNU Build ID 与生成库相同。
Dart 制品中也存在新查询入口／来源标记，作为包核对的辅助证据，不能代替源码绑定或运行测试。

## 复现与体验

在同一工具及依赖环境中，用冻结包的 `commands.json` 运行合成测试或构建；Go bridge 为本次源码离线编译的测试进程。
Flutter 测试复用未改动的 Rust library，其路径与 hash 在 binding 中；测试只用内存、临时目录、受控时钟、adapter 和
loopback HTTP/TLS／假代理。
APK 未安装或启动。未来获准运行时，可从仪表盘手动刷新、卡片设置及 IP 详情的显式分类按钮体验；Hide IP 只控制显示，复制仍是显式原值操作。

## 未验证范围与剩余交付

- 未访问真实 Cloudflare／Proxycheck API，未证明线上匿名可达性、来源分类准确性或每日限额实际行为；本地 fixture 不能代替这些观察。
- 未进行设备／JNI、系统回调、宿主 TUN／代理或外部出口验证，不声称全部设备流量或匿名性保证。
- 自动资格不包含 viewport／弹窗遮挡检测。来源可见请求出口与被查 IP，`tag=0` 不承诺服务端完全不记录。
- 未修改 mihomo、gitlink 或 carrier；未读取真实订阅／数据库／凭据，未 push、上传或发布。
- M1 已通过 implementation_v2；D-02 已完成本地提交、合入与本项临时分支清理，
  再交 M1 核对 Details 和任务文档收尾。

## Disclaimer 已交付增量

Disclaimer 删除已在本次 IP 实施前通过 M1 评审并本地交付，实际当前基线为 `99e0678`。
移除专属启动同意／退出、工具入口、页面、接受状态及 gate/listener；旧 JSON 键按未知键忽略，其它请求／刷新资格和许可证保留。
当时 168 个不同合成用例通过；该未改动增量沿用原验证，不与本轮 358 项简单相加。
原实现与交付证据分别冻结于
`build/verification/l1-t08/disclaimer_implementation_v1/binding.json` 和
`build/verification/l1-t08/disclaimer_delivery_v1/binding.json`；完整增量记录可按上述 Git 版本查阅。

## 本地交付与整理

本地定稿相对获审快照仅整理五份手写文档，并由提交钩子格式化两份生成的 locale 文件。
生产逻辑与测试字节不变；两份生成文件经 Dart parser 核对，所有 token 完全一致，
另补跑的 3 项本地化测试通过。358 项主验证及获审 APK 据此等价复用，不将重复执行相加。

默认 Markdown lint 本次新增违规为 0；594 项基线 MD013 长行保留并单列，
不声称整篇默认 lint 零违规。实际整理差异和核对材料在本地交付 binding 中。

本项临时 feature branch 已清理；未创建额外 worktree，主共享 checkout、独立聊天、
获审 APK、有效验证与依赖缓存保留。M1 接续 message-only Details 和独立任务文档清理，
D-02 未提前删除 Plan／Tasks／Result；未推送或上传。
