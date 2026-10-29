import 'package:blockatie/utils/size_config.dart';
import 'package:flutter/material.dart';

class CustomToggleBtn extends StatefulWidget {
  final Function(int) onTabChanged;

  const CustomToggleBtn({super.key, required this.onTabChanged});

  @override
  State<CustomToggleBtn> createState() => _CustomToggleBtnState();
}

class _CustomToggleBtnState extends State<CustomToggleBtn>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: 0);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      widget.onTabChanged(_tabController.index);
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    // The locale MaterialApp resolved, which Login itself reads. tr() went
    // through EasyLocalization's own locale, which could disagree with it and
    // put English tabs on an Arabic Login.
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return Container(
      width: SizeConfig.widthMultiplier * 54,
      height: SizeConfig.heightMultiplier * 4.5,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white),
        borderRadius: BorderRadius.circular(6),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: ShapeDecoration(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            // Directional: the first tab's rounded corner belongs on the
            // leading edge and the second's on the trailing edge, which are
            // opposite sides in Arabic. Physical left/right kept the rounding
            // on the wrong end of the control under RTL.
            borderRadius: BorderRadiusDirectional.horizontal(
              start:
                  _tabController.index == 0
                      ? const Radius.circular(5)
                      : Radius.zero,
              end:
                  _tabController.index == 1
                      ? const Radius.circular(5)
                      : Radius.zero,
            ),
          ),
        ),
        labelColor: Colors.black,
        unselectedLabelColor: Colors.white,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        labelPadding: EdgeInsets.zero,
        tabs: [
          _buildTab(
            'assets/images/icn_hero.png',
            isArabic ? 'المندوب' : 'Hero',
            _tabController.index == 0,
          ),
          _buildTab(
            'assets/images/icn_support.png',
            isArabic ? 'الدعم' : 'Support',
            _tabController.index == 1,
          ),
        ],
      ),
    );
  }

  Widget _buildTab(dynamic icon, String text, bool isSelected) {
    final textTheme = Theme.of(context).textTheme;

    Widget iconWidget;

    if (icon is IconData) {
      iconWidget = Icon(
        icon,
        size: 18,
        color: isSelected ? Colors.black : Colors.white,
      );
    } else if (icon is String) {
      iconWidget = Image.asset(
        icon,
        width: 18,
        height: 18,
        color: isSelected ? Colors.black : Colors.white,
      );
    } else {
      iconWidget = const SizedBox(); // fallback
    }

    return Tab(
      child: SizedBox(
        width: 100, // Each tab gets half of 200
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              iconWidget,
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  text,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium!.copyWith(
                    color: isSelected ? Colors.black : Colors.white,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}
