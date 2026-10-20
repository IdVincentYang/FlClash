# L1-T07：实施与验证记录

本项已完成本地交付并结束；源码已快进合入本地 `security/android`，任务分支已删除，未推送。M1 已通过 design_v1 及
implementation_v2，I1–I4 全部关闭；implementation_v1 保留原未通过结论。
范围及正式语义见[设计](l1_t07_plan.md)，归属、授权与交付终点见[任务入口](loop1_tasks.md#l1-t07-修改常用站点诊断)。

## 实际证明的范围

- 基础检查对每个所选服务发送一次匿名 HTTPS GET，只读取响应头，不跟随跳转；2xx、跳转、受限响应和无法判断分别呈现。
- 高级检查只在详情中明确开始，打开、过期或重返详情不会自动重跑。Disney 在开始前说明匿名设备注册、临时令牌和 session 查询。
- 服务卡与列表展示实际诊断节点；所有页面用例均检查未调用 IP 查询，IP 质量 provider 一旦被读取即抛错。
- 全部服务可关闭；空集合不发请求，空页面仍可进入管理并重新启用。限频、路由变化、后台、取消及迟到答案由既有 RoutedProbe/Request 机制处理。
- 本地 TLS 收件端验证了接收方、证书身份、跳转和实际发送次数；高级最多八次发送，各步保留自己的出口与响应头耗时，聚合结果仅展示整轮总耗时。

上述结果来自合成数据、可控时钟及 loopback 收件端，不证明公开服务当前页面兼容、真实账号权益、播放或全设备流量保护。

## 运行与静态结果

获审 v2 的源码快照、精确命令、原始输出、1,328 项输入哈希及制品见本地忽略目录中的
[implementation_v2/binding.json](../../../../build/verification/l1-t07/implementation_v2/binding.json)
。日志中的旧失败轮次保留当时结论，最终通过轮次为 `flutter_final.jsonl` 和 `go_affected.jsonl`。

| 检查 | 实际结果 | 证明边界 |
| --- | --- | --- |
| Flutter 受影响矩阵 | 178 项通过，无跳过或失败 | common/provider/页面、共享 route/IP、协议、Request、四语言及圆角契约；不是全仓测试 |
| Go 受影响矩阵 | 75 个顶层用例、47 个子用例通过 | 六个受影响文件声明的用例全部列出、执行并核对；不是整个 Go 包的全部用例 |
| Dart→Go 联动 | Request scope 矩阵中的实际 Go registry 消费通过 | 合成状态及本地 Go 子进程，不是 Android JNI/VPN |
| 依赖与生成 | 离线解析与锁定解析、正常 build_runner 完成 | 测试使用既有 Rust 库；运行时生成结果随源维护 |
| 全仓静态 | 0 error、0 warning、42 项既有信息 | `flutter analyze --no-fatal-infos`；未将信息问题写为零问题 |
| Go 静态 | `go vet .` 通过 | CGO 关闭、依赖网络关闭 |
| Android ARM64 | release/dev 打包、ZIP、包信息及签名检查通过 | 温重跑无 hook 变化提示，构建前后 1,328 项输入相同；未安装或运行应用 |

`fake_async` 成为直接开发依赖，仍使用原锁中的 `1.3.3` 和同一校验值；根锁仅改变该项依赖分类，其余四份锁不变。
Core 仍为 `6c6e3e472bb246cc55f2e8577d9eddccc2623afc`，未修改 mihomo、gitlink 或 carrier。

Go 选择入口为
[go_selection.json](../../../../build/verification/l1-t07/implementation_v2/logs/go_selection.json)
：从 service_check、service_rules、service_diagnostics、probe、route、outbound_ip
六份测试文件提取真实声明，分别为 16、9、21、13、9、7 项；实际列出及执行的顶层集合与全部 75 项声明一致。v1
的命名前缀选择遗漏不能记为这些既有回归已运行。

## 实现首轮评审修订

M1 已在 implementation_v2 复审中关闭 I1–I4，以下为修订及实际自验依据。

| 问题 | 修订与实际证据 |
| --- | --- |
| I1 观察资格与手动意图 | 既有 inFlight 记录增加手动标记；合并操作保留真实手动意图。mutation 队列 hold 后，最后自动观察者退出的无 watcher/剩 passive 两种反例均为 Core 零调用，真实 RouteTracker 引用按持有者释放；手动基础请求退出观察后可完成，高级对照撤销。另修复关闭高级详情丢失已完成缓存年龄，重开后过期且不自动重跑。 |
| I2 失效后的统一收尾 | 路由变化撤销 due/inFlight 后立即重算引用及 timer。真实 RouteTracker 用例在迟到答案前确认无卡请求已释放 watch；其它消费者继续持有时不误释放，其退出后才发最终 stop，旧答案不落且无重发。 |
| I3 ChatGPT 分步观察 | 各实际请求增加固定 observation/规范化 region，传输 outcome 独立。真实三步收件端七种组合覆盖 iOS ISP/blocked/已识别页面、trace 正常/截断及 Web 正常/坏正文/unsupported；后续失败不抹去前步，原始正文不输出。两项详情页面用例验证端点各自的观察和地区可见；整轮不宣称账号或全服务可用。 |
| I4 既有回归遗漏 | 改为按文件真实声明建立精确选择，并比对 go test 列表、执行结果及计数；已补齐 service 16 项、probe 13 项及 route 全部 9 项，失败历史保留。 |

## 反例、修复与夹具边界

- 真实 provider 反例复现了请求在 Request.begin 中排队时，关闭再启用仍可能发送旧轮次。修复复用 inFlight 轮次资格，在进入
  Core 前复核，并直接观察主设置的关闭集合；修复后反例通过。
- 共享回归发现 Riverpod 销毁阶段同步释放 route 触发生命周期错误，以及重复 watch 导致 IP 失败项提前重试；
  修复后共享默认行为回归通过。
- 实际消费者拒绝了不可信证书、受信任但主机名错误的证书、跨源/降级/带 userinfo/错误端口跳转。失败代理不转直连；Disney 五类 POST
  跳转均不重放。
- 正文用例区分完成、完整标记、上限及读取错误；真实 Spotify 消费者拒绝超限或截断的有效 JSON 前缀，Gemini 不接受缺结束引号的地区标记。
  未知页面和缺字段不会成为可用结论。
- Disney 三步成功使用合成 assertion/token；输出 JSON 不含这些秘密、认证头或正文。多步不同出口及版本变化各有独立反例，
  聚合不把末步延迟/HTTP 状态冒充整轮结果。
- 原生 scope 反例使用真实 appRequestRegistry 租约和 HTTP consumer，撤销后连接结束且旧 scope 不能重发。代理协议
  adapter 与宿主 socket 许可为受控测试 seam，未验证实际 JNI、protect fd 或 VPN 接管。

旧失败日志保留在 `work/tests/`；v2 的修复前反例及最终通过日志保存在本轮包的 `logs/`。页面夹具曾受 Request 进程级队列的异步
zone、视口和加载动画清理影响；最终夹具跨 zone 回传结果、使用明确视口并清理剩余动画。
一次扩展矩阵在 Go 夹具修改期间运行联动子进程而失败；未保留该失败子进程的独立输出，不能确认根因。源码稳定后的完整矩阵已通过，旧轮次不计入通过。

## 制品与复现

获审 v2
[APK](../../../../build/verification/l1-t07/implementation_v2/artifacts/FlClash-0.8.99-android-arm64-v8a.apk)
SHA-256 为 `5de3e64553bc22583246f26940d31972a397f9967489d9bdcd00ec15ae361ce0`；包名
`com.follow.clash.dev`、版本 `0.8.99` / `2026102301`，仅 arm64-v8a，Android Debug 签名。
首轮 native hook 提示重跑，原日志保留；温重跑无此提示，输入哈希未变。构建使用
[本机指南](../../../development/android_build_guide.md)的 ARM64 release/dev 命令，禁用
upload/publish。
Flutter 测试临时关闭 native hooks 并恢复原始 pubspec 字节，使用此前保留的同源 Rust 库；Go 测试关闭 CGO、
GOPROXY 和 GOSUMDB，仅连接受控 loopback。
所需脚本、精确命令、前提及原始日志随本地交评包保留，不能把设备检查视为可由这些命令替代。

首轮未通过对象
[implementation_v1](../../../../build/verification/l1-t07/implementation_v1/binding.json)
保留原源码、APK、168 项 Flutter 与 33 顶层/40 子用例 Go 结果，I4 所指遗漏不计为通过。
历史进展包
[progress_v1](../../../../build/verification/l1-t07/progress_v1/binding.json) 和
[static_compatibility_v1](../../../../build/verification/l1-t07/static_compatibility_v1/binding.json)
保留当时的未测试/类型兼容结论，不作为当前最终实现的通过证据；其中旧 APK 已被后续源码修复取代。

## 收尾与本地集成

源码提交 `2de2f3460f7f420e3bd5f88ae12093ca18fc4534` 已从 `e25b4dd` 快进合入本地
`security/android`；任务分支 `security/l1-t07-service-diagnostics` 已删除。本项只有共享主
checkout，没有临时 worktree；共享目录、独立聊天、已审冻结包和有效复现材料保留。
最终关闭文档提交、当前树与源码/获审/构建对象的关系见本地忽略目录中的
[交付绑定](../../../../build/verification/l1-t07/delivery_v1/binding.json)。

提交前结构检查覆盖本项修改的 RoutedProbe/Request/RouteTracker 边界、服务 transport/规则/调度、模型及诊断页面；
未增加并行状态或通用适配层。
按既有收尾授权删除 Netflix 已被非 2xx 提前返回覆盖的旧 403 分支及对应不可达判断，移除重复状态赋值和失效说明；公开契约与已审失败语义保持一致。
整理后 Go 原精确 75 项选择和 47 个子用例、go vet 通过；两个生成 locale 文件经标准格式化并比对 token 完全一致，其余 Dart、
测试、依赖及生成文件与获审 v2 逐字节一致，复用 178 项 Flutter 和全仓静态结果。新 APK 重新构建，最终版本关系已记录到交付绑定。
三份手写 Markdown 检查按 80 字符正文换行，GFM 表格和代码块不限制列宽；其它规则使用 markdownlint 默认值。路径与锚点、
comment-density 和提交信息检查通过；关闭文档的补记只改变文档，复用同一生产与制品证据。

收尾后
[APK](../../../../build/verification/l1-t07/delivery_v1/artifacts/FlClash-0.8.99-android-arm64-v8a.apk)
SHA-256 为 `c234b6c45d9fa3eb6d94d72a18e8092f8697c4cbaeaf3b9ae03059b7c27532ee`，
包信息及签名与获审 v2 相同。新构建对应上述两份 Go 文件的等价整理，构建前后 1,328 项输入相同；初轮 hook 提示保留，温重跑无提示。
最终源码另含两个 locale 生成文件的标准格式化；其 token 与构建输入完全相同，字节差异由交付绑定明确列出。

### 用户体验入口

1. 在仪表盘添加或打开服务状态卡；当前显示的启用服务会在前台按约定进行基础检查。
2. 点卡片打开列表，可单项检查或检查全部启用项；管理页可关闭最后一项，再从空状态重新进入管理。
3. 地区/服务检查通过列表的信息入口打开，先阅读接收方和检测说明，再明确开始单次检查。Disney 额外显示匿名注册及临时令牌说明；
   离开高级详情撤销未完成检查。
4. 分步结果显示各自端点、受限观察、地区、HTTP 响应和出口，不能当作账号权益、播放或全设备保护结论。本文仅说明体验入口，本轮未启动应用进行实机体验。

## 未证明与剩余事项

未访问公开站点、真实订阅/DB/备份/凭据，未安装或启动应用，未改变宿主 TUN/系统代理，也未上传或 push。
T04/T05 全面整改、T08 的 IP 产品选择和其它任务未启动；设备、外部出口、当前服务协议兼容仍无实测结论。
实现复审、本地提交合入及任务分支清理均已完成，本项结束。整个 L2-T02 完成前仍不推送。
