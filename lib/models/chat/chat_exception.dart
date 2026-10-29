class ChatException implements Exception {
  const ChatException({
    required this.safeMessage,
    required this.isRetryable,
    this.statusCode,
    this.code,
    this.retryAfterSeconds,
    this.messageEn,
    this.messageAr,
  });

  final String safeMessage;
  final int? statusCode;
  final String? code;
  final int? retryAfterSeconds;
  final bool isRetryable;
  final String? messageEn;
  final String? messageAr;

  @override
  String toString() => 'ChatException($code, $statusCode)';
}

class ChatAuthenticationException extends ChatException {
  const ChatAuthenticationException({
    super.safeMessage = 'chat_authentication_required',
    super.statusCode = 401,
    super.code = 'UNAUTHORIZED',
    super.messageEn,
    super.messageAr,
  }) : super(isRetryable: false);
}

class ChatAuthorizationException extends ChatException {
  const ChatAuthorizationException({
    super.safeMessage = 'chat_access_denied',
    super.statusCode = 403,
    super.code = 'CHAT_ACCESS_DENIED',
    super.messageEn,
    super.messageAr,
  }) : super(isRetryable: false);
}

class ChatValidationException extends ChatException {
  const ChatValidationException({
    super.safeMessage = 'chat_invalid_request',
    super.statusCode = 400,
    super.code = 'INVALID_REQUEST',
    super.messageEn,
    super.messageAr,
  }) : super(isRetryable: false);
}

class ChatRateLimitException extends ChatException {
  const ChatRateLimitException({
    super.safeMessage = 'chat_rate_limited',
    super.statusCode = 429,
    super.code = 'CHAT_RATE_LIMITED',
    super.retryAfterSeconds,
    super.messageEn,
    super.messageAr,
  }) : super(isRetryable: true);
}

class ChatConflictException extends ChatException {
  const ChatConflictException({
    super.safeMessage = 'chat_message_conflict',
    super.statusCode = 409,
    super.code = 'CHAT_MESSAGE_CONFLICT',
    super.messageEn,
    super.messageAr,
  }) : super(isRetryable: false);
}

class ChatNetworkException extends ChatException {
  const ChatNetworkException({
    super.safeMessage = 'chat_network_error',
    super.code = 'NETWORK_ERROR',
    super.isRetryable = true,
  });
}

class ChatServerException extends ChatException {
  const ChatServerException({
    super.safeMessage = 'chat_server_error',
    super.statusCode,
    super.code = 'SERVER_ERROR',
    super.messageEn,
    super.messageAr,
    super.isRetryable = true,
  });
}
