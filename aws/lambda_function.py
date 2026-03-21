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

        # Step 1: Extract search query via OpenAI
        query = _extract_search_query(text)

        # Step 2: Web search via Serper
        sources = _web_search(query)

        # Step 3: Classify via OpenAI
        result = _classify_news(text, sources)

        return _response(200, result)

    except Exception as e:
        return _response(500, {"error": str(e)})


# ---------------------------------------------------------------------------
# 1. Extract search query
# ---------------------------------------------------------------------------

def _extract_search_query(text):
    truncated = text[:1000]

    prompt = (
        "From the following text, extract the single most important factual "
        "claim and turn it into a concise Google search query (Vietnamese or "
        "English, matching the text language). Return ONLY the search query, "
        "nothing else.\n\nTEXT:\n" + truncated
    )

    try:
        content = _openai_chat(
            messages=[
                {
                    "role": "system",
                    "content": (
                        "You extract search queries from text. "
                        "Return ONLY the query string, no quotes, no explanation."
                    ),
                },
                {"role": "user", "content": prompt},
            ],
            temperature=0.0,
            max_tokens=100,
        )

        query = content.strip().strip("\"'")
        if query:
            return query
    except Exception:
        pass

    # Fallback: longest line > 20 chars
    lines = [l for l in text.split("\n") if len(l.strip()) > 20]
    if not lines:
        return text[:100]
    longest = max(lines, key=len)
    return longest[:100]


# ---------------------------------------------------------------------------
# 2. Web search via Serper.dev
# ---------------------------------------------------------------------------

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

CLAIM:
{truncated}

TODAY'S WEB SEARCH RESULTS:
{source_summary}

{{"verdict":"real|fake|uncertain","confidence":0.0-1.0,"summary":"1-2 sentence Vietnamese explanation based on sources"}}"""

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

        confidence = min(max(float(parsed.get("confidence", 0)), 0.0), 1.0)
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
    """Call OpenAI API (gpt-4o-mini — fast, cheap, reliable from AWS)."""
    body = {
        "model": "gpt-4o-mini",
        "temperature": temperature,
        "max_tokens": max_tokens,
        "messages": messages,
    }
    if json_mode:
        body["response_format"] = {"type": "json_object"}

    req = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=json.dumps(body).encode(),
        headers={
            "Authorization": f"Bearer {OPENAI_API_KEY}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=45) as resp:
        data = json.loads(resp.read())

    return (
        data.get("choices", [{}])[0]
        .get("message", {})
        .get("content", "")
    )


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
