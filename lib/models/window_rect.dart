import 'dart:convert';

/// Положение и размер одного окна на экране — в ДОЛЯХ области окон
/// (0..1), чтобы раскладка не зависела от разрешения и отступов.
class WindowRect {
  const WindowRect({
    required this.slotId,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  final String slotId;
  final double x;
  final double y;
  final double w;
  final double h;

  /// Минимальный размер окна (доля области).
  static const double minW = 0.2;
  static const double minH = 0.12;

  /// Шаг привязки к сетке.
  static const double snap = 0.025;

  WindowRect copyWith({double? x, double? y, double? w, double? h}) => WindowRect(
        slotId: slotId,
        x: x ?? this.x,
        y: y ?? this.y,
        w: w ?? this.w,
        h: h ?? this.h,
      );

  /// Ограничить рамками области и минимальным размером.
  WindowRect clamped() {
    final nw = w.clamp(minW, 1.0);
    final nh = h.clamp(minH, 1.0);
    return WindowRect(
      slotId: slotId,
      x: x.clamp(0.0, 1.0 - nw),
      y: y.clamp(0.0, 1.0 - nh),
      w: nw,
      h: nh,
    );
  }

  /// Привязать к сетке (после окончания перетаскивания).
  WindowRect snapped() {
    double s(double v) => (v / snap).round() * snap;
    return WindowRect(slotId: slotId, x: s(x), y: s(y), w: s(w), h: s(h)).clamped();
  }

  Map<String, Object> toJson() => {'id': slotId, 'x': x, 'y': y, 'w': w, 'h': h};

  static WindowRect? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    double? d(Object? v) => v is num ? v.toDouble() : null;
    final x = d(raw['x']), y = d(raw['y']), w = d(raw['w']), h = d(raw['h']);
    if (id is! String || x == null || y == null || w == null || h == null) return null;
    return WindowRect(slotId: id, x: x, y: y, w: w, h: h).clamped();
  }

  static String encodeList(List<WindowRect> list) =>
      jsonEncode([for (final r in list) r.toJson()]);

  static List<WindowRect>? decodeList(String? raw) {
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! List) return null;
      final out = <WindowRect>[];
      for (final e in data) {
        final r = WindowRect.fromJson(e);
        if (r != null) out.add(r);
      }
      return out;
    } catch (_) {
      return null;
    }
  }
}
