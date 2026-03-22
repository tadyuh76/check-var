import json
import os
import urllib.request
import urllib.error

OPENAI_API_KEY = os.environ["OPENAI_API_KEY"]
SERPER_API_KEY = os.environ["SERPER_API_KEY"]


def lambda_handler(event, context):
    try:
        body = json.loads(event.get("body", "{}"))
        text = body.get("text", "").strip()

        if not text or len(text) < 20:
            return _response(400, {"error": "Text too short"})

        # Step 1: Extract search queries + detect non-news
        queries = _extract_search_query(text)

        if queries is None:
            return _response(200, {
                "verdict": "not_news",
                "confidence": 1.0,
                "summary": "Nội dung này không phải tin tức có thể kiểm chứng.",
                "sources": [],
            })

        # Step 2: Web search via Serper (search all query variants, deduplicate)
        sources = _multi_search(queries)

        # Step 3: Classify via OpenAI
        result = _classify_news(text, sources)

        return _response(200, result)

    except Exception as e:
        import traceback
        traceback.print_exc()  # Log to CloudWatch
        return _response(500, {"error": "Internal server error"})


# ---------------------------------------------------------------------------
# 1. Extract search query
# ---------------------------------------------------------------------------

def _extract_search_query(text):
    """Extract search query + detect non-news content in a single API call."""
    truncated = text[:1000]

    try:
        content = _openai_chat(
            messages=[
                {
                    "role": "system",
                    "content": (
                        "You analyze text from a phone screenshot (OCR). Return JSON. No explanation.\n"
                        "The text may contain noise: ads, UI buttons, navigation, crypto banners, etc.\n"
                        "IGNORE the noise. Focus on the MAIN content.\n\n"
                        'If the MAIN content is a verifiable news claim or article headline:\n'
                        '  {"type":"news","queries":["<query1>","<query2>","<query3>"]}\n'
                        '  - query1: direct factual claim\n'
                        '  - query2: rephrased with different keywords\n'
                        '  - query3: Vietnamese/English alternate (opposite language of query1)\n'
                        'If the MAIN content is NOT news (personal chat, opinions, product listings, '
                        'app notifications, memes, jokes, or ONLY ads with no article):\n'
                        '  {"type":"not_news","queries":[]}'
                    ),
                },
                {"role": "user", "content": truncated},
            ],
            temperature=0.0,
            max_tokens=200,
            json_mode=True,
        )

        parsed = _extract_json(content)
        if parsed and parsed.get("type") == "not_news":
            return None  # Signal: skip fact-checking
        queries = parsed.get("queries", []) if parsed else []
        if queries and isinstance(queries, list):
            return [q.strip().strip("\"'") for q in queries if q.strip()]
    except (json.JSONDecodeError, KeyError, TypeError):
        pass
    except urllib.error.URLError:
        raise  # Let network errors propagate to top-level handler

    # Fallback: longest line > 20 chars
    lines = [l for l in text.split("\n") if len(l.strip()) > 20]
    if not lines:
        return [text[:100]]
    longest = max(lines, key=len)
    return [longest[:100]]


# ---------------------------------------------------------------------------
# 2. Web search via Serper.dev
# ---------------------------------------------------------------------------


# Trusted news domains — tiered by reliability
# Tier 1: Government, wire services, major national outlets
# Tier 2: Major newspapers, TV networks
# Tier 3: Known reputable outlets
TRUSTED_DOMAINS = {
    # ── Vietnam: Tier 1 (state media, wire services) ──
    "nhandan.vn": 1, "dangcongsan.vn": 1, "chinhphu.vn": 1,
    "baochinhphu.vn": 1, "quochoi.vn": 1, "vtv.vn": 1,
    "vov.vn": 1, "ttxvn.vn": 1, "vietnamplus.vn": 1,
    "qdnd.vn": 1, "cand.com.vn": 1, "bvn.com.vn": 1,

    # ── Vietnam: Tier 2 (major outlets) ──
    "vnexpress.net": 2, "tuoitre.vn": 2, "thanhnien.vn": 2,
    "dantri.com.vn": 2, "laodong.vn": 2, "tienphong.vn": 2,
    "vietnamnet.vn": 2, "nld.com.vn": 2, "sggp.org.vn": 2,
    "zingnews.vn": 2, "vnanet.vn": 2, "baomoi.com": 2,

    # ── Vietnam: Tier 3 (reputable) ──
    "vneconomy.vn": 3, "cafef.vn": 3, "genk.vn": 3,
    "soha.vn": 3, "vietcetera.com": 3,
    "plo.vn": 3, "anninhthudo.vn": 3, "hanoimoi.vn": 3,
    "hcmcpv.org.vn": 3, "congan.com.vn": 3, "kinhtedothi.vn": 3,
    "phapluatplus.vn": 3, "baogiaothong.vn": 3, "danviet.vn": 3,

    # ── US/International: Tier 1 (wire services, public media) ──
    "apnews.com": 1, "reuters.com": 1, "bbc.com": 1,
    "bbc.co.uk": 1, "pbs.org": 1, "npr.org": 1,

    # ── US/International: Tier 2 (major outlets) ──
    "nytimes.com": 2, "washingtonpost.com": 2, "wsj.com": 2,
    "cnn.com": 2, "nbcnews.com": 2, "abcnews.go.com": 2,
    "cbsnews.com": 2, "bloomberg.com": 2, "theguardian.com": 2,
    "usatoday.com": 2, "politico.com": 2, "time.com": 2,

    # ── US/International: Tier 3 (reputable) ──
    "forbes.com": 3, "businessinsider.com": 3, "cnbc.com": 3,
    "thehill.com": 3, "axios.com": 3, "aljazeera.com": 3,
    "france24.com": 3, "dw.com": 3, "scmp.com": 3,

    # ── Tech ──
    "techcrunch.com": 2, "theverge.com": 2, "arstechnica.com": 2,
    "wired.com": 2, "engadget.com": 3, "tomshardware.com": 3,

    # ── Fact-checking sites ──
    "factcheck.org": 1, "snopes.com": 2, "politifact.com": 2,

    # ── Vietnam extras ──
    "baotintuc.vn": 1, "znews.vn": 2, "thanhtra.com.vn": 2,
}


def _get_domain(url):
    """Extract domain from URL."""
    try:
        from urllib.parse import urlparse
        host = urlparse(url).hostname or ""
        # Strip www.
        if host.startswith("www."):
            host = host[4:]
        return host
    except Exception:
        return ""


def _multi_search(queries):
    """Search all query variants in parallel, deduplicate, sort by trust + recency."""
    from concurrent.futures import ThreadPoolExecutor

    # Parallel search — 3 queries at once instead of sequential
    with ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(_web_search, queries))

    seen_urls = set()
    all_sources = []
    for batch in results:
        for src in batch:
            if src["url"] not in seen_urls:
                seen_urls.add(src["url"])
                domain = _get_domain(src["url"])
                tier = TRUSTED_DOMAINS.get(domain, 99)
                src["tier"] = tier
                all_sources.append(src)

    # Sort: trusted first, then sources with dates before undated
    all_sources.sort(key=lambda s: (s["tier"], not s.get("date")))
    return all_sources[:15]


def _web_search(query):
    try:
        req = urllib.request.Request(
            "https://google.serper.dev/search",
            data=json.dumps({"q": query, "num": 7}).encode(),
            headers={
                "X-API-KEY": SERPER_API_KEY,
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read())

        organic = data.get("organic", [])
        return [
            {
                "title": r.get("title", ""),
                "url": r.get("link", ""),
                "snippet": r.get("snippet", ""),
                "date": r.get("date", ""),  # e.g. "2 hours ago", "Mar 21, 2026"
            }
            for r in organic[:10]
        ]
    except Exception:
        return []


# ---------------------------------------------------------------------------
# 3. Classify news via OpenAI
# ---------------------------------------------------------------------------

def _classify_news(text, sources):
    truncated = text[:500]

    tier_labels = {1: "⭐ OFFICIAL", 2: "✓ MAJOR", 3: "• KNOWN"}
    source_lines = []
    for idx, s in enumerate(sources):
        tier = s.get("tier", 99)
        badge = tier_labels.get(tier, "")
        date = s.get("date", "")
        date_str = f" ({date})" if date else ""
        source_lines.append(f"[{idx}] {badge} [{s['title']}]{date_str}: {s['snippet']}")
    source_summary = "\n".join(source_lines) if source_lines else "(no sources available)"

    from datetime import date as _date
    today = _date.today().isoformat()

    prompt = f"""Fact-checker. Today: {today}. Return JSON ONLY. Use ONLY sources below, not training data.

Rules:
- Sources confirm → "real", contradict → "fake", irrelevant/none → "uncertain"
- ⭐ OFFICIAL/✓ MAJOR sources outweigh unmarked ones
- More recent sources override older ones when contradicting
- confidence: "very_high"|"high"|"medium"|"low"|"very_low" (based on source count+quality)
- summary: 1-2 sentences in Vietnamese
- relevant_sources: list of source indices [0,1,...] that are RELEVANT to the claim. Exclude sources that are about a different topic, person, or event.

CLAIM:
{truncated}

SOURCES:
{source_summary}

{{"verdict":"real|fake|uncertain","confidence":"...","summary":"...","relevant_sources":[0,1,...]}}"""

    try:
        content = _openai_chat(
            messages=[
                {
                    "role": "system",
                    "content": "You always respond with a single JSON object only. No explanations.",
                },
                {"role": "user", "content": prompt},
            ],
            temperature=0.1,
            max_tokens=200,
            json_mode=True,
        )

        parsed = _extract_json(content)

        if parsed is None:
            return _uncertain_result(text, sources, "Khong the phan tich phan hoi tu AI.")

        verdict = parsed.get("verdict", "uncertain").lower()
        if verdict not in ("real", "fake", "uncertain"):
            verdict = "uncertain"

        confidence_map = {
            "very_high": 0.95,
            "high": 0.75,
            "medium": 0.50,
            "low": 0.30,
            "very_low": 0.10,
        }
        raw_conf = str(parsed.get("confidence", "very_low")).lower().strip()
        confidence = confidence_map.get(raw_conf, 0.50)
        summary = parsed.get("summary", "")

        if not sources:
            summary = "Web search khong kha dung, ket qua chi dua tren AI.\n" + summary

        # Filter to only relevant sources if AI provided indices
        relevant_indices = parsed.get("relevant_sources")
        if isinstance(relevant_indices, list) and relevant_indices:
            valid_indices = {i for i in relevant_indices if isinstance(i, int) and 0 <= i < len(sources)}
            filtered = [sources[i] for i in sorted(valid_indices)] if valid_indices else sources
        else:
            filtered = sources

        # Clean internal fields before returning to app
        clean_sources = [
            {"title": s["title"], "url": s["url"], "snippet": s["snippet"],
             **({"date": s["date"]} if s.get("date") else {})}
            for s in filtered
        ]

        return {
            "verdict": verdict,
            "confidence": confidence,
            "summary": summary,
            "sources": clean_sources,
        }

    except Exception as e:
        return _uncertain_result(text, sources, f"Loi khi goi AI: {e}")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _openai_chat(messages, temperature=0.0, max_tokens=100, json_mode=False):
    """Call OpenAI Responses API (gpt-5.4-mini)."""
    body = {
        "model": "gpt-5.4-mini",
        "input": messages,
        "temperature": temperature,
        "max_output_tokens": max_tokens,
    }
    if json_mode:
        body["text"] = {"format": {"type": "json_object"}}

    req = urllib.request.Request(
        "https://api.openai.com/v1/responses",
        data=json.dumps(body).encode(),
        headers={
            "Authorization": f"Bearer {OPENAI_API_KEY}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        data = json.loads(resp.read())

    # Responses API returns output[].content[].text
    output = data.get("output", [])
    for item in output:
        if item.get("type") == "message":
            for part in item.get("content", []):
                if part.get("type") == "output_text":
                    return part.get("text", "")
    return ""


def _extract_json(raw):
    """Parse JSON from GPT response. Since we use json_mode, output should be clean."""
    try:
        import re
        s = re.sub(r"```json\s*|```\s*", "", raw, flags=re.IGNORECASE)
        s = re.sub(r"<think>[\s\S]*?</think>", "", s, flags=re.IGNORECASE)
        return json.loads(s.strip())
    except Exception:
        return None


def _uncertain_result(text, sources, summary):
    clean = [
        {"title": s["title"], "url": s["url"], "snippet": s["snippet"],
         **({"date": s["date"]} if s.get("date") else {})}
        for s in sources
    ] if sources else []
    return {
        "verdict": "uncertain",
        "confidence": 0.0,
        "summary": summary,
        "sources": clean,
    }


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, ensure_ascii=False),
    }
