import Foundation
import Testing
import CashFlowKit
@testable import CashFlowData

@Suite("SimpleFINClient")
struct SimpleFINClientTests {
    @Test("Claim POST sends empty body and Content-Length 0")
    func claimSendsEmptyBody() async throws {
        let http = MockHTTPClient { request in
            #expect(request.httpMethod == "POST")
            #expect(request.httpBody?.isEmpty == true)
            #expect(request.value(forHTTPHeaderField: "Content-Length") == "0")
            let data = Data("https://user:pass@beta-bridge.simplefin.org/simplefin".utf8)
            return (data, HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!)
        }
        let client = SimpleFINClient(http: http)
        let token = Data("https://beta-bridge.simplefin.org/simplefin/claim/DEMO".utf8)
            .base64EncodedString()
        let accessURL = try await client.claimAccessURL(setupToken: token)
        #expect(accessURL.contains("user:pass@"))
    }

    @Test("Accounts requests are chunked into 90-day windows")
    func accountsAreChunked() async throws {
        let recorder = RequestRecorder()
        let http = MockHTTPClient { request in
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let start = Int(items.first(where: { $0.name == "start-date" })?.value ?? "0")!
            let end = Int(items.first(where: { $0.name == "end-date" })?.value ?? "0")!
            await recorder.append(start: start, end: end)
            #expect(items.contains(where: { $0.name == "version" && $0.value == "2" }))
            #expect(items.contains(where: { $0.name == "pending" && $0.value == "1" }))

            let json = """
            {"errors":[],"accounts":[{"id":"a1","name":"Checking","currency":"USD","balance":"10.00","balance-date":\(end),"org":{"name":"Bank"},"transactions":[{"id":"t-\(start)","posted":\(start),"amount":"-1.00","description":"Coffee"}]}]}
            """
            return (
                Data(json.utf8),
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }

        let client = SimpleFINClient(http: http)
        let accessURL = "https://user:pass@beta-bridge.simplefin.org/simplefin"
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let start = Calendar.current.date(byAdding: .day, value: -180, to: end)!
        let payload = try await client.fetchAccounts(
            accessURL: accessURL,
            startDate: start,
            endDate: end
        )

        let requestedRanges = await recorder.ranges
        #expect(requestedRanges.count >= 2)
        for (rangeStart, rangeEnd) in requestedRanges {
            let start = Date(timeIntervalSince1970: TimeInterval(rangeStart))
            let end = Date(timeIntervalSince1970: TimeInterval(rangeEnd))
            let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? Int.max
            #expect(days <= SimpleFINClient.maxAccountsRangeDays)
        }
        #expect(payload.accounts.count == 1)
        #expect(payload.accounts[0].transactions.count >= 2)
    }

    @Test("dateWindows covers full range with overlap without exceeding max days")
    func dateWindowsRespectMax() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let start = Calendar.current.date(byAdding: .day, value: -100, to: end)!
        let windows = SimpleFINClient.dateWindows(
            from: start,
            to: end,
            maxDays: 45,
            overlapDays: 5
        )
        #expect(windows.count >= 3)
        #expect(windows.first?.lowerBound == start)
        #expect(windows.last?.upperBound == end)
        for window in windows {
            let days = Calendar.current.dateComponents([.day], from: window.lowerBound, to: window.upperBound).day ?? 0
            #expect(days <= 45)
        }
        if windows.count >= 2 {
            let firstEnd = windows[0].upperBound
            let secondStart = windows[1].lowerBound
            #expect(secondStart < firstEnd)
        }
    }

    @Test("errlist attaches sync issues by account_id and conn_id")
    func attachesSyncIssues() {
        let checking = RemoteAccountSnapshot(
            externalID: "acct-checking",
            name: "Checking",
            institutionName: "Bank",
            currencyCode: "USD",
            balance: 10,
            balanceDate: .now,
            transactions: [],
            connectionExternalID: "conn-bank"
        )
        let card = RemoteAccountSnapshot(
            externalID: "acct-card",
            name: "Card",
            institutionName: "Bank",
            currencyCode: "USD",
            balance: -5,
            balanceDate: .now,
            transactions: [],
            connectionExternalID: "conn-card"
        )
        let healthy = RemoteAccountSnapshot(
            externalID: "acct-ok",
            name: "Savings",
            institutionName: "Bank",
            currencyCode: "USD",
            balance: 100,
            balanceDate: .now,
            transactions: [],
            connectionExternalID: "conn-ok"
        )

        let result = SimpleFINClient.applyingSyncIssues(
            to: [checking, card, healthy],
            errors: [
                SimpleFINErrorDTO(
                    code: "auth",
                    msg: "Authentication failed for Checking",
                    connID: nil,
                    accountID: "acct-checking"
                ),
                SimpleFINErrorDTO(
                    code: "auth",
                    msg: "Card connection needs attention",
                    connID: "conn-card",
                    accountID: nil
                ),
                SimpleFINErrorDTO(
                    code: "info",
                    msg: "Requested date range exceeds limit of 90 days and was capped.",
                    connID: nil,
                    accountID: nil
                ),
            ]
        )

        let byID = Dictionary(uniqueKeysWithValues: result.map { ($0.externalID, $0) })
        #expect(byID["acct-checking"]?.syncIssue == "Authentication failed for Checking")
        #expect(byID["acct-card"]?.syncIssue == "Card connection needs attention")
        #expect(byID["acct-ok"]?.syncIssue == nil)
    }

    @Test("Pending posted=0 maps to pending with non-epoch date")
    func pendingZeroPostedMaps() async throws {
        let postedAnchor = 1_700_000_000
        let json = """
        {"errors":[],"accounts":[{"id":"a1","name":"Checking","currency":"USD","balance":"10.00","balance-date":\(postedAnchor),"org":{"name":"Bank"},"transactions":[{"id":"p1","posted":0,"amount":"-12.00","description":"Pending Coffee","pending":true}]}]}
        """
        let http = MockHTTPClient { request in
            (
                Data(json.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }
        let client = SimpleFINClient(http: http)
        let before = Date.now.addingTimeInterval(-5)
        let payload = try await client.fetchAccounts(
            accessURL: "https://user:pass@example.com/simplefin",
            startDate: Date(timeIntervalSince1970: TimeInterval(postedAnchor)),
            endDate: Date(timeIntervalSince1970: TimeInterval(postedAnchor + 86_400))
        )
        let tx = try #require(payload.accounts.first?.transactions.first)
        #expect(tx.isPending)
        #expect(tx.postedDate >= before)
        #expect(tx.postedDate.timeIntervalSince1970 != 0)
    }

    @Test("Date-range advisories are filtered and deduped")
    func filtersDateRangeAdvisories() {
        let messages = SimpleFINClient.normalizeProviderMessages([
            "Requested date range exceeds recommended range of 45 days. In the future, this may be capped.",
            "Requested date range exceeds limit of 90 days and was capped.",
            "Authentication failed for My Bank",
            "Authentication failed for My Bank",
            "Something else happened.",
        ])
        #expect(messages == [
            "Authentication failed for My Bank",
            "Something else happened.",
        ])
    }

    @Test("No connections available becomes actionable guidance")
    func noConnectionsMessage() {
        let body = Data("""
        {"errlist":[{"code":"gen.","msg":"No connections available."}],"accounts":[],"connections":[]}
        """.utf8)
        let messages = SimpleFINClient.providerMessages(fromResponseBody: body)
        #expect(messages?.count == 1)
        #expect(messages?.first?.contains("Financial Institution") == true)
        #expect(messages?.first?.contains("Sync Now") == true)
    }

    @Test("Institution name comes from v2 connections, not placeholder")
    func institutionFromConnections() async throws {
        let json = """
        {"errlist":[],"connections":[{"conn_id":"c1","name":"American Express - Collin","org_id":"amex","org_name":"American Express","org_url":"https://americanexpress.com","sfin-url":"https://example.com"}],"accounts":[{"id":"a1","name":"Blue Cash Preferred","currency":"USD","balance":"-10.00","balance-date":1700000000,"conn_id":"c1","transactions":[]}]}
        """
        let http = MockHTTPClient { request in
            (
                Data(json.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }
        let client = SimpleFINClient(http: http)
        let payload = try await client.fetchAccounts(
            accessURL: "https://user:pass@example.com/simplefin",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_086_400)
        )
        #expect(payload.accounts.count == 1)
        #expect(payload.accounts[0].institutionName == "American Express")
        #expect(payload.accounts[0].name == "Blue Cash Preferred")
    }

    @Test("Connection nickname is stripped when org_name is missing")
    func stripsConnectionNickname() {
        let account = SimpleFINAccountDTO(
            org: nil,
            id: "a1",
            name: "Checking",
            currency: "USD",
            balance: "1.00",
            availableBalance: nil,
            balanceDate: 1,
            transactions: nil,
            connID: "c1",
            connName: nil
        )
        let connection = SimpleFINConnectionDTO(
            connID: "c1",
            name: "Bank of America - Collin",
            orgID: "boa",
            orgName: nil,
            orgURL: nil,
            sfinURL: nil
        )
        let name = SimpleFINClient.institutionName(account: account, connection: connection)
        #expect(name == "Bank of America")
    }
}

private actor MockHTTPClient: HTTPClient {
    private let handler: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    init(handler: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await handler(request)
    }
}

private actor RequestRecorder {
    private(set) var ranges: [(Int, Int)] = []

    func append(start: Int, end: Int) {
        ranges.append((start, end))
    }
}
