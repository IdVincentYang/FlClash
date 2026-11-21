import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/core/geo_seed.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/models/config_state.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:path/path.dart';

class CoreController {
  static CoreController? _instance;
  late CoreHandlerInterface _interface;
  final ({String homePath, AssetBundle assets, bool android})? _seedFixture;

  CoreController._internal() : _seedFixture = null {
    if (system.isAndroid) {
      _interface = coreLib!;
    } else {
      _interface = coreService!;
    }
  }

  @visibleForTesting
  CoreController.test(this._interface) : _seedFixture = null {
    _instance = this;
  }

  @visibleForTesting
  CoreController.scoped(this._interface) : _seedFixture = null;

  @visibleForTesting
  CoreController.forSeedTesting(
    this._interface, {
    required String homePath,
    required AssetBundle assets,
    required bool isAndroid,
  }) : _seedFixture = (homePath: homePath, assets: assets, android: isAndroid);

  @visibleForTesting
  static void resetInstance() {
    _instance = null;
  }

  factory CoreController() {
    _instance ??= CoreController._internal();
    return _instance!;
  }

  Future<CoreLifecycleResult> start() => _interface.start();

  Future<CoreLifecycleResult> restart() => _interface.restart();

  Future<CoreLifecycleResult> stop() => _interface.stop();

  Future<CoreLifecycleResult> close() => _interface.close();

  static Future<void> ensureHomeDir() async {
    final homePath = await appPath.homeDirPath;
    final homeDir = Directory(homePath);
    final isExists = await homeDir.exists();
    if (!isExists) {
      await homeDir.create(recursive: true);
    }
    await system.grantHomeDirAccess(homePath);
  }

  static Future<void> initGeo() async {
    await _seedGeo(await appPath.homeDirPath, rootBundle, system.isAndroid);
  }

  static Future<void> _seedGeo(
    String homePath,
    AssetBundle assets,
    bool isAndroid,
  ) async {
    const geoFileNameList = [MMDB, GEOIP, GEOSITE, ASN];
    GeoSeedReference? reference;
    try {
      for (final geoFileName in geoFileNameList) {
        final geoFile = File(join(homePath, geoFileName));
        final isExists = await geoFile.exists();
        if (isExists) {
          continue;
        }
        final data = await assets.load('assets/data/$geoFileName');
        await dataMutations.run(() async {
          if (await geoFile.exists()) return;
          if (isAndroid) {
            reference ??= GeoSeedReference.fromAsset(
              await assets.load(GeoSeedReference.manifestAsset),
            );
          }
          final bytes = isAndroid
              ? reference!.verifiedBytes(geoFileName, data)
              : data.buffer.asUint8List();
          final staged = File('${geoFile.path}.seed');
          try {
            await staged.writeAsBytes(bytes, flush: true);
            await staged.rename(geoFile.path);
          } finally {
            await staged.safeDelete();
          }
        });
      }
    } catch (e) {
      commonPrint.log(
        'Failed to initialize geo data: $e',
        logLevel: LogLevel.error,
      );
      rethrow;
    }
  }

  Future<bool> init(int version) async {
    final fixture = _seedFixture;
    if (fixture == null) {
      await ensureHomeDir();
      await initGeo();
    } else {
      await Directory(fixture.homePath).create(recursive: true);
      await _seedGeo(fixture.homePath, fixture.assets, fixture.android);
    }
    final homeDirPath = fixture?.homePath ?? await appPath.homeDirPath;
    return _interface.init(InitParams(homeDir: homeDirPath, version: version));
  }

  FutureOr<bool> get isInit => _interface.isInit;

  Future<ConfigFact> getConfigState() => _interface.getConfigState();

  Future<Map<String, dynamic>> sourceAcceptance(Map<String, Object?> input) =>
      _interface.sourceAcceptance(input);

  Future<void> releaseConfigInput(String markerName) =>
      _interface.releaseConfigInput(markerName);

  Future<ConfigApplyResult> applyConfigInput(Map<String, Object?> input) =>
      _interface.applyConfigInput(input);

  Future<ConfigApplyResult> failConfigBuild(Map<String, Object?> input) =>
      _interface.failConfigBuild(input);

  Future<String> validateConfig(String path) async {
    final res = await _interface.validateConfig(path);
    return res;
  }

  Future<List<String>> validateProxies(List<Map<String, dynamic>> proxies) {
    if (proxies.isEmpty) {
      return Future.value(const []);
    }
    return _interface.validateProxies(proxies);
  }

  Future<String> validateConfigWithData(String data) async {
    final path = await appPath.tempFilePath;
    final file = File(path);
    await file.safeWriteAsString(data);
    final res = await _interface.validateConfig(path);
    await File(path).safeDelete();
    return res;
  }

  Future<String> updateApplicationRouting(Map<String, dynamic> settings) =>
      _interface.updateApplicationRouting(settings);

  Future<String> updateConfig(UpdateParams updateParams) async {
    return _interface.updateConfig(updateParams);
  }

  Future<String> setupConfig({required SetupParams params}) =>
      _interface.setupConfig(params);

  Future<List<Group>> getProxiesGroups({
    required ProxiesSortType sortType,
    required DelayMap delayMap,
    required Map<String, String> selectedMap,
    required String defaultTestUrl,
  }) async {
    final proxiesData = await _interface.getProxies();
    return toGroupsTask(
      ComputeGroupsState(
        proxiesData: proxiesData,
        sortType: sortType,
        delayMap: delayMap,
        selectedMap: selectedMap,
        defaultTestUrl: defaultTestUrl,
      ),
    );
  }

  Future<ChangeProxyResult> changeProxy(ChangeProxyParams changeProxyParams) {
    return _interface.changeProxy(changeProxyParams);
  }

  Future<RouteSnapshot?> watchRoute(bool watch) {
    return _interface.watchRoute(watch);
  }

  Future<List<TrackerInfo>> getConnections() async {
    return _interface.getConnections();
  }

  Future<int> getConnectionCount() async {
    return _interface.getConnectionCount();
  }

  Future<void> closeConnection(String id) async {
    await _interface.closeConnection(id);
  }

  Future<void> closeConnections() async {
    await _interface.closeConnections();
  }

  Future<void> resetConnections() async {
    await _interface.resetConnections();
  }

  Future<List<ExternalProvider>> getExternalProviders() async {
    return _interface.getExternalProviders();
  }

  Future<ExternalProvider?> getExternalProvider(
    String externalProviderName,
  ) async {
    return _interface.getExternalProvider(externalProviderName);
  }

  Future<String> updateGeoData(String type) {
    return _interface.updateGeoData(type);
  }

  Future<String> sideLoadExternalProvider({
    required String providerName,
    required String data,
  }) {
    return _interface.sideLoadExternalProvider(
      providerName: providerName,
      data: data,
    );
  }

  Future<String> dumpRuleSet(String path) {
    return _interface.dumpRuleSet(path);
  }

  Future<String> updateExternalProvider({required String providerName}) async {
    return _interface.updateExternalProvider(providerName);
  }

  Future<bool> startListener() async {
    return _interface.startListener();
  }

  Future<bool> stopListener() async {
    return _interface.stopListener();
  }

  Future<Delay?> getDelay(String url, String proxyName) async {
    return _interface.asyncTestDelay(url, proxyName);
  }

  Future<ProbeResult?> probe(ProbeParams params) => _interface.probe(params);

  Future<Map<String, String>> lookupIpCountries(List<String> ips) =>
      _interface.lookupIpCountries(ips);

  Future<OutboundIpResult?> outboundIp(OutboundIpParams params) =>
      _interface.outboundIp(params);

  Future<List<ServiceCheckItem>> serviceCheck(ServiceCheckParams params) =>
      _interface.serviceCheck(params);

  Future<Map<String, dynamic>> getConfig(int id) async {
    return _readConfig(await appPath.getProfilePath(id.toString()));
  }

  Future<Map<String, dynamic>> getConfigPath(String path) => _readConfig(path);

  Future<Map<String, dynamic>> getAppliedConfig() async {
    final result = await _interface.invokeMethod<Map<String, dynamic>>(
      method: CoreMethod.getAppliedInput,
    );
    if (result == null) throw StateError('Applied configuration unavailable');
    return result;
  }

  Future<Map<String, dynamic>> _readConfig(String path) async {
    final data = Map<String, dynamic>.from(await _interface.getConfig(path));
    data['rules'] = data['rule'];
    data.remove('rule');
    return data;
  }

  Future<Traffic> getTraffic(bool onlyStatisticsProxy) async {
    return _interface.getTraffic(onlyStatisticsProxy);
  }

  Future<Traffic> getTotalTraffic(bool onlyStatisticsProxy) async {
    return _interface.getTotalTraffic(onlyStatisticsProxy);
  }

  Future<CoreMemoryStats?> getMemoryStats() async {
    return _interface.getMemoryStats();
  }

  void resetTraffic() {
    _interface.resetTraffic();
  }

  void startLog() {
    _interface.startLog();
  }

  void stopLog() {
    _interface.stopLog();
  }

  Future<void> requestGc() async {
    await _interface.forceGc();
  }

  Future<void> crash() async {
    await _interface.crash();
  }

  Future<String> clearEffect(int profileId) async {
    return _interface.clearEffect(profileId);
  }
}

final coreController = CoreController();
