import Foundation

/// Executes a user-specified script to fetch usage data.
///
/// The script is executed in an external process with a 10-second timeout.
/// The script is expected to output a JSON string on stdout matching `CustomUsagePayload`,
/// `MultiCustomUsagePayload` (containing a list of providers), or an array of payloads.
struct CustomScriptUsageService: Sendable {
    let scriptPath: String?

    func fetch(account: AccountKey = AccountKey(.custom)) async -> ProviderUsage {
        guard let rawPath = scriptPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty else {
            return .unavailable(account, reason: .customScriptMissing)
        }

        let resolvedPath = NSString(string: rawPath).expandingTildeInPath
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: resolvedPath) else {
            return .unavailable(account, reason: .customScriptMissing)
        }

        guard fileManager.isExecutableFile(atPath: resolvedPath) else {
            return .unavailable(account, reason: .customScriptNotExecutable)
        }

        let output: Data
        do {
            output = try await runProcess(executablePath: resolvedPath, timeoutSeconds: 10)
        } catch {
            return .unavailable(account, reason: .customScriptFailed)
        }

        // Try decoding multi-provider formats first or single payload
        guard let payload = parsePayload(from: output) else {
            return .unavailable(account, reason: .unreadableReply)
        }

        let windows = payload.windows.compactMap { $0.toUsageWindow() }
        guard !windows.isEmpty else {
            return .unavailable(account, reason: .noLimitsReported)
        }

        return ProviderUsage(
            account: account,
            windows: windows,
            observedAt: Date(),
            state: .live,
            plan: payload.plan,
            creditBalance: payload.creditBalance
        )
    }

    private func parsePayload(from data: Data) -> CustomUsagePayload? {
        let decoder = JSONDecoder()

        // 1. Single CustomUsagePayload
        if let single = try? decoder.decode(CustomUsagePayload.self, from: data), !single.windows.isEmpty {
            return single
        }

        // 2. { "providers": [ ... ] } wrapper
        if let multi = try? decoder.decode(MultiCustomUsagePayload.self, from: data), !multi.providers.isEmpty {
            return mergeProviders(multi.providers)
        }

        // 3. Direct array of providers: [ { "plan": ..., "windows": [...] }, ... ]
        if let list = try? decoder.decode([CustomProviderItem].self, from: data), !list.isEmpty {
            return mergeProviders(list)
        }

        return try? decoder.decode(CustomUsagePayload.self, from: data)
    }

    private func mergeProviders(_ items: [CustomProviderItem]) -> CustomUsagePayload {
        var mergedWindows: [CustomWindowPayload] = []
        var plans: [String] = []
        var balances: [String] = []

        for item in items {
            // A returned provider item is a rail group. Its windows may carry
            // their own model scope, but using that here would merge matching
            // model names from separate accounts into one ring.
            let providerScope = item.displayName ?? item.id ?? item.plan
            if let p = item.plan, !p.isEmpty { plans.append(p) }
            if let b = item.creditBalance, !b.isEmpty { balances.append(b) }

            for w in item.windows {
                let scopedWindow = CustomWindowPayload(
                    id: "\(item.id ?? "prov")_\(w.id)",
                    name: w.name,
                    kind: w.kind,
                    scope: providerScope,
                    usedFraction: w.usedFraction,
                    resetsAt: w.resetsAt,
                    windowSeconds: w.windowSeconds,
                    icon: PresetIcon.validResource(item.icon) ? item.icon : w.icon,
                    isExhausted: w.isExhausted
                )
                mergedWindows.append(scopedWindow)
            }
        }

        let combinedPlan = plans.isEmpty ? nil : plans.joined(separator: " · ")
        let combinedBalance = balances.isEmpty ? nil : balances.joined(separator: " | ")
        return CustomUsagePayload(plan: combinedPlan, creditBalance: combinedBalance, windows: mergedWindows)
    }

    private final class ProcessState: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Data, any Error>?

        init(continuation: CheckedContinuation<Data, any Error>) {
            self.continuation = continuation
        }

        func resume(with result: Result<Data, any Error>) {
            lock.lock()
            defer { lock.unlock() }
            if let cont = continuation {
                continuation = nil
                switch result {
                case .success(let data):
                    cont.resume(returning: data)
                case .failure(let error):
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func runProcess(executablePath: String, timeoutSeconds: Double) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = []

        var env = ProcessInfo.processInfo.environment
        if env["PATH"] == nil {
            env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            let state = ProcessState(continuation: continuation)

            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
            timer.schedule(deadline: .now() + timeoutSeconds)
            timer.setEventHandler {
                if process.isRunning {
                    process.terminate()
                }
                state.resume(with: .failure(NSError(
                    domain: "CustomScriptUsageService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Script execution timed out"]
                )))
            }
            timer.resume()

            process.terminationHandler = { proc in
                timer.cancel()
                let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                if proc.terminationStatus == 0 {
                    state.resume(with: .success(data))
                } else {
                    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let reason = (errMsg?.isEmpty == false) ? errMsg! : "Process exited with code \(proc.terminationStatus)"
                    state.resume(with: .failure(NSError(
                        domain: "CustomScriptUsageService",
                        code: Int(proc.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: reason]
                    )))
                }
            }

            do {
                try process.run()
            } catch {
                timer.cancel()
                state.resume(with: .failure(error))
            }
        }
    }
}

// MARK: - JSON Contract Decodables

struct MultiCustomUsagePayload: Decodable, Sendable {
    let providers: [CustomProviderItem]
}

struct CustomProviderItem: Decodable, Sendable {
    let id: String?
    let displayName: String?
    let icon: String?
    let plan: String?
    let creditBalance: String?
    let windows: [CustomWindowPayload]

    init(
        id: String? = nil,
        displayName: String? = nil,
        icon: String? = nil,
        plan: String? = nil,
        creditBalance: String? = nil,
        windows: [CustomWindowPayload] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.icon = icon
        self.plan = plan
        self.creditBalance = creditBalance
        self.windows = windows
    }
}

struct CustomUsagePayload: Decodable, Sendable {
    let plan: String?
    let creditBalance: String?
    let windows: [CustomWindowPayload]

    init(plan: String? = nil, creditBalance: String? = nil, windows: [CustomWindowPayload] = []) {
        self.plan = plan
        self.creditBalance = creditBalance
        self.windows = windows
    }
}

struct CustomWindowPayload: Decodable, Sendable {
    let id: String
    let name: String?
    let kind: String?
    let scope: String?
    let usedFraction: Double
    let resetsAt: String?
    let windowSeconds: Int?
    /// A name from Pulse's built-in icon set, for example `"gemini"`.
    let icon: String?
    let isExhausted: Bool?

    init(
        id: String,
        name: String? = nil,
        kind: String? = nil,
        scope: String? = nil,
        usedFraction: Double,
        resetsAt: String? = nil,
        windowSeconds: Int? = nil,
        icon: String? = nil,
        isExhausted: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.scope = scope
        self.usedFraction = usedFraction
        self.resetsAt = resetsAt
        self.windowSeconds = windowSeconds
        self.icon = icon
        self.isExhausted = isExhausted
    }

    func toUsageWindow() -> UsageWindow? {
        let mappedKind: UsageWindow.Kind
        switch (kind ?? "").lowercased() {
        case "fivehour", "5hour", "five_hour":
            mappedKind = .fiveHour
        case "weekly", "week":
            mappedKind = .weekly
        case "daily", "day":
            mappedKind = .daily
        case "monthly", "month":
            mappedKind = .monthly
        case "balance":
            mappedKind = .balance
        case "messages":
            mappedKind = .messages
        case "spend":
            mappedKind = .spend
        default:
            if let seconds = windowSeconds, seconds > 0 {
                mappedKind = .other(seconds: seconds)
            } else {
                mappedKind = .fiveHour
            }
        }

        let clampedFraction = min(max(usedFraction, 0), 1.0)
        let resolvedResetsAt = resetsAt.flatMap { CustomScriptUsageService.parseDate($0) }
        let resolvedSeconds = windowSeconds ?? 0
        let effectiveScope = scope ?? name

        return UsageWindow(
            id: id,
            kind: mappedKind,
            scope: effectiveScope,
            usedFraction: clampedFraction,
            windowSeconds: resolvedSeconds,
            resetsAt: resolvedResetsAt,
            iconResource: PresetIcon.validResource(icon) ? icon : nil,
            isExhausted: isExhausted ?? (clampedFraction >= 1.0)
        )
    }
}

extension CustomScriptUsageService {
    static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
