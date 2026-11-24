# Translations waiting for native review

These were translated without a native speaker. They need review by one
before release in the country named. The terms follow Ortus core's web
catalogs (`web/src/locales/es.ts`, `it.ts`, with the section names from its
`app.*` keys) and the Android app's texts, which wait for the same review.

| Language | Files | Status |
|---|---|---|
| Spanish (es) | `Ortus/Resources/es.lproj/`, `store/ios/listing/es-ES/` | Translated without a native speaker; needs review before release in Spain |
| Italian (it) | `Ortus/Resources/it.lproj/`, `store/ios/listing/it/` | Translated without a native speaker; needs review before release in Italy |

The Android app's texts follow these catalogs (`ortus-android/tools/strings.py`),
so a reviewed wording goes in here first and then into Android's.

When a native speaker has reviewed a language, remove its row and the note
at the top of its `Localizable.strings`, `Localizable.stringsdict` and
`InfoPlist.strings`.
