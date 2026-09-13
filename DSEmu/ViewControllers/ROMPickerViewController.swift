import UIKit
import UniformTypeIdentifiers

enum ROMPicker {
    static func make(delegate: UIDocumentPickerDelegate) -> UIDocumentPickerViewController {
        let ndsType = UTType(filenameExtension: "nds") ?? .data
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [ndsType])
        picker.delegate = delegate
        picker.allowsMultipleSelection = false
        return picker
    }
}
