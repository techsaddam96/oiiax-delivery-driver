import 'settlement_parsing.dart';

class SettlementPagination {
  const SettlementPagination({
    required this.page,
    required this.limit,
    required this.total,
    required this.pages,
  });
  final int page;
  final int limit;
  final int total;
  final int pages;
  bool get hasMore => page < pages;
  factory SettlementPagination.fromJson(Map<String, dynamic>? json) {
    final page = settlementInt(json?['page']);
    return SettlementPagination(
      page: page < 1 ? 1 : page,
      limit: settlementInt(json?['limit']),
      total: settlementInt(json?['total']),
      pages: settlementInt(json?['pages']),
    );
  }
}
