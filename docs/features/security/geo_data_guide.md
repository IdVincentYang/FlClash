# Geo 固定基线核验指南

L6-T01固定基线及核验工具已通过M实现评审，**待本地交付及M收尾**。接受对象与证据边界见[契约](geo_data_design.md)，
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
