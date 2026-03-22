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
    struct GameMediaGroup {
        let title: String
        let items: [MediaItem]
    }

    struct PS5MediaLibrary {
        let screenshots: [GameMediaGroup]
        let videoClips: [GameMediaGroup]
    }

    static func scanLibrary(rootURL: URL) -> PS5MediaLibrary {
        let createURL = rootURL.appendingPathComponent("CREATE")
        let screenshotsURL = createURL.appendingPathComponent("Screenshots")
        let videoClipsURL = createURL.appendingPathComponent("Video Clips")

        let screenshots = scanCategory(folderURL: screenshotsURL, ignoreImage: false)
        let videoClips = scanCategory(folderURL: videoClipsURL, ignoreImage: true)
        return PS5MediaLibrary(screenshots: screenshots, videoClips: videoClips)
    }

    private static func scanCategory(folderURL: URL, ignoreImage: Bool) -> [GameMediaGroup] {
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

    private static func removeDuplicates(from items: [MediaItem]) -> [MediaItem] {
        var grouped: [String: [MediaItem]] = [:]
        for item in items {
            let key = normalizedKey(for: item)
            grouped[key, default: []].append(item)
        }

        var result: [MediaItem] = []
        for group in grouped.values {
            if group.count == 1 {
                result.append(group[0])
                continue
            }

            let sortedGroup = group.sorted {
                if $0.name.count != $1.name.count {
                    return $0.name.count < $1.name.count
                }
                return $0.name < $1.name
            }

            var sizeCache: [URL: Int] = [:]
            var hashCache: [URL: String] = [:]
            var keepers: [MediaItem] = []

            for item in sortedGroup {
                guard let original = keepers.first else {
                    keepers.append(item)
                    continue
                }

                if !isSuspectedDuplicateName(item.name) && !isSuspectedDuplicateName(original.name) {
                    keepers.append(item)
                    continue
                }

                guard let originalSize = fileSize(for: original.filePath, cache: &sizeCache),
                      let itemSize = fileSize(for: item.filePath, cache: &sizeCache) else {
                    keepers.append(item)
                    continue
                }

                if originalSize != itemSize {
                    keepers.append(item)
                    continue
                }

                guard let originalHash = edgeHash(for: original.filePath, size: originalSize, cache: &hashCache),
                      let itemHash = edgeHash(for: item.filePath, size: itemSize, cache: &hashCache) else {
                    keepers.append(item)
                    continue
                }

                if originalHash == itemHash {
                    if item.name.count < original.name.count {
                        removeCoverImageIfNeeded(for: original)
                        removeDuplicateVideoIfNeeded(for: original)
                        keepers[0] = item
                    } else if item.name.count == original.name.count && item.name < original.name {
                        removeCoverImageIfNeeded(for: original)
                        removeDuplicateVideoIfNeeded(for: original)
                        keepers[0] = item
                    } else {
                        removeCoverImageIfNeeded(for: item)
                        removeDuplicateVideoIfNeeded(for: item)
                    }
                } else {
                    keepers.append(item)
                }
            }

            result.append(contentsOf: keepers)
        }

        return result
    }

    private static func removeCoverImageIfNeeded(for item: MediaItem) {
        guard let videoItem = item as? VideoItem,
              let coverImage = videoItem.coverImage else {
            return
        }
        try? FileManager.default.removeItem(at: coverImage.filePath)
    }

    private static func removeDuplicateVideoIfNeeded(for item: MediaItem) {
        guard item is VideoItem else {
            return
        }
        try? FileManager.default.removeItem(at: item.filePath)
    }

    private static func normalizedKey(for item: MediaItem) -> String {
        let normalizedName = normalizedName(for: item.name)
        let ext = item.filePath.pathExtension.lowercased()
        return "\(normalizedName).\(ext)"
    }

    private static func normalizedName(for name: String) -> String {
        if let range = name.range(of: "_\\d+$", options: .regularExpression) {
            return String(name[..<range.lowerBound])
        }
        return name
    }

    private static func isSuspectedDuplicateName(_ name: String) -> Bool {
        return name.range(of: "_\\d+$", options: .regularExpression) != nil
    }

    private static func fileSize(for url: URL, cache: inout [URL: Int]) -> Int? {
        if let cached = cache[url] {
            return cached
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        if let size {
            cache[url] = size
        }
        return size
    }

    private static func edgeHash(for url: URL, size: Int, cache: inout [URL: String]) -> String? {
        if let cached = cache[url] {
            return cached
        }
        let chunkSize = min(4096, size)
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        let startData = (try? handle.read(upToCount: chunkSize)) ?? Data()
        let tailOffset = max(0, size - chunkSize)
        if size > chunkSize {
            try? handle.seek(toOffset: UInt64(tailOffset))
        } else {
            try? handle.seek(toOffset: 0)
        }
        let endData = (try? handle.read(upToCount: chunkSize)) ?? Data()

        var combined = Data()
        combined.append(startData)
        combined.append(endData)

        let digest = SHA256.hash(data: combined)
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        cache[url] = hash
        return hash
    }
}
