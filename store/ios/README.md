# Ortus Workspace on the App Store

What the App Store listing needs, kept with the app: the texts in six
languages (`listing/<locale>/`), the App Privacy answers (`PRIVACY.md`),
the sign-in codes for App Review (`review-codes.mjs`) and the screenshots
(workflow `screenshots`).

## Before each submission

1. **Build**: Actions → release → Run workflow with *upload* (from `main`,
   after CI is green). The build appears in App Store Connect → TestFlight.
2. **Screenshots** (when the screens changed): Actions → screenshots → Run
   workflow. The artifact has the 6.9" iPhone screenshots, in English.
3. **Review codes**: with the sample organisation's owner sign-in
   (`~/git/ORTUS-SAMPLE-signin.local.txt`):

   ```sh
   ORTUS_REVIEW_SERVER=https://sample.ortus.cc ORTUS_REVIEW_EMAIL=olena@sample.ortus.cc \
   ORTUS_REVIEW_PASSWORD='…' ORTUS_REVIEW_TOTP_SECRET='…' node store/ios/review-codes.mjs
   ```

   Codes work once each, for 7 days.

## Once, in App Store Connect (app "Ortus Workspace")

- **App Information**: category *Business* (secondary *Productivity*);
  content rights: no third-party content; age rating questionnaire: all
  "None", unrestricted web access "No" (the app shows only the
  organisation's own content) → 4+.
- **Pricing and Availability**: free; all countries except France until the
  ANSSI encryption declaration (as for HiTop's Mac App Store release).
- **App Privacy**: answers in `PRIVACY.md`; privacy policy
  `https://ortus.cc/privacy`.
- **Version → each language** (English (U.S.), Polish, Ukrainian, German,
  French, Arabic): paste name, subtitle, promotional text, description,
  keywords and "What's New" from `listing/<locale>/`; support URL
  `https://ortus.cc/support`, marketing URL `https://ortus.cc`.
- **App Review Information**: sign-in required: yes. Put in **Notes**
  (username/password fields: leave empty, or "see notes"):

  > Ortus Workspace signs in to an organisation's own Ortus server. Please
  > use our sample organisation:
  > 1. Open the app. In "Address or your work email" type **sample.ortus.cc**.
  > 2. In "Code from your welcome letter" type one of the codes below, then
  >    tap Continue.
  > 3. Tap "Make this phone my key" and confirm with Face ID (or the
  >    device passcode): the phone becomes this account's key. Mail, Chat, Calendar, Files and More
  >    then show the sample organisation's week.
  >
  > Codes (each works once): <from review-codes.mjs>
  >
  > The camera is used only to scan sign-in codes and in calls (Chat → a
  > channel → camera button); the microphone only in calls.

  Contact: name and phone of the person App Review may call;
  email `support@ortus.cc`.
- **Export compliance**: the build declares `ITSAppUsesNonExemptEncryption
  = NO` (only the system's HTTPS and the Secure Enclave).
