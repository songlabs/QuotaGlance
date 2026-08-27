import Foundation

@MainActor
func performRestore(
    sync: @MainActor () async throws -> Void,
    refreshEntitlements: @MainActor () async -> Void
) async -> Result<Void, Error> {
    do {
        try await sync()
        await refreshEntitlements()
        return .success(())
    } catch {
        return .failure(error)
    }
}

func restoreFeedbackLocalizationKey(succeeded: Bool) -> String {
    succeeded ? "Restore Completed" : "Restore Failed"
}
