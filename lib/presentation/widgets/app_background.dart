import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/theme.dart';
import '../../domain/theme/background_style.dart';
import '../../services/background/background_settings.dart';

/// Paints the chosen background behind [child].
///
/// Competitor-driven polish: `docs/competitor-analysis.md`'s recording shows
/// every competitor floating the grid and word list as opaque cards over a
/// full-screen scene, which is what makes their boards look like a place
/// rather than a form. This is that, over the app's own tokens — defaulting
/// to the app's own bundled artwork ([BackgroundStyle.brandArt]) rather than
/// a flat gradient, plus the one thing none of them offer, the player's own
/// photo.
///
/// A screen using this must make its `Scaffold` transparent, or the Scaffold's
/// own opaque colour paints straight over it.
class AppBackground extends ConsumerWidget {
  const AppBackground({required this.child, super.key});

  final Widget child;

  /// How much of the page colour is laid over a photo.
  ///
  /// NOT decoration — legibility. A photo is arbitrary: it can be a white sky
  /// or a black night, and behind it sit the top bar's score and the word
  /// chips, which are plain text with no card of their own. The scrim is what
  /// makes those readable against ANY picture rather than against the pictures
  /// that happened to be tried. Tuned toward the readable end on purpose,
  /// because CLAUDE.md's audience is 45+ and often running a large system
  /// font — the same reasoning that put a contrast floor on every other
  /// surface in this app.
  static const double photoScrimOpacity = 0.55;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(backgroundStyleSettingProvider);
    final path = ref.watch(backgroundPhotoPathProvider);
    final tokens = AppTokens.of(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Its own boundary: the background changes when a player picks a new
        // one and at no other time, while `child` above it is a whole game
        // screen repainting as it is played.
        RepaintBoundary(
          child: _BackgroundLayer(style: style, path: path, tokens: tokens),
        ),
        child,
      ],
    );
  }
}

class _BackgroundLayer extends StatelessWidget {
  const _BackgroundLayer({
    required this.style,
    required this.path,
    required this.tokens,
  });

  final BackgroundStyle style;
  final String? path;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final gradient = _gradient();

    if (style == BackgroundStyle.brandArt) {
      // A bundled asset, not a file — always present in the app bundle, so
      // this needs no existence check the way the player's own photo does.
      // `errorBuilder` still guards it: a corrupt or missing asset should
      // degrade to the gradient exactly like a missing photo does, never
      // throw past this widget.
      return _imageOverScrim(
        Image.asset(
          'assets/branding/background.png',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => gradient,
        ),
      );
    }

    if (style != BackgroundStyle.photo || path == null) return gradient;

    // The decoded size is capped at what this screen can actually show. The
    // stored copy is already downscaled (`ImagePickerBackgroundPhotoService`),
    // so on most phones this changes nothing — it is the guard for a narrow
    // device, where decoding the full stored width would hold memory no pixel
    // ever uses.
    final cacheWidth =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .round();

    return _imageOverScrim(
      Image.file(
        File(path!),
        fit: BoxFit.cover,
        cacheWidth: cacheWidth > 0 ? cacheWidth : null,
        // THE FILE GOING MISSING IS AN ORDINARY STATE, not an error. It
        // lives in a cache directory the OS may empty whenever it wants the
        // space, so this path runs for a player who did nothing wrong —
        // they get the gradient back, silently, exactly as Ch10 requires of
        // every other background failure in this app.
        errorBuilder: (context, error, stackTrace) => gradient,
      ),
    );
  }

  /// Shared by [BackgroundStyle.photo] and [BackgroundStyle.brandArt] — both
  /// are a full-bleed image with the SAME legibility scrim over it, just
  /// sourced from disk versus the app bundle.
  Widget _imageOverScrim(Widget image) {
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        ColoredBox(
          color: tokens.colors.background.withValues(
            alpha: AppBackground.photoScrimOpacity,
          ),
        ),
      ],
    );
  }

  Widget _gradient() {
    final gradients = tokens.colors.backgroundGradients;
    final stops = gradients[style.gradientIndex % gradients.length];

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [stops.from, stops.to],
        ),
      ),
    );
  }
}
