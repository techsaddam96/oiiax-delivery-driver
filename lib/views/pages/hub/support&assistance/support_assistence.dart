import 'dart:async';

import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/provider/profile.dart';
import 'package:blockatie/provider/support.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/clientMessageService.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/external_action.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/views/widgets/driver_chat_bubble.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SupportAssistencePage extends StatefulWidget {
  const SupportAssistencePage({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<SupportAssistencePage> createState() => _SupportAssistencePageState();
}

class _SupportAssistencePageState extends State<SupportAssistencePage> {
  static const String _whatsappNumber = '962779735616';

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();

  String _issueType = 'shipment';
  String? _driverId;
  bool _isSubmitting = false;

  /// The session this screen's prefilled identity belongs to.
  ///
  /// The form holds a driver's name, phone and id in plain widget state, which
  /// no provider reset can reach. Without this stamp, an account switch while
  /// Support is open would leave Driver A's identity in the fields for
  /// Driver B to submit.
  int _identityGeneration = UserSessionState.generation;

  @override
  void initState() {
    super.initState();
    UserSessionState.register(_clearDriverIdentity);
    unawaited(_prefillDriverData());
  }

  @override
  void dispose() {
    UserSessionState.unregister(_clearDriverIdentity);
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  /// Wipes everything that identifies the previous driver.
  ///
  /// What they typed themselves — subject, message, issue type — is left
  /// alone: it is not the previous driver's identity, and clearing a
  /// half-written complaint is not this boundary's job.
  void _clearDriverIdentity() {
    _identityGeneration = UserSessionState.generation;
    _nameController.clear();
    _phoneController.clear();
    _emailController.clear();
    _driverId = null;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _prefillDriverData() async {
    final generation = UserSessionState.generation;
    final profileProvider = context.read<ProfileProvider>();
    final profile =
        profileProvider.profileInfo ??
        await profileProvider.fetchDriverProfile();
    final values = await Future.wait([
      AuthService.getDrivername(),
      AuthService.getPhone(),
      AuthService.getuserId(),
    ]);
    // Opened from Login there is no session to read, and that is fine — the
    // form simply starts empty. What must not happen is a read that began
    // under one driver landing in the form under another.
    if (!mounted || !UserSessionState.isCurrent(generation)) return;
    setState(() {
      _identityGeneration = generation;
      _nameController.text = profile?.dname ?? values[0] ?? '';
      _phoneController.text = profile?.dphone ?? values[1] ?? '';
      _driverId = values[2];
    });
  }

  Future<void> _submitSupportRequest() async {
    if (_isSubmitting) return;
    FocusScope.of(context).unfocus();

    // A driver id captured under a previous session must never be submitted
    // under this one. The reset callback already blanks the fields; this is
    // the guard for the case where the switch lands between validation and
    // send.
    if (!UserSessionState.isCurrent(_identityGeneration)) {
      _clearDriverIdentity();
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final nameParts =
          _nameController.text
              .trim()
              .split(RegExp(r'\s+'))
              .where((part) => part.trim().isNotEmpty)
              .toList();
      final firstName = nameParts.isNotEmpty ? nameParts.first : 'Driver';
      final lastName =
          nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '-';
      final issueLabel = _issueTypeLabel(context, _issueType);
      final composedMessage = [
        'Driver App Support Request',
        'Driver ID: ${_driverId ?? '-'}',
        'Issue type: $issueLabel',
        'Subject: ${_subjectController.text.trim()}',
        '',
        _messageController.text.trim(),
      ].join('\n');

      final result = await ClientMessageService.sendClientMessage(
        firstname: firstName,
        lastname: lastName,
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        message: composedMessage,
        languageCode: Localizations.localeOf(context).languageCode,
      );

      if (!mounted) return;
      _showSnack(_submitMessage(result), isError: !result.isSuccess);

      if (result.isSuccess) {
        _subjectController.clear();
        _messageController.clear();
        setState(() => _issueType = 'shipment');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// What the driver reads after submitting.
  ///
  /// The endpoint's own sentence is used only when it arrived in the language
  /// the driver is reading; otherwise this screen writes it. Previously the
  /// untyped `message` key was shown whatever language it was in, so an Arabic
  /// driver could be handed English backend prose.
  String _submitMessage(SupportMessageResult result) {
    final serverMessage = result.serverMessage;
    if (serverMessage != null && serverMessage.isNotEmpty) {
      return serverMessage;
    }

    switch (result.outcome) {
      case SupportMessageOutcome.sent:
        return _copy(
          context,
          'Support request sent successfully.',
          'تم إرسال طلب الدعم بنجاح.',
        );
      case SupportMessageOutcome.network:
        return _copy(
          context,
          'Unable to connect. Please try again.',
          'تعذر الاتصال. يرجى المحاولة مرة أخرى.',
        );
      case SupportMessageOutcome.rejected:
      case SupportMessageOutcome.unknown:
        return _copy(
          context,
          'Unable to send your message. Please try again.',
          'تعذر إرسال رسالتك. يرجى المحاولة مرة أخرى.',
        );
    }
  }

  /// Hands off to WhatsApp and says so when it could not be opened.
  ///
  /// Awaited, unlike before: the call used to be fired and dropped, so a device
  /// without WhatsApp produced a tap that did nothing and an exception that
  /// went nowhere.
  Future<void> _openWhatsAppSupport() async {
    final result = await context.read<SupportProvider>().openWhatsApp(
      phoneNumber: _whatsappNumber,
      message: _copy(
        context,
        'Hello, I need help with the driver app.',
        'مرحباً، أحتاج مساعدة في تطبيق السائق.',
      ),
    );

    if (!mounted || result.isSuccess) return;
    _showSnack(externalActionFailureMessage(context), isError: true);
  }

  void _showSnack(String message, {bool isError = false}) {
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
            if (widget.showAppBar)
              _PageHeader(
                title: _copy(context, 'Technical Support', 'الدعم الفني'),
                subtitle: _copy(
                  context,
                  'How can we help you?',
                  'كيف يمكننا مساعدتك؟',
                ),
              )
            else
              const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                // The floating chat launcher sits above this screen. 110 was
                // less than it occupies, so the last card ended up underneath
                // it; the constant is read from the launcher itself so a change
                // to its geometry cannot leave this screen short again.
                padding: EdgeInsets.fromLTRB(
                  18,
                  16,
                  18,
                  DriverChatBubble.reservedBottomSpace + 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SupportHero(
                      title: _copy(
                        context,
                        'Need help on the road?',
                        'تحتاج مساعدة أثناء العمل؟',
                      ),
                      subtitle: _copy(
                        context,
                        'Send a request or contact us directly on WhatsApp.',
                        'أرسل طلب دعم أو تواصل معنا مباشرة عبر واتساب.',
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: _copy(
                        context,
                        'Contact Options',
                        'خيارات التواصل',
                      ),
                      children: [
                        _SupportActionTile(
                          icon: Icons.chat_rounded,
                          label: _copy(
                            context,
                            'WhatsApp Support',
                            'واتساب الدعم',
                          ),
                          subtitle: _copy(
                            context,
                            'Fastest way to contact the support team',
                            'أسرع طريقة للتواصل مع فريق الدعم',
                          ),
                          color: const Color(0xff16A06D),
                          onTap: _openWhatsAppSupport,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _SupportRequestForm(
                      formKey: _formKey,
                      nameController: _nameController,
                      phoneController: _phoneController,
                      emailController: _emailController,
                      subjectController: _subjectController,
                      messageController: _messageController,
                      issueType: _issueType,
                      isSubmitting: _isSubmitting,
                      onIssueTypeChanged: (value) {
                        if (value == null) return;
                        setState(() => _issueType = value);
                      },
                      onSubmit: _submitSupportRequest,
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: _copy(context, 'Quick FAQ', 'أسئلة سريعة'),
                      children: [
                        _FaqTile(
                          question: _copy(
                            context,
                            'How do I accept an available shipment?',
                            'كيف أقبل شحنة متاحة؟',
                          ),
                          answer: _copy(
                            context,
                            'Open Shipments, choose Available, then tap Accept Shipment.',
                            'افتح الشحنات، اختر المتاحة، ثم اضغط قبول الشحنة.',
                          ),
                        ),
                        _FaqTile(
                          question: _copy(
                            context,
                            'Why is location permission required?',
                            'لماذا صلاحية الموقع مطلوبة؟',
                          ),
                          answer: _copy(
                            context,
                            'It helps confirm arrival and update delivery tracking while you are online.',
                            'تساعد في تأكيد الوصول وتحديث تتبع التوصيل أثناء عملك.',
                          ),
                        ),
                        _FaqTile(
                          question: _copy(
                            context,
                            'How do I request a withdrawal?',
                            'كيف أطلب سحب المستحقات؟',
                          ),
                          answer: _copy(
                            context,
                            'Open Wallet, enter the amount, then send the withdrawal request.',
                            'افتح المحفظة، أدخل المبلغ، ثم أرسل طلب السحب.',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportRequestForm extends StatelessWidget {
  const _SupportRequestForm({
    required this.formKey,
    required this.nameController,
    required this.phoneController,
    required this.emailController,
    required this.subjectController,
    required this.messageController,
    required this.issueType,
    required this.isSubmitting,
    required this.onIssueTypeChanged,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController emailController;
  final TextEditingController subjectController;
  final TextEditingController messageController;
  final String issueType;
  final bool isSubmitting;
  final ValueChanged<String?> onIssueTypeChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _copy(context, 'Support Request', 'طلب دعم'),
              style: const TextStyle(
                color: Color(0xff0F172A),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _copy(
                context,
                'Describe the issue and our team will review it.',
                'اشرح المشكلة وسيقوم فريق الدعم بمراجعتها.',
              ),
              style: const TextStyle(
                color: Color(0xff64748B),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            _SupportTextField(
              controller: nameController,
              label: _copy(context, 'Name', 'الاسم'),
              icon: Icons.person_outline_rounded,
              validator: (value) {
                if ((value ?? '').trim().length < 2) {
                  return _copy(context, 'Name is required.', 'الاسم مطلوب.');
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            _SupportTextField(
              controller: phoneController,
              label: _copy(context, 'Phone', 'الهاتف'),
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              isIdentifier: true,
              validator: (value) {
                final phone = (value ?? '').replaceAll(RegExp(r'\D+'), '');
                if (phone.isEmpty) {
                  return _copy(
                    context,
                    'Phone is required.',
                    'رقم الهاتف مطلوب.',
                  );
                }
                if (!_isValidJordanPhoneInput(phone)) {
                  return _copy(
                    context,
                    'Enter a valid Jordan phone number.',
                    'أدخل رقم هاتف أردني صحيح.',
                  );
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            _SupportTextField(
              controller: emailController,
              label: _copy(context, 'Email', 'البريد الإلكتروني'),
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              isIdentifier: true,
              validator: (value) {
                final email = (value ?? '').trim();
                if (email.isEmpty) {
                  return _copy(
                    context,
                    'Email is required.',
                    'البريد الإلكتروني مطلوب.',
                  );
                }
                if (!RegExp(
                  r'^[\w\-.]+@([\w-]+\.)+[\w-]{2,}$',
                ).hasMatch(email)) {
                  return _copy(
                    context,
                    'Enter a valid email address.',
                    'أدخل بريداً إلكترونياً صحيحاً.',
                  );
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: issueType,
              borderRadius: BorderRadius.circular(16),
              // Without this the control sizes itself to its widest option,
              // which overflowed the form by 111px in Arabic — the Arabic
              // labels are longer than the English ones the layout was built
              // against. Expanded, the options wrap to the field's width.
              isExpanded: true,
              decoration: _inputDecoration(
                context,
                label: _copy(context, 'Issue Type', 'نوع المشكلة'),
                icon: Icons.category_outlined,
              ),
              items:
                  const ['shipment', 'login', 'wallet', 'location', 'other']
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(
                            _issueTypeLabel(context, type),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
              onChanged: isSubmitting ? null : onIssueTypeChanged,
            ),
            const SizedBox(height: 12),
            _SupportTextField(
              controller: subjectController,
              label: _copy(context, 'Subject', 'الموضوع'),
              icon: Icons.subject_rounded,
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return _copy(
                    context,
                    'Subject is required.',
                    'الموضوع مطلوب.',
                  );
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            _SupportTextField(
              controller: messageController,
              label: _copy(context, 'Message', 'الرسالة'),
              icon: Icons.notes_rounded,
              maxLines: 5,
              validator: (value) {
                if ((value ?? '').trim().length < 10) {
                  return _copy(
                    context,
                    'Message must be at least 10 characters.',
                    'الرسالة يجب أن تكون 10 أحرف على الأقل.',
                  );
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isSubmitting ? null : onSubmit,
                icon:
                    isSubmitting
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                        : const Icon(Icons.send_rounded),
                label: Text(
                  isSubmitting
                      ? _copy(context, 'Sending...', 'جارٍ الإرسال...')
                      : _copy(context, 'Send Request', 'إرسال الطلب'),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.primary.withValues(
                    alpha: 0.65,
                  ),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
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

class _SupportTextField extends StatelessWidget {
  const _SupportTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.maxLines = 1,
    this.validator,
    this.isIdentifier = false,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final int maxLines;
  final String? Function(String?)? validator;

  /// A phone number or an email address: left-to-right content that keeps its
  /// own direction inside an Arabic form. Prose fields — name, subject,
  /// message — are not identifiers and follow the page.
  final bool isIdentifier;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      textDirection: isIdentifier ? TextDirection.ltr : null,
      textAlign: isIdentifier ? TextAlign.left : TextAlign.start,
      decoration: _inputDecoration(context, label: label, icon: icon),
    );
  }
}

InputDecoration _inputDecoration(
  BuildContext context, {
  required String label,
  required IconData icon,
}) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, color: AppColors.primary),
    filled: true,
    fillColor: Colors.white,
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
  );
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
            tooltip:
                Localizations.localeOf(context).languageCode == 'ar'
                    ? 'رجوع'
                    : 'Back',
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
  const _HeaderButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    // The visual square stays 42 so the header keeps its proportions; the
    // touch target around it is grown to the 48 minimum instead.
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Center(child: _square(context)),
          ),
        ),
      ),
    );
  }

  Widget _square(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xffE2E8F0)),
      ),
      child: Icon(icon, color: AppColors.primary, size: 18),
    );
  }
}

class _SupportHero extends StatelessWidget {
  const _SupportHero({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xff0B63CE), Color(0xff00346F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  subtitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 12,
                    height: 1.35,
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
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
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _SupportActionTile extends StatelessWidget {
  const _SupportActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.16)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xff0F172A),
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xff64748B),
                      fontSize: 12,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.open_in_new_rounded, color: Color(0xff94A3B8)),
          ],
        ),
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 10),
        iconColor: AppColors.primary,
        collapsedIconColor: const Color(0xff94A3B8),
        title: Text(
          question,
          style: const TextStyle(
            color: Color(0xff0F172A),
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              answer,
              style: const TextStyle(
                color: Color(0xff64748B),
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
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

bool _isValidJordanPhoneInput(String value) {
  var phone = value.replaceAll(RegExp(r'\D+'), '');
  if (phone.startsWith('00962')) {
    phone = phone.substring(5);
  } else if (phone.startsWith('962')) {
    phone = phone.substring(3);
  }
  if (phone.isNotEmpty && !phone.startsWith('0')) {
    phone = '0$phone';
  }
  return RegExp(r'^07(7|8|9)\d{7}$').hasMatch(phone);
}

String _issueTypeLabel(BuildContext context, String type) {
  switch (type) {
    case 'shipment':
      return _copy(context, 'Shipment issue', 'مشكلة في شحنة');
    case 'login':
      return _copy(context, 'Login issue', 'مشكلة في تسجيل الدخول');
    case 'wallet':
      return _copy(context, 'Wallet issue', 'مشكلة في المحفظة');
    case 'location':
      return _copy(context, 'Location issue', 'مشكلة في الموقع');
    default:
      return _copy(context, 'Other', 'أخرى');
  }
}

String _copy(BuildContext context, String en, String ar) {
  return Localizations.localeOf(context).languageCode == 'ar' ? ar : en;
}
