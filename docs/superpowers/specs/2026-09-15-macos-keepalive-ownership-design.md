# macOS KeepAlive Ownership Repair Design

## Goal

Keep Ping running until the user explicitly quits it. If macOS terminates Ping during sleep, memory pressure, disk pressure, or an application crash, launchd must own the active process and restart it. A normal user quit must still stop Ping for the remainder of the login session.

This feature cannot prevent macOS from terminating a process. It guarantees automatic recovery after an abnormal termination.

## Evidence

The installed app on the affected Mac is Ping 0.3.73 build 85. Its ServiceManagement agent is enabled, but `launchctl print gui/501/com.youngminpark.ping.Ping.keepalive` reports:

- `state = not running`
- `runs = 1`
- `last exit code = 0`
- `parent bundle version = 83`

The app process is absent while the user's `ping.autostart.userChoice` is `true`. The data volume has only about 1.7 GiB available and reports 100% capacity, matching the disk-pressure environment in which `com.apple.cache_delete` previously terminated Ping with `0xBADDD15C`. No Ping crash report exists in the last 30 days.

The macOS 26.5 ServiceManagement SDK header also states that a changed LaunchAgent plist or executable must be re-registered or it may not launch, and recommends unregistering before re-registering when the executable changes.

## Root Cause

The current KeepAlive registration does not own the process that users actually run.

1. Registering the agent immediately starts a launchd-managed Ping process.
2. `SingleInstanceGuard` sees the already-running LaunchServices process and makes the new launchd process call `exit(0)`.
3. `KeepAlive = { SuccessfulExit: false }` correctly leaves that successfully exited job stopped.
4. The older LaunchServices process remains visible to the user but is not launchd's child. macOS can terminate it without triggering KeepAlive.

The same gap returns after every Sparkle relaunch and every manual reopen. Updates introduce a second defect: the enabled ServiceManagement registration is treated as healthy without being refreshed, so it can remain associated with an older executable. On the affected Mac the registration is build 83 while the installed app is build 85.

The previous 2026-08-04 design explicitly accepted both gaps as trade-offs. Current user reports show that trade-off does not meet the product requirement.

## Architecture

### Launch origin

Add a small launch-origin abstraction in `Ping/Core/AutoStart.swift`. A process is launchd-managed only when its `XPC_SERVICE_NAME` exactly matches `com.youngminpark.ping.Ping.keepalive`. LaunchServices processes use a different service name and are therefore unmanaged.

The environment lookup is injected into the pure decision layer so tests do not depend on the test runner's process environment.

### Deterministic single-instance ownership

Replace the current "newest process always yields" rule with an ownership rule:

- No other Ping process: continue.
- Current process is unmanaged and another Ping exists: exit successfully, preserving the existing instance.
- Current process is launchd-managed and another Ping exists: the launchd process wins. It requests graceful termination of the unmanaged predecessor and continues launching.

This produces only one steady-state process while ensuring that the survivor is the process launchd can monitor. Graceful termination uses `NSRunningApplication.terminate()` for resolved same-bundle PIDs; it does not send an unconditional shell signal or target unrelated processes.

### Registration reconciliation

Extend `AutoStartPolicy` with whether the current process is launchd-managed.

- Enabled and launchd-managed: no action.
- Enabled and unmanaged with an already registered agent: re-register the agent.
- Enabled and unmanaged with a missing agent: register it.
- Approval required: do nothing and respect System Settings.
- Explicit user choice off: keep the existing unregister behavior.

Re-registration uses the asynchronous `SMAppService.unregister(completionHandler:)` API and waits for completion before calling `register()`, as required by the SDK contract. Registering immediately starts a launchd process; the ownership rule then makes that process replace the unmanaged predecessor.

The launch-time controller becomes asynchronous. `AppDelegate` starts it in a main-actor task after the normal launch setup. Registration errors are logged and leave the currently running app intact; they do not create a crash or forced exit.

### Normal quit

Keep `KeepAlive = { SuccessfulExit: false }` unchanged. A menu-bar Quit follows `NSApplication.terminate`, exits successfully, and is not restarted during the current login session. Because the agent remains registered with `RunAtLoad`, an enabled login-start preference still starts Ping at the next login.

## Components and Files

- `Ping/Core/AutoStart.swift`
  - Detect launch origin.
  - Decide which duplicate instance owns the session.
  - Add the re-registration action.
  - Perform asynchronous unregister-then-register reconciliation.
- `Ping/AppDelegate.swift`
  - Apply the ownership decision before normal setup.
  - Gracefully terminate displaced same-bundle instances when the current process is agent-managed.
  - Await launch-time registration reconciliation in a task.
- `PingTests/AutoStartLaunchGuardTests.swift`
  - Cover managed and unmanaged duplicate decisions.
  - Cover exact `XPC_SERVICE_NAME` detection and AppDelegate wiring.
- `PingTests/AutoStartPolicyTests.swift`
  - Cover re-registration for an enabled unmanaged process and no refresh for a managed process.
- `docs/superpowers/specs/2026-08-04-macos-autostart-keepalive-design.md`
  - Mark the previously accepted unprotected-session trade-off as superseded by this repair.
- `PING_PROJECT_SPECIFICATION.md` and `README.md`
  - Describe automatic recovery accurately without claiming that macOS termination itself can be prevented.

The LaunchAgent plist, deployment target, Swift version, app sandbox, `.pingGlassEffect()` wrapper, and backend are unchanged.

## Failure Handling

- If asynchronous unregister fails, log the error and keep the current app running.
- If unregister succeeds but register fails, log the error and keep the current app running. The next launch retries because the service status is missing.
- If System Settings reports `requiresApproval`, do not fight the user's OS-level choice.
- If an old PID disappears before `NSRunningApplication` resolves it, ignore it; the managed process is already the correct survivor.
- Do not force-terminate a predecessor. If graceful termination is delayed, a brief overlap is preferable to risking unrelated state loss.

## Testing

### Automated

- Write failing pure-policy tests before production changes.
- Verify an unmanaged process with an enabled registered agent selects re-registration.
- Verify a managed process with the same state does nothing.
- Verify an unmanaged duplicate yields and a managed duplicate replaces the predecessor.
- Verify only the exact KeepAlive service name counts as managed.
- Run focused AutoStart tests, the complete Ping test suite, and a Debug build.

### Installed-app smoke test

ServiceManagement behavior requires a signed app in `/Applications` and cannot be proven by unit tests alone. After producing an installable build:

1. Confirm `launchctl print` reports a running job whose PID matches the sole Ping process.
2. Confirm the parent bundle version matches the installed build.
3. Terminate that managed PID abnormally and confirm launchd starts a new PID within the configured 30-second throttle window.
4. Quit through the Ping menu and confirm the job records exit code 0 and does not restart during the current login session.
5. Reopen Ping manually and confirm ownership transfers back to a running launchd job.

No destructive installed-app test runs automatically as part of the source change.

## Out of Scope

- Freeing user disk space or preventing macOS pressure termination.
- Changing the login-start setting into a mandatory preference.
- Adding a separate helper executable or XPC service.
- Changing Windows or iOS lifecycle behavior.
- Fixing unrelated historical CFNetwork crashes unless a new crash report identifies them as the current cause.
