import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/colors.dart';
import '../../utils/size_config.dart';

class AuthTextfield extends StatefulWidget {
  const AuthTextfield({
    super.key,
    required this.hintText,
    required this.controller,
    this.prefix,
    this.width,
    this.isPassword = false,
    this.suffix,
    this.maxLines,
    this.keyboardType,
    this.onTap,
    this.inputFormatters,
    this.isDisable = false,
    this.height,
    this.validator,
    this.readOnly = false,
    // this.title = ""
  });
  // final String title;
  final VoidCallback? onTap;
  final String? Function(String?)? validator;
  final String hintText;
  final Widget? prefix;
  final bool isPassword;
  final TextEditingController controller;
  final double? width;
  final Widget? suffix;
  final int? maxLines;
  final bool isDisable;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final double? height;
  final bool readOnly;

  @override
  State<AuthTextfield> createState() => _AuthTextfieldState();
}

class _AuthTextfieldState extends State<AuthTextfield> {
  bool isObscure = true;
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Stack(
      alignment: Alignment.center,
      children: [
        Column(
          children: [
            SizedBox(
              height:
                  widget.height ??
                  (widget.maxLines != null
                      ? null
                      : SizeConfig.heightMultiplier * 5.5),
              // widget.maxLines != null ? null : SizeConfig.heightMultiplier * 5,
              width: widget.width,
              child: InkWell(
                child: TextFormField(
                  validator: widget.validator,
                  enabled: !widget.isDisable,
                  obscureText: widget.isPassword ? isObscure : false,
                  controller: widget.controller,
                  readOnly: widget.readOnly,
                  //  widget.onTap != null,
                  // autovalidateMode:AutovalidateMode.onUserInteraction,
                  onTap: widget.onTap,
                  // onSubmitted: (val) {},
                  textInputAction: TextInputAction.done,
                  keyboardType: widget.keyboardType,
                  maxLines: widget.isPassword ? 1 : widget.maxLines,
                  cursorColor: AppColors.primary,
                  textAlignVertical: TextAlignVertical.center,
                  style: textTheme.bodyMedium!.copyWith(color: Colors.black),
                  inputFormatters: widget.inputFormatters,
                  decoration: InputDecoration(
                    // isDense: true,
                    hintText: widget.hintText,
                    hintStyle: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                    // isCollapsed: true,
                    prefixIcon: widget.prefix,
                    prefixIconConstraints: BoxConstraints(
                      minWidth: SizeConfig.widthMultiplier * 12,
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal:
                          widget.prefix == null
                              ? SizeConfig.widthMultiplier * 3
                              : 0,

                      // widget.height ?? SizeConfig.heightMultiplier * 2,
                    ),
                    errorStyle: const TextStyle(height: 0, fontSize: 4),
                    // fillColor: Colors.white,
                    // filled: true,
                    suffixIcon:
                        widget.isPassword
                            ? IconButton(
                              onPressed: () {
                                isObscure = !isObscure;
                                setState(() {});
                              },
                              icon: Icon(
                                isObscure
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                color: Colors.grey,
                                size: 18,
                                // ? FluentIcons.eye_16_filled
                                // : FluentIcons.eye_off_16_filled,
                              ),
                            )
                            : widget.suffix == null
                            ? const SizedBox()
                            : IconButton(
                              onPressed: () {},
                              icon: widget.suffix!,
                            ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(
                        color: Colors.black,
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.red, width: 1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                // ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
