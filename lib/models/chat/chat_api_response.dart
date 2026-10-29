import 'chat_parsing.dart';

class ChatApiResponse<T> {
  const ChatApiResponse({
    required this.success,
    required this.status,
    required this.code,
    required this.message,
    required this.messageEn,
    required this.messageAr,
    required this.data,
  });

  final bool success;
  final String status;
  final String code;
  final String message;
  final String messageEn;
  final String messageAr;
  final T data;

  factory ChatApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic> data) parseData,
  ) {
    return ChatApiResponse<T>(
      success: chatBool(json['success']),
      status: chatString(json['status']),
      code: chatString(json['code']),
      message: chatString(json['message']),
      messageEn: chatString(json['message_en']),
      messageAr: chatString(json['message_ar']),
      data: parseData(
        chatJsonMap(json['data'], fieldName: 'data', allowNull: true),
      ),
    );
  }
}
