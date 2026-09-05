/**
 * A once-daily, per-account push nudging a player whose engagement streak
 * lapses at midnight UTC if they do not play again today (user-requested
 * re-engagement feature, post-P17).
 *
 * ---------------------------------------------------------------------------
 * WHY THIS REUSES `stats.engagementStreak` RATHER THAN INVENTING A SYNC PATH
 *
 * The player-FACING streak (`lib/domain/progression/streak.dart`) lives
 * entirely on the device and is never synced — CLAUDE.md is explicit that it
 * is a deliberate, permanent design choice, not a gap. Building a second sync
 * mechanism just so the server could know it would duplicate a system this
 * codebase already decided not to have.
 *
 * `stats.engagementStreak` (`stats.ts`, P17's Streak Keeper achievement)
 * already tracks almost the same thing server-side, DERIVED from submission
 * timestamps the timing checks already scrutinise — no client change, no new
 * collection. `stats.ts`'s own header already states honestly that this
 * number "will not always agree with the number the player sees on their
 * home screen" because of sync lag; that mismatch was an accepted trade for
 * Streak Keeper being unforgeable, and it is exactly as acceptable here,
 * where the cost of a stale read is an occasionally-early or occasionally-
 * skipped reminder, not a wrongly-granted achievement.
 *
 * One consequence worth being honest about: a player who has a streak FREEZE
 * available (`StreakRules`, local-only) is not exposed to this function at
 * all — freezes never sync. Such a player may get a "your streak is about to
 * end" nudge on a day they are actually already safe. Erring toward sending
 * the reminder is the right side of that trade for a low-stakes engagement
 * nudge — the cost of a false positive is one extra notification, not a lost
 * score or a lost level (the same false-positive-budget reasoning
 * `SECURITY.md`'s standing assumption #3 applies to every threshold in this
 * codebase).
 *
 * ---------------------------------------------------------------------------
 * "MAX ONE PUSH A DAY" IS ENFORCED HERE, SERVER-SIDE, PER ACCOUNT
 *
 * `users/{uid}.notifications.lastPushSentDay` is written ONLY by this
 * function (it is not a `profileFields()` entry, so no client can touch it),
 * which is what makes the rule trustworthy rather than advisory: today this
 * is the only push this codebase ever sends, but the field is already keyed
 * by TYPE-AGNOSTIC "was ANY push sent today", so a future second push type
 * shares the same gate rather than each type keeping its own clock and
 * silently doubling up.
 *
 * ---------------------------------------------------------------------------
 * THE SEND TRANSPORT IS INJECTABLE, ON PURPOSE
 *
 * There is no FCM emulator — `firebase emulators:exec` in this repo only
 * stands up Firestore and Auth (`functions/README.md`). A test that called
 * `getMessaging().send` directly would either need real Google credentials
 * this sandbox does not have, or would silently no-op the one behaviour worth
 * proving: that a successful send writes `lastPushSentDay`. [StreakReminderSender]
 * is the seam `test/integration/streakReminders.test.ts` uses to prove the
 * QUERY, the skip rules and the write-back against a real Firestore, with a
 * fake transport — the identical shape `bootstrap.dart`'s injectable
 * `openDatabase`/`loadContent` already use on the client for the same reason.
 *
 * ---------------------------------------------------------------------------
 * ONE FIXED UTC RUN TIME, NOT PER-TIMEZONE — A STATED SIMPLIFICATION
 *
 * There is no per-account timezone anywhere in this system (`TrustedClock`
 * deliberately keys everything to UTC calendar days, never a local one). This
 * schedule picks ONE UTC hour — 13:00, which is 18:00 in Pakistan and 18:30 in
 * India, Ch01's primary audience — rather than trying to fire per-account near
 * each player's own evening. A player far outside PK/IN gets a reminder at a
 * less considerate local hour; closing that needs storing a timezone or a
 * preferred hour per account, which this prompt does not attempt.
 */

import { getMessaging } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions';
import { onSchedule } from 'firebase-functions/v2/scheduler';

import { isLanguageCode, REGION, type LanguageCode } from './config';
import { db } from './firestore';
import { utcDateKey } from './leaderboardKeys';
import { readUserStats, type UserStats } from './stats';

/** Deliberately tiny — one line per language, not a taxonomy. A second push
 * type gets its own small table alongside this one, not a shared framework
 * built ahead of the second caller that would need it (CLAUDE.md's "never
 * do" section on premature abstraction). */
const COPY: Record<LanguageCode, { title: string; body: string }> = {
  en: {
    title: 'Your streak is about to end',
    body: "You haven't played today yet — one puzzle keeps it going.",
  },
  ur: {
    title: 'آپ کی لڑی ختم ہونے والی ہے',
    body: 'آپ نے آج ابھی تک نہیں کھیلا — ایک پہیلی اسے جاری رکھے گی۔',
  },
  hi: {
    title: 'आपकी लड़ी खत्म होने वाली है',
    body: 'आपने आज अभी तक नहीं खेला — एक पहेली इसे जारी रखेगी।',
  },
};

function utcDayBefore(day: string): string {
  const date = new Date(`${day}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() - 1);
  return utcDateKey(date);
}

/**
 * Pure: does this account deserve today's reminder?
 *
 * `alreadySentDay` is compared against `todayUtc` for the one-push-a-day
 * rule; `engagementStreak.lastDay` is compared against YESTERDAY, because
 * that is the shape of "about to lapse" — a streak whose last played day was
 * today needs no reminder, and one whose last played day was two or more
 * days ago has already lapsed (a "you lost it" push is not what this
 * function sends).
 */
export function shouldRemind(
  engagementStreak: UserStats['engagementStreak'],
  todayUtc: string,
  alreadySentDay: string | null,
): boolean {
  if (alreadySentDay === todayUtc) return false;
  if (engagementStreak.current <= 0) return false;
  return engagementStreak.lastDay === utcDayBefore(todayUtc);
}

export interface StreakReminderSender {
  send(token: string, message: { title: string; body: string }): Promise<void>;
}

class FcmStreakReminderSender implements StreakReminderSender {
  async send(token: string, message: { title: string; body: string }): Promise<void> {
    await getMessaging().send({ token, notification: message });
  }
}

function readLastPushSentDay(
  data: FirebaseFirestore.DocumentData | undefined,
): string | null {
  const notifications: unknown = data?.['notifications'];
  if (typeof notifications !== 'object' || notifications === null) return null;
  const day = (notifications as Record<string, unknown>)['lastPushSentDay'];
  return typeof day === 'string' ? day : null;
}

/**
 * Scans for accounts whose streak lapses if they do not play again today,
 * and sends each ONE push.
 *
 * ONE COLLECTION SCAN, ONCE A DAY — the same "the one place allowed a scan
 * beyond `.limit(100)`" shape `recomputeRanksForBoard` (`ranks.ts`) already
 * uses, and for the identical reason: doing this per-submission would read a
 * stats blob on every event, but a once-daily scheduled scan amortises a
 * single-field-equality query (no composite index needed — see
 * `firestore.indexes.json`'s header for the query that DOES need one) across
 * every account once a day.
 */
export async function sendDueStreakReminders(
  todayUtc: string,
  sender: StreakReminderSender = new FcmStreakReminderSender(),
): Promise<number> {
  const yesterday = utcDayBefore(todayUtc);
  const snapshot = await db()
    .collection('users')
    .where('stats.engagementStreak.lastDay', '==', yesterday)
    .get();

  let sent = 0;
  for (const doc of snapshot.docs) {
    const data = doc.data();
    const stats = readUserStats(data);
    if (!shouldRemind(stats.engagementStreak, todayUtc, readLastPushSentDay(data))) {
      continue;
    }

    const token: unknown = data['fcmToken'];
    if (typeof token !== 'string' || token.length === 0) continue;

    const language: unknown = data['language'];
    const copy = COPY[isLanguageCode(language) ? language : 'en'];

    try {
      await sender.send(token, copy);
    } catch (error) {
      // An expired or unregistered token is routine churn — an uninstall, a
      // reinstall, an app-data clear. Log and move to the next account rather
      // than failing a whole day's run over one stale token.
      logger.warn('streak reminder send failed', { uid: doc.id, error: String(error) });
      continue;
    }

    await doc.ref.set(
      { notifications: { lastPushSentDay: todayUtc } },
      { merge: true },
    );
    sent++;
  }
  return sent;
}

export const sendStreakReminders = onSchedule(
  { schedule: '0 13 * * *', timeZone: 'Etc/UTC', region: REGION },
  async () => {
    const sent = await sendDueStreakReminders(utcDateKey(new Date()));
    logger.info('streak reminders sent', { count: sent });
  },
);
