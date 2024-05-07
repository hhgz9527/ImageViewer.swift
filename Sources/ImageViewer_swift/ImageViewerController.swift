import UIKit
import PhotosUI
import VisionKit

class ImageViewerController:UIViewController,
UIGestureRecognizerDelegate {
    
    var imageView: UIImageView = UIImageView(frame: .zero)
    var livePhotoView: PHLivePhotoView = PHLivePhotoView(frame: CGRect(x: 0, y: 0, width: 320, height: 320))
    let livePhotoFlag = UIImageView(image: UIImage(systemName: "livephoto"))
    var downloadButton: UIButton = UIButton()
    var removeBackgroundButton: UIButton = UIButton()
    var resetImageButton: UIButton = UIButton()
    var saveSubjectImageButton: UIButton = UIButton()
    let imageLoader: ImageLoader
    
    private var _interaction: Any? = nil
    @available(iOS 16.0, *)
    fileprivate var interaction: ImageAnalysisInteraction {
        if _interaction == nil {
            _interaction = ImageAnalysisInteraction()
        }
        return _interaction as! ImageAnalysisInteraction
    }

    
    var backgroundView:UIView? {
        guard let _parent = parent as? ImageCarouselViewController
            else { return nil}
        return _parent.backgroundView
    }
    
    var index:Int = 0
    var imageItem:ImageItem!

    var navBar:UINavigationBar? {
        guard let _parent = parent as? ImageCarouselViewController
            else { return nil}
        return _parent.navBar
    }
    
    // MARK: Layout Constraints
    private var top:NSLayoutConstraint!
    private var leading:NSLayoutConstraint!
    private var trailing:NSLayoutConstraint!
    private var bottom:NSLayoutConstraint!
    
    private var scrollView:UIScrollView!
    
    private var lastLocation:CGPoint = .zero
    private var isAnimating:Bool = false
    private var maxZoomScale:CGFloat = 1.0
    
    private var liftSubjectImageAction: ((UIImage?) -> Void)?
    
    init(
        index: Int,
        imageItem:ImageItem,
        imageLoader: ImageLoader,
        liftSubjectImageAction: ((UIImage?) -> Void)? = nil) {

        self.index = index
        self.imageItem = imageItem
        self.imageLoader = imageLoader
        self.liftSubjectImageAction = liftSubjectImageAction
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        let view = UIView()
    
        view.backgroundColor = .clear
        self.view = view
        
        scrollView = UIScrollView()
        scrollView.delegate = self
        scrollView.showsVerticalScrollIndicator = false
        
        if #available(iOS 11.0, *) {
            scrollView.contentInsetAdjustmentBehavior = .never
        } else {
            // Fallback on earlier versions
        }
        view.addSubview(scrollView)
        scrollView.bindFrameToSuperview()
        scrollView.backgroundColor = .clear
        scrollView.addSubview(imageView)
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        top = imageView.topAnchor.constraint(equalTo: scrollView.topAnchor)
        leading = imageView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor)
        trailing = scrollView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor)
        bottom = scrollView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor)
        
        top.isActive = true
        leading.isActive = true
        trailing.isActive = true
        bottom.isActive = true
        
        switch imageItem {
        case .image(_):
            break
        case .url(_, _):
            break
        case .livePhotoByResourceFileURLs(_, _):
            livePhotoView.isHidden = true
            livePhotoFlag.isHidden = true
            scrollView.addSubview(livePhotoView)
            scrollView.addSubview(livePhotoFlag)
        case .none:
            break
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        switch imageItem {
        case .image(let img):
            imageView.image = img
            imageView.layoutIfNeeded()
        case .url(let url, let placeholder):
            imageLoader.loadImage(url, placeholder: placeholder, imageView: imageView) { (image) in
                DispatchQueue.main.async {[weak self] in
                    self?.layout()
                }
            }
        case .livePhotoByResourceFileURLs(imageFileURL: let image, videoFileURL: let video):
            imageView.image = UIImage(contentsOfFile: image!.relativePath)
            imageView.layoutIfNeeded()

            PHLivePhoto.request(withResourceFileURLs: [video!, image!], placeholderImage: nil, targetSize: CGSize.zero, contentMode: .aspectFit) { livePhoto, info in
                DispatchQueue.main.async { [weak self] in
                    self?.livePhotoView.livePhoto = livePhoto
                    self?.livePhotoView.layoutIfNeeded()
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.livePhotoFlag.isHidden = false
                self?.livePhotoFlag.tintColor = .white
            }
            let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            longPressGesture.minimumPressDuration = 0.2
            scrollView.addGestureRecognizer(longPressGesture)
        default:
            break
        }
        if #available(iOS 16.0, *), ImageAnalyzer.isSupported {
            imageView.addInteraction(interaction)
            interaction.preferredInteractionTypes = .automatic
            Task {
                let configuration = ImageAnalyzer.Configuration([.visualLookUp])
                
                let analyzer = ImageAnalyzer()
                
                let analysis = try? await analyzer.analyze(imageView.image!, configuration: configuration)
                interaction.analysis = analysis
                
                let subjects = await interaction.subjects
                if !subjects.isEmpty {
                    buildRemoveBackgroundButton()
                }
            }
        }
        addGestureRecognizers()
        buildDownloadButton()
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.navBar?.alpha = 1.0
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.navBar?.alpha = 0.0
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        layout()
    }
    
    private func buildDownloadButton() {
        var filled = UIButton.Configuration.plain()
        filled.buttonSize = .small
        filled.image = UIImage(systemName: "square.and.arrow.down.fill")
        filled.image?.withTintColor(.white)
        filled.imagePadding = 15

        downloadButton = UIButton(configuration: filled, primaryAction: nil)
        downloadButton.titleLabel?.font = .systemFont(ofSize: 14)
        downloadButton.titleLabel?.textColor = .white
        downloadButton.layer.cornerRadius = 34 / 2
        downloadButton.translatesAutoresizingMaskIntoConstraints = false
        downloadButton.tintColor = .white
        downloadButton.backgroundColor = .black.withAlphaComponent(0.3)
        view.addSubview(downloadButton)
        downloadButton.layer.zPosition = 9999
        downloadButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -34).isActive = true
        downloadButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -15).isActive = true
        downloadButton.widthAnchor.constraint(equalToConstant: 34).isActive = true
        downloadButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
        downloadButton.addTarget(self, action: #selector(saveImageToPhoto), for: .touchUpInside)
    }
    
    private func buildRemoveBackgroundButton() {
        var filled = UIButton.Configuration.plain()
        filled.buttonSize = .small
        filled.image = UIImage(systemName: "wand.and.rays.inverse")
        filled.image?.withTintColor(.white)
        filled.imagePadding = 5
        filled.title = NSLocalizedString("Remove Background", comment: "Close button title")
        
        removeBackgroundButton = UIButton(configuration: filled, primaryAction: nil)
        removeBackgroundButton.titleLabel?.font = .systemFont(ofSize: 14)
        removeBackgroundButton.titleLabel?.textColor = .white
        removeBackgroundButton.layer.cornerRadius = 34 / 2
        removeBackgroundButton.translatesAutoresizingMaskIntoConstraints = false
        removeBackgroundButton.tintColor = .white
        removeBackgroundButton.backgroundColor = .black.withAlphaComponent(0.3)
        view.addSubview(removeBackgroundButton)
        removeBackgroundButton.layer.zPosition = 9999
        removeBackgroundButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -34).isActive = true
        removeBackgroundButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 15).isActive = true
//        removeBackgroundButton.widthAnchor.constraint(equalToConstant: 34).isActive = true
        removeBackgroundButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
        removeBackgroundButton.addTarget(self, action: #selector(liftSubjectsFromImage), for: .touchUpInside)
    }
    
    private func buildResetButton() {
        var filled = UIButton.Configuration.plain()
        filled.buttonSize = .small
        filled.image = UIImage(systemName: "arrow.counterclockwise")
        filled.image?.withTintColor(.white)
        filled.imagePadding = 5
        filled.title = String(localized: "Reset", table: "ImageViewerLocalizable")
        
        resetImageButton = UIButton(configuration: filled, primaryAction: nil)
        resetImageButton.titleLabel?.font = .systemFont(ofSize: 14)
        resetImageButton.titleLabel?.textColor = .white
        resetImageButton.layer.cornerRadius = 34 / 2
        resetImageButton.translatesAutoresizingMaskIntoConstraints = false
        resetImageButton.tintColor = .white
        resetImageButton.backgroundColor = .black.withAlphaComponent(0.3)
        view.addSubview(resetImageButton)
        resetImageButton.layer.zPosition = 9999
        resetImageButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -34).isActive = true
        resetImageButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 15).isActive = true
        resetImageButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
        resetImageButton.addTarget(self, action: #selector(resetImage), for: .touchUpInside)
    }
    
    private func buildSaveSubjectImageButton() {
        var filled = UIButton.Configuration.plain()
        filled.buttonSize = .small
        filled.image = UIImage(systemName: "checkmark")
        filled.image?.withTintColor(.white)
        filled.imagePadding = 5
        filled.title = String(localized: "Confirm", table: "ImageViewerLocalizable")
        
        saveSubjectImageButton = UIButton(configuration: filled, primaryAction: nil)
        saveSubjectImageButton.titleLabel?.font = .systemFont(ofSize: 14)
        saveSubjectImageButton.titleLabel?.textColor = .white
        saveSubjectImageButton.layer.cornerRadius = 34 / 2
        saveSubjectImageButton.translatesAutoresizingMaskIntoConstraints = false
        saveSubjectImageButton.tintColor = .white
        saveSubjectImageButton.backgroundColor = .black.withAlphaComponent(0.3)
        view.addSubview(saveSubjectImageButton)
        saveSubjectImageButton.layer.zPosition = 9999
        saveSubjectImageButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -34).isActive = true
        saveSubjectImageButton.leadingAnchor.constraint(equalTo: resetImageButton.trailingAnchor, constant: 15).isActive = true
        saveSubjectImageButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
        saveSubjectImageButton.addTarget(self, action: #selector(saveLiftSubjectImage), for: .touchUpInside)
    }
    
    @objc func saveLiftSubjectImage() {
        if #available(iOS 16.0, *), ImageAnalyzer.isSupported {
            Task {
                let subjects = await interaction.subjects
                do {
                    let img = try await interaction.image(for: subjects)
                    if let result = buildLiftSubjectsImage(image: img) {
                        liftSubjectImageAction?(result)
                        resetImageButton.removeFromSuperview()
                        saveSubjectImageButton.removeFromSuperview()
                    }
                } catch {
                    print(error)
                }
                
            }
        }
    }
    
    @objc func resetImage() {
        resetImageButton.removeFromSuperview()
        saveSubjectImageButton.removeFromSuperview()
        removeBackgroundButton.isHidden = false
        switch imageItem {
        case .image(let img):
            imageView.image = img
            imageView.layoutIfNeeded()
        case .url(let url, let placeholder):
            imageLoader.loadImage(url, placeholder: placeholder, imageView: imageView) { (image) in
                DispatchQueue.main.async {[weak self] in
                    self?.layout()
                }
            }
        case .livePhotoByResourceFileURLs(imageFileURL: let image, videoFileURL: let video):
            imageView.image = UIImage(contentsOfFile: image!.relativePath)
            imageView.layoutIfNeeded()

            PHLivePhoto.request(withResourceFileURLs: [video!, image!], placeholderImage: nil, targetSize: CGSize.zero, contentMode: .aspectFit) { livePhoto, info in
                DispatchQueue.main.async { [weak self] in
                    self?.livePhotoView.isHidden = false
                    self?.livePhotoView.livePhoto = livePhoto
                    self?.livePhotoView.layoutIfNeeded()
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.livePhotoFlag.isHidden = false
                self?.livePhotoFlag.tintColor = .white
            }
            let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            longPressGesture.minimumPressDuration = 0.2
            scrollView.addGestureRecognizer(longPressGesture)
        default:
            break
        }
    }
    
    @objc func liftSubjectsFromImage() {
        switch imageItem {
        case .image(_):
            if #available(iOS 16.0, *), ImageAnalyzer.isSupported {
                Task {
                    let subjects = await interaction.subjects
                    do {
                        let img = try await interaction.image(for: subjects)
                        if let result = buildLiftSubjectsImage(image: img) {
                            imageView.contentMode = .scaleAspectFit
                            imageView.image = result
                        } else {
                            imageView.image = img
                        }
                        removeBackgroundButton.isHidden = true
                        buildResetButton()
                        buildSaveSubjectImageButton()
                    } catch {
                        print(error)
                    }
                    
                }
            }
        case .url(_, _):
            break
        case .livePhotoByResourceFileURLs(_, _):
            if #available(iOS 16.0, *), ImageAnalyzer.isSupported {
                Task {
                    let subjects = await interaction.subjects
                    do {
                        let img = try await interaction.image(for: subjects)
                        if let result = buildLiftSubjectsImage(image: img) {
                            imageView.contentMode = .scaleAspectFit
                            imageView.image = result
                        } else {
                            imageView.image = img
                        }
                        removeBackgroundButton.isHidden = true
                        buildResetButton()
                        buildSaveSubjectImageButton()
                        livePhotoView.isHidden = true
                    } catch {
                        print(error)
                    }
                    
                }
            }
        case .none:
            break
        }
    }
    
    @objc func saveImageToPhoto() {
        switch imageItem {
        case .image(let uIImage):
            if let uIImage {
                UIImageWriteToSavedPhotosAlbum(uIImage, self, #selector(saveImageCompletion(image:didFinishSavingWithError:contextInfo:)), nil)
            }
        case .url(_, _):
            break
        case .livePhotoByResourceFileURLs(let imageFileURL, let videoFileURL):
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: imageFileURL!, options: nil)
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = true
                request.addResource(with: .pairedVideo, fileURL: videoFileURL!, options: options)
                request.creationDate = Date()
            }) { [weak self] success, error in
                if success {
                    self?.changeButtonImageWhenSaveSuccess()
                }
            }
        case .none:
            break
        }
    }
    
    private func buildLiftSubjectsImage(image: UIImage) -> UIImage? {
    
        let max = max(image.size.height, image.size.width)
        // 计算拼接后的总大小
        let totalHeight = max //+ (max / 10)
        let totalSize = CGSize(width: totalHeight, height: totalHeight)
        
        // 开始上下文
        UIGraphicsBeginImageContextWithOptions(totalSize, false, 1)
        let context = UIGraphicsGetCurrentContext()
        context?.setFillColor(UIColor.clear.cgColor)
        context?.fill(CGRect(origin: .zero, size: totalSize))
        
        // 当前绘制的起始位置
        
        // 在当前上下文中绘制图像
//        image.draw(in: rect)
//        image.draw(in: CGRect(origin: CGPoint(x: totalHeight / 2, y: totalHeight / 2), size: CGSize(width: image.size.width, height: image.size.height)))
        
        let rect2 = CGRect(x: 0, y: 0, width: totalSize.width, height: totalSize.height)

        // 计算绘制矩形的起点位置，使图像中心与矩形中心对齐
        let originX = rect2.origin.x + (rect2.size.width - image.size.width) / 2
        let originY = rect2.origin.y + (rect2.size.height - image.size.height) / 2
        let origin = CGPoint(x: originX, y: originY)

        // 在指定矩形的中心绘制图像
        image.draw(in: CGRect(origin: origin, size: image.size))

        
        // 获取拼接后的图像
        let concatenatedImage = UIGraphicsGetImageFromCurrentImageContext()
        
        // 结束上下文
        UIGraphicsEndImageContext()
        
        return concatenatedImage
    }
    
    @objc func saveImageCompletion(image: UIImage, didFinishSavingWithError error: Error, contextInfo: UnsafeMutableRawPointer?) {
        changeButtonImageWhenSaveSuccess()
    }
    
    private func changeButtonImageWhenSaveSuccess() {
        DispatchQueue.main.async { [weak self] in
            self?.downloadButton.setImage(UIImage(systemName: "checkmark"), for: .normal)
            self?.downloadButton.backgroundColor = .systemGreen.withAlphaComponent(0.5)
            self?.downloadButton.sizeToFit()
        }
    }
    
    private func layout() {
        updateConstraintsForSize(view.bounds.size)
        updateMinMaxZoomScaleForSize(view.bounds.size)
    }
    
    // MARK: Add Gesture Recognizers
    
    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            livePhotoFlag.isHidden = true
            livePhotoView.isHidden = false
            livePhotoView.startPlayback(with: .full)
        } else if gesture.state == .ended {
            livePhotoFlag.isHidden = false
            livePhotoView.isHidden = true
            livePhotoView.stopPlayback()
        }
    }

    func addGestureRecognizers() {
        
        let panGesture = UIPanGestureRecognizer(
            target: self, action: #selector(didPan(_:)))
        panGesture.cancelsTouchesInView = false
        panGesture.delegate = self
        scrollView.addGestureRecognizer(panGesture)
        
        let pinchRecognizer = UITapGestureRecognizer(
            target: self, action: #selector(didPinch(_:)))
        pinchRecognizer.numberOfTapsRequired = 1
        pinchRecognizer.numberOfTouchesRequired = 2
        scrollView.addGestureRecognizer(pinchRecognizer)
        
        let singleTapGesture = UITapGestureRecognizer(
            target: self, action: #selector(didSingleTap(_:)))
        singleTapGesture.numberOfTapsRequired = 1
        singleTapGesture.numberOfTouchesRequired = 1
        scrollView.addGestureRecognizer(singleTapGesture)
        
        let doubleTapRecognizer = UITapGestureRecognizer(
            target: self, action: #selector(didDoubleTap(_:)))
        doubleTapRecognizer.numberOfTapsRequired = 2
        doubleTapRecognizer.numberOfTouchesRequired = 1
        scrollView.addGestureRecognizer(doubleTapRecognizer)
        
        singleTapGesture.require(toFail: doubleTapRecognizer)
    }
    
    @objc
    func didPan(_ gestureRecognizer: UIPanGestureRecognizer) {
        livePhotoFlag.isHidden = true
        guard
            isAnimating == false,
            scrollView.zoomScale == scrollView.minimumZoomScale
            else { return }
        
        let container:UIView! = imageView
        if gestureRecognizer.state == .began {
            lastLocation = container.center
        }
        
        if gestureRecognizer.state != .cancelled {
            let translation: CGPoint = gestureRecognizer
                .translation(in: view)
            container.center = CGPoint(
                x: lastLocation.x + translation.x,
                y: lastLocation.y + translation.y)
        }
        
        let diffY = view.center.y - container.center.y
        backgroundView?.alpha = 1.0 - abs(diffY/view.center.y)
        if gestureRecognizer.state == .ended {
            if abs(diffY) > 60 {
                dismiss(animated: true)
            } else {
                executeCancelAnimation()
            }
        }
    }
    
    @objc
    func didPinch(_ recognizer: UITapGestureRecognizer) {
        livePhotoFlag.isHidden = true
        var newZoomScale = scrollView.zoomScale / 1.5
        newZoomScale = max(newZoomScale, scrollView.minimumZoomScale)
        scrollView.setZoomScale(newZoomScale, animated: true)
    }
    
    @objc
    func didSingleTap(_ recognizer: UITapGestureRecognizer) {
        
        let currentNavAlpha = self.navBar?.alpha ?? 0.0
        UIView.animate(withDuration: 0.235) {
            self.navBar?.alpha = currentNavAlpha > 0.5 ? 0.0 : 1.0
        }
    }
    
    @objc
    func didDoubleTap(_ recognizer:UITapGestureRecognizer) {
        let pointInView = recognizer.location(in: imageView)
        zoomInOrOut(at: pointInView)
    }
    
    func gestureRecognizerShouldBegin(
        _ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard scrollView.zoomScale == scrollView.minimumZoomScale,
            let panGesture = gestureRecognizer as? UIPanGestureRecognizer
            else { return false }
        
        let velocity = panGesture.velocity(in: scrollView)
        return abs(velocity.y) > abs(velocity.x)
    }
    
    
}

// MARK: Adjusting the dimensions
extension ImageViewerController {
    
    func updateMinMaxZoomScaleForSize(_ size: CGSize) {
        
        let targetSize = imageView.bounds.size
        if targetSize.width == 0 || targetSize.height == 0 {
            return
        }
        
        let minScale = min(
            size.width/targetSize.width,
            size.height/targetSize.height)
        let maxScale = max(
            (size.width + 1.0) / targetSize.width,
            (size.height + 1.0) / targetSize.height)
        
        scrollView.minimumZoomScale = minScale
        scrollView.zoomScale = minScale
        maxZoomScale = maxScale
        scrollView.maximumZoomScale = maxZoomScale * 1.1
    }
    
    
    func zoomInOrOut(at point:CGPoint) {
        let newZoomScale = scrollView.zoomScale == scrollView.minimumZoomScale
            ? maxZoomScale : scrollView.minimumZoomScale
        let size = scrollView.bounds.size
        let w = size.width / newZoomScale
        let h = size.height / newZoomScale
        let x = point.x - (w * 0.5)
        let y = point.y - (h * 0.5)
        let rect = CGRect(x: x, y: y, width: w, height: h)
        scrollView.zoom(to: rect, animated: true)
    }
    
    func updateConstraintsForSize(_ size: CGSize) {
        let yOffset = max(0, (size.height - imageView.frame.height) / 2)
        top.constant = yOffset
        bottom.constant = yOffset
        
        let xOffset = max(0, (size.width - imageView.frame.width) / 2)
        leading.constant = xOffset
        trailing.constant = xOffset
        view.layoutIfNeeded()
        
        switch imageItem {
        case .image(_):
            break
        case .url(_, _):
            break
        case .livePhotoByResourceFileURLs(_, _):
            livePhotoView.frame = imageView.frame
            livePhotoFlag.frame = CGRect(x: imageView.frame.minX + 10, y: imageView.frame.minY + 10, width: 15, height: 15)
        case .none:
            break
        }
    }
    
}

// MARK: Animation Related stuff
extension ImageViewerController {
    
    private func executeCancelAnimation() {
        self.isAnimating = true
        UIView.animate(
            withDuration: 0.237,
            animations: {
                self.imageView.center = self.view.center
                self.backgroundView?.alpha = 1.0
        }) {[weak self] _ in
            self?.isAnimating = false
        }
    }
}

extension ImageViewerController:UIScrollViewDelegate {
    
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        livePhotoFlag.isHidden = true
        
        updateConstraintsForSize(view.bounds.size)
    }
}

