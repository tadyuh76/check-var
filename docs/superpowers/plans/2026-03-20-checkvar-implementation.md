# CheckVar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Flutter Android app that detects phone shakes, captures screenshots via Accessibility Service, OCRs the text, searches the web for verification, and uses an LLM to classify news as real/fake/uncertain.

**Architecture:** Native Android foreground service detects shakes → Accessibility Service captures screenshot + ML Kit OCR → EventChannel sends text to Flutter → Dart cleans text, extracts search queries, calls JigsawStack web search + Groq LLM → displays verdict. Singleton ChangeNotifier controller orchestrates the flow. Hive for local history.

**Tech Stack:** Flutter/Dart, Kotlin (Android native), Google ML Kit, JigsawStack API, Groq API (Llama 3.3 70B), Hive, ChangeNotifier

---

## File Structure

### Dart (lib/)
| File | Responsibility |
|------|---------------|
| `lib/main.dart` | App entry, MaterialApp, Hive init, providers |
| `lib/app_shell.dart` | Main scaffold, shake event handler, glow overlay |
| `lib/models/check_result.dart` | Verdict enum, SearchSource, CheckResult |
| `lib/models/history_entry.dart` | HistoryEntry, HistoryType, Hive TypeAdapter |
| `lib/api/api_keys.dart` | JigsawStack + Groq API keys |
| `lib/api/jigsawstack_api.dart` | cleanOcrText, extractSearchQueries, webSearch, classifyNews |
| `lib/services/platform_channel.dart` | MethodChannel + EventChannel bridge |
| `lib/services/shake_service.dart` | Listens to EventChannel, exposes shake stream |
| `lib/services/history_service.dart` | Hive CRUD for history |
| `lib/services/notification_service.dart` | Local notification for results |
| `lib/controllers/news_check_controller.dart` | Singleton ChangeNotifier, orchestrates flow |
| `lib/screens/home_screen.dart` | Home with "Kiểm tra tin giả" card + permission checks |
| `lib/screens/news_check_screen.dart` | Loading states, verdict card, sources list |
| `lib/screens/history_screen.dart` | List of past checks |

### Android Native (android/app/src/main/kotlin/com/example/check_var/)
| File | Responsibility |
|------|---------------|
| `MainActivity.kt` | pendingScreenText, MethodChannel/EventChannel setup |
| `ShakeDetectorService.kt` | Foreground service, accelerometer, double-shake detection |
| `ServiceBridge.kt` | Connects shake → captureAndOcr → pendingScreenText |
| `CheckVarAccessibilityService.kt` | takeScreenshot + ML Kit OCR |

### Config
| File | Changes |
|------|---------|
| `pubspec.yaml` | Add hive, hive_flutter, http, url_launcher, flutter_local_notifications, path_provider |
| `android/app/src/main/AndroidManifest.xml` | Permissions + service declarations |
| `android/app/build.gradle.kts` | ML Kit dependency, minSdk 30 |

---

## Task 1: Foundation — Models, API Keys, pubspec.yaml

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/models/check_result.dart`
- Create: `lib/models/history_entry.dart`
- Create: `lib/api/api_keys.dart`

- [ ] **Step 1: Update pubspec.yaml with dependencies**

Add to dependencies:
```yaml
dependencies:
  flutter:
    sdk: flutter
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  http: ^1.2.1
  url_launcher: ^6.2.5
  flutter_local_notifications: ^17.2.1
  path_provider: ^2.1.3
  provider: ^6.1.2
```

- [ ] **Step 2: Create check_result.dart**

```dart
enum Verdict { real, fake, uncertain }

class SearchSource {
  final String title;
  final String url;
  final String snippet;
  const SearchSource({required this.title, required this.url, required this.snippet});
  Map<String, dynamic> toJson() => {'title': title, 'url': url, 'snippet': snippet};
  factory SearchSource.fromJson(Map<String, dynamic> json) => SearchSource(
    title: json['title'] ?? '', url: json['url'] ?? '', snippet: json['snippet'] ?? '',
  );
}

class CheckResult {
  final Verdict verdict;
  final double confidence;
  final String extractedText;
  final String summary;
  final List<SearchSource> sources;
  const CheckResult({required this.verdict, required this.confidence, required this.extractedText, required this.summary, required this.sources});
}
```

- [ ] **Step 3: Create history_entry.dart**

HistoryEntry with id, type, timestamp, data map. Hive TypeAdapter for serialization.

- [ ] **Step 4: Create api_keys.dart**

Placeholder keys for JigsawStack and Groq.

- [ ] **Step 5: Run `flutter pub get`**

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: add foundation - models, api keys, dependencies"
```

---

## Task 2: API Layer — jigsawstack_api.dart

**Files:**
- Create: `lib/api/jigsawstack_api.dart`

Depends on: Task 1 (models)

- [ ] **Step 1: Implement cleanOcrText()**

Filter junk lines (timestamps, status bar, app names, UI elements, ads). Merge short consecutive lines into paragraphs. Min 20 chars check.

- [ ] **Step 2: Implement extractSearchQueries()**

Extract 1-2 queries: longest line (body) + first long line (headline), max 100 chars each.

- [ ] **Step 3: Implement webSearch()**

POST to JigsawStack `/v1/web/search`, return top 5 SearchSource per query, deduplicate by URL.

- [ ] **Step 4: Implement classifyNews()**

Call Groq API with Llama 3.3 70B. Prompt: fact-checker, verdict based on sources only. Parse JSON response.

- [ ] **Step 5: Implement _extractJson() helper**

Strip markdown code blocks, find balanced braces, jsonDecode.

- [ ] **Step 6: Commit**

```bash
git add lib/api/jigsawstack_api.dart && git commit -m "feat: add API layer - OCR cleaning, web search, LLM classification"
```

---

## Task 3: Services — Platform Channel, Shake, History, Notifications

**Files:**
- Create: `lib/services/platform_channel.dart`
- Create: `lib/services/shake_service.dart`
- Create: `lib/services/history_service.dart`
- Create: `lib/services/notification_service.dart`

Depends on: Task 1 (models)

- [ ] **Step 1: Implement platform_channel.dart**

MethodChannel `com.checkvar/methods` for startShakeService, stopShakeService, setMode, getPendingText.
EventChannel `com.checkvar/events` for shake events.

- [ ] **Step 2: Implement shake_service.dart**

Listen to EventChannel, expose Stream of shake events, filter by mode.

- [ ] **Step 3: Implement history_service.dart**

Hive box 'history'. Save, getAll, delete, clear operations on HistoryEntry.

- [ ] **Step 4: Implement notification_service.dart**

Flutter local notifications init + showResult method.

- [ ] **Step 5: Commit**

```bash
git add lib/services/ && git commit -m "feat: add services - platform channel, shake, history, notifications"
```

---

## Task 4: Controller — NewsCheckController

**Files:**
- Create: `lib/controllers/news_check_controller.dart`

Depends on: Task 2 (API), Task 3 (services)

- [ ] **Step 1: Implement NewsCheckController**

Singleton ChangeNotifier. Status state machine: idle → extracting → searching → classifying → done/error.
`runCheckWithText(screenText)`: clean → extract queries → web search (parallel) → classify → save history → notify.

- [ ] **Step 2: Commit**

```bash
git add lib/controllers/ && git commit -m "feat: add NewsCheckController - orchestrates full check flow"
```

---

## Task 5: UI — Screens + App Shell

**Files:**
- Create: `lib/screens/home_screen.dart`
- Create: `lib/screens/news_check_screen.dart`
- Create: `lib/screens/history_screen.dart`
- Create: `lib/app_shell.dart`
- Modify: `lib/main.dart`

Depends on: Task 4 (controller)

- [ ] **Step 1: Implement home_screen.dart**

Card "Kiểm tra tin giả" — checks Accessibility + Overlay permissions, starts shake service, shows snackbar.

- [ ] **Step 2: Implement news_check_screen.dart**

Loading states per NewsCheckStatus. Verdict card (green/red/orange). Source list with tap to open URL. "Kiểm tra lại" button.

- [ ] **Step 3: Implement history_screen.dart**

ListView of past HistoryEntry items. Tap to view details.

- [ ] **Step 4: Implement app_shell.dart**

Scaffold with bottom nav (Home, History). Shake event listener → haptic + glow overlay → getPendingText → runCheckWithText → push NewsCheckScreen.

- [ ] **Step 5: Update main.dart**

Hive init, Provider setup, runApp with AppShell.

- [ ] **Step 6: Commit**

```bash
git add lib/ && git commit -m "feat: add UI - home, news check, history screens + app shell"
```

---

## Task 6: Android Native — Kotlin

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/build.gradle.kts`
- Modify: `android/app/src/main/kotlin/com/example/check_var/MainActivity.kt`
- Create: `android/app/src/main/kotlin/com/example/check_var/ShakeDetectorService.kt`
- Create: `android/app/src/main/kotlin/com/example/check_var/ServiceBridge.kt`
- Create: `android/app/src/main/kotlin/com/example/check_var/CheckVarAccessibilityService.kt`

Independent of Dart tasks (can run in parallel with Tasks 2-5).

- [ ] **Step 1: Update AndroidManifest.xml**

Add permissions: FOREGROUND_SERVICE, FOREGROUND_SERVICE_SPECIAL_USE, SYSTEM_ALERT_WINDOW, INTERNET, HIGH_SAMPLING_RATE_SENSORS.
Declare services: ShakeDetectorService (foreground), CheckVarAccessibilityService (accessibility).
Add accessibility service meta-data XML.

- [ ] **Step 2: Update build.gradle.kts**

Set minSdk to 30. Add ML Kit text recognition dependency.

- [ ] **Step 3: Implement MainActivity.kt**

pendingScreenText variable. MethodChannel handler for startShakeService, stopShakeService, setMode, getPendingText. EventChannel setup with EventSink.

- [ ] **Step 4: Implement ShakeDetectorService.kt**

Foreground service with notification. SensorManager accelerometer listener. Double-shake detection algorithm (acceleration threshold + timing window). Calls ServiceBridge on detection.

- [ ] **Step 5: Implement ServiceBridge.kt**

Singleton. Stores mode. onShakeDetected → if mode=='news' → CheckVarAccessibilityService.captureAndOcr(). Stores result in MainActivity.pendingScreenText. Sends event via EventSink.

- [ ] **Step 6: Implement CheckVarAccessibilityService.kt**

AccessibilityService. captureAndOcr(): takeScreenshot → HardwareBuffer → Bitmap → ML Kit TextRecognition → callback with text. Proper memory management (recycle buffers).

- [ ] **Step 7: Create accessibility_service_config.xml**

```xml
<accessibility-service
    android:accessibilityEventTypes="typeAllMask"
    android:canPerformGestures="false"
    android:canRetrieveWindowContent="false"
    android:description="@string/accessibility_description"
    android:notificationTimeout="100"
    android:settingsActivity="com.example.check_var.MainActivity" />
```

- [ ] **Step 8: Commit**

```bash
git add android/ && git commit -m "feat: add Android native - shake detection, accessibility screenshot, ML Kit OCR"
```

---

## Execution Order

```
Task 1 (Foundation) ──→ Task 2 (API) ──→ Task 4 (Controller) ──→ Task 5 (UI)
                    ──→ Task 3 (Services) ─↗
Task 6 (Android Native) — parallel with Tasks 2-5
```

Tasks 2+3 can run in parallel after Task 1.
Task 6 can run in parallel with everything after Task 1.
