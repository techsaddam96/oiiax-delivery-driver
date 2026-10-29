class ShipmentFlowConfig {
  const ShipmentFlowConfig({
    required this.statuses,
    required this.actions,
    required this.failureReasons,
    required this.returnReasons,
    required this.privacyRules,
    required this.scheduledShipments,
  });

  final List<ShipmentFlowStatus> statuses;
  final List<ShipmentFlowAction> actions;
  final List<ShipmentFlowReason> failureReasons;
  final List<ShipmentFlowReason> returnReasons;
  final ShipmentPrivacyRules privacyRules;
  final ScheduledShipmentsVisibility scheduledShipments;

  /// The app always retains Instant and Other. Scheduled is server-controlled.
  List<String> get visibleShipmentScopes => [
    'instant',
    if (scheduledShipments.isVisible) 'scheduled',
    'other',
  ];

  /// Reuses the current server catalog while replacing only the separately
  /// resolved visibility policy restored for this authenticated driver.
  ShipmentFlowConfig withScheduledShipments(
    ScheduledShipmentsVisibility visibility,
  ) {
    return ShipmentFlowConfig(
      statuses: statuses,
      actions: actions,
      failureReasons: failureReasons,
      returnReasons: returnReasons,
      privacyRules: privacyRules,
      scheduledShipments: visibility,
    );
  }

  factory ShipmentFlowConfig.fromJson(Map<String, dynamic> json) {
    final data =
        json['data'] is Map ? Map<String, dynamic>.from(json['data']) : json;

    return ShipmentFlowConfig(
      statuses:
          _listOfMaps(
            data['statuses'],
          ).map(ShipmentFlowStatus.fromJson).toList(),
      actions:
          _listOfMaps(
            data['actions'],
          ).map(ShipmentFlowAction.fromJson).toList(),
      failureReasons:
          _listOfMaps(
            data['failure_reasons'],
          ).map(ShipmentFlowReason.fromJson).toList(),
      returnReasons:
          _listOfMaps(
            data['return_reasons'],
          ).map(ShipmentFlowReason.fromJson).toList(),
      privacyRules: ShipmentPrivacyRules.fromJson(
        data['privacy_rules'] is Map
            ? Map<String, dynamic>.from(data['privacy_rules'])
            : const <String, dynamic>{},
      ),
      scheduledShipments: ScheduledShipmentsVisibility.fromJson(
        _mapAt(data['feature_policies'], 'scheduled_shipments'),
      ),
    );
  }

  factory ShipmentFlowConfig.fallback() {
    return ShipmentFlowConfig(
      statuses: const [
        ShipmentFlowStatus(
          id: 1,
          nameEn: 'Pending',
          nameAr: 'قيد الانتظار',
          isFinal: false,
          colorKey: 'warning',
        ),
        ShipmentFlowStatus(
          id: 2,
          nameEn: 'Accepted',
          nameAr: 'تم القبول',
          isFinal: false,
          colorKey: 'info',
        ),
        ShipmentFlowStatus(
          id: 4,
          nameEn: 'In Progress',
          nameAr: 'قيد التنفيذ',
          isFinal: false,
          colorKey: 'info',
        ),
        ShipmentFlowStatus(
          id: 5,
          nameEn: 'Out For Delivery',
          nameAr: 'خارج للتسليم',
          isFinal: false,
          colorKey: 'info',
        ),
        ShipmentFlowStatus(
          id: 6,
          nameEn: 'Delivered',
          nameAr: 'تم التسليم',
          isFinal: true,
          colorKey: 'success',
        ),
        ShipmentFlowStatus(
          id: 8,
          nameEn: 'Returned',
          nameAr: 'مرتجع',
          isFinal: true,
          colorKey: 'danger',
        ),
        ShipmentFlowStatus(
          id: 9,
          nameEn: 'Failed Delivery',
          nameAr: 'فشل التسليم',
          isFinal: false,
          colorKey: 'danger',
        ),
        ShipmentFlowStatus(
          id: 11,
          nameEn: 'Completed',
          nameAr: 'مكتمل',
          isFinal: true,
          colorKey: 'success',
        ),
      ],
      actions: const [
        ShipmentFlowAction(
          actionKey: 'accept_shipment',
          labelEn: 'Accept Shipment',
          labelAr: 'قبول الشحنة',
          fromStatusIds: [1],
          targetStatusId: 2,
          endpoint: 'accept_shipment_driver.php',
          requiresConfirmation: true,
          requiresReason: false,
          requiresNote: false,
          reasonGroup: null,
          isFinalAction: false,
        ),
        // Mirrors the server catalog (driver_status_transitions.php): delivery
        // is 4 (in transit) -> 11 (Completed). This offline copy used to say
        // 5 -> 6, which the server never accepts.
        ShipmentFlowAction(
          actionKey: 'delivered',
          labelEn: 'Delivered',
          labelAr: 'تم التسليم',
          fromStatusIds: [4],
          targetStatusId: 11,
          endpoint: 'complete_shipment_driver.php',
          requiresConfirmation: true,
          requiresReason: false,
          requiresNote: false,
          reasonGroup: null,
          isFinalAction: true,
        ),
      ],
      failureReasons: const [
        ShipmentFlowReason(
          id: 1,
          reasonKey: 'customer_not_answering',
          labelEn: 'Customer not answering',
          labelAr: 'العميل لا يرد',
        ),
      ],
      returnReasons: const [
        ShipmentFlowReason(
          id: 1,
          reasonKey: 'customer_refused',
          labelEn: 'Customer refused delivery',
          labelAr: 'العميل رفض الاستلام',
        ),
      ],
      privacyRules: ShipmentPrivacyRules.fallback(),
      // No successful policy response is not an Admin-OFF decision. The
      // provider retains a prior successful response during transient errors.
      scheduledShipments: ScheduledShipmentsVisibility.unavailable(),
    );
  }
}

class ScheduledShipmentsVisibility {
  const ScheduledShipmentsVisibility({
    required this.policyState,
    required this.isVisible,
    required this.resolution,
    required this.policyVersion,
    required this.assignedAccessPreserved,
  });

  final String policyState;
  final bool isVisible;
  final String resolution;
  final int? policyVersion;
  final bool assignedAccessPreserved;

  factory ScheduledShipmentsVisibility.fromJson(Map<String, dynamic> json) {
    final rawState = json['policy_state']?.toString().trim().toLowerCase();
    final isDisabled = rawState == 'disabled' || rawState == 'hidden';
    final state = switch (rawState) {
      'enabled' || 'disabled' || 'hidden' || 'unavailable' => rawState!,
      _ => 'missing',
    };
    final version = int.tryParse(json['policy_version']?.toString() ?? '');

    return ScheduledShipmentsVisibility(
      policyState: state,
      // Only an explicit, successful disabled/hidden policy hides the module.
      // A missing or unavailable response preserves the legacy visible state.
      isVisible: !isDisabled,
      resolution:
          json['resolution']?.toString().trim().isNotEmpty == true
              ? json['resolution'].toString().trim()
              : 'missing_policy',
      policyVersion: version,
      assignedAccessPreserved:
          json['assigned_access']?.toString() != 'restricted',
    );
  }

  factory ScheduledShipmentsVisibility.unavailable() =>
      const ScheduledShipmentsVisibility(
        policyState: 'unavailable',
        isVisible: true,
        resolution: 'config_unavailable',
        policyVersion: null,
        assignedAccessPreserved: true,
      );

  /// This deliberately excludes credentials and shipment data. It is only a
  /// per-driver copy of the latest server-resolved module visibility, used
  /// while an app restart waits for its next authenticated config refresh.
  Map<String, dynamic> toCacheJson() => {
    'policy_state': policyState,
    'resolution': resolution,
    if (policyVersion != null) 'policy_version': policyVersion,
    'assigned_access': assignedAccessPreserved ? 'preserved' : 'restricted',
  };
}

Map<String, dynamic> _mapAt(Object? value, String key) {
  if (value is! Map) return const <String, dynamic>{};
  final entry = value[key];
  return entry is Map
      ? Map<String, dynamic>.from(entry)
      : const <String, dynamic>{};
}

class ShipmentFlowStatus {
  const ShipmentFlowStatus({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    required this.isFinal,
    required this.colorKey,
  });

  final int id;
  final String nameEn;
  final String nameAr;
  final bool isFinal;
  final String colorKey;

  factory ShipmentFlowStatus.fromJson(Map<String, dynamic> json) {
    return ShipmentFlowStatus(
      id: _asInt(json['id']),
      nameEn: json['name_en']?.toString() ?? '',
      nameAr: json['name_ar']?.toString() ?? '',
      isFinal: _asBool(json['is_final']),
      colorKey: json['color_key']?.toString() ?? 'info',
    );
  }
}

class ShipmentFlowAction {
  const ShipmentFlowAction({
    required this.actionKey,
    required this.labelEn,
    required this.labelAr,
    required this.fromStatusIds,
    required this.targetStatusId,
    required this.endpoint,
    required this.requiresConfirmation,
    required this.requiresReason,
    required this.requiresNote,
    required this.reasonGroup,
    required this.isFinalAction,
  });

  final String actionKey;
  final String labelEn;
  final String labelAr;
  final List<int> fromStatusIds;
  final int targetStatusId;
  final String endpoint;
  final bool requiresConfirmation;
  final bool requiresReason;
  final bool requiresNote;
  final String? reasonGroup;
  final bool isFinalAction;

  factory ShipmentFlowAction.fromJson(Map<String, dynamic> json) {
    return ShipmentFlowAction(
      actionKey: json['action_key']?.toString() ?? '',
      labelEn: json['label_en']?.toString() ?? '',
      labelAr: json['label_ar']?.toString() ?? '',
      fromStatusIds:
          _listOfValues(json['from_status_ids']).map(_asInt).toList(),
      targetStatusId: _asInt(json['target_status_id']),
      endpoint: json['endpoint']?.toString() ?? '',
      requiresConfirmation: _asBool(json['requires_confirmation']),
      requiresReason: _asBool(json['requires_reason']),
      requiresNote: _asBool(json['requires_note']),
      reasonGroup: json['reason_group']?.toString(),
      isFinalAction: _asBool(json['is_final_action']),
    );
  }
}

class ShipmentFlowReason {
  const ShipmentFlowReason({
    required this.id,
    required this.reasonKey,
    required this.labelEn,
    required this.labelAr,
  });

  final int id;
  final String reasonKey;
  final String labelEn;
  final String labelAr;

  factory ShipmentFlowReason.fromJson(Map<String, dynamic> json) {
    return ShipmentFlowReason(
      id: _asInt(json['id']),
      reasonKey: json['reason_key']?.toString() ?? '',
      labelEn: json['label_en']?.toString() ?? '',
      labelAr: json['label_ar']?.toString() ?? '',
    );
  }
}

class ShipmentPrivacyRules {
  const ShipmentPrivacyRules({
    required this.beforeAccept,
    required this.afterAccept,
  });

  final ShipmentPrivacyProfile beforeAccept;
  final ShipmentPrivacyProfile afterAccept;

  factory ShipmentPrivacyRules.fromJson(Map<String, dynamic> json) {
    return ShipmentPrivacyRules(
      beforeAccept: ShipmentPrivacyProfile.fromJson(
        json['before_accept'] is Map
            ? Map<String, dynamic>.from(json['before_accept'])
            : ShipmentPrivacyProfile.beforeAcceptFallback().values,
      ),
      afterAccept: ShipmentPrivacyProfile.fromJson(
        json['after_accept'] is Map
            ? Map<String, dynamic>.from(json['after_accept'])
            : ShipmentPrivacyProfile.afterAcceptFallback().values,
      ),
    );
  }

  factory ShipmentPrivacyRules.fallback() {
    return ShipmentPrivacyRules(
      beforeAccept: ShipmentPrivacyProfile.beforeAcceptFallback(),
      afterAccept: ShipmentPrivacyProfile.afterAcceptFallback(),
    );
  }
}

class ShipmentPrivacyProfile {
  const ShipmentPrivacyProfile(this.values);

  final Map<String, bool> values;

  factory ShipmentPrivacyProfile.fromJson(Map<String, dynamic> json) {
    return ShipmentPrivacyProfile(
      json.map((key, value) => MapEntry(key, _asBool(value))),
    );
  }

  factory ShipmentPrivacyProfile.beforeAcceptFallback() {
    return const ShipmentPrivacyProfile({
      'show_policy_number': true,
      'show_status': true,
      'show_created_time': true,
      'show_relative_time': true,
      'show_accept_button': true,
      'show_store': false,
      'show_recipient': false,
      'show_phone': false,
      'show_address': false,
      'show_map': false,
      'show_costs': false,
      'show_notes': false,
    });
  }

  factory ShipmentPrivacyProfile.afterAcceptFallback() {
    return const ShipmentPrivacyProfile({
      'show_store': true,
      'show_recipient': true,
      'show_phone': true,
      'show_address': true,
      'show_map': true,
      'show_costs': true,
      'show_notes': true,
    });
  }

  bool allows(String key, {bool defaultValue = false}) {
    return values[key] ?? defaultValue;
  }
}

List<Map<String, dynamic>> _listOfMaps(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

List<dynamic> _listOfValues(dynamic value) {
  if (value is! List) return const [];
  return value;
}

int _asInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  final normalized = value?.toString().toLowerCase();
  return normalized == 'true' || normalized == '1' || normalized == 'yes';
}
