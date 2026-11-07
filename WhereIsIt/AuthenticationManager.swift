
import Foundation
import Supabase

@MainActor
final class AuthenticationManager {

    static let shared = AuthenticationManager()

    private init() {}

    func ensureAuthenticated() async throws {

        // Reuse an existing session if available.
        if let session = try? await
            SupabaseManager.client.auth.session,
           !session.isExpired {
            print("Supabase: Existing session found")
            return
        }

        // Otherwise, sign in anonymously.
        let session = try await
            SupabaseManager.client.auth.signInAnonymously()

        print("Supabase: Anonymous sign-in successful")
        print("User ID: \(session.user.id)")
    }
}

