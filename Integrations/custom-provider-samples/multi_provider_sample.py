#!/usr/bin/env python3
import json
import sys
from datetime import datetime, timezone, timedelta

# 示例：一个脚本同时返回多个供应商/平台的用量
def main():
    now = datetime.now(timezone.utc)
    resets_5h = (now + timedelta(hours=4, minutes=15)).strftime("%Y-%m-%dT%H:%M:%SZ")

    payload = {
        "providers": [
            {
                "id": "claude-gateway",
                "displayName": "Claude 内部网关",
                "plan": "Team Pro",
                "creditBalance": "$45.00",
                "windows": [
                    {
                        "id": "5h",
                        "kind": "fiveHour",
                        "scope": "claude-3-7-sonnet",
                        "usedFraction": 0.38,
                        "resetsAt": resets_5h,
                        "windowSeconds": 18000,
                        "isExhausted": False
                    },
                    {
                        "id": "weekly",
                        "kind": "weekly",
                        "usedFraction": 0.18,
                        "windowSeconds": 604800,
                        "isExhausted": False
                    }
                ]
            },
            {
                "id": "deepseek-local",
                "displayName": "DeepSeek 私有云",
                "creditBalance": "¥320.00",
                "windows": [
                    {
                        "id": "balance",
                        "kind": "balance",
                        "usedFraction": 0.15,
                        "windowSeconds": 0
                    }
                ]
            }
        ]
    }

    json.dump(payload, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")

if __name__ == "__main__":
    main()

