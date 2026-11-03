# 暂缓安全事项备忘

本文维护尚未解决且需要接续的安全事项：Loop 1 T04/T05 保持用户决定的暂缓状态，
L2-T02-R1 保留本轮已证实缺陷及上游跟踪。记录/暂缓不表示风险已解决或被用户接受，
也不构成自动修改 Core、恢复其它任务或扩大权限的授权。
共同目标见[安全要求](security_requirements.md)，当前用途和局部保护见[联网用途清单](android_network_inventory.md)。

- [T04 服务身份、认证与跳转](#t04服务身份认证与跳转)
- [T05 日志与错误信息脱敏](#t05日志与错误信息脱敏)
- [L2-T02-R1 共享 IP 与域名身份](#l2-t02-r1-共享-ip-与域名身份)

## T04：服务身份、认证与跳转

- 风险：普通下载可使用 HTTP，证书检查开关可被关闭，重定向的接收方、认证和正文没有完成统一保护。
  WebDAV 跨源虽剥离 Authorization，仍可能重发含秘密的备份正文；代理出口不能代替服务身份校验。
- 影响入口：订阅导入/刷新、远程脚本、图标、provider/Geo、手动更新与 WebDAV。
  自动订阅或核心维护也可能触发，不能只按是否打开 WebDAV 页面判断未使用。
- 恢复评估条件：准备使用上述实际可达路径、调整证书信任/跳转策略，或新增接收方时，核对启用条件与敏感字段。
  原暂缓决定日期为 2026-10-15；日常调度许可不等于已接受跨源秘密传输。
- 处理目标：必要认证正常可用，错误身份、HTTPS 降级和跨源跳转不得未经接受继续发送秘密；
  同时审查 URL、认证头、请求体及私有证书兼容，直连和代理使用同一身份要求。
  不以全局忽略证书错误解决兼容问题。
- 当前边界：站点/IP 诊断的严格 TLS、接收方和跳转限制只覆盖对应消费者，未替代本项全面整改。
  入口见[请求会话](../../../lib/common/request.dart)、[证书/HTTP](../../../lib/common/http.dart)、
  [WebDAV](../../../lib/common/webdav.dart)。

## T05：日志与错误信息脱敏

- 风险：订阅令牌、URL 用户信息/查询、认证、密码、请求体和异常字符串仍可能进入 Dart/Go/原生日志或错误显示。
  本地保存不等于没有秘密；主动分享、导出或备份会扩大接收范围。
- 暂缓依据：用户于 2026-10-18 基于当前本地使用方式降低优先级，有必要时再做。
- 恢复评估条件：准备分享/导出普通日志、将其加入备份或上传，或发现新的秘密复制路径时重新评估。
- 处理目标：常规成功、失败、跳转、重试及底层异常不暴露完整秘密或无关配置，同时保留定位错误所需信息。
  覆盖普通日志、错误显示及相应导出消费者，不能只处理一条打印语句。
- 当前边界：[报告受控摘要和显式原文导出](crash_reports_design.md)已交付，但不表示普通日志已全面脱敏。
  原始 dump 可能含敏感内存，字符串过滤不能保证清除其秘密，继续采用私有保管与明确选择导出。

## L2-T02-R1 共享 IP 与域名身份

状态：**未解决，DNS 安全验收未通过**。本轮在当前公开 API 和窄应用边界内未找到可信完整修正；
用户于2026-11-03决定继续不改核心，无可行应用方案则记录问题、后续跟踪核心修复。
这是调查/说明的交付出口，不是接受错路风险，也不把 L2-T02 或 Loop 2 标为全部完成。

### 影响、版本与已证实事实

受管模式从一份策略生成业务/DNS规则，但 Core 仍须在业务连接时辨认域名。
当前 redir-host 将真实 DNS 答案按单一 IP→域名保存；A/B 共用 IP 时，后解析的 B 可覆盖 A。
IP-only 入站据此恢复 Host，可能使原 A 业务使用 B 的路由，即使两份生成规则本身完全同源。

宿主真实 Core 的 TCP/SOCKS IP 实验已证实：A→组A/DNS A、B→组B/DNS B，两个 DNS 均答同一真实地址，
依次解析 A/B 后，客户端使用先前取得的 A 地址发送标为 A 的 HTTP 请求，实际只有代理 B 新增收件1、A增0。
显式域名 SOCKS A/B 对照各自正确；未建立 mapping 前，同一 IP 按显式地址默认 REJECT 被拒绝。
这是独立业务收件反例，不只依据 Core 最后恢复出的 Host、界面文案或 YAML 判断。

当前固定 Core 为 `6c6e3e472bb246cc55f2e8577d9eddccc2623afc`，
由 configured [FlClash Core fork](https://github.com/chen08209/Clash.Meta) 的公共基线
`8597778c7df410ebe88c57e59eaab32d203156df` 加既有 carrier 恢复，
来源关系由[carrier manifest](../../../core/patches/l1_t03/manifest.json)维护。
该基线与当前 Core 的 DNS mapping/enhancer 和 fake-ip pool/store 相关文件相同；
本轮不修改 Core 源码、gitlink 或 carrier，不把它等同于最新 MetaCubeX release。

受影响的用户理解入口包括 Policy draft、Generated draft preview、Save and request application、
Actual accepted configuration、Start 与 Android service。保存、采用成功或 VPN active 只说明各自事实，
不能证明原域名身份和实际业务/DNS收件一致。普通配置也不因未选择受管模式而自动避开核心 mapping 问题。

### fake-ip 候选调查及证据边界

本轮只以公开 API 和手工机制配置调查 fake-ip，未作为产品默认/受管 Apply 上线：

| 机制条件 | 实际观察 |
| --- | --- |
| 原内存池持续使用 | A别名保留，新B获另一个地址 |
| 新池 CloneFrom 或真实 Executor 普通更新 | A别名表先保留，随后新B重用A地址 |
| 持久化自动重建或无 Shutdown 的新进程恢复 | 原A丢失，新B重用其地址 |
| 无并发、正常缓存、显式 StoreState 后重建/恢复 | A保留，B获新地址；仅有条件成功 |
| 同一内存池 CloneFrom 自己 | 调用进入后未返回，3秒截止回收；源码支持同锁等待 |
| 小 LRU 与小地址范围分别验证 | 前者丢失A；后者循环把A地址分给D，不能混称 |
| 专用 DB Close 后继续分配 | 返回别名但反向身份不存在，API未返回错误 |

因此单改 enhanced-mode 或打开持久化不足以成为修正。
普通 DNS listener scope 不覆盖全部 TUN relay；全局 Service 包装也不提供 Pool 分配前原子拒绝重用、
可靠接管 allocator 和所有恢复/失败条件。另建别名数据库、matcher、平行运行状态或复制 Core 实现
超出本轮窄边界。结论是本轮未找到可行窄方案，不宣称所有应用方案均不可能。

未证明的部分保持分开：DIRECT 外发、REJECT 绕过、UDP、APK/AVD/TUN 实际业务未由本轮 R1 复现；
不能把宿主 TCP 结果扩大为已经发生设备外发。小 LRU/范围仅隔离机制，不代表生产第三/第四次查询即耗尽。
冷恢复为两个合成测试进程间恢复、未调用 Shutdown，不等于任意写入时刻断电；
DB Close 不覆盖全部 I/O 故障。有条件 StoreState 成功未证明 live DNS 排空/并发/原子持久化安全。

### 使用条件与规避限制

SOCKS 目标使用 DOMAIN 类型，或 HTTP 代理的 absolute URL/CONNECT 目标携带域名时，
入口 metadata 可保留该域名；未变成 IP-only/嗅探覆写时，不需要本次 IP 反查恢复身份。
本轮实测对照为 SOCKS 域名入口；HTTP 代理上述字段是源码边界，未做本轮 HTTP 入站独立实测。
仅在业务载荷写 HTTP Host 头不能提供同样条件：R1 中 Host=A 的 IP-only 请求仍去了 B。
这些条件不可推广为普通 TUN、任意代理协议或全部目的身份保证。
字面 IP 也可能被 mapping 归入域名表；地址规则仅适用于 Core 没有有效逻辑域名的情况，
IP REJECT 不等于限制所有域名最终目的 IP。

统一出口最多减小 A/B 的跨出口差异，仍不能恢复原域名/目的身份；normal 或仅显式域名代理
会改变既定普通 TUN 分流能力。本轮不更改用户默认、不将其作为等价修复或关闭本项。
新 qname、短 TTL、清答案缓存、立即连接、重启或单次成功也不能单独证明身份可靠。
代理内部 DNS/实际远端 IP、应用自带加密 DNS 的不可见域名及设备接管范围另按原保护边界判断。

### 最小复现与未来判定

正式入口为[共享 IP 收件诊断](../../../core/managed_identity_test.go)与
[生命周期诊断](../../../core/managed_fakeip_lifecycle_test.go)，复用既有本地消费者夹具。
需要仓库当前源码/已恢复 Core、Go/Dart 和正常依赖，准备方法见[构建指南](../../development/android_build_guide.md)。
下面使用新的本地输出目录；生命周期目录须尚未存在，不覆盖已冻结证据。
默认测试选集跳过这些手动调查；显式运行在当前版本预期 exit 1，不应改断言接受 B 来使其变绿。

```bash
mkdir -p build/verification
r1_run_root="$(mktemp -d "$PWD/build/verification/r1-manual.XXXXXX")"
DART_SUPPRESS_ANALYTICS=true FLUTTER_SUPPRESS_ANALYTICS=true \
  dart compile exe tool/compile_managed_profile.dart \
  -o "$r1_run_root/compiler"
compiler="$r1_run_root/compiler"
CGO_ENABLED=0 GOTELEMETRY=off \
  FLCLASH_MANAGED_IDENTITY_INVESTIGATION=1 \
  FLCLASH_MANAGED_PROFILE_COMPILER="$compiler" \
  FLCLASH_MANAGED_PROFILE_EVIDENCE="$r1_run_root/domain" \
  go -C core test -run '^TestManagedProfileSharedIPInvestigation$' \
    -count=1 -v -timeout 60s .
CGO_ENABLED=0 GOTELEMETRY=off FLCLASH_FAKEIP_LIFECYCLE=1 \
  FLCLASH_FAKEIP_LIFECYCLE_EVIDENCE="$r1_run_root/lifecycle" \
  go -C core test -run '^TestManagedFakeIPLifecycleInvestigation$' \
    -count=1 -v -timeout 45s .
```

共享真实地址仅为 mapping/代理请求标记，合成收件实际位于 loopback；不向文档网段/公网发送连接。
生命周期测试只用合成缓存与自有子进程，死锁案例按截止回收；测试不修改宿主网络或用户数据。
调查的观察项是原请求、DNS/代理收件、实际 alias→host、失败和超时；它们不是未来保护已成立的保证。
诊断含当前故障前提，例如同池调用的预期截止，不是无需适配即可用于未来版本的统一验收套件。
后续 API/机制改变时可更新观测分支和夹具，仍须单独证明原身份、失败关闭及相应真实消费者的保护判据。

后续在同步/升级 Core、官方相关变动或用户重新安排修复时复查
[MetaCubeX upstream](https://github.com/MetaCubeX/mihomo)及 configured fork。
官方只读查询日为2026-11-03，已核以下不同状态：

- [PR #3283](https://github.com/MetaCubeX/mihomo/pull/3283) 于2026-10-08合并，
  commit `e4dd968de9e10ecc6770acfafd306edeb578eb52`，
  [v1.19.33](https://github.com/MetaCubeX/mihomo/releases/tag/v1.19.33)
  包含同范围复制 allocator 状态的修复。
  已读 tagged 源码，但该变化未进入当前固定 Core；不代表 R1 全部解决。
- [PR #3313](https://github.com/MetaCubeX/mihomo/pull/3313)
  查询时 Open，涉及持久化 pool 重建清掉在用缓存。
- [issue #2997](https://github.com/MetaCubeX/mihomo/issues/2997)
  查询时 Open，涉及 filtered 真实 IP/VLESS 目标改写；
  是相关线索，不是本地 SOCKS 路由错配的同一反例或完整修复证明。

更新本项状态前，变化必须实际进入当前源码/依赖及对应构建/APK，并重跑原 A/B 请求与独立收件、
普通更新后旧别名/新分配、恢复/缺失/容量/写失败等受影响反例；保持原身份与失败关闭预期。
若修正改变 DNS 返回格式，夹具应使用其真实返回地址，仍保留原域名/独立收件的预期，不改为接受 B。
若变化影响 TUN、UDP、DIRECT/LAN、DNS出口或维护请求，还需相应真实消费者验证。
release notes、issue关闭、API改动、退出码或短时未收件不足以关闭本项。
本记录不创建新 automation/任务，不授权发上游 issue/评论或上传本地证据。

## 历史与接续

Loop 1 已交付项、当时计划和验证限制可从 `aae1850` 的仓库历史读取；清理的是当前任务记录，
长期能力契约、构建指南、源码与本地证据继续保留。后续重新安排上述事项时先核对实际源码和使用条件。

```bash
git show aae1850:docs/features/security/loop1/loop1_tasks.md
git show aae1850:docs/features/security/loop1/loop1_plan.md
```
