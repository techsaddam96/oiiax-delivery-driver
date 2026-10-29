// Transport tests for DriverChatService.
//
// The central claim being defended here is that the Driver app never tells the
// backend who it is: identity comes only from X-API-KEY. Every request's actual
// wire bytes are decoded and checked against the field names
// services/api_driver_chat.php refuses with IDENTITY_NOT_ACCEPTED.

import 'dart:convert';
import 'dart:typed_data';

import 'package:blockatie/models/chat/chat_exception.dart';
import 'package:blockatie/services/driver_chat_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exactly the aliases DRIVER_CHAT_IDENTITY_ALIASES rejects, plus the two role
/// fields, so a regression that starts sending any of them fails here first.
const List<String> _forbiddenIdentityFields = <String>[
  'driver_id',
  'user_id',
  'account_id',
  'client_id',
  'participant_id',
  'sender_id',
  'sender_role',
  'reader_id',
  'reader_role',
];

class _Captured {
  _Captured(this.options, this.body);

  final RequestOptions options;
  final String body;

  /// Everything the request actually carried: query string and body together.
  String get wire => '${options.uri.query}&$body';
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._responder);

  final ResponseBody Function(RequestOptions options) _responder;
  final List<_Captured> requests = <_Captured>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    var body = '';
    if (requestStream != null) {
      final chunks = await requestStream.toList();
      body = utf8.decode(chunks.expand((chunk) => chunk).toList());
    }
    requests.add(_Captured(options, body));
    return _responder(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(
  Map<String, dynamic> body, {
  int status = 200,
  Map<String, List<String>>? headers,
}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>['application/json'],
      ...?headers,
    },
  );
}

Map<String, dynamic> _envelope(Map<String, dynamic> data) => <String, dynamic>{
      'success': true,
      'status': 'success',
      'code': 'OK',
      'message': '',
      'message_en': '',
      'message_ar': '',
      'data': data,
    };

Map<String, dynamic> _failure(String code, {String messageEn = 'failed'}) =>
    <String, dynamic>{
      'success': false,
      'status': 'error',
      'code': code,
      'message': messageEn,
      'message_en': messageEn,
      'message_ar': '',
      'data': null,
    };

({DriverChatService service, _FakeAdapter adapter}) _build(
  ResponseBody Function(RequestOptions options) responder,
) {
  final adapter = _FakeAdapter(responder);
  final dio = Dio(BaseOptions(validateStatus: (_) => true))
    ..httpClientAdapter = adapter;
  return (
    service: DriverChatService(
      dio: dio,
      apiKeyLoader: () async => 'test-api-key',
    ),
    adapter: adapter,
  );
}

void main() {
  group('identity is never sent', () {
    test('no request carries any identity field', () async {
      final built = _build(
        (options) {
          if (options.method == 'POST') {
            final body = options.data;
            final action = body is Map ? body['action'] : null;
            if (action == 'send_message') {
              return _json(_envelope({
                'message': {
                  'message_id': 90,
                  'conversation_id': 3001,
                  'client_message_id': body['client_message_id'],
                  'created_at_utc': '2026-09-15T10:00:00Z',
                  'is_duplicate': false,
                },
              }));
            }
            if (action == 'get_or_create_shipment_conversation') {
              return _json(_envelope({
                'conversation': {
                  'conversation_id': 3001,
                  'conversation_type': 'shipment_driver',
                  'shipment_id': body['shipment_id'],
                  'policy_num': 'BLK-0077',
                  'shipment_status_id': 4,
                  'title': 'Admin / Operations',
                  'last_message': '',
                  'last_message_type': 'text',
                  'last_message_sender_role': null,
                  'last_message_at': null,
                  'unread_count': 0,
                },
                'is_created': true,
              }));
            }
            return _json(_envelope(const {
              'conversation_id': 3001,
              'last_read_message_id': 51,
              'marked_count': 1,
              'unread_count': 0,
              'unread_before': 1,
            }));
          }
          return _json(_envelope(const {
            'conversations': <dynamic>[],
            'pagination': {
              'page': 1,
              'limit': 15,
              'total': 0,
              'total_pages': 0,
            },
            'messages': <dynamic>[],
            'has_more': false,
            'next_before_message_id': null,
            'latest_message_id': 0,
            'unread_count': 0,
          }));
        },
      );

      await built.service.listConversations();
      await built.service.getMessages(conversationId: 3001);
      await built.service
          .getNewMessages(conversationId: 3001, afterMessageId: 10);
      await built.service.getUnreadCount();
      await built.service.sendMessage(
        conversationId: 3001,
        message: 'On my way',
        clientMessageId: DriverChatService.generateClientMessageId(),
      );
      await built.service.markRead(conversationId: 3001, lastMessageId: 51);
      await built.service.getOrCreateShipmentConversation(shipmentId: 77);

      expect(built.adapter.requests, hasLength(7));
      for (final request in built.adapter.requests) {
        for (final field in _forbiddenIdentityFields) {
          expect(
            request.wire.contains(field),
            isFalse,
            reason: '${request.options.uri.path} leaked $field',
          );
        }
        expect(request.options.headers['X-API-KEY'], 'test-api-key');
      }
    });

    test('a missing API key fails before any network call', () async {
      final adapter = _FakeAdapter((_) => _json(_envelope(const {})));
      final dio = Dio(BaseOptions(validateStatus: (_) => true))
        ..httpClientAdapter = adapter;
      final service = DriverChatService(
        dio: dio,
        apiKeyLoader: () async => '   ',
      );

      await expectLater(
        service.listConversations(),
        throwsA(isA<ChatAuthenticationException>()),
      );
      expect(adapter.requests, isEmpty);
    });
  });

  group('request shape', () {
    test('mark_read omits the cursor entirely when it is null', () async {
      final built = _build(
        (_) => _json(_envelope(const {
          'conversation_id': 3001,
          'last_read_message_id': 51,
          'marked_count': 3,
          'unread_count': 0,
          'unread_before': 3,
        })),
      );

      await built.service.markRead(conversationId: 3001);

      final body = built.adapter.requests.single.body;
      expect(body.contains('action=mark_read'), isTrue);
      expect(body.contains('last_message_id'), isFalse);
    });

    test('reads use GET and writes use POST, matching the backend verbs',
        () async {
      final built = _build(
        (options) => options.method == 'POST'
            ? _json(_envelope(const {
                'conversation_id': 3001,
                'last_read_message_id': 51,
                'marked_count': 0,
                'unread_count': 0,
                'unread_before': 0,
              }))
            : _json(_envelope(const {'unread_count': 4})),
      );

      await built.service.getUnreadCount();
      await built.service.markRead(conversationId: 3001);

      expect(built.adapter.requests[0].options.method, 'GET');
      expect(built.adapter.requests[1].options.method, 'POST');
    });

    test('an out-of-range limit is refused locally', () async {
      final built = _build((_) => _json(_envelope(const {})));

      await expectLater(
        built.service.listConversations(limit: 51),
        throwsA(isA<ChatValidationException>()),
      );
      await expectLater(
        built.service.getMessages(conversationId: 3001, limit: 0),
        throwsA(isA<ChatValidationException>()),
      );
      expect(built.adapter.requests, isEmpty);
    });

    test('an empty or oversized message never leaves the device', () async {
      final built = _build((_) => _json(_envelope(const {})));
      final clientMessageId = DriverChatService.generateClientMessageId();

      await expectLater(
        built.service.sendMessage(
          conversationId: 3001,
          message: '   ',
          clientMessageId: clientMessageId,
        ),
        throwsA(isA<ChatValidationException>()),
      );
      await expectLater(
        built.service.sendMessage(
          conversationId: 3001,
          message: 'x' * (DriverChatService.maximumMessageLength + 1),
          clientMessageId: clientMessageId,
        ),
        throwsA(isA<ChatValidationException>()),
      );
      expect(built.adapter.requests, isEmpty);
    });
  });

  group('client_message_id', () {
    test('is unique, secure-random and within the backend format', () {
      final ids = <String>{
        for (var index = 0; index < 500; index++)
          DriverChatService.generateClientMessageId(),
      };

      expect(ids, hasLength(500));
      for (final id in ids) {
        expect(id.startsWith('driver-chat-'), isTrue);
        expect(id.length, inInclusiveRange(8, 100));
        expect(RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]*$').hasMatch(id), isTrue);
      }
    });

    test('a malformed id is rejected before the request is built', () async {
      final built = _build((_) => _json(_envelope(const {})));

      await expectLater(
        built.service.sendMessage(
          conversationId: 3001,
          message: 'hello',
          clientMessageId: 'no spaces allowed',
        ),
        throwsA(isA<ChatValidationException>()),
      );
      expect(built.adapter.requests, isEmpty);
    });

    test('the send response is refused when the echoed id does not match',
        () async {
      final built = _build(
        (_) => _json(_envelope(const {
          'message': {
            'message_id': 90,
            'conversation_id': 3001,
            'client_message_id': 'driver-chat-someone-else',
            'created_at_utc': '2026-09-15T10:00:00Z',
            'is_duplicate': false,
          },
        })),
      );

      await expectLater(
        built.service.sendMessage(
          conversationId: 3001,
          message: 'hello',
          clientMessageId: DriverChatService.generateClientMessageId(),
        ),
        throwsA(
          isA<ChatServerException>()
              .having((error) => error.code, 'code', 'INVALID_RESPONSE'),
        ),
      );
    });

    test('a duplicate send returns the stored message, flagged', () async {
      late String sentId;
      final built = _build(
        (options) {
          final body = options.data as Map;
          sentId = body['client_message_id'] as String;
          return _json(_envelope({
            'message': {
              'message_id': 90,
              'conversation_id': 3001,
              'client_message_id': sentId,
              'created_at_utc': '2026-09-15T10:00:00Z',
              'is_duplicate': true,
            },
          }));
        },
      );

      final clientMessageId = DriverChatService.generateClientMessageId();
      final result = await built.service.sendMessage(
        conversationId: 3001,
        message: 'On my way',
        clientMessageId: clientMessageId,
      );

      expect(result.isDuplicate, isTrue);
      expect(result.message.messageId, 90);
      expect(result.message.clientMessageId, clientMessageId);
      expect(result.message.isMine, isTrue);
      expect(result.message.senderRole, 'driver');
    });
  });

  group('error mapping', () {
    test('401 becomes an authentication error', () async {
      final built = _build(
        (_) => _json(_failure('AUTH_REQUIRED'), status: 401),
      );

      await expectLater(
        built.service.listConversations(),
        throwsA(isA<ChatAuthenticationException>()),
      );
    });

    test('403 DRIVER_INACTIVE keeps its code for the UI', () async {
      final built = _build(
        (_) => _json(_failure('DRIVER_INACTIVE'), status: 403),
      );

      await expectLater(
        built.service.listConversations(),
        throwsA(
          isA<ChatAuthorizationException>()
              .having((error) => error.code, 'code', 'DRIVER_INACTIVE'),
        ),
      );
    });

    test('429 carries the Retry-After the backend sent', () async {
      final built = _build(
        (_) => _json(
          _failure('CHAT_RATE_LIMITED'),
          status: 429,
          headers: <String, List<String>>{
            'retry-after': <String>['7'],
          },
        ),
      );

      await expectLater(
        built.service.sendMessage(
          conversationId: 3001,
          message: 'hello',
          clientMessageId: DriverChatService.generateClientMessageId(),
        ),
        throwsA(
          isA<ChatRateLimitException>()
              .having((error) => error.retryAfterSeconds, 'retryAfter', 7)
              .having((error) => error.isRetryable, 'isRetryable', true),
        ),
      );
    });

    test('a 200 carrying success:false is still an error', () async {
      final built = _build((_) => _json(_failure('INVALID_REQUEST')));

      await expectLater(
        built.service.listConversations(),
        throwsA(isA<ChatServerException>()),
      );
    });

    test('a non-JSON body never reaches the UI as a raw error', () async {
      final built = _build(
        (_) => ResponseBody.fromString('<html>502</html>', 502),
      );

      await expectLater(
        built.service.listConversations(),
        throwsA(
          isA<ChatServerException>()
              .having((error) => error.code, 'code', 'INVALID_RESPONSE'),
        ),
      );
    });

    test('a cancelled request is reported as cancelled, not as a failure',
        () async {
      final token = CancelToken();
      final built = _build((_) {
        token.cancel('test');
        return _json(_envelope(const {'unread_count': 0}));
      });

      await expectLater(
        built.service.getUnreadCount(cancelToken: token),
        throwsA(
          isA<ChatNetworkException>()
              .having((error) => error.code, 'code', 'REQUEST_CANCELLED'),
        ),
      );
    });
  });

  group('response parsing', () {
    test('a negative unread_count is clamped rather than shown', () async {
      final built = _build(
        (_) => _json(_envelope(const {'unread_count': -3})),
      );

      expect(await built.service.getUnreadCount(), 0);
    });

    test('list_conversations maps the page and its pagination block', () async {
      final built = _build(
        (_) => _json(_envelope(const {
          'conversations': [
            {
              'conversation_id': 3001,
              'conversation_type': 'shipment_driver',
              'shipment_id': 77,
              'policy_num': 'BLK-0077',
              'shipment_status_id': 4,
              'title': 'Shipment BLK-0077',
              'last_message': 'On my way',
              'last_message_type': 'text',
              'last_message_sender_role': 'driver',
              'unread_count': 1,
            },
          ],
          'pagination': {
            'page': 1,
            'limit': 15,
            'total': 2,
            'total_pages': 1,
          },
        })),
      );

      final page = await built.service.listConversations();

      expect(page.conversations, hasLength(1));
      expect(page.conversations.single.shipmentStatusId, 4);
      expect(page.pagination.total, 2);
      expect(page.pagination.hasNextPage, isFalse);
    });
  });
  group('get_or_create_shipment_conversation', () {
    Map<String, dynamic> conversationEnvelope(
      int shipmentId, {
      String type = 'shipment_driver',
      bool isCreated = true,
    }) {
      return _envelope({
        'conversation': {
          'conversation_id': 3001,
          'conversation_type': type,
          'shipment_id': shipmentId,
          'policy_num': 'BLK-0077',
          'shipment_status_id': 4,
          'title': 'Admin / Operations',
          'last_message': 'Please confirm pickup',
          'last_message_type': 'text',
          'last_message_sender_role': 'admin',
          'last_message_at': '2026-09-15T09:30:00Z',
          'unread_count': 2,
        },
        'is_created': isCreated,
      });
    }

    test('sends shipment_id and nothing else', () async {
      final built = _build((_) => _json(conversationEnvelope(77)));

      final result =
          await built.service.getOrCreateShipmentConversation(shipmentId: 77);

      final request = built.adapter.requests.single;
      expect(request.options.method, 'POST');
      expect(
        request.body,
        'action=get_or_create_shipment_conversation&shipment_id=77',
      );
      expect(result.isCreated, isTrue);
      expect(result.conversation.conversationId, 3001);
      expect(result.conversation.unreadCount, 2);
      expect(result.conversation.shipmentStatusId, 4);
    });

    test('an existing thread reports is_created false', () async {
      final built = _build(
        (_) => _json(conversationEnvelope(77, isCreated: false)),
      );

      final result =
          await built.service.getOrCreateShipmentConversation(shipmentId: 77);

      expect(result.isCreated, isFalse);
      expect(result.conversation.conversationId, 3001);
    });

    test('an answer about a different shipment is refused', () async {
      final built = _build((_) => _json(conversationEnvelope(99)));

      await expectLater(
        built.service.getOrCreateShipmentConversation(shipmentId: 77),
        throwsA(
          isA<ChatServerException>()
              .having((error) => error.code, 'code', 'INVALID_RESPONSE'),
        ),
      );
    });

    test('a non-shipment conversation is refused', () async {
      final built = _build(
        (_) => _json(conversationEnvelope(77, type: 'admin_driver')),
      );

      await expectLater(
        built.service.getOrCreateShipmentConversation(shipmentId: 77),
        throwsA(
          isA<ChatServerException>()
              .having((error) => error.code, 'code', 'INVALID_RESPONSE'),
        ),
      );
    });

    test('an invalid shipment id never leaves the device', () async {
      final built = _build((_) => _json(_envelope(const {})));

      await expectLater(
        built.service.getOrCreateShipmentConversation(shipmentId: 0),
        throwsA(isA<ChatValidationException>()),
      );
      expect(built.adapter.requests, isEmpty);
    });

    test('a denied shipment surfaces as an authorization error', () async {
      final built = _build(
        (_) => _json(_failure('CHAT_ACCESS_DENIED'), status: 403),
      );

      await expectLater(
        built.service.getOrCreateShipmentConversation(shipmentId: 77),
        throwsA(
          isA<ChatAuthorizationException>()
              .having((error) => error.code, 'code', 'CHAT_ACCESS_DENIED'),
        ),
      );
    });
  });
}
