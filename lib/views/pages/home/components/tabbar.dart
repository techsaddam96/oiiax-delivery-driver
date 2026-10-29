import 'package:blockatie/provider/header.dart';
import 'package:blockatie/provider/home.dart';
import 'package:blockatie/utils/app_images.dart';
import 'package:blockatie/utils/size_config.dart';
import 'package:blockatie/utils/spacing.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../provider/profile.dart';

class HomeTabbar extends StatelessWidget {
  HomeTabbar({super.key, required this.tabController});

  final TabController tabController;

  final GlobalKey _dropdownKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final homeProvider = context.watch<HomeProvider>();
    final profileProvider = context.watch<ProfileProvider>();

    // Check if user has subscription (subscription == 1)
    final hasSubscription = profileProvider.profileInfo?.subscription == 1;
    return TabBar(
      isScrollable: true,
      dividerColor: Colors.white,
      tabAlignment: TabAlignment.start,
      controller: tabController,
      padding: EdgeInsets.zero,
      indicatorPadding: const EdgeInsets.all(0),
      labelPadding: EdgeInsets.zero,
      indicatorColor:
          homeProvider.selectedTabIndex == -1
              ? Colors.transparent
              : Colors.cyan,
      labelColor: Colors.black,
      indicatorSize: TabBarIndicatorSize.tab,
      unselectedLabelColor: Colors.black54,
      onTap: (index) {
        // When tab is tapped, update the home provider
        context.read<HomeProvider>().setSelectedTab(index);
      },
      tabs: [
        _tabbarItem(textTheme, AppImages.tabl, tr("shipments")),
        hasSubscription == true
            ? _tabbarItem(
              textTheme,
              AppImages.shipment,
              tr("shipment_instant").replaceAll('\n', ' '),
            )
            : const SizedBox.shrink(),
        _tabbarItem(textTheme, AppImages.assistent, tr("supportTab")),
      ],
    );
  }

  Widget _tabbarItem(TextTheme textTheme, String? icon, String? label) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: SizeConfig.widthMultiplier * 1.8,
      ),
      height: SizeConfig.heightMultiplier * 6,
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(icon ?? "", color: Colors.black, height: 13),
          Spacing.x(2),
          Text(
            label ?? "",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall!.copyWith(
              fontSize: SizeConfig.textMultiplier * 1.12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabbarItemWithDropdown(
    BuildContext context,
    TextTheme textTheme,
    String? icon,
    String? label,
  ) {
    final dropdown = Provider.of<Headerprovider>(context);
    return Container(
      key: _dropdownKey,
      padding: EdgeInsets.symmetric(horizontal: SizeConfig.widthMultiplier * 2),
      height: SizeConfig.heightMultiplier * 6,
      alignment: Alignment.center,
      child: GestureDetector(
        onTap: () {
          // dropdown.toggle(
          //   context: context,
          //   targetKey: _dropdownKey,
          //   overlayChild: _buildDropdownOverlay(context),
          // );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(icon ?? "", color: Colors.black, height: 13),
            Spacing.x(2),
            Text(
              label ?? "",
              style: textTheme.bodySmall!.copyWith(
                fontSize: SizeConfig.textMultiplier * 1.2,
              ),
            ),
            Spacing.x(1),
            Icon(
              dropdown.isOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
              color: Colors.black,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownOverlay(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () {
              debugPrint("Instant Shipment selected");
              // When dropdown item is selected, set the tab to index 1 (Shipment Instant)
              context.read<HomeProvider>().setSelectedTab(1);
              Provider.of<Headerprovider>(context, listen: false).close();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  Image.asset(
                    AppImages.shipment,
                    color: Colors.black,
                    height: 13,
                  ),
                  Spacing.x(2),
                  Text(
                    "add Shipment",
                    style: TextStyle(
                      fontSize: SizeConfig.textMultiplier * 1.2,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
