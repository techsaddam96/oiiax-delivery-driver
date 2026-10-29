import 'package:blockatie/provider/support.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/size_config.dart';

class SocailMediaContactCard extends StatelessWidget {
  const SocailMediaContactCard({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SupportProvider>(context, listen: false);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: SizeConfig.widthMultiplier * 13,
        vertical: 13,
      ),
      // height: SizeConfig.heightMultiplier * 6,
      // width: SizeConfig.widthMultiplier * 100,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          InkWell(
            onTap: () {
              provider.openFacebook(pageId: 'flutterdev');
            },
            child: Image.asset(
              'assets/images/facebook.png',
              width: 33,
              height: 33,
            ),
          ),
          InkWell(
            onTap: () {
              provider.openInstagram(username: 'flutterdev');
            },
            child: Image.asset(
              'assets/images/instagram.png',
              width: 33,
              height: 33,
            ),
          ),
          InkWell(
            onTap: () {
              provider.openLinkedIn(
                profileUrl: 'https://www.linkedin.com/in/flutterdev',
              );
            },
            child: Image.asset(
              'assets/images/linkedin.png',
              width: 33,
              height: 33,
            ),
          ),

          // InkWell(
          //   onTap: () {
          //     provider.openTwitter(username: 'flutterdev');
          //   },
          //   child: Image.asset(
          //     'assets/images/twiter.png',
          //     width: 30,
          //     height: 30,
          //   ),
          // ),
        ],
      ),
    );
  }
}
