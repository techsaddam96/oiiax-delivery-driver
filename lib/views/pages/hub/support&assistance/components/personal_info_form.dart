import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/constants/helper.dart';
import 'package:blockatie/utils/localization.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/utils/size_config.dart';
import 'package:blockatie/utils/spacing.dart';
import 'package:blockatie/views/widgets/custom_elevated_btn.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../../../services/clientMessageService.dart';
import '../../../../dialoges/alert_dialoge.dart';
import '../../../../dialoges/sucess_dialoge.dart';

class ContactFormWidget extends StatefulWidget {
  final TextTheme textTheme;

  const ContactFormWidget({super.key, required this.textTheme});

  @override
  State<ContactFormWidget> createState() => _ContactFormWidgetState();
}

class _ContactFormWidgetState extends State<ContactFormWidget> with Helper {
  final _formKey = GlobalKey<FormState>();
  final _firstnameController = TextEditingController();
  final _lastnameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _messageController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _firstnameController.dispose();
    _lastnameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await ClientMessageService.sendClientMessage(
        firstname: _firstnameController.text.trim(),
        lastname: _lastnameController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        message: _messageController.text.trim(),
      );
      if (result.isSuccess) {
        // Show success message
        // AppUtils.showSuccessDialog(result['message'],
        //     title: tr('success'));
        showSucessDialoge(
          Nav.context,
          tr('success'),
          // The service now returns the endpoint's message only when it is in
          // the language being read, so there is nothing left to pick between
          // here; app-owned wording covers the case where it sent none.
          result.serverMessage ??
              (AppLocalizations.isArabic
                  ? 'تم إرسال رسالتك بنجاح.'
                  : 'Your message has been sent.'),
        );
        // Clear form
        _formKey.currentState!.reset();
        _firstnameController.clear();
        _lastnameController.clear();
        _phoneController.clear();
        _emailController.clear();
        _messageController.clear();
      } else if (_phoneController.text.length != 10 &&
          !_phoneController.text.startsWith('077') &&
          !_phoneController.text.startsWith('079') &&
          !_phoneController.text.startsWith('078')) {
        // AppUtils.showErrorDialog(tr('phone_valid'),
        //     title: tr('error'));
      } else {
        showAlertDialog(
          context,
          tr('serviceError'),
          tr('phone_valid'),
          showBtn: false,
        );
      }
    } catch (e) {
      // AppUtils.showErrorDialog(
      //     '${tr('an_error_occurred')}: $e',
      //     title: tr('error'));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Text(
              tr('contact_us'),
              style: widget.textTheme.bodyLarge!.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Text(
                textAlign: TextAlign.center,
                tr('support_24_hours'),
                style: widget.textTheme.bodySmall!,
              ),
            ),
            Spacing.y(1.5),
            TextFormField(
              controller: _firstnameController,
              decoration: InputDecoration(
                hintText: tr('first_name'),
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return tr('please_enter_first_name');
                }
                return null;
              },
            ),
            Spacing.y(1.5),
            TextFormField(
              controller: _lastnameController,
              decoration: InputDecoration(
                hintText: tr('last_name'),
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return tr('please_enter_last_name');
                }
                return null;
              },
            ),
            Spacing.y(1.5),
            TextFormField(
              controller: _phoneController,
              decoration: InputDecoration(
                hintText: tr('phone'),
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return tr('please_enter_your_phone_number');
                }
                return null;
              },
            ),
            Spacing.y(1.5),
            TextFormField(
              controller: _emailController,
              decoration: InputDecoration(
                hintText: tr('email'),
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return tr('please_enter_your_email');
                }
                if (!RegExp(
                  r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                ).hasMatch(value)) {
                  return tr('please_enter_a_valid_email');
                }
                return null;
              },
            ),
            Spacing.y(1.5),
            TextFormField(
              controller: _messageController,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: tr('message'),
                label: Text(tr('message')),
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return tr('please_enter_your_message');
                }
                return null;
              },
            ),
            Spacing.y(1.5),
            SizedBox(
              width: double.infinity,
              child: CustomElevatedBtn(
                label: _isLoading ? tr('sending') : tr('submit'),
                bgColor: AppColors.primary,
                height: SizeConfig.heightMultiplier * 5,
                textColor: Colors.white,
                onTap: _isLoading ? null : _submitForm,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Keep the old function for backward compatibility
Widget buildContactForm(TextTheme textTheme) {
  return ContactFormWidget(textTheme: textTheme);
}
