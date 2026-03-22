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
    @Test func extractTimestampDateFromFileName() throws {
        let date = try #require(
            FileTimestampSynchronizer.extractTimestampDate(from: "IMG_20200101123456.jpg")
        )
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: .current, from: date)

        #expect(components.year == 2020)
        #expect(components.month == 1)
        #expect(components.day == 1)
        #expect(components.hour == 12)
        #expect(components.minute == 34)
        #expect(components.second == 56)
    }

    @Test func synchronizeRecursivelyUpdatesMatchingFiles() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nestedDir = tempRoot
            .appendingPathComponent("CREATE")
            .appendingPathComponent("Screenshots")
            .appendingPathComponent("GameA")
        try fileManager.createDirectory(at: nestedDir, withIntermediateDirectories: true)

        let matchedURL = nestedDir.appendingPathComponent("shot_20200101123456.jpg")
        let unmatchedURL = nestedDir.appendingPathComponent("shot_without_timestamp.jpg")
        try Data([0x01, 0x02, 0x03]).write(to: matchedURL)
        try Data([0x04, 0x05, 0x06]).write(to: unmatchedURL)

        defer { try? fileManager.removeItem(at: tempRoot) }

        let result = FileTimestampSynchronizer.synchronizeRecursively(in: tempRoot)
        let matchedAttributes = try fileManager.attributesOfItem(atPath: matchedURL.path)
        let unmatchedAttributes = try fileManager.attributesOfItem(atPath: unmatchedURL.path)
        let matchedModificationDate = try #require(matchedAttributes[.modificationDate] as? Date)
        let unmatchedModificationDate = try #require(unmatchedAttributes[.modificationDate] as? Date)
        let expectedDate = try #require(
            FileTimestampSynchronizer.extractTimestampDate(from: matchedURL.lastPathComponent)
        )

        #expect(result.updatedCount == 1)
        #expect(result.skippedUnchangedCount == 0)
        #expect(result.failedCount == 0)
        #expect(abs(matchedModificationDate.timeIntervalSince(expectedDate)) < 1)
        #expect(abs(unmatchedModificationDate.timeIntervalSince(expectedDate)) > 1)
    }

    @Test func synchronizeFileDatesSkipsWhenDatesAlreadyMatch() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let fileURL = tempRoot.appendingPathComponent("shot_20200101123456.jpg")
        try Data([0x01, 0x02, 0x03]).write(to: fileURL)
        let expectedDate = try #require(
            FileTimestampSynchronizer.extractTimestampDate(from: fileURL.lastPathComponent)
        )

        try fileManager.setAttributes(
            [
                .creationDate: expectedDate,
                .modificationDate: expectedDate
            ],
            ofItemAtPath: fileURL.path
        )

        let outcome = FileTimestampSynchronizer.synchronizeFileDates(for: fileURL)

        switch outcome {
        case .skippedAlreadyMatched:
            #expect(true)
        default:
            Issue.record("Expected skippedAlreadyMatched but got \(String(describing: outcome))")
        }
    }

    @Test func partialFileHasherUsesLeadingBytes() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let firstURL = tempRoot.appendingPathComponent("first.bin")
        let secondURL = tempRoot.appendingPathComponent("second.bin")
        let leadingBytes = Data(repeating: 0x7A, count: ImportedMediaRegistry.defaultChunkSize)

        try (leadingBytes + Data(repeating: 0x01, count: 128)).write(to: firstURL)
        try (leadingBytes + Data(repeating: 0x02, count: 128)).write(to: secondURL)

        let firstHash = try PartialFileHasher.hashFirstChunk(of: firstURL)
        let secondHash = try PartialFileHasher.hashFirstChunk(of: secondURL)

        #expect(firstHash == secondHash)
    }

    @Test func importedMediaRegistryPersistsAndFindsDuplicates() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let registryURL = tempRoot.appendingPathComponent("imported-media-registry.json")
        let registry = ImportedMediaRegistry(storeURL: registryURL)

        try await registry.recordImportedFile(
            hash: "abc",
            sourceFilePath: "/tmp/original.mp4",
            isVideo: true,
            chunkSize: ImportedMediaRegistry.defaultChunkSize
        )

        let reloadedRegistry = ImportedMediaRegistry(storeURL: registryURL)
        let duplicate = await reloadedRegistry.findDuplicate(
            forHash: "abc",
            chunkSize: ImportedMediaRegistry.defaultChunkSize
        )

        #expect(duplicate?.existingFilePath == "/tmp/original.mp4")
        #expect(duplicate?.chunkSize == ImportedMediaRegistry.defaultChunkSize)
    }

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
