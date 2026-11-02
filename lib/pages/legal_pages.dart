import 'package:flutter/material.dart';

import '../legal/legal_texts.dart';
import '../theme/app_tokens.dart';

class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const LegalPage(document: termsOfService);
}

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const LegalPage(document: privacyPolicy);
}

/// Shows a [LegalDocument] as headings and paragraphs; the text can be
/// selected and copied.
class LegalPage extends StatelessWidget {
  const LegalPage({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = AppTone.of(context).mutedText;

    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(
              'Effective ${document.effectiveDate}',
              style: textTheme.bodySmall?.copyWith(color: muted),
            ),
            for (final section in document.sections) ...[
              const SizedBox(height: 20),
              Semantics(
                header: true,
                child: Text(
                  section.heading,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final paragraph in section.paragraphs)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: paragraph.startsWith('• ')
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('•', style: textTheme.bodyMedium),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                paragraph.substring(2),
                                style: textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        )
                      : Text(paragraph, style: textTheme.bodyMedium),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
