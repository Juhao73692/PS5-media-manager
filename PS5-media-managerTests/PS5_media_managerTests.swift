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

    @Test func scanDedupRemovesPrefixMatchedPngInSameFolder() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let screenshotsDir = tempRoot
            .appendingPathComponent("CREATE")
            .appendingPathComponent("Screenshots")
            .appendingPathComponent("GameA")
        try fileManager.createDirectory(at: screenshotsDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let firstURL = screenshotsDir.appendingPathComponent("20200101100101_png_.png")
        let secondURL = screenshotsDir.appendingPathComponent("20200101100101_png__1.png")
        let sharedData = Data(repeating: 0x7A, count: 4096)
        try sharedData.write(to: firstURL)
        try sharedData.write(to: secondURL)

        let library = PS5MediaScanner.scanLibrary(rootURL: tempRoot)
        let gameGroup = try #require(library.screenshots.first)
        #expect(gameGroup.items.count == 1)
        #expect(gameGroup.items.first?.name == "20200101100101_png_")
    }

    @Test func scanDedupKeepsSameFileAcrossDifferentFolders() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let gameA = tempRoot
            .appendingPathComponent("CREATE")
            .appendingPathComponent("Screenshots")
            .appendingPathComponent("GameA")
        let gameB = tempRoot
            .appendingPathComponent("CREATE")
            .appendingPathComponent("Screenshots")
            .appendingPathComponent("GameB")
        try fileManager.createDirectory(at: gameA, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: gameB, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let sharedData = Data(repeating: 0x41, count: 2048)
        try sharedData.write(to: gameA.appendingPathComponent("shot.png"))
        try sharedData.write(to: gameB.appendingPathComponent("shot.png"))

        let library = PS5MediaScanner.scanLibrary(rootURL: tempRoot)
        #expect(library.screenshots.count == 2)
        #expect(library.screenshots.allSatisfy { $0.items.count == 1 })
    }

    @Test func scanDedupUsesVideoEdgeHashForPrefixMatchedNames() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let videoDir = tempRoot
            .appendingPathComponent("CREATE")
            .appendingPathComponent("Video Clips")
            .appendingPathComponent("GameA")
        try fileManager.createDirectory(at: videoDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let chunk = 1024 * 1024
        let head = Data(repeating: 0x11, count: chunk)
        let tail = Data(repeating: 0x22, count: chunk)
        let middleA = Data(repeating: 0x33, count: 300_000)
        let middleB = Data(repeating: 0x44, count: 300_000)

        try (head + middleA + tail).write(to: videoDir.appendingPathComponent("clip.mp4"))
        try (head + middleB + tail).write(to: videoDir.appendingPathComponent("clip_1.mp4"))

        let library = PS5MediaScanner.scanLibrary(rootURL: tempRoot)
        let gameGroup = try #require(library.videoClips.first)
        #expect(gameGroup.items.count == 1)
        #expect(gameGroup.items.first?.name == "clip")
    }

    @Test func importDedupDetectsPrefixMatchedPngWithSameHash() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let firstURL = tempRoot.appendingPathComponent("20200101100101_png_.png")
        let secondURL = tempRoot.appendingPathComponent("20200101100101_png__1.png")
        let sharedData = Data(repeating: 0x5A, count: ImportedMediaRegistry.defaultChunkSize * 3)
        try sharedData.write(to: firstURL)
        try sharedData.write(to: secondURL)

        let firstHash = try PartialFileHasher.hashFirstAndLastChunk(of: firstURL)
        let secondHash = try PartialFileHasher.hashFirstAndLastChunk(of: secondURL)
        let registryURL = tempRoot.appendingPathComponent("imported-media-registry.json")
        let registry = ImportedMediaRegistry(storeURL: registryURL)

        try await registry.recordImportedFile(sourceURL: firstURL, hash: firstHash)
        let duplicate = await registry.findDuplicate(forSourceURL: secondURL, hash: secondHash)

        #expect(duplicate != nil)
        #expect(duplicate?.existingFileName == "20200101100101_png_")
        #expect(duplicate?.existingFileType == "png")
    }

    @Test func importDedupRequiresSameFileTypeAndSameHash() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let registryURL = tempRoot.appendingPathComponent("imported-media-registry.json")
        let registry = ImportedMediaRegistry(storeURL: registryURL)
        let recordedURL = tempRoot.appendingPathComponent("clip.mp4")
        try Data(repeating: 0x2A, count: 100).write(to: recordedURL)
        try await registry.recordImportedFile(sourceURL: recordedURL, hash: "hash-clip")

        let sameNameDifferentType = tempRoot.appendingPathComponent("clip.jpg")
        let sameNameDifferentHash = tempRoot.appendingPathComponent("clip_1.mp4")

        let duplicateByType = await registry.findDuplicate(
            forSourceURL: sameNameDifferentType,
            hash: "hash-clip"
        )
        let duplicateByHash = await registry.findDuplicate(
            forSourceURL: sameNameDifferentHash,
            hash: "hash-other"
        )

        #expect(duplicateByType == nil)
        #expect(duplicateByHash == nil)
    }

}
