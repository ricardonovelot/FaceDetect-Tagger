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
                            .padding()
                        ScrollView(.horizontal) {
                            HStack{
                                ForEach(viewModel.faceThumbnails, id: \.self) { thumbnail in
                                    Image(uiImage: thumbnail)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 50, height: 50)
                                        .clipShape(Circle())
                                        .padding(4)
                                        .onTapGesture {
                                            viewModel.showAddNameSheet = true
                                            viewModel.newContactPhoto = thumbnail
                                        }
                                }
                            }
                        }
                        .padding()
                    }
                    
                    
                    Section{
                        ForEach(viewModel.selectedNames){ contact in
                            Text(contact.name)
                        }
                    }
                    
                    Section{
                        TextField("", text: $viewModel.searchText, prompt: Text("Test"))
                            .onChange(of: viewModel.searchText) { newValue in
                                viewModel.updateSearchResults()
                            }
                            .autocorrectionDisabled(true)
                            .onSubmit{
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation{
                                        viewModel.searchText = ""
                                    }
                                }
                                // move to viewcontroller
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
                                .foregroundStyle(contact.selected == true ? Color(uiColor: .secondaryLabel) : Color(uiColor: .label))
                        }
                    }
                    
                }
            }
            .task {
                await viewModel.detectFaces()
            }
            .sheet(isPresented: $viewModel.showAddNameSheet) {
                Image(uiImage: viewModel.newContactPhoto)
                    .resizable()
                    .scaledToFit()
                TextField("Add Name", text: $viewModel.newContactName)
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

extension Contact{
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


extension PhotoView {
    class PhotoViewModel: ObservableObject {
        
        @Published var showSheet = false
        @Published var showAddNameSheet = false
        @Published var showPhotosPicker = false
        
        @Published var contacts: [Contact] = []
        @Published var imageItem: UIImage = UIImage()
        @Published var selectedItem: PhotosPickerItem?
        @Published var newContactName = ""
        @Published var newContactPhoto = UIImage()
        @Published var searchResults: [Contact] = []
        @Published var selectedNames: [Contact] = []
        @Published var searchText = ""
        
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
       
        var detectedFaces: [FaceObservation] = []
        @Published var faceThumbnails: [UIImage] = []
        
        func detectFaces() async {
            
            
            
            guard let cgImage = imageItem.cgImage else {
                print("Failed to get CGImage from UIImage")
                return
            }
            let request = DetectFaceRectanglesRequest()
            
            
            let handler = ImageRequestHandler(cgImage)

            
            do {
                self.detectedFaces = try await handler.perform(request)
                await generateFaceThumbnails()
            } catch {
                print("Error performing face detection: \(error)")
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
                    faceThumbnails.append(thumbnail)
                }
            }
        }
        
        private func sortFaceThumbnails(_ faces: [FaceObservation], imageSize: CGSize) -> [FaceObservation] {
            // AI Assisted: Sort the FaceObservation array based on each face's relative position in the image.
            
            guard let firstFace = faces.first else {
                print("No faces detected")
                return []
            }
            
            let firstBoundingBox = firstFace.boundingBox
            let boxHeight = firstBoundingBox.height * imageSize.height
            let rowThreshold = boxHeight * 1.5 // Adjust as needed
            
            // Group faces into rows
            var rows: [[FaceObservation]] = []
            var currentRow: [FaceObservation] = []
            var lastY: CGFloat? = nil
            
            for face in faces.sorted(by: { $0.boundingBox.origin.y < $1.boundingBox.origin.y }) {
                let boundingBox = face.boundingBox
                let faceY = boundingBox.origin.y
                
                if let lastY = lastY {
                    if abs(faceY - lastY) * imageSize.height > rowThreshold {
                        // Start a new row
                        rows.append(currentRow)
                        currentRow = []
                    }
                }
                currentRow.append(face)
                lastY = faceY
            }
            // Append the last row
            if !currentRow.isEmpty {
                rows.append(currentRow)
            }
            
            // Sort rows by their average y-coordinate
            let sortedRows = rows.sorted { row1, row2 in
                let avgY1 = row1.map { $0.boundingBox.origin.y }.reduce(0, +) / CGFloat(row1.count)
                let avgY2 = row2.map { $0.boundingBox.origin.y }.reduce(0, +) / CGFloat(row2.count)
                return avgY1 > avgY2
            }
            
            // Flatten sorted rows into a single array and sort each row by x-coordinate
            return sortedRows.flatMap { row in
                row.sorted { $0.boundingBox.origin.x < $1.boundingBox.origin.x }
            }
        }



    }
}

#Preview {
    PhotoView()
}
