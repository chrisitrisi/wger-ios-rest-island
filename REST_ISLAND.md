# wger with native iOS rest timers

This fork integrates ActivityKit into wger's existing gym mode. A planned rest (for example 60 seconds) starts a Live Activity automatically. Skipping the rest, advancing to a set, leaving gym mode or completing the workout ends it. Extending the rest updates the same activity. The system renders the countdown and progress ring while wger is in the background or the screen is locked. At zero, the system timer remains at zero until the activity is ended by the next app update or dismissed.

Build: GitHub Actions workflow "Build wger with Rest Island", branch dynamic-island. Download the wger-RestIsland-IPA artifact, unzip it, import the IPA in SideStore and keep its extension (register an App ID for each extension). Requires iOS 16.2+ for Live Activities; older supported wger devices keep their normal in-app timer.

This is wger itself with a distinct bundle ID for side-by-side testing. Log in to your existing server/account. Local-only data of another app installation is not automatically copied. This fork currently follows upstream master, including upstream server requirements.

The sideload build removes Apple's HealthKit and remote push entitlements because free Apple signing does not provision those capabilities. Apple Health import is unavailable in this build. Existing local rest notifications remain available.

No external server or push service is needed for the Live Activity. Existing wger license and attribution apply.
