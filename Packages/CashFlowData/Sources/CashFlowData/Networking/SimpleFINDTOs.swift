import Foundation

struct SimpleFINAccountSetDTO: Decodable, Sendable {
    let errors: [String]?
    let accounts: [SimpleFINAccountDTO]
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

    enum CodingKeys: String, CodingKey {
        case org, id, name, currency, balance
        case availableBalance = "available-balance"
        case balanceDate = "balance-date"
        case transactions
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
