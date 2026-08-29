import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/config/app_config.dart';
import 'package:word_search_master/services/app_check/app_check_gateway.dart';

/// The provider mapping, enumerated.
///
/// Worth a test of its own for the reason `app_check_gateway.dart`'s header
/// gives: a debug provider shipped to production is a SILENT TOTAL OUTAGE the
/// day enforcement is turned on — every real install presenting a debug token
/// the console has never registered. It is exactly the class of mistake that
/// a switch statement makes impossible and an `if (kDebugMode)` makes likely.
void main() {
  test('prod attests for real', () {
    expect(AppCheckPolicy.forFlavor(Flavor.prod), AppCheckPolicy.playIntegrity);
  });

  test('dev and stg use the debug provider', () {
    expect(AppCheckPolicy.forFlavor(Flavor.dev), AppCheckPolicy.debug);
    expect(AppCheckPolicy.forFlavor(Flavor.stg), AppCheckPolicy.debug);
  });

  test('PROD IS THE ONLY FLAVOR THAT EVER GETS PLAY INTEGRITY', () {
    // Stated as a whole-enum sweep rather than three separate asserts so that
    // adding a fourth flavor fails here until someone decides which side it
    // belongs on, instead of silently defaulting to real attestation.
    final withRealAttestation = Flavor.values
        .where(
          (f) => AppCheckPolicy.forFlavor(f) == AppCheckPolicy.playIntegrity,
        )
        .toList();

    expect(withRealAttestation, [Flavor.prod]);
  });

  test('every flavor resolves to something — the switch is exhaustive', () {
    for (final flavor in Flavor.values) {
      expect(AppCheckPolicy.forFlavor(flavor), isNotNull);
    }
  });

  test('NoopAppCheckGateway activates without throwing', () async {
    // The binding whenever Firebase is unavailable; bootstrap step 3 calls it
    // unconditionally, so it has to be safe.
    const gateway = NoopAppCheckGateway();
    await gateway.activate(AppCheckPolicy.playIntegrity);
    await gateway.activate(AppCheckPolicy.debug);
  });
}
