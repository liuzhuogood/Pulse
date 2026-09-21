#!/usr/bin/env python3
import json
import sys
from datetime import datetime, timezone

# 读取示例数据并转换
sample_data = {
    "activeAccountId": "88df1f7567f84960ef555db2edbab8a5",
    "accounts": [
        {
            "id": "88df1f7567f84960ef555db2edbab8a5",
            "email": "l***d@gmail.com",
            "active": True,
            "expiresAt": 1789980220553,
            "plan": None,
            "health": { "status": "healthy" },
            "healthLabel": "Healthy",
            "healthSummary": "google-antigravity account-…b8a5: healthy",
            "quotaMode": "probe",
            "quota": {
                "customWindows": [
                    { "label": "Gem", "percent": 18.1729, "resetAt": 1789983028000 },
                    { "label": "Gem (Weekly)", "percent": 30.091613999999993, "resetAt": 1790130496000 },
                    { "label": "Cla", "percent": 0, "resetAt": 1789995069000 },
                    { "label": "Cla (Weekly)", "percent": 41.031589999999994, "resetAt": 1790013003000 }
                ],
                "updatedAt": 1789977069607
            },
            "quotaUnavailable": False
        },
        {
            "id": "35b8596296e010c4b86e996ae6bfd00c",
            "email": "l***0@gmail.com",
            "active": False,
            "expiresAt": 1789979316328,
            "plan": None,
            "health": { "status": "healthy" },
            "healthLabel": "Healthy",
            "healthSummary": "google-antigravity account-…d00c: healthy",
            "quotaMode": "probe",
            "quota": {
                "customWindows": [
                    { "label": "Gem", "percent": 0, "resetAt": 1789995069000 },
                    { "label": "Gem (Weekly)", "percent": 0.12754000000001042, "resetAt": 1790437287000 },
                    { "label": "Cla", "percent": 0, "resetAt": 1789995069000 },
                    { "label": "Cla (Weekly)", "percent": 0, "resetAt": 1790581869000 }
                ],
                "updatedAt": 1789977070166
            },
            "quotaUnavailable": False
        }
    ]
}

def parse_ms_timestamp(ts_ms):
    if not ts_ms:
        return None
    try:
        dt = datetime.fromtimestamp(ts_ms / 1000.0, tz=timezone.utc)
        return dt.strftime("%Y-%m-%dT%H:%M:%SZ")
    except Exception:
        return None

def main():
    accounts = sample_data.get("accounts", [])
    output_providers = []

    for acc in accounts:
        email = acc.get("email") or acc.get("id") or "account"
        email_prefix = email.split("@")[0]
        custom_windows = (acc.get("quota") or {}).get("customWindows") or []

        gem_raw = [w for w in custom_windows if w.get("label", "").startswith("Gem")]
        cla_raw = [w for w in custom_windows if w.get("label", "").startswith("Cla")]

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
                "plan": "Antigravity",
                "windows": gem_windows
            })

        if cla_windows:
            output_providers.append({
                "id": f"{acc.get('id', '')}_cla",
                "displayName": f"{email_prefix} · Cla",
                "plan": "Antigravity",
                "windows": cla_windows
            })

    result = {
        "providers": output_providers
    }

    json.dump(result, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")

if __name__ == "__main__":
    main()

