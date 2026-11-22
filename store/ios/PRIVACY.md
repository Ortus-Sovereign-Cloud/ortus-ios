# App Privacy answers (App Store Connect → App Privacy)

**Data Not Collected.**

Apple counts data as collected when it leaves the device so that the
developer or its partners can access it. Ortus Workspace sends nothing to
its publisher: it has no servers of its own, no analytics, advertising,
tracking or crash-reporting SDKs, and no third-party code at all. Everything
the person works with goes only to the server their organisation runs (its
own Ortus, at the address they sign in to), which the publisher cannot
reach. This is the same answer self-hosted workspace apps give.

| Question | Answer |
|---|---|
| Do you or your third-party partners collect data from this app? | No |
| Tracking | No |
| Privacy policy URL | https://ortus.cc/privacy |
| User privacy choices URL | (none needed) |

On the device: the sign-in session and the phone's passkey (Secure Enclave,
Face ID), never sent anywhere but the organisation's server; the camera only
for scanning sign-in codes and in calls; the microphone only in calls.

If a future version adds anything that sends data to the publisher (crash
reports, for instance), these answers must change before it ships.
