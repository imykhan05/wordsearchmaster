import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/config/app_config.dart';
import '../../app/theme/theme.dart';
import '../../application/account_controller.dart';
import '../../domain/text/language.dart';
import '../../l10n/app_localizations.dart';
import '../../services/auth/auth_service.dart';
import '../meta/meta_tiles.dart';

/// The account section of the profile screen, and the shared sign-in action
/// behind the home screen's post-level-8 banner (Ch02 / P13).
///
/// GUEST IS NOT AN ERROR STATE. Ch02's whole FTUE is built on playing without
/// an account, so the guest copy is a plain statement of fact ("Playing as a
/// guest") with an offer next to it — never a warning icon, never a red
/// banner, and never a modal. The only thing signing in buys the player is
/// durability, so that is the only thing the copy promises.
class AccountCard extends ConsumerStatefulWidget {
  const AccountCard({super.key});

  @override
  ConsumerState<AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends ConsumerState<AccountCard> {
  /// True while the Google sheet is up, so the button can show a spinner and
  /// refuse a second tap. A `ValueNotifier` rather than `setState` — the same
  /// idiom the rest of the presentation layer uses (CLAUDE.md → no `setState`
  /// in game screens; this is not a game screen, but consistency is cheaper
  /// than a second convention).
  final ValueNotifier<bool> _busy = ValueNotifier(false);

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy.value) return;
    _busy.value = true;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);

    final result = await ref
        .read(accountControllerProvider.notifier)
        .linkWithGoogle();

    if (!mounted) return;
    _busy.value = false;

    final message = switch (result) {
      AccountLinkResult.linked => l10n.signInSuccessMessage,
      AccountLinkResult.linkedMergePending => l10n.signInMergePendingMessage,
      AccountLinkResult.failed => l10n.signInFailedMessage,
      // Backing out of the sheet is a decision, not an event worth narrating.
      AccountLinkResult.cancelled => null,
    };
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }

    // Closed-testing diagnostic, never shown on prod. `cancelled` and
    // `failed` both look the same to a player as "nothing happened", but
    // Android's Credential Manager reports `canceled` for a real user
    // cancel AND for the system cancelling credential retrieval after a
    // backend failure — indistinguishable without this raw code. See
    // `AuthService.lastGoogleSignInDiagnostic`'s own doc.
    if (result != AccountLinkResult.linked &&
        ref.read(appConfigProvider).flavor != Flavor.prod) {
      final diagnostic = ref
          .read(authServiceProvider)
          .lastGoogleSignInDiagnostic;
      if (diagnostic != null) {
        // Built as a variable, not a `Text('...')` literal: this is
        // deliberately NOT a translatable string (it never reaches a
        // player), so it must not trip `check_localized_strings.dart` either.
        final debugText = '[debug] $diagnostic';
        messenger.showSnackBar(
          SnackBar(
            content: Text(debugText),
            duration: const Duration(seconds: 12),
          ),
        );
      }
    }
  }

  Future<void> _signOut() async {
    if (_busy.value) return;
    _busy.value = true;
    await ref.read(accountControllerProvider.notifier).signOut();
    if (mounted) _busy.value = false;
  }

  static String _accountLabel(
    AppLocalizations l10n,
    AuthAccount? account, {
    required bool isLinked,
  }) {
    if (!isLinked) return l10n.accountGuestLabel;
    final name = account?.displayName ?? account?.email;
    return name == null ? l10n.accountSignedIn : l10n.accountSignedInAs(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final account = ref.watch(currentAccountProvider).value;
    final isLinked = account?.isLinked ?? false;

    return MetaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                isLinked ? Icons.cloud_done_outlined : Icons.person_outline,
                color: isLinked
                    ? tokens.colors.primary
                    : tokens.colors.onSurfaceMuted,
              ),
              const SizedBox(width: AppTokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.accountSectionTitle,
                      style: AppTypography.uiTextStyle(
                        Language.english,
                        UiRole.caption,
                        color: tokens.colors.onSurfaceMuted,
                      ),
                    ),
                    Text(
                      // A linked Google account can expose neither a display
                      // name nor an email (a hidden profile), so the
                      // name-less form exists rather than rendering
                      // "Signed in as null".
                      _accountLabel(l10n, account, isLinked: isLinked),
                      style: AppTypography.uiTextStyle(
                        Language.english,
                        UiRole.body,
                        color: tokens.colors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.space16),
          ValueListenableBuilder<bool>(
            valueListenable: _busy,
            builder: (context, busy, child) {
              if (isLinked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton(
                      onPressed: busy ? null : _signOut,
                      child: Text(l10n.signOutButton),
                    ),
                    const SizedBox(height: AppTokens.space4),
                    Text(
                      l10n.signOutKeepsProgress,
                      textAlign: TextAlign.center,
                      style: AppTypography.uiTextStyle(
                        Language.english,
                        UiRole.caption,
                        color: tokens.colors.onSurfaceMuted,
                      ),
                    ),
                  ],
                );
              }
              return FilledButton.icon(
                onPressed: busy ? null : _signIn,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: Text(l10n.signInWithGoogle),
              );
            },
          ),
        ],
      ),
    );
  }
}
