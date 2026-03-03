//
//  MediaPreviewView.swift
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

import AppKit
import AVFoundation
import Combine
import SwiftUI

struct MediaPreviewView: View {
    let item: MediaItem?
    @StateObject private var thumbnailLoader = VideoThumbnailLoader()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let item = item {
                Text(item.name)
                    .font(.title2)
                Text(item.typeLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(item.filePath.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let videoItem = item as? VideoItem {
                    if let coverImage = videoItem.coverImage {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("封面图")
                                .font(.subheadline)
                            Text(coverImage.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(coverImage.filePath.path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    else {
                        Text("无封面图")
                            .font(.subheadline)
                    }
                }
                if item.isVideo {
                    if let videoItem = item as? VideoItem, let coverImage = videoItem.coverImage {
                        PhotoPreviewView(url: coverImage.filePath)
                            .frame(minHeight: 240)
                    } else {
                        VideoThumbnailView(image: thumbnailLoader.image)
                            .frame(minHeight: 240)
                            .onAppear {
                                thumbnailLoader.load(url: item.filePath)
                            }
                            .onChange(of: item.filePath) { _, newURL in
                                thumbnailLoader.load(url: newURL)
                            }
                    }
                } else {
                    PhotoPreviewView(url: item.filePath)
                        .frame(minHeight: 240)
                }
            } else {
                Text("请选择一个媒体文件")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}

final class VideoThumbnailLoader: ObservableObject {
    @Published var image: NSImage? = nil

    func load(url: URL) {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 900, height: 540)

        let targetTime = CMTime(seconds: 1.0, preferredTimescale: 600)
        DispatchQueue.main.async {
            self.image = nil
        }
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: targetTime)]) { [weak self] _, cgImage, _, result, _ in
            let nsImage: NSImage?
            if result == .succeeded, let cgImage {
                nsImage = NSImage(cgImage: cgImage, size: .zero)
            } else {
                nsImage = nil
            }

            DispatchQueue.main.async {
                self?.image = nsImage
            }
        }
    }
}

struct VideoThumbnailView: View {
    let image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.08))

            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(12)
            } else {
                ProgressView()
            }
        }
    }
}
struct PhotoPreviewView: View {
    let url: URL
    @State private var image: NSImage? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.08))

            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(12)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: url) { _, _ in
            loadImage()
        }
    }

    private func loadImage() {
        let urlCopy = url
        DispatchQueue.main.async {
            image = nil
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = NSImage(contentsOf: urlCopy)
            DispatchQueue.main.async {
                image = loaded
            }
        }
    }
}

