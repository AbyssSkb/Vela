import 'package:flutter/widgets.dart';

String notificationTitle(String name) {
  int width(String text) => text.characters.fold(
    0,
    (total, char) => total + (char.runes.first > 0x2fff ? 2 : 1),
  );
  const limit = 22;
  if (width(name) <= limit) return name;
  final dot = name.lastIndexOf('.');
  final extension = dot > 0 && name.length - dot <= 8
      ? name.substring(dot)
      : '';
  final budget = limit - width(extension) - 1;
  final prefix = StringBuffer();
  var used = 0;
  for (final char in name.characters) {
    final next = width(char);
    if (used + next > budget) break;
    prefix.write(char);
    used += next;
  }
  return '$prefix…$extension';
}
