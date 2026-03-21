# Reduce False Positive Scam Classification

**Date:** 2026-03-21
**Branch:** feature/live-caption-scam-transcription
**Status:** Draft

## Problem

The on-device scam classifier is too eager to classify innocent calls as scam/suspicious. Root causes:

1. **suspiciousThreshold too low (0.35):** Only 35% gate confidence triggers warnings
2. **Threat level ratchets up, never down:** One false blip permanently marks a call
3. **No temporal smoothing:** Single-shot classification on 600-char windows is noisy

## Solution

Targeted changes across three files. No retraining required.

### Change 1: Add `scamProbability` to ScamAnalysisResult

**File:** `lib/core/api/gemini_scam_text_api.dart`

Add a `scamProbability` field to `ScamAnalysisResult` — the raw gate probability on a consistent 0-1 scale where higher = more likely scam. This is necessary because the existing `confidence` field has **inverted semantics**: safe results store `1.0 - gateProb` while scam results store `gateProb` directly. The EMA needs a consistent axis.

- `LocalScamClassifier` sets `scamProbability` to `gateProb`
- `GeminiScamTextApi` sets `scamProbability` to its confidence when scam, `1.0 - confidence` when safe
- Existing `confidence` field remains unchanged for backward compatibility

### Change 2: Raise Suspicious Threshold

**File:** `lib/core/api/local_scam_classifier.dart`

- `suspiciousThreshold` default: **0.35 → 0.50**
- Effect: Model must be >=50% confident before flagging anything as non-safe
- Gate threshold (0.55 for full "scam") remains unchanged (loaded from model weights)

### Change 3: Hybrid EMA + Minimum-Analyses Gate

**File:** `lib/features/scam_call/scam_call_controller.dart`

Replace the ratchet-only `_applyAnalysis()` with a smoothed, decay-capable system.

#### New State

| Field | Type | Initial | Purpose |
|-------|------|---------|---------|
| `_emaScamProb` | `double` | `-1.0` (sentinel) | EMA of raw scam probability |
| `_consecutiveNonSafe` | `int` | `0` | Consecutive analyses where classifier returned non-safe |

No `_analysisCount` — the consecutive counter handles the minimum-analyses gate.

#### EMA Update (runs every analysis)

```
alpha = 0.35

if _emaScamProb < 0:
    // First analysis: initialize directly (no history to blend with)
    _emaScamProb = result.scamProbability
else:
    _emaScamProb = alpha * result.scamProbability + (1 - alpha) * _emaScamProb
```

Using `-1.0` as sentinel avoids cold-start bias. The first analysis value is used directly so a strong scam signal can trigger escalation by analysis #2.

#### Consecutive Non-Safe Counter

- Incremented when `result.threatLevel != safe`
- **Decremented by 1** (min 0) when `result.threatLevel == safe`
- A single clean analysis does NOT fully reset the counter, preventing flicker in mixed-signal streams

#### Decision Logic (runs every analysis, after EMA update)

```
suspiciousThreshold = 0.50  (from classifier)
gateThreshold = 0.55        (from model weights)

if _emaScamProb < suspiciousThreshold:
    threatLevel = safe
elif _consecutiveNonSafe < 2:
    threatLevel = safe       // still gathering signal
elif _emaScamProb < gateThreshold:
    threatLevel = suspicious
else:
    threatLevel = scam
```

Both gates must agree before escalation: the EMA must be above threshold AND there must be 2+ consecutive non-safe results.

#### Scam Type / Summary / Advice

When the decision logic outputs a non-safe threat level, the scam type, summary, and advice are taken from the latest analysis result (same as before).

When the decision logic outputs safe:
- `_summary` and `_advice` are cleared
- `_patterns` are preserved (informational history)
- Overlay updates to reflect safe status

#### Session Reset

All EMA state (`_emaScamProb`, `_consecutiveNonSafe`) resets when `startListening()` is called.

## Worked Example

Innocent call with one noisy window:

| # | gateProb | classifier says | _emaScamProb | _consecutiveNonSafe | **output** |
|---|----------|-----------------|-------------|---------------------|------------|
| 1 | 0.10 | safe | 0.10 | 0 | safe |
| 2 | 0.52 | suspicious | 0.25 | 1 | safe (consecutive < 2) |
| 3 | 0.15 | safe | 0.21 | 0 | safe |

Genuine scam call:

| # | gateProb | classifier says | _emaScamProb | _consecutiveNonSafe | **output** |
|---|----------|-----------------|-------------|---------------------|------------|
| 1 | 0.70 | scam | 0.70 | 1 | safe (consecutive < 2) |
| 2 | 0.75 | scam | 0.72 | 2 | scam |
| 3 | 0.80 | scam | 0.75 | 3 | scam |

Mixed signal (scam with one clean window):

| # | gateProb | classifier says | _emaScamProb | _consecutiveNonSafe | **output** |
|---|----------|-----------------|-------------|---------------------|------------|
| 1 | 0.70 | scam | 0.70 | 1 | safe (consecutive < 2) |
| 2 | 0.65 | scam | 0.68 | 2 | scam |
| 3 | 0.30 | safe | 0.55 | 1 | safe (consecutive < 2) |
| 4 | 0.72 | scam | 0.61 | 2 | scam |

Note: In analysis 3, one clean window drops consecutive to 1 (decrement, not reset), so analysis 4 only needs one more hit to re-escalate. The EMA stays elevated because it's smoothed.

## Files Modified

| File | Change |
|------|--------|
| `lib/core/api/gemini_scam_text_api.dart` | Add `scamProbability` field to `ScamAnalysisResult` |
| `lib/core/api/local_scam_classifier.dart` | Set `scamProbability` in results; default `suspiciousThreshold` 0.35 → 0.50 |
| `lib/features/scam_call/scam_call_controller.dart` | Replace ratchet with EMA + min-analyses gate |

## What This Does NOT Change

- Gate threshold (loaded from model weights, currently 0.55)
- Type classifier (Stage 2, 41-class)
- Training pipeline or model weights
- Transcript capture, debouncing, or window size
- Overlay UI rendering

## Classifier Compatibility Note

The EMA smoothing logic uses `scamProbability` which is on a consistent 0-1 scale (higher = more likely scam) regardless of which classifier implementation is used. Both `LocalScamClassifier` and `GeminiScamTextApi` must set this field correctly.

## Testing

- Existing `local_scam_classifier_test.dart` should still pass (threshold change is backward-compatible)
- Controller EMA logic should be tested for:
  - Single scam analysis does NOT escalate (consecutive gate blocks)
  - 2+ consecutive scam analyses DO escalate
  - Scam → safe → safe sequence decays threat level back to safe
  - One clean analysis in a scam stream decrements but does not fully reset counter
  - EMA initialization uses first value directly (no cold-start bias)
