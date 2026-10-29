import 'dart:developer';

import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/constants/helper.dart';
import 'package:blockatie/models/order_status_modle.dart';
import 'package:blockatie/models/statistics.dart';
import 'package:blockatie/provider/shipment.dart';
import 'package:blockatie/provider/shipment_instsnt.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/request_id_service.dart';
import 'package:blockatie/services/session_dio.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/views/dialoges/alert_dialoge.dart';
import 'package:blockatie/views/dialoges/sucess_dialoge.dart';
import 'package:blockatie/views/pages/home/tabs/all-shipments/table_all_shipment.dart';
import 'package:blockatie/views/pages/home/tabs/shipment-instant/shipment_instant.dart';
import 'package:blockatie/views/pages/hub/support&assistance/support_assistence.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HomeProvider extends UserScopedNotifier with Helper {
  // Statistics and the driver name are account data and must not survive logout.
  @override
  void clearUserState() {
    isLoading = true;
    driverStats = null;
    orderStatusData = null;
    driverName = null;
    statisticsError = null;
    orderStatusError = null;
    isStatusLoading = false;
    _isFetchingStatistics = false;
    _isFetchingOrderStatus = false;
    _isUpdatingStatus = false;
    query = '';
  }

  int _selectedTabIndex = -1; // -1 means no tab selected yet

  int get selectedTabIndex => _selectedTabIndex;
  final List<Widget> tabViews = const [
    TableAllShipment(),
    ShipmentInstantPage(),
    SupportAssistencePage(showAppBar: false),
  ];

  void setSelectedTab(int index) {
    _selectedTabIndex = index;
    notifyListeners();
  }

  void resetTab() {
    _selectedTabIndex = -1;
    notifyListeners();
  }

  void resetToHome() {
    _selectedTabIndex = -1;
    notifyListeners();
  }

  String query = '';

  String getDeliveryTypeNameById(int id) {
    switch (id) {
      case 1:
        return getLocalizedTypeName('Instant', 'فوري');
      case 2:
        return getLocalizedTypeName('Scheduled', 'مجدول');
      case 3:
        return getLocalizedTypeName('Same-Day', 'نفس اليوم');
      case 4:
        return getLocalizedTypeName('Next-Day', 'اليوم التالي');
      case 5:
        return getLocalizedTypeName('Economy', 'اقتصاد');
      case 6:
        return getLocalizedTypeName('Express', 'يعبر');
      case 7:
        return getLocalizedTypeName('Contactless', 'تماس');
      case 11:
        return getLocalizedTypeName('Complete', 'مكتمل');
      default:
        return 'Unknown';
    }
  }

  void setQuery(String val) {
    query = val.trim().toLowerCase();
    notifyListeners();
  }

  void clear() {
    query = '';
    notifyListeners();
  }

  Future<void> refresh() async {
    await getDriverStatistics(Nav.context, force: true);
  }

  bool isLoading = true;
  DriverStatisticsData? driverStats;
  OrderStatusData? orderStatusData;
  String? driverName;
  String? statisticsError;
  String? orderStatusError;
  bool isStatusLoading = false;
  bool _isFetchingStatistics = false;
  bool _isFetchingOrderStatus = false;
  bool _isUpdatingStatus = false;

  DriverStatisticsData get safeStats =>
      driverStats ?? DriverStatisticsData.empty();

  bool get hasStatisticsError =>
      statisticsError != null && statisticsError!.trim().isNotEmpty;

  Future<void> getDriverStatistics(
    BuildContext context, {
    bool force = false,
  }) async {
    if (_isFetchingStatistics) return;
    if (driverStats != null && !force) return;

    // Statistics are balances. A reply addressed to the previous driver must
    // never be written into the next driver's cards.
    final generation = stateGeneration;
    _isFetchingStatistics = true;
    isLoading = driverStats == null;
    statisticsError = null;
    notifyListeners();

    try {
      final session = await AuthService.getSessionSnapshot();
      if (!acceptsState(generation)) return;
      driverName = await AuthService.getDrivername();
      if (!acceptsState(generation)) return;

      if (!session.isAuthenticated) {
        driverStats = DriverStatisticsData.empty();
        statisticsError = 'Missing driver session.';
        return;
      }

      final formData = FormData.fromMap({
        'driver_id': session.driverId,
        'api_key': session.apiKey,
      });

      final dio = sessionDio(BaseOptions(validateStatus: (_) => true));
      final response = await dio.post(
        AppUrls.driverStatistics,
        data: formData,
        options: Options(
          headers: {'Accept': '*/*', 'X-API-KEY': session.apiKey},
          contentType: 'multipart/form-data',
        ),
      );

      if (!acceptsState(generation)) return;

      final responseData = response.data;
      final model =
          responseData is Map
              ? DriverStatisticsModel.fromJson(
                Map<String, dynamic>.from(responseData),
              )
              : null;

      if (response.statusCode == 200 && model != null && model.success) {
        driverStats = model.data;
      } else {
        driverStats = DriverStatisticsData.empty();
        statisticsError = _messageFrom(responseData) ?? 'Unable to load data.';
      }
    } catch (e) {
      driverStats = DriverStatisticsData.empty();
      statisticsError = 'Unable to load data.';
      log("Driver statistics error: ${e.runtimeType}");
    } finally {
      _isFetchingStatistics = false;
      // After a reset the cleared state is the current one and must stand.
      if (acceptsState(generation)) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  String? _messageFrom(dynamic data) {
    if (data is! Map) return null;
    return (data['message'] ?? data['message_en'] ?? data['message_ar'])
        ?.toString();
  }

  Future<void> getOrderStatus({bool force = false}) async {
    if (_isFetchingOrderStatus && !force) return;
    if (orderStatusData != null && !force) return;
    _isFetchingOrderStatus = true;
    isStatusLoading = true;
    orderStatusError = null;
    notifyListeners();

    try {
      final dio = sessionDio();
      final response = await dio.get(
        AppUrls.getOrderStatus,
        options: Options(
          headers: {'Accept': '*/*'},
          contentType: 'multipart/form-data',
        ),
      );
      final data = response.data;
      if (response.statusCode == 200 &&
          data is Map &&
          (data['success'] == true ||
              data['status']?.toString().toLowerCase() == 'success')) {
        final model = OrderStatusData.fromJson(Map<String, dynamic>.from(data));
        orderStatusData = model;
      } else {
        orderStatusError = _messageFrom(data) ?? 'Unable to load statuses.';
      }
    } catch (e) {
      orderStatusError = 'Unable to load statuses.';
      log("Order status error: ${e.runtimeType}");
    }

    isStatusLoading = false;
    _isFetchingOrderStatus = false;
    notifyListeners();
  }

  Future<bool> updateStatus({
    required int shipmentId,
    required String statusId,
    int? reasonId,
    String? reasonNote,
    String? feeCollectedAmount,
    bool isInstant = false,
    bool showSuccessDialog = true,
  }) async {
    if (_isUpdatingStatus) return false;
    if (statusId.isEmpty) {
      showAlertDialog(
        Nav.context,
        tr('error'),
        tr('something_went_wrong'),
        showBtn: false,
      );
      return false;
    }
    _isUpdatingStatus = true;
    isLoading = true;
    // notifyListeners();

    final apiKey = await AuthService.getApiKey();
    final driverId = await AuthService.getuserId();
    if (apiKey == null || driverId == null) {
      isLoading = false;
      _isUpdatingStatus = false;
      notifyListeners();
      showAlertDialog(
        Nav.context,
        tr('error'),
        tr('something_went_wrong'),
        showBtn: false,
      );
      return false;
    }
    final requestData = {
      'shipment_id': '$shipmentId',
      'driver_id': driverId,
      'status_id': statusId,
      if (reasonId != null && reasonId > 0) 'reason_id': reasonId,
      if (reasonNote != null && reasonNote.trim().isNotEmpty)
        'note': reasonNote.trim(),
      // Door fee on a cancel/return; the server validates it against the fee due.
      if (feeCollectedAmount != null && feeCollectedAmount.isNotEmpty)
        'fee_collected_amount': feeCollectedAmount,
    };
    final formData = FormData.fromMap(requestData);
    try {
      final dio = sessionDio();
      final lease = RequestIdService.acquire(
        operation: 'driver.updateShipmentStatus',
        payload: requestData,
      );
      final response = await dio.postUri(
        data: formData,

        Uri.parse(AppUrls.updateStatus),
        options: Options(
          headers: {'Accept': '*/*', 'X-API-KEY': apiKey, ...lease.headers()},
          contentType: 'multipart/form-data',
        ),
      );
      lease.complete();

      if (response.statusCode == 200 && response.data['success'] == true) {
        if (!isInstant) {
          final shipmentprovider = Provider.of<ShipmentProvider>(
            Nav.context,
            listen: false,
          );
          shipmentprovider.getAllShipments();
        }
        if (isInstant) {
          Provider.of<ShipmentInstantprovider>(
            Nav.context,
            listen: false,
          ).getShipmentsInstant();
        }

        notifyListeners();

        if (showSuccessDialog) {
          showSucessDialoge(
            Nav.context,
            tr('success'),
            getLocalizedTypeName(
              response.data['message_en'] ?? 'Shipment status updated.',
              response.data['message_ar'] ?? 'Shipment status updated.',
            ),
          );
        }
        isLoading = false;
        _isUpdatingStatus = false;
        notifyListeners();
        return true;
        // driverStats = model.data ?? DriverStatisticsData.empty();
      } else {
        showAlertDialog(
          Nav.context,
          tr('error'),
          getLocalizedTypeName(
            response.data['message_en'] ?? 'Unknown error occurred.',
            response.data['message_ar'] ?? 'Unknown error occurred.',
          ),
          showBtn: false,
        );
      }
    } catch (e) {
      showAlertDialog(
        Nav.context,
        tr('error'),
        tr('something_went_wrong'),
        showBtn: false,
      );
    }

    isLoading = false;
    _isUpdatingStatus = false;
    notifyListeners();
    return false;
  }

  Future<void> getShipmentStatus(int shipmentId) async {
    try {
      final dio = sessionDio();

      final userId = await AuthService.getuserId();
      final apiKey = await AuthService.getApiKey();

      if (userId == null || apiKey == null) {
        // AppUtils.errorToast('Missing user ID or API key');
        return;
      }

      final response = await dio.postUri(
        Uri.parse(AppUrls.getShipmentStatus),
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-API-KEY': apiKey,
          },
        ),
        data: {'shipment_id': shipmentId},
      );

      if (response.data != null && response.data is Map<String, dynamic>) {
        if (response.statusCode == 200 &&
            response.data['status'] == 'success') {
          notifyListeners();
        } else {
          // AppUtils.errorToast(
          //   response.data['message'] ?? 'Failed to load profile',
          // );
        }
      } else {
        // AppUtils.errorToast("Invalid response format from server");
      }

      return;
    } on DioException catch (e) {
      final msg = e.response?.data.toString() ?? e.message;
      log('❌ Dio error: $msg');
      // AppUtils.errorToast("Error: $msg");
      return;
    } catch (e) {
      log('❌ Unexpected error: $e');
      // AppUtils.errorToast("Something went wrong");
      return;
    }
  }
}
