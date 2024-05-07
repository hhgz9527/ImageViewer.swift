import UIKit
import Photos

public enum ImageItem {
    case image(UIImage?)
    case url(URL, placeholder: UIImage?)
    case livePhotoByResourceFileURLs(imageFileURL: URL?, videoFileURL: URL?)
}
