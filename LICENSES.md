# Licences of what the Ortus iOS app ships

The app is MIT OR Apache-2.0. It carries no third-party code: it uses only
Apple's system frameworks (SwiftUI, Foundation, CryptoKit, Security,
LocalAuthentication), which are part of iOS and not shipped in the app.
`ci/check.sh` fails if a third-party package is added, until its licence is
reviewed and listed here.
