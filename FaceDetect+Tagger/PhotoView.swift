//
//  ContentView.swift
//  FaceDetect+Tagger
//
//  Created by Ricardo on 22/08/24.
//

import SwiftUI
import SwiftData
import PhotosUI
import Vision

struct PhotoView: View {
    @ObservedObject var viewModel = PhotoViewModel()
    
    var body: some View {
        NavigationStack{
            List(viewModel.contacts){ contact in
                Text(contact.name)
            }
            .contentMargins(.top, 12)
            .navigationTitle("Faces")
            .toolbar{
                ToolbarItemGroup(placement: .primaryAction) {
                    Button{
                        viewModel.showPhotosPicker = true
                    } label: {
                        Image(systemName: "photo.on.rectangle.angled")
                    }
                }
                ToolbarItemGroup(placement: .secondaryAction) {
                    Button(action: viewModel.loadSampleImages){
                        Label("Use Sample Images", systemImage: "document")
                    }
                }
            }
            .overlay {
                if viewModel.contacts.isEmpty {
                    ContentUnavailableView {
                        Label("Oh no!", systemImage: "person.fill")
                    } description: {
                        Text("It looks like you haven’t added any faces yet.")
                    } actions: {
                        Button("Add new face"){
                            viewModel.showPhotosPicker = true
                        }
                    }
                }
            }
        }
        .photosPicker(isPresented: $viewModel.showPhotosPicker, selection: $viewModel.selectedItem)
        .task(id:viewModel.selectedItem) {
            await viewModel.loadSelectedImage()
        }
        .sheet(isPresented: $viewModel.showSheet) {
            NavigationView {
                List{
                    ZStack(alignment: .bottom){
                        if let outputImage = viewModel.imageWithDetections {
                            Image(uiImage: outputImage)
                                .resizable()
                                .scaledToFit()
                        } else {
                            Image(uiImage: viewModel.imageItem)
                                .resizable()
                                .scaledToFit()
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    
                    Section{
                        ScrollView(.horizontal) {
                            HStack{
                                ForEach(viewModel.faceThumbnails, id: \.id) { thumbnail in
                                    Image(uiImage: thumbnail.image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 50, height: 50)
                                        .clipShape(Circle())
                                        .padding(4)
                                        .overlay(
                                            Circle()
                                                .stroke(thumbnail.isSelected ? Color.blue : Color.clear, lineWidth: 2)
                                        )
                                        .onTapGesture {
                                            // Deselect all thumbnails first
                                            viewModel.deselectAllThumbnails()
                                            // Select only the tapped thumbnail
                                            if let index = viewModel.faceThumbnails.firstIndex(where: { $0.id == thumbnail.id }) {
                                                viewModel.faceThumbnails[index].isSelected = true
                                            }
                                        }
                                }
                            }
                        }
                    }
                    
                    
                    Section{
                        ForEach(viewModel.selectedNames){ contact in
                            Text(contact.name)
                        }
                    }
                    
                    Section{
                        TextField("", text: $viewModel.searchText, prompt: Text("Test"))
                            .onChange(of: viewModel.searchText) { oldValue, newValue in
                                viewModel.updateSearchResults()
                            }
                            .autocorrectionDisabled(true)
                            .onSubmit{
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation{
                                        viewModel.searchText = ""
                                    }
                                }
                                if let firstResult = viewModel.searchResults.first,
                                   let index = viewModel.searchResults.firstIndex(where: { $0.id == firstResult.id }) {
                                    viewModel.selectedNames.append(firstResult)
                                    viewModel.searchResults[index].selected = true
                                }
                            }
                    }

                    Section{
                        ForEach(viewModel.searchResults){ contact in
                            Text(contact.name)
                                .foregroundStyle(contact.selected ? Color(uiColor: .secondaryLabel) : Color(uiColor: .label))
                        }
                    }
                }
            }
            .task {
                await viewModel.detectFaces()
            }
            .onDisappear {
                viewModel.faceThumbnails = []
            }
        }
    }
}

struct Contact: Identifiable {
    var id = UUID()
    var name: String
    var selected: Bool
    
    func contains(_ query: String) -> Bool {
        return name.lowercased().contains(query.lowercased())
    }
}

extension Contact {
    static var samples: [Contact] {
        return [
            Contact(name: "Rachel Green", selected: false),
            Contact(name: "Phoebe Buffay", selected: false),
            Contact(name: "Chandler Bing", selected: false),
            Contact(name: "Ross Geller", selected: false),
            Contact(name: "Monica Geller", selected: false),
            Contact(name: "Joey Tribbiani", selected: false)
        ]
    }
}

struct FaceThumbnail: Identifiable, Hashable {
    var id = UUID()
    var image: UIImage
    var isSelected: Bool = false
}

extension PhotoView {
    class PhotoViewModel: ObservableObject {
        
        @Published var showSheet = false
        @Published var showAddNameSheet = false
        @Published var showPhotosPicker = false
        
        @Published var contacts: [Contact] = []
        @Published var imageItem: UIImage = UIImage()
        @Published var selectedItem: PhotosPickerItem?
        @Published var newContactName = ""
        @Published var searchResults: [Contact] = []
        @Published var selectedNames: [Contact] = []
        @Published var searchText = ""
        var detectedFaces: [VNFaceObservation] = []
        @Published var faceThumbnails: [FaceThumbnail] = []
        
        var photoGalleryImages: [UIImage] = []
        
        @Published var imageWithDetections: UIImage?
        
        init(){
            addSampleData()
            searchResults = Contact.samples
        }
        
        func loadSampleImages(){
            #if DEBUG
            deleteAllPhotoLibraryPhotos()
            #endif
            addSampleGalleryImages()
        }
        
        func addSampleData() {
            contacts = Contact.samples
        }
        
        func addSampleGalleryImages() {
            for i in 1...9 {
                if let image = UIImage(named: "test-\(i)") {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                }
            }
        }
        
        func deleteAllPhotoLibraryPhotos() {
            let assetsToDelete = PHAsset.fetchAssets(with: .image, options: nil)
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets(assetsToDelete)
            }) { success, error in
                if !success {
                    print("Error deleting photos: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
        
        func loadSelectedImage() async {
            if let pickerItem = selectedItem {
                if let imageData = try? await pickerItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: imageData) {
                    DispatchQueue.main.async {
                        self.imageItem = uiImage
                        self.showSheet = true
                        self.selectedItem = nil
                    }
                }
            }
        }
        
        // MARK: Photo Entry View Model
        
        func updateSearchResults() {
            let query = searchText.lowercased()
            searchResults = contacts.filter { contact in
                contact.contains(query)
            }
        }
       
        func detectFaces() async {
            
            guard let cgImage = imageItem.cgImage else {
                print("Failed to get CGImage from UIImage")
                return
            }
            
            let request = VNDetectFaceRectanglesRequest(completionHandler: completionHandler)
            
#if targetEnvironment(simulator)
            let allDevices = MLComputeDevice.allComputeDevices
            for device in allDevices {
                request.setComputeDevice(device, for: .main)
            }
#endif
            
            let handler = VNImageRequestHandler(cgImage: cgImage)
            
            do {
                try handler.perform([request])
                await generateFaceThumbnails()
            } catch {
                print("Error performing face detection: \(error)")
            }
            
            func completionHandler (request: VNRequest, error: Error?) {
                guard
                    let barcodeObservations = request.results as? [VNFaceObservation] else {
                    return
                }
                self.detectedFaces = barcodeObservations
                
                
            }
            
            print("Number of faces detected on first round: \(detectedFaces.count)")
            
            if self.detectedFaces.isEmpty {
                let imageWidth = cgImage.width
                let imageHeight = cgImage.height
                
                for segment in 0..<2 {
                    let segmentWidth = imageWidth / 2
                    let xOffset = segment * segmentWidth
                    let segmentRect = CGRect(x: xOffset, y: 0, width: segmentWidth, height: imageHeight)
                    
                    // Create a cropped CGImage for the segment
                    guard let croppedImage = cgImage.cropping(to: segmentRect) else { continue }
                    
                    let handler = VNImageRequestHandler(cgImage: croppedImage)
                    
                    do {
                        try handler.perform([request])
                        await generateFaceThumbnails()
                    } catch {
                        print("Error performing face detection: \(error)")
                    }
                    print("Number of faces detected on second round: \(detectedFaces.count)")
                }
            }
        }
           
        
        @MainActor
        private func generateFaceThumbnails() {
            guard let cgImage = imageItem.cgImage else {
                print("Failed to get CGImage from UIImage")
                return
            }

            let imageSize = CGSize(width: imageItem.size.width, height: imageItem.size.height)

            for face in detectedFaces {
                let boundingBox = face.boundingBox

                // No scaling applied; the box will be based directly on the face's boundingBox
                let box = CGRect(
                    x: boundingBox.origin.x * imageSize.width,
                    y: (1 - boundingBox.origin.y - boundingBox.height) * imageSize.height,
                    width: boundingBox.width * imageSize.width,
                    height: boundingBox.height * imageSize.height
                )

                if let cgCroppedImage = cgImage.cropping(to: box) {
                    let thumbnail = UIImage(cgImage: cgCroppedImage)
                    faceThumbnails.append(FaceThumbnail(image: thumbnail))
                } else {
                    print("Failed to crop image for boundingBox: \(boundingBox)")
                }
            }
        }
        
        private func sortFaceThumbnails(_ faces: [VNFaceObservation], imageSize: CGSize) -> [VNFaceObservation] {
            guard let firstFace = faces.first else {
                return faces
            }
            
            // Calculate rowThreshold dynamically based on bounding box size compared to photo size
            let rowThreshold = firstFace.boundingBox.height * imageSize.height * 1.5
            
            // Sort first by the vertical position of the top of the bounding box (y-coordinate), then by the x-coordinate
            let sortedFaces = faces.sorted { (face1, face2) -> Bool in
                let face1Top = (1 - face1.boundingBox.origin.y) * imageSize.height
                let face2Top = (1 - face2.boundingBox.origin.y) * imageSize.height
                
                if abs(face1Top - face2Top) < rowThreshold {
                    return face1.boundingBox.origin.x < face2.boundingBox.origin.x
                } else {
                    return face1Top < face2Top
                }
            }
            return sortedFaces
        }
        
        // Deselect all thumbnails
        func deselectAllThumbnails() {
            faceThumbnails = faceThumbnails.map { FaceThumbnail(id: $0.id, image: $0.image, isSelected: false) }
        }
        
        func addFaceRectsToImage(results: [VNFaceObservation], in image: CGImage){
            let uiImage = UIImage(cgImage: image)
            let imageSize = uiImage.size
            
            // Begin image context for drawing
            UIGraphicsBeginImageContext(imageSize)
            uiImage.draw(at: .zero)
            
            guard let context = UIGraphicsGetCurrentContext() else { return }
            
            // Set up rectangle drawing
            context.setStrokeColor(UIColor.red.cgColor)
            context.setLineWidth(5.0)
            
            for face in results {
                let boundingBox = face.boundingBox
                // Scale bounding box to the image size
                let rect = CGRect(
                    x: boundingBox.origin.x * imageSize.width,
                    y: (1 - boundingBox.origin.y - boundingBox.size.height) * imageSize.height,
                    width: boundingBox.size.width * imageSize.width,
                    height: boundingBox.size.height * imageSize.height
                )
                
                context.stroke(rect) // Draw rectangle
            }
            
            imageWithDetections = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
        }
    }
}

#Preview {
    PhotoView()
}
