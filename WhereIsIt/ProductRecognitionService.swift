
import Foundation
import Supabase

struct BoundingBox: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct RecognizedProduct: Codable, Identifiable {
    var id = UUID()

    var brand: String?
    var name: String
    var variety: String?
    var packageSize: String?
    var shelfFromTop: Int
    let identification: String
    let boundingBox: BoundingBox

    enum CodingKeys: String, CodingKey {
        case brand, name, variety, packageSize
        case shelfFromTop, identification, boundingBox
    }
}

struct RecognitionResponse: Codable {
    let model: String
    let productCount: Int
    let products: [RecognizedProduct]
}

struct RecognitionRequest: Encodable {
    let imageBase64: String
    let mimeType: String
}

enum ProductRecognitionService {

    static func analyze(
        imageData: Data
    ) async throws -> RecognitionResponse {

        try await AuthenticationManager.shared
            .ensureAuthenticated()

        let request = RecognitionRequest(
            imageBase64: imageData.base64EncodedString(),
            mimeType: "image/jpeg"
        )

        let response: RecognitionResponse =
            try await SupabaseManager.client.functions.invoke(
                "recognize-products",
                options: FunctionInvokeOptions(body: request)
            )

        return response
    }
}

