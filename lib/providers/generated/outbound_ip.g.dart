// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../outbound_ip.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(OutboundIpProbe)
final outboundIpProbeProvider = OutboundIpProbeProvider._();

final class OutboundIpProbeProvider
    extends
        $NotifierProvider<OutboundIpProbe, RoutedProbeState<String, IpInfo>> {
  OutboundIpProbeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'outboundIpProbeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$outboundIpProbeHash();

  @$internal
  @override
  OutboundIpProbe create() => OutboundIpProbe();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RoutedProbeState<String, IpInfo> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RoutedProbeState<String, IpInfo>>(
        value,
      ),
    );
  }
}

String _$outboundIpProbeHash() => r'016b9eeb12483f5d6c52ace67895b770e9a73f7d';

abstract class _$OutboundIpProbe
    extends $Notifier<RoutedProbeState<String, IpInfo>> {
  RoutedProbeState<String, IpInfo> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              RoutedProbeState<String, IpInfo>,
              RoutedProbeState<String, IpInfo>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                RoutedProbeState<String, IpInfo>,
                RoutedProbeState<String, IpInfo>
              >,
              RoutedProbeState<String, IpInfo>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
