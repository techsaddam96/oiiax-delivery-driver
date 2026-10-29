// providers/dropdown_provider.dart
import 'package:blockatie/services/user_session_state.dart';
import 'package:flutter/material.dart';

class Headerprovider extends UserScopedNotifier {
  bool _isOpen = false;
  OverlayEntry? _overlayEntry;

  bool get isOpen => _isOpen;

  // An overlay opened by the previous driver must never stay mounted.
  @override
  void clearUserState() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isOpen = false;
  }

  void toggle({
    required BuildContext context,
    required GlobalKey targetKey,
    required Widget overlayChild,
  }) {
    if (_isOpen) {
      close();
    } else {
      final renderBox =
          targetKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) return;

      final size = renderBox.size;
      final offset = renderBox.localToGlobal(Offset.zero);

      _overlayEntry = OverlayEntry(
        builder:
            (context) => Positioned(
              left: offset.dx,
              top: offset.dy + size.height + 5,
              width: size.width + 20,
              child: Material(color: Colors.transparent, child: overlayChild),
            ),
      );

      Overlay.of(context).insert(_overlayEntry!);
      _isOpen = true;
      notifyListeners();
    }
  }

  void close() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (_isOpen) {
      _isOpen = false;
      notifyListeners();
    }
  }
}
