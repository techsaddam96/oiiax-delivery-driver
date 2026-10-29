import 'dart:async';
import 'dart:io';

import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/models/driver_profile.dart';
import 'package:blockatie/provider/profile.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/session_dio.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/utils/password_policy.dart';
import 'package:blockatie/views/widgets/driver_chat_bubble.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _loadFailed = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  File? _selectedImage;
  DriverInfo? _profile;

  /// The session this form belongs to. Every async result is checked against
  /// it, so a reply addressed to the previous driver can never repopulate the
  /// next one's form or be written into their storage.
  late int _generation;

  @override
  void initState() {
    super.initState();
    _generation = UserSessionState.generation;
    UserSessionState.changes.addListener(_onSessionChanged);
    unawaited(_loadProfile());
  }

  @override
  void dispose() {
    UserSessionState.changes.removeListener(_onSessionChanged);
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  /// A logout or an account switch invalidates the whole form. The controllers
  /// hold the previous driver's name and phone and possibly a typed password,
  /// and none of that may survive into the next account.
  void _onSessionChanged() {
    if (!mounted || UserSessionState.isCurrent(_generation)) return;
    setState(() {
      _profile = null;
      _nameController.clear();
      _phoneController.clear();
      _passwordController.clear();
      _confirmPasswordController.clear();
      _selectedImage = null;
      _isSaving = false;
      _isLoading = false;
      _loadFailed = true;
    });
    if (Navigator.of(context).canPop()) Nav.back();
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });

    final provider = context.read<ProfileProvider>();
    final profile = provider.profileInfo ?? await provider.fetchDriverProfile();
    if (!mounted || !UserSessionState.isCurrent(_generation)) return;
    final fallbackName = await AuthService.getDrivername();
    final fallbackPhone = await AuthService.getPhone();
    if (!mounted || !UserSessionState.isCurrent(_generation)) return;

    final name = profile?.dname ?? fallbackName ?? '';
    final phone = profile?.dphone ?? fallbackPhone ?? '';
    setState(() {
      _profile = profile;
      _nameController.text = name;
      _phoneController.text = phone;
      _isLoading = false;
      // Nothing to edit and nothing cached: a failed read, not an account with
      // no details. Save must not be offered against it.
      _loadFailed = profile == null && name.isEmpty && phone.isEmpty;
    });
  }

  Future<void> _pickImage() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null || !mounted) return;
      setState(() => _selectedImage = File(picked.path));
    } catch (e) {
      // A denied permission or a missing platform implementation must leave
      // the form usable and say so in the driver's language, never as a raw
      // PlatformException.
      debugPrint('Image picker failed: ${e.runtimeType}');
      if (!mounted) return;
      _showSnack(
        _copy(
          context,
          'Unable to open the photo gallery.',
          'تعذر فتح معرض الصور.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    final password = _passwordController.text.trim();
    if (_selectedImage == null && password.isEmpty) {
      _showSnack(
        _copy(
          context,
          'No supported changes selected.',
          'لا توجد تغييرات مدعومة للحفظ.',
        ),
        isError: true,
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final apiKey = await AuthService.getApiKey();
      if (!mounted || !UserSessionState.isCurrent(_generation)) return;
      if (apiKey == null || apiKey.trim().isEmpty) {
        _showSnack(
          _copy(
            context,
            'Session expired. Please login again.',
            'انتهت الجلسة. يرجى تسجيل الدخول مرة أخرى.',
          ),
          isError: true,
        );
        return;
      }

      final fields = <String, dynamic>{};
      if (password.isNotEmpty) fields['dpass'] = password;
      if (_selectedImage != null) {
        fields['driver_img'] = await MultipartFile.fromFile(
          _selectedImage!.path,
          filename: _selectedImage!.path.split(Platform.pathSeparator).last,
        );
      }

      // The session-aware client, not a bare Dio: this endpoint answers 401
      // for a missing key and 403 for a revoked one, and only this layer turns
      // those into the app's single sign-out path.
      final response = await sessionDio().post(
        AppUrls.updateprofile,
        data: FormData.fromMap(fields),
        options: Options(
          headers: {'X-API-KEY': apiKey, 'Accept': '*/*'},
          contentType: 'multipart/form-data',
        ),
      );

      if (!mounted || !UserSessionState.isCurrent(_generation)) return;

      final data = response.data;
      final success =
          response.statusCode == 200 &&
          data is Map &&
          (data['success'] == true || data['status'] == 'success');

      if (!success) {
        _showSnack(_messageFrom(data), isError: true);
        return;
      }

      // A password change rotates the key and signs every other device out;
      // this device continues with the new one.
      final rotatedKey = data['api_key'];
      if (rotatedKey is String && rotatedKey.trim().isNotEmpty) {
        await AuthService.replaceApiKey(
          rotatedKey.trim(),
          expectedGeneration: _generation,
        );
        if (!mounted || !UserSessionState.isCurrent(_generation)) return;
      }

      _passwordController.clear();
      _confirmPasswordController.clear();
      setState(() => _selectedImage = null);

      final profileProvider = context.read<ProfileProvider>();
      final updated = await profileProvider.fetchDriverProfile();
      // The identity write is the dangerous one: without this check a reply
      // belonging to the previous driver would overwrite the next driver's
      // stored name and phone.
      if (!mounted || !UserSessionState.isCurrent(_generation)) return;
      if (updated != null) {
        await AuthService.saveName(updated.dname);
        await AuthService.savePhone(updated.dphone);
        if (!mounted || !UserSessionState.isCurrent(_generation)) return;
      }
      _showSnack(
        _copy(
          context,
          'Profile updated successfully.',
          'تم تحديث المعلومات بنجاح.',
        ),
      );
      await _loadProfile();
    } on DioException catch (_) {
      if (!mounted || !UserSessionState.isCurrent(_generation)) return;
      _showSnack(
        _copy(
          context,
          'Unable to save changes. Please try again.',
          'تعذر حفظ التغييرات. حاول مرة أخرى.',
        ),
        isError: true,
      );
    } catch (_) {
      if (!mounted || !UserSessionState.isCurrent(_generation)) return;
      _showSnack(
        _copy(
          context,
          'Unable to save changes. Please try again.',
          'تعذر حفظ التغييرات. حاول مرة أخرى.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// What the driver reads after a failed save.
  ///
  /// The app's own wording for the outcomes it recognises, then the server's
  /// own text in the driver's language, then the generic fallback. The
  /// endpoint localizes its `message` field from a `lang` the app does not
  /// send, so borrowing it would put English in an Arabic snackbar — and the
  /// DB_* wording must never reach the driver at all.
  String _messageFrom(dynamic data) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final generic = _copy(
      context,
      'Unable to save changes. Please try again.',
      'تعذر حفظ التغييرات. حاول مرة أخرى.',
    );
    if (data is! Map) return generic;

    final byCode = _messageForCode(data['code']?.toString().toUpperCase());
    if (byCode != null) return byCode;

    final localized = isArabic ? data['message_ar'] : data['message_en'];
    final text = localized?.toString().trim();
    if (text != null && text.isNotEmpty) return text;
    return generic;
  }

  /// App-owned wording for the codes worth naming. Anything database-shaped
  /// collapses to the neutral service message.
  String? _messageForCode(String? code) {
    if (code == null || code.isEmpty) return null;
    if (code.startsWith('DB_')) {
      return _copy(
        context,
        'Service is unavailable. Please try again later.',
        'الخدمة غير متاحة حاليًا. يرجى المحاولة لاحقًا.',
      );
    }
    return switch (code) {
      'WEAK_PASSWORD' => _copy(
        context,
        'Password must be at least 10 characters.',
        'كلمة المرور يجب أن تكون 10 أحرف على الأقل.',
      ),
      'INVALID_IMAGE_TYPE' => _copy(
        context,
        'That image type is not supported.',
        'نوع الصورة غير مدعوم.',
      ),
      'UPLOAD_FAILED' || 'UPLOAD_DIR_ERROR' => _copy(
        context,
        'Unable to upload the photo. Please try again.',
        'تعذر رفع الصورة. حاول مرة أخرى.',
      ),
      'NO_DATA' => _copy(
        context,
        'No supported changes selected.',
        'لا توجد تغييرات مدعومة للحفظ.',
      ),
      'API_KEY_REQUIRED' || 'INVALID_API_KEY' => _copy(
        context,
        'Session expired. Please login again.',
        'انتهت الجلسة. يرجى تسجيل الدخول مرة أخرى.',
      ),
      _ => null,
    };
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
              isError ? const Color(0xffDC2626) : const Color(0xff16A06D),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF4F7FB),
      body: SafeArea(
        child: Column(
          children: [
            _PageHeader(
              title: _copy(context, 'Edit Profile', 'تعديل المعلومات'),
              subtitle: _copy(
                context,
                'Update supported driver information',
                'تحديث البيانات المدعومة حالياً',
              ),
            ),
            Expanded(
              child:
                  _isLoading
                      ? const _LoadingState()
                      : _loadFailed
                      ? _ErrorState(
                        message: _copy(
                          context,
                          'Unable to load account details. Please try again.',
                          'تعذر تحميل بيانات الحساب. يرجى المحاولة مرة أخرى.',
                        ),
                        retryLabel: _copy(context, 'Retry', 'حاول مرة أخرى'),
                        onRetry: _loadProfile,
                      )
                      : SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        // Clears the floating chat launcher as well as the
                        // bottom-navigation pill: at 110 Save sat under it.
                        padding: EdgeInsets.fromLTRB(
                          18,
                          16,
                          18,
                          DriverChatBubble.reservedBottomSpace + 16,
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _PhotoCard(
                                profile: _profile,
                                selectedImage: _selectedImage,
                                onPick: _pickImage,
                              ),
                              const SizedBox(height: 16),
                              _SectionCard(
                                title: _copy(
                                  context,
                                  'Driver Information',
                                  'معلومات المندوب',
                                ),
                                subtitle: _copy(
                                  context,
                                  'Name and phone are managed by the company.',
                                  'الاسم ورقم الهاتف يتم تعديلهما من قبل الشركة.',
                                ),
                                children: [
                                  _AppTextField(
                                    controller: _nameController,
                                    label: _copy(context, 'Name', 'الاسم'),
                                    icon: Icons.person_outline_rounded,
                                    readOnly: true,
                                    lockTooltip: _lockTooltip(context),
                                  ),
                                  const SizedBox(height: 12),
                                  _AppTextField(
                                    controller: _phoneController,
                                    label: _copy(context, 'Phone', 'الهاتف'),
                                    icon: Icons.phone_outlined,
                                    readOnly: true,
                                    // No keyboard type: the field cannot be
                                    // edited, and offering a phone keypad only
                                    // suggests otherwise.
                                    contentTextDirection: TextDirection.ltr,
                                    lockTooltip: _lockTooltip(context),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _SectionCard(
                                title: _copy(context, 'Security', 'الأمان'),
                                subtitle: _copy(
                                  context,
                                  'Password is optional. Leave it empty to keep the current password.',
                                  'كلمة المرور اختيارية. اتركها فارغة للإبقاء على الحالية.',
                                ),
                                children: [
                                  _AppTextField(
                                    controller: _passwordController,
                                    label: _copy(
                                      context,
                                      'New password',
                                      'كلمة مرور جديدة',
                                    ),
                                    icon: Icons.lock_outline_rounded,
                                    obscureText: _obscurePassword,
                                    onToggleObscure:
                                        () => setState(
                                          () =>
                                              _obscurePassword =
                                                  !_obscurePassword,
                                        ),
                                    validator: (value) {
                                      final text = value ?? '';
                                      if (text.trim().isEmpty) return null;
                                      return PasswordPolicy.message(
                                        text,
                                        isArabic:
                                            Localizations.localeOf(
                                              context,
                                            ).languageCode ==
                                            'ar',
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  _AppTextField(
                                    controller: _confirmPasswordController,
                                    label: _copy(
                                      context,
                                      'Confirm password',
                                      'تأكيد كلمة المرور',
                                    ),
                                    icon: Icons.lock_reset_rounded,
                                    obscureText: _obscureConfirm,
                                    onToggleObscure:
                                        () => setState(
                                          () =>
                                              _obscureConfirm =
                                                  !_obscureConfirm,
                                        ),
                                    validator: (value) {
                                      final password =
                                          _passwordController.text.trim();
                                      final confirm = value?.trim() ?? '';
                                      if (password.isEmpty && confirm.isEmpty) {
                                        return null;
                                      }
                                      if (password != confirm) {
                                        return _copy(
                                          context,
                                          'Passwords do not match.',
                                          'كلمتا المرور غير متطابقتين.',
                                        );
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              // `minimumSize` rather than a rigid SizedBox, so
                              // a larger accessibility text scale grows the
                              // button instead of clipping it.
                              ElevatedButton.icon(
                                onPressed: _isSaving ? null : _save,
                                icon:
                                    _isSaving
                                        ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                            color: Colors.white,
                                          ),
                                        )
                                        : const Icon(Icons.save_rounded),
                                label: Text(
                                  _isSaving
                                      ? _copy(
                                        context,
                                        'Saving...',
                                        'جارٍ الحفظ...',
                                      )
                                      : _copy(
                                        context,
                                        'Save Changes',
                                        'حفظ التغييرات',
                                      ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: AppColors.primary
                                      .withValues(alpha: 0.65),
                                  elevation: 0,
                                  minimumSize: const Size.fromHeight(54),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          _HeaderButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: Nav.back,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff0F172A),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xffE2E8F0)),
        ),
        child: Icon(icon, color: AppColors.primary, size: 18),
      ),
    );
  }
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({
    required this.profile,
    required this.selectedImage,
    required this.onPick,
  });

  final DriverInfo? profile;
  final File? selectedImage;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(22),
            ),
            clipBehavior: Clip.antiAlias,
            child:
                selectedImage != null
                    ? Image.file(selectedImage!, fit: BoxFit.cover)
                    : _ProfileImage(profile: profile),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _copy(context, 'Profile photo', 'صورة الحساب'),
                  style: const TextStyle(
                    color: Color(0xff0F172A),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _copy(
                    context,
                    'JPG, PNG, or WebP image.',
                    'صورة JPG أو PNG أو WebP.',
                  ),
                  style: const TextStyle(
                    color: Color(0xff64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: onPick,
                  icon: const Icon(Icons.image_outlined, size: 17),
                  label: Text(_copy(context, 'Choose photo', 'اختيار صورة')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.25),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileImage extends StatelessWidget {
  const _ProfileImage({required this.profile});

  final DriverInfo? profile;

  @override
  Widget build(BuildContext context) {
    final image = profile?.img.trim() ?? '';
    final url =
        image.isEmpty
            ? ''
            : image.startsWith('http')
            ? image
            : 'https://dashboard.blockatie.com$image';
    if (url.isEmpty) {
      return Icon(Icons.person_rounded, color: AppColors.primary, size: 32);
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder:
          (_, __, ___) =>
              Icon(Icons.person_rounded, color: AppColors.primary, size: 32),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xff0F172A),
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xff64748B),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _AppTextField extends StatelessWidget {
  const _AppTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.readOnly = false,
    this.obscureText = false,
    this.validator,
    this.contentTextDirection,
    this.onToggleObscure,
    this.lockTooltip,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool readOnly;
  final bool obscureText;
  final String? Function(String?)? validator;

  /// Direction of the typed content only. A phone reads left-to-right even in
  /// Arabic; the label and the error around it keep the page direction.
  final TextDirection? contentTextDirection;

  /// Non-null turns the field into a password field with a reveal control.
  final VoidCallback? onToggleObscure;

  /// Why a read-only field cannot be edited, in the driver's language.
  final String? lockTooltip;

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      obscureText: obscureText,
      validator: validator,
      // Once the driver has touched the field, a correction clears the error
      // as they type instead of waiting for the next Save.
      autovalidateMode:
          validator == null ? null : AutovalidateMode.onUserInteraction,
      textDirection: contentTextDirection,
      textAlign:
          contentTextDirection == TextDirection.ltr
              ? TextAlign.left
              : TextAlign.start,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.primary),
        suffixIcon: switch ((readOnly, onToggleObscure)) {
          (true, _) => Tooltip(
            message: lockTooltip ?? '',
            child: Semantics(
              label: lockTooltip,
              child: const Icon(Icons.lock_outline_rounded, size: 18),
            ),
          ),
          (false, final VoidCallback toggle) => IconButton(
            onPressed: toggle,
            tooltip:
                obscureText
                    ? (isArabic ? 'إظهار كلمة المرور' : 'Show password')
                    : (isArabic ? 'إخفاء كلمة المرور' : 'Hide password'),
            icon: Icon(
              obscureText
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
              size: 20,
              color: const Color(0xff64748B),
            ),
          ),
          _ => null,
        },
        filled: true,
        fillColor: readOnly ? const Color(0xffF8FAFC) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xffE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xffE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.primary, width: 1.4),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(child: CircularProgressIndicator(color: AppColors.primary));
  }
}

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: const Color(0xffE1E8F2)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.035),
        blurRadius: 18,
        offset: const Offset(0, 10),
      ),
    ],
  );
}

/// Why name and phone cannot be edited here.
String _lockTooltip(BuildContext context) =>
    _copy(context, 'Managed by the company', 'يتم تعديله من قبل الشركة');

/// Shown instead of the form when the profile could not be loaded, so Save is
/// never offered against an empty failed read.
class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 44,
              color: Color(0xff94A3B8),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xff0F172A),
                fontSize: 14,
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(retryLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _copy(BuildContext context, String en, String ar) {
  return Localizations.localeOf(context).languageCode == 'ar' ? ar : en;
}
