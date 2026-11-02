import 'package:flutter/painting.dart';

/// WCAG contrast ratio between two opaque colours (1 to 21).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// [color], darkened on light backgrounds or lightened on dark ones just
/// enough to reach [minRatio] against [background] (4.5:1 is WCAG AA for
/// normal text). Keeps the hue, so tinted labels stay recognisable.
Color readableOn(Color color, Color background, {double minRatio = 4.5}) {
  if (contrastRatio(color, background) >= minRatio) return color;
  final darken = background.computeLuminance() > 0.5;
  var hsl = HSLColor.fromColor(color.withValues(alpha: 1));
  for (var i = 0; i < 40; i++) {
    final lightness = (hsl.lightness + (darken ? -0.025 : 0.025)).clamp(
      0.0,
      1.0,
    );
    hsl = hsl.withLightness(lightness);
    final candidate = hsl.toColor();
    if (contrastRatio(candidate, background) >= minRatio) return candidate;
    if (lightness == 0 || lightness == 1) break;
  }
  return darken ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
}
