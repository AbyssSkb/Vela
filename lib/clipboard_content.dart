String? detectHttpLink(String text) {
  final value = text.trim();
  if (value.contains(RegExp(r'\s'))) return null;
  final uri = Uri.tryParse(value);
  return uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty
      ? uri.toString()
      : null;
}
