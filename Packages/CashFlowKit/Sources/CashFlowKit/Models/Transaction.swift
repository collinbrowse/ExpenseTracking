import Foundation

public struct TransactionID: Hashable, Sendable, Codable, Comparable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static func < (lhs: TransactionID, rhs: TransactionID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct Transaction: Identifiable, Hashable, Sendable, Codable {
    public let id: TransactionID
    public let accountID: AccountID
    public let externalID: String
    public let amount: Decimal
    public let postedDate: Date
    public let description: String
    public let categoryID: CategoryID
    public let currencyCode: String
    public let userEditedCategory: Bool
    public let isPending: Bool
    /// When true, user categorization rules never change this transaction’s category.
    public let categoryLocked: Bool
    /// Local-only user tags; sync never invents or clears these.
    public let tagIDs: [TagID]
    /// Tags the user removed that rules must not re-add.
    public let suppressedTagIDs: [TagID]
    /// Local-only LLM/heuristic merchant title cache; sync never invents or clears unless description changes.
    public let enrichedTitle: String?
    /// Local-only location cache paired with `enrichedTitle`.
    public let enrichedLocation: String?

    public init(
        id: TransactionID,
        accountID: AccountID,
        externalID: String,
        amount: Decimal,
        postedDate: Date,
        description: String,
        categoryID: CategoryID,
        currencyCode: String = "USD",
        userEditedCategory: Bool = false,
        isPending: Bool = false,
        categoryLocked: Bool = false,
        tagIDs: [TagID] = [],
        suppressedTagIDs: [TagID] = [],
        enrichedTitle: String? = nil,
        enrichedLocation: String? = nil
    ) {
        self.id = id
        self.accountID = accountID
        self.externalID = externalID
        self.amount = amount
        self.postedDate = postedDate
        self.description = description
        self.categoryID = categoryID
        self.currencyCode = currencyCode
        self.userEditedCategory = userEditedCategory
        self.isPending = isPending
        self.categoryLocked = categoryLocked
        self.tagIDs = tagIDs
        self.suppressedTagIDs = suppressedTagIDs
        self.enrichedTitle = enrichedTitle
        self.enrichedLocation = enrichedLocation
    }

    private enum CodingKeys: String, CodingKey {
        case id, accountID, externalID, amount, postedDate, description
        case categoryID, currencyCode, userEditedCategory, isPending
        case categoryLocked, tagIDs, suppressedTagIDs, enrichedTitle, enrichedLocation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(TransactionID.self, forKey: .id)
        accountID = try container.decode(AccountID.self, forKey: .accountID)
        externalID = try container.decode(String.self, forKey: .externalID)
        amount = try container.decode(Decimal.self, forKey: .amount)
        postedDate = try container.decode(Date.self, forKey: .postedDate)
        description = try container.decode(String.self, forKey: .description)
        categoryID = try container.decode(CategoryID.self, forKey: .categoryID)
        currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode) ?? "USD"
        userEditedCategory = try container.decodeIfPresent(Bool.self, forKey: .userEditedCategory) ?? false
        isPending = try container.decodeIfPresent(Bool.self, forKey: .isPending) ?? false
        categoryLocked = try container.decodeIfPresent(Bool.self, forKey: .categoryLocked) ?? false
        tagIDs = try container.decodeIfPresent([TagID].self, forKey: .tagIDs) ?? []
        suppressedTagIDs = try container.decodeIfPresent([TagID].self, forKey: .suppressedTagIDs) ?? []
        enrichedTitle = try container.decodeIfPresent(String.self, forKey: .enrichedTitle)
        enrichedLocation = try container.decodeIfPresent(String.self, forKey: .enrichedLocation)
    }

    /// Display title: enrichment cache when present, else heuristic parse.
    public var displayTitle: String {
        if let enrichedTitle, !enrichedTitle.isEmpty {
            return enrichedTitle
        }
        return ParseTransactionDescriptionUseCase.execute(description).title
    }

    /// Display location: enrichment cache when present, else heuristic parse.
    public var displayLocation: String? {
        if let enrichedTitle, !enrichedTitle.isEmpty {
            let trimmed = enrichedLocation?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmed?.isEmpty == false) ? trimmed : nil
        }
        return ParseTransactionDescriptionUseCase.execute(description).location
    }

    public var category: Category {
        SystemCategory.category(for: categoryID)
    }
}

/// Batch category write for rule re-apply (not list pagination).
public struct CategoryAssignment: Hashable, Sendable {
    public let transactionID: TransactionID
    public let categoryID: CategoryID
    public let userEditedCategory: Bool

    public init(
        transactionID: TransactionID,
        categoryID: CategoryID,
        userEditedCategory: Bool
    ) {
        self.transactionID = transactionID
        self.categoryID = categoryID
        self.userEditedCategory = userEditedCategory
    }
}
