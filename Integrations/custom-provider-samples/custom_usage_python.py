#!/usr/bin/env python3
import json
import sys
from datetime import datetime, timezone, timedelta

# 示例：通过 Python3 脚本获取并输出 Pulse 约定的用量 JSON
# 可以在此处执行 requests / urllib 调用内部网关、API 或查询本地配置

def main():
    # 模拟计算 5 小时重置倒计时
    now = datetime.now(timezone.utc)
    resets_at = (now + timedelta(hours=3, minutes=30)).strftime("%Y-%m-%dT%H:%M:%SZ")

    payload = {
        "plan": "Enterprise VIP (Python3)",
        "creditBalance": "¥128.50",
        "windows": [
            {
                "id": "5h-window",
                "kind": "fiveHour",
                "scope": "deepseek-r1",
                "usedFraction": 0.58,  # 已用 58%
                "resetsAt": resets_at,
                "windowSeconds": 18000,
                "isExhausted": False,
            },
            {
                "id": "weekly-allowance",
                "kind": "weekly",
                "scope": None,
                "usedFraction": 0.25,
                "windowSeconds": 604800,
                "isExhausted": False,
            },
            {
                "id": "prepaid-balance",
                "kind": "balance",
                "scope": None,
                "usedFraction": 0.08,
                "windowSeconds": 0,
            },
        ],
    }

    # 必须向 stdout 输出合法 JSON
    json.dump(payload, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")

if __name__ == "__main__":
    main()

