import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/data/local/submission_nonce.dart';
import 'package:word_search_master/domain/text/language.dart';

/// The nonce format is HALF OF A CONTRACT: `functions/src/validation.ts`
/// derives the same string for outbox rows queued by a pre-P14 build, so a
/// change here that is not mirrored there turns every such row into a second,
/// separately-counted submission. These assertions are the literal strings, on
/// purpose — a test written in terms of the function it is testing would pass
/// after any rename of the format.
void main() {
  test('a level nonce is level:{lang}:{level}:{completedAt}', () {
    expect(
      SubmissionNonce.forLevel(
        language: Language.urdu,
        level: 47,
        completedAt: 1756600000000,
      ),
      'level:ur:47:1756600000000',
    );
  });

  test('a daily nonce is daily:{lang}:{date}:{completedAt}', () {
    expect(
      SubmissionNonce.forDaily(
        language: Language.hindi,
        date: '2026-08-31',
        completedAt: 1756600000000,
      ),
      'daily:hi:2026-08-31:1756600000000',
    );
  });

  test('the same attempt derives the same nonce every time it is retried', () {
    String forAttempt() => SubmissionNonce.forLevel(
      language: Language.english,
      level: 3,
      completedAt: 111,
    );
    expect(forAttempt(), forAttempt());
  });

  test('a second attempt at the same level derives a different nonce', () {
    expect(
      SubmissionNonce.forLevel(
        language: Language.english,
        level: 3,
        completedAt: 111,
      ),
      isNot(
        SubmissionNonce.forLevel(
          language: Language.english,
          level: 3,
          completedAt: 222,
        ),
      ),
    );
  });

  test('the same level in two languages is two different submissions', () {
    expect(
      SubmissionNonce.forLevel(
        language: Language.urdu,
        level: 47,
        completedAt: 111,
      ),
      isNot(
        SubmissionNonce.forLevel(
          language: Language.hindi,
          level: 47,
          completedAt: 111,
        ),
      ),
    );
  });

  test('a level and a daily can never collide', () {
    expect(
      SubmissionNonce.forLevel(
        language: Language.english,
        level: 1,
        completedAt: 111,
      ).startsWith('level:'),
      isTrue,
    );
    expect(
      SubmissionNonce.forDaily(
        language: Language.english,
        date: '2026-08-31',
        completedAt: 111,
      ).startsWith('daily:'),
      isTrue,
    );
  });
}
