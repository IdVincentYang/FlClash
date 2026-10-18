part of 'config.dart';

final _applicationPublicationKey = Object();

class _ApplicationPublication {
  bool active = true;
}

void _publishApplicationInputs(Request client, void Function() publish) {
  if (!client.applicationInputsInvalidated) {
    throw const RequestUnavailable('application_input_commit_required');
  }
  final publication = _ApplicationPublication();
  try {
    runZoned(publish, zoneValues: {_applicationPublicationKey: publication});
  } finally {
    publication.active = false;
  }
}

mixin _ApplicationInputGuard<T> on AutoDisposeNotifierMixin<T> {
  bool inputChanged(T previous, T next) => previous != next;

  @override
  set value(T next) {
    if (inputChanged(value, next)) {
      final publication = Zone.current[_applicationPublicationKey];
      if (publication is! _ApplicationPublication || !publication.active) {
        throw const RequestUnavailable('application_input_commit_required');
      }
    }
    super.value = next;
  }
}

@Riverpod(keepAlive: true)
class ApplicationInputAction extends _$ApplicationInputAction {
  @protected
  Request get requestClient => request;

  @override
  void build() {}

  Future<void> updatePatch(
    PatchClashConfig Function(PatchClashConfig) update,
  ) => _change(
    () => ref.read(patchClashConfigProvider),
    (value) => ref.read(patchClashConfigProvider.notifier).value = value,
    update,
    validate: (previous, next, managed) {
      if (!managed) return;
      final unchanged = next.copyWith(
        logLevel: previous.logLevel,
        tcpConcurrent: previous.tcpConcurrent,
        unifiedDelay: previous.unifiedDelay,
        tun: previous.tun,
        interfaceName: previous.interfaceName,
        interfaceNameMode: previous.interfaceNameMode,
        mode: previous.mode,
      );
      if (unchanged != previous ||
          next.mode != previous.mode && next.mode != Mode.rule ||
          next.interfaceNameMode == InterfaceNameMode.follow) {
        throw const RequestUnavailable('managed_policy_edit_required');
      }
    },
  );

  Future<void> updateNetwork(NetworkProps Function(NetworkProps) update) =>
      _change(
        () => ref.read(networkSettingProvider),
        (value) => ref.read(networkSettingProvider.notifier).value = value,
        update,
      );

  Future<void> updateVpn(VpnProps Function(VpnProps) update) => _change(
    () => ref.read(vpnSettingProvider),
    (value) => ref.read(vpnSettingProvider.notifier).value = value,
    update,
  );

  Future<void> updateGeoUrl(GeoResource resource, String url) => _change(
    () => ref.read(patchClashConfigProvider),
    (value) => ref.read(patchClashConfigProvider.notifier).value = value,
    (previous) =>
        previous.copyWith(geoXUrl: {...previous.geoXUrl, resource: url}),
    validate: (_, _, managed) {
      if (managed) {
        throw const RequestUnavailable('managed_policy_edit_required');
      }
    },
    beforePublish: () => requestClient.invalidate('geo:${resource.name}'),
  );

  Future<void> updateAppSetting(
    AppSettingProps Function(AppSettingProps) update,
  ) => _change(
    () => ref.read(appSettingProvider),
    (value) => ref.read(appSettingProvider.notifier).value = value,
    update,
  );

  Future<void> setOverrideDns(bool value) => _change(
    () => ref.read(overrideDnsProvider),
    (value) => ref.read(overrideDnsProvider.notifier).value = value,
    (_) => value,
    validate: _validateOverride,
  );

  Future<void> setOverrideNtp(bool value) => _change(
    () => ref.read(overrideNtpProvider),
    (value) => ref.read(overrideNtpProvider.notifier).value = value,
    (_) => value,
    validate: _validateOverride,
  );

  void _validateOverride(bool previous, bool next, bool managed) {
    if (managed && previous != next) {
      throw const RequestUnavailable('managed_policy_edit_required');
    }
  }

  Future<void> _change<T>(
    T Function() read,
    void Function(T) publish,
    T Function(T) update, {
    void Function(T previous, T next, bool managed)? validate,
    Future<void> Function()? beforePublish,
  }) async {
    var managed = false;
    var changed = false;
    ConfigFailureObservation? failure;
    final setup = ref.read(setupActionProvider.notifier);
    try {
      await requestClient.mutate(() async {
        final profileId = ref.read(currentProfileIdProvider);
        managed =
            profileId != null &&
            await database.profilePolicySelectionsDao
                    .query(profileId)
                    .getSingleOrNull() !=
                null;
        final previous = read();
        final next = update(previous);
        if (previous == next) return;
        validate?.call(previous, next, managed);
        failure = await setup.captureConfigFailure(requestClient);
        await beforePublish?.call();
        await requestClient.invalidate('application-config');
        try {
          _publishApplicationInputs(requestClient, () => publish(next));
          if (!await preferences.saveConfig(ref.read(configProvider))) {
            throw const RequestUnavailable('preferences_save_failed');
          }
        } catch (_) {
          var compensated = false;
          try {
            _publishApplicationInputs(requestClient, () => publish(previous));
            compensated = await preferences.saveConfig(
              ref.read(configProvider),
            );
          } catch (_) {}
          if (!compensated) {
            try {
              await requestClient.markPartialCommit();
            } catch (_) {
              throw const RequestUnavailable('request_partial_commit');
            }
            throw const RequestUnavailable('request_partial_commit');
          }
          throw const RequestUnavailable('preferences_save_failed');
        }
        changed = true;
      });
    } catch (_) {
      final observation = failure;
      if (observation != null) await setup.finishConfigFailure(observation);
      rethrow;
    }
    if (changed && ref.mounted && ref.read(initProvider)) {
      final setup = ref.read(setupActionProvider.notifier);
      if (managed) {
        await setup.applyProfile(force: true);
      } else {
        await setup.updateConfigDebounce();
      }
    }
  }
}
