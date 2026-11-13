import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/icons/icons.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config_state.dart';
import 'package:fl_clash/providers/connection_exits.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:visibility_detector/visibility_detector.dart';

class ConnectionExitIcon extends ConsumerStatefulWidget {
  const ConnectionExitIcon({
    super.key,
    required this.info,
    required this.active,
  });
  final TrackerInfo info;
  final bool? active;
  @override
  ConsumerState<ConnectionExitIcon> createState() => _ConnectionExitIconState();
}

class _ConnectionExitIconState extends ConsumerState<ConnectionExitIcon> {
  final _visibilityKey = UniqueKey();
  Timer? _stable;
  bool _visible = false, _automatic = false;
  ConnectionExitTarget? _watched, _wanted;
  bool _currentRoute = false, _foreground = false;
  late ConnectionExits _cache;

  @override
  void initState() {
    super.initState();
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    _cache = ref.read(connectionExitsProvider.notifier);
  }

  void _unsubscribe() {
    _stable?.cancel();
    _stable = null;
    final target = _watched;
    _watched = null;
    if (target != null) _cache.unwatch(target, automatic: _automatic);
    _automatic = false;
  }

  void _sync() {
    if (!mounted) return;
    final target = _visible && _currentRoute && _foreground ? _wanted : null;
    if (target != _watched) {
      _unsubscribe();
      if (target != null) {
        _watched = target;
        _cache.watch(target, automatic: false);
      }
    }
    if (target == null) return;
    if (widget.active != true) {
      _stable?.cancel();
      _stable = null;
      if (_automatic) {
        _cache.watch(target, automatic: false);
        _cache.unwatch(target, automatic: true);
        _automatic = false;
      }
    } else if (!_automatic && _stable == null) {
      _stable = Timer(const Duration(milliseconds: 350), () {
        _stable = null;
        if (!mounted ||
            _watched != target ||
            !_visible ||
            !_currentRoute ||
            !_foreground ||
            widget.active != true) {
          return;
        }
        _cache.watch(target, automatic: true);
        _cache.unwatch(target, automatic: false);
        _automatic = true;
      });
    }
  }

  @override
  void dispose() {
    _stable?.cancel();
    final target = _watched;
    final automatic = _automatic;
    if (target != null) {
      scheduleMicrotask(() => _cache.unwatch(target, automatic: automatic));
    }
    VisibilityDetectorController.instance.forget(_visibilityKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    _currentRoute = ModalRoute.isCurrentOf(context) ?? true;
    _foreground = ref.watch(appVisibleProvider);
    final configuration = ref.watch(
      configStateProvider.select((value) => value.fact.inputId),
    );
    final nodes = ref.watch(groupsProvider).expand((group) => group.all);
    final identity =
        nodes
            .where(
              (node) =>
                  widget.info.chains.isNotEmpty &&
                  node.name == widget.info.chains.first,
            )
            .firstOrNull
            ?.cacheIdentity ??
        '';
    _wanted = connectionExitTarget(
      widget.info,
      configuration,
      identity: identity,
    );
    scheduleMicrotask(_sync);
    final entry = ref.watch(
      connectionExitsProvider.select((values) => values[_wanted]),
    );
    final value = entry?.value;
    final fresh = _wanted != null && !_cache.isExpired(_wanted!);
    final inactive = widget.active != true;
    final direct =
        widget.info.chains.isNotEmpty && widget.info.chains.first == 'DIRECT';
    final known = value != null && fresh;
    final message = known
        ? '${l.activityExitObserved(value.ip, value.countryCode, value.checkedAt?.showFull ?? '')}${entry?.phase == ProbePhase.failed ? '\n${l.activityExitFailed}' : ''}'
        : _wanted == null
        ? (direct ? l.activityExitNotApplicable : l.activityExitUnavailable)
        : entry?.busy == true
        ? l.activityExitChecking
        : entry?.phase == ProbePhase.failed
        ? l.activityExitFailed
        : inactive
        ? l.activityExitInactive
        : l.activityExitNotChecked;
    final Widget icon;
    if (known) {
      icon = SizedBox(
        width: 32,
        height: 32,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              value.countryCode.countryFlagEmoji,
              style: const TextStyle(
                fontSize: 24,
                fontFamily: 'Apple Color Emoji',
                fontFamilyFallback: ['Noto Color Emoji'],
              ),
            ),
            if (entry?.busy == true)
              Positioned(
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    shape: AppShape.circle,
                    color: context.colorScheme.surface,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    } else if (entry?.busy == true) {
      icon = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else {
      icon = GlyphIcon(
        direct
            ? AppGlyphs.direct
            : entry?.phase == ProbePhase.failed
            ? AppGlyphs.error
            : _wanted == null
            ? AppGlyphs.block
            : AppGlyphs.proxies,
        size: 22,
        color: context.colorScheme.onSurfaceVariant,
      );
    }
    return VisibilityDetector(
      key: _visibilityKey,
      onVisibilityChanged: (info) {
        _visible = info.visibleFraction >= 0.5;
        _sync();
      },
      child: IconButton(
        constraints: const BoxConstraints(minWidth: 36, minHeight: 40),
        padding: EdgeInsets.zero,
        tooltip: message,
        onPressed: _wanted == null
            ? null
            : () {
                _visible = true;
                _sync();
                if (_watched != null) {
                  final result = _cache.refresh(_watched!);
                  if (result == ExitRefreshResult.throttled ||
                      result == ExitRefreshResult.unavailable) {
                    context.showSnackBar(
                      result == ExitRefreshResult.throttled
                          ? l.activityExitCooldown
                          : l.activityExitUnavailable,
                    );
                  }
                }
              },
        icon: icon,
      ),
    );
  }
}
