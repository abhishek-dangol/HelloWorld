import SwiftUI
import Photos
import UIKit

/// CinematiCam's own "All Photos": every photo and video in the library in rows of
/// three, oldest at the top and the newest at the bottom (it opens at the bottom, like
/// the Photos app). Needs full Photos access; tapping an item hands it back.
struct GalleryGrid: View {
    let onPick: (PHAsset) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("All Photos")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                HStack {
                    Spacer()
                    Button("Close", action: onClose)
                        .font(.system(size: 17))
                        .foregroundColor(.white)
                        .padding(.trailing, 16)
                }
            }
            .frame(height: 52)
            GalleryCollection(onPick: onPick)
                .ignoresSafeArea(edges: .bottom)
        }
        .background(Color.black.ignoresSafeArea())
    }
}

/// Every photo and video in the library, oldest first: the one order shared by the
/// All Photos rows and the swipe viewer, so an item has the same place in both.
enum GalleryLibrary {
    static func fetchAll() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                        PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        return PHAsset.fetchAssets(with: options)
    }
}

private struct GalleryCollection: UIViewControllerRepresentable {
    let onPick: (PHAsset) -> Void

    func makeUIViewController(context: Context) -> GalleryCollectionController {
        let controller = GalleryCollectionController()
        controller.onPick = onPick
        return controller
    }

    func updateUIViewController(_ controller: GalleryCollectionController, context: Context) {}
}

final class GalleryCollectionController: UIViewController, UICollectionViewDataSource,
                                         UICollectionViewDelegateFlowLayout {
    var onPick: ((PHAsset) -> Void)?

    private var assets = PHFetchResult<PHAsset>()
    private let imageManager = PHCachingImageManager()
    private var collectionView: UICollectionView!
    private var didScrollToNewest = false
    private let columns: CGFloat = 3
    private let gap: CGFloat = 2

    override func viewDidLoad() {
        super.viewDidLoad()
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = gap
        layout.minimumLineSpacing = gap
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .black
        collectionView.register(GalleryCell.self, forCellWithReuseIdentifier: "cell")
        collectionView.dataSource = self
        collectionView.delegate = self
        view.addSubview(collectionView)

        assets = GalleryLibrary.fetchAll()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !didScrollToNewest, assets.count > 0, collectionView.bounds.width > 0 else { return }
        didScrollToNewest = true
        collectionView.layoutIfNeeded()
        collectionView.scrollToItem(at: IndexPath(item: assets.count - 1, section: 0), at: .bottom, animated: false)
    }

    private var cellSide: CGFloat {
        floor((collectionView.bounds.width - gap * (columns - 1)) / columns)
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        assets.count
    }

    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        CGSize(width: cellSide, height: cellSide)
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! GalleryCell
        let asset = assets.object(at: indexPath.item)
        cell.assetID = asset.localIdentifier
        cell.imageView.image = nil
        cell.durationLabel.text = asset.mediaType == .video ? Self.clock(asset.duration) : nil

        let pixels = cellSide * UIScreen.main.scale
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        imageManager.requestImage(for: asset, targetSize: CGSize(width: pixels, height: pixels),
                                  contentMode: .aspectFill, options: options) { [weak cell] image, _ in
            // The cell may have been reused for another picture by the time this arrives
            guard let cell = cell, cell.assetID == asset.localIdentifier, let image = image else { return }
            cell.imageView.image = image
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onPick?(assets.object(at: indexPath.item))
    }

    /// Video length the way Photos writes it: 0:07, 1:32, 1:02:05
    private static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

private final class GalleryCell: UICollectionViewCell {
    let imageView = UIImageView()
    let durationLabel = UILabel()
    var assetID: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.frame = contentView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor(white: 0.12, alpha: 1)
        contentView.addSubview(imageView)

        durationLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        durationLabel.textColor = .white
        durationLabel.textAlignment = .right
        durationLabel.layer.shadowColor = UIColor.black.cgColor
        durationLabel.layer.shadowOpacity = 0.8
        durationLabel.layer.shadowRadius = 2
        durationLabel.layer.shadowOffset = .zero
        durationLabel.frame = CGRect(x: 4, y: contentView.bounds.height - 20,
                                     width: contentView.bounds.width - 9, height: 16)
        durationLabel.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
        contentView.addSubview(durationLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
