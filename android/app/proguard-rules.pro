# AppLovin MAX (applovin_max) bundles the IAB Open Measurement SDK, whose
# attestation path optionally references Amazon's Privacy Pass library
# (com.amazon.privacypass.*) for Amazon-Appstore builds. This app is never
# built for the Amazon Appstore, so that class is never on the classpath —
# R8 flags the reference as a "missing class" and fails the release build
# (:app:minifyStgReleaseWithR8 / minifyProdReleaseWithR8 / ...) unless told
# this is expected and safe to ignore. See CLAUDE.md's "applovin_max"
# build-fix notes for the sibling compileSdk issue this same dependency
# required.
-dontwarn com.amazon.privacypass.**
