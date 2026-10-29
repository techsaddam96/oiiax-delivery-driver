import 'package:flutter/widgets.dart';

/// Left-to-right for anything that is a number or an identifier, and the
/// ambient direction for everything else.
///
/// Phone numbers, policy numbers, driver ids and dial codes read the same way
/// in both languages: without this a leading `+`, or a `-` between groups, is
/// reordered by the surrounding Arabic paragraph. Localized words, names and
/// addresses are left alone — forcing them left-to-right would be wrong.
TextDirection? identifierTextDirection(String value) {
  if (value.trim().isEmpty) return null;
  return RegExp(r'^[0-9+\-()\s./]+$').hasMatch(value)
      ? TextDirection.ltr
      : null;
}

/// Wraps an identifier-shaped value in a left-to-right isolate.
///
/// For rich text, where a single span cannot carry its own direction, this is
/// the standard bidi tool: the isolate stops the surrounding Arabic paragraph
/// from reordering a leading `+` or the hyphens inside a policy number, while
/// the label around it keeps the page direction. Values that are not
/// identifier-shaped are returned untouched.
String isolateIdentifier(String value) {
  if (identifierTextDirection(value) != TextDirection.ltr) return value;
  return '\u2066$value\u2069';
}

/// Wraps any run in a left-to-right isolate, whatever its shape.
///
/// [isolateIdentifier] only acts on identifier-shaped values, which is right
/// for a policy number but wrong for something like a date range: the em dash
/// between two dates is not an identifier character, so the range fell through
/// unisolated and an Arabic paragraph reordered the two dates.
String isolateLtr(String value) {
  if (value.isEmpty) return value;
  return '⁦$value⁩';
}
