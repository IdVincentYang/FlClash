// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a zh_CN locale. All the
// messages from the main program should be duplicated here with the same
// function name.

// Ignore issues from commonly used lints in this file.
// ignore_for_file:unnecessary_brace_in_string_interps, unnecessary_new
// ignore_for_file:prefer_single_quotes,comment_references, directives_ordering
// ignore_for_file:annotate_overrides,prefer_generic_function_type_aliases
// ignore_for_file:unused_import, file_names, avoid_escaping_inner_quotes
// ignore_for_file:unnecessary_string_interpolations, unnecessary_string_escapes

import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'zh_CN';

  static String m0(active, count) => "活跃 ${active}/${count}";

  static String m1(id) => "连接 ${id}";

  static String m2(active, count) => "活跃 ${active} · 近期 ${count} 次连接";

  static String m3(time) => "最近活动：${time}";

  static String m4(ip, country) => "本机公网 IP（最近检测）：${ip} · ${country}";

  static String m5(count) => "展开其余 ${count} 个地址";

  static String m6(ip, country) => "代理服务器：${ip} · ${country}，不代表网站看到的出口。";

  static String m7(count) => "本次运行 · 最近 ${count} 条已观察连接";

  static String m8(rules, exits) => "${rules} 种规则结果 · ${exits} 种出口";

  static String m9(uid) => "UID ${uid}";

  static String m10(count, skipped) => "将添加 ${count} 项，跳过 ${skipped} 项已存在";

  static String m11(phase) => "上次阶段：${phase}";

  static String m12(reason) => "系统退出原因：${reason}";

  static String m13(code) =>
      "Windows 拒绝运行 FlClashCore.exe（错误 ${code}）。智能应用控制、AppLocker 等应用控制策略会拦截未签名程序，请在该策略中放行 FlClash 或关闭策略后重试。";

  static String m14(name) =>
      "系统报告上次启动期间异常退出。当时的配置为 ${name}。本次跳过自动配置，当前选择和文件均已保留。";

  static String m15(url) => "是否要通过 ${url} 创建配置？";

  static String m16(count) => "${count} 天前";

  static String m17(reason) => "延迟测试未完成：${reason}";

  static String m18(label) => "确定删除选中的${label}吗？";

  static String m19(label) => "确定删除当前${label}吗？";

  static String m20(label) => "${label}详情";

  static String m21(label) => "${label}不能为空";

  static String m22(label) => "${label}当前已存在";

  static String m23(name) => "${name} 已是最新版本";

  static String m24(name) => "${name} 已更新";

  static String m25(action) => "已被“${action}”使用，保存后将移到这里";

  static String m26(modifiers) => "至少包含 ${modifiers} 中的一个";

  static String m27(count) => "${count} 小时前";

  static String m28(count) => "${count} 小时";

  static String m29(target) => "${target} 是一个无效的策略";

  static String m30(proxyName) => "${proxyName} 是一个无效的代理";

  static String m31(providerName) => "${providerName} 是一个无效的代理集";

  static String m32(ruleSet) => "${ruleSet} 不是有效的规则集";

  static String m33(subRule) => "${subRule} 是一个无效的SUB_RULE";

  static String m34(line, message) => "第 ${line} 行：${message}";

  static String m35(name) => "${name} 的操作";

  static String m36(name) => "实际出口：${name}";

  static String m37(name) => "删除全局分组“${name}”及其订阅引用？";

  static String m38(name) => "订阅“${name}”正在使用此分组，请先在那里选择其他节点。";

  static String m39(name) => "节点已不可用：${name}";

  static String m40(count) => "${count} 个节点";

  static String m41(name) => "首选节点：${name}";

  static String m42(count) => "已加入 ${count} 个分组";

  static String m43(name) => "${name}";

  static String m44(appName) =>
      "1. 打开 系统设置 > 隐私与安全性\n2. 选择 定位服务\n3. 在右侧列表中找到并勾选 ${appName}\n\n完成设置后，返回应用即可正常使用。感谢您的配合。";

  static String m45(label, max) => "${label}最多${max}个字符";

  static String m46(size) => "已释放 ${size}";

  static String m47(count) => "${count} 分钟前";

  static String m48(count) => "${count} 个月前";

  static String m49(code) => "服务器拒绝访问（HTTP ${code}），链接可能已过期或凭据有误";

  static String m50(code) => "服务器拒绝了请求（HTTP ${code}）";

  static String m51(code) => "该地址下没有内容（HTTP ${code}），请确认链接是否正确";

  static String m52(detail) => "网络请求失败：${detail}";

  static String m53(code) => "服务器出现问题（HTTP ${code}），请稍后再试";

  static String m54(label) => "暂无${label}";

  static String m55(label) => "${label}必须为数字";

  static String m56(message) => "内核无法解析该代理：${message}";

  static String m57(name) => "名称 ${name} 已被其他代理或策略组使用";

  static String m58(path) => "策略组之间存在循环引用：${path}";

  static String m59(names) => "以下代理集不存在：${names}";

  static String m60(names) => "以下代理或策略不存在：${names}";

  static String m61(name) => "${name} 是内置策略名，不能在此使用";

  static String m62(names) => "配置文件自身的策略组引用了自定义代理中已没有的代理：${names}";

  static String m63(count) => "${count} 项存在问题，应用覆写可能失败";

  static String m64(location) => "请检查 ${location}，补齐或修正后才能预览。";

  static String m65(locations) => "资源被以下位置引用：${locations}。请先修改引用再删除。";

  static String m66(label) => "${label} 必须在 1024 到 49151 之间";

  static String m67(label, profiles) =>
      "${label} 仍被 ${profiles} 的自定义策略组或规则使用，请先在那里移除";

  static String m68(profiles, label) =>
      "${profiles} 的订阅里已有 ${label}，改名后这些配置会改用订阅里的那个，请换一个名称";

  static String m69(count) => "${count} 个代理";

  static String m70(host) => "当前配置无法获取此对象。是否允许本次操作直连 ${host}？许可在操作结束或来源变化后失效。";

  static String m71(target) => "GLOBAL（当前选择：${target}）";

  static String m72(count) => "${count} 条规则";

  static String m73(appName) => "${appName}（安全模式）";

  static String m74(count) => "${count} 秒";

  static String m75(count) => "已选择 ${count} 项";

  static String m76(time) => "检测于 ${time}";

  static String m77(region) => "检测报告地区：${region}";

  static String m78(milliseconds) => "总耗时（含排队及正文）：${milliseconds} ms";

  static String m79(result) => "已过期：${result}";

  static String m80(hosts) => "接收方：${hosts}";

  static String m81(label) => "${label}只能是一项";

  static String m82(features) => "已接受的声明能力：${features}";

  static String m83(services) => "已接受的 DNS 范围：${services}";

  static String m84(protocols) => "已接受的节点协议：${protocols}";

  static String m85(count) => "已接受版本数：${count}";

  static String m86(features) => "声明的能力：${features}";

  static String m87(target) => "来源默认出口：${target}";

  static String m88(ready, total) => "已就绪：${ready}/${total}";

  static String m89(nodes, rules) => "来源材料：${nodes} 个节点，${rules} 条规则";

  static String m90(services) => "拟用 DNS 服务：${services}";

  static String m91(protocols) => "节点协议：${protocols}";

  static String m92(count) => "关联数据源：${count} 个";

  static String m93(targets) =>
      "委托的代理规则块：${targets}。条件可覆盖任意域名或 IP；固定保护与默认出口保持不变，可能扩大 DIRECT 的删除仍需审查。";

  static String m94(label) => "${label}必须为URL";

  static String m95(count) => "${count} 年前";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "about": MessageLookupByLibrary.simpleMessage("关于"),
    "accessControl": MessageLookupByLibrary.simpleMessage("访问控制"),
    "accessControlAllowDesc": MessageLookupByLibrary.simpleMessage(
      "只允许选中应用进入VPN",
    ),
    "accessControlDesc": MessageLookupByLibrary.simpleMessage("配置应用访问代理"),
    "accessControlDisabledDesc": MessageLookupByLibrary.simpleMessage(
      "应用访问控制已关闭",
    ),
    "accessControlNotAllowDesc": MessageLookupByLibrary.simpleMessage(
      "选中应用将会被排除在VPN之外",
    ),
    "accessControlSettings": MessageLookupByLibrary.simpleMessage("访问控制设置"),
    "account": MessageLookupByLibrary.simpleMessage("账号"),
    "action": MessageLookupByLibrary.simpleMessage("操作"),
    "actionDelayTest": MessageLookupByLibrary.simpleMessage("测试全部延迟"),
    "actionDirectMode": MessageLookupByLibrary.simpleMessage("直连模式"),
    "actionGlobalMode": MessageLookupByLibrary.simpleMessage("全局模式"),
    "actionMode": MessageLookupByLibrary.simpleMessage("切换模式"),
    "actionProxy": MessageLookupByLibrary.simpleMessage("系统代理"),
    "actionRuleMode": MessageLookupByLibrary.simpleMessage("规则模式"),
    "actionStart": MessageLookupByLibrary.simpleMessage("启动/停止"),
    "actionTun": MessageLookupByLibrary.simpleMessage("虚拟网卡"),
    "actionUpdateProfiles": MessageLookupByLibrary.simpleMessage("更新全部配置"),
    "actionView": MessageLookupByLibrary.simpleMessage("显示/隐藏"),
    "activityActive": MessageLookupByLibrary.simpleMessage("当前活跃"),
    "activityActiveFilterUnavailable": MessageLookupByLibrary.simpleMessage(
      "暂时无法确认活跃状态，显示已保留的目标。",
    ),
    "activityAllApps": MessageLookupByLibrary.simpleMessage("全部应用"),
    "activityAllAppsForTarget": MessageLookupByLibrary.simpleMessage(
      "查看所有应用对此目标的连接",
    ),
    "activityCatalogueUnavailable": MessageLookupByLibrary.simpleMessage(
      "应用目录不可用，仍显示已观察活动。",
    ),
    "activityChecking": MessageLookupByLibrary.simpleMessage("正在确认活跃连接…"),
    "activityCompactCounts": m0,
    "activityConfiguration": MessageLookupByLibrary.simpleMessage("连接采用的配置"),
    "activityConnectionEnded": MessageLookupByLibrary.simpleMessage("已结束"),
    "activityConnectionId": m1,
    "activityConnectionIdLabel": MessageLookupByLibrary.simpleMessage("连接 ID"),
    "activityConnectionState": MessageLookupByLibrary.simpleMessage("连接状态"),
    "activityConnectionsUnconfirmed": MessageLookupByLibrary.simpleMessage(
      "活动状态暂无法确认，显示保留的连接。",
    ),
    "activityCounts": m2,
    "activityExcludedSetting": MessageLookupByLibrary.simpleMessage(
      "当前设置：排除此应用",
    ),
    "activityExits": MessageLookupByLibrary.simpleMessage("实际出口路径"),
    "activityFewerAddresses": MessageLookupByLibrary.simpleMessage("收起地址"),
    "activityIdentityUncertain": MessageLookupByLibrary.simpleMessage(
      "无法确定所属应用",
    ),
    "activityIncludedSetting": MessageLookupByLibrary.simpleMessage(
      "当前设置：接管此应用",
    ),
    "activityIncomplete": MessageLookupByLibrary.simpleMessage("观察记录可能不完整"),
    "activityLast": m3,
    "activityLastLabel": MessageLookupByLibrary.simpleMessage("最近活动"),
    "activityLoadingApps": MessageLookupByLibrary.simpleMessage("正在读取应用名称…"),
    "activityLocalPublicCountry": m4,
    "activityMoreAddresses": m5,
    "activityNoActive": MessageLookupByLibrary.simpleMessage("暂无已确认的活跃连接"),
    "activityNoMatches": MessageLookupByLibrary.simpleMessage("没有匹配的应用"),
    "activityNoObserved": MessageLookupByLibrary.simpleMessage("尚无已观察活动"),
    "activityNoTargetMatches": MessageLookupByLibrary.simpleMessage("没有匹配的目标"),
    "activityObservationScope": MessageLookupByLibrary.simpleMessage("观察范围"),
    "activityObservedAddresses": MessageLookupByLibrary.simpleMessage(
      "已观察到的目标地址",
    ),
    "activityObservedDownload": MessageLookupByLibrary.simpleMessage("已观察下载"),
    "activityObservedUpload": MessageLookupByLibrary.simpleMessage("已观察上传"),
    "activityObserving": MessageLookupByLibrary.simpleMessage("正在观察 VPN 活动"),
    "activityOnlyActiveConnections": MessageLookupByLibrary.simpleMessage(
      "仅显示活跃连接",
    ),
    "activityOnlyActiveTargets": MessageLookupByLibrary.simpleMessage(
      "仅显示活跃目标",
    ),
    "activityPaused": MessageLookupByLibrary.simpleMessage("观察已暂停 · 保留近期活动"),
    "activityPending": MessageLookupByLibrary.simpleMessage("待确认"),
    "activityProxyServerAddress": MessageLookupByLibrary.simpleMessage(
      "代理服务器地址",
    ),
    "activityProxyServerCountry": m6,
    "activityRecent": MessageLookupByLibrary.simpleMessage("近期活动"),
    "activityRetention": m7,
    "activityRouteCounts": m8,
    "activityRules": MessageLookupByLibrary.simpleMessage("实际命中规则"),
    "activityRulesBypassed": MessageLookupByLibrary.simpleMessage(
      "全局或直连模式未使用分流规则",
    ),
    "activityScopeHelp": MessageLookupByLibrary.simpleMessage(
      "这里只展示 FlClash 已观察到的流量。次数表示保留的连接数，不是 HTTP 请求数或完整历史。记录仅在内存中，进程重启后重新累计。后台挂起、事件传递缺口或保留上限可能导致遗漏。当前接管设置不代表运行中的 VPN 已采用这些设置。",
    ),
    "activitySearchApps": MessageLookupByLibrary.simpleMessage("搜索应用名称或包名"),
    "activitySearchTargets": MessageLookupByLibrary.simpleMessage(
      "搜索域名或 IP 地址",
    ),
    "activitySharedIdentityHelp": MessageLookupByLibrary.simpleMessage(
      "这些应用共享同一个 UID，无法确定连接由其中哪个应用发起。",
    ),
    "activitySharedUid": MessageLookupByLibrary.simpleMessage("共享应用身份"),
    "activityShowAllApps": MessageLookupByLibrary.simpleMessage("显示全部应用"),
    "activitySnapshotFailed": MessageLookupByLibrary.simpleMessage(
      "刷新失败 · 活跃状态待确认",
    ),
    "activityUid": m9,
    "activityUnknownApp": MessageLookupByLibrary.simpleMessage("未知应用"),
    "activityUnknownTarget": MessageLookupByLibrary.simpleMessage("未知目标"),
    "activityVpnObserved": MessageLookupByLibrary.simpleMessage(
      "这些连接有 VPN 接管记录",
    ),
    "add": MessageLookupByLibrary.simpleMessage("添加"),
    "addCustomProxy": MessageLookupByLibrary.simpleMessage("添加代理"),
    "addOverrideEntry": MessageLookupByLibrary.simpleMessage("添加覆写项"),
    "addProfile": MessageLookupByLibrary.simpleMessage("添加配置"),
    "addProxies": MessageLookupByLibrary.simpleMessage("添加代理"),
    "addProxyGroup": MessageLookupByLibrary.simpleMessage("添加策略组"),
    "addProxyProviders": MessageLookupByLibrary.simpleMessage("添加代理集"),
    "addRule": MessageLookupByLibrary.simpleMessage("添加规则"),
    "addSsid": MessageLookupByLibrary.simpleMessage("添加SSID"),
    "addWidget": MessageLookupByLibrary.simpleMessage("添加组件"),
    "addedRules": MessageLookupByLibrary.simpleMessage("附加规则"),
    "additionalParameters": MessageLookupByLibrary.simpleMessage("附加参数"),
    "address": MessageLookupByLibrary.simpleMessage("地址"),
    "addressHelp": MessageLookupByLibrary.simpleMessage("WebDAV服务器地址"),
    "addressTip": MessageLookupByLibrary.simpleMessage("请输入有效的WebDAV地址"),
    "advancedConfig": MessageLookupByLibrary.simpleMessage("进阶配置"),
    "advancedConfigDesc": MessageLookupByLibrary.simpleMessage(
      "网络、DNS、附加规则与脚本",
    ),
    "agree": MessageLookupByLibrary.simpleMessage("同意"),
    "allowBypass": MessageLookupByLibrary.simpleMessage("允许应用绕过VPN"),
    "allowLan": MessageLookupByLibrary.simpleMessage("局域网代理"),
    "androidServiceProxyOnly": MessageLookupByLibrary.simpleMessage("仅代理服务"),
    "androidServiceStopped": MessageLookupByLibrary.simpleMessage("已停止"),
    "androidServiceStopping": MessageLookupByLibrary.simpleMessage("正在停止服务"),
    "androidServiceSuspended": MessageLookupByLibrary.simpleMessage("已暂停"),
    "androidServiceTitle": MessageLookupByLibrary.simpleMessage("Android 服务"),
    "androidServiceUnavailable": MessageLookupByLibrary.simpleMessage("服务不可用"),
    "androidServiceVpnActive": MessageLookupByLibrary.simpleMessage("VPN 已启动"),
    "answers": MessageLookupByLibrary.simpleMessage("应答"),
    "app": MessageLookupByLibrary.simpleMessage("应用"),
    "appAccessControl": MessageLookupByLibrary.simpleMessage("应用访问控制"),
    "appIconDesign": MessageLookupByLibrary.simpleMessage("应用图标设计"),
    "appendSystemDns": MessageLookupByLibrary.simpleMessage("追加系统DNS"),
    "applicationNetwork": MessageLookupByLibrary.simpleMessage("应用网络"),
    "appliedProfile": MessageLookupByLibrary.simpleMessage("实际生效配置"),
    "authentication": MessageLookupByLibrary.simpleMessage("认证"),
    "authenticationDesc": MessageLookupByLibrary.simpleMessage(
      "为本地代理端口启用认证，防止本机其他应用擅自使用",
    ),
    "authenticationSystemProxyDesc": MessageLookupByLibrary.simpleMessage(
      "认证启用时不生效",
    ),
    "authorize": MessageLookupByLibrary.simpleMessage("授权"),
    "authorized": MessageLookupByLibrary.simpleMessage("已授权"),
    "auto": MessageLookupByLibrary.simpleMessage("自动"),
    "autoCloseConnections": MessageLookupByLibrary.simpleMessage("自动关闭连接"),
    "autoCloseConnectionsDesc": MessageLookupByLibrary.simpleMessage(
      "切换节点后自动关闭连接",
    ),
    "autoLaunch": MessageLookupByLibrary.simpleMessage("自启动"),
    "autoLaunchDesc": MessageLookupByLibrary.simpleMessage("跟随系统自启动"),
    "autoRun": MessageLookupByLibrary.simpleMessage("自动运行"),
    "autoRunDesc": MessageLookupByLibrary.simpleMessage("应用打开时自动运行"),
    "autoSetSystemDns": MessageLookupByLibrary.simpleMessage("自动设置系统DNS"),
    "autoUpdate": MessageLookupByLibrary.simpleMessage("自动更新"),
    "autoUpdateInterval": MessageLookupByLibrary.simpleMessage("自动更新间隔（分钟）"),
    "back": MessageLookupByLibrary.simpleMessage("返回"),
    "backgroundStartFailed": MessageLookupByLibrary.simpleMessage(
      "FlClash 未启动。请打开应用，处理待审核来源或查看错误。",
    ),
    "backup": MessageLookupByLibrary.simpleMessage("备份"),
    "backupAndRestore": MessageLookupByLibrary.simpleMessage("备份与恢复"),
    "backupAndRestoreDesc": MessageLookupByLibrary.simpleMessage(
      "通过WebDAV或者文件同步数据",
    ),
    "backupFromNewerVersion": MessageLookupByLibrary.simpleMessage(
      "该备份来自更高版本的应用，请先更新应用再恢复",
    ),
    "backupSuccess": MessageLookupByLibrary.simpleMessage("备份成功"),
    "basicInfo": MessageLookupByLibrary.simpleMessage("基础信息"),
    "basicStrategy": MessageLookupByLibrary.simpleMessage("基础策略"),
    "batchAdd": MessageLookupByLibrary.simpleMessage("批量添加"),
    "batchListInputTip": MessageLookupByLibrary.simpleMessage("每行一项，也可用逗号分隔"),
    "batchMapInputTip": MessageLookupByLibrary.simpleMessage("每行一条，键和值之间用空格分隔"),
    "batchPreviewTip": m10,
    "batteryOptimizationDesc": MessageLookupByLibrary.simpleMessage(
      "为保证后台运行，请关闭本应用的电池优化。点击前往设置。",
    ),
    "batteryOptimizationStatusTip": MessageLookupByLibrary.simpleMessage(
      "由于系统限制，运行状态下无法正确获取电池优化状态",
    ),
    "behavior": MessageLookupByLibrary.simpleMessage("行为"),
    "bind": MessageLookupByLibrary.simpleMessage("绑定"),
    "blacklistMode": MessageLookupByLibrary.simpleMessage("黑名单模式"),
    "blockConnection": MessageLookupByLibrary.simpleMessage("阻止连接"),
    "bootExitAnr": MessageLookupByLibrary.simpleMessage("应用无响应"),
    "bootExitCrash": MessageLookupByLibrary.simpleMessage("应用崩溃"),
    "bootExitInitialization": MessageLookupByLibrary.simpleMessage("进程初始化失败"),
    "bootExitNativeCrash": MessageLookupByLibrary.simpleMessage("原生崩溃"),
    "bootPhaseBootstrap": MessageLookupByLibrary.simpleMessage("准备应用"),
    "bootPhaseCore": MessageLookupByLibrary.simpleMessage("连接 Core"),
    "bootPhaseRecovery": MessageLookupByLibrary.simpleMessage("恢复提示"),
    "bootPhaseSetup": MessageLookupByLibrary.simpleMessage("初始化配置"),
    "bootRecordDamaged": MessageLookupByLibrary.simpleMessage(
      "启动保护记录已损坏，本次跳过自动配置。是否仅重建这条记录？也可保留原记录并继续。订阅、设置和诊断文件均会保留。",
    ),
    "bootRecordKeep": MessageLookupByLibrary.simpleMessage("保留并继续"),
    "bootRecordNewer": MessageLookupByLibrary.simpleMessage(
      "启动记录使用了更新的格式，将保留原记录。本次跳过自动配置，你仍可手动使用应用。",
    ),
    "bootRecordRebuild": MessageLookupByLibrary.simpleMessage("重建启动记录"),
    "bootRecordUnavailable": MessageLookupByLibrary.simpleMessage(
      "启动保护记录无法读取或保存，本次跳过自动配置。现有服务和文件均已保留，手动操作仍然可用。",
    ),
    "bootRecoveryPhase": m11,
    "bootRecoveryReason": m12,
    "bootRecoveryRepeated": MessageLookupByLibrary.simpleMessage(
      "启动已连续中断，建议到配置列表检查或重新选择配置，再手动启动。",
    ),
    "bypassDomain": MessageLookupByLibrary.simpleMessage("排除域名"),
    "bypassDomainDesc": MessageLookupByLibrary.simpleMessage("仅在系统代理启用时生效"),
    "cache": MessageLookupByLibrary.simpleMessage("缓存"),
    "cacheAlgorithm": MessageLookupByLibrary.simpleMessage("缓存算法"),
    "cacheCorrupt": MessageLookupByLibrary.simpleMessage("缓存已损坏，是否清空？"),
    "cacheMaxSize": MessageLookupByLibrary.simpleMessage("缓存大小"),
    "cameraPermissionDesc": MessageLookupByLibrary.simpleMessage(
      "请在系统设置中允许访问相机以扫描二维码，或从相册选择二维码图片。",
    ),
    "cameraPermissionRequired": MessageLookupByLibrary.simpleMessage("需要相机权限"),
    "cameraUnavailable": MessageLookupByLibrary.simpleMessage("相机不可用"),
    "cancel": MessageLookupByLibrary.simpleMessage("取消"),
    "cancelSelectAll": MessageLookupByLibrary.simpleMessage("取消全选"),
    "changeProxyFailedTip": MessageLookupByLibrary.simpleMessage(
      "切换代理失败，已恢复上一次的选择",
    ),
    "changelogBreaking": MessageLookupByLibrary.simpleMessage("重大变更"),
    "changelogFeatures": MessageLookupByLibrary.simpleMessage("新功能"),
    "changelogFixes": MessageLookupByLibrary.simpleMessage("问题修复"),
    "changelogPerformance": MessageLookupByLibrary.simpleMessage("性能优化"),
    "changelogReverts": MessageLookupByLibrary.simpleMessage("已回滚"),
    "checkCertificate": MessageLookupByLibrary.simpleMessage("校验 TLS 证书"),
    "checkCertificateDesc": MessageLookupByLibrary.simpleMessage(
      "拒绝不受信任的证书。关闭后订阅和备份将暴露于中间人攻击",
    ),
    "checkUpdate": MessageLookupByLibrary.simpleMessage("检查更新"),
    "checkUpdateError": MessageLookupByLibrary.simpleMessage("当前应用已经是最新版了"),
    "clearData": MessageLookupByLibrary.simpleMessage("清除数据"),
    "clearSearch": MessageLookupByLibrary.simpleMessage("清除搜索"),
    "clipboardExport": MessageLookupByLibrary.simpleMessage("导出剪贴板"),
    "clipboardImport": MessageLookupByLibrary.simpleMessage("剪贴板导入"),
    "clipboardWriteFailed": MessageLookupByLibrary.simpleMessage(
      "无法复制到剪贴板，所选内容可能过大",
    ),
    "close": MessageLookupByLibrary.simpleMessage("关闭"),
    "closeConnections": MessageLookupByLibrary.simpleMessage("关闭连接"),
    "color": MessageLookupByLibrary.simpleMessage("颜色"),
    "colorSchemes": MessageLookupByLibrary.simpleMessage("配色方案"),
    "columns": MessageLookupByLibrary.simpleMessage("列数"),
    "compatible": MessageLookupByLibrary.simpleMessage("兼容模式"),
    "configApplying": MessageLookupByLibrary.simpleMessage("正在应用配置"),
    "configDataDetected": MessageLookupByLibrary.simpleMessage("检测到配置中存在数据"),
    "configInactive": MessageLookupByLibrary.simpleMessage("当前未接管流量"),
    "configLoaded": MessageLookupByLibrary.simpleMessage("已载入配置，尚未接管流量"),
    "configRetained": MessageLookupByLibrary.simpleMessage("新配置未应用，仍使用之前的配置"),
    "confirm": MessageLookupByLibrary.simpleMessage("确定"),
    "confirmClearAllData": MessageLookupByLibrary.simpleMessage("确定要清除所有数据？"),
    "confirmDeleteProxyGroup": MessageLookupByLibrary.simpleMessage(
      "确定要删除当前策略组吗？",
    ),
    "confirmExitWindow": MessageLookupByLibrary.simpleMessage("确定要退出当前窗口吗？"),
    "confirmForceCrashCore": MessageLookupByLibrary.simpleMessage("确定要强制崩溃核心？"),
    "confirmOverwriteTip": MessageLookupByLibrary.simpleMessage("确定后将会覆盖已有数据"),
    "connected": MessageLookupByLibrary.simpleMessage("已连接"),
    "connecting": MessageLookupByLibrary.simpleMessage("连接中…"),
    "connection": MessageLookupByLibrary.simpleMessage("连接"),
    "connections": MessageLookupByLibrary.simpleMessage("连接"),
    "connectivity": MessageLookupByLibrary.simpleMessage("连通性："),
    "content": MessageLookupByLibrary.simpleMessage("内容"),
    "contentNotEmpty": MessageLookupByLibrary.simpleMessage("内容不能为空"),
    "contentScheme": MessageLookupByLibrary.simpleMessage("内容主题"),
    "controlGlobalAddedRules": MessageLookupByLibrary.simpleMessage("控制全局附加规则"),
    "copy": MessageLookupByLibrary.simpleMessage("复制"),
    "copyEnvVar": MessageLookupByLibrary.simpleMessage("复制环境变量"),
    "copyLink": MessageLookupByLibrary.simpleMessage("复制链接"),
    "copySuccess": MessageLookupByLibrary.simpleMessage("复制成功"),
    "core": MessageLookupByLibrary.simpleMessage("内核"),
    "coreBlockedByPolicyTip": m13,
    "coreBlockedBySmartAppControlTip": MessageLookupByLibrary.simpleMessage(
      "Windows 智能应用控制拦截了未签名的 FlClashCore.exe。请打开 Windows 安全中心 → 应用和浏览器控制 → 智能应用控制设置，选择「关闭」后重新启动 FlClash。智能应用控制关闭后无法再开启，除非重装 Windows。",
    ),
    "coreStatus": MessageLookupByLibrary.simpleMessage("核心状态"),
    "country": MessageLookupByLibrary.simpleMessage("区域"),
    "crashDetected": MessageLookupByLibrary.simpleMessage("检测到崩溃"),
    "crashDetectedTip": m14,
    "crashTest": MessageLookupByLibrary.simpleMessage("崩溃测试"),
    "create": MessageLookupByLibrary.simpleMessage("创建"),
    "createProfileFromUrlTip": m15,
    "creationTime": MessageLookupByLibrary.simpleMessage("创建时间"),
    "custom": MessageLookupByLibrary.simpleMessage("自定义"),
    "customProxiesEmpty": MessageLookupByLibrary.simpleMessage(
      "未添加自定义代理，沿用配置文件自身的代理",
    ),
    "cut": MessageLookupByLibrary.simpleMessage("剪切"),
    "dark": MessageLookupByLibrary.simpleMessage("深色"),
    "dashboard": MessageLookupByLibrary.simpleMessage("仪表盘"),
    "dataChangedSave": MessageLookupByLibrary.simpleMessage("检测到数据有更改，是否保存"),
    "databaseWriteFailedTip": MessageLookupByLibrary.simpleMessage(
      "保存更改失败，已回滚",
    ),
    "daysAgo": m16,
    "defaultText": MessageLookupByLibrary.simpleMessage("默认"),
    "delay": MessageLookupByLibrary.simpleMessage("延迟"),
    "delayTest": MessageLookupByLibrary.simpleMessage("延迟测试"),
    "delayTestFailed": m17,
    "delayTestNoResult": MessageLookupByLibrary.simpleMessage(
      "核心未返回测试结果，请确认代理已连接后重试。",
    ),
    "delayTestRequiresProxy": MessageLookupByLibrary.simpleMessage(
      "请先启动代理，连接成功后再测试节点延迟。",
    ),
    "delayTestUnavailable": MessageLookupByLibrary.simpleMessage("不可测试"),
    "delayTestWaiting": MessageLookupByLibrary.simpleMessage("等待测试"),
    "delayTestWaitingResult": MessageLookupByLibrary.simpleMessage("等待测试结果"),
    "delete": MessageLookupByLibrary.simpleMessage("删除"),
    "deleteMultipTip": m18,
    "deleteTip": m19,
    "desc": MessageLookupByLibrary.simpleMessage(
      "基于ClashMeta的多平台代理客户端，简单易用，开源无广告。",
    ),
    "destination": MessageLookupByLibrary.simpleMessage("目标地址"),
    "destinationGeoIP": MessageLookupByLibrary.simpleMessage("目标地理定位"),
    "destinationIPASN": MessageLookupByLibrary.simpleMessage("目标IP ASN"),
    "details": m20,
    "detectionTip": MessageLookupByLibrary.simpleMessage("依赖第三方api，仅供参考"),
    "developerMode": MessageLookupByLibrary.simpleMessage("开发者模式"),
    "developerModeEnableTip": MessageLookupByLibrary.simpleMessage("开发者模式已启用。"),
    "dialerProxy": MessageLookupByLibrary.simpleMessage("拨号代理"),
    "dialerProxyDesc": MessageLookupByLibrary.simpleMessage("用于连接NTP服务器的出站"),
    "direct": MessageLookupByLibrary.simpleMessage("直连"),
    "disableUDP": MessageLookupByLibrary.simpleMessage("禁用UDP"),
    "disabled": MessageLookupByLibrary.simpleMessage("已关闭"),
    "discardChanges": MessageLookupByLibrary.simpleMessage("是否放弃更改？"),
    "disconnected": MessageLookupByLibrary.simpleMessage("已断开"),
    "discoverNewVersion": MessageLookupByLibrary.simpleMessage("发现新版本"),
    "dnsHijacking": MessageLookupByLibrary.simpleMessage("DNS劫持"),
    "dnsMode": MessageLookupByLibrary.simpleMessage("DNS模式"),
    "dnsQueries": MessageLookupByLibrary.simpleMessage("DNS查询"),
    "docked": MessageLookupByLibrary.simpleMessage("固定"),
    "domain": MessageLookupByLibrary.simpleMessage("域名"),
    "download": MessageLookupByLibrary.simpleMessage("下载"),
    "edit": MessageLookupByLibrary.simpleMessage("编辑"),
    "editGlobalRules": MessageLookupByLibrary.simpleMessage("编辑全局规则"),
    "editProxy": MessageLookupByLibrary.simpleMessage("编辑代理"),
    "editProxyGroup": MessageLookupByLibrary.simpleMessage("编辑策略组"),
    "editRule": MessageLookupByLibrary.simpleMessage("编辑规则"),
    "editSsid": MessageLookupByLibrary.simpleMessage("编辑SSID"),
    "editorUnavailable": MessageLookupByLibrary.simpleMessage("编辑器不可用"),
    "emptyTip": m21,
    "en": MessageLookupByLibrary.simpleMessage("英语"),
    "enabled": MessageLookupByLibrary.simpleMessage("已开启"),
    "entries": MessageLookupByLibrary.simpleMessage("个条目"),
    "error": MessageLookupByLibrary.simpleMessage("错误"),
    "exclude": MessageLookupByLibrary.simpleMessage("从最近任务中隐藏"),
    "excludeDesc": MessageLookupByLibrary.simpleMessage("应用在后台时，从最近任务中隐藏应用"),
    "excludeProxyFilter": MessageLookupByLibrary.simpleMessage("排除节点过滤器"),
    "excludeSsids": MessageLookupByLibrary.simpleMessage("排除SSIDs"),
    "excludeSsidsDesc": MessageLookupByLibrary.simpleMessage(
      "连接到被排除SSID的WIFI时，将会自动切换应用运行状态",
    ),
    "excludeType": MessageLookupByLibrary.simpleMessage("排除类型"),
    "existsTip": m22,
    "exit": MessageLookupByLibrary.simpleMessage("退出"),
    "exitFullScreen": MessageLookupByLibrary.simpleMessage("退出全屏"),
    "expand": MessageLookupByLibrary.simpleMessage("标准"),
    "expectedStatus": MessageLookupByLibrary.simpleMessage("预期状态"),
    "expireTime": MessageLookupByLibrary.simpleMessage("到期时间"),
    "exportFile": MessageLookupByLibrary.simpleMessage("导出文件"),
    "exportLogs": MessageLookupByLibrary.simpleMessage("导出日志"),
    "exportSuccess": MessageLookupByLibrary.simpleMessage("导出成功"),
    "expressiveScheme": MessageLookupByLibrary.simpleMessage("表现力"),
    "externalController": MessageLookupByLibrary.simpleMessage("外部控制器"),
    "externalControllerDesc": MessageLookupByLibrary.simpleMessage(
      "开启后将可以通过9090端口控制Clash内核",
    ),
    "externalLink": MessageLookupByLibrary.simpleMessage("外部链接"),
    "extraLarge": MessageLookupByLibrary.simpleMessage("超大"),
    "fade": MessageLookupByLibrary.simpleMessage("淡入"),
    "fakeipFilter": MessageLookupByLibrary.simpleMessage("Fake-IP过滤"),
    "fakeipFilterMode": MessageLookupByLibrary.simpleMessage("Fake-IP过滤模式"),
    "fakeipFilterModeDesc": MessageLookupByLibrary.simpleMessage(
      "blacklist排除匹配项，whitelist仅用于匹配项，rule按规则匹配",
    ),
    "fakeipRange": MessageLookupByLibrary.simpleMessage("Fake-IP范围"),
    "fakeipRange6": MessageLookupByLibrary.simpleMessage("Fake-IP范围（IPv6）"),
    "fakeipTtl": MessageLookupByLibrary.simpleMessage("Fake-IP TTL"),
    "fallbackFilter": MessageLookupByLibrary.simpleMessage("Fallback过滤"),
    "fidelityScheme": MessageLookupByLibrary.simpleMessage("高保真"),
    "file": MessageLookupByLibrary.simpleMessage("文件"),
    "fileDesc": MessageLookupByLibrary.simpleMessage("直接上传配置文件"),
    "fileIsUpdate": MessageLookupByLibrary.simpleMessage("文件有修改，是否保存修改"),
    "filter": MessageLookupByLibrary.simpleMessage("筛选"),
    "findProcessMode": MessageLookupByLibrary.simpleMessage("查找进程"),
    "floating": MessageLookupByLibrary.simpleMessage("悬浮"),
    "followProfile": MessageLookupByLibrary.simpleMessage("跟随配置"),
    "followSystem": MessageLookupByLibrary.simpleMessage("跟随系统"),
    "fontFamily": MessageLookupByLibrary.simpleMessage("字体"),
    "fontSize": MessageLookupByLibrary.simpleMessage("大小"),
    "forceRestartCoreTip": MessageLookupByLibrary.simpleMessage("您确定要强制重启核心吗？"),
    "format": MessageLookupByLibrary.simpleMessage("格式"),
    "fruitSaladScheme": MessageLookupByLibrary.simpleMessage("果缤纷"),
    "general": MessageLookupByLibrary.simpleMessage("常规"),
    "geoAutoUpdate": MessageLookupByLibrary.simpleMessage("自动更新"),
    "geoAutoUpdateInterval": MessageLookupByLibrary.simpleMessage("自动更新间隔"),
    "geoAutoUpdateIntervalTip": MessageLookupByLibrary.simpleMessage(
      "自动更新间隔必须大于0",
    ),
    "geoOptions": MessageLookupByLibrary.simpleMessage("Geo 选项"),
    "geoResourceAsnAbout": MessageLookupByLibrary.simpleMessage(
      "查询 IP 地址所属的自治系统编号（ASN）及运营组织，例如互联网运营商或云服务网络。供 IP-ASN 和 SRC-IP-ASN 规则使用。",
    ),
    "geoResourceGeoipAbout": MessageLookupByLibrary.simpleMessage(
      "以 .dat 格式按国家或地区组织 IP 网段。开启 Geo 数据模式时供 GEOIP 规则使用；另一模式使用 MMDB 数据库。",
    ),
    "geoResourceGeositeAbout": MessageLookupByLibrary.simpleMessage(
      "将域名按服务、地区等类别分组，供 GEOSITE 规则及支持此分类的 DNS 设置匹配域名。",
    ),
    "geoResourceMmdbAbout": MessageLookupByLibrary.simpleMessage(
      "将 IP 地址映射为国家或地区代码，供 GEOIP 规则及部分 DNS 判断使用。在 Geo 数据模式关闭时使用；FlClash 中此项指 MaxMind DB 格式的国家或地区数据库。",
    ),
    "geoResources": MessageLookupByLibrary.simpleMessage("Geo 资源"),
    "geoSkipped": m23,
    "geoUpdated": m24,
    "geodataLoader": MessageLookupByLibrary.simpleMessage("Geo低内存模式"),
    "global": MessageLookupByLibrary.simpleMessage("全局"),
    "go": MessageLookupByLibrary.simpleMessage("前往"),
    "goDownload": MessageLookupByLibrary.simpleMessage("前往下载"),
    "goToConfigureScript": MessageLookupByLibrary.simpleMessage("前往配置脚本"),
    "hasCacheChange": MessageLookupByLibrary.simpleMessage("是否缓存修改"),
    "helperCorruptTip": MessageLookupByLibrary.simpleMessage(
      "Helper 服务不可用，无法启用 TUN 模式，请重新安装 FlClash。",
    ),
    "hideFromList": MessageLookupByLibrary.simpleMessage("从列表中隐藏"),
    "hideIp": MessageLookupByLibrary.simpleMessage("隐藏 IP"),
    "hidePassword": MessageLookupByLibrary.simpleMessage("隐藏密码"),
    "hideTimeoutProxies": MessageLookupByLibrary.simpleMessage("隐藏超时节点"),
    "hideTimeoutProxiesDesc": MessageLookupByLibrary.simpleMessage(
      "不显示上次延迟测试超时的节点",
    ),
    "host": MessageLookupByLibrary.simpleMessage("主机"),
    "hotkeyConflictWith": m25,
    "hotkeyDesc": MessageLookupByLibrary.simpleMessage(
      "全局快捷键在窗口隐藏时依然生效，点击操作即可录制组合键。",
    ),
    "hotkeyManagement": MessageLookupByLibrary.simpleMessage("快捷键管理"),
    "hotkeyNeedsModifier": m26,
    "hotkeyNotSet": MessageLookupByLibrary.simpleMessage("未设置"),
    "hotkeyUnavailable": MessageLookupByLibrary.simpleMessage(
      "未能注册，可能已被其他应用占用",
    ),
    "hours": MessageLookupByLibrary.simpleMessage("小时"),
    "hoursAgo": m27,
    "hoursCount": m28,
    "icon": MessageLookupByLibrary.simpleMessage("图片"),
    "iconRecords": MessageLookupByLibrary.simpleMessage("图标记录"),
    "iconStyle": MessageLookupByLibrary.simpleMessage("图标样式"),
    "iconStyleFilled": MessageLookupByLibrary.simpleMessage("色块"),
    "iconStyleHidden": MessageLookupByLibrary.simpleMessage("隐藏"),
    "iconStylePlain": MessageLookupByLibrary.simpleMessage("纯图标"),
    "iconUrl": MessageLookupByLibrary.simpleMessage("图标链接"),
    "ignoreBatteryOptimization": MessageLookupByLibrary.simpleMessage("忽略电池优化"),
    "import": MessageLookupByLibrary.simpleMessage("导入"),
    "importFile": MessageLookupByLibrary.simpleMessage("通过文件导入"),
    "importFromURL": MessageLookupByLibrary.simpleMessage("从URL导入"),
    "importUrl": MessageLookupByLibrary.simpleMessage("通过URL导入"),
    "inbound": MessageLookupByLibrary.simpleMessage("入站"),
    "includeAllProxies": MessageLookupByLibrary.simpleMessage("包含所有代理"),
    "includeAllProxiesTip": MessageLookupByLibrary.simpleMessage(
      "引入不包含策略组的所有代理，可在下方额外添加策略组",
    ),
    "includeAllProxyProviders": MessageLookupByLibrary.simpleMessage("包含所有代理集"),
    "includeAllProxyProvidersTip": MessageLookupByLibrary.simpleMessage(
      "开启后包含本配置的全部代理集：订阅自带的，以及任一策略组引用的配置和应用代理集",
    ),
    "infiniteTime": MessageLookupByLibrary.simpleMessage("长期有效"),
    "init": MessageLookupByLibrary.simpleMessage("初始化"),
    "initiator": MessageLookupByLibrary.simpleMessage("发起方"),
    "inputProxyGroupName": MessageLookupByLibrary.simpleMessage("输入策略组名称"),
    "inputRuleContent": MessageLookupByLibrary.simpleMessage("输入规则内容"),
    "installedAppsPermissionDeniedMessage":
        MessageLookupByLibrary.simpleMessage(
          "读取应用列表权限已被拒绝，无法获取已安装的应用。请前往系统设置手动开启。",
        ),
    "installedAppsPermissionDesc": MessageLookupByLibrary.simpleMessage(
      "当前系统在授权前不会提供已安装的应用列表，授权后即可配置分应用代理。",
    ),
    "installedAppsPermissionRequired": MessageLookupByLibrary.simpleMessage(
      "需要读取应用列表权限",
    ),
    "intelligentSelected": MessageLookupByLibrary.simpleMessage("智能选择"),
    "interfaceName": MessageLookupByLibrary.simpleMessage("网卡名称"),
    "interfaceNameDesc": MessageLookupByLibrary.simpleMessage("出站连接使用的网卡名称"),
    "interfaceNameMode": MessageLookupByLibrary.simpleMessage("出站网卡"),
    "interfaceNameModeClear": MessageLookupByLibrary.simpleMessage("清空"),
    "interfaceNameModeCustom": MessageLookupByLibrary.simpleMessage("自定义"),
    "interfaceNameModeFollow": MessageLookupByLibrary.simpleMessage("跟随配置"),
    "internet": MessageLookupByLibrary.simpleMessage("互联网"),
    "interval": MessageLookupByLibrary.simpleMessage("间隔"),
    "intranetIP": MessageLookupByLibrary.simpleMessage("内网 IP"),
    "invalidBackupFile": MessageLookupByLibrary.simpleMessage("无效备份文件"),
    "invalidDscpContent": MessageLookupByLibrary.simpleMessage(
      "DSCP 标记不能超过 63",
    ),
    "invalidNetworkContent": MessageLookupByLibrary.simpleMessage(
      "仅支持 tcp 或 udp",
    ),
    "invalidPolicy": m29,
    "invalidProfileQrcode": MessageLookupByLibrary.simpleMessage(
      "该二维码不包含配置文件链接",
    ),
    "invalidProxy": m30,
    "invalidProxyProvider": m31,
    "invalidRangeContent": MessageLookupByLibrary.simpleMessage(
      "请输入数字或范围，如 80 或 8000-9000，多个用 / 分隔",
    ),
    "invalidRuleSet": m32,
    "invalidSubRule": m33,
    "ipAddress": MessageLookupByLibrary.simpleMessage("IP 地址"),
    "ipAsn": MessageLookupByLibrary.simpleMessage("ASN"),
    "ipClassificationDisclosure": MessageLookupByLibrary.simpleMessage(
      "点击查询将通过 HTTPS 把此 IP 交给 proxycheck.io 分类。该服务也能看到请求自身的出口 IP，两者可能不同。匿名每日限额 100 次，代理出口可能被拒；拒绝后不会直连或换源。缺字段为未知，分类不保证安全。请求关闭可选的阳性检测面板保存，不代表服务端完全不记录日志。",
    ),
    "ipClassificationStart": MessageLookupByLibrary.simpleMessage("查询此 IP 的分类"),
    "ipFlagAnonymous": MessageLookupByLibrary.simpleMessage("匿名服务检测"),
    "ipFlagCompromised": MessageLookupByLibrary.simpleMessage("被攻陷标记"),
    "ipFlagHosting": MessageLookupByLibrary.simpleMessage("托管检测"),
    "ipFlagProxy": MessageLookupByLibrary.simpleMessage("代理"),
    "ipFlagScraper": MessageLookupByLibrary.simpleMessage("抓取服务检测"),
    "ipFlagTor": MessageLookupByLibrary.simpleMessage("Tor"),
    "ipFlagVpn": MessageLookupByLibrary.simpleMessage("VPN"),
    "ipFlags": MessageLookupByLibrary.simpleMessage("命中标记"),
    "ipLookupAutomatic": MessageLookupByLibrary.simpleMessage("仪表盘自动查询"),
    "ipLookupBodyLimit": MessageLookupByLibrary.simpleMessage("响应超限"),
    "ipLookupCancelled": MessageLookupByLibrary.simpleMessage("查询已取消"),
    "ipLookupCheckedAt": MessageLookupByLibrary.simpleMessage("观测时间"),
    "ipLookupDisclosure": MessageLookupByLibrary.simpleMessage(
      "通过 HTTPS 向 Cloudflare 查询本次请求出口和国家。自动查询仅在应用前台、显示仪表盘且服务运行时执行。单次观测不代表所有网站出口。",
    ),
    "ipLookupDisplayOnly": MessageLookupByLibrary.simpleMessage(
      "仅控制显示；复制使用原 IP，此设置不会阻止联网查询。",
    ),
    "ipLookupHttpFailed": MessageLookupByLibrary.simpleMessage("来源拒绝请求"),
    "ipLookupInvalid": MessageLookupByLibrary.simpleMessage("响应无效或不完整"),
    "ipLookupIpMismatch": MessageLookupByLibrary.simpleMessage("响应 IP 不匹配"),
    "ipLookupManual": MessageLookupByLibrary.simpleMessage("查询出口 IP"),
    "ipLookupNotChecked": MessageLookupByLibrary.simpleMessage("尚未查询"),
    "ipLookupRoutes": MessageLookupByLibrary.simpleMessage("当前规则"),
    "ipLookupSourceWarning": MessageLookupByLibrary.simpleMessage(
      "来源警告：已返回结果，但可能涉及限额或访问限制。",
    ),
    "ipLookupStale": MessageLookupByLibrary.simpleMessage("历史观测"),
    "ipLookupTlsFailed": MessageLookupByLibrary.simpleMessage("证书校验失败"),
    "ipLookupWaiting": MessageLookupByLibrary.simpleMessage("等待 30 秒查询间隔"),
    "ipOrganization": MessageLookupByLibrary.simpleMessage("组织"),
    "ipQualityFailed": MessageLookupByLibrary.simpleMessage("类型查询失败"),
    "ipQualityRetry": MessageLookupByLibrary.simpleMessage("重新查询"),
    "ipQualitySource": MessageLookupByLibrary.simpleMessage("采用来源"),
    "ipQualitySources": MessageLookupByLibrary.simpleMessage("各来源"),
    "ipSourceIpMismatch": MessageLookupByLibrary.simpleMessage("出站 IP 不一致"),
    "ipSourceNoType": MessageLookupByLibrary.simpleMessage("无法判定类型"),
    "ipSourceRateLimited": MessageLookupByLibrary.simpleMessage("限流"),
    "ipType": MessageLookupByLibrary.simpleMessage("类型"),
    "ipTypeBusiness": MessageLookupByLibrary.simpleMessage("商业"),
    "ipTypeHosting": MessageLookupByLibrary.simpleMessage("机房"),
    "ipTypeResidential": MessageLookupByLibrary.simpleMessage("住宅"),
    "ipTypeWireless": MessageLookupByLibrary.simpleMessage("无线（蜂窝或卫星）"),
    "ipv6Desc": MessageLookupByLibrary.simpleMessage("开启后将可以接收IPv6流量"),
    "ipv6InboundDesc": MessageLookupByLibrary.simpleMessage("允许IPv6入站"),
    "ipv6Timeout": MessageLookupByLibrary.simpleMessage("IPv6超时（毫秒）"),
    "ja": MessageLookupByLibrary.simpleMessage("日语"),
    "justNow": MessageLookupByLibrary.simpleMessage("刚刚"),
    "keepAliveIntervalDesc": MessageLookupByLibrary.simpleMessage("TCP保持活动间隔"),
    "key": MessageLookupByLibrary.simpleMessage("键"),
    "language": MessageLookupByLibrary.simpleMessage("语言"),
    "large": MessageLookupByLibrary.simpleMessage("大"),
    "lastUpdated": MessageLookupByLibrary.simpleMessage("上次更新"),
    "launchInterrupted": MessageLookupByLibrary.simpleMessage("启动未完成"),
    "launchInterruptedTip": MessageLookupByLibrary.simpleMessage(
      "上次启动未完成，原因未知。本次跳过自动配置，当前选择和文件均已保留，你可以手动启动。",
    ),
    "layout": MessageLookupByLibrary.simpleMessage("布局"),
    "light": MessageLookupByLibrary.simpleMessage("浅色"),
    "lineIssueTip": m34,
    "lineWrap": MessageLookupByLibrary.simpleMessage("自动换行"),
    "list": MessageLookupByLibrary.simpleMessage("列表"),
    "listen": MessageLookupByLibrary.simpleMessage("监听"),
    "listenRoutingMark": MessageLookupByLibrary.simpleMessage("监听路由标记"),
    "listenRoutingMarkDesc": MessageLookupByLibrary.simpleMessage("仅Linux有效"),
    "liveConnections": MessageLookupByLibrary.simpleMessage("实时连接"),
    "loading": MessageLookupByLibrary.simpleMessage("加载中…"),
    "local": MessageLookupByLibrary.simpleMessage("本地"),
    "localCrashReports": MessageLookupByLibrary.simpleMessage("本地故障报告"),
    "localGroupsActions": m35,
    "localGroupsActualExit": m36,
    "localGroupsAmbiguous": MessageLookupByLibrary.simpleMessage(
      "所选节点在多个来源中重名，请选择名称可区分的节点，以免选错出口。",
    ),
    "localGroupsApplyFailed": MessageLookupByLibrary.simpleMessage(
      "分组变更未能应用，请检查配置后重试。",
    ),
    "localGroupsApplying": MessageLookupByLibrary.simpleMessage("正在应用配置…"),
    "localGroupsAutomatic": MessageLookupByLibrary.simpleMessage("测速优先"),
    "localGroupsChanged": MessageLookupByLibrary.simpleMessage(
      "配置已变化，请刷新分组管理后重试。",
    ),
    "localGroupsCreate": MessageLookupByLibrary.simpleMessage("新建分组"),
    "localGroupsDelete": m37,
    "localGroupsDisable": MessageLookupByLibrary.simpleMessage("禁用"),
    "localGroupsDownloading": MessageLookupByLibrary.simpleMessage("正在下载来源更新…"),
    "localGroupsEmpty": MessageLookupByLibrary.simpleMessage(
      "选择当前订阅的节点，创建自己的分组。",
    ),
    "localGroupsEnable": MessageLookupByLibrary.simpleMessage("启用"),
    "localGroupsEnableSpeedTest": MessageLookupByLibrary.simpleMessage(
      "启用速度测试",
    ),
    "localGroupsFallback": MessageLookupByLibrary.simpleMessage("故障转移"),
    "localGroupsForegroundRequired": MessageLookupByLibrary.simpleMessage(
      "此修改需要完整应用配置，请回到应用前台后重试。",
    ),
    "localGroupsGlobal": MessageLookupByLibrary.simpleMessage("全局自建分组"),
    "localGroupsIdentitySection": MessageLookupByLibrary.simpleMessage("基本信息"),
    "localGroupsInUse": MessageLookupByLibrary.simpleMessage(
      "请先选择其它节点或分组，再取消此引用、禁用或删除此组。",
    ),
    "localGroupsInUseProfile": m38,
    "localGroupsIndependent": MessageLookupByLibrary.simpleMessage("仅独立显示"),
    "localGroupsInvalidParent": MessageLookupByLibrary.simpleMessage(
      "请选择可用的手动分组，或选择仅独立显示。",
    ),
    "localGroupsInvalidTestUrl": MessageLookupByLibrary.simpleMessage(
      "请输入有效的 HTTP(S) 测速地址。",
    ),
    "localGroupsLimit": MessageLookupByLibrary.simpleMessage("分组或成员数量超出限制。"),
    "localGroupsLoadFailed": MessageLookupByLibrary.simpleMessage(
      "无法读取已保存的分组，请重试。",
    ),
    "localGroupsLoadFirst": MessageLookupByLibrary.simpleMessage(
      "请先使用此订阅并完成来源审核，以加载可选节点。",
    ),
    "localGroupsManaged": MessageLookupByLibrary.simpleMessage(
      "此配置请在策略草稿中管理分组。",
    ),
    "localGroupsManual": MessageLookupByLibrary.simpleMessage("手动"),
    "localGroupsMembersRequired": MessageLookupByLibrary.simpleMessage(
      "请至少选择一个可用节点。",
    ),
    "localGroupsMissing": m39,
    "localGroupsNameConflict": MessageLookupByLibrary.simpleMessage(
      "请使用未被节点或其他分组占用的名称。",
    ),
    "localGroupsNoEntrance": MessageLookupByLibrary.simpleMessage(
      "当前配置没有可选择的路由入口。",
    ),
    "localGroupsNoMatchingNodes": MessageLookupByLibrary.simpleMessage(
      "当前订阅中没有匹配的节点。",
    ),
    "localGroupsNoSaved": MessageLookupByLibrary.simpleMessage(
      "还没有自建分组，请先在分组管理中新建。",
    ),
    "localGroupsNodeCount": m40,
    "localGroupsNodesSection": MessageLookupByLibrary.simpleMessage("节点"),
    "localGroupsOwn": MessageLookupByLibrary.simpleMessage("自建"),
    "localGroupsParent": MessageLookupByLibrary.simpleMessage("加入分组的可选项"),
    "localGroupsPending": MessageLookupByLibrary.simpleMessage("已保存，正在等待应用。"),
    "localGroupsPreferred": m41,
    "localGroupsPreparing": MessageLookupByLibrary.simpleMessage("正在检查已保存配置…"),
    "localGroupsPreparingSources": MessageLookupByLibrary.simpleMessage(
      "正在校验已保存的来源文件…",
    ),
    "localGroupsReferenceAdded": MessageLookupByLibrary.simpleMessage(
      "已加入可选列表",
    ),
    "localGroupsReferenceNotAdded": MessageLookupByLibrary.simpleMessage("未加入"),
    "localGroupsReferenceUsing": MessageLookupByLibrary.simpleMessage("正在使用"),
    "localGroupsReferences": m42,
    "localGroupsReferencesSaved": MessageLookupByLibrary.simpleMessage(
      "引用已生效，各分组的当前选择已保留。",
    ),
    "localGroupsRegex": MessageLookupByLibrary.simpleMessage("节点正则表达式（可选）"),
    "localGroupsRegexDocs": MessageLookupByLibrary.simpleMessage("正则语法帮助"),
    "localGroupsRegexHelp": MessageLookupByLibrary.simpleMessage(
      "匹配节点默认选中，可继续手工调整。",
    ),
    "localGroupsRouteThis": MessageLookupByLibrary.simpleMessage("管理分组引用"),
    "localGroupsSaving": MessageLookupByLibrary.simpleMessage("正在检查并保存分组…"),
    "localGroupsScope": m43,
    "localGroupsSearch": MessageLookupByLibrary.simpleMessage("搜索节点"),
    "localGroupsSelectNodeHelp": MessageLookupByLibrary.simpleMessage(
      "点击节点即可切换，无需保存。",
    ),
    "localGroupsSource": MessageLookupByLibrary.simpleMessage("订阅分组（只读）"),
    "localGroupsSourceUnavailable": MessageLookupByLibrary.simpleMessage(
      "当前已审核配置或来源许可不可用，请在订阅中检查来源权限。",
    ),
    "localGroupsStrategyHelp": MessageLookupByLibrary.simpleMessage(
      "开启：按测速选择；关闭：按 Core 默认顺序故障转移。两种方式都会自动检查可用性。",
    ),
    "localGroupsStrategySection": MessageLookupByLibrary.simpleMessage("切换策略"),
    "localGroupsSubscription": MessageLookupByLibrary.simpleMessage("订阅"),
    "localGroupsTitle": MessageLookupByLibrary.simpleMessage("分组管理"),
    "localGroupsTransientHelp": MessageLookupByLibrary.simpleMessage(
      "点击节点用于当前运行；检测到故障后自动迁移，不保存这次手选。",
    ),
    "localGroupsUnavailable": MessageLookupByLibrary.simpleMessage(
      "该分组尚未运行，请启用或等待配置准备完成。",
    ),
    "localGroupsUnbound": MessageLookupByLibrary.simpleMessage("尚未加入此订阅"),
    "localGroupsUse": MessageLookupByLibrary.simpleMessage("管理分组引用"),
    "localGroupsUseHelp": MessageLookupByLibrary.simpleMessage(
      "勾选允许选择此自建组的目标分组。保存后应用引用，保留各组当前选择。",
    ),
    "localNetworkDeniedTip": MessageLookupByLibrary.simpleMessage(
      "本地网络权限被拒绝：已改用 gvisor 栈，局域网无法访问。",
    ),
    "locationPermission": MessageLookupByLibrary.simpleMessage("位置权限"),
    "locationPermissionDeniedMessage": MessageLookupByLibrary.simpleMessage(
      "位置权限已被拒绝，无法获取当前 Wi-Fi 名称。请前往系统设置手动开启位置权限。",
    ),
    "locationPermissionDesc": MessageLookupByLibrary.simpleMessage(
      "根据系统要求，获取Wi-Fi名称需要您授予位置权限。Android 上请选择“始终允许”，否则应用在后台时无法获取 Wi-Fi 名称。",
    ),
    "locationPermissionGuide": m44,
    "locationPermissionRequired": MessageLookupByLibrary.simpleMessage(
      "需要位置权限",
    ),
    "log": MessageLookupByLibrary.simpleMessage("日志"),
    "logLevel": MessageLookupByLibrary.simpleMessage("日志等级"),
    "logcat": MessageLookupByLibrary.simpleMessage("日志捕获"),
    "logcatDesc": MessageLookupByLibrary.simpleMessage("禁用将会隐藏日志入口"),
    "logs": MessageLookupByLibrary.simpleMessage("日志"),
    "logsAndDiagnostics": MessageLookupByLibrary.simpleMessage("日志与诊断"),
    "logsTest": MessageLookupByLibrary.simpleMessage("日志测试"),
    "loopback": MessageLookupByLibrary.simpleMessage("UWP 回环解锁"),
    "loose": MessageLookupByLibrary.simpleMessage("宽松"),
    "matchSourceIp": MessageLookupByLibrary.simpleMessage("匹配来源IP"),
    "matchTarget": MessageLookupByLibrary.simpleMessage("MATCH-TARGET"),
    "maxFailedTimes": MessageLookupByLibrary.simpleMessage("最大失败次数"),
    "maxLengthTip": m45,
    "maximize": MessageLookupByLibrary.simpleMessage("最大化"),
    "memoryAppResident": MessageLookupByLibrary.simpleMessage("常驻内存"),
    "memoryAppShared": MessageLookupByLibrary.simpleMessage("应用及共享"),
    "memoryCoreHeapIdle": MessageLookupByLibrary.simpleMessage("堆内存空闲"),
    "memoryCoreHeapInuse": MessageLookupByLibrary.simpleMessage("堆内存使用中"),
    "memoryCoreNotRunning": MessageLookupByLibrary.simpleMessage("内核未运行"),
    "memoryCoreRuntime": MessageLookupByLibrary.simpleMessage("运行时开销"),
    "memoryCoreStack": MessageLookupByLibrary.simpleMessage("协程栈"),
    "memoryEstimateDesc": MessageLookupByLibrary.simpleMessage(
      "基于进程常驻内存估算，可能与系统显示的数值不同。",
    ),
    "memoryEstimateSharedDesc": MessageLookupByLibrary.simpleMessage(
      "内核与应用运行在同一进程，内核部分按运行时统计估算，其余计入应用及共享内存。",
    ),
    "memoryInfo": MessageLookupByLibrary.simpleMessage("内存信息"),
    "memoryReleased": MessageLookupByLibrary.simpleMessage("内存已释放"),
    "memoryReleasedSize": m46,
    "messageTest": MessageLookupByLibrary.simpleMessage("消息测试"),
    "messageTestTip": MessageLookupByLibrary.simpleMessage("这是一条消息。"),
    "min": MessageLookupByLibrary.simpleMessage("最小"),
    "minimize": MessageLookupByLibrary.simpleMessage("最小化"),
    "minimizeOnExit": MessageLookupByLibrary.simpleMessage("退出时最小化"),
    "minutesAgo": m47,
    "mixedPort": MessageLookupByLibrary.simpleMessage("混合端口"),
    "mode": MessageLookupByLibrary.simpleMessage("模式"),
    "monochromeScheme": MessageLookupByLibrary.simpleMessage("单色"),
    "monthsAgo": m48,
    "more": MessageLookupByLibrary.simpleMessage("更多"),
    "name": MessageLookupByLibrary.simpleMessage("名称"),
    "navigationBarStyle": MessageLookupByLibrary.simpleMessage("底栏"),
    "network": MessageLookupByLibrary.simpleMessage("网络"),
    "networkAccessDeniedError": m49,
    "networkBadResponseError": m50,
    "networkCancelledError": MessageLookupByLibrary.simpleMessage("请求已取消"),
    "networkConnectionError": MessageLookupByLibrary.simpleMessage(
      "无法连接到服务器，请检查网络连接或代理设置",
    ),
    "networkDetection": MessageLookupByLibrary.simpleMessage("网络检测"),
    "networkHostLookupError": MessageLookupByLibrary.simpleMessage(
      "无法解析服务器地址，请确认链接正确且 DNS 可用",
    ),
    "networkNotFoundError": m51,
    "networkRateLimitedError": MessageLookupByLibrary.simpleMessage(
      "请求过于频繁（HTTP 429），请稍后再试",
    ),
    "networkRequestFailed": m52,
    "networkServerError": m53,
    "networkSpeed": MessageLookupByLibrary.simpleMessage("网络速度"),
    "networkTimeoutError": MessageLookupByLibrary.simpleMessage(
      "请求超时，请检查网络或代理后重试",
    ),
    "networkTlsError": MessageLookupByLibrary.simpleMessage(
      "安全连接失败，服务器证书可能无效，或连接被拦截",
    ),
    "networkType": MessageLookupByLibrary.simpleMessage("网络类型"),
    "neutralScheme": MessageLookupByLibrary.simpleMessage("中性"),
    "nextMatch": MessageLookupByLibrary.simpleMessage("下一个匹配"),
    "no": MessageLookupByLibrary.simpleMessage("否"),
    "noData": MessageLookupByLibrary.simpleMessage("暂无数据"),
    "noInfo": MessageLookupByLibrary.simpleMessage("暂无信息"),
    "noNetwork": MessageLookupByLibrary.simpleMessage("无网络"),
    "noNetworkApp": MessageLookupByLibrary.simpleMessage("无网络应用"),
    "noRecords": MessageLookupByLibrary.simpleMessage("暂无记录"),
    "noResolve": MessageLookupByLibrary.simpleMessage("不解析IP"),
    "noResolveHostname": MessageLookupByLibrary.simpleMessage("不解析主机名"),
    "noSearchResults": MessageLookupByLibrary.simpleMessage("没有匹配的结果"),
    "nonTextProviderFile": MessageLookupByLibrary.simpleMessage("该外部资源不是文本文件"),
    "none": MessageLookupByLibrary.simpleMessage("无"),
    "notSelectedTip": MessageLookupByLibrary.simpleMessage("当前代理组无法选中"),
    "ntpInterval": MessageLookupByLibrary.simpleMessage("同步间隔（分钟）"),
    "ntpStatusDesc": MessageLookupByLibrary.simpleMessage("从NTP服务器获取时间，而非系统时钟"),
    "nullProfileDesc": MessageLookupByLibrary.simpleMessage("添加一个配置文件后即可开始使用"),
    "nullTip": m54,
    "numberTip": m55,
    "officialDocumentation": MessageLookupByLibrary.simpleMessage("官方文档"),
    "onDemand": MessageLookupByLibrary.simpleMessage("按需运行"),
    "onDemandDesc": MessageLookupByLibrary.simpleMessage("配置程序特定场景运行状态"),
    "onlyStatisticsProxy": MessageLookupByLibrary.simpleMessage("仅统计代理流量"),
    "optional": MessageLookupByLibrary.simpleMessage("可选"),
    "options": MessageLookupByLibrary.simpleMessage("选项"),
    "other": MessageLookupByLibrary.simpleMessage("其他"),
    "otherContributors": MessageLookupByLibrary.simpleMessage("其他贡献者"),
    "outboundIp": MessageLookupByLibrary.simpleMessage("出站 IP"),
    "outboundMode": MessageLookupByLibrary.simpleMessage("出站模式"),
    "override": MessageLookupByLibrary.simpleMessage("覆写"),
    "overrideDns": MessageLookupByLibrary.simpleMessage("覆写DNS"),
    "overrideEntries": MessageLookupByLibrary.simpleMessage("覆写项"),
    "overrideMode": MessageLookupByLibrary.simpleMessage("覆写模式"),
    "overrideNtp": MessageLookupByLibrary.simpleMessage("覆写NTP"),
    "overrideScript": MessageLookupByLibrary.simpleMessage("覆写脚本"),
    "overwriteIssueCoreRejected": m56,
    "overwriteIssueDuplicateName": m57,
    "overwriteIssueEmptyName": MessageLookupByLibrary.simpleMessage("名称为空"),
    "overwriteIssueGroupLoop": m58,
    "overwriteIssueMissingProviders": m59,
    "overwriteIssueMissingProxies": m60,
    "overwriteIssueNoProxySource": MessageLookupByLibrary.simpleMessage(
      "未选择任何代理或代理集，内核会拒绝该策略组",
    ),
    "overwriteIssueReservedName": m61,
    "overwriteIssueSubscriptionGroupMissingProxies": m62,
    "overwriteIssuesSummary": m63,
    "overwriteTypeCustom": MessageLookupByLibrary.simpleMessage("自定义"),
    "overwriteTypeCustomDesc": MessageLookupByLibrary.simpleMessage(
      "自定义模式，支持完全自定义修改代理、策略组以及规则",
    ),
    "palette": MessageLookupByLibrary.simpleMessage("调色板"),
    "password": MessageLookupByLibrary.simpleMessage("密码"),
    "paste": MessageLookupByLibrary.simpleMessage("粘贴"),
    "pickFromAlbum": MessageLookupByLibrary.simpleMessage("从相册选择"),
    "pinWindow": MessageLookupByLibrary.simpleMessage("窗口置顶"),
    "pleaseBindWebDAV": MessageLookupByLibrary.simpleMessage("请绑定WebDAV"),
    "pleaseEnterScriptName": MessageLookupByLibrary.simpleMessage("请输入脚本名称"),
    "pleaseUploadValidQrcode": MessageLookupByLibrary.simpleMessage(
      "请上传有效的二维码",
    ),
    "policyActualPreview": MessageLookupByLibrary.simpleMessage("实际接受配置"),
    "policyAndroidRequired": MessageLookupByLibrary.simpleMessage(
      "目前仅 Android 支持应用受管策略；仍可编辑草稿和预览。",
    ),
    "policyApply": MessageLookupByLibrary.simpleMessage("保存并请求应用"),
    "policyApplyConfirm": MessageLookupByLibrary.simpleMessage(
      "使用本策略处理分流和 DNS，包括明确选择的 DIRECT。原规则、DNS、provider 和特殊覆写不参与；已有受管节点选择将重置。此操作不会启动已停止的代理。",
    ),
    "policyApplyRequested": MessageLookupByLibrary.simpleMessage(
      "已保存选择并请求应用，请查看实际配置状态。",
    ),
    "policyDraftAuthentication": MessageLookupByLibrary.simpleMessage(
      "使用用户名和密码",
    ),
    "policyDraftBackupConsent": MessageLookupByLibrary.simpleMessage(
      "此冻结备份包含策略草稿，可能含凭据和原始迁移材料。请重新确认备份后再导出。",
    ),
    "policyDraftBackupLocal": MessageLookupByLibrary.simpleMessage(
      "所选本地文件将保存未加密 ZIP，包含完整策略草稿、凭据和迁移材料。继续？",
    ),
    "policyDraftBackupWebDav": MessageLookupByLibrary.simpleMessage(
      "将向所选 WebDAV 服务上传未加密 ZIP，包含完整策略草稿、凭据和迁移材料。继续？",
    ),
    "policyDraftBootstrap": MessageLookupByLibrary.simpleMessage(
      "启动 DNS（DIRECT）",
    ),
    "policyDraftConflict": MessageLookupByLibrary.simpleMessage(
      "已保存的草稿发生变化。输入已保留，请重新载入后再修改。",
    ),
    "policyDraftCopyFull": MessageLookupByLibrary.simpleMessage("复制完整生成配置"),
    "policyDraftCopyFullConfirm": MessageLookupByLibrary.simpleMessage(
      "将完整生成配置（可能含用户名和密码）复制到剪贴板？",
    ),
    "policyDraftDeleted": MessageLookupByLibrary.simpleMessage("策略草稿已删除"),
    "policyDraftDirectWarning": MessageLookupByLibrary.simpleMessage(
      "显式默认 DIRECT 也会把未命中域名的 DNS 直连发送给所选解析服务。",
    ),
    "policyDraftDiscard": MessageLookupByLibrary.simpleMessage("放弃未保存的修改？"),
    "policyDraftDnsServices": MessageLookupByLibrary.simpleMessage("DNS 服务"),
    "policyDraftDomainDefault": MessageLookupByLibrary.simpleMessage(
      "未命中域名的默认策略",
    ),
    "policyDraftDomainRules": MessageLookupByLibrary.simpleMessage("域名规则"),
    "policyDraftExtract": MessageLookupByLibrary.simpleMessage("从已保存配置提取"),
    "policyDraftExtractConfirm": MessageLookupByLibrary.simpleMessage(
      "用本地已保存材料提取的草稿替换当前编辑内容？不会执行脚本；不支持的规则仍会阻断迁移，不会应用配置。",
    ),
    "policyDraftExtractFailed": MessageLookupByLibrary.simpleMessage(
      "无法提取本地已保存材料，草稿未变。",
    ),
    "policyDraftGeneratePreview": MessageLookupByLibrary.simpleMessage(
      "生成草稿预览",
    ),
    "policyDraftGroups": MessageLookupByLibrary.simpleMessage("静态代理组"),
    "policyDraftIncomplete": m64,
    "policyDraftIpDefault": MessageLookupByLibrary.simpleMessage(
      "未命中 IP 的默认策略",
    ),
    "policyDraftIpRules": MessageLookupByLibrary.simpleMessage("IP 规则"),
    "policyDraftListeners": MessageLookupByLibrary.simpleMessage("预览监听端口"),
    "policyDraftLoadFailed": MessageLookupByLibrary.simpleMessage(
      "无法读取草稿，可重试载入。",
    ),
    "policyDraftMembers": MessageLookupByLibrary.simpleMessage("选择固定节点成员"),
    "policyDraftMigration": MessageLookupByLibrary.simpleMessage("历史迁移材料"),
    "policyDraftMigrationBlocked": MessageLookupByLibrary.simpleMessage(
      "迁移已阻断，原始材料和规则位置已保留。修改提取行或默认策略不能解除阻断。",
    ),
    "policyDraftMigrationChoices": MessageLookupByLibrary.simpleMessage(
      "提取行只是候选，两个默认、DNS 和启动解析服务仍需明确选择。原 Profile、覆写和全局 DNS 继续沿传统配置路径生效；此预览不是当前运行配置。",
    ),
    "policyDraftMigrationIp": MessageLookupByLibrary.simpleMessage(
      "目的 IP 规则也可能限制域名连接，分表不能保证保留该保护。",
    ),
    "policyDraftMigrationMatch": MessageLookupByLibrary.simpleMessage(
      "MATCH 后还有规则，不能把它的位置改成表尾默认。",
    ),
    "policyDraftMigrationScript": MessageLookupByLibrary.simpleMessage(
      "提取时不执行脚本，其输出未知。",
    ),
    "policyDraftMigrationUnsupported": MessageLookupByLibrary.simpleMessage(
      "此规则、资源或配置超出迁移支持范围。",
    ),
    "policyDraftMissing": MessageLookupByLibrary.simpleMessage(
      "此 Profile 已不存在，当前输入尚未保存。",
    ),
    "policyDraftMoveDown": MessageLookupByLibrary.simpleMessage("下移"),
    "policyDraftMoveUp": MessageLookupByLibrary.simpleMessage("上移"),
    "policyDraftNeedsPreview": MessageLookupByLibrary.simpleMessage(
      "输入尚需生成预览校验",
    ),
    "policyDraftNodes": MessageLookupByLibrary.simpleMessage("固定 SOCKS5 节点"),
    "policyDraftProtocol": MessageLookupByLibrary.simpleMessage("协议"),
    "policyDraftReadOnly": MessageLookupByLibrary.simpleMessage(
      "版本未知或结构不支持。原文已保留，不能编辑或预览。",
    ),
    "policyDraftReady": MessageLookupByLibrary.simpleMessage("草稿预览已校验，尚未应用"),
    "policyDraftRebuild": MessageLookupByLibrary.simpleMessage("新建独立草稿"),
    "policyDraftRebuildConfirm": MessageLookupByLibrary.simpleMessage(
      "放弃此草稿及迁移材料并新建？新策略不代表保留了旧配置的保护。原 Profile 和运行配置不变。",
    ),
    "policyDraftReferenced": m65,
    "policyDraftReload": MessageLookupByLibrary.simpleMessage("重新载入已保存草稿"),
    "policyDraftRestoreFailed": MessageLookupByLibrary.simpleMessage(
      "未能完成恢复，请重新载入核对已保存的数据；如有恢复提示，仍需处理。",
    ),
    "policyDraftRestoreWarning": MessageLookupByLibrary.simpleMessage(
      "覆盖恢复在归档含实体数据时替换实体，备份中没有的草稿可能被清除；实体全空的归档保留现有实体。继续？",
    ),
    "policyDraftRevealCredentials": MessageLookupByLibrary.simpleMessage(
      "显示凭据",
    ),
    "policyDraftSaveFailed": MessageLookupByLibrary.simpleMessage(
      "保存失败，输入和原有草稿已保留。",
    ),
    "policyDraftSaved": MessageLookupByLibrary.simpleMessage("已保存草稿，尚未应用"),
    "policyDraftStorage": MessageLookupByLibrary.simpleMessage(
      "草稿可能含凭据，沿现有数据库目录保存（Android 为应用私有目录）。备份 ZIP 不加密。保存不会应用草稿。",
    ),
    "policyDraftTarget": MessageLookupByLibrary.simpleMessage("分流目标"),
    "policyDraftTitle": MessageLookupByLibrary.simpleMessage("策略草稿"),
    "policyDraftUdp": MessageLookupByLibrary.simpleMessage("为此节点启用 UDP"),
    "policyDraftUnsaved": MessageLookupByLibrary.simpleMessage("未保存草稿，尚未应用"),
    "policyDraftUnset": MessageLookupByLibrary.simpleMessage("未配置"),
    "policyDraftUsername": MessageLookupByLibrary.simpleMessage("用户名"),
    "policyFinalPreview": MessageLookupByLibrary.simpleMessage("最终生成配置"),
    "policyMaintenanceNone": MessageLookupByLibrary.simpleMessage(
      "不设置维护代理默认目标",
    ),
    "policyMaintenanceRequired": MessageLookupByLibrary.simpleMessage(
      "请选择并应用维护代理组或节点，或为本次请求明确选择 Auto／Direct。旧目标可能已不存在。",
    ),
    "policyMaintenanceTarget": MessageLookupByLibrary.simpleMessage("维护请求代理目标"),
    "policyManagedEditRequired": MessageLookupByLibrary.simpleMessage(
      "此 Profile 使用受管策略。请在策略草稿中修改分流和 DNS，再明确请求应用。",
    ),
    "policyMaterialBindings": MessageLookupByLibrary.simpleMessage("来源绑定"),
    "policyMaterialCancel": MessageLookupByLibrary.simpleMessage("丢弃预览材料"),
    "policyMaterialCollections": MessageLookupByLibrary.simpleMessage("来源集合"),
    "policyMaterialDomain": MessageLookupByLibrary.simpleMessage("绑定来源域名集合"),
    "policyMaterialGroup": MessageLookupByLibrary.simpleMessage(
      "绑定来源 select 组",
    ),
    "policyMaterialIp": MessageLookupByLibrary.simpleMessage("绑定来源地址集合"),
    "policyMaterialLatest": MessageLookupByLibrary.simpleMessage("加载最新材料供预览"),
    "policyMaterialLoaded": MessageLookupByLibrary.simpleMessage(
      "最新材料已加载。重新绑定变化的名称并预览后，点击 Apply 才会采用。Save 仅保存草稿。",
    ),
    "policyMaterialNode": MessageLookupByLibrary.simpleMessage("绑定来源节点"),
    "policyMaterialSource": MessageLookupByLibrary.simpleMessage("选择准确的来源名称"),
    "policyMaterialUnavailable": MessageLookupByLibrary.simpleMessage(
      "材料不可用或不兼容。请检查来源绑定并重新预览。",
    ),
    "policyOriginal": MessageLookupByLibrary.simpleMessage("改用原 Profile"),
    "policyOriginalConfirm": MessageLookupByLibrary.simpleMessage(
      "退出受管分流，改用原 Profile 的规则、DNS 和覆写？这可能改变流量出口。",
    ),
    "policyOriginalStatus": MessageLookupByLibrary.simpleMessage(
      "已选择原 Profile",
    ),
    "policySelectedStatus": MessageLookupByLibrary.simpleMessage(
      "已选择策略；实际接受结果单独显示",
    ),
    "policySelectionPending": MessageLookupByLibrary.simpleMessage(
      "已选策略与实际接受的配置不同。",
    ),
    "policySelectionUnavailable": MessageLookupByLibrary.simpleMessage(
      "需要受管策略，但当前选择不可用，请选择有效策略。",
    ),
    "policyUnappliedEdits": MessageLookupByLibrary.simpleMessage(
      "草稿与已选策略不同，编辑尚未应用",
    ),
    "port": MessageLookupByLibrary.simpleMessage("端口"),
    "portConflictTip": MessageLookupByLibrary.simpleMessage("请输入不同的端口"),
    "portTip": m66,
    "prerequisites": MessageLookupByLibrary.simpleMessage("前置条件"),
    "pressKeyboard": MessageLookupByLibrary.simpleMessage("请按下组合键"),
    "preview": MessageLookupByLibrary.simpleMessage("预览"),
    "previousMatch": MessageLookupByLibrary.simpleMessage("上一个匹配"),
    "process": MessageLookupByLibrary.simpleMessage("进程"),
    "profile": MessageLookupByLibrary.simpleMessage("配置"),
    "profileAutoUpdateIntervalInvalidValidationDesc":
        MessageLookupByLibrary.simpleMessage("请输入正整数分钟；历史无效值暂按一天调度。"),
    "profileAutoUpdateIntervalNullValidationDesc":
        MessageLookupByLibrary.simpleMessage("请输入自动更新间隔时间"),
    "profileDownloadFailed": MessageLookupByLibrary.simpleMessage(
      "订阅下载失败，已保留原文件。",
    ),
    "profileDownloadTimeout": MessageLookupByLibrary.simpleMessage(
      "订阅下载超过 90 秒。",
    ),
    "profileDownloadTooLarge": MessageLookupByLibrary.simpleMessage(
      "订阅超过 16 MiB 下载上限。",
    ),
    "profileHasUpdate": MessageLookupByLibrary.simpleMessage(
      "配置文件已经修改，是否关闭自动更新？",
    ),
    "profileImportContinue": MessageLookupByLibrary.simpleMessage("继续"),
    "profileImportDownloadFailed": MessageLookupByLibrary.simpleMessage(
      "无法下载订阅，请检查 URL 和请求方式后重试。",
    ),
    "profileImportDownloading": MessageLookupByLibrary.simpleMessage("正在下载订阅…"),
    "profileImportInvalid": MessageLookupByLibrary.simpleMessage(
      "下载的文件不是有效订阅，请检查 URL。",
    ),
    "profileImportPreparing": MessageLookupByLibrary.simpleMessage("正在准备导入…"),
    "profileImportSaving": MessageLookupByLibrary.simpleMessage("正在保存订阅…"),
    "profileInvalidBody": MessageLookupByLibrary.simpleMessage(
      "下载的订阅无效，已保留原文件。",
    ),
    "profileNameNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "请输入配置名称",
    ),
    "profileRefreshFailed": MessageLookupByLibrary.simpleMessage(
      "订阅刷新失败，请检查当前配置状态。",
    ),
    "profileSavedNotApplied": MessageLookupByLibrary.simpleMessage(
      "订阅已保存，请查看当前配置状态，更新可能尚未应用。",
    ),
    "profileSavedRecoveryRequired": MessageLookupByLibrary.simpleMessage(
      "订阅已保存，但无法确认清理结果。恢复完成前已暂停后续请求。",
    ),
    "profileUrlInvalidValidationDesc": MessageLookupByLibrary.simpleMessage(
      "请输入有效配置URL",
    ),
    "profileUrlNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "请输入配置URL",
    ),
    "profiles": MessageLookupByLibrary.simpleMessage("配置"),
    "profilesSort": MessageLookupByLibrary.simpleMessage("配置排序"),
    "project": MessageLookupByLibrary.simpleMessage("项目"),
    "providerInUse": m67,
    "providerRenameShadowed": m68,
    "providerSourceSubscription": MessageLookupByLibrary.simpleMessage("订阅"),
    "providerUrlTip": MessageLookupByLibrary.simpleMessage("仅支持远程资源"),
    "providers": MessageLookupByLibrary.simpleMessage("外部资源"),
    "proxies": MessageLookupByLibrary.simpleMessage("代理"),
    "proxiesCount": m69,
    "proxiesEmpty": MessageLookupByLibrary.simpleMessage("代理为空"),
    "proxyChains": MessageLookupByLibrary.simpleMessage("代理链"),
    "proxyDefinition": MessageLookupByLibrary.simpleMessage("完整配置"),
    "proxyDefinitionNotMap": MessageLookupByLibrary.simpleMessage(
      "配置必须是包含 name 和 type 的 YAML 映射",
    ),
    "proxyFilter": MessageLookupByLibrary.simpleMessage("节点过滤器"),
    "proxyGroup": MessageLookupByLibrary.simpleMessage("策略组"),
    "proxyGroupEmpty": MessageLookupByLibrary.simpleMessage("策略组为空"),
    "proxyGroupNameDuplicate": MessageLookupByLibrary.simpleMessage("策略组名称重复"),
    "proxyNode": MessageLookupByLibrary.simpleMessage("代理节点"),
    "proxyProviders": MessageLookupByLibrary.simpleMessage("代理集"),
    "proxyProvidersEmpty": MessageLookupByLibrary.simpleMessage("代理集为空"),
    "proxyProvidersNotEmpty": MessageLookupByLibrary.simpleMessage("代理集不能为空"),
    "proxyType": MessageLookupByLibrary.simpleMessage("代理类型"),
    "pruneCache": MessageLookupByLibrary.simpleMessage("修剪缓存"),
    "pureBlack": MessageLookupByLibrary.simpleMessage("纯黑"),
    "pureBlackMode": MessageLookupByLibrary.simpleMessage("纯黑模式"),
    "qrImageBusy": MessageLookupByLibrary.simpleMessage(
      "图片识别正忙，请使用相机，或通过链接、文件导入。",
    ),
    "qrImageReadFailed": MessageLookupByLibrary.simpleMessage(
      "无法读取此图片，请选择另一张本地图片。",
    ),
    "qrImageTimeout": MessageLookupByLibrary.simpleMessage(
      "图片识别超时，请稍后重试或使用相机。",
    ),
    "qrcode": MessageLookupByLibrary.simpleMessage("二维码"),
    "qrcodeDesc": MessageLookupByLibrary.simpleMessage("扫描二维码获取配置文件"),
    "quickAdd": MessageLookupByLibrary.simpleMessage("快捷添加"),
    "quickEdit": MessageLookupByLibrary.simpleMessage("快速编辑"),
    "quickFill": MessageLookupByLibrary.simpleMessage("一键填入"),
    "rainbowScheme": MessageLookupByLibrary.simpleMessage("彩虹"),
    "recentRequests": MessageLookupByLibrary.simpleMessage("最近请求"),
    "recordType": MessageLookupByLibrary.simpleMessage("记录类型"),
    "redirPort": MessageLookupByLibrary.simpleMessage("Redir端口"),
    "redo": MessageLookupByLibrary.simpleMessage("重做"),
    "releaseMemory": MessageLookupByLibrary.simpleMessage("释放内存"),
    "releaseMemoryFailed": MessageLookupByLibrary.simpleMessage("释放内存失败"),
    "remote": MessageLookupByLibrary.simpleMessage("远程"),
    "remoteDestination": MessageLookupByLibrary.simpleMessage("远程目标"),
    "remove": MessageLookupByLibrary.simpleMessage("移除"),
    "replace": MessageLookupByLibrary.simpleMessage("替换"),
    "replaceAll": MessageLookupByLibrary.simpleMessage("全部替换"),
    "reportBuildIdentity": MessageLookupByLibrary.simpleMessage(
      "构建身份（缺失字段为未知）",
    ),
    "reportBusy": MessageLookupByLibrary.simpleMessage(
      "忙或超时；底层 I/O 可能仍在进行，请稍后刷新。",
    ),
    "reportCancelled": MessageLookupByLibrary.simpleMessage(
      "已取消；请检查目标是否留下部分副本。",
    ),
    "reportCorrupt": MessageLookupByLibrary.simpleMessage("损坏或不支持的项目"),
    "reportDeleteAll": MessageLookupByLibrary.simpleMessage("删除当前报告"),
    "reportDeleteWarning": MessageLookupByLibrary.simpleMessage(
      "删除所选报告，或当前快照中的全部报告？新报告可能保留。内部去重记录与已导出副本不会删除，后续新故障仍可记录。",
    ),
    "reportDeleted": MessageLookupByLibrary.simpleMessage("所选报告已删除"),
    "reportDestinationWarning": MessageLookupByLibrary.simpleMessage(
      "请核对保存位置：其提供方可能同步至云端。应用不会自动发送此报告；取消或失败可能留下部分副本。",
    ),
    "reportEmpty": MessageLookupByLibrary.simpleMessage("没有已保存报告"),
    "reportExportRaw": MessageLookupByLibrary.simpleMessage("导出原始报告（ZIP）"),
    "reportExportSummary": MessageLookupByLibrary.simpleMessage("导出摘要（JSON）"),
    "reportExported": MessageLookupByLibrary.simpleMessage("已保存并核验"),
    "reportFailed": MessageLookupByLibrary.simpleMessage(
      "操作失败或仅部分完成，请刷新；导出时另检查目标位置。",
    ),
    "reportIntegrity": MessageLookupByLibrary.simpleMessage(
      "完整性核验失败；请检查目标是否留下部分副本。",
    ),
    "reportLimited": MessageLookupByLibrary.simpleMessage("目录达到处理上限，部分项目未能处理。"),
    "reportMetadataOnly": MessageLookupByLibrary.simpleMessage(
      "仅元信息；后续不会自动补齐 trace",
    ),
    "reportRawMissing": MessageLookupByLibrary.simpleMessage("原文缺失或不一致"),
    "reportRawUnverified": MessageLookupByLibrary.simpleMessage("原文尚未核验"),
    "reportRawWarning": MessageLookupByLibrary.simpleMessage(
      "原始报告可能含凭据、地址和内存片段，请仅向预期接收方导出。系统目的地可能由云端提供方同步；取消或失败可能留下部分副本。继续导出原始报告？",
    ),
    "reportRefresh": MessageLookupByLibrary.simpleMessage("刷新"),
    "reportRetention": MessageLookupByLibrary.simpleMessage(
      "上限：20 份、16 MiB、30 天。自动清理为尽力维护。",
    ),
    "reportStale": MessageLookupByLibrary.simpleMessage(
      "报告已变化或选择已过期，请刷新后重新选择。",
    ),
    "reportTruncated": MessageLookupByLibrary.simpleMessage("材料已截断，不是完整 dump"),
    "reportUnknownFormat": MessageLookupByLibrary.simpleMessage("未知报告格式"),
    "reportUsage": MessageLookupByLibrary.simpleMessage("存储占用（含未知项目及内部索引）"),
    "reportWrittenUnverified": MessageLookupByLibrary.simpleMessage(
      "已写入，目标内容未核验",
    ),
    "request": MessageLookupByLibrary.simpleMessage("请求"),
    "requestDirectRecoveryMessage": m70,
    "requestDirectRecoveryTitle": MessageLookupByLibrary.simpleMessage(
      "本次通过直连恢复？",
    ),
    "requestMode": MessageLookupByLibrary.simpleMessage("请求出口"),
    "requestModeAuto": MessageLookupByLibrary.simpleMessage("自动"),
    "requestModeDirect": MessageLookupByLibrary.simpleMessage("直连"),
    "requestModeHelp": MessageLookupByLibrary.simpleMessage(
      "用于此对象自身的联网请求。代理需要有效代理节点；直连需要可用的非 VPN 网络。",
    ),
    "requestModeProxy": MessageLookupByLibrary.simpleMessage("代理"),
    "requestPartialCommit": MessageLookupByLibrary.simpleMessage(
      "部分本地修改未能恢复。已保留恢复文件，并阻止自动更新。",
    ),
    "requestProxyDefault": m71,
    "requestProxyTarget": MessageLookupByLibrary.simpleMessage("代理目标"),
    "requestRestartRequired": MessageLookupByLibrary.simpleMessage(
      "未完成的本地保存可能仍在运行。请打开应用信息 → 强行停止，再重新打开 FlClash。仅重启代理服务或关闭界面无法解决。重新打开后，请在来源权限中核对已保存的数据。",
    ),
    "requestRouteUnavailable": MessageLookupByLibrary.simpleMessage(
      "所选请求出口当前不可用。",
    ),
    "requests": MessageLookupByLibrary.simpleMessage("请求"),
    "requestsAndUpdates": MessageLookupByLibrary.simpleMessage("请求与更新"),
    "reset": MessageLookupByLibrary.simpleMessage("重置"),
    "resetPageChangesTip": MessageLookupByLibrary.simpleMessage(
      "当前页面存在更改，确定重置吗？",
    ),
    "resetTip": MessageLookupByLibrary.simpleMessage("确定要重置吗？"),
    "resources": MessageLookupByLibrary.simpleMessage("资源"),
    "respectRules": MessageLookupByLibrary.simpleMessage("遵守规则"),
    "respectRulesDesc": MessageLookupByLibrary.simpleMessage(
      "DNS连接遵守规则，需配置Proxy Server Nameserver",
    ),
    "responseCode": MessageLookupByLibrary.simpleMessage("响应码"),
    "restart": MessageLookupByLibrary.simpleMessage("重启"),
    "restartCoreTip": MessageLookupByLibrary.simpleMessage("您确定要重启核心吗？"),
    "restore": MessageLookupByLibrary.simpleMessage("恢复"),
    "restoreAllData": MessageLookupByLibrary.simpleMessage("恢复所有数据"),
    "restoreOnlyConfig": MessageLookupByLibrary.simpleMessage("仅恢复配置文件"),
    "restoreStrategy": MessageLookupByLibrary.simpleMessage("恢复策略"),
    "restoreStrategyCompatible": MessageLookupByLibrary.simpleMessage("兼容"),
    "restoreStrategyOverride": MessageLookupByLibrary.simpleMessage("覆盖"),
    "restoreSuccess": MessageLookupByLibrary.simpleMessage("恢复成功"),
    "retry": MessageLookupByLibrary.simpleMessage("重试"),
    "routeAddress": MessageLookupByLibrary.simpleMessage("路由地址"),
    "routeMode": MessageLookupByLibrary.simpleMessage("路由模式"),
    "routeModeBypassPrivate": MessageLookupByLibrary.simpleMessage("绕过私有路由地址"),
    "routeModeConfig": MessageLookupByLibrary.simpleMessage("使用配置"),
    "ru": MessageLookupByLibrary.simpleMessage("俄语"),
    "rule": MessageLookupByLibrary.simpleMessage("规则"),
    "ruleActionAndDesc": MessageLookupByLibrary.simpleMessage("逻辑规则 AND"),
    "ruleActionDomainDesc": MessageLookupByLibrary.simpleMessage("匹配完整域名"),
    "ruleActionDomainKeywordDesc": MessageLookupByLibrary.simpleMessage(
      "匹配域名关键字",
    ),
    "ruleActionDomainRegexDesc": MessageLookupByLibrary.simpleMessage(
      "使用域名正则表达式匹配",
    ),
    "ruleActionDomainSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "匹配域名后缀",
    ),
    "ruleActionDomainWildcardDesc": MessageLookupByLibrary.simpleMessage(
      "通配符匹配，仅支持*和?通配符",
    ),
    "ruleActionDscpDesc": MessageLookupByLibrary.simpleMessage(
      "匹配DSCP标记（仅限 tproxy udp 入站）",
    ),
    "ruleActionDstPortDesc": MessageLookupByLibrary.simpleMessage("匹配请求目标端口范围"),
    "ruleActionGeoipDesc": MessageLookupByLibrary.simpleMessage("匹配 IP 所属国家代码"),
    "ruleActionGeositeDesc": MessageLookupByLibrary.simpleMessage(
      "匹配 Geosite 内的域名",
    ),
    "ruleActionInNameDesc": MessageLookupByLibrary.simpleMessage("匹配入站名称"),
    "ruleActionInPortDesc": MessageLookupByLibrary.simpleMessage("匹配入站端口"),
    "ruleActionInTypeDesc": MessageLookupByLibrary.simpleMessage("匹配入站类型"),
    "ruleActionInUserDesc": MessageLookupByLibrary.simpleMessage(
      "匹配入站用户名，支持使用 / 分隔多个用户名",
    ),
    "ruleActionIpAsnDesc": MessageLookupByLibrary.simpleMessage("匹配 IP 所属 ASN"),
    "ruleActionIpCidr6Desc": MessageLookupByLibrary.simpleMessage(
      "匹配 IP 地址范围，IP-CIDR6 只是一个别名",
    ),
    "ruleActionIpCidrDesc": MessageLookupByLibrary.simpleMessage("匹配 IP 地址范围"),
    "ruleActionIpSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "匹配 IP 后缀范围",
    ),
    "ruleActionMatchDesc": MessageLookupByLibrary.simpleMessage("匹配所有请求，无需条件"),
    "ruleActionNetworkDesc": MessageLookupByLibrary.simpleMessage("匹配TCP或者UDP"),
    "ruleActionNotDesc": MessageLookupByLibrary.simpleMessage("逻辑规则 NOT"),
    "ruleActionOrDesc": MessageLookupByLibrary.simpleMessage("逻辑规则 OR"),
    "ruleActionProcessNameDesc": MessageLookupByLibrary.simpleMessage(
      "使用进程匹配，在Android平台可以匹配包名",
    ),
    "ruleActionProcessNameRegexDesc": MessageLookupByLibrary.simpleMessage(
      "使用进程名称正则表达式匹配，在Android平台可以匹配包名",
    ),
    "ruleActionProcessNameWildcardDesc": MessageLookupByLibrary.simpleMessage(
      "使用进程名称通配符匹配，仅支持*和?通配符",
    ),
    "ruleActionProcessPathDesc": MessageLookupByLibrary.simpleMessage(
      "使用完整进程路径匹配",
    ),
    "ruleActionProcessPathRegexDesc": MessageLookupByLibrary.simpleMessage(
      "使用进程路径正则表达式匹配",
    ),
    "ruleActionProcessPathWildcardDesc": MessageLookupByLibrary.simpleMessage(
      "使用进程路径通配符匹配，仅支持*和?通配符",
    ),
    "ruleActionRematchNameDesc": MessageLookupByLibrary.simpleMessage(
      "匹配重匹配名称，多个名称用/分隔",
    ),
    "ruleActionRuleSetDesc": MessageLookupByLibrary.simpleMessage(
      "引用规则集合，需配置rule-providers",
    ),
    "ruleActionSrcGeoipDesc": MessageLookupByLibrary.simpleMessage(
      "匹配来源 IP 所属国家代码",
    ),
    "ruleActionSrcIpAsnDesc": MessageLookupByLibrary.simpleMessage(
      "匹配来源 IP 所属 ASN",
    ),
    "ruleActionSrcIpCidrDesc": MessageLookupByLibrary.simpleMessage(
      "匹配来源 IP 地址范围",
    ),
    "ruleActionSrcIpSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "匹配来源 IP 后缀范围",
    ),
    "ruleActionSrcPortDesc": MessageLookupByLibrary.simpleMessage("匹配请求来源端口范围"),
    "ruleActionSubRuleDesc": MessageLookupByLibrary.simpleMessage(
      "匹配至子规则，需要注意括号的使用",
    ),
    "ruleActionUidDesc": MessageLookupByLibrary.simpleMessage(
      "匹配 Linux USER ID",
    ),
    "ruleEmpty": MessageLookupByLibrary.simpleMessage("规则为空"),
    "ruleName": MessageLookupByLibrary.simpleMessage("规则名称"),
    "rulePresetBittorrentDirect": MessageLookupByLibrary.simpleMessage(
      "BT 下载直连",
    ),
    "rulePresetBlockDot": MessageLookupByLibrary.simpleMessage(
      "屏蔽 DNS over TLS",
    ),
    "rulePresetBlockQuic": MessageLookupByLibrary.simpleMessage("屏蔽 QUIC"),
    "rulePresetBlockStun": MessageLookupByLibrary.simpleMessage("屏蔽 STUN"),
    "rulePresetLanDirect": MessageLookupByLibrary.simpleMessage("局域网直连"),
    "rulePresetSystemServicesDirect": MessageLookupByLibrary.simpleMessage(
      "Apple 与 Microsoft 直连",
    ),
    "ruleProviders": MessageLookupByLibrary.simpleMessage("规则集"),
    "ruleSet": MessageLookupByLibrary.simpleMessage("规则集"),
    "ruleTarget": MessageLookupByLibrary.simpleMessage("规则目标"),
    "rules": MessageLookupByLibrary.simpleMessage("规则"),
    "rulesCount": m72,
    "runTime": MessageLookupByLibrary.simpleMessage("启动时间"),
    "safeMode": MessageLookupByLibrary.simpleMessage("安全模式"),
    "safeModeAppTitle": m73,
    "save": MessageLookupByLibrary.simpleMessage("保存"),
    "saveChanges": MessageLookupByLibrary.simpleMessage("是否保存更改？"),
    "script": MessageLookupByLibrary.simpleMessage("脚本"),
    "scriptModeDesc": MessageLookupByLibrary.simpleMessage(
      "脚本模式，使用外部扩展脚本，提供一键覆写配置的能力",
    ),
    "scrollToSelected": MessageLookupByLibrary.simpleMessage("滚动到已选"),
    "search": MessageLookupByLibrary.simpleMessage("搜索"),
    "seconds": MessageLookupByLibrary.simpleMessage("秒"),
    "secondsCount": m74,
    "selectAll": MessageLookupByLibrary.simpleMessage("全选"),
    "selectProxies": MessageLookupByLibrary.simpleMessage("选择代理"),
    "selectProxyProviders": MessageLookupByLibrary.simpleMessage("选择代理集"),
    "selectRuleSet": MessageLookupByLibrary.simpleMessage("请选择规则集"),
    "selectSplitStrategy": MessageLookupByLibrary.simpleMessage("请选择分流策略"),
    "selectSubRule": MessageLookupByLibrary.simpleMessage("请选择子规则"),
    "selected": MessageLookupByLibrary.simpleMessage("已选择"),
    "selectedCountTitle": m75,
    "server": MessageLookupByLibrary.simpleMessage("服务器"),
    "serviceAdvanced": MessageLookupByLibrary.simpleMessage("地区 / 服务检测"),
    "serviceAdvancedExplanation": MessageLookupByLibrary.simpleMessage(
      "此项为可选的单次主动检测，通过匿名请求取得地区及服务页面线索，可能访问下列额外端点。不携带浏览器登录 Cookie 或订阅凭据；结果不证明账号权益、实际播放或全设备保护。基础响应单独判断。",
    ),
    "serviceAdvancedTiming": MessageLookupByLibrary.simpleMessage(
      "结果 5 分钟后过期，每次至少间隔 30 秒；不自动重跑，离开本页取消未完成检测。各步时间为响应头耗时，并非 ping 或吞吐量。",
    ),
    "serviceAllDisabled": MessageLookupByLibrary.simpleMessage(
      "全部服务已关闭 · 管理服务",
    ),
    "serviceAvailable": MessageLookupByLibrary.simpleMessage("可用"),
    "serviceBasic": MessageLookupByLibrary.simpleMessage("基础 HTTPS 响应"),
    "serviceBasicExplanation": MessageLookupByLibrary.simpleMessage(
      "显示中的服务会在前台自动检查；结果 5 分钟后过期，出口变化或返回应用时按需重检。每项至少间隔 30 秒；全部检查仅包含启用项。仅读取响应头，不跟随跳转或加载网页资源。响应不证明网站功能、账号权益或全设备保护。",
    ),
    "serviceBlocked": MessageLookupByLibrary.simpleMessage("已被封禁"),
    "serviceBodyComplete": MessageLookupByLibrary.simpleMessage("响应读取完整"),
    "serviceBodyLimit": MessageLookupByLibrary.simpleMessage("响应超过读取上限"),
    "serviceCheck": MessageLookupByLibrary.simpleMessage("检测"),
    "serviceCheckAll": MessageLookupByLibrary.simpleMessage("全部检测"),
    "serviceCheckedAt": m76,
    "serviceComingSoon": MessageLookupByLibrary.simpleMessage("即将上线"),
    "serviceConnectFailed": MessageLookupByLibrary.simpleMessage(
      "本次请求未能建立有效响应",
    ),
    "serviceDetectedRegion": m77,
    "serviceDisallowedIsp": MessageLookupByLibrary.simpleMessage("不允许的 ISP"),
    "serviceDisneyExplanation": MessageLookupByLibrary.simpleMessage(
      "开始后将注册匿名浏览器设备、交换临时令牌并查询会话；令牌仅供本次检测使用，不保存。",
    ),
    "serviceDnsFailed": MessageLookupByLibrary.simpleMessage("本次请求无法解析主机"),
    "serviceElapsed": m78,
    "serviceExpired": m79,
    "serviceFailed": MessageLookupByLibrary.simpleMessage("无法判定"),
    "serviceHeaders": MessageLookupByLibrary.simpleMessage("已收到响应头"),
    "serviceHttpResponse": MessageLookupByLibrary.simpleMessage("HTTP 异常响应"),
    "serviceIndeterminate": MessageLookupByLibrary.simpleMessage(
      "无法判定；检测可能未完成，或响应规则已变化。",
    ),
    "serviceManage": MessageLookupByLibrary.simpleMessage("管理服务"),
    "serviceMarkerFound": MessageLookupByLibrary.simpleMessage("已取得所需标记"),
    "serviceMultipleRoutes": MessageLookupByLibrary.simpleMessage(
      "多个出口 · 见各请求",
    ),
    "serviceObserved": MessageLookupByLibrary.simpleMessage("已取得服务线索"),
    "serviceOriginalsOnly": MessageLookupByLibrary.simpleMessage("仅限自制内容"),
    "servicePending": MessageLookupByLibrary.simpleMessage("待检测"),
    "serviceQueued": MessageLookupByLibrary.simpleMessage("等待检测间隔"),
    "serviceReadError": MessageLookupByLibrary.simpleMessage("响应中断或无法读取"),
    "serviceRecipientBlocked": MessageLookupByLibrary.simpleMessage(
      "接收方或跳转超出检测范围",
    ),
    "serviceRecipients": m80,
    "serviceRedirected": MessageLookupByLibrary.simpleMessage("要求跳转（未跟随）"),
    "serviceRequestLimit": MessageLookupByLibrary.simpleMessage("已达本轮请求上限"),
    "serviceResponded": MessageLookupByLibrary.simpleMessage("已响应"),
    "serviceRestricted": MessageLookupByLibrary.simpleMessage("访问受限"),
    "serviceRouteChanged": MessageLookupByLibrary.simpleMessage(
      "出口已变化 · 请手动重检",
    ),
    "serviceStartAdvanced": MessageLookupByLibrary.simpleMessage("开始单次检测"),
    "serviceStatus": MessageLookupByLibrary.simpleMessage("服务状态"),
    "serviceTlsFailed": MessageLookupByLibrary.simpleMessage(
      "本次请求未通过 TLS 身份校验",
    ),
    "serviceUnavailable": MessageLookupByLibrary.simpleMessage("本次请求无有效响应"),
    "serviceUnknownRoute": MessageLookupByLibrary.simpleMessage("出口未知"),
    "serviceUnsupportedRegion": MessageLookupByLibrary.simpleMessage("地区不支持"),
    "settings": MessageLookupByLibrary.simpleMessage("设置"),
    "show": MessageLookupByLibrary.simpleMessage("显示"),
    "showLess": MessageLookupByLibrary.simpleMessage("收起"),
    "showMore": MessageLookupByLibrary.simpleMessage("展开"),
    "showNotificationStopAction": MessageLookupByLibrary.simpleMessage(
      "通知栏显示停止按钮",
    ),
    "showPassword": MessageLookupByLibrary.simpleMessage("显示密码"),
    "shrink": MessageLookupByLibrary.simpleMessage("紧凑"),
    "sidebarBlur": MessageLookupByLibrary.simpleMessage("侧边栏背景模糊"),
    "sidebarBlurDesc": MessageLookupByLibrary.simpleMessage("侧边栏透出窗口后方模糊的桌面"),
    "silentLaunch": MessageLookupByLibrary.simpleMessage("静默启动"),
    "silentLaunchDesc": MessageLookupByLibrary.simpleMessage("启动时不显示窗口"),
    "singleAdd": MessageLookupByLibrary.simpleMessage("单条添加"),
    "singleValueTip": m81,
    "size": MessageLookupByLibrary.simpleMessage("尺寸"),
    "slide": MessageLookupByLibrary.simpleMessage("滑动"),
    "socksPort": MessageLookupByLibrary.simpleMessage("Socks端口"),
    "sort": MessageLookupByLibrary.simpleMessage("排序"),
    "source": MessageLookupByLibrary.simpleMessage("来源"),
    "sourceAcceptRevision": MessageLookupByLibrary.simpleMessage("接受此版本"),
    "sourceAcceptedCapabilities": m82,
    "sourceAcceptedDns": m83,
    "sourceAcceptedProtocols": m84,
    "sourceAcceptedRevisions": m85,
    "sourceAppliedNotSaved": MessageLookupByLibrary.simpleMessage("已应用，恢复尚未保存"),
    "sourceAppliedRevision": MessageLookupByLibrary.simpleMessage("采用版本"),
    "sourceAutomaticAllowed": MessageLookupByLibrary.simpleMessage("允许自动维护"),
    "sourceAutomaticStopped": MessageLookupByLibrary.simpleMessage("已停止自动维护"),
    "sourceBatchPreparing": MessageLookupByLibrary.simpleMessage("正在加载关联数据源…"),
    "sourceBatchScope": MessageLookupByLibrary.simpleMessage(
      "统一审核此订阅、最终配置及列出的全部关联数据源。确认仅批准本次展示的内容快照。",
    ),
    "sourceBinaryMaterial": MessageLookupByLibrary.simpleMessage(
      "二进制 RuleSet：只接受这些精确字节。原解析器验证材料前，规则数量未知。",
    ),
    "sourceCapabilitiesChanged": MessageLookupByLibrary.simpleMessage(
      "节点能力或节点组绑定发生变化。",
    ),
    "sourceCodeChanged": MessageLookupByLibrary.simpleMessage("脚本的精确代码发生变化。"),
    "sourceConfigParsed": MessageLookupByLibrary.simpleMessage(
      "已解析 · 关联来源需分别核验",
    ),
    "sourceConfigurationUnavailable": MessageLookupByLibrary.simpleMessage(
      "完整来源配置暂不可用的原因",
    ),
    "sourceDeclaredCapabilities": m86,
    "sourceDefaultExit": m87,
    "sourceDelegateMaintenance": MessageLookupByLibrary.simpleMessage(
      "允许在此范围内维护",
    ),
    "sourceDnsChanged": MessageLookupByLibrary.simpleMessage("DNS 服务或其策略发生变化。"),
    "sourceEntryChanged": MessageLookupByLibrary.simpleMessage(
      "监听、隧道或控制能力发生变化。",
    ),
    "sourceFinalUse": MessageLookupByLibrary.simpleMessage("最终配置"),
    "sourceFirstUse": MessageLookupByLibrary.simpleMessage("此来源尚未获准使用。"),
    "sourceImplicitDirect": MessageLookupByLibrary.simpleMessage(
      "隐式 DIRECT 回退",
    ),
    "sourceInspectMaterial": MessageLookupByLibrary.simpleMessage(
      "查看来源原文（可能包含凭据）",
    ),
    "sourceIp": MessageLookupByLibrary.simpleMessage("源IP"),
    "sourceLoadCached": MessageLookupByLibrary.simpleMessage("已就绪 · 已核验快照"),
    "sourceLoadChecking": MessageLookupByLibrary.simpleMessage("正在检查订阅和来源权限…"),
    "sourceLoadDownloading": MessageLookupByLibrary.simpleMessage("正在下载…"),
    "sourceLoadFailed": MessageLookupByLibrary.simpleMessage("失败"),
    "sourceLoadProgress": m88,
    "sourceLoadQueued": MessageLookupByLibrary.simpleMessage("等待中"),
    "sourceLoadReady": MessageLookupByLibrary.simpleMessage("已就绪"),
    "sourceLoadVerifying": MessageLookupByLibrary.simpleMessage("正在核验…"),
    "sourceLocalPolicy": MessageLookupByLibrary.simpleMessage("本地策略"),
    "sourceMaintenanceLimits": MessageLookupByLibrary.simpleMessage(
      "仅已证明处于此版本能力范围内的变化可自动更新，其它变化保持待确认。已有连接继续使用原 socket；资源预算可能延后采用。",
    ),
    "sourceMaterialCounts": m89,
    "sourceMaterialUnavailable": MessageLookupByLibrary.simpleMessage(
      "无法加载关联数据源。请检查其地址、网络连接和请求出口，然后重试。",
    ),
    "sourceNoPermissions": MessageLookupByLibrary.simpleMessage("尚无已接受的来源权限。"),
    "sourceNodeImportHint": MessageLookupByLibrary.simpleMessage(
      "已获取的节点可以使用。此配置使用应用网络设置和一个代理分组，暂不采用来源的规则、DNS 和原分组。保留原 URL，关闭自动更新；手动更新可重试完整配置。",
    ),
    "sourceNodeUse": MessageLookupByLibrary.simpleMessage("作为 provider 使用的节点"),
    "sourceNotDeclared": MessageLookupByLibrary.simpleMessage("此来源未声明"),
    "sourceNotDelegated": MessageLookupByLibrary.simpleMessage("尚未委托自动维护。"),
    "sourceOwnDefaultConflict": MessageLookupByLibrary.simpleMessage(
      "自有规则必须以唯一一条 MATCH 规则结束，并使用你选择的未命中出口。",
    ),
    "sourceOwnDefaultRequired": MessageLookupByLibrary.simpleMessage(
      "应用自有规则前，请明确选择未匹配流量的出口。",
    ),
    "sourceOwnRoutingHint": MessageLookupByLibrary.simpleMessage(
      "关闭后排除来源分流、监听和隧道。自有规则必须明确未匹配流量的出口；清空规则不会恢复来源分流。DNS 和节点组分别授权。",
    ),
    "sourcePartialBlocked": MessageLookupByLibrary.simpleMessage(
      "以下必要依赖缺失，无法生成部分配置",
    ),
    "sourcePartialConfigurationHint": MessageLookupByLibrary.simpleMessage(
      "部分配置：保留可用规则、分组、DNS 和已审核的来源内容。接受前请检查停用项及默认出口。保留原订阅 URL，关闭自动刷新；手动更新可恢复完整配置。",
    ),
    "sourcePartialGroups": MessageLookupByLibrary.simpleMessage("将停用的分组"),
    "sourcePartialImportHint": MessageLookupByLibrary.simpleMessage(
      "所有来源均已尝试。保留可用内容，下方列出缺失依赖。可重试失败来源，或审核可用配置。",
    ),
    "sourcePartialMissing": MessageLookupByLibrary.simpleMessage("不可用来源"),
    "sourcePartialRules": MessageLookupByLibrary.simpleMessage(
      "将停用的规则（其它规则保留原顺序）",
    ),
    "sourcePartialSettings": MessageLookupByLibrary.simpleMessage(
      "将停用的 DNS 策略",
    ),
    "sourcePermissionEffects": MessageLookupByLibrary.simpleMessage(
      "每项操作仅影响所列用途。停止自动维护会保留已接受内容；停止使用会关闭受影响连接并取消重放资格。其他用途保留各自权限。",
    ),
    "sourcePermissions": MessageLookupByLibrary.simpleMessage("来源权限"),
    "sourcePermissionsUnavailable": MessageLookupByLibrary.simpleMessage(
      "无法读取或核验来源权限。请重试；若持续失败，请查看应用日志。",
    ),
    "sourceProfileUse": MessageLookupByLibrary.simpleMessage("Profile 配置内容"),
    "sourceProposedDns": m90,
    "sourceProtocols": m91,
    "sourceProviderChanged": MessageLookupByLibrary.simpleMessage(
      "Provider 或其下载来源发生变化。",
    ),
    "sourceRecoveryDescription": MessageLookupByLibrary.simpleMessage(
      "核对本机已保存的配置、脚本和权限。核对将停止当前配置的流量处理，并丢弃未完成的确认。之后请重新审查来源并应用配置。",
    ),
    "sourceRecoveryTitle": MessageLookupByLibrary.simpleMessage("核对未完成的保存"),
    "sourceRecoveryUnavailable": MessageLookupByLibrary.simpleMessage(
      "来源权限已更改，但恢复 checkpoint 未能更新，重启恢复不可用。",
    ),
    "sourceRelatedSourcesCount": m92,
    "sourceRematchDenied": MessageLookupByLibrary.simpleMessage(
      "排除来源路由时，不能使用 REMATCH 节点。",
    ),
    "sourceReviewPending": MessageLookupByLibrary.simpleMessage("待审核"),
    "sourceReviewRequired": MessageLookupByLibrary.simpleMessage(
      "来源变化需要审查后才能使用。",
    ),
    "sourceReviewScope": MessageLookupByLibrary.simpleMessage(
      "仅接受你信任其选择节点和此版本能力的来源。接受材料与实际应用是不同步骤。",
    ),
    "sourceReviewTitle": MessageLookupByLibrary.simpleMessage("审查来源"),
    "sourceRoutingChanged": MessageLookupByLibrary.simpleMessage(
      "分流、固定保护或默认出口发生变化。",
    ),
    "sourceRoutingExcluded": MessageLookupByLibrary.simpleMessage(
      "此内容包含已排除的路由能力。请移除这些能力，或明确更改来源路由选择。",
    ),
    "sourceRuleDelegation": m93,
    "sourceRuleOrigin": MessageLookupByLibrary.simpleMessage("规则来源"),
    "sourceRuleSetUse": MessageLookupByLibrary.simpleMessage("RuleSet 内容"),
    "sourceSavePending": MessageLookupByLibrary.simpleMessage("保存待补齐"),
    "sourceScriptScope": MessageLookupByLibrary.simpleMessage(
      "此代码可读取配置并写入 console。接受前不会执行，输出另行审查；接受代码不等于接受其任意输出。",
    ),
    "sourceScriptTitle": MessageLookupByLibrary.simpleMessage("审查脚本"),
    "sourceStatusChecking": MessageLookupByLibrary.simpleMessage("正在检查来源权限…"),
    "sourceStatusRetry": MessageLookupByLibrary.simpleMessage("权限状态暂不可用 · 重试"),
    "sourceStopAutomatic": MessageLookupByLibrary.simpleMessage("停止自动维护"),
    "sourceStopUse": MessageLookupByLibrary.simpleMessage("停止使用此内容"),
    "sourceStorageFull": MessageLookupByLibrary.simpleMessage(
      "已达到来源存储上限，本次操作未完成。",
    ),
    "sourceSubscriptionReview": MessageLookupByLibrary.simpleMessage("审核订阅"),
    "sourceUnknownChanged": MessageLookupByLibrary.simpleMessage(
      "存在无法安全分类的有效变化。",
    ),
    "sourceUseAvailableConfiguration": MessageLookupByLibrary.simpleMessage(
      "审核可用配置",
    ),
    "sourceUseRouting": MessageLookupByLibrary.simpleMessage("使用来源分流规则"),
    "specialProxy": MessageLookupByLibrary.simpleMessage("特殊代理"),
    "specialRules": MessageLookupByLibrary.simpleMessage("特殊规则"),
    "speedStatistics": MessageLookupByLibrary.simpleMessage("网速统计"),
    "splitStrategy": MessageLookupByLibrary.simpleMessage("分流策略"),
    "splitStrategyNotEmpty": MessageLookupByLibrary.simpleMessage("分流策略不能为空"),
    "ssidsEmpty": MessageLookupByLibrary.simpleMessage("SSIDs为空"),
    "stackMode": MessageLookupByLibrary.simpleMessage("栈模式"),
    "standard": MessageLookupByLibrary.simpleMessage("标准"),
    "standardModeDesc": MessageLookupByLibrary.simpleMessage(
      "标准模式，覆写基础配置，提供简单追加规则能力",
    ),
    "start": MessageLookupByLibrary.simpleMessage("启动"),
    "startFromScratch": MessageLookupByLibrary.simpleMessage("从零开始"),
    "startVpn": MessageLookupByLibrary.simpleMessage("正在启动VPN…"),
    "startupAndBackground": MessageLookupByLibrary.simpleMessage("启动与后台"),
    "status": MessageLookupByLibrary.simpleMessage("状态"),
    "statusDesc": MessageLookupByLibrary.simpleMessage("关闭后将使用系统DNS"),
    "stop": MessageLookupByLibrary.simpleMessage("暂停"),
    "stopVpn": MessageLookupByLibrary.simpleMessage("正在停止VPN…"),
    "strategy": MessageLookupByLibrary.simpleMessage("策略"),
    "style": MessageLookupByLibrary.simpleMessage("风格"),
    "subRule": MessageLookupByLibrary.simpleMessage("子规则"),
    "subRuleEmpty": MessageLookupByLibrary.simpleMessage("子规则为空"),
    "subRuleNotEmpty": MessageLookupByLibrary.simpleMessage("子规则不能为空"),
    "submit": MessageLookupByLibrary.simpleMessage("提交"),
    "subscriptionInfo": MessageLookupByLibrary.simpleMessage("订阅信息"),
    "suspended": MessageLookupByLibrary.simpleMessage("挂起中…"),
    "switchProfile": MessageLookupByLibrary.simpleMessage("切换配置"),
    "sync": MessageLookupByLibrary.simpleMessage("同步"),
    "system": MessageLookupByLibrary.simpleMessage("系统"),
    "systemApp": MessageLookupByLibrary.simpleMessage("系统应用"),
    "systemProxy": MessageLookupByLibrary.simpleMessage("系统代理"),
    "tab": MessageLookupByLibrary.simpleMessage("标签页"),
    "tabAnimation": MessageLookupByLibrary.simpleMessage("选项卡动画"),
    "tapToAuthorize": MessageLookupByLibrary.simpleMessage("点击授权"),
    "tcpConcurrent": MessageLookupByLibrary.simpleMessage("TCP并发"),
    "testInterval": MessageLookupByLibrary.simpleMessage("测试间隔"),
    "testUrl": MessageLookupByLibrary.simpleMessage("测速链接"),
    "testWhenUsed": MessageLookupByLibrary.simpleMessage("使用时测试"),
    "textScale": MessageLookupByLibrary.simpleMessage("文本缩放"),
    "textScalePreview": MessageLookupByLibrary.simpleMessage("应用内的文字将以这个大小显示"),
    "theme": MessageLookupByLibrary.simpleMessage("主题"),
    "themeColor": MessageLookupByLibrary.simpleMessage("主题色彩"),
    "themeDesc": MessageLookupByLibrary.simpleMessage("设置深色模式，调整色彩"),
    "themeMode": MessageLookupByLibrary.simpleMessage("主题模式"),
    "tight": MessageLookupByLibrary.simpleMessage("紧凑"),
    "time": MessageLookupByLibrary.simpleMessage("时间"),
    "timeout": MessageLookupByLibrary.simpleMessage("超时"),
    "tip": MessageLookupByLibrary.simpleMessage("提示"),
    "toggle": MessageLookupByLibrary.simpleMessage("切换"),
    "tolerance": MessageLookupByLibrary.simpleMessage("容差"),
    "tonalSpotScheme": MessageLookupByLibrary.simpleMessage("调性点缀"),
    "tools": MessageLookupByLibrary.simpleMessage("工具"),
    "torch": MessageLookupByLibrary.simpleMessage("手电筒"),
    "total": MessageLookupByLibrary.simpleMessage("总计"),
    "totalTraffic": MessageLookupByLibrary.simpleMessage("总流量"),
    "tproxyPort": MessageLookupByLibrary.simpleMessage("Tproxy端口"),
    "trafficUsage": MessageLookupByLibrary.simpleMessage("流量统计"),
    "tun": MessageLookupByLibrary.simpleMessage("虚拟网卡"),
    "tunDesc": MessageLookupByLibrary.simpleMessage("仅在管理员模式生效"),
    "turnOff": MessageLookupByLibrary.simpleMessage("关闭"),
    "turnOn": MessageLookupByLibrary.simpleMessage("开启"),
    "undo": MessageLookupByLibrary.simpleMessage("撤销"),
    "unifiedDelay": MessageLookupByLibrary.simpleMessage("统一延迟"),
    "unknown": MessageLookupByLibrary.simpleMessage("未知"),
    "unknownNetworkError": MessageLookupByLibrary.simpleMessage("未知网络错误"),
    "unmaximize": MessageLookupByLibrary.simpleMessage("向下还原"),
    "unnamed": MessageLookupByLibrary.simpleMessage("未命名"),
    "unpinWindow": MessageLookupByLibrary.simpleMessage("取消置顶"),
    "update": MessageLookupByLibrary.simpleMessage("更新"),
    "upload": MessageLookupByLibrary.simpleMessage("上传"),
    "url": MessageLookupByLibrary.simpleMessage("URL"),
    "urlDesc": MessageLookupByLibrary.simpleMessage("通过URL获取配置文件"),
    "urlTip": m94,
    "useHosts": MessageLookupByLibrary.simpleMessage("使用Hosts"),
    "useProfile": MessageLookupByLibrary.simpleMessage("使用"),
    "useSystemHosts": MessageLookupByLibrary.simpleMessage("使用系统Hosts"),
    "usedTraffic": MessageLookupByLibrary.simpleMessage("已用流量"),
    "userAgent": MessageLookupByLibrary.simpleMessage("用户代理"),
    "value": MessageLookupByLibrary.simpleMessage("值"),
    "vibrantScheme": MessageLookupByLibrary.simpleMessage("活力"),
    "view": MessageLookupByLibrary.simpleMessage("查看"),
    "vpnConfigChangeDetected": MessageLookupByLibrary.simpleMessage(
      "检测到VPN相关配置改动",
    ),
    "vpnEnableDesc": MessageLookupByLibrary.simpleMessage(
      "通过VpnService自动路由系统所有流量",
    ),
    "vpnTip": MessageLookupByLibrary.simpleMessage("重启VPN后改变生效"),
    "webDAVConfiguration": MessageLookupByLibrary.simpleMessage("WebDAV配置"),
    "whitelistMode": MessageLookupByLibrary.simpleMessage("白名单模式"),
    "writeToSystem": MessageLookupByLibrary.simpleMessage("写入系统"),
    "writeToSystemDesc": MessageLookupByLibrary.simpleMessage(
      "同时设置系统时钟，Android上不生效",
    ),
    "yearsAgo": m95,
    "yes": MessageLookupByLibrary.simpleMessage("是"),
    "zhCN": MessageLookupByLibrary.simpleMessage("中文简体"),
  };
}
