import Foundation

/// Local category suggestion from merchant description + amount.
/// Keyword / phrase rules only — not ML. Prefer “Other” over a confident wrong guess.
public enum SuggestTransactionCategoryUseCase: Sendable {
    public static func execute(description: String, amount: Decimal) -> CategoryID {
        let haystack = normalize(description)

        // Explicit income cues (credits only).
        if amount > 0, matchesIncome(haystack) {
            return SystemCategory.income.id
        }

        if matchesAnyPhrase(haystack, ["credit card payment"])
            || matchesAnyWord(haystack, ["autopay"])
        {
            return SystemCategory.creditCardPayment.id
        }

        if matchesAnyPhrase(haystack, [
            "payment thank you", "electronic payment", "ach deposit", "ach credit", "cash app",
        ]) || matchesAnyWord(haystack, [
            "transfer", "venmo", "zelle", "cashapp",
        ]) {
            return SystemCategory.transfer.id
        }

        if matchesAnyPhrase(haystack, [
            "whole foods", "trader joe", "trader joes", "food lion",
        ]) || matchesAnyWord(haystack, [
            "grocery", "groceries", "kroger", "safeway", "costco",
            "albertsons", "publix", "wegmans", "aldi", "heb",
        ]) {
            return SystemCategory.groceries.id
        }

        if matchesAnyPhrase(haystack, ["gas station", "exxonmobil"])
            || matchesAnyWord(haystack, [
                "uber", "lyft", "shell", "chevron", "exxon", "mobil",
                "parking", "toll",
            ])
        {
            return SystemCategory.transport.id
        }

        if matchesAnyWord(haystack, ["rent", "mortgage"]) {
            return SystemCategory.rentMortgage.id
        }

        if matchesAnyPhrase(haystack, ["planet fitness", "orange theory"])
            || matchesAnyWord(haystack, ["gym", "fitness"])
        {
            return SystemCategory.healthFitness.id
        }

        if matchesAnyPhrase(haystack, ["air lines"])
            || matchesAnyWord(haystack, [
                "hotel", "airbnb", "airline", "airlines", "vacation",
                "marriott", "hilton", "hyatt", "delta", "southwest",
                "jetblue", "united",
            ])
        {
            return SystemCategory.travelVacation.id
        }

        if matchesAnyWord(haystack, [
            "pharmacy", "hospital", "clinic", "dental", "dentist",
            "medical", "orthodontic", "kaiser", "cvs", "walgreens",
        ]) {
            return SystemCategory.medical.id
        }

        // Word-boundary "fee" so "coffee" does not match.
        if matchesAnyPhrase(haystack, ["service charge", "foreign transaction"])
            || matchesAnyWord(haystack, ["fee", "fees", "overdraft", "nsf"])
        {
            return SystemCategory.feesCharges.id
        }

        if matchesAnyPhrase(haystack, ["apple com"])
            || matchesAnyWord(haystack, [
                "netflix", "spotify", "hulu", "disney", "hbo", "youtube",
            ])
        {
            return SystemCategory.entertainment.id
        }

        if matchesAnyWord(haystack, [
            "starbucks", "mcdonald", "mcdonalds", "qdoba", "chipotle",
            "dunkin", "subway", "wendy", "wendys", "doordash", "grubhub",
            "ubereats", "cafe", "coffee", "restaurant", "pizza", "burger",
            "taco", "sushi", "bakery", "diner",
        ]) {
            return SystemCategory.dining.id
        }

        if matchesAnyWord(haystack, [
            "amazon", "target", "walmart", "ebay", "etsy", "bestbuy", "ikea",
        ]) || matchesAnyPhrase(haystack, ["best buy"]) {
            return SystemCategory.shopping.id
        }

        if matchesAnyPhrase(haystack, ["pg&e", "at&t", "t-mobile", "t mobile"])
            || matchesAnyWord(haystack, [
                "comcast", "xfinity", "verizon", "spectrum", "cox",
                "xcel", "utility", "utilities", "electric", "internet", "att",
            ])
        {
            return SystemCategory.bills.id
        }

        if matchesAnyPhrase(haystack, ["google workspace", "microsoft 365"])
            || matchesAnyWord(haystack, [
                "intuit", "quickbooks", "godaddy", "aws", "adobe", "slack",
                "zoom", "shopify", "squarespace", "github", "cursor",
            ])
        {
            return SystemCategory.businessServices.id
        }

        // Unmatched amounts (including credits): Other — not automatic Income.
        return SystemCategory.other.id
    }

    // MARK: - Matching

    private static func normalize(_ description: String) -> String {
        description
            .lowercased()
            .replacingOccurrences(of: "*", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "#", with: " ")
    }

    private static func tokens(in haystack: String) -> [String] {
        haystack
            .split { !($0.isLetter || $0.isNumber || $0 == "&") }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func matchesAnyWord(_ haystack: String, _ words: [String]) -> Bool {
        let tokenSet = Set(tokens(in: haystack))
        for word in words where !word.contains(" ") {
            if tokenSet.contains(word) { return true }
            // mcdonald ≈ mcdonalds
            if tokenSet.contains(where: {
                $0 == word || ($0.hasPrefix(word) && $0.count <= word.count + 2)
            }) {
                return true
            }
        }
        return false
    }

    private static func matchesAnyPhrase(_ haystack: String, _ phrases: [String]) -> Bool {
        phrases.contains { haystack.contains($0) }
    }

    private static func matchesIncome(_ haystack: String) -> Bool {
        matchesAnyPhrase(haystack, ["direct deposit", "tax refund", "payroll"])
            || matchesAnyWord(haystack, [
                "salary", "paycheck", "interest", "dividend", "pension", "bonus",
            ])
    }
}
