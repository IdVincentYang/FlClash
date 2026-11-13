// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a ja locale. All the
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
  String get localeName => 'ja';

  static String m0(active, count) => "接続中 ${active}/${count}";

  static String m1(active, count) => "接続中 ${active}・観測 ${count} 件";

  static String m2(time) => "最終通信：${time}";

  static String m3(count) => "今回の実行・直近 ${count} 件の接続";

  static String m4(rules, exits) => "ルールの結果 ${rules} 種類 · 出口 ${exits} 種類";

  static String m5(uid) => "UID ${uid}";

  static String m6(count, skipped) => "${count}件を追加、${skipped}件は既存のためスキップ";

  static String m7(phase) => "前回の段階：${phase}";

  static String m8(reason) => "システムの終了理由：${reason}";

  static String m9(code) =>
      "Windows が FlClashCore.exe の実行を拒否しました（エラー ${code}）。スマート アプリ コントロールや AppLocker などのアプリ制御ポリシーは未署名のプログラムをブロックします。ポリシーで FlClash を許可するか、ポリシーを無効にしてから再試行してください。";

  static String m10(name) =>
      "システムが起動中の異常終了を報告しました。前回のプロファイル：${name}。今回は自動設定をスキップし、現在の選択とファイルを保持します。";

  static String m11(url) => "${url} からプロファイルを作成しますか？";

  static String m12(count) => "${count} 日前";

  static String m13(reason) => "遅延テストが完了しませんでした：${reason}";

  static String m14(label) => "選択した${label}を削除してもよろしいですか？";

  static String m15(label) => "この${label}を削除してもよろしいですか？";

  static String m16(label) => "${label}の詳細";

  static String m17(label) => "${label}は空にできません";

  static String m18(label) => "${label}はすでに存在します";

  static String m19(name) => "${name} はすでに最新です";

  static String m20(name) => "${name} を更新しました";

  static String m21(action) => "「${action}」で使用中です。保存するとこちらに移動します。";

  static String m22(modifiers) => "${modifiers} のいずれかを含めてください";

  static String m23(count) => "${count} 時間前";

  static String m24(count) => "${count} 時間";

  static String m25(target) => "${target} は無効なポリシーです";

  static String m26(proxyName) => "${proxyName} は無効なプロキシです";

  static String m27(providerName) => "${providerName} は無効なプロキシプロバイダーです";

  static String m28(ruleSet) => "${ruleSet} は無効なルールセットです";

  static String m29(subRule) => "${subRule} は無効な SUB_RULE です";

  static String m30(line, message) => "${line}行目：${message}";

  static String m31(name) => "${name} の操作";

  static String m32(name) => "現在の出口：${name}";

  static String m33(name) => "グループ「${name}」を削除しますか？";

  static String m34(name) => "利用できないノード: ${name}";

  static String m35(count) => "${count} ノード";

  static String m36(name) => "優先ノード：${name}";

  static String m37(count) => "${count} 個のグループに追加済み";

  static String m38(name) => "${name}";

  static String m39(appName) =>
      "1. システム設定 > プライバシーとセキュリティ を開く\n2. 位置情報サービス を選択\n3. リストで ${appName} を見つけてチェックを入れる\n\n設定が完了したらアプリに戻ると、通常どおり使用できます。ご協力ありがとうございます。";

  static String m40(label, max) => "${label}は最大${max}文字です";

  static String m41(size) => "${size} を解放しました";

  static String m42(count) => "${count} 分前";

  static String m43(count) => "${count} か月前";

  static String m44(code) =>
      "サーバーがアクセスを拒否しました（HTTP ${code}）。リンクの期限切れか、認証情報が誤っている可能性があります";

  static String m45(code) => "サーバーがリクエストを拒否しました（HTTP ${code}）";

  static String m46(code) =>
      "このアドレスには何も見つかりませんでした（HTTP ${code}）。URL が正しいか確認してください";

  static String m47(detail) => "ネットワークリクエストに失敗しました：${detail}";

  static String m48(code) => "サーバーで問題が発生しました（HTTP ${code}）。しばらくしてから再試行してください";

  static String m49(label) => "${label}はまだありません";

  static String m50(label) => "${label}は数値である必要があります";

  static String m51(message) => "コアがこのプロキシを解析できません：${message}";

  static String m52(name) => "名前 ${name} は他のプロキシまたはプロキシグループで使用されています";

  static String m53(path) => "プロキシグループが循環参照しています：${path}";

  static String m54(names) => "次のプロキシプロバイダーは存在しません：${names}";

  static String m55(names) => "次のプロキシまたはポリシーは存在しません：${names}";

  static String m56(name) => "${name} は組み込みポリシー名のため使用できません";

  static String m57(names) =>
      "プロファイル自身のプロキシグループが、カスタムプロキシに含まれないプロキシを参照しています：${names}";

  static String m58(count) => "${count} 件に問題があり、上書きの適用に失敗する可能性があります";

  static String m59(location) => "${location} を確認し、入力・修正してからプレビューしてください。";

  static String m60(locations) =>
      "このリソースは ${locations} で使用されています。参照を変更してから削除してください。";

  static String m61(label) => "${label} は 1024〜49151 の範囲で指定してください";

  static String m62(label, profiles) =>
      "${label} は ${profiles} のカスタムプロキシグループまたはルールでまだ使用されています。先にそこから外してください";

  static String m63(profiles, label) =>
      "${profiles} のサブスクリプションには既に ${label} があるため、名前を変えるとそちらが使われます。別の名前にしてください";

  static String m64(count) => "プロキシ ${count} 件";

  static String m65(host) =>
      "現在の設定ではこの項目を取得できません。今回の操作で ${host} への直接接続を許可しますか？操作の完了または接続先の変更で許可は失効します。";

  static String m66(target) => "GLOBAL（現在の選択：${target}）";

  static String m67(count) => "ルール ${count} 件";

  static String m68(appName) => "${appName}（セーフモード）";

  static String m69(count) => "${count} 秒";

  static String m70(count) => "${count} 件選択中";

  static String m71(time) => "${time} に検査";

  static String m72(region) => "報告された地域：${region}";

  static String m73(milliseconds) => "合計時間（待機・本文を含む）：${milliseconds} ms";

  static String m74(result) => "期限切れ：${result}";

  static String m75(hosts) => "接続先：${hosts}";

  static String m76(label) => "${label}は1項目のみ指定できます";

  static String m77(features) => "承認済みの宣言された機能：${features}";

  static String m78(services) => "承認済みDNSの範囲：${services}";

  static String m79(protocols) => "承認済みのノードプロトコル：${protocols}";

  static String m80(count) => "承認済みバージョン数：${count}";

  static String m81(features) => "宣言された機能：${features}";

  static String m82(target) => "ソースの既定の出口：${target}";

  static String m83(ready, total) => "準備完了：${ready}/${total}";

  static String m84(nodes, rules) => "ソース材料：ノード ${nodes} 件、規則 ${rules} 件";

  static String m85(services) => "提案されたDNSサービス：${services}";

  static String m86(protocols) => "ノードのプロトコル：${protocols}";

  static String m87(count) => "関連ソース：${count} 件";

  static String m88(targets) =>
      "委任するプロキシ規則ブロック：${targets}。条件は任意のドメインまたはIPを対象にできます。固定保護と既定の出口は変えず、DIRECTを拡大し得る削除は確認が必要です。";

  static String m89(label) => "${label}はURLである必要があります";

  static String m90(count) => "${count} 年前";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "about": MessageLookupByLibrary.simpleMessage("アプリについて"),
    "accessControl": MessageLookupByLibrary.simpleMessage("アクセス制御"),
    "accessControlAllowDesc": MessageLookupByLibrary.simpleMessage(
      "選択したアプリのみVPNを経由します",
    ),
    "accessControlDesc": MessageLookupByLibrary.simpleMessage(
      "プロキシを利用するアプリを設定します",
    ),
    "accessControlDisabledDesc": MessageLookupByLibrary.simpleMessage(
      "アプリアクセス制御は無効です",
    ),
    "accessControlNotAllowDesc": MessageLookupByLibrary.simpleMessage(
      "選択したアプリはVPNから除外されます",
    ),
    "accessControlSettings": MessageLookupByLibrary.simpleMessage("アクセス制御の設定"),
    "account": MessageLookupByLibrary.simpleMessage("アカウント"),
    "action": MessageLookupByLibrary.simpleMessage("アクション"),
    "actionDelayTest": MessageLookupByLibrary.simpleMessage("すべての遅延をテスト"),
    "actionDirectMode": MessageLookupByLibrary.simpleMessage("ダイレクトモード"),
    "actionGlobalMode": MessageLookupByLibrary.simpleMessage("グローバルモード"),
    "actionMode": MessageLookupByLibrary.simpleMessage("モード切替"),
    "actionProxy": MessageLookupByLibrary.simpleMessage("システムプロキシ"),
    "actionRuleMode": MessageLookupByLibrary.simpleMessage("ルールモード"),
    "actionStart": MessageLookupByLibrary.simpleMessage("開始/停止"),
    "actionTun": MessageLookupByLibrary.simpleMessage("TUN"),
    "actionUpdateProfiles": MessageLookupByLibrary.simpleMessage("プロファイルを更新"),
    "actionView": MessageLookupByLibrary.simpleMessage("表示/非表示"),
    "activityActive": MessageLookupByLibrary.simpleMessage("接続中"),
    "activityActiveFilterUnavailable": MessageLookupByLibrary.simpleMessage(
      "通信状態を確認できません。保持中の接続先を表示します。",
    ),
    "activityAllApps": MessageLookupByLibrary.simpleMessage("すべてのアプリ"),
    "activityCatalogueUnavailable": MessageLookupByLibrary.simpleMessage(
      "アプリ一覧を取得できません。観測済みの通信は表示されます。",
    ),
    "activityChecking": MessageLookupByLibrary.simpleMessage("接続状況を確認中…"),
    "activityCompactCounts": m0,
    "activityCounts": m1,
    "activityExcludedSetting": MessageLookupByLibrary.simpleMessage(
      "現在の設定：このアプリを除外",
    ),
    "activityExits": MessageLookupByLibrary.simpleMessage("観測した出口経路"),
    "activityIdentityUncertain": MessageLookupByLibrary.simpleMessage(
      "接続元のアプリを特定できません",
    ),
    "activityIncludedSetting": MessageLookupByLibrary.simpleMessage(
      "現在の設定：このアプリを対象にする",
    ),
    "activityIncomplete": MessageLookupByLibrary.simpleMessage("観測に欠落があります"),
    "activityLast": m2,
    "activityLoadingApps": MessageLookupByLibrary.simpleMessage("アプリ名を読み込み中…"),
    "activityNoActive": MessageLookupByLibrary.simpleMessage("確認済みの接続はありません"),
    "activityNoMatches": MessageLookupByLibrary.simpleMessage("一致するアプリはありません"),
    "activityNoObserved": MessageLookupByLibrary.simpleMessage(
      "まだ通信が観測されていません",
    ),
    "activityNoTargetMatches": MessageLookupByLibrary.simpleMessage(
      "一致する接続先がありません",
    ),
    "activityObservationScope": MessageLookupByLibrary.simpleMessage("観測の範囲"),
    "activityObserving": MessageLookupByLibrary.simpleMessage("VPN 通信を観測中"),
    "activityOnlyActiveTargets": MessageLookupByLibrary.simpleMessage(
      "通信中の接続先のみ表示",
    ),
    "activityPaused": MessageLookupByLibrary.simpleMessage("観測を一時停止・最近の通信を保持"),
    "activityPending": MessageLookupByLibrary.simpleMessage("未確認"),
    "activityRecent": MessageLookupByLibrary.simpleMessage("最近の通信"),
    "activityRetention": m3,
    "activityRouteCounts": m4,
    "activityRules": MessageLookupByLibrary.simpleMessage("観測したルール"),
    "activityRulesBypassed": MessageLookupByLibrary.simpleMessage(
      "グローバル・直接モードではルールは適用されません",
    ),
    "activityScopeHelp": MessageLookupByLibrary.simpleMessage(
      "FlClash が観測した通信のみを表示します。件数は保持中の接続数で、HTTP リクエスト数や完全な履歴ではありません。記録はメモリ内に保持され、プロセス再起動でリセットされます。バックグラウンド停止、イベント欠落、保持上限により通信が抜ける場合があります。現在の設定が実行中の VPN に反映済みとは限りません。",
    ),
    "activitySearchApps": MessageLookupByLibrary.simpleMessage(
      "アプリ名・パッケージ名で検索",
    ),
    "activitySearchTargets": MessageLookupByLibrary.simpleMessage(
      "ドメイン・IP アドレスで検索",
    ),
    "activitySharedIdentityHelp": MessageLookupByLibrary.simpleMessage(
      "これらのアプリは UID を共有しているため、接続元を一つに特定できません。",
    ),
    "activitySharedUid": MessageLookupByLibrary.simpleMessage("共有アプリ ID"),
    "activityShowAllApps": MessageLookupByLibrary.simpleMessage("すべてのアプリを表示"),
    "activitySnapshotFailed": MessageLookupByLibrary.simpleMessage(
      "更新できません・接続状況は未確認",
    ),
    "activityUid": m5,
    "activityUnknownApp": MessageLookupByLibrary.simpleMessage("不明なアプリ"),
    "activityUnknownTarget": MessageLookupByLibrary.simpleMessage("不明な接続先"),
    "activityVpnObserved": MessageLookupByLibrary.simpleMessage(
      "これらの接続で VPN 経由を確認",
    ),
    "add": MessageLookupByLibrary.simpleMessage("追加"),
    "addCustomProxy": MessageLookupByLibrary.simpleMessage("プロキシを追加"),
    "addOverrideEntry": MessageLookupByLibrary.simpleMessage("上書き項目を追加"),
    "addProfile": MessageLookupByLibrary.simpleMessage("プロファイルを追加"),
    "addProxies": MessageLookupByLibrary.simpleMessage("プロキシを追加"),
    "addProxyGroup": MessageLookupByLibrary.simpleMessage("プロキシグループを追加"),
    "addProxyProviders": MessageLookupByLibrary.simpleMessage("プロキシプロバイダーを追加"),
    "addRule": MessageLookupByLibrary.simpleMessage("ルールを追加"),
    "addSsid": MessageLookupByLibrary.simpleMessage("SSIDを追加"),
    "addWidget": MessageLookupByLibrary.simpleMessage("ウィジェットを追加"),
    "addedRules": MessageLookupByLibrary.simpleMessage("追加ルール"),
    "additionalParameters": MessageLookupByLibrary.simpleMessage("追加パラメータ"),
    "address": MessageLookupByLibrary.simpleMessage("アドレス"),
    "addressHelp": MessageLookupByLibrary.simpleMessage("WebDAVサーバーのアドレス"),
    "addressTip": MessageLookupByLibrary.simpleMessage(
      "有効なWebDAVアドレスを入力してください",
    ),
    "advancedConfig": MessageLookupByLibrary.simpleMessage("詳細設定"),
    "advancedConfigDesc": MessageLookupByLibrary.simpleMessage(
      "ネットワーク、DNS、追加ルール、スクリプト",
    ),
    "agree": MessageLookupByLibrary.simpleMessage("同意する"),
    "allowBypass": MessageLookupByLibrary.simpleMessage("アプリによるVPNバイパスを許可"),
    "allowLan": MessageLookupByLibrary.simpleMessage("LANプロキシ"),
    "androidServiceProxyOnly": MessageLookupByLibrary.simpleMessage("プロキシのみ"),
    "androidServiceStopped": MessageLookupByLibrary.simpleMessage("停止済み"),
    "androidServiceStopping": MessageLookupByLibrary.simpleMessage("サービスを停止中"),
    "androidServiceSuspended": MessageLookupByLibrary.simpleMessage("一時停止中"),
    "androidServiceTitle": MessageLookupByLibrary.simpleMessage("Android サービス"),
    "androidServiceUnavailable": MessageLookupByLibrary.simpleMessage(
      "サービス利用不可",
    ),
    "androidServiceVpnActive": MessageLookupByLibrary.simpleMessage("VPN 動作中"),
    "answers": MessageLookupByLibrary.simpleMessage("応答"),
    "app": MessageLookupByLibrary.simpleMessage("アプリ"),
    "appAccessControl": MessageLookupByLibrary.simpleMessage("アプリアクセス制御"),
    "appIconDesign": MessageLookupByLibrary.simpleMessage("アプリアイコンのデザイン"),
    "appendSystemDns": MessageLookupByLibrary.simpleMessage("システムDNSを追加"),
    "applicationNetwork": MessageLookupByLibrary.simpleMessage("アプリのネットワーク"),
    "applicationNetworkDesc": MessageLookupByLibrary.simpleMessage(
      "観測したアプリの通信・ルール・出口を確認",
    ),
    "appliedProfile": MessageLookupByLibrary.simpleMessage("適用中の設定"),
    "authentication": MessageLookupByLibrary.simpleMessage("認証"),
    "authenticationDesc": MessageLookupByLibrary.simpleMessage(
      "ローカルプロキシポートに認証を要求し、他のアプリによる無断利用を防ぎます",
    ),
    "authenticationSystemProxyDesc": MessageLookupByLibrary.simpleMessage(
      "認証が有効な間は適用されません",
    ),
    "authorize": MessageLookupByLibrary.simpleMessage("許可"),
    "authorized": MessageLookupByLibrary.simpleMessage("許可済み"),
    "auto": MessageLookupByLibrary.simpleMessage("自動"),
    "autoCloseConnections": MessageLookupByLibrary.simpleMessage("接続を自動的に閉じる"),
    "autoCloseConnectionsDesc": MessageLookupByLibrary.simpleMessage(
      "ノードの切り替え後、接続を自動的に閉じます",
    ),
    "autoLaunch": MessageLookupByLibrary.simpleMessage("自動起動"),
    "autoLaunchDesc": MessageLookupByLibrary.simpleMessage("システム起動時に自動的に起動します"),
    "autoRun": MessageLookupByLibrary.simpleMessage("自動実行"),
    "autoRunDesc": MessageLookupByLibrary.simpleMessage("アプリを開いたときに自動的に実行します"),
    "autoSetSystemDns": MessageLookupByLibrary.simpleMessage("システムDNSを自動設定"),
    "autoUpdate": MessageLookupByLibrary.simpleMessage("自動更新"),
    "autoUpdateInterval": MessageLookupByLibrary.simpleMessage("自動更新間隔（分）"),
    "back": MessageLookupByLibrary.simpleMessage("戻る"),
    "backgroundStartFailed": MessageLookupByLibrary.simpleMessage(
      "FlClashを起動できませんでした。アプリを開いて保留中のソースを確認するか、エラーを確認してください。",
    ),
    "backup": MessageLookupByLibrary.simpleMessage("バックアップ"),
    "backupAndRestore": MessageLookupByLibrary.simpleMessage("バックアップと復元"),
    "backupAndRestoreDesc": MessageLookupByLibrary.simpleMessage(
      "WebDAVまたはファイルでデータを同期します",
    ),
    "backupFromNewerVersion": MessageLookupByLibrary.simpleMessage(
      "このバックアップは新しいバージョンのアプリで作成されています。アプリを更新してから復元してください",
    ),
    "backupSuccess": MessageLookupByLibrary.simpleMessage("バックアップが完了しました"),
    "basicInfo": MessageLookupByLibrary.simpleMessage("基本情報"),
    "basicStrategy": MessageLookupByLibrary.simpleMessage("基本ポリシー"),
    "batchAdd": MessageLookupByLibrary.simpleMessage("一括追加"),
    "batchListInputTip": MessageLookupByLibrary.simpleMessage(
      "1行に1項目、またはカンマ区切りで入力してください",
    ),
    "batchMapInputTip": MessageLookupByLibrary.simpleMessage(
      "1行に1件、キーと値はスペースで区切ってください",
    ),
    "batchPreviewTip": m6,
    "batteryOptimizationDesc": MessageLookupByLibrary.simpleMessage(
      "バックグラウンドでの動作を維持するため、このアプリの電池の最適化を無効にしてください。タップすると設定を開きます。",
    ),
    "batteryOptimizationStatusTip": MessageLookupByLibrary.simpleMessage(
      "システムの制限により、実行中は電池の最適化の状態を正しく取得できません",
    ),
    "behavior": MessageLookupByLibrary.simpleMessage("動作"),
    "bind": MessageLookupByLibrary.simpleMessage("連携"),
    "blacklistMode": MessageLookupByLibrary.simpleMessage("ブラックリストモード"),
    "blockConnection": MessageLookupByLibrary.simpleMessage("接続をブロック"),
    "bootExitAnr": MessageLookupByLibrary.simpleMessage("アプリが応答しない"),
    "bootExitCrash": MessageLookupByLibrary.simpleMessage("アプリのクラッシュ"),
    "bootExitInitialization": MessageLookupByLibrary.simpleMessage(
      "プロセスの初期化失敗",
    ),
    "bootExitNativeCrash": MessageLookupByLibrary.simpleMessage("ネイティブクラッシュ"),
    "bootPhaseBootstrap": MessageLookupByLibrary.simpleMessage("アプリの準備"),
    "bootPhaseCore": MessageLookupByLibrary.simpleMessage("Core に接続"),
    "bootPhaseRecovery": MessageLookupByLibrary.simpleMessage("復旧の確認"),
    "bootPhaseSetup": MessageLookupByLibrary.simpleMessage("設定の初期化"),
    "bootRecordDamaged": MessageLookupByLibrary.simpleMessage(
      "起動保護の記録が破損しています。今回は自動設定をスキップします。この記録のみ再作成しますか？元の記録を保持して続行することもできます。プロファイル、設定、診断ファイルは保持されます。",
    ),
    "bootRecordKeep": MessageLookupByLibrary.simpleMessage("保持して続行"),
    "bootRecordNewer": MessageLookupByLibrary.simpleMessage(
      "起動記録は新しい形式のため、そのまま保持します。自動設定をスキップしますが、手動操作は可能です。",
    ),
    "bootRecordRebuild": MessageLookupByLibrary.simpleMessage("起動記録を再作成"),
    "bootRecordUnavailable": MessageLookupByLibrary.simpleMessage(
      "起動保護の記録を読み書きできません。今回は自動設定をスキップします。既存のサービスとファイルは保持され、手動操作は可能です。",
    ),
    "bootRecoveryPhase": m7,
    "bootRecoveryReason": m8,
    "bootRecoveryRepeated": MessageLookupByLibrary.simpleMessage(
      "起動が連続して中断されました。プロファイル一覧で確認または選択し直してから、手動で開始してください。",
    ),
    "bypassDomain": MessageLookupByLibrary.simpleMessage("除外ドメイン"),
    "bypassDomainDesc": MessageLookupByLibrary.simpleMessage(
      "システムプロキシが有効な場合のみ適用されます",
    ),
    "cache": MessageLookupByLibrary.simpleMessage("キャッシュ"),
    "cacheAlgorithm": MessageLookupByLibrary.simpleMessage("キャッシュアルゴリズム"),
    "cacheCorrupt": MessageLookupByLibrary.simpleMessage(
      "キャッシュが破損しています。クリアしますか？",
    ),
    "cacheMaxSize": MessageLookupByLibrary.simpleMessage("キャッシュサイズ"),
    "cameraPermissionDesc": MessageLookupByLibrary.simpleMessage(
      "QRコードをスキャンするには、システム設定でカメラへのアクセスを許可するか、アルバムからQRコード画像を選択してください。",
    ),
    "cameraPermissionRequired": MessageLookupByLibrary.simpleMessage(
      "カメラの権限が必要です",
    ),
    "cameraUnavailable": MessageLookupByLibrary.simpleMessage("カメラを使用できません"),
    "cancel": MessageLookupByLibrary.simpleMessage("キャンセル"),
    "cancelSelectAll": MessageLookupByLibrary.simpleMessage("すべて選択解除"),
    "changeProxyFailedTip": MessageLookupByLibrary.simpleMessage(
      "プロキシの切り替えに失敗したため、前回の選択に戻しました",
    ),
    "changelogBreaking": MessageLookupByLibrary.simpleMessage("破壊的変更"),
    "changelogFeatures": MessageLookupByLibrary.simpleMessage("新機能"),
    "changelogFixes": MessageLookupByLibrary.simpleMessage("不具合修正"),
    "changelogPerformance": MessageLookupByLibrary.simpleMessage("パフォーマンス"),
    "changelogReverts": MessageLookupByLibrary.simpleMessage("取り消し"),
    "checkCertificate": MessageLookupByLibrary.simpleMessage("TLS証明書を検証"),
    "checkCertificateDesc": MessageLookupByLibrary.simpleMessage(
      "信頼できない証明書を拒否します。無効にすると、サブスクリプションやバックアップが中間者攻撃にさらされます",
    ),
    "checkUpdate": MessageLookupByLibrary.simpleMessage("更新を確認"),
    "checkUpdateError": MessageLookupByLibrary.simpleMessage("すでに最新バージョンです"),
    "clearData": MessageLookupByLibrary.simpleMessage("データを消去"),
    "clearSearch": MessageLookupByLibrary.simpleMessage("検索をクリア"),
    "clipboardExport": MessageLookupByLibrary.simpleMessage("クリップボードへエクスポート"),
    "clipboardImport": MessageLookupByLibrary.simpleMessage("クリップボードからインポート"),
    "clipboardWriteFailed": MessageLookupByLibrary.simpleMessage(
      "クリップボードにコピーできませんでした。選択範囲が大きすぎる可能性があります",
    ),
    "close": MessageLookupByLibrary.simpleMessage("閉じる"),
    "closeConnections": MessageLookupByLibrary.simpleMessage("接続を閉じる"),
    "color": MessageLookupByLibrary.simpleMessage("カラー"),
    "colorSchemes": MessageLookupByLibrary.simpleMessage("カラースキーム"),
    "columns": MessageLookupByLibrary.simpleMessage("列数"),
    "compatible": MessageLookupByLibrary.simpleMessage("互換モード"),
    "configApplying": MessageLookupByLibrary.simpleMessage("設定を適用中"),
    "configDataDetected": MessageLookupByLibrary.simpleMessage(
      "設定内にデータが見つかりました",
    ),
    "configInactive": MessageLookupByLibrary.simpleMessage("トラフィックを処理していません"),
    "configLoaded": MessageLookupByLibrary.simpleMessage("読み込み済み・トラフィック未処理"),
    "configRetained": MessageLookupByLibrary.simpleMessage(
      "新しい設定は未適用です。以前の設定を使用しています",
    ),
    "confirm": MessageLookupByLibrary.simpleMessage("OK"),
    "confirmClearAllData": MessageLookupByLibrary.simpleMessage(
      "すべてのデータを消去してもよろしいですか？",
    ),
    "confirmDeleteProxyGroup": MessageLookupByLibrary.simpleMessage(
      "このプロキシグループを削除してもよろしいですか？",
    ),
    "confirmExitWindow": MessageLookupByLibrary.simpleMessage(
      "現在のウィンドウを閉じてもよろしいですか？",
    ),
    "confirmForceCrashCore": MessageLookupByLibrary.simpleMessage(
      "コアを強制クラッシュさせてもよろしいですか？",
    ),
    "confirmOverwriteTip": MessageLookupByLibrary.simpleMessage(
      "確定すると既存のデータを上書きします",
    ),
    "connected": MessageLookupByLibrary.simpleMessage("接続済み"),
    "connecting": MessageLookupByLibrary.simpleMessage("接続中…"),
    "connection": MessageLookupByLibrary.simpleMessage("接続"),
    "connections": MessageLookupByLibrary.simpleMessage("接続"),
    "connectivity": MessageLookupByLibrary.simpleMessage("接続状態："),
    "content": MessageLookupByLibrary.simpleMessage("内容"),
    "contentNotEmpty": MessageLookupByLibrary.simpleMessage("内容は空にできません"),
    "contentScheme": MessageLookupByLibrary.simpleMessage("コンテンツ"),
    "controlGlobalAddedRules": MessageLookupByLibrary.simpleMessage(
      "グローバル追加ルールを管理",
    ),
    "copy": MessageLookupByLibrary.simpleMessage("コピー"),
    "copyEnvVar": MessageLookupByLibrary.simpleMessage("環境変数をコピー"),
    "copyLink": MessageLookupByLibrary.simpleMessage("リンクをコピー"),
    "copySuccess": MessageLookupByLibrary.simpleMessage("コピーしました"),
    "core": MessageLookupByLibrary.simpleMessage("コア"),
    "coreBlockedByPolicyTip": m9,
    "coreBlockedBySmartAppControlTip": MessageLookupByLibrary.simpleMessage(
      "Windows のスマート アプリ コントロールが、署名されていない FlClashCore.exe をブロックしました。Windows セキュリティ → アプリとブラウザーの制御 → スマート アプリ コントロールの設定で「オフ」を選び、FlClash を再起動してください。一度オフにすると、Windows を再インストールしない限り再度オンにはできません。",
    ),
    "coreStatus": MessageLookupByLibrary.simpleMessage("コアの状態"),
    "country": MessageLookupByLibrary.simpleMessage("地域"),
    "crashDetected": MessageLookupByLibrary.simpleMessage("クラッシュを検出しました"),
    "crashDetectedTip": m10,
    "crashTest": MessageLookupByLibrary.simpleMessage("クラッシュテスト"),
    "create": MessageLookupByLibrary.simpleMessage("作成"),
    "createProfileFromUrlTip": m11,
    "creationTime": MessageLookupByLibrary.simpleMessage("作成日時"),
    "custom": MessageLookupByLibrary.simpleMessage("カスタム"),
    "customProxiesEmpty": MessageLookupByLibrary.simpleMessage(
      "カスタムプロキシがないため、プロファイル自身のプロキシを使用します",
    ),
    "cut": MessageLookupByLibrary.simpleMessage("切り取り"),
    "dark": MessageLookupByLibrary.simpleMessage("ダーク"),
    "dashboard": MessageLookupByLibrary.simpleMessage("ダッシュボード"),
    "dataChangedSave": MessageLookupByLibrary.simpleMessage(
      "データの変更を検出しました。保存しますか？",
    ),
    "databaseWriteFailedTip": MessageLookupByLibrary.simpleMessage(
      "変更の保存に失敗したため、元に戻しました",
    ),
    "daysAgo": m12,
    "defaultText": MessageLookupByLibrary.simpleMessage("デフォルト"),
    "delay": MessageLookupByLibrary.simpleMessage("遅延"),
    "delayTest": MessageLookupByLibrary.simpleMessage("遅延テスト"),
    "delayTestFailed": m13,
    "delayTestNoResult": MessageLookupByLibrary.simpleMessage(
      "Core からテスト結果が返されませんでした。プロキシの接続を確認して再試行してください。",
    ),
    "delayTestRequiresProxy": MessageLookupByLibrary.simpleMessage(
      "プロキシを起動し、接続が完了してからノードの遅延をテストしてください。",
    ),
    "delayTestUnavailable": MessageLookupByLibrary.simpleMessage("テスト不可"),
    "delayTestWaiting": MessageLookupByLibrary.simpleMessage("テスト待ち"),
    "delayTestWaitingResult": MessageLookupByLibrary.simpleMessage("結果待ち"),
    "delete": MessageLookupByLibrary.simpleMessage("削除"),
    "deleteMultipTip": m14,
    "deleteTip": m15,
    "desc": MessageLookupByLibrary.simpleMessage(
      "ClashMetaベースのマルチプラットフォーム対応プロキシクライアント。シンプルで使いやすく、オープンソースで広告もありません。",
    ),
    "destination": MessageLookupByLibrary.simpleMessage("宛先"),
    "destinationGeoIP": MessageLookupByLibrary.simpleMessage("宛先GeoIP"),
    "destinationIPASN": MessageLookupByLibrary.simpleMessage("宛先IP ASN"),
    "details": m16,
    "detectionTip": MessageLookupByLibrary.simpleMessage(
      "サードパーティAPIに依存しているため、参考値です",
    ),
    "developerMode": MessageLookupByLibrary.simpleMessage("開発者モード"),
    "developerModeEnableTip": MessageLookupByLibrary.simpleMessage(
      "開発者モードが有効になりました。",
    ),
    "dialerProxy": MessageLookupByLibrary.simpleMessage("ダイヤラープロキシ"),
    "dialerProxyDesc": MessageLookupByLibrary.simpleMessage(
      "NTPサーバーへの接続に使用するアウトバウンド",
    ),
    "direct": MessageLookupByLibrary.simpleMessage("ダイレクト"),
    "disableUDP": MessageLookupByLibrary.simpleMessage("UDPを無効化"),
    "disabled": MessageLookupByLibrary.simpleMessage("無効"),
    "discardChanges": MessageLookupByLibrary.simpleMessage("変更を破棄しますか？"),
    "disconnected": MessageLookupByLibrary.simpleMessage("切断済み"),
    "discoverNewVersion": MessageLookupByLibrary.simpleMessage(
      "新しいバージョンが見つかりました",
    ),
    "dnsHijacking": MessageLookupByLibrary.simpleMessage("DNSハイジャック"),
    "dnsMode": MessageLookupByLibrary.simpleMessage("DNSモード"),
    "dnsQueries": MessageLookupByLibrary.simpleMessage("DNSクエリ"),
    "docked": MessageLookupByLibrary.simpleMessage("固定"),
    "domain": MessageLookupByLibrary.simpleMessage("ドメイン"),
    "download": MessageLookupByLibrary.simpleMessage("ダウンロード"),
    "edit": MessageLookupByLibrary.simpleMessage("編集"),
    "editGlobalRules": MessageLookupByLibrary.simpleMessage("グローバルルールを編集"),
    "editProxy": MessageLookupByLibrary.simpleMessage("プロキシを編集"),
    "editProxyGroup": MessageLookupByLibrary.simpleMessage("プロキシグループを編集"),
    "editRule": MessageLookupByLibrary.simpleMessage("ルールを編集"),
    "editSsid": MessageLookupByLibrary.simpleMessage("SSIDを編集"),
    "editorUnavailable": MessageLookupByLibrary.simpleMessage("エディターを利用できません"),
    "emptyTip": m17,
    "en": MessageLookupByLibrary.simpleMessage("英語"),
    "enabled": MessageLookupByLibrary.simpleMessage("有効"),
    "entries": MessageLookupByLibrary.simpleMessage(" 件"),
    "error": MessageLookupByLibrary.simpleMessage("エラー"),
    "exclude": MessageLookupByLibrary.simpleMessage("最近のタスクから隠す"),
    "excludeDesc": MessageLookupByLibrary.simpleMessage(
      "バックグラウンド時に、最近のタスクからアプリを隠します",
    ),
    "excludeProxyFilter": MessageLookupByLibrary.simpleMessage("除外ノードフィルター"),
    "excludeSsids": MessageLookupByLibrary.simpleMessage("除外SSID"),
    "excludeSsidsDesc": MessageLookupByLibrary.simpleMessage(
      "除外したSSIDのWi-Fiに接続すると、アプリの実行状態が自動的に切り替わります",
    ),
    "excludeType": MessageLookupByLibrary.simpleMessage("除外タイプ"),
    "existsTip": m18,
    "exit": MessageLookupByLibrary.simpleMessage("終了"),
    "exitFullScreen": MessageLookupByLibrary.simpleMessage("全画面表示を終了"),
    "expand": MessageLookupByLibrary.simpleMessage("標準"),
    "expectedStatus": MessageLookupByLibrary.simpleMessage("期待するステータス"),
    "expireTime": MessageLookupByLibrary.simpleMessage("有効期限"),
    "exportFile": MessageLookupByLibrary.simpleMessage("ファイルをエクスポート"),
    "exportLogs": MessageLookupByLibrary.simpleMessage("ログをエクスポート"),
    "exportSuccess": MessageLookupByLibrary.simpleMessage("エクスポートが完了しました"),
    "expressiveScheme": MessageLookupByLibrary.simpleMessage("エクスプレッシブ"),
    "externalController": MessageLookupByLibrary.simpleMessage("外部コントローラー"),
    "externalControllerDesc": MessageLookupByLibrary.simpleMessage(
      "有効にすると、ポート9090でClashコアを制御できます",
    ),
    "externalLink": MessageLookupByLibrary.simpleMessage("外部リンク"),
    "extraLarge": MessageLookupByLibrary.simpleMessage("特大"),
    "fade": MessageLookupByLibrary.simpleMessage("フェード"),
    "fakeipFilter": MessageLookupByLibrary.simpleMessage("Fake-IPフィルター"),
    "fakeipFilterMode": MessageLookupByLibrary.simpleMessage("Fake-IPフィルターモード"),
    "fakeipFilterModeDesc": MessageLookupByLibrary.simpleMessage(
      "blacklistは一致を除外、whitelistは一致のみ、ruleはルールで判定",
    ),
    "fakeipRange": MessageLookupByLibrary.simpleMessage("Fake-IP範囲"),
    "fakeipRange6": MessageLookupByLibrary.simpleMessage("Fake-IP範囲（IPv6）"),
    "fakeipTtl": MessageLookupByLibrary.simpleMessage("Fake-IP TTL"),
    "fallbackFilter": MessageLookupByLibrary.simpleMessage("フォールバックフィルター"),
    "fidelityScheme": MessageLookupByLibrary.simpleMessage("フィデリティ"),
    "file": MessageLookupByLibrary.simpleMessage("ファイル"),
    "fileDesc": MessageLookupByLibrary.simpleMessage("プロファイルファイルを直接アップロードします"),
    "fileIsUpdate": MessageLookupByLibrary.simpleMessage(
      "ファイルが変更されています。変更を保存しますか？",
    ),
    "filter": MessageLookupByLibrary.simpleMessage("フィルター"),
    "findProcessMode": MessageLookupByLibrary.simpleMessage("プロセス検出"),
    "floating": MessageLookupByLibrary.simpleMessage("フローティング"),
    "followProfile": MessageLookupByLibrary.simpleMessage("プロファイルに従う"),
    "followSystem": MessageLookupByLibrary.simpleMessage("システムに従う"),
    "fontFamily": MessageLookupByLibrary.simpleMessage("フォント"),
    "fontSize": MessageLookupByLibrary.simpleMessage("サイズ"),
    "forceRestartCoreTip": MessageLookupByLibrary.simpleMessage(
      "コアを強制再起動してもよろしいですか？",
    ),
    "format": MessageLookupByLibrary.simpleMessage("形式"),
    "fruitSaladScheme": MessageLookupByLibrary.simpleMessage("フルーツサラダ"),
    "general": MessageLookupByLibrary.simpleMessage("一般"),
    "geoAutoUpdate": MessageLookupByLibrary.simpleMessage("自動更新"),
    "geoAutoUpdateInterval": MessageLookupByLibrary.simpleMessage("自動更新間隔"),
    "geoAutoUpdateIntervalTip": MessageLookupByLibrary.simpleMessage(
      "自動更新間隔は0より大きくしてください",
    ),
    "geoOptions": MessageLookupByLibrary.simpleMessage("Geoオプション"),
    "geoResourceAsnAbout": MessageLookupByLibrary.simpleMessage(
      "IP アドレスに対応する自律システム番号（ASN）と、通信事業者やクラウドネットワークなどの運営組織を調べます。IP-ASN と SRC-IP-ASN ルールで使用します。",
    ),
    "geoResourceGeoipAbout": MessageLookupByLibrary.simpleMessage(
      ".dat 形式で IP アドレス範囲を国・地域ごとに分類します。Geo データモードが有効な場合に GEOIP ルールで使用し、無効な場合は MMDB を使用します。",
    ),
    "geoResourceGeositeAbout": MessageLookupByLibrary.simpleMessage(
      "ドメイン名をサービスや地域などのカテゴリに分類します。GEOSITE ルールと、この分類に対応する DNS 設定でドメインを照合します。",
    ),
    "geoResourceMmdbAbout": MessageLookupByLibrary.simpleMessage(
      "IP アドレスから国・地域コードを調べ、GEOIP ルールや一部の DNS 判定で使用します。Geo データモードが無効のときに使われます。FlClash では MaxMind DB 形式の国・地域データベースを指します。",
    ),
    "geoResources": MessageLookupByLibrary.simpleMessage("Geoリソース"),
    "geoSkipped": m19,
    "geoUpdated": m20,
    "geodataLoader": MessageLookupByLibrary.simpleMessage("Geo低メモリモード"),
    "global": MessageLookupByLibrary.simpleMessage("グローバル"),
    "go": MessageLookupByLibrary.simpleMessage("開く"),
    "goDownload": MessageLookupByLibrary.simpleMessage("ダウンロードへ"),
    "goToConfigureScript": MessageLookupByLibrary.simpleMessage("スクリプト設定へ移動"),
    "hasCacheChange": MessageLookupByLibrary.simpleMessage("変更をキャッシュしますか？"),
    "helperCorruptTip": MessageLookupByLibrary.simpleMessage(
      "Helper サービスが利用できないため、TUN モードを有効にできません。FlClash を再インストールしてください。",
    ),
    "hideFromList": MessageLookupByLibrary.simpleMessage("リストから隠す"),
    "hideIp": MessageLookupByLibrary.simpleMessage("IP を隠す"),
    "hidePassword": MessageLookupByLibrary.simpleMessage("パスワードを隠す"),
    "hideTimeoutProxies": MessageLookupByLibrary.simpleMessage(
      "タイムアウトしたノードを隠す",
    ),
    "hideTimeoutProxiesDesc": MessageLookupByLibrary.simpleMessage(
      "前回の遅延テストがタイムアウトしたノードを表示しない",
    ),
    "host": MessageLookupByLibrary.simpleMessage("ホスト"),
    "hotkeyConflictWith": m21,
    "hotkeyDesc": MessageLookupByLibrary.simpleMessage(
      "グローバルホットキーはウィンドウが非表示でも有効です。アクションをタップしてキーの組み合わせを記録します。",
    ),
    "hotkeyManagement": MessageLookupByLibrary.simpleMessage("ホットキー管理"),
    "hotkeyNeedsModifier": m22,
    "hotkeyNotSet": MessageLookupByLibrary.simpleMessage("未設定"),
    "hotkeyUnavailable": MessageLookupByLibrary.simpleMessage(
      "登録できませんでした。他のアプリが使用している可能性があります",
    ),
    "hours": MessageLookupByLibrary.simpleMessage("時間"),
    "hoursAgo": m23,
    "hoursCount": m24,
    "icon": MessageLookupByLibrary.simpleMessage("アイコン"),
    "iconRecords": MessageLookupByLibrary.simpleMessage("アイコン履歴"),
    "iconStyle": MessageLookupByLibrary.simpleMessage("アイコンスタイル"),
    "iconStyleFilled": MessageLookupByLibrary.simpleMessage("背景あり"),
    "iconStyleHidden": MessageLookupByLibrary.simpleMessage("非表示"),
    "iconStylePlain": MessageLookupByLibrary.simpleMessage("背景なし"),
    "iconUrl": MessageLookupByLibrary.simpleMessage("アイコンURL"),
    "ignoreBatteryOptimization": MessageLookupByLibrary.simpleMessage(
      "電池の最適化を無視",
    ),
    "import": MessageLookupByLibrary.simpleMessage("インポート"),
    "importFile": MessageLookupByLibrary.simpleMessage("ファイルからインポート"),
    "importFromURL": MessageLookupByLibrary.simpleMessage("URLからインポート"),
    "importUrl": MessageLookupByLibrary.simpleMessage("URLからインポート"),
    "inbound": MessageLookupByLibrary.simpleMessage("インバウンド"),
    "includeAllProxies": MessageLookupByLibrary.simpleMessage("すべてのプロキシを含める"),
    "includeAllProxiesTip": MessageLookupByLibrary.simpleMessage(
      "プロキシグループに属さないすべてのプロキシを取り込みます。下でプロキシグループを追加できます",
    ),
    "includeAllProxyProviders": MessageLookupByLibrary.simpleMessage(
      "すべてのプロキシプロバイダーを含める",
    ),
    "includeAllProxyProvidersTip": MessageLookupByLibrary.simpleMessage(
      "有効にすると、このプロファイルのすべてのプロキシプロバイダーを含めます。サブスクリプション自身のものに加え、いずれかのプロキシグループが使うプロファイルとアプリのプロキシプロバイダーも含みます",
    ),
    "infiniteTime": MessageLookupByLibrary.simpleMessage("無期限"),
    "init": MessageLookupByLibrary.simpleMessage("初期化"),
    "initiator": MessageLookupByLibrary.simpleMessage("発信元"),
    "inputProxyGroupName": MessageLookupByLibrary.simpleMessage(
      "プロキシグループ名を入力してください",
    ),
    "inputRuleContent": MessageLookupByLibrary.simpleMessage("ルールの内容を入力してください"),
    "installedAppsPermissionDeniedMessage":
        MessageLookupByLibrary.simpleMessage(
          "アプリ一覧の権限が拒否されたため、インストール済みアプリを取得できません。システム設定から手動で許可してください。",
        ),
    "installedAppsPermissionDesc": MessageLookupByLibrary.simpleMessage(
      "このシステムでは、許可するまでインストール済みアプリの一覧が提供されません。許可すると、アプリごとのプロキシを設定できます。",
    ),
    "installedAppsPermissionRequired": MessageLookupByLibrary.simpleMessage(
      "アプリ一覧の権限が必要です",
    ),
    "intelligentSelected": MessageLookupByLibrary.simpleMessage("スマート選択"),
    "interfaceName": MessageLookupByLibrary.simpleMessage("インターフェース名"),
    "interfaceNameDesc": MessageLookupByLibrary.simpleMessage(
      "アウトバウンド接続に使用するネットワークインターフェース名",
    ),
    "interfaceNameMode": MessageLookupByLibrary.simpleMessage(
      "アウトバウンドインターフェース",
    ),
    "interfaceNameModeClear": MessageLookupByLibrary.simpleMessage("クリア"),
    "interfaceNameModeCustom": MessageLookupByLibrary.simpleMessage("カスタム"),
    "interfaceNameModeFollow": MessageLookupByLibrary.simpleMessage("設定に従う"),
    "internet": MessageLookupByLibrary.simpleMessage("インターネット"),
    "interval": MessageLookupByLibrary.simpleMessage("間隔"),
    "intranetIP": MessageLookupByLibrary.simpleMessage("イントラネットIP"),
    "invalidBackupFile": MessageLookupByLibrary.simpleMessage("無効なバックアップファイル"),
    "invalidDscpContent": MessageLookupByLibrary.simpleMessage(
      "DSCP マークは 63 を超えられません",
    ),
    "invalidNetworkContent": MessageLookupByLibrary.simpleMessage(
      "tcp または udp のみ対応しています",
    ),
    "invalidPolicy": m25,
    "invalidProfileQrcode": MessageLookupByLibrary.simpleMessage(
      "このQRコードにはプロファイルのリンクが含まれていません",
    ),
    "invalidProxy": m26,
    "invalidProxyProvider": m27,
    "invalidRangeContent": MessageLookupByLibrary.simpleMessage(
      "80 や 8000-9000 のような数値または範囲を / 区切りで入力してください",
    ),
    "invalidRuleSet": m28,
    "invalidSubRule": m29,
    "ipAddress": MessageLookupByLibrary.simpleMessage("IP アドレス"),
    "ipAsn": MessageLookupByLibrary.simpleMessage("ASN"),
    "ipClassificationDisclosure": MessageLookupByLibrary.simpleMessage(
      "このボタンは表示 IP を HTTPS で proxycheck.io に送り分類します。取得元にはリクエストの出口 IP も見え、表示 IP と異なる場合があります。匿名利用は 1 日 100 回までで、プロキシ経由は拒否される場合があります。拒否時に直結や別の取得元へ変更しません。欠落は不明で、安全性を保証しません。任意の陽性検出ダッシュボード保存を無効にしますが、全サーバーログの停止を保証しません。",
    ),
    "ipClassificationStart": MessageLookupByLibrary.simpleMessage("この IP を分類"),
    "ipFlagAnonymous": MessageLookupByLibrary.simpleMessage("匿名サービス検出"),
    "ipFlagCompromised": MessageLookupByLibrary.simpleMessage("侵害されたホスト"),
    "ipFlagHosting": MessageLookupByLibrary.simpleMessage("ホスティング検出"),
    "ipFlagProxy": MessageLookupByLibrary.simpleMessage("プロキシ"),
    "ipFlagScraper": MessageLookupByLibrary.simpleMessage("スクレイピング検出"),
    "ipFlagTor": MessageLookupByLibrary.simpleMessage("Tor"),
    "ipFlagVpn": MessageLookupByLibrary.simpleMessage("VPN"),
    "ipFlags": MessageLookupByLibrary.simpleMessage("検出"),
    "ipLookupAutomatic": MessageLookupByLibrary.simpleMessage("ダッシュボードで自動確認"),
    "ipLookupBodyLimit": MessageLookupByLibrary.simpleMessage("応答が大きすぎます"),
    "ipLookupCancelled": MessageLookupByLibrary.simpleMessage("確認をキャンセル"),
    "ipLookupCheckedAt": MessageLookupByLibrary.simpleMessage("確認日時"),
    "ipLookupDisclosure": MessageLookupByLibrary.simpleMessage(
      "HTTPS で Cloudflare にリクエストの出口 IP と国を確認します。自動確認はアプリが前面でダッシュボードを表示し、サービスが動作している間だけ行います。結果は他のサイトの出口を保証しません。",
    ),
    "ipLookupDisplayOnly": MessageLookupByLibrary.simpleMessage(
      "表示のみを隠します。コピーは元の IP を使用し、通信は停止しません。",
    ),
    "ipLookupHttpFailed": MessageLookupByLibrary.simpleMessage("取得元がリクエストを拒否"),
    "ipLookupInvalid": MessageLookupByLibrary.simpleMessage("無効または不完全な応答"),
    "ipLookupIpMismatch": MessageLookupByLibrary.simpleMessage("応答 IP が一致しません"),
    "ipLookupManual": MessageLookupByLibrary.simpleMessage("出口 IP を確認"),
    "ipLookupNotChecked": MessageLookupByLibrary.simpleMessage("未確認"),
    "ipLookupRoutes": MessageLookupByLibrary.simpleMessage("現在のルール"),
    "ipLookupSourceWarning": MessageLookupByLibrary.simpleMessage(
      "取得元の警告：結果は返されましたが、割当量やアクセス制限に注意してください。",
    ),
    "ipLookupStale": MessageLookupByLibrary.simpleMessage("過去の結果"),
    "ipLookupTlsFailed": MessageLookupByLibrary.simpleMessage("証明書の検証に失敗"),
    "ipLookupWaiting": MessageLookupByLibrary.simpleMessage("30 秒の間隔を待機中"),
    "ipOrganization": MessageLookupByLibrary.simpleMessage("組織"),
    "ipQualityFailed": MessageLookupByLibrary.simpleMessage(
      "IP タイプを判定できませんでした",
    ),
    "ipQualityRetry": MessageLookupByLibrary.simpleMessage("再確認"),
    "ipQualitySource": MessageLookupByLibrary.simpleMessage("採用したソース"),
    "ipQualitySources": MessageLookupByLibrary.simpleMessage("各ソース"),
    "ipSourceIpMismatch": MessageLookupByLibrary.simpleMessage(
      "アウトバウンド IP が不一致",
    ),
    "ipSourceNoType": MessageLookupByLibrary.simpleMessage("判定不可"),
    "ipSourceRateLimited": MessageLookupByLibrary.simpleMessage("レート制限"),
    "ipType": MessageLookupByLibrary.simpleMessage("タイプ"),
    "ipTypeBusiness": MessageLookupByLibrary.simpleMessage("ビジネス"),
    "ipTypeHosting": MessageLookupByLibrary.simpleMessage("データセンター"),
    "ipTypeResidential": MessageLookupByLibrary.simpleMessage("住宅"),
    "ipTypeWireless": MessageLookupByLibrary.simpleMessage("無線（携帯回線・衛星）"),
    "ipv6Desc": MessageLookupByLibrary.simpleMessage(
      "有効にすると、IPv6トラフィックを受信できます",
    ),
    "ipv6InboundDesc": MessageLookupByLibrary.simpleMessage("IPv6インバウンドを許可します"),
    "ipv6Timeout": MessageLookupByLibrary.simpleMessage("IPv6タイムアウト（ms）"),
    "ja": MessageLookupByLibrary.simpleMessage("日本語"),
    "justNow": MessageLookupByLibrary.simpleMessage("たった今"),
    "keepAliveIntervalDesc": MessageLookupByLibrary.simpleMessage(
      "TCPキープアライブ間隔",
    ),
    "key": MessageLookupByLibrary.simpleMessage("キー"),
    "language": MessageLookupByLibrary.simpleMessage("言語"),
    "large": MessageLookupByLibrary.simpleMessage("大"),
    "lastUpdated": MessageLookupByLibrary.simpleMessage("最終更新"),
    "launchInterrupted": MessageLookupByLibrary.simpleMessage("起動が完了しませんでした"),
    "launchInterruptedTip": MessageLookupByLibrary.simpleMessage(
      "前回の起動は完了していません。原因は不明です。今回は自動設定をスキップします。選択とファイルは保持され、手動で開始できます。",
    ),
    "layout": MessageLookupByLibrary.simpleMessage("レイアウト"),
    "light": MessageLookupByLibrary.simpleMessage("ライト"),
    "lineIssueTip": m30,
    "lineWrap": MessageLookupByLibrary.simpleMessage("折り返し"),
    "list": MessageLookupByLibrary.simpleMessage("リスト"),
    "listen": MessageLookupByLibrary.simpleMessage("リッスン"),
    "listenRoutingMark": MessageLookupByLibrary.simpleMessage("リッスンのルーティングマーク"),
    "listenRoutingMarkDesc": MessageLookupByLibrary.simpleMessage("Linuxのみ"),
    "liveConnections": MessageLookupByLibrary.simpleMessage("リアルタイム接続"),
    "loading": MessageLookupByLibrary.simpleMessage("読み込み中…"),
    "local": MessageLookupByLibrary.simpleMessage("ローカル"),
    "localCrashReports": MessageLookupByLibrary.simpleMessage("ローカル障害レポート"),
    "localGroupsActions": m31,
    "localGroupsActualExit": m32,
    "localGroupsAmbiguous": MessageLookupByLibrary.simpleMessage(
      "選択したノード名が複数のソースに存在します。識別できる名前のノードを選択してください。",
    ),
    "localGroupsApplyFailed": MessageLookupByLibrary.simpleMessage(
      "変更を適用できませんでした。設定を確認して再試行してください。",
    ),
    "localGroupsApplying": MessageLookupByLibrary.simpleMessage("設定を適用中…"),
    "localGroupsAutomatic": MessageLookupByLibrary.simpleMessage("遅延優先"),
    "localGroupsChanged": MessageLookupByLibrary.simpleMessage(
      "設定が変更されました。グループ管理を更新して再試行してください。",
    ),
    "localGroupsCreate": MessageLookupByLibrary.simpleMessage("新規グループ"),
    "localGroupsDelete": m33,
    "localGroupsDisable": MessageLookupByLibrary.simpleMessage("無効にする"),
    "localGroupsDownloading": MessageLookupByLibrary.simpleMessage(
      "ソースの更新をダウンロード中…",
    ),
    "localGroupsEmpty": MessageLookupByLibrary.simpleMessage(
      "このサブスクリプションのノードからグループを作成します。",
    ),
    "localGroupsEnable": MessageLookupByLibrary.simpleMessage("有効にする"),
    "localGroupsEnableSpeedTest": MessageLookupByLibrary.simpleMessage(
      "速度テストを有効にする",
    ),
    "localGroupsFallback": MessageLookupByLibrary.simpleMessage("フェイルオーバー"),
    "localGroupsForegroundRequired": MessageLookupByLibrary.simpleMessage(
      "この変更には設定全体の再適用が必要です。アプリを開いて再試行してください。",
    ),
    "localGroupsIdentitySection": MessageLookupByLibrary.simpleMessage("基本情報"),
    "localGroupsInUse": MessageLookupByLibrary.simpleMessage(
      "参照の解除、無効化、削除の前に、別のノードまたはグループを選択してください。",
    ),
    "localGroupsIndependent": MessageLookupByLibrary.simpleMessage("独立グループ"),
    "localGroupsInvalidParent": MessageLookupByLibrary.simpleMessage(
      "利用可能な手動グループまたは独立グループを選択してください。",
    ),
    "localGroupsInvalidTestUrl": MessageLookupByLibrary.simpleMessage(
      "有効なHTTP(S)テストURLを入力してください。",
    ),
    "localGroupsLimit": MessageLookupByLibrary.simpleMessage(
      "グループ数またはメンバー数が上限を超えています。",
    ),
    "localGroupsLoadFirst": MessageLookupByLibrary.simpleMessage(
      "このサブスクリプションを使用し、ソースの確認を完了してノードを読み込んでください。",
    ),
    "localGroupsManaged": MessageLookupByLibrary.simpleMessage(
      "この設定のグループはポリシー草案で管理してください。",
    ),
    "localGroupsManual": MessageLookupByLibrary.simpleMessage("手動"),
    "localGroupsMembersRequired": MessageLookupByLibrary.simpleMessage(
      "利用可能なノードを1つ以上選択してください。",
    ),
    "localGroupsMissing": m34,
    "localGroupsNameConflict": MessageLookupByLibrary.simpleMessage(
      "他のノードやグループと重複しない名前を指定してください。",
    ),
    "localGroupsNoEntrance": MessageLookupByLibrary.simpleMessage(
      "この設定に選択可能なルーティング入口はありません。",
    ),
    "localGroupsNoSaved": MessageLookupByLibrary.simpleMessage(
      "カスタムグループがありません。グループ管理で作成してください。",
    ),
    "localGroupsNodeCount": m35,
    "localGroupsNodesSection": MessageLookupByLibrary.simpleMessage("ノード"),
    "localGroupsOwn": MessageLookupByLibrary.simpleMessage("カスタム"),
    "localGroupsParent": MessageLookupByLibrary.simpleMessage("選択肢を追加するグループ"),
    "localGroupsPending": MessageLookupByLibrary.simpleMessage(
      "変更を保存しました。適用待ちです。",
    ),
    "localGroupsPreferred": m36,
    "localGroupsPreparing": MessageLookupByLibrary.simpleMessage("保存した設定を確認中…"),
    "localGroupsPreparingSources": MessageLookupByLibrary.simpleMessage(
      "保存したソースを検証中…",
    ),
    "localGroupsReferenceAdded": MessageLookupByLibrary.simpleMessage(
      "選択肢に追加済み",
    ),
    "localGroupsReferenceNotAdded": MessageLookupByLibrary.simpleMessage("未追加"),
    "localGroupsReferenceUsing": MessageLookupByLibrary.simpleMessage("現在使用中"),
    "localGroupsReferences": m37,
    "localGroupsReferencesSaved": MessageLookupByLibrary.simpleMessage(
      "参照を適用しました。現在の選択は保持されています。",
    ),
    "localGroupsRegex": MessageLookupByLibrary.simpleMessage("ノードの正規表現（任意）"),
    "localGroupsRegexDocs": MessageLookupByLibrary.simpleMessage("正規表現のヘルプ"),
    "localGroupsRegexHelp": MessageLookupByLibrary.simpleMessage(
      "一致したノードは選択済みです。タップで変更できます。",
    ),
    "localGroupsRouteThis": MessageLookupByLibrary.simpleMessage("グループの参照を管理"),
    "localGroupsSaving": MessageLookupByLibrary.simpleMessage("グループを確認して保存中…"),
    "localGroupsScope": m38,
    "localGroupsSearch": MessageLookupByLibrary.simpleMessage("ノードを検索"),
    "localGroupsSelectNodeHelp": MessageLookupByLibrary.simpleMessage(
      "ノードをタップするとすぐに切り替わります。保存は不要です。",
    ),
    "localGroupsSource": MessageLookupByLibrary.simpleMessage(
      "サブスクリプショングループ（読み取り専用）",
    ),
    "localGroupsSourceUnavailable": MessageLookupByLibrary.simpleMessage(
      "承認済みの設定または権限を利用できません。プロファイルでソース権限を確認してください。",
    ),
    "localGroupsStrategyHelp": MessageLookupByLibrary.simpleMessage(
      "オン：遅延で選択。オフ：Core の順序でフェイルオーバー。どちらも可用性を自動確認します。",
    ),
    "localGroupsStrategySection": MessageLookupByLibrary.simpleMessage(
      "切り替え方式",
    ),
    "localGroupsSubscription": MessageLookupByLibrary.simpleMessage("購読"),
    "localGroupsTitle": MessageLookupByLibrary.simpleMessage("グループ管理"),
    "localGroupsTransientHelp": MessageLookupByLibrary.simpleMessage(
      "タップで今回の接続に使用します。障害時は自動切替し、この選択は保存しません。",
    ),
    "localGroupsUnavailable": MessageLookupByLibrary.simpleMessage(
      "このグループは未稼働です。有効化するか、設定の準備をお待ちください。",
    ),
    "localGroupsUse": MessageLookupByLibrary.simpleMessage("グループの参照を管理"),
    "localGroupsUseHelp": MessageLookupByLibrary.simpleMessage(
      "このカスタムグループを追加する対象を選びます。保存すると参照が適用され、現在の選択は保持されます。",
    ),
    "localNetworkDeniedTip": MessageLookupByLibrary.simpleMessage(
      "ローカルネットワークの権限が拒否されたため gvisor スタックを使用します。LAN にはアクセスできません。",
    ),
    "locationPermission": MessageLookupByLibrary.simpleMessage("位置情報の権限"),
    "locationPermissionDeniedMessage": MessageLookupByLibrary.simpleMessage(
      "位置情報の権限が拒否されたため、現在の Wi-Fi 名を取得できません。システム設定で位置情報の権限を手動で有効にしてください。",
    ),
    "locationPermissionDesc": MessageLookupByLibrary.simpleMessage(
      "システムの要件により、Wi-Fi 名の取得には位置情報の権限が必要です。Android では「常に許可」を選択してください。そうしないと、アプリがバックグラウンドにあるときに Wi-Fi 名を取得できません。",
    ),
    "locationPermissionGuide": m39,
    "locationPermissionRequired": MessageLookupByLibrary.simpleMessage(
      "位置情報の権限が必要です",
    ),
    "log": MessageLookupByLibrary.simpleMessage("ログ"),
    "logLevel": MessageLookupByLibrary.simpleMessage("ログレベル"),
    "logcat": MessageLookupByLibrary.simpleMessage("ログキャプチャ"),
    "logcatDesc": MessageLookupByLibrary.simpleMessage("無効にするとログの入り口が非表示になります"),
    "logs": MessageLookupByLibrary.simpleMessage("ログ"),
    "logsAndDiagnostics": MessageLookupByLibrary.simpleMessage("ログと診断"),
    "logsTest": MessageLookupByLibrary.simpleMessage("ログテスト"),
    "loopback": MessageLookupByLibrary.simpleMessage("UWP ループバック解除"),
    "loose": MessageLookupByLibrary.simpleMessage("ゆったり"),
    "matchSourceIp": MessageLookupByLibrary.simpleMessage("送信元IPにマッチ"),
    "matchTarget": MessageLookupByLibrary.simpleMessage("MATCH-TARGET"),
    "maxFailedTimes": MessageLookupByLibrary.simpleMessage("最大失敗回数"),
    "maxLengthTip": m40,
    "maximize": MessageLookupByLibrary.simpleMessage("最大化"),
    "memoryAppResident": MessageLookupByLibrary.simpleMessage("常駐メモリ"),
    "memoryAppShared": MessageLookupByLibrary.simpleMessage("アプリと共有"),
    "memoryCoreHeapIdle": MessageLookupByLibrary.simpleMessage("未使用のヒープ"),
    "memoryCoreHeapInuse": MessageLookupByLibrary.simpleMessage("使用中のヒープ"),
    "memoryCoreNotRunning": MessageLookupByLibrary.simpleMessage(
      "コアは実行されていません",
    ),
    "memoryCoreRuntime": MessageLookupByLibrary.simpleMessage("ランタイムのオーバーヘッド"),
    "memoryCoreStack": MessageLookupByLibrary.simpleMessage("ゴルーチンスタック"),
    "memoryEstimateDesc": MessageLookupByLibrary.simpleMessage(
      "プロセスの常駐メモリからの推定値で、システムの表示とは異なる場合があります。",
    ),
    "memoryEstimateSharedDesc": MessageLookupByLibrary.simpleMessage(
      "コアはアプリと同じプロセスで動作します。コア分はランタイム統計から推定し、残りはアプリと共有メモリとして計上します。",
    ),
    "memoryInfo": MessageLookupByLibrary.simpleMessage("メモリ情報"),
    "memoryReleased": MessageLookupByLibrary.simpleMessage("メモリを解放しました"),
    "memoryReleasedSize": m41,
    "messageTest": MessageLookupByLibrary.simpleMessage("メッセージテスト"),
    "messageTestTip": MessageLookupByLibrary.simpleMessage("これはメッセージです。"),
    "min": MessageLookupByLibrary.simpleMessage("最小"),
    "minimize": MessageLookupByLibrary.simpleMessage("最小化"),
    "minimizeOnExit": MessageLookupByLibrary.simpleMessage("終了時に最小化"),
    "minutesAgo": m42,
    "mixedPort": MessageLookupByLibrary.simpleMessage("Mixedポート"),
    "mode": MessageLookupByLibrary.simpleMessage("モード"),
    "monochromeScheme": MessageLookupByLibrary.simpleMessage("モノクローム"),
    "monthsAgo": m43,
    "more": MessageLookupByLibrary.simpleMessage("その他"),
    "name": MessageLookupByLibrary.simpleMessage("名前"),
    "navigationBarStyle": MessageLookupByLibrary.simpleMessage("ボトムバー"),
    "network": MessageLookupByLibrary.simpleMessage("ネットワーク"),
    "networkAccessDeniedError": m44,
    "networkBadResponseError": m45,
    "networkCancelledError": MessageLookupByLibrary.simpleMessage(
      "リクエストはキャンセルされました",
    ),
    "networkConnectionError": MessageLookupByLibrary.simpleMessage(
      "サーバーに接続できませんでした。ネットワーク接続またはプロキシ設定を確認してください",
    ),
    "networkDetection": MessageLookupByLibrary.simpleMessage("ネットワーク検出"),
    "networkHostLookupError": MessageLookupByLibrary.simpleMessage(
      "サーバーのアドレスを解決できませんでした。URL が正しいこと、DNS が使えることを確認してください",
    ),
    "networkNotFoundError": m46,
    "networkRateLimitedError": MessageLookupByLibrary.simpleMessage(
      "リクエストが多すぎます（HTTP 429）。しばらく待ってから再試行してください",
    ),
    "networkRequestFailed": m47,
    "networkServerError": m48,
    "networkSpeed": MessageLookupByLibrary.simpleMessage("ネットワーク速度"),
    "networkTimeoutError": MessageLookupByLibrary.simpleMessage(
      "リクエストがタイムアウトしました。ネットワークまたはプロキシを確認してから再試行してください",
    ),
    "networkTlsError": MessageLookupByLibrary.simpleMessage(
      "安全な接続に失敗しました。サーバー証明書が無効か、接続が傍受されている可能性があります",
    ),
    "networkType": MessageLookupByLibrary.simpleMessage("ネットワーク種別"),
    "neutralScheme": MessageLookupByLibrary.simpleMessage("ニュートラル"),
    "nextMatch": MessageLookupByLibrary.simpleMessage("次の一致"),
    "no": MessageLookupByLibrary.simpleMessage("いいえ"),
    "noData": MessageLookupByLibrary.simpleMessage("データがありません"),
    "noInfo": MessageLookupByLibrary.simpleMessage("情報がありません"),
    "noNetwork": MessageLookupByLibrary.simpleMessage("ネットワークがありません"),
    "noNetworkApp": MessageLookupByLibrary.simpleMessage("ネットワーク不使用アプリ"),
    "noRecords": MessageLookupByLibrary.simpleMessage("記録がありません"),
    "noResolve": MessageLookupByLibrary.simpleMessage("IPを解決しない"),
    "noResolveHostname": MessageLookupByLibrary.simpleMessage("ホスト名を解決しない"),
    "noSearchResults": MessageLookupByLibrary.simpleMessage("一致する結果はありません"),
    "nonTextProviderFile": MessageLookupByLibrary.simpleMessage(
      "この外部リソースはテキストファイルではありません",
    ),
    "none": MessageLookupByLibrary.simpleMessage("なし"),
    "notSelectedTip": MessageLookupByLibrary.simpleMessage(
      "現在のプロキシグループは選択できません",
    ),
    "ntpInterval": MessageLookupByLibrary.simpleMessage("同期間隔（分）"),
    "ntpStatusDesc": MessageLookupByLibrary.simpleMessage(
      "システムクロックではなくNTPサーバーから時刻を取得します",
    ),
    "nullProfileDesc": MessageLookupByLibrary.simpleMessage(
      "プロファイルを追加して始めましょう",
    ),
    "nullTip": m49,
    "numberTip": m50,
    "officialDocumentation": MessageLookupByLibrary.simpleMessage("公式ドキュメント"),
    "onDemand": MessageLookupByLibrary.simpleMessage("オンデマンド"),
    "onDemandDesc": MessageLookupByLibrary.simpleMessage(
      "特定のシナリオでのアプリの実行状態を設定します",
    ),
    "onlyStatisticsProxy": MessageLookupByLibrary.simpleMessage(
      "プロキシトラフィックのみ集計",
    ),
    "optional": MessageLookupByLibrary.simpleMessage("任意"),
    "options": MessageLookupByLibrary.simpleMessage("オプション"),
    "other": MessageLookupByLibrary.simpleMessage("その他"),
    "otherContributors": MessageLookupByLibrary.simpleMessage("その他の貢献者"),
    "outboundIp": MessageLookupByLibrary.simpleMessage("アウトバウンド IP"),
    "outboundMode": MessageLookupByLibrary.simpleMessage("アウトバウンドモード"),
    "override": MessageLookupByLibrary.simpleMessage("上書き"),
    "overrideDns": MessageLookupByLibrary.simpleMessage("DNSを上書き"),
    "overrideEntries": MessageLookupByLibrary.simpleMessage("上書き項目"),
    "overrideMode": MessageLookupByLibrary.simpleMessage("上書きモード"),
    "overrideNtp": MessageLookupByLibrary.simpleMessage("NTPを上書き"),
    "overrideScript": MessageLookupByLibrary.simpleMessage("上書きスクリプト"),
    "overwriteIssueCoreRejected": m51,
    "overwriteIssueDuplicateName": m52,
    "overwriteIssueEmptyName": MessageLookupByLibrary.simpleMessage("名前が空です"),
    "overwriteIssueGroupLoop": m53,
    "overwriteIssueMissingProviders": m54,
    "overwriteIssueMissingProxies": m55,
    "overwriteIssueNoProxySource": MessageLookupByLibrary.simpleMessage(
      "プロキシもプロキシプロバイダーも選択されていないため、コアはこのグループを拒否します",
    ),
    "overwriteIssueReservedName": m56,
    "overwriteIssueSubscriptionGroupMissingProxies": m57,
    "overwriteIssuesSummary": m58,
    "overwriteTypeCustom": MessageLookupByLibrary.simpleMessage("カスタム"),
    "overwriteTypeCustomDesc": MessageLookupByLibrary.simpleMessage(
      "カスタムモード：プロキシ、プロキシグループ、ルールを完全にカスタマイズできます",
    ),
    "palette": MessageLookupByLibrary.simpleMessage("パレット"),
    "password": MessageLookupByLibrary.simpleMessage("パスワード"),
    "paste": MessageLookupByLibrary.simpleMessage("貼り付け"),
    "pickFromAlbum": MessageLookupByLibrary.simpleMessage("アルバムから選択"),
    "pinWindow": MessageLookupByLibrary.simpleMessage("最前面に固定"),
    "pleaseBindWebDAV": MessageLookupByLibrary.simpleMessage("WebDAVを連携してください"),
    "pleaseEnterScriptName": MessageLookupByLibrary.simpleMessage(
      "スクリプト名を入力してください",
    ),
    "pleaseUploadValidQrcode": MessageLookupByLibrary.simpleMessage(
      "有効なQRコードをアップロードしてください",
    ),
    "policyActualPreview": MessageLookupByLibrary.simpleMessage("実際に受理された構成"),
    "policyAndroidRequired": MessageLookupByLibrary.simpleMessage(
      "管理ポリシーの適用は現在 Android のみ対応しています。下書きの編集とプレビューは引き続き利用できます。",
    ),
    "policyApply": MessageLookupByLibrary.simpleMessage("保存して適用を要求"),
    "policyApplyConfirm": MessageLookupByLibrary.simpleMessage(
      "明示的な DIRECT を含め、このポリシーでルーティングと DNS を処理します。元のルール、DNS、プロバイダー、特殊な上書きは使用しません。管理対象のノード選択はリセットされます。停止中のプロキシは起動しません。",
    ),
    "policyApplyRequested": MessageLookupByLibrary.simpleMessage(
      "選択を保存して適用を要求しました。実際の構成状態を確認してください。",
    ),
    "policyDraftAuthentication": MessageLookupByLibrary.simpleMessage(
      "ユーザー名とパスワードを使用",
    ),
    "policyDraftBackupConsent": MessageLookupByLibrary.simpleMessage(
      "このバックアップには下書き、認証情報、元の移行資料が含まれる場合があります。改めて確認してから出力してください。",
    ),
    "policyDraftBackupLocal": MessageLookupByLibrary.simpleMessage(
      "選択したローカルファイルへ、下書き・認証情報・移行資料を含む暗号化されていないZIPを保存します。続行しますか？",
    ),
    "policyDraftBackupWebDav": MessageLookupByLibrary.simpleMessage(
      "選択したWebDAVサービスへ、下書き・認証情報・移行資料を含む暗号化されていないZIPを送信します。続行しますか？",
    ),
    "policyDraftBootstrap": MessageLookupByLibrary.simpleMessage(
      "起動用DNS（DIRECT）",
    ),
    "policyDraftConflict": MessageLookupByLibrary.simpleMessage(
      "保存済みの下書きが変更されました。入力は保持されています。再読み込みしてください。",
    ),
    "policyDraftCopyFull": MessageLookupByLibrary.simpleMessage("生成設定をすべてコピー"),
    "policyDraftCopyFullConfirm": MessageLookupByLibrary.simpleMessage(
      "ユーザー名やパスワードを含む生成設定全体をクリップボードへコピーしますか？",
    ),
    "policyDraftDeleted": MessageLookupByLibrary.simpleMessage(
      "ポリシーの下書きを削除しました",
    ),
    "policyDraftDirectWarning": MessageLookupByLibrary.simpleMessage(
      "ドメインの既定値DIRECTは未一致ドメインのDNSも選択したDNSサービスへ直接送信します。",
    ),
    "policyDraftDiscard": MessageLookupByLibrary.simpleMessage(
      "未保存の変更を破棄しますか？",
    ),
    "policyDraftDnsServices": MessageLookupByLibrary.simpleMessage("DNSサービス"),
    "policyDraftDomainDefault": MessageLookupByLibrary.simpleMessage(
      "未一致ドメインの既定ポリシー",
    ),
    "policyDraftDomainRules": MessageLookupByLibrary.simpleMessage("ドメインルール"),
    "policyDraftExtract": MessageLookupByLibrary.simpleMessage("保存済み設定から抽出"),
    "policyDraftExtractConfirm": MessageLookupByLibrary.simpleMessage(
      "ローカルの保存済み資料から抽出した下書きで編集内容を置き換えますか？スクリプトは実行せず、未対応ルールは移行を阻止します。設定は適用されません。",
    ),
    "policyDraftExtractFailed": MessageLookupByLibrary.simpleMessage(
      "保存済みのローカル資料を抽出できませんでした。下書きは変更されていません。",
    ),
    "policyDraftGeneratePreview": MessageLookupByLibrary.simpleMessage(
      "生成した下書きのプレビュー",
    ),
    "policyDraftGroups": MessageLookupByLibrary.simpleMessage("静的プロキシグループ"),
    "policyDraftIncomplete": m59,
    "policyDraftIpDefault": MessageLookupByLibrary.simpleMessage(
      "未一致IPの既定ポリシー",
    ),
    "policyDraftIpRules": MessageLookupByLibrary.simpleMessage("IPルール"),
    "policyDraftListeners": MessageLookupByLibrary.simpleMessage("プレビューの待受ポート"),
    "policyDraftLoadFailed": MessageLookupByLibrary.simpleMessage(
      "下書きを読み込めませんでした。再読み込みしてください。",
    ),
    "policyDraftMembers": MessageLookupByLibrary.simpleMessage("固定ノードを選択"),
    "policyDraftMigration": MessageLookupByLibrary.simpleMessage("過去の移行資料"),
    "policyDraftMigrationBlocked": MessageLookupByLibrary.simpleMessage(
      "移行は保留中です。元の資料とルール位置は保持されています。抽出行や既定値の変更では解除できません。",
    ),
    "policyDraftMigrationChoices": MessageLookupByLibrary.simpleMessage(
      "抽出行は候補です。両方の既定値、DNS、起動用DNSを明示的に選んでください。元のプロファイル・上書き・グローバルDNSは従来の設定経路を使用し、このプレビューは動作中の設定ではありません。",
    ),
    "policyDraftMigrationIp": MessageLookupByLibrary.simpleMessage(
      "宛先IPルールはドメイン接続も制限する場合があり、分離では保護を維持できません。",
    ),
    "policyDraftMigrationMatch": MessageLookupByLibrary.simpleMessage(
      "後続ルールより前にMATCHがあります。末尾の既定値には置き換えられません。",
    ),
    "policyDraftMigrationScript": MessageLookupByLibrary.simpleMessage(
      "抽出時にスクリプトを実行しないため、出力は不明です。",
    ),
    "policyDraftMigrationUnsupported": MessageLookupByLibrary.simpleMessage(
      "このルール・リソース・設定は移行の対応範囲外です。",
    ),
    "policyDraftMissing": MessageLookupByLibrary.simpleMessage(
      "このプロファイルは存在しません。入力内容は保存されていません。",
    ),
    "policyDraftMoveDown": MessageLookupByLibrary.simpleMessage("下へ"),
    "policyDraftMoveUp": MessageLookupByLibrary.simpleMessage("上へ"),
    "policyDraftNeedsPreview": MessageLookupByLibrary.simpleMessage(
      "入力は生成プレビューでの検証が必要です",
    ),
    "policyDraftNodes": MessageLookupByLibrary.simpleMessage("固定SOCKS5ノード"),
    "policyDraftProtocol": MessageLookupByLibrary.simpleMessage("プロトコル"),
    "policyDraftReadOnly": MessageLookupByLibrary.simpleMessage(
      "不明なバージョンまたは未対応の構造です。元の内容は保持され、編集・プレビューはできません。",
    ),
    "policyDraftReady": MessageLookupByLibrary.simpleMessage(
      "下書きのプレビューを検証済み。未適用です",
    ),
    "policyDraftRebuild": MessageLookupByLibrary.simpleMessage("独立した下書きを作成"),
    "policyDraftRebuildConfirm": MessageLookupByLibrary.simpleMessage(
      "この下書きと移行資料を破棄しますか？新しいポリシーは旧設定の保護を引き継ぐものではありません。元のプロファイルと動作中の設定は変更されません。",
    ),
    "policyDraftReferenced": m60,
    "policyDraftReload": MessageLookupByLibrary.simpleMessage("保存済み下書きを再読み込み"),
    "policyDraftRestoreFailed": MessageLookupByLibrary.simpleMessage(
      "復元を完了できませんでした。再読み込みして保存済みデータを確認してください。復旧の案内がある場合は対応してください。",
    ),
    "policyDraftRestoreWarning": MessageLookupByLibrary.simpleMessage(
      "上書き復元は資料にエンティティがある場合に置換し、含まれない下書きを削除する場合があります。エンティティが空なら保持します。続行しますか？",
    ),
    "policyDraftRevealCredentials": MessageLookupByLibrary.simpleMessage(
      "認証情報を表示",
    ),
    "policyDraftSaveFailed": MessageLookupByLibrary.simpleMessage(
      "保存できませんでした。入力内容と保存済みの下書きは保持されています。",
    ),
    "policyDraftSaved": MessageLookupByLibrary.simpleMessage(
      "下書きを保存しました。未適用です",
    ),
    "policyDraftStorage": MessageLookupByLibrary.simpleMessage(
      "下書きには認証情報が含まれる場合があります。既存のDB領域（Androidではアプリ専用領域）に保存され、ZIPバックアップは暗号化されません。保存しても適用されません。",
    ),
    "policyDraftTarget": MessageLookupByLibrary.simpleMessage("転送先"),
    "policyDraftTitle": MessageLookupByLibrary.simpleMessage("ポリシーの下書き"),
    "policyDraftUdp": MessageLookupByLibrary.simpleMessage("このノードでUDPを有効化"),
    "policyDraftUnsaved": MessageLookupByLibrary.simpleMessage("未保存の下書き。未適用です"),
    "policyDraftUnset": MessageLookupByLibrary.simpleMessage("未設定"),
    "policyDraftUsername": MessageLookupByLibrary.simpleMessage("ユーザー名"),
    "policyFinalPreview": MessageLookupByLibrary.simpleMessage("生成された最終構成"),
    "policyMaintenanceNone": MessageLookupByLibrary.simpleMessage(
      "既定のプロキシを設定しない",
    ),
    "policyMaintenanceRequired": MessageLookupByLibrary.simpleMessage(
      "メンテナンス用のグループかノードを選択して適用するか、この要求に Auto または Direct を明示的に選択してください。以前の対象は存在しない可能性があります。",
    ),
    "policyMaintenanceTarget": MessageLookupByLibrary.simpleMessage(
      "メンテナンス通信のプロキシ",
    ),
    "policyManagedEditRequired": MessageLookupByLibrary.simpleMessage(
      "このプロファイルは管理対象ポリシーを使用します。下書きでルーティングと DNS を編集し、適用を要求してください。",
    ),
    "policyMaterialBindings": MessageLookupByLibrary.simpleMessage("ソースの関連付け"),
    "policyMaterialCancel": MessageLookupByLibrary.simpleMessage("プレビュー素材を破棄"),
    "policyMaterialCollections": MessageLookupByLibrary.simpleMessage("ソースの集合"),
    "policyMaterialDomain": MessageLookupByLibrary.simpleMessage(
      "ソースのドメイン集合を関連付け",
    ),
    "policyMaterialGroup": MessageLookupByLibrary.simpleMessage(
      "ソースの select グループを関連付け",
    ),
    "policyMaterialIp": MessageLookupByLibrary.simpleMessage("ソースのアドレス集合を関連付け"),
    "policyMaterialLatest": MessageLookupByLibrary.simpleMessage(
      "最新の素材をプレビュー用に読み込む",
    ),
    "policyMaterialLoaded": MessageLookupByLibrary.simpleMessage(
      "最新の素材を読み込みました。変更された名前を関連付け直してプレビューし、Apply で適用してください。Save は下書きのみ保存します。",
    ),
    "policyMaterialNode": MessageLookupByLibrary.simpleMessage("ソースノードを関連付け"),
    "policyMaterialSource": MessageLookupByLibrary.simpleMessage("ソース名を選択"),
    "policyMaterialUnavailable": MessageLookupByLibrary.simpleMessage(
      "素材が利用できないか互換性がありません。ソースの関連付けを確認して再度プレビューしてください。",
    ),
    "policyOriginal": MessageLookupByLibrary.simpleMessage("元のプロファイルを使用"),
    "policyOriginalConfirm": MessageLookupByLibrary.simpleMessage(
      "管理対象のルーティングを終了し、元のルール、DNS、上書きを使用しますか？通信経路が変わる可能性があります。",
    ),
    "policyOriginalStatus": MessageLookupByLibrary.simpleMessage(
      "元のプロファイルを選択済み",
    ),
    "policySelectedStatus": MessageLookupByLibrary.simpleMessage(
      "ポリシーを選択済み。実際の受理状態は別に表示します",
    ),
    "policySelectionPending": MessageLookupByLibrary.simpleMessage(
      "選択済みポリシーは実際に受理された構成と異なります。",
    ),
    "policySelectionUnavailable": MessageLookupByLibrary.simpleMessage(
      "管理対象ポリシーが必要ですが利用できません。有効なポリシーを選択してください。",
    ),
    "policyUnappliedEdits": MessageLookupByLibrary.simpleMessage(
      "下書きは選択済みポリシーと異なり、変更は未適用です",
    ),
    "port": MessageLookupByLibrary.simpleMessage("ポート"),
    "portConflictTip": MessageLookupByLibrary.simpleMessage("別のポートを入力してください"),
    "portTip": m61,
    "prerequisites": MessageLookupByLibrary.simpleMessage("前提条件"),
    "pressKeyboard": MessageLookupByLibrary.simpleMessage("キーの組み合わせを押してください"),
    "preview": MessageLookupByLibrary.simpleMessage("プレビュー"),
    "previousMatch": MessageLookupByLibrary.simpleMessage("前の一致"),
    "process": MessageLookupByLibrary.simpleMessage("プロセス"),
    "profile": MessageLookupByLibrary.simpleMessage("プロファイル"),
    "profileAutoUpdateIntervalInvalidValidationDesc":
        MessageLookupByLibrary.simpleMessage(
          "分単位の正の整数を入力してください。以前の無効な値は1日として扱われます。",
        ),
    "profileAutoUpdateIntervalNullValidationDesc":
        MessageLookupByLibrary.simpleMessage("自動更新間隔を入力してください"),
    "profileDownloadFailed": MessageLookupByLibrary.simpleMessage(
      "ダウンロードに失敗しました。以前のファイルを保持しました。",
    ),
    "profileDownloadTimeout": MessageLookupByLibrary.simpleMessage(
      "サブスクリプションのダウンロードが90秒を超えました。",
    ),
    "profileDownloadTooLarge": MessageLookupByLibrary.simpleMessage(
      "サブスクリプションが16 MiBの上限を超えています。",
    ),
    "profileHasUpdate": MessageLookupByLibrary.simpleMessage(
      "プロファイルが変更されています。自動更新を無効にしますか？",
    ),
    "profileImportContinue": MessageLookupByLibrary.simpleMessage("続ける"),
    "profileImportDownloadFailed": MessageLookupByLibrary.simpleMessage(
      "サブスクリプションをダウンロードできませんでした。URL とリクエスト経路を確認して再試行してください。",
    ),
    "profileImportDownloading": MessageLookupByLibrary.simpleMessage(
      "サブスクリプションをダウンロード中…",
    ),
    "profileImportInvalid": MessageLookupByLibrary.simpleMessage(
      "ダウンロードしたファイルは有効なサブスクリプションではありません。URL を確認してください。",
    ),
    "profileImportPreparing": MessageLookupByLibrary.simpleMessage(
      "インポートを準備中…",
    ),
    "profileImportSaving": MessageLookupByLibrary.simpleMessage(
      "サブスクリプションを保存中…",
    ),
    "profileInvalidBody": MessageLookupByLibrary.simpleMessage(
      "ダウンロードした設定が無効です。以前のファイルを保持しました。",
    ),
    "profileNameNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "プロファイル名を入力してください",
    ),
    "profileRefreshFailed": MessageLookupByLibrary.simpleMessage(
      "サブスクリプションの更新に失敗しました。現在の設定状態を確認してください。",
    ),
    "profileSavedNotApplied": MessageLookupByLibrary.simpleMessage(
      "保存しました。現在の設定状態を確認してください。更新はまだ適用されていない可能性があります。",
    ),
    "profileSavedRecoveryRequired": MessageLookupByLibrary.simpleMessage(
      "サブスクリプションは保存されましたが、クリーンアップを確認できません。以降のリクエストには復旧が必要です。",
    ),
    "profileUrlInvalidValidationDesc": MessageLookupByLibrary.simpleMessage(
      "有効なプロファイルURLを入力してください",
    ),
    "profileUrlNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "プロファイルのURLを入力してください",
    ),
    "profiles": MessageLookupByLibrary.simpleMessage("プロファイル"),
    "profilesSort": MessageLookupByLibrary.simpleMessage("プロファイルの並べ替え"),
    "project": MessageLookupByLibrary.simpleMessage("プロジェクト"),
    "providerInUse": m62,
    "providerRenameShadowed": m63,
    "providerSourceSubscription": MessageLookupByLibrary.simpleMessage(
      "サブスクリプション",
    ),
    "providerUrlTip": MessageLookupByLibrary.simpleMessage("リモートリソースのみ対応しています"),
    "providers": MessageLookupByLibrary.simpleMessage("外部リソース"),
    "proxies": MessageLookupByLibrary.simpleMessage("プロキシ"),
    "proxiesCount": m64,
    "proxiesEmpty": MessageLookupByLibrary.simpleMessage("プロキシが空です"),
    "proxyChains": MessageLookupByLibrary.simpleMessage("プロキシチェーン"),
    "proxyDefinition": MessageLookupByLibrary.simpleMessage("完全な設定"),
    "proxyDefinitionNotMap": MessageLookupByLibrary.simpleMessage(
      "設定は name と type を含む YAML マッピングである必要があります",
    ),
    "proxyFilter": MessageLookupByLibrary.simpleMessage("ノードフィルター"),
    "proxyGroup": MessageLookupByLibrary.simpleMessage("プロキシグループ"),
    "proxyGroupEmpty": MessageLookupByLibrary.simpleMessage("プロキシグループが空です"),
    "proxyGroupNameDuplicate": MessageLookupByLibrary.simpleMessage(
      "プロキシグループ名が重複しています",
    ),
    "proxyNode": MessageLookupByLibrary.simpleMessage("プロキシノード"),
    "proxyProviders": MessageLookupByLibrary.simpleMessage("プロキシプロバイダー"),
    "proxyProvidersEmpty": MessageLookupByLibrary.simpleMessage(
      "プロキシプロバイダーが空です",
    ),
    "proxyProvidersNotEmpty": MessageLookupByLibrary.simpleMessage(
      "プロキシプロバイダーは空にできません",
    ),
    "proxyType": MessageLookupByLibrary.simpleMessage("プロキシタイプ"),
    "pruneCache": MessageLookupByLibrary.simpleMessage("キャッシュを整理"),
    "pureBlack": MessageLookupByLibrary.simpleMessage("ピュアブラック"),
    "pureBlackMode": MessageLookupByLibrary.simpleMessage("ピュアブラックモード"),
    "qrImageBusy": MessageLookupByLibrary.simpleMessage(
      "画像の認識は処理中です。カメラ、URL、またはファイルから取り込んでください。",
    ),
    "qrImageReadFailed": MessageLookupByLibrary.simpleMessage(
      "この画像を読み取れません。別のローカル画像を選択してください。",
    ),
    "qrImageTimeout": MessageLookupByLibrary.simpleMessage(
      "画像の認識がタイムアウトしました。後でもう一度試すか、カメラを使用してください。",
    ),
    "qrcode": MessageLookupByLibrary.simpleMessage("QRコード"),
    "qrcodeDesc": MessageLookupByLibrary.simpleMessage(
      "QRコードをスキャンしてプロファイルを取得します",
    ),
    "quickAdd": MessageLookupByLibrary.simpleMessage("クイック追加"),
    "quickEdit": MessageLookupByLibrary.simpleMessage("クイック編集"),
    "quickFill": MessageLookupByLibrary.simpleMessage("クイック入力"),
    "rainbowScheme": MessageLookupByLibrary.simpleMessage("レインボー"),
    "recentRequests": MessageLookupByLibrary.simpleMessage("最近のリクエスト"),
    "recordType": MessageLookupByLibrary.simpleMessage("レコードタイプ"),
    "redirPort": MessageLookupByLibrary.simpleMessage("Redirポート"),
    "redo": MessageLookupByLibrary.simpleMessage("やり直す"),
    "releaseMemory": MessageLookupByLibrary.simpleMessage("メモリを解放"),
    "releaseMemoryFailed": MessageLookupByLibrary.simpleMessage(
      "メモリの解放に失敗しました",
    ),
    "remote": MessageLookupByLibrary.simpleMessage("リモート"),
    "remoteDestination": MessageLookupByLibrary.simpleMessage("リモート宛先"),
    "remove": MessageLookupByLibrary.simpleMessage("削除"),
    "replace": MessageLookupByLibrary.simpleMessage("置換"),
    "replaceAll": MessageLookupByLibrary.simpleMessage("すべて置換"),
    "reportBuildIdentity": MessageLookupByLibrary.simpleMessage(
      "ビルド情報（欠落項目は不明）",
    ),
    "reportBusy": MessageLookupByLibrary.simpleMessage(
      "処理中またはタイムアウトです。I/O は続行中の可能性があります。後で更新してください。",
    ),
    "reportCancelled": MessageLookupByLibrary.simpleMessage(
      "キャンセルしました。保存先に不完全なコピーがないか確認してください。",
    ),
    "reportCorrupt": MessageLookupByLibrary.simpleMessage("破損または未対応の項目"),
    "reportDeleteAll": MessageLookupByLibrary.simpleMessage("現在のレポートを削除"),
    "reportDeleteWarning": MessageLookupByLibrary.simpleMessage(
      "選択したレポート、または現在のスナップショット全体を削除しますか？新しいレポートは残る場合があります。重複防止記録とエクスポート済みコピーは保持され、今後の障害は引き続き記録されます。",
    ),
    "reportDeleted": MessageLookupByLibrary.simpleMessage("選択したレポートを削除しました"),
    "reportDestinationWarning": MessageLookupByLibrary.simpleMessage(
      "保存先を確認してください。プロバイダーがクラウドに同期する場合があります。アプリは自動送信しません。キャンセル・失敗後に不完全なコピーが残る場合があります。",
    ),
    "reportEmpty": MessageLookupByLibrary.simpleMessage("保存されたレポートはありません"),
    "reportExportRaw": MessageLookupByLibrary.simpleMessage("原文をエクスポート（ZIP）"),
    "reportExportSummary": MessageLookupByLibrary.simpleMessage(
      "概要をエクスポート（JSON）",
    ),
    "reportExported": MessageLookupByLibrary.simpleMessage("保存して検証しました"),
    "reportFailed": MessageLookupByLibrary.simpleMessage(
      "処理に失敗、または一部のみ完了しました。更新し、エクスポート先も確認してください。",
    ),
    "reportIntegrity": MessageLookupByLibrary.simpleMessage(
      "整合性の検証に失敗しました。保存先の不完全なコピーを確認してください。",
    ),
    "reportLimited": MessageLookupByLibrary.simpleMessage(
      "ディレクトリの処理上限に達しました。一部を処理できませんでした。",
    ),
    "reportMetadataOnly": MessageLookupByLibrary.simpleMessage(
      "メタデータのみ。trace は後から自動補完されません",
    ),
    "reportRawMissing": MessageLookupByLibrary.simpleMessage("原文がないか一致しません"),
    "reportRawUnverified": MessageLookupByLibrary.simpleMessage("原文は未検証です"),
    "reportRawWarning": MessageLookupByLibrary.simpleMessage(
      "原文には認証情報、アドレス、メモリの断片が含まれる可能性があります。意図した相手のみに渡してください。保存先がクラウドに同期する場合や、キャンセル・失敗後に不完全なコピーが残る場合があります。原文をエクスポートしますか？",
    ),
    "reportRefresh": MessageLookupByLibrary.simpleMessage("更新"),
    "reportRetention": MessageLookupByLibrary.simpleMessage(
      "上限：20 件、16 MiB、30 日。自動削除はベストエフォートです。",
    ),
    "reportStale": MessageLookupByLibrary.simpleMessage(
      "レポートが変更されたか選択が期限切れです。更新して再選択してください。",
    ),
    "reportTruncated": MessageLookupByLibrary.simpleMessage(
      "切り詰められた資料です。完全な dump ではありません",
    ),
    "reportUnknownFormat": MessageLookupByLibrary.simpleMessage("不明なレポート形式"),
    "reportUsage": MessageLookupByLibrary.simpleMessage("使用容量（不明な項目と内部索引を含む）"),
    "reportWrittenUnverified": MessageLookupByLibrary.simpleMessage(
      "書き込み済み。保存先の内容は未検証です",
    ),
    "request": MessageLookupByLibrary.simpleMessage("リクエスト"),
    "requestDirectRecoveryMessage": m65,
    "requestDirectRecoveryTitle": MessageLookupByLibrary.simpleMessage(
      "今回のみ直接接続で復元しますか？",
    ),
    "requestMode": MessageLookupByLibrary.simpleMessage("リクエストの経路"),
    "requestModeAuto": MessageLookupByLibrary.simpleMessage("自動"),
    "requestModeDirect": MessageLookupByLibrary.simpleMessage("直接接続"),
    "requestModeHelp": MessageLookupByLibrary.simpleMessage(
      "この項目自体の通信に適用します。プロキシには有効なノードが、直接接続には利用可能な非 VPN ネットワークが必要です。",
    ),
    "requestModeProxy": MessageLookupByLibrary.simpleMessage("プロキシ"),
    "requestPartialCommit": MessageLookupByLibrary.simpleMessage(
      "一部のローカル変更を復元できませんでした。復旧用ファイルを保持し、自動更新を停止しました。",
    ),
    "requestProxyDefault": m66,
    "requestProxyTarget": MessageLookupByLibrary.simpleMessage("プロキシの接続先"),
    "requestRestartRequired": MessageLookupByLibrary.simpleMessage(
      "未完了のローカル保存が実行中の可能性があります。アプリ情報 → 強制停止を選び、FlClashを開き直してください。プロキシサービスの再起動や画面を閉じるだけでは解決しません。開き直した後、ソースの権限で保存済みデータを確認してください。",
    ),
    "requestRouteUnavailable": MessageLookupByLibrary.simpleMessage(
      "選択した通信経路は現在利用できません。",
    ),
    "requests": MessageLookupByLibrary.simpleMessage("リクエスト"),
    "requestsAndUpdates": MessageLookupByLibrary.simpleMessage("リクエストと更新"),
    "reset": MessageLookupByLibrary.simpleMessage("リセット"),
    "resetPageChangesTip": MessageLookupByLibrary.simpleMessage(
      "このページには変更があります。リセットしてもよろしいですか？",
    ),
    "resetTip": MessageLookupByLibrary.simpleMessage("リセットしてもよろしいですか？"),
    "resources": MessageLookupByLibrary.simpleMessage("リソース"),
    "respectRules": MessageLookupByLibrary.simpleMessage("ルールに従う"),
    "respectRulesDesc": MessageLookupByLibrary.simpleMessage(
      "DNS接続がルールに従います。Proxy Server Nameserverの設定が必要です",
    ),
    "responseCode": MessageLookupByLibrary.simpleMessage("応答コード"),
    "restart": MessageLookupByLibrary.simpleMessage("再起動"),
    "restartCoreTip": MessageLookupByLibrary.simpleMessage("コアを再起動してもよろしいですか？"),
    "restore": MessageLookupByLibrary.simpleMessage("復元"),
    "restoreAllData": MessageLookupByLibrary.simpleMessage("すべてのデータを復元"),
    "restoreOnlyConfig": MessageLookupByLibrary.simpleMessage("プロファイルのみ復元"),
    "restoreStrategy": MessageLookupByLibrary.simpleMessage("復元方式"),
    "restoreStrategyCompatible": MessageLookupByLibrary.simpleMessage("互換"),
    "restoreStrategyOverride": MessageLookupByLibrary.simpleMessage("上書き"),
    "restoreSuccess": MessageLookupByLibrary.simpleMessage("復元が完了しました"),
    "retry": MessageLookupByLibrary.simpleMessage("再試行"),
    "routeAddress": MessageLookupByLibrary.simpleMessage("ルートアドレス"),
    "routeMode": MessageLookupByLibrary.simpleMessage("ルートモード"),
    "routeModeBypassPrivate": MessageLookupByLibrary.simpleMessage(
      "プライベートアドレスをバイパス",
    ),
    "routeModeConfig": MessageLookupByLibrary.simpleMessage("設定を使用"),
    "ru": MessageLookupByLibrary.simpleMessage("ロシア語"),
    "rule": MessageLookupByLibrary.simpleMessage("ルール"),
    "ruleActionAndDesc": MessageLookupByLibrary.simpleMessage("論理ルール AND"),
    "ruleActionDomainDesc": MessageLookupByLibrary.simpleMessage("完全なドメインにマッチ"),
    "ruleActionDomainKeywordDesc": MessageLookupByLibrary.simpleMessage(
      "ドメインキーワードにマッチ",
    ),
    "ruleActionDomainRegexDesc": MessageLookupByLibrary.simpleMessage(
      "ドメインの正規表現でマッチ",
    ),
    "ruleActionDomainSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "ドメインサフィックスにマッチ",
    ),
    "ruleActionDomainWildcardDesc": MessageLookupByLibrary.simpleMessage(
      "ワイルドカードでマッチ（* と ? のみ対応）",
    ),
    "ruleActionDscpDesc": MessageLookupByLibrary.simpleMessage(
      "DSCPマークにマッチ（tproxy udpインバウンドのみ）",
    ),
    "ruleActionDstPortDesc": MessageLookupByLibrary.simpleMessage(
      "宛先ポート範囲にマッチ",
    ),
    "ruleActionGeoipDesc": MessageLookupByLibrary.simpleMessage("IPの国コードにマッチ"),
    "ruleActionGeositeDesc": MessageLookupByLibrary.simpleMessage(
      "Geosite 内のドメインにマッチ",
    ),
    "ruleActionInNameDesc": MessageLookupByLibrary.simpleMessage("インバウンド名にマッチ"),
    "ruleActionInPortDesc": MessageLookupByLibrary.simpleMessage(
      "インバウンドポートにマッチ",
    ),
    "ruleActionInTypeDesc": MessageLookupByLibrary.simpleMessage(
      "インバウンドタイプにマッチ",
    ),
    "ruleActionInUserDesc": MessageLookupByLibrary.simpleMessage(
      "インバウンドユーザー名にマッチ（/ で複数指定可）",
    ),
    "ruleActionIpAsnDesc": MessageLookupByLibrary.simpleMessage(
      "IPが属するASNにマッチ",
    ),
    "ruleActionIpCidr6Desc": MessageLookupByLibrary.simpleMessage(
      "IPアドレス範囲にマッチ（IP-CIDR6 は別名です）",
    ),
    "ruleActionIpCidrDesc": MessageLookupByLibrary.simpleMessage(
      "IPアドレス範囲にマッチ",
    ),
    "ruleActionIpSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "IPサフィックス範囲にマッチ",
    ),
    "ruleActionMatchDesc": MessageLookupByLibrary.simpleMessage(
      "すべてのリクエストにマッチ（条件不要）",
    ),
    "ruleActionNetworkDesc": MessageLookupByLibrary.simpleMessage(
      "TCPまたはUDPにマッチ",
    ),
    "ruleActionNotDesc": MessageLookupByLibrary.simpleMessage("論理ルール NOT"),
    "ruleActionOrDesc": MessageLookupByLibrary.simpleMessage("論理ルール OR"),
    "ruleActionProcessNameDesc": MessageLookupByLibrary.simpleMessage(
      "プロセス名でマッチ（Androidではパッケージ名にマッチ）",
    ),
    "ruleActionProcessNameRegexDesc": MessageLookupByLibrary.simpleMessage(
      "プロセス名の正規表現でマッチ（Androidではパッケージ名にマッチ）",
    ),
    "ruleActionProcessNameWildcardDesc": MessageLookupByLibrary.simpleMessage(
      "プロセス名のワイルドカードでマッチ（* と ? のみ対応）",
    ),
    "ruleActionProcessPathDesc": MessageLookupByLibrary.simpleMessage(
      "プロセスのフルパスでマッチ",
    ),
    "ruleActionProcessPathRegexDesc": MessageLookupByLibrary.simpleMessage(
      "プロセスパスの正規表現でマッチ",
    ),
    "ruleActionProcessPathWildcardDesc": MessageLookupByLibrary.simpleMessage(
      "プロセスパスのワイルドカードでマッチ（* と ? のみ対応）",
    ),
    "ruleActionRematchNameDesc": MessageLookupByLibrary.simpleMessage(
      "再マッチ名にマッチ（複数は / で区切る）",
    ),
    "ruleActionRuleSetDesc": MessageLookupByLibrary.simpleMessage(
      "ルールセットを参照します。rule-providersの設定が必要です",
    ),
    "ruleActionSrcGeoipDesc": MessageLookupByLibrary.simpleMessage(
      "送信元IPの国コードにマッチ",
    ),
    "ruleActionSrcIpAsnDesc": MessageLookupByLibrary.simpleMessage(
      "送信元IPが属するASNにマッチ",
    ),
    "ruleActionSrcIpCidrDesc": MessageLookupByLibrary.simpleMessage(
      "送信元IPアドレス範囲にマッチ",
    ),
    "ruleActionSrcIpSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "送信元IPサフィックス範囲にマッチ",
    ),
    "ruleActionSrcPortDesc": MessageLookupByLibrary.simpleMessage(
      "送信元ポート範囲にマッチ",
    ),
    "ruleActionSubRuleDesc": MessageLookupByLibrary.simpleMessage(
      "サブルールへマッチします。括弧の使い方に注意してください",
    ),
    "ruleActionUidDesc": MessageLookupByLibrary.simpleMessage(
      "LinuxのユーザーIDにマッチ",
    ),
    "ruleEmpty": MessageLookupByLibrary.simpleMessage("ルールが空です"),
    "ruleName": MessageLookupByLibrary.simpleMessage("ルール名"),
    "rulePresetBittorrentDirect": MessageLookupByLibrary.simpleMessage(
      "BitTorrent を直接接続",
    ),
    "rulePresetBlockDot": MessageLookupByLibrary.simpleMessage(
      "DNS over TLS をブロック",
    ),
    "rulePresetBlockQuic": MessageLookupByLibrary.simpleMessage("QUIC をブロック"),
    "rulePresetBlockStun": MessageLookupByLibrary.simpleMessage("STUN をブロック"),
    "rulePresetLanDirect": MessageLookupByLibrary.simpleMessage("LAN 直接接続"),
    "rulePresetSystemServicesDirect": MessageLookupByLibrary.simpleMessage(
      "Apple と Microsoft に直接接続",
    ),
    "ruleProviders": MessageLookupByLibrary.simpleMessage("ルールプロバイダー"),
    "ruleSet": MessageLookupByLibrary.simpleMessage("ルールセット"),
    "ruleTarget": MessageLookupByLibrary.simpleMessage("ルールターゲット"),
    "rules": MessageLookupByLibrary.simpleMessage("ルール"),
    "rulesCount": m67,
    "runTime": MessageLookupByLibrary.simpleMessage("起動時間"),
    "safeMode": MessageLookupByLibrary.simpleMessage("セーフモード"),
    "safeModeAppTitle": m68,
    "save": MessageLookupByLibrary.simpleMessage("保存"),
    "saveChanges": MessageLookupByLibrary.simpleMessage("変更を保存しますか？"),
    "script": MessageLookupByLibrary.simpleMessage("スクリプト"),
    "scriptModeDesc": MessageLookupByLibrary.simpleMessage(
      "スクリプトモード：外部の拡張スクリプトを使用し、ワンクリックで設定を上書きします",
    ),
    "scrollToSelected": MessageLookupByLibrary.simpleMessage("選択項目へスクロール"),
    "search": MessageLookupByLibrary.simpleMessage("検索"),
    "seconds": MessageLookupByLibrary.simpleMessage("秒"),
    "secondsCount": m69,
    "selectAll": MessageLookupByLibrary.simpleMessage("すべて選択"),
    "selectProxies": MessageLookupByLibrary.simpleMessage("プロキシを選択"),
    "selectProxyProviders": MessageLookupByLibrary.simpleMessage(
      "プロキシプロバイダーを選択",
    ),
    "selectRuleSet": MessageLookupByLibrary.simpleMessage("ルールセットを選択してください"),
    "selectSplitStrategy": MessageLookupByLibrary.simpleMessage(
      "振り分け戦略を選択してください",
    ),
    "selectSubRule": MessageLookupByLibrary.simpleMessage("サブルールを選択してください"),
    "selected": MessageLookupByLibrary.simpleMessage("選択済み"),
    "selectedCountTitle": m70,
    "server": MessageLookupByLibrary.simpleMessage("サーバー"),
    "serviceAdvanced": MessageLookupByLibrary.simpleMessage("地域・サービス検査"),
    "serviceAdvancedExplanation": MessageLookupByLibrary.simpleMessage(
      "任意の一回限りの匿名リクエストで地域やサービスページの情報を調べます。下記の追加接続先にアクセスする場合があります。ブラウザーのログインCookieや購読認証情報は送信しません。アカウント権限・再生・端末全体の保護は保証せず、基本応答とは別に判断します。",
    ),
    "serviceAdvancedTiming": MessageLookupByLibrary.simpleMessage(
      "結果は5分で期限切れ、開始間隔は最低30秒です。自動再実行はせず、ページを離れると未完了の検査を中止します。各時間は応答ヘッダーまでの時間で、pingや速度ではありません。",
    ),
    "serviceAllDisabled": MessageLookupByLibrary.simpleMessage(
      "すべて無効 · サービス管理",
    ),
    "serviceAvailable": MessageLookupByLibrary.simpleMessage("利用可能"),
    "serviceBasic": MessageLookupByLibrary.simpleMessage("基本 HTTPS 応答"),
    "serviceBasicExplanation": MessageLookupByLibrary.simpleMessage(
      "表示中のサービスを前景で自動検査します。結果は5分で期限切れになり、経路変更やアプリ復帰時に必要に応じ再検査します。開始間隔は最低30秒です。一括検査は有効な項目のみです。応答ヘッダーのみ読み、転送やページ素材は読み込みません。応答は機能・アカウント権限・端末全体の保護を保証しません。",
    ),
    "serviceBlocked": MessageLookupByLibrary.simpleMessage("ブロック済み"),
    "serviceBodyComplete": MessageLookupByLibrary.simpleMessage("本文を完全に読み取り"),
    "serviceBodyLimit": MessageLookupByLibrary.simpleMessage("応答サイズの上限に到達"),
    "serviceCheck": MessageLookupByLibrary.simpleMessage("検査"),
    "serviceCheckAll": MessageLookupByLibrary.simpleMessage("すべて検査"),
    "serviceCheckedAt": m71,
    "serviceComingSoon": MessageLookupByLibrary.simpleMessage("近日提供予定"),
    "serviceConnectFailed": MessageLookupByLibrary.simpleMessage(
      "今回のリクエストは応答を確立できません",
    ),
    "serviceDetectedRegion": m72,
    "serviceDisallowedIsp": MessageLookupByLibrary.simpleMessage(
      "許可されていない ISP",
    ),
    "serviceDisneyExplanation": MessageLookupByLibrary.simpleMessage(
      "開始すると匿名ブラウザーデバイスを登録し、一時トークンに交換してセッションを照会します。トークンは今回のみ使用し保存しません。",
    ),
    "serviceDnsFailed": MessageLookupByLibrary.simpleMessage("今回のホストを解決できません"),
    "serviceElapsed": m73,
    "serviceExpired": m74,
    "serviceFailed": MessageLookupByLibrary.simpleMessage("判定不能"),
    "serviceHeaders": MessageLookupByLibrary.simpleMessage("応答ヘッダーを受信"),
    "serviceHttpResponse": MessageLookupByLibrary.simpleMessage("HTTP 応答"),
    "serviceIndeterminate": MessageLookupByLibrary.simpleMessage(
      "判定できません。検査未完了または応答形式が変更された可能性があります。",
    ),
    "serviceManage": MessageLookupByLibrary.simpleMessage("サービスを管理"),
    "serviceMarkerFound": MessageLookupByLibrary.simpleMessage("必要な情報を検出"),
    "serviceMultipleRoutes": MessageLookupByLibrary.simpleMessage(
      "複数の出口 · 各リクエストを確認",
    ),
    "serviceObserved": MessageLookupByLibrary.simpleMessage("サービス情報を確認"),
    "serviceOriginalsOnly": MessageLookupByLibrary.simpleMessage("オリジナル作品のみ"),
    "servicePending": MessageLookupByLibrary.simpleMessage("未検査"),
    "serviceQueued": MessageLookupByLibrary.simpleMessage("検査間隔を待機中"),
    "serviceReadError": MessageLookupByLibrary.simpleMessage("応答が中断または読取不能"),
    "serviceRecipientBlocked": MessageLookupByLibrary.simpleMessage(
      "接続先または転送が検査範囲外",
    ),
    "serviceRecipients": m75,
    "serviceRedirected": MessageLookupByLibrary.simpleMessage("リダイレクト応答（未追跡）"),
    "serviceRequestLimit": MessageLookupByLibrary.simpleMessage("リクエスト上限に到達"),
    "serviceResponded": MessageLookupByLibrary.simpleMessage("応答あり"),
    "serviceRestricted": MessageLookupByLibrary.simpleMessage("アクセス制限"),
    "serviceRouteChanged": MessageLookupByLibrary.simpleMessage(
      "経路変更 · 手動で再検査",
    ),
    "serviceStartAdvanced": MessageLookupByLibrary.simpleMessage("一回検査を開始"),
    "serviceStatus": MessageLookupByLibrary.simpleMessage("サービスの状態"),
    "serviceTlsFailed": MessageLookupByLibrary.simpleMessage("今回のTLS証明書検証に失敗"),
    "serviceUnavailable": MessageLookupByLibrary.simpleMessage(
      "今回のリクエストに有効な応答なし",
    ),
    "serviceUnknownRoute": MessageLookupByLibrary.simpleMessage("経路不明"),
    "serviceUnsupportedRegion": MessageLookupByLibrary.simpleMessage("対象外の地域"),
    "settings": MessageLookupByLibrary.simpleMessage("設定"),
    "show": MessageLookupByLibrary.simpleMessage("表示"),
    "showLess": MessageLookupByLibrary.simpleMessage("折りたたむ"),
    "showMore": MessageLookupByLibrary.simpleMessage("展開"),
    "showNotificationStopAction": MessageLookupByLibrary.simpleMessage(
      "通知に停止ボタンを表示",
    ),
    "showPassword": MessageLookupByLibrary.simpleMessage("パスワードを表示"),
    "shrink": MessageLookupByLibrary.simpleMessage("コンパクト"),
    "sidebarBlur": MessageLookupByLibrary.simpleMessage("サイドバーのぼかし"),
    "sidebarBlurDesc": MessageLookupByLibrary.simpleMessage(
      "ウィンドウ背後のデスクトップをぼかしてサイドバーに透過します",
    ),
    "silentLaunch": MessageLookupByLibrary.simpleMessage("サイレント起動"),
    "silentLaunchDesc": MessageLookupByLibrary.simpleMessage(
      "起動時にウィンドウを表示しません",
    ),
    "singleAdd": MessageLookupByLibrary.simpleMessage("個別追加"),
    "singleValueTip": m76,
    "size": MessageLookupByLibrary.simpleMessage("サイズ"),
    "slide": MessageLookupByLibrary.simpleMessage("スライド"),
    "socksPort": MessageLookupByLibrary.simpleMessage("SOCKSポート"),
    "sort": MessageLookupByLibrary.simpleMessage("並べ替え"),
    "source": MessageLookupByLibrary.simpleMessage("ソース"),
    "sourceAcceptRevision": MessageLookupByLibrary.simpleMessage("この版を承認"),
    "sourceAcceptedCapabilities": m77,
    "sourceAcceptedDns": m78,
    "sourceAcceptedProtocols": m79,
    "sourceAcceptedRevisions": m80,
    "sourceAppliedNotSaved": MessageLookupByLibrary.simpleMessage(
      "適用済み・復元情報は未保存",
    ),
    "sourceAppliedRevision": MessageLookupByLibrary.simpleMessage("適用リビジョン"),
    "sourceAutomaticAllowed": MessageLookupByLibrary.simpleMessage("自動保守を許可"),
    "sourceAutomaticStopped": MessageLookupByLibrary.simpleMessage("自動保守を停止済み"),
    "sourceBatchPreparing": MessageLookupByLibrary.simpleMessage(
      "関連ソースを読み込み中…",
    ),
    "sourceBatchScope": MessageLookupByLibrary.simpleMessage(
      "この購読、最終設定、および一覧にあるすべての関連ソースをまとめて確認します。承認はここに表示された内容のスナップショットのみに適用されます。",
    ),
    "sourceBinaryMaterial": MessageLookupByLibrary.simpleMessage(
      "バイナリRuleSet：この正確なバイト列のみを承認します。元のパーサーが検証するまでルール数は不明です。",
    ),
    "sourceCapabilitiesChanged": MessageLookupByLibrary.simpleMessage(
      "ノードの機能またはグループの参照が変更されました。",
    ),
    "sourceCodeChanged": MessageLookupByLibrary.simpleMessage(
      "スクリプトのコードが変更されました。",
    ),
    "sourceConfigParsed": MessageLookupByLibrary.simpleMessage(
      "解析済み・関連ソースは別途確認",
    ),
    "sourceConfigurationUnavailable": MessageLookupByLibrary.simpleMessage(
      "完全なソース設定を利用できない理由",
    ),
    "sourceDeclaredCapabilities": m81,
    "sourceDefaultExit": m82,
    "sourceDelegateMaintenance": MessageLookupByLibrary.simpleMessage(
      "この範囲での保守を許可",
    ),
    "sourceDnsChanged": MessageLookupByLibrary.simpleMessage(
      "DNSサービスまたはポリシーが変更されました。",
    ),
    "sourceEntryChanged": MessageLookupByLibrary.simpleMessage(
      "リスナー、トンネル、または制御機能が変更されました。",
    ),
    "sourceFinalUse": MessageLookupByLibrary.simpleMessage("最終設定"),
    "sourceFirstUse": MessageLookupByLibrary.simpleMessage(
      "このソースはまだ使用を承認されていません。",
    ),
    "sourceImplicitDirect": MessageLookupByLibrary.simpleMessage(
      "暗黙のDIRECTフォールバック",
    ),
    "sourceInspectMaterial": MessageLookupByLibrary.simpleMessage(
      "ソース原文を確認（認証情報を含む場合があります）",
    ),
    "sourceIp": MessageLookupByLibrary.simpleMessage("送信元IP"),
    "sourceLoadCached": MessageLookupByLibrary.simpleMessage(
      "準備完了 · 検証済みスナップショット",
    ),
    "sourceLoadChecking": MessageLookupByLibrary.simpleMessage("購読と権限を確認中…"),
    "sourceLoadDownloading": MessageLookupByLibrary.simpleMessage("ダウンロード中…"),
    "sourceLoadFailed": MessageLookupByLibrary.simpleMessage("失敗"),
    "sourceLoadProgress": m83,
    "sourceLoadQueued": MessageLookupByLibrary.simpleMessage("待機中"),
    "sourceLoadReady": MessageLookupByLibrary.simpleMessage("準備完了"),
    "sourceLoadVerifying": MessageLookupByLibrary.simpleMessage("検証中…"),
    "sourceLocalPolicy": MessageLookupByLibrary.simpleMessage("ローカルポリシー"),
    "sourceMaintenanceLimits": MessageLookupByLibrary.simpleMessage(
      "この版の機能範囲内と確認できる変更だけを自動更新します。他の変更は確認待ちになります。既存接続は元のソケットを使い続け、資源の上限により適用が遅れる場合があります。",
    ),
    "sourceMaterialCounts": m84,
    "sourceMaterialUnavailable": MessageLookupByLibrary.simpleMessage(
      "関連ソースを読み込めません。アドレス、ネットワーク接続、通信経路を確認して再試行してください。",
    ),
    "sourceNoPermissions": MessageLookupByLibrary.simpleMessage(
      "承認済みのソース権限はありません。",
    ),
    "sourceNodeImportHint": MessageLookupByLibrary.simpleMessage(
      "読み込んだノードを利用できます。アプリのネットワーク設定と1つのプロキシグループを使い、ソースのルール、DNS、元のグループは適用しません。元の URL を保持し、自動更新を停止します。手動更新で完全な設定を再試行できます。",
    ),
    "sourceNodeUse": MessageLookupByLibrary.simpleMessage("providerとして使うノード"),
    "sourceNotDeclared": MessageLookupByLibrary.simpleMessage("このソースでは未指定"),
    "sourceNotDelegated": MessageLookupByLibrary.simpleMessage(
      "自動保守はまだ委任されていません。",
    ),
    "sourceOwnDefaultConflict": MessageLookupByLibrary.simpleMessage(
      "独自ルールの末尾には、選択した未一致時の出口を使うMATCHルールを1つだけ指定してください。",
    ),
    "sourceOwnDefaultRequired": MessageLookupByLibrary.simpleMessage(
      "独自規則を適用する前に、未一致通信の出口を明示してください。",
    ),
    "sourceOwnRoutingHint": MessageLookupByLibrary.simpleMessage(
      "オフにするとソースの規則、リスナー、トンネルを除外します。独自規則には未一致通信の出口を明示する必要があります。空の規則でソース規則は復元されません。DNSとグループは別々に承認します。",
    ),
    "sourcePartialBlocked": MessageLookupByLibrary.simpleMessage(
      "次の必須依存関係が不足しているため部分設定を生成できません",
    ),
    "sourcePartialConfigurationHint": MessageLookupByLibrary.simpleMessage(
      "部分設定：利用可能なルール、グループ、DNS、承認済みソースを保持します。承認前に無効化される項目と既定の経路を確認してください。元の URL を保持し、自動更新を停止します。手動更新で完全な設定を復元できます。",
    ),
    "sourcePartialGroups": MessageLookupByLibrary.simpleMessage("無効化されるグループ"),
    "sourcePartialImportHint": MessageLookupByLibrary.simpleMessage(
      "すべてのソースを試行しました。利用可能な内容は保持されます。不足する依存関係を以下に示します。失敗したソースを再試行するか、利用可能な設定を確認してください。",
    ),
    "sourcePartialMissing": MessageLookupByLibrary.simpleMessage("利用できないソース"),
    "sourcePartialRules": MessageLookupByLibrary.simpleMessage(
      "無効化されるルール（他のルールの順序は保持）",
    ),
    "sourcePartialSettings": MessageLookupByLibrary.simpleMessage(
      "無効化される DNS ポリシー",
    ),
    "sourcePermissionEffects": MessageLookupByLibrary.simpleMessage(
      "操作は表示された用途だけに適用されます。自動保守の停止は承認済みの内容を保持します。使用の停止は影響する接続を閉じ、再適用を無効にします。他の用途の権限は維持されます。",
    ),
    "sourcePermissions": MessageLookupByLibrary.simpleMessage("ソースの権限"),
    "sourcePermissionsUnavailable": MessageLookupByLibrary.simpleMessage(
      "ソース権限を読み取れないか、検証できません。再試行し、解消しない場合はアプリのログを確認してください。",
    ),
    "sourceProfileUse": MessageLookupByLibrary.simpleMessage("Profileの設定内容"),
    "sourceProposedDns": m85,
    "sourceProtocols": m86,
    "sourceProviderChanged": MessageLookupByLibrary.simpleMessage(
      "プロバイダーまたは取得元が変更されました。",
    ),
    "sourceRecoveryDescription": MessageLookupByLibrary.simpleMessage(
      "この端末に保存されたプロファイル、スクリプト、権限を確認します。現在の設定による通信を停止し、未完了の承認を破棄します。確認後にソースを再確認して設定を適用してください。",
    ),
    "sourceRecoveryTitle": MessageLookupByLibrary.simpleMessage("未完了の保存を確認"),
    "sourceRecoveryUnavailable": MessageLookupByLibrary.simpleMessage(
      "ソース権限は変更されましたが、復元checkpointを更新できませんでした。再起動時の復元は利用できません。",
    ),
    "sourceRelatedSourcesCount": m87,
    "sourceRematchDenied": MessageLookupByLibrary.simpleMessage(
      "ソースのルーティングを除外している間は、REMATCHノードを使用できません。",
    ),
    "sourceReviewPending": MessageLookupByLibrary.simpleMessage("確認が必要"),
    "sourceReviewRequired": MessageLookupByLibrary.simpleMessage(
      "ソースの変更を使用するには確認が必要です。",
    ),
    "sourceReviewScope": MessageLookupByLibrary.simpleMessage(
      "この版のノードと機能を選択する権限を信頼できるソースだけを承認してください。材料の承認と実際の適用は別の操作です。",
    ),
    "sourceReviewTitle": MessageLookupByLibrary.simpleMessage("ソースを確認"),
    "sourceRoutingChanged": MessageLookupByLibrary.simpleMessage(
      "ルーティング、固定保護、または既定の出口が変更されました。",
    ),
    "sourceRoutingExcluded": MessageLookupByLibrary.simpleMessage(
      "この内容には除外したルーティング機能が含まれます。削除するか、ソースのルーティング設定を明示的に変更してください。",
    ),
    "sourceRuleDelegation": m88,
    "sourceRuleOrigin": MessageLookupByLibrary.simpleMessage("ルールの出所"),
    "sourceRuleSetUse": MessageLookupByLibrary.simpleMessage("RuleSetの内容"),
    "sourceSavePending": MessageLookupByLibrary.simpleMessage("後で確認するため保存"),
    "sourceScriptScope": MessageLookupByLibrary.simpleMessage(
      "このコードは設定を読み、consoleに出力できます。承認前には実行せず、出力も別に確認します。コードの承認はすべての出力の承認ではありません。",
    ),
    "sourceScriptTitle": MessageLookupByLibrary.simpleMessage("スクリプトを確認"),
    "sourceStatusChecking": MessageLookupByLibrary.simpleMessage("ソースの権限を確認中…"),
    "sourceStatusRetry": MessageLookupByLibrary.simpleMessage(
      "権限の状態を取得できません · 再試行",
    ),
    "sourceStopAutomatic": MessageLookupByLibrary.simpleMessage("自動保守を停止"),
    "sourceStopUse": MessageLookupByLibrary.simpleMessage("この内容の使用を停止"),
    "sourceStorageFull": MessageLookupByLibrary.simpleMessage(
      "ソース保存容量の上限に達したため、操作を完了できませんでした。",
    ),
    "sourceSubscriptionReview": MessageLookupByLibrary.simpleMessage(
      "サブスクリプションを確認",
    ),
    "sourceUnknownChanged": MessageLookupByLibrary.simpleMessage(
      "安全に分類できない有効な変更があります。",
    ),
    "sourceUseAvailableConfiguration": MessageLookupByLibrary.simpleMessage(
      "利用可能な設定を確認",
    ),
    "sourceUseRouting": MessageLookupByLibrary.simpleMessage("ソースのルーティング規則を使用"),
    "specialProxy": MessageLookupByLibrary.simpleMessage("特殊プロキシ"),
    "specialRules": MessageLookupByLibrary.simpleMessage("特殊ルール"),
    "speedStatistics": MessageLookupByLibrary.simpleMessage("速度統計"),
    "splitStrategy": MessageLookupByLibrary.simpleMessage("振り分け戦略"),
    "splitStrategyNotEmpty": MessageLookupByLibrary.simpleMessage(
      "振り分け戦略は空にできません",
    ),
    "ssidsEmpty": MessageLookupByLibrary.simpleMessage("SSIDが空です"),
    "stackMode": MessageLookupByLibrary.simpleMessage("スタックモード"),
    "standard": MessageLookupByLibrary.simpleMessage("標準"),
    "standardModeDesc": MessageLookupByLibrary.simpleMessage(
      "標準モード：基本設定を上書きし、シンプルなルール追加機能を提供します",
    ),
    "start": MessageLookupByLibrary.simpleMessage("開始"),
    "startFromScratch": MessageLookupByLibrary.simpleMessage("最初から作成"),
    "startVpn": MessageLookupByLibrary.simpleMessage("VPNを起動しています…"),
    "startupAndBackground": MessageLookupByLibrary.simpleMessage("起動とバックグラウンド"),
    "status": MessageLookupByLibrary.simpleMessage("状態"),
    "statusDesc": MessageLookupByLibrary.simpleMessage("無効にすると、システムDNSを使用します"),
    "stop": MessageLookupByLibrary.simpleMessage("停止"),
    "stopVpn": MessageLookupByLibrary.simpleMessage("VPNを停止しています…"),
    "strategy": MessageLookupByLibrary.simpleMessage("戦略"),
    "style": MessageLookupByLibrary.simpleMessage("スタイル"),
    "subRule": MessageLookupByLibrary.simpleMessage("サブルール"),
    "subRuleEmpty": MessageLookupByLibrary.simpleMessage("サブルールが空です"),
    "subRuleNotEmpty": MessageLookupByLibrary.simpleMessage("サブルールは空にできません"),
    "submit": MessageLookupByLibrary.simpleMessage("送信"),
    "subscriptionInfo": MessageLookupByLibrary.simpleMessage("サブスクリプション情報"),
    "suspended": MessageLookupByLibrary.simpleMessage("一時停止中…"),
    "switchProfile": MessageLookupByLibrary.simpleMessage("プロファイルを切り替え"),
    "sync": MessageLookupByLibrary.simpleMessage("同期"),
    "system": MessageLookupByLibrary.simpleMessage("システム"),
    "systemApp": MessageLookupByLibrary.simpleMessage("システムアプリ"),
    "systemProxy": MessageLookupByLibrary.simpleMessage("システムプロキシ"),
    "tab": MessageLookupByLibrary.simpleMessage("タブ"),
    "tabAnimation": MessageLookupByLibrary.simpleMessage("タブアニメーション"),
    "tapToAuthorize": MessageLookupByLibrary.simpleMessage("タップして許可"),
    "tcpConcurrent": MessageLookupByLibrary.simpleMessage("TCP同時接続"),
    "testInterval": MessageLookupByLibrary.simpleMessage("テスト間隔"),
    "testUrl": MessageLookupByLibrary.simpleMessage("テストURL"),
    "testWhenUsed": MessageLookupByLibrary.simpleMessage("使用時にテスト"),
    "textScale": MessageLookupByLibrary.simpleMessage("テキストの拡大縮小"),
    "textScalePreview": MessageLookupByLibrary.simpleMessage(
      "アプリ内の文字はこの大きさで表示されます",
    ),
    "theme": MessageLookupByLibrary.simpleMessage("テーマ"),
    "themeColor": MessageLookupByLibrary.simpleMessage("テーマカラー"),
    "themeDesc": MessageLookupByLibrary.simpleMessage("ダークモードの設定と色の調整"),
    "themeMode": MessageLookupByLibrary.simpleMessage("テーマモード"),
    "tight": MessageLookupByLibrary.simpleMessage("コンパクト"),
    "time": MessageLookupByLibrary.simpleMessage("時刻"),
    "timeout": MessageLookupByLibrary.simpleMessage("タイムアウト"),
    "tip": MessageLookupByLibrary.simpleMessage("ヒント"),
    "toggle": MessageLookupByLibrary.simpleMessage("切り替え"),
    "tolerance": MessageLookupByLibrary.simpleMessage("許容値"),
    "tonalSpotScheme": MessageLookupByLibrary.simpleMessage("トーナルスポット"),
    "tools": MessageLookupByLibrary.simpleMessage("ツール"),
    "torch": MessageLookupByLibrary.simpleMessage("ライト"),
    "total": MessageLookupByLibrary.simpleMessage("合計"),
    "totalTraffic": MessageLookupByLibrary.simpleMessage("合計トラフィック"),
    "tproxyPort": MessageLookupByLibrary.simpleMessage("TProxyポート"),
    "trafficUsage": MessageLookupByLibrary.simpleMessage("トラフィック統計"),
    "tun": MessageLookupByLibrary.simpleMessage("TUN"),
    "tunDesc": MessageLookupByLibrary.simpleMessage("管理者モードでのみ有効"),
    "turnOff": MessageLookupByLibrary.simpleMessage("オフにする"),
    "turnOn": MessageLookupByLibrary.simpleMessage("オンにする"),
    "undo": MessageLookupByLibrary.simpleMessage("元に戻す"),
    "unifiedDelay": MessageLookupByLibrary.simpleMessage("統一遅延"),
    "unknown": MessageLookupByLibrary.simpleMessage("不明"),
    "unknownNetworkError": MessageLookupByLibrary.simpleMessage("不明なネットワークエラー"),
    "unmaximize": MessageLookupByLibrary.simpleMessage("元に戻す"),
    "unnamed": MessageLookupByLibrary.simpleMessage("名称未設定"),
    "unpinWindow": MessageLookupByLibrary.simpleMessage("固定を解除"),
    "update": MessageLookupByLibrary.simpleMessage("更新"),
    "upload": MessageLookupByLibrary.simpleMessage("アップロード"),
    "url": MessageLookupByLibrary.simpleMessage("URL"),
    "urlDesc": MessageLookupByLibrary.simpleMessage("URLからプロファイルを取得します"),
    "urlTip": m89,
    "useHosts": MessageLookupByLibrary.simpleMessage("Hostsを使用"),
    "useProfile": MessageLookupByLibrary.simpleMessage("使用"),
    "useSystemHosts": MessageLookupByLibrary.simpleMessage("システムのHostsを使用"),
    "usedTraffic": MessageLookupByLibrary.simpleMessage("使用済みトラフィック"),
    "userAgent": MessageLookupByLibrary.simpleMessage("User-Agent"),
    "value": MessageLookupByLibrary.simpleMessage("値"),
    "vibrantScheme": MessageLookupByLibrary.simpleMessage("ビブラント"),
    "view": MessageLookupByLibrary.simpleMessage("表示"),
    "vpnConfigChangeDetected": MessageLookupByLibrary.simpleMessage(
      "VPN関連の設定変更を検出しました",
    ),
    "vpnEnableDesc": MessageLookupByLibrary.simpleMessage(
      "VpnServiceでシステムの全トラフィックを自動的にルーティングします",
    ),
    "vpnTip": MessageLookupByLibrary.simpleMessage("変更はVPNの再起動後に有効になります"),
    "webDAVConfiguration": MessageLookupByLibrary.simpleMessage("WebDAV設定"),
    "whitelistMode": MessageLookupByLibrary.simpleMessage("ホワイトリストモード"),
    "writeToSystem": MessageLookupByLibrary.simpleMessage("システムに書き込む"),
    "writeToSystemDesc": MessageLookupByLibrary.simpleMessage(
      "システムクロックも設定します。Androidでは無視されます",
    ),
    "yearsAgo": m90,
    "yes": MessageLookupByLibrary.simpleMessage("はい"),
    "zhCN": MessageLookupByLibrary.simpleMessage("簡体字中国語"),
  };
}
