# 部分来源配置保留 Plan

基线 2f78082。扩展关联来源部分失败的前台导入和审核，替代原来的仅节点降级；不推进应用网络后续任务。

全部来源首次尝试结束后才允许选择部分配置。成功加载的关联材料保留；声明匹配、许可仍有效的旧快照继续复用。
没有可用正文的来源按依赖处理：移除对应 provider 声明及引用它的业务规则，保留其它规则的原有顺序；
节点来源缺失时清理分组的 use，递归移除确实失去成员的分组及其引用。不得补隐式 DIRECT。
缺失内容涉及 DNS、sniffer、listener、tunnel、默认出口或无法可靠处理的复杂依赖时，明确列出阻塞位置。

部分配置先展示停用来源、规则和分组及保留的默认出口，再通过原来源接受、材料提交与完整 ConfigInput 路径审核、保存。
成功的 provider 正文只在本次操作内传递，在新的配置上下文重新核验；不是新授权或持久缓存。
保留订阅 URL，关闭部分快照的自动刷新；手动更新仍从原 URL 获取完整配置。自动刷新失败不自行删除规则。
保存待补齐仍只限新导入；取消、失败和过期不能改变旧材料或当前选择。

先维护本文及当前契约的 draft，再实现 Go 纯投影、Dart 编排和审核反馈，最后同步有效设计与使用说明。
受影响当前文档为 source_acceptance_design.md、source_acceptance_guide.md 和 .agents/architecture.md；
原 partial_import_plan/result 保留历史。本次验证结果回填本文，不另建任务清单。

验证覆盖规则源失败、节点源失败、旧正文复用、默认出口和 DNS 依赖阻塞、全部尝试完成前禁用接受、
成功正文不重复下载、二次审核取消、保存及离线重建；使用本地合成服务及真实 Dart→Go 桥接。
运行相关 Go/Flutter 测试、静态检查和生成器，构建并覆盖安装到已运行 AVD，保留应用数据。

## 实施与验证结果

Go 的 previewPartialConfiguration 负责无副作用的缺失依赖投影。
Dart 的 ProfileReviewContext 仅保存本次操作的正文，供派生配置重新核验；
原 SourceAcceptance、RequestSession、材料提交和 ConfigInput 继续负责许可与生效。
原仅节点投影及其测试已移除，改由原配置的规则、分组和 DNS 保留验证覆盖。

- 最终定向 Flutter：67 通过；包含全部尝试完成前禁止接受、独立重试及阻塞项展示。
- 真实 Dart→Go 桥接全文件：61 通过、19 跳过；跳过项缺少受管编译器测试环境。
  其中 7 项新导入／已有订阅审核用例全部通过，覆盖取消、首次默认选择、规则保留、
  成功来源仅下载一次、已有订阅部分更新、离线重建及恢复完整 URL 配置。
- Go 定向：8 个顶层测试通过，含子用例共 15 项；go vet 通过。
- 跨语言协议：10 通过。pub get 锁文件不变；生成器完成。
- analyze：无 error／warning，42 项继承 info。
- 扩展探索回归首轮：2472 通过、100 跳过、8 失败。
  本次新增 UI 测试的 ProviderScope／尺寸夹具已修正并在最终定向集通过；
  其它失败涉及未改动的 DAV 本地服务夹具及未完成测试、update_dialog 的
  RequestUnavailable 夹具、design_package 对 bootstrap_test 的旧导入约束。
  未宣称扩展全集通过，也未扩大范围修改这些测试。
- Go 全集的 ZeroTier checkpoint、ProviderStageRetirement 两项失败，
  使用基线源码的 Go overlay 单独重现；不是本次投影导致。
- Markdown 改动行无新增违规；其它位置 759 项继承违规未批量整理。

Android ARM64 debug 最终构建 13.8 秒，无 File modified during build 提示。
签名校验通过，已用保留数据的 replacement install 安装到 emulator-5554，
并确认已安装 base.apk 与构建 APK 的 SHA256 一致：

```text
10f3792570bc13cca1ce5a6218cc7f30f50cf8f88a37170f4099bb38c5f98926
```

生产源文件摘要与安装绑定保留在本地忽略目录
build/verification/partial-configuration/source-binding.json；
原始检查日志位于 .buildlog/android-build/partial-config-*。
没有导出 Downloads，没有操作用户订阅或切换设备代理。
复杂逻辑 RuleSet／sub-rules、关键 DNS 引用和无法证明成员的筛选组仍明确阻塞部分接受；
真实私有订阅和真机网络连通性不属于本轮合成数据验证结论。
