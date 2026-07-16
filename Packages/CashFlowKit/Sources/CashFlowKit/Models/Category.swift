import Foundation

/// System and user-facing transaction categories.
public struct Category: Identifiable, Hashable, Sendable, Codable {
    public let id: CategoryID
    public let name: String
    public let kind: CategoryKind

    public init(id: CategoryID, name: String, kind: CategoryKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

public struct CategoryID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum CategoryKind: String, Sendable, Codable, Hashable {
    case income
    case expense
    /// Contributes zero to all cash-flow calculations.
    case excluded
}

public enum SystemCategory: String, Sendable, CaseIterable {
    case income
    case hidden
    case transfer
    case creditCardPayment
    case groceries
    case dining
    case transport
    case shopping
    case bills
    case entertainment
    case other

    public var id: CategoryID { CategoryID(rawValue) }

    public var name: String {
        switch self {
        case .income: "Income"
        case .hidden: "Hidden"
        case .transfer: "Transfer"
        case .creditCardPayment: "Credit Card Payment"
        case .groceries: "Groceries"
        case .dining: "Dining"
        case .transport: "Transport"
        case .shopping: "Shopping"
        case .bills: "Bills"
        case .entertainment: "Entertainment"
        case .other: "Other"
        }
    }

    public var kind: CategoryKind {
        switch self {
        case .income: .income
        case .hidden, .transfer, .creditCardPayment: .excluded
        case .groceries, .dining, .transport, .shopping, .bills, .entertainment, .other:
            .expense
        }
    }

    public var category: Category {
        Category(id: id, name: name, kind: kind)
    }

    public static var allCategories: [Category] {
        allCases.map(\.category)
    }

    public static func category(for id: CategoryID) -> Category {
        if let match = SystemCategory(rawValue: id.rawValue) {
            return match.category
        }
        return SystemCategory.other.category
    }
}
