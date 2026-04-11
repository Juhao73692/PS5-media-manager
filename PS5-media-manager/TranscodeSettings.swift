//
//  TranscodeSettings.swift
//  PS5-media-manager
//
//  Created by 赵亦涵 on 2026/4/7.
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

enum TranscodeBitratePreset: String, CaseIterable, Identifiable {
    case low
    case medium
    case high
    case ultra

    nonisolated var id: String { rawValue }

    nonisolated var factor: Double {
        switch self {
        case .low:
            return 1.0
        case .medium:
            return 1.8
        case .high:
            return 2.5
        case .ultra:
            return 3.4
        }
    }
}

enum TranscodeSettings {
    nonisolated static let bitratePresetUserDefaultsKey = "transcode.bitratePreset"
    nonisolated static let cacheDirectoryBookmarkUserDefaultsKey = "transcode.cacheDirectoryBookmark"

    nonisolated static let defaultBitratePreset: TranscodeBitratePreset = .low

    nonisolated static var selectedBitratePreset: TranscodeBitratePreset {
        let rawValue = UserDefaults.standard.string(forKey: bitratePresetUserDefaultsKey) ?? defaultBitratePreset.rawValue
        return TranscodeBitratePreset(rawValue: rawValue) ?? defaultBitratePreset
    }

    nonisolated static var selectedBitrateFactor: Double {
        selectedBitratePreset.factor
    }

    nonisolated static var isUsingCustomCacheDirectory: Bool {
        UserDefaults.standard.data(forKey: cacheDirectoryBookmarkUserDefaultsKey) != nil
    }

    nonisolated static func currentCacheRootDirectoryURL() throws -> URL {
        if let customDirectory = try resolvedCustomCacheRootDirectoryURL() {
            return customDirectory
        }
        return try defaultCacheRootDirectoryURL()
    }

    nonisolated static func resolvedCustomCacheRootDirectoryURL() throws -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: cacheDirectoryBookmarkUserDefaultsKey) else {
            return nil
        }

        do {
            return try resolveBookmarkData(bookmarkData)
        } catch {
            UserDefaults.standard.removeObject(forKey: cacheDirectoryBookmarkUserDefaultsKey)
            return nil
        }
    }

    nonisolated static func setCustomCacheRootDirectoryURL(_ directoryURL: URL) throws {
        let bookmarkData = try directoryURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmarkData, forKey: cacheDirectoryBookmarkUserDefaultsKey)
    }

    nonisolated static func clearCustomCacheRootDirectoryURL() {
        UserDefaults.standard.removeObject(forKey: cacheDirectoryBookmarkUserDefaultsKey)
    }

    nonisolated static func defaultCacheRootDirectoryURL() throws -> URL {
        let appSupportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appDirectoryName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackDirectoryName = Bundle.main.bundleIdentifier ?? "PS5-media-manager"
        let resolvedDirectoryName = {
            guard let appDirectoryName, !appDirectoryName.isEmpty else {
                return fallbackDirectoryName
            }
            return appDirectoryName
        }()

        return appSupportDirectory
            .appendingPathComponent(resolvedDirectoryName, isDirectory: true)
            .appendingPathComponent("cache", isDirectory: true)
    }

    nonisolated private static func resolveBookmarkData(_ bookmarkData: Data) throws -> URL {
        var isStale = false
        let resolvedURL = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        if isStale {
            try setCustomCacheRootDirectoryURL(resolvedURL)
        }

        return resolvedURL
    }
}
