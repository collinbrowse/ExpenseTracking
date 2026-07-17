import Foundation

/// Domain merge policy for accounts: remote wins balance/institution; local wins name when user edited.
public enum MergeAccountSyncPolicy: Sendable {
    public static func resolvedName(
        localName: String,
        localUserEditedName: Bool,
        remoteName: String
    ) -> (name: String, userEditedName: Bool) {
        if localUserEditedName {
            return (localName, true)
        }
        return (remoteName, false)
    }
}
