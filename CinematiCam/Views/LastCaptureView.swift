import SwiftUI
import AVKit
import PhotosUI
import Photos
import UniformTypeIdentifiers

/// Opens when the round thumbnail beside the shutter is tapped: shows the photo or video
/// that was just taken. "All Photos" slides up the library rows (Apple's own photo grid,
/// newest at the bottom); tapping a picture or video there shows it here.
/// The grid stays inside the app because the Photos app cannot be told which screen to
/// open on: it comes up wherever it was last left (tested on iOS 27.2).
struct LastCaptureView: View {
    let photo: UIImage?
    let videoURL: URL?
    /// The Photos id of the capture being shown, once Photos has finished saving it
    var savedAssetID: () -> String? = { nil }

    @Environment(\.dismiss) private var dismiss
    @State private var shownPhoto: UIImage?
    @State private var player: AVPlayer?
    @State private var didLoad = false
    @State private var showGallery = false
    /// True when full Photos access was refused: Apple's own picker is shown instead
    @State private var galleryUsesPicker = false
    @State private var isLoading = false
    /// Our own copy of a video picked from the library; removed when replaced or on close.
    @State private var pickedVideoCopy: URL?
    /// Set once the whole library can be swiped through (needs full Photos access)
    @State private var library: PHFetchResult<PHAsset>?
    @State private var libraryStart = 0
    @State private var libraryJump: LibraryJump?
    /// The Photos item on screen while swiping through the library
    @State private var shownAssetID: String?
    /// False once something picked without Photos access is shown: it has no item to hand over
    @State private var canShare = true
    /// What the iPhone's share panel is showing; nil while it is closed
    @State private var shareItems: ShareItems?
    @State private var isPreparingShare = false

    var body: some View {
        // The picture sits in the middle of the whole screen, with the same gap above and
        // below; the buttons float over the top instead of pushing it down.
        ZStack(alignment: .top) {
            ZStack {
                if let library = library {
                    LibraryPager(assets: library, startIndex: libraryStart, jump: libraryJump,
                                 onShow: { shownAssetID = $0.localIdentifier })
                        .ignoresSafeArea()
                } else if let shownPhoto = shownPhoto {
                    ZoomablePhoto(image: shownPhoto)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                } else if let player = player {
                    // Equal space top and bottom keeps the player's own buttons clear of ours
                    VideoPlayer(player: player)
                        .padding(.vertical, 56)
                }
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(0.45), in: Circle())
                }
                .accessibilityLabel("Back to camera")
                Spacer()
                Button {
                    openGallery()
                } label: {
                    Text("All Photos")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(Color.black.opacity(0.45), in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            // Low enough to sit fully on a tall (9:16) picture instead of across its top edge
            .padding(.top, 36)

            if canShare {
                shareButtons
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if let photo = photo {
                shownPhoto = photo
            } else if let url = videoURL {
                play(url)
            }
            enterLibraryAtCapture(triesLeft: 6)
        }
        .onDisappear {
            player?.pause()
            removePickedVideoCopy()
        }
        .sheet(isPresented: $showGallery) {
            if galleryUsesPicker {
                GalleryPicker { provider in
                    showGallery = false
                    if let provider = provider { show(provider) }
                }
                .ignoresSafeArea()
            } else {
                GalleryGrid(onPick: { asset in
                    showGallery = false
                    show(asset)
                }, onClose: { showGallery = false })
            }
        }
    }

    /// Sits just above the thumbnail row, in the gap a video leaves below itself
    private var shareButtons: some View {
        VStack(spacing: 10) {
            Text("Share to")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.7), radius: 3)
            // Instagram is the only app that takes an item straight from us without
            // CinematiCam being registered with it; every other app is under Others.
            shareChoice("Instagram", action: shareToInstagram) {
                InstagramGlyph()
            }
            shareChoice("Others", action: openSharePanel) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.black.opacity(0.45), in: Circle())
            }
            .disabled(isPreparingShare)
            .opacity(isPreparingShare ? 0.5 : 1)
        }
        .padding(.trailing, 12)
        .padding(.bottom, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .background(
            // Hung on its own view so it does not clash with the All Photos sheet
            Color.clear.sheet(item: $shareItems) { shared in
                SharePanel(items: shared.items) {
                    shareItems = nil
                    if let copy = shared.copy { try? FileManager.default.removeItem(at: copy) }
                }
                .ignoresSafeArea()
            }
        )
    }

    /// One entry of the share column: its icon with its name underneath
    private func shareChoice<Icon: View>(_ name: String, action: @escaping () -> Void,
                                         @ViewBuilder icon: () -> Icon) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                icon()
                    .frame(width: 38, height: 38)
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.7), radius: 3)
            }
        }
    }

    /// The Photos item on screen, when the app may read it
    private var shownAsset: PHAsset? {
        guard let id = library == nil ? savedAssetID() : shownAssetID else { return nil }
        return PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    /// Opens the iPhone's share panel with the item on screen. Other apps cannot read
    /// the Photos library through us, so they get a full-quality copy, removed afterwards.
    private func openSharePanel() {
        player?.pause()
        guard let asset = shownAsset else {
            // No Photos access: hand over what the camera just made
            if let url = videoURL, library == nil, photo == nil {
                shareItems = ShareItems(items: [url], copy: nil)
            } else if let photo = photo {
                shareItems = ShareItems(items: [photo], copy: nil)
            }
            return
        }
        let resources = PHAssetResource.assetResources(for: asset)
        let wanted: [PHAssetResourceType] = asset.mediaType == .video
            ? [.fullSizeVideo, .video] : [.fullSizePhoto, .photo]
        guard let resource = wanted.compactMap({ type in resources.first { $0.type == type } }).first
                ?? resources.first else { return }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent(resource.originalFilename)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        isPreparingShare = true
        PHAssetResourceManager.default().writeData(for: resource, toFile: copy, options: options) { error in
            DispatchQueue.main.async {
                isPreparingShare = false
                if error == nil {
                    shareItems = ShareItems(items: [copy], copy: folder)
                } else {
                    try? FileManager.default.removeItem(at: folder)
                }
            }
        }
    }

    /// Opens Instagram with the item on screen already picked; Instagram then asks whether
    /// it becomes a story, a post or a reel. Without Instagram, its App Store page opens.
    private func shareToInstagram() {
        guard let id = library == nil ? savedAssetID() : shownAssetID else { return }
        var link = URLComponents()
        link.scheme = "instagram"
        link.host = "library"
        link.queryItems = [URLQueryItem(name: "LocalIdentifier", value: id)]
        guard let url = link.url else { return }
        player?.pause()
        UIApplication.shared.open(url, options: [:]) { opened in
            guard !opened, let store = URL(string: "https://apps.apple.com/app/instagram/id389801252") else { return }
            UIApplication.shared.open(store)
        }
    }

    /// Our own rows need full Photos access (asked once). If it is refused, Apple's
    /// picker, which needs no permission, is shown instead.
    private func openGallery() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                galleryUsesPicker = !(status == .authorized || status == .limited)
                showGallery = true
            }
        }
    }

    /// With full Photos access, swaps the single capture for the swipeable library opened
    /// on that same capture. Photos may still be saving it, so this looks a few times.
    private func enterLibraryAtCapture(triesLeft: Int) {
        let access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard library == nil, access == .authorized || access == .limited else { return }
        if let id = savedAssetID(),
           let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject {
            enterLibrary(at: asset)
        } else if triesLeft > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                enterLibraryAtCapture(triesLeft: triesLeft - 1)
            }
        }
    }

    /// Opens the swipeable library on one item. False if the item is not in it.
    @discardableResult
    private func enterLibrary(at asset: PHAsset) -> Bool {
        let all = library ?? GalleryLibrary.fetchAll()
        let index = all.index(of: asset)
        guard index != NSNotFound else { return false }
        if library == nil {
            player?.pause()
            player = nil
            shownPhoto = nil
            removePickedVideoCopy()
            libraryStart = index
            library = all
        } else {
            libraryJump = LibraryJump(index: index)
        }
        return true
    }

    /// Loads the picture or video tapped in our own rows and shows it.
    private func show(_ asset: PHAsset) {
        if enterLibrary(at: asset) { return }
        isLoading = true
        if asset.mediaType == .video {
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .automatic
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                DispatchQueue.main.async {
                    isLoading = false
                    guard let item = item else { return }
                    player?.pause()
                    removePickedVideoCopy()
                    shownPhoto = nil
                    let newPlayer = AVPlayer(playerItem: item)
                    player = newPlayer
                    newPlayer.play()
                }
            }
        } else {
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            // A screen-sized copy is plenty to look at (full photos can be 48 megapixels)
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 3000, height: 3000),
                                                  contentMode: .aspectFit, options: options) { image, _ in
                DispatchQueue.main.async {
                    isLoading = false
                    guard let image = image else { return }
                    player?.pause()
                    player = nil
                    removePickedVideoCopy()
                    shownPhoto = image
                }
            }
        }
    }

    /// Starts playing by itself, like a video opened in Photos.
    private func play(_ url: URL) {
        let newPlayer = AVPlayer(url: url)
        player = newPlayer
        newPlayer.play()
    }

    private func removePickedVideoCopy() {
        if let copy = pickedVideoCopy { try? FileManager.default.removeItem(at: copy) }
        pickedVideoCopy = nil
    }

    /// Loads the picture or video picked from the library rows and shows it.
    private func show(_ provider: NSItemProvider) {
        canShare = false
        let movie = UTType.movie.identifier
        if provider.hasItemConformingToTypeIdentifier(movie) {
            isLoading = true
            provider.loadFileRepresentation(forTypeIdentifier: movie) { url, _ in
                // The file only exists inside this block, so keep a copy to play from
                var copy: URL?
                if let url = url {
                    let target = FileManager.default.temporaryDirectory
                        .appendingPathComponent("gallery-\(UUID().uuidString).\(url.pathExtension)")
                    if (try? FileManager.default.copyItem(at: url, to: target)) != nil { copy = target }
                }
                DispatchQueue.main.async {
                    isLoading = false
                    guard let copy = copy else { return }
                    player?.pause()
                    removePickedVideoCopy()
                    pickedVideoCopy = copy
                    shownPhoto = nil
                    play(copy)
                }
            }
        } else if provider.canLoadObject(ofClass: UIImage.self) {
            isLoading = true
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                // Full-size photos can be 48 megapixels; a screen-sized copy is plenty to look at
                let full = object as? UIImage
                let image = full.flatMap { Self.screenSized($0) } ?? full
                DispatchQueue.main.async {
                    isLoading = false
                    guard let image = image else { return }
                    player?.pause()
                    player = nil
                    removePickedVideoCopy()
                    shownPhoto = image
                }
            }
        }
    }

    private static func screenSized(_ image: UIImage) -> UIImage? {
        let longest = max(image.size.width, image.size.height) * image.scale
        let limit: CGFloat = 3000
        guard longest > limit else { return image }
        let factor = limit / longest
        let size = CGSize(width: image.size.width * image.scale * factor,
                          height: image.size.height * image.scale * factor)
        return image.preparingThumbnail(of: size)
    }
}

/// Apple's own photo grid: the library rows, newest at the bottom. Needs no Photos
/// permission. Calls back with the tapped item, or nil when closed without picking.
/// Instagram's camera mark, drawn here so no picture file is needed: white outline,
/// lens and dot on the pink-to-orange square.
private struct InstagramGlyph: View {
    var body: some View {
        GeometryReader { box in
            let side = min(box.size.width, box.size.height)
            let line = side * 0.075
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.26, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.99, green: 0.80, blue: 0.36),
                                                  Color(red: 0.96, green: 0.26, blue: 0.33),
                                                  Color(red: 0.76, green: 0.19, blue: 0.62),
                                                  Color(red: 0.36, green: 0.31, blue: 0.84)],
                                         startPoint: .bottomLeading, endPoint: .topTrailing))
                RoundedRectangle(cornerRadius: side * 0.17, style: .continuous)
                    .stroke(Color.white, lineWidth: line)
                    .frame(width: side * 0.58, height: side * 0.58)
                Circle()
                    .stroke(Color.white, lineWidth: line)
                    .frame(width: side * 0.28, height: side * 0.28)
                Circle()
                    .fill(Color.white)
                    .frame(width: side * 0.07, height: side * 0.07)
                    .offset(x: side * 0.17, y: -side * 0.17)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// One opening of the share panel: what is handed over, and our copy to remove afterwards
private struct ShareItems: Identifiable {
    let id = UUID()
    let items: [Any]
    let copy: URL?
}

/// The iPhone's own share panel (the one the Photos app shows)
private struct SharePanel: UIViewControllerRepresentable {
    let items: [Any]
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let panel = UIActivityViewController(activityItems: items, applicationActivities: nil)
        panel.completionWithItemsHandler = { _, _, _, _ in onFinish() }
        return panel
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct GalleryPicker: UIViewControllerRepresentable {
    let onFinish: (NSItemProvider?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = 1
        configuration.filter = .any(of: [.images, .videos])
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onFinish: (NSItemProvider?) -> Void

        init(onFinish: @escaping (NSItemProvider?) -> Void) { self.onFinish = onFinish }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            onFinish(results.first?.itemProvider)
        }
    }
}
