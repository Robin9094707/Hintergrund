import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct StudioDocumentPicker: UIViewControllerRepresentable {
    var onCompletion: (URL?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        makePicker(delegate: context.coordinator)
    }

    func updateUIViewController(_ picker: UIDocumentPickerViewController, context: Context) {
        context.coordinator.onCompletion = onCompletion
    }

    func makePicker(delegate: Coordinator) -> UIDocumentPickerViewController {
        // Keep the Files browser open to every document type. The caller validates the contents.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item, .data], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = delegate
        return picker
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onCompletion: (URL?) -> Void

        init(onCompletion: @escaping (URL?) -> Void) {
            self.onCompletion = onCompletion
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onCompletion(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCompletion(nil)
        }
    }
}
