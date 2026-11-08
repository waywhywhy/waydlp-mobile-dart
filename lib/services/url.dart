/// URL validation and batch extraction (mirrors waydlp-core on desktop).
library;

class UrlError implements Exception {
  const UrlError(this.message);
  final String message;
  @override
  String toString() => message;
}

final _hostLike = RegExp(r'^[\p{L}\p{N}.-]+$', unicode: true);

bool _isLocalHost(String host) {
  final h = host.toLowerCase().replaceAll('[', '').replaceAll(']', '');
  if (h == 'localhost' || h.endsWith('.localhost') || h.endsWith('.local')) return true;
  final v4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(h);
  if (v4 != null) {
    final a = int.parse(v4.group(1)!);
    final b = int.parse(v4.group(2)!);
    return a == 127 ||
        a == 10 ||
        a == 0 ||
        (a == 192 && b == 168) ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 169 && b == 254);
  }
  if (h == '::1' || h.startsWith('fc') || h.startsWith('fd') || h.startsWith('fe80')) {
    return h.contains(':');
  }
  return false;
}

/// Validate and conservatively normalise a user-supplied URL.
Uri validateUrl(String input) {
  var s = input.trim();
  s = s.replaceAll(RegExp(r'''^["'<]+|["'>]+$'''), '').trim();
  if (s.isEmpty) throw const UrlError('Please enter a URL.');
  if (RegExp(r'\s').hasMatch(s)) throw const UrlError("This doesn't look like a web address.");
  final lower = s.toLowerCase();
  for (final bad in ['javascript:', 'data:', 'file:', 'mailto:', 'about:', 'content:', 'intent:']) {
    if (lower.startsWith(bad)) {
      throw const UrlError('Only http:// and https:// links are supported.');
    }
  }
  if (!s.contains('://')) {
    final host = s.split(RegExp(r'[/?#]')).first.split('@').last.split(':').first;
    if (!host.contains('.') || host.startsWith('.') || host.endsWith('.') || !_hostLike.hasMatch(host)) {
      throw const UrlError("This doesn't look like a web address.");
    }
    s = 'https://$s';
  }
  final Uri uri;
  try {
    uri = Uri.parse(s);
  } on FormatException {
    throw const UrlError("This doesn't look like a web address.");
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw UrlError('Only http:// and https:// links are supported (got "${uri.scheme}").');
  }
  if (uri.host.isEmpty) throw const UrlError('The link has no host name.');
  if (_isLocalHost(uri.host)) throw const UrlError('Local network addresses are not allowed.');
  return uri;
}

/// Pull every valid, unique URL out of free text (e.g. text shared from another app).
({List<Uri> valid, List<String> rejected}) extractUrls(String text) {
  final seen = <String>{};
  final valid = <Uri>[];
  final rejected = <String>[];
  for (final token in text.split(RegExp(r'[\s,;]+')).where((t) => t.isNotEmpty)) {
    try {
      final u = validateUrl(token);
      if (seen.add(u.toString())) valid.add(u);
    } on UrlError {
      rejected.add(token);
    }
  }
  return (valid: valid, rejected: rejected);
}

/// Extract the first URL from shared text such as "Check this out https://…".
Uri? firstUrlIn(String text) {
  final m = RegExp(r'https?://\S+').firstMatch(text);
  if (m == null) return null;
  try {
    return validateUrl(m.group(0)!);
  } on UrlError {
    return null;
  }
}

bool looksLikePlaylist(Uri u) {
  final p = u.path.toLowerCase();
  return u.queryParameters.containsKey('list') ||
      p.contains('/playlist') ||
      p.contains('/sets/') ||
      p.contains('/album/') ||
      p.contains('/channel/');
}

bool hasVideoAndList(Uri u) => u.queryParameters.containsKey('v') && u.queryParameters.containsKey('list');

/// Friendly site name ("YouTube", "example.org").
String siteName(Uri u) {
  const known = {
    'youtube.com': 'YouTube',
    'youtu.be': 'YouTube',
    'music.youtube.com': 'YouTube Music',
    'tiktok.com': 'TikTok',
    'instagram.com': 'Instagram',
    'facebook.com': 'Facebook',
    'x.com': 'X',
    'twitter.com': 'X',
    'reddit.com': 'Reddit',
    'twitch.tv': 'Twitch',
    'soundcloud.com': 'SoundCloud',
    'vimeo.com': 'Vimeo',
    'dailymotion.com': 'Dailymotion',
    'bandcamp.com': 'Bandcamp',
    'pinterest.com': 'Pinterest',
  };
  final h = u.host.toLowerCase();
  if (known.containsKey(h)) return known[h]!;
  for (final e in known.entries) {
    if (h.endsWith('.${e.key}')) return e.value;
  }
  for (final p in ['www.', 'm.', 'mobile.']) {
    if (h.startsWith(p)) return h.substring(p.length);
  }
  return h;
}
