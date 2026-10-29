import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'ip_quality_sheet.dart';

class IpQualityText extends ConsumerStatefulWidget {
  const IpQualityText({
    super.key,
    required this.ip,
    this.style,
    this.openDetails = false,
  });

  final String ip;
  final TextStyle? style;
  final bool openDetails;

  @override
  ConsumerState<IpQualityText> createState() => _IpQualityTextState();
}

class _IpQualityTextState extends ConsumerState<IpQualityText> {
  static const _mask = '*****';

  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final ip = widget.ip;
    final hideIp = ref.watch(
      appSettingProvider.select((state) => state.hideIp),
    );
    final shownIp = hideIp ? _mask : ip;
    var style = widget.style;
    if (hideIp) {
      style = (style ?? const TextStyle()).toJetBrainsMono;
    }
    if (widget.openDetails && !_isHovered) {
      style = style?.copyWith(color: style.color?.opacity80);
    }
    final text = Tooltip(
      preferBelow: false,
      message: shownIp,
      child: Text(
        shownIp,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    if (!widget.openDetails) {
      return text;
    }
    return InkWell(
      onTap: () => showIpQualitySheet(context, ip: ip),
      onHover: (value) => setState(() => _isHovered = value),
      customBorder: AppShape.xs,
      hoverColor: Colors.transparent,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: text,
    );
  }
}
