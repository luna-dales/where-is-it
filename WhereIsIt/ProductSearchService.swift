
import Foundation
import Supabase

struct ProductLocation: Codable, Identifiable {
    let productId: UUID
    let productName: String
    let brand: String?
    let variety: String?
    let packageSize: String?
    let storeId: UUID
    let storeName: String
    let aisleNumber: String
    let shelfSide: String
    let shelfFromTop: Int
    let lastSeen: Date
    let observationId: UUID

    // Photograph and product position
    let imagePath: String?
    let boundingX: Double?
    let boundingY: Double?
    let boundingWidth: Double?
    let boundingHeight: Double?

    var id: UUID { observationId }

    var hasPhotograph: Bool {
        guard let imagePath else { return false }
        return !imagePath.isEmpty
    }

    var hasBoundingBox: Bool {
        boundingX != nil &&
        boundingY != nil &&
        boundingWidth != nil &&
        boundingHeight != nil
    }

    enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case productName = "product_name"
        case brand
        case variety
        case packageSize = "package_size"
        case storeId = "store_id"
        case storeName = "store_name"
        case aisleNumber = "aisle_number"
        case shelfSide = "shelf_side"
        case shelfFromTop = "shelf_from_top"
        case lastSeen = "last_seen"
        case observationId = "observation_id"
        case imagePath = "image_path"
        case boundingX = "bounding_x"
        case boundingY = "bounding_y"
        case boundingWidth = "bounding_width"
        case boundingHeight = "bounding_height"
    }
}

enum ProductSearchService {

    static func search(
        query: String,
        storeId: UUID? = nil
    ) async throws -> [ProductLocation] {

        try await AuthenticationManager.shared
            .ensureAuthenticated()

        let searchText = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !searchText.isEmpty else {
            return []
        }

        let pattern = "%\(searchText)%"

        if let storeId {
            let results: [ProductLocation] = try await
                SupabaseManager.client
                    .from("product_locations")
                    .select()
                    .or(
                        "product_name.ilike.\(pattern),brand.ilike.\(pattern)"
                    )
                    .eq("store_id", value: storeId.uuidString)
                    .order("last_seen", ascending: false)
                    .limit(100)
                    .execute()
                    .value

            return results
        } else {
            let results: [ProductLocation] = try await
                SupabaseManager.client
                    .from("product_locations")
                    .select()
                    .or(
                        "product_name.ilike.\(pattern),brand.ilike.\(pattern)"
                    )
                    .order("last_seen", ascending: false)
                    .limit(100)
                    .execute()
                    .value

            return results
        }
    }
}

