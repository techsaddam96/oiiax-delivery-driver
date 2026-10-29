import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/constants/fonts.dart';
import 'package:blockatie/provider/chat/driver_chat_conversations_provider.dart';
import 'package:blockatie/services/driver_chat_service.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/views/pages/chat/driver_chat_navigation.dart';
import 'package:blockatie/views/pages/chat/widgets/driver_chat_copy.dart';
import 'package:blockatie/views/pages/chat/widgets/driver_chat_header.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// "Open chat" for a shipment, shown on the shipment details screen.
///
/// The thread is resolved on tap, not looked up in whatever the conversation
/// list happens to have loaded: the backend returns the existing thread or
/// opens one, so this works for a shipment that has never been chatted about
/// and for one whose thread sits on another page of the list.
///
/// Only `shipment_id` is sent. Whether the shipment is this driver's, and which
/// thread belongs to them, are decided server-side.
class DriverShipmentChatAction extends StatefulWidget {
  const DriverShipmentChatAction({
    super.key,
    required this.shipmentId,
    this.repository,
  });

  final int shipmentId;

  /// Handed to the thread this action opens. Production leaves it null, so the
  /// thread builds its own service.
  @visibleForTesting
  final DriverChatRepository? repository;

  @override
  State<DriverShipmentChatAction> createState() =>
      _DriverShipmentChatActionState();
}

class _DriverShipmentChatActionState extends State<DriverShipmentChatAction> {
  /// The session this button belongs to. A resolution that finishes after the
  /// driver changed must not open anything.
  final int _accountGeneration = UserSessionState.generation;
  bool get _active =>
      mounted && _accountGeneration == UserSessionState.generation;

  bool _isResolving = false;

  Future<void> _openChat() async {
    // The single guard against a double tap: the second one finds this set and
    // returns, so one tap can never become two resolutions or two routes.
    if (_isResolving || !_active) return;
    setState(() => _isResolving = true);

    final provider = context.read<DriverChatConversationsProvider>();
    try {
      final conversation =
          await provider.resolveShipmentConversation(widget.shipmentId);
      if (!mounted || !_active) return;

      if (conversation == null) {
        // Nothing to open, so nothing is pushed.
        _showError(chatErrorText(context, provider.errorMessage));
        return;
      }

      await DriverChatNavigation.openConversation(
        context,
        conversation: conversation,
        repository: widget.repository,
      );
    } finally {
      if (_active) {
        setState(() => _isResolving = false);
      }
    }
  }

  void _showError(String message) {
    if (!_active || message.isEmpty) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.shipmentId <= 0) return const SizedBox.shrink();

    // Opportunistic only: if the conversation list happens to be loaded, the
    // badge is shown. Nothing is fetched for it, and its absence never blocks
    // the button.
    final unread = context.select<DriverChatConversationsProvider, int>(
      (provider) => DriverChatNavigation.findShipmentConversation(
            provider,
            widget.shipmentId,
          )?.unreadCount ??
          0,
    );

    return SizedBox(
      height: 50,
      child: ElevatedButton.icon(
        onPressed: _isResolving ? null : _openChat,
        icon: _isResolving
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: AppColors.primary,
                ),
              )
            : const Icon(Icons.chat_bubble_outline_rounded, size: 19),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                _isResolving
                    ? chatCopy(context, 'Opening chat…', 'جارٍ فتح المحادثة…')
                    : chatCopy(context, 'Shipment Chat', 'محادثة الشحنة'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppFonts.currentFontFamily,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
            if (!_isResolving && unread > 0) ...[
              const SizedBox(width: 8),
              DriverChatUnreadBadge(count: unread),
            ],
          ],
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.primary,
          disabledBackgroundColor: Colors.white,
          disabledForegroundColor: AppColors.primary.withValues(alpha: 0.7),
          elevation: 0,
          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.22)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
