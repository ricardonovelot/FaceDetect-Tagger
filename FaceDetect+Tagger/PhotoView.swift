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
                    .gesture(
                        DragGesture(minimumDistance: 30)
                            .onEnded { value in
                                print("gesture captured")
                                guard let index = viewModel.faces.firstIndex(where: { $0.isSelected }) else { return }
                                
                                // Check if the drag was horizontal
                                if abs(value.translation.width) > abs(value.translation.height) {
                                    // Deselect the current face
                                    viewModel.faces[index].isSelected = false
                                    
                                    // Update the index based on the swipe direction
                                    let newIndex = value.translation.width > 0 ? index + 1 : index - 1
                                    
                                    // Ensure the new index is within bounds
                                    if viewModel.faces.indices.contains(newIndex) {
                                        viewModel.faces[newIndex].isSelected = true
                                    } else {
                                        // Revert to the current index if out of bounds
                                        viewModel.faces[index].isSelected = true
                                    }
                                }
                            }
                    )
                    
                   
                        Section{
                            ScrollView(.horizontal) {
                                HStack(spacing: 10){
                                    ForEach(viewModel.faces, id: \.id) { thumbnail in
                                        Image(uiImage: thumbnail.image)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 70, height: 70)
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
                                                if let index = viewModel.faces.firstIndex(where: { $0.id == thumbnail.id }) {
                                                    viewModel.faces[index].isSelected = true
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
                                if let firstResult = viewModel.searchResults.first,
                                   let index = viewModel.searchResults.firstIndex(where: { $0.id == firstResult.id }) {
                                    
                                    // if contacto exite
                                    // agregar face selecctionada a contacto
                                    // else (contacto no existe)
                                    // crear contacto con texto y thumnail seleccionado
                                    //viewModel.contacts[index] =
                                    //viewModel.selectedNames.append(firstResult)
                                    //viewModel.searchResults[index].selected = true
                                }
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation{
                                        viewModel.searchText = ""
                                    }
                                }
                            }
                            
                        // on swipe seleccionar siguiente contacto // seleccionar previo contacto
                        
                    }
                    

                    Section{
                        ForEach(viewModel.searchResults){ contact in
                            Text(contact.name)
                                .foregroundStyle(contact.selected ? Color(uiColor: .secondaryLabel) : Color(uiColor: .label))
                        }
                    }
                }
                
                .task {
                    await viewModel.detectFaces()
                }
            }
            
            .onDisappear {
                viewModel.detectedFaces.removeAll()
                viewModel.faces.removeAll()
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

class Face: Identifiable {
    var id = UUID()
    var image: UIImage
    var isSelected: Bool
    var faceQuality: Float?
    
    init(id: UUID = UUID(), image: UIImage, isSelected: Bool = false, faceQuality: Float? = nil) {
        self.id = id
        self.image = image
        self.isSelected = isSelected
        self.faceQuality = faceQuality
    }
}

extension PhotoView {
    class PhotoViewModel: ObservableObject {
        
        @Published var showSheet = false
        @Published var showAddNameSheet = false
        @Published var showPhotosPicker = false
        
        @Published var contacts: [Contact] = []
        @Published var faces: [Face] = []
        
        @Published var imageItem: UIImage = UIImage()
        @Published var selectedItem: PhotosPickerItem?
        @Published var newContactName = ""
        @Published var searchResults: [Contact] = []
        @Published var selectedNames: [Contact] = []
        @Published var searchText = ""

        @Published var imageWithDetections: UIImage?
        @Published var croppedImages: [CGImage] = []
        
        var detectedFaces: [VNFaceObservation] = []
        var photoGalleryImages: [UIImage] = []
        
        var segments = 1
        var segmentXOffset = 0.0

        
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
                segments = 1
                segmentXOffset = 0
                await generateFaceThumbnails()
            } catch {
                print("Error performing face detection: \(error)")
            }
            
            func completionHandler (request: VNRequest, error: Error?) {
                guard let results = request.results as? [VNFaceObservation] else { return }
                self.detectedFaces.append(contentsOf: results)
            }
            
            print("Number of faces detected on first round: \(detectedFaces.count)")
            
            if self.detectedFaces.isEmpty {
                let imageWidth = cgImage.width
                let imageHeight = cgImage.height
                segments = 2
                
                for segment in 0..<2 {
                    let segmentWidth = imageWidth / 2
                    segmentXOffset = CGFloat(segment * segmentWidth)
                    let segmentRect = CGRect(x: Int(segmentXOffset), y: 0, width: segmentWidth, height: imageHeight)
                    
                    // Create a cropped CGImage for the segment
                    croppedImages.append(cgImage.cropping(to: segmentRect)!)
                    
                    let handler = VNImageRequestHandler(cgImage: croppedImages[segment])
                    
                    do {
                        try handler.perform([request])
                        await generateFaceThumbnails()
                    } catch {
                        print("Error performing face detection: \(error)")
                    }
                    

                    
                    print("Number of faces detected on second round: \(detectedFaces.count)")
                }
            }
            //addFaceRectsToImage()
        }
           
        
        @MainActor
        private func generateFaceThumbnails() {
            guard let cgImage = imageItem.cgImage else {
                print("Failed to get CGImage from UIImage")
                return
            }

            let imageSize = CGSize(width: imageItem.size.width/CGFloat(segments), height: imageItem.size.height)

            
            
            for face in detectedFaces {
                let boundingBox = face.boundingBox

                let scaleFactor: CGFloat = 1.8 // Adjust this value to increase the box size (1.0 = original size)

                let scaledBox = CGRect(
                    x: boundingBox.origin.x * imageSize.width - (boundingBox.width * imageSize.width * (scaleFactor - 1)) / 2,
                    y: (1 - boundingBox.origin.y - boundingBox.height) * imageSize.height - (boundingBox.height * imageSize.height * (scaleFactor - 1)) / 2,
                    width: boundingBox.width * imageSize.width * scaleFactor,
                    height: boundingBox.height * imageSize.height * scaleFactor
                )
                
                if let cgCroppedImage = cgImage.cropping(to: scaledBox) {
                    let thumbnail = UIImage(cgImage: cgCroppedImage)
                    faces.append(Face(image: thumbnail))
                } else {
                    print("Failed to crop image for boundingBox: \(boundingBox)")
                }
            }
        }
        
        func addFaceQuality(){
            let request = VNDetectFaceCaptureQualityRequest()
            
            #if targetEnvironment(simulator)
            let allDevices = MLComputeDevice.allComputeDevices
            for device in allDevices {
                request.setComputeDevice(device, for: .main)
            }
            #endif
            
            for face in faces {
                let requestHandler = VNImageRequestHandler(cgImage: face.image as! CGImage)
                do {
                    try requestHandler.perform([request])
                } catch {
                    print("Can't make the request due to \(error)")
                }
                guard let results = request.results else { return }
                face.faceQuality = results.first?.faceCaptureQuality
            }
            
            
        }
        
        private func sortFaceThumbnails(_ faces: [VNFaceObservation], imageSize: CGSize) -> [VNFaceObservation] {
            guard let firstFace = faces.first else {
                return faces
            }
            // rowThreshold based on bounding box size compared to photo size
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
        
        func deselectAllThumbnails() {
            faces = faces.map { Face(id: $0.id, image: $0.image, isSelected: false) }
        }
        
        func addFaceRectsToImage(){
            let imageSize = imageItem.size
        
            UIGraphicsBeginImageContext(imageSize)
            imageItem.draw(at: .zero)
            
            guard let context = UIGraphicsGetCurrentContext() else { return }
            
            context.setStrokeColor(UIColor.red.cgColor)
            context.setLineWidth(5.0)
            
            for face in detectedFaces {
                let boundingBox = face.boundingBox
                let rect = CGRect(
                    x: boundingBox.origin.x * imageSize.width,
                    y: (1 - boundingBox.origin.y - boundingBox.size.height) * imageSize.height/2,
                    width: boundingBox.size.width * imageSize.width,
                    height: boundingBox.size.height * imageSize.height
                )
                context.stroke(rect)
            }
            
            imageWithDetections = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
        }
    }
}

#Preview {
    PhotoView()
}
