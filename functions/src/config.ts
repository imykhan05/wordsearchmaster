/**
 * Region, collection paths and every tunable the validation pipeline reads.
 *
 * ---------------------------------------------------------------------------
 * WHY asia-south1 IS NOT NEGOTIABLE
 *
 * The client pins the same region in `lib/app/config/app_config.dart`
 * (`functionsRegion`). A callable deployed to a region the client is not
 * pointed at fails at runtime with an opaque `internal`/`not-found`, not with
 * anything that names the mismatch — so the two constants are a matched pair,
 * and asia-south1 (Mumbai) is the one closest to the PK/IN audience in Ch01.
 *
 * ---------------------------------------------------------------------------
 * WHY THE THRESHOLDS LIVE HERE AND NOT AT THEIR CALL SITES
 *
 * Same reason `RemoteConfigKeys` exists on the client: a number with a name
 * and a stated rationale can be re-tuned by someone who did not write the
 * check. Every one of these is a FALSE-POSITIVE BUDGET, not a fact — a
 * threshold set too tight flags honest players, and the cost of that is
 * invisible (they never see an error, they just quietly stop appearing on a
 * leaderboard).
 */

/** Matches `AppConfig.functionsRegion`. Changing one without the other breaks every call. */
export const REGION = 'asia-south1';

export const COLLECTIONS = {
  users: 'users',
  /** `users/{uid}/scores/{scoreId}` — one doc per level and per daily. */
  scores: 'scores',
  /** `users/{uid}/nonces/{nonce}` — the replay guard. */
  nonces: 'nonces',
  /** `users/{uid}/coinGrants/{eventId}` — coins the SERVER granted (P18 rewarded ads). */
  coinGrants: 'coinGrants',
  /** `leaderboards/{board}/entries/{uid}`. */
  leaderboards: 'leaderboards',
  entries: 'entries',
  /** `moderation/{uid}/flags/{autoId}` — every suspicious submission, in full. */
  moderation: 'moderation',
  flags: 'flags',
  /** `rewardCallbacks/{eventId}` — AppLovin MAX S2S idempotency. */
  rewardCallbacks: 'rewardCallbacks',
} as const;

/** The three language codes, matching `Language.code`. */
export const LANGUAGES = ['ur', 'hi', 'en'] as const;
export type LanguageCode = (typeof LANGUAGES)[number];

export function isLanguageCode(value: unknown): value is LanguageCode {
  return typeof value === 'string' && (LANGUAGES as readonly string[]).includes(value);
}

export const LIMITS = {
  /** Journey levels, from `assets/content/levels.json` (P10). */
  minLevel: 1,
  maxLevel: 300,

  /**
   * Hard structural ceiling on the events array.
   *
   * A real level is at most 12 words; the rest of a replay is wrong
   * selections, which an unlucky player produces plenty of. 500 is far above
   * anything human and far below anything that would cost real CPU to replay,
   * so crossing it is MALFORMED (a hard `invalid-argument`), not suspicious.
   */
  maxEvents: 500,

  /** Below the breather floor in `DdaDownshift.minWords` / the Ch07 curve. */
  minWordsPerLevel: 3,

  /**
   * The shortest plausible time to find one word, in client milliseconds.
   *
   * Deliberately LOW. This is not "how long a level takes" — it is the floor
   * below which a human hand could not have traced that many words, and a
   * fast player on a 6x6 with four three-letter words is genuinely quick. A
   * generous floor catches the script that submits fifty levels stamped one
   * second apart without ever flagging the player who is simply good.
   */
  minMillisPerWord: 900,

  /**
   * How far into the future a client's `completedAt` may sit before it is a
   * signal.
   *
   * `TrustedClock` already documents that a clock set FORWARD offline is the
   * one case it cannot stop. This is the server half of that defence: a
   * device claiming to have finished a level tomorrow is exactly the forward
   * clock, seen from the only place that can see it. Ten minutes absorbs real
   * unsynced-device drift.
   */
  maxClockSkewMillis: 10 * 60 * 1000,

  /**
   * How far in the PAST a `completedAt` may sit before it is a signal.
   *
   * Deliberately enormous, and measured against the server clock rather than
   * against the account's creation time. The tempting check — "a completion
   * cannot predate the account" — flags an entirely normal case: the
   * `users/{uid}` document is first written by the first SUBMISSION, while the
   * levels in that submission were played before it, offline, possibly for
   * days. Ch10's outbox exists to make exactly that sequence work.
   *
   * What no honest client produces is a completion from before the game
   * existed, which is what a device clock reset to 1970 or to a random past
   * date looks like. 400 days also bounds how far a rewound clock can stretch
   * the timing accumulator's span — see `timingIsPlausible`.
   */
  maxSubmissionAgeMillis: 400 * 24 * 60 * 60 * 1000,

  /**
   * Fixed-window rate limit, per uid.
   *
   * SIZED FOR AN OFFLINE BACKLOG DRAIN, not for interactive play. The outbox
   * (Ch10) deliberately decouples playing from submitting: a player can
   * finish twenty levels on a plane and the queue drains all twenty within
   * seconds of the radio coming back. A limit tuned to "how fast can someone
   * play" would reject that player's real progress, which is the worst
   * outcome this whole file exists to avoid.
   */
  rateWindowMillis: 60 * 60 * 1000,
  rateMaxSubmissions: 240,

  /** Ceiling on a single rewarded-ad grant, so a mis-configured MAX unit cannot mint coins. */
  maxRewardCoins: 500,

  /** How stale a MAX callback's timestamp may be before it is refused. */
  rewardCallbackMaxAgeMillis: 15 * 60 * 1000,
} as const;

/**
 * Flag codes written onto a suspicious submission and into `moderation/`.
 *
 * Stable strings, because a moderation query written six months from now
 * filters on them. They are never returned to the client — see
 * `submitScore`'s header for why.
 */
export const FLAGS = {
  specVersionMismatch: 'spec_version_mismatch',
  unknownLevel: 'unknown_level',
  wordCountOutOfBounds: 'word_count_out_of_bounds',
  graphemeCountImplausible: 'grapheme_count_implausible',
  hintCountImplausible: 'hint_count_implausible',
  timingFloor: 'timing_floor',
  clockAhead: 'clock_ahead',
  clockRewound: 'clock_rewound',
  progressionGap: 'progression_gap',
  clientStarsMismatch: 'client_stars_mismatch',
  clientHintsMismatch: 'client_hints_mismatch',
  dailyReplay: 'daily_replay',
} as const;

export type FlagCode = (typeof FLAGS)[keyof typeof FLAGS];
