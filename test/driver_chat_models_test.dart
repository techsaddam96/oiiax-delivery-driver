// Contract tests for the Driver Chat models.
//
// Every payload below is shaped exactly as services/api_driver_chat.php emits
// it, including the cases where mysqli hands integers back as strings.

import 'package:blockatie/models/chat/driver_chat_conversation.dart';
import 'package:blockatie/models/chat/driver_chat_message.dart';
import 'package:blockatie/models/chat/driver_chat_pagination.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DriverChatConversation', () {
    test('parses a shipment thread including the Driver-only fields', () {
      final conversation = DriverChatConversation.fromJson(const {
        'conversation_id': 3001,
        'conversation_type': 'shipment_driver',
        'shipment_id': 77,
        'policy_num': 'BLK-0077',
        'shipment_status_id': 4,
        'title': 'Shipment BLK-0077',
        'last_message': 'On my way',
        'last_message_type': 'text',
        'last_message_sender_role': 'driver',
        'last_message_at_utc': '2026-09-15T09:30:00Z',
        'unread_count': 2,
      });

      expect(conversation.conversationId, 3001);
      expect(conversation.isShipmentConversation, isTrue);
      expect(conversation.shipmentId, 77);
      expect(conversation.policyNum, 'BLK-0077');
      expect(conversation.shipmentStatusId, 4);
      expect(conversation.lastMessageSenderRole, 'driver');
      expect(conversation.unreadCount, 2);
      expect(conversation.lastMessageAt, isNotNull);
    });

    test('an admin thread carries no shipment fields', () {
      final conversation = DriverChatConversation.fromJson(const {
        'conversation_id': 3002,
        'conversation_type': 'admin_driver',
        'shipment_id': null,
        'policy_num': null,
        'shipment_status_id': null,
        'title': 'Operations',
        'last_message': '',
        'last_message_type': 'text',
        'last_message_sender_role': null,
        'last_message_at': null,
        'unread_count': 0,
      });

      expect(conversation.isShipmentConversation, isFalse);
      expect(conversation.shipmentId, isNull);
      expect(conversation.policyNum, isNull);
      expect(conversation.shipmentStatusId, isNull);
      expect(conversation.lastMessageSenderRole, isNull);
      expect(conversation.lastMessageAt, isNull);
    });

    test('accepts numeric strings and never renders a negative count', () {
      final conversation = DriverChatConversation.fromJson(const {
        'conversation_id': '3003',
        'conversation_type': 'shipment_driver',
        'shipment_id': '9',
        'title': 'Shipment',
        'last_message': 'hi',
        'unread_count': '-4',
      });

      expect(conversation.conversationId, 3003);
      expect(conversation.shipmentId, 9);
      expect(conversation.unreadCount, 0);
      // Absent last_message_type falls back rather than becoming an empty
      // string the UI would have to special-case.
      expect(conversation.lastMessageType, 'text');
    });

    test('a missing conversation_id is rejected, not silently zeroed', () {
      expect(
        () => DriverChatConversation.fromJson(const {
          'conversation_type': 'admin_driver',
          'title': 'Operations',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('DriverChatMessage', () {
    DriverChatMessage serverMessage({int id = 51}) =>
        DriverChatMessage.fromJson({
          'message_id': id,
          'conversation_id': 3001,
          'sender_role': 'admin',
          'sender_name': 'Admin / Operations',
          'message_type': 'text',
          'message': 'Please confirm pickup',
          'is_mine': false,
          'is_read': false,
          'created_at_utc': '2026-09-15T09:31:00Z',
        });

    test('a stored message identifies by its server id', () {
      expect(serverMessage().identityKey, 'server:51');
      expect(serverMessage().status, DriverChatMessageStatus.sent);
      expect(serverMessage().isPending, isFalse);
    });

    test('an optimistic message identifies by its client id', () {
      const pending = DriverChatMessage(
        conversationId: 3001,
        senderRole: 'driver',
        senderName: '',
        messageType: 'text',
        message: 'On my way',
        isMine: true,
        isRead: false,
        clientMessageId: 'driver-chat-1-abc',
        status: DriverChatMessageStatus.sending,
      );

      expect(pending.identityKey, 'client:driver-chat-1-abc');
      expect(pending.isPending, isTrue);
      expect(pending.messageId, isNull);
    });

    test('a message with neither id cannot be rendered', () {
      const orphan = DriverChatMessage(
        conversationId: 3001,
        senderRole: 'admin',
        senderName: 'Admin',
        messageType: 'text',
        message: 'x',
        isMine: false,
        isRead: false,
        status: DriverChatMessageStatus.sent,
      );

      expect(() => orphan.identityKey, throwsStateError);
    });

    test('the server id wins once an optimistic message is reconciled', () {
      const pending = DriverChatMessage(
        conversationId: 3001,
        senderRole: 'driver',
        senderName: '',
        messageType: 'text',
        message: 'On my way',
        isMine: true,
        isRead: false,
        clientMessageId: 'driver-chat-1-abc',
        status: DriverChatMessageStatus.sending,
      );

      final reconciled = pending.copyWith(
        messageId: 52,
        status: DriverChatMessageStatus.sent,
      );

      expect(reconciled.identityKey, 'server:52');
      expect(reconciled.clientMessageId, 'driver-chat-1-abc');
    });

    test('value equality distinguishes a changed row from an identical one',
        () {
      expect(serverMessage(), equals(serverMessage()));
      expect(serverMessage().copyWith(isRead: true), isNot(serverMessage()));
      expect(serverMessage(id: 52), isNot(serverMessage()));
    });
  });

  group('DriverChatPagination', () {
    test('derives page navigation from the contract block', () {
      final page = DriverChatPagination.fromJson(const {
        'page': 2,
        'limit': 15,
        'total': 40,
        'total_pages': 3,
      });

      expect(page.hasPreviousPage, isTrue);
      expect(page.hasNextPage, isTrue);
    });

    test('the last page has no next, the first has no previous', () {
      const last = DriverChatPagination(
        page: 3,
        limit: 15,
        total: 40,
        totalPages: 3,
      );
      const first = DriverChatPagination(
        page: 1,
        limit: 15,
        total: 40,
        totalPages: 3,
      );

      expect(last.hasNextPage, isFalse);
      expect(first.hasPreviousPage, isFalse);
      expect(DriverChatPagination.empty.hasNextPage, isFalse);
      expect(DriverChatPagination.empty.hasPreviousPage, isFalse);
    });
  });

  group('DriverChatMessagesPage', () {
    test('a full page reports has_more with a cursor for the next call', () {
      final page = DriverChatMessagesPage.fromJson({
        'messages': [
          {
            'message_id': 10,
            'conversation_id': 3001,
            'sender_role': 'admin',
            'sender_name': 'Admin',
            'message': 'first',
            'is_mine': false,
            'is_read': true,
          },
          {
            'message_id': 11,
            'conversation_id': 3001,
            'sender_role': 'driver',
            'sender_name': 'Driver',
            'message': 'second',
            'is_mine': true,
            'is_read': false,
          },
        ],
        'has_more': true,
        'next_before_message_id': 10,
      });

      // Oldest -> newest, exactly as the backend orders it.
      expect(page.messages.first.messageId, 10);
      expect(page.messages.last.messageId, 11);
      expect(page.hasMore, isTrue);
      expect(page.nextBeforeMessageId, 10);
    });

    test('the start of a thread reports no cursor', () {
      final page = DriverChatMessagesPage.fromJson(const {
        'messages': <dynamic>[],
        'has_more': false,
        'next_before_message_id': null,
      });

      expect(page.messages, isEmpty);
      expect(page.hasMore, isFalse);
      expect(page.nextBeforeMessageId, isNull);
    });
  });

  group('DriverChatNewMessagesPage', () {
    test('an empty poll still advances the cursor', () {
      final page = DriverChatNewMessagesPage.fromJson(const {
        'messages': <dynamic>[],
        'latest_message_id': 44,
        'has_more': false,
      });

      expect(page.messages, isEmpty);
      expect(page.latestMessageId, 44);
    });

    test('a missing latest_message_id is a contract violation', () {
      expect(
        () => DriverChatNewMessagesPage.fromJson(const {
          'messages': <dynamic>[],
          'has_more': false,
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('DriverChatReadResult', () {
    test('a repeat mark_read reports zero newly written receipts', () {
      final result = DriverChatReadResult.fromJson(const {
        'conversation_id': 3001,
        'last_read_message_id': 51,
        'marked_count': 0,
        'unread_count': 0,
        'unread_before': 0,
      });

      expect(result.markedCount, 0);
      expect(result.unreadCount, 0);
    });

    test('last_read_message_id of 0 is legal for an empty thread', () {
      final result = DriverChatReadResult.fromJson(const {
        'conversation_id': 3002,
        'last_read_message_id': 0,
        'marked_count': 0,
        'unread_count': 0,
        'unread_before': 0,
      });

      expect(result.lastReadMessageId, 0);
    });
  });
}
