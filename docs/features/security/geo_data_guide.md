# Geo 固定基线核验指南

固定随包基线及离线核验工具已交付。接受对象与证据边界见[契约](geo_data_design.md)，
实际任务状态见[Loop 6 Tasks](loop6/loop6_tasks.md)。

## 离线核验

命令使用Python 3.11及以上版本的标准库，只读文件并输出JSON，不联网或替换任何资产。
默认参考是此脚本所属仓库的`assets/data/geo_manifest.json`；APK内附带的manifest不充当验证根。

```bash
python3 tool/verify_geo_assets.py
python3 tool/verify_geo_assets.py --apk /absolute/path/to/FlClash.apk
python3 tool/verify_geo_assets.py --home /absolute/path/to/synthetic-home
python3 tool/verify_geo_assets.py --repo /absolute/path/to/alternative-repository
```

成功只表示文件与当前接受参考对应；不证明发布者签名、数据全集分类准确或运行reader已使用这些字节。
错误schema、错误／重复角色映射、缺文件、大小或digest错误应返回非零结果。
兼容名存在多个候选时列出Core规则下的所选路径和冲突，不把旧缓存当成新基线；home参数仅用于显式给定的合成目录。
指定其它repo属于替代参考检查，输出必须明确该参考，不能当成此仓库获审基线。
JSON的`ok`为true时退出码为0，其余为1；`publisher_signature_verified=false`及`runtime_loaded_version=not_observed`保留证据边界。

## 现有English入口

Resources → Geo resources当前显示MMDB、GEOIP、GEOSITE及ASN的大小和修改时间，菜单包含Sync及Edit URL。
Geo options中的Auto update和Auto-update interval控制已有更新路径。
这些入口目前不显示接受的发布身份或loaded版本，不能从成功提示、mtime变化或自定义URL推导已通过发布校验。

随包数据更新只影响缺文件时的seed；已存在私有文件、兼容名及运行缓存不会自动变成新基线。
T02／T03尚未交付，当前工具不能代替运行期更新保护、重载证明或真实路由验收。
Android以外平台共用新随包数据，但未验证其构建或运行保护。

## Android 内置缺失 seed

Android启动时，缺失的标准目标会自动使用[接受基线](geo_data_design.md#android-缺失-seed-核验)核验内置manifest及对应payload，再写入私有目录；无需新开关或额外网络。
已有文件不会被替换或因此获信，全部目标已有时不读取bundle。不要删除用户文件来体验这一功能；开发验证使用临时合成home。

核验失败会在原启动错误路径报告资源／原因，并阻止本次Core init；文件I/O失败保留原系统错误。
维护者先运行上面的离线工具核对资产与已接受来源，检查manifest与代码派生锚是否同步；不要通过改hash绕过错误。
逐文件写入不是整体事务：后项失败时，前项合法文件可能已写入。成功仅说明对应缺失文件按接受参考写入，不证明reader已加载。

手动／自动远端更新、未知缓存／兼容名、热重载／恢复与正式版本展示仍未覆盖；当前Resources时间不是发布身份或实际采用证据。
可运行`flutter test test/core/geo_seed_test.dart test/core/controller_test.dart`验证合成home下的真实controller入口；测试平台缝不代表Android设备运行。
交付状态及实际制品证据见[Loop6 Tasks](loop6/loop6_tasks.md)。
