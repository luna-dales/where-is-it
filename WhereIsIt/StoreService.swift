
import Foundation
import Supabase

struct GroceryStore: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let address: String?
    let city: String?
    let state: String?
    let postalCode: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case address
        case city
        case state
        case postalCode = "postal_code"
    }

    var displayAddress: String {
        let parts = [
            address,
            city,
            state,
            postalCode
        ].compactMap { $0 }

        return parts.joined(separator: ", ")
    }
}

enum StoreService {

    static func fetchStores() async throws -> [GroceryStore] {
        try await AuthenticationManager.shared
            .ensureAuthenticated()

        let stores: [GroceryStore] = try await
            SupabaseManager.client
                .from("stores")
                .select(
                    "id,name,address,city,state,postal_code"
                )
                .order("name", ascending: true)
                .execute()
                .value

        return stores
    }
}

