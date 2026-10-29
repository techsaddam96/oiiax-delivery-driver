// import 'dart:developer';

// import 'package:blockatie/constants/app_urls.dart';
// import 'package:blockatie/models/shipment_status.dart';
// import 'package:blockatie/services/auth_services.dart';
// import 'package:blockatie/utils/app_utils.dart';
// import 'package:dio/dio.dart';
//
// class OrderStatusProvider extends ChangeNotifier {
//   String _currentStatus = 'Order Placed';
//   int _currentStatusIndex = 0;
//   int _inProgressSubState = 0; // 0: partner assigned, 1: out for delivery
//   String? status;
//   String? statusMsg;
//   Future<ShipmentStatus?> getShipmentStatus(int shipmentId) async {
//     try {
//       final dio = sessionDio();
//       final userId = await AuthService.getuserId();
//       final apiKey = await AuthService.getApiKey();

//       if (userId == null || apiKey == null) {
//         AppUtils.errorToast('Missing user ID or API key');
//         return null;
//       }

//       final response = await dio.postUri(
//         Uri.parse(AppUrls.getShipmentStatus),
//         options: Options(
//           headers: {
//             'Content-Type': 'application/x-www-form-urlencoded',
//             'X-API-KEY': apiKey,
//           },
//         ),
//         data: {
//           'shipment_id': shipmentId,
//         },
//       );

//       if (response.statusCode == 200 &&
//           response.data != null &&
//           response.data['status'] == 'success') {
//         final data = ShipmentStatusResponse.fromJson(response.data);
//         status = data.shipmentStatus.statusNameEn;
//         statusMsg = data.shipmentStatus.messageEn;
//         log('order status >> $status');

//         notifyListeners();
//         return data.shipmentStatus;
//       } else {
//         AppUtils.errorToast(
//             response.data['message'] ?? 'Failed to load status');
//         return null;
//       }
//     } on DioException catch (e) {
//       final msg = e.response?.data.toString() ?? e.message;
//       log('❌ Dio error: $msg');
//       AppUtils.errorToast("Error: $msg");
//       return null;
//     } catch (e) {
//       log('❌ Unexpected error: $e');
//       AppUtils.errorToast("Something went wrong");
//       return null;
//     }
//   }

//   final List<String> _statuses = [
//     'Pending',
//     'Processing',
//     'Dispatched',
//     'In Transit',
//     'Out for Delivery',
//     'Delivered',
//     'Cancelled',
//     'Returned',
//     'Failed Delivery',
//     'Awaiting Pickup',
//     'Completed'
//   ];

//   String get currentStatus => _currentStatus;
//   int get currentStatusIndex => _currentStatusIndex;
//   int get inProgressSubState => _inProgressSubState;
//   List<String> get statuses => _statuses;

//   void updateStatus(String status) {
//     int index = _statuses.indexOf(status);
//     if (index != -1) {
//       _currentStatus = status;
//       _currentStatusIndex = index;
//       notifyListeners();
//     }
//   }

//   void updateStatusByIndex(int index) {
//     if (index >= 0 && index < _statuses.length) {
//       _currentStatus = _statuses[index];
//       _currentStatusIndex = index;
//       notifyListeners();
//     }
//   }

//   void updateInProgressSubState(int subState) {
//     if (_currentStatus == 'In Progress' && subState >= 0 && subState <= 1) {
//       _inProgressSubState = subState;
//       notifyListeners();
//     }
//   }

//   bool isStatusActive(int index) {
//     return index == _currentStatusIndex;
//   }

//   bool isStatusCompleted(int index) {
//     return index < _currentStatusIndex;
//   }

//   bool isStatusClickable(int index) {
//     // Allow clicking on current status, completed statuses, and next status
//     return index <= _currentStatusIndex + 1 && index >= 0;
//   }

//   String getTopImageByStatus(String? status) {
//     switch (status) {
//       case 'Pending':
//         return 'assets/images/order_pending.png';
//       case 'Processing':
//         return 'assets/images/order_processing.png';
//       case 'Dispatched':
//         return 'assets/images/order_dispatched.png';
//       case 'In Transit':
//         return 'assets/images/in_transit.png';
//       case 'Out for Delivery':
//         return 'assets/images/order_out_for_del.png';
//       case 'Delivered':
//         return 'assets/images/order_delivered.png';
//       case 'Cancelled':
//         return 'assets/images/cancelled.png';
//       case 'Returned':
//         return 'assets/images/returned.png';
//       case 'Failed Delivery':
//         return 'assets/images/failed_del.png';
//       case 'Awaiting Pickup':
//         return 'assets/images/awaiting_pickup.png';
//       case 'Completed':
//         return 'assets/images/order_completed.png';
//       default:
//         return 'assets/images/orderplaced.png';
//     }
//   }

//   String getStatusMessage() {
//     switch (_currentStatus) {
//       case 'Pending':
//         return 'Your Order is Pending';
//       case 'Processing':
//         return 'Your Order Is Processing';
//       case 'Dispatched':
//         return 'Your Order Is Dispatched';
//       case 'In Transit':
//         return 'Your Order Is In Transit';
//       case 'Out for Delivery':
//         return 'Your Order Is Out for Delivery';
//       case 'Delivered':
//         return 'Your order Is Delivered';
//       case 'Cancelled':
//         return 'Your Order Is Cancelled';
//       case 'Returned':
//         return 'Your Order Is Returned';
//       case 'Failed Delivery':
//         return 'Your Order Is Failed Delivery';
//       case 'Awaiting Pickup':
//         return 'Your order Is Awaiting Pickup';
//       case 'Completed':
//         return 'Your Order Is Completed';
//       default:
//         return 'Your Order has been Placed';
//     }
//   }

//   String getStatusSubMessage() {
//     return statusMsg ?? '';

//   }

//   // New method to get the appropriate icon for status card
//   String getStatusCardIcon() {
//     switch (_currentStatus) {
//       case 'Order Placed':
//         return 'assets/images/orderplace.png';
//       case 'Accepted':
//         return 'assets/images/order_accep.png';
//       // case 'In Progress':
//       //   return _inProgressSubState == 0
//       //       ? 'assets/images/delivery_partner.png' // Icon for partner assigned
//       //       : 'assets/images/in progress.png'; // Icon for out for delivery
//       // case 'Delivered':
//       //   return 'assets/images/delivered.png';
//       default:
//         return 'assets/images/orderplace.png';
//     }
//   }

//   // Method to handle call delivery partner and transition to next state
//   void callDeliveryPartner() {
//     if (_currentStatus == 'In Progress' && _inProgressSubState == 0) {
//       _inProgressSubState = 1;
//       notifyListeners();
//     }
//   }

// }

import 'dart:developer';

import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/models/shipment_status.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/session_dio.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class OrderStatusProvider extends UserScopedNotifier {
  String _currentStatus = 'Order Placed';
  int _currentStatusIndex = 0;
  int _inProgressSubState = 0; // 0: partner assigned, 1: out for delivery
  String? status;
  String? statusMsg;

  @override
  void clearUserState() {
    _currentStatus = 'Order Placed';
    _currentStatusIndex = 0;
    _inProgressSubState = 0;
    status = null;
    statusMsg = null;
  }

  Future<ShipmentStatus?> getShipmentStatus(int shipmentId) async {
    try {
      final dio = sessionDio();
      final userId = await AuthService.getuserId();
      final apiKey = await AuthService.getApiKey();

      if (userId == null || apiKey == null) {
        // AppUtils.errorToast('Missing user ID or API key');
        return null;
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

      if (response.statusCode == 200 &&
          response.data != null &&
          response.data['status'] == 'success') {
        final data = ShipmentStatusResponse.fromJson(response.data);
        status = data.shipmentStatus.statusNameEn;
        statusMsg = data.shipmentStatus.messageEn;
        log('order status >> $status');

        // Update the current status based on API response
        if (status != null) {
          updateStatus(status!);
        }

        notifyListeners();
        return data.shipmentStatus;
      } else {
        // AppUtils.errorToast(
        //   response.data['message'] ?? 'Failed to load status',
        // );
        return null;
      }
    } on DioException catch (e) {
      final msg = e.response?.data.toString() ?? e.message;
      log('❌ Dio error: $msg');
      // AppUtils.errorToast("Error: $msg");
      return null;
    } catch (e) {
      log('❌ Unexpected error: $e');
      // AppUtils.errorToast("Something went wrong");
      return null;
    }
  }

  final List<String> statuses = [
    'Pending',
    'Processing',
    'Dispatched',
    'In Transit',
    'Out for Delivery',
    'Delivered',
    'Cancelled',
    'Returned',
    'Failed Delivery',
    'Awaiting Pickup',
    'Completed',
  ];

  String get currentStatus => _currentStatus;

  int get currentStatusIndex => _currentStatusIndex;

  int get inProgressSubState => _inProgressSubState;

  // List<String> get statuses => _statuses;

  void updateStatus(String status) {
    int index = statuses.indexOf(status);
    if (index != -1) {
      _currentStatus = status;
      _currentStatusIndex = index;
      notifyListeners();
    }
  }

  void updateStatusByIndex(int index) {
    if (index >= 0 && index < statuses.length) {
      _currentStatus = statuses[index];
      _currentStatusIndex = index;
      notifyListeners();
    }
  }

  void updateInProgressSubState(int subState) {
    if (_currentStatus == 'In Progress' && subState >= 0 && subState <= 1) {
      _inProgressSubState = subState;
      notifyListeners();
    }
  }

  bool isStatusActive(int index) {
    return index == _currentStatusIndex;
  }

  bool isStatusCompleted(int index) {
    return index < _currentStatusIndex;
  }

  bool isStatusClickable(int index) {
    // Allow clicking on current status, completed statuses, and next status
    return index <= _currentStatusIndex + 1 && index >= 0;
  }

  String getTopImageByStatus(String? status) {
    switch (status) {
      case 'Pending':
        return 'assets/images/order_pending.png';
      case 'Processing':
        return 'assets/images/order_processing.png';
      case 'Dispatched':
        return 'assets/images/order_dispatched.png';
      case 'In Transit':
        return 'assets/images/in_transit.png';
      case 'Out for Delivery':
        return 'assets/images/order_out_for_del.png';
      case 'Delivered':
        return 'assets/images/order_delivered.png';
      case 'Cancelled':
        return 'assets/images/cancelled.png';
      case 'Returned':
        return 'assets/images/returned.png';
      case 'Failed Delivery':
        return 'assets/images/failed_del.png';
      case 'Awaiting Pickup':
        return 'assets/images/awaiting_pickup.png';
      case 'Completed':
        return 'assets/images/order_completed.png';
      default:
        return 'assets/images/orderplaced.png';
    }
  }

  String getStatusMessage() {
    switch (_currentStatus) {
      case 'Pending':
        return '${tr('your_order_is')} ${tr('pending')}';
      case 'Processing':
        return '${tr('your_order_is')} ${tr('processing')}';
      case 'Dispatched':
        return '${tr('your_order_is')} ${tr('dispatched')}';
      case 'In Transit':
        return '${tr('your_order_is')} ${tr('inTransit')}';
      case 'Out for Delivery':
        return '${tr('your_order_is')} ${tr('outForDelivery')}';
      case 'Delivered':
        return '${tr('your_order_is')} ${tr('delivered')}';
      case 'Cancelled':
        return '${tr('your_order_is')} ${tr('cancelled')}';
      case 'Returned':
        return '${tr('your_order_is')} ${tr('returned')}';
      case 'Failed Delivery':
        return '${tr('your_order_is')} ${tr('failedDelivery')}';
      case 'Awaiting Pickup':
        return '${tr('your_order_is')} ${tr('awaitingPickup')}';
      case 'Completed':
        return '${tr('your_order_is')} ${tr('statusCompleted')}';
      default:
        return '';
    }
  }

  String getStatusSubMessage() {
    return statusMsg ?? '';
  }

  // New method to get the appropriate icon for status card
  String getStatusCardIcon() {
    switch (_currentStatus) {
      case 'Order Placed':
        return 'assets/images/orderplace.png';
      case 'Accepted':
        return 'assets/images/order_accep.png';
      // case 'In Progress':
      //   return _inProgressSubState == 0
      //       ? 'assets/images/delivery_partner.png' // Icon for partner assigned
      //       : 'assets/images/in progress.png'; // Icon for out for delivery
      // case 'Delivered':
      //   return 'assets/images/delivered.png';
      default:
        return 'assets/images/orderplace.png';
    }
  }

  // Method to handle call delivery partner and transition to next state
  void callDeliveryPartner() {
    if (_currentStatus == 'In Progress' && _inProgressSubState == 0) {
      _inProgressSubState = 1;
      notifyListeners();
    }
  }
}
