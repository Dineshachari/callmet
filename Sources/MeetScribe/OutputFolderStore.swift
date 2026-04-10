import Foundation

final class OutputFolderStore {
    static let shared = OutputFolderStore()

    private let selectedFolderKey = "selectedOutputFolderPath"
    private let fileManager = FileManager.default

    private init() {}

    var selectedFolderURL: URL? {
        get {
            guard let path = UserDefaults.standard.string(forKey: selectedFolderKey) else {
                return nil
            }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        set {
            guard let newValue else {
                UserDefaults.standard.removeObject(forKey: selectedFolderKey)
                return
            }
            UserDefaults.standard.set(newValue.path, forKey: selectedFolderKey)
        }
    }

    func recordingDirectoryURL() -> URL {
        guard let selectedFolderURL else {
            return fileManager.temporaryDirectory
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: selectedFolderURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return fileManager.temporaryDirectory
        }

        return selectedFolderURL
    }

    func displayName() -> String {
        selectedFolderURL?.lastPathComponent ?? "Temporary Files"
    }
}
