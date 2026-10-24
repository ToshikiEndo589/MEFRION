# Registration guidance and floating tabs — 2026-10-24

The registration button previously combined email, 12-character password, matching confirmation, age and data-handling checks into a silent disabled state. Password contents cannot be inferred from the supplied redacted screenshots. The form now accepts a submit attempt and names the first unmet condition; it only disables submission during an active request. Persistent input labels explain the existing minimum length and confirmation. The server Auth request and minimum password policy are preserved.

Removed the three requested explanatory sections (利用条件 / 写真の公開 / Twins) from PrivacyInformationView. Public privacy/terms/support links and model license notices remain accessible.

The five existing tabs now sit in a translucent material capsule with an inset, outline and subtle shadow. Native tab bars are hidden in each navigation stack to avoid duplicate bars. Keyboard visibility and existing routes/reselect behavior are retained.

## Verification

- Four selected XCTest cases passed in `.local/signup-confirmed-flow-20261024.xcresult`: two signup-validation unit tests, short-password feedback/privacy UI, and valid signup-to-code-entry/floating-tab UI.
- The valid UI flow entered 12 characters in each password field and reached the code-entry screen. The native tab bar was absent; the five custom tabs remained accessible.
- Early automation failures were caused by typing through the iOS strong-password suggestion panel. Tests now dismiss that panel before manual entry. Experimental UIKit input bridges were removed; shipping inputs remain SwiftUI SecureField/TextField with standard password AutoFill semantics.
- Email delivery is simulated only under DEBUG plus both isolated UI-fixture arguments. No real account or email was created by these UI tests. This verifies form behavior, not a fresh end-to-end mail delivery.
- Visual inspection: signup feedback, code entry and simplified privacy screenshots exported under `.local/signup-confirmed-flow-screens-20261024/`.
- Device build succeeded: `.local/signup-ascii-device-20261024.log`.
- Connected iPhone installation and normal launch succeeded: `.local/signup-final-install-20261024.json`, `.local/signup-final-launch-20261024.json`.
- `git diff --check` and repository contract checks passed. No database/schema/email-provider changes were required.
