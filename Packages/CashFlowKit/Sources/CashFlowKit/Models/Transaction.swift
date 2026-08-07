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
    /// Immutable bank description after ingest. Sync is the only writer.
    public let description: String
    public let categoryID: CategoryID
    public let currencyCode: String
    /// Derived sticky compat for `.user` / `.rule` — not an independent authorship writer.
    /// Prefer `effectiveCategorySource` / `CategorySource.isUserEditedCompat` for new logic.
    public let userEditedCategory: Bool
    public let isPending: Bool
    /// When true, user categorization rules never change this transaction’s category.
    public let categoryLocked: Bool
    /// Local-only user tags; sync never invents or clears these.
    public let tagIDs: [TagID]
    /// Tags the user removed that rules must not re-add.
    public let suppressedTagIDs: [TagID]
    /// Local-only merchant title; authored by LLM, rule, or user (`titleSource`).
    public let enrichedTitle: String?
    /// Local-only location paired with `enrichedTitle`.
    public let enrichedLocation: String?
    /// Who authored the enrichment fields. Nil when no enrichment is present.
    public let titleSource: TitleSource?
    /// Who authored `categoryID`. Nil on unprocessed / legacy rows (see `effectiveCategorySource`).
    public let categorySource: CategorySource?

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
        enrichedLocation: String? = nil,
        titleSource: TitleSource? = nil,
        categorySource: CategorySource? = nil
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
        self.titleSource = titleSource
        self.categorySource = categorySource
    }

    private enum CodingKeys: String, CodingKey {
        case id, accountID, externalID, amount, postedDate, description
        case categoryID, currencyCode, userEditedCategory, isPending
        case categoryLocked, tagIDs, suppressedTagIDs, enrichedTitle, enrichedLocation
        case titleSource, categorySource
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
        titleSource = try container.decodeIfPresent(TitleSource.self, forKey: .titleSource)
        categorySource = try container.decodeIfPresent(CategorySource.self, forKey: .categorySource)
    }

    /// Display title: enrichment when present, else raw bank description.
    public var displayTitle: String {
        if let enrichedTitle, !enrichedTitle.isEmpty {
            return enrichedTitle
        }
        return description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Display location: enrichment when a titled cache exists; never invented from heuristics.
    public var displayLocation: String? {
        guard let enrichedTitle, !enrichedTitle.isEmpty else { return nil }
        let trimmed = enrichedLocation?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    public var category: Category {
        SystemCategory.category(for: categoryID)
    }

    /// Authorship for sticky / overwrite decisions, including legacy dual-flag backfill.
    /// - Explicit `categorySource` wins when present.
    /// - Legacy sticky: `userEditedCategory && categorySource == nil` → `.user`.
    /// - Legacy processed: real category, no source, not sticky → `.keyword`.
    /// - Else `nil` (unprocessed / Undefined).
    public var effectiveCategorySource: CategorySource? {
        if let categorySource { return categorySource }
        if userEditedCategory { return .user }
        if categoryID != SystemCategory.undefined.id { return .keyword }
        return nil
    }

    /// Sticky compat derived from `effectiveCategorySource`.
    public var derivedUserEditedCategory: Bool {
        effectiveCategorySource?.isUserEditedCompat ?? false
    }
}

/// Batch category write for rule re-apply (not list pagination).
public struct CategoryAssignment: Hashable, Sendable {
    public let transactionID: TransactionID
    public let categoryID: CategoryID
    public let userEditedCategory: Bool
    public let categorySource: CategorySource?

    public init(
        transactionID: TransactionID,
        categoryID: CategoryID,
        userEditedCategory: Bool,
        categorySource: CategorySource? = nil
    ) {
        self.transactionID = transactionID
        self.categoryID = categoryID
        self.userEditedCategory = userEditedCategory
        self.categorySource = categorySource
    }

    /// Source-first factory: derives sticky bool from `CategorySource.isUserEditedCompat`.
    public init(
        transactionID: TransactionID,
        categoryID: CategoryID,
        categorySource: CategorySource?
    ) {
        self.transactionID = transactionID
        self.categoryID = categoryID
        self.categorySource = categorySource
        self.userEditedCategory = categorySource?.isUserEditedCompat ?? false
    }
}

/// Local title/location write with provenance. Never mutates the bank description.
public struct TitleLocationAssignment: Hashable, Sendable {
    public let transactionID: TransactionID
    public let title: String?
    public let location: String?
    public let titleSource: TitleSource?

    public init(
        transactionID: TransactionID,
        title: String?,
        location: String?,
        titleSource: TitleSource?
    ) {
        self.transactionID = transactionID
        self.title = title
        self.location = location
        self.titleSource = titleSource
    }
}
