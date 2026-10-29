import 'shipment.dart';

/// The server's page cursor for a filtered query.
///
/// The endpoint has always returned this; the app ignored it and took whatever
/// arrived in the first page, so a driver with more than fifty matching
/// shipments silently saw fifty and no indication there were more.
class FilterPagination {
  const FilterPagination({
    required this.page,
    required this.limit,
    required this.total,
    required this.pages,
  });

  final int page;
  final int limit;
  final int total;
  final int pages;

  /// Whether another page exists. Derived from the server's own page count, so
  /// the app never has to guess from the size of the batch it received.
  bool get hasMore => page < pages;

  static FilterPagination? fromJson(dynamic json) {
    if (json is! Map) return null;
    final page = int.tryParse('${json['page']}');
    final limit = int.tryParse('${json['limit']}');
    final total = int.tryParse('${json['total']}');
    final pages = int.tryParse('${json['pages']}');
    // A malformed cursor is reported as absent rather than defaulted to zero:
    // zeros would read as a valid empty result.
    if (page == null || limit == null || total == null || pages == null) {
      return null;
    }
    if (page < 1 || limit < 1 || total < 0 || pages < 0) return null;
    return FilterPagination(
      page: page,
      limit: limit,
      total: total,
      pages: pages,
    );
  }
}

/// One page of filtered shipments.
///
/// `message` is deliberately not parsed. It carried the endpoint's own prose,
/// which is what used to be shown to drivers verbatim; the app keys on [code]
/// and writes its own wording.
class FilterResponse {
  const FilterResponse({
    required this.success,
    required this.code,
    required this.shipments,
    required this.pagination,
  });

  final bool success;

  /// `OK`, `EMPTY`, or an error code. Uppercased, empty when absent.
  final String code;

  final List<Shipment> shipments;

  /// Null when the server sent no usable cursor.
  final FilterPagination? pagination;

  /// Parses a reply, or returns null when the shape cannot be trusted.
  ///
  /// Returning null rather than an empty FilterResponse is what keeps a
  /// malformed answer from being rendered as "no shipments found".
  static FilterResponse? fromJson(dynamic json) {
    if (json is! Map) return null;

    final rows = json['shipments'];
    if (rows is! List) return null;

    return FilterResponse(
      success: json['success'] == true,
      code: json['code']?.toString().trim().toUpperCase() ?? '',
      shipments:
          rows
              .whereType<Map<String, dynamic>>()
              .map(Shipment.fromJson)
              .toList(),
      pagination: FilterPagination.fromJson(json['pagination']),
    );
  }
}
