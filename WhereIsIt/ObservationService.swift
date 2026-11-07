
import Foundation
import Supabase

struct SaveObservationProduct: Encodable {
    let brand: String?
    let name: String
    let variety: String?
    let packageSize: String?
    let shelfFromTop: Int
    let identification: String
    let boundingBox: BoundingBox

    init(from product: RecognizedProduct) {
        brand = product.brand
        name = product.name
        variety = product.variety
        packageSize = product.packageSize
        shelfFromTop = product.shelfFromTop
        identification = product.identification
        boundingBox = product.boundingBox
    }
}

struct SaveObservationsRequest: Encodable {
    let storeId: UUID
    let aisleNumber: String
    let shelfSide: String
    let products: [SaveObservationProduct]
}

struct SaveObservationsResponse: Decodable {
    let success: Bool
    let photoId: UUID
    let savedCount: Int
}

enum ObservationService {

    static func save(
        storeId: UUID,
        aisleNumber: String,
        shelfSide: String,
        products: [RecognizedProduct]
    ) async throws -> SaveObservationsResponse {

        try await AuthenticationManager.shared
            .ensureAuthenticated()

        let request = SaveObservationsRequest(
            storeId: storeId,
            aisleNumber: aisleNumber,
            shelfSide: shelfSide,
            products: products.map {
                SaveObservationProduct(from: $0)
            }
        )

        let response: SaveObservationsResponse =
            try await SupabaseManager.client.functions.invoke(
                "save-observations",
                options: FunctionInvokeOptions(body: request)
            )

        return response
    }
}

