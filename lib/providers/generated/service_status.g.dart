// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../service_status.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ServiceStatus)
final serviceStatusProvider = ServiceStatusProvider._();

final class ServiceStatusProvider
    extends
        $NotifierProvider<
          ServiceStatus,
          RoutedProbeState<ServiceProbeKey, ServiceCheck>
        > {
  ServiceStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'serviceStatusProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$serviceStatusHash();

  @$internal
  @override
  ServiceStatus create() => ServiceStatus();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(
    RoutedProbeState<ServiceProbeKey, ServiceCheck> value,
  ) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<RoutedProbeState<ServiceProbeKey, ServiceCheck>>(
            value,
          ),
    );
  }
}

String _$serviceStatusHash() => r'f17881e1f13946223167944341aeaa77494bd7df';

abstract class _$ServiceStatus
    extends $Notifier<RoutedProbeState<ServiceProbeKey, ServiceCheck>> {
  RoutedProbeState<ServiceProbeKey, ServiceCheck> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              RoutedProbeState<ServiceProbeKey, ServiceCheck>,
              RoutedProbeState<ServiceProbeKey, ServiceCheck>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                RoutedProbeState<ServiceProbeKey, ServiceCheck>,
                RoutedProbeState<ServiceProbeKey, ServiceCheck>
              >,
              RoutedProbeState<ServiceProbeKey, ServiceCheck>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(serviceTargets)
final serviceTargetsProvider = ServiceTargetsProvider._();

final class ServiceTargetsProvider
    extends
        $FunctionalProvider<
          List<ServiceTarget>,
          List<ServiceTarget>,
          List<ServiceTarget>
        >
    with $Provider<List<ServiceTarget>> {
  ServiceTargetsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'serviceTargetsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$serviceTargetsHash();

  @$internal
  @override
  $ProviderElement<List<ServiceTarget>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<ServiceTarget> create(Ref ref) {
    return serviceTargets(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<ServiceTarget> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<ServiceTarget>>(value),
    );
  }
}

String _$serviceTargetsHash() => r'f1c9ae92b6d0c5b7fcf72c90571ff1c67f7ca66e';

@ProviderFor(enabledServiceTargets)
final enabledServiceTargetsProvider = EnabledServiceTargetsProvider._();

final class EnabledServiceTargetsProvider
    extends
        $FunctionalProvider<
          List<ServiceTarget>,
          List<ServiceTarget>,
          List<ServiceTarget>
        >
    with $Provider<List<ServiceTarget>> {
  EnabledServiceTargetsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'enabledServiceTargetsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$enabledServiceTargetsHash();

  @$internal
  @override
  $ProviderElement<List<ServiceTarget>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<ServiceTarget> create(Ref ref) {
    return enabledServiceTargets(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<ServiceTarget> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<ServiceTarget>>(value),
    );
  }
}

String _$enabledServiceTargetsHash() =>
    r'ec0b9a985bc1f826b102f3bf01861152a4e2d692';
