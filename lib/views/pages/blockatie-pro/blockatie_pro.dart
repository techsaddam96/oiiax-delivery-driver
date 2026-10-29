import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/constants/helper.dart';
import 'package:blockatie/provider/blockatie_pro.dart';
import 'package:blockatie/provider/support.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/utils/size_config.dart';
import 'package:blockatie/utils/spacing.dart';
import 'package:blockatie/views/pages/hub/support&assistance/support_assistence.dart';
import 'package:blockatie/views/widgets/cutom-appbar.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/packages.dart';

class BlockatieProPage extends StatefulWidget {
  const BlockatieProPage({super.key});

  @override
  State<BlockatieProPage> createState() => _BlockatieProPageState();
}

class _BlockatieProPageState extends State<BlockatieProPage> with Helper {
  late final BlockatiePro provider;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    provider = Provider.of<BlockatiePro>(context, listen: false);
    getPackages();
  }

  void getPackages() async {
    await provider.getPackages();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SupportProvider>(context, listen: false);
    return Scaffold(
      appBar: CustomAppBar(
        title: tr('blockatieProTitle'),
        subtitle: tr('blockatieProSubtitle'),
        onHelp: () {
          Nav.to(SupportAssistencePage());
        },
      ),
      body: Padding(
        padding: const EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 30,
        ),
        child: Consumer<BlockatiePro>(
          builder: (context, value, child) {
            final packages = value.packeges?.packages ?? [];

            if (value.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 30),
              itemCount: packages.length,
              itemBuilder: (context, index) {
                final pkg = packages[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _buildServiceCard(
                    description: getLocalizedTypeName(
                      pkg.descriptionEn,
                      pkg.descriptionAr,
                    ),
                    title: getLocalizedTypeName(pkg.nameEn, pkg.nameAr),
                    price: '${pkg.currency} ${pkg.price}',
                    statusColor: Colors.green,
                    statusText:
                        pkg.isActive == 1
                            ? tr('activeStatus')
                            : tr('inactiveStatus'),
                    features: pkg.features,
                    onWhatsAppPressed: () {
                      provider.openWhatsApp(phoneNumber: '0779063650');
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildServiceCard({
    required String title,
    required String description,
    required String price,
    required Color statusColor,
    required String statusText,
    required List<Features> features,
    required VoidCallback onWhatsAppPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            tr('blockatieProTitle'),
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Spacing.x(5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  padding: EdgeInsets.all(1),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: statusColor),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: statusColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  statusText,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: statusColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Spacing.y(1),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      SizedBox(height: 7),
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      tr('inJustLabel'),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textColor,
                      ),
                    ),
                    Text(
                      price,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 8),

            /// Features
            ...features.map(
              (feature) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.textColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Spacing.x(2),
                    Text(
                      getLocalizedTypeName(
                        feature.featureEn ?? '',
                        feature.featureAr ?? '',
                      ),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.bottomEnd,
              child: SizedBox(
                width: SizeConfig.widthMultiplier * 35,
                child: ElevatedButton(
                  onPressed: onWhatsAppPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        "assets/images/logos_whatsapp-icon.png",
                        width: 15,
                        height: 15,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        tr('whatsAppButton'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // const SizedBox(height: 60), // Add space to make room for button
          ],
        ),
      ),
    );
  }
}

// import 'package:blockatie/constants/colors.dart';
// import 'package:blockatie/provider/blockatie_pro.dart';
// import 'package:blockatie/provider/support.dart';
// import 'package:blockatie/utils/nav.dart';
// import 'package:blockatie/utils/size_config.dart';
// import 'package:blockatie/utils/spacing.dart';
// import 'package:blockatie/views/pages/hub/support&assistance/support_assistence.dart';
// import 'package:blockatie/views/widgets/cutom-appbar.dart';
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:easy_localization/easy_localization.dart';

// class BlockatieProPage extends StatefulWidget {
//   const BlockatieProPage({super.key});

//   @override
//   State<BlockatieProPage> createState() => _BlockatieProPageState();
// }

// class _BlockatieProPageState extends State<BlockatieProPage> {
//   late final BlockatiePro provider;

//   @override
//   void initState() {
//     super.initState();
//     provider = Provider.of<BlockatiePro>(context, listen: false);
//     getPackages();
//   }

//   void getPackages() async {
//     await provider.getPackages();
//   }

//   @override
//   Widget build(BuildContext context) {
//     final supportProvider = Provider.of<SupportProvider>(context, listen: false);
//     return Scaffold(
//       appBar: CustomAppBar(
//         title: tr('blockatieProTitle'),
//         subtitle: tr('blockatieProSubtitle'),
//         onHelp: () {
//           Nav.to(const SupportAssistencePage());
//         },
//       ),
//       body: Padding(
//         padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 30),
//         child: Consumer<BlockatiePro>(
//           builder: (context, value, child) {
//             final packages = value.packeges?.packages ?? [];

//             if (packages.isEmpty) {
//               return const Center(child: CircularProgressIndicator());
//             }

//             return ListView.builder(
//               padding: const EdgeInsets.only(bottom: 30),
//               itemCount: packages.length,
//               itemBuilder: (context, index) {
//                 final pkg = packages[index];
//                 return Padding(
//                   padding: const EdgeInsets.only(bottom: 16),
//                   child: _buildServiceCard(
//                     title: pkg.name,
//                     price: '${pkg.currency} ${pkg.price}',
//                     statusColor: Colors.green,
//                     statusText: pkg.isActive == 1 ? tr("activeStatus") : tr("inactiveStatus"),
//                     features: pkg.features,
//                     onWhatsAppPressed: () {
//                       supportProvider.openWhatsApp(phoneNumber: '0779063650');
//                     },
//                   ),
//                 );
//               },
//             );
//           },
//         ),
//       ),
//     );
//   }
// }

// Widget _buildServiceCard({
//   required String title,
//   required String price,
//   required Color statusColor,
//   required String statusText,
//   required List<String> features,
//   required VoidCallback onWhatsAppPressed,
// }) {
//   return Stack(
//     children: [
//       Container(
//         decoration: BoxDecoration(
//           color: Colors.white,
//           border: Border.all(color: Colors.grey.withValues(alpha: 0.5)),
//           borderRadius: BorderRadius.circular(16),
//           boxShadow: [
//             BoxShadow(
//               color: Colors.black.withValues(alpha: 0.05),
//               blurRadius: 10,
//               offset: const Offset(0, 2),
//             ),
//           ],
//         ),
//         child: Padding(
//           padding: const EdgeInsets.all(20),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               /// Header
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Expanded(
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Row(
//                           children: [
//                             Text(
//                               tr('blockatieProLabel'),
//                               style: TextStyle(
//                                 fontSize: 12,
//                                 color: AppColors.textColor,
//                                 fontWeight: FontWeight.w500,
//                               ),
//                             ),
//                             Spacing.x(5),
//                             Container(
//                               padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//                               decoration: BoxDecoration(
//                                 color: statusColor.withValues(alpha: 0.1),
//                                 borderRadius: BorderRadius.circular(4),
//                               ),
//                               child: Row(
//                                 mainAxisSize: MainAxisSize.min,
//                                 children: [
//                                   Container(
//                                     width: 8,
//                                     height: 8,
//                                     padding: const EdgeInsets.all(1),
//                                     decoration: BoxDecoration(
//                                       border: Border.all(color: statusColor),
//                                       shape: BoxShape.circle,
//                                     ),
//                                     child: Container(
//                                       width: 6,
//                                       height: 6,
//                                       decoration: BoxDecoration(
//                                         color: statusColor,
//                                         shape: BoxShape.circle,
//                                       ),
//                                     ),
//                                   ),
//                                   const SizedBox(width: 4),
//                                   Text(
//                                     statusText,
//                                     style: TextStyle(
//                                       fontSize: 10,
//                                       color: statusColor,
//                                       fontWeight: FontWeight.w600,
//                                     ),
//                                   ),
//                                 ],
//                               ),
//                             ),
//                           ],
//                         ),
//                         Spacing.y(1),
//                         Text(
//                           title,
//                           style: const TextStyle(
//                             fontSize: 18,
//                             fontWeight: FontWeight.bold,
//                             color: Colors.black,
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                   Column(
//                     crossAxisAlignment: CrossAxisAlignment.end,
//                     children: [
//                       Text(
//                         tr('inJustLabel'),
//                         style: TextStyle(
//                           fontSize: 12,
//                           color: AppColors.textColor,
//                         ),
//                       ),
//                       Text(
//                         price,
//                         style: const TextStyle(
//                           fontSize: 18,
//                           fontWeight: FontWeight.bold,
//                           color: Colors.black,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ],
//               ),
//               const SizedBox(height: 20),

//               /// Features
//               ...features.map(
//                 (feature) => Padding(
//                   padding: const EdgeInsets.only(bottom: 2),
//                   child: Row(
//                     children: [
//                       Container(
//                         width: 5,
//                         height: 5,
//                         decoration: BoxDecoration(
//                           color: AppColors.textColor,
//                           shape: BoxShape.circle,
//                         ),
//                       ),
//                       Spacing.x(2),
//                       Text(
//                         feature,
//                         style: const TextStyle(
//                           fontSize: 10,
//                           color: Colors.black87,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),

//       /// WhatsApp Button
//       Positioned(
//         right: 15,
//         bottom: 10,
//         child: SizedBox(
//           width: SizeConfig.widthMultiplier * 35,
//           child: ElevatedButton(
//             onPressed: onWhatsAppPressed,
//             style: ElevatedButton.styleFrom(
//               backgroundColor: AppColors.primary,
//               foregroundColor: Colors.white,
//               padding: const EdgeInsets.symmetric(vertical: 10),
//               shape: RoundedRectangleBorder(
//                 borderRadius: BorderRadius.circular(8),
//               ),
//               elevation: 0,
//             ),
//             child: Row(
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: [
//                 Image.asset(
//                   "assets/images/logos_whatsapp-icon.png",
//                   width: 15,
//                   height: 15,
//                 ),
//                 const SizedBox(width: 8),
//                 Text(
//                   tr('whatsAppButton'),
//                   style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     ],
//   );
// }
