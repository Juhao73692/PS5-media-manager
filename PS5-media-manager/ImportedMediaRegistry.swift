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

    struct Entry: Codable, Equatable {
        let hash: String
        let sourceFilePath: String
        let importedAt: Date
        let isVideo: Bool
        let chunkSize: Int
    }

    struct DuplicateMatch: Equatable {
        let hash: String
        let existingFilePath: String
        let chunkSize: Int
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

    func findDuplicate(forHash hash: String, chunkSize: Int) -> DuplicateMatch? {
        guard let entry = store.entries.last(where: { $0.hash == hash && $0.chunkSize == chunkSize }) else {
            return nil
        }

        return DuplicateMatch(hash: hash, existingFilePath: entry.sourceFilePath, chunkSize: chunkSize)
    }

    func recordImportedFile(hash: String, sourceFilePath: String, isVideo: Bool, chunkSize: Int) throws {
        if let index = store.entries.lastIndex(where: { $0.hash == hash && $0.chunkSize == chunkSize }) {
            store.entries.remove(at: index)
        }

        store.entries.append(
            Entry(
                hash: hash,
                sourceFilePath: sourceFilePath,
                importedAt: Date(),
                isVideo: isVideo,
                chunkSize: chunkSize
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
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode(PersistedStore.self, from: data) else {
            return PersistedStore()
        }

        return decoded
    }
}

enum PartialFileHasher {
    nonisolated static func hashFirstChunk(of fileURL: URL, chunkSize: Int = ImportedMediaRegistry.defaultChunkSize) throws -> String {
        let inputAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if inputAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let data = try handle.read(upToCount: max(1, chunkSize)) ?? Data()
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
