import 'package:blockatie/models/chat/driver_chat_conversation.dart';
import 'package:blockatie/provider/chat/driver_chat_conversations_provider.dart';
import 'package:blockatie/services/driver_chat_service.dart';
import 'package:blockatie/views/pages/chat/driver_conversation_page.dart';
import 'package:blockatie/views/pages/chat/driver_conversations_page.dart';
import 'package:flutter/material.dart';

/// Route names for the chat stack.
///
/// Naming every chat route is what lets [DriverChatNavigation] recognise a
/// thread that is already open instead of stacking a second copy of it.
class DriverChatRoutes {
  DriverChatRoutes._();

  static const String conversations = 'driver-chat/conversations';

  /// The shipment screen as reached from inside a thread.
  static const String shipment = 'driver-chat/shipment';

  static const String _conversationPrefix = 'driver-chat/conversation/';

  static String conversation(int conversationId) =>
      '$_conversationPrefix$conversationId';

  /// Whether a route showing chat itself is on top, in which case the floating
  /// launcher has nothing to offer and hides.
  ///
  /// [shipment] is deliberately excluded: it is an ordinary Driver screen that
  /// happens to be reachable from a thread, and the launcher belongs there.
  static bool hidesLauncher(String? routeName) {
    if (routeName == null) {
      return false;
    }
    return routeName == conversations ||
        routeName.startsWith(_conversationPrefix);
  }
}

class DriverChatNavigation {
  DriverChatNavigation._();

  /// Opens a thread on a plain Navigator stack.
  ///
  /// Chat deliberately does not use `Nav.to(withNav: true)`: that shows the
  /// page through the bottom-nav overlay, and `Nav.back()` then clears the
  /// overlay instead of popping, which would break a conversations -> thread ->
  /// shipment stack.
  static Future<void> openConversation(
    BuildContext context, {
    required DriverChatConversation conversation,
    DriverChatRepository? repository,
  }) {
    return openConversationById(
      Navigator.of(context),
      conversationId: conversation.conversationId,
      title: conversation.title,
      shipmentId: conversation.shipmentId,
      policyNum: conversation.policyNum,
      repository: repository,
      currentRouteName: ModalRoute.of(context)?.settings.name,
    );
  }

  /// Opens a thread known only by its id — the shape a push signal arrives in.
  ///
  /// Metadata is optional: the page loads the thread itself, so a signal that
  /// carries nothing but an id still opens the right screen. The caller is
  /// responsible for having proven the driver may open it.
  static Future<void> openConversationById(
    NavigatorState navigator, {
    required int conversationId,
    String title = '',
    int? shipmentId,
    String? policyNum,
    DriverChatRepository? repository,
    String? currentRouteName,
  }) async {
    if (conversationId <= 0) {
      return;
    }
    final name = DriverChatRoutes.conversation(conversationId);
    // Covers a double tap on the tile, the loop back from shipment details and
    // a second notification for the thread already on screen.
    final onScreen =
        currentRouteName ?? ModalRoute.of(navigator.context)?.settings.name;
    if (onScreen == name) {
      return;
    }

    await navigator.push<void>(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: name),
        builder: (_) => DriverConversationPage(
          conversationId: conversationId,
          title: title,
          shipmentId: shipmentId,
          policyNum: policyNum,
          repository: repository,
        ),
      ),
    );
  }

  /// Opens the conversation list on a plain Navigator stack.
  ///
  /// The route is named so the launcher observer can recognise it and hide the
  /// bubble while it is on top. The same push is used from the hub row and from
  /// the bubble, so there is one way in and one route name.
  static Future<void> openConversations(
    NavigatorState navigator, {
    DriverChatRepository? repository,
  }) {
    return navigator.push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: DriverChatRoutes.conversations),
        builder: (_) => DriverConversationsPage(repository: repository),
      ),
    );
  }

  /// The loaded thread for a shipment, or null when there is none to open.
  ///
  /// Resolution is limited to conversations the provider currently holds. There
  /// is no Driver get-or-create endpoint, so a thread that does not exist yet,
  /// or that sits on another page of the list, cannot be resolved here — and a
  /// conversation id is never guessed.
  static DriverChatConversation? findShipmentConversation(
    DriverChatConversationsProvider provider,
    int shipmentId,
  ) {
    if (shipmentId <= 0) {
      return null;
    }
    for (final conversation in provider.conversations) {
      if (conversation.isShipmentConversation &&
          conversation.shipmentId == shipmentId) {
        return conversation;
      }
    }
    return null;
  }
}
