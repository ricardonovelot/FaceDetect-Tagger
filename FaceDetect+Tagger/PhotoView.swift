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
                        Image(uiImage: viewModel.imageItem)
                            .resizable()
                            .scaledToFit()
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
                    .listRowInsets(EdgeInsets())
                    
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
            for i in 1...7 {
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
        }
        
        @MainActor
        private func generateFaceThumbnails() {
            faceThumbnails = []
            
            guard let cgImage = imageItem.cgImage else {
                print("Failed to get CGImage from UIImage")
                return
            }
            
            let imageSize = CGSize(width: imageItem.size.width, height: imageItem.size.height)
            
            let sortedFaces = sortFaceThumbnails(detectedFaces, imageSize: imageSize)
            
            for face in sortedFaces {
                let boundingBox = face.boundingBox
                
                let scaleFactor: CGFloat = 1.6 // Adjust this value to increase the box size (1.0 = original size)

                let scaledBox = CGRect(
                    x: boundingBox.origin.x * imageSize.width - (boundingBox.width * imageSize.width * (scaleFactor - 1)) / 2,
                    y: (1 - boundingBox.origin.y - boundingBox.height) * imageSize.height - (boundingBox.height * imageSize.height * (scaleFactor - 1)) / 2,
                    width: boundingBox.width * imageSize.width * scaleFactor,
                    height: boundingBox.height * imageSize.height * scaleFactor
                )
                
                if let cgCroppedImage = cgImage.cropping(to: scaledBox) {
                    let thumbnail = UIImage(cgImage: cgCroppedImage)
                    faceThumbnails.append(FaceThumbnail(image: thumbnail))
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
    }
}

#Preview {
    PhotoView()
}
