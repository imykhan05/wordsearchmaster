/**
 * The Ch08 validation pipeline — PURE, so all of it is unit-testable without a
 * Firestore instance, an emulator, or an auth context.
 *
 * ---------------------------------------------------------------------------
 * TWO REJECTION CLASSES, AND THE LINE BETWEEN THEM IS THE POINT
 *
 *  * MALFORMED -> a thrown `MalformedSubmission`, which the callable turns
 *    into `invalid-argument`. These are payloads an honest client CANNOT
 *    produce: a missing field, a level id that is not a number, an events
 *    array of ten thousand entries. There is no player behaviour to attribute
 *    them to and nothing to flag, so answering honestly costs nothing.
 *
 *  * SUSPICIOUS -> a flag on an otherwise SUCCESSFUL response. These are
 *    well-formed payloads whose contents do not add up: a level reached
 *    without playing the one before it, fifty completions inside a minute, a
 *    claimed star count that disagrees with the events. P14's rule is
 *    explicit — never return an error to a suspected cheater. They get a
 *    normal-looking success, the score is written with `suspicious: true`,
 *    every leaderboard skips it, and `moderation/` gets the whole payload.
 *    A cheater who is told they were caught iterates until they are not.
 *
 * The one thing NEITHER class does is trust the client's arithmetic. The score
 * is always recomputed here from the submitted events; the client's own total
 * is not read because `ScoreEventCodec` does not even send it.
 */

import {
  FLAGS,
  LIMITS,
  isLanguageCode,
  type FlagCode,
  type LanguageCode,
} from './config';
import { isDayKey } from './leaderboardKeys';
import { isPlausibleGraphemeCount, wordCountBounds, type LevelShape } from './levels';
import {
  EVENT_HINT_USED,
  EVENT_WORD_FOUND,
  EVENT_WRONG_SELECTION,
  SPEC_VERSION,
  computeScore,
  computeStars,
  hintsIn,
  maxComboIn,
  wordsFoundIn,
  type ScoreEvent,
} from './scoring';

/** Thrown for a payload an honest client could not have produced. */
export class MalformedSubmission extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'MalformedSubmission';
  }
}

export type SubmissionKind = 'level' | 'daily';

interface BaseSubmission {
  readonly language: LanguageCode;
  readonly events: readonly ScoreEvent[];
  readonly completedAt: number;
  readonly specVersion: number;
  readonly nonce: string;
  /**
   * What the client THINKS it scored in stars and hints.
   *
   * Read as a TAMPER SIGNAL and nothing else — the values written are always
   * the recomputed ones. A modified client that inflates its stars while
   * leaving the events untouched is exactly the naive attack, and it is free
   * to detect here. (The score itself has no such field: the client never
   * sends one.)
   */
  readonly clientStars: number | null;
  readonly clientHintsUsed: number | null;
}

export interface LevelSubmission extends BaseSubmission {
  readonly kind: 'level';
  readonly level: number;
}

export interface DailySubmission extends BaseSubmission {
  readonly kind: 'daily';
  readonly date: string;
}

export type Submission = LevelSubmission | DailySubmission;

/** Everything the stateful checks need, read from `users/{uid}` before the replay. */
export interface PlayerContext {
  /** Server wall clock in millis. The one clock in this file that is trusted. */
  readonly serverNowMillis: number;
  /** Highest journey level already recorded in THIS language. */
  readonly highestLevel: number;
  readonly timing: TimingContext;
}

/**
 * The cumulative timing state, and the reason it is cumulative rather than a
 * "how long did this level take" field.
 *
 * A level has no measured duration to send: relaxed mode has no timer at all
 * (`Scoring.computeStars` takes no elapsed parameter, on purpose), so there is
 * nothing honest for the client to put in such a field — and anything it did
 * put there would be client-controlled and therefore worthless as a bound.
 *
 * What IS checkable is the whole account at once: the span of client time the
 * player has claimed to play across, versus the minimum time the work they
 * have submitted could possibly have taken. That comparison is ORDER
 * INDEPENDENT, which matters because the outbox (Ch10) can and does deliver
 * completions out of order after a retry — a check written as "this
 * submission minus the previous one" would flag honest players every time a
 * queued row was retried behind a newer one.
 *
 * The earliest submission contributes no requirement, because nothing bounds
 * how long the very first level took.
 */
export interface TimingContext {
  readonly submissionCount: number;
  readonly earliestCompletedAt: number | null;
  readonly latestCompletedAt: number | null;
  readonly minRequiredMillis: number;
}

export const EMPTY_TIMING: TimingContext = {
  submissionCount: 0,
  earliestCompletedAt: null,
  latestCompletedAt: null,
  minRequiredMillis: 0,
};

export interface EvaluatedSubmission {
  /** THE number that gets written. Recomputed here, never read from the client. */
  readonly score: number;
  readonly stars: number;
  readonly hintsUsed: number;
  readonly wordsFound: number;
  readonly maxCombo: number;
  readonly flags: readonly FlagCode[];
  readonly suspicious: boolean;
  /** The timing accumulator to persist when this submission is accepted. */
  readonly timing: TimingContext;
}

// ---------------------------------------------------------------------------
// Parsing — structural only. Anything that fails here is MALFORMED.
// ---------------------------------------------------------------------------

function requireObject(data: unknown): Record<string, unknown> {
  if (typeof data !== 'object' || data === null || Array.isArray(data)) {
    throw new MalformedSubmission('payload must be an object');
  }
  return data as Record<string, unknown>;
}

function requireInt(raw: unknown, field: string): number {
  if (typeof raw !== 'number' || !Number.isFinite(raw) || !Number.isInteger(raw)) {
    throw new MalformedSubmission(`${field} must be an integer`);
  }
  return raw;
}

function optionalInt(raw: unknown, field: string): number | null {
  if (raw === undefined || raw === null) return null;
  return requireInt(raw, field);
}

/**
 * Decodes the `ScoreEventCodec` wire form.
 *
 * STRICTER THAN THE CLIENT'S OWN DECODER, deliberately. `ScoreEventCodec.decode`
 * drops entries it cannot parse, because a queue row that cannot be read must
 * not wedge sync forever on the device. The server has the opposite duty: a
 * dropped event silently changes the score, so an unreadable event is a
 * malformed submission and is refused whole.
 */
export function parseEvents(raw: unknown): ScoreEvent[] {
  if (!Array.isArray(raw)) throw new MalformedSubmission('events must be a list');
  if (raw.length > LIMITS.maxEvents) {
    throw new MalformedSubmission(`events exceeds ${LIMITS.maxEvents} entries`);
  }

  return raw.map((entry, index) => {
    if (typeof entry !== 'object' || entry === null) {
      throw new MalformedSubmission(`events[${index}] must be an object`);
    }
    const record = entry as Record<string, unknown>;
    switch (record['t']) {
      case EVENT_WORD_FOUND:
        return {
          t: EVENT_WORD_FOUND,
          g: requireInt(record['g'], `events[${index}].g`),
        } as const;
      case EVENT_WRONG_SELECTION:
        return { t: EVENT_WRONG_SELECTION } as const;
      case EVENT_HINT_USED:
        return { t: EVENT_HINT_USED } as const;
      default:
        throw new MalformedSubmission(`events[${index}].t is not a known event`);
    }
  });
}

function parseNonce(raw: unknown, fallback: () => string): string {
  if (raw === undefined || raw === null) {
    // Rows queued by a pre-P14 build carry no nonce. Deriving one from the
    // submission's own identity fields is exactly as good a replay guard,
    // because those fields are what make an attempt unique — and refusing
    // those rows instead would strand real progress on upgraded devices.
    return fallback();
  }
  if (typeof raw !== 'string' || raw.length === 0 || raw.length > 200) {
    throw new MalformedSubmission('nonce must be a short non-empty string');
  }
  return raw;
}

function parseLanguage(raw: unknown): LanguageCode {
  if (!isLanguageCode(raw)) throw new MalformedSubmission('unknown language');
  return raw;
}

/** `level:{lang}:{level}:{completedAt}` — stable across outbox retries of one attempt. */
export function deriveLevelNonce(
  language: string,
  level: number,
  completedAt: number,
): string {
  return `level:${language}:${level}:${completedAt}`;
}

/** `daily:{lang}:{date}:{completedAt}`. */
export function deriveDailyNonce(
  language: string,
  date: string,
  completedAt: number,
): string {
  return `daily:${language}:${date}:${completedAt}`;
}

export function parseLevelSubmission(data: unknown): LevelSubmission {
  const record = requireObject(data);
  const language = parseLanguage(record['language']);
  const level = requireInt(record['level'], 'level');
  const completedAt = requireInt(record['completedAt'], 'completedAt');
  if (completedAt <= 0) throw new MalformedSubmission('completedAt must be positive');

  return {
    kind: 'level',
    language,
    level,
    completedAt,
    specVersion: requireInt(record['specVersion'], 'specVersion'),
    events: parseEvents(record['events']),
    nonce: parseNonce(record['nonce'], () =>
      deriveLevelNonce(language, level, completedAt),
    ),
    clientStars: optionalInt(record['stars'], 'stars'),
    clientHintsUsed: optionalInt(record['hintsUsed'], 'hintsUsed'),
  };
}

export function parseDailySubmission(data: unknown): DailySubmission {
  const record = requireObject(data);
  const language = parseLanguage(record['language']);
  const date = record['date'];
  if (!isDayKey(date)) throw new MalformedSubmission('date must be YYYY-MM-DD');
  const completedAt = requireInt(record['completedAt'], 'completedAt');
  if (completedAt <= 0) throw new MalformedSubmission('completedAt must be positive');

  return {
    kind: 'daily',
    language,
    date,
    completedAt,
    specVersion: requireInt(record['specVersion'], 'specVersion'),
    events: parseEvents(record['events']),
    nonce: parseNonce(record['nonce'], () =>
      deriveDailyNonce(language, date, completedAt),
    ),
    clientStars: optionalInt(record['stars'], 'stars'),
    clientHintsUsed: optionalInt(record['hintsUsed'], 'hintsUsed'),
  };
}

// ---------------------------------------------------------------------------
// Evaluation — the score is recomputed, and everything else becomes a flag.
// ---------------------------------------------------------------------------

/**
 * Replays [submission] and collects every Ch08 signal it trips.
 *
 * [shape] is the board the submission claims to have played: the curve's shape
 * for a journey level, `DAILY_SHAPE` for a daily. Pass null when the level id
 * itself is unknown — the shape-dependent checks are then skipped rather than
 * guessed at, and `unknownLevel` is flagged in their place.
 */
export function evaluateSubmission(
  submission: Submission,
  shape: LevelShape | null,
  context: PlayerContext,
): EvaluatedSubmission {
  const flags: FlagCode[] = [];

  const score = computeScore(submission.events);
  const hintsUsed = hintsIn(submission.events);
  const stars = computeStars(hintsUsed);
  const wordsFound = wordsFoundIn(submission.events);
  const maxCombo = maxComboIn(submission.events);

  if (submission.specVersion !== SPEC_VERSION) {
    // Not an error: an old build whose queue is draining after an update is a
    // real, honest situation. It is flagged so a spike is visible, and the
    // score is still the SERVER's — computed under today's rules, which is the
    // only self-consistent choice.
    flags.push(FLAGS.specVersionMismatch);
  }

  if (shape === null) {
    flags.push(FLAGS.unknownLevel);
  } else {
    const bounds = wordCountBounds(shape);
    if (wordsFound < bounds.min || wordsFound > bounds.max) {
      flags.push(FLAGS.wordCountOutOfBounds);
    }
    for (const event of submission.events) {
      if (event.t === EVENT_WORD_FOUND && !isPlausibleGraphemeCount(event.g, shape)) {
        flags.push(FLAGS.graphemeCountImplausible);
        break;
      }
    }
    if (hintsUsed > shape.wordCount) flags.push(FLAGS.hintCountImplausible);
  }

  const clockAhead =
    submission.completedAt > context.serverNowMillis + LIMITS.maxClockSkewMillis;
  const clockRewound =
    submission.completedAt < context.serverNowMillis - LIMITS.maxSubmissionAgeMillis;
  if (clockAhead) flags.push(FLAGS.clockAhead);
  if (clockRewound) flags.push(FLAGS.clockRewound);

  // A timestamp already known to be nonsense is NOT folded into the timing
  // accumulator, and that exclusion is load-bearing rather than tidy: the
  // accumulator compares a claimed span against a required minimum, so one
  // completion stamped in 2099 would stretch the span far enough to make every
  // future submission plausible. The cheapest forgery of a cumulative bound is
  // to inflate the bound, so the values that inflate it are the ones that must
  // not enter it.
  const timing =
    clockAhead || clockRewound
      ? context.timing
      : advanceTiming(context.timing, submission.completedAt, wordsFound);
  if (!timingIsPlausible(timing)) flags.push(FLAGS.timingFloor);

  if (submission.kind === 'level' && submission.level > context.highestLevel + 1) {
    // Ch02's unlock rule is `level <= highestCompleted + 1`, and it is DERIVED
    // on the client rather than stored precisely so there is no flag to forge
    // (`JourneyMap`). This is the server saying the same thing: a submission
    // for a level the player could not have reached did not come from playing.
    flags.push(FLAGS.progressionGap);
  }

  if (submission.clientStars !== null && submission.clientStars !== stars) {
    flags.push(FLAGS.clientStarsMismatch);
  }
  if (submission.clientHintsUsed !== null && submission.clientHintsUsed !== hintsUsed) {
    flags.push(FLAGS.clientHintsMismatch);
  }

  return {
    score,
    stars,
    hintsUsed,
    wordsFound,
    maxCombo,
    flags,
    suspicious: flags.length > 0,
    timing,
  };
}

/** Folds one submission into the cumulative timing state. */
export function advanceTiming(
  timing: TimingContext,
  completedAt: number,
  wordsFound: number,
): TimingContext {
  return {
    submissionCount: timing.submissionCount + 1,
    earliestCompletedAt:
      timing.earliestCompletedAt === null
        ? completedAt
        : Math.min(timing.earliestCompletedAt, completedAt),
    latestCompletedAt:
      timing.latestCompletedAt === null
        ? completedAt
        : Math.max(timing.latestCompletedAt, completedAt),
    // The FIRST submission adds no requirement: nothing bounds how long the
    // level before the account's first completion took.
    minRequiredMillis:
      timing.submissionCount === 0
        ? 0
        : timing.minRequiredMillis + wordsFound * LIMITS.minMillisPerWord,
  };
}

/**
 * Whether the claimed span of play covers the minimum the work would take.
 *
 * WHAT THIS DOES AND DOES NOT CATCH, stated as plainly as `integrity.dart`
 * states its own limits. It catches the naive forgery — a script that
 * fabricates fifty completions with adjacent timestamps — because that span is
 * seconds wide and the work claimed inside it is hours. It does NOT catch a
 * forger who spaces their fake timestamps plausibly; nothing measured from
 * client-supplied time can, because relaxed mode has no clock to measure with.
 *
 * That is an acceptable ceiling because of what it is one signal among. A
 * perfectly-paced forgery still has to pass progression continuity and word
 * count bounds, and it still only earns whatever score its own events justify:
 * the number written is always recomputed here. Beating this check does not
 * buy points, it only avoids a flag.
 */
export function timingIsPlausible(timing: TimingContext): boolean {
  if (timing.earliestCompletedAt === null || timing.latestCompletedAt === null) {
    return true;
  }
  const span = timing.latestCompletedAt - timing.earliestCompletedAt;
  return span >= timing.minRequiredMillis;
}

/**
 * Fixed-window rate limit.
 *
 * Returned as a value rather than thrown so the callable owns the HTTP shape,
 * and so this stays testable as arithmetic.
 */
export interface RateWindow {
  readonly windowStartMillis: number;
  readonly count: number;
}

export function nextRateWindow(
  window: RateWindow | null,
  nowMillis: number,
): { window: RateWindow; allowed: boolean } {
  if (
    window === null ||
    nowMillis - window.windowStartMillis >= LIMITS.rateWindowMillis
  ) {
    return { window: { windowStartMillis: nowMillis, count: 1 }, allowed: true };
  }
  const count = window.count + 1;
  return {
    window: { windowStartMillis: window.windowStartMillis, count },
    allowed: count <= LIMITS.rateMaxSubmissions,
  };
}
