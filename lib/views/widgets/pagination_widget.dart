import 'package:blockatie/constants/colors.dart';
import 'package:flutter/material.dart';

/// Server-side pager used by the instant shipments queue.
///
/// The previous version built its window from three hand-written branches and
/// emitted page 1 twice whenever the driver was near the end of a long list.
/// [visiblePaginationSlots] replaces all of it: one rule, no duplicates, and
/// the current page is always present.
///
/// Arrow glyphs are left to Flutter — `Icons.chevron_left` and `chevron_right`
/// both carry `matchTextDirection`, so they flip with the row in Arabic.
class PaginationWidget extends StatelessWidget {
  const PaginationWidget({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
    this.hasNextPage = true,
    this.hasPreviousPage = true,
    this.isBusy = false,
  });

  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;
  final bool hasNextPage;
  final bool hasPreviousPage;

  /// A page is already in flight. The rows stay on screen, so this is the only
  /// place that can tell the driver something is happening.
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) return const SizedBox.shrink();

    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _NavButton(
                  icon: Icons.chevron_left,
                  label: isArabic ? 'الصفحة السابقة' : 'Previous page',
                  isEnabled: hasPreviousPage && !isBusy,
                  onTap: () => onPageChanged(currentPage - 1),
                ),
                const SizedBox(width: 6),
                for (final slot in visiblePaginationSlots(
                  current: currentPage,
                  total: totalPages,
                )) ...[
                  slot == null
                      ? const _Ellipsis()
                      : _PageButton(
                        page: slot,
                        isCurrent: slot == currentPage,
                        isEnabled: !isBusy,
                        onTap: () => onPageChanged(slot),
                      ),
                  const SizedBox(width: 4),
                ],
                const SizedBox(width: 2),
                _NavButton(
                  icon: Icons.chevron_right,
                  label: isArabic ? 'الصفحة التالية' : 'Next page',
                  isEnabled: hasNextPage && !isBusy,
                  onTap: () => onPageChanged(currentPage + 1),
                ),
              ],
            ),
          ),
          if (isBusy) ...[
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
}

/// The page numbers to draw, with `null` standing for a gap.
///
/// Always includes page 1, the last page and the current page, plus one
/// neighbour on each side. Never repeats a number, and never emits a gap that
/// would hide exactly one page — drawing that page costs the same width as the
/// ellipsis would.
List<int?> visiblePaginationSlots({required int current, required int total}) {
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
    required this.isCurrent,
    required this.isEnabled,
    required this.onTap,
  });

  final int page;
  final bool isCurrent;
  final bool isEnabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: isCurrent,
      button: true,
      child: GestureDetector(
        onTap: isEnabled && !isCurrent ? onTap : null,
        child: Opacity(
          opacity: isEnabled ? 1 : 0.5,
          child: Container(
            // A minimum rather than a rigid box, so a larger accessibility
            // text scale grows the button instead of clipping the number.
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isCurrent ? AppColors.primary : Colors.grey.shade300,
                width: isCurrent ? 2 : 1,
              ),
            ),
            child: Text(
              '$page',
              // Page numbers read left-to-right in both languages.
              textDirection: TextDirection.ltr,
              style: TextStyle(
                color: isCurrent ? AppColors.primary : Colors.black,
                fontWeight: isCurrent ? FontWeight.w800 : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.isEnabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isEnabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        button: true,
        enabled: isEnabled,
        child: GestureDetector(
          onTap: isEnabled ? onTap : null,
          child: Container(
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isEnabled ? Colors.white : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isEnabled ? Colors.grey.shade300 : Colors.grey.shade400,
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              color: isEnabled ? Colors.grey.shade600 : Colors.grey.shade400,
              size: 16,
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
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300, width: 1),
      ),
      child: const Text(
        '…',
        style: TextStyle(color: Colors.black, fontSize: 12),
      ),
    );
  }
}
