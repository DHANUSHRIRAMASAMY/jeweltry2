import 'package:flutter/foundation.dart';
import '../models/jewelry_item.dart';

/// Global singleton that holds the currently selected jewelry item.
/// Any widget can listen to [ArState.instance] and rebuild when the
/// selection changes — no external state-management package required.
class ArState extends ChangeNotifier {
  ArState._();
  static final ArState instance = ArState._();

  JewelryItem? _selected;
  JewelryItem? get selected => _selected;

  void select(JewelryItem item) {
    _selected = item;
    notifyListeners();
  }

  void clear() {
    if (_selected == null) return;
    _selected = null;
    notifyListeners();
  }

  void toggle(JewelryItem item) {
    if (_selected?.id == item.id) {
      clear();
    } else {
      select(item);
    }
  }
}
