#!/usr/bin/env bash
set -euo pipefail

# 示例：通过 Bash 脚本获取并输出 Pulse 约定的用量 JSON
# 只要脚本带可执行权限（chmod +x），Pulse 即可直接拉起执行并捕获 stdout

# 动态计算 4 小时后的 ISO 8601 重置时间（适配 macOS date 命令）
RESETS_AT=$(date -u -v+4H "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "+4 hours" "+%Y-%m-%dT%H:%M:%SZ")

cat <<EOF
{
  "plan": "Team Pro (Bash)",
  "creditBalance": "\$18.50",
  "windows": [
    {
      "id": "5h-session",
      "kind": "fiveHour",
      "scope": "claude-3-7-sonnet",
      "usedFraction": 0.42,
      "resetsAt": "${RESETS_AT}",
      "windowSeconds": 18000,
      "isExhausted": false
    },
    {
      "id": "daily-limit",
      "kind": "daily",
      "scope": null,
      "usedFraction": 0.15,
      "windowSeconds": 86400,
      "isExhausted": false
    },
    {
      "id": "account-balance",
      "kind": "balance",
      "scope": null,
      "usedFraction": 0.10,
      "windowSeconds": 0
    }
  ]
}
