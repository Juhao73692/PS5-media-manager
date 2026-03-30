//
//  ImportedMediaRegistry.swift
//  PS5-media-manager
//
//  Created by 赵亦涵 on 2026/3/22.
//
//  Copyright © 2026 赵亦涵.
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU Lesser General Public License as published by
//  the Free Software Foundation; either version 2.1 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU Lesser General Public License for more details.
//
//  You should have received a copy of the GNU Lesser General Public License
//  along with this program. If not, see <http://www.gnu.org/licenses/>.
//

import CryptoKit
import Foundation

actor ImportedMediaRegistry {
    static let shared = ImportedMediaRegistry()
    static let defaultChunkSize = 4096
    static let detectionMethodVersion = "1.0"

    struct Entry: Codable, Equatable {
        let hash: String
        let fileName: String
        let fileType: String
        let detectionMethodVersion: String
    }

    struct DuplicateMatch: Equatable {
        let hash: String
        let existingFileName: String
        let existingFileType: String
    }

    private struct PersistedStore: Codable {
        var entries: [Entry] = []
    }

    private let storeURL: URL
    private var store: PersistedStore

    init(fileManager: FileManager = .default) {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directoryURL = appSupportURL.appendingPathComponent("PS5-media-manager", isDirectory: true)
        self.storeURL = directoryURL.appendingPathComponent("imported-media-registry.json")
        self.store = Self.loadStore(from: storeURL)
    }

    init(storeURL: URL) {
        self.storeURL = storeURL
        self.store = Self.loadStore(from: storeURL)
    }

    func findDuplicate(forSourceURL sourceURL: URL, hash: String) -> DuplicateMatch? {
        let incomingName = Self.normalizedFileName(from: sourceURL)
        let incomingType = sourceURL.pathExtension.lowercased()
        guard let entry = store.entries.reversed().first(where: { entry in
            guard entry.detectionMethodVersion == Self.detectionMethodVersion else {
                return false
            }

            guard entry.fileType == incomingType else {
                return false
            }

            guard Self.shouldCompareNames(incomingName, entry.fileName) else {
                return false
            }

            return entry.hash == hash
        }) else {
            return nil
        }

        return DuplicateMatch(
            hash: hash,
            existingFileName: entry.fileName,
            existingFileType: entry.fileType
        )
    }

    func recordImportedFile(sourceURL: URL, hash: String) throws {
        let fileName = Self.normalizedFileName(from: sourceURL)
        let fileType = sourceURL.pathExtension.lowercased()
        if let index = store.entries.lastIndex(where: {
            $0.fileName == fileName && $0.fileType == fileType && $0.detectionMethodVersion == Self.detectionMethodVersion
        }) {
            store.entries.remove(at: index)
        }

        store.entries.append(
            Entry(
                hash: hash,
                fileName: fileName,
                fileType: fileType,
                detectionMethodVersion: Self.detectionMethodVersion
            )
        )

        try persist()
    }

    private func persist() throws {
        let directoryURL = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(store)
        try data.write(to: storeURL, options: .atomic)
    }

    private static func loadStore(from storeURL: URL) -> PersistedStore {
        guard let data = try? Data(contentsOf: storeURL) else {
            return PersistedStore()
        }

        let decoder = JSONDecoder()
        guard let decoded = try? decoder.decode(PersistedStore.self, from: data) else {
            return PersistedStore()
        }

        return decoded
    }

    private static func normalizedFileName(from url: URL) -> String {
        url.deletingPathExtension().lastPathComponent.lowercased()
    }

    private static func shouldCompareNames(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || lhs.hasPrefix(rhs) || rhs.hasPrefix(lhs)
    }
}

enum PartialFileHasher {
    nonisolated static func hashFirstAndLastChunk(of fileURL: URL, chunkSize: Int = ImportedMediaRegistry.defaultChunkSize) throws -> String {
        let inputAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if inputAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let actualChunkSize = max(1, chunkSize)
        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0

        let startData = try handle.read(upToCount: actualChunkSize) ?? Data()
        let endData: Data

        if fileSize > actualChunkSize {
            let tailOffset = UInt64(max(0, fileSize - actualChunkSize))
            try handle.seek(toOffset: tailOffset)
            endData = try handle.read(upToCount: actualChunkSize) ?? Data()
        } else {
            endData = Data()
        }

        var combined = Data()
        combined.append(startData)
        combined.append(endData)

        let digest = SHA256.hash(data: combined)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
