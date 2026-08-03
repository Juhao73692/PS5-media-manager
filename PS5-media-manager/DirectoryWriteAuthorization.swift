//
//  DirectoryWriteAuthorization.swift
//  PS5-media-manager
//

import AppKit
import Foundation
import UniformTypeIdentifiers

enum DirectoryWriteAuthorization {
    /// Returns a directory backed by a valid, writable security-scoped bookmark.
    /// If the previous grant is missing or no longer usable, asks the user to
    /// select a directory and creates a fresh persistent grant.
    @MainActor
    static func movieOutputDirectory() throws -> URL? {
        if let directoryURL = try TranscodeSettings.resolvedMovieOutputDirectoryURL(),
           isWritableDirectory(directoryURL) {
            return directoryURL
        }

        TranscodeSettings.clearMovieOutputDirectoryURL()

        let panel = NSOpenPanel()
        panel.title = "选择转码输出文件夹"
        panel.message = "PS5 Media Manager 仅能写入你选择的文件夹。请选择用于保存 MOV 文件的文件夹。"
        panel.prompt = "授权并选择"
        panel.allowedContentTypes = [.folder]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true

        if let moviesDirectory = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first {
            panel.directoryURL = moviesDirectory
        }

        guard panel.runModal() == .OK, let directoryURL = panel.url else {
            return nil
        }

        try TranscodeSettings.setMovieOutputDirectoryURL(directoryURL)
        guard let resolvedURL = try TranscodeSettings.resolvedMovieOutputDirectoryURL(),
              isWritableDirectory(resolvedURL) else {
            TranscodeSettings.clearMovieOutputDirectoryURL()
            throw DirectoryWriteAuthorizationError.directoryIsNotWritable
        }
        return resolvedURL
    }

    /// The default cache lives in the app container and needs no user grant.
    /// A custom cache must retain a valid writable bookmark; otherwise ask the
    /// user to renew the grant before any transcode starts.
    @MainActor
    static func validateCustomCacheDirectoryIfNeeded() throws -> Bool {
        guard TranscodeSettings.isUsingCustomCacheDirectory else {
            return true
        }

        if let directoryURL = try TranscodeSettings.resolvedCustomCacheRootDirectoryURL(),
           isWritableDirectory(directoryURL) {
            return true
        }

        TranscodeSettings.clearCustomCacheRootDirectoryURL()

        let panel = NSOpenPanel()
        panel.title = "重新授权转码 Cache 文件夹"
        panel.message = "之前选择的 Cache 文件夹已无法写入。请重新选择文件夹以继续转码。"
        panel.prompt = "重新授权"
        panel.allowedContentTypes = [.folder]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let directoryURL = panel.url else {
            return false
        }

        try TranscodeSettings.setCustomCacheRootDirectoryURL(directoryURL)
        guard let resolvedURL = try TranscodeSettings.resolvedCustomCacheRootDirectoryURL(),
              isWritableDirectory(resolvedURL) else {
            TranscodeSettings.clearCustomCacheRootDirectoryURL()
            throw DirectoryWriteAuthorizationError.directoryIsNotWritable
        }
        return true
    }

    nonisolated static func isWritableDirectory(_ directoryURL: URL) -> Bool {
        let didStartAccess = directoryURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                directoryURL.stopAccessingSecurityScopedResource()
            }
        }

        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && FileManager.default.isWritableFile(atPath: directoryURL.path)
    }
}

enum DirectoryWriteAuthorizationError: LocalizedError {
    case directoryIsNotWritable

    var errorDescription: String? {
        switch self {
        case .directoryIsNotWritable:
            return "所选文件夹不可写，请选择其他文件夹"
        }
    }
}
