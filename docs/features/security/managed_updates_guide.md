# Managed Profile 更新与验收指南

本指南说明如何明确绑定订阅材料，以及如何区分保存、预览和实际采用。
本地合成验证覆盖支持材料的更新、失败保护及预览并发；实际设备、物理网络和真实订阅兼容尚未验证。
支持上限和失败语义以[材料更新契约](managed_updates_design.md)为准。
完整受管使用路径见[受管使用指南](managed_profile_guide.md)。
未解决的共享 IP 身份缺陷统一见[R1 长期记录](deferred_security_items.md#l2-t02-r1-共享-ip-与域名身份)，
既有材料更新/采用结果不等于 TUN 原域名身份保证。
产品界面名称以下列 English 文案为准。

## 绑定与更新

1. 在 Profiles 导入自己的配置，保留所需的 Request route 和 Auto update。
   打开该 Profile 的 Policy draft，维护 domain/IP 的 target、默认、DNS 服务和监听端口。
2. More → Source bindings → Bind source node / Bind source select group，选择源文件中的精确名称。
   这会新增明确的来源资源；原手工节点及组保留手工含义，不按同名自动替换。
   点击已绑定资源可重新选择来源名称。源 select 组的全部成员都须受支持，不能含 DIRECT 或嵌套组。
3. 集合使用 Source bindings → Bind source domain collection / Bind source address collection。
   在域名或 IP 条目编辑器的 Source collections 中选择该集合，再指定自己的 target 和 DNS 服务。
   集合只提供条件，用户条目的位置、target、DNS 和显式默认仍决定策略。
4. Generated draft preview 检查展开后的脱敏配置。Save 只保存草稿；Save and request application
   会选择维护目标、显示采用确认，再保存选择并请求应用。它不启动已停止的服务。
5. 常规 Sync 和合资格自动刷新会先预检候选，成功后保存材料并重新构建。
   Profile detail 的实际状态与 Actual accepted configuration 用于核对采用；模板文本相同或 Sync 成功
   不能单独证明新节点生效。页面核对实际 input 的材料摘要与当前保存文件，而非只比较模板摘要。

来源须为 UTF-8 YAML/JSON 对象；本项不处理加密封装、远程 provider、Geo 或其它节点协议。
不支持输入会整份失败，不能通过关闭校验或切换 Direct 来绕过。

## 失败与重绑

候选在源提交前失败时，旧文件与刷新日期不变，仍合资格的 A 保持可用。
源已提交后的构建或应用失败由既有配置接受链判定保留或关闭，不能恢复已经失效的 A。

重命名或改 URL/overwrite/script 后，可在 Source bindings 中选择
Load latest material for preview。它下载到页面临时文件，不改变正式源文件、日期或选择。
重新选择变化的来源资源，预览后使用 Save and request application，才会采用这份候选及绑定。
Save 仍只保存草稿。Discard preview material、离页或较新加载使旧候选不可采用；关闭页面会清理临时文件。
来源或设置在预览后变化时须重新加载，旧预览不能覆盖较新状态。

备份恢复保留模板原版本和来源身份。相同 ID 但 URL、overwrite 或 script 不匹配时须重绑，不能静默采用。
缺少脚本时先恢复或明确选择正确的脚本，再预览；未知版本保持不可采用。

## 本地合成 A/B 夹具

不要覆盖真实 ouo。本项使用独立的 `ouo-local`，只在 loopback 提供合成 HTTP、SOCKS5 和 TCP DNS
收件端；源代码在[手动入口](../../../core/managed_update_fixture_test.go)，收件实现复用
[受管消费者夹具](../../../core/managed_profile_test.go)。夹具不读取用户配置，也不连接外部测试目标。

在仓库根构建编译器，再启动夹具；`FLCLASH_MANAGED_UPDATE_AVD=1` 使材料地址为 Android Emulator 的主机别名
10.0.2.2。宿主本地消费者省略该变量，使用 127.0.0.1。
下述设备操作须由用户执行，或在明确授权的独立专用 AVD 中执行；不操作已有用户设备或 global ADB。
该手动夹具分别发业务与 DNS，不能证明共享 IP 的原域名身份；真实 mapping 反例及复现见 R1 长期记录。

```bash
dart compile exe tool/compile_managed_profile.dart -o build/managed_profile_compiler
FLCLASH_MANAGED_PROFILE_COMPILER="$PWD/build/managed_profile_compiler" \
  FLCLASH_MANAGED_UPDATE_FIXTURE=1 FLCLASH_MANAGED_UPDATE_AVD=1 \
  go -C core test -run '^TestManagedUpdateManualFixture$' -v -timeout 0
```

启动输出 `managed-update-fixture:` 后的一行 JSON，包含 `httpPort`、`dnsA`、`bootstrapDns`、`mixedPort`、`dnsPort`。
最后两个是宿主探针入口端口；夹具等待用户应用提供监听。记录端口后，在第二个终端操作。

1. 用户自行安装/打开 AVD 中的本次 APK。在 Profiles → Add → Import from URL 导入
   `http://10.0.2.2:<httpPort>/profile`，命名为 ouo-local；Request route 选 Direct。
   测试期间关闭 Auto update。
2. Policy draft 中将 Preview listener ports 设为 mixed-port 7890、DNS port 1053。
   新增 DNS 服务：TCP、地址 10.0.2.2、端口为输出的 dnsA；Bootstrap DNS 同地址、端口为 bootstrapDns。
3. Source bindings → Bind source select group → pool；
   再 Bind source domain collection → domains。
   新增域名条目，在 Source collections 选择 domains，target 选择 Proxy group: pool，
   DNS 选择刚建的服务。
   两个未匹配默认都设为 REJECT。Generated draft preview 后 Save and request application，
   选择所需维护目标并确认。
   用户自行启动代理，等待实际配置可用。
4. 用户将夹具的两个探针端口转发到设备监听；替换尖括号端口值。
   这些转发仅供宿主 `/probe` 调用，结束后删除对应转发。

```bash
adb forward tcp:<mixedPort> tcp:7890
adb forward tcp:<dnsPort> tcp:1053
curl 'http://127.0.0.1:<httpPort>/probe?name=a.example.test'
curl 'http://127.0.0.1:<httpPort>/status'
curl 'http://127.0.0.1:<httpPort>/phase/B'
```

回到 App 对 ouo-local 执行 Sync，再以 `b.example.test` 调用 `/probe`。
A 的 `body` 应为 A，B 应为 B，`businessOK` 与 `dnsOK` 都为 true；`/status` 的 proxyB 增加，
proxyA 不再增加，
dnsA 继续作为用户指定的 DNS 接收方。B 改变认证和源组成员，新增 `added.test` 条件；不能只看下载或 YAML 文本。
每次探针用不同域名，避免把缓存命中当成接收方证明。

`/phase/bad` 提供悬空组成员：Sync 应失败，源文件/日期及合资格旧输入保持。
`/phase/rename` 将 pool 改为 renamed-pool：普通 Sync 应拒绝；使用 Load latest material for preview，
在已有来源组上选择 renamed-pool，预览并 Apply 后才采用。试验中也可关闭页面或 Discard preview material，
确认材料没有因为预览而保存。Ctrl-C 结束夹具；删除用户刚创建的两个 `adb forward`。

本地自动化另覆盖提交后的重新解析失败、CAS 冲突、取消和来源票据变化；实际结果见本次交付记录。
夹具 HTTP 阶段和宿主消费者的通过不等于设备、TUN、物理网络或真实订阅兼容通过。
真实 ouo 未由本项拉取，URL/凭据无需加入夹具或报告。
