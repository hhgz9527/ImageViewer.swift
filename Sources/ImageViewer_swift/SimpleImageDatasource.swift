import UIKit

class SimpleImageDatasource:ImageDataSource {
    func liftSubject(img: UIImage?, index: Int) {
        
    }
    
    private(set) var imageItems:[ImageItem]
    
    init(imageItems: [ImageItem]) {
        self.imageItems = imageItems
    }
    
    func numberOfImages() -> Int {
        return imageItems.count
    }
    
    func imageItem(at index: Int) -> ImageItem {
        return imageItems[index]
    }
}


class YGSimpleImageDataSource: ImageDataSource {

    
    private(set) var imageItems:[ImageItem]
    private(set) var action: ((UIImage?, Int) -> Void)?
    
    init(imageItems: [ImageItem], action: @escaping ((UIImage?, Int) -> Void)) {
        self.imageItems = imageItems
        self.action = action
    }
    
    func numberOfImages() -> Int {
        return imageItems.count
    }
    
    func imageItem(at index: Int) -> ImageItem {
        return imageItems[index]
    }
    
    func liftSubject(img: UIImage?, index: Int) {
        action?(img, index)
    }
}
