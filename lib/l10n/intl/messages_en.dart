// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a en locale. All the
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
  String get localeName => 'en';

  static String m0(active, count) => "Active ${active}/${count}";

  static String m1(id) => "Connection ${id}";

  static String m2(active, count) => "Active ${active} · Observed ${count}";

  static String m3(time) => "Last activity: ${time}";

  static String m4(ip, country) =>
      "Local public IP (recent observation): ${ip} · ${country}";

  static String m5(count) => "Show ${count} more addresses";

  static String m6(ip, country) =>
      "Proxy server: ${ip} · ${country}. This is not the website-observed exit.";

  static String m7(count) => "This run · latest ${count} observed connections";

  static String m8(rules, exits) =>
      "${rules} rule results · ${exits} exit paths";

  static String m9(uid) => "UID ${uid}";

  static String m10(count, skipped) =>
      "${count} to add, ${skipped} skipped as existing";

  static String m11(phase) => "Previous stage: ${phase}";

  static String m12(reason) => "System exit reason: ${reason}";

  static String m13(code) =>
      "Windows refused to run FlClashCore.exe (error ${code}). An app control policy such as Smart App Control or AppLocker blocks unsigned programs; allow FlClash in that policy or turn it off, then try again.";

  static String m14(name) =>
      "The system reported an abnormal exit during startup. Previous profile: ${name}. Automatic setup is skipped this time; your current selection and files are preserved.";

  static String m15(url) => "Do you want to create a profile from ${url}?";

  static String m16(count) =>
      "${Intl.plural(count, one: '1 day ago', other: '${count} days ago')}";

  static String m17(reason) => "Delay test did not complete: ${reason}";

  static String m18(label) =>
      "Are you sure you want to delete the selected ${label}?";

  static String m19(label) => "Are you sure you want to delete this ${label}?";

  static String m20(label) => "${label} details";

  static String m21(label) => "${label} cannot be empty";

  static String m22(label) => "${label} already exists";

  static String m23(name) => "${name} is already up to date";

  static String m24(name) => "${name} updated";

  static String m25(action) =>
      "Already used by “${action}”. Saving moves it here.";

  static String m26(modifiers) => "Include at least one of ${modifiers}";

  static String m27(count) =>
      "${Intl.plural(count, one: '1 hour ago', other: '${count} hours ago')}";

  static String m28(count) =>
      "${Intl.plural(count, one: '1 hour', other: '${count} hours')}";

  static String m29(target) => "${target} is an invalid policy";

  static String m30(proxyName) => "${proxyName} is an invalid proxy";

  static String m31(providerName) =>
      "${providerName} is an invalid proxy provider";

  static String m32(ruleSet) => "${ruleSet} is an invalid rule set";

  static String m33(subRule) => "${subRule} is an invalid SUB_RULE";

  static String m34(line, message) => "Line ${line}: ${message}";

  static String m35(name) => "Actions for ${name}";

  static String m36(name) => "Current exit: ${name}";

  static String m37(name) => "Delete group “${name}”?";

  static String m38(name) => "Unavailable node: ${name}";

  static String m39(count) => "${count} nodes";

  static String m40(name) => "Preferred node: ${name}";

  static String m41(count) => "Added to ${count} groups";

  static String m42(name) => "${name}";

  static String m43(appName) =>
      "1. Open System Settings > Privacy & Security\n2. Choose Location Services\n3. Find and check ${appName} in the list\n\nWhen you are done, return to the app to continue. Thank you for your cooperation.";

  static String m44(label, max) => "${label} must be at most ${max} characters";

  static String m45(size) => "Released ${size}";

  static String m46(count) =>
      "${Intl.plural(count, one: '1 minute ago', other: '${count} minutes ago')}";

  static String m47(count) =>
      "${Intl.plural(count, one: '1 month ago', other: '${count} months ago')}";

  static String m48(code) =>
      "The server denied access (HTTP ${code}). The link may have expired, or the credentials are wrong";

  static String m49(code) => "The server rejected the request (HTTP ${code})";

  static String m50(code) =>
      "Nothing was found at this address (HTTP ${code}). Check that the URL is correct";

  static String m51(detail) => "Network request failed: ${detail}";

  static String m52(code) =>
      "The server ran into a problem (HTTP ${code}). Try again later";

  static String m53(label) => "No ${label} yet";

  static String m54(label) => "${label} must be a number";

  static String m55(message) => "The core cannot parse this proxy: ${message}";

  static String m56(name) =>
      "The name ${name} is already used by another proxy or proxy group";

  static String m57(path) =>
      "Proxy groups reference each other in a loop: ${path}";

  static String m58(names) => "These proxy providers do not exist: ${names}";

  static String m59(names) =>
      "These proxies or policies do not exist: ${names}";

  static String m60(name) =>
      "${name} is a built-in policy name and cannot be used here";

  static String m61(names) =>
      "The profile\'s own proxy groups name proxies that the custom proxies no longer include: ${names}";

  static String m62(count) =>
      "${count} items have problems, and applying this override may fail";

  static String m63(location) =>
      "Check ${location}. Complete or correct this field before previewing.";

  static String m64(locations) =>
      "This resource is used at: ${locations}. Change those references before deleting it.";

  static String m65(label) => "${label} must be between 1024 and 49151";

  static String m66(label, profiles) =>
      "${label} is still used by the custom proxy groups or rules of ${profiles}. Remove it there first";

  static String m67(profiles, label) =>
      "The subscriptions of ${profiles} already have ${label}, so those profiles would switch to theirs. Choose another name";

  static String m68(count) =>
      "${Intl.plural(count, one: '1 proxy', other: '${count} proxies')}";

  static String m69(host) =>
      "The current configuration cannot fetch this item. Allow this operation to connect directly to ${host}? This permission ends when the operation finishes or its source changes.";

  static String m70(target) => "GLOBAL (current selection: ${target})";

  static String m71(count) =>
      "${Intl.plural(count, one: '1 rule', other: '${count} rules')}";

  static String m72(appName) => "${appName} (Safe mode)";

  static String m73(count) =>
      "${Intl.plural(count, one: '1 second', other: '${count} seconds')}";

  static String m74(count) => "${count} selected";

  static String m75(time) => "Checked at ${time}";

  static String m76(region) => "Reported region: ${region}";

  static String m77(milliseconds) =>
      "Total elapsed (including queue and body): ${milliseconds} ms";

  static String m78(result) => "Expired: ${result}";

  static String m79(hosts) => "Recipients: ${hosts}";

  static String m80(label) => "${label} must be a single item";

  static String m81(features) => "Accepted declared capabilities: ${features}";

  static String m82(services) => "Accepted DNS scope: ${services}";

  static String m83(protocols) => "Accepted node protocols: ${protocols}";

  static String m84(count) => "Accepted revisions: ${count}";

  static String m85(features) => "Declared capabilities: ${features}";

  static String m86(target) => "Source default exit: ${target}";

  static String m87(ready, total) => "Ready: ${ready}/${total}";

  static String m88(nodes, rules) =>
      "Source material: ${nodes} nodes, ${rules} rules";

  static String m89(services) => "Proposed DNS services: ${services}";

  static String m90(protocols) => "Node protocols: ${protocols}";

  static String m91(count) => "Associated sources: ${count}";

  static String m92(targets) =>
      "Delegated proxy blocks: ${targets}. Conditions may cover any domain or IP. Fixed protection rules and the default stay unchanged; deletions that might expand DIRECT still need review.";

  static String m93(label) => "${label} must be a URL";

  static String m94(count) =>
      "${Intl.plural(count, one: '1 year ago', other: '${count} years ago')}";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "about": MessageLookupByLibrary.simpleMessage("About"),
    "accessControl": MessageLookupByLibrary.simpleMessage("Access control"),
    "accessControlAllowDesc": MessageLookupByLibrary.simpleMessage(
      "Only selected apps go through the VPN",
    ),
    "accessControlDesc": MessageLookupByLibrary.simpleMessage(
      "Control which apps use the proxy",
    ),
    "accessControlDisabledDesc": MessageLookupByLibrary.simpleMessage(
      "App access control is disabled",
    ),
    "accessControlNotAllowDesc": MessageLookupByLibrary.simpleMessage(
      "Selected apps are excluded from the VPN",
    ),
    "accessControlSettings": MessageLookupByLibrary.simpleMessage(
      "Access control settings",
    ),
    "account": MessageLookupByLibrary.simpleMessage("Account"),
    "action": MessageLookupByLibrary.simpleMessage("Action"),
    "actionDelayTest": MessageLookupByLibrary.simpleMessage("Test all delays"),
    "actionDirectMode": MessageLookupByLibrary.simpleMessage("Direct mode"),
    "actionGlobalMode": MessageLookupByLibrary.simpleMessage("Global mode"),
    "actionMode": MessageLookupByLibrary.simpleMessage("Switch mode"),
    "actionProxy": MessageLookupByLibrary.simpleMessage("System proxy"),
    "actionRuleMode": MessageLookupByLibrary.simpleMessage("Rule mode"),
    "actionStart": MessageLookupByLibrary.simpleMessage("Start/Stop"),
    "actionTun": MessageLookupByLibrary.simpleMessage("TUN"),
    "actionUpdateProfiles": MessageLookupByLibrary.simpleMessage(
      "Update profiles",
    ),
    "actionView": MessageLookupByLibrary.simpleMessage("Show/Hide"),
    "activityActive": MessageLookupByLibrary.simpleMessage("Active now"),
    "activityActiveFilterUnavailable": MessageLookupByLibrary.simpleMessage(
      "Active state is unconfirmed. Showing retained targets.",
    ),
    "activityAllApps": MessageLookupByLibrary.simpleMessage("All apps"),
    "activityAllAppsForTarget": MessageLookupByLibrary.simpleMessage(
      "All apps for this target",
    ),
    "activityCatalogueUnavailable": MessageLookupByLibrary.simpleMessage(
      "App directory unavailable; observed activity is still shown.",
    ),
    "activityChecking": MessageLookupByLibrary.simpleMessage(
      "Checking active connections…",
    ),
    "activityCompactCounts": m0,
    "activityConfiguration": MessageLookupByLibrary.simpleMessage(
      "Connection configuration",
    ),
    "activityConnectionEnded": MessageLookupByLibrary.simpleMessage("Ended"),
    "activityConnectionId": m1,
    "activityConnectionIdLabel": MessageLookupByLibrary.simpleMessage(
      "Connection ID",
    ),
    "activityConnectionState": MessageLookupByLibrary.simpleMessage(
      "Connection state",
    ),
    "activityConnectionsUnconfirmed": MessageLookupByLibrary.simpleMessage(
      "Active state is unconfirmed. Showing retained connections.",
    ),
    "activityCounts": m2,
    "activityExcludedSetting": MessageLookupByLibrary.simpleMessage(
      "Current settings: exclude this app",
    ),
    "activityExits": MessageLookupByLibrary.simpleMessage(
      "Observed exit paths",
    ),
    "activityFewerAddresses": MessageLookupByLibrary.simpleMessage(
      "Show fewer addresses",
    ),
    "activityIdentityUncertain": MessageLookupByLibrary.simpleMessage(
      "Application could not be identified",
    ),
    "activityIncludedSetting": MessageLookupByLibrary.simpleMessage(
      "Current settings: include this app",
    ),
    "activityIncomplete": MessageLookupByLibrary.simpleMessage(
      "Observation has gaps",
    ),
    "activityLast": m3,
    "activityLastLabel": MessageLookupByLibrary.simpleMessage("Last activity"),
    "activityLoadingApps": MessageLookupByLibrary.simpleMessage(
      "Loading app names…",
    ),
    "activityLocalPublicCountry": m4,
    "activityMoreAddresses": m5,
    "activityNoActive": MessageLookupByLibrary.simpleMessage(
      "No confirmed active connections",
    ),
    "activityNoMatches": MessageLookupByLibrary.simpleMessage(
      "No matching apps",
    ),
    "activityNoObserved": MessageLookupByLibrary.simpleMessage(
      "No activity observed yet",
    ),
    "activityNoTargetMatches": MessageLookupByLibrary.simpleMessage(
      "No matching targets",
    ),
    "activityObservationScope": MessageLookupByLibrary.simpleMessage(
      "Observation scope",
    ),
    "activityObservedAddresses": MessageLookupByLibrary.simpleMessage(
      "Observed destination addresses",
    ),
    "activityObservedDownload": MessageLookupByLibrary.simpleMessage(
      "Observed download",
    ),
    "activityObservedUpload": MessageLookupByLibrary.simpleMessage(
      "Observed upload",
    ),
    "activityObserving": MessageLookupByLibrary.simpleMessage(
      "Observing VPN activity",
    ),
    "activityOnlyActiveConnections": MessageLookupByLibrary.simpleMessage(
      "Only show active connections",
    ),
    "activityOnlyActiveTargets": MessageLookupByLibrary.simpleMessage(
      "Only show active targets",
    ),
    "activityPaused": MessageLookupByLibrary.simpleMessage(
      "Observation paused · retained activity",
    ),
    "activityPending": MessageLookupByLibrary.simpleMessage("Unconfirmed"),
    "activityProxyServerAddress": MessageLookupByLibrary.simpleMessage(
      "Proxy server address",
    ),
    "activityProxyServerCountry": m6,
    "activityRecent": MessageLookupByLibrary.simpleMessage("Recent activity"),
    "activityRetention": m7,
    "activityRouteCounts": m8,
    "activityRules": MessageLookupByLibrary.simpleMessage("Observed rules"),
    "activityRulesBypassed": MessageLookupByLibrary.simpleMessage(
      "Rules bypassed in Global or Direct mode",
    ),
    "activityScopeHelp": MessageLookupByLibrary.simpleMessage(
      "Only traffic observed by FlClash is included. Counts refer to retained connections, not HTTP requests or complete history. Records stay in memory and reset when the process restarts. Background suspension, event delivery gaps or the retention limit can omit activity. Current access settings do not prove which settings a running VPN has adopted.",
    ),
    "activitySearchApps": MessageLookupByLibrary.simpleMessage(
      "Search app name or package",
    ),
    "activitySearchTargets": MessageLookupByLibrary.simpleMessage(
      "Search domain or IP address",
    ),
    "activitySharedIdentityHelp": MessageLookupByLibrary.simpleMessage(
      "These apps share a UID. The connection cannot be attributed to a single app.",
    ),
    "activitySharedUid": MessageLookupByLibrary.simpleMessage(
      "Shared application identity",
    ),
    "activityShowAllApps": MessageLookupByLibrary.simpleMessage(
      "Show all apps",
    ),
    "activitySnapshotFailed": MessageLookupByLibrary.simpleMessage(
      "Could not refresh · active state unconfirmed",
    ),
    "activityUid": m9,
    "activityUnknownApp": MessageLookupByLibrary.simpleMessage("Unknown app"),
    "activityUnknownTarget": MessageLookupByLibrary.simpleMessage(
      "Unknown target",
    ),
    "activityVpnObserved": MessageLookupByLibrary.simpleMessage(
      "VPN capture observed for these connections",
    ),
    "add": MessageLookupByLibrary.simpleMessage("Add"),
    "addCustomProxy": MessageLookupByLibrary.simpleMessage("Add proxy"),
    "addOverrideEntry": MessageLookupByLibrary.simpleMessage(
      "Add override entry",
    ),
    "addProfile": MessageLookupByLibrary.simpleMessage("Add profile"),
    "addProxies": MessageLookupByLibrary.simpleMessage("Add proxies"),
    "addProxyGroup": MessageLookupByLibrary.simpleMessage("Add proxy group"),
    "addProxyProviders": MessageLookupByLibrary.simpleMessage(
      "Add proxy providers",
    ),
    "addRule": MessageLookupByLibrary.simpleMessage("Add rule"),
    "addSsid": MessageLookupByLibrary.simpleMessage("Add SSID"),
    "addWidget": MessageLookupByLibrary.simpleMessage("Add widget"),
    "addedRules": MessageLookupByLibrary.simpleMessage("Added rules"),
    "additionalParameters": MessageLookupByLibrary.simpleMessage(
      "Additional parameters",
    ),
    "address": MessageLookupByLibrary.simpleMessage("Address"),
    "addressHelp": MessageLookupByLibrary.simpleMessage(
      "WebDAV server address",
    ),
    "addressTip": MessageLookupByLibrary.simpleMessage(
      "Please enter a valid WebDAV address",
    ),
    "advancedConfig": MessageLookupByLibrary.simpleMessage(
      "Advanced configuration",
    ),
    "advancedConfigDesc": MessageLookupByLibrary.simpleMessage(
      "Network, DNS, added rules, and scripts",
    ),
    "agree": MessageLookupByLibrary.simpleMessage("Agree"),
    "allowBypass": MessageLookupByLibrary.simpleMessage(
      "Allow apps to bypass VPN",
    ),
    "allowLan": MessageLookupByLibrary.simpleMessage("Allow LAN"),
    "androidServiceProxyOnly": MessageLookupByLibrary.simpleMessage(
      "Proxy only",
    ),
    "androidServiceStopped": MessageLookupByLibrary.simpleMessage("Stopped"),
    "androidServiceStopping": MessageLookupByLibrary.simpleMessage(
      "Stopping service",
    ),
    "androidServiceSuspended": MessageLookupByLibrary.simpleMessage(
      "Suspended",
    ),
    "androidServiceTitle": MessageLookupByLibrary.simpleMessage(
      "Android service",
    ),
    "androidServiceUnavailable": MessageLookupByLibrary.simpleMessage(
      "Service unavailable",
    ),
    "androidServiceVpnActive": MessageLookupByLibrary.simpleMessage(
      "VPN active",
    ),
    "answers": MessageLookupByLibrary.simpleMessage("Answers"),
    "app": MessageLookupByLibrary.simpleMessage("App"),
    "appAccessControl": MessageLookupByLibrary.simpleMessage(
      "App access control",
    ),
    "appIconDesign": MessageLookupByLibrary.simpleMessage("App icon design"),
    "appendSystemDns": MessageLookupByLibrary.simpleMessage(
      "Append system DNS",
    ),
    "applicationNetwork": MessageLookupByLibrary.simpleMessage(
      "Application network",
    ),
    "appliedProfile": MessageLookupByLibrary.simpleMessage(
      "Active configuration",
    ),
    "authentication": MessageLookupByLibrary.simpleMessage("Authentication"),
    "authenticationDesc": MessageLookupByLibrary.simpleMessage(
      "Require credentials on the local proxy port to keep other local apps from using it",
    ),
    "authenticationSystemProxyDesc": MessageLookupByLibrary.simpleMessage(
      "Not applied while authentication is enabled",
    ),
    "authorize": MessageLookupByLibrary.simpleMessage("Authorize"),
    "authorized": MessageLookupByLibrary.simpleMessage("Authorized"),
    "auto": MessageLookupByLibrary.simpleMessage("Auto"),
    "autoCloseConnections": MessageLookupByLibrary.simpleMessage(
      "Auto close connections",
    ),
    "autoCloseConnectionsDesc": MessageLookupByLibrary.simpleMessage(
      "Close connections automatically after switching nodes",
    ),
    "autoLaunch": MessageLookupByLibrary.simpleMessage("Auto launch"),
    "autoLaunchDesc": MessageLookupByLibrary.simpleMessage(
      "Launch automatically at system startup",
    ),
    "autoRun": MessageLookupByLibrary.simpleMessage("Auto run"),
    "autoRunDesc": MessageLookupByLibrary.simpleMessage(
      "Run automatically when the app opens",
    ),
    "autoSetSystemDns": MessageLookupByLibrary.simpleMessage(
      "Auto-set system DNS",
    ),
    "autoUpdate": MessageLookupByLibrary.simpleMessage("Auto update"),
    "autoUpdateInterval": MessageLookupByLibrary.simpleMessage(
      "Auto-update interval (minutes)",
    ),
    "back": MessageLookupByLibrary.simpleMessage("Back"),
    "backgroundStartFailed": MessageLookupByLibrary.simpleMessage(
      "FlClash could not start. Open the app to review pending sources or check the error.",
    ),
    "backup": MessageLookupByLibrary.simpleMessage("Backup"),
    "backupAndRestore": MessageLookupByLibrary.simpleMessage(
      "Backup and restore",
    ),
    "backupAndRestoreDesc": MessageLookupByLibrary.simpleMessage(
      "Sync data via WebDAV or files",
    ),
    "backupFromNewerVersion": MessageLookupByLibrary.simpleMessage(
      "This backup comes from a newer version of the app. Update the app before restoring it",
    ),
    "backupSuccess": MessageLookupByLibrary.simpleMessage("Backup successful"),
    "basicInfo": MessageLookupByLibrary.simpleMessage("Basic info"),
    "basicStrategy": MessageLookupByLibrary.simpleMessage("Basic strategies"),
    "batchAdd": MessageLookupByLibrary.simpleMessage("Batch add"),
    "batchListInputTip": MessageLookupByLibrary.simpleMessage(
      "One item per line, or separated by commas",
    ),
    "batchMapInputTip": MessageLookupByLibrary.simpleMessage(
      "One entry per line: key, a space, then value",
    ),
    "batchPreviewTip": m10,
    "batteryOptimizationDesc": MessageLookupByLibrary.simpleMessage(
      "To keep the app running in the background, disable battery optimization for it. Tap to open settings.",
    ),
    "batteryOptimizationStatusTip": MessageLookupByLibrary.simpleMessage(
      "Due to system limitations, the battery optimization status cannot be read correctly while running",
    ),
    "behavior": MessageLookupByLibrary.simpleMessage("Behavior"),
    "bind": MessageLookupByLibrary.simpleMessage("Bind"),
    "blacklistMode": MessageLookupByLibrary.simpleMessage("Blacklist mode"),
    "blockConnection": MessageLookupByLibrary.simpleMessage("Block connection"),
    "bootExitAnr": MessageLookupByLibrary.simpleMessage("App not responding"),
    "bootExitCrash": MessageLookupByLibrary.simpleMessage("App crash"),
    "bootExitInitialization": MessageLookupByLibrary.simpleMessage(
      "Process initialization failed",
    ),
    "bootExitNativeCrash": MessageLookupByLibrary.simpleMessage("Native crash"),
    "bootPhaseBootstrap": MessageLookupByLibrary.simpleMessage(
      "Preparing the app",
    ),
    "bootPhaseCore": MessageLookupByLibrary.simpleMessage("Connecting to Core"),
    "bootPhaseRecovery": MessageLookupByLibrary.simpleMessage(
      "Recovery prompt",
    ),
    "bootPhaseSetup": MessageLookupByLibrary.simpleMessage(
      "Initializing configuration",
    ),
    "bootRecordDamaged": MessageLookupByLibrary.simpleMessage(
      "The startup protection record is damaged. Automatic setup is skipped. Rebuild only this record, or keep it and continue? Profiles, settings and diagnostic files are preserved.",
    ),
    "bootRecordKeep": MessageLookupByLibrary.simpleMessage("Keep and continue"),
    "bootRecordNewer": MessageLookupByLibrary.simpleMessage(
      "The startup record uses a newer format and will be preserved. Automatic setup is skipped; you can use the app manually.",
    ),
    "bootRecordRebuild": MessageLookupByLibrary.simpleMessage(
      "Rebuild startup record",
    ),
    "bootRecordUnavailable": MessageLookupByLibrary.simpleMessage(
      "Startup protection could not save or read its record. Automatic setup is skipped this time. Existing service and files are preserved; manual controls remain available.",
    ),
    "bootRecoveryPhase": m11,
    "bootRecoveryReason": m12,
    "bootRecoveryRepeated": MessageLookupByLibrary.simpleMessage(
      "Startup has been interrupted repeatedly. Check or reselect a profile in the profile list before starting manually.",
    ),
    "bypassDomain": MessageLookupByLibrary.simpleMessage("Bypass domains"),
    "bypassDomainDesc": MessageLookupByLibrary.simpleMessage(
      "Only takes effect while the system proxy is enabled",
    ),
    "cache": MessageLookupByLibrary.simpleMessage("Cache"),
    "cacheAlgorithm": MessageLookupByLibrary.simpleMessage("Cache algorithm"),
    "cacheCorrupt": MessageLookupByLibrary.simpleMessage(
      "The cache is corrupted. Clear it?",
    ),
    "cacheMaxSize": MessageLookupByLibrary.simpleMessage("Cache size"),
    "cameraPermissionDesc": MessageLookupByLibrary.simpleMessage(
      "Allow camera access in system settings to scan QR codes, or choose a QR code image from the album.",
    ),
    "cameraPermissionRequired": MessageLookupByLibrary.simpleMessage(
      "Camera permission required",
    ),
    "cameraUnavailable": MessageLookupByLibrary.simpleMessage(
      "Camera unavailable",
    ),
    "cancel": MessageLookupByLibrary.simpleMessage("Cancel"),
    "cancelSelectAll": MessageLookupByLibrary.simpleMessage("Deselect all"),
    "changeProxyFailedTip": MessageLookupByLibrary.simpleMessage(
      "Failed to switch proxy; the previous selection has been restored",
    ),
    "changelogBreaking": MessageLookupByLibrary.simpleMessage(
      "Breaking changes",
    ),
    "changelogFeatures": MessageLookupByLibrary.simpleMessage("New features"),
    "changelogFixes": MessageLookupByLibrary.simpleMessage("Bug fixes"),
    "changelogPerformance": MessageLookupByLibrary.simpleMessage("Performance"),
    "changelogReverts": MessageLookupByLibrary.simpleMessage("Reverts"),
    "checkCertificate": MessageLookupByLibrary.simpleMessage(
      "Verify TLS certificates",
    ),
    "checkCertificateDesc": MessageLookupByLibrary.simpleMessage(
      "Reject untrusted certificates. Turning this off exposes subscriptions and backups to man-in-the-middle attacks",
    ),
    "checkUpdate": MessageLookupByLibrary.simpleMessage("Check for updates"),
    "checkUpdateError": MessageLookupByLibrary.simpleMessage(
      "The app is already up to date",
    ),
    "clearData": MessageLookupByLibrary.simpleMessage("Clear data"),
    "clearSearch": MessageLookupByLibrary.simpleMessage("Clear search"),
    "clipboardExport": MessageLookupByLibrary.simpleMessage(
      "Export to clipboard",
    ),
    "clipboardImport": MessageLookupByLibrary.simpleMessage(
      "Import from clipboard",
    ),
    "clipboardWriteFailed": MessageLookupByLibrary.simpleMessage(
      "Couldn\'t copy to the clipboard. The selection may be too large",
    ),
    "close": MessageLookupByLibrary.simpleMessage("Close"),
    "closeConnections": MessageLookupByLibrary.simpleMessage(
      "Close connections",
    ),
    "color": MessageLookupByLibrary.simpleMessage("Color"),
    "colorSchemes": MessageLookupByLibrary.simpleMessage("Color schemes"),
    "columns": MessageLookupByLibrary.simpleMessage("Columns"),
    "compatible": MessageLookupByLibrary.simpleMessage("Compatibility mode"),
    "configApplying": MessageLookupByLibrary.simpleMessage(
      "Applying configuration",
    ),
    "configDataDetected": MessageLookupByLibrary.simpleMessage(
      "Data detected in the configuration",
    ),
    "configInactive": MessageLookupByLibrary.simpleMessage(
      "No active configuration",
    ),
    "configLoaded": MessageLookupByLibrary.simpleMessage(
      "Loaded; traffic is not handled",
    ),
    "configRetained": MessageLookupByLibrary.simpleMessage(
      "New configuration not applied; using the previous configuration",
    ),
    "confirm": MessageLookupByLibrary.simpleMessage("Confirm"),
    "confirmClearAllData": MessageLookupByLibrary.simpleMessage(
      "Are you sure you want to clear all data?",
    ),
    "confirmDeleteProxyGroup": MessageLookupByLibrary.simpleMessage(
      "Are you sure you want to delete this proxy group?",
    ),
    "confirmExitWindow": MessageLookupByLibrary.simpleMessage(
      "Are you sure you want to exit the current window?",
    ),
    "confirmForceCrashCore": MessageLookupByLibrary.simpleMessage(
      "Are you sure you want to force crash the core?",
    ),
    "confirmOverwriteTip": MessageLookupByLibrary.simpleMessage(
      "Confirming will overwrite existing data",
    ),
    "connected": MessageLookupByLibrary.simpleMessage("Connected"),
    "connecting": MessageLookupByLibrary.simpleMessage("Connecting…"),
    "connection": MessageLookupByLibrary.simpleMessage("Connection"),
    "connections": MessageLookupByLibrary.simpleMessage("Connections"),
    "connectivity": MessageLookupByLibrary.simpleMessage("Connectivity: "),
    "content": MessageLookupByLibrary.simpleMessage("Content"),
    "contentNotEmpty": MessageLookupByLibrary.simpleMessage(
      "Content cannot be empty",
    ),
    "contentScheme": MessageLookupByLibrary.simpleMessage("Content"),
    "controlGlobalAddedRules": MessageLookupByLibrary.simpleMessage(
      "Control global added rules",
    ),
    "copy": MessageLookupByLibrary.simpleMessage("Copy"),
    "copyEnvVar": MessageLookupByLibrary.simpleMessage(
      "Copy environment variables",
    ),
    "copyLink": MessageLookupByLibrary.simpleMessage("Copy link"),
    "copySuccess": MessageLookupByLibrary.simpleMessage("Copied successfully"),
    "core": MessageLookupByLibrary.simpleMessage("Core"),
    "coreBlockedByPolicyTip": m13,
    "coreBlockedBySmartAppControlTip": MessageLookupByLibrary.simpleMessage(
      "Windows Smart App Control blocked FlClashCore.exe because it is not signed. Open Windows Security → App & browser control → Smart App Control settings, choose Off, then start FlClash again. Smart App Control cannot be turned back on without reinstalling Windows.",
    ),
    "coreStatus": MessageLookupByLibrary.simpleMessage("Core status"),
    "country": MessageLookupByLibrary.simpleMessage("Region"),
    "crashDetected": MessageLookupByLibrary.simpleMessage("Crash detected"),
    "crashDetectedTip": m14,
    "crashTest": MessageLookupByLibrary.simpleMessage("Crash test"),
    "create": MessageLookupByLibrary.simpleMessage("Create"),
    "createProfileFromUrlTip": m15,
    "creationTime": MessageLookupByLibrary.simpleMessage("Creation time"),
    "custom": MessageLookupByLibrary.simpleMessage("Custom"),
    "customProxiesEmpty": MessageLookupByLibrary.simpleMessage(
      "No custom proxies, so the profile\'s own proxies are used",
    ),
    "cut": MessageLookupByLibrary.simpleMessage("Cut"),
    "dark": MessageLookupByLibrary.simpleMessage("Dark"),
    "dashboard": MessageLookupByLibrary.simpleMessage("Dashboard"),
    "dataChangedSave": MessageLookupByLibrary.simpleMessage(
      "Data changes detected. Save them?",
    ),
    "databaseWriteFailedTip": MessageLookupByLibrary.simpleMessage(
      "Failed to save the change; it has been rolled back",
    ),
    "daysAgo": m16,
    "defaultText": MessageLookupByLibrary.simpleMessage("Default"),
    "delay": MessageLookupByLibrary.simpleMessage("Delay"),
    "delayTest": MessageLookupByLibrary.simpleMessage("Delay test"),
    "delayTestFailed": m17,
    "delayTestNoResult": MessageLookupByLibrary.simpleMessage(
      "The Core returned no test result. Check that the proxy is connected and retry.",
    ),
    "delayTestRequiresProxy": MessageLookupByLibrary.simpleMessage(
      "Start the proxy and wait for it to connect before testing node latency.",
    ),
    "delayTestUnavailable": MessageLookupByLibrary.simpleMessage("Unavailable"),
    "delayTestWaiting": MessageLookupByLibrary.simpleMessage("Waiting"),
    "delayTestWaitingResult": MessageLookupByLibrary.simpleMessage(
      "Waiting for result",
    ),
    "delete": MessageLookupByLibrary.simpleMessage("Delete"),
    "deleteMultipTip": m18,
    "deleteTip": m19,
    "desc": MessageLookupByLibrary.simpleMessage(
      "A multi-platform proxy client based on ClashMeta, simple and easy to use, open-source and ad-free.",
    ),
    "destination": MessageLookupByLibrary.simpleMessage("Destination"),
    "destinationGeoIP": MessageLookupByLibrary.simpleMessage(
      "Destination GeoIP",
    ),
    "destinationIPASN": MessageLookupByLibrary.simpleMessage(
      "Destination IP ASN",
    ),
    "details": m20,
    "detectionTip": MessageLookupByLibrary.simpleMessage(
      "Relies on a third-party API; for reference only",
    ),
    "developerMode": MessageLookupByLibrary.simpleMessage("Developer mode"),
    "developerModeEnableTip": MessageLookupByLibrary.simpleMessage(
      "Developer mode is enabled.",
    ),
    "dialerProxy": MessageLookupByLibrary.simpleMessage("Dialer proxy"),
    "dialerProxyDesc": MessageLookupByLibrary.simpleMessage(
      "The outbound used to reach the NTP server",
    ),
    "direct": MessageLookupByLibrary.simpleMessage("Direct"),
    "disableUDP": MessageLookupByLibrary.simpleMessage("Disable UDP"),
    "disabled": MessageLookupByLibrary.simpleMessage("Disabled"),
    "discardChanges": MessageLookupByLibrary.simpleMessage(
      "Discard the changes?",
    ),
    "disconnected": MessageLookupByLibrary.simpleMessage("Disconnected"),
    "discoverNewVersion": MessageLookupByLibrary.simpleMessage(
      "New version found",
    ),
    "dnsHijacking": MessageLookupByLibrary.simpleMessage("DNS hijacking"),
    "dnsMode": MessageLookupByLibrary.simpleMessage("DNS mode"),
    "dnsQueries": MessageLookupByLibrary.simpleMessage("DNS queries"),
    "docked": MessageLookupByLibrary.simpleMessage("Docked"),
    "domain": MessageLookupByLibrary.simpleMessage("Domain"),
    "download": MessageLookupByLibrary.simpleMessage("Download"),
    "edit": MessageLookupByLibrary.simpleMessage("Edit"),
    "editGlobalRules": MessageLookupByLibrary.simpleMessage(
      "Edit global rules",
    ),
    "editProxy": MessageLookupByLibrary.simpleMessage("Edit proxy"),
    "editProxyGroup": MessageLookupByLibrary.simpleMessage("Edit proxy group"),
    "editRule": MessageLookupByLibrary.simpleMessage("Edit rule"),
    "editSsid": MessageLookupByLibrary.simpleMessage("Edit SSID"),
    "editorUnavailable": MessageLookupByLibrary.simpleMessage(
      "Editor unavailable",
    ),
    "emptyTip": m21,
    "en": MessageLookupByLibrary.simpleMessage("English"),
    "enabled": MessageLookupByLibrary.simpleMessage("Enabled"),
    "entries": MessageLookupByLibrary.simpleMessage(" entries"),
    "error": MessageLookupByLibrary.simpleMessage("Error"),
    "exclude": MessageLookupByLibrary.simpleMessage("Hide from recent tasks"),
    "excludeDesc": MessageLookupByLibrary.simpleMessage(
      "Hide the app from recent tasks while it is in the background",
    ),
    "excludeProxyFilter": MessageLookupByLibrary.simpleMessage(
      "Exclude proxy filter",
    ),
    "excludeSsids": MessageLookupByLibrary.simpleMessage("Exclude SSIDs"),
    "excludeSsidsDesc": MessageLookupByLibrary.simpleMessage(
      "When connected to Wi-Fi with an excluded SSID, the app\'s running state switches automatically",
    ),
    "excludeType": MessageLookupByLibrary.simpleMessage("Exclude type"),
    "existsTip": m22,
    "exit": MessageLookupByLibrary.simpleMessage("Exit"),
    "exitFullScreen": MessageLookupByLibrary.simpleMessage("Exit full screen"),
    "expand": MessageLookupByLibrary.simpleMessage("Standard"),
    "expectedStatus": MessageLookupByLibrary.simpleMessage("Expected status"),
    "expireTime": MessageLookupByLibrary.simpleMessage("Expiration time"),
    "exportFile": MessageLookupByLibrary.simpleMessage("Export file"),
    "exportLogs": MessageLookupByLibrary.simpleMessage("Export logs"),
    "exportSuccess": MessageLookupByLibrary.simpleMessage("Export successful"),
    "expressiveScheme": MessageLookupByLibrary.simpleMessage("Expressive"),
    "externalController": MessageLookupByLibrary.simpleMessage(
      "External controller",
    ),
    "externalControllerDesc": MessageLookupByLibrary.simpleMessage(
      "When enabled, the Clash core can be controlled on port 9090",
    ),
    "externalLink": MessageLookupByLibrary.simpleMessage("External link"),
    "extraLarge": MessageLookupByLibrary.simpleMessage("Extra large"),
    "fade": MessageLookupByLibrary.simpleMessage("Fade"),
    "fakeipFilter": MessageLookupByLibrary.simpleMessage("Fake-IP filter"),
    "fakeipFilterMode": MessageLookupByLibrary.simpleMessage(
      "Fake-IP filter mode",
    ),
    "fakeipFilterModeDesc": MessageLookupByLibrary.simpleMessage(
      "blacklist excludes matches, whitelist fakes only matches, rule matches as rules",
    ),
    "fakeipRange": MessageLookupByLibrary.simpleMessage("Fake-IP range"),
    "fakeipRange6": MessageLookupByLibrary.simpleMessage(
      "Fake-IP range (IPv6)",
    ),
    "fakeipTtl": MessageLookupByLibrary.simpleMessage("Fake-IP TTL"),
    "fallbackFilter": MessageLookupByLibrary.simpleMessage("Fallback filter"),
    "fidelityScheme": MessageLookupByLibrary.simpleMessage("Fidelity"),
    "file": MessageLookupByLibrary.simpleMessage("File"),
    "fileDesc": MessageLookupByLibrary.simpleMessage(
      "Upload a profile file directly",
    ),
    "fileIsUpdate": MessageLookupByLibrary.simpleMessage(
      "The file has been modified. Save the changes?",
    ),
    "filter": MessageLookupByLibrary.simpleMessage("Filter"),
    "findProcessMode": MessageLookupByLibrary.simpleMessage("Find process"),
    "floating": MessageLookupByLibrary.simpleMessage("Floating"),
    "followProfile": MessageLookupByLibrary.simpleMessage("Follow profile"),
    "followSystem": MessageLookupByLibrary.simpleMessage("Follow system"),
    "fontFamily": MessageLookupByLibrary.simpleMessage("Font family"),
    "fontSize": MessageLookupByLibrary.simpleMessage("Size"),
    "forceRestartCoreTip": MessageLookupByLibrary.simpleMessage(
      "Are you sure you want to force restart the core?",
    ),
    "format": MessageLookupByLibrary.simpleMessage("Format"),
    "fruitSaladScheme": MessageLookupByLibrary.simpleMessage("Fruit salad"),
    "general": MessageLookupByLibrary.simpleMessage("General"),
    "geoAutoUpdate": MessageLookupByLibrary.simpleMessage("Auto update"),
    "geoAutoUpdateInterval": MessageLookupByLibrary.simpleMessage(
      "Auto-update interval",
    ),
    "geoAutoUpdateIntervalTip": MessageLookupByLibrary.simpleMessage(
      "The auto-update interval must be greater than 0",
    ),
    "geoOptions": MessageLookupByLibrary.simpleMessage("Geo options"),
    "geoResourceAsnAbout": MessageLookupByLibrary.simpleMessage(
      "Maps IP addresses to autonomous system numbers (ASNs) and network organizations, such as internet service providers or cloud networks. Used by IP-ASN and SRC-IP-ASN rules.",
    ),
    "geoResourceGeoipAbout": MessageLookupByLibrary.simpleMessage(
      "Groups IP ranges by country or region in a .dat database. Used by GEOIP rules when Geo data mode is enabled; MMDB is the alternative for the other mode.",
    ),
    "geoResourceGeositeAbout": MessageLookupByLibrary.simpleMessage(
      "Groups domain names into categories such as services or regions. Used by GEOSITE rules and supported DNS settings to match domains.",
    ),
    "geoResourceMmdbAbout": MessageLookupByLibrary.simpleMessage(
      "Maps IP addresses to country or region codes for GEOIP rules and some DNS decisions. Used when Geo data mode is disabled; in FlClash this is the country database in MaxMind DB format.",
    ),
    "geoResources": MessageLookupByLibrary.simpleMessage("Geo resources"),
    "geoSkipped": m23,
    "geoUpdated": m24,
    "geodataLoader": MessageLookupByLibrary.simpleMessage(
      "Geo low-memory mode",
    ),
    "global": MessageLookupByLibrary.simpleMessage("Global"),
    "go": MessageLookupByLibrary.simpleMessage("Go"),
    "goDownload": MessageLookupByLibrary.simpleMessage("Download"),
    "goToConfigureScript": MessageLookupByLibrary.simpleMessage(
      "Go to script configuration",
    ),
    "hasCacheChange": MessageLookupByLibrary.simpleMessage(
      "Cache the changes?",
    ),
    "helperCorruptTip": MessageLookupByLibrary.simpleMessage(
      "Helper service unavailable; TUN mode cannot be enabled. Reinstall FlClash to restore it.",
    ),
    "hideFromList": MessageLookupByLibrary.simpleMessage("Hide from list"),
    "hideIp": MessageLookupByLibrary.simpleMessage("Hide IP"),
    "hidePassword": MessageLookupByLibrary.simpleMessage("Hide password"),
    "hideTimeoutProxies": MessageLookupByLibrary.simpleMessage(
      "Hide timed-out nodes",
    ),
    "hideTimeoutProxiesDesc": MessageLookupByLibrary.simpleMessage(
      "Leave out nodes whose last delay test timed out",
    ),
    "host": MessageLookupByLibrary.simpleMessage("Host"),
    "hotkeyConflictWith": m25,
    "hotkeyDesc": MessageLookupByLibrary.simpleMessage(
      "Global hotkeys work even while the window is hidden. Tap an action to record its key combination.",
    ),
    "hotkeyManagement": MessageLookupByLibrary.simpleMessage(
      "Hotkey management",
    ),
    "hotkeyNeedsModifier": m26,
    "hotkeyNotSet": MessageLookupByLibrary.simpleMessage("Not set"),
    "hotkeyUnavailable": MessageLookupByLibrary.simpleMessage(
      "Not registered, it may be taken by another app",
    ),
    "hours": MessageLookupByLibrary.simpleMessage("hours"),
    "hoursAgo": m27,
    "hoursCount": m28,
    "icon": MessageLookupByLibrary.simpleMessage("Icon"),
    "iconRecords": MessageLookupByLibrary.simpleMessage("Icon records"),
    "iconStyle": MessageLookupByLibrary.simpleMessage("Icon style"),
    "iconStyleFilled": MessageLookupByLibrary.simpleMessage("Filled"),
    "iconStyleHidden": MessageLookupByLibrary.simpleMessage("Hidden"),
    "iconStylePlain": MessageLookupByLibrary.simpleMessage("Plain"),
    "iconUrl": MessageLookupByLibrary.simpleMessage("Icon URL"),
    "ignoreBatteryOptimization": MessageLookupByLibrary.simpleMessage(
      "Ignore battery optimization",
    ),
    "import": MessageLookupByLibrary.simpleMessage("Import"),
    "importFile": MessageLookupByLibrary.simpleMessage("Import from file"),
    "importFromURL": MessageLookupByLibrary.simpleMessage("Import from URL"),
    "importUrl": MessageLookupByLibrary.simpleMessage("Import from URL"),
    "inbound": MessageLookupByLibrary.simpleMessage("Inbound"),
    "includeAllProxies": MessageLookupByLibrary.simpleMessage(
      "Include all proxies",
    ),
    "includeAllProxiesTip": MessageLookupByLibrary.simpleMessage(
      "Imports all proxies outside proxy groups; extra proxy groups can be added below",
    ),
    "includeAllProxyProviders": MessageLookupByLibrary.simpleMessage(
      "Include all proxy providers",
    ),
    "includeAllProxyProvidersTip": MessageLookupByLibrary.simpleMessage(
      "When enabled, the group takes every proxy provider of this profile: the subscription\'s own, plus the profiles and app proxy providers any proxy group uses",
    ),
    "infiniteTime": MessageLookupByLibrary.simpleMessage("Never expires"),
    "init": MessageLookupByLibrary.simpleMessage("Init"),
    "initiator": MessageLookupByLibrary.simpleMessage("Initiator"),
    "inputProxyGroupName": MessageLookupByLibrary.simpleMessage(
      "Enter the proxy group name",
    ),
    "inputRuleContent": MessageLookupByLibrary.simpleMessage(
      "Enter the rule content",
    ),
    "installedAppsPermissionDeniedMessage": MessageLookupByLibrary.simpleMessage(
      "The app list permission was denied, so installed apps cannot be listed. Please grant it manually in system settings.",
    ),
    "installedAppsPermissionDesc": MessageLookupByLibrary.simpleMessage(
      "This system hides the installed app list until the permission is granted. Authorize it to configure the per-app proxy.",
    ),
    "installedAppsPermissionRequired": MessageLookupByLibrary.simpleMessage(
      "App list permission required",
    ),
    "intelligentSelected": MessageLookupByLibrary.simpleMessage(
      "Smart selection",
    ),
    "interfaceName": MessageLookupByLibrary.simpleMessage("Interface name"),
    "interfaceNameDesc": MessageLookupByLibrary.simpleMessage(
      "Network interface used for outbound connections",
    ),
    "interfaceNameMode": MessageLookupByLibrary.simpleMessage(
      "Outbound interface",
    ),
    "interfaceNameModeClear": MessageLookupByLibrary.simpleMessage("Clear"),
    "interfaceNameModeCustom": MessageLookupByLibrary.simpleMessage("Custom"),
    "interfaceNameModeFollow": MessageLookupByLibrary.simpleMessage(
      "Follow config",
    ),
    "internet": MessageLookupByLibrary.simpleMessage("Internet"),
    "interval": MessageLookupByLibrary.simpleMessage("Interval"),
    "intranetIP": MessageLookupByLibrary.simpleMessage("Intranet IP"),
    "invalidBackupFile": MessageLookupByLibrary.simpleMessage(
      "Invalid backup file",
    ),
    "invalidDscpContent": MessageLookupByLibrary.simpleMessage(
      "A DSCP mark cannot exceed 63",
    ),
    "invalidNetworkContent": MessageLookupByLibrary.simpleMessage(
      "Only tcp or udp is supported",
    ),
    "invalidPolicy": m29,
    "invalidProfileQrcode": MessageLookupByLibrary.simpleMessage(
      "This QR code doesn\'t contain a profile link",
    ),
    "invalidProxy": m30,
    "invalidProxyProvider": m31,
    "invalidRangeContent": MessageLookupByLibrary.simpleMessage(
      "Enter numbers or ranges such as 80 or 8000-9000, separated by /",
    ),
    "invalidRuleSet": m32,
    "invalidSubRule": m33,
    "ipAddress": MessageLookupByLibrary.simpleMessage("IP address"),
    "ipAsn": MessageLookupByLibrary.simpleMessage("ASN"),
    "ipClassificationDisclosure": MessageLookupByLibrary.simpleMessage(
      "This button sends this IP to proxycheck.io over HTTPS for classification. The service also sees the request exit IP, which may differ. Anonymous use is limited to 100 queries a day and may be refused from proxy exits. Refusal never changes the route or source. Missing fields mean unknown; no safety guarantee. The request disables optional positive-detection dashboard saving, not all server logging.",
    ),
    "ipClassificationStart": MessageLookupByLibrary.simpleMessage(
      "Classify this IP",
    ),
    "ipFlagAnonymous": MessageLookupByLibrary.simpleMessage(
      "Anonymous detection",
    ),
    "ipFlagCompromised": MessageLookupByLibrary.simpleMessage("Compromised"),
    "ipFlagHosting": MessageLookupByLibrary.simpleMessage("Hosting detection"),
    "ipFlagProxy": MessageLookupByLibrary.simpleMessage("Proxy"),
    "ipFlagScraper": MessageLookupByLibrary.simpleMessage("Scraper detection"),
    "ipFlagTor": MessageLookupByLibrary.simpleMessage("Tor"),
    "ipFlagVpn": MessageLookupByLibrary.simpleMessage("VPN"),
    "ipFlags": MessageLookupByLibrary.simpleMessage("Flags"),
    "ipLookupAutomatic": MessageLookupByLibrary.simpleMessage(
      "Automatic on dashboard",
    ),
    "ipLookupBodyLimit": MessageLookupByLibrary.simpleMessage(
      "Response too large",
    ),
    "ipLookupCancelled": MessageLookupByLibrary.simpleMessage(
      "Query cancelled",
    ),
    "ipLookupCheckedAt": MessageLookupByLibrary.simpleMessage("Observed at"),
    "ipLookupDisclosure": MessageLookupByLibrary.simpleMessage(
      "Checks your request exit and country with Cloudflare over HTTPS. Automatic checks run only while the app is in front, the dashboard is shown and the service is running. One observation does not describe every website.",
    ),
    "ipLookupDisplayOnly": MessageLookupByLibrary.simpleMessage(
      "Display only; copying uses the original IP. This setting does not stop network queries.",
    ),
    "ipLookupHttpFailed": MessageLookupByLibrary.simpleMessage(
      "Source rejected the request",
    ),
    "ipLookupInvalid": MessageLookupByLibrary.simpleMessage(
      "Invalid or incomplete response",
    ),
    "ipLookupIpMismatch": MessageLookupByLibrary.simpleMessage(
      "Response IP does not match",
    ),
    "ipLookupManual": MessageLookupByLibrary.simpleMessage("Check exit IP"),
    "ipLookupNotChecked": MessageLookupByLibrary.simpleMessage("Not checked"),
    "ipLookupRoutes": MessageLookupByLibrary.simpleMessage("Current rules"),
    "ipLookupSourceWarning": MessageLookupByLibrary.simpleMessage(
      "Source warning: the result was returned, but quota or access restrictions may apply.",
    ),
    "ipLookupStale": MessageLookupByLibrary.simpleMessage(
      "Previous observation",
    ),
    "ipLookupTlsFailed": MessageLookupByLibrary.simpleMessage(
      "Certificate verification failed",
    ),
    "ipLookupWaiting": MessageLookupByLibrary.simpleMessage(
      "Waiting for the 30-second interval",
    ),
    "ipOrganization": MessageLookupByLibrary.simpleMessage("Organization"),
    "ipQualityFailed": MessageLookupByLibrary.simpleMessage(
      "Couldn\'t determine the IP type",
    ),
    "ipQualityRetry": MessageLookupByLibrary.simpleMessage("Check again"),
    "ipQualitySource": MessageLookupByLibrary.simpleMessage("Answered by"),
    "ipQualitySources": MessageLookupByLibrary.simpleMessage("Sources"),
    "ipSourceIpMismatch": MessageLookupByLibrary.simpleMessage(
      "Different outbound IP",
    ),
    "ipSourceNoType": MessageLookupByLibrary.simpleMessage("No type"),
    "ipSourceRateLimited": MessageLookupByLibrary.simpleMessage("Rate limited"),
    "ipType": MessageLookupByLibrary.simpleMessage("Type"),
    "ipTypeBusiness": MessageLookupByLibrary.simpleMessage("Business"),
    "ipTypeHosting": MessageLookupByLibrary.simpleMessage("Data center"),
    "ipTypeResidential": MessageLookupByLibrary.simpleMessage("Residential"),
    "ipTypeWireless": MessageLookupByLibrary.simpleMessage(
      "Wireless (cellular or satellite)",
    ),
    "ipv6Desc": MessageLookupByLibrary.simpleMessage(
      "When enabled, IPv6 traffic can be received",
    ),
    "ipv6InboundDesc": MessageLookupByLibrary.simpleMessage(
      "Allow IPv6 inbound",
    ),
    "ipv6Timeout": MessageLookupByLibrary.simpleMessage("IPv6 timeout (ms)"),
    "ja": MessageLookupByLibrary.simpleMessage("Japanese"),
    "justNow": MessageLookupByLibrary.simpleMessage("Just now"),
    "keepAliveIntervalDesc": MessageLookupByLibrary.simpleMessage(
      "TCP keep-alive interval",
    ),
    "key": MessageLookupByLibrary.simpleMessage("Key"),
    "language": MessageLookupByLibrary.simpleMessage("Language"),
    "large": MessageLookupByLibrary.simpleMessage("Large"),
    "lastUpdated": MessageLookupByLibrary.simpleMessage("Last updated"),
    "launchInterrupted": MessageLookupByLibrary.simpleMessage(
      "Launch did not finish",
    ),
    "launchInterruptedTip": MessageLookupByLibrary.simpleMessage(
      "The previous launch did not finish. The cause is unknown. Automatic setup is skipped this time. Your selection and files are preserved; you can start manually.",
    ),
    "layout": MessageLookupByLibrary.simpleMessage("Layout"),
    "light": MessageLookupByLibrary.simpleMessage("Light"),
    "lineIssueTip": m34,
    "lineWrap": MessageLookupByLibrary.simpleMessage("Word wrap"),
    "list": MessageLookupByLibrary.simpleMessage("List"),
    "listen": MessageLookupByLibrary.simpleMessage("Listen"),
    "listenRoutingMark": MessageLookupByLibrary.simpleMessage(
      "Listen routing mark",
    ),
    "listenRoutingMarkDesc": MessageLookupByLibrary.simpleMessage("Linux only"),
    "liveConnections": MessageLookupByLibrary.simpleMessage("Live connections"),
    "loading": MessageLookupByLibrary.simpleMessage("Loading…"),
    "local": MessageLookupByLibrary.simpleMessage("Local"),
    "localCrashReports": MessageLookupByLibrary.simpleMessage(
      "Local crash reports",
    ),
    "localGroupsActions": m35,
    "localGroupsActualExit": m36,
    "localGroupsAmbiguous": MessageLookupByLibrary.simpleMessage(
      "Some selected node names occur in multiple sources. Use uniquely named nodes to avoid choosing the wrong endpoint.",
    ),
    "localGroupsApplyFailed": MessageLookupByLibrary.simpleMessage(
      "The changes could not be applied. Check the configuration and retry.",
    ),
    "localGroupsApplying": MessageLookupByLibrary.simpleMessage(
      "Applying configuration…",
    ),
    "localGroupsAutomatic": MessageLookupByLibrary.simpleMessage(
      "Latency-based",
    ),
    "localGroupsChanged": MessageLookupByLibrary.simpleMessage(
      "The configuration changed. Refresh group management and retry.",
    ),
    "localGroupsCreate": MessageLookupByLibrary.simpleMessage("New group"),
    "localGroupsDelete": m37,
    "localGroupsDisable": MessageLookupByLibrary.simpleMessage("Disable"),
    "localGroupsDownloading": MessageLookupByLibrary.simpleMessage(
      "Downloading source updates…",
    ),
    "localGroupsEmpty": MessageLookupByLibrary.simpleMessage(
      "Create a group by choosing nodes from this subscription.",
    ),
    "localGroupsEnable": MessageLookupByLibrary.simpleMessage("Enable"),
    "localGroupsEnableSpeedTest": MessageLookupByLibrary.simpleMessage(
      "Enable speed test",
    ),
    "localGroupsFallback": MessageLookupByLibrary.simpleMessage("Failover"),
    "localGroupsForegroundRequired": MessageLookupByLibrary.simpleMessage(
      "Open the app to apply this change. A full configuration reload is required.",
    ),
    "localGroupsIdentitySection": MessageLookupByLibrary.simpleMessage(
      "Group details",
    ),
    "localGroupsInUse": MessageLookupByLibrary.simpleMessage(
      "Choose another node or group before removing this reference, disabling or deleting this group.",
    ),
    "localGroupsIndependent": MessageLookupByLibrary.simpleMessage(
      "Standalone group",
    ),
    "localGroupsInvalidParent": MessageLookupByLibrary.simpleMessage(
      "Select an available manual group or Standalone group.",
    ),
    "localGroupsInvalidTestUrl": MessageLookupByLibrary.simpleMessage(
      "Enter a valid HTTP(S) test URL.",
    ),
    "localGroupsLimit": MessageLookupByLibrary.simpleMessage(
      "The group or member limit was exceeded.",
    ),
    "localGroupsLoadFirst": MessageLookupByLibrary.simpleMessage(
      "Use this subscription and complete source review to load its nodes.",
    ),
    "localGroupsManaged": MessageLookupByLibrary.simpleMessage(
      "Manage groups in Policy draft for this configuration.",
    ),
    "localGroupsManual": MessageLookupByLibrary.simpleMessage("Manual"),
    "localGroupsMembersRequired": MessageLookupByLibrary.simpleMessage(
      "Select at least one available node.",
    ),
    "localGroupsMissing": m38,
    "localGroupsNameConflict": MessageLookupByLibrary.simpleMessage(
      "Choose a unique group name.",
    ),
    "localGroupsNoEntrance": MessageLookupByLibrary.simpleMessage(
      "There is no selectable routing entry in this configuration.",
    ),
    "localGroupsNoSaved": MessageLookupByLibrary.simpleMessage(
      "No custom groups yet. Create one in Group management.",
    ),
    "localGroupsNodeCount": m39,
    "localGroupsNodesSection": MessageLookupByLibrary.simpleMessage("Nodes"),
    "localGroupsOwn": MessageLookupByLibrary.simpleMessage("Custom"),
    "localGroupsParent": MessageLookupByLibrary.simpleMessage(
      "Add as an option in",
    ),
    "localGroupsPending": MessageLookupByLibrary.simpleMessage(
      "Saved changes are waiting to be applied.",
    ),
    "localGroupsPreferred": m40,
    "localGroupsPreparing": MessageLookupByLibrary.simpleMessage(
      "Checking saved configuration…",
    ),
    "localGroupsPreparingSources": MessageLookupByLibrary.simpleMessage(
      "Checking saved source files…",
    ),
    "localGroupsReferenceAdded": MessageLookupByLibrary.simpleMessage(
      "Added to choices",
    ),
    "localGroupsReferenceNotAdded": MessageLookupByLibrary.simpleMessage(
      "Not added",
    ),
    "localGroupsReferenceUsing": MessageLookupByLibrary.simpleMessage(
      "Currently selected",
    ),
    "localGroupsReferences": m41,
    "localGroupsReferencesSaved": MessageLookupByLibrary.simpleMessage(
      "References applied. Current selections were kept.",
    ),
    "localGroupsRegex": MessageLookupByLibrary.simpleMessage(
      "Node regular expression (optional)",
    ),
    "localGroupsRegexDocs": MessageLookupByLibrary.simpleMessage(
      "Regular expression help",
    ),
    "localGroupsRegexHelp": MessageLookupByLibrary.simpleMessage(
      "Matches start selected. Tap a node to change its selection.",
    ),
    "localGroupsRouteThis": MessageLookupByLibrary.simpleMessage(
      "Manage group references",
    ),
    "localGroupsSaving": MessageLookupByLibrary.simpleMessage(
      "Checking and saving group…",
    ),
    "localGroupsScope": m42,
    "localGroupsSearch": MessageLookupByLibrary.simpleMessage("Search nodes"),
    "localGroupsSelectNodeHelp": MessageLookupByLibrary.simpleMessage(
      "Tap a node to switch immediately. No save is needed.",
    ),
    "localGroupsSource": MessageLookupByLibrary.simpleMessage(
      "Subscription groups (read-only)",
    ),
    "localGroupsSourceUnavailable": MessageLookupByLibrary.simpleMessage(
      "The accepted configuration or its permissions are unavailable. Check source permissions in Profiles.",
    ),
    "localGroupsStrategyHelp": MessageLookupByLibrary.simpleMessage(
      "On: choose by latency. Off: fail over in Core order. Both check availability automatically.",
    ),
    "localGroupsStrategySection": MessageLookupByLibrary.simpleMessage(
      "Switching strategy",
    ),
    "localGroupsSubscription": MessageLookupByLibrary.simpleMessage(
      "Subscription",
    ),
    "localGroupsTitle": MessageLookupByLibrary.simpleMessage(
      "Group management",
    ),
    "localGroupsTransientHelp": MessageLookupByLibrary.simpleMessage(
      "Tap a node to use it for this run. If it fails, the group switches automatically. This choice is not saved.",
    ),
    "localGroupsUnavailable": MessageLookupByLibrary.simpleMessage(
      "This group is not active. Enable it or wait for the configuration to be ready.",
    ),
    "localGroupsUse": MessageLookupByLibrary.simpleMessage(
      "Manage group references",
    ),
    "localGroupsUseHelp": MessageLookupByLibrary.simpleMessage(
      "Choose where this custom group is available. Save applies the references and keeps each group’s current selection.",
    ),
    "localNetworkDeniedTip": MessageLookupByLibrary.simpleMessage(
      "Local network permission denied: using the gvisor stack, LAN is unreachable.",
    ),
    "locationPermission": MessageLookupByLibrary.simpleMessage(
      "Location permission",
    ),
    "locationPermissionDeniedMessage": MessageLookupByLibrary.simpleMessage(
      "Location permission was denied, so the current Wi-Fi name cannot be read. Please enable location permission manually in system settings.",
    ),
    "locationPermissionDesc": MessageLookupByLibrary.simpleMessage(
      "The system requires location permission to read the Wi-Fi name. On Android choose \"Allow all the time\", otherwise the Wi-Fi name cannot be read while the app is in the background.",
    ),
    "locationPermissionGuide": m43,
    "locationPermissionRequired": MessageLookupByLibrary.simpleMessage(
      "Location permission required",
    ),
    "log": MessageLookupByLibrary.simpleMessage("Log"),
    "logLevel": MessageLookupByLibrary.simpleMessage("Log level"),
    "logcat": MessageLookupByLibrary.simpleMessage("Logcat"),
    "logcatDesc": MessageLookupByLibrary.simpleMessage(
      "Disabling hides the log entry point",
    ),
    "logs": MessageLookupByLibrary.simpleMessage("Logs"),
    "logsAndDiagnostics": MessageLookupByLibrary.simpleMessage(
      "Logs and diagnostics",
    ),
    "logsTest": MessageLookupByLibrary.simpleMessage("Logs test"),
    "loopback": MessageLookupByLibrary.simpleMessage("UWP loopback exemption"),
    "loose": MessageLookupByLibrary.simpleMessage("Loose"),
    "matchSourceIp": MessageLookupByLibrary.simpleMessage("Match source IP"),
    "matchTarget": MessageLookupByLibrary.simpleMessage("MATCH-TARGET"),
    "maxFailedTimes": MessageLookupByLibrary.simpleMessage("Max failures"),
    "maxLengthTip": m44,
    "maximize": MessageLookupByLibrary.simpleMessage("Maximize"),
    "memoryAppResident": MessageLookupByLibrary.simpleMessage(
      "Resident memory",
    ),
    "memoryAppShared": MessageLookupByLibrary.simpleMessage("App & shared"),
    "memoryCoreHeapIdle": MessageLookupByLibrary.simpleMessage("Heap idle"),
    "memoryCoreHeapInuse": MessageLookupByLibrary.simpleMessage("Heap in use"),
    "memoryCoreNotRunning": MessageLookupByLibrary.simpleMessage(
      "Core is not running",
    ),
    "memoryCoreRuntime": MessageLookupByLibrary.simpleMessage(
      "Runtime overhead",
    ),
    "memoryCoreStack": MessageLookupByLibrary.simpleMessage("Goroutine stacks"),
    "memoryEstimateDesc": MessageLookupByLibrary.simpleMessage(
      "Estimated from process resident memory; it may differ from what the system reports.",
    ),
    "memoryEstimateSharedDesc": MessageLookupByLibrary.simpleMessage(
      "The Core runs inside the app process. Its share is estimated from runtime stats, and the rest counts as app and shared memory.",
    ),
    "memoryInfo": MessageLookupByLibrary.simpleMessage("Memory info"),
    "memoryReleased": MessageLookupByLibrary.simpleMessage("Memory released"),
    "memoryReleasedSize": m45,
    "messageTest": MessageLookupByLibrary.simpleMessage("Message test"),
    "messageTestTip": MessageLookupByLibrary.simpleMessage(
      "This is a message.",
    ),
    "min": MessageLookupByLibrary.simpleMessage("Minimal"),
    "minimize": MessageLookupByLibrary.simpleMessage("Minimize"),
    "minimizeOnExit": MessageLookupByLibrary.simpleMessage("Minimize on exit"),
    "minutesAgo": m46,
    "mixedPort": MessageLookupByLibrary.simpleMessage("Mixed port"),
    "mode": MessageLookupByLibrary.simpleMessage("Mode"),
    "monochromeScheme": MessageLookupByLibrary.simpleMessage("Monochrome"),
    "monthsAgo": m47,
    "more": MessageLookupByLibrary.simpleMessage("More"),
    "name": MessageLookupByLibrary.simpleMessage("Name"),
    "navigationBarStyle": MessageLookupByLibrary.simpleMessage("Bottom bar"),
    "network": MessageLookupByLibrary.simpleMessage("Network"),
    "networkAccessDeniedError": m48,
    "networkBadResponseError": m49,
    "networkCancelledError": MessageLookupByLibrary.simpleMessage(
      "The request was cancelled",
    ),
    "networkConnectionError": MessageLookupByLibrary.simpleMessage(
      "Couldn\'t connect to the server. Check your network connection or proxy settings",
    ),
    "networkDetection": MessageLookupByLibrary.simpleMessage(
      "Network detection",
    ),
    "networkHostLookupError": MessageLookupByLibrary.simpleMessage(
      "Couldn\'t resolve the server address. Check that the URL is correct and DNS is working",
    ),
    "networkNotFoundError": m50,
    "networkRateLimitedError": MessageLookupByLibrary.simpleMessage(
      "Too many requests (HTTP 429). Wait a moment and try again",
    ),
    "networkRequestFailed": m51,
    "networkServerError": m52,
    "networkSpeed": MessageLookupByLibrary.simpleMessage("Network speed"),
    "networkTimeoutError": MessageLookupByLibrary.simpleMessage(
      "The request timed out. Check your network or proxy, then try again",
    ),
    "networkTlsError": MessageLookupByLibrary.simpleMessage(
      "Secure connection failed. The server\'s certificate may be invalid, or the connection is being intercepted",
    ),
    "networkType": MessageLookupByLibrary.simpleMessage("Network type"),
    "neutralScheme": MessageLookupByLibrary.simpleMessage("Neutral"),
    "nextMatch": MessageLookupByLibrary.simpleMessage("Next match"),
    "no": MessageLookupByLibrary.simpleMessage("No"),
    "noData": MessageLookupByLibrary.simpleMessage("No data"),
    "noInfo": MessageLookupByLibrary.simpleMessage("No info"),
    "noNetwork": MessageLookupByLibrary.simpleMessage("No network"),
    "noNetworkApp": MessageLookupByLibrary.simpleMessage("No-network apps"),
    "noRecords": MessageLookupByLibrary.simpleMessage("No records"),
    "noResolve": MessageLookupByLibrary.simpleMessage("Don\'t resolve IP"),
    "noResolveHostname": MessageLookupByLibrary.simpleMessage(
      "Don\'t resolve hostname",
    ),
    "noSearchResults": MessageLookupByLibrary.simpleMessage(
      "No matching results",
    ),
    "nonTextProviderFile": MessageLookupByLibrary.simpleMessage(
      "This external resource is not a text file",
    ),
    "none": MessageLookupByLibrary.simpleMessage("None"),
    "notSelectedTip": MessageLookupByLibrary.simpleMessage(
      "The current proxy group cannot be selected",
    ),
    "ntpInterval": MessageLookupByLibrary.simpleMessage(
      "Sync interval (minutes)",
    ),
    "ntpStatusDesc": MessageLookupByLibrary.simpleMessage(
      "Take the time from an NTP server instead of the system clock",
    ),
    "nullProfileDesc": MessageLookupByLibrary.simpleMessage(
      "Add a profile to get started",
    ),
    "nullTip": m53,
    "numberTip": m54,
    "officialDocumentation": MessageLookupByLibrary.simpleMessage(
      "Official documentation",
    ),
    "onDemand": MessageLookupByLibrary.simpleMessage("On demand"),
    "onDemandDesc": MessageLookupByLibrary.simpleMessage(
      "Configure the app\'s running state for specific scenarios",
    ),
    "onlyStatisticsProxy": MessageLookupByLibrary.simpleMessage(
      "Only count proxy traffic",
    ),
    "optional": MessageLookupByLibrary.simpleMessage("Optional"),
    "options": MessageLookupByLibrary.simpleMessage("Options"),
    "other": MessageLookupByLibrary.simpleMessage("Other"),
    "otherContributors": MessageLookupByLibrary.simpleMessage(
      "Other contributors",
    ),
    "outboundIp": MessageLookupByLibrary.simpleMessage("Outbound IP"),
    "outboundMode": MessageLookupByLibrary.simpleMessage("Outbound mode"),
    "override": MessageLookupByLibrary.simpleMessage("Override"),
    "overrideDns": MessageLookupByLibrary.simpleMessage("Override DNS"),
    "overrideEntries": MessageLookupByLibrary.simpleMessage("Override entries"),
    "overrideMode": MessageLookupByLibrary.simpleMessage("Override mode"),
    "overrideNtp": MessageLookupByLibrary.simpleMessage("Override NTP"),
    "overrideScript": MessageLookupByLibrary.simpleMessage("Override script"),
    "overwriteIssueCoreRejected": m55,
    "overwriteIssueDuplicateName": m56,
    "overwriteIssueEmptyName": MessageLookupByLibrary.simpleMessage(
      "The name is empty",
    ),
    "overwriteIssueGroupLoop": m57,
    "overwriteIssueMissingProviders": m58,
    "overwriteIssueMissingProxies": m59,
    "overwriteIssueNoProxySource": MessageLookupByLibrary.simpleMessage(
      "No proxies or proxy providers are selected, so the core rejects this group",
    ),
    "overwriteIssueReservedName": m60,
    "overwriteIssueSubscriptionGroupMissingProxies": m61,
    "overwriteIssuesSummary": m62,
    "overwriteTypeCustom": MessageLookupByLibrary.simpleMessage("Custom"),
    "overwriteTypeCustomDesc": MessageLookupByLibrary.simpleMessage(
      "Custom mode: fully customize proxies, proxy groups and rules",
    ),
    "palette": MessageLookupByLibrary.simpleMessage("Palette"),
    "password": MessageLookupByLibrary.simpleMessage("Password"),
    "paste": MessageLookupByLibrary.simpleMessage("Paste"),
    "pickFromAlbum": MessageLookupByLibrary.simpleMessage("Choose from album"),
    "pinWindow": MessageLookupByLibrary.simpleMessage("Pin window"),
    "pleaseBindWebDAV": MessageLookupByLibrary.simpleMessage(
      "Please bind WebDAV",
    ),
    "pleaseEnterScriptName": MessageLookupByLibrary.simpleMessage(
      "Please enter a script name",
    ),
    "pleaseUploadValidQrcode": MessageLookupByLibrary.simpleMessage(
      "Please upload a valid QR code",
    ),
    "policyActualPreview": MessageLookupByLibrary.simpleMessage(
      "Actual accepted configuration",
    ),
    "policyAndroidRequired": MessageLookupByLibrary.simpleMessage(
      "Managed policies can currently be applied only on Android. Draft editing and previews remain available.",
    ),
    "policyApply": MessageLookupByLibrary.simpleMessage(
      "Save and request application",
    ),
    "policyApplyConfirm": MessageLookupByLibrary.simpleMessage(
      "Use this policy for routing and DNS, including any explicit DIRECT choices. Original rules, DNS, providers and special overrides will not participate. Existing managed node selections will reset. This does not start a stopped proxy.",
    ),
    "policyApplyRequested": MessageLookupByLibrary.simpleMessage(
      "Selection saved and application requested. Check the actual configuration status.",
    ),
    "policyDraftAuthentication": MessageLookupByLibrary.simpleMessage(
      "Use username and password",
    ),
    "policyDraftBackupConsent": MessageLookupByLibrary.simpleMessage(
      "This frozen backup contains policy drafts and may contain credentials and original migration materials. Confirm a new backup before exporting it.",
    ),
    "policyDraftBackupLocal": MessageLookupByLibrary.simpleMessage(
      "The unencrypted ZIP saved to your chosen local file will include complete policy drafts, credentials, and migration materials. Continue?",
    ),
    "policyDraftBackupWebDav": MessageLookupByLibrary.simpleMessage(
      "The unencrypted ZIP uploaded to your selected WebDAV service will include complete policy drafts, credentials, and migration materials. Continue?",
    ),
    "policyDraftBootstrap": MessageLookupByLibrary.simpleMessage(
      "Bootstrap DNS (DIRECT)",
    ),
    "policyDraftConflict": MessageLookupByLibrary.simpleMessage(
      "The stored draft changed. Your input is preserved; reload before replacing it.",
    ),
    "policyDraftCopyFull": MessageLookupByLibrary.simpleMessage(
      "Copy full generated configuration",
    ),
    "policyDraftCopyFullConfirm": MessageLookupByLibrary.simpleMessage(
      "Copy the full generated configuration, including any usernames and passwords, to the clipboard?",
    ),
    "policyDraftDeleted": MessageLookupByLibrary.simpleMessage(
      "Policy draft deleted",
    ),
    "policyDraftDirectWarning": MessageLookupByLibrary.simpleMessage(
      "An explicit DIRECT domain default also sends DNS for unmatched domains directly to its selected DNS service.",
    ),
    "policyDraftDiscard": MessageLookupByLibrary.simpleMessage(
      "Discard unsaved changes?",
    ),
    "policyDraftDnsServices": MessageLookupByLibrary.simpleMessage(
      "DNS services",
    ),
    "policyDraftDomainDefault": MessageLookupByLibrary.simpleMessage(
      "Default for unmatched domains",
    ),
    "policyDraftDomainRules": MessageLookupByLibrary.simpleMessage(
      "Domain rules",
    ),
    "policyDraftExtract": MessageLookupByLibrary.simpleMessage(
      "Extract from saved configuration",
    ),
    "policyDraftExtractConfirm": MessageLookupByLibrary.simpleMessage(
      "Replace the editor contents with a draft extracted from local saved materials? Scripts are not executed. Unsupported rules remain blocked. This does not apply a configuration.",
    ),
    "policyDraftExtractFailed": MessageLookupByLibrary.simpleMessage(
      "Could not extract local saved materials. The draft is unchanged.",
    ),
    "policyDraftGeneratePreview": MessageLookupByLibrary.simpleMessage(
      "Generated draft preview",
    ),
    "policyDraftGroups": MessageLookupByLibrary.simpleMessage(
      "Static proxy groups",
    ),
    "policyDraftIncomplete": m63,
    "policyDraftIpDefault": MessageLookupByLibrary.simpleMessage(
      "Default for unmatched IPs",
    ),
    "policyDraftIpRules": MessageLookupByLibrary.simpleMessage("IP rules"),
    "policyDraftListeners": MessageLookupByLibrary.simpleMessage(
      "Preview listener ports",
    ),
    "policyDraftLoadFailed": MessageLookupByLibrary.simpleMessage(
      "Could not load the draft. Retry to reload it.",
    ),
    "policyDraftMembers": MessageLookupByLibrary.simpleMessage(
      "Select fixed node members",
    ),
    "policyDraftMigration": MessageLookupByLibrary.simpleMessage(
      "Historical migration materials",
    ),
    "policyDraftMigrationBlocked": MessageLookupByLibrary.simpleMessage(
      "Migration is blocked. Original materials and rule positions are preserved. Editing extracted rows or defaults cannot remove the block.",
    ),
    "policyDraftMigrationChoices": MessageLookupByLibrary.simpleMessage(
      "Extracted rows are candidates. Choose both defaults, DNS and bootstrap services explicitly. The original Profile, overwrite settings and global DNS keep using the traditional configuration path. This preview is not the current running configuration.",
    ),
    "policyDraftMigrationIp": MessageLookupByLibrary.simpleMessage(
      "Destination-IP rules may also restrict domain connections. Splitting them cannot preserve that protection.",
    ),
    "policyDraftMigrationMatch": MessageLookupByLibrary.simpleMessage(
      "A MATCH occurs before later rules. Its position cannot become an end-of-table default.",
    ),
    "policyDraftMigrationScript": MessageLookupByLibrary.simpleMessage(
      "Script output is unknown because scripts are not executed during extraction.",
    ),
    "policyDraftMigrationUnsupported": MessageLookupByLibrary.simpleMessage(
      "This rule, resource, or configuration is outside the supported migration scope.",
    ),
    "policyDraftMissing": MessageLookupByLibrary.simpleMessage(
      "This profile no longer exists. Your input has not been saved.",
    ),
    "policyDraftMoveDown": MessageLookupByLibrary.simpleMessage("Move down"),
    "policyDraftMoveUp": MessageLookupByLibrary.simpleMessage("Move up"),
    "policyDraftNeedsPreview": MessageLookupByLibrary.simpleMessage(
      "Inputs still need generated preview validation",
    ),
    "policyDraftNodes": MessageLookupByLibrary.simpleMessage(
      "Fixed SOCKS5 nodes",
    ),
    "policyDraftProtocol": MessageLookupByLibrary.simpleMessage("Protocol"),
    "policyDraftReadOnly": MessageLookupByLibrary.simpleMessage(
      "Unknown version or unsupported structure. The original content is preserved and cannot be previewed or edited.",
    ),
    "policyDraftReady": MessageLookupByLibrary.simpleMessage(
      "Draft preview validated; not applied",
    ),
    "policyDraftRebuild": MessageLookupByLibrary.simpleMessage(
      "Create an independent draft",
    ),
    "policyDraftRebuildConfirm": MessageLookupByLibrary.simpleMessage(
      "Discard this draft and any migration materials? The new policy will not preserve the old configuration’s protections. The original profile and running configuration stay unchanged.",
    ),
    "policyDraftReferenced": m64,
    "policyDraftReload": MessageLookupByLibrary.simpleMessage(
      "Reload stored draft",
    ),
    "policyDraftRestoreFailed": MessageLookupByLibrary.simpleMessage(
      "Could not complete restore. Reload to check the stored data. Any recovery notice still applies.",
    ),
    "policyDraftRestoreWarning": MessageLookupByLibrary.simpleMessage(
      "Override restore replaces entities when the archive contains entity data. Drafts absent from that backup may be removed. Archives with no entities preserve existing entities. Continue?",
    ),
    "policyDraftRevealCredentials": MessageLookupByLibrary.simpleMessage(
      "Show credentials",
    ),
    "policyDraftSaveFailed": MessageLookupByLibrary.simpleMessage(
      "Could not save the draft. Your input and the stored draft were preserved.",
    ),
    "policyDraftSaved": MessageLookupByLibrary.simpleMessage(
      "Draft saved; not applied",
    ),
    "policyDraftStorage": MessageLookupByLibrary.simpleMessage(
      "Drafts may contain credentials. They use the existing database directory (private app storage on Android). Backups are unencrypted ZIP files. Saving does not apply the draft.",
    ),
    "policyDraftTarget": MessageLookupByLibrary.simpleMessage("Routing target"),
    "policyDraftTitle": MessageLookupByLibrary.simpleMessage("Policy draft"),
    "policyDraftUdp": MessageLookupByLibrary.simpleMessage(
      "Enable UDP for this node",
    ),
    "policyDraftUnsaved": MessageLookupByLibrary.simpleMessage(
      "Unsaved draft; not applied",
    ),
    "policyDraftUnset": MessageLookupByLibrary.simpleMessage("Not configured"),
    "policyDraftUsername": MessageLookupByLibrary.simpleMessage("Username"),
    "policyFinalPreview": MessageLookupByLibrary.simpleMessage(
      "Generated final configuration",
    ),
    "policyMaintenanceNone": MessageLookupByLibrary.simpleMessage(
      "No default maintenance proxy",
    ),
    "policyMaintenanceRequired": MessageLookupByLibrary.simpleMessage(
      "Choose and apply a maintenance proxy group or node, or explicitly select Auto or Direct for this request. A previous target may no longer exist.",
    ),
    "policyMaintenanceTarget": MessageLookupByLibrary.simpleMessage(
      "Maintenance proxy target",
    ),
    "policyManagedEditRequired": MessageLookupByLibrary.simpleMessage(
      "This profile uses a managed policy. Edit routing and DNS in the policy draft, then explicitly request application.",
    ),
    "policyMaterialBindings": MessageLookupByLibrary.simpleMessage(
      "Source bindings",
    ),
    "policyMaterialCancel": MessageLookupByLibrary.simpleMessage(
      "Discard preview material",
    ),
    "policyMaterialCollections": MessageLookupByLibrary.simpleMessage(
      "Source collections",
    ),
    "policyMaterialDomain": MessageLookupByLibrary.simpleMessage(
      "Bind source domain collection",
    ),
    "policyMaterialGroup": MessageLookupByLibrary.simpleMessage(
      "Bind source select group",
    ),
    "policyMaterialIp": MessageLookupByLibrary.simpleMessage(
      "Bind source address collection",
    ),
    "policyMaterialLatest": MessageLookupByLibrary.simpleMessage(
      "Load latest material for preview",
    ),
    "policyMaterialLoaded": MessageLookupByLibrary.simpleMessage(
      "Latest material loaded. Rebind changed names, preview, then Apply to adopt it. Save only stores the draft.",
    ),
    "policyMaterialNode": MessageLookupByLibrary.simpleMessage(
      "Bind source node",
    ),
    "policyMaterialSource": MessageLookupByLibrary.simpleMessage(
      "Choose an exact source name",
    ),
    "policyMaterialUnavailable": MessageLookupByLibrary.simpleMessage(
      "Material is unavailable or incompatible. Check the source binding and preview again.",
    ),
    "policyOriginal": MessageLookupByLibrary.simpleMessage(
      "Use original profile",
    ),
    "policyOriginalConfirm": MessageLookupByLibrary.simpleMessage(
      "Leave managed routing and use the original profile with its rules, DNS and overrides? This can change the traffic path.",
    ),
    "policyOriginalStatus": MessageLookupByLibrary.simpleMessage(
      "Original profile selected",
    ),
    "policySelectedStatus": MessageLookupByLibrary.simpleMessage(
      "Policy selected; actual acceptance is shown separately",
    ),
    "policySelectionPending": MessageLookupByLibrary.simpleMessage(
      "The selected policy differs from the actual accepted configuration.",
    ),
    "policySelectionUnavailable": MessageLookupByLibrary.simpleMessage(
      "Managed policy is required but unavailable. Choose a valid policy.",
    ),
    "policyUnappliedEdits": MessageLookupByLibrary.simpleMessage(
      "Draft differs from the selected policy; edits are not applied",
    ),
    "port": MessageLookupByLibrary.simpleMessage("Port"),
    "portConflictTip": MessageLookupByLibrary.simpleMessage(
      "Please enter a different port",
    ),
    "portTip": m65,
    "prerequisites": MessageLookupByLibrary.simpleMessage("Prerequisites"),
    "pressKeyboard": MessageLookupByLibrary.simpleMessage(
      "Press a key combination",
    ),
    "preview": MessageLookupByLibrary.simpleMessage("Preview"),
    "previousMatch": MessageLookupByLibrary.simpleMessage("Previous match"),
    "process": MessageLookupByLibrary.simpleMessage("Process"),
    "profile": MessageLookupByLibrary.simpleMessage("Profile"),
    "profileAutoUpdateIntervalInvalidValidationDesc":
        MessageLookupByLibrary.simpleMessage(
          "Enter a positive whole number of minutes. An old invalid value is scheduled as one day.",
        ),
    "profileAutoUpdateIntervalNullValidationDesc":
        MessageLookupByLibrary.simpleMessage(
          "Please enter the auto-update interval",
        ),
    "profileDownloadFailed": MessageLookupByLibrary.simpleMessage(
      "The subscription download failed. The previous file was kept.",
    ),
    "profileDownloadTimeout": MessageLookupByLibrary.simpleMessage(
      "The subscription download exceeded 90 seconds.",
    ),
    "profileDownloadTooLarge": MessageLookupByLibrary.simpleMessage(
      "The subscription exceeds the 16 MiB download limit.",
    ),
    "profileHasUpdate": MessageLookupByLibrary.simpleMessage(
      "The profile has been modified. Turn off auto update?",
    ),
    "profileImportContinue": MessageLookupByLibrary.simpleMessage("Continue"),
    "profileImportDownloadFailed": MessageLookupByLibrary.simpleMessage(
      "Could not download the subscription. Check the URL and request route, then retry.",
    ),
    "profileImportDownloading": MessageLookupByLibrary.simpleMessage(
      "Downloading subscription…",
    ),
    "profileImportInvalid": MessageLookupByLibrary.simpleMessage(
      "The downloaded file is not a valid subscription. Check the URL.",
    ),
    "profileImportPreparing": MessageLookupByLibrary.simpleMessage(
      "Preparing import…",
    ),
    "profileImportSaving": MessageLookupByLibrary.simpleMessage(
      "Saving subscription…",
    ),
    "profileInvalidBody": MessageLookupByLibrary.simpleMessage(
      "The downloaded subscription is invalid. The previous file was kept.",
    ),
    "profileNameNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "Please enter the profile name",
    ),
    "profileRefreshFailed": MessageLookupByLibrary.simpleMessage(
      "Subscription refresh failed. Check the current configuration status.",
    ),
    "profileSavedNotApplied": MessageLookupByLibrary.simpleMessage(
      "The subscription was saved. Check the current configuration status; it may not have been applied.",
    ),
    "profileSavedRecoveryRequired": MessageLookupByLibrary.simpleMessage(
      "Subscription saved. Cleanup could not be confirmed. Recovery is required before further requests.",
    ),
    "profileUrlInvalidValidationDesc": MessageLookupByLibrary.simpleMessage(
      "Please enter a valid profile URL",
    ),
    "profileUrlNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "Please enter the profile URL",
    ),
    "profiles": MessageLookupByLibrary.simpleMessage("Profiles"),
    "profilesSort": MessageLookupByLibrary.simpleMessage("Sort profiles"),
    "project": MessageLookupByLibrary.simpleMessage("Project"),
    "providerInUse": m66,
    "providerRenameShadowed": m67,
    "providerSourceSubscription": MessageLookupByLibrary.simpleMessage(
      "Subscription",
    ),
    "providerUrlTip": MessageLookupByLibrary.simpleMessage(
      "Only remote providers are supported",
    ),
    "providers": MessageLookupByLibrary.simpleMessage("External resources"),
    "proxies": MessageLookupByLibrary.simpleMessage("Proxies"),
    "proxiesCount": m68,
    "proxiesEmpty": MessageLookupByLibrary.simpleMessage("Proxies are empty"),
    "proxyChains": MessageLookupByLibrary.simpleMessage("Proxy chain"),
    "proxyDefinition": MessageLookupByLibrary.simpleMessage(
      "Full configuration",
    ),
    "proxyDefinitionNotMap": MessageLookupByLibrary.simpleMessage(
      "The configuration must be a YAML mapping with a name and a type",
    ),
    "proxyFilter": MessageLookupByLibrary.simpleMessage("Proxy filter"),
    "proxyGroup": MessageLookupByLibrary.simpleMessage("Proxy group"),
    "proxyGroupEmpty": MessageLookupByLibrary.simpleMessage(
      "Proxy group is empty",
    ),
    "proxyGroupNameDuplicate": MessageLookupByLibrary.simpleMessage(
      "Duplicate proxy group name",
    ),
    "proxyNode": MessageLookupByLibrary.simpleMessage("Proxy node"),
    "proxyProviders": MessageLookupByLibrary.simpleMessage("Proxy providers"),
    "proxyProvidersEmpty": MessageLookupByLibrary.simpleMessage(
      "Proxy providers are empty",
    ),
    "proxyProvidersNotEmpty": MessageLookupByLibrary.simpleMessage(
      "Proxy providers cannot be empty",
    ),
    "proxyType": MessageLookupByLibrary.simpleMessage("Proxy type"),
    "pruneCache": MessageLookupByLibrary.simpleMessage("Prune cache"),
    "pureBlack": MessageLookupByLibrary.simpleMessage("Pure black"),
    "pureBlackMode": MessageLookupByLibrary.simpleMessage("Pure black mode"),
    "qrImageBusy": MessageLookupByLibrary.simpleMessage(
      "Image recognition is busy. Use the camera or import a URL or file.",
    ),
    "qrImageReadFailed": MessageLookupByLibrary.simpleMessage(
      "Unable to read this image. Choose another local image.",
    ),
    "qrImageTimeout": MessageLookupByLibrary.simpleMessage(
      "Image recognition timed out. Try again later or use the camera.",
    ),
    "qrcode": MessageLookupByLibrary.simpleMessage("QR code"),
    "qrcodeDesc": MessageLookupByLibrary.simpleMessage(
      "Scan a QR code to obtain a profile",
    ),
    "quickAdd": MessageLookupByLibrary.simpleMessage("Quick add"),
    "quickEdit": MessageLookupByLibrary.simpleMessage("Quick edit"),
    "quickFill": MessageLookupByLibrary.simpleMessage("Quick fill"),
    "rainbowScheme": MessageLookupByLibrary.simpleMessage("Rainbow"),
    "recentRequests": MessageLookupByLibrary.simpleMessage("Recent requests"),
    "recordType": MessageLookupByLibrary.simpleMessage("Record type"),
    "redirPort": MessageLookupByLibrary.simpleMessage("Redir port"),
    "redo": MessageLookupByLibrary.simpleMessage("Redo"),
    "releaseMemory": MessageLookupByLibrary.simpleMessage("Release memory"),
    "releaseMemoryFailed": MessageLookupByLibrary.simpleMessage(
      "Failed to release memory",
    ),
    "remote": MessageLookupByLibrary.simpleMessage("Remote"),
    "remoteDestination": MessageLookupByLibrary.simpleMessage(
      "Remote destination",
    ),
    "remove": MessageLookupByLibrary.simpleMessage("Remove"),
    "replace": MessageLookupByLibrary.simpleMessage("Replace"),
    "replaceAll": MessageLookupByLibrary.simpleMessage("Replace all"),
    "reportBuildIdentity": MessageLookupByLibrary.simpleMessage(
      "Build identity (missing fields are unknown)",
    ),
    "reportBusy": MessageLookupByLibrary.simpleMessage(
      "Busy or timed out. I/O may still be running; refresh later.",
    ),
    "reportCancelled": MessageLookupByLibrary.simpleMessage(
      "Cancelled. Check the destination for a possible partial copy.",
    ),
    "reportCorrupt": MessageLookupByLibrary.simpleMessage(
      "Damaged or unsupported item",
    ),
    "reportDeleteAll": MessageLookupByLibrary.simpleMessage(
      "Delete current reports",
    ),
    "reportDeleteWarning": MessageLookupByLibrary.simpleMessage(
      "Delete the selected report, or all reports in this snapshot? New reports may remain. Internal deduplication records and exported copies are kept. Future faults can still be recorded.",
    ),
    "reportDeleted": MessageLookupByLibrary.simpleMessage(
      "Selected reports deleted",
    ),
    "reportDestinationWarning": MessageLookupByLibrary.simpleMessage(
      "Choose the destination carefully: its provider may sync to the cloud. The app does not automatically send this report. Cancellation or failure may leave a partial copy.",
    ),
    "reportEmpty": MessageLookupByLibrary.simpleMessage("No saved reports"),
    "reportExportRaw": MessageLookupByLibrary.simpleMessage(
      "Export raw report (ZIP)",
    ),
    "reportExportSummary": MessageLookupByLibrary.simpleMessage(
      "Export summary (JSON)",
    ),
    "reportExported": MessageLookupByLibrary.simpleMessage(
      "Saved and verified",
    ),
    "reportFailed": MessageLookupByLibrary.simpleMessage(
      "Operation failed or only partly completed. Refresh; check any export destination.",
    ),
    "reportIntegrity": MessageLookupByLibrary.simpleMessage(
      "Integrity check failed. Check the destination for a partial copy.",
    ),
    "reportLimited": MessageLookupByLibrary.simpleMessage(
      "Directory limit reached; some items could not be processed.",
    ),
    "reportMetadataOnly": MessageLookupByLibrary.simpleMessage(
      "Metadata only; trace will not be filled in later",
    ),
    "reportRawMissing": MessageLookupByLibrary.simpleMessage(
      "Raw contents missing or inconsistent",
    ),
    "reportRawUnverified": MessageLookupByLibrary.simpleMessage(
      "Raw contents not verified",
    ),
    "reportRawWarning": MessageLookupByLibrary.simpleMessage(
      "Raw reports may contain credentials, addresses and memory fragments. Export only for an intended recipient. The system destination may sync to a cloud provider. Cancellation or failure may leave a partial copy. Continue with raw export?",
    ),
    "reportRefresh": MessageLookupByLibrary.simpleMessage("Refresh"),
    "reportRetention": MessageLookupByLibrary.simpleMessage(
      "Limits: 20 reports, 16 MiB, 30 days. Automatic cleanup is best effort.",
    ),
    "reportStale": MessageLookupByLibrary.simpleMessage(
      "Report changed or selection expired. Refresh and select again.",
    ),
    "reportTruncated": MessageLookupByLibrary.simpleMessage(
      "Truncated material; not a complete dump",
    ),
    "reportUnknownFormat": MessageLookupByLibrary.simpleMessage(
      "Unknown report format",
    ),
    "reportUsage": MessageLookupByLibrary.simpleMessage(
      "Storage usage (including unknown items and internal index)",
    ),
    "reportWrittenUnverified": MessageLookupByLibrary.simpleMessage(
      "Written; destination contents could not be verified",
    ),
    "request": MessageLookupByLibrary.simpleMessage("Request"),
    "requestDirectRecoveryMessage": m69,
    "requestDirectRecoveryTitle": MessageLookupByLibrary.simpleMessage(
      "Restore this item using Direct?",
    ),
    "requestMode": MessageLookupByLibrary.simpleMessage("Request route"),
    "requestModeAuto": MessageLookupByLibrary.simpleMessage("Auto"),
    "requestModeDirect": MessageLookupByLibrary.simpleMessage("Direct"),
    "requestModeHelp": MessageLookupByLibrary.simpleMessage(
      "Applies to this item’s own requests. Proxy requires a valid proxy node; Direct requires an available non-VPN network.",
    ),
    "requestModeProxy": MessageLookupByLibrary.simpleMessage("Proxy"),
    "requestPartialCommit": MessageLookupByLibrary.simpleMessage(
      "Some local changes could not be restored. Recovery files have been retained; automatic updates are blocked.",
    ),
    "requestProxyDefault": m70,
    "requestProxyTarget": MessageLookupByLibrary.simpleMessage("Proxy target"),
    "requestRestartRequired": MessageLookupByLibrary.simpleMessage(
      "An unfinished local save may still be running. Open App info → Force stop, then open FlClash again. Restarting the proxy service or closing the screen is not enough. Review the saved data in Source permissions after reopening.",
    ),
    "requestRouteUnavailable": MessageLookupByLibrary.simpleMessage(
      "The selected request route is unavailable.",
    ),
    "requests": MessageLookupByLibrary.simpleMessage("Requests"),
    "requestsAndUpdates": MessageLookupByLibrary.simpleMessage(
      "Requests and updates",
    ),
    "reset": MessageLookupByLibrary.simpleMessage("Reset"),
    "resetPageChangesTip": MessageLookupByLibrary.simpleMessage(
      "This page has changes. Are you sure you want to reset?",
    ),
    "resetTip": MessageLookupByLibrary.simpleMessage(
      "Are you sure you want to reset?",
    ),
    "resources": MessageLookupByLibrary.simpleMessage("Resources"),
    "respectRules": MessageLookupByLibrary.simpleMessage("Respect rules"),
    "respectRulesDesc": MessageLookupByLibrary.simpleMessage(
      "DNS connections follow rules; requires Proxy Server Nameserver",
    ),
    "responseCode": MessageLookupByLibrary.simpleMessage("Response code"),
    "restart": MessageLookupByLibrary.simpleMessage("Restart"),
    "restartCoreTip": MessageLookupByLibrary.simpleMessage(
      "Are you sure you want to restart the core?",
    ),
    "restore": MessageLookupByLibrary.simpleMessage("Restore"),
    "restoreAllData": MessageLookupByLibrary.simpleMessage("Restore all data"),
    "restoreOnlyConfig": MessageLookupByLibrary.simpleMessage(
      "Restore profiles only",
    ),
    "restoreStrategy": MessageLookupByLibrary.simpleMessage("Restore strategy"),
    "restoreStrategyCompatible": MessageLookupByLibrary.simpleMessage(
      "Compatible",
    ),
    "restoreStrategyOverride": MessageLookupByLibrary.simpleMessage("Override"),
    "restoreSuccess": MessageLookupByLibrary.simpleMessage(
      "Restore successful",
    ),
    "retry": MessageLookupByLibrary.simpleMessage("Retry"),
    "routeAddress": MessageLookupByLibrary.simpleMessage("Route addresses"),
    "routeMode": MessageLookupByLibrary.simpleMessage("Route mode"),
    "routeModeBypassPrivate": MessageLookupByLibrary.simpleMessage(
      "Bypass private addresses",
    ),
    "routeModeConfig": MessageLookupByLibrary.simpleMessage("Use config"),
    "ru": MessageLookupByLibrary.simpleMessage("Russian"),
    "rule": MessageLookupByLibrary.simpleMessage("Rule"),
    "ruleActionAndDesc": MessageLookupByLibrary.simpleMessage(
      "Logical rule AND",
    ),
    "ruleActionDomainDesc": MessageLookupByLibrary.simpleMessage(
      "Match the full domain",
    ),
    "ruleActionDomainKeywordDesc": MessageLookupByLibrary.simpleMessage(
      "Match a domain keyword",
    ),
    "ruleActionDomainRegexDesc": MessageLookupByLibrary.simpleMessage(
      "Match a domain regex",
    ),
    "ruleActionDomainSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "Match a domain suffix",
    ),
    "ruleActionDomainWildcardDesc": MessageLookupByLibrary.simpleMessage(
      "Wildcard match; only * and ? are supported",
    ),
    "ruleActionDscpDesc": MessageLookupByLibrary.simpleMessage(
      "Match the DSCP mark (tproxy UDP inbound only)",
    ),
    "ruleActionDstPortDesc": MessageLookupByLibrary.simpleMessage(
      "Match the destination port range",
    ),
    "ruleActionGeoipDesc": MessageLookupByLibrary.simpleMessage(
      "Match the IP\'s country code",
    ),
    "ruleActionGeositeDesc": MessageLookupByLibrary.simpleMessage(
      "Match domains in Geosite",
    ),
    "ruleActionInNameDesc": MessageLookupByLibrary.simpleMessage(
      "Match the inbound name",
    ),
    "ruleActionInPortDesc": MessageLookupByLibrary.simpleMessage(
      "Match the inbound port",
    ),
    "ruleActionInTypeDesc": MessageLookupByLibrary.simpleMessage(
      "Match the inbound type",
    ),
    "ruleActionInUserDesc": MessageLookupByLibrary.simpleMessage(
      "Match the inbound username; separate multiple usernames with /",
    ),
    "ruleActionIpAsnDesc": MessageLookupByLibrary.simpleMessage(
      "Match the IP\'s ASN",
    ),
    "ruleActionIpCidr6Desc": MessageLookupByLibrary.simpleMessage(
      "Match an IP address range; IP-CIDR6 is just an alias",
    ),
    "ruleActionIpCidrDesc": MessageLookupByLibrary.simpleMessage(
      "Match an IP address range",
    ),
    "ruleActionIpSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "Match an IP suffix range",
    ),
    "ruleActionMatchDesc": MessageLookupByLibrary.simpleMessage(
      "Match all requests, no conditions needed",
    ),
    "ruleActionNetworkDesc": MessageLookupByLibrary.simpleMessage(
      "Match TCP or UDP",
    ),
    "ruleActionNotDesc": MessageLookupByLibrary.simpleMessage(
      "Logical rule NOT",
    ),
    "ruleActionOrDesc": MessageLookupByLibrary.simpleMessage("Logical rule OR"),
    "ruleActionProcessNameDesc": MessageLookupByLibrary.simpleMessage(
      "Match by process name; matches the package name on Android",
    ),
    "ruleActionProcessNameRegexDesc": MessageLookupByLibrary.simpleMessage(
      "Match by process name regex; matches the package name on Android",
    ),
    "ruleActionProcessNameWildcardDesc": MessageLookupByLibrary.simpleMessage(
      "Match by process name wildcard; only * and ? are supported",
    ),
    "ruleActionProcessPathDesc": MessageLookupByLibrary.simpleMessage(
      "Match by the full process path",
    ),
    "ruleActionProcessPathRegexDesc": MessageLookupByLibrary.simpleMessage(
      "Match by process path regex",
    ),
    "ruleActionProcessPathWildcardDesc": MessageLookupByLibrary.simpleMessage(
      "Match by process path wildcard; only * and ? are supported",
    ),
    "ruleActionRematchNameDesc": MessageLookupByLibrary.simpleMessage(
      "Match the rematch name; separate multiple names with /",
    ),
    "ruleActionRuleSetDesc": MessageLookupByLibrary.simpleMessage(
      "Reference a rule set; requires rule-providers",
    ),
    "ruleActionSrcGeoipDesc": MessageLookupByLibrary.simpleMessage(
      "Match the source IP\'s country code",
    ),
    "ruleActionSrcIpAsnDesc": MessageLookupByLibrary.simpleMessage(
      "Match the source IP\'s ASN",
    ),
    "ruleActionSrcIpCidrDesc": MessageLookupByLibrary.simpleMessage(
      "Match a source IP address range",
    ),
    "ruleActionSrcIpSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "Match a source IP suffix range",
    ),
    "ruleActionSrcPortDesc": MessageLookupByLibrary.simpleMessage(
      "Match the source port range",
    ),
    "ruleActionSubRuleDesc": MessageLookupByLibrary.simpleMessage(
      "Match into a sub-rule; mind the parentheses",
    ),
    "ruleActionUidDesc": MessageLookupByLibrary.simpleMessage(
      "Match the Linux user ID",
    ),
    "ruleEmpty": MessageLookupByLibrary.simpleMessage("Rule is empty"),
    "ruleName": MessageLookupByLibrary.simpleMessage("Rule name"),
    "rulePresetBittorrentDirect": MessageLookupByLibrary.simpleMessage(
      "BitTorrent direct",
    ),
    "rulePresetBlockDot": MessageLookupByLibrary.simpleMessage(
      "Block DNS over TLS",
    ),
    "rulePresetBlockQuic": MessageLookupByLibrary.simpleMessage("Block QUIC"),
    "rulePresetBlockStun": MessageLookupByLibrary.simpleMessage("Block STUN"),
    "rulePresetLanDirect": MessageLookupByLibrary.simpleMessage("LAN direct"),
    "rulePresetSystemServicesDirect": MessageLookupByLibrary.simpleMessage(
      "Apple and Microsoft direct",
    ),
    "ruleProviders": MessageLookupByLibrary.simpleMessage("Rule providers"),
    "ruleSet": MessageLookupByLibrary.simpleMessage("Rule set"),
    "ruleTarget": MessageLookupByLibrary.simpleMessage("Rule target"),
    "rules": MessageLookupByLibrary.simpleMessage("Rules"),
    "rulesCount": m71,
    "runTime": MessageLookupByLibrary.simpleMessage("Run time"),
    "safeMode": MessageLookupByLibrary.simpleMessage("Safe mode"),
    "safeModeAppTitle": m72,
    "save": MessageLookupByLibrary.simpleMessage("Save"),
    "saveChanges": MessageLookupByLibrary.simpleMessage("Save the changes?"),
    "script": MessageLookupByLibrary.simpleMessage("Script"),
    "scriptModeDesc": MessageLookupByLibrary.simpleMessage(
      "Script mode: uses external extension scripts to override the configuration in one click",
    ),
    "scrollToSelected": MessageLookupByLibrary.simpleMessage(
      "Scroll to selected",
    ),
    "search": MessageLookupByLibrary.simpleMessage("Search"),
    "seconds": MessageLookupByLibrary.simpleMessage("seconds"),
    "secondsCount": m73,
    "selectAll": MessageLookupByLibrary.simpleMessage("Select all"),
    "selectProxies": MessageLookupByLibrary.simpleMessage("Select proxies"),
    "selectProxyProviders": MessageLookupByLibrary.simpleMessage(
      "Select proxy providers",
    ),
    "selectRuleSet": MessageLookupByLibrary.simpleMessage(
      "Please select a rule set",
    ),
    "selectSplitStrategy": MessageLookupByLibrary.simpleMessage(
      "Please select a split strategy",
    ),
    "selectSubRule": MessageLookupByLibrary.simpleMessage(
      "Please select a sub-rule",
    ),
    "selected": MessageLookupByLibrary.simpleMessage("Selected"),
    "selectedCountTitle": m74,
    "server": MessageLookupByLibrary.simpleMessage("Server"),
    "serviceAdvanced": MessageLookupByLibrary.simpleMessage(
      "Region / service check",
    ),
    "serviceAdvancedExplanation": MessageLookupByLibrary.simpleMessage(
      "This optional one-time check observes region and service-page clues using anonymous requests. It may contact extra endpoints listed below. No browser login cookies or subscription credentials are sent. Results do not prove account benefits, playback or device-wide protection. Basic connectivity is independent.",
    ),
    "serviceAdvancedTiming": MessageLookupByLibrary.simpleMessage(
      "Expires after 5 minutes. Minimum interval: 30 seconds. No automatic reruns; leaving this page cancels unfinished work. Step times measure response headers, not ping or throughput.",
    ),
    "serviceAllDisabled": MessageLookupByLibrary.simpleMessage(
      "All services disabled · Manage services",
    ),
    "serviceAvailable": MessageLookupByLibrary.simpleMessage("Available"),
    "serviceBasic": MessageLookupByLibrary.simpleMessage(
      "Basic HTTPS response",
    ),
    "serviceBasicExplanation": MessageLookupByLibrary.simpleMessage(
      "The displayed service is checked automatically in the foreground. Results expire after 5 minutes; route changes or returning to the app may trigger a new check. Checks start at least 30 seconds apart. Check all covers enabled services only. Only response headers are read; redirects and page resources are not loaded. A response does not prove site features, account access or device-wide protection.",
    ),
    "serviceBlocked": MessageLookupByLibrary.simpleMessage("Blocked"),
    "serviceBodyComplete": MessageLookupByLibrary.simpleMessage(
      "Response read completely",
    ),
    "serviceBodyLimit": MessageLookupByLibrary.simpleMessage(
      "Response size limit reached",
    ),
    "serviceCheck": MessageLookupByLibrary.simpleMessage("Check"),
    "serviceCheckAll": MessageLookupByLibrary.simpleMessage("Check all"),
    "serviceCheckedAt": m75,
    "serviceComingSoon": MessageLookupByLibrary.simpleMessage("Coming soon"),
    "serviceConnectFailed": MessageLookupByLibrary.simpleMessage(
      "This request could not establish a response",
    ),
    "serviceDetectedRegion": m76,
    "serviceDisallowedIsp": MessageLookupByLibrary.simpleMessage(
      "Disallowed ISP",
    ),
    "serviceDisneyExplanation": MessageLookupByLibrary.simpleMessage(
      "Starting this check registers an anonymous browser device, exchanges its assertion for a temporary token, and queries a session. Tokens are used only within this check and are not saved.",
    ),
    "serviceDnsFailed": MessageLookupByLibrary.simpleMessage(
      "This request could not resolve the host",
    ),
    "serviceElapsed": m77,
    "serviceExpired": m78,
    "serviceFailed": MessageLookupByLibrary.simpleMessage(
      "Unable to determine",
    ),
    "serviceHeaders": MessageLookupByLibrary.simpleMessage(
      "Response headers received",
    ),
    "serviceHttpResponse": MessageLookupByLibrary.simpleMessage(
      "HTTP response",
    ),
    "serviceIndeterminate": MessageLookupByLibrary.simpleMessage(
      "Unable to determine; the check may be incomplete or the response format may have changed.",
    ),
    "serviceManage": MessageLookupByLibrary.simpleMessage("Manage services"),
    "serviceMarkerFound": MessageLookupByLibrary.simpleMessage(
      "Required marker found",
    ),
    "serviceMultipleRoutes": MessageLookupByLibrary.simpleMessage(
      "Multiple exits · see each request",
    ),
    "serviceObserved": MessageLookupByLibrary.simpleMessage(
      "Service clues observed",
    ),
    "serviceOriginalsOnly": MessageLookupByLibrary.simpleMessage(
      "Originals only",
    ),
    "servicePending": MessageLookupByLibrary.simpleMessage("Not checked"),
    "serviceQueued": MessageLookupByLibrary.simpleMessage(
      "Waiting for check interval",
    ),
    "serviceReadError": MessageLookupByLibrary.simpleMessage(
      "Response interrupted or unreadable",
    ),
    "serviceRecipientBlocked": MessageLookupByLibrary.simpleMessage(
      "Recipient or redirect outside this check",
    ),
    "serviceRecipients": m79,
    "serviceRedirected": MessageLookupByLibrary.simpleMessage(
      "Redirect response",
    ),
    "serviceRequestLimit": MessageLookupByLibrary.simpleMessage(
      "Request limit reached",
    ),
    "serviceResponded": MessageLookupByLibrary.simpleMessage("Responded"),
    "serviceRestricted": MessageLookupByLibrary.simpleMessage(
      "Access restricted",
    ),
    "serviceRouteChanged": MessageLookupByLibrary.simpleMessage(
      "Route changed · check again manually",
    ),
    "serviceStartAdvanced": MessageLookupByLibrary.simpleMessage(
      "Start one-time check",
    ),
    "serviceStatus": MessageLookupByLibrary.simpleMessage("Service status"),
    "serviceTlsFailed": MessageLookupByLibrary.simpleMessage(
      "This request failed TLS identity validation",
    ),
    "serviceUnavailable": MessageLookupByLibrary.simpleMessage(
      "No valid response to this request",
    ),
    "serviceUnknownRoute": MessageLookupByLibrary.simpleMessage(
      "Route unknown",
    ),
    "serviceUnsupportedRegion": MessageLookupByLibrary.simpleMessage(
      "Region not supported",
    ),
    "settings": MessageLookupByLibrary.simpleMessage("Settings"),
    "show": MessageLookupByLibrary.simpleMessage("Show"),
    "showLess": MessageLookupByLibrary.simpleMessage("Collapse"),
    "showMore": MessageLookupByLibrary.simpleMessage("Expand"),
    "showNotificationStopAction": MessageLookupByLibrary.simpleMessage(
      "Stop button in notification",
    ),
    "showPassword": MessageLookupByLibrary.simpleMessage("Show password"),
    "shrink": MessageLookupByLibrary.simpleMessage("Compact"),
    "sidebarBlur": MessageLookupByLibrary.simpleMessage("Sidebar blur"),
    "sidebarBlurDesc": MessageLookupByLibrary.simpleMessage(
      "Show the blurred desktop behind the window through the sidebar",
    ),
    "silentLaunch": MessageLookupByLibrary.simpleMessage("Silent launch"),
    "silentLaunchDesc": MessageLookupByLibrary.simpleMessage(
      "Start without showing the window",
    ),
    "singleAdd": MessageLookupByLibrary.simpleMessage("Single add"),
    "singleValueTip": m80,
    "size": MessageLookupByLibrary.simpleMessage("Size"),
    "slide": MessageLookupByLibrary.simpleMessage("Slide"),
    "socksPort": MessageLookupByLibrary.simpleMessage("SOCKS port"),
    "sort": MessageLookupByLibrary.simpleMessage("Sort"),
    "source": MessageLookupByLibrary.simpleMessage("Source"),
    "sourceAcceptRevision": MessageLookupByLibrary.simpleMessage(
      "Accept this revision",
    ),
    "sourceAcceptedCapabilities": m81,
    "sourceAcceptedDns": m82,
    "sourceAcceptedProtocols": m83,
    "sourceAcceptedRevisions": m84,
    "sourceAppliedNotSaved": MessageLookupByLibrary.simpleMessage(
      "Applied; recovery not saved",
    ),
    "sourceAppliedRevision": MessageLookupByLibrary.simpleMessage(
      "Applied revision",
    ),
    "sourceAutomaticAllowed": MessageLookupByLibrary.simpleMessage(
      "Automatic maintenance allowed",
    ),
    "sourceAutomaticStopped": MessageLookupByLibrary.simpleMessage(
      "Automatic maintenance stopped",
    ),
    "sourceBatchPreparing": MessageLookupByLibrary.simpleMessage(
      "Loading associated sources…",
    ),
    "sourceBatchScope": MessageLookupByLibrary.simpleMessage(
      "Review this subscription, its final configuration and all listed sources. Accept approves only the content snapshots displayed here.",
    ),
    "sourceBinaryMaterial": MessageLookupByLibrary.simpleMessage(
      "Binary RuleSet: accept only these exact bytes. The rule count is unknown until the original parser validates the material.",
    ),
    "sourceCapabilitiesChanged": MessageLookupByLibrary.simpleMessage(
      "Node capabilities or group bindings changed.",
    ),
    "sourceCodeChanged": MessageLookupByLibrary.simpleMessage(
      "The exact script code changed.",
    ),
    "sourceConfigParsed": MessageLookupByLibrary.simpleMessage(
      "Parsed · associated sources checked separately",
    ),
    "sourceConfigurationUnavailable": MessageLookupByLibrary.simpleMessage(
      "Why the full source configuration is unavailable",
    ),
    "sourceDeclaredCapabilities": m85,
    "sourceDefaultExit": m86,
    "sourceDelegateMaintenance": MessageLookupByLibrary.simpleMessage(
      "Allow maintenance within this scope",
    ),
    "sourceDnsChanged": MessageLookupByLibrary.simpleMessage(
      "DNS services or their policy changed.",
    ),
    "sourceEntryChanged": MessageLookupByLibrary.simpleMessage(
      "Listener, tunnel, or control capabilities changed.",
    ),
    "sourceFinalUse": MessageLookupByLibrary.simpleMessage(
      "Final configuration",
    ),
    "sourceFirstUse": MessageLookupByLibrary.simpleMessage(
      "This source has not been accepted for use.",
    ),
    "sourceImplicitDirect": MessageLookupByLibrary.simpleMessage(
      "Implicit DIRECT fallback",
    ),
    "sourceInspectMaterial": MessageLookupByLibrary.simpleMessage(
      "Inspect source text (may contain credentials)",
    ),
    "sourceIp": MessageLookupByLibrary.simpleMessage("Source IP"),
    "sourceLoadCached": MessageLookupByLibrary.simpleMessage(
      "Ready · verified snapshot",
    ),
    "sourceLoadChecking": MessageLookupByLibrary.simpleMessage(
      "Checking subscription and permissions…",
    ),
    "sourceLoadDownloading": MessageLookupByLibrary.simpleMessage(
      "Downloading…",
    ),
    "sourceLoadFailed": MessageLookupByLibrary.simpleMessage("Failed"),
    "sourceLoadProgress": m87,
    "sourceLoadQueued": MessageLookupByLibrary.simpleMessage("Waiting"),
    "sourceLoadReady": MessageLookupByLibrary.simpleMessage("Ready"),
    "sourceLoadVerifying": MessageLookupByLibrary.simpleMessage("Verifying…"),
    "sourceLocalPolicy": MessageLookupByLibrary.simpleMessage("Local policy"),
    "sourceMaintenanceLimits": MessageLookupByLibrary.simpleMessage(
      "Only proven changes within this revision’s capabilities may update automatically. Other changes stay pending. Existing connections stay on their original sockets; resource limits can delay adoption.",
    ),
    "sourceMaterialCounts": m88,
    "sourceMaterialUnavailable": MessageLookupByLibrary.simpleMessage(
      "An associated source could not be loaded. Check its address, connection and request route, then retry.",
    ),
    "sourceNoPermissions": MessageLookupByLibrary.simpleMessage(
      "No accepted source permissions.",
    ),
    "sourceNodeImportHint": MessageLookupByLibrary.simpleMessage(
      "The loaded nodes can be used. This configuration uses app network settings and one proxy group; source rules, DNS and original groups are not applied. The original URL is kept and automatic refresh is off. Update manually to retry the complete configuration.",
    ),
    "sourceNodeUse": MessageLookupByLibrary.simpleMessage(
      "Nodes used as a provider",
    ),
    "sourceNotDeclared": MessageLookupByLibrary.simpleMessage(
      "Not declared by this source",
    ),
    "sourceNotDelegated": MessageLookupByLibrary.simpleMessage(
      "Automatic maintenance has not been delegated.",
    ),
    "sourceOwnDefaultConflict": MessageLookupByLibrary.simpleMessage(
      "Your own rules must end in one MATCH rule with the unmatched-traffic target you selected.",
    ),
    "sourceOwnDefaultRequired": MessageLookupByLibrary.simpleMessage(
      "Choose an explicit unmatched-traffic target for your own rules before applying.",
    ),
    "sourceOwnRoutingHint": MessageLookupByLibrary.simpleMessage(
      "Turn off to exclude source routing, listeners and tunnels. Your own rules need an explicit unmatched-traffic target; empty rules never restore source routing. DNS and node groups remain independent uses.",
    ),
    "sourcePartialBlocked": MessageLookupByLibrary.simpleMessage(
      "Required dependencies prevent a partial configuration",
    ),
    "sourcePartialConfigurationHint": MessageLookupByLibrary.simpleMessage(
      "Partial configuration: retains available rules, groups, DNS and accepted source content. Review disabled items and the default exit before accepting. The original URL is kept; automatic refresh is off. Update manually to restore the complete configuration.",
    ),
    "sourcePartialGroups": MessageLookupByLibrary.simpleMessage(
      "Groups to disable",
    ),
    "sourcePartialImportHint": MessageLookupByLibrary.simpleMessage(
      "All sources have been attempted. Available content is retained; missing dependencies are listed below. Retry failed sources or review the available configuration.",
    ),
    "sourcePartialMissing": MessageLookupByLibrary.simpleMessage(
      "Unavailable sources",
    ),
    "sourcePartialRules": MessageLookupByLibrary.simpleMessage(
      "Rules to disable (other rules keep their order)",
    ),
    "sourcePartialSettings": MessageLookupByLibrary.simpleMessage(
      "DNS policies to disable",
    ),
    "sourcePermissionEffects": MessageLookupByLibrary.simpleMessage(
      "Each action applies to the displayed use. Stopping automatic maintenance keeps accepted content. Stopping use closes affected connections and disables replay; other uses keep their own permissions.",
    ),
    "sourcePermissions": MessageLookupByLibrary.simpleMessage(
      "Source permissions",
    ),
    "sourcePermissionsUnavailable": MessageLookupByLibrary.simpleMessage(
      "Source permissions could not be read or verified. Retry; if this persists, check the app log.",
    ),
    "sourceProfileUse": MessageLookupByLibrary.simpleMessage("Profile content"),
    "sourceProposedDns": m89,
    "sourceProtocols": m90,
    "sourceProviderChanged": MessageLookupByLibrary.simpleMessage(
      "A provider or its download source changed.",
    ),
    "sourceRecoveryDescription": MessageLookupByLibrary.simpleMessage(
      "Check the saved profiles, scripts and permissions on this device. This will stop traffic through the current configuration and discard unfinished approvals. Review sources and apply the configuration again after the check.",
    ),
    "sourceRecoveryTitle": MessageLookupByLibrary.simpleMessage(
      "Review incomplete save",
    ),
    "sourceRecoveryUnavailable": MessageLookupByLibrary.simpleMessage(
      "Source permission changed, but the recovery checkpoint could not be updated. Restart recovery is unavailable.",
    ),
    "sourceRelatedSourcesCount": m91,
    "sourceRematchDenied": MessageLookupByLibrary.simpleMessage(
      "REMATCH nodes cannot be used while source routing is excluded.",
    ),
    "sourceReviewPending": MessageLookupByLibrary.simpleMessage(
      "Review required",
    ),
    "sourceReviewRequired": MessageLookupByLibrary.simpleMessage(
      "Source changes need review before they can be used.",
    ),
    "sourceReviewScope": MessageLookupByLibrary.simpleMessage(
      "Accept only sources you trust to choose the nodes and capabilities in this revision. Acceptance and actual application are separate.",
    ),
    "sourceReviewTitle": MessageLookupByLibrary.simpleMessage("Review source"),
    "sourceRoutingChanged": MessageLookupByLibrary.simpleMessage(
      "Routing, fixed protections, or the default exit changed.",
    ),
    "sourceRoutingExcluded": MessageLookupByLibrary.simpleMessage(
      "This content includes routing capabilities you excluded. Remove them or explicitly change the source routing choice.",
    ),
    "sourceRuleDelegation": m92,
    "sourceRuleOrigin": MessageLookupByLibrary.simpleMessage("Rule source"),
    "sourceRuleSetUse": MessageLookupByLibrary.simpleMessage(
      "Rule set content",
    ),
    "sourceSavePending": MessageLookupByLibrary.simpleMessage(
      "Save for later review",
    ),
    "sourceScriptScope": MessageLookupByLibrary.simpleMessage(
      "This code can read the configuration and write to console. It will not run until accepted. Its output is reviewed separately; code acceptance does not approve every output.",
    ),
    "sourceScriptTitle": MessageLookupByLibrary.simpleMessage("Review script"),
    "sourceStatusChecking": MessageLookupByLibrary.simpleMessage(
      "Checking source permissions…",
    ),
    "sourceStatusRetry": MessageLookupByLibrary.simpleMessage(
      "Permissions unavailable · retry",
    ),
    "sourceStopAutomatic": MessageLookupByLibrary.simpleMessage(
      "Stop automatic maintenance",
    ),
    "sourceStopUse": MessageLookupByLibrary.simpleMessage(
      "Stop using this content",
    ),
    "sourceStorageFull": MessageLookupByLibrary.simpleMessage(
      "The source storage limit was reached. This operation could not be completed.",
    ),
    "sourceSubscriptionReview": MessageLookupByLibrary.simpleMessage(
      "Review subscription",
    ),
    "sourceUnknownChanged": MessageLookupByLibrary.simpleMessage(
      "An effective change could not be classified safely.",
    ),
    "sourceUseAvailableConfiguration": MessageLookupByLibrary.simpleMessage(
      "Review available configuration",
    ),
    "sourceUseRouting": MessageLookupByLibrary.simpleMessage(
      "Use source routing rules",
    ),
    "specialProxy": MessageLookupByLibrary.simpleMessage("Special proxy"),
    "specialRules": MessageLookupByLibrary.simpleMessage("Special rules"),
    "speedStatistics": MessageLookupByLibrary.simpleMessage("Speed statistics"),
    "splitStrategy": MessageLookupByLibrary.simpleMessage("Split strategy"),
    "splitStrategyNotEmpty": MessageLookupByLibrary.simpleMessage(
      "Split strategy cannot be empty",
    ),
    "ssidsEmpty": MessageLookupByLibrary.simpleMessage("SSIDs are empty"),
    "stackMode": MessageLookupByLibrary.simpleMessage("Stack mode"),
    "standard": MessageLookupByLibrary.simpleMessage("Standard"),
    "standardModeDesc": MessageLookupByLibrary.simpleMessage(
      "Standard mode: overrides the basic configuration and offers simple rule additions",
    ),
    "start": MessageLookupByLibrary.simpleMessage("Start"),
    "startFromScratch": MessageLookupByLibrary.simpleMessage(
      "Start from scratch",
    ),
    "startVpn": MessageLookupByLibrary.simpleMessage("Starting VPN…"),
    "startupAndBackground": MessageLookupByLibrary.simpleMessage(
      "Startup and background",
    ),
    "status": MessageLookupByLibrary.simpleMessage("Status"),
    "statusDesc": MessageLookupByLibrary.simpleMessage(
      "When disabled, the system DNS is used",
    ),
    "stop": MessageLookupByLibrary.simpleMessage("Stop"),
    "stopVpn": MessageLookupByLibrary.simpleMessage("Stopping VPN…"),
    "strategy": MessageLookupByLibrary.simpleMessage("Strategy"),
    "style": MessageLookupByLibrary.simpleMessage("Style"),
    "subRule": MessageLookupByLibrary.simpleMessage("Sub-rule"),
    "subRuleEmpty": MessageLookupByLibrary.simpleMessage("Sub-rule is empty"),
    "subRuleNotEmpty": MessageLookupByLibrary.simpleMessage(
      "Sub-rule cannot be empty",
    ),
    "submit": MessageLookupByLibrary.simpleMessage("Submit"),
    "subscriptionInfo": MessageLookupByLibrary.simpleMessage(
      "Subscription info",
    ),
    "suspended": MessageLookupByLibrary.simpleMessage("Suspended…"),
    "switchProfile": MessageLookupByLibrary.simpleMessage("Switch profile"),
    "sync": MessageLookupByLibrary.simpleMessage("Sync"),
    "system": MessageLookupByLibrary.simpleMessage("System"),
    "systemApp": MessageLookupByLibrary.simpleMessage("System apps"),
    "systemProxy": MessageLookupByLibrary.simpleMessage("System proxy"),
    "tab": MessageLookupByLibrary.simpleMessage("Tab"),
    "tabAnimation": MessageLookupByLibrary.simpleMessage("Tab animation"),
    "tapToAuthorize": MessageLookupByLibrary.simpleMessage("Tap to authorize"),
    "tcpConcurrent": MessageLookupByLibrary.simpleMessage("TCP concurrent"),
    "testInterval": MessageLookupByLibrary.simpleMessage("Test interval"),
    "testUrl": MessageLookupByLibrary.simpleMessage("Test URL"),
    "testWhenUsed": MessageLookupByLibrary.simpleMessage("Test when used"),
    "textScale": MessageLookupByLibrary.simpleMessage("Text scaling"),
    "textScalePreview": MessageLookupByLibrary.simpleMessage(
      "Text in the app will look like this",
    ),
    "theme": MessageLookupByLibrary.simpleMessage("Theme"),
    "themeColor": MessageLookupByLibrary.simpleMessage("Theme color"),
    "themeDesc": MessageLookupByLibrary.simpleMessage(
      "Set dark mode and adjust colors",
    ),
    "themeMode": MessageLookupByLibrary.simpleMessage("Theme mode"),
    "tight": MessageLookupByLibrary.simpleMessage("Tight"),
    "time": MessageLookupByLibrary.simpleMessage("Time"),
    "timeout": MessageLookupByLibrary.simpleMessage("Timeout"),
    "tip": MessageLookupByLibrary.simpleMessage("Tip"),
    "toggle": MessageLookupByLibrary.simpleMessage("Toggle"),
    "tolerance": MessageLookupByLibrary.simpleMessage("Tolerance"),
    "tonalSpotScheme": MessageLookupByLibrary.simpleMessage("Tonal spot"),
    "tools": MessageLookupByLibrary.simpleMessage("Tools"),
    "torch": MessageLookupByLibrary.simpleMessage("Flashlight"),
    "total": MessageLookupByLibrary.simpleMessage("Total"),
    "totalTraffic": MessageLookupByLibrary.simpleMessage("Total traffic"),
    "tproxyPort": MessageLookupByLibrary.simpleMessage("TProxy port"),
    "trafficUsage": MessageLookupByLibrary.simpleMessage("Traffic usage"),
    "tun": MessageLookupByLibrary.simpleMessage("TUN"),
    "tunDesc": MessageLookupByLibrary.simpleMessage(
      "Only effective in administrator mode",
    ),
    "turnOff": MessageLookupByLibrary.simpleMessage("Turn off"),
    "turnOn": MessageLookupByLibrary.simpleMessage("Turn on"),
    "undo": MessageLookupByLibrary.simpleMessage("Undo"),
    "unifiedDelay": MessageLookupByLibrary.simpleMessage("Unified delay"),
    "unknown": MessageLookupByLibrary.simpleMessage("Unknown"),
    "unknownNetworkError": MessageLookupByLibrary.simpleMessage(
      "Unknown network error",
    ),
    "unmaximize": MessageLookupByLibrary.simpleMessage("Restore down"),
    "unnamed": MessageLookupByLibrary.simpleMessage("Unnamed"),
    "unpinWindow": MessageLookupByLibrary.simpleMessage("Unpin window"),
    "update": MessageLookupByLibrary.simpleMessage("Update"),
    "upload": MessageLookupByLibrary.simpleMessage("Upload"),
    "url": MessageLookupByLibrary.simpleMessage("URL"),
    "urlDesc": MessageLookupByLibrary.simpleMessage(
      "Obtain a profile from a URL",
    ),
    "urlTip": m93,
    "useHosts": MessageLookupByLibrary.simpleMessage("Use hosts"),
    "useProfile": MessageLookupByLibrary.simpleMessage("Use"),
    "useSystemHosts": MessageLookupByLibrary.simpleMessage("Use system hosts"),
    "usedTraffic": MessageLookupByLibrary.simpleMessage("Used traffic"),
    "userAgent": MessageLookupByLibrary.simpleMessage("User-Agent"),
    "value": MessageLookupByLibrary.simpleMessage("Value"),
    "vibrantScheme": MessageLookupByLibrary.simpleMessage("Vibrant"),
    "view": MessageLookupByLibrary.simpleMessage("View"),
    "vpnConfigChangeDetected": MessageLookupByLibrary.simpleMessage(
      "VPN-related configuration change detected",
    ),
    "vpnEnableDesc": MessageLookupByLibrary.simpleMessage(
      "Route all system traffic through VpnService automatically",
    ),
    "vpnTip": MessageLookupByLibrary.simpleMessage(
      "Changes take effect after restarting the VPN",
    ),
    "webDAVConfiguration": MessageLookupByLibrary.simpleMessage(
      "WebDAV configuration",
    ),
    "whitelistMode": MessageLookupByLibrary.simpleMessage("Whitelist mode"),
    "writeToSystem": MessageLookupByLibrary.simpleMessage("Write to system"),
    "writeToSystemDesc": MessageLookupByLibrary.simpleMessage(
      "Also set the system clock; Android ignores it",
    ),
    "yearsAgo": m94,
    "yes": MessageLookupByLibrary.simpleMessage("Yes"),
    "zhCN": MessageLookupByLibrary.simpleMessage("Simplified Chinese"),
  };
}
