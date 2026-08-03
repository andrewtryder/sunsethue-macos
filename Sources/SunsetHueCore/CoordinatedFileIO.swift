import Foundation

enum CoordinatedFileIO {
    static func readData(from url: URL, maxBytes: Int) throws -> Data? {
        var coordinatorError: NSError?
        var readError: Error?
        var result: Data?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
            do {
                guard FileManager.default.fileExists(atPath: readURL.path) else {
                    result = nil
                    return
                }
                let values = try readURL.resourceValues(forKeys: [.fileSizeKey])
                if let size = values.fileSize, size > maxBytes {
                    throw SunsetHueError.storageTooLarge
                }
                let data = try Data(contentsOf: readURL)
                if data.count > maxBytes {
                    throw SunsetHueError.storageTooLarge
                }
                result = data
            } catch {
                readError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let readError { throw readError }
        return result
    }

    static func writeAtomically(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var coordinatorError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            writingItemAt: url,
            options: [.forReplacing],
            error: &coordinatorError
        ) { writeURL in
            do {
                let tempURL = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
                try data.write(to: tempURL, options: .atomic)
                if FileManager.default.fileExists(atPath: writeURL.path) {
                    _ = try FileManager.default.replaceItemAt(writeURL, withItemAt: tempURL)
                } else {
                    try FileManager.default.moveItem(at: tempURL, to: writeURL)
                }
            } catch {
                writeError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let writeError { throw writeError }
    }

    static func deleteItem(at url: URL) throws {
        var coordinatorError: NSError?
        var deleteError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            writingItemAt: url,
            options: [.forDeleting],
            error: &coordinatorError
        ) { writeURL in
            do {
                if FileManager.default.fileExists(atPath: writeURL.path) {
                    try FileManager.default.removeItem(at: writeURL)
                }
            } catch {
                deleteError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let deleteError { throw deleteError }
    }

    /// Moves a damaged file aside. Returns the quarantine file name on success.
    @discardableResult
    static func quarantineCorruptFile(at url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let stamp = Int(Date().timeIntervalSince1970)
        let fileName = "\(url.lastPathComponent).corrupt-\(stamp)"
        let dest = url.deletingLastPathComponent().appendingPathComponent(fileName)
        do {
            try FileManager.default.moveItem(at: url, to: dest)
            return fileName
        } catch {
            return nil
        }
    }
}
