import Foundation

public protocol OnDeviceModelAvailabilityChecking: Sendable {
    func availability() async -> OnDeviceModelAvailability
}
