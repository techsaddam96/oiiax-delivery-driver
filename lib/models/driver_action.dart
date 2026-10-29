/// Version 1 shipment-specific authorization snapshot. Unknown actions never execute.
class DriverAction {
  const DriverAction({required this.id, required this.targetStatusId,
    required this.enabled, required this.labelEn, required this.labelAr,
    this.blockedReason, this.group = 'progression'});
  final String id;
  final int targetStatusId;
  final bool enabled;
  final String labelEn;
  final String labelAr;
  final String? blockedReason;
  final String group;
  factory DriverAction.fromJson(Map<String, dynamic> json) => DriverAction(
    id: json['id']?.toString() ?? '',
    targetStatusId: int.tryParse('${json['target_status_id']}') ?? 0,
    enabled: json['enabled'] == true,
    labelEn: json['label_en']?.toString() ?? '',
    labelAr: json['label_ar']?.toString() ?? '',
    group: json['group']?.toString() ?? '',
    blockedReason: json['blocked_reason']?.toString(),
  );
  static const targets = <String, int>{'accept_shipment': 2,
    'arrive_at_pickup': 10, 'confirm_pickup': 4, 'complete_delivery': 11,
    'failed_delivery': 9, 'cancel_shipment': 7, 'return_shipment': 8};
  bool get canExecute => enabled && blockedReason == null && targets[id] == targetStatusId &&
      group == (const {'failed_delivery','cancel_shipment','return_shipment'}.contains(id) ? 'exception' : 'progression');
}
