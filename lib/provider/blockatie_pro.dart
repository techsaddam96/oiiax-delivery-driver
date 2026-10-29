import 'dart:developer';
import 'dart:io';

import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/models/packages.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/session_dio.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/views/dialoges/alert_dialoge.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class BlockatiePro extends UserScopedNotifier {
  PackageResponse? packeges;
  bool isLoading = false;

  // The package catalogue itself is global, but it is fetched under a driver
  // session, so drop the in-flight loading state at the account boundary.
  @override
  void clearUserState() {
    packeges = null;
    isLoading = false;
  }

  Future<void> getPackages() async {
    isLoading = true;
    notifyListeners();
    final apiKey = await AuthService.getApiKey();
    try {
      final dio = sessionDio();

      final url = AppUrls.getpackages;

      final response = await dio.get(
        url,
        options: Options(headers: {'X-API-KEY': apiKey}),
      );
      isLoading = false;
      notifyListeners();
      if (response.statusCode == 200 && response.data != null) {
        if (response.data is Map<String, dynamic>) {
          final data = response.data as Map<String, dynamic>;

          if (data['success'] == true && data['packages'] != null) {
            packeges = PackageResponse.fromJson(data);
            log('✅ packages fetched: ${packeges?.packages.length}');

            notifyListeners();
          } else {
            // AppUtils.errorToast(errorMsg);
            return;
          }
        } else {
          log('❌ Response data is not a Map: ${response.data.runtimeType}');
          showAlertDialog(Nav.context, 'Error', 'error while fetching clients');
          return;
        }
      } else {
        showAlertDialog(Nav.context, 'Error', 'server error');
        return;
      }
    } on DioException catch (e) {
      isLoading = false;
      notifyListeners();
      // ... existing error handling code remains the same
      final statusCode = e.response?.statusCode;
      final errorType = e.type;
      final message = e.message ?? 'No message';

      log('❌ === DIO ERROR DEBUG ===');
      log('❌ Error Type: $errorType');
      log('❌ Status Code: $statusCode');
      log('❌ Error Message: $message');
      log('❌ Request URL: ${e.requestOptions.uri}');

      String userMessage = "Connection failed";

      switch (errorType) {
        case DioExceptionType.connectionTimeout:
          userMessage = "Connection timeout";
          break;
        case DioExceptionType.sendTimeout:
          userMessage = "Send timeout";
          break;
        case DioExceptionType.receiveTimeout:
          userMessage = "Receive timeout";
          break;
        case DioExceptionType.badResponse:
          userMessage = "Server error: ${statusCode ?? 'Unknown'}";
          break;
        case DioExceptionType.cancel:
          userMessage = "Request cancelled";
          break;
        case DioExceptionType.unknown:
          if (e.error is SocketException) {
            userMessage = "Network connection failed";
          } else if (e.error is HandshakeException) {
            userMessage = "SSL Certificate error";
          } else {
            userMessage = "Connection failed: Unknown error";
          }
          break;
        default:
          userMessage = "Network error occurred";
      }

      log('Package request message: $userMessage');
      return;
    } catch (e, stack) {
      isLoading = false;
      notifyListeners();
      log('❌ Unexpected error type: ${e.runtimeType}');
      log('❌ Error type: ${e.runtimeType}');
      log('Stacktrace type: ${stack.runtimeType}');
      // AppUtils.errorToast("Something went wrong: $e");
      return;
    }
  }
}
