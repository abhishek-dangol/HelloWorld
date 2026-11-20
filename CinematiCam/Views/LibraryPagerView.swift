import SwiftUI
import Photos
import AVKit
import UIKit

/// Asks the viewer to jump to another library item (after a tap in the All Photos rows).
struct LibraryJump: Equatable {
    let index: Int
    let token = UUID()
}

/// The library one item at a time, like the Photos app: swipe left and right between
/// photos and videos, with a row of small thumbnails along the bottom that can be
/// tapped or dragged to move quickly.
struct LibraryPager: UIViewControllerRepresentable {
    let assets: PHFetchResult<PHAsset>
    let startIndex: Int
    let jump: LibraryJump?
    /// The picture already on screen for the first item. It stays up until Photos has the
    /// sharp copy, so the change to the library never shows Photos' blurry first copy.
    var startImage: UIImage? = nil
    /// Told which item is on screen, at the start and after every swipe or tap
    var onShow: (PHAsset) -> Void = { _ in }

    func makeUIViewController(context: Context) -> LibraryPagerController {
        let controller = LibraryPagerController(assets: assets, startIndex: startIndex, startImage: startImage)
        controller.onShow = onShow
        return controller
    }

    func updateUIViewController(_ controller: LibraryPagerController, context: Context) {
        controller.onShow = onShow
        guard let jump = jump, jump.token != context.coordinator.lastToken else { return }
        context.coordinator.lastToken = jump.token
        controller.show(jump.index, moveStrip: true)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator { var lastToken: UUID? }
}

final class LibraryPagerController: UIViewController, UIPageViewControllerDataSource,
                                    UIPageViewControllerDelegate, UICollectionViewDataSource,
                                    UICollectionViewDelegateFlowLayout {
    private let assets: PHFetchResult<PHAsset>
    private var index: Int
    private let pages = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal,
                                             options: [.interPageSpacing: 12])
    private var strip: UICollectionView!
    private let thumbnails = PHCachingImageManager()
    private let itemSize = CGSize(width: 32, height: 46)
    private let gap: CGFloat = 2
    private var didPlaceStrip = false
    private var fingerOnStrip = false
    private var startImage: UIImage?
    var onShow: (PHAsset) -> Void = { _ in }

    init(assets: PHFetchResult<PHAsset>, startIndex: Int, startImage: UIImage? = nil) {
        self.assets = assets
        self.index = max(0, min(startIndex, assets.count - 1))
        self.startImage = startImage
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        pages.dataSource = self
        pages.delegate = self
        addChild(pages)
        pages.view.frame = view.bounds
        pages.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(pages.view)
        pages.didMove(toParent: self)
        if assets.count > 0 {
            pages.setViewControllers([page(at: index)], direction: .forward, animated: false)
            // Later, so the screen that owns us is not changed while it is being drawn
            DispatchQueue.main.async { [weak self] in self?.reportShown() }
        }

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = gap
        layout.itemSize = itemSize
        strip = UICollectionView(frame: .zero, collectionViewLayout: layout)
        strip.backgroundColor = .clear
        strip.showsHorizontalScrollIndicator = false
        strip.decelerationRate = .fast
        strip.register(StripCell.self, forCellWithReuseIdentifier: "cell")
        strip.dataSource = self
        strip.delegate = self
        // Fades in once it is in place, instead of popping in
        strip.alpha = 0
        view.addSubview(strip)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bottom = max(view.safeAreaInsets.bottom, 12)
        strip.frame = CGRect(x: 0, y: view.bounds.height - bottom - 6 - itemSize.height,
                             width: view.bounds.width, height: itemSize.height)
        // Room on both sides so the first and last thumbnails can sit in the middle too
        let side = (view.bounds.width - itemSize.width) / 2
        strip.contentInset = UIEdgeInsets(top: 0, left: side, bottom: 0, right: side)
        if !didPlaceStrip, view.bounds.width > 0, assets.count > 0 {
            didPlaceStrip = true
            strip.layoutIfNeeded()
            centreStrip(animated: false)
            UIView.animate(withDuration: 0.3) { self.strip.alpha = 1 }
        }
    }

    // MARK: Moving between items

    private func page(at index: Int) -> AssetPageController {
        // Only the item the viewer opened on has a picture in hand, and only the first time
        let held = index == self.index ? startImage : nil
        if held != nil { startImage = nil }
        return AssetPageController(asset: assets.object(at: index), index: index, placeholder: held)
    }

    /// Shows another item straight away (a tap on the thumbnail row or in All Photos).
    func show(_ newIndex: Int, moveStrip: Bool) {
        guard newIndex >= 0, newIndex < assets.count, newIndex != index else { return }
        index = newIndex
        pages.setViewControllers([page(at: newIndex)], direction: .forward, animated: false)
        if moveStrip { centreStrip(animated: false) }
        markCurrentThumbnail()
        reportShown()
    }

    private func reportShown() {
        guard index >= 0, index < assets.count else { return }
        onShow(assets.object(at: index))
    }

    private func stripOffset(for index: Int) -> CGFloat {
        CGFloat(index) * (itemSize.width + gap) - strip.contentInset.left
    }

    private func centreStrip(animated: Bool) {
        strip.setContentOffset(CGPoint(x: stripOffset(for: index), y: 0), animated: animated)
    }

    private func markCurrentThumbnail() {
        for case let cell as StripCell in strip.visibleCells {
            cell.isCurrent = strip.indexPath(for: cell)?.item == index
        }
    }

    // MARK: Swiping the big picture

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let current = (viewController as? AssetPageController)?.index, current > 0 else { return nil }
        return page(at: current - 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let current = (viewController as? AssetPageController)?.index,
              current < assets.count - 1 else { return nil }
        return page(at: current + 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let shown = (pages.viewControllers?.first as? AssetPageController)?.index else { return }
        index = shown
        centreStrip(animated: true)
        markCurrentThumbnail()
        reportShown()
    }

    // MARK: The thumbnail row

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        assets.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! StripCell
        let asset = assets.object(at: indexPath.item)
        cell.assetID = asset.localIdentifier
        cell.imageView.image = nil
        cell.isCurrent = indexPath.item == index
        let scale = UIScreen.main.scale
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        thumbnails.requestImage(for: asset,
                                targetSize: CGSize(width: itemSize.height * scale, height: itemSize.height * scale),
                                contentMode: .aspectFill, options: options) { [weak cell] image, _ in
            guard let cell = cell, cell.assetID == asset.localIdentifier, let image = image else { return }
            cell.imageView.image = image
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        show(indexPath.item, moveStrip: false)
        centreStrip(animated: true)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        fingerOnStrip = true
    }

    /// Dragging the row flips through the items as they pass the middle
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard fingerOnStrip else { return }
        let passed = (scrollView.contentOffset.x + scrollView.contentInset.left) / (itemSize.width + gap)
        show(max(0, min(assets.count - 1, Int(passed.rounded()))), moveStrip: false)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { settleStrip() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        settleStrip()
    }

    private func settleStrip() {
        guard fingerOnStrip else { return }
        fingerOnStrip = false
        centreStrip(animated: true)
    }
}

/// One photo or video, filling the screen. A video starts playing when its page is shown
/// and stops when it is swiped away.
final class AssetPageController: UIViewController {
    let asset: PHAsset
    let index: Int
    private let imageView = ZoomableImageView()
    private var playerController: AVPlayerViewController?
    private var isOnScreen = false
    /// A sharp picture of this item that is already in hand; Photos' blurry first copy is
    /// skipped while it is up
    private let placeholder: UIImage?

    init(asset: PHAsset, index: Int, placeholder: UIImage? = nil) {
        self.asset = asset
        self.index = index
        self.placeholder = placeholder
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Videos leave equal room above and below, so the player's own buttons stay clear
    /// of Back / All Photos at the top and the thumbnail row at the bottom.
    private var mediaFrame: CGRect {
        asset.mediaType == .video ? view.bounds.insetBy(dx: 0, dy: 140) : view.bounds
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        imageView.frame = mediaFrame
        imageView.image = placeholder
        view.addSubview(imageView)
        // Pinching in asks Photos for a bigger copy, so the close-up stays sharp
        imageView.onFirstZoom = { [weak self] in self?.loadImage(screens: 2.5, bestOnly: true) }
        loadImage(screens: 1, bestOnly: false)
    }

    /// A screen-sized copy is plenty to look at (full photos can be 48 megapixels); a
    /// zoomed-in one gets a copy `screens` times that size
    private func loadImage(screens: CGFloat, bestOnly: Bool) {
        let scale = UIScreen.main.scale * screens
        let screen = UIScreen.main.bounds.size
        let options = PHImageRequestOptions()
        options.deliveryMode = bestOnly ? .highQualityFormat : .opportunistic
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(for: asset,
                                              targetSize: CGSize(width: screen.width * scale, height: screen.height * scale),
                                              contentMode: .aspectFit, options: options) { [weak self] image, info in
            guard let self, let image else { return }
            let blurry = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            if blurry, self.placeholder != nil { return }
            self.imageView.image = image
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        imageView.frame = mediaFrame
        playerController?.view.frame = mediaFrame
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isOnScreen = true
        guard asset.mediaType == .video else { return }
        if let player = playerController?.player {
            player.play()
        } else {
            loadVideo()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isOnScreen = false
        imageView.resetZoom()
        playerController?.player?.pause()
    }

    private func loadVideo() {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self = self, let item = item, self.playerController == nil else { return }
                let controller = AVPlayerViewController()
                controller.player = AVPlayer(playerItem: item)
                controller.view.backgroundColor = .black
                self.addChild(controller)
                controller.view.frame = self.mediaFrame
                self.view.addSubview(controller.view)
                controller.didMove(toParent: self)
                self.playerController = controller
                self.imageView.isHidden = true
                if self.isOnScreen { controller.player?.play() }
            }
        }
    }
}

private final class StripCell: UICollectionViewCell {
    let imageView = UIImageView()
    var assetID: String?
    /// The item on screen is at full strength with a white edge; the rest are dimmed
    var isCurrent = false {
        didSet {
            imageView.alpha = isCurrent ? 1 : 0.55
            contentView.layer.borderWidth = isCurrent ? 2 : 0
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.frame = contentView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.alpha = 0.55
        contentView.backgroundColor = UIColor(white: 0.12, alpha: 1)
        contentView.layer.borderColor = UIColor.white.cgColor
        contentView.layer.cornerRadius = 3
        contentView.clipsToBounds = true
        contentView.addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// A picture that can be pinched to zoom, dragged around while zoomed, and double-tapped to
/// zoom in and back out, like in the iPhone's Photos app.
final class ZoomableImageView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var laidOutSize = CGSize.zero
    private var didZoom = false
    /// Called the first time the picture is zoomed
    var onFirstZoom: (() -> Void)?

    var image: UIImage? {
        get { imageView.image }
        set { imageView.image = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 5
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Only when the space itself changes: this also runs on every scroll and zoom step
        guard bounds.size != laidOutSize else { return }
        laidOutSize = bounds.size
        zoomScale = 1
        imageView.frame = CGRect(origin: .zero, size: bounds.size)
        contentSize = bounds.size
    }

    func resetZoom() {
        if zoomScale != 1 { setZoomScale(1, animated: false) }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        guard !didZoom else { return }
        didZoom = true
        onFirstZoom?()
    }

    @objc private func doubleTapped(_ tap: UITapGestureRecognizer) {
        if zoomScale > 1 {
            setZoomScale(1, animated: true)
        } else {
            if !didZoom { didZoom = true; onFirstZoom?() }
            let point = tap.location(in: imageView)
            let size = CGSize(width: bounds.width / 2.5, height: bounds.height / 2.5)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                            width: size.width, height: size.height), animated: true)
        }
    }
}

/// The zoomable picture for SwiftUI screens
struct ZoomablePhoto: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ZoomableImageView {
        let view = ZoomableImageView()
        view.image = image
        return view
    }

    func updateUIView(_ view: ZoomableImageView, context: Context) {
        if view.image !== image {
            // A soft change (the real photo taking the place of the screen copy), not a cut
            UIView.transition(with: view, duration: 0.3,
                              options: [.transitionCrossDissolve, .allowUserInteraction]) {
                view.image = image
            }
            view.resetZoom()
        }
    }
}
