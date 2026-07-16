import SwiftUI
import CashFlowKit

enum CategoryIcon {
    static func systemName(for categoryID: CategoryID) -> String {
        switch SystemCategory(rawValue: categoryID.rawValue) {
        case .income: "banknote"
        case .groceries: "cart"
        case .dining: "fork.knife"
        case .transport: "car"
        case .shopping: "bag"
        case .bills: "doc.text"
        case .entertainment: "tv"
        case .transfer: "arrow.left.arrow.right"
        case .creditCardPayment: "creditcard"
        case .hidden: "eye.slash"
        case .other, .none: "circle.grid.2x2"
        }
    }
}
