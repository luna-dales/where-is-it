
import SwiftUI
import Supabase
import UIKit

struct ProductDetailView: View {
    let location: ProductLocation

    @State private var shelfImage: UIImage?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                VStack(alignment: .leading, spacing: 6) {
                    Text(location.productName)
                        .font(.title2.bold())

                    if let brand = location.brand, !brand.isEmpty {
                        Text(brand)
                            .foregroundStyle(.secondary)
                    }

                    Label(location.storeName, systemImage: "storefront")

                    Text(
                        "Aisle \(location.aisleNumber) · \(location.shelfSide) side"
                    )

                    Text("Shelf \(location.shelfFromTop) from top")
                        .foregroundStyle(.secondary)
                    
                    Button {
                        let shelfNumber = location.shelfFromTop

                        let shelfDescription: String
                        switch shelfNumber {
                        case 1:
                            shelfDescription = "top shelf"
                        case 2:
                            shelfDescription = "second shelf from the top"
                        case 3:
                            shelfDescription = "third shelf from the top"
                        default:
                            shelfDescription = "shelf \(shelfNumber) from the top"
                        }

                        let productDescription: String
                        if let brand = location.brand, !brand.isEmpty {
                            productDescription = "\(location.productName) by \(brand)"
                        } else {
                            productDescription = location.productName
                        }

                        let announcement = """
                        \(productDescription).
                        At \(location.storeName).
                        Aisle \(location.aisleNumber),
                        \(location.shelfSide.lowercased()) side,
                        \(shelfDescription).
                        """

                        SpeechService.shared.speak(announcement)

                    } label: {
                        Label("Speak Location", systemImage: "speaker.wave.2.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .accessibilityHint("Reads the product's location aloud")
                }

                if isLoading {
                    ProgressView("Loading shelf photograph...")

                } else if let shelfImage {

                    GeometryReader { geometry in
                        let imageSize = shelfImage.size

                        let scale = min(
                            geometry.size.width / imageSize.width,
                            geometry.size.height / imageSize.height
                        )

                        let displayedWidth = imageSize.width * scale
                        let displayedHeight = imageSize.height * scale

                        let offsetX =
                            (geometry.size.width - displayedWidth) / 2
                        let offsetY =
                            (geometry.size.height - displayedHeight) / 2

                        ZStack(alignment: .topLeading) {

                            Image(uiImage: shelfImage)
                                .resizable()
                                .scaledToFit()
                                .frame(
                                    width: geometry.size.width,
                                    height: geometry.size.height
                                )

                            if let x = location.boundingX,
                               let y = location.boundingY,
                               let width = location.boundingWidth,
                               let height = location.boundingHeight {

                                let boxX = offsetX + x * displayedWidth
                                let boxY = offsetY + y * displayedHeight
                                let boxWidth = width * displayedWidth
                                let boxHeight = height * displayedHeight

                                Rectangle()
                                    .stroke(Color.yellow, lineWidth: 4)
                                    .background(
                                        Color.yellow.opacity(0.15)
                                    )
                                    .frame(
                                        width: boxWidth,
                                        height: boxHeight
                                    )
                                    .position(
                                        x: boxX + boxWidth / 2,
                                        y: boxY + boxHeight / 2
                                    )
                            }
                        }
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                    }
                    .frame(
                        height: shelfImage.size.height *
                            (UIScreen.main.bounds.width - 32) /
                            shelfImage.size.width
                    )

                    Text(
                        "The yellow rectangle highlights the product's position."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                } else if let errorMessage {
                    ContentUnavailableView(
                        "Photograph Unavailable",
                        systemImage: "photo",
                        description: Text(errorMessage)
                    )

                } else {
                    ContentUnavailableView(
                        "No Photograph",
                        systemImage: "photo",
                        description: Text(
                            "This observation was saved before photograph storage was enabled."
                        )
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Product Location")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadPhotograph()
        }
    }

    @MainActor
    private func loadPhotograph() async {
        guard let imagePath = location.imagePath,
              !imagePath.isEmpty else {
            return
        }

        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            try await AuthenticationManager.shared
                .ensureAuthenticated()

            let data = try await SupabaseManager.client.storage
                .from("shelf-photos")
                .download(path: imagePath)

            guard let image = UIImage(data: data) else {
                errorMessage = "Unable to decode the photograph."
                return
            }

            shelfImage = image

        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

