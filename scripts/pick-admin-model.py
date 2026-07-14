#!/usr/bin/env python3
"""Pick the highest-quality remote Ollama model that fits a T4 (16GB) reasonably.

Budget (conservative for chat + tool use + KV cache):
  - On-disk blob <= ~10 GB (Q4 12–15B class)
  - Prefer 12–15B instruct models; then 9–12B; then 7–9B
  - Prefer coding/instruct/tool tags; skip embeddings and pure base weights
"""

from __future__ import annotations

import json
import re
import sys
import urllib.request

MAX_BLOB_BYTES = 10 * 10**9


def parse_param_b(details: dict, name: str) -> float | None:
    ps = (details or {}).get("parameter_size") or ""
    m = re.search(r"([\d.]+)\s*B", str(ps), re.I)
    if m:
        return float(m.group(1))
    m = re.search(r"(\d+(?:\.\d+)?)\s*b\b", name, re.I)
    if m:
        return float(m.group(1))
    # e.g. gemma4:e4b effective size from blob
    return None


def is_embed(name: str) -> bool:
    return bool(
        re.search(
            r"embed|arctic-embed|bge-|nomic-embed|mxbai|qwen3-embedding",
            name,
            re.I,
        )
    )


def is_base_not_instruct(name: str) -> bool:
    if re.search(r"instruct|it-q|tools|chat", name, re.I):
        return False
    return bool(re.search(r":base\b|-base-|base-q", name, re.I))


def score_model(m: dict) -> float:
    name = m.get("name") or ""
    details = m.get("details") or {}
    size = int(m.get("size") or 0)

    if size <= 0 or size > MAX_BLOB_BYTES:
        return -1e9
    if is_embed(name):
        return -1e9
    if re.search(r"stable-diffusion|flux-prompt|nsfw", name, re.I):
        return -1e9

    score = 0.0
    param_b = parse_param_b(details, name)
    gb = size / 1e9

    # Quality: larger models in the T4-safe band win
    if param_b is not None:
        if 12.0 <= param_b <= 15.5:
            score += 200 + param_b * 2  # top tier for T4
        elif 9.0 <= param_b < 12.0:
            score += 140 + param_b * 2
        elif 7.0 <= param_b < 9.0:
            score += 90 + param_b
        elif 4.0 <= param_b < 7.0:
            score += 40 + param_b
        elif param_b > 15.5:
            # only if blob still under budget — often too slow/tight on T4
            score += 30 - (param_b - 15.5) * 3
        else:
            score += 10 + param_b
    else:
        # Infer from blob size
        if 7.5 <= gb <= 9.5:
            score += 180 + gb
        elif 5.5 <= gb < 7.5:
            score += 120 + gb
        elif 3.5 <= gb < 5.5:
            score += 70 + gb
        else:
            score += gb

    # Family / task fit — prefer modern instruct models for agent tool use
    if re.search(r"qwen2\.5-coder:", name, re.I) and not is_base_not_instruct(name):
        score += 45
    elif re.search(r"qwen2\.5:", name, re.I):
        score += 42  # strong general+coding instruct family
    elif re.search(r"deepseek-coder", name, re.I):
        score += 30
    elif re.search(r"nemotron.*tools|tools", name, re.I):
        score += 28
    elif re.search(r"qwen3|hermes|gemma3|llama3\.1|mistral", name, re.I):
        score += 18
    elif re.search(r"codellama|coder", name, re.I):
        score += 8  # older code models
    if re.search(r"instruct|it-q", name, re.I):
        score += 12
    if is_base_not_instruct(name):
        score -= 100

    quant = (details.get("quantization_level") or "").upper()
    if "Q4" in quant or "Q5" in quant:
        score += 8
    if "Q8" in quant:
        score -= 15  # heavier VRAM for same param count
    if "F16" in quant:
        score -= 40

    if ":latest" in name:
        score -= 0.5

    return score


def pick(models: list[dict]) -> dict | None:
    ranked = sorted(
        ((score_model(m), m) for m in models),
        key=lambda t: t[0],
        reverse=True,
    )
    ranked = [(s, m) for s, m in ranked if s > -1e8]
    return ranked[0][1] if ranked else None


def main() -> int:
    url = (sys.argv[1] if len(sys.argv) > 1 else "http://192.168.200.120:11434").rstrip(
        "/"
    )
    tags_url = f"{url}/api/tags"
    try:
        with urllib.request.urlopen(tags_url, timeout=15) as resp:
            data = json.loads(resp.read().decode())
    except Exception as e:
        print(f"error: cannot list models at {tags_url}: {e}", file=sys.stderr)
        return 1

    models = data.get("models") or []
    if not models:
        print("error: no models on server", file=sys.stderr)
        return 1

    best = pick(models)
    if not best:
        print("error: no model fits T4 budget", file=sys.stderr)
        return 1

    details = best.get("details") or {}
    print(best["name"])
    print(
        f"# pick: {best['name']}  size={best.get('size', 0)/1e9:.1f}G  "
        f"params={details.get('parameter_size', '?')}  "
        f"quant={details.get('quantization_level', '?')}  "
        f"score={score_model(best):.1f}",
        file=sys.stderr,
    )
    if "--rank" in sys.argv:
        for s, m in sorted(
            ((score_model(x), x) for x in models), key=lambda t: -t[0]
        )[:12]:
            if s <= -1e8:
                continue
            print(f"  {s:7.1f}  {m.get('size', 0)/1e9:5.1f}G  {m['name']}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
