import Foundation
import Testing
import CashFlowKit

@Suite("SuggestTransactionCategoryUseCase")
struct SuggestTransactionCategoryUseCaseTests {
    @Test("Coffee does not match fee substring")
    func coffeeIsDiningNotFee() {
        let id = SuggestTransactionCategoryUseCase.execute(
            description: "LOONEY BEAN COFFEE",
            amount: -7.29
        )
        #expect(id == SystemCategory.dining.id)
    }

    @Test("Unmatched credits are Other, not Income")
    func unmatchedCreditIsOther() {
        #expect(
            SuggestTransactionCategoryUseCase.execute(
                description: "MISC DEPOSIT REF 998877",
                amount: 100
            ) == SystemCategory.other.id
        )
    }

    @Test("Electronic payment credits are Transfer")
    func electronicPaymentIsTransfer() {
        #expect(
            SuggestTransactionCategoryUseCase.execute(
                description: "BA ELECTRONIC PAYMENT",
                amount: 250
            ) == SystemCategory.transfer.id
        )
    }

    @Test("Payroll credit is Income")
    func payrollIsIncome() {
        #expect(
            SuggestTransactionCategoryUseCase.execute(
                description: "PAYROLL ACME CORP",
                amount: 3_200
            ) == SystemCategory.income.id
        )
    }

    @Test("Gold set covers realistic merchants")
    func goldSetAccuracy() {
        let cases: [(String, Decimal, CategoryID)] = [
            ("PAYROLL ACME CORP", 3_200, SystemCategory.income.id),
            ("DIRECT DEPOSIT PAYROLL", 2_500, SystemCategory.income.id),
            ("ACH Transfer to Savings", -500, SystemCategory.transfer.id),
            ("PAYMENT THANK YOU", 200, SystemCategory.transfer.id),
            ("CREDIT CARD PAYMENT AUTOPAY", -1_200, SystemCategory.creditCardPayment.id),
            ("WHOLE FOODS #102", -64, SystemCategory.groceries.id),
            ("TRADER JOE'S #512", -87, SystemCategory.groceries.id),
            ("UBER TRIP HELP.UBER.COM", -18, SystemCategory.transport.id),
            ("LYFT *RIDE", -22, SystemCategory.transport.id),
            ("SHELL OIL 57442942", -42, SystemCategory.transport.id),
            ("MONTHLY RENT PAYMENT", -1_800, SystemCategory.rentMortgage.id),
            ("MORTGAGE PAYMENT CHASE", -2_100, SystemCategory.rentMortgage.id),
            ("MARRIOTT HOTEL SEATTLE", -240, SystemCategory.travelVacation.id),
            ("AIRBNB * HM XYZ", -350, SystemCategory.travelVacation.id),
            ("PLANET FITNESS", -25, SystemCategory.healthFitness.id),
            ("CVS/PHARMACY #4521", -18, SystemCategory.medical.id),
            ("OVERDRAFT FEE", -35, SystemCategory.feesCharges.id),
            ("NETFLIX.COM", -15.99, SystemCategory.entertainment.id),
            ("SPOTIFY USA", -11.99, SystemCategory.entertainment.id),
            ("KROGER #412", -56, SystemCategory.groceries.id),
            ("SAFEWAY 1234", -48, SystemCategory.groceries.id),
            ("COSTCO WHOLESALE", -120, SystemCategory.groceries.id),
            ("QDOBA 2727", -13.78, SystemCategory.dining.id),
            // Ambiguous Square descriptor without a dining keyword → Other (manual edit).
            ("SQ *DOS GRINGOS BUR", -14.21, SystemCategory.other.id),
            ("LOONEY BEAN COFFEE", -7.29, SystemCategory.dining.id),
            ("STARBUCKS STORE 123", -6.45, SystemCategory.dining.id),
            ("MCDONALD'S F1234", -12, SystemCategory.dining.id),
            ("AMAZON.COM*AB123", -35, SystemCategory.shopping.id),
            ("TARGET T-1234", -67, SystemCategory.shopping.id),
            ("WALMART SUPERCENTER", -89, SystemCategory.shopping.id),
            ("COMCAST CABLE COMM", -89, SystemCategory.bills.id),
            ("XCEL ENERGY", -120, SystemCategory.bills.id),
            ("VERIZON WIRELESS", -70, SystemCategory.bills.id),
            ("PG&E UTILITY", -95, SystemCategory.bills.id),
            ("DELTA AIR LINES", -420, SystemCategory.travelVacation.id),
            ("UNITED 0161234567890", -380, SystemCategory.travelVacation.id),
            ("CHEVRON 0309123", -55, SystemCategory.transport.id),
            ("EXXONMOBIL", -48, SystemCategory.transport.id),
            ("ORTHODONTIC SPECIALISTS", -200, SystemCategory.medical.id),
            ("KAISER PERMANENTE", -40, SystemCategory.medical.id),
            ("ORANGE THEORY FITNESS", -159, SystemCategory.healthFitness.id),
            ("BA ELECTRONIC PAYMENT", 250, SystemCategory.transfer.id),
            ("VENMO CASHOUT", 80, SystemCategory.transfer.id),
            ("ZELLE FROM JOHN", 50, SystemCategory.transfer.id),
            ("IRS TREAS 310 TAX REFUND", 800, SystemCategory.income.id),
            ("INTEREST PAYMENT", Decimal(string: "2.15")!, SystemCategory.income.id),
            ("SQ *APPLE.COM/BILL", Decimal(string: "-0.99")!, SystemCategory.entertainment.id),
            ("CURSOR AI POWERED I", -20, SystemCategory.businessServices.id),
            ("INTUIT *QUICKBOOKS", -30, SystemCategory.businessServices.id),
            ("GODADDY.COM", Decimal(string: "-21.99")!, SystemCategory.businessServices.id),
            ("ATM FEE CHASE", Decimal(string: "-3.50")!, SystemCategory.feesCharges.id),
            ("FOREIGN TRANSACTION FEE", Decimal(string: "-2.10")!, SystemCategory.feesCharges.id),
        ]

        var misses: [String] = []
        for (description, amount, expected) in cases {
            let got = SuggestTransactionCategoryUseCase.execute(
                description: description,
                amount: amount
            )
            if got != expected {
                misses.append(
                    "\(description): expected \(expected.rawValue), got \(got.rawValue)"
                )
            }
        }
        #expect(misses.isEmpty, Comment(rawValue: misses.joined(separator: "\n")))
        #expect(cases.count >= 50)
    }
}
