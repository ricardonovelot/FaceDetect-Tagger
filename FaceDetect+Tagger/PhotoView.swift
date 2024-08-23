//
//  ContentView.swift
//  FaceDetect+Tagger
//
//  Created by Ricardo on 22/08/24.
//

import SwiftUI
import SwiftData
import PhotosUI

struct PhotoView: View {
    @ObservedObject var viewModel = PhotoViewController()
    
    
    var body: some View {
        NavigationStack{
            
            
            List(viewModel.contacts){ contact in
                Text(contact.name)
            }
            .contentMargins(.top, 12)
            .navigationTitle("Contacts")
            .toolbar{
                ToolbarItemGroup(placement: .primaryAction) {
                    
                    PhotosPicker(selection: $viewModel.pickerItem, matching: .images){
                        Image(systemName: "camera")
                    }

                }
            }
        }
        .sheet(isPresented: $viewModel.showSheet) {
            NavigationView {
                VStack{
                    viewModel.imageItem?
                        .resizable()
                        .scaledToFit()
                        .padding()
                }
            }
        }
    }
}

#Preview {
    PhotoView()
}

@Model
class Contact{
    var name: String
    
    init(name: String) {
        self.name = name
    }
}


extension PhotoView{
    class PhotoViewController: ObservableObject{
        @Published var contacts: [Contact] = []
        @Published var showSheet = false
        @Published var imageItem: Image?
        @Published var pickerItem: PhotosPickerItem? {
            didSet {
                loadSelectedImage()
            }
        }
        
        
        init(){
            addTestContacts()
        }
        
        func addTestContacts() {
            contacts = sampleContacts
        }
        
        
        private func loadSelectedImage() {
            Task {
                if let pickerItem = pickerItem {
                    if let imageData = try? await pickerItem.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: imageData) {
                        imageItem = Image(uiImage: uiImage)
                        showSheet = true
                    }
                }
            }
           
        }
        
        
        let sampleContacts = [
            Contact(name: "Ricardo"),
            Contact(name: "Daniel"),
            Contact(name: "Juan"),
        ]
    }
}

