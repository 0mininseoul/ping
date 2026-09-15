# Mandatory Auto Face Reply Design

## Goal

Make automatic face replies mandatory for every macOS Ping user. The setting must no longer be visible or configurable, including for users who previously stored an explicit opt-out.

## Behavior

- Every fresh, normal incoming ping is eligible for a three-second automatic face reply.
- A previously stored `ping.autoReply.faceOnPing = false` value has no effect after the update.
- The existing safety and loop-prevention rules remain unchanged. Ping still skips an automatic reply when the incoming message is itself an automatic reply, the message was already handled, its timestamp is missing, it is stale or predates this app launch, camera permission is unavailable, or the camera is busy.
- Recording continues to show the non-activating indicator, and replies continue to target only the original sender.

## Code Changes

Remove the preference rather than hard-coding it to `true`:

- Delete `PingPreferenceKeys.autoFaceReplyOnPing` and `PingAutoFaceReplyPreference` from `Ping/Core/UserPreferences.swift`.
- Delete `isEnabled` from `AutoFaceReplyPolicy.Context`, the `disabled` skip reason, and the setting guard from `AutoFaceReplyPolicy.decide`.
- Stop passing a preference value from `AutoFaceReplyCoordinator`.
- Remove the `@AppStorage` property and the complete automatic-reply row from General Settings, including the divider that only separated that row from its neighbor.

This leaves one source of truth: automatic face reply eligibility is decided solely by `AutoFaceReplyPolicy` and its safety conditions.

## Tests

- Update policy tests so no context accepts an enablement flag and no test expects an opt-out.
- Replace the Settings contract with assertions that the preference key, label, and toggle binding are absent.
- Update the coordinator contract so it verifies that the policy receives the message and safety state without a preference dependency.
- Run the focused automatic-reply tests, then the full macOS test suite and Debug build.

## Documentation

Update `PING_PROJECT_SPECIFICATION.md` so automatic face reply is described as mandatory on macOS, the opt-out skip reason is removed, and the privacy section no longer claims that recipients can disable it. The recording indicator and all existing safety rules remain documented.

## Out of Scope

- Changing automatic replies on Windows or iOS.
- Changing the three-second duration, freshness window, batching, layout, notification behavior, or backend message contract.
- Requesting camera permission automatically when it is unavailable.
