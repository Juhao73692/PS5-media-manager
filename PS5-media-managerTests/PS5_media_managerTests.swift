//
//  PS5_media_managerTests.swift
//  PS5-media-managerTests
//
//  Created by 赵亦涵 on 2026/1/10.
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

import Testing
@testable import PS5_media_manager

struct PS5_media_managerTests {

    @Test func scanLibraryRemovesDuplicateMedia() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let screenshotsDir = tempRoot
            .appendingPathComponent("CREATE")
            .appendingPathComponent("Screenshots")
            .appendingPathComponent("GameA")
        try fileManager.createDirectory(at: screenshotsDir, withIntermediateDirectories: true)

        let data = Data(repeating: 0xAB, count: 3000)
        let originalURL = screenshotsDir.appendingPathComponent("shot.jpg")
        let duplicateURL = screenshotsDir.appendingPathComponent("shot_1.jpg")
        try data.write(to: originalURL)
        try data.write(to: duplicateURL)

        defer { try? fileManager.removeItem(at: tempRoot) }

        let library = PS5MediaScanner.scanLibrary(rootURL: tempRoot)
        let gameGroup = try #require(library.screenshots.first)

        #expect(gameGroup.items.count == 1)
        #expect(gameGroup.items.first?.name == "shot")
    }

    @Test func scanLibraryHandlesManyVideosWithMixedDuplicates() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let videoDir = tempRoot
            .appendingPathComponent("CREATE")
            .appendingPathComponent("Video Clips")
            .appendingPathComponent("BulkGame")
        try fileManager.createDirectory(at: videoDir, withIntermediateDirectories: true)

        let baseNames = (1...10).map { String(format: "clip%02d", $0) }
        let trueDuplicateSet = Set(baseNames.prefix(7))
        var expectedKeptNames: [String] = []

        for name in baseNames {
            let originalURL = videoDir.appendingPathComponent("\(name).mp4")
            let duplicateURL = videoDir.appendingPathComponent("\(name)_1.mp4")
            let originalCover = videoDir.appendingPathComponent("\(name).jpg")
            let duplicateCover = videoDir.appendingPathComponent("\(name)_1.jpg")

            let baseByte = UInt8(name.hashValue & 0xFF)
            let originalData = Data(repeating: baseByte, count: 9000)
            try originalData.write(to: originalURL)
            try Data(repeating: baseByte ^ 0xFF, count: 200).write(to: originalCover)

            if trueDuplicateSet.contains(name) {
                try originalData.write(to: duplicateURL)
                try Data(repeating: baseByte ^ 0xFF, count: 200).write(to: duplicateCover)
                expectedKeptNames.append(name)
            } else {
                let differentData = Data(repeating: baseByte &+ 1, count: 9000)
                try differentData.write(to: duplicateURL)
                try Data(repeating: baseByte &+ 2, count: 200).write(to: duplicateCover)
                expectedKeptNames.append(contentsOf: [name, "\(name)_1"])
            }
        }

        defer { try? fileManager.removeItem(at: tempRoot) }

        let library = PS5MediaScanner.scanLibrary(rootURL: tempRoot)
        let gameGroup = try #require(library.videoClips.first)
        let returnedNames = Set(gameGroup.items.map { $0.name })

        #expect(returnedNames.count == expectedKeptNames.count)
        #expect(returnedNames == Set(expectedKeptNames))

        for name in baseNames {
            let originalURL = videoDir.appendingPathComponent("\(name).mp4")
            let duplicateURL = videoDir.appendingPathComponent("\(name)_1.mp4")
            let originalCover = videoDir.appendingPathComponent("\(name).jpg")
            let duplicateCover = videoDir.appendingPathComponent("\(name)_1.jpg")
            #expect(fileManager.fileExists(atPath: originalCover.path))
            if trueDuplicateSet.contains(name) {
                #expect(fileManager.fileExists(atPath: originalURL.path))
                #expect(!fileManager.fileExists(atPath: duplicateURL.path))
                #expect(!fileManager.fileExists(atPath: duplicateCover.path))
            } else {
                #expect(fileManager.fileExists(atPath: originalURL.path))
                #expect(fileManager.fileExists(atPath: duplicateURL.path))
                #expect(fileManager.fileExists(atPath: duplicateCover.path))
            }
        }
    }

}
