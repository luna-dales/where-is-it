
import SwiftUI
import PhotosUI
import UIKit

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "basket.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.green)

                Text("WhereIsIt")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Find what you need, where you shop.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                NavigationLink {
                    FindProductView()
                } label: {
                    Label("Find Product",
                          systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                NavigationLink {
                    ContributePhotoView()
                } label: {
                    Label("Contribute Photo",
                          systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.bordered)
                .tint(.green)

                Spacer()
            }
            .padding(24)
            .navigationTitle("WhereIsIt")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                            .accessibilityLabel("Settings")
                    }
                }
            }
        }
        .task {
            do {
                try await AuthenticationManager.shared
                    .ensureAuthenticated()
            } catch {
                print("Supabase authentication error: \(error)")
            }
        }
    }
}


struct FindProductView: View {
    @State private var searchText = ""
    @State private var results: [ProductLocation] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var hasSearched = false
    @StateObject private var speechRecognition = SpeechRecognitionService()
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                TextField("Search for a grocery product", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await searchProducts() }
                    }
                    .accessibilityLabel("Product name or brand")

                Button("Search") {
                    Task { await searchProducts() }
                }
                .disabled(
                    searchText.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty || isSearching
                )
            }
            .padding(.horizontal)

            VStack(spacing: 10) {
                Button {
                    if speechRecognition.isListening {
                        speechRecognition.stopListening()

                        if !searchText.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty {
                            Task {
                                await searchProducts()
                            }
                        }
                    } else {
                        Task {
                            await speechRecognition.startListening()
                        }
                    }
                } label: {
                    Label(
                        speechRecognition.isListening
                            ? "Stop and Search"
                            : "Speak to Search",
                        systemImage: speechRecognition.isListening
                            ? "stop.circle.fill"
                            : "mic.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(speechRecognition.isListening ? .red : .blue)
                .disabled(isSearching)
                .accessibilityHint(
                    speechRecognition.isListening
                        ? "Stops listening and searches for the spoken product"
                        : "Starts listening for a grocery product name"
                )

                if speechRecognition.isListening {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Listening... Speak a product name")
                    }
                    .font(.subheadline)
                    .accessibilityLabel("Listening for product name")
                }

                if let error = speechRecognition.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal)
            .onChange(of: speechRecognition.transcript) { _, newValue in
                searchText = newValue
            }
            .onDisappear {
                speechRecognition.stopListening()
            }

            if isSearching {
                ProgressView("Searching products...")
                Spacer()
            } else if let errorMessage {
                ContentUnavailableView(
                    "Search Failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if results.isEmpty {
                ContentUnavailableView(
                    hasSearched ? "No Products Found" : "Find a Product",
                    systemImage: "magnifyingglass",
                    description: Text(
                        hasSearched
                        ? "Try another product name or brand."
                        : "Search for products previously photographed in a grocery store."
                    )
                )
            } else {
                List(results) { location in
                    NavigationLink(destination: ProductDetailView(location: location)) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(location.productName)
                                .font(.headline)
                            
                            if let brand = location.brand,
                               !brand.isEmpty {
                                Text(brand)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Label(
                                location.storeName,
                                systemImage: "storefront"
                            )
                            .font(.subheadline)
                            
                            HStack {
                                Label(
                                    "Aisle \(location.aisleNumber)",
                                    systemImage: "number"
                                )
                                
                                Text("·")
                                
                                Text("\(location.shelfSide) side")
                            }
                            .font(.subheadline)
                            
                            Text(
                                "Shelf \(location.shelfFromTop) from top"
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Find Product")
    }

    @MainActor
    private func searchProducts() async {
        guard !isSearching else { return }

        isSearching = true
        errorMessage = nil
        hasSearched = true

        defer { isSearching = false }

        do {
            results = try await ProductSearchService.search(
                query: searchText
            )
        } catch {
            results = []
            errorMessage = error.localizedDescription
        }
    }
}





struct ContributePhotoView: View {
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var isLoading = false
    @State private var isAnalyzing = false
    @State private var showCamera = false
    @State private var errorMessage: String?
    @State private var recognitionResult: RecognitionResponse?
    @State private var selectedProductID: UUID?
    @State private var editedProducts: [RecognizedProduct] = []
    @State private var showingProductEditor = false
    @State private var showingDeleteConfirmation = false
    @State private var showingReviewSummary = false
    @State private var reviewCompleted = false
    @State private var stores: [GroceryStore] = []
    @State private var selectedStoreID: UUID?
    @State private var isLoadingStores = false
    @State private var storeError: String?
    @State private var aisleNumber = ""
    @State private var shelfSide = "Left"
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var savedObservationCount = 0
    @State private var pendingPhotoID: String?
    @State private var pendingImagePath: String?
    @State private var analyzedImage: UIImage?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Grocery Store")
                        .font(.headline)

                    if isLoadingStores {
                        ProgressView("Loading stores...")
                    } else if let storeError {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(storeError)
                                .foregroundStyle(.red)

                            Button("Retry") {
                                Task {
                                    await loadStores()
                                }
                            }
                        }
                    } else if stores.isEmpty {
                        Text("No grocery stores available.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Select Store", selection: $selectedStoreID) {
                            Text("Choose a store")
                                .tag(nil as UUID?)

                            ForEach(stores) { store in
                                Text(store.name)
                                    .tag(Optional(store.id))
                            }
                        }
                        .pickerStyle(.menu)

                        if let selectedStoreID,
                           let store = stores.first(where: {
                               $0.id == selectedStoreID
                           }),
                           !store.displayAddress.isEmpty {
                            Text(store.displayAddress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Shelf Location")
                        .font(.headline)

                    HStack {
                        Text("Aisle")
                            .frame(width: 65, alignment: .leading)

                        TextField("e.g. 7 or 12A", text: $aisleNumber)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.characters)
                            .accessibilityLabel("Aisle number")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Shelf Side")

                        Picker("Shelf Side", selection: $shelfSide) {
                            Text("Left").tag("Left")
                            Text("Right").tag("Right")
                        }
                        .pickerStyle(.segmented)
                    }

                    Text(
                        "Choose the side of the aisle as viewed " +
                        "from its numbered starting end."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                
                if let photoData,
                   let image = UIImage(data: photoData) {
                    ProductPhotoOverlay(
                        image: image,
                        products: editedProducts,
                        selectedProductID: $selectedProductID
                    )
                    .frame(height: 300)
                    .accessibilityLabel(
                        "Grocery shelf photograph with recognized products"
                    )
                    
                    if let selectedProductID,
                       let product = editedProducts.first(
                           where: { $0.id == selectedProductID }
                       ) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Selected Product")
                                .font(.headline)

                            Text(product.name)
                                .font(.title3)
                                .fontWeight(.semibold)

                            if let brand = product.brand {
                                Text("Brand: \(brand)")
                            }

                            if let variety = product.variety {
                                Text("Variety: \(variety)")
                            }

                            Text("Shelf \(product.shelfFromTop) from top")
                                .foregroundStyle(.secondary)
                            
                            Button {
                                showingProductEditor = true
                            } label: {
                                Label("Edit Product", systemImage: "pencil")
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button(role: .destructive) {
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Remove Product", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                } else {
                    ContentUnavailableView(
                        "No Photo Selected",
                        systemImage: "camera.fill",
                        description: Text(
                            "Take a photo or choose one from your library."
                        )
                    )
                }

                Button {
                    if UIImagePickerController
                        .isSourceTypeAvailable(.camera) {
                        showCamera = true
                    } else {
                        errorMessage =
                            "Camera is unavailable on this device."
                    }
                } label: {
                    Label("Take Photo", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isLoading || isAnalyzing)

                PhotosPicker(
                    selection: $selectedPhoto,
                    matching: .images
                ) {
                    Label(
                        "Choose from Photo Library",
                        systemImage: "photo.on.rectangle"
                    )
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .disabled(isLoading || isAnalyzing)

                if isLoading {
                    ProgressView("Loading photograph...")
                }

                if photoData != nil {
                    Button {
                        Task {
                            await analyzePhoto()
                        }
                    } label: {
                        Label(
                            "Analyze Products",
                            systemImage: "sparkles"
                        )
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(isLoading || isAnalyzing)
                }

                if isAnalyzing {
                    ProgressView("Identifying products...")
                        .padding()
                }

                if let result = recognitionResult {
                    resultsSection(result)

                    Button {
                        showingReviewSummary = true
                    } label: {
                        Label(
                            "Review Complete",
                            systemImage: "checkmark.circle.fill"
                        )
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(
                        isSaving ||
                        reviewCompleted ||
                        editedProducts.isEmpty ||
                        selectedStoreID == nil ||
                        aisleNumber.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                    
                    if isSaving {
                        ProgressView("Saving products to Supabase...")
                            .padding()
                    }

                    if let saveError {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(saveError)
                                .foregroundStyle(.red)

                            Button("Dismiss Error") {
                                self.saveError = nil
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    if reviewCompleted {
                        Label(
                            "\(savedObservationCount) products saved successfully",
                            systemImage: "checkmark.seal.fill"
                        )
                        .foregroundStyle(.green)
                        .font(.headline)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Contribute Photo")
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in
                photoData = image.jpegData(
                    compressionQuality: 0.85
                )
                selectedPhoto = nil
                recognitionResult = nil
                editedProducts = []
                selectedProductID = nil
                reviewCompleted = false
                pendingPhotoID = nil
                pendingImagePath = nil
                savedObservationCount = 0
                saveError = nil
            }
        }
        .task {
            await loadStores()
        }
        .confirmationDialog(
            "Complete Product Review?",
            isPresented: $showingReviewSummary,
            titleVisibility: .visible
        ) {
            Button("Save Reviewed Products") {
                Task {
                    await saveReviewedProducts()
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                """
                Store: \(selectedStoreName)
                Aisle: \(aisleNumber)
                Side: \(shelfSide)
                Products: \(editedProducts.count)

                The reviewed product locations will be saved to Supabase.
                """
            )
        }

        .onChange(of: selectedPhoto) { _, newValue in
            guard let newValue else { return }

            Task {
                isLoading = true
                recognitionResult = nil
                editedProducts = []
                selectedProductID = nil
                reviewCompleted = false
                pendingPhotoID = nil
                pendingImagePath = nil
                savedObservationCount = 0
                saveError = nil
                
                defer { isLoading = false }

                do {
                    photoData = try await newValue
                        .loadTransferable(type: Data.self)

                    if photoData == nil {
                        errorMessage = "Unable to load the photo."
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .confirmationDialog(
            "Remove this product?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Product", role: .destructive) {
                guard let selectedProductID else { return }

                editedProducts.removeAll {
                    $0.id == selectedProductID
                }

                self.selectedProductID = nil
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This removes the detection from the current " +
                "review. The original photograph is unchanged."
            )
        }
        .sheet(
            isPresented: $showingProductEditor,
            onDismiss: {
                reviewCompleted = false
            }
        ) {
            if let selectedProductID,
               let index = editedProducts.firstIndex(
                   where: { $0.id == selectedProductID }
               ) {
                ProductEditorView(product: $editedProducts[index])
            }
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }


    @MainActor
    private func loadStores() async {
        isLoadingStores = true
        storeError = nil

        defer {
            isLoadingStores = false
        }

        do {
            stores = try await StoreService.fetchStores()

            // Automatically select the store when
            // only one is available.
            if stores.count == 1 {
                selectedStoreID = stores[0].id
            } else if let selectedStoreID,
                      !stores.contains(where: {
                          $0.id == selectedStoreID
                      }) {
                self.selectedStoreID = nil
            }
        } catch {
            storeError = "Unable to load stores: \(error.localizedDescription)"
        }
    }
            
    private var selectedStoreName: String {
        stores.first(where: {
            $0.id == selectedStoreID
        })?.name ?? "Unknown"
    }

    
    @MainActor
    private func saveReviewedProducts() async {
        guard !isSaving, !reviewCompleted else { return }

        guard let selectedStoreID else {
            saveError = "Please select a grocery store."
            return
        }

        let aisle = aisleNumber.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !aisle.isEmpty else {
            saveError = "Please enter an aisle number."
            return
        }

        guard !editedProducts.isEmpty else {
            saveError = "There are no products to save."
            return
        }

        guard let photoData,
              let image = UIImage(data: photoData) else {
            saveError = "Please select a valid photograph."
            return
        }

        isSaving = true
        saveError = nil

        defer {
            isSaving = false
        }

        // Phase 1: Save the observations exactly once.
        if pendingPhotoID == nil {
            do {
                let result = try await ObservationService.save(
                    storeId: selectedStoreID,
                    aisleNumber: aisle,
                    shelfSide: shelfSide,
                    products: editedProducts
                )

                guard result.success else {
                    saveError = "The server did not confirm the save."
                    return
                }

                savedObservationCount = result.savedCount

                // Retain this ID for retries.
                pendingPhotoID = String(describing: result.photoId)

            } catch {
                saveError = "Unable to save products: \(error.localizedDescription)"
                return
            }
        }

        guard let photoID = pendingPhotoID else {
            saveError = "The server did not return a photo record ID."
            return
        }

        // Phase 2: Upload the photograph exactly once.
        if pendingImagePath == nil {
            do {
                pendingImagePath = try await
                    PhotoStorageService.uploadPhoto(
                        image: analyzedImage ?? image
                    )
            } catch {
                saveError = """
                Products were saved, but the photograph upload failed:
                \(error.localizedDescription)

                Please try saving again to retry the photograph upload.
                """
                return
            }
        }

        guard let imagePath = pendingImagePath else {
            saveError = "The photograph storage path is missing."
            return
        }

        // Phase 3: Link the uploaded image to the saved record.
        do {
            try await SupabaseManager.client
                .rpc(
                    "link_shelf_photo",
                    params: [
                        "p_photo_id": photoID,
                        "p_image_path": imagePath
                    ]
                )
                .execute()

            reviewCompleted = true
            saveError = nil

        } catch {
            saveError = """
            Products and photograph were saved, but linking failed:
            \(error.localizedDescription)

            Please try saving again to retry the link.
            """
        }
    }

    
    private func analyzePhoto() async {
        guard let photoData,
              let image = UIImage(data: photoData) else {
            errorMessage = "Please select a valid photograph."
            return
        }

        isAnalyzing = true
        recognitionResult = nil
        editedProducts = []
        selectedProductID = nil
        reviewCompleted = false
        defer { isAnalyzing = false }

        // Resize to control upload size and processing cost.
        let maxDimension: CGFloat = 2048
        let originalSize = image.size
        let scale = min(
            1,
            maxDimension / max(
                originalSize.width,
                originalSize.height
            )
        )

        let targetSize = CGSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )

        let renderer = UIGraphicsImageRenderer(
            size: targetSize
        )

        let resizedImage = renderer.image { _ in
            image.draw(
                in: CGRect(
                    origin: .zero,
                    size: targetSize
                )
            )
        }
        
        analyzedImage = resizedImage

        guard let jpegData = resizedImage.jpegData(
            compressionQuality: 0.85
        ) else {
            errorMessage = "Unable to prepare photograph."
            return
        }

        do {
            let result =
                try await ProductRecognitionService.analyze(
                    imageData: jpegData
                )

            recognitionResult = result
            editedProducts = result.products
        } catch {
            errorMessage =
                "Product recognition failed: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private func resultsSection(
        _ result: RecognitionResponse
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recognized Products")
                .font(.title2)
                .fontWeight(.bold)

            Text("\(editedProducts.count) products in review")
                .foregroundStyle(.secondary)

            ForEach(editedProducts) { product in
                VStack(alignment: .leading, spacing: 6) {
                    Text(product.name)
                        .font(.headline)

                    if let brand = product.brand {
                        Text(brand)
                            .font(.subheadline)
                    }

                    if let variety = product.variety {
                        Text("Variety: \(variety)")
                    }

                    if let size = product.packageSize {
                        Text("Size: \(size)")
                    }

                    Text(
                        "Shelf \(product.shelfFromTop) from top"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text(
                        "Identification: \(product.identification)"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .padding()
                .background(
                    Color(.secondarySystemBackground)
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: 12)
                )
            }
        }
    }
}


struct ProductEditorView: View {
    @Binding var product: RecognizedProduct

    @Environment(\.dismiss) private var dismiss

    @State private var brand = ""
    @State private var name = ""
    @State private var variety = ""
    @State private var packageSize = ""
    @State private var shelfFromTop = 1

    var body: some View {
        NavigationStack {
            Form {
                Section("Product Identification") {
                    TextField("Product Name", text: $name)

                    TextField("Brand", text: $brand)

                    TextField("Variety", text: $variety)

                    TextField("Package Size", text: $packageSize)
                }

                Section("Shelf Location") {
                    Stepper(
                        "Shelf \(shelfFromTop) from top",
                        value: $shelfFromTop,
                        in: 1...20
                    )
                }

                Section {
                    Text(
                        "Review the product packaging before " +
                        "saving corrections."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        product.brand = optionalText(brand)
                        product.name = name.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        product.variety = optionalText(variety)
                        product.packageSize = optionalText(packageSize)
                        product.shelfFromTop = shelfFromTop

                        dismiss()
                    }
                    .disabled(
                        name.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }
            }
            .onAppear {
                brand = product.brand ?? ""
                name = product.name
                variety = product.variety ?? ""
                packageSize = product.packageSize ?? ""
                shelfFromTop = product.shelfFromTop
            }
        }
    }

    private func optionalText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.isEmpty ? nil : trimmed
    }
}



struct CameraPicker: UIViewControllerRepresentable {
    let onPhotoCaptured: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(
        context: Context
    ) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIImagePickerController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject,
                       UIImagePickerControllerDelegate,
                       UINavigationControllerDelegate {

        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info:
                [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onPhotoCaptured(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(
            _ picker: UIImagePickerController
        ) {
            parent.dismiss()
        }
    }
}


struct ProductPhotoOverlay: View {
    let image: UIImage
    let products: [RecognizedProduct]

    @Binding var selectedProductID: UUID?

    var body: some View {
        GeometryReader { geometry in
            let imageSize = image.size

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
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )

                ForEach(products) { product in
                    let index = products.firstIndex {
                        $0.id == product.id
                    } ?? 0

                    let box = product.boundingBox

                    let x = offsetX + box.x * displayedWidth
                    let y = offsetY + box.y * displayedHeight
                    let width = box.width * displayedWidth
                    let height = box.height * displayedHeight

                    let isSelected =
                        selectedProductID == product.id

                    Button {
                        selectedProductID = product.id
                    } label: {
                        ZStack(alignment: .topLeading) {
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())

                            Rectangle()
                                .stroke(
                                    isSelected
                                        ? Color.blue
                                        : product.identification == "uncertain"
                                            ? Color.orange
                                            : Color.green,
                                    lineWidth: isSelected ? 4 : 2
                                )

                            Text("\(index + 1)")
                                .font(.system(
                                    size: 11,
                                    weight: .bold
                                ))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(
                                    isSelected
                                        ? Color.blue
                                        : Color.green
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(width: width, height: height)
                    .position(
                        x: x + width / 2,
                        y: y + height / 2
                    )
                    .accessibilityLabel(
                        "\(product.name), shelf \(product.shelfFromTop)"
                    )
                }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
        }
        .clipped()
    }
}


#Preview {
    ContentView()
}

