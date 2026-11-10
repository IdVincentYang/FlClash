# 取消审核误报与 URL 导入选项（2026-11-10）

Add profile → URL 的 Advanced configuration 改为直接显示请求方式及相关选项，不提供折叠按钮。其它页面保留原来的折叠行为。

经用户同意，在 emulator-5554 只打开 BGY 的 Review source 并取消，未接受来源或操作代理开关。进入前卡片没有 Review required，取消后出现了该提示，随后已返回 Dashboard，界面仍显示 Stop。审核列出了 55 个关联来源，其中多项显示 The selected request route is unavailable；这说明本次关联材料加载存在问题，不能作为订阅内容变化的证据，也未据此修改请求路径。

本次确认了一条误报路径：审核窗口关闭后，其 currentness guard 先失效，SourceAcceptance 在清理候选前检查该 guard，提前退出。Core 留存的强制审核候选被后续状态查询计入待审。此观察不能穷尽 BGY 历史上每次待审的原因；实际内容、关联来源或许可变化仍可能需要审核，审核许可本身没有按几分钟定时过期的逻辑。

修复让中止的交互审核按候选 token 清理自己的待审记录；自动更新的真实候选继续保留，较新候选也不会被旧窗口的取消操作删除。已经展示审核时，调用方等清理完成后再刷新状态；准备阶段尚未展示审核的取消仍及时返回。没有新增接受许可或应用配置的路径。职责见[架构说明](../../../.agents/architecture.md)。

验证：真实 Dart→Go 页面回归覆盖“既有已接受订阅 → 打开审核 → 取消 → 状态恢复正常”，并比较许可文件及配置 fence 不变；并发新候选场景确认取消旧审核后仍显示待审。来源、导入、页面、widgets、本地化和 lint 合并回归 669 项通过、19 项跳过，5 项既有失败仍为更新说明夹具 3 项、macOS 编辑器动态库 LINKEDIT 加载 1 项、test/bootstrap_test.dart 的 Material 导入 1 项。静态分析无错误、无警告，保留既有 42 条 info；依赖、生成及 diff 空白检查通过。

ARM64 Release 已生成并通过 APK v2 签名校验，包名 com.follow.clash.dev，版本 0.8.99，versionCode 2026113007。制品为 build/app/outputs/flutter-apk/app-arm64-v8a-release.apk，SHA256 为 a57aaa091621ebb60c8dfe0f8e1de75c31bbdb3d85148890853063a09e10ac9d。构建后只读检查仍有前台 ProxyService 运行。用户明确同意立即安装后，通过 adb install -r 保留数据覆盖安装；设备记录 lastUpdateTime 为 2026-11-10 16:28:46，firstInstallTime 仍为 2026-11-04 21:11:29。安装后未代替用户打开应用、接受来源或启动代理。没有创建 Loop 验证副本。
