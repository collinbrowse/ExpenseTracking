import Foundation
import CashFlowKit

public struct SimpleFINClient: Sendable {
    /// Bridge hard-caps `/accounts` at 90 days per request (≤45 is recommended; advisories are filtered).
    public static let maxAccountsRangeDays = 90
    /// Bridge guidance: overlap windows so boundary txs are not missed when ranges are capped.
    public static let windowOverlapDays = 5

    private let http: any HTTPClient

    public init(http: any HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    /// Claims a setup token (base64-encoded claim URL) and returns the Access URL string.
    public func claimAccessURL(setupToken: String) async throws -> String {
        let trimmed = setupToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let claimURL = try? decodeClaimURL(from: trimmed) else {
            throw CashFlowError.decoding(message: "Invalid SimpleFIN setup token")
        }

        var request = URLRequest(url: claimURL)
        request.httpMethod = "POST"
        // Bridge examples require an explicit empty body + Content-Length: 0.
        request.httpBody = Data()
        request.setValue("0", forHTTPHeaderField: "Content-Length")
        request.setValue("text/plain", forHTTPHeaderField: "Accept")

        let (data, response) = try await http.data(for: request)

        switch response.statusCode {
        case 200:
            guard let accessURL = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !accessURL.isEmpty
            else {
                throw CashFlowError.decoding(message: "Empty Access URL")
            }
            return accessURL
        case 403:
            throw CashFlowError.unauthorized
        case 402:
            throw CashFlowError.paymentRequired
        default:
            throw CashFlowError.transport(
                message: httpErrorMessage(
                    action: "Claiming setup token",
                    statusCode: response.statusCode,
                    body: data
                )
            )
        }
    }

    public func fetchInfo(accessURL: String) async throws -> [String] {
        let root = try rootURL(from: accessURL)
        let infoURL = root.appending(path: "info")
        var request = URLRequest(url: infoURL)
        try applyBasicAuth(from: accessURL, to: &request)
        let (data, response) = try await http.data(for: request)
        try throwForStatus(response.statusCode, action: "Checking connection", body: data)
        let dto = try JSONDecoder().decode(SimpleFINInfoDTO.self, from: data)
        return dto.versions
    }

    /// Result of a windowed `/accounts` fetch, including empty-window trailing count for backfill stop.
    public struct WindowedFetchResult: Sendable {
        public let payload: RemoteSyncPayload
        public let windowsCompleted: Int
        public let consecutiveEmptyTrailing: Int
        public let fetchedStart: Date
        public let fetchedEnd: Date

        public init(
            payload: RemoteSyncPayload,
            windowsCompleted: Int,
            consecutiveEmptyTrailing: Int,
            fetchedStart: Date,
            fetchedEnd: Date
        ) {
            self.payload = payload
            self.windowsCompleted = windowsCompleted
            self.consecutiveEmptyTrailing = consecutiveEmptyTrailing
            self.fetchedStart = fetchedStart
            self.fetchedEnd = fetchedEnd
        }
    }

    public func fetchAccounts(
        accessURL: String,
        startDate: Date?,
        endDate: Date?,
        onWindowProgress: (@Sendable (_ completed: Int, _ total: Int) -> Void)? = nil
    ) async throws -> RemoteSyncPayload {
        try await fetchAccountsWindowed(
            accessURL: accessURL,
            startDate: startDate,
            endDate: endDate,
            maxWindows: nil,
            stopAfterConsecutiveEmpty: nil,
            onWindowProgress: onWindowProgress
        ).payload
    }

    public func fetchAccountsWindowed(
        accessURL: String,
        startDate: Date?,
        endDate: Date?,
        maxWindows: Int?,
        stopAfterConsecutiveEmpty: Int?,
        onWindowProgress: (@Sendable (_ completed: Int, _ total: Int) -> Void)? = nil
    ) async throws -> WindowedFetchResult {
        let resolvedEnd = endDate ?? .now
        let resolvedStart = startDate
            ?? Calendar.current.date(byAdding: .day, value: -Self.maxAccountsRangeDays, to: resolvedEnd)
            ?? resolvedEnd

        var windows = Self.dateWindows(
            from: resolvedStart,
            to: resolvedEnd,
            maxDays: Self.maxAccountsRangeDays,
            overlapDays: Self.windowOverlapDays
        )
        // Walk newest → oldest so consecutive-empty stop detects bank retention cliff.
        windows.reverse()
        if let maxWindows, maxWindows > 0, windows.count > maxWindows {
            windows = Array(windows.prefix(maxWindows))
        }

        onWindowProgress?(0, windows.count)
        var payloads: [RemoteSyncPayload] = []
        payloads.reserveCapacity(windows.count)
        var consecutiveEmpty = 0
        var completed = 0
        for window in windows {
            let payload = try await fetchAccountsWindow(
                accessURL: accessURL,
                startDate: window.lowerBound,
                endDate: window.upperBound
            )
            payloads.append(payload)
            completed += 1
            onWindowProgress?(completed, windows.count)
            let txCount = payload.accounts.reduce(0) { $0 + $1.transactions.count }
            if txCount == 0 {
                consecutiveEmpty += 1
                if let stopAfterConsecutiveEmpty,
                   stopAfterConsecutiveEmpty > 0,
                   consecutiveEmpty >= stopAfterConsecutiveEmpty
                {
                    break
                }
            } else {
                consecutiveEmpty = 0
            }
        }

        let fetchedStart = payloads.isEmpty
            ? resolvedStart
            : (windows.prefix(completed).map(\.lowerBound).min() ?? resolvedStart)
        let fetchedEnd = payloads.isEmpty
            ? resolvedEnd
            : (windows.prefix(completed).map(\.upperBound).max() ?? resolvedEnd)

        return WindowedFetchResult(
            payload: Self.mergePayloads(payloads),
            windowsCompleted: completed,
            consecutiveEmptyTrailing: consecutiveEmpty,
            fetchedStart: fetchedStart,
            fetchedEnd: fetchedEnd
        )
    }

    private func fetchAccountsWindow(
        accessURL: String,
        startDate: Date,
        endDate: Date
    ) async throws -> RemoteSyncPayload {
        let root = try rootURL(from: accessURL)
        var components = URLComponents(
            url: root.appending(path: "accounts"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "start-date", value: String(Int(startDate.timeIntervalSince1970))),
            URLQueryItem(name: "end-date", value: String(Int(endDate.timeIntervalSince1970))),
            URLQueryItem(name: "pending", value: "1"),
            URLQueryItem(name: "version", value: "2"),
        ]
        guard let url = components?.url else {
            throw CashFlowError.transport(message: "Invalid accounts URL")
        }

        var request = URLRequest(url: url)
        try applyBasicAuth(from: accessURL, to: &request)
        let (data, response) = try await http.data(for: request)
        try throwForStatus(response.statusCode, action: "Syncing accounts", body: data)

        let dto = try JSONDecoder().decode(SimpleFINAccountSetDTO.self, from: data)
        let messages = dto.displayMessages.map(sanitize)
        let connectionsByID = Dictionary(
            uniqueKeysWithValues: (dto.connections ?? []).map { ($0.connID, $0) }
        )
        let mapped = dto.accounts.map { mapAccount($0, connectionsByID: connectionsByID) }
        let accounts = Self.applyingSyncIssues(to: mapped, errors: dto.errlist ?? [])
        return RemoteSyncPayload(accounts: accounts, providerMessages: messages)
    }

    /// Splits `[start, end]` into inclusive windows of at most `maxDays` days,
    /// advancing by `maxDays - overlapDays` so adjacent windows overlap.
    static func dateWindows(
        from start: Date,
        to end: Date,
        maxDays: Int,
        overlapDays: Int = 0,
        calendar: Calendar = .current
    ) -> [ClosedRange<Date>] {
        precondition(maxDays > 0)
        precondition(overlapDays >= 0 && overlapDays < maxDays)
        if end <= start {
            return [start...start]
        }

        let stepDays = maxDays - overlapDays
        var windows: [ClosedRange<Date>] = []
        var cursor = start
        while cursor < end {
            let rawEnd = calendar.date(byAdding: .day, value: maxDays, to: cursor) ?? end
            let windowEnd = min(rawEnd, end)
            windows.append(cursor...windowEnd)
            if windowEnd >= end { break }
            guard let next = calendar.date(byAdding: .day, value: stepDays, to: cursor),
                  next > cursor
            else { break }
            cursor = next
        }
        return windows
    }

    static func mergePayloads(_ payloads: [RemoteSyncPayload]) -> RemoteSyncPayload {
        guard !payloads.isEmpty else {
            return RemoteSyncPayload(accounts: [], providerMessages: [])
        }

        var accountsByID: [String: RemoteAccountSnapshot] = [:]
        var messages: [String] = []

        for payload in payloads {
            messages.append(contentsOf: payload.providerMessages)
            for account in payload.accounts {
                if let existing = accountsByID[account.externalID] {
                    accountsByID[account.externalID] = mergeAccounts(existing, account)
                } else {
                    accountsByID[account.externalID] = account
                }
            }
        }

        return RemoteSyncPayload(
            accounts: Array(accountsByID.values).sorted { $0.externalID < $1.externalID },
            providerMessages: normalizeProviderMessages(messages)
        )
    }

    /// Drop Bridge date-window advisories (we already chunk) and dedupe the rest.
    static func normalizeProviderMessages(_ messages: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for message in messages {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !isBenignDateRangeAdvisory(trimmed) else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    static func isBenignDateRangeAdvisory(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("date range exceeds")
            || lower.contains("recommended range")
            || (lower.contains("was capped") && lower.contains("day"))
    }

    private static func mergeAccounts(
        _ lhs: RemoteAccountSnapshot,
        _ rhs: RemoteAccountSnapshot
    ) -> RemoteAccountSnapshot {
        var transactionsByID: [String: RemoteTransactionSnapshot] = [:]
        for transaction in lhs.transactions {
            transactionsByID[transaction.externalID] = transaction
        }
        for transaction in rhs.transactions {
            transactionsByID[transaction.externalID] = transaction
        }

        let preferRHS = rhs.balanceDate >= lhs.balanceDate
        let primary = preferRHS ? rhs : lhs
        let institutionName = Self.preferredInstitutionName(lhs.institutionName, rhs.institutionName)
        return RemoteAccountSnapshot(
            externalID: primary.externalID,
            name: primary.name,
            institutionName: institutionName,
            currencyCode: primary.currencyCode,
            balance: primary.balance,
            balanceDate: primary.balanceDate,
            transactions: Array(transactionsByID.values),
            connectionExternalID: primary.connectionExternalID ?? lhs.connectionExternalID ?? rhs.connectionExternalID,
            syncIssue: mergeSyncIssues(lhs.syncIssue, rhs.syncIssue)
        )
    }

    /// Keeps any issue seen across chunked windows (do not clear just because one window was clean).
    static func mergeSyncIssues(_ lhs: String?, _ rhs: String?) -> String? {
        let parts = [lhs, rhs]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        var seen = Set<String>()
        var unique: [String] = []
        for part in parts {
            let key = part.lowercased()
            guard seen.insert(key).inserted else { continue }
            unique.append(part)
        }
        return unique.joined(separator: " ")
    }

    /// Attaches Bridge `errlist` entries to accounts by `account_id`, then `conn_id`, then globally.
    static func applyingSyncIssues(
        to accounts: [RemoteAccountSnapshot],
        errors: [SimpleFINErrorDTO]
    ) -> [RemoteAccountSnapshot] {
        guard !errors.isEmpty else {
            return accounts.map {
                RemoteAccountSnapshot(
                    externalID: $0.externalID,
                    name: $0.name,
                    institutionName: $0.institutionName,
                    currencyCode: $0.currencyCode,
                    balance: $0.balance,
                    balanceDate: $0.balanceDate,
                    transactions: $0.transactions,
                    connectionExternalID: $0.connectionExternalID,
                    syncIssue: nil
                )
            }
        }

        return accounts.map { account in
            let messages = relevantSyncMessages(for: account, errors: errors)
            return RemoteAccountSnapshot(
                externalID: account.externalID,
                name: account.name,
                institutionName: account.institutionName,
                currencyCode: account.currencyCode,
                balance: account.balance,
                balanceDate: account.balanceDate,
                transactions: account.transactions,
                connectionExternalID: account.connectionExternalID,
                syncIssue: messages.isEmpty ? nil : messages.joined(separator: " ")
            )
        }
    }

    private static func relevantSyncMessages(
        for account: RemoteAccountSnapshot,
        errors: [SimpleFINErrorDTO]
    ) -> [String] {
        var seen = Set<String>()
        var messages: [String] = []
        for error in errors {
            let message = error.msg.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty, !isBenignDateRangeAdvisory(message) else { continue }

            let accountID = error.accountID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let connID = error.connID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            let matches: Bool
            if !accountID.isEmpty {
                matches = accountID == account.externalID
                    || messageMatchesAccountIdentity(
                        message,
                        name: account.name,
                        institutionName: account.institutionName
                    )
            } else if !connID.isEmpty {
                matches = connID == account.connectionExternalID
                    || messageMatchesAccountIdentity(
                        message,
                        name: account.name,
                        institutionName: account.institutionName
                    )
            } else {
                // Unscoped provider errors apply to every account in the payload.
                matches = true
            }
            guard matches else { continue }

            let key = message.lowercased()
            guard seen.insert(key).inserted else { continue }
            messages.append(message)
        }
        return messages
    }

    /// Bridge errlist copy often names the FI/account even when ids are missing or stale.
    static func messageMatchesAccountIdentity(
        _ message: String,
        name: String,
        institutionName: String
    ) -> Bool {
        let haystack = message.lowercased()
        let candidates = [name, institutionName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 }
        for candidate in candidates {
            if haystack.contains(candidate.lowercased()) {
                return true
            }
        }
        return false
    }

    private func mapAccount(
        _ dto: SimpleFINAccountDTO,
        connectionsByID: [String: SimpleFINConnectionDTO]
    ) -> RemoteAccountSnapshot {
        let connection = dto.connID.flatMap { connectionsByID[$0] }
        let institution = Self.institutionName(
            account: dto,
            connection: connection
        )
        let balance = Decimal(string: dto.balance) ?? 0
        let txs = (dto.transactions ?? []).compactMap { tx -> RemoteTransactionSnapshot? in
            let posted = tx.posted
            let pending = tx.pending ?? (posted == 0)
            guard let amount = Decimal(string: tx.amount) else { return nil }
            let sanitizedDescription = sanitize(tx.description)
            // Pending often arrives with `posted == 0`. Use "now" so list sort/sections
            // stay current; MergeSyncPolicy keeps the first-seen date across re-syncs.
            let postedDate = posted == 0
                ? Date.now
                : Date(timeIntervalSince1970: TimeInterval(posted))
            return RemoteTransactionSnapshot(
                externalID: tx.id,
                amount: amount,
                postedDate: postedDate,
                description: sanitizedDescription,
                isPending: pending,
                suggestedCategoryID: SystemCategory.undefined.id
            )
        }
        return RemoteAccountSnapshot(
            externalID: dto.id,
            name: sanitize(dto.name),
            institutionName: sanitize(institution),
            currencyCode: dto.currency.count == 3 ? dto.currency : "USD",
            balance: balance,
            balanceDate: Date(timeIntervalSince1970: TimeInterval(dto.balanceDate)),
            transactions: txs,
            connectionExternalID: dto.connID
        )
    }

    /// Resolves a bank/institution display name from v2 `connections` (preferred) or legacy `org`.
    static func institutionName(
        account: SimpleFINAccountDTO,
        connection: SimpleFINConnectionDTO?
    ) -> String {
        if let orgName = connection?.orgName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !orgName.isEmpty
        {
            return orgName
        }
        if let connectionName = connection?.name.trimmingCharacters(in: .whitespacesAndNewlines),
           !connectionName.isEmpty
        {
            // Bridge often uses "American Express - Collin" for the connection nickname.
            if let dash = connectionName.range(of: " - ") {
                let institution = String(connectionName[..<dash.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !institution.isEmpty { return institution }
            }
            return connectionName
        }
        if let connName = account.connName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !connName.isEmpty
        {
            if let dash = connName.range(of: " - ") {
                let institution = String(connName[..<dash.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !institution.isEmpty { return institution }
            }
            return connName
        }
        if let orgName = account.org?.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !orgName.isEmpty
        {
            return orgName
        }
        if let domain = account.org?.domain?.trimmingCharacters(in: .whitespacesAndNewlines),
           !domain.isEmpty
        {
            return domain
        }
        if let orgURL = connection?.orgURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           let host = URL(string: orgURL)?.host,
           !host.isEmpty
        {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return "Unknown institution"
    }

    private static func preferredInstitutionName(_ lhs: String, _ rhs: String) -> String {
        let placeholders: Set<String> = ["Institution", "Unknown institution", ""]
        if placeholders.contains(lhs), !placeholders.contains(rhs) { return rhs }
        if placeholders.contains(rhs), !placeholders.contains(lhs) { return lhs }
        return rhs
    }

    private func decodeClaimURL(from setupToken: String) throws -> URL {
        let padded = Self.padBase64(setupToken)
        guard let decoded = Data(base64Encoded: padded, options: .ignoreUnknownCharacters),
              let claimURLString = String(data: decoded, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let claimURL = URL(string: claimURLString),
              claimURL.scheme?.lowercased() == "https"
        else {
            throw CashFlowError.decoding(message: "Invalid SimpleFIN setup token")
        }
        return claimURL
    }

    /// `Data(base64Encoded:)` is strict about padding; Bridge tokens sometimes omit `=`.
    static func padBase64(_ value: String) -> String {
        let remainder = value.count % 4
        guard remainder != 0 else { return value }
        return value + String(repeating: "=", count: 4 - remainder)
    }

    private func rootURL(from accessURL: String) throws -> URL {
        guard var components = URLComponents(string: accessURL) else {
            throw CashFlowError.decoding(message: "Invalid Access URL")
        }
        components.user = nil
        components.password = nil
        guard let url = components.url, url.scheme?.lowercased() == "https" else {
            throw CashFlowError.decoding(message: "Access URL must be HTTPS")
        }
        return url
    }

    private func applyBasicAuth(from accessURL: String, to request: inout URLRequest) throws {
        guard let components = URLComponents(string: accessURL),
              let user = components.user,
              let password = components.password
        else {
            throw CashFlowError.decoding(message: "Access URL missing credentials")
        }
        let raw = "\(user):\(password)"
        let encoded = Data(raw.utf8).base64EncodedString()
        request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
    }

    private func throwForStatus(_ code: Int, action: String, body: Data) throws {
        switch code {
        case 200: return
        case 403: throw CashFlowError.unauthorized
        case 402: throw CashFlowError.paymentRequired
        default:
            if let providerMessages = Self.providerMessages(fromResponseBody: body), !providerMessages.isEmpty {
                throw CashFlowError.providerMessages(providerMessages)
            }
            throw CashFlowError.transport(
                message: httpErrorMessage(action: action, statusCode: code, body: body)
            )
        }
    }

    private func httpErrorMessage(action: String, statusCode: Int, body: Data) -> String {
        let snippet = String(data: body, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let snippet, !snippet.isEmpty, snippet.count <= 180, !snippet.hasPrefix("<") {
            return "\(action) failed (HTTP \(statusCode)): \(snippet)"
        }
        return "\(action) failed (HTTP \(statusCode))."
    }

    /// Prefer SimpleFIN `errlist` / `errors` messages over raw JSON dumps.
    static func providerMessages(fromResponseBody body: Data) -> [String]? {
        guard let dto = try? JSONDecoder().decode(SimpleFINAccountSetDTO.self, from: body) else {
            return nil
        }
        let messages = dto.displayMessages.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        guard !messages.isEmpty else { return nil }
        return messages.map(Self.userFacingProviderMessage)
    }

    static func userFacingProviderMessage(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("no connections available") {
            return """
            SimpleFIN has no bank connections yet. In SimpleFIN Bridge, add a Financial Institution \
            (connect your bank), then come back here and tap Sync Now. You do not need a new setup token.
            """
        }
        return message
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
    }

    private func sanitize(_ string: String) -> String {
        string
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
