//
//  PS5MediaScanner.swift
//  PS5-media-manager
//
//  Created by 赵亦涵 on 2026/2/13.
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

struct PS5MediaScanner {
    struct GameMediaGroup: Sendable {
        let title: String
        let items: [MediaItem]
    }

    struct PS5MediaLibrary: Sendable {
        let screenshots: [GameMediaGroup]
        let videoClips: [GameMediaGroup]
    }

    nonisolated static func scanLibrary(rootURL: URL) -> PS5MediaLibrary {
        let createURL = rootURL.appendingPathComponent("CREATE")
        let screenshotsURL = createURL.appendingPathComponent("Screenshots")
        let videoClipsURL = createURL.appendingPathComponent("Video Clips")

        let screenshots = scanCategory(folderURL: screenshotsURL, ignoreImage: false)
        let videoClips = scanCategory(folderURL: videoClipsURL, ignoreImage: true)
        return PS5MediaLibrary(screenshots: screenshots, videoClips: videoClips)
    }

    nonisolated private static func scanCategory(folderURL: URL, ignoreImage: Bool) -> [GameMediaGroup] {
        guard let gameFolders = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var groups: [GameMediaGroup] = []
        for gameFolderURL in gameFolders {
            let values = try? gameFolderURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }

            guard let files = try? FileManager.default.contentsOfDirectory(
                at: gameFolderURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            var items: [MediaItem] = []
            for fileURL in files {
                let fileValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey])
                guard fileValues?.isDirectory != true else { continue }

                let ext = fileURL.pathExtension.lowercased()
                if ignoreImage && (ext == "jpg" || ext == "jpeg" || ext == "png") {
                    continue
                }

                if let item = MediaItemFactory.create(from: fileURL) {
                    items.append(item)
                }
            }

            if !items.isEmpty {
                let deduped = removeDuplicates(from: items)
                let sorted = deduped.sorted { $0.filePath.path < $1.filePath.path }
                groups.append(GameMediaGroup(title: gameFolderURL.lastPathComponent, items: sorted))
            }
        }

        return groups.sorted { $0.title < $1.title }
    }

    nonisolated private static func removeDuplicates(from items: [MediaItem]) -> [MediaItem] {
        let sortedItems = items.sorted {
            if $0.name.count != $1.name.count {
                return $0.name.count < $1.name.count
            }
            return $0.name < $1.name
        }

        var result: [MediaItem] = []
        var sizeCache: [URL: Int] = [:]
        var hashCache: [URL: String] = [:]

        for item in sortedItems {
            var duplicateIndex: Int? = nil

            for (index, existing) in result.enumerated() {
                guard isComparableType(lhs: item, rhs: existing),
                      shouldCompareNames(item.name, existing.name) else {
                    continue
                }

                guard let existingHash = contentHash(for: existing, sizeCache: &sizeCache, hashCache: &hashCache),
                      let itemHash = contentHash(for: item, sizeCache: &sizeCache, hashCache: &hashCache) else {
                    continue
                }

                if existingHash == itemHash {
                    duplicateIndex = index
                    break
                }
            }

            guard let duplicateIndex else {
                result.append(item)
                continue
            }

            let existing = result[duplicateIndex]
            print("[ScanDedup] detected duplicate: current=\(item.filePath.lastPathComponent), existing=\(existing.filePath.lastPathComponent)")

            if shouldReplaceKeptItem(existing: existing, candidate: item) {
                removeCoverImageIfNeeded(for: existing)
                removeDuplicateVideoIfNeeded(for: existing)
                result[duplicateIndex] = item
            } else {
                removeCoverImageIfNeeded(for: item)
                removeDuplicateVideoIfNeeded(for: item)
            }
        }

        return result.sorted { $0.filePath.path < $1.filePath.path }
    }

    nonisolated private static func removeCoverImageIfNeeded(for item: MediaItem) {
        guard let videoItem = item as? VideoItem,
              let coverImage = videoItem.coverImage else {
            return
        }
        try? FileManager.default.removeItem(at: coverImage.filePath)
    }

    nonisolated private static func removeDuplicateVideoIfNeeded(for item: MediaItem) {
        guard item is VideoItem else {
            return
        }
        try? FileManager.default.removeItem(at: item.filePath)
    }

    nonisolated private static func isComparableType(lhs: MediaItem, rhs: MediaItem) -> Bool {
        lhs.filePath.pathExtension.caseInsensitiveCompare(rhs.filePath.pathExtension) == .orderedSame
    }

    nonisolated private static func shouldCompareNames(_ lhs: String, _ rhs: String) -> Bool {
        let lowerLHS = lhs.lowercased()
        let lowerRHS = rhs.lowercased()
        return lowerLHS == lowerRHS || lowerLHS.hasPrefix(lowerRHS) || lowerRHS.hasPrefix(lowerLHS)
    }

    nonisolated private static func shouldReplaceKeptItem(existing: MediaItem, candidate: MediaItem) -> Bool {
        if candidate.name.count != existing.name.count {
            return candidate.name.count < existing.name.count
        }
        return candidate.name < existing.name
    }

    nonisolated private static func fileSize(for url: URL, cache: inout [URL: Int]) -> Int? {
        if let cached = cache[url] {
            return cached
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        if let size {
            cache[url] = size
        }
        return size
    }

    nonisolated private static func contentHash(
        for item: MediaItem,
        sizeCache: inout [URL: Int],
        hashCache: inout [URL: String]
    ) -> String? {
        let url = item.filePath
        let hashChunkSize = 1024 * 1024

        if item.isVideo {
            guard let size = fileSize(for: url, cache: &sizeCache) else {
                return nil
            }
            return edgeHash(for: url, size: size, chunkSize: hashChunkSize, cache: &hashCache)
        }

        return fullFileHash(for: url, chunkSize: hashChunkSize, cache: &hashCache)
    }

    nonisolated private static func edgeHash(
        for url: URL,
        size: Int,
        chunkSize: Int,
        cache: inout [URL: String]
    ) -> String? {
        if let cached = cache[url] {
            return cached
        }
        let actualChunkSize = min(max(1, chunkSize), size)
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        let startData = (try? handle.read(upToCount: actualChunkSize)) ?? Data()
        let tailOffset = max(0, size - actualChunkSize)
        if size > actualChunkSize {
            try? handle.seek(toOffset: UInt64(tailOffset))
        } else {
            try? handle.seek(toOffset: 0)
        }
        let endData = (try? handle.read(upToCount: actualChunkSize)) ?? Data()

        var combined = Data()
        combined.append(startData)
        combined.append(endData)

        let digest = SHA256.hash(data: combined)
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        cache[url] = hash
        return hash
    }

    nonisolated private static func fullFileHash(
        for url: URL,
        chunkSize: Int,
        cache: inout [URL: String]
    ) -> String? {
        if let cached = cache[url] {
            return cached
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        let readChunkSize = max(1, chunkSize)

        while true {
            let chunk = (try? handle.read(upToCount: readChunkSize)) ?? Data()
            if chunk.isEmpty {
                break
            }
            hasher.update(data: chunk)
        }

        let digest = hasher.finalize()
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        cache[url] = hash
        return hash
    }
}
