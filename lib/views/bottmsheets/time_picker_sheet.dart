// widgets/custom_time_picker_sheet.dart
import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/provider/time.dart';
import 'package:blockatie/utils/size_config.dart';
import 'package:blockatie/utils/spacing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CustomTimePickerSheet extends StatelessWidget {
  const CustomTimePickerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final timeProvider = Provider.of<TimeProvider>(context);
    final hours = List.generate(12, (index) => index + 1); // 1–12
    final minutes = List.generate(60, (index) => index); // 0–59
    final periods = ['AM', 'PM'];

    return Container(
      height: SizeConfig.heightMultiplier * 42,
      padding: const EdgeInsets.only(
        top: 12.0,
        bottom: 20,
        left: 15,
        right: 15,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // drag handle
          Container(
            width: 40,
            height: 3,
            decoration: BoxDecoration(
              color: Colors.grey,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          const SizedBox(height: 16),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Set Time",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Row(
                  children: [
                    Spacing.x(15),
                    _buildWheel<int>(
                      context,
                      items: hours,
                      selectedItem: timeProvider.selectedHour,
                      onChanged: (val) => timeProvider.setHour(val),
                    ),
                    _buildWheel<int>(
                      context,
                      items: minutes,
                      selectedItem: timeProvider.selectedMinute,
                      onChanged: (val) => timeProvider.setMinute(val),
                    ),
                    _buildWheel<String>(
                      context,
                      items: periods,
                      selectedItem: timeProvider.selectedPeriod,
                      onChanged: (val) => timeProvider.setPeriod(val),
                    ),
                  ],
                ),
                // dividers
                Positioned(
                  top: 30,
                  left: 0,
                  right: 0,
                  child: Divider(color: Colors.grey.shade400),
                ),
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: Divider(color: Colors.grey.shade400),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context, timeProvider.formattedTime);
                },
                child: Text('Save', style: TextStyle(color: AppColors.primary)),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWheel<T>(
    BuildContext context, {
    required List<T> items,
    required T selectedItem,
    required void Function(T) onChanged,
  }) {
    final controller = FixedExtentScrollController(
      initialItem: items.indexOf(selectedItem),
    );

    return Expanded(
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: 50,
        physics: const FixedExtentScrollPhysics(),
        overAndUnderCenterOpacity: 0.0,
        perspective: 0.0001,
        useMagnifier: false,
        onSelectedItemChanged: (index) {
          onChanged(items[index]);
        },
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: items.length,
          builder: (context, index) {
            final isSelected = items[index] == selectedItem;
            return Center(
              child: Text(
                items[index].toString().padLeft(2, '0'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? AppColors.primary : Colors.black54,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
