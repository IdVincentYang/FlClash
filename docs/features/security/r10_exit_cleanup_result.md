# R10 exit cleanup Result

对象为 `security/android` 上以 `5d16bb9` 为父基线的 R10 交付改动。
首轮实现证据已冻结；实现评审 I1 已复现、修订并自验，M 实现复审通过。
本记录随实现纳入本地 fixup，最终版本由包含本文件的提交标识，Issue 关闭及任务文档清理由 M 负责。
范围和顺序见 [Plan](r10_exit_cleanup_plan.md)，长期边界见
[Application exit](../../../.agents/architecture.md)及[来源提交契约](source_acceptance_design.md)。

## 实际验证

| 对象 | 结果与边界 |
| --- | --- |
| 实际 SystemAction／Request → Go registry | 32 项通过，覆盖退出入口、真实保存、提交 admission、错误、attachment 交错、撤权和 watchdog。 |
| 受影响 Flutter 回归 | 12 个文件共 182 pass，0 fail／skip；包含上述 32 项，不另外相加。 |
| Go wrapper（沿用首轮） | CGO_ENABLED=0；444 个顶层 test 通过，683 个含 subtest 的 pass events、40 个既有 skip；host vet 通过；本次 Go 源码及桥二进制未变。 |
| 静态检查 | pub get offline、Dart format、Flutter analyze 通过；analyze 保留原 42 条 info，没有新增 error／warning／info。 |

修复前使用相同的首批 10 项业务断言，1 pass／9 fail。
该对象仍是原 cleanup 控制流，仅增加 pass-through 依赖入口以接入 host 的真实消费者；
preflight 失败跳过保存／其它收尾，正常路径无 receipt，以及 fault／未知写者未得到应有失败反馈的反例均已暴露。
补证先确认真实 Core 在 detach 后即使 lock 成功，beginCommit 仍返回 request_cancelled，
没有沿用被否定的 retained client 方案。首轮另有 18 项覆盖 attachment、队列、BootGuard IO 和 watchdog；
I1 本轮再增加 4 项，具体边界如下。

正常退出和纯 prepare／detach 控制通道异常、提交资格仍有效时，实际 config 保存一次；
原 client 的 lock → beginCommit → complete 在 native detach 之前完成。
fault 与真实退休的未知写者则拒绝提交，保存被尝试而写动作为零，恢复 marker 不被清除。
退出 needSave=false 不申请写资格，即使无 client 或 fault 仍完成其它允许收尾。

quiesce 撤销已有 session，拒绝之后新 begin，也拒绝串行队列或 inspect／begin await 中的旧 begin。
prepare、lock、beginCommit 期间新 attach，以及排队提交期间新 attach，均使旧保存与 final detach 失效：
新 client／clientReady 保留，旧退出不调用针对新 owner 的 detach。
已授予的旧 receipt 仍完成自己的清理，unknown writer 计数归零，不撤销新 attachment；
其恢复 marker 仍保留，不能把新 client／clientReady 存在当作业务已恢复。
重复 detach、attach 失败后退出及从未 attach 的 Android 保存不走无 receipt 降级。

原第一 error 的对象和 StackTrace 保留，额外 tray／DNS／proxy 和 detach 失败按步骤可观察；
preferences 保存失败仍完成自己的 receipt 并尝试 detach。
BootGuard close IO 失败的用例确认内存许可已撤销、关闭调用一次，但记录没有被假报为 durable closed。
prepare 或保存挂起时，独立资源已开始收尾；watchdog 与恢复后的正常路径共享一次 application exit，
没有第二次保存／detach。其余 window／Core 关闭在正常 cleanup 返回后继续。

## I1 写前窗口修订

Bootstrap 启动前已等待 preferences 初始化；再次 await 同一个已完成 Future 仍会让出执行权。
反例先确认 isCompleted 与 isInit=true，仅在 Future getter 安排 microtask 执行真实 Request.attach／ready，
仍返回原已完成 Future，不延迟初始化或改写 Core readiness。
首轮实现在 beginCommit 后、setString 前被新 attachment 替换，仍写入一次，违反写前失效契约。
相同测试正文修复前 1 fail（预期 0／实际 1），修复后 1 pass（写入 0 次），新 client 保持 attached／ready，
旧 final detach 不触及新 owner，其它资源和退出一次均完成。

Preferences.prepareConfigWriter 只异步取得存储句柄，SystemAction 在进入 commit 前等待其准备。
commit 内读取最新 Config 并直接调用准备好的写入口，从 owner 检查到 setString 无 await；
原 saveConfig 调用者复用同一存储准备能力，缺失存储仍反馈 preferences_save_failed。
新增断言确认串行队列期间修改的配置被保存，桌面 geometry 与原 saveConfig 回归继续通过。
最小化仍沿用同一 best-effort 调用路径，本轮未操作实际桌面窗口。

对于 setString 已被调用后才发生的新 attach，测试观察写入仅一次；旧 receipt 仍以原 client 完成，
真实 unknown writer 从 1 归零，恢复 marker 保留，新 client／ready 不被旧 final detach 撤销。
这与写前替换零写入的反例分开，不把已进入 action 或取得 receipt 当作存储写入已开始。

## 复现与证据

真实 Go gate 通过既有 PolicyCoreBridge／TestApplicationInputBridge 接入；requestControl 直接转发生产 registry。
测试桥仅增加 fault 注入和状态观测，未知写者由真实 lock／beginCommit／detach 产生，
clientReady 使用实际 attach／ready；没有修改 Core 生产、JNI、gitlink 或 carrier。

在仓库根目录使用新输出目录，先生成桥再运行入口：

```bash
mkdir -p .buildlog/r10-repro
(cd core && CGO_ENABLED=0 go test -c -o ../.buildlog/r10-repro/core-bridge.exec .)
FLCLASH_EXIT_CORE_BRIDGE="$PWD/.buildlog/r10-repro/core-bridge.exec" \
  flutter test --no-pub test/providers/system_exit_cleanup_bridge_test.dart
```

首轮 11 文件选集、命令／输入和输出绑定保存在本地、未入库目录
`.buildlog/r10-exit-cleanup-20261116/implementation/` 的 source manifest，保持冻结。
有效 before 为 `before-02/` 与 `flutter-before-02.log`，最终回归为 `flutter-final-03.log`，
Go 结果为 `go-root-final-01.jsonl`、`go-vet.log`；最终源码与 bridge executable 由同一 manifest 绑定。
最早一次 before 有 Preferences 初始化夹具错误，修复初始化后取得上述有效反例；原失败保留。
首次 analyze 的两条新增测试提示已修正；初轮 161 项及中间 bridge 结果保留，不充当最终 165 项的输入版本。

I1 本轮源码、相同反例正文及未变桥二进制绑定见本地、未入库目录
`.buildlog/r10-exit-cleanup-20261116/revision-02/` 的 source manifest。
`before-i1/`／`flutter-before-i1.log` 是 1 fail 反例，`flutter-after-i1.log` 为同一反例 1 pass，
`counterexample-binding.json` 确认正文相同；`flutter-final.jsonl` 为最终 12 文件 182 pass。
首轮有效的 Go／vet 及 JNI 未变边界沿用，不重新编译桥或重跑未变矩阵。

## 收尾自验与证据复用

相对获审 revision-02，唯一代码整理是退出 detach closure 直接委托 _detach：
后者已同步核对同一 client／revision，删除重复检查和 async 包装不改变 owner 边界。
其余代码／测试与获审快照相同；Plan／Result 仅更新真实评审和交付状态。
整理后三个受影响文件选集共 69 pass、0 fail／skip，包含全部 32 项退出 bridge 测试及 Request receipt／scope。
重新 analyze 仍为原 42 条 info，无新增问题；格式、Markdown／链接、注释密度及 diff 检查通过。
上表 182 项对应获审 revision-02，收尾仅重验该等价整理的影响范围；未变的 pub get、其它回归和 Go 证据沿用。
最终纳入范围、获审至交付差异及提交对应保存在本地、未入库目录
`.buildlog/r10-exit-cleanup-20261116/delivery/`，冻结的 revision-02 证据保持原样。

## 限制

service 控制异常、BootGuard IO、系统资源和进程出口是受控叶子；preferences 使用测试 SharedPreferences，
Go receipt／marker 与 client 检查为生产实现，不能据此声称真实 Android 存储、JNI、TUN 或设备已验证。
紧急 exit 不表示保存或 native detach 已完成；物理写入已开始后也不声称可强制撤销。
没有绕过 fault／未知写者或清除原恢复责任；未改退出 coordinator、非退出无 client 策略、R11 或 F01。
未跑完整 Flutter 或未变 JNI／Android 矩阵；没有 APK、设备、main 合入或远端操作。
