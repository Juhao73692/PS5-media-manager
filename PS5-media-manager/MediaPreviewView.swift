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
import CryptoKit
import Photos
import SwiftUI
import UniformTypeIdentifiers

struct MediaPreviewView: View {
    let item: MediaItem?
    let selectedItems: [MediaItem]
    @StateObject private var thumbnailLoader = VideoThumbnailLoader()
    @State private var isTranscoding = false
    @State private var transcodeStatusMessage: String? = nil
    @State private var isAddingToPhotos = false
    @State private var photoLibraryStatusMessage: String? = nil
    @State private var isBatchTranscoding = false
    @State private var batchTranscodeStatusMessage: String? = nil
    @State private var isBatchAddingToPhotos = false
    @State private var batchPhotoLibraryStatusMessage: String? = nil
    @State private var duplicateImportAlert: DuplicateImportAlertContext? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !selectedItems.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("已选媒体：\(selectedItems.count) 项")
                        .font(.headline)

                    HStack(spacing: 12) {
                        Button(isBatchTranscoding ? "正在批量转码…" : "批量转码为 MOV（\(selectedVideoCount)）") {
                            startBatchTranscode(for: selectedItems)
                        }
                        .disabled(isBatchTranscoding || selectedVideoCount == 0)

                        if let batchTranscodeStatusMessage {
                            Text(batchTranscodeStatusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 12) {
                        Button(isBatchAddingToPhotos ? "正在批量导入…" : "批量添加至 Apple 相册") {
                            addBatchToPhotos(for: selectedItems)
                        }
                        .disabled(isBatchAddingToPhotos)

                        if let batchPhotoLibraryStatusMessage {
                            Text(batchPhotoLibraryStatusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()
            }

            if let item = item {
                Text(item.name)
                    .font(.title2)
                Text(item.typeLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(item.filePath.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if item.isVideo {
                    HStack(spacing: 12) {
                        Button(isTranscoding ? "正在转码…" : "转码为 MOV") {
                            startTranscode(for: item)
                        }
                        .disabled(isTranscoding)

                        if let transcodeStatusMessage {
                            Text(transcodeStatusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button(photoImportButtonTitle(for: item)) {
                        addToPhotos(for: item)
                    }
                    .disabled(isAddingToPhotos)

                    if let photoLibraryStatusMessage {
                        Text(photoLibraryStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

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
        .alert(
            "检测到重复媒体",
            isPresented: duplicateImportAlertIsPresented,
            presenting: duplicateImportAlert
        ) { context in
            Button("继续入库") {
                continueDuplicateImport(with: context)
            }
            Button("取消", role: .cancel) {
                duplicateImportAlert = nil
                isAddingToPhotos = false
                photoLibraryStatusMessage = "已取消入库"
            }
        } message: { context in
            Text("文件名匹配，且前后 \(ImportedMediaRegistry.defaultChunkSize) 字节哈希与已入库文件一致：\(context.existingFileName).\(context.existingFileType)")
        }
    }

    private func startTranscode(for item: MediaItem) {
        isTranscoding = true
        transcodeStatusMessage = "正在转码到影片目录…"

        let inputURL = item.filePath
        Task.detached(priority: .userInitiated) {
            do {
                let outputURL = try VideoTranscodePipeline.transcodeToManagedMovie(for: inputURL)

                await MainActor.run {
                    isTranscoding = false
                    transcodeStatusMessage = "已输出到 \(outputURL.path)"
                }
            } catch {
                await MainActor.run {
                    isTranscoding = false
                    transcodeStatusMessage = "转码失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func addToPhotos(for item: MediaItem) {
        isAddingToPhotos = true
        let isVideo = item.isVideo
        photoLibraryStatusMessage = isVideo ? "正在转码并导入 Apple 相册…" : "正在导入 Apple 相册…"

        let sourceURL = item.filePath
        Task.detached(priority: .userInitiated) {
            do {
                let hash = try PartialFileHasher.hashFirstAndLastChunk(
                    of: sourceURL,
                    chunkSize: ImportedMediaRegistry.defaultChunkSize
                )
                if let duplicate = await ImportedMediaRegistry.shared.findDuplicate(
                    forSourceURL: sourceURL,
                    hash: hash
                ) {
                    let currentFile = sourceURL.lastPathComponent
                    let existingFile = "\(duplicate.existingFileName).\(duplicate.existingFileType)"
                    print("[ImportDedup] detected duplicate: current=\(currentFile), existing=\(existingFile)")
                    await MainActor.run {
                        duplicateImportAlert = DuplicateImportAlertContext(
                            sourceURL: sourceURL,
                            isVideo: isVideo,
                            hash: hash,
                            existingFileName: duplicate.existingFileName,
                            existingFileType: duplicate.existingFileType
                        )
                        photoLibraryStatusMessage = "检测到疑似重复，等待确认…"
                    }
                    return
                }

                try await finalizePhotoImport(sourceURL: sourceURL, isVideo: isVideo, hash: hash)
            } catch {
                await MainActor.run {
                    isAddingToPhotos = false
                    photoLibraryStatusMessage = "导入失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private var selectedVideoCount: Int {
        selectedItems.filter { $0.isVideo }.count
    }

    private func startBatchTranscode(for items: [MediaItem]) {
        let videos = items.filter { $0.isVideo }
        guard !videos.isEmpty else {
            batchTranscodeStatusMessage = "当前选择中没有视频"
            return
        }

        isBatchTranscoding = true
        batchTranscodeStatusMessage = "准备批量转码…"

        Task.detached(priority: .userInitiated) {
            var successCount = 0
            var failedCount = 0

            for (index, video) in videos.enumerated() {
                await MainActor.run {
                    batchTranscodeStatusMessage = "正在转码 \(index + 1)/\(videos.count)：\(video.name)"
                }

                do {
                    _ = try VideoTranscodePipeline.transcodeToManagedMovie(for: video.filePath)
                    successCount += 1
                } catch {
                    failedCount += 1
                }
            }

            let resultMessage = "批量转码完成：成功 \(successCount)，失败 \(failedCount)"
            await MainActor.run {
                isBatchTranscoding = false
                batchTranscodeStatusMessage = resultMessage
            }
        }
    }

    private func addBatchToPhotos(for items: [MediaItem]) {
        isBatchAddingToPhotos = true
        batchPhotoLibraryStatusMessage = "准备批量导入 Apple 相册…"

        Task.detached(priority: .userInitiated) {
            var successCount = 0
            var skippedCount = 0
            var failedCount = 0

            for (index, media) in items.enumerated() {
                await MainActor.run {
                    batchPhotoLibraryStatusMessage = "正在导入 \(index + 1)/\(items.count)：\(media.name)"
                }

                do {
                    let hash = try PartialFileHasher.hashFirstAndLastChunk(
                        of: media.filePath,
                        chunkSize: ImportedMediaRegistry.defaultChunkSize
                    )
                    if let duplicate = await ImportedMediaRegistry.shared.findDuplicate(
                        forSourceURL: media.filePath,
                        hash: hash
                    ) {
                        let currentFile = media.filePath.lastPathComponent
                        let existingFile = "\(duplicate.existingFileName).\(duplicate.existingFileType)"
                        print("[ImportDedup] detected duplicate: current=\(currentFile), existing=\(existingFile)")
                        skippedCount += 1
                        continue
                    }

                    try await finalizeBatchPhotoImport(sourceURL: media.filePath, isVideo: media.isVideo, hash: hash)
                    successCount += 1
                } catch {
                    failedCount += 1
                }
            }

            let resultMessage = "批量导入完成：成功 \(successCount)，跳过重复 \(skippedCount)，失败 \(failedCount)"
            await MainActor.run {
                isBatchAddingToPhotos = false
                batchPhotoLibraryStatusMessage = resultMessage
            }
        }
    }

    private func photoImportButtonTitle(for item: MediaItem) -> String {
        if isAddingToPhotos {
            return item.isVideo ? "正在转码并导入…" : "正在导入…"
        }
        return item.isVideo ? "转码后添加至 Apple 相册" : "添加至 Apple 相册"
    }

    @MainActor
    private func continueDuplicateImport(with context: DuplicateImportAlertContext) {
        duplicateImportAlert = nil
        photoLibraryStatusMessage = "继续导入重复媒体…"

        Task.detached(priority: .userInitiated) {
            do {
                try await finalizePhotoImport(sourceURL: context.sourceURL, isVideo: context.isVideo, hash: context.hash)
            } catch {
                await MainActor.run {
                    isAddingToPhotos = false
                    photoLibraryStatusMessage = "导入失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private var duplicateImportAlertIsPresented: Binding<Bool> {
        Binding(
            get: { duplicateImportAlert != nil },
            set: { isPresented in
                if !isPresented {
                    duplicateImportAlert = nil
                }
            }
        )
    }

    nonisolated private func finalizePhotoImport(sourceURL: URL, isVideo: Bool, hash: String) async throws {
        let importURL: URL
        let shouldDeleteImportedFileAfterImport: Bool

        if isVideo {
            importURL = try VideoTranscodePipeline.transcodeToPhotoImportCache(for: sourceURL)
            shouldDeleteImportedFileAfterImport = true
        } else {
            importURL = sourceURL
            shouldDeleteImportedFileAfterImport = false
        }

//        try await PhotoLibraryImporter.importMedia(at: importURL, isVideo: isVideo)
        try await ImportedMediaRegistry.shared.recordImportedFile(sourceURL: sourceURL, hash: hash)
        if shouldDeleteImportedFileAfterImport {
            try? FileManager.default.removeItem(at: importURL)
        }

        await MainActor.run {
            isAddingToPhotos = false
            photoLibraryStatusMessage = "已添加到 Apple 相册"
        }
    }

    nonisolated private func finalizeBatchPhotoImport(sourceURL: URL, isVideo: Bool, hash: String) async throws {
        let importURL: URL
        let shouldDeleteImportedFileAfterImport: Bool

        if isVideo {
            importURL = try VideoTranscodePipeline.transcodeToPhotoImportCache(for: sourceURL)
            shouldDeleteImportedFileAfterImport = true
        } else {
            importURL = sourceURL
            shouldDeleteImportedFileAfterImport = false
        }

        try await PhotoLibraryImporter.importMedia(at: importURL, isVideo: isVideo)
        try await ImportedMediaRegistry.shared.recordImportedFile(sourceURL: sourceURL, hash: hash)
        if shouldDeleteImportedFileAfterImport {
            try? FileManager.default.removeItem(at: importURL)
        }
    }
}

struct DuplicateImportAlertContext: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let isVideo: Bool
    let hash: String
    let existingFileName: String
    let existingFileType: String
}

enum VideoTranscodePipeline {
    nonisolated static func transcodeToManagedMovie(for inputURL: URL) throws -> URL {
        let outputURL = try managedMovieOutputURL(for: inputURL)
        return try transcode(inputURL: inputURL, outputURL: outputURL)
    }

    nonisolated static func transcodeToPhotoImportCache(for inputURL: URL) throws -> URL {
        let outputURL = try photoImportCacheOutputURL(for: inputURL)
        return try transcode(inputURL: inputURL, outputURL: outputURL)
    }

    nonisolated private static func transcode(inputURL: URL, outputURL: URL) throws -> URL {
        try createManagedMovieDirectoryIfNeeded(for: outputURL.deletingLastPathComponent())

        let outputDirectoryURL = outputURL.deletingLastPathComponent()
        let inputAccess = inputURL.startAccessingSecurityScopedResource()
        let outputDirectoryAccess = outputDirectoryURL.startAccessingSecurityScopedResource()
        defer {
            if inputAccess {
                inputURL.stopAccessingSecurityScopedResource()
            }
            if outputDirectoryAccess {
                outputDirectoryURL.stopAccessingSecurityScopedResource()
            }
        }

        let wrapper = FFmpegWrapper()
        wrapper.transcodeToMOV(
            withInput: inputURL.path,
            andOutput: outputURL.path,
            andBitrateFactor: TranscodeSettings.selectedBitrateFactor
        )
        return outputURL
    }

    nonisolated private static func managedMovieOutputURL(for inputURL: URL) throws -> URL {
        guard let moviesDirectory = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first else {
            throw VideoTranscodePipelineError.moviesDirectoryUnavailable
        }

        let outputDirectory = moviesDirectory.appendingPathComponent("PS5 Media Manager", isDirectory: true)
        let outputFileName = inputURL.deletingPathExtension().lastPathComponent + ".mov"
        return uniqueOutputURL(
            in: outputDirectory,
            preferredFileName: outputFileName
        )
    }

    nonisolated private static func photoImportCacheOutputURL(for inputURL: URL) throws -> URL {
        let cacheRootDirectory = try importCacheRootDirectory()
        let hash = cachePathHash(for: inputURL)
        let levelOneDirectory = String(hash.prefix(2))
        let levelTwoDirectory = String(hash.dropFirst(2).prefix(2))
        let outputDirectory = cacheRootDirectory
            .appendingPathComponent(levelOneDirectory, isDirectory: true)
            .appendingPathComponent(levelTwoDirectory, isDirectory: true)
            .appendingPathComponent(hash, isDirectory: true)
        let outputFileName = inputURL.deletingPathExtension().lastPathComponent + ".mov"
        return uniqueOutputURL(
            in: outputDirectory,
            preferredFileName: outputFileName
        )
    }

    nonisolated private static func importCacheRootDirectory() throws -> URL {
        try TranscodeSettings.currentCacheRootDirectoryURL()
    }

    nonisolated private static func cachePathHash(for inputURL: URL) -> String {
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        let rawValue = "\(timestamp)-\(inputURL.lastPathComponent)"
        let digest = SHA256.hash(data: Data(rawValue.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func createManagedMovieDirectoryIfNeeded(for directoryURL: URL) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    nonisolated private static func uniqueOutputURL(in directoryURL: URL, preferredFileName: String) -> URL {
        let fileManager = FileManager.default
        let baseName = (preferredFileName as NSString).deletingPathExtension
        let ext = (preferredFileName as NSString).pathExtension
        var candidateURL = directoryURL.appendingPathComponent(preferredFileName)
        var suffix = 1

        while fileManager.fileExists(atPath: candidateURL.path) {
            let numberedName = "\(baseName)-\(suffix).\(ext)"
            candidateURL = directoryURL.appendingPathComponent(numberedName)
            suffix += 1
        }

        return candidateURL
    }
}

enum VideoTranscodePipelineError: LocalizedError {
    case moviesDirectoryUnavailable

    var errorDescription: String? {
        switch self {
        case .moviesDirectoryUnavailable:
            return "无法定位 Movies 目录"
        }
    }
}

enum PhotoLibraryImporter {
    private static let albumName = "PS5 Media"

    nonisolated static func importMedia(at fileURL: URL, isVideo: Bool) async throws {
        let authorizationStatus = await requestAuthorization()
        guard authorizationStatus == .authorized else {
            throw PhotoLibraryImportError.authorizationDenied
        }

        let album = try await ensureAlbumExists(named: albumName)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let assetRequest: PHAssetChangeRequest?
                if isVideo {
                    assetRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
                } else {
                    assetRequest = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
                }

                if let assetPlaceholder = assetRequest?.placeholderForCreatedAsset,
                   let albumChangeRequest = PHAssetCollectionChangeRequest(for: album) {
                    albumChangeRequest.addAssets([assetPlaceholder] as NSArray)
                }
            }) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: PhotoLibraryImportError.importFailed)
                }
            }
        }
    }

    nonisolated private static func requestAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    nonisolated private static func ensureAlbumExists(named albumName: String) async throws -> PHAssetCollection {
        if let existingAlbum = fetchAlbum(named: albumName) {
            return existingAlbum
        }

        let localIdentifier = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            var placeholder: PHObjectPlaceholder?

            PHPhotoLibrary.shared().performChanges({
                let createRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
                placeholder = createRequest.placeholderForCreatedAssetCollection
            }) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success, let localIdentifier = placeholder?.localIdentifier {
                    continuation.resume(returning: localIdentifier)
                } else {
                    continuation.resume(throwing: PhotoLibraryImportError.albumCreationFailed)
                }
            }
        }

        let result = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let createdAlbum = result.firstObject else {
            throw PhotoLibraryImportError.albumCreationFailed
        }
        return createdAlbum
    }

    nonisolated private static func fetchAlbum(named albumName: String) -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "localizedTitle == %@", albumName)
        let result = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options)
        return result.firstObject
    }
}

enum PhotoLibraryImportError: LocalizedError {
    case authorizationDenied
    case importFailed
    case albumCreationFailed

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "没有获得 Apple 相册写入权限"
        case .importFailed:
            return "Apple 相册未接受该媒体文件"
        case .albumCreationFailed:
            return "无法创建或定位相簿“PS5 Media”"
        }
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
