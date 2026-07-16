import Foundation
import CashFlowKit

public struct SimpleFINClient: Sendable {
    private let http: any HTTPClient

    public init(http: any HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    /// Claims a setup token (base64-encoded claim URL) and returns the Access URL string.
    public func claimAccessURL(setupToken: String) async throws -> String {
        let trimmed = setupToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decoded = Data(base64Encoded: trimmed),
              let claimURLString = String(data: decoded, encoding: .utf8),
              let claimURL = URL(string: claimURLString),
              claimURL.scheme?.lowercased() == "https"
        else {
            throw CashFlowError.decoding(message: "Invalid SimpleFIN setup token")
        }

        var request = URLRequest(url: claimURL)
        request.httpMethod = "POST"
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
            throw CashFlowError.transport(message: "Claim failed (\(response.statusCode))")
        }
    }

    public func fetchInfo(accessURL: String) async throws -> [String] {
        let root = try rootURL(from: accessURL)
        let infoURL = root.appending(path: "info")
        var request = URLRequest(url: infoURL)
        try applyBasicAuth(from: accessURL, to: &request)
        let (data, response) = try await http.data(for: request)
        try throwForStatus(response.statusCode)
        let dto = try JSONDecoder().decode(SimpleFINInfoDTO.self, from: data)
        return dto.versions
    }

    public func fetchAccounts(
        accessURL: String,
        startDate: Date?,
        endDate: Date?
    ) async throws -> RemoteSyncPayload {
        let root = try rootURL(from: accessURL)
        var components = URLComponents(
            url: root.appending(path: "accounts"),
            resolvingAgainstBaseURL: false
        )
        var items: [URLQueryItem] = []
        if let startDate {
            items.append(URLQueryItem(
                name: "start-date",
                value: String(Int(startDate.timeIntervalSince1970))
            ))
        }
        if let endDate {
            items.append(URLQueryItem(
                name: "end-date",
                value: String(Int(endDate.timeIntervalSince1970))
            ))
        }
        components?.queryItems = items.isEmpty ? nil : items
        guard let url = components?.url else {
            throw CashFlowError.transport(message: "Invalid accounts URL")
        }

        var request = URLRequest(url: url)
        try applyBasicAuth(from: accessURL, to: &request)
        let (data, response) = try await http.data(for: request)
        try throwForStatus(response.statusCode)

        let dto = try JSONDecoder().decode(SimpleFINAccountSetDTO.self, from: data)
        let messages = (dto.errors ?? []).map(sanitize)
        let accounts = dto.accounts.map(mapAccount)
        return RemoteSyncPayload(accounts: accounts, providerMessages: messages)
    }

    private func mapAccount(_ dto: SimpleFINAccountDTO) -> RemoteAccountSnapshot {
        let institution = dto.org?.name ?? dto.org?.domain ?? "Institution"
        let balance = Decimal(string: dto.balance) ?? 0
        let txs = (dto.transactions ?? []).compactMap { tx -> RemoteTransactionSnapshot? in
            let posted = tx.posted
            let pending = tx.pending ?? (posted == 0)
            guard let amount = Decimal(string: tx.amount) else { return nil }
            let category = Self.suggestCategory(description: tx.description, amount: amount)
            return RemoteTransactionSnapshot(
                externalID: tx.id,
                amount: amount,
                postedDate: Date(timeIntervalSince1970: TimeInterval(posted)),
                description: sanitize(tx.description),
                isPending: pending,
                suggestedCategoryID: category
            )
        }
        return RemoteAccountSnapshot(
            externalID: dto.id,
            name: sanitize(dto.name),
            institutionName: sanitize(institution),
            currencyCode: dto.currency.count == 3 ? dto.currency : "USD",
            balance: balance,
            balanceDate: Date(timeIntervalSince1970: TimeInterval(dto.balanceDate)),
            transactions: txs
        )
    }

    static func suggestCategory(description: String, amount: Decimal) -> CategoryID {
        let lower = description.lowercased()
        if amount > 0 {
            if lower.contains("payroll") || lower.contains("direct deposit") || lower.contains("salary") {
                return SystemCategory.income.id
            }
        }
        if lower.contains("transfer") || lower.contains("payment thank you") {
            return SystemCategory.transfer.id
        }
        if lower.contains("credit card payment") || lower.contains("autopay") {
            return SystemCategory.creditCardPayment.id
        }
        if lower.contains("grocery") || lower.contains("whole foods") || lower.contains("trader joe") {
            return SystemCategory.groceries.id
        }
        if lower.contains("uber") || lower.contains("lyft") || lower.contains("shell") {
            return SystemCategory.transport.id
        }
        if lower.contains("netflix") || lower.contains("spotify") {
            return SystemCategory.entertainment.id
        }
        if amount > 0 {
            return SystemCategory.income.id
        }
        return SystemCategory.other.id
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

    private func throwForStatus(_ code: Int) throws {
        switch code {
        case 200: return
        case 403: throw CashFlowError.unauthorized
        case 402: throw CashFlowError.paymentRequired
        default: throw CashFlowError.transport(message: "HTTP \(code)")
        }
    }

    private func sanitize(_ string: String) -> String {
        string
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
