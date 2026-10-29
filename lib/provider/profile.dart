import 'dart:io';

import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/constants/helper.dart';
import 'package:blockatie/models/d_rating.dart';
import 'package:blockatie/models/driver_profile.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/session_dio.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/localization.dart';
import 'package:blockatie/utils/app_utils.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/views/dialoges/alert_dialoge.dart';
import 'package:blockatie/views/dialoges/get_location.dart';
import 'package:blockatie/views/dialoges/shipment_accept_dialog.dart';
import 'package:blockatie/utils/session_redirect.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

class ProfileProvider extends UserScopedNotifier with Helper {
  /// Injectable so tests drive the real deactivation method rather than
  /// replacing it — including the reply shapes that used to throw.
  final Dio? _injectedDio;
  Dio get _deactivateDio => _injectedDio ?? sessionDio();
  Dio get _profileDio => _injectedDio ?? sessionDio();

  File? profileImage;
  String? location;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Whether a profile read is in flight, and whether the last one failed.
  /// The hub needs all three states — loading, loaded-but-empty and failed —
  /// because rendering "Not available" for a failed read tells the driver
  /// their data is missing when it is only unreachable.
  bool isProfileLoading = false;
  bool hasProfileError = false;

  /// Set when a deactivation attempt fails, so the reason can be asserted and
  /// re-shown without depending on a dialog being on screen.
  String? deactivateError;

  /// How a failure is presented. Production uses the shared alert dialog;
  /// tests replace it so the message can be checked without a Navigator.
  @visibleForTesting
  void Function(String title, String message)? alertPresenter;

  static const String _deactivateFailedEn =
      'Could not deactivate the account. Please try again later.';
  static const String _deactivateFailedAr =
      'تعذر إيقاف الحساب. يرجى المحاولة لاحقًا.';
  static const String _deactivateRejectedEn =
      'Could not deactivate the account.';
  static const String _deactivateRejectedAr = 'تعذر إيقاف الحساب.';

  /// The wording for a deactivation that never reached a verdict: no session,
  /// a transport failure, or anything unexpected.
  static String deactivateUnavailableMessage({required bool isArabic}) =>
      isArabic ? _deactivateFailedAr : _deactivateFailedEn;

  /// The wording for a deactivation the server refused. The API's own message
  /// is preferred when it exists in the driver's language; the fallback never
  /// borrows the other language.
  static String deactivateRejectedMessage(
    dynamic response, {
    required bool isArabic,
  }) {
    if (response is Map) {
      final localized =
          isArabic ? response['message_ar'] : response['message_en'];
      final text = localized?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return isArabic ? _deactivateRejectedAr : _deactivateRejectedEn;
  }

  void _reportDeactivateFailure(String message) {
    deactivateError = message;
    notifyListeners();
    final present = alertPresenter;
    if (present != null) {
      present(tr('error'), message);
      return;
    }
    showAlertDialog(Nav.context, tr('error'), message);
  }

  /// Clears the driver identity shown across Hub, Profile and Settings.
  /// `selectedLanguage` is deliberately left alone: it mirrors a device
  /// preference, not driver-owned data.
  @override
  void clearUserState() {
    profileImage = null;
    location = null;
    locationLatLong = null;
    profileInfo = null;
    ratingInfo = null;
    isProfileLoading = false;
    hasProfileError = false;
    deactivateError = null;
    streetNumber = null;
    city = null;
    _isLoading = false;
    nameController.clear();
    newPasswordController.clear();
    confirmPasswordController.clear();
    phoneController.clear();
    locationController.clear();
  }

  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  // Language dropdown
  final List<String> languages = ['English', 'Arabic'];
  String selectedLanguage = 'English';

  void setLanguage(String lang) {
    selectedLanguage = lang;
    notifyListeners();
  }

  // TextEditingControllers
  final nameController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final phoneController = TextEditingController();
  final locationController = TextEditingController();
  LatLng? locationLatLong;

  Future<void> pickImage() async {
    final pickedFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    if (pickedFile != null) {
      profileImage = File(pickedFile.path);
      notifyListeners();
    }
  }

  setLocation(LatLng location) {
    locationLatLong = location;
    notifyListeners();
  }

  bool isPasswordMatch() {
    return newPasswordController.text == confirmPasswordController.text;
  }

  void disposeControllers() {
    nameController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    phoneController.dispose();
    locationController.dispose();
  }

  @override
  void dispose() {
    disposeControllers();
    super.dispose();
  }

  Future<void> updateDriverProfile(BuildContext context) async {
    AppUtils.showLoaderDialog();

    final apiKey = await AuthService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      AppUtils.hideLoaderDialog();
      showAlertDialog(
        context,
        tr('error'),
        tr('something_went_wrong'),
        showBtn: false,
      );
      return;
    }

    try {
      final dio = sessionDio();
      final Map<String, dynamic> fields = {};

      // // Add password only if entered
      // if (newPasswordController.text.isNotEmpty ||
      //     confirmPasswordController.text.isNotEmpty) {
      //   if (!isPasswordMatch()) {
      //     AppUtils.hideLoaderDialog();
      //     showAlertDialog(
      //       context,
      //       tr('error'),
      //       tr('passwords_do_not_match'),
      //       showBtn: false,
      //     );
      //     return;
      //   }
      //
      // }
      if (newPasswordController.text.isNotEmpty ||
          confirmPasswordController.text.isNotEmpty) {
        if (!isPasswordMatch()) {
          AppUtils.hideLoaderDialog();
          showAlertDialog(
            context,
            tr('error'),
            tr('passwords_do_not_match'),
            showBtn: false,
          );
          return;
        }
        fields['dpass'] = newPasswordController.text;
      }
      if (locationLatLong != null) {
        fields['latitude'] = locationLatLong!.latitude;
        fields['longitude'] = locationLatLong!.longitude;
      }
      // Add image if selected
      if (profileImage != null) {
        fields['driver_img'] = await MultipartFile.fromFile(
          profileImage!.path,
          filename: profileImage!.path.split('/').last,
        );
      }

      if (fields.isEmpty) {
        AppUtils.hideLoaderDialog();
        showAlertDialog(
          context,
          tr('no_changes'),
          tr('no_changes_desc'),
          showBtn: false,
        );
        return;
      }

      final formData = FormData.fromMap(fields);

      final response = await dio.post(
        AppUrls.updateprofile,
        data: formData,
        options: Options(
          headers: {'X-API-KEY': apiKey, 'Accept': '*/*'},
          contentType: 'multipart/form-data',
        ),
      );

      AppUtils.hideLoaderDialog();

      if (response.statusCode == 200 && response.data['success']) {
        showAcceptanceDilaoge(
          context,
          tr('success'),
          tr('profile_updated_successfully'),
        );
        await fetchDriverProfile();
      } else {
        showAlertDialog(
          context,
          tr('error'),
          (context.locale.languageCode == 'ar'
                  ? response.data['message_ar']
                  : response.data['message_en']) ??
              response.data['message'] ??
              'Failed to update profile',
          showBtn: false,
        );
      }
    } catch (e) {
      AppUtils.hideLoaderDialog();
      debugPrint('Profile update failed: ${e.runtimeType}');
      showAlertDialog(
        context,
        tr('error'),
        tr('an_error_occurred'),
        showBtn: false,
      );
    }
  }

  // Future<void> updateDriverProfile(BuildContext context) async {
  //   AppUtils.showLoaderDialog();
  //   if (!isPasswordMatch()) {
  //     showAlertDialog(
  //       context,
  //       'Error',
  //       'Passwords do not match',
  //       showBtn: false,
  //     );
  //     AppUtils.hideLoaderDialog();
  //     return;
  //   }
  //   final apiKey = await AuthService.getApiKey();
  //
  //   try {
  //     final dio = sessionDio();
  //
  //     final formData = FormData.fromMap({
  //       'dpass': newPasswordController.text,
  //       'driver_img': await MultipartFile.fromFile(
  //         profileImage!.path,
  //         filename: profileImage!.path.split('/').last,
  //       ),
  //     });
  //
  //     final response = await dio.post(
  //       AppUrls.updateprofile,
  //       data: formData,
  //       options: Options(
  //         headers: {'X-API-KEY': apiKey, 'Accept': '*/*'},
  //         contentType: 'multipart/form-data',
  //       ),
  //     );
  //
  //     if (response.statusCode == 200 && response.data['status'] == 'success') {
  //       // ScaffoldMessenger.of(context).showSnackBar(
  //       //   SnackBar(
  //       //     content: Text(response.data['message']),
  //       //     backgroundColor: Colors.green,
  //       //   ),
  //       // );
  //          AppUtils.hideLoaderDialog();
  //       showAcceptanceDilaoge(context, 'sucess', 'profile updated');
  //       await fetchDriverProfile();
  //     } else {
  //
  //     }
  //   } catch (e) {
  //        AppUtils.hideLoaderDialog();
  //     debugPrint("Error updating profile: $e");
  //
  //   }
  // }
  /// True while the deactivation request is in flight.
  ///
  /// This replaced a global loader dialog. That loader was closed with an
  /// unconditional `Navigator.pop`, and this flow closed it once after the
  /// request and again from `catch` — so any throw after the first close
  /// (a non-JSON reply makes `response.data['status']` throw) popped whatever
  /// real page was on top instead. Progress is owned by this provider now, so
  /// there is no route to close and nothing to close twice.
  bool isDeactivating = false;

  Future<void> deleteAccount() async {
    // Re-entry guard in the provider, not only on the button: a second tap
    // that lands before the first rebuild must still be refused.
    if (isDeactivating) return;
    isDeactivating = true;
    deactivateError = null;
    notifyListeners();

    final isArabic = AppLocalizations.isArabic;
    try {
      final dio = _deactivateDio;

      final userId = await AuthService.getuserId();
      final apiKey = await AuthService.getApiKey();

      if (userId == null || apiKey == null) {
        // Without a session the request cannot even be attempted. The driver
        // confirmed a destructive action, so silence is not an option.
        _reportDeactivateFailure(
          deactivateUnavailableMessage(isArabic: isArabic),
        );
        return;
      }

      final response = await dio.postUri(
        Uri.parse(AppUrls.deleteAccount),
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-API-KEY': apiKey,
          },
        ),
        data: {'driverId': userId},
      );

      // Read defensively. A proxy or an error page answers with a String, and
      // indexing that threw from inside the success branch.
      final body = response.data;
      final status = body is Map ? '${body['status']}' : '';
      if (response.statusCode == 200 && status == 'success') {
        final logout = await AuthService.clearSession();
        // Every route goes, so back cannot return to the authenticated shell.
        SessionRedirect.toWelcome();
        logout.recordLoginNavigation();
        logout.startDetachedCleanup();
      } else {
        _reportDeactivateFailure(
          deactivateRejectedMessage(body, isArabic: isArabic),
        );
      }
    } on DioException catch (e) {
      // Only the shape of the failure is logged; the driver sees the neutral
      // localized message, never a status line or a transport type.
      debugPrint(
        'Delete account Dio error: ${e.response?.statusCode ?? e.type}',
      );
      _reportDeactivateFailure(
        deactivateUnavailableMessage(isArabic: isArabic),
      );
    } catch (e) {
      debugPrint('Delete account failed: ${e.runtimeType}');
      _reportDeactivateFailure(
        deactivateUnavailableMessage(isArabic: isArabic),
      );
    } finally {
      // One place, every path: the busy state always ends, and it ends once.
      isDeactivating = false;
      notifyListeners();
    }
  }

  DriverInfo? profileInfo;

  Future<void> onefresh() async {
    await fetchDriverProfile();
  }

  /// Full profile refresh used by the Hub and Profile screens.
  Future<DriverInfo?> fetchDriverProfile() =>
      _fetchDriverProfile(loadCurrentLocation: true);

  /// A fast, authenticated identity refresh for the login path.
  ///
  /// The dashboard greeting consumes this same provider, so it follows the
  /// server's current display name rather than a name kept only in local
  /// session storage. Location lookup is intentionally skipped here: a slow
  /// device-permission check must not delay a successful sign-in.
  Future<DriverInfo?> refreshAuthoritativeIdentity() =>
      _fetchDriverProfile(loadCurrentLocation: false);

  Future<DriverInfo?> _fetchDriverProfile({
    required bool loadCurrentLocation,
  }) async {
    final generation = stateGeneration;
    isProfileLoading = true;
    notifyListeners();
    try {
      final dio = _profileDio;

      final session = await AuthService.getSessionSnapshot();
      if (!acceptsState(generation)) return null;
      final userId = session.driverId;
      final apiKey = session.apiKey;
      if (!session.isAuthenticated || userId == null || apiKey == null) {
        hasProfileError = true;
        return null;
      }

      final response = await dio.postUri(
        Uri.parse(AppUrls.profileInfo),
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-API-KEY': apiKey,
          },
        ),
        data: {'driverId': userId},
      );

      if (response.data != null && response.data is Map<String, dynamic>) {
        if (response.statusCode == 200 &&
            response.data['status'] == 'success') {
          final model = DriverProfileModel.fromJson(response.data);
          if (!acceptsState(generation)) return null;

          // `api_driver_profile.php` binds the posted id to X-API-KEY. Keep
          // the local fallback in sync only while that very same session is
          // still current; a late profile reply can never rename another
          // driver's dashboard.
          await AuthService.saveProfileNameIfCurrent(
            dname: model.driver.dname,
            expectedGeneration: generation,
            apiKey: apiKey,
            driverId: userId,
          );
          if (!acceptsState(generation)) return null;

          profileInfo = model.driver;
          hasProfileError = false;

          if (loadCurrentLocation) {
            final getLocation = LocationServiceNoContext();
            location = await getLocation.getUserLocation();
            if (!acceptsState(generation)) return null;
          }

          // location = await getAddressFromLatLng(
          //   double.parse(profileInfo!.latitude),
          //   double.parse(profileInfo!.longitude),
          // );
          setDriverData();
          isProfileLoading = false;
          notifyListeners();
          return model.driver;
        } else {
          hasProfileError = true;
        }
      } else {
        hasProfileError = true;
      }

      return null;
    } on DioException catch (e) {
      hasProfileError = true;
      debugPrint(
        'Fetch profile Dio error: ${e.response?.statusCode ?? e.type}',
      );
      return null;
    } catch (e) {
      hasProfileError = true;
      debugPrint('Fetch profile failed: ${e.runtimeType}');
      return null;
    } finally {
      // The hub reads this to tell "still loading" apart from "unreachable",
      // so it must land on every path, including the successful early return.
      if (acceptsState(generation)) {
        isProfileLoading = false;
        notifyListeners();
      }
    }
  }

  Widget getProfileImageWidget() {
    if (profileImage != null) {
      return Image.file(profileImage!, fit: BoxFit.cover);
    }

    final imagePath = profileInfo?.img ?? '';
    if (imagePath.isNotEmpty) {
      return Image.network(
        'https://dashboard.blockatie.com$imagePath',
        fit: BoxFit.cover,
        errorBuilder:
            (context, error, stackTrace) => const Icon(Icons.person, size: 40),
      );
    }

    return const Icon(Icons.person, size: 40);
  }

  void setDriverData() {
    if (profileInfo != null) {
      nameController.text = profileInfo!.dname;
      phoneController.text = profileInfo!.dphone;
      locationController.text = location ?? '';
    }
  }

  ProfileProvider({Dio? httpClient, bool loadProfile = true})
    : _injectedDio = httpClient {
    // Load driver info from your service or saved data. A test that only
    // exercises deactivation can skip the network call it would otherwise
    // make on construction.
    if (loadProfile) fetchDriverProfile();
  }

  String? streetNumber;
  String? city;

  Future<String> getAddressFromLatLng(double latitude, double longitude) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      );
      if (placemarks.isNotEmpty) {
        String? country = placemarks.first.country;
        return country ?? 'Unknown Country';
      } else {
        return 'Unknown Country';
      }
    } catch (e) {
      return tr('location_not_available');
    }
  }

  DriverRating? ratingInfo;

  Future<DriverRating?> getDriverRating() async {
    setLoading(true);
    try {
      final dio = sessionDio();

      final userId = await AuthService.getuserId();
      final apiKey = await AuthService.getApiKey();
      if (userId == null || apiKey == null) {
        // AppUtils.errorToast('Missing user ID or API key');
        return null;
      }

      final response = await dio.postUri(
        Uri.parse(AppUrls.getDriverRank),
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-API-KEY': apiKey,
          },
        ),
        data: {'driver_id': userId},
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final model = DriverRating.fromJson(response.data);

        // Set it wherever needed
        ratingInfo = model;
        setLoading(false);
        notifyListeners();
        return model;
      } else {
        // AppUtils.errorToast("Invalid response format from server");
        setLoading(false);
      }

      return null;
    } on DioException catch (e) {
      setLoading(false);
      debugPrint(
        'Driver rating Dio error: ${e.response?.statusCode ?? e.type}',
      );
      // AppUtils.errorToast("Error: $msg");
      return null;
    } catch (e) {
      setLoading(false);
      debugPrint('Driver rating failed: ${e.runtimeType}');
      // AppUtils.errorToast("Something went wrong");
      return null;
    }
  }
}
