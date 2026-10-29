import 'package:blockatie/utils/localization.dart';
import 'package:blockatie/utils/time/jordan_time.dart';

class Logic {
  static String timeAgo(String createdAt, {String lang = "en"}) {
    final created = JordanTime.parse(createdAt);
    if (created == null) return '';
    final now = JordanTime.now();

    Duration diff = now.difference(created);

    if (lang == "ar") {
      if (diff.inSeconds < 60) {
        return "منذ ${diff.inSeconds} ثانية";
      } else if (diff.inMinutes < 60) {
        return "منذ ${diff.inMinutes} دقيقة";
      } else if (diff.inHours < 24) {
        return "منذ ${diff.inHours} ساعة";
      } else if (diff.inDays < 30) {
        return "منذ ${diff.inDays} يوم";
      } else if (diff.inDays < 365) {
        return "منذ ${(diff.inDays / 30).floor()} شهر";
      } else {
        return "منذ ${(diff.inDays / 365).floor()} سنة";
      }
    } else {
      if (diff.inSeconds < 60) {
        return "${diff.inSeconds} seconds ago";
      } else if (diff.inMinutes < 60) {
        return "${diff.inMinutes} minutes ago";
      } else if (diff.inHours < 24) {
        return "${diff.inHours} hours ago";
      } else if (diff.inDays < 30) {
        return "${diff.inDays} days ago";
      } else if (diff.inDays < 365) {
        return "${(diff.inDays / 30).floor()} months ago";
      } else {
        return "${(diff.inDays / 365).floor()} years ago";
      }
    }
  }

  static String getCreatedFrom(String createdAt, {String lang = "en"}) {
    String createdFrom = timeAgo(createdAt);
    if (AppLocalizations.isArabic) {
      createdFrom = timeAgo(createdAt, lang: lang);
    }
    return createdFrom;
  }
}
