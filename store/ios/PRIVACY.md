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

Notifications (1.2): when an organisation turns them on, its server hands
each push to Apple, through the publisher's push gateway (ortus.cc) unless
it runs its own. The gateway receives the phone's push token, a notification
reference and the installation's address, passes them to Apple at once and
keeps none of it (no storage, no logs of the body): data processed only in
real time to serve the request is not "collected" in Apple's sense. The text
of a notification goes only from the organisation's server to the phone.
Offline reading keeps copies of recent mail, chats and calendar on the
phone itself (deleted on sign-out); they are not sent anywhere.

If a future version adds anything that sends data to the publisher (crash
reports, for instance), these answers must change before it ships.
