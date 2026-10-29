class AppUrls {
  static String _userAgent = "";
  static String _accessToken = "";

  static setUserAgeent(String userAgent) {
    _userAgent = userAgent;
  }

  static setAccessToken(String accessToken) {
    _accessToken = accessToken;
  }

  static Map<String, String> authHeader() {
    return {
      'accept': 'application/json',
      'Content-Type': 'application/json',
      'User-Agent': _userAgent,
    };
  }

  static Map<String, String> acessTokenHeader() {
    return {
      'accept': 'application/json',
      'Content-Type': 'application/json',
      'User-Agent': _userAgent,
      'Authorization': 'Bearer $_accessToken',
    };
  }

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://dashboard.blockatie.com/services',
  );
  static const String driverlogin = '$baseUrl/api_driver_login.php';

  /// Forced password change after an admin-issued temporary password.
  static const String driverChangePassword =
      '$baseUrl/api_driver_change_password.php';
  static const String getStatusShipment = '$baseUrl/api_order_status.php';
  static const String readNotification =
      '$baseUrl/api_read_notification_driver.php';
  static const String markAllDriverNotificationsRead =
      '$baseUrl/api_mark_all_driver_notifications_read.php';

  static const String driverregister = '$baseUrl/api_register_drivers.php';
  static const String profileInfo = '$baseUrl/api_driver_profile.php';
  static const String driverStatistics = '$baseUrl/api_driver_statistics.php';
  static const String updateprofile = '$baseUrl/api_update_driver_info.php';
  static const String getNotificatios = '$baseUrl/api_driver_notifications.php';
  static const String getInAppNotifications =
      '$baseUrl/api_get_in_app_notifications.php';
  static const String acknowledgeNotification =
      '$baseUrl/api_acknowledge_notification.php';
  static const String getAllShipments = '$baseUrl/api_shipments_driver.php';

  /// Authoritative category-specific shipment lists for the Driver App.
  /// Unlike the legacy list endpoints, this returns one non-overlapping
  /// operational category and a signed workload snapshot with each response.
  static const String driverShipmentSections =
      '$baseUrl/api_driver_shipment_sections.php';
  static const String deleteAccount = '$baseUrl/api_delete_account_driver.php';
  static const String getShipmentinstant =
      '$baseUrl/api_shipments_instant_driver.php';
  static const String driverShipmentFlowConfig =
      '$baseUrl/api_driver_shipment_flow_config.php';
  static const String checkDriverArrival = '$baseUrl/check_driver_arrival.php';
  static const String acceptShipment = '$baseUrl/accept_shipment_driver.php';
  static const String markAsReceive = '$baseUrl/mark_as_arrived_driver.php';
  static const String completeShipment =
      '$baseUrl/complete_shipment_driver.php';
  static const String getShipmentStatus = '$baseUrl/api_shipment_status.php';

  // Stores are scoped to the authenticated driver's own shipments.
  // Never point this at api_clients.php, which returns the whole client directory.
  static const String driverStores = '$baseUrl/api_driver_stores.php';
  static const String filterShipments =
      '$baseUrl/api_shipment_filter_driver.php';
  static const String getWithdrawal = '$baseUrl/api_requests_drivers.php';
  static const String makeWithdrawalRequest =
      '$baseUrl/api_driver_add_withdrawal_request.php';
  static const String getdrivershipmentcordinates =
      '$baseUrl/shipment_driver_coords.php';
  static const String updateDriverLocation = '$baseUrl/api_update_location.php';
  static const String driverWorkSession =
      '$baseUrl/api_driver_work_session.php';
  static const String updateDriverFcmToken =
      '$baseUrl/api_update_driver_fcm_token.php';

  // Releases this device's FCM token from the authenticated driver on logout.
  static const String driverLogout = '$baseUrl/api_driver_logout.php';
  static const String getDriverRank = '$baseUrl/api_driver_rating.php';
  static const String getpackages = '$baseUrl/api_packages_driver.php';
  static const String sendNotifications =
      '$baseUrl/send_driver_notification.php';
  static const String getOrderStatus = '$baseUrl/api_order_status.php';
  static const String updateStatus = '$baseUrl/update_shipment_status.php';
  static const String shipmentActionReasons =
      '$baseUrl/api_shipment_action_reasons.php';
  static const String driverSettlements = '$baseUrl/api_driver_settlements.php';
  static const String driverSettlementDetails =
      '$baseUrl/api_driver_settlement_details.php';
  static const String driverFinancialSummary =
      '$baseUrl/api_driver_financial_summary.php';
  static const String driverPerformanceSummary =
      '$baseUrl/api_driver_performance_summary.php';
  // Driver Chat (read + send + read receipts). Server-derived identity only:
  // the driver is resolved from X-API-KEY, never from a request field.
  static const String driverChat = '$baseUrl/api_driver_chat.php';

  /// Work-session GPS is deliberately a release-time opt-in. Existing Driver
  /// builds, and a build without this define, retain the established location
  /// workflow and never call the additive work-session endpoint.
  ///
  /// The server remains authoritative: this flag is not an authorization
  /// signal and does not enable the server's OPT_IN or ENFORCED mode.
  static const bool driverWorkSessionsEnabled = bool.fromEnvironment(
    'DRIVER_WORK_SESSIONS_ENABLED',
  );

  /// Driver Tours stays hidden until the owner activates it for a build
  /// (`--dart-define=DRIVER_TOURS_ENABLED=true`). Without it the app shows no
  /// Tours entry and never calls the Tours API, so a backend that runs without
  /// the Tours schema cannot affect shipments, notifications or navigation.
  static const bool driverToursEnabled = bool.fromEnvironment(
    'DRIVER_TOURS_ENABLED',
  );

  static const String _driverToursOverride = String.fromEnvironment(
    'DRIVER_TOURS_API_URL',
  );

  /// Driver Tours lives in the protected dashboard module, not the legacy
  /// `/services` directory. By default it is resolved beside [baseUrl], so a
  /// staging build never sends its key to the production host. Deployments may
  /// override this complete URL through `--dart-define=DRIVER_TOURS_API_URL=...`
  /// without changing other APIs.
  static String get driverTours =>
      _driverToursOverride.isNotEmpty
          ? _driverToursOverride
          : Uri.parse(
            baseUrl,
          ).resolve('modules/driver_tours/api/driver_tours.php').toString();

  static const String driverSettlementPdf =
      '$baseUrl/api_driver_settlement_pdf.php';
}
