import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/provider/filter.dart';
import 'package:blockatie/utils/size_config.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// Replace with your AppColors class

class CalendarSheet extends StatelessWidget {
  const CalendarSheet({super.key});

  static Future<void> show(BuildContext context) {
    // The two lines that followed this call used to run the moment the sheet
    // opened — before the driver had touched anything — so merely opening the
    // calendar and cancelling left a date in the field. `selectDate` keeps the
    // field in step now, and there is nothing to write here.
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return const _CalendarBottomContent();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Not used directly; use `CalendarSheet.show(context);`
    return const SizedBox.shrink();
  }
}

class _CalendarBottomContent extends StatelessWidget {
  const _CalendarBottomContent();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        height: SizeConfig.heightMultiplier * 56,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 3,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            CalendarWidget(),
            // const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    "Cancel",
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    // Optionally handle selected date
                    Navigator.of(context).pop();
                  },
                  child: const Text(
                    "Ok",
                    style: TextStyle(
                      color: Colors.indigo,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class CalendarWidget extends StatelessWidget {
  final List<String> weekDays = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

  CalendarWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FilterProvider>(
      builder: (context, provider, child) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _buildHeader(provider),
              // const Divider(color: Colors.grey, thickness: 0.5),
              // const SizedBox(height: 20),
              _buildWeekDaysHeader(),
              const SizedBox(height: 10),
              ..._buildCalendarGrid(provider),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(FilterProvider provider) {
    return Row(
      children: [
        Text(
          '${provider.getMonthName(provider.visibleMonth.month)} ${provider.visibleMonth.year}',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        IconButton(
          icon: Icon(Icons.chevron_left, color: AppColors.primary),
          onPressed: provider.previousMonth,
        ),
        IconButton(
          icon: Icon(Icons.chevron_right, color: AppColors.primary),
          onPressed: provider.nextMonth,
        ),
      ],
    );
  }

  Widget _buildWeekDaysHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children:
          weekDays
              .map(
                (day) => Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  child: Text(
                    day,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              )
              .toList(),
    );
  }

  List<Widget> _buildCalendarGrid(FilterProvider provider) {
    List<List<int?>> weeks = provider.getCalendarDays();

    return weeks
        .map(
          (week) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children:
                  week.map((day) => _buildDayCell(day, provider)).toList(),
            ),
          ),
        )
        .toList();
  }

  Widget _buildDayCell(int? day, FilterProvider provider) {
    if (day == null) {
      return const SizedBox(width: 32, height: 32);
    }

    // Only a day inside the month currently on screen is the selected one, and
    // no day is selected until the driver picks one.
    final selected = provider.selectedDate;
    final isSelected =
        selected != null &&
        selected.day == day &&
        selected.month == provider.visibleMonth.month &&
        selected.year == provider.visibleMonth.year;

    return GestureDetector(
      onTap: () => provider.selectDate(day),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: Text(
          day.toString(),
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black,
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
