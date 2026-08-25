import 'dart:math' as math;
import 'dart:ui';

/// Colour-vision simulation, for verifying that the found-word palette stays
/// distinguishable rather than merely asserting that it does.
///
/// Uses the Viénot, Brettel & Mollon (1999) dichromat model: convert sRGB to
/// linear light, project onto the LMS plane the missing cone leaves behind,
/// then convert back. Perceptual distance is CIE76 ΔE in Lab, which is coarse
/// but more than adequate for "are these two obviously different colours".
///
/// Test-only. Nothing in lib/ depends on this.
enum ColorVision {
  /// Typical trichromatic vision.
  normal,

  /// Missing L-cones — roughly 1% of men.
  protanopia,

  /// Missing M-cones — roughly 1% of men, the most common form.
  deuteranopia,
}

/// Returns [color] as someone with [vision] would see it.
Color simulate(Color color, ColorVision vision) {
  if (vision == ColorVision.normal) return color;

  final r = _toLinear(color.r);
  final g = _toLinear(color.g);
  final b = _toLinear(color.b);

  // Linear RGB → LMS
  final l = 17.8824 * r + 43.5161 * g + 4.11935 * b;
  final m = 3.45565 * r + 27.1554 * g + 3.86714 * b;
  final s = 0.0299566 * r + 0.184309 * g + 1.46709 * b;

  final double lSim;
  final double mSim;
  switch (vision) {
    case ColorVision.protanopia:
      lSim = 2.02344 * m - 2.52581 * s;
      mSim = m;
    case ColorVision.deuteranopia:
      lSim = l;
      mSim = 0.494207 * l + 1.24827 * s;
    case ColorVision.normal:
      lSim = l;
      mSim = m;
  }

  // LMS → linear RGB
  final rSim = 0.080944 * lSim - 0.130504 * mSim + 0.116721 * s;
  final gSim = -0.0102485 * lSim + 0.0540194 * mSim - 0.113615 * s;
  final bSim = -0.000365294 * lSim - 0.00412163 * mSim + 0.693513 * s;

  return Color.from(
    alpha: color.a,
    red: _toSrgb(rSim),
    green: _toSrgb(gSim),
    blue: _toSrgb(bSim),
  );
}

/// CIE76 ΔE between two colours. Rough rule of thumb: ~2.3 is a just-noticeable
/// difference, and anything above ~15 reads as plainly a different colour.
double deltaE(Color a, Color b) {
  final labA = _toLab(a);
  final labB = _toLab(b);
  final dl = labA.$1 - labB.$1;
  final da = labA.$2 - labB.$2;
  final db = labA.$3 - labB.$3;
  return math.sqrt(dl * dl + da * da + db * db);
}

/// The smallest ΔE between any two colours in [colors] under [vision], plus
/// the indices of that closest pair.
({double distance, int a, int b}) closestPair(
  List<Color> colors,
  ColorVision vision,
) {
  final simulated = [for (final color in colors) simulate(color, vision)];

  var best = double.infinity;
  var bestA = 0;
  var bestB = 1;

  for (var i = 0; i < simulated.length; i++) {
    for (var j = i + 1; j < simulated.length; j++) {
      final distance = deltaE(simulated[i], simulated[j]);
      if (distance < best) {
        best = distance;
        bestA = i;
        bestB = j;
      }
    }
  }

  return (distance: best, a: bestA, b: bestB);
}

/// WCAG relative-luminance contrast ratio between two opaque colours,
/// from 1:1 (identical) to 21:1 (black on white).
double contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

double _relativeLuminance(Color color) =>
    0.2126 * _toLinear(color.r) +
    0.7152 * _toLinear(color.g) +
    0.0722 * _toLinear(color.b);

double _toLinear(double channel) {
  return channel <= 0.04045
      ? channel / 12.92
      : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
}

double _toSrgb(double linear) {
  final clamped = linear.clamp(0.0, 1.0);
  final encoded = clamped <= 0.0031308
      ? clamped * 12.92
      : 1.055 * math.pow(clamped, 1 / 2.4) - 0.055;
  return encoded.clamp(0.0, 1.0).toDouble();
}

/// sRGB → CIE Lab, D65 white point.
(double, double, double) _toLab(Color color) {
  final r = _toLinear(color.r);
  final g = _toLinear(color.g);
  final b = _toLinear(color.b);

  final x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047;
  final y = (0.2126729 * r + 0.7151522 * g + 0.0721750 * b) / 1.00000;
  final z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883;

  final fx = _labF(x);
  final fy = _labF(y);
  final fz = _labF(z);

  return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
}

double _labF(double t) {
  const epsilon = 216 / 24389;
  const kappa = 24389 / 27;
  return t > epsilon ? math.pow(t, 1 / 3).toDouble() : (kappa * t + 16) / 116;
}
