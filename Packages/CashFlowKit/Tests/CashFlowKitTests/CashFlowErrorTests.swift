import Foundation
import Testing
@testable import CashFlowKit

@Suite("CashFlowError")
struct CashFlowErrorTests {
    @Test("Every case has a non-empty user-facing description")
    func everyCaseHasDescription() {
        let samples: [CashFlowError] = [
            .unauthorized,
            .paymentRequired,
            .transport(message: ""),
            .transport(message: "Timed out"),
            .decoding(message: ""),
            .decoding(message: "Bad JSON"),
            .persistence(message: ""),
            .persistence(message: "Disk full"),
            .providerMessages([]),
            .providerMessages(["Bridge says hi"]),
            .notLinked,
            .cancelled,
            .authenticationUnavailable,
            .authenticationFailed,
            .intelligenceUnavailable,
            .intelligence(message: ""),
            .intelligence(message: "Try again"),
        ]
        for error in samples {
            let text = error.errorDescription ?? ""
            #expect(!text.isEmpty, "Missing description for \(error)")
            #expect(!text.contains("error 2"))
        }
    }

    @Test("Bridged NSError keeps a readable localizedDescription")
    func bridgedNSErrorIsReadable() {
        let error = CashFlowError.transport(message: "Timed out talking to SimpleFIN.")
        let nsError = error as NSError

        #expect(nsError.domain == CashFlowError.errorDomain)
        #expect(nsError.code == 2)
        #expect(nsError.localizedDescription == "Timed out talking to SimpleFIN.")
    }

    @Test("userFacingMessage recovers bridged transport code 2")
    func userFacingMessageRecoversTransport() {
        let nsError = NSError(
            domain: CashFlowError.errorDomain,
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Network down"]
        )
        let message = CashFlowError.userFacingMessage(for: nsError, fallback: "Fallback")
        #expect(message == "Network down")
        #expect(!message.contains("error 2"))
    }

    @Test("userFacingMessage rejects opaque type dumps")
    func rejectsOpaqueDumps() {
        let nsError = NSError(
            domain: "SomeOtherDomain",
            code: 99,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "The operation couldn’t be completed. (CashFlowKit.CashFlowError error 2.)",
            ]
        )
        let message = CashFlowError.userFacingMessage(for: nsError, fallback: "Try again.")
        #expect(message == "Try again.")
    }

    @Test("userFacingMessage prefers typed CashFlowError over fallback")
    func prefersTypedError() {
        let message = CashFlowError.userFacingMessage(
            for: CashFlowError.intelligence(message: "Try a shorter request."),
            fallback: "Fallback"
        )
        #expect(message == "Try a shorter request.")
    }
}
