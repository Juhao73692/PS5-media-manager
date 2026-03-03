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
                let sorted = items.sorted { $0.filePath.path < $1.filePath.path }
                groups.append(GameMediaGroup(title: gameFolderURL.lastPathComponent, items: sorted))
            }
        }

        return groups.sorted { $0.title < $1.title }
    }
}
