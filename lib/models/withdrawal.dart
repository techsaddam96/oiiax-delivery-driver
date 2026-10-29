class WithdrawalRequestsResponse {
  final bool success;
  final String message;
  final List<WithdrawalRequest> requests;

  WithdrawalRequestsResponse({
    required this.success,
    required this.message,
    required this.requests,
  });

  factory WithdrawalRequestsResponse.fromJson(Map<String, dynamic> json) {
    List<WithdrawalRequest> requestsList = [];

    if (json['requests'] != null && json['requests'] is List) {
      requestsList =
          (json['requests'] as List)
              .map(
                (e) => WithdrawalRequest.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList();
    } else if (json['request'] != null && json['request'] is Map) {
      requestsList = [
        WithdrawalRequest.fromJson(Map<String, dynamic>.from(json['request'])),
      ];
    }

    return WithdrawalRequestsResponse(
      success: json['success'] == true || json['status'] == 'success',
      message: json['message']?.toString() ?? '',
      requests: requestsList,
    );
  }
}

class WithdrawalRequest {
  final int id;
  final int driverId;
  final double amount;
  final String currency;
  final int status;
  final String withdrawalMethod;
  final String accountDetails;
  final String requestedAt;

  WithdrawalRequest({
    required this.id,
    required this.driverId,
    required this.amount,
    required this.currency,
    required this.status,
    required this.withdrawalMethod,
    required this.accountDetails,
    required this.requestedAt,
  });

  factory WithdrawalRequest.fromJson(Map<String, dynamic> json) {
    return WithdrawalRequest(
      id: _asInt(json['id']),
      driverId: _asInt(json['driver_id']),
      amount: double.tryParse(json['amount'].toString()) ?? 0.0,
      currency: json['currency']?.toString() ?? 'JOD',
      status: _asInt(json['status']),
      withdrawalMethod: json['withdrawal_method']?.toString() ?? '',
      accountDetails: json['account_details']?.toString() ?? '',
      requestedAt: json['requested_at']?.toString() ?? '',
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
