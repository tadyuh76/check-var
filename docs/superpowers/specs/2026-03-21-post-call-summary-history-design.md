# Post-Call Summary Notification & History Wiring

**Date:** 2026-03-21
**Status:** Draft
**Scope:** Scam call detection feature — post-call finalization

## Problem

When a call ends, the scam detection session is disposed and all analysis data is lost. The user has no record of what happened during the call, no notification of the result, and no entry in call history. This means:

- Users who activated detection get no post-call feedback
- Users who didn't activate detection have no record the call happened
- The existing `CallResult` model and `HistoryEntry.fromCallResult()` factory are never used
- The existing `NotificationService` is wired for news checks but not scam calls

## Goals

1. After a call where detection was activated, show a notification summarizing the scam verdict
2. After every call (analyzed or not), save a history entry
3. Tapping the notification navigates to the history detail screen for that call

## Non-Goals

- Cloud sync of call history
- Analytics or telemetry
- Caller ID lookup services
- Notification preferences/settings UI
- Notification for unanalyzed calls

## Design

### 1. Data Model Changes

#### CallResult (extend existing)

Add the following fields to `lib/models/call_result.dart`:

| Field | Type | Description |
|-------|------|-------------|
| `callerNumber` | `String?` | Phone number from platform, null if unavailable |
| `callStartTime` | `DateTime` | When `call_state=active` fired |
| `callEndTime` | `DateTime` | When `call_state=inactive` fired |
| `wasAnalyzed` | `bool` | Whether the detection pipeline ran |
| `summary` | `String?` | Human-readable threat description from analysis |
| `advice` | `String?` | Safety advice from analysis |
| `scamProbability` | `double?` | Raw EMA-smoothed probability (0.0-1.0) |

Existing fields remain unchanged: `threatLevel`, `confidence`, `transcript`, `patterns`, `duration`.

`duration` becomes derived from `callEndTime - callStartTime` or stays explicit — whichever is simpler.

#### HistoryEntry (extend existing)

Update `HistoryEntry.fromCallResult()` factory in `lib/models/history_entry.dart` to include new fields in the `data` map.

Add getters:
- `callerNumber` → `String?`
- `wasAnalyzed` → `bool`
- `summary` → `String?`
- `scamProbability` → `double?`

For unanalyzed calls, `CallResult` is created with:
- `wasAnalyzed: false`
- `threatLevel: safe`
- Empty transcript and patterns
- Only timing + caller number populated

### 2. Post-Call Finalization Flow

#### Analyzed Calls — ScamCallSessionManager.stopSession()

Before disposing the controller, the session manager finalizes the result:

1. **Grace period (1.5s):** Wait for any in-flight analysis to complete. If the controller has a pending analysis timer, await its completion or timeout after 1.5 seconds — whichever comes first.
2. **Extract final state** from the controller:
   - `threatLevel`, `confidence`, `scamProbability` (EMA-smoothed values)
   - `transcript` (joined from `TranscriptLine` list)
   - `patterns`, `summary`, `advice` (from latest `ScamAnalysisResult`)
3. **Build `CallResult`** with `wasAnalyzed: true`, call timing from `AppShell`, caller number from platform.
4. **Save to `HistoryService`** via `HistoryService.instance.save(HistoryEntry.fromCallResult(result))`.
5. **Fire notification** via `NotificationService`.
6. **Dispose the controller.**

The session manager needs access to call timing and caller number. These are passed in from `AppShell` — either via `stopSession()` parameters or stored on the session manager when the session starts.

#### Unanalyzed Calls — AppShell._onCallEnded()

When `_sessionManager.hasActiveSession` is false:

1. Build a minimal `CallResult` with `wasAnalyzed: false`, timing data, and caller number.
2. Save to `HistoryService`.
3. No notification.
4. Hide overlay as usual.

#### Call Timing

`AppShell` records `_callStartTime = DateTime.now()` when `_onCallStarted()` fires. Uses `DateTime.now()` as `callEndTime` in `_onCallEnded()`.

### 3. Notification

#### Content

- **Title:** `"CheckVar: {Verdict} ({confidence}%)"`
  - Examples: `"CheckVar: Lừa đảo (87%)"`, `"CheckVar: An toàn (12%)"`, `"CheckVar: Đáng ngờ (63%)"`
  - Verdict uses Vietnamese labels matching existing UI: "An toàn", "Đáng ngờ", "Lừa đảo"
- **Body:** Top detected pattern's Vietnamese display name
  - Example: `"Mạo danh ngân hàng"`
  - Fallback to `summary` text if no specific pattern detected
- **Channel:** `checkvar_results` (existing)
- **Behavior:** Dismissible, not ongoing

#### Tap Navigation

Tapping the notification opens `HistoryDetailScreen` for the saved entry:

1. Notification payload contains the `HistoryEntry.id` (millisecondsSinceEpoch as string).
2. `NotificationService.init()` registers an `onDidReceiveNotificationResponse` handler.
3. On tap, parse the payload ID, retrieve the entry from `HistoryService`, push `HistoryDetailScreen`.
4. Requires a `GlobalKey<NavigatorState>` or equivalent navigation mechanism accessible from `NotificationService`.

#### When It Fires

- Only for analyzed calls (`wasAnalyzed: true`)
- After history save completes
- Fires regardless of threat level (user sees "An toàn" for safe calls too — confirms the call was analyzed)

### 4. History Display Updates

#### History List Screen (history_screen.dart)

Analyzed call cards — no changes needed, existing display works.

Unanalyzed call cards — new neutral/grey style:
- Label: "Không phân tích" (Not analyzed)
- Caller number if available, otherwise "Số không xác định"
- Timestamp and duration
- No threat level color coding (grey/neutral tint)

#### History Detail Screen (history_detail_screen.dart)

For analyzed calls — extend existing view:
- Add caller number display (if available)
- Add `scamProbability` percentage
- Add summary and advice text sections

For unanalyzed calls — simplified view:
- "Không phân tích" header with neutral icon
- Caller number, timestamp, duration
- Transcript/patterns/confidence sections hidden (not shown empty)

### 5. Platform Channel — Caller Number

#### Event Payload Change

Extend the native `call_state` event to include phone number:

```json
{ "type": "call_state", "isActive": true, "phoneNumber": "+84..." }
```

`phoneNumber` is nullable — omitted or null when the number is private/blocked/unavailable.

#### Android Side

The native phone state listener already has access to the incoming number. Forward it through the existing platform channel event.

#### Permission

`READ_PHONE_STATE` should already be declared for call state detection. No additional permissions expected for incoming call numbers. If the number is unavailable, the field is simply omitted.

## Files to Modify

| File | Change |
|------|--------|
| `lib/models/call_result.dart` | Add new fields |
| `lib/models/history_entry.dart` | Extend factory + add getters |
| `lib/features/scam_call/scam_call_session_manager.dart` | Add finalization logic in stopSession() |
| `lib/app_shell.dart` | Record call timing, pass to session manager, handle unanalyzed saves |
| `lib/services/notification_service.dart` | Add scam call notification method + tap handler |
| `lib/screens/history_screen.dart` | Add unanalyzed call card style |
| `lib/screens/history_detail_screen.dart` | Add caller number, scamProbability, summary/advice, unanalyzed view |
| `android/.../MainActivity.kt` (or equivalent) | Forward phoneNumber in call_state event |

## Testing

- Unit test: `ScamCallSessionManager.stopSession()` extracts correct state and saves to history
- Unit test: Unanalyzed call creates correct minimal `CallResult`
- Unit test: Notification content formatting (verdict, confidence, pattern)
- Widget test: History list renders unanalyzed cards correctly
- Widget test: History detail shows/hides sections based on `wasAnalyzed`
- Integration test: Full call lifecycle — start → analyze → end → verify history entry + notification
