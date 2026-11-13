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
  ConnectionExitTarget? _manualTarget;
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
    final interested = widget.active == true || _manualTarget == _wanted;
    final target = _visible && _currentRoute && _foreground && interested
        ? _wanted
        : null;
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
    _wanted = connectionExitTarget(widget.info, configuration);
    scheduleMicrotask(_sync);
    final entry = ref.watch(
      connectionExitsProvider.select((values) => values[_wanted]),
    );
    final value = entry?.value;
    final fresh = _wanted != null && !_cache.isExpired(_wanted!);
    final inactive = widget.active != true && _manualTarget != _wanted;
    final message = _wanted == null
        ? (widget.info.chains.isNotEmpty && widget.info.chains.first == 'DIRECT'
              ? l.activityExitNotApplicable
              : l.activityExitUnavailable)
        : inactive
        ? l.activityExitInactive
        : entry?.busy == true
        ? l.activityExitChecking
        : value != null && fresh
        ? l.activityExitObserved(
            value.ip,
            value.countryCode,
            value.checkedAt?.showFull ?? '',
          )
        : entry?.phase == ProbePhase.failed
        ? l.activityExitFailed
        : l.activityExitNotChecked;
    final Widget icon;
    if (_wanted == null || inactive) {
      icon = GlyphIcon(
        AppGlyphs.block,
        size: 22,
        color: context.colorScheme.onSurfaceVariant,
      );
    } else if (entry?.busy == true) {
      icon = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (value != null && fresh) {
      icon = Text(
        value.countryCode.countryFlagEmoji,
        style: const TextStyle(
          fontSize: 24,
          fontFamily: 'Apple Color Emoji',
          fontFamilyFallback: ['Noto Color Emoji'],
        ),
      );
    } else {
      icon = GlyphIcon(
        entry?.phase == ProbePhase.failed ? AppGlyphs.error : AppGlyphs.proxies,
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
                setState(() => _manualTarget = _wanted);
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
