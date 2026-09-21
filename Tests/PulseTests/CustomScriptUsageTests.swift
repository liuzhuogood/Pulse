import Foundation
import Testing
@testable import Pulse

struct CustomScriptUsageTests {
    @Test func decodesValidPayloadAndMapsWindows() {
        let json = """
        {
            "plan": "Pro Plan",
            "creditBalance": "$42.00",
            "windows": [
                {
                    "id": "short-window",
                    "kind": "fiveHour",
                    "scope": "claude-3-7-sonnet",
                    "usedFraction": 0.45,
                    "resetsAt": "2026-09-20T18:00:00Z",
                    "windowSeconds": 18000,
                    "isExhausted": false
                },
                {
                    "id": "balance-window",
                    "kind": "balance",
                    "usedFraction": 0.10,
                    "windowSeconds": 0
                }
            ]
        }
        """

        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(CustomUsagePayload.self, from: data) else {
            Issue.record("Failed to decode valid JSON payload")
            return
        }

        #expect(payload.plan == "Pro Plan")
        #expect(payload.creditBalance == "$42.00")
        #expect(payload.windows.count == 2)

        let windows = payload.windows.compactMap { $0.toUsageWindow() }
        #expect(windows.count == 2)

        let first = windows[0]
        #expect(first.id == "short-window")
        #expect(first.kind == .fiveHour)
        #expect(first.scope == "claude-3-7-sonnet")
        #expect(first.usedFraction == 0.45)
        #expect(first.windowSeconds == 18000)
        #expect(first.resetsAt != nil)
        #expect(!first.isExhausted)

        let second = windows[1]
        #expect(second.id == "balance-window")
        #expect(second.kind == .balance)
        #expect(second.usedFraction == 0.10)
    }

    @Test func handlesMissingScriptPath() async {
        let service = CustomScriptUsageService(scriptPath: nil)
        let usage = await service.fetch()
        guard case .unavailable(let reason) = usage.state else {
            Issue.record("Expected unavailable state for missing script path")
            return
        }
        #expect(reason == .customScriptMissing)
    }

    @Test func handlesNonexistentScriptPath() async {
        let service = CustomScriptUsageService(scriptPath: "/path/to/nonexistent/script.sh")
        let usage = await service.fetch()
        guard case .unavailable(let reason) = usage.state else {
            Issue.record("Expected unavailable state for nonexistent script")
            return
        }
        #expect(reason == .customScriptMissing)
    }

    @Test func executesLocalScriptSuccessfully() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let scriptURL = tempDir.appendingPathComponent("pulse_test_script_\(UUID().uuidString).sh")
        let scriptContent = """
        #!/bin/sh
        cat << 'EOF'
        {
            "plan": "Custom Plan",
            "windows": [
                {
                    "id": "daily-usage",
                    "kind": "daily",
                    "usedFraction": 0.8
                }
            ]
        }
        EOF
        """
        try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let service = CustomScriptUsageService(scriptPath: scriptURL.path)
        let usage = await service.fetch()

        #expect(usage.state == .live)
        #expect(usage.account.provider == .custom)
        #expect(usage.plan == "Custom Plan")
        #expect(usage.windows.count == 1)
        #expect(usage.windows.first?.kind == .daily)
        #expect(usage.windows.first?.usedFraction == 0.8)
    }
}

import Foundation
import Testing
@testable import Pulse

struct CustomScriptSampleTests {
    @Test func executesBashSampleSuccessfully() async throws {
        let samplePath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Integrations/custom-provider-samples/custom_usage_bash.sh").path

        let service = CustomScriptUsageService(scriptPath: samplePath)
        let usage = await service.fetch()

        #expect(usage.state == .live)
        #expect(usage.account.provider == .custom)
        #expect(usage.plan == "Team Pro (Bash)")
        #expect(usage.windows.count == 3)
        #expect(usage.windows.first?.kind == .fiveHour)
        #expect(usage.windows.first?.usedFraction == 0.42)
    }

    @Test func executesPythonSampleSuccessfully() async throws {
        let samplePath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Integrations/custom-provider-samples/custom_usage_python.py").path

        let service = CustomScriptUsageService(scriptPath: samplePath)
        let usage = await service.fetch()

        #expect(usage.state == .live)
        #expect(usage.account.provider == .custom)
        #expect(usage.plan == "Enterprise VIP (Python3)")
        #expect(usage.windows.count == 3)
        #expect(usage.windows.first?.usedFraction == 0.58)
    }
}

import Foundation
import Testing
@testable import Pulse

struct CustomScriptMultiProviderTests {
    @Test func decodesMultiProviderObjectFormat() {
        let json = """
        {
          "providers": [
            {
              "id": "my-claude",
              "displayName": "Claude Internal",
              "plan": "Pro",
              "creditBalance": "$50.00",
              "windows": [
                {
                  "id": "5h",
                  "kind": "fiveHour",
                  "usedFraction": 0.35,
                  "resetsAt": "2026-09-21T18:00:00Z"
                }
              ]
            },
            {
              "id": "my-deepseek",
              "displayName": "DeepSeek Private",
              "creditBalance": "¥128.00",
              "windows": [
                {
                  "id": "balance",
                  "kind": "balance",
                  "usedFraction": 0.12
                }
              ]
            }
          ]
        }
        """

        guard let data = json.data(using: .utf8) else {
            Issue.record("Failed to create data")
            return
        }

        // Test decoding via JSONDecoder
        let multi = try? JSONDecoder().decode(MultiCustomUsagePayload.self, from: data)
        #expect(multi != nil)
        #expect(multi?.providers.count == 2)

        let first = multi?.providers[0]
        #expect(first?.id == "my-claude")
        #expect(first?.displayName == "Claude Internal")
        #expect(first?.windows.count == 1)

        let second = multi?.providers[1]
        #expect(second?.id == "my-deepseek")
        #expect(second?.displayName == "DeepSeek Private")
        #expect(second?.windows.count == 1)
    }

    @Test func decodesDirectArrayFormat() {
        let json = """
        [
          {
            "id": "prov1",
            "displayName": "Provider 1",
            "windows": [
              {
                "id": "w1",
                "kind": "daily",
                "usedFraction": 0.5
              }
            ]
          }
        ]
        """
        guard let data = json.data(using: .utf8) else {
            Issue.record("Failed to create data")
            return
        }
        let list = try? JSONDecoder().decode([CustomProviderItem].self, from: data)
        #expect(list != nil)
        #expect(list?.count == 1)
        #expect(list?.first?.id == "prov1")
        #expect(list?.first?.windows.first?.usedFraction == 0.5)
    }
}

import Foundation
import Testing
@testable import Pulse

struct MultiProviderSampleScriptTests {
    @Test func executesMultiProviderSampleFile() async throws {
        let samplePath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Integrations/custom-provider-samples/multi_provider_sample.py").path

        let service = CustomScriptUsageService(scriptPath: samplePath)
        let usage = await service.fetch()

        #expect(usage.state == .live)
        #expect(usage.windows.count == 3)
        // Check merged plan & balance
        #expect(usage.plan == "Team Pro")
        #expect(usage.creditBalance?.contains("$45.00") == true)
        #expect(usage.creditBalance?.contains("¥320.00") == true)
        // Check window scopes carry provider names
        #expect(usage.windows[0].scope == "Claude 内部网关")
        #expect(usage.windows[1].scope?.contains("Claude 内部网关") == true)
        #expect(usage.windows[2].scope?.contains("DeepSeek 私有云") == true)
    }
}
