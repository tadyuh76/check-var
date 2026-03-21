# Post-Call Summary Notification & History Wiring — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After every call, save a history entry (analyzed or not); after analyzed calls, show a summary notification that taps through to the history detail screen.

**Architecture:** Extend existing `CallResult` and `HistoryEntry` models with new fields. `ScamCallSessionManager.stopSession()` becomes the finalization point — it extracts final state from the controller, saves to `HistoryService`, and fires a notification via `NotificationService`. `AppShell._onCallEnded()` handles unanalyzed calls. Native side forwards caller info from `readDialerCallerInfo()` in the `call_state` event. A `GlobalKey<NavigatorState>` enables notification tap → `HistoryDetailScreen` navigation.

**Tech Stack:** Flutter/Dart, Hive, flutter_local_notifications, Kotlin (Android native)

**Spec:** `docs/superpowers/specs/2026-03-21-post-call-summary-history-design.md`

---

### Task 1: Extend CallResult Model

**Files:**
- Modify: `lib/models/call_result.dart:1-38`
- Test: `test/models/call_result_test.dart` (create)

- [ ] **Step 1: Write failing test for extended CallResult**

Create `test/models/call_result_test.dart`:

```dart
import 'package:check_var/models/call_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CallResult stores new fields and serializes round-trip', () {
    final start = DateTime(2026, 3, 21, 10, 0);
    final end = DateTime(2026, 3, 21, 10, 5);

    final result = CallResult(
      threatLevel: ThreatLevel.scam,
      confidence: 0.87,
      transcript: 'Xin chào, đây là ngân hàng',
      patterns: ['bankFraudAlert'],
      duration: end.difference(start),
      callerNumber: '+84123456789',
      callStartTime: start,
      callEndTime: end,
      wasAnalyzed: true,
      summary: 'Mạo danh ngân hàng',
      advice: 'Cúp máy ngay',
      scamProbability: 0.92,
    );

    expect(result.callerNumber, '+84123456789');
    expect(result.wasAnalyzed, true);
    expect(result.summary, 'Mạo danh ngân hàng');
    expect(result.advice, 'Cúp máy ngay');
    expect(result.scamProbability, 0.92);
    expect(result.callStartTime, start);
    expect(result.callEndTime, end);

    final json = result.toJson();
    expect(json['callerNumber'], '+84123456789');
    expect(json['wasAnalyzed'], true);
    expect(json['summary'], 'Mạo danh ngân hàng');

    final restored = CallResult.fromJson(json);
    expect(restored.callerNumber, '+84123456789');
    expect(restored.wasAnalyzed, true);
    expect(restored.scamProbability, 0.92);
    expect(restored.callStartTime, start);
    expect(restored.callEndTime, end);
  });

  test('CallResult defaults for unanalyzed call', () {
    final start = DateTime(2026, 3, 21, 10, 0);
    final end = DateTime(2026, 3, 21, 10, 2);

    final result = CallResult(
      threatLevel: ThreatLevel.safe,
      confidence: 0.0,
      transcript: '',
      patterns: [],
      duration: end.difference(start),
      callerNumber: null,
      callStartTime: start,
      callEndTime: end,
      wasAnalyzed: false,
    );

    expect(result.wasAnalyzed, false);
    expect(result.callerNumber, isNull);
    expect(result.summary, isNull);
    expect(result.advice, isNull);
    expect(result.scamProbability, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/call_result_test.dart`
Expected: FAIL — `CallResult` constructor doesn't accept the new fields yet.

- [ ] **Step 3: Implement extended CallResult**

Replace `lib/models/call_result.dart` with:

```dart
enum ThreatLevel { safe, suspicious, scam }

class CallResult {
  final ThreatLevel threatLevel;
  final double confidence;
  final String transcript;
  final List<String> patterns;
  final Duration duration;
  final String? callerNumber;
  final DateTime callStartTime;
  final DateTime callEndTime;
  final bool wasAnalyzed;
  final String? summary;
  final String? advice;
  final double? scamProbability;

  const CallResult({
    required this.threatLevel,
    required this.confidence,
    required this.transcript,
    required this.patterns,
    required this.duration,
    required this.callStartTime,
    required this.callEndTime,
    required this.wasAnalyzed,
    this.callerNumber,
    this.summary,
    this.advice,
    this.scamProbability,
  });

  Map<String, dynamic> toJson() => {
        'threatLevel': threatLevel.name,
        'confidence': confidence,
        'transcript': transcript,
        'patterns': patterns,
        'duration': duration.inSeconds,
        'callerNumber': callerNumber,
        'callStartTime': callStartTime.toIso8601String(),
        'callEndTime': callEndTime.toIso8601String(),
        'wasAnalyzed': wasAnalyzed,
        'summary': summary,
        'advice': advice,
        'scamProbability': scamProbability,
      };

  factory CallResult.fromJson(Map<String, dynamic> json) {
    return CallResult(
      threatLevel: ThreatLevel.values.firstWhere(
        (t) => t.name == json['threatLevel'],
        orElse: () => ThreatLevel.safe,
      ),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      transcript: json['transcript'] ?? '',
      patterns: List<String>.from(json['patterns'] ?? []),
      duration: Duration(seconds: json['duration'] ?? 0),
      callerNumber: json['callerNumber'] as String?,
      callStartTime: json['callStartTime'] != null
          ? DateTime.parse(json['callStartTime'] as String)
          : DateTime.now(),
      callEndTime: json['callEndTime'] != null
          ? DateTime.parse(json['callEndTime'] as String)
          : DateTime.now(),
      wasAnalyzed: json['wasAnalyzed'] as bool? ?? true,
      summary: json['summary'] as String?,
      advice: json['advice'] as String?,
      scamProbability: (json['scamProbability'] as num?)?.toDouble(),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/call_result_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/models/call_result.dart test/models/call_result_test.dart
git commit -m "feat: extend CallResult with caller number, timing, analyzed flag, summary fields"
```

---

### Task 2: Extend HistoryEntry + HistoryService.getById()

**Files:**
- Modify: `lib/models/history_entry.dart:36-50` (fromCallResult factory)
- Modify: `lib/models/history_entry.dart:76-91` (call getters section)
- Modify: `lib/services/history_service.dart:23-27` (add getById)
- Test: `test/models/history_entry_test.dart` (create)

- [ ] **Step 1: Write failing test for extended HistoryEntry**

Create `test/models/history_entry_test.dart`:

```dart
import 'package:check_var/models/call_result.dart';
import 'package:check_var/models/history_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromCallResult includes new fields in data map', () {
    final start = DateTime(2026, 3, 21, 10, 0);
    final end = DateTime(2026, 3, 21, 10, 5);

    final result = CallResult(
      threatLevel: ThreatLevel.scam,
      confidence: 0.87,
      transcript: 'Test transcript',
      patterns: ['bankFraudAlert'],
      duration: end.difference(start),
      callerNumber: '+84123456789',
      callStartTime: start,
      callEndTime: end,
      wasAnalyzed: true,
      summary: 'Mạo danh ngân hàng',
      advice: 'Cúp máy ngay',
      scamProbability: 0.92,
    );

    final entry = HistoryEntry.fromCallResult(result);

    expect(entry.type, HistoryType.call);
    expect(entry.callerNumber, '+84123456789');
    expect(entry.wasAnalyzed, true);
    expect(entry.callSummary, 'Mạo danh ngân hàng');
    expect(entry.scamProbability, 0.92);
    expect(entry.callAdvice, 'Cúp máy ngay');
  });

  test('fromCallResult handles unanalyzed call', () {
    final start = DateTime(2026, 3, 21, 10, 0);
    final end = DateTime(2026, 3, 21, 10, 2);

    final result = CallResult(
      threatLevel: ThreatLevel.safe,
      confidence: 0.0,
      transcript: '',
      patterns: [],
      duration: end.difference(start),
      callerNumber: null,
      callStartTime: start,
      callEndTime: end,
      wasAnalyzed: false,
    );

    final entry = HistoryEntry.fromCallResult(result);

    expect(entry.wasAnalyzed, false);
    expect(entry.callerNumber, isNull);
    expect(entry.callSummary, isNull);
  });

  test('HistoryEntry JSON round-trip preserves new call fields', () {
    final entry = HistoryEntry(
      id: 1234567890,
      type: HistoryType.call,
      timestamp: DateTime(2026, 3, 21),
      data: {
        'threatLevel': 'scam',
        'confidence': 0.87,
        'transcript': 'Test',
        'patterns': ['bankFraudAlert'],
        'duration': 300,
        'callerNumber': '+84123456789',
        'wasAnalyzed': true,
        'summary': 'Mạo danh ngân hàng',
        'advice': 'Cúp máy ngay',
        'scamProbability': 0.92,
      },
    );

    final json = entry.toJson();
    final restored = HistoryEntry.fromJson(json);

    expect(restored.callerNumber, '+84123456789');
    expect(restored.wasAnalyzed, true);
    expect(restored.callSummary, 'Mạo danh ngân hàng');
    expect(restored.scamProbability, 0.92);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/history_entry_test.dart`
Expected: FAIL — getters `callerNumber`, `wasAnalyzed`, `callSummary`, `scamProbability`, `callAdvice` don't exist.

- [ ] **Step 3: Update HistoryEntry.fromCallResult() factory**

In `lib/models/history_entry.dart`, replace the `fromCallResult` factory (lines 36-50) with:

```dart
  factory HistoryEntry.fromCallResult(CallResult result) {
    final now = DateTime.now();
    return HistoryEntry(
      id: now.millisecondsSinceEpoch,
      type: HistoryType.call,
      timestamp: now,
      data: {
        'threatLevel': result.threatLevel.name,
        'confidence': result.confidence,
        'transcript': result.transcript,
        'patterns': result.patterns,
        'duration': result.duration.inSeconds,
        'callerNumber': result.callerNumber,
        'wasAnalyzed': result.wasAnalyzed,
        'summary': result.summary,
        'advice': result.advice,
        'scamProbability': result.scamProbability,
      },
    );
  }
```

- [ ] **Step 4: Add new call-specific getters**

In `lib/models/history_entry.dart`, after the existing `callDuration` getter (line 91), add:

```dart
  String? get callerNumber => data['callerNumber'] as String?;

  bool get wasAnalyzed => data['wasAnalyzed'] as bool? ?? true;

  String? get callSummary => data['summary'] as String?;

  String? get callAdvice => data['advice'] as String?;

  double? get scamProbability =>
      (data['scamProbability'] as num?)?.toDouble();
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/models/history_entry_test.dart`
Expected: PASS

- [ ] **Step 6: Add HistoryService.getById()**

In `lib/services/history_service.dart`, after the `getAll()` method (line 27), add:

```dart
  HistoryEntry? getById(int id) {
    return _box?.get(id.toString());
  }
```

- [ ] **Step 7: Commit**

```bash
git add lib/models/history_entry.dart lib/services/history_service.dart test/models/history_entry_test.dart
git commit -m "feat: extend HistoryEntry with caller number, wasAnalyzed, summary, scamProbability; add HistoryService.getById()"
```

---

### Task 3: Add Scam Call Notification to NotificationService

**Files:**
- Modify: `lib/services/notification_service.dart:1-82`
- Test: `test/services/notification_service_test.dart` (create)

- [ ] **Step 1: Write test for notification content formatting**

Create `test/services/notification_service_test.dart`:

```dart
import 'package:check_var/models/call_result.dart';
import 'package:check_var/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScamCallNotification formatting', () {
    test('formats scam verdict notification content', () {
      final now = DateTime.now();
      final result = CallResult(
        threatLevel: ThreatLevel.scam,
        confidence: 0.87,
        transcript: 'Test',
        patterns: ['Mạo danh ngân hàng'],
        duration: const Duration(minutes: 5),
        callerNumber: '+84123456789',
        callStartTime: now.subtract(const Duration(minutes: 5)),
        callEndTime: now,
        wasAnalyzed: true,
        summary: 'Cuộc gọi có dấu hiệu lừa đảo',
        scamProbability: 0.92,
      );

      final title = NotificationService.buildScamCallTitle(result);
      final body = NotificationService.buildScamCallBody(result);

      expect(title, 'CheckVar: Lừa đảo (87%)');
      expect(body, 'Mạo danh ngân hàng');
    });

    test('formats safe verdict notification content', () {
      final now = DateTime.now();
      final result = CallResult(
        threatLevel: ThreatLevel.safe,
        confidence: 0.12,
        transcript: 'Test',
        patterns: [],
        duration: const Duration(minutes: 3),
        callerNumber: null,
        callStartTime: now.subtract(const Duration(minutes: 3)),
        callEndTime: now,
        wasAnalyzed: true,
        summary: 'Cuộc gọi an toàn',
      );

      final title = NotificationService.buildScamCallTitle(result);
      final body = NotificationService.buildScamCallBody(result);

      expect(title, 'CheckVar: An toàn (12%)');
      expect(body, 'Cuộc gọi an toàn');
    });

    test('formats suspicious verdict notification content', () {
      final now = DateTime.now();
      final result = CallResult(
        threatLevel: ThreatLevel.suspicious,
        confidence: 0.63,
        transcript: 'Test',
        patterns: ['Mạo danh cơ quan thuế'],
        duration: const Duration(minutes: 2),
        callerNumber: null,
        callStartTime: now.subtract(const Duration(minutes: 2)),
        callEndTime: now,
        wasAnalyzed: true,
        summary: 'Nghi ngờ lừa đảo',
      );

      final title = NotificationService.buildScamCallTitle(result);
      final body = NotificationService.buildScamCallBody(result);

      expect(title, 'CheckVar: Đáng ngờ (63%)');
      expect(body, 'Mạo danh cơ quan thuế');
    });

    test('falls back to summary when no patterns', () {
      final now = DateTime.now();
      final result = CallResult(
        threatLevel: ThreatLevel.scam,
        confidence: 0.80,
        transcript: 'Test',
        patterns: [],
        duration: const Duration(minutes: 1),
        callerNumber: null,
        callStartTime: now.subtract(const Duration(minutes: 1)),
        callEndTime: now,
        wasAnalyzed: true,
        summary: 'Phát hiện dấu hiệu lừa đảo',
      );

      final body = NotificationService.buildScamCallBody(result);
      expect(body, 'Phát hiện dấu hiệu lừa đảo');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/notification_service_test.dart`
Expected: FAIL — `buildScamCallTitle` and `buildScamCallBody` don't exist.

- [ ] **Step 3: Implement scam call notification methods**

In `lib/services/notification_service.dart`, add import for `call_result.dart` and add the new methods. Replace the entire file:

```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/check_result.dart';
import '../models/call_result.dart';

/// Callback type for handling notification taps.
/// The payload is the notification payload string (e.g., history entry ID).
typedef NotificationTapCallback = void Function(String? payload);

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static NotificationTapCallback? _onNotificationTap;

  static Future<void> init({NotificationTapCallback? onNotificationTap}) async {
    if (_initialized) return;
    _onNotificationTap = onNotificationTap;
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );
    _initialized = true;
  }

  static void _handleNotificationResponse(NotificationResponse response) {
    _onNotificationTap?.call(response.payload);
  }

  static Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    final granted = await android.requestNotificationsPermission();
    return granted ?? false;
  }

  static const _analyzingId = 999;

  static Future<void> showAnalyzing() async {
    try {
      await _plugin.show(
        _analyzingId,
        'CheckVar',
        'Dang phan tich noi dung...',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'checkvar_analyzing',
            'Trang thai phan tich',
            channelDescription: 'Trang thai phan tich',
            importance: Importance.high,
            priority: Priority.high,
            ongoing: true,
            autoCancel: false,
            showProgress: true,
            indeterminate: true,
          ),
        ),
      );
    } catch (e) {
      // Don't crash the analysis flow if notification fails
    }
  }

  static Future<void> cancelAnalyzing() async {
    await _plugin.cancel(_analyzingId);
  }

  static Future<void> showResult(CheckResult result) async {
    await cancelAnalyzing();
    final verdictText = switch (result.verdict) {
      Verdict.real => 'Tin that',
      Verdict.fake => 'Tin gia',
      Verdict.uncertain => 'Chua ro',
    };

    final confidence = (result.confidence * 100).round();

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'CheckVar: $verdictText ($confidence%)',
      result.summary,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'checkvar_results',
          'Ket qua kiem tra',
          channelDescription: 'Thong bao ket qua kiem tra tin tuc',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  // ── Scam call result notification ──────────────────────────────────

  /// Builds the notification title for a scam call result.
  static String buildScamCallTitle(CallResult result) {
    final verdictText = switch (result.threatLevel) {
      ThreatLevel.safe => 'An toàn',
      ThreatLevel.suspicious => 'Đáng ngờ',
      ThreatLevel.scam => 'Lừa đảo',
    };
    final confidence = (result.confidence * 100).round();
    return 'CheckVar: $verdictText ($confidence%)';
  }

  /// Builds the notification body for a scam call result.
  static String buildScamCallBody(CallResult result) {
    if (result.patterns.isNotEmpty) {
      return result.patterns.first;
    }
    return result.summary ?? '';
  }

  /// Shows a notification summarizing a scam call analysis result.
  /// [historyEntryId] is the HistoryEntry.id for tap navigation.
  static Future<void> showScamCallResult(
    CallResult result, {
    required int historyEntryId,
  }) async {
    try {
      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        buildScamCallTitle(result),
        buildScamCallBody(result),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'checkvar_results',
            'Ket qua kiem tra',
            channelDescription: 'Thong bao ket qua cuoc goi',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: historyEntryId.toString(),
      );
    } catch (e) {
      // Don't crash the finalization flow if notification fails
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/notification_service_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/notification_service.dart test/services/notification_service_test.dart
git commit -m "feat: add scam call result notification with tap payload support"
```

---

### Task 4: Add Global NavigatorKey for Notification Tap Navigation

**Files:**
- Modify: `lib/main.dart:35` (add navigatorKey to MaterialApp)
- Modify: `lib/main.dart:17` (pass onNotificationTap to NotificationService.init)
- Modify: `lib/app_shell.dart` (no change needed — navigation happens via navigatorKey)

- [ ] **Step 1: Add navigatorKey and notification tap handler to main.dart**

In `lib/main.dart`, make these changes:

1. Add a top-level `navigatorKey`:

```dart
final navigatorKey = GlobalKey<NavigatorState>();
```

2. Update `main()` to pass the notification tap handler:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await HistoryService.instance.init();
  await NotificationService.init(
    onNotificationTap: _handleNotificationTap,
  );
  runApp(const CheckVarApp());
}

void _handleNotificationTap(String? payload) {
  if (payload == null) return;
  final id = int.tryParse(payload);
  if (id == null) return;
  final entry = HistoryService.instance.getById(id);
  if (entry == null) return;
  navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (_) => HistoryDetailScreen(entry: entry),
    ),
  );
}
```

3. Add `navigatorKey` to `MaterialApp`:

```dart
return MaterialApp(
  navigatorKey: navigatorKey,
  title: 'CheckVar',
  // ... rest unchanged
);
```

4. Add import for `HistoryDetailScreen`:

```dart
import 'screens/history_detail_screen.dart';
```

- [ ] **Step 2: Verify the app builds**

Run: `flutter build apk --debug 2>&1 | tail -5`
Expected: BUILD SUCCESSFUL

- [ ] **Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "feat: add global navigatorKey + notification tap → history detail navigation"
```

---

### Task 5: Forward Caller Info from Native Side

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/check_var/EventPayloadBuilder.kt:12-17`
- Modify: `android/app/src/main/kotlin/com/example/check_var/CallMonitorService.kt:75-104`
- Modify: `android/app/src/main/kotlin/com/example/check_var/ServiceBridge.kt:42-43` (add callerDisplayText cache)

- [ ] **Step 1: Extend EventPayloadBuilder to accept callerDisplayText**

Replace the `buildCallActiveEvent` method in `EventPayloadBuilder.kt`:

```kotlin
object EventPayloadBuilder {

    /**
     * Builds the event map sent to Flutter when a call state change
     * indicates the user can shake to activate scam detection.
     *
     * [callerDisplayText] is the raw text scraped from the dialer by the
     * accessibility service — could be a phone number, a contact name,
     * or null if the dialer wasn't readable.
     */
    fun buildCallActiveEvent(
        isActive: Boolean,
        callerDisplayText: String? = null,
    ): Map<String, Any?> {
        return mapOf(
            "type" to "call_state",
            "isActive" to isActive,
            "callerDisplayText" to callerDisplayText,
        )
    }
}
```

- [ ] **Step 2: Cache callerDisplayText in ServiceBridge**

In `ServiceBridge.kt`, add a field after `lastCallerType` (line 43):

```kotlin
    /** Raw dialer text from the most recent RINGING event (phone number or contact name). */
    var lastCallerDisplayText: String? = null
        private set
```

Update `cacheCallerType` to also accept and store the display text:

```kotlin
    fun cacheCallerInfo(type: CallerIdentityResolver.CallerType, displayText: String?) {
        lastCallerType = type
        lastCallerDisplayText = displayText
        Log.d(TAG, "cacheCallerInfo: type=$type, displayText='${displayText?.take(40)}'")
    }
```

Update `resetCallerType` to also reset display text:

```kotlin
    fun resetCallerType() {
        lastCallerType = CallerIdentityResolver.CallerType.UNDETERMINED
        lastCallerDisplayText = null
        Log.d(TAG, "resetCallerType: reset to UNDETERMINED")
    }
```

- [ ] **Step 3: Update CallMonitorService to forward callerDisplayText**

In `CallMonitorService.kt`, update the RINGING handler (line 82-85) to cache display text:

```kotlin
        if (state == android.telephony.TelephonyManager.CALL_STATE_RINGING) {
            val a11y = CheckVarAccessibilityService.instance
            val dialerText = a11y?.readDialerCallerInfo()
            val callerType = CallerIdentityResolver.resolve(dialerText)
            ServiceBridge.instance.cacheCallerInfo(callerType, dialerText)
            android.util.Log.d("CallMonitor", "RINGING: dialerText='${dialerText?.take(40)}', callerType=$callerType")
        }
```

Update the event building (lines 96-103) to include callerDisplayText:

```kotlin
        if (isActive) {
            val callerType = ServiceBridge.instance.lastCallerType
            if (callerType == CallerIdentityResolver.CallerType.KNOWN_CONTACT) {
                android.util.Log.d("CallMonitor", "OFFHOOK: known contact — suppressing scam detection")
                return
            }

            val event = EventPayloadBuilder.buildCallActiveEvent(
                isActive,
                callerDisplayText = ServiceBridge.instance.lastCallerDisplayText,
            )
            onCallStateChanged?.invoke(event)

            val overlayIntent = Intent(this, OverlayBubbleService::class.java)
            startService(overlayIntent)
        } else {
            val event = EventPayloadBuilder.buildCallActiveEvent(
                isActive,
                callerDisplayText = ServiceBridge.instance.lastCallerDisplayText,
            )
            onCallStateChanged?.invoke(event)
        }
```

- [ ] **Step 4: Update ServiceBridge.startCallMonitor to handle nullable map values**

In `ServiceBridge.kt`, the `startCallMonitor` lambda (line 354-359) forwards the event to Flutter. The event map type changed from `Map<String, Any>` to `Map<String, Any?>` because `callerDisplayText` can be null. Update:

```kotlin
    private fun startCallMonitor() {
        CallMonitorService.onCallStateChanged = { event ->
            val active = event["isActive"] as? Boolean ?: false
            isCallActive = active
            mainHandler.post {
                eventSink?.success(event)
            }
        }
        val intent = Intent(context, CallMonitorService::class.java)
        context.startForegroundService(intent)
    }
```

Also update the `onCallStateChanged` callback type in `CallMonitorService.kt`:

```kotlin
    companion object {
        private const val CHANNEL_ID = "call_monitor_channel"
        private const val NOTIFICATION_ID = 3001

        var onCallStateChanged: ((Map<String, Any?>) -> Unit)? = null
    }
```

- [ ] **Step 5: Verify the Android side builds**

Run: `cd android && ./gradlew assembleDebug 2>&1 | tail -5`
Expected: BUILD SUCCESSFUL

- [ ] **Step 6: Commit**

```bash
git add android/app/src/main/kotlin/com/example/check_var/EventPayloadBuilder.kt \
        android/app/src/main/kotlin/com/example/check_var/CallMonitorService.kt \
        android/app/src/main/kotlin/com/example/check_var/ServiceBridge.kt
git commit -m "feat: forward callerDisplayText from dialer scraping through call_state event to Flutter"
```

---

### Task 6: Add Controller State Extraction Method

**Files:**
- Modify: `lib/features/scam_call/scam_call_controller.dart:100-112` (add extraction method)
- Modify: `lib/models/call_result.dart` (no changes — already done in Task 1)
- Test: `test/features/scam_call/scam_call_controller_test.dart` (extend)

- [ ] **Step 1: Write failing test for extractCallResult**

Add to `test/features/scam_call/scam_call_controller_test.dart`:

```dart
  test('extractCallResult returns current analysis state', () async {
    final gateway = _FakeTranscriptGateway();
    final classifier = _FakeScamTextClassifier();
    final controller = ScamCallController(
      transcriptGateway: gateway,
      classifier: classifier,
      analysisDebounce: const Duration(milliseconds: 10),
    );
    addTearDown(controller.dispose);

    final now = DateTime.now();
    final result = controller.extractCallResult(
      callStartTime: now.subtract(const Duration(minutes: 5)),
      callEndTime: now,
      callerNumber: '+84123456789',
    );

    expect(result.threatLevel, ThreatLevel.safe);
    expect(result.wasAnalyzed, true);
    expect(result.callerNumber, '+84123456789');
    expect(result.callStartTime, now.subtract(const Duration(minutes: 5)));
    expect(result.callEndTime, now);
    expect(result.transcript, isEmpty);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/scam_call/scam_call_controller_test.dart`
Expected: FAIL — `extractCallResult` doesn't exist.

- [ ] **Step 3: Implement extractCallResult on ScamCallController**

In `lib/features/scam_call/scam_call_controller.dart`, after the `sessionStatusLabel` getter (line 121), add:

```dart
  /// The raw EMA-smoothed scam probability. Returns null if no analysis has run.
  double? get emaScamProbability => _emaScamProb < 0 ? null : _emaScamProb;

  /// Extracts the controller's current analysis state as a [CallResult].
  /// Call this before disposing the controller to capture the final state.
  CallResult extractCallResult({
    required DateTime callStartTime,
    required DateTime callEndTime,
    String? callerNumber,
  }) {
    return CallResult(
      threatLevel: _threatLevel,
      confidence: _confidence,
      transcript: _transcript.map((l) => l.text).join(' '),
      patterns: List.unmodifiable(_patterns),
      duration: callEndTime.difference(callStartTime),
      callerNumber: callerNumber,
      callStartTime: callStartTime,
      callEndTime: callEndTime,
      wasAnalyzed: true,
      summary: _summary.isNotEmpty ? _summary : null,
      advice: _advice.isNotEmpty ? _advice : null,
      scamProbability: _emaScamProb < 0 ? null : _emaScamProb,
    );
  }
```

Add import at top of file:

```dart
import '../../models/call_result.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/scam_call/scam_call_controller_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/scam_call/scam_call_controller.dart test/features/scam_call/scam_call_controller_test.dart
git commit -m "feat: add extractCallResult() to ScamCallController for post-call finalization"
```

---

### Task 7: Add Finalization to ScamCallSessionManager.stopSession()

**Files:**
- Modify: `lib/features/scam_call/scam_call_session_manager.dart:84-98`
- Test: `test/features/scam_call/scam_call_session_manager_test.dart` (extend)

- [ ] **Step 1: Write failing test for stopSession finalization**

Add to `test/features/scam_call/scam_call_session_manager_test.dart`:

First add imports at the top:

```dart
import 'package:check_var/models/call_result.dart';
import 'package:check_var/models/history_entry.dart';
```

Then add the test:

```dart
  test('stopSession extracts CallResult and calls onSessionFinalized', () async {
    final liveGateway = _FakeTranscriptGateway();
    CallResult? capturedResult;

    final manager = ScamCallSessionManager(
      liveCallControllerFactory: () => _buildController(liveGateway),
      simulationControllerFactory: (_) => _buildController(
        _FakeTranscriptGateway(),
      ),
      speakText: (_, {preferSpeaker = false}) async {},
      stopSpeaking: () async {},
      onSessionFinalized: (result) async {
        capturedResult = result;
      },
    );

    final startTime = DateTime.now();
    manager.setCallTiming(
      callStartTime: startTime,
      callerNumber: '+84123456789',
    );

    await manager.startLiveCallSession();
    expect(manager.hasActiveSession, isTrue);

    await manager.stopSession();
    expect(manager.hasActiveSession, isFalse);
    expect(capturedResult, isNotNull);
    expect(capturedResult!.wasAnalyzed, true);
    expect(capturedResult!.callerNumber, '+84123456789');
    expect(capturedResult!.callStartTime, startTime);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/scam_call/scam_call_session_manager_test.dart`
Expected: FAIL — `onSessionFinalized` and `setCallTiming` don't exist.

- [ ] **Step 3: Implement finalization in ScamCallSessionManager**

In `lib/features/scam_call/scam_call_session_manager.dart`:

1. Add import:

```dart
import '../../models/call_result.dart';
```

2. Add callback typedef after existing typedefs (line 16):

```dart
typedef SessionFinalizedCallback = Future<void> Function(CallResult result);
```

3. Add fields and constructor parameter. Update the class:

```dart
class ScamCallSessionManager extends ChangeNotifier {
  ScamCallSessionManager({
    LiveCallControllerFactory? liveCallControllerFactory,
    SimulationControllerFactory? simulationControllerFactory,
    SpeakTextCallback? speakText,
    StopSpeakingCallback? stopSpeaking,
    this.onSessionFinalized,
  }) : _liveCallControllerFactory =
           liveCallControllerFactory ?? _buildLiveCallController,
       _simulationControllerFactory =
           simulationControllerFactory ?? _buildSimulationController,
       _speakText = speakText ?? PlatformChannel.speakText,
       _stopSpeaking = stopSpeaking ?? PlatformChannel.stopSpeaking;

  // ... existing fields ...

  final SessionFinalizedCallback? onSessionFinalized;

  // ── Call timing (set by AppShell when call starts) ──────────────────
  DateTime? _callStartTime;
  String? _callerNumber;

  /// Store call timing info from AppShell when a call starts.
  void setCallTiming({required DateTime callStartTime, String? callerNumber}) {
    _callStartTime = callStartTime;
    _callerNumber = callerNumber;
  }
```

4. Replace `stopSession()` method:

```dart
  /// Grace period for in-flight analysis to complete before finalization.
  static const _finalizationGrace = Duration(milliseconds: 1500);

  Future<void> stopSession() async {
    final controller = _controller;
    _controller = null;
    _sessionKind = ScamCallSessionKind.idle;
    notifyListeners();

    if (controller == null) {
      await _stopSpeaking();
      _resetCallTiming();
      return;
    }

    await _stopSpeaking();

    // Grace period: wait for in-flight analysis to finish.
    if (controller.analysisInFlight) {
      await Future.any([
        _waitForAnalysis(controller),
        Future.delayed(_finalizationGrace),
      ]);
    }

    // Extract final state before disposing.
    final callEndTime = DateTime.now();
    final callResult = controller.extractCallResult(
      callStartTime: _callStartTime ?? callEndTime,
      callEndTime: callEndTime,
      callerNumber: _callerNumber,
    );

    await controller.stopListening();
    controller.dispose();

    // Finalize: save to history + notify.
    await onSessionFinalized?.call(callResult);
    _resetCallTiming();
  }

  Future<void> _waitForAnalysis(ScamCallController controller) async {
    while (controller.analysisInFlight) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  void _resetCallTiming() {
    _callStartTime = null;
    _callerNumber = null;
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/scam_call/scam_call_session_manager_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/scam_call/scam_call_session_manager.dart test/features/scam_call/scam_call_session_manager_test.dart
git commit -m "feat: add post-call finalization to ScamCallSessionManager.stopSession()"
```

---

### Task 8: Wire AppShell — Call Timing, Caller Number, History Save

**Files:**
- Modify: `lib/app_shell.dart:23-190`

- [ ] **Step 1: Add call timing state and finalization wiring to AppShell**

In `lib/app_shell.dart`:

1. Add imports:

```dart
import 'models/call_result.dart';
import 'models/history_entry.dart';
import 'services/history_service.dart';
import 'services/notification_service.dart';
```

2. Add state fields in `_AppShellState` (after `_hasNavigatedToResult` on line 29):

```dart
  DateTime? _callStartTime;
  String? _callerNumber;
```

3. Update `_sessionManager` initialization in `initState()` to include `onSessionFinalized`:

```dart
    _sessionManager = ScamCallSessionManager(
      onSessionFinalized: _onSessionFinalized,
    );
```

4. Add the finalization callback:

```dart
  Future<void> _onSessionFinalized(CallResult result) async {
    final entry = HistoryEntry.fromCallResult(result);
    await HistoryService.instance.save(entry);
    await NotificationService.showScamCallResult(
      result,
      historyEntryId: entry.id,
    );
  }
```

5. Update `_handlePlatformEvent` to extract `callerDisplayText`:

```dart
  void _handlePlatformEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    switch (type) {
      case 'call_state':
        final isActive = event['isActive'] as bool? ?? false;
        final callerDisplayText = event['callerDisplayText'] as String?;
        debugPrint('AppShell: call_state isActive=$isActive, caller=$callerDisplayText');
        if (isActive) {
          _onCallStarted(callerDisplayText: callerDisplayText);
        } else {
          _onCallEnded();
        }
      case 'overlay_activate':
        debugPrint('AppShell: overlay_activate received');
        _handleOverlayActivate();
      default:
        break;
    }
  }
```

6. Update `_onCallStarted` to record timing:

```dart
  Future<void> _onCallStarted({String? callerDisplayText}) async {
    final homeState = context.read<HomeStateProvider>();
    if (!homeState.scamCallEnabled) return;

    _callStartTime = DateTime.now();
    _callerNumber = callerDisplayText;

    debugPrint('AppShell: call started — showing overlay reminder');
    try {
      await core_channel.PlatformChannel.showOverlayBubble();
    } catch (e) {
      debugPrint('AppShell: failed to show overlay bubble: $e');
    }
  }
```

7. Update `_onCallEnded` to pass timing to session manager and save unanalyzed calls:

```dart
  Future<void> _onCallEnded() async {
    try {
      await core_channel.PlatformChannel.stopCaptionCapture();
    } catch (_) {}

    if (_sessionManager.hasActiveSession) {
      // Pass call timing to session manager for finalization.
      _sessionManager.setCallTiming(
        callStartTime: _callStartTime ?? DateTime.now(),
        callerNumber: _callerNumber,
      );
      await _sessionManager.stopSession();
    } else {
      // No session — save unanalyzed call to history.
      await _saveUnanalyzedCall();
      try {
        await core_channel.PlatformChannel.hideOverlayBubble();
      } catch (_) {}
    }

    _callStartTime = null;
    _callerNumber = null;
  }

  Future<void> _saveUnanalyzedCall() async {
    final now = DateTime.now();
    final result = CallResult(
      threatLevel: ThreatLevel.safe,
      confidence: 0.0,
      transcript: '',
      patterns: [],
      duration: now.difference(_callStartTime ?? now),
      callerNumber: _callerNumber,
      callStartTime: _callStartTime ?? now,
      callEndTime: now,
      wasAnalyzed: false,
    );
    final entry = HistoryEntry.fromCallResult(result);
    await HistoryService.instance.save(entry);
  }
```

8. Update `_tryStartScamSession` to pass timing to session manager:

```dart
  Future<void> _tryStartScamSession() async {
    final homeState = context.read<HomeStateProvider>();
    if (!homeState.scamCallEnabled) return;
    if (_sessionManager.hasActiveSession) return;

    debugPrint('AppShell: starting background scam call session');
    _sessionManager.setCallTiming(
      callStartTime: _callStartTime ?? DateTime.now(),
      callerNumber: _callerNumber,
    );
    await _sessionManager.startLiveCallSession();
    debugPrint(
      'AppShell: session started, '
      'isListening=${_sessionManager.controller?.isListening}',
    );
  }
```

- [ ] **Step 2: Verify the app builds**

Run: `flutter build apk --debug 2>&1 | tail -5`
Expected: BUILD SUCCESSFUL

- [ ] **Step 3: Commit**

```bash
git add lib/app_shell.dart
git commit -m "feat: wire AppShell — call timing, caller number, finalization callback, unanalyzed call saving"
```

---

### Task 9: Update History List Screen for Unanalyzed Calls

**Files:**
- Modify: `lib/screens/history_screen.dart:176-243` (_buildCallCard method)

- [ ] **Step 1: Update _buildCallCard to handle unanalyzed calls**

In `lib/screens/history_screen.dart`, replace the `_buildCallCard` method (lines 176-243):

```dart
  Widget _buildCallCard(HistoryEntry entry) {
    final bool analyzed = entry.wasAnalyzed;

    final (color, label) = analyzed
        ? switch (entry.threatLevel) {
            ThreatLevel.safe => (AppTheme.success, 'An toàn'),
            ThreatLevel.suspicious => (AppTheme.warning, 'Đáng ngờ'),
            ThreatLevel.scam => (AppTheme.danger, 'Lừa đảo'),
          }
        : (Colors.grey, 'Không phân tích');

    final time = _formatTime(entry.timestamp);

    final subtitleText = analyzed
        ? (entry.patterns.isNotEmpty
            ? 'Phát hiện: ${entry.patterns.join(', ')}'
            : 'Không phát hiện dấu hiệu bất thường')
        : entry.callerNumber ?? 'Số không xác định';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => HistoryDetailScreen(entry: entry),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    time,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                subtitleText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
```

- [ ] **Step 2: Verify the app builds**

Run: `flutter build apk --debug 2>&1 | tail -5`
Expected: BUILD SUCCESSFUL

- [ ] **Step 3: Commit**

```bash
git add lib/screens/history_screen.dart
git commit -m "feat: update history call cards to show unanalyzed calls with neutral styling"
```

---

### Task 10: Update History Detail Screen for New Fields + Unanalyzed View

**Files:**
- Modify: `lib/screens/history_detail_screen.dart:177-281` (_buildCallDetail method)

- [ ] **Step 1: Replace _buildCallDetail with updated version**

In `lib/screens/history_detail_screen.dart`, replace the `_buildCallDetail` method (lines 177-281):

```dart
  Widget _buildCallDetail(BuildContext context) {
    if (!entry.wasAnalyzed) {
      return _buildUnanalyzedCallDetail(context);
    }

    final (color, icon, label) = switch (entry.threatLevel) {
      ThreatLevel.safe =>
        (AppTheme.success, Icons.verified_user_rounded, 'AN TOÀN'),
      ThreatLevel.suspicious =>
        (AppTheme.warning, Icons.shield_rounded, 'ĐÁNG NGỜ'),
      ThreatLevel.scam =>
        (AppTheme.danger, Icons.gpp_bad_rounded, 'LỪA ĐẢO'),
    };
    final confidence = (entry.confidence * 100).round();
    final duration = entry.callDuration;
    final durationStr =
        '${duration.inMinutes.toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Verdict card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: [
              Icon(icon, size: 48, color: color),
              const SizedBox(height: 12),
              Text(
                label,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Độ tin cậy: $confidence%',
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: color),
              ),
              if (entry.scamProbability != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Xác suất lừa đảo: ${(entry.scamProbability! * 100).round()}%',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: color.withValues(alpha: 0.8),
                      ),
                ),
              ],
              if (entry.patterns.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: entry.patterns
                      .map((p) => Chip(
                            label: Text(p,
                                style:
                                    TextStyle(fontSize: 12, color: color)),
                            backgroundColor: color.withValues(alpha: 0.1),
                            side: BorderSide.none,
                            visualDensity: VisualDensity.compact,
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),

        // Caller number
        if (entry.callerNumber != null) ...[
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Số gọi: ${entry.callerNumber}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],

        const SizedBox(height: 16),
        Center(
          child: Text(
            'Thời gian: $durationStr',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),

        // Summary & advice
        if (entry.callSummary != null && entry.callSummary!.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Tóm tắt',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              entry.callSummary!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
        if (entry.callAdvice != null && entry.callAdvice!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline, size: 20,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entry.callAdvice!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ],

        // Transcript
        if (entry.transcript.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Nội dung cuộc gọi',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              entry.transcript,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildUnanalyzedCallDetail(BuildContext context) {
    final duration = entry.callDuration;
    final durationStr =
        '${duration.inMinutes.toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Neutral verdict card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: [
              Icon(Icons.phone_missed_rounded, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                'KHÔNG PHÂN TÍCH',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Chưa kích hoạt phát hiện lừa đảo',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
              ),
            ],
          ),
        ),

        // Caller number
        if (entry.callerNumber != null) ...[
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Số gọi: ${entry.callerNumber}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],

        const SizedBox(height: 16),
        Center(
          child: Text(
            'Thời gian: $durationStr',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }
```

- [ ] **Step 2: Verify the app builds**

Run: `flutter build apk --debug 2>&1 | tail -5`
Expected: BUILD SUCCESSFUL

- [ ] **Step 3: Commit**

```bash
git add lib/screens/history_detail_screen.dart
git commit -m "feat: update history detail screen — caller number, scamProbability, summary/advice, unanalyzed view"
```

---

### Task 11: Run Full Test Suite and Fix Any Issues

**Files:** All modified files

- [ ] **Step 1: Run all existing tests**

Run: `flutter test`
Expected: All tests PASS. If any fail due to the new required `CallResult` fields, update those call sites.

- [ ] **Step 2: Fix any broken call sites**

If any existing code creates `CallResult` without the new required fields (`callStartTime`, `callEndTime`, `wasAnalyzed`), update those call sites. The most likely places are:
- Existing test fakes in `scam_call_controller_test.dart` — not affected since they don't create `CallResult`
- `scam_call_screen_test.dart` — check if it creates `CallResult` objects

- [ ] **Step 3: Run full test suite again**

Run: `flutter test`
Expected: All PASS

- [ ] **Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: update existing call sites for new CallResult required fields"
```

---

### Task 12: Final Build Verification

- [ ] **Step 1: Run full Flutter build**

Run: `flutter build apk --debug`
Expected: BUILD SUCCESSFUL

- [ ] **Step 2: Run full test suite**

Run: `flutter test`
Expected: All PASS

- [ ] **Step 3: Verify no analysis warnings**

Run: `flutter analyze`
Expected: No errors (warnings acceptable)
