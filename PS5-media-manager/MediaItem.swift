//
//  MediaItem.swift
//  PS5-media-manager
//
//  Created by 赵亦涵 on 2026/1/26.
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

enum MediaType: Sendable {
    enum VideoType {
        case webm
        case mp4
    }

    enum PhotoType {
        case jpeg
        case png
    }
    
    case video(VideoType)
    case photo(PhotoType)
}

protocol MediaItem: Sendable {
    nonisolated var id: UUID { get }
    nonisolated var type: MediaType { get }
    nonisolated var name: String { get }
    nonisolated var filePath: URL { get }
}

protocol PhotoItem: MediaItem {
    
}

final class JpegItem: PhotoItem, @unchecked Sendable {
    let id: UUID
    let type: MediaType
    let name: String
    let filePath: URL
    nonisolated init(filePath: URL) {
        self.id = UUID()
        self.type = .photo(.jpeg)
        self.name = filePath.deletingPathExtension().lastPathComponent
        self.filePath = filePath
    }
}

final class PngItem: PhotoItem, @unchecked Sendable {
    let id: UUID
    let type: MediaType
    let name: String
    let filePath: URL
    nonisolated init(filePath: URL) {
        self.id = UUID()
        self.type = .photo(.png)
        self.name = filePath.deletingPathExtension().lastPathComponent
        self.filePath = filePath
    }
}

protocol VideoItem: MediaItem {
    nonisolated var coverImage: PhotoItem? { get }
}

final class WebmItem: VideoItem, @unchecked Sendable {
    let id: UUID
    let type: MediaType
    let name: String
    let filePath: URL
    let coverImage: PhotoItem?
    nonisolated init(filePath: URL) {
        self.id = UUID()
        self.type = .video(.webm)
        self.name = filePath.deletingPathExtension().lastPathComponent
        self.filePath = filePath
        self.coverImage = VideoItemCoverResolver.resolveCoverImage(for: filePath)
    }
}

final class Mp4Item: VideoItem, @unchecked Sendable {
    let id: UUID
    let type: MediaType
    let name: String
    let filePath: URL
    let coverImage: PhotoItem?
    nonisolated init(filePath: URL) {
        self.id = UUID()
        self.type = .video(.mp4)
        self.name = filePath.deletingPathExtension().lastPathComponent
        self.filePath = filePath
        self.coverImage = VideoItemCoverResolver.resolveCoverImage(for: filePath)
    }
}

enum VideoItemCoverResolver {
    nonisolated static func resolveCoverImage(for videoURL: URL) -> PhotoItem? {
        let pathWithoutExt = videoURL.deletingPathExtension()
        let candidates: [(String, (URL) -> PhotoItem)] = [
            ("jpg", { JpegItem(filePath: $0) }),
            ("jpeg", { JpegItem(filePath: $0) }),
            ("png", { PngItem(filePath: $0) })
        ]

        for (ext, builder) in candidates {
            let candidateURL = pathWithoutExt.appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: candidateURL.path) {
                return builder(candidateURL)
            }
        }

        return nil
    }
}

enum MediaItemFactory {
    nonisolated static func create(from filePath: URL) -> MediaItem? {
        let ext = filePath.pathExtension.lowercased()

        switch ext {
        case "webm":
            return WebmItem(filePath: filePath)

        case "mp4":
            return Mp4Item(filePath: filePath)

        case "jpg", "jpeg":
            return JpegItem(filePath: filePath)

        case "png":
            return PngItem(filePath: filePath)

        default:
            return nil
        }
    }
}
extension MediaItem {
    nonisolated var isVideo: Bool {
        if case .video = type {
            return true
        }
        return false
    }

    nonisolated var typeLabel: String {
        switch type {
        case .video(let videoType):
            switch videoType {
            case .webm:
                return "webm"
            case .mp4:
                return "mp4"
            }
        case .photo(let photoType):
            switch photoType {
            case .jpeg:
                return "jpeg"
            case .png:
                return "png"
            }
        }
    }
}
