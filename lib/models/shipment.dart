import 'package:blockatie/models/driver_action.dart';
import 'package:blockatie/utils/time/jordan_time.dart';
import 'package:intl/intl.dart';

import 'shipment_financial.dart';

/// Server-side paging block returned alongside a page of shipments.
class ShipmentsPagination {
  const ShipmentsPagination({
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
  });

  final int page;
  final int limit;
  final int total;
  final int totalPages;

  factory ShipmentsPagination.fromJson(Map<String, dynamic> json) {
    return ShipmentsPagination(
      page: _asInt(json['page']),
      limit: _asInt(json['limit']),
      total: _asInt(json['total']),
      totalPages: _asInt(json['total_pages'] ?? json['totalPages']),
    );
  }
}

/// A deliberately narrow proof that the server has evaluated *all* of the
/// authenticated driver's operational work at one point in time.
///
/// It is not inferred from a page of shipment rows: pagination, reassignment,
/// return custody and a concurrently accepted offer make that unsafe.  The
/// Available-for-Acceptance surface is enabled only when this versioned server
/// contract proves the driver has no active operational work and has not
/// expired.  An absent, malformed or old contract fails closed.
class DriverWorkloadSnapshot {
  const DriverWorkloadSnapshot({
    required this.contractVersion,
    required this.snapshotId,
    required this.driverId,
    required this.isComplete,
    required this.activeOperationalTotal,
    required this.expiresAt,
  });

  final int contractVersion;
  final String snapshotId;
  final int driverId;
  final bool isComplete;
  final int activeOperationalTotal;
  final DateTime? expiresAt;

  factory DriverWorkloadSnapshot.fromJson(Map<String, dynamic> json) {
    final expiresAtText = json['expires_at']?.toString().trim();
    return DriverWorkloadSnapshot(
      contractVersion: _asInt(json['contract_version']),
      snapshotId: json['snapshot_id']?.toString().trim() ?? '',
      driverId: _asInt(json['driver_id']),
      isComplete: _asBool(json['complete']),
      activeOperationalTotal: _asInt(json['active_operational_total']),
      expiresAt:
          expiresAtText == null || expiresAtText.isEmpty
              ? null
              : DateTime.tryParse(expiresAtText)?.toUtc(),
    );
  }

  /// The driver id and expiry are part of the proof.  A response meant for a
  /// prior account, a partial scan, or an old cache can therefore never make
  /// an offer visible.
  bool provesNoActiveOperationalWorkFor(int currentDriverId, DateTime now) {
    final expiry = expiresAt;
    return contractVersion == 1 &&
        snapshotId.isNotEmpty &&
        driverId > 0 &&
        driverId == currentDriverId &&
        isComplete &&
        activeOperationalTotal == 0 &&
        expiry != null &&
        now.toUtc().isBefore(expiry);
  }
}

class ShipmentsResponse {
  final String status;
  final String message;
  final int driverId;
  final int count;
  final List<Shipment> shipments;

  /// Null when the backend does not send a pagination block, so an older
  /// server keeps working.
  final ShipmentsPagination? pagination;

  /// The driver's own live instant shipment. Delivered outside pagination so
  /// the pinned card stays on screen on every page. Null when there is none.
  final Shipment? activeInstant;

  /// Optional server-wide operational-workload proof. It must never be
  /// reconstructed from [shipments] or [pagination].
  final DriverWorkloadSnapshot? driverWorkloadSnapshot;

  ShipmentsResponse({
    required this.status,
    required this.message,
    required this.driverId,
    required this.count,
    required this.shipments,
    this.pagination,
    this.activeInstant,
    this.driverWorkloadSnapshot,
  });

  factory ShipmentsResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    final source = data is Map ? Map<String, dynamic>.from(data) : json;
    final shipmentsJson = source['shipments'] ?? json['shipments'];
    final shipments =
        shipmentsJson is List
            ? shipmentsJson
                .whereType<Map>()
                .map(
                  (item) => Shipment.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList()
            : <Shipment>[];

    final paginationJson = source['pagination'] ?? json['pagination'];
    final activeInstantJson =
        source['active_instant'] ?? json['active_instant'];
    final workloadSnapshotJson =
        source['driver_workload_snapshot'] ?? json['driver_workload_snapshot'];

    return ShipmentsResponse(
      status: json['status']?.toString() ?? '',
      message:
          (json['message'] ?? json['message_en'] ?? json['message_ar'])
              ?.toString() ??
          '',
      driverId: _asInt(source['driver_id'] ?? source['driverId']),
      count: _asInt(source['count'] ?? shipments.length),
      shipments: shipments,
      pagination:
          paginationJson is Map
              ? ShipmentsPagination.fromJson(
                Map<String, dynamic>.from(paginationJson),
              )
              : null,
      activeInstant:
          activeInstantJson is Map
              ? Shipment.fromJson(Map<String, dynamic>.from(activeInstantJson))
              : null,
      driverWorkloadSnapshot:
          workloadSnapshotJson is Map
              ? DriverWorkloadSnapshot.fromJson(
                Map<String, dynamic>.from(workloadSnapshotJson),
              )
              : null,
    );
  }
}

class Shipment {
  final int? actionContractVersion;
  final List<DriverAction> driverActions;
  final List<Map<String, dynamic>> driverLifecycle;
  final Map<String, dynamic>? pickupSource;
  final Map<String, dynamic>? custodyState;
  bool get hasActionContract => actionContractVersion == 1;
  bool allowsAction(String id) =>
      hasActionContract && driverActions.any((a) => a.id == id && a.canExecute);

  final int id;
  final String shipmentDate;
  final String policyNum;
  final String? barcode;
  final String recipientName;
  final String recipientPhone;
  final int storeId;
  final int governorateId;
  final String deliveryAddress;
  final int driverId;
  final double shipmentCost;
  final double deliveryCost;
  final int customerDiscount;
  final int percentDriver;
  final String shipmentNote;
  final int employeeId;
  final int deliveryTypeId;
  final int productTypeId;
  final int shipmentStatus;
  final int accountingShipment;
  final int returnedShipment;
  final String createdAt;
  final String updatedAt;
  final int shipmentStatusId;
  final String statusNameEn;
  final String statusNameAr;
  final String typeColor;
  final String messageEn;
  final String messageAr;
  final String typeNameEn;
  final String typeNameAr;
  final String descriptionEn;
  final String descriptionAr;
  final String returnTypeNameEn;
  final String returnTypeNameAr;
  final String nclient;
  final String nstore;
  final String lclient;
  final String loshop;
  final String phclient;
  final int clientStatus;
  bool withinRadius = false;
  final String? latitude;
  final String? longitude;
  final String? deliveryLatitude;
  final String? deliveryLongitude;
  final String? driverImage;
  final String? driverName;
  final String actionReasonType;
  final int actionReasonId;
  final String actionReasonTitleAr;
  final String actionReasonTitleEn;
  final String actionReasonDescriptionAr;
  final String actionReasonDescriptionEn;
  final String actionReasonNote;
  final String actionReasonCreatedAt;

  /// cod | prepaid, from the server. Prepaid means nothing to collect.
  final String paymentType;

  /// The server's amount to collect; null on servers that predate it.
  final double? serverProductToCollect;

  /// The server's money view of this shipment; null on older servers.
  final DriverShipmentFinancial? financial;

  Shipment({
    required this.id,
    required this.shipmentDate,
    required this.policyNum,
    required this.barcode,
    required this.recipientName,
    required this.recipientPhone,
    required this.storeId,
    required this.governorateId,
    required this.deliveryAddress,
    required this.driverId,
    required this.shipmentCost,
    required this.deliveryCost,
    required this.customerDiscount,
    required this.percentDriver,
    required this.shipmentNote,
    required this.employeeId,
    required this.deliveryTypeId,
    required this.productTypeId,
    required this.shipmentStatus,
    required this.accountingShipment,
    required this.returnedShipment,
    required this.createdAt,
    required this.updatedAt,
    required this.shipmentStatusId,
    required this.statusNameEn,
    required this.statusNameAr,
    required this.typeColor,
    required this.messageEn,
    required this.messageAr,
    required this.typeNameEn,
    required this.typeNameAr,
    required this.descriptionEn,
    required this.descriptionAr,
    required this.returnTypeNameEn,
    required this.returnTypeNameAr,
    required this.nclient,
    required this.nstore,
    required this.lclient,
    required this.loshop,
    required this.phclient,
    required this.clientStatus,
    required this.latitude,
    required this.longitude,
    required this.deliveryLatitude,
    required this.deliveryLongitude,
    required this.driverImage,
    required this.driverName,
    required this.actionReasonType,
    required this.actionReasonId,
    required this.actionReasonTitleAr,
    required this.actionReasonTitleEn,
    required this.actionReasonDescriptionAr,
    required this.actionReasonDescriptionEn,
    required this.actionReasonNote,
    required this.actionReasonCreatedAt,
    this.paymentType = 'cod',
    this.serverProductToCollect,
    this.actionContractVersion,
    this.driverActions = const [],
    this.driverLifecycle = const [],
    this.pickupSource,
    this.custodyState,
    this.financial,
  });

  bool get isPrepaid => paymentType == 'prepaid';

  /// What the driver collects from the recipient. The server decides; the
  /// shipment_cost fallback only serves servers that predate the field.
  double get productToCollect =>
      serverProductToCollect ?? (isPrepaid ? 0 : shipmentCost);

  Shipment copyWith({
    int? driverId,
    int? shipmentStatus,
    int? shipmentStatusId,
    String? statusNameEn,
    String? statusNameAr,
    String? messageEn,
    String? messageAr,
    String? updatedAt,
    String? actionReasonType,
    int? actionReasonId,
    String? actionReasonTitleAr,
    String? actionReasonTitleEn,
    String? actionReasonDescriptionAr,
    String? actionReasonDescriptionEn,
    String? actionReasonNote,
    String? actionReasonCreatedAt,
    DriverShipmentFinancial? financial,
  }) {
    return Shipment(
      actionContractVersion:
          driverId == null && shipmentStatusId == null && shipmentStatus == null
              ? actionContractVersion
              : null,
      driverActions: driverActions,
      driverLifecycle: driverLifecycle,
      pickupSource: pickupSource,
      custodyState: custodyState,
      id: id,
      shipmentDate: shipmentDate,
      policyNum: policyNum,
      barcode: barcode,
      recipientName: recipientName,
      recipientPhone: recipientPhone,
      storeId: storeId,
      governorateId: governorateId,
      deliveryAddress: deliveryAddress,
      driverId: driverId ?? this.driverId,
      shipmentCost: shipmentCost,
      deliveryCost: deliveryCost,
      customerDiscount: customerDiscount,
      percentDriver: percentDriver,
      shipmentNote: shipmentNote,
      employeeId: employeeId,
      deliveryTypeId: deliveryTypeId,
      productTypeId: productTypeId,
      shipmentStatus: shipmentStatus ?? this.shipmentStatus,
      accountingShipment: accountingShipment,
      returnedShipment: returnedShipment,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      shipmentStatusId: shipmentStatusId ?? this.shipmentStatusId,
      statusNameEn: statusNameEn ?? this.statusNameEn,
      statusNameAr: statusNameAr ?? this.statusNameAr,
      typeColor: typeColor,
      messageEn: messageEn ?? this.messageEn,
      messageAr: messageAr ?? this.messageAr,
      typeNameEn: typeNameEn,
      typeNameAr: typeNameAr,
      descriptionEn: descriptionEn,
      descriptionAr: descriptionAr,
      returnTypeNameEn: returnTypeNameEn,
      returnTypeNameAr: returnTypeNameAr,
      nclient: nclient,
      nstore: nstore,
      lclient: lclient,
      loshop: loshop,
      phclient: phclient,
      clientStatus: clientStatus,
      latitude: latitude,
      longitude: longitude,
      deliveryLatitude: deliveryLatitude,
      deliveryLongitude: deliveryLongitude,
      driverImage: driverImage,
      driverName: driverName,
      actionReasonType: actionReasonType ?? this.actionReasonType,
      actionReasonId: actionReasonId ?? this.actionReasonId,
      actionReasonTitleAr: actionReasonTitleAr ?? this.actionReasonTitleAr,
      actionReasonTitleEn: actionReasonTitleEn ?? this.actionReasonTitleEn,
      actionReasonDescriptionAr:
          actionReasonDescriptionAr ?? this.actionReasonDescriptionAr,
      actionReasonDescriptionEn:
          actionReasonDescriptionEn ?? this.actionReasonDescriptionEn,
      actionReasonNote: actionReasonNote ?? this.actionReasonNote,
      actionReasonCreatedAt:
          actionReasonCreatedAt ?? this.actionReasonCreatedAt,
      paymentType: financial?.paymentType ?? paymentType,
      serverProductToCollect:
          financial?.productToCollect ?? serverProductToCollect,
      financial: financial ?? this.financial,
    );
  }

  factory Shipment.fromJson(Map<String, dynamic> json) {
    return Shipment(
      actionContractVersion: _asInt(json['driver_action_contract_version']),
      driverActions:
          (json['driver_actions'] is List
                  ? json['driver_actions'] as List
                  : const [])
              .whereType<Map>()
              .map((a) => DriverAction.fromJson(Map<String, dynamic>.from(a)))
              .toList(),
      driverLifecycle:
          (json['driver_lifecycle'] is List
                  ? json['driver_lifecycle'] as List
                  : const [])
              .whereType<Map>()
              .map((a) => Map<String, dynamic>.from(a))
              .toList(),
      pickupSource:
          json['pickup_source'] is Map
              ? Map<String, dynamic>.from(json['pickup_source'])
              : null,
      custodyState:
          json['custody_state'] is Map
              ? Map<String, dynamic>.from(json['custody_state'])
              : null,
      id: _asInt(json['id']),
      shipmentDate: json['shipment_date']?.toString() ?? '',
      policyNum: json['policy_num']?.toString() ?? '',
      barcode: json['barcode']?.toString(),
      // This can be null
      latitude: json['latitude']?.toString() ?? '',
      longitude: json['longitude']?.toString(),
      deliveryLatitude:
          (json['delivery_latitude'] ??
                  json['deliveryLatitude'] ??
                  json['recipient_latitude'] ??
                  json['customer_latitude'])
              ?.toString(),
      deliveryLongitude:
          (json['delivery_longitude'] ??
                  json['deliveryLongitude'] ??
                  json['recipient_longitude'] ??
                  json['customer_longitude'])
              ?.toString(),
      // This can be null
      recipientName: json['recipient_name']?.toString() ?? '',
      recipientPhone: json['recipient_phone']?.toString() ?? '',
      storeId: _asInt(json['store_id']),
      governorateId: _asInt(json['governorate_id']),
      deliveryAddress: json['delivery_address']?.toString() ?? '',
      driverId: _asInt(json['driver_id'] ?? json['driverId']),
      shipmentCost: _asDouble(json['shipment_cost']),
      deliveryCost: _asDouble(json['delivery_cost']),
      customerDiscount: _asInt(json['customer_discount']),
      percentDriver: _asInt(json['percent_driver']),
      shipmentNote: json['shipment_note']?.toString() ?? '',
      employeeId: _asInt(json['employee_id']),
      deliveryTypeId: _asInt(json['delivery_type_id']),
      productTypeId: _asInt(json['product_type_id']),
      shipmentStatus: _asInt(json['shipment_status']),
      accountingShipment: _asInt(json['accounting_shipment']),
      returnedShipment: _asInt(json['returned_shipment']),
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
      shipmentStatusId: _asInt(json['shipment_status_id']),
      statusNameEn: json['status_name_en']?.toString() ?? '',
      statusNameAr: json['status_name_ar']?.toString() ?? '',
      typeColor: json['type_color']?.toString() ?? '',
      messageEn: json['message_en']?.toString() ?? '',
      messageAr: json['message_ar']?.toString() ?? '',
      typeNameEn: json['type_name_en']?.toString() ?? '',
      typeNameAr: json['type_name_ar']?.toString() ?? '',
      descriptionEn: json['description_en']?.toString() ?? '',
      descriptionAr: json['description_ar']?.toString() ?? '',
      returnTypeNameEn: json['return_type_name_en']?.toString() ?? '',
      returnTypeNameAr: json['return_type_name_ar']?.toString() ?? '',
      nclient: json['nclient']?.toString() ?? '',
      nstore: json['nstore']?.toString() ?? '',
      lclient: json['lclient']?.toString() ?? '',
      loshop: json['loshop']?.toString() ?? '',
      phclient: json['phclient']?.toString() ?? '',
      driverImage: json['driver_image']?.toString() ?? '',
      driverName: json['driver_name']?.toString() ?? '',
      clientStatus: _asInt(json['client_status']),
      actionReasonType: json['action_reason_type']?.toString() ?? '',
      actionReasonId: _asInt(json['action_reason_id']),
      actionReasonTitleAr: json['action_reason_title_ar']?.toString() ?? '',
      actionReasonTitleEn: json['action_reason_title_en']?.toString() ?? '',
      actionReasonDescriptionAr:
          json['action_reason_description_ar']?.toString() ?? '',
      actionReasonDescriptionEn:
          json['action_reason_description_en']?.toString() ?? '',
      actionReasonNote: json['action_reason_note']?.toString() ?? '',
      actionReasonCreatedAt: json['action_reason_created_at']?.toString() ?? '',
      paymentType: json['payment_type'] == 'prepaid' ? 'prepaid' : 'cod',
      serverProductToCollect: financialMoney(json['product_to_collect']),
      financial: DriverShipmentFinancial.tryParse(json['financial']),
    );
  }

  String actionReasonTitle(bool isArabic) {
    final preferred = isArabic ? actionReasonTitleAr : actionReasonTitleEn;
    final fallback = isArabic ? actionReasonTitleEn : actionReasonTitleAr;
    return preferred.trim().isNotEmpty ? preferred.trim() : fallback.trim();
  }

  String actionReasonDescription(bool isArabic) {
    final preferred =
        isArabic ? actionReasonDescriptionAr : actionReasonDescriptionEn;
    final fallback =
        isArabic ? actionReasonDescriptionEn : actionReasonDescriptionAr;
    return preferred.trim().isNotEmpty ? preferred.trim() : fallback.trim();
  }

  String get formattedShipmentDate {
    final parsedDate = shipmentDateTime;
    return parsedDate == null
        ? shipmentDate
        : DateFormat('dd/MM/yyyy').format(parsedDate);
  }

  /// The shipment date as a value, or null when the backend sent something
  /// that is not a date.
  ///
  /// MySQL's zero date is rejected explicitly: `DateTime.parse` happily turns
  /// `0000-00-00 00:00:00` into year zero, which would then be formatted and
  /// shown as a real date. Legacy naive values are Amman wall-clock values;
  /// offset-aware API values are converted to the same business zone, so the
  /// result does not depend on the driver's device timezone.
  DateTime? get shipmentDateTime {
    final raw = shipmentDate.trim();
    if (raw.isEmpty) return null;
    if (raw.startsWith('0000-00-00') || raw.startsWith('0000-01-01')) {
      return null;
    }
    final parsed = JordanTime.parse(raw);
    return parsed == null || parsed.year < 1900 ? null : parsed;
  }

  /// When the shipment was created, under the same rules as
  /// [shipmentDateTime]: zero dates and unparseable values become null rather
  /// than a date nobody can trust.
  DateTime? get createdAtDateTime => _safeDateTime(createdAt);

  /// The one rule for turning a backend datetime string into something
  /// displayable, shared with screens that hold a raw value rather than a
  /// [Shipment]. Zero dates and unparseable values become null rather than a
  /// date nobody can trust; all valid values are displayed in Asia/Amman.
  static DateTime? safeDateTime(String? value) => _safeDateTime(value ?? '');

  static DateTime? _safeDateTime(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return null;
    if (raw.startsWith('0000-00-00') || raw.startsWith('0000-01-01')) {
      return null;
    }
    final parsed = JordanTime.parse(raw);
    return parsed == null || parsed.year < 1900 ? null : parsed;
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  final normalized = value?.toString().trim().toLowerCase();
  return normalized == 'true' || normalized == '1';
}

double _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}
