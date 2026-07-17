import Foundation

struct SimpleFINAccountSetDTO: Decodable, Sendable {
    let errors: [String]?
    let errlist: [SimpleFINErrorDTO]?
    let connections: [SimpleFINConnectionDTO]?
    let accounts: [SimpleFINAccountDTO]

    var displayMessages: [String] {
        if let errlist, !errlist.isEmpty {
            return errlist.map(\.msg)
        }
        return errors ?? []
    }
}

struct SimpleFINErrorDTO: Decodable, Sendable {
    let code: String
    let msg: String
    let connID: String?
    let accountID: String?

    enum CodingKeys: String, CodingKey {
        case code, msg
        case connID = "conn_id"
        case accountID = "account_id"
    }
}

struct SimpleFINConnectionDTO: Decodable, Sendable {
    let connID: String
    let name: String
    let orgID: String?
    let orgName: String?
    let orgURL: String?
    let sfinURL: String?

    enum CodingKeys: String, CodingKey {
        case name
        case connID = "conn_id"
        case orgID = "org_id"
        case orgName = "org_name"
        case orgURL = "org_url"
        case sfinURL = "sfin-url"
    }
}

struct SimpleFINAccountDTO: Decodable, Sendable {
    let org: SimpleFINOrgDTO?
    let id: String
    let name: String
    let currency: String
    let balance: String
    let availableBalance: String?
    let balanceDate: Int
    let transactions: [SimpleFINTransactionDTO]?
    let connID: String?
    let connName: String?

    enum CodingKeys: String, CodingKey {
        case org, id, name, currency, balance, transactions
        case availableBalance = "available-balance"
        case balanceDate = "balance-date"
        case connID = "conn_id"
        case connName = "conn_name"
    }
}

struct SimpleFINOrgDTO: Decodable, Sendable {
    let domain: String?
    let name: String?
    let sfinURL: String?

    enum CodingKeys: String, CodingKey {
        case domain, name
        case sfinURL = "sfin-url"
    }
}

struct SimpleFINTransactionDTO: Decodable, Sendable {
    let id: String
    let posted: Int
    let amount: String
    let description: String
    let pending: Bool?
}

struct SimpleFINInfoDTO: Decodable, Sendable {
    let versions: [String]
}
