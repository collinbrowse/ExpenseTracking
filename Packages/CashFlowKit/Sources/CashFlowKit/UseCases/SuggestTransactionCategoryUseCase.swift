import Foundation

/// Local category suggestion from merchant description + amount.
/// Keyword / phrase rules only — not ML. Prefer “Other” over a confident wrong guess.
public enum SuggestTransactionCategoryUseCase: Sendable {
    public static func execute(description: String, amount: Decimal) -> CategoryID {
        let haystack = TransactionDescriptionMatcher.normalize(description)

        // Explicit income cues (credits only).
        if amount > 0, matchesIncome(haystack) {
            return SystemCategory.income.id
        }

        if TransactionDescriptionMatcher.matchesAnyPhrase(haystack, ["credit card payment"])
            || TransactionDescriptionMatcher.matchesAnyWord(haystack, ["autopay"])
        {
            return SystemCategory.creditCardPayment.id
        }

        if TransactionDescriptionMatcher.matchesAnyPhrase(haystack, [
            "payment thank you", "electronic payment", "ach deposit", "ach credit", "cash app",
        ]) || TransactionDescriptionMatcher.matchesAnyWord(haystack, [
            "transfer", "venmo", "zelle", "cashapp",
        ]) {
            return SystemCategory.transfer.id
        }

        if TransactionDescriptionMatcher.matchesAnyPhrase(haystack, [
            "whole foods", "trader joe", "trader joes", "food lion",
        ]) || TransactionDescriptionMatcher.matchesAnyWord(haystack, [
            "grocery", "groceries", "kroger", "safeway", "costco",
            "albertsons", "publix", "wegmans", "aldi", "heb",
        ]) {
            return SystemCategory.groceries.id
        }

        if TransactionDescriptionMatcher.matchesAnyPhrase(haystack, ["gas station", "exxonmobil"])
            || TransactionDescriptionMatcher.matchesAnyWord(haystack, [
                "uber", "lyft", "shell", "chevron", "exxon", "mobil",
                "parking", "toll",
            ])
        {
            return SystemCategory.transport.id
        }

        if TransactionDescriptionMatcher.matchesAnyWord(haystack, ["rent", "mortgage"]) {
            return SystemCategory.rentMortgage.id
        }

        if TransactionDescriptionMatcher.matchesAnyPhrase(haystack, ["planet fitness", "orange theory"])
            || TransactionDescriptionMatcher.matchesAnyWord(haystack, ["gym", "fitness"])
        {
            return SystemCategory.healthFitness.id
        }

        if TransactionDescriptionMatcher.matchesAnyPhrase(haystack, ["air lines"])
            || TransactionDescriptionMatcher.matchesAnyWord(haystack, [
                "hotel", "airbnb", "airline", "airlines", "vacation",
                "marriott", "hilton", "hyatt", "delta", "southwest",
                "jetblue", "united",
            ])
        {
            return SystemCategory.travelVacation.id
        }

        if TransactionDescriptionMatcher.matchesAnyWord(haystack, [
            "pharmacy", "hospital", "clinic", "dental", "dentist",
            "medical", "orthodontic", "kaiser", "cvs", "walgreens",
        ]) {
            return SystemCategory.medical.id
        }

        // Word-boundary "fee" so "coffee" does not match.
        if TransactionDescriptionMatcher.matchesAnyPhrase(haystack, ["service charge", "foreign transaction"])
            || TransactionDescriptionMatcher.matchesAnyWord(haystack, ["fee", "fees", "overdraft", "nsf"])
        {
            return SystemCategory.feesCharges.id
        }

        if TransactionDescriptionMatcher.matchesAnyPhrase(haystack, ["apple com"])
            || TransactionDescriptionMatcher.matchesAnyWord(haystack, [
                "netflix", "spotify", "hulu", "disney", "hbo", "youtube",
            ])
        {
            return SystemCategory.entertainment.id
        }

        if TransactionDescriptionMatcher.matchesAnyWord(haystack, [
            "starbucks", "mcdonald", "mcdonalds", "qdoba", "chipotle",
            "dunkin", "subway", "wendy", "wendys", "doordash", "grubhub",
            "ubereats", "cafe", "coffee", "restaurant", "pizza", "burger",
            "taco", "sushi", "bakery", "diner",
        ]) {
            return SystemCategory.dining.id
        }

        if TransactionDescriptionMatcher.matchesAnyWord(haystack, [
            "amazon", "target", "walmart", "ebay", "etsy", "bestbuy", "ikea",
        ]) || TransactionDescriptionMatcher.matchesAnyPhrase(haystack, ["best buy"]) {
            return SystemCategory.shopping.id
        }

        if TransactionDescriptionMatcher.matchesAnyPhrase(haystack, ["pg&e", "at&t", "t-mobile", "t mobile"])
            || TransactionDescriptionMatcher.matchesAnyWord(haystack, [
                "comcast", "xfinity", "verizon", "spectrum", "cox",
                "xcel", "utility", "utilities", "electric", "internet", "att",
            ])
        {
            return SystemCategory.bills.id
        }

        if TransactionDescriptionMatcher.matchesAnyPhrase(haystack, ["google workspace", "microsoft 365"])
            || TransactionDescriptionMatcher.matchesAnyWord(haystack, [
                "intuit", "quickbooks", "godaddy", "aws", "adobe", "slack",
                "zoom", "shopify", "squarespace", "github", "cursor",
            ])
        {
            return SystemCategory.businessServices.id
        }

        // Unmatched amounts (including credits): Other — not automatic Income.
        return SystemCategory.other.id
    }

    private static func matchesIncome(_ haystack: String) -> Bool {
        TransactionDescriptionMatcher.matchesAnyPhrase(haystack, ["direct deposit", "tax refund", "payroll"])
            || TransactionDescriptionMatcher.matchesAnyWord(haystack, [
                "salary", "paycheck", "interest", "dividend", "pension", "bonus",
            ])
    }
}
