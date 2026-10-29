# IP 查询设计

本文件维护公网出口观测与 IP 分类的有效契约；T08 已实现、通过 M1 实现评审并完成本地合成验证。
依据 [共同需求](security_requirements.md)与 [Loop 1 决定](loop1/loop1_plan.md#功能决定与待细化事项)。
实际受测对象、制品与未验证边界见 [T08 Result](loop1/l1_t08_result.md)。
以下使用入口可在获准运行时体验；来源线上可达性与设备行为仍受文末验证范围限制。

## 用途与数据

- 出口 IP／国家：仅 `https://www.cloudflare.com/cdn-cgi/trace`，无被查 IP 参数。
  结果：该端点本次看到的请求出口；国家由同一响应提供。
- IP 分类：仅 `https://proxycheck.io/v3/{ip}?tag=0`，规范化被查 IP 放在 path；固定 tag=0
  减少可选检测记录。结果：该来源对被查 IP 的 network.type、organisation、ASN 与 detections 标记。

接收方均看到本次请求出口，分类接收方还可关联被查 IP。两条请求各按自己的目标规则路由，出口可能不同；
不能把观测推广为节点对全部目标的地址、全设备保护或安全／匿名证明。无隐式备用源、竞速、HTTP 降级或故障切 DIRECT。
不附登录认证、Cookie、Referer、设备标识或应用 UA，使用固定通用 UA，强制 TLS 验证并拒绝所有 redirect。
来源当前协议可用性与分类准确性未做外网实测；单源故障显示失败。
旧候选 ipapi.is 的官方匿名协议仅提供简化归属，不提供分类标记；该真实能力缺口导致选源调整，不能以全 unknown 算分类可用。
用户已明确选择 Proxycheck 单一 HTTPS；不注册、不附 key。依据 [Proxycheck Stable v3](https://proxycheck.io/api/)：
匿名限额每日 100 次，代理出口可能被拒绝；失败不改变请求出口或接收方。固定 tag=0 用于禁用该查询在 positive detection
dashboard log 的可选保存，
不承诺服务端完全不记录。线上匿名可达性／分类准确性未实测。
HTTP 403/429 与 API denied/error 均不得成功；按 Retry-After 在同来源范围退避（秒数／HTTP date 限制为
30 s–24 h，缺失或畸形用 5 min），到期不自动重试。
API warning 仅在存在唯一有效匹配条目时接受，并保留 warning 状态供用户识别；不静默视为普通成功。
响应中的地址 key 是身份依据：只接受与输入规范化公开 IP 相等的唯一条目；缺失、错 IP、多个等价 key 或额外其它 IP 条目均失败。
JSON 解码时也拒绝重复的地址键或 status，避免同名键覆盖后掩盖冲突。
network.type 为 Residential/Business/Wireless/Hosting 或 unknown；Wireless
同时包含蜂窝与卫星，独立显示 Wireless，不能映射为 Mobile。
detections.proxy/vpn/tor/hosting/compromised 等分别维护原义；compromised 不当作 Abuser，
缺失保持 unknown。
响应的 hostname、docs 或其它链接仅作数据，绝不触发额外访问。

## 入口与请求资格

出口默认手动，旧配置缺少新设置也默认手动。用户可在正常仪表盘卡片明确开启自动，说明单一接收方与用途。
自动须同时满足 appVisible、当前导航为仪表盘、正常卡片已配置、运行且未暂停、用户已开启；滚出 viewport 或弹窗遮挡不改变资格。
组件预览使用无请求展示；IntranetIP 是独立本地卡片，不参与公网查询。
手动闲置查询明确标 DIRECT；自动不在闲置时发起。不可用路由／服务状态显示失败，不静默回退。

IP 文字、隐藏设置、打开／重开分类详情及 provider build/watch 都不发分类请求；只有显式查询／重试 action 产生一次意图。
开始前固定被查 IP、来源与 generation。native/provider/retry 状态重建不消耗新许可，不重放失败或取消的意图；UI 随
notifier 实例更新转移 passive watch，关闭时释放当前实例的请求资格。
hideIp 只遮罩显示，复制原 IP 是显式操作，不能描述为外发控制。

## 所有权与失败

沿用 RequestSession、RoutedProbe、RouteTracker 和原生 ServiceState；出口经 Go wrapper，
分类经受管 session.dio。
不增加平行队列或旁路 client。每用途／来源最短间隔 30 s；出口自动 TTL 5 min，手动只标 stale 不重查。
分类缓存绑定 IP、来源及观测时间；旧目标的分类不冒充当前出口。
离开页面／后台、撤销自动用途、路由失效和关闭详情撤销相关请求资格，关闭在途连接，丢弃迟到回答。
公网卡片移除时，即使自动设置仍开启，也撤销其手动请求或已合并的手动意图；不沿用基础站点诊断允许手动任务脱离卡片完成的行为。
begin 等待窗口也核对 generation；晚到 session 必须关闭，不能继续发送。
provider 重建若复用 notifier，保留 passive watch、来源间隔和退避，但撤销旧请求意图；
路由租约和计时器按新生命周期恢复，不因重建重放手动查询。

达到最短查询间隔后才受理网络轮；UI 间隔等待不计入网络轮期限，页面／用途撤销仍取消等待。路由快照不可用时失败，不保留手动意图等待恢复。
出口／分类从网络轮受理起的整轮期限分别 6 s／8 s，覆盖 begin、Core slot 排队、DNS/TLS、发送、读取与结果接受；
到期实际取消请求与 stream。body 在交给 parser 前按字节累计，上限分别 4 KiB／64 KiB，超限立刻取消。
仅解析完整 EOF、无读取错误且未过期的回答；截断不能用已有字段冒充成功。
区分取消、超时、HTTP 拒绝／429、越限、身份不匹配和解析失败；本用途日志不记录 IP、完整 URL 或 body。

输入与响应地址 key 都必须为公开 IP literal，规范化字节相等才接受分类；IPv6 压缩／展开和大小写等价，
IPv4-mapped 先统一为 IPv4 再判断公开性，拒绝私网、loopback、link-local、multicast、非公网保留段、zone ID
和 URL 片段。
IPv6 文档段包含 `2001:db8::/32` 与 `3fff::/20`，依据 [IANA Special-Purpose Registry](https://www.iana.org/assignments/iana-ipv6-special-registry/)。
响应 IP 缺失、畸形或不匹配均失败，不能用输入补身份。类型或风险字段缺失为 unknown，不能推断 residential／安全；
保留来源实际声明的类型与标记，删除 Good 等等级和安全配色暗示。

## 使用与验证范围

手动出口入口给出 Cloudflare、路由模式与刷新动作；分类详情先说明 proxycheck.io 将收到被查 IP，再由按钮开始单次查询。
结果显示来源、IP、时间，必要时标 stale／失败；分类字段分别表达 unknown。请求取消后只能由新的显式动作重试。
使用本地合成 adapter、受控时钟、loopback HTTP/TLS／假代理验证 UI→provider→begin→Go 消费链及失败反例；
实际通过范围由当次结果记录维护。测试不接触真实配置／凭据，不发外部测试流量，不替代设备／JNI 或全设备验收。
