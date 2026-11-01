import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Emits the current Flutter window geometry in Debug builds only.
///
/// This is intended for collecting real foldable-device measurements with
/// adb logcat. It never logs page content, model prompts, or user data.
class WindowMetricsDiagnostics extends StatefulWidget {
  const WindowMetricsDiagnostics({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<WindowMetricsDiagnostics> createState() =>
      _WindowMetricsDiagnosticsState();
}

class _WindowMetricsDiagnosticsState extends State<WindowMetricsDiagnostics> {
  String? _lastLoggedSnapshot;
  String? _pendingSnapshot;
  bool _logScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!kDebugMode) return;

    final snapshot = _snapshot(MediaQuery.of(context));
    if (snapshot == _pendingSnapshot) return;

    _pendingSnapshot = snapshot;
    if (_logScheduled || snapshot == _lastLoggedSnapshot) return;

    _logScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _logScheduled = false;
      if (!mounted || !kDebugMode) return;

      final pending = _pendingSnapshot;
      if (pending == null || pending == _lastLoggedSnapshot) return;

      _lastLoggedSnapshot = pending;
      debugPrint('[WINDOW_METRICS] $pending');
    });
  }

  String _snapshot(MediaQueryData data) {
    final logicalSize = data.size;
    final dpr = data.devicePixelRatio;
    final physicalWidth = logicalSize.width * dpr;
    final physicalHeight = logicalSize.height * dpr;
    final displayFeatures = data.displayFeatures.map((feature) {
      final bounds = feature.bounds;
      return '${feature.type.name}/${feature.state.name}'
          '@${bounds.left.toStringAsFixed(1)},'
          '${bounds.top.toStringAsFixed(1)},'
          '${bounds.width.toStringAsFixed(1)}x'
          '${bounds.height.toStringAsFixed(1)}';
    }).join(';');

    return 'sizeDp=${logicalSize.width.toStringAsFixed(1)}x'
        '${logicalSize.height.toStringAsFixed(1)} '
        'physicalPx=${physicalWidth.toStringAsFixed(1)}x'
        '${physicalHeight.toStringAsFixed(1)} '
        'dpr=${dpr.toStringAsFixed(2)} '
        'displayFeatures=[$displayFeatures] '
        'viewInsets=${_formatInsets(data.viewInsets)} '
        'viewPadding=${_formatInsets(data.viewPadding)} '
        'textScale=${data.textScaler.scale(1.0).toStringAsFixed(2)}';
  }

  String _formatInsets(EdgeInsets insets) {
    return 'l=${insets.left.toStringAsFixed(1)},'
        't=${insets.top.toStringAsFixed(1)},'
        'r=${insets.right.toStringAsFixed(1)},'
        'b=${insets.bottom.toStringAsFixed(1)}';
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
