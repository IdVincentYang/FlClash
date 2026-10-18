part of '../action.dart';

@Riverpod(keepAlive: true)
class GeoResourceAction extends _$GeoResourceAction {
  final _manualUpdates = <GeoResource>{};
  final _operations = <GeoResource, int>{};

  CoreController get _core => ref.read(coreHandlerProvider);

  @override
  void build() {
    ref.listen(coreStatusProvider, (_, next) {
      if (next != CoreStatus.connected) {
        _manualUpdates.clear();
        _operations.clear();
      }
    });
  }

  int _startUpdating(GeoResource geoResource) {
    return _operations.putIfAbsent(
      geoResource,
      () => ref
          .read(updatingKeysProvider.notifier)
          .start(geoResource.updatingKey, scope: UpdatingScope.core),
    );
  }

  void _stopUpdating(GeoResource geoResource, [int? operation]) {
    final current = _operations[geoResource];
    if (current == null || (operation != null && current != operation)) {
      return;
    }
    _operations.remove(geoResource);
    ref
        .read(updatingKeysProvider.notifier)
        .stop(geoResource.updatingKey, current);
  }

  /// Completes once the Core has accepted the update, not once it finishes.
  /// Completion arrives as a geo-update event through [handleCoreUpdate];
  /// callers that need it watch [isUpdatingProvider] for the key to clear.
  Future<void> updateGeoResource(GeoResource geoResource) async {
    if (!system.isAndroid) {
      _manualUpdates.add(geoResource);
      final operation = _startUpdating(geoResource);
      try {
        final message = await _core.updateGeoData(geoResource.name);
        if (message.isNotEmpty) throw MessageException(message);
      } catch (_) {
        _manualUpdates.remove(geoResource);
        _stopUpdating(geoResource, operation);
        rethrow;
      }
      return;
    }
    final operation = _startUpdating(geoResource);
    RequestSession? session;
    try {
      final url =
          ref.read(patchClashConfigProvider).geoXUrl[geoResource] ??
          defaultGeoXUrl[geoResource]!;
      session = await request.begin(key: 'geo:${geoResource.name}', url: url);
      final message = await session.run(
        () => _core.updateGeoData(geoResource.name),
      );
      if (message.isNotEmpty) throw MessageException(message);
      await session.check();
      dialogs.showNotifier(
        currentAppLocalizations.geoUpdated(geoResource.name),
      );
    } finally {
      session?.close();
      _stopUpdating(geoResource, operation);
    }
  }

  void handleCoreUpdate(
    String geoType,
    bool updating,
    bool skipped,
    String? error,
  ) {
    final geoResource = GeoResource.fromJson(geoType.toLowerCase());
    final shouldNotify = !updating && _manualUpdates.remove(geoResource);
    if (shouldNotify) {
      if (error == null || error.isEmpty) {
        final l10n = currentAppLocalizations;
        final message = skipped
            ? l10n.geoSkipped(geoResource.name)
            : l10n.geoUpdated(geoResource.name);
        dialogs.showNotifier(message);
      } else {
        dialogs.showNotifier(error, level: MessageLevel.error);
      }
    }
    if (updating) {
      _startUpdating(geoResource);
    } else {
      _stopUpdating(geoResource);
    }
  }

  Future<void> updateGeoResourceUrl(
    GeoResource geoResource,
    String newUrl,
  ) async {
    if (!newUrl.isUrl) {
      throw ArgumentError.value(newUrl, 'newUrl', 'Not a valid URL');
    }
    await ref
        .read(applicationInputActionProvider.notifier)
        .updateGeoUrl(geoResource, newUrl);
  }
}
