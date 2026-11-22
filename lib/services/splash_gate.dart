import 'package:flutter/foundation.dart';

/// true, пока на экране заставка при холодном запуске. Живые окна (нативный
/// слой поверх Flutter) до её окончания не показываются, иначе они закрывали
/// бы заставку.
final ValueNotifier<bool> splashGate = ValueNotifier<bool>(true);
