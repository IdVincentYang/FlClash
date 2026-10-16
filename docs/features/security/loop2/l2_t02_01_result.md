# L2-T02-01 验证记录：静态策略编译与本地消费

2026-10-16，D-02 在 macOS arm64 完成首项实现、自验及 I1／I2 窄修订，**implementation_v2 已获 M1 实现评审通过，源码已本地合入 security/android，首项结束**。仅交付本地编译出口，普通 Profile／UI／DB／setup 尚未消费本策略；整个 L2-T02 未完成，未推送。

范围与契约见[首项设计](l2_t02_01_plan.md)，阶段状态见[子任务清单](l2_t02_tasks.md)。本次证明的是封闭静态输入在当前 Core 下的生成与消费行为，不证明所有应用上网已受管，也不消除[总体残留风险](l2_t02_plan.md#10-残留风险与不再承诺的能力)。

## 实际能力与使用入口

一份 JSON 输入生成互斥域名／地址分支、同序 DNS provider、显式默认及完整静态配置。严格模型拒绝未知条件／引用、空代理组、DoH（包括 bootstrap）、不支持协议和能力组合；固定节点、组、DNS 都由生成命名空间引用。无节点但显式 DIRECT／REJECT 的策略可以编译。

分支取决于 Core 当前有效 RuleHost。redir-host 的[反向映射记录](../../../../core/Clash.Meta/dns/middleware.go)和[入站预处理](../../../../core/Clash.Meta/tunnel/tunnel.go)可能把后续原始 literal 请求恢复为 Host，从而进入域名表；只有仍仅有地址时进入 IP 表。本次 DNS 夹具返回 loopback 地址，未建立这类 global-unicast 答案映射。C9 不证明“所有原始 IP 请求永远进入 IP 表”，“先记录适用地址映射再 literal”尚未验证。

本地命令的输入示例为[合成策略](../../../../test/fixtures/managed_profile/policy.json)。从仓库根运行：

```bash
dart run tool/compile_managed_profile.dart --input test/fixtures/managed_profile/policy.json --output build/verification/l2-t02/subtask_01/example.yaml
```

先创建输出目录，并按[项目工具链说明](../../../../.agents/commands.md#building)准备依赖。示例端口只是合成材料，不代表对应服务已运行；命令只生成文件，不应用配置或启动业务入口。实际消费者测试会创建本地服务、填入临时端口，再调用同一命令编译器生成真正被消费的 YAML。

macOS 输出在认证字节写入前，先对新建临时目录和空文件清除 ACL，再分别设为 0700／0600；完成写入后原子替换。只处理本项新建对象，父目录和旧输出权限不被改写。认证限 1–255 UTF-8 字节、拒绝控制／非无损文本，并作 YAML 回读核对。诊断不打印认证值。CLI 写入当前限 macOS／Linux；本轮仅实际验证 macOS，Windows 明确拒绝，Linux 未运行。SOCKS5 不提供到节点的链路加密。

## 受测对象与运行条件

| 对象 | 本次实际绑定 |
| --- | --- |
| 父仓库起点 | `02cb5546d6cf708587bc28ec655a863e3cb947a6` |
| 源码快照 | [implementation_v2 绑定](../../../../build/verification/l2-t02/subtask_01/implementation_v2/binding.json)，本地忽略目录；[v1](../../../../build/verification/l2-t02/subtask_01/implementation_v1/binding.json) 保留作为未受影响证据 |
| mihomo | `6c6e3e472bb246cc55f2e8577d9eddccc2623afc`；源码、gitlink、carrier 无改动 |
| 工具 | Flutter 3.47.4、Dart 3.13.3、Go 1.26.4；Rust／Cargo 1.98.0、主机 clang 可用 |
| native hook | 默认 setup／rust_api 开关保留；实际 dart run／Flutter test 进入 hook 流程，本机资产构建／复用日志保留 |
| 网络目标 | 仅 loopback DNS、SOCKS5、TCP／UDP 业务及测试进程 CA；未接触真实订阅、秘密或外部测试目标 |

初次默认 Go 缓存准备发生了官方依赖下载。后续复用了已有 Go 模块缓存，GOPROXY／GOSUMDB 设为 off；未改共享 pubspec 或锁文件。`dart compile exe` 成功生成 AOT 命令，并以同一主机的 `--help`、文件编译和真实消费验证其可运行性；不据此声称所有根命令无需 native hook，亦不承诺任意机器单文件搬运。

按贡献指南只读取得上游 `03f955382409a4a7ac1f3f92e46d9fcc6d39f106`（v0.9.0）并查阅与现有基线关系；该版本不是受测对象，本项未混入上游同步。首项新增模块保持应用侧边界，后续同步仍需复核核心能力与最终合成接口。

## 消费者结果

[Go 消费测试](../../../../core/managed_profile_test.go)直接执行编译后的真实 Dart 命令，读取其原样 YAML，经现有 prepare／install／activate 应用后访问核心监听。测试只调整源 JSON 中的端口／场景，不在 Go 侧手写或补写待测路由 YAML。

| 判据 | 实际观察 | 结论 |
| --- | --- | --- |
| C1 同序 | 宽后缀先时业务及 DNS 均到 A；交换后均到 B；各目标场景其它 DNS／bootstrap／DIRECT 为 0 | 通过 |
| C2 正常／默认 | DIRECT 域名、A/B、域名默认、IPv4／IPv6 CIDR、IP 代理默认及直连／代理本地 UDP DNS 实际收件正确 | 通过 |
| C3 拒绝／空项 | 条目与默认拒绝均无业务目标收件；真实 DNS 返回 REFUSED；无节点空列表配置也被真实 Core 接受 | 通过 |
| C4 严格失败 | 未知字段／版本、缺默认、重复 ID、空组／坏引用／条件、DoH 与 bootstrap DoH 被拒绝，旧输出保持 | 通过 |
| C5 UDP 隔离 | TCP-only 域名组下 UDP 目标收件为 0；同目标的显式 IP DIRECT 收件为 1 | 通过 |
| C6 DNS 能力／失败 | UDP 能力错配编译失败；A 代理失败有 1 次实际尝试，查询期限内其它代理、直连及 DNS 收件为 0 | 通过，有界观察 |
| C7 DirectResolver | 真实 DIRECT 适配器的未命中域名查询到 B DNS；默认拒绝时失败；bootstrap 均为 0 | 通过 |
| C8 DoT 身份 | 正确信任／IP 时 DoT 收件 1；错误 IP 或未信任证书收件 0，无明文／备用服务收件 | 通过 |
| C9 仅地址／确定性 | 未恢复 Host 的 IPv4／IPv6／地址默认场景未新增目标 DNS；相同输入输出相同，调序同时改变两端顺序 | 通过，限本场景 |
| C10 认证／IO | 实际 SOCKS5 接受 255 UTF-8 字节认证；v2 增加继承 ACL 反例及清除验证，权限／替换／写入限额失败仍保留旧输出 | 通过，见修订增量 |

v1 Go 消费组为 **13 个顶层测试、25 个叶场景，0 失败、0 跳过**。v2 复验受影响的认证与写入失败消费者，2 个顶层／2 个叶场景通过，无跳过；规则、模型和 Go 消费源码未变，其它消费证据直接复用。每个场景区分服务与代理收件；DoT 测试只向当前测试进程证书池加入合成 CA，不改系统信任。失败观测均有期限，不能据此推导任意时长后台任务已经停止。

bootstrap 为明确 IP 服务，配置被核心接受；本轮业务不需要节点／DNS 服务的域名启动解析，实际启动查询为 0，不声称已支持域名节点。TEST-NET 地址场景由本地合成代理直接响应，不向该地址发起外部拨号。

## 静态检查与回归

| 检查 | 实际结果 |
| --- | --- |
| flutter pub get | 通过；依赖清单与锁文件无差异 |
| 正常 build_runner | 通过；写出 7 个生成输出，跟踪文件无额外差异；旧 delete-conflicting-outputs 参数被工具忽略 |
| Dart format | 变更文件通过 |
| flutter analyze --no-fatal-infos | 退出 0；0 error／warning，42 条既有 info，涉及未改的测试 |
| Flutter 窄测 | v1 的 53 项通过证据保留；v2 写入相关 3 项通过，含 2 项复验及 1 项新增 macOS ACL 回归，无跳过 |
| Go wrapper 回归 | 配置失败、分阶段激活、监听失败和 UDP／迟到响应：4 个顶层、7 个叶场景通过 |
| Go vet | 通过 |

## I1／I2 修订增量

- **I1 反例。** 在本项新建的父目录加入可继承的 everyone read ACL，运行冻结的 v1 命令。旧输出虽然 mode=0600，仍有 inherited allow read ACE；因此 v1 单独的 BSD 位检查不足以证明其私有输出声明。没有使用其它身份、sudo，或修改已有用户目录权限。
- **I1 修复与观察。** 对新建临时目录／空文件先执行 macOS chmod -N，再设 0700／0600，任何失败均先于秘密写入。v2 实际命令在相同父目录输出无 ACL 的 0600 文件；父目录及旧输出 ACL 未变，同一输入的 YAML 字节与 v1 完全一致。替换失败退出 74；子进程写入限额触发 SIGXFSZ 时旧输出不变，残留临时目录／部分文件为 0700／0600 且无 ACL。正常失败清理与原子替换保持原契约。
- **I2 范围。** C9 只承接本次未恢复 Host 的地址场景；已有映射恢复域名后按域名表处理的语义保留，先 global-unicast 答案映射再 literal 未验证，不把原始输入形式视为永久分类。

最小反例和修复后的有效 ACL 观察保留于 [v1 反例](../../../../build/verification/l2-t02/subtask_01/implementation_v2/acl_repro_v1.json)、[v2 观察](../../../../build/verification/l2-t02/subtask_01/implementation_v2/acl_repro_v2.json)。两份均为本地忽略目录的合成记录；实际 ACL 回归及相关 writer 复验可由测试文件的 writer／permission 用例重建。v2 analyze 退出 0，仍为 42 条既有 info、无 error／warning；仅重编译 CLI，未重跑未受影响的完整矩阵或 APK。Linux 未运行，不从 macOS 结果推广其 ACL 行为。

没有运行全量 Flutter／Go 测试、APK 构建、设备、TUN、系统代理或 Linux／Windows 验证。首项不改平台接口或普通合成代码，以上范围不扩写为其它环境通过。

## 复现与保留

本地原始日志、合成输入、真正消费的 YAML 和 AOT 命令保存在忽略目录。当前冻结包为 [implementation_v2](../../../../build/verification/l2-t02/subtask_01/implementation_v2/binding.json)，[v1 完整矩阵](../../../../build/verification/l2-t02/subtask_01/implementation_v1/binding.json) 保留；绑定记录列出复用范围及受影响的增量验证，不上传。重新生成时使用当前源码、对应工具链、已解析依赖及 Core carrier；服务端口由测试重新分配，不能直接把历史 YAML 当作仍在运行的配置。

从仓库根执行，设置实际可用的 Go 模块缓存后：

```bash
mkdir -p build/verification/l2-t02/subtask_01/bin
dart compile exe tool/compile_managed_profile.dart -o build/verification/l2-t02/subtask_01/bin/managed_profile_compiler
env FLCLASH_MANAGED_PROFILE_COMPILER="$PWD/build/verification/l2-t02/subtask_01/bin/managed_profile_compiler" CGO_ENABLED=0 go -C core test . -run '^TestManagedProfile' -count=1 -v
```

缺少编译器环境变量时集成测试会明确 skip；本次带真实路径运行，未复用 skip 作为通过。CLI 输入／输出夹具与记录可本地检查，不需要启动应用或改变宿主网络。

## 本地交付

- 实现提交为 `d7b66dcd00f0c7242c0ac1b7d59768d7bb74395f`，已快进合入 `security/android`；最终本地 HEAD、状态记录提交及文件校验见[收尾绑定](../../../../build/verification/l2-t02/subtask_01/final/binding.json)。
- 合入后产品代码、测试及最小夹具与已审 implementation_v2 完全相同；后续只记录评审／交付状态，原构建及消费证据保持有效，没有因提交历史重复产品验证。
- 按 pre-commit-quality-review 检查严格模型、同源编译器与 CLI I/O 的职责和依赖，未发现需处理的结构问题。Dart／Go 格式、comment-density、文档 H1／链接及 diff 检查通过；6 份 Markdown 按现有长段落风格关闭 MD013，其余 lint 为 0。
- 临时分支 `security/l2-t02-01-static-policy` 已删除；没有创建临时 worktree。共享 checkout、独立聊天及 v1／v2／收尾本地证据保留。

## 未接入与剩余边界

- 尚无 Profile 策略页、DB／备份迁移、普通 setup 最终编译接入、来源资格撤销、受管控制接口和刷新。现有 Profile 的行为仍由旧路径决定。
- 尚不支持 DoH、域名节点／服务、regex／Geo／动态 provider、其它节点协议、fake-ip／hosts 或 WG 特殊解析；未知／不支持输入拒绝，不能用丢条件提高兼容率。
- 主动 DNS 探针为 A，真实 DIRECT 解析还触发 A／AAAA；CNAME、非地址记录和 UDP 截断后重试未做专项验证。本轮不把这些核心路径记作已验证。
- 旧 DNS Background、共享缓存／查询、迟到结果、远端解析以及物理网络来源未修复。本地配置级证明不能替代全设备接管、停止后零外发或核心取消保证。
- M1 已通过 implementation_v2，I1／I2 闭合，首项完成本地交付；后续子任务未启动，整个 L2-T02 未完成前不推送。
