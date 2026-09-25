import Foundation
import ZIPFoundation

/// Wraps ZIPFoundation so the Wallet module does not depend on zip details.
public enum ZipArchiver {
    public enum ZipError: Error, Sendable {
        case createFailed(String)
        case readFailed(String)
    }

    /// Creates an in-memory zip with every file at the archive root.
    public static func zip(files: [String: Data]) throws -> Data {
        guard let archive = Archive(accessMode: .create) else {
            throw ZipError.createFailed("Could not create in-memory archive")
        }
        for (name, data) in files.sorted(by: { $0.key < $1.key }) {
            let entryData = data
            let provider: (Int, Int) throws -> Data = { position, size in
                let start = position
                let end = min(position + size, entryData.count)
                guard start <= end, end <= entryData.count else {
                    throw ZipError.createFailed("Invalid buffer range while writing \(name)")
                }
                return entryData.subdata(in: start..<end)
            }
            do {
                try archive.addEntry(
                    with: name,
                    type: .file,
                    uncompressedSize: UInt32(entryData.count),
                    compressionMethod: .deflate,
                    provider: provider
                )
            } catch {
                throw ZipError.createFailed("Failed adding \(name): \(error)")
            }
        }
        guard let data = archive.data else {
            throw ZipError.createFailed("Archive produced no data")
        }
        return data
    }

    public static func unzip(_ data: Data) throws -> [String: Data] {
        guard let archive = Archive(data: data, accessMode: .read) else {
            throw ZipError.readFailed("Could not open archive")
        }
        var files: [String: Data] = [:]
        for entry in archive {
            guard entry.type == .file else { continue }
            var contents = Data()
            _ = try archive.extract(entry) { chunk in
                contents.append(chunk)
            }
            files[entry.path] = contents
        }
        return files
    }

    public static func entryNames(_ data: Data) throws -> [String] {
        guard let archive = Archive(data: data, accessMode: .read) else {
            throw ZipError.readFailed("Could not open archive")
        }
        return archive.map(\.path).sorted()
    }
}
