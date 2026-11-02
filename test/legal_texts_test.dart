import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snooze_app/legal/legal_texts.dart';
import 'package:snooze_app/pages/legal_pages.dart';
import 'package:snooze_app/theme/app_theme.dart';

void main() {
  for (final doc in [privacyPolicy, termsOfService]) {
    group(doc.title, () {
      test('has no escaped line breaks and no empty sections', () {
        expect(doc.sections, isNotEmpty);
        for (final section in doc.sections) {
          expect(section.heading.trim(), isNotEmpty);
          expect(section.paragraphs, isNotEmpty, reason: section.heading);
          for (final paragraph in section.paragraphs) {
            expect(paragraph, isNot(contains(r'\n')), reason: section.heading);
            expect(paragraph.trim(), isNotEmpty, reason: section.heading);
          }
        }
      });

      test('ends with a way to contact us', () {
        expect(doc.sections.last.heading, 'Contact');
        expect(doc.sections.last.paragraphs.join(), contains('@'));
      });
    });
  }

  test('the privacy policy explains in-app account deletion', () {
    final text = privacyPolicy.sections.expand((s) => s.paragraphs).join(' ');
    expect(text, contains('Delete account'));
  });

  testWidgets('legal pages show their headings', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const PrivacyPage()),
    );
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('The short version'), findsOneWidget);
    expect(find.textContaining(r'\n'), findsNothing);
  });
}
