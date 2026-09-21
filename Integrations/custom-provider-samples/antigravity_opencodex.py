#!/usr/bin/env python3
import json
import re
import sys
import urllib.request
import urllib.error
from datetime import datetime, timezone

# 目标：查询 OpenCodex 本地接口，并为每个账号的 Gem 和 Cla 各输出一个独立供应商（共 4 个圈）
BASE_URL = "http://127.0.0.1:10100"
API_URL = f"{BASE_URL}/api/oauth/accounts?provider=google-antigravity&quota=1&refresh=1"
SESSION_TOKEN_PATTERN = re.compile(
    r'<meta\s+name=["\']opencodex-session-token["\']\s+content=["\']([^"\']+)["\']',
    re.IGNORECASE,
)

def parse_ms_timestamp(ts_ms):
    if not ts_ms:
        return None
    try:
        dt = datetime.fromtimestamp(ts_ms / 1000.0, tz=timezone.utc)
        return dt.strftime("%Y-%m-%dT%H:%M:%SZ")
    except Exception:
        return None

def request(url, accept):
    req = urllib.request.Request(url)
    req.add_header("Accept", accept)
    req.add_header("Cache-Control", "no-cache")
    req.add_header("Pragma", "no-cache")
    req.add_header("User-Agent", "Pulse-Custom-Provider/1.0")
    return req


def fetch_session_token():
    try:
        with urllib.request.urlopen(request(f"{BASE_URL}/", "text/html"), timeout=8) as resp:
            html = resp.read().decode("utf-8")
    except (urllib.error.URLError, UnicodeDecodeError) as error:
        sys.stderr.write(f"Cannot read OpenCodex page: {error}\n")
        return None

    match = SESSION_TOKEN_PATTERN.search(html)
    if not match:
        sys.stderr.write("OpenCodex session-token meta tag was not found.\n")
        return None
    return match.group(1)


def fetch_upstream(session_token):
    req = request(API_URL, "*/*")
    req.add_header("x-opencodex-api-key", session_token)
    req.add_header("x-opencodex-gui-origin", BASE_URL)

    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            data = resp.read()
            return json.loads(data.decode("utf-8"))
    except (urllib.error.URLError, json.JSONDecodeError, UnicodeDecodeError) as error:
        sys.stderr.write(f"Cannot read Antigravity quotas: {error}\n")
        return None

def main():
    session_token = fetch_session_token()
    if not session_token:
        sys.exit(1)

    data = fetch_upstream(session_token)
    if not data or "accounts" not in data:
        sys.exit(1)

    accounts = data.get("accounts", [])
    output_providers = []

    for acc in accounts:
        email = acc.get("email") or acc.get("id") or "account"
        # 简化邮箱前缀显示，如 l***d
        email_prefix = email.split("@")[0]
        custom_windows = (acc.get("quota") or {}).get("customWindows") or []

        # 区分 Gem (Gemini) 和 Cla (Claude)
        gem_raw = [w for w in custom_windows if w.get("label", "").startswith("Gem")]
        cla_raw = [w for w in custom_windows if w.get("label", "").startswith("Cla")]

        # 1. 构建 Gemini 圈 (包含 5h 与 Weekly 两个窗口)
        gem_windows = []
        for w in gem_raw:
            label = w.get("label", "")
            is_weekly = "weekly" in label.lower()
            fraction = min(max(float(w.get("percent", 0.0)) / 100.0, 0.0), 1.0)
            resets_at = parse_ms_timestamp(w.get("resetAt"))
            gem_windows.append({
                "id": "weekly" if is_weekly else "fiveHour",
                "kind": "weekly" if is_weekly else "fiveHour",
                "scope": "Gemini",
                "usedFraction": fraction,
                "resetsAt": resets_at,
                "windowSeconds": 604800 if is_weekly else 18000,
                "isExhausted": fraction >= 1.0
            })

        # 2. 构建 Claude 圈 (包含 5h 与 Weekly 两个窗口)
        cla_windows = []
        for w in cla_raw:
            label = w.get("label", "")
            is_weekly = "weekly" in label.lower()
            fraction = min(max(float(w.get("percent", 0.0)) / 100.0, 0.0), 1.0)
            resets_at = parse_ms_timestamp(w.get("resetAt"))
            cla_windows.append({
                "id": "weekly" if is_weekly else "fiveHour",
                "kind": "weekly" if is_weekly else "fiveHour",
                "scope": "Claude & GPT",
                "usedFraction": fraction,
                "resetsAt": resets_at,
                "windowSeconds": 604800 if is_weekly else 18000,
                "isExhausted": fraction >= 1.0
            })

        if gem_windows:
            output_providers.append({
                "id": f"{acc.get('id', '')}_gem",
                "displayName": f"{email_prefix} · Gem",
                "icon": "gemini",
                "plan": "Google Antigravity",
                "windows": gem_windows
            })

        if cla_windows:
            output_providers.append({
                "id": f"{acc.get('id', '')}_cla",
                "displayName": f"{email_prefix} · Cla",
                "icon": "claude",
                "plan": "Google Antigravity",
                "windows": cla_windows
            })

    result = {
        "providers": output_providers
    }

    json.dump(result, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")

if __name__ == "__main__":
    main()
