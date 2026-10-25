import UIKit
import UniformTypeIdentifiers

/// The Files picker, for audio files or whole folders.
enum Importer {
    private static let delegate = PickerDelegate()

    static func present(from controller: UIViewController) {
        var types: [UTType] = [.audio, .folder]
        if let flac = UTType(filenameExtension: "flac") { types.append(flac) }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.allowsMultipleSelection = true
        picker.delegate = delegate
        controller.present(picker, animated: true)
    }

    private final class PickerDelegate: NSObject, UIDocumentPickerDelegate {
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            Library.shared.importFiles(urls)
        }
    }
}
