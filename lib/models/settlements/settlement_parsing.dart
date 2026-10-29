int settlementInt(dynamic value) =>
    value is int ? value : int.tryParse('${value ?? ''}') ?? 0;

double settlementDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('${value ?? ''}'.replaceAll(',', '')) ?? 0;
}

bool settlementBool(dynamic value) {
  if (value is bool) return value;
  final normalized = '${value ?? ''}'.trim().toLowerCase();
  return normalized == '1' || normalized == 'true' || normalized == 'yes';
}

String settlementText(dynamic value) => '${value ?? ''}'.trim();
