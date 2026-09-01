import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme/theme.dart';
import '../../application/friends_controller.dart';
import '../../data/remote/friends_api.dart';
import '../../domain/text/language.dart';
import '../../l10n/app_localizations.dart';
import 'meta_tiles.dart';

/// The Friends tab of the leaderboard (P17) — invite code, share sheet,
/// redeem field, and the accepted-friends list.
///
/// ---------------------------------------------------------------------------
/// NO CONTACT-BOOK ACCESS, EVER
///
/// The prompt is explicit: that permission scares this audience and hurts
/// install-to-open rate. Everything here goes through a share CODE and the
/// native share sheet (`share_plus`, wrapped no differently from any other
/// vendor SDK this codebase keeps behind an interface) — never a contacts
/// picker, never a phone-number lookup.
///
/// ---------------------------------------------------------------------------
/// FRIENDS ARE FEW; THIS LIST NEEDS NO LIVE-LISTENER LIFECYCLE DISCIPLINE
/// BEYOND WHAT [friendsListProvider] ALREADY GIVES IT
///
/// `friendsListProvider` follows the identical "plain `@riverpod`, no
/// `keepAlive`" shape `leaderboardTopProvider` uses — leaving this tab (the
/// screen's own `switch`, not a `TabBarView`) drops the last watcher and
/// closes the Firestore listener with it.
class FriendsTab extends ConsumerWidget {
  const FriendsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(friendsListProvider);

    return ListView(
      children: [
        const _InviteCodeCard(),
        const SizedBox(height: AppTokens.space16),
        const _RedeemCodeCard(),
        const SizedBox(height: AppTokens.space16),
        switch (friends) {
          AsyncData(value: final list) when list.isNotEmpty => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final friend in list) _FriendRow(friend: friend)],
          ),
          AsyncData() => const _EmptyFriends(),
          _ => const SizedBox.shrink(),
        },
      ],
    );
  }
}

class _InviteCodeCard extends ConsumerWidget {
  const _InviteCodeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final code = ref.watch(ownInviteCodeProvider);

    return MetaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.friendsInviteCodeLabel,
            style: AppTypography.uiTextStyle(
              Language.english,
              UiRole.caption,
              color: tokens.colors.onSurfaceMuted,
            ),
          ),
          const SizedBox(height: AppTokens.space8),
          Row(
            children: [
              Expanded(
                child: Text(
                  code.value ?? '—',
                  style: AppTypography.uiTextStyle(
                    Language.english,
                    UiRole.display,
                    color: tokens.colors.onSurface,
                  ),
                ),
              ),
              FilledButton(
                onPressed: code.value == null
                    ? null
                    : () => SharePlus.instance.share(
                        ShareParams(text: code.value!),
                      ),
                child: Text(l10n.friendsShareButton),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RedeemCodeCard extends ConsumerStatefulWidget {
  const _RedeemCodeCard();

  @override
  ConsumerState<_RedeemCodeCard> createState() => _RedeemCodeCardState();
}

class _RedeemCodeCardState extends ConsumerState<_RedeemCodeCard> {
  final _controller = TextEditingController();
  String? _status;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final code = _controller.text.trim();
    if (code.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });

    final l10n = AppLocalizations.of(context);
    final outcome = await ref
        .read(friendRedeemerProvider.notifier)
        .redeem(code);
    if (!mounted) return;

    setState(() {
      _busy = false;
      _status = switch (outcome) {
        RedeemFriended() || RedeemAlreadyFriends() =>
          outcome is RedeemAlreadyFriends
              ? l10n.friendsRedeemAlreadyFriends
              : l10n.friendsRedeemSuccess,
        RedeemNotFound() => l10n.friendsRedeemNotFound,
        RedeemOwnCode() => l10n.friendsRedeemOwnCode,
        RedeemLimitReached() => l10n.friendsRedeemLimitReached,
        RedeemFailed() => l10n.friendsRedeemFailed,
      };
    });
    if (outcome is RedeemFriended) {
      _controller.clear();
      // A fresh friendship changed the graph `friendsListProvider` watches —
      // invalidate so the list refetches rather than waiting on whatever
      // cadence the live listener happens to notice the new doc under.
      ref.invalidate(friendsListProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);

    return MetaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: l10n.friendsRedeemFieldLabel,
            ),
            onSubmitted: (_) => _redeem(),
          ),
          const SizedBox(height: AppTokens.space8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (_status != null)
                Expanded(
                  child: Text(
                    _status!,
                    style: AppTypography.uiTextStyle(
                      Language.english,
                      UiRole.caption,
                      color: tokens.colors.onSurfaceMuted,
                    ),
                  ),
                ),
              FilledButton(
                onPressed: _busy ? null : _redeem,
                child: Text(l10n.friendsRedeemButton),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({required this.friend});

  final FriendEntry friend;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.space8),
      child: MetaCard(
        child: Text(
          friend.displayName ?? friend.uid,
          style: AppTypography.uiTextStyle(
            Language.english,
            UiRole.body,
            color: tokens.colors.onSurface,
          ),
        ),
      ),
    );
  }
}

class _EmptyFriends extends StatelessWidget {
  const _EmptyFriends();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.space32),
        child: Text(
          l10n.friendsEmpty,
          textAlign: TextAlign.center,
          style: AppTypography.uiTextStyle(
            Language.english,
            UiRole.body,
            color: tokens.colors.onSurfaceMuted,
          ),
        ),
      ),
    );
  }
}
