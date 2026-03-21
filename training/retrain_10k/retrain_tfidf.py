"""
Retrain TF-IDF classifiers on checkvar_corpus_10k.jsonl.

Produces two models:
  1. Binary gate   (safe / scam) — high-recall first-pass filter
  2. Multiclass    (41 scam subtypes + safe) — detailed classification

All outputs go to  training/retrain_10k/output/  and are also copied to
checkvar/assets/models/ for on-device use.

Usage:
    cd training/retrain_10k
    python retrain_tfidf.py
    python retrain_tfidf.py --data ../../checkvar_corpus_10k.jsonl --no-copy
"""

from __future__ import annotations

import argparse
import json
import math
import random
import shutil
import warnings
from pathlib import Path
from time import perf_counter

import numpy as np
import pandas as pd
from scipy.sparse import hstack, vstack as sp_vstack
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    accuracy_score,
    classification_report,
    f1_score,
    precision_recall_curve,
    roc_auc_score,
)
from sklearn.model_selection import (
    PredefinedSplit,
    RandomizedSearchCV,
    StratifiedKFold,
    cross_val_score,
    train_test_split,
)
from sklearn.pipeline import Pipeline

warnings.filterwarnings("ignore")

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

SCRIPT_DIR = Path(__file__).resolve().parent
TRAINING_ROOT = SCRIPT_DIR.parent
PROJECT_ROOT = TRAINING_ROOT.parent
DEFAULT_DATA = PROJECT_ROOT / "checkvar_corpus_10k.jsonl"
OUTPUT_DIR = SCRIPT_DIR / "output"
ASSETS_DIR = PROJECT_ROOT / "checkvar" / "assets" / "models"

# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------


def load_corpus(path: Path) -> pd.DataFrame:
    """Load the 10k JSONL corpus."""
    rows = []
    with path.open(encoding="utf-8") as fh:
        for line in fh:
            rows.append(json.loads(line))
    df = pd.DataFrame(rows)
    print(f"Loaded {len(df):,} rows from {path.name}")
    print(f"  Binary labels : {df['label'].value_counts().to_dict()}")
    print(f"  Scam types    : {df['scam_type'].nunique()} unique")
    return df


# ---------------------------------------------------------------------------
# TF-IDF helpers
# ---------------------------------------------------------------------------


def build_char_wb_vectorizer(max_features: int = 25_000) -> TfidfVectorizer:
    return TfidfVectorizer(
        analyzer="char_wb",
        ngram_range=(2, 5),
        max_features=max_features,
        sublinear_tf=True,
        strip_accents=None,
        dtype=np.float32,
    )


def build_word_vectorizer(max_features: int = 20_000) -> TfidfVectorizer:
    return TfidfVectorizer(
        analyzer="word",
        ngram_range=(1, 2),
        max_features=max_features,
        sublinear_tf=True,
        strip_accents=None,
        dtype=np.float32,
    )


def build_multiclass_pipeline(max_features: int = 50_000) -> Pipeline:
    """TF-IDF (char_wb) + LogisticRegression for multiclass scam-type."""
    return Pipeline([
        ("tfidf", TfidfVectorizer(
            analyzer="char_wb",
            ngram_range=(2, 5),
            max_features=max_features,
            sublinear_tf=True,
            strip_accents=None,
        )),
        ("clf", LogisticRegression(
            C=1.0,
            max_iter=5000,
            class_weight="balanced",
            solver="lbfgs",
        )),
    ])


LR_PARAM_DIST = {
    "C": [0.01, 0.05, 0.1, 0.5, 1.0, 2.0, 5.0],
    "penalty": ["l1", "l2"],
    "solver": ["saga"],
    "max_iter": [4000],
}
N_ITER = 20


def choose_recall_threshold(
    scam_probs: np.ndarray,
    y_true: np.ndarray,
    target_recall: float = 0.92,
) -> float:
    """Find the highest probability threshold that still achieves >= target_recall.

    precision_recall_curve returns thresholds in ascending order and recall in
    descending order.  We want the highest threshold (best precision) that
    still meets the recall target.
    """
    precision, recall, thresholds = precision_recall_curve(y_true, scam_probs)
    chosen = 0.5
    for thr, rec in zip(thresholds, recall[:-1]):
        if rec >= target_recall:
            chosen = float(thr)
        else:
            break
    return chosen


def print_top_features(coef: np.ndarray, feature_names: np.ndarray, n: int = 20) -> list[str]:
    lines = []
    top_scam_idx = np.argsort(coef)[-n:][::-1]
    top_safe_idx = np.argsort(coef)[:n]

    lines.append(f"\n  Top {n} SCAM features (positive coef):")
    for rank, idx in enumerate(top_scam_idx, 1):
        lines.append(f"    {rank:>2}. {feature_names[idx]!r:>20s}  coef={coef[idx]:+.4f}")

    lines.append(f"\n  Top {n} SAFE features (negative coef):")
    for rank, idx in enumerate(top_safe_idx, 1):
        lines.append(f"    {rank:>2}. {feature_names[idx]!r:>20s}  coef={coef[idx]:+.4f}")

    text = "\n".join(lines)
    print(text)
    return lines


# ---------------------------------------------------------------------------
# Export helpers (Dart-compatible JSON)
# ---------------------------------------------------------------------------


def export_tfidf_json(vectorizer: TfidfVectorizer, path: Path) -> None:
    payload = {
        "analyzer": vectorizer.analyzer,
        "ngram_range": list(vectorizer.ngram_range),
        "sublinear_tf": vectorizer.sublinear_tf,
        "max_features": vectorizer.max_features,
        "vocabulary": {t: int(i) for t, i in vectorizer.vocabulary_.items()},
        "idf": vectorizer.idf_.tolist(),
    }
    path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    print(f"  Exported {path.name} ({len(vectorizer.vocabulary_):,} terms, {path.stat().st_size / 1024:.0f} KB)")


def export_classifier_json(classifier: LogisticRegression, path: Path, **extra) -> None:
    payload = {
        "classes": classifier.classes_.tolist(),
        "coef_shape": list(classifier.coef_.shape),
        "coef": classifier.coef_.tolist(),
        "intercept": classifier.intercept_.tolist(),
        **extra,
    }
    path.write_text(json.dumps(payload), encoding="utf-8")
    print(f"  Exported {path.name} ({path.stat().st_size / 1024:.0f} KB)")


# ---------------------------------------------------------------------------
# Part 1: Binary gate
# ---------------------------------------------------------------------------


def train_binary_gate(
    df: pd.DataFrame,
    output_dir: Path,
    seed: int,
    target_recall: float,
    calibration_path: Path | None = None,
) -> dict:
    print("\n" + "=" * 70)
    print("PART 1: BINARY GATE (safe / scam)")
    print("=" * 70)

    texts = df["transcript_window"].tolist()
    y_all = np.array([1 if lbl == "scam" else 0 for lbl in df["label"]])

    # 60/20/20 split
    texts_tv, texts_test, y_tv, y_test = train_test_split(
        texts, y_all, test_size=0.20, random_state=seed, stratify=y_all,
    )
    texts_train, texts_val, y_train, y_val = train_test_split(
        texts_tv, y_tv, test_size=0.25, random_state=seed, stratify=y_tv,
    )

    print(f"  Train: {len(texts_train):,}  Val: {len(texts_val):,}  Test: {len(texts_test):,}")

    # Load calibration set (human-curated test cases) if provided
    cal_texts, cal_y = [], np.array([])
    if calibration_path and calibration_path.exists():
        with calibration_path.open(encoding="utf-8") as f:
            cal_cases = json.load(f)
        cal_texts = [c["transcript_window"] for c in cal_cases]
        cal_y = np.array([1 if c["binary_label"] == "scam" else 0 for c in cal_cases])
        print(f"  Calibration set: {len(cal_texts)} cases "
              f"(safe={int((cal_y == 0).sum())}, scam={int((cal_y == 1).sum())})")

    # Class weights — boost scam to favor recall
    class_weight = {0: 1.0, 1: 2.0}
    print(f"  Class weights: safe={class_weight[0]:.2f}, scam={class_weight[1]:.2f}")

    # Fit char_wb vectorizer
    print("  Fitting char_wb vectorizer...")
    char_vec = build_char_wb_vectorizer(25_000)
    X_train_c = char_vec.fit_transform(texts_train)
    X_val_c = char_vec.transform(texts_val)
    X_test_c = char_vec.transform(texts_test)
    print(f"    char_wb vocab: {len(char_vec.vocabulary_):,}")

    # Fit word vectorizer
    print("  Fitting word vectorizer...")
    word_vec = build_word_vectorizer(20_000)
    X_train_w = word_vec.fit_transform(texts_train)
    X_val_w = word_vec.transform(texts_val)
    X_test_w = word_vec.transform(texts_test)
    print(f"    word vocab   : {len(word_vec.vocabulary_):,}")

    # Hyperparameter search on char_wb features (the exportable model)
    print("\n  Hyperparameter search (char_wb)...")
    X_search = sp_vstack([X_train_c, X_val_c], format="csr")
    y_search = np.concatenate([y_train, y_val])
    split_idx = np.concatenate([np.full(len(y_train), -1), np.zeros(len(y_val), dtype=int)])
    ps = PredefinedSplit(split_idx)

    search = RandomizedSearchCV(
        LogisticRegression(random_state=seed, class_weight=class_weight, n_jobs=-1),
        param_distributions=LR_PARAM_DIST,
        n_iter=N_ITER,
        cv=ps,
        scoring="f1",
        n_jobs=-1,
        refit=False,
        random_state=seed,
        verbose=0,
    )
    t0 = perf_counter()
    search.fit(X_search, y_search)
    print(f"    Best val F1: {search.best_score_:.4f}  ({perf_counter() - t0:.1f}s)")
    print(f"    Best params: {search.best_params_}")

    # Retrain on train+val with best params
    X_tv_c = sp_vstack([X_train_c, X_val_c], format="csr")
    y_tv = np.concatenate([y_train, y_val])
    clf = LogisticRegression(
        **search.best_params_,
        random_state=seed,
        class_weight=class_weight,
        n_jobs=-1,
    )
    clf.fit(X_tv_c, y_tv)

    # Evaluate on synthetic test split
    y_prob = clf.predict_proba(X_test_c)[:, 1]
    synth_threshold = choose_recall_threshold(y_prob, y_test, target_recall)

    # Calibrate threshold on human-curated data if available
    if len(cal_texts) > 0:
        X_cal_c = char_vec.transform(cal_texts)
        cal_prob = clf.predict_proba(X_cal_c)[:, 1]
        cal_threshold = choose_recall_threshold(cal_prob, cal_y, target_recall)
        # Use the calibration threshold (real-world data is more representative)
        threshold = cal_threshold
        print(f"\n  Synthetic threshold  : {synth_threshold:.4f}")
        print(f"  Calibration threshold: {cal_threshold:.4f} (using this)")

        # Report on calibration set
        cal_pred = (cal_prob >= threshold).astype(int)
        cal_pred_labels = ["scam" if p == 1 else "safe" for p in cal_pred]
        cal_true_labels = ["scam" if t == 1 else "safe" for t in cal_y]
        cal_report = classification_report(
            cal_true_labels, cal_pred_labels,
            target_names=["safe", "scam"], digits=4,
        )
        print(f"\n  --- Calibration Set Report ---")
        print(cal_report)
    else:
        threshold = synth_threshold

    y_pred = (y_prob >= threshold).astype(int)
    y_pred_labels = ["scam" if p == 1 else "safe" for p in y_pred]
    y_test_labels = ["scam" if t == 1 else "safe" for t in y_test]

    acc = accuracy_score(y_test, y_pred)
    f1 = f1_score(y_test, y_pred)
    auc = roc_auc_score(y_test, y_prob)

    report = classification_report(y_test_labels, y_pred_labels, target_names=["safe", "scam"], digits=4)
    print(f"\n  Gate threshold (recall >= {target_recall}): {threshold:.4f}")
    print(f"  Accuracy: {acc:.4f}  F1: {f1:.4f}  ROC-AUC: {auc:.4f}")
    print(report)

    # Feature importance
    feat_lines = print_top_features(clf.coef_[0], np.array(char_vec.get_feature_names_out()), n=20)

    # Export
    gate_dir = output_dir / "gate"
    gate_dir.mkdir(parents=True, exist_ok=True)

    original_classes = clf.classes_.copy()
    clf.classes_ = np.array(["safe", "scam"])
    export_tfidf_json(char_vec, gate_dir / "gate_tfidf_config.json")
    export_classifier_json(clf, gate_dir / "gate_classifier_weights.json",
                           threshold=threshold, target_recall=target_recall)
    clf.classes_ = original_classes

    # Save metrics
    metrics_text = (
        f"Binary Gate Evaluation (10k corpus)\n"
        f"{'=' * 50}\n"
        f"Threshold (target recall >= {target_recall}): {threshold:.4f}\n"
        f"Accuracy : {acc:.4f}\n"
        f"F1       : {f1:.4f}\n"
        f"ROC-AUC  : {auc:.4f}\n\n"
        f"{report}\n"
        + "\n".join(feat_lines)
    )
    (gate_dir / "gate_metrics.txt").write_text(metrics_text, encoding="utf-8")

    return {
        "threshold": threshold,
        "accuracy": acc,
        "f1": f1,
        "auc": auc,
        "vocab_size": len(char_vec.vocabulary_),
    }


# ---------------------------------------------------------------------------
# Part 2: Multiclass classifier
# ---------------------------------------------------------------------------


def train_multiclass(
    df: pd.DataFrame,
    output_dir: Path,
    seed: int,
) -> dict:
    print("\n" + "=" * 70)
    print("PART 2: MULTICLASS CLASSIFIER (scam_type)")
    print("=" * 70)

    texts = df["transcript_window"].tolist()
    labels = df["scam_type"].tolist()
    unique_labels = sorted(set(labels))
    print(f"  {len(unique_labels)} classes: {unique_labels[:5]} ... {unique_labels[-3:]}")

    # 80/20 split
    X_train, X_test, y_train, y_test = train_test_split(
        texts, labels, test_size=0.2, random_state=seed, stratify=labels,
    )
    print(f"  Train: {len(X_train):,}  Test: {len(X_test):,}")

    # Cross-validation
    pipeline = build_multiclass_pipeline(50_000)
    print("  Running 5-fold cross-validation...")
    t0 = perf_counter()
    cv_scores = cross_val_score(
        pipeline, X_train, y_train,
        cv=StratifiedKFold(n_splits=5, shuffle=True, random_state=seed),
        scoring="f1_macro",
    )
    print(f"  CV F1 (macro): {cv_scores.mean():.4f} +/- {cv_scores.std():.4f}  ({perf_counter() - t0:.1f}s)")

    # Train on full training set
    print("  Training final model...")
    pipeline.fit(X_train, y_train)

    # Evaluate
    y_pred = pipeline.predict(X_test)
    report = classification_report(y_test, y_pred, digits=4)
    accuracy = accuracy_score(y_test, y_pred)
    macro_f1 = f1_score(y_test, y_pred, average="macro")

    print(f"\n  Test Accuracy: {accuracy:.4f}  Macro-F1: {macro_f1:.4f}")
    print(report)

    # Export
    mc_dir = output_dir / "multiclass"
    mc_dir.mkdir(parents=True, exist_ok=True)

    tfidf_vec = pipeline.named_steps["tfidf"]
    clf = pipeline.named_steps["clf"]
    export_tfidf_json(tfidf_vec, mc_dir / "tfidf_config.json")
    export_classifier_json(clf, mc_dir / "classifier_weights.json")

    # Label map
    label_map = {i: label for i, label in enumerate(pipeline.classes_)}
    (mc_dir / "label_map.json").write_text(
        json.dumps(label_map, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"  Exported label_map.json ({len(label_map)} classes)")

    # Save metrics
    metrics_text = (
        f"Multiclass Classifier Evaluation (10k corpus)\n"
        f"{'=' * 50}\n"
        f"CV F1 (macro): {cv_scores.mean():.4f} +/- {cv_scores.std():.4f}\n"
        f"Test Accuracy : {accuracy:.4f}\n"
        f"Test Macro-F1 : {macro_f1:.4f}\n\n"
        f"{report}"
    )
    (mc_dir / "multiclass_metrics.txt").write_text(metrics_text, encoding="utf-8")

    # Sanity check
    print("\n  --- Sanity Check ---")
    test_samples = [
        "Chào bạn, tối nay mình đi ăn phở nhé.",
        "Đây là ngân hàng Vietcombank. Tài khoản bạn bị khóa. Đọc mã OTP ngay.",
        "Công an yêu cầu bạn chuyển tiền vào tài khoản điều tra.",
        "Chúc mừng bạn trúng thưởng 50 triệu từ Shopee.",
        "Gói hàng bị giữ tại hải quan. Đóng phí thông quan ngay.",
        "Đầu tư Bitcoin lãi 300% trong 30 ngày.",
        "Bạn được duyệt vay 100 triệu lãi 0%. Đóng phí hồ sơ.",
        "Chúng tôi đang giữ con bạn. Chuyển 200 triệu ngay.",
        "Điện thoại bị virus. Cài ứng dụng bảo mật theo link này.",
        "Em cần tiền mua vé máy bay sang gặp anh.",
    ]
    for sample in test_samples:
        pred = pipeline.predict([sample])[0]
        proba = pipeline.predict_proba([sample])[0]
        conf = proba.max()
        print(f"    [{pred:>25s}] ({conf:.2f})  {sample[:60]}")

    return {
        "cv_f1": cv_scores.mean(),
        "accuracy": accuracy,
        "macro_f1": macro_f1,
        "vocab_size": len(tfidf_vec.vocabulary_),
        "num_classes": len(label_map),
    }


# ---------------------------------------------------------------------------
# Copy to Flutter assets
# ---------------------------------------------------------------------------


def copy_to_assets(output_dir: Path, assets_dir: Path) -> None:
    print("\n" + "=" * 70)
    print("COPYING TO FLUTTER ASSETS")
    print("=" * 70)

    copies = [
        (output_dir / "gate" / "gate_tfidf_config.json", assets_dir / "gate_tfidf_config.json"),
        (output_dir / "gate" / "gate_classifier_weights.json", assets_dir / "gate_classifier_weights.json"),
        (output_dir / "multiclass" / "tfidf_config.json", assets_dir / "tfidf_config.json"),
        (output_dir / "multiclass" / "classifier_weights.json", assets_dir / "classifier_weights.json"),
    ]
    for src, dst in copies:
        shutil.copy2(src, dst)
        print(f"  {src.name} -> {dst}")


# ---------------------------------------------------------------------------
# Also export transformer_corpus.jsonl for PhoBERT training compatibility
# ---------------------------------------------------------------------------


def export_phobert_corpus(df: pd.DataFrame, output_dir: Path) -> None:
    """Write a transformer_corpus.jsonl in the format expected by train_phobert_distilled.py."""
    phobert_dir = output_dir / "phobert_corpus"
    phobert_dir.mkdir(parents=True, exist_ok=True)
    path = phobert_dir / "transformer_corpus.jsonl"

    with path.open("w", encoding="utf-8") as fh:
        for _, row in df.iterrows():
            record = {
                "id": row["id"],
                "binary_label": row["label"],
                "subtype_label": row["scam_type"],
                "source_type": row.get("source_type", "synthetic_augmented"),
                "noise_style": "original",
                "transcript_window": row["transcript_window"],
            }
            fh.write(json.dumps(record, ensure_ascii=False) + "\n")

    print(f"\n  Exported PhoBERT-compatible corpus: {path}")
    print(f"    {len(df):,} rows, ready for train_phobert_distilled.py")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(description="Retrain TF-IDF classifiers on 10k corpus")
    parser.add_argument("--data", type=Path, default=DEFAULT_DATA)
    parser.add_argument("--calibration", type=Path,
                        default=PROJECT_ROOT / "claude_100_test_case.json",
                        help="Human-curated test cases for gate threshold calibration")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--target-recall", type=float, default=0.92)
    parser.add_argument("--no-copy", action="store_true", help="Skip copying to Flutter assets")
    args = parser.parse_args()

    random.seed(args.seed)
    np.random.seed(args.seed)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Load
    df = load_corpus(args.data)

    # Train both models
    gate_metrics = train_binary_gate(
        df, OUTPUT_DIR, args.seed, args.target_recall,
        calibration_path=args.calibration,
    )
    mc_metrics = train_multiclass(df, OUTPUT_DIR, args.seed)

    # Export PhoBERT-compatible corpus
    export_phobert_corpus(df, OUTPUT_DIR)

    # Copy to Flutter assets
    if not args.no_copy:
        copy_to_assets(OUTPUT_DIR, ASSETS_DIR)

    # Summary
    print("\n" + "=" * 70)
    print("SUMMARY")
    print("=" * 70)
    print(f"  Corpus           : {args.data.name} ({len(df):,} samples)")
    print(f"  Gate threshold   : {gate_metrics['threshold']:.4f}")
    print(f"  Gate F1          : {gate_metrics['f1']:.4f}")
    print(f"  Gate AUC         : {gate_metrics['auc']:.4f}")
    print(f"  Gate vocab       : {gate_metrics['vocab_size']:,}")
    print(f"  Multiclass CV-F1 : {mc_metrics['cv_f1']:.4f}")
    print(f"  Multiclass F1    : {mc_metrics['macro_f1']:.4f}")
    print(f"  Multiclass vocab : {mc_metrics['vocab_size']:,}")
    print(f"  Multiclass labels: {mc_metrics['num_classes']}")
    print(f"\n  Output folder    : {OUTPUT_DIR}")
    print(f"  Flutter assets   : {'skipped' if args.no_copy else str(ASSETS_DIR)}")

    # Save summary JSON
    summary = {"gate": gate_metrics, "multiclass": mc_metrics, "corpus": args.data.name, "seed": args.seed}
    (OUTPUT_DIR / "summary.json").write_text(json.dumps(summary, indent=2, default=float), encoding="utf-8")


if __name__ == "__main__":
    main()
