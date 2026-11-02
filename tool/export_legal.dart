// Writes the public legal pages (docs/, served by GitHub Pages) from the same
// texts the app shows (lib/legal/legal_texts.dart), so they can't drift.
//
//   dart run tool/export_legal.dart
import 'dart:io';

import 'package:snooze_app/legal/legal_texts.dart';

void main() {
  Directory('docs').createSync();
  _write('docs/privacy.html', privacyPolicy);
  _write('docs/terms.html', termsOfService);
  _write('docs/delete-account.html', accountDeletion);
  File('docs/index.html').writeAsStringSync(
    _page(
      'Snooze',
      '<p class="lead">Reminders that ring like an alarm until you answer '
          'them. Works without an account; sign in only to back up.</p>'
          '<ul class="links">'
          '<li><a href="privacy.html">Privacy policy</a></li>'
          '<li><a href="terms.html">Terms of service</a></li>'
          '<li><a href="delete-account.html">Delete your account</a></li>'
          '</ul>'
          '<p>Contact: <a href="mailto:$kLegalSupportEmail">'
          '$kLegalSupportEmail</a></p>',
    ),
  );
  stdout.writeln(
    'Wrote docs/index.html, privacy.html, terms.html, '
    'delete-account.html',
  );
}

void _write(String path, LegalDocument doc) {
  final body = StringBuffer(
    '<p class="date">Effective ${_escape(doc.effectiveDate)}</p>',
  );
  for (final section in doc.sections) {
    body.write('<h2>${_escape(section.heading)}</h2>');
    final bullets = <String>[];
    void flush() {
      if (bullets.isEmpty) return;
      body.write('<ul>${bullets.map((b) => '<li>$b</li>').join()}</ul>');
      bullets.clear();
    }

    for (final paragraph in section.paragraphs) {
      if (paragraph.startsWith('• ')) {
        bullets.add(_linkify(_escape(paragraph.substring(2))));
      } else {
        flush();
        body.write('<p>${_linkify(_escape(paragraph))}</p>');
      }
    }
    flush();
  }
  File(path).writeAsStringSync(_page(doc.title, body.toString()));
}

String _page(String title, String body) =>
    '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_escape(title)}</title>
<style>
  body { font: 17px/1.55 -apple-system, "Segoe UI", Roboto, sans-serif;
         color: #191511; background: #fcfaf8; margin: 0; }
  header { background: #b05108; color: #fff; padding: 20px; }
  header a { color: #fff; text-decoration: none; font-weight: 700; }
  main { max-width: 720px; margin: 0 auto; padding: 8px 20px 48px; }
  h1 { font-size: 30px; margin: 24px 0 4px; }
  h2 { font-size: 20px; margin: 28px 0 6px; }
  .date { color: #736b61; margin: 0; }
  .lead { font-size: 20px; }
  a { color: #b05108; }
</style>
</head>
<body>
<header><a href="index.html">Snooze</a></header>
<main>
<h1>${_escape(title)}</h1>
$body
</main>
</body>
</html>
''';

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _linkify(String text) => text.replaceAll(
  kLegalSupportEmail,
  '<a href="mailto:$kLegalSupportEmail">$kLegalSupportEmail</a>',
);
