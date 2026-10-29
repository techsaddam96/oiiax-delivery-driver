import 'dart:convert';
import 'dart:math';

import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/models/chat/chat_api_response.dart';
import 'package:blockatie/models/chat/chat_exception.dart';
import 'package:blockatie/models/chat/chat_parsing.dart';
import 'package:blockatie/models/chat/driver_chat_message.dart';
import 'package:blockatie/models/chat/driver_chat_pagination.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/session_dio.dart';
import 'package:dio/dio.dart';

typedef DriverChatApiKeyLoader = Future<String?> Function();

/// Transport contract, so providers can be tested against a fake.
///
/// Every method reports failure through the returned Future, including local
/// validation. Nothing throws synchronously, so a caller can rely on one error
/// path rather than needing a try/catch around the call itself as well.
abstract interface class DriverChatRepository {
  Future<DriverChatConversationPage> listConversations({
    int page = 1,
    int limit = 15,
    CancelToken? cancelToken,
  });

  Future<DriverChatMessagesPage> getMessages({
    required int conversationId,
    int? beforeMessageId,
    int limit = 30,
    CancelToken? cancelToken,
  });

  Future<DriverChatNewMessagesPage> getNewMessages({
    required int conversationId,
    required int afterMessageId,
    int limit = 50,
    CancelToken? cancelToken,
  });

  Future<DriverChatSendResult> sendMessage({
    required int conversationId,
    required String message,
    required String clientMessageId,
    CancelToken? cancelToken,
  });

  Future<DriverChatReadResult> markRead({
    required int conversationId,
    int? lastMessageId,
    CancelToken? cancelToken,
  });

  Future<int> getUnreadCount({CancelToken? cancelToken});

  Future<DriverChatConversationResult> getOrCreateShipmentConversation({
    required int shipmentId,
    CancelToken? cancelToken,
  });
}

/// Driver Chat transport.
///
/// Every call goes through [sessionDio], so the existing session interceptor
/// still sees the response: a 401, or a 403 carrying DRIVER_INACTIVE, ends the
/// driver session exactly as it does for every other Driver API. Nothing about
/// authentication is reimplemented here.
///
/// The request payloads deliberately never contain driver_id, user_id,
/// account_id, client_id, participant_id, sender_id or reader_id — the backend
/// rejects all of them, and identity comes only from the X-API-KEY header.
class DriverChatService implements DriverChatRepository {
  DriverChatService({Dio? dio, DriverChatApiKeyLoader? apiKeyLoader})
    : _dio =
          dio ??
          sessionDio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 15),
              headers: const {'Accept': 'application/json'},
              // The envelope carries the real outcome, so non-2xx bodies must
              // reach us to be mapped rather than being thrown away by Dio.
              validateStatus: (_) => true,
            ),
          ),
      _apiKeyLoader = apiKeyLoader ?? AuthService.getApiKey;

  final Dio _dio;
  final DriverChatApiKeyLoader _apiKeyLoader;

  static final Random _secureRandom = Random.secure();

  /// Mirrors the backend limits so obviously-invalid input fails locally
  /// instead of costing a round trip. The server remains the authority.
  static const int maximumMessageLength = 2000;
  static const int conversationsMaxLimit = 50;
  static const int messagesMaxLimit = 50;
  static const int newMessagesMaxLimit = 100;

  static final RegExp _clientMessageIdPattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9._:-]*$',
  );

  /// Idempotency key for a send.
  ///
  /// Uses [Random.secure] plus a microsecond timestamp so two devices, or the
  /// same device after a restart, cannot collide. The `driver-chat-` prefix
  /// keeps Driver keys visually distinct from Client ones in logs; the backend
  /// namespace is already separated by sender_role, so this is for humans.
  ///
  /// A retry MUST reuse the id from the original attempt — generating a new one
  /// would defeat the backend's idempotency and store the message twice.
  static String generateClientMessageId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final randomPart =
        List<String>.generate(
          4,
          (_) => _secureRandom
              .nextInt(0x100000000)
              .toRadixString(16)
              .padLeft(8, '0'),
        ).join();
    return 'driver-chat-$timestamp-$randomPart';
  }

  @override
  Future<DriverChatConversationPage> listConversations({
    int page = 1,
    int limit = 15,
    CancelToken? cancelToken,
  }) async {
    _validatePositiveId(page, 'page');
    _validateLimit(limit, maximum: conversationsMaxLimit);

    return _get(
      parameters: <String, dynamic>{
        'action': 'list_conversations',
        'page': page,
        'limit': limit,
      },
      parser: DriverChatConversationPage.fromJson,
      cancelToken: cancelToken,
    );
  }

  @override
  Future<DriverChatMessagesPage> getMessages({
    required int conversationId,
    int? beforeMessageId,
    int limit = 30,
    CancelToken? cancelToken,
  }) async {
    _validatePositiveId(conversationId, 'conversation_id');
    _validateLimit(limit, maximum: messagesMaxLimit);
    if (beforeMessageId != null && beforeMessageId <= 0) {
      throw const ChatValidationException(
        code: 'INVALID_CURSOR',
        safeMessage: 'chat_invalid_cursor',
      );
    }

    final parameters = <String, dynamic>{
      'action': 'list_messages',
      'conversation_id': conversationId,
      'limit': limit,
    };
    if (beforeMessageId != null) {
      parameters['before_message_id'] = beforeMessageId;
    }

    return _get(
      parameters: parameters,
      parser: DriverChatMessagesPage.fromJson,
      cancelToken: cancelToken,
    );
  }

  @override
  Future<DriverChatNewMessagesPage> getNewMessages({
    required int conversationId,
    required int afterMessageId,
    int limit = 50,
    CancelToken? cancelToken,
  }) async {
    _validatePositiveId(conversationId, 'conversation_id');
    _validateLimit(limit, maximum: newMessagesMaxLimit);
    // Zero is legal and means "from the beginning of the thread".
    if (afterMessageId < 0) {
      throw const ChatValidationException(
        code: 'INVALID_CURSOR',
        safeMessage: 'chat_invalid_cursor',
      );
    }

    return _get(
      parameters: <String, dynamic>{
        'action': 'list_new_messages',
        'conversation_id': conversationId,
        'after_message_id': afterMessageId,
        'limit': limit,
      },
      parser: DriverChatNewMessagesPage.fromJson,
      cancelToken: cancelToken,
    );
  }

  @override
  Future<DriverChatSendResult> sendMessage({
    required int conversationId,
    required String message,
    required String clientMessageId,
    CancelToken? cancelToken,
  }) async {
    _validatePositiveId(conversationId, 'conversation_id');
    final normalized = message.trim();
    if (normalized.isEmpty) {
      throw const ChatValidationException(
        code: 'EMPTY_MESSAGE',
        safeMessage: 'chat_message_required',
      );
    }
    if (normalized.runes.length > maximumMessageLength) {
      throw const ChatValidationException(
        code: 'MESSAGE_TOO_LONG',
        safeMessage: 'chat_message_too_long',
      );
    }
    _validateClientMessageId(clientMessageId);

    final payload = await _post(
      data: <String, dynamic>{
        'action': 'send_message',
        'conversation_id': conversationId,
        'message': normalized,
        'client_message_id': clientMessageId,
      },
      parser: (data) => chatJsonMap(data['message'], fieldName: 'message'),
      cancelToken: cancelToken,
    );

    final responseConversationId = chatRequiredPositiveInt(
      payload['conversation_id'],
      fieldName: 'conversation_id',
    );
    final responseClientMessageId = chatString(payload['client_message_id']);

    // The server must be answering about the exact message we asked it to
    // store. If it is not, something is wrong upstream and we refuse the
    // response rather than reconciling an optimistic row against the wrong id.
    if (responseConversationId != conversationId ||
        responseClientMessageId != clientMessageId) {
      throw const ChatServerException(
        code: 'INVALID_RESPONSE',
        safeMessage: 'chat_invalid_server_response',
        isRetryable: false,
      );
    }

    return DriverChatSendResult(
      message: DriverChatMessage(
        messageId: chatRequiredPositiveInt(
          payload['message_id'],
          fieldName: 'message_id',
        ),
        conversationId: responseConversationId,
        // The send contract returns identity-free metadata only, so these are
        // filled in from what we know locally: the sender is this driver.
        senderRole: 'driver',
        senderName: '',
        messageType: 'text',
        message: normalized,
        isMine: true,
        isRead: false,
        createdAt: chatDateTime(
          payload['created_at_utc'] ?? payload['created_at'],
        ),
        clientMessageId: responseClientMessageId,
        status: DriverChatMessageStatus.sent,
      ),
      isDuplicate: chatBool(payload['is_duplicate']),
    );
  }

  @override
  Future<DriverChatReadResult> markRead({
    required int conversationId,
    int? lastMessageId,
    CancelToken? cancelToken,
  }) async {
    _validatePositiveId(conversationId, 'conversation_id');
    if (lastMessageId != null && lastMessageId <= 0) {
      throw const ChatValidationException(
        code: 'INVALID_LAST_READ_MESSAGE',
        safeMessage: 'chat_invalid_last_read_message',
      );
    }

    final data = <String, dynamic>{
      'action': 'mark_read',
      'conversation_id': conversationId,
    };
    // Omitted means "clear the whole thread", which is what the Driver backend
    // does when the cursor is absent.
    if (lastMessageId != null) {
      data['last_message_id'] = lastMessageId;
    }

    return _post(
      data: data,
      parser: DriverChatReadResult.fromJson,
      cancelToken: cancelToken,
    );
  }

  @override
  Future<int> getUnreadCount({CancelToken? cancelToken}) async {
    final count = await _get(
      parameters: const <String, dynamic>{'action': 'unread_count'},
      parser: (data) => chatInt(data['unread_count']) ?? 0,
      cancelToken: cancelToken,
    );
    return count < 0 ? 0 : count;
  }

  /// The thread for one of this driver's shipments, opening it if needed.
  ///
  /// `shipment_id` is the only field sent. Which driver the thread belongs to,
  /// and that the shipment is theirs, are both decided server-side from the API
  /// key — this call cannot name an owner or a conversation type.
  @override
  Future<DriverChatConversationResult> getOrCreateShipmentConversation({
    required int shipmentId,
    CancelToken? cancelToken,
  }) async {
    _validatePositiveId(shipmentId, 'shipment_id');

    final result = await _post(
      data: <String, dynamic>{
        'action': 'get_or_create_shipment_conversation',
        'shipment_id': shipmentId,
      },
      parser: DriverChatConversationResult.fromJson,
      cancelToken: cancelToken,
    );

    // The answer must be about the shipment that was asked about, and must be
    // a shipment thread. Anything else is refused rather than opened.
    if (result.conversation.shipmentId != shipmentId ||
        !result.conversation.isShipmentConversation) {
      throw const ChatServerException(
        code: 'INVALID_RESPONSE',
        safeMessage: 'chat_invalid_server_response',
        isRetryable: false,
      );
    }

    return result;
  }

  // -------------------------------------------------------------------------
  // Transport
  // -------------------------------------------------------------------------

  Future<T> _get<T>({
    required Map<String, dynamic> parameters,
    required T Function(Map<String, dynamic> data) parser,
    CancelToken? cancelToken,
  }) {
    return _request(
      method: 'GET',
      queryParameters: parameters,
      parser: parser,
      cancelToken: cancelToken,
    );
  }

  Future<T> _post<T>({
    required Map<String, dynamic> data,
    required T Function(Map<String, dynamic> data) parser,
    CancelToken? cancelToken,
  }) {
    return _request(
      method: 'POST',
      data: data,
      parser: parser,
      cancelToken: cancelToken,
    );
  }

  Future<T> _request<T>({
    required String method,
    required T Function(Map<String, dynamic> data) parser,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? data,
    CancelToken? cancelToken,
  }) async {
    final apiKey = (await _apiKeyLoader())?.trim() ?? '';
    if (apiKey.isEmpty) {
      // No credential means no session; fail before touching the network.
      throw const ChatAuthenticationException();
    }

    try {
      final response = await _dio.request<dynamic>(
        AppUrls.driverChat,
        queryParameters: queryParameters,
        data: data,
        cancelToken: cancelToken,
        options: Options(
          method: method,
          contentType:
              method == 'POST' ? Headers.formUrlEncodedContentType : null,
          headers: {'Accept': 'application/json', 'X-API-KEY': apiKey},
        ),
      );

      final json = _decodeResponse(response.data);
      final envelope = ChatApiResponse<Map<String, dynamic>>.fromJson(
        json,
        (data) => data,
      );

      final statusCode = response.statusCode;
      if (statusCode == null ||
          statusCode < 200 ||
          statusCode >= 300 ||
          !envelope.success) {
        throw _httpException(statusCode, envelope, response.headers);
      }
      return parser(envelope.data);
    } on ChatException {
      rethrow;
    } on FormatException {
      throw const ChatServerException(
        code: 'INVALID_RESPONSE',
        safeMessage: 'chat_invalid_server_response',
        isRetryable: false,
      );
    } on DioException catch (error) {
      throw _dioException(error);
    } catch (_) {
      // Never surface a raw error object to the UI.
      throw const ChatServerException();
    }
  }

  static Map<String, dynamic> _decodeResponse(dynamic body) {
    if (body is String) {
      final normalized = body.trim();
      if (normalized.isEmpty) {
        throw const FormatException('Empty chat response');
      }
      return chatJsonMap(jsonDecode(normalized), fieldName: 'response');
    }
    return chatJsonMap(body, fieldName: 'response');
  }

  static ChatException _httpException<T>(
    int? statusCode,
    ChatApiResponse<T> response,
    Headers headers,
  ) {
    final code = response.code.isEmpty ? null : response.code;
    final messageEn = response.messageEn.isEmpty ? null : response.messageEn;
    final messageAr = response.messageAr.isEmpty ? null : response.messageAr;

    switch (statusCode) {
      case 401:
        return ChatAuthenticationException(
          code: code,
          messageEn: messageEn,
          messageAr: messageAr,
        );
      case 403:
        // Includes DRIVER_INACTIVE. The session interceptor has already seen
        // this response and started teardown; we only shape the error.
        return ChatAuthorizationException(
          code: code,
          messageEn: messageEn,
          messageAr: messageAr,
        );
      case 400:
      case 404:
      case 422:
        return ChatValidationException(
          code: code,
          messageEn: messageEn,
          messageAr: messageAr,
        );
      case 409:
        return ChatConflictException(
          code: code,
          messageEn: messageEn,
          messageAr: messageAr,
        );
      case 429:
        return ChatRateLimitException(
          code: code,
          retryAfterSeconds: int.tryParse(headers.value('retry-after') ?? ''),
          messageEn: messageEn,
          messageAr: messageAr,
        );
      default:
        return ChatServerException(
          statusCode: statusCode,
          code: code,
          messageEn: messageEn,
          messageAr: messageAr,
        );
    }
  }

  static ChatException _dioException(DioException error) {
    if (error.type == DioExceptionType.cancel) {
      return const ChatNetworkException(
        code: 'REQUEST_CANCELLED',
        safeMessage: 'chat_request_cancelled',
        isRetryable: false,
      );
    }
    return const ChatNetworkException();
  }

  static void _validatePositiveId(int value, String fieldName) {
    if (value <= 0) {
      throw ChatValidationException(
        code: 'INVALID_${fieldName.toUpperCase()}',
        safeMessage: 'chat_invalid_request',
      );
    }
  }

  static void _validateLimit(int limit, {required int maximum}) {
    if (limit <= 0 || limit > maximum) {
      throw const ChatValidationException(
        code: 'INVALID_LIMIT',
        safeMessage: 'chat_invalid_request',
      );
    }
  }

  static void _validateClientMessageId(String clientMessageId) {
    final length = clientMessageId.length;
    if (length < 8 ||
        length > 100 ||
        !_clientMessageIdPattern.hasMatch(clientMessageId)) {
      throw const ChatValidationException(
        code: 'INVALID_CLIENT_MESSAGE_ID',
        safeMessage: 'chat_invalid_client_message_id',
      );
    }
  }
}
