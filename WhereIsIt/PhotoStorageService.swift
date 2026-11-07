
import Foundation
import Supabase
import UIKit

enum PhotoStorageError: LocalizedError {
    case invalidImage
    case imageTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The selected photo could not be converted to JPEG."
        case .imageTooLarge:
            return "The photograph exceeds the 8 MB upload limit."
        }
    }
}

enum PhotoStorageService {

    static let bucketName = "shelf-photos"
    static let maximumFileSize = 8 * 1024 * 1024

    /// Uploads a shelf photograph to private Supabase Storage.
    ///
    /// Returns the storage path, not a public URL.
    /// Example: user-uuid/photo-uuid.jpg
    static func uploadPhoto(
        image: UIImage
    ) async throws -> String {

        // Ensure the existing anonymous Supabase session is active.
        try await AuthenticationManager.shared
            .ensureAuthenticated()

        let user = try await SupabaseManager.client.auth.user()

        // Convert the image to JPEG.
        guard let jpegData = image.jpegData(
            compressionQuality: 0.80
        ) else {
            throw PhotoStorageError.invalidImage
        }

        guard jpegData.count <= maximumFileSize else {
            throw PhotoStorageError.imageTooLarge
        }

        // Use the authenticated user's UUID as the folder name.
        // This matches our existing Supabase Storage RLS policy.
        let photoId = UUID()
        let path = "\(user.id.uuidString.lowercased())/\(photoId.uuidString.lowercased()).jpg"

        try await SupabaseManager.client.storage
            .from(bucketName)
            .upload(
                path: path,
                file: jpegData,
                options: FileOptions(
                    contentType: "image/jpeg",
                    upsert: false
                )
            )

        return path
    }
}
//
//  PhotoStorageService.swift
//  WhereIsIt
//
//  Created by Jeffrey Dales on 11/7/26.
//

