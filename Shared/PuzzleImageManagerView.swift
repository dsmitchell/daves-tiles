//
//  PuzzleImageManagerView.swift
//  daves-tiles
//

import PhotosUI
import SwiftUI

struct PuzzleImageManagerView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var builtInImages: [PuzzleImage] = []
    @State private var disabledBuiltInImageIDs: Set<String> = []
    @State private var isAddingImage = false
    @State private var isShowingImageError = false
    @State private var pendingDeletion: PuzzleImage?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var userImages: [PuzzleImage] = []

    let onPuzzleImageAdded: (PuzzleImage) -> Void
    let onPuzzleImageDeleted: (String) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                PuzzleImageManagerIntro(
                    selectedPhoto: $selectedPhoto,
                    isAddingImage: isAddingImage
                )

                if !userImages.isEmpty {
                    UserPuzzleImageSection(images: userImages) { image in
                        pendingDeletion = image
                    }
                }

                BuiltInPuzzleImageSection(
                    images: builtInImages,
                    disabledImageIDs: disabledBuiltInImageIDs,
                    toggle: setBuiltInImage
                )
            }
            .padding()
        }
        .navigationTitle("Manage Photos")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .overlay {
            if isAddingImage {
                PuzzleImageManagerLoadingOverlay()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isAddingImage)
        .onAppear(perform: reloadImages)
        .onChange(of: selectedPhoto) { _, newPhoto in
            guard let newPhoto else { return }
            addPuzzleImage(from: newPhoto)
        }
        .alert("Couldn’t Add Image", isPresented: $isShowingImageError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The selected photo couldn’t be loaded. Please try another image.")
        }
        .confirmationDialog(
            "Delete Photo?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { image in
            Button("Delete Photo", role: .destructive) {
                deleteUserImage(image)
            }
        } message: { _ in
            Text("This photo will be removed from Dave’s Tiles.")
        }
    }

    private func reloadImages() {
        builtInImages = PuzzleImageLibrary.bundledImages()
        disabledBuiltInImageIDs = Set(PuzzleImageLibrary.bundledImageIDs.filter {
            !PuzzleImageLibrary.isBundledImageEnabled(id: $0)
        })
        userImages = PuzzleImageLibrary.userImages()
    }

    private func setBuiltInImage(_ image: PuzzleImage, enabled: Bool) {
        PuzzleImageLibrary.setBundledImage(image.id, enabled: enabled)
        disabledBuiltInImageIDs = Set(PuzzleImageLibrary.bundledImageIDs.filter {
            !PuzzleImageLibrary.isBundledImageEnabled(id: $0)
        })
    }

    private func addPuzzleImage(from item: PhotosPickerItem) {
        isAddingImage = true
        Task {
            defer {
                isAddingImage = false
                selectedPhoto = nil
            }
            do {
                let imported = try await PuzzleImageImporter.importItem(item)
                defer { try? FileManager.default.removeItem(at: imported.url) }
                let image = try await PuzzleImageLibrary.addUserMedia(imported)
                userImages.append(image)
                onPuzzleImageAdded(image)
            } catch {
                isShowingImageError = true
            }
        }
    }

    private func deleteUserImage(_ image: PuzzleImage) {
        do {
            try PuzzleImageLibrary.deleteUserImage(id: image.id)
            userImages.removeAll { $0.id == image.id }
            onPuzzleImageDeleted(image.id)
        } catch {
            isShowingImageError = true
        }
        pendingDeletion = nil
    }
}

private struct PuzzleImageManagerIntro: View {

    @Binding var selectedPhoto: PhotosPickerItem?
    let isAddingImage: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PhotosPicker(
                selection: $selectedPhoto,
                matching: .images,
                preferredItemEncoding: .current,
                photoLibrary: .shared()
            ) {
                Label("Add Photo", systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isAddingImage)

            Text("Added photos and enabled built-in photos are included in the random rotation.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct BuiltInPuzzleImageSection: View {

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 280), spacing: 16)]

    let images: [PuzzleImage]
    let disabledImageIDs: Set<String>
    let toggle: (PuzzleImage, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Built-in Photos")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(images, id: \.id) { image in
                    let isEnabled = !disabledImageIDs.contains(image.id)
                    BuiltInPuzzleImageCard(
                        image: image,
                        name: PuzzleImageLibrary.bundledImageName(id: image.id),
                        isEnabled: isEnabled
                    ) {
                        toggle(image, !isEnabled)
                    }
                }
            }
        }
    }
}

private struct BuiltInPuzzleImageCard: View {

    let image: PuzzleImage
    let name: LocalizedStringResource
    let isEnabled: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 0) {
                PuzzleImageThumbnail(image: image)
                    .grayscale(isEnabled ? 0 : 1)
                    .opacity(isEnabled ? 1 : 0.4)
                VStack(alignment: .leading, spacing: 6) {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Text(isEnabled ? "Included in Rotation" : "Skipped")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isEnabled ? Color.accentColor : .secondary)
                    }
                }
                .padding(10)
            }
            .contentShape(Rectangle())
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isEnabled ? "\(name), included" : "\(name), skipped")
        .accessibilityHint("Double-tap to change whether this photo appears in random rotation")
    }
}

private struct UserPuzzleImageSection: View {

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 280), spacing: 16)]

    let images: [PuzzleImage]
    let delete: (PuzzleImage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Photos")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(images, id: \.id) { image in
                    UserPuzzleImageCard(image: image) {
                        delete(image)
                    }
                }
            }
        }
    }
}

private struct UserPuzzleImageCard: View {

    let image: PuzzleImage
    let delete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PuzzleImageThumbnail(image: image)
            HStack {
                Text("Included in rotation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive, action: delete) {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete Photo")
            }
            .padding(10)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct PuzzleImageThumbnail: View {

    let image: PuzzleImage

    var body: some View {
        Color.clear
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay {
                image.image(toFill: CGSize(width: 360, height: 270))
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

private struct PuzzleImageManagerLoadingOverlay: View {

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
            ProgressView("Preparing Puzzle Image…")
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isModal)
    }
}

#Preview {
    NavigationStack {
        PuzzleImageManagerView(
            onPuzzleImageAdded: { _ in },
            onPuzzleImageDeleted: { _ in }
        )
    }
}
