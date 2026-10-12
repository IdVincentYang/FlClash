# Loop 5：Android 构建链与第三方依赖

目标是核实 Flutter Engine、Android SDK/NDK、Gradle、插件和 Maven 等依赖是否来自各自官方发布渠道，确保实际工具选择与构建声明对应，同时核验 Android 核心嵌入的 EasyTier WASM、ZeroTier 根节点数据等运行资产的来源和生成关系，建立固定版本、完整性验证及组件清单，使 Android 发布物能追溯到被审源码、依赖、工具和嵌入资产。对应[审计基线](../android_security_baseline.md) A-08、A-09、A-14。

进入本 loop 时再细化方案和验收。
