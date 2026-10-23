/// Capture before the temporary authentication MaterialApp updates browser URL.
String creatorInitialRoute(Uri base, {String fallback = '/'}) {
  final route = base.fragment.isNotEmpty ? base.fragment : fallback;
  final parsed = Uri.tryParse(route);
  if (parsed == null ||
      parsed.hasScheme ||
      parsed.hasAuthority ||
      !route.startsWith('/')) {
    return '/';
  }
  return route;
}
