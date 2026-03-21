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
        return _response(500, {"error": str(e)})


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
            max_tokens=100,
            json_mode=True,
        )

        parsed = _extract_json(content)
        if parsed and parsed.get("type") == "not_news":
            return None  # Signal: skip fact-checking
        queries = parsed.get("queries", []) if parsed else []
        if queries and isinstance(queries, list):
            return [q.strip().strip("\"'") for q in queries if q.strip()]
    except Exception:
        pass

    # Fallback: longest line > 20 chars
    lines = [l for l in text.split("\n") if len(l.strip()) > 20]
    if not lines:
        return [text[:100]]
    longest = max(lines, key=len)
    return [longest[:100]]


# ---------------------------------------------------------------------------
# 2. Web search via Serper.dev
# ---------------------------------------------------------------------------

def _multi_search(queries):
    """Search all query variants and deduplicate by URL."""
    seen_urls = set()
    all_sources = []
    for q in queries:
        for src in _web_search(q):
            if src["url"] not in seen_urls:
                seen_urls.add(src["url"])
                all_sources.append(src)
    return all_sources[:15]


def _web_search(query):
    try:
        req = urllib.request.Request(
            "https://google.serper.dev/search",
            data=json.dumps({"q": query, "num": 10}).encode(),
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

    source_summary = (
        "\n".join(f"- [{s['title']}]: {s['snippet']}" for s in sources)
        if sources
        else "(no sources available)"
    )

    from datetime import date
    today = date.today().isoformat()

    prompt = f"""You are a fact-checker. Today is {today}. Return ONLY JSON.

IMPORTANT: Base your verdict ONLY on the SOURCES below — NOT on your training data.
The sources are real-time web search results from today.
Your knowledge cutoff does NOT matter.

Rules:
- If SOURCES confirm the claim -> "real"
- If SOURCES contradict the claim -> "fake"
- If no sources or sources are irrelevant -> "uncertain"
- Rumors/opinions/non-news/ads/memes -> "uncertain"
- NEVER say "beyond knowledge cutoff" — use the sources instead

Confidence levels (pick ONE based on source quality):
- "very_high": 3+ reliable sources clearly confirm/deny
- "high": 1-2 reliable sources support the verdict
- "medium": sources are relevant but not conclusive
- "low": few relevant sources, mostly indirect
- "very_low": no relevant sources found, pure guess

CLAIM:
{truncated}

TODAY'S WEB SEARCH RESULTS:
{source_summary}

{{"verdict":"real|fake|uncertain","confidence":"very_high|high|medium|low|very_low","summary":"1-2 sentence Vietnamese explanation based on sources"}}"""

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

        return {
            "verdict": verdict,
            "confidence": confidence,
            "summary": summary,
            "sources": sources,
        }

    except Exception as e:
        return _uncertain_result(text, sources, f"Loi khi goi AI: {e}")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _openai_chat(messages, temperature=0.0, max_tokens=100, json_mode=False):
    """Call OpenAI Responses API (gpt-5.4-mini — fastest, most accurate)."""
    # Convert chat messages format to Responses API input
    input_msgs = []
    for m in messages:
        input_msgs.append({"role": m["role"], "content": m["content"]})

    body = {
        "model": "gpt-5.4-mini",
        "input": input_msgs,
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
    with urllib.request.urlopen(req, timeout=45) as resp:
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
    import re
    try:
        s = re.sub(r"```json\s*", "", raw, flags=re.IGNORECASE)
        s = re.sub(r"```\s*", "", s)
        s = re.sub(r"<think>[\s\S]*?</think>", "", s, flags=re.IGNORECASE)
        s = s.strip()

        start = s.find("{")
        if start == -1:
            return None

        depth = 0
        end = None
        for i in range(start, len(s)):
            if s[i] == "{":
                depth += 1
            elif s[i] == "}":
                depth -= 1
                if depth == 0:
                    end = i
                    break

        if end is None:
            return None

        return json.loads(s[start : end + 1])
    except Exception:
        return None


def _uncertain_result(text, sources, summary):
    return {
        "verdict": "uncertain",
        "confidence": 0.0,
        "summary": summary,
        "sources": sources,
    }


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, ensure_ascii=False),
    }
