import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/provider/shipment.dart';
import 'package:flutter/material.dart';

/// The pager for the assigned shipments list.
///
/// The previous version always rendered `1, 2, … , n-1, n`, so on ten pages a
/// driver sitting on page five saw no highlighted button and no way to tell
/// where they were. [visiblePageSlots] now always contains the current page.
///
/// Arrow glyphs are left to Flutter: `Icons.chevron_left` and
/// `chevron_right` both carry `matchTextDirection`, so they flip with the row
/// in Arabic without any manual swapping.
Widget buildPagination(BuildContext context, ShipmentProvider provider) {
  final current = provider.currentPage;
  final total = provider.totalPages;
  final busy = provider.isPageChanging;
  final isArabic = Localizations.localeOf(context).languageCode == 'ar';

  final children = <Widget>[
    _NavArrow(
      icon: Icons.chevron_left,
      label: isArabic ? 'الصفحة السابقة' : 'Previous page',
      enabled: current > 1 && !busy,
      onTap: provider.goToPrevPage,
    ),
    for (final slot in visiblePageSlots(current: current, total: total))
      slot == null
          ? const _Ellipsis()
          : _PageButton(
            page: slot,
            isSelected: slot == current,
            enabled: !busy,
            onTap: () => provider.setPage(slot),
          ),
    _NavArrow(
      icon: Icons.chevron_right,
      label: isArabic ? 'الصفحة التالية' : 'Next page',
      enabled: current < total && !busy,
      onTap: provider.goToNextPage,
    ),
  ];

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: children),
        // A page change keeps the rows the driver is reading on screen, so the
        // only signal that something is happening has to live here.
        if (busy) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(
                isArabic ? 'جارٍ تحميل الصفحة…' : 'Loading page…',
                style: const TextStyle(
                  color: Color(0xff64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

/// The page numbers to draw, with `null` standing for a gap.
///
/// Always includes page 1, the last page and the current page, plus one
/// neighbour on each side. Never repeats a number, and never emits a gap that
/// hides exactly one page — showing that page costs the same width as the
/// ellipsis would.
List<int?> visiblePageSlots({required int current, required int total}) {
  if (total <= 0) return const [];
  final page = current.clamp(1, total);

  final wanted = <int>{1, total, page};
  if (page - 1 > 1) wanted.add(page - 1);
  if (page + 1 < total) wanted.add(page + 1);

  final pages = wanted.toList()..sort();

  final slots = <int?>[];
  int? previous;
  for (final value in pages) {
    if (previous != null) {
      final gap = value - previous;
      if (gap == 2) {
        slots.add(previous + 1);
      } else if (gap > 2) {
        slots.add(null);
      }
    }
    slots.add(value);
    previous = value;
  }
  return slots;
}

class _PageButton extends StatelessWidget {
  const _PageButton({
    required this.page,
    required this.isSelected,
    required this.enabled,
    required this.onTap,
  });

  final int page;
  final bool isSelected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: isSelected,
      button: true,
      child: GestureDetector(
        onTap: enabled && !isSelected ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.all(1), // room for the gradient border
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient:
                  isSelected
                      ? LinearGradient(
                        colors: [AppColors.gradient1, AppColors.gradient2],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                      : null,
              border:
                  !isSelected
                      ? Border.all(color: Colors.grey.shade300, width: 1)
                      : null,
            ),
            child: Container(
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$page',
                // Page numbers read left-to-right in both languages.
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  color: isSelected ? Colors.blue.shade600 : Colors.black87,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavArrow extends StatelessWidget {
  const _NavArrow({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        button: true,
        enabled: enabled,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: enabled ? Colors.white : Colors.grey.shade200,
              border: Border.all(color: Colors.grey.shade300, width: 1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Icon(
                icon,
                size: 16,
                color: enabled ? Colors.black87 : Colors.grey.shade400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Ellipsis extends StatelessWidget {
  const _Ellipsis();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: Text(
          '…',
          style: TextStyle(
            fontSize: 16,
            color: Colors.black54,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
