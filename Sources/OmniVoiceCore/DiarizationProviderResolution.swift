import Foundation

public enum DiarizationProviderResolution {
    public static let noDiarizationProviderID = "none"
    public static let enabledProviderIDs = Set(DiarizationPrecision.allCases.map(\.providerID))
    public static let mlxSortformerProviderIDs = enabledProviderIDs

    public static func isEnabledProviderID(_ providerID: String) -> Bool {
        enabledProviderIDs.contains(providerID.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public static func effectiveProviderID(
        preferred providerID: String,
        knownProvider: EngineProviderInfo?
    ) -> String {
        let preferred = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEnabledProviderID(preferred) else {
            return noDiarizationProviderID
        }

        if let knownProvider, !knownProvider.available {
            return noDiarizationProviderID
        }

        return preferred
    }

    public static func usesLiveConversationStream(
        preferred providerID: String,
        knownProvider: EngineProviderInfo?
    ) -> Bool {
        effectiveProviderID(preferred: providerID, knownProvider: knownProvider) != noDiarizationProviderID
    }
}
