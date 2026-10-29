// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../ip_quality.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(IpQualityProbe)
final ipQualityProbeProvider = IpQualityProbeProvider._();

final class IpQualityProbeProvider
    extends
        $NotifierProvider<IpQualityProbe, RoutedProbeState<String, IpQuality>> {
  IpQualityProbeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ipQualityProbeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ipQualityProbeHash();

  @$internal
  @override
  IpQualityProbe create() => IpQualityProbe();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RoutedProbeState<String, IpQuality> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RoutedProbeState<String, IpQuality>>(
        value,
      ),
    );
  }
}

String _$ipQualityProbeHash() => r'b2ddb63af5757df69a71f0ae74d7a26c7745a167';

abstract class _$IpQualityProbe
    extends $Notifier<RoutedProbeState<String, IpQuality>> {
  RoutedProbeState<String, IpQuality> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              RoutedProbeState<String, IpQuality>,
              RoutedProbeState<String, IpQuality>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                RoutedProbeState<String, IpQuality>,
                RoutedProbeState<String, IpQuality>
              >,
              RoutedProbeState<String, IpQuality>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
