# Android 应用连接观测验证

此夹具验证实际开发版 APK 的 ServiceState、ConfigInput v2、VPN、Go Core 和 JNI。
只访问宿主的本地回声服务及受控 SOCKS5；不使用真实订阅、外部诊断或遥测。
四个客户端中 a／b 的 UID 不同，shareda／sharedb 使用真实 sharedUserId。
客户端记录自己的 UID、socket 和响应结果，宿主另记实际收到的数据及代理转发，作为独立核对依据。

## 前提与设备影响

先取得使用目标模拟器、临时接管其 VPN 和清理 FlClash 开发版数据的许可。
脚本只接受明确指定的模拟器 serial 与 AVD 名，不接受真机。
每次运行会覆盖安装并清空 com.follow.clash.dev，安装测试客户端与 instrumentation；
结束时停止自己启动的测试进程，保留结果文件，包和数据的最终清理由执行者完成。
不要将脚本指向未经同意的日常实例。

需要已经安装的 Android SDK、JDK 17、ADB、Python，以及标准 Android debug.keystore。
构建不下载新的模拟器镜像，不复制 Gradle home。客户端使用前台服务，避免 Android 的后台冻结
把测试暂停误判成 Core 丢失连接；不会修改系统的后台冻结设置。

## 构建与运行

先按[构建说明](../../../../docs/development/android_build_guide.md)准备工具链、构建缓存与拒绝发布配置，
构建 ARM64 debug APK。APP_ENV=dev，目标包必须为 com.follow.clash.dev。
build_clients 会把测试 APK 副本与 instrumentation 使用同一标准调试密钥重签，保留原构建 APK；
仅签名改变，源码、Dart 与 Native 库内容不变，便于独立于 Gradle 的本地调试密钥位置运行 instrumentation。

```bash
python3 android/tests/device/network_activity/build_clients.py \
  --app build/app/outputs/flutter-apk/app-debug.apk
python3 android/tests/device/network_activity/run_device.py \
  --serial emulator-5554 --avd Pixel_7a_API_34 --count 4 \
  --out build/verification/na-t01-01/device-candidate
```

serial 与 AVD 名替换为已获准实例。若原来安装的是更高版本、不可降级的发行版，
须在已授权清理的前提下移除 com.follow.clash.dev 后再运行；不要移除其它包来绕过安装错误。

instrumentation 通过正式原生接口接受合成来源、注册并采用 ConfigInput，使用正式 VPN 服务。
它不增加生产 RPC、调试导出 Activity 或测试后门，也不绕过接受流程。
它直接记录 JNI 数据，不启动 Flutter UI。Dart 的同一解析／事件分发路径在主机测试中消费这些真实数据：

```bash
FLCLASH_ANDROID_OBSERVATION_EVENTS="$PWD/build/verification/na-t01-01/device-candidate/events.jsonl" \
  flutter test test/models/connection_observation_test.dart
```

这不是三层 UI 的设备验收；页面入口在 03，完整交付在 08。

## 判断结果

- Rule／Global／Direct 均不配置 App 规则，find-process-mode=off；核对唯一 UID 的归属与共享 UID 的歧义。
- 用客户端 socket 与宿主收包核对真实路径，再检查 Core 的 rule、chains 和观测字段。
- Mode 切换后的新记录核对实际采用的 inputId；仍保留的旧记录不得改写。
  配置边界忙或前后不一致时，unknown 计数单列；所有已知版本必须正确，每种模式至少取得已知版本，
  不允许用当前版本补齐未知。
- 短连接回声后立即关闭，必须在事件中存在，并实际覆盖快照中已找不到的 TCP。
- 连接事件与快照对同一 ID 的 observation 一致；Dart 解码与事件分发保留 Native 原值。
- 另测本地 512 KiB TCP 回声有效负载吞吐、Native 进程 CPU、固定负载的 PSS，以及实际 UID／包名查询耗时。
  回声吞吐按单向有效负载字节计算；不把模拟器串行回声或启动耗时当作公网代理吞吐。

build/verification/na-t01-01 下保存 report、facts、events、snapshots、宿主收到的数据及 instrumentation 输出，
均为忽略的本地证据。版本、计数、已知失败及平台限制汇总在[任务 Result](../../../../docs/features/network_activity/na_t01_01_result.md)。

## 基线对照

使用 048e99b 的 parent Go 源码及相同、未修改的 Clash.Meta gitlink，按生产 Android 的
with_gvisor,no_zerotier、ARM64、API 24、c-shared 参数构建；debug 对照不去除符号。
用这个 libclash.so 替换同一开发 APK 副本的唯一对应条目，再 zipalign 和调试签名，得到 baseline.apk。
Kotlin／Dart、客户端、配置和执行参数保持一致；其 find-process-mode=off 不会调用新增包名 JSON 桥接。

```bash
python3 android/tests/device/network_activity/build_clients.py \
  --app build/app/outputs/flutter-apk/app-debug.apk \
  --baseline-core .buildlog/android-build/na-t01-01-baseline-libclash.so
python3 android/tests/device/network_activity/run_device.py \
  --serial emulator-5554 --avd Pixel_7a_API_34 --count 4 --variant baseline \
  --apk build/verification/na-t01-01/baseline.apk \
  --out build/verification/na-t01-01/device-baseline
```

baseline 验证流量与事件路径，明确不要求新增 observation。对照不是旧正式 APK 的完整回归，
只比较本次采集增量。额外维护大缓存、长期压力和真机耗电仍需另行验证。
