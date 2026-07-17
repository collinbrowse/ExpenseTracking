import Foundation
import Testing
import CashFlowKit

@Suite("ParseTransactionDescriptionUseCase")
struct ParseTransactionDescriptionUseCaseTests {
    @Test("Splits merchant and location on wide padding")
    func splitsOnWideSpaces() {
        let parsed = ParseTransactionDescriptionUseCase.execute(
            "KROGER #412          FORT COLLINS CO"
        )
        #expect(parsed.title == "KROGER #412")
        #expect(parsed.location == "FORT COLLINS CO")
    }

    @Test("Collapses location internal whitespace")
    func collapsesLocationWhitespace() {
        let parsed = ParseTransactionDescriptionUseCase.execute(
            "SHELL OIL    DENVER    CO"
        )
        #expect(parsed.title == "SHELL OIL")
        #expect(parsed.location == "DENVER CO")
    }

    @Test("Strips trailing city and state with single spaces")
    func trailingCityState() {
        let parsed = ParseTransactionDescriptionUseCase.execute(
            "SQ *DOS GRINGOS BUR DURANGO CO"
        )
        #expect(parsed.title == "SQ *DOS GRINGOS BUR")
        #expect(parsed.location == "DURANGO CO")
    }

    @Test("Supports comma before state")
    func commaBeforeState() {
        let parsed = ParseTransactionDescriptionUseCase.execute(
            "TARGET T-2145 DENVER, CO"
        )
        #expect(parsed.title == "TARGET T-2145")
        #expect(parsed.location == "DENVER CO")
    }

    @Test("Does not treat EXPRESS CO as a location")
    func rejectsCompanyCO() {
        let parsed = ParseTransactionDescriptionUseCase.execute("AMERICAN EXPRESS CO")
        #expect(parsed.location == nil)
        #expect(parsed.title == "AMERICAN EXPRESS CO")
    }

    @Test("No split when only single spaces without a state")
    func noSplitForSingleSpaces() {
        let parsed = ParseTransactionDescriptionUseCase.execute("PAYROLL ACME CORP")
        #expect(parsed.title == "PAYROLL ACME CORP")
        #expect(parsed.location == nil)
    }

    @Test("Recombine keeps location after title edit")
    func recombinePreservesLocation() {
        let combined = ParsedTransactionDescription.recombine(
            title: "Kroger",
            location: "Fort Collins CO"
        )
        let again = ParseTransactionDescriptionUseCase.execute(combined)
        #expect(again.title == "Kroger")
        #expect(again.location == "Fort Collins CO")
    }
}
