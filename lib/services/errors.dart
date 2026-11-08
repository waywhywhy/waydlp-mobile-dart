/// Readable error classification (port of waydlp-core errors.rs).
library;

enum ErrorKind {
  unsupportedUrl('This link isn\'t supported', 'yt-dlp doesn\'t recognise this website or page.'),
  unavailable('The media is unavailable', 'It may have been removed by the uploader.'),
  private('The media is private', 'Only people the uploader shared it with can access it.'),
  ageRestricted('Age-restricted content', 'The site requires a signed-in account.'),
  loginRequired('Sign-in required', 'The site requires a signed-in account.'),
  geoRestricted('Not available in your region', 'The uploader limited it to other countries.'),
  liveNotStarted('The live stream hasn\'t started', 'Try again once the stream is live.'),
  drm('DRM-protected content', 'waydlp does not and will not circumvent DRM protection.'),
  extractorOutdated(
    'yt-dlp may be out of date',
    'The website probably changed. Update yt-dlp in Settings, then retry.',
  ),
  rateLimited('The site is rate-limiting requests', 'Wait a while before retrying, or download fewer items at once.'),
  formatUnavailable('The selected format isn\'t available', 'Analyse the link again and choose a listed quality.'),
  diskFull('Storage is full', 'Free up space on your device.'),
  permissionDenied('Permission denied', 'waydlp could not write to the chosen folder. Choose another in Settings.'),
  network('Network problem', 'Check your connection and try again.'),
  timeout('The connection timed out', 'The site took too long to respond. Try again later.'),
  conversionFailed('Conversion failed', 'Try a different output format.'),
  engine('The download engine failed to start', 'Restart waydlp. If it persists, reinstall the app.'),
  cancelled('Cancelled', 'The download was cancelled.'),
  unknown('The download failed', 'Open the technical details for more information.');

  const ErrorKind(this.title, this.hint);
  final String title;
  final String hint;

  bool get isTransient => this == network || this == timeout || this == rateLimited || this == unknown;
}

const _rules = <(ErrorKind, List<String>)>[
  (ErrorKind.drm, ['drm protected', 'is drm', 'known to use drm']),
  (ErrorKind.unsupportedUrl, ['unsupported url', 'is not a valid url', 'no suitable extractor']),
  (ErrorKind.private, ['private video', 'this video is private', 'is private']),
  (ErrorKind.ageRestricted, ['confirm your age', 'age-restricted', 'age restricted', 'inappropriate for some users']),
  (
    ErrorKind.loginRequired,
    [
      'sign in to confirm',
      'login required',
      'log in to',
      'requires authentication',
      'only available for registered users',
      'use --cookies',
      'members-only',
      'join this channel',
    ],
  ),
  (
    ErrorKind.geoRestricted,
    ['available in your country', 'geo restrict', 'geo-restrict', 'not available from your location'],
  ),
  (ErrorKind.liveNotStarted, ['live event will begin', 'premieres in', 'this live event will']),
  (ErrorKind.rateLimited, ['http error 429', 'too many requests', 'rate-limit', 'rate limit']),
  (
    ErrorKind.formatUnavailable,
    ['requested format is not available', 'requested format not available', 'no video formats found'],
  ),
  (ErrorKind.diskFull, ['no space left on device', 'errno 28', 'enospc']),
  (ErrorKind.permissionDenied, ['permission denied', 'errno 13', 'eacces']),
  (ErrorKind.timeout, ['timed out', 'timeout']),
  (
    ErrorKind.network,
    [
      'unable to download webpage',
      'getaddrinfo failed',
      'name or service not known',
      'temporary failure in name resolution',
      'no address associated with hostname',
      'connection refused',
      'connection reset',
      'network is unreachable',
      'failed to resolve',
      'remote end closed connection',
      'http error 5',
    ],
  ),
  (
    ErrorKind.unavailable,
    ['video unavailable', 'has been removed', 'no longer available', 'http error 404', 'does not exist'],
  ),
  (ErrorKind.conversionFailed, ['postprocessing:', 'conversion failed', 'error opening output file']),
  (
    ErrorKind.extractorOutdated,
    ['unable to extract', 'please report this issue', 'update to the latest version', 'unable to parse'],
  ),
];

ErrorKind classify(String output) {
  final lower = output.toLowerCase();
  final errorLines = lower.split('\n').where((l) => l.contains('error')).join('\n');
  for (final hay in [errorLines, lower]) {
    if (hay.isEmpty) continue;
    for (final (kind, needles) in _rules) {
      if (needles.any(hay.contains)) return kind;
    }
  }
  return ErrorKind.unknown;
}

/// Remove cookie/authorization headers and URL credentials from diagnostics.
String redact(String s) {
  return s
      .split('\n')
      .map((line) {
        final l = line.toLowerCase();
        if (l.contains('cookie:') || l.contains('authorization:') || l.contains('set-cookie')) {
          return '[redacted header]';
        }
        return line.replaceAllMapped(RegExp(r'://[^/\s@]+@'), (_) => '://***@');
      })
      .join('\n');
}

class Failure {
  Failure(this.kind, this.summary, String details) : details = redact(details);

  factory Failure.fromOutput(String output) {
    final lines = output.split('\n').reversed;
    final summary =
        lines.map((l) => l.trim()).where((l) => l.startsWith('ERROR:')).map((l) => l.substring(6).trim()).firstOrNull ??
        lines.map((l) => l.trim()).where((l) => l.isNotEmpty).firstOrNull ??
        '';
    final kind = classify(output);
    return Failure(kind, summary.isEmpty ? kind.title : summary, output);
  }

  final ErrorKind kind;
  final String summary;
  final String details;

  Map<String, Object?> toJson() => {'kind': kind.name, 'summary': summary, 'details': details};
}
