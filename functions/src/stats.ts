/**
 * Server-granted achievements and the counters behind them (P17).
 *
 * ---------------------------------------------------------------------------
 * WHY THESE EIGHT SPLIT INTO TWO GRANTING PATHS
 *
 * Six of the eight named achievements are answerable from data the server
 * ALREADY has authoritative custody of by the time `recordSubmission`'s
 * transaction commits — a running word count, a per-language "has played"
 * set, a hint-free streak, a daily count, an engagement-day streak. Those are
 * evaluated HERE, inside that same transaction, and never need the client to
 * ask for them: the moment the counter crosses its threshold, the unlock is
 * written in the same write that advanced the counter.
 *
 * The two that are not:
 *
 *  * COLLECTOR ("a full category") needs to know which WORDS were in a level,
 *    and the server does not — `assets/content/` is not ported to this
 *    bundle (SECURITY.md's AR-9 already states this limit for the scoring
 *    pipeline; it applies here for the identical reason). Category
 *    completion is therefore detected on the DEVICE, from the same
 *    `Collections` derivation P11 already built over local `level_progress`,
 *    and submitted as a CLAIM via `submitAchievement` (`submissions.ts`'s
 *    sibling for this one path) — bounded-checked, never blindly trusted, the
 *    same posture the rest of this pipeline takes toward every client claim.
 *  * SPEED RUNNER ("level under 30s, Blitz only") depends on Blitz mode,
 *    which CLAUDE.md places at v1.2 and does not exist in this build. Its id
 *    is defined below so the client can render a locked, greyed slot with an
 *    honest caption — nothing anywhere grants it yet.
 *
 * ---------------------------------------------------------------------------
 * WHY `engagementStreak` IS NOT THE SAME NUMBER AS THE CLIENT'S `StreakState`
 *
 * Ch02's play streak (`lib/domain/progression/streak.dart`) lives entirely on
 * the device — it is never synced, by design (P16's ConflictResolver rule 8:
 * a device setting, kept local). Trusting a client-reported streak length for
 * an achievement would mean trusting a number this server has never seen
 * computed. So Streak Keeper is backed by a SEPARATE, server-own counter:
 * distinct UTC calendar days on which this account had at least one ACCEPTED
 * (non-suspicious) submission, derived from `completedAt` timestamps the
 * timing/clock checks in `validation.ts` already scrutinise. It will not
 * always agree with the number the player sees on their home screen — a day
 * played entirely offline and not yet synced has not reached this counter —
 * and that is the honest trade for the achievement being unforgeable rather
 * than for the two numbers matching exactly.
 */

import { LANGUAGES, type LanguageCode } from './config';
import { utcDateKey } from './leaderboardKeys';

export const ACHIEVEMENTS = {
  firstWord: 'first_word',
  wordMaster: 'word_master',
  trilingual: 'trilingual',
  onFire: 'on_fire',
  streakKeeper: 'streak_keeper',
  dailyDevotee: 'daily_devotee',
  collector: 'collector', // client-claimed — see header.
  speedRunner: 'speed_runner', // TODO(v1.2, Blitz mode) — never granted here.
} as const;

export type AchievementId = (typeof ACHIEVEMENTS)[keyof typeof ACHIEVEMENTS];

export const THRESHOLDS = {
  wordMasterWords: 500,
  onFireLevels: 5,
  streakKeeperDays: 7,
  dailyDevoteeCount: 10,
} as const;

export interface UserStats {
  readonly wordsFoundTotal: number;
  readonly dailyCount: number;
  readonly onFireStreak: number;
  readonly languagesPlayed: readonly LanguageCode[];
  readonly engagementStreak: {
    readonly current: number;
    readonly lastDay: string | null;
  };
  /** Ids already unlocked. A `Set` at read time; serialised as a map of `true`. */
  readonly achievements: ReadonlySet<AchievementId>;
}

export const EMPTY_STATS: UserStats = {
  wordsFoundTotal: 0,
  dailyCount: 0,
  onFireStreak: 0,
  languagesPlayed: [],
  engagementStreak: { current: 0, lastDay: null },
  achievements: new Set(),
};

/** Reads `users/{uid}.stats`, degrading every unreadable field to empty/zero. */
export function readUserStats(
  data: FirebaseFirestore.DocumentData | undefined,
): UserStats {
  const stats: unknown = data?.['stats'];
  if (typeof stats !== 'object' || stats === null) return EMPTY_STATS;
  const record = stats as Record<string, unknown>;

  const num = (key: string): number => {
    const value = record[key];
    return typeof value === 'number' && Number.isFinite(value) ? value : 0;
  };

  const languages = Array.isArray(record['languagesPlayed'])
    ? (record['languagesPlayed'] as unknown[]).filter(
        (value): value is LanguageCode =>
          typeof value === 'string' && (LANGUAGES as readonly string[]).includes(value),
      )
    : [];

  const engagement = record['engagementStreak'];
  const engagementRecord =
    typeof engagement === 'object' && engagement !== null
      ? (engagement as Record<string, unknown>)
      : {};

  const achievementsRaw = record['achievements'];
  const achievements = new Set<AchievementId>();
  if (typeof achievementsRaw === 'object' && achievementsRaw !== null) {
    const known = new Set<string>(Object.values(ACHIEVEMENTS));
    for (const id of Object.keys(achievementsRaw)) {
      if (known.has(id)) achievements.add(id as AchievementId);
    }
  }

  return {
    wordsFoundTotal: num('wordsFoundTotal'),
    dailyCount: num('dailyCount'),
    onFireStreak: num('onFireStreak'),
    languagesPlayed: languages,
    engagementStreak: {
      current:
        typeof engagementRecord['current'] === 'number'
          ? engagementRecord['current']
          : 0,
      lastDay:
        typeof engagementRecord['lastDay'] === 'string'
          ? engagementRecord['lastDay']
          : null,
    },
    achievements,
  };
}

/** One accepted submission, as `advanceStats` needs to see it. */
export interface AcceptedSubmissionEvent {
  readonly kind: 'level' | 'daily';
  readonly language: LanguageCode;
  readonly wordsFound: number;
  readonly hintsUsed: number;
  readonly completedAtMillis: number;
}

export interface StatsAdvance {
  readonly stats: UserStats;
  readonly newlyUnlocked: readonly AchievementId[];
}

/**
 * Folds one accepted (non-suspicious) submission into [prior], returning the
 * new counters and whatever crossed its threshold for the first time.
 *
 * PURE — no Firestore, no clock (the event carries its own timestamp) — so
 * every rule below is walked by `stats_test.ts` with no emulator.
 */
export function advanceStats(
  prior: UserStats,
  event: AcceptedSubmissionEvent,
): StatsAdvance {
  const wordsFoundTotal = prior.wordsFoundTotal + Math.max(0, event.wordsFound);
  const dailyCount = event.kind === 'daily' ? prior.dailyCount + 1 : prior.dailyCount;

  // On Fire counts LEVELS only ("5 levels, no hints") — a hint-free daily
  // neither extends nor breaks it, since the daily is a different mode with
  // its own difficulty shape.
  const onFireStreak =
    event.kind === 'level'
      ? event.hintsUsed <= 0
        ? prior.onFireStreak + 1
        : 0
      : prior.onFireStreak;

  const languagesPlayed = prior.languagesPlayed.includes(event.language)
    ? prior.languagesPlayed
    : [...prior.languagesPlayed, event.language];

  const engagementStreak = advanceEngagementStreak(
    prior.engagementStreak,
    event.completedAtMillis,
  );

  const unlocked = new Set(prior.achievements);
  const newlyUnlocked: AchievementId[] = [];
  const grant = (id: AchievementId) => {
    if (!unlocked.has(id)) {
      unlocked.add(id);
      newlyUnlocked.push(id);
    }
  };

  if (wordsFoundTotal >= 1) grant(ACHIEVEMENTS.firstWord);
  if (wordsFoundTotal >= THRESHOLDS.wordMasterWords) grant(ACHIEVEMENTS.wordMaster);
  if (languagesPlayed.length >= LANGUAGES.length) grant(ACHIEVEMENTS.trilingual);
  if (onFireStreak >= THRESHOLDS.onFireLevels) grant(ACHIEVEMENTS.onFire);
  if (dailyCount >= THRESHOLDS.dailyDevoteeCount) grant(ACHIEVEMENTS.dailyDevotee);
  if (engagementStreak.current >= THRESHOLDS.streakKeeperDays)
    grant(ACHIEVEMENTS.streakKeeper);

  return {
    stats: {
      wordsFoundTotal,
      dailyCount,
      onFireStreak,
      languagesPlayed,
      engagementStreak,
      achievements: unlocked,
    },
    newlyUnlocked,
  };
}

/**
 * Advances the day-streak counter by one submission's completion time.
 *
 * ORDER-AWARE, the same way the timing accumulator in `validation.ts` has to
 * be: the outbox can and does deliver an older backlog row AFTER a newer one.
 * A submission whose day is not strictly after `lastDay` is folded in without
 * moving the streak at all — same day, counted already; an EARLIER day,
 * arriving late, must not reopen or shrink a streak that has already moved
 * past it.
 */
export function advanceEngagementStreak(
  prior: UserStats['engagementStreak'],
  completedAtMillis: number,
): UserStats['engagementStreak'] {
  const day = utcDateKey(new Date(completedAtMillis));
  if (prior.lastDay === null) return { current: 1, lastDay: day };
  if (day <= prior.lastDay) return prior;
  if (isNextUtcDay(prior.lastDay, day))
    return { current: prior.current + 1, lastDay: day };
  return { current: 1, lastDay: day }; // a gap: the streak restarts at this day.
}

function isNextUtcDay(previousDay: string, day: string): boolean {
  const previous = new Date(`${previousDay}T00:00:00.000Z`);
  const next = new Date(`${day}T00:00:00.000Z`);
  return next.getTime() - previous.getTime() === 86_400_000;
}

/**
 * The plain-object form `recordSubmission` merges into `users/{uid}.stats`.
 *
 * Omits `achievements` entirely when nothing unlocked THIS submission — the
 * caller uses `{merge: true}`, and Firestore's merge is per-field, so leaving
 * the key out means "do not touch the achievements already stored" rather
 * than "there are now none".
 */
export function statsUpdatePayload(advance: StatsAdvance): Record<string, unknown> {
  const payload: Record<string, unknown> = {
    wordsFoundTotal: advance.stats.wordsFoundTotal,
    dailyCount: advance.stats.dailyCount,
    onFireStreak: advance.stats.onFireStreak,
    languagesPlayed: advance.stats.languagesPlayed,
    engagementStreak: advance.stats.engagementStreak,
  };
  if (advance.newlyUnlocked.length > 0) {
    payload['achievements'] = Object.fromEntries(
      advance.newlyUnlocked.map((id) => [id, { unlockedAt: Date.now() }]),
    );
  }
  return payload;
}
