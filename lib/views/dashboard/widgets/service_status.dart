import 'dart:math';
import 'dart:ui';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/icons/icons.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:fl_clash/providers/service_status.dart';
import 'package:fl_clash/views/dashboard/probe_start_hold.dart';
import 'package:fl_clash/views/dashboard/widget_metrics.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

String _statusLabel(BuildContext context, ServiceProbeStatus status) {
  final localizations = context.appLocalizations;
  return switch (status) {
    ServiceProbeStatus.available => localizations.serviceResponded,
    ServiceProbeStatus.redirected => localizations.serviceRedirected,
    ServiceProbeStatus.httpResponse => localizations.serviceHttpResponse,
    ServiceProbeStatus.observed => localizations.serviceObserved,
    ServiceProbeStatus.restricted => localizations.serviceRestricted,
    ServiceProbeStatus.unavailable => localizations.serviceUnavailable,
    ServiceProbeStatus.disallowedIsp => localizations.serviceDisallowedIsp,
    ServiceProbeStatus.blocked => localizations.serviceBlocked,
    ServiceProbeStatus.unsupportedRegion =>
      localizations.serviceUnsupportedRegion,
    ServiceProbeStatus.originalsOnly => localizations.serviceOriginalsOnly,
    ServiceProbeStatus.comingSoon => localizations.serviceComingSoon,
    ServiceProbeStatus.timeout => localizations.timeout,
    ServiceProbeStatus.failed => localizations.serviceFailed,
  };
}

Color _statusColor(BuildContext context, ServiceProbeStatus status) {
  return switch (status) {
    ServiceProbeStatus.available => context.colorScheme.success,
    ServiceProbeStatus.observed => context.colorScheme.onSurfaceVariant,
    ServiceProbeStatus.redirected ||
    ServiceProbeStatus.httpResponse => context.colorScheme.warning,
    ServiceProbeStatus.restricted ||
    ServiceProbeStatus.disallowedIsp ||
    ServiceProbeStatus.blocked ||
    ServiceProbeStatus.unsupportedRegion ||
    ServiceProbeStatus.originalsOnly ||
    ServiceProbeStatus.comingSoon => context.colorScheme.warning,
    ServiceProbeStatus.unavailable ||
    ServiceProbeStatus.timeout ||
    ServiceProbeStatus.failed => context.colorScheme.error,
  };
}

(String, Color) _statusOf(
  BuildContext context,
  ServiceCheck? check,
  ProbePhase phase, {
  bool expired = false,
}) {
  final localizations = context.appLocalizations;
  if (phase == ProbePhase.queued) {
    return (localizations.serviceQueued, context.colorScheme.onSurfaceVariant);
  }
  if (phase == ProbePhase.probing) {
    return (localizations.loading, context.colorScheme.onSurfaceVariant);
  }
  if (expired && check == null) {
    return (localizations.serviceRouteChanged, context.colorScheme.warning);
  }
  if (check != null) {
    final label =
        check.status == ServiceProbeStatus.failed && check.reason.isNotEmpty
        ? _serviceReason(context, check.reason)
        : _statusLabel(context, check.status);
    return (
      expired
          ? localizations.serviceExpired(label)
          : '$label${check.httpStatus > 0 && check.purpose == ServiceProbePurpose.basic ? ' · HTTP ${check.httpStatus}' : ''}',
      expired
          ? context.colorScheme.warning
          : _statusColor(context, check.status),
    );
  }
  if (phase == ProbePhase.failed) {
    return (
      _statusLabel(context, ServiceProbeStatus.failed),
      _statusColor(context, ServiceProbeStatus.failed),
    );
  }
  return (localizations.servicePending, context.colorScheme.onSurfaceVariant);
}

class ServiceStatusCard extends ConsumerStatefulWidget {
  const ServiceStatusCard({super.key});

  @override
  ConsumerState<ServiceStatusCard> createState() => _ServiceStatusCardState();
}

class _ServiceStatusCardState extends ConsumerState<ServiceStatusCard>
    with ProbeStartHold<ServiceStatusCard> {
  static const _gap = 12.0;
  // The badge sits the same distance from the start, top and bottom edges. At
  // this inset a concentric radius would square it off, so it takes the card's
  // own proportion of radius to height instead.
  static const _badgeInsetShare = 0.7;

  late final PageController _controller;
  late final ServiceStatus _services;
  ServiceTarget? _shown;
  bool _scrolling = false;

  static ServiceTarget? _savedIn(List<ServiceTarget> targets, String? id) {
    final saved = id == null ? null : ServiceTarget.byId(id);
    return saved != null && targets.contains(saved)
        ? saved
        : targets.firstOrNull;
  }

  ServiceTarget? _targetIn(List<ServiceTarget> targets) =>
      _savedIn(targets, ref.read(appSettingProvider).currentService);

  void _select(ServiceTarget target) {
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(currentService: target.id));
  }

  @override
  void initState() {
    super.initState();
    _services = ref.read(serviceStatusProvider.notifier);
    final targets = ref.read(enabledServiceTargetsProvider);
    _controller = PageController(
      initialPage: max(
        0,
        targets.indexWhere((target) => target == _targetIn(targets)),
      ),
    );
  }

  @override
  void dispose() {
    _show(null);
    _controller.dispose();
    super.dispose();
  }

  void _show(ServiceTarget? target) {
    final previous = _shown;
    if (target == previous) return;
    _shown = target;
    if (target != null) _services.watch(target.basic);
    if (previous != null) _services.unwatch(previous.basic);
  }

  void _onTargetChanged(List<ServiceTarget> targets, int index) {
    final target = targets[index];
    if (target == _targetIn(targets)) return;
    _select(target);
  }

  /// A swipe or an animated jump passes through the services in between; only
  /// the one the pager settles on is worth a check.
  bool _onPagerScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification) {
      _scrolling = true;
    } else if (notification is ScrollEndNotification) {
      _show(_targetIn(ref.read(enabledServiceTargetsProvider)));
      if (mounted) setState(() => _scrolling = false);
    }
    return false;
  }

  void _onTargetsChanged(
    List<ServiceTarget>? previous,
    List<ServiceTarget> next,
  ) {
    if (next.isEmpty) {
      _show(null);
      return;
    }
    final current = _targetIn(previous ?? next);
    final kept = next.contains(current);
    final index = kept
        ? next.indexWhere((target) => target == current)
        : (previous?.indexWhere((target) => target == current) ?? 0).clamp(
            0,
            next.length - 1,
          );
    _select(next[index]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      if (_controller.page?.round() != index) _controller.jumpToPage(index);
    });
  }

  Future<void> _openSheet() async {
    final picked = await showServiceStatusSheet(context);
    if (picked == null || !mounted) return;
    final targets = ref.read(enabledServiceTargetsProvider);
    final index = targets.indexOf(picked);
    if (index < 0 || picked == _targetIn(targets)) return;
    await _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  /// Only a service the pager has settled on is checked, so one still being
  /// swiped past shows a result only if it is already current.
  bool _isLoading(ProbePhase phase, {required bool settled}) =>
      phase == ProbePhase.probing ||
      ((_scrolling || !settled) && phase != ProbePhase.fresh);

  Widget _buildPage(
    ServiceTarget target, {
    required bool settled,
    required double badgeSize,
    required double badgeRadius,
  }) {
    return Consumer(
      builder: (context, ref, _) {
        final entry = ref.watch(
          serviceStatusProvider.select((state) => state.entryOf(target.basic)),
        );
        final phase = settled ? shownPhase(entry) : entry.phase;
        final loading = _isLoading(phase, settled: settled);
        final check = entry.value;
        final node = check?.node;
        final (label, color) = _statusOf(
          context,
          check,
          phase,
          expired: entry.expired,
        );
        return _ServicePage(
          target: target,
          badgeSize: badgeSize,
          badgeRadius: badgeRadius,
          label: label,
          color: color,
          loading: loading,
          node: node,
          checkedAt: check?.checkedAt,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(enabledServiceTargetsProvider, _onTargetsChanged);
    final targets = ref.watch(enabledServiceTargetsProvider);
    if (targets.isEmpty) {
      _show(null);
      return SizedBox(
        height: DashboardWidgetMetrics.heightOf(context, 1),
        child: CommonCard(
          radius: DashboardWidgetMetrics.radiusOf(context),
          onPressed: _openSheet,
          child: Center(
            child: Text(context.appLocalizations.serviceAllDisabled),
          ),
        ),
      );
    }
    final target = _savedIn(
      targets,
      ref.watch(appSettingProvider.select((state) => state.currentService)),
    )!;
    if (!_scrolling) _show(target);
    final entry = ref.watch(
      serviceStatusProvider.select((state) => state.entryOf(target.basic)),
    );
    final check = entry.value;
    final loading = _isLoading(shownPhase(entry), settled: true);

    final inset = DashboardWidgetMetrics.insetOf(context);
    final height = DashboardWidgetMetrics.heightOf(context, 1);
    final badgeInset =
        DashboardWidgetMetrics.radiusOf(context) * _badgeInsetShare;
    final badgeSize = height - badgeInset * 2;
    final badgeRadius =
        badgeSize * DashboardWidgetMetrics.radiusOf(context) / height;
    final index = targets.indexOf(target);
    return SizedBox(
      height: height,
      child: CommonCard(
        radius: DashboardWidgetMetrics.radiusOf(context),
        onPressed: _openSheet,
        child: Row(
          children: [
            Expanded(
              child: _EdgeFade(
                start: badgeInset,
                end: _gap,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onPagerScroll,
                  child: _ServicePager(
                    controller: _controller,
                    targets: targets,
                    index: index,
                    onChanged: (index) => _onTargetChanged(targets, index),
                    itemBuilder: (context, item) => Padding(
                      padding: EdgeInsetsDirectional.only(
                        start: badgeInset,
                        end: _gap,
                      ),
                      child: _buildPage(
                        item,
                        settled: item == target,
                        badgeSize: badgeSize,
                        badgeRadius: badgeRadius,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsetsDirectional.only(end: inset),
              child: _ServiceAside(
                loading: loading,
                delay: check?.delay,
                controller: _controller,
                count: targets.length,
                index: index,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServicePage extends StatelessWidget {
  const _ServicePage({
    required this.target,
    required this.badgeSize,
    required this.badgeRadius,
    required this.label,
    required this.color,
    required this.loading,
    required this.node,
    required this.checkedAt,
  });

  final ServiceTarget target;
  final double badgeSize;
  final double badgeRadius;
  final String label;
  final Color color;
  final bool loading;
  final String? node;
  final DateTime? checkedAt;

  @override
  Widget build(BuildContext context) {
    final secondary = context.textTheme.bodySmall?.copyWith(
      color: context.colorScheme.onSurfaceVariant,
    );
    return Row(
      spacing: 12,
      children: [
        _ServiceBadge(
          target: target,
          size: badgeSize,
          radius: badgeRadius,
          dot: loading ? context.colorScheme.outlineVariant : color,
        ),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              _ServiceTitle(
                name: target.label,
                style: context.textTheme.titleMedium,
                status: Semantics(
                  liveRegion: true,
                  label: loading ? label : null,
                  child: loading
                      ? SkeletonText(
                          width: 48,
                          style: context.textTheme.labelMedium,
                        )
                      : _StatusPill(label: label, color: color),
                ),
              ),
              if (loading)
                SkeletonText(width: 96, style: secondary)
              else
                Tooltip(
                  message: checkedAt == null
                      ? context.appLocalizations.servicePending
                      : context.appLocalizations.serviceCheckedAt(
                          checkedAt!.showFull,
                        ),
                  child: _NodeLine(node: node, style: secondary),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ServiceTitle extends StatelessWidget {
  const _ServiceTitle({required this.name, required this.status, this.style});

  static const _statusShare = 0.6;

  final String name;
  final Widget status;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      // A Flexible status would cap the name at its own share even when the
      // status is short, so the status takes what it needs up to a limit.
      builder: (context, constraints) => Row(
        spacing: 8,
        children: [
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth * _statusShare,
            ),
            child: status,
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.14),
        shape: AppShape.full,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.labelMedium?.copyWith(color: color),
        ),
      ),
    );
  }
}

class _NodeLine extends StatelessWidget {
  const _NodeLine({this.node, this.style});
  final String? node;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(
    node ?? context.appLocalizations.serviceUnknownRoute,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: style,
  );
}

class _ServiceAside extends StatelessWidget {
  const _ServiceAside({
    required this.loading,
    required this.delay,
    required this.controller,
    required this.count,
    required this.index,
  });

  final bool loading;
  final int? delay;
  final PageController controller;
  final int count;
  final int index;

  /// The pager beside this column must keep its width: a resize mid-swipe
  /// cancels the page animation and lets it settle on the wrong service.
  double _widthOf(BuildContext context, TextSpan widest) {
    final painter = TextPainter(
      text: widest,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return max(width, _PageDots.widthOf(count));
  }

  @override
  Widget build(BuildContext context) {
    final delay = this.delay;
    final numeric = context.textTheme.titleMedium
        ?.adjustSize(2)
        .toSoftBold
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final unit = context.textTheme.labelSmall?.copyWith(
      color: context.colorScheme.onSurfaceVariant,
    );
    TextSpan span(String value) => TextSpan(
      text: value,
      style: numeric,
      children: [TextSpan(text: ' ms', style: unit)],
    );
    return SizedBox(
      width: _widthOf(context, span('0000')),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        spacing: 8,
        children: [
          if (loading)
            SkeletonText(width: 36, style: numeric)
          else if (delay != null)
            Text.rich(span('$delay'), maxLines: 1),
          if (count > 1)
            _PageDots(controller: controller, count: count, index: index),
        ],
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.controller,
    required this.count,
    required this.index,
  });

  static const _window = 7;
  static const _size = 4.0;
  static const _edgeSize = 2.5;
  static const _activeWidth = 12.0;
  static const _spacing = 3.0;

  static double widthOf(int count) {
    if (count < 2) return 0;
    final shown = min(count, _window);
    return (shown - 1) * (_size + _spacing) + _activeWidth;
  }

  final PageController controller;
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final page =
              controller.hasClients && controller.position.hasContentDimensions
              ? controller.page ?? index.toDouble()
              : index.toDouble();
          final shown = min(count, _window);
          final first = (page.round() - _window ~/ 2).clamp(0, count - shown);
          final last = first + shown - 1;
          return SizedBox(
            height: _size,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: _spacing,
              children: [
                for (var i = first; i <= last; i++)
                  _dot(
                    colorScheme,
                    active: (1 - (page - i).abs()).clamp(0.0, 1.0),
                    edge:
                        (i == first && first > 0) ||
                        (i == last && last < count - 1),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _dot(
    ColorScheme colorScheme, {
    required double active,
    required bool edge,
  }) {
    final size = edge ? _edgeSize : _size;
    return SizedBox(
      width: lerpDouble(size, _activeWidth, active),
      height: size,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: Color.lerp(
            colorScheme.outlineVariant,
            colorScheme.primary,
            active,
          ),
          shape: AppShape.full,
        ),
      ),
    );
  }
}

class _EdgeFade extends StatelessWidget {
  const _EdgeFade({
    required this.start,
    required this.end,
    required this.child,
  });

  final double start;
  final double end;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.of(context);
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: AlignmentDirectional.centerStart,
        end: AlignmentDirectional.centerEnd,
        colors: const [
          Colors.transparent,
          Colors.black,
          Colors.black,
          Colors.transparent,
        ],
        stops: [
          0,
          (start / bounds.width).clamp(0.0, 0.5),
          (1 - end / bounds.width).clamp(0.5, 1.0),
          1,
        ],
      ).createShader(bounds, textDirection: textDirection),
      child: child,
    );
  }
}

/// The status dot sits in a notch cleared from the tile rather than on a ring
/// painted in the surface colour, which differs between the card and the rows.
class _ServiceBadge extends StatelessWidget {
  const _ServiceBadge({
    required this.target,
    required this.size,
    this.radius,
    this.dot,
    this.enabled = true,
  });

  static const _glyphShare = 0.56;

  final ServiceTarget target;
  final double size;
  final double? radius;
  final Color? dot;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return CustomPaint(
      size: Size.square(size),
      painter: _BadgePainter(
        color: enabled
            ? colorScheme.secondaryContainer
            : colorScheme.surfaceContainerHighest,
        radius: radius ?? AppCorner.fit(size),
        dot: dot,
        dotRadius: max(size / 10, 4),
        ring: max(size / 16, 2),
      ),
      child: SizedBox.square(
        dimension: size,
        child: Center(
          child: SvgPicture.asset(
            'assets/images/services/${target.icon}.svg',
            width: size * _glyphShare,
            height: size * _glyphShare,
            excludeFromSemantics: true,
            colorFilter: ColorFilter.mode(
              enabled ? colorScheme.onSecondaryContainer : colorScheme.outline,
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
    );
  }
}

class _BadgePainter extends CustomPainter {
  const _BadgePainter({
    required this.color,
    required this.radius,
    required this.dot,
    required this.dotRadius,
    required this.ring,
  });

  final Color color;
  final double radius;
  final Color? dot;
  final double dotRadius;
  final double ring;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final tile = RSuperellipse.fromRectAndRadius(
      bounds,
      Radius.circular(radius),
    );
    final dot = this.dot;
    if (dot == null) {
      canvas.drawRSuperellipse(tile, Paint()..color = color);
      return;
    }
    final center = size.bottomRight(Offset(-dotRadius, -dotRadius));
    canvas
      ..saveLayer(bounds, Paint())
      ..drawRSuperellipse(tile, Paint()..color = color)
      ..drawCircle(
        center,
        dotRadius + ring,
        Paint()..blendMode = BlendMode.clear,
      )
      ..restore()
      ..drawCircle(center, dotRadius, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_BadgePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.dot != dot ||
      oldDelegate.dotRadius != dotRadius ||
      oldDelegate.ring != ring;
}

Future<ServiceTarget?> showServiceStatusSheet(BuildContext context) {
  return showSheet<ServiceTarget>(
    context: context,
    props: nestedPagedSheetProps,
    builder: (_) =>
        NestedPagedSheet(builder: (_) => const ServiceStatusSheet()),
  );
}

/// Lists every enabled service at once, so the card's pager never has to be
/// swiped through to find one. Tapping a row hands it back to the card.
/// The rows read the cache and are only checked on request.
class ServiceStatusSheet extends ConsumerWidget {
  const ServiceStatusSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = ref.watch(enabledServiceTargetsProvider);
    final state = ref.watch(serviceStatusProvider);
    final saved = ServiceTarget.byId(
      ref.watch(appSettingProvider.select((state) => state.currentService)) ??
          '',
    );
    final current = targets.contains(saved) ? saved : targets.firstOrNull;
    final services = ref.read(serviceStatusProvider.notifier);
    final localizations = context.appLocalizations;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: ref.sheetHeight(context, 0.7)),
      child: CommonScaffold(
        title: localizations.serviceStatus,
        iconActions: [
          IconButtonData(
            glyph: AppGlyphs.bolt,
            tooltip: localizations.serviceCheckAll,
            isLoading: targets.any((target) => state.isLoading(target.basic)),
            onPressed: targets.isEmpty
                ? null
                : () => services.refresh(targets.map((target) => target.basic)),
          ),
          IconButtonData(
            glyph: AppGlyphs.close,
            tooltip: localizations.cancel,
            onPressed: () => services.cancel([
              for (final target in ServiceTarget.values) ...[
                target.basic,
                target.advanced,
              ],
            ]),
          ),
          IconButtonData(
            glyph: AppGlyphs.sliders,
            tooltip: localizations.serviceManage,
            onPressed: () => Navigator.of(
              context,
            ).push(PagedSheetRoute(builder: (_) => const ServiceManageView())),
          ),
        ],
        body: CustomScrollView(
          shrinkWrap: true,
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(height: context.contentTopPadding),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  targets.isEmpty
                      ? localizations.serviceAllDisabled
                      : localizations.serviceBasicExplanation,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverList.builder(
                itemCount: targets.length,
                itemBuilder: (context, index) {
                  final target = targets[index];
                  return ItemPositionProvider(
                    position: ItemPosition.get(index, targets.length),
                    child: _ServiceRow(
                      target: target,
                      key: ValueKey(target),
                      entry: state.entryOf(target.basic),
                      selected: target == current,
                      onTap: () => context.safeNestedPop(target),
                      onCheck: () => services.refresh([target.basic]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdvancedServiceView extends ConsumerStatefulWidget {
  const _AdvancedServiceView({required this.target});
  final ServiceTarget target;

  @override
  ConsumerState<_AdvancedServiceView> createState() =>
      _AdvancedServiceViewState();
}

class _AdvancedServiceViewState extends ConsumerState<_AdvancedServiceView> {
  late final ServiceStatus _services;

  @override
  void initState() {
    super.initState();
    _services = ref.read(serviceStatusProvider.notifier);
    _services.watch(widget.target.basic, automatic: false);
    _services.watch(widget.target.advanced, automatic: false);
  }

  @override
  void dispose() {
    _services.unwatch(widget.target.basic, automatic: false);
    _services.unwatch(widget.target.advanced, automatic: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = context.appLocalizations;
    final target = widget.target;
    final enabled = ref.watch(enabledServiceTargetsProvider).contains(target);
    final state = ref.watch(serviceStatusProvider);
    final basic = state.entryOf(target.basic);
    final advanced = state.entryOf(target.advanced);
    final check = advanced.value;
    final (basicLabel, _) = _statusOf(
      context,
      basic.value,
      basic.phase,
      expired: basic.expired,
    );
    final (advancedLabel, _) = _statusOf(
      context,
      check,
      advanced.phase,
      expired: advanced.expired,
    );
    final exits =
        check?.steps.map((step) => step.chains.firstOrNull).toSet() ?? {};
    final exitLabel = exits.contains(null) || exits.isEmpty
        ? text.serviceUnknownRoute
        : exits.length == 1
        ? exits.single!
        : text.serviceMultipleRoutes;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: ref.sheetHeight(context, 0.85)),
      child: CommonScaffold(
        title: '${target.label} · ${text.serviceAdvanced}',
        body: ListView(
          padding: const EdgeInsets.all(16),
          shrinkWrap: true,
          children: [
            Text(text.serviceAdvancedExplanation),
            const SizedBox(height: 12),
            Text(text.serviceRecipients(target.advancedRecipients.join(', '))),
            if (target == ServiceTarget.disneyPlus) ...[
              const SizedBox(height: 12),
              Text(text.serviceDisneyExplanation),
            ],
            const SizedBox(height: 16),
            Text('${text.serviceBasic}: $basicLabel'),
            const SizedBox(height: 8),
            Text('${text.serviceAdvanced}: $advancedLabel'),
            if (check?.checkedAt != null)
              Text(text.serviceCheckedAt(check!.checkedAt!.showFull)),
            if (check != null) ...[
              Text(text.serviceElapsed(check.elapsed)),
              Text(exitLabel),
              if (check.region != null)
                Text(text.serviceDetectedRegion(check.region!)),
              if (check.status == ServiceProbeStatus.failed)
                Text(_serviceReason(context, check.reason)),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: !enabled || advanced.isLoading
                  ? null
                  : () => _services.refresh([target.advanced]),
              child: Text(text.serviceStartAdvanced),
            ),
            if (advanced.isLoading)
              TextButton(
                onPressed: () => _services.cancel([target.advanced]),
                child: Text(text.cancel),
              ),
            if (!enabled) Text('${target.label} · ${text.disabled}'),
            Text(text.serviceAdvancedTiming),
            for (final step in check?.steps ?? <ServiceCheckStep>[])
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(step.endpoint),
                subtitle: Text(
                  [
                    if (step.httpStatus > 0) 'HTTP ${step.httpStatus}',
                    _serviceReason(context, step.outcome),
                    if (step.observation.isNotEmpty)
                      _statusLabel(
                        context,
                        ServiceProbeStatus.byId(step.observation),
                      ),
                    if (step.region.isNotEmpty)
                      text.serviceDetectedRegion(step.region),
                    step.chains.isEmpty
                        ? text.serviceUnknownRoute
                        : step.chains.join(' ← '),
                  ].join(' · '),
                ),
                trailing: Text('${step.delay} ms'),
              ),
          ],
        ),
      ),
    );
  }
}

String _serviceReason(BuildContext context, String reason) {
  final text = context.appLocalizations;
  return switch (reason) {
    'headers' => text.serviceHeaders,
    'complete' => text.serviceBodyComplete,
    'marker' => text.serviceMarkerFound,
    'body-limit' => text.serviceBodyLimit,
    'read-error' => text.serviceReadError,
    'recipient-blocked' || 'redirect-blocked' => text.serviceRecipientBlocked,
    'request-limit' => text.serviceRequestLimit,
    'route-changed' => text.serviceRouteChanged,
    'timeout' => text.timeout,
    'dns-failed' => text.serviceDnsFailed,
    'tls-failed' => text.serviceTlsFailed,
    'connect-failed' => text.serviceConnectFailed,
    _ => text.serviceIndeterminate,
  };
}

class ServiceManageView extends ConsumerWidget {
  const ServiceManageView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = ref.watch(serviceTargetsProvider);
    final enabled = ref.watch(enabledServiceTargetsProvider);
    final settings = ref.read(appSettingProvider.notifier);

    void reorder(int oldIndex, int newIndex) {
      settings.update(
        (state) => state.copyWith(
          serviceOrder: [
            for (final target in targets.copyAndReorder(oldIndex, newIndex))
              target.id,
          ],
        ),
      );
    }

    void toggle(ServiceTarget target, bool value) {
      settings.update((state) {
        final disabled = {...state.disabledServices};
        if (value) {
          disabled.remove(target.id);
        } else {
          disabled.add(target.id);
        }
        return state.copyWith(disabledServices: disabled.toList());
      });
    }

    Widget itemAt(int index) {
      final target = targets[index];
      final isEnabled = enabled.contains(target);
      return _ServiceManageItem(
        key: ValueKey(target),
        target: target,
        index: index,
        position: ItemPosition.get(index, targets.length),
        enabled: isEnabled,
        onChanged: (value) => toggle(target, value),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: ref.sheetHeight(context, 0.8)),
      child: CommonScaffold(
        title: context.appLocalizations.serviceManage,
        body: CustomScrollView(
          shrinkWrap: true,
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(height: context.contentTopPadding),
            ),
            SliverReorderableList(
              itemBuilder: (_, index) => itemAt(index),
              itemCount: targets.length,
              proxyDecorator: (child, index, animation) =>
                  commonProxyDecorator(itemAt(index), index, animation),
              onReorderItem: reorder,
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
        ),
      ),
    );
  }
}

const _rowBadgeSize = 40.0;
const _rowBadgeInset = 12.0;
// Concentric with the corners DecorationListItem gives the ends of a run.
const _rowBadgeRadius = AppCorner.xl - _rowBadgeInset;

class _ServiceManageItem extends StatelessWidget {
  const _ServiceManageItem({
    super.key,
    required this.target,
    required this.index,
    required this.position,
    required this.enabled,
    required this.onChanged,
  });

  final ServiceTarget target;
  final int index;
  final ItemPosition position;
  final bool enabled;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ItemPositionProvider(
        position: position,
        child: DecorationListItem(
          minVerticalPadding: _rowBadgeInset,
          contentPadding: const EdgeInsets.only(left: _rowBadgeInset, right: 0),
          onPressed: onChanged == null ? null : () => onChanged(!enabled),
          leading: _ServiceBadge(
            target: target,
            size: _rowBadgeSize,
            radius: _rowBadgeRadius,
            enabled: enabled,
          ),
          title: Text(
            target.label,
            style: enabled
                ? null
                : TextStyle(color: context.colorScheme.onSurfaceVariant),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(value: enabled, onChanged: onChanged),
              ReorderableDelayedDragStartListener(
                index: index,
                child: Container(
                  color: Colors.transparent,
                  padding: const EdgeInsets.all(12),
                  child: const GlyphIcon(AppGlyphs.dragHandle),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceRow extends ConsumerStatefulWidget {
  const _ServiceRow({
    super.key,
    required this.target,
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onCheck,
  });

  final ServiceTarget target;
  final ProbeEntry<ServiceCheck> entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onCheck;

  @override
  ConsumerState<_ServiceRow> createState() => _ServiceRowState();
}

class _ServiceRowState extends ConsumerState<_ServiceRow> {
  late final ServiceStatus _services;

  @override
  void initState() {
    super.initState();
    _services = ref.read(serviceStatusProvider.notifier);
    _services.watch(widget.target.basic, automatic: false);
  }

  @override
  void didUpdateWidget(covariant _ServiceRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target) {
      _services.unwatch(oldWidget.target.basic, automatic: false);
      _services.watch(widget.target.basic, automatic: false);
    }
  }

  @override
  void dispose() {
    _services.unwatch(widget.target.basic, automatic: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = context.appLocalizations;
    final secondary = context.textTheme.bodySmall?.copyWith(
      color: context.colorScheme.onSurfaceVariant,
    );
    final target = widget.target;
    final entry = widget.entry;
    final check = entry.value;
    final loading = entry.isLoading;
    final node = check?.node;
    final (label, color) = _statusOf(
      context,
      check,
      entry.phase,
      expired: entry.expired,
    );
    return DecorationListItem(
      isSelected: widget.selected,
      minVerticalPadding: _rowBadgeInset,
      contentPadding: const EdgeInsets.only(left: _rowBadgeInset, right: 4),
      onPressed: widget.onTap,
      leading: _ServiceBadge(
        target: target,
        size: _rowBadgeSize,
        radius: _rowBadgeRadius,
        dot: loading
            ? context.colorScheme.outlineVariant
            : check != null || entry.phase == ProbePhase.failed
            ? color
            : null,
      ),
      title: _ServiceTitle(
        name: target.label,
        status: _StatusPill(label: label, color: color),
      ),
      // A one-line tile is shorter than a two-line one, so the line is always
      // there and a check does not resize the row.
      subtitle: loading
          ? SkeletonText(width: 96, style: secondary)
          : _NodeLine(node: node, style: secondary),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          _ServiceRowTrailing(check: check, style: secondary),
          if (target.hasAdvanced)
            IconButton(
              tooltip: localizations.serviceAdvanced,
              onPressed: () => Navigator.of(context).push(
                PagedSheetRoute(
                  builder: (_) => _AdvancedServiceView(target: target),
                ),
              ),
              icon: const GlyphIcon(AppGlyphs.info),
            ),
          IconButton(
            tooltip: loading
                ? localizations.cancel
                : localizations.serviceCheck,
            onPressed: loading
                ? () => _services.cancel([target.basic])
                : widget.onCheck,
            icon: GlyphIcon(loading ? AppGlyphs.close : AppGlyphs.refresh),
          ),
        ],
      ),
    );
  }
}

class _ServiceRowTrailing extends StatelessWidget {
  const _ServiceRowTrailing({required this.check, this.style});

  final ServiceCheck? check;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final delay = check?.delay;
    final checkedAt = check?.checkedAt;
    if (delay == null && checkedAt == null) {
      return const SizedBox.shrink();
    }
    final numeric = style?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (delay != null)
          Text(
            '$delay ms',
            style: numeric?.copyWith(
              color: context.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (checkedAt != null)
          Text(
            checkedAt.showTime.trim(),
            style: numeric?.copyWith(color: context.colorScheme.outline),
          ),
      ],
    );
    if (checkedAt == null) return column;
    return Tooltip(
      message: context.appLocalizations.serviceCheckedAt(checkedAt.showFull),
      child: column,
    );
  }
}

class _ServicePager extends StatefulWidget {
  const _ServicePager({
    required this.controller,
    required this.targets,
    required this.index,
    required this.onChanged,
    required this.itemBuilder,
  });

  final PageController controller;
  final List<ServiceTarget> targets;
  final int index;
  final ValueChanged<int> onChanged;
  final Widget Function(BuildContext context, ServiceTarget target) itemBuilder;

  @override
  State<_ServicePager> createState() => _ServicePagerState();
}

class _ServicePagerState extends State<_ServicePager> {
  bool _moving = false;

  Future<void> _select(int index) async {
    if (_moving || !widget.controller.hasClients) return;
    final next = index.clamp(0, widget.targets.length - 1);
    if (next == widget.index) return;
    _moving = true;
    try {
      await widget.controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _moving = false;
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final delta = event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    if (delta == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _select(widget.index + (delta > 0 ? 1 : -1));
    });
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.index;
    final targets = widget.targets;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _select(index - 1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _select(index + 1),
      },
      child: Focus(
        child: Semantics(
          label: context.appLocalizations.serviceStatus,
          value: targets[index].label,
          increasedValue: index < targets.length - 1
              ? targets[index + 1].label
              : null,
          decreasedValue: index > 0 ? targets[index - 1].label : null,
          onIncrease: index < targets.length - 1
              ? () => _select(index + 1)
              : null,
          onDecrease: index > 0 ? () => _select(index - 1) : null,
          child: Listener(
            onPointerSignal: _onPointerSignal,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: PointerDeviceKind.values.toSet(),
                scrollbars: false,
              ),
              child: PageView.builder(
                controller: widget.controller,
                itemCount: targets.length,
                onPageChanged: widget.onChanged,
                itemBuilder: (context, itemIndex) =>
                    widget.itemBuilder(context, targets[itemIndex]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
