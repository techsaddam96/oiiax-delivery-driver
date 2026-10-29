import 'package:dio/dio.dart';

import '../constants/app_urls.dart';

/// How a support submission ended, in terms the app owns.
///
/// The endpoint's own prose is not part of this. It once reached the screen
/// verbatim, which meant an Arabic driver could be shown an English sentence —
/// including `"Database error: prepare failed."`, which is what the backend
/// sends for `DB_PREPARE_ERROR`.
enum SupportMessageOutcome { sent, rejected, network, unknown }

class SupportMessageResult {
  const SupportMessageResult(this.outcome, {this.serverMessage});

  final SupportMessageOutcome outcome;

  /// The endpoint's message in the **requested language only**, when it sent
  /// one, and never a cross-language fallback. The page decides whether to
  /// show it; nothing here obliges it to.
  final String? serverMessage;

  bool get isSuccess => outcome == SupportMessageOutcome.sent;
}

class ClientMessageService {
  static final Dio _dio = Dio();

  static Future<SupportMessageResult> sendClientMessage({
    required String firstname,
    required String lastname,
    required String phone,
    required String email,
    required String message,
    String languageCode = 'en',
  }) async {
    final lang = languageCode.toLowerCase().startsWith('ar') ? 'ar' : 'en';
    try {
      final response = await _dio.post(
        '${AppUrls.baseUrl}/api_client_messages.php?lang=$lang',
        data: {
          'firstname': firstname,
          'lastname': lastname,
          'phone': phone,
          'email': email,
          'message': message,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'Accept': 'application/json', 'Accept-Language': lang},
          validateStatus: (_) => true,
        ),
      );

      final data = response.data;
      final isSuccess =
          response.statusCode == 200 &&
          data is Map &&
          data['status']?.toString().toLowerCase() == 'success';

      return SupportMessageResult(
        isSuccess ? SupportMessageOutcome.sent : SupportMessageOutcome.rejected,
        serverMessage: _sameLanguageMessage(data, lang),
      );
    } on DioException {
      return const SupportMessageResult(SupportMessageOutcome.network);
    } catch (_) {
      return const SupportMessageResult(SupportMessageOutcome.unknown);
    }
  }

  /// The endpoint's message for [lang] and nothing else.
  ///
  /// There is deliberately no fallback to the other language, and none to the
  /// untyped `message` key: that key carries whatever the endpoint happened to
  /// produce, in whatever language it was written in, which is exactly how
  /// English backend prose used to end up in front of an Arabic driver.
  static String? _sameLanguageMessage(dynamic data, String lang) {
    if (data is! Map) return null;
    final value = lang == 'ar' ? data['message_ar'] : data['message_en'];
    final text = value?.toString().trim();
    return (text == null || text.isEmpty) ? null : text;
  }
}
