//
//  FileTimestampSynchronizer.swift
//  PS5-media-manager
//
//  Created by 赵亦涵 on 2026/3/22.
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

enum FileTimestampSynchronizer {
    struct SynchronizationResult: Sendable {
        var updatedCount = 0
        var skippedUnchangedCount = 0
        var failedCount = 0

        nonisolated init(
            updatedCount: Int = 0,
            skippedUnchangedCount: Int = 0,
            failedCount: Int = 0
        ) {
            self.updatedCount = updatedCount
            self.skippedUnchangedCount = skippedUnchangedCount
            self.failedCount = failedCount
        }
    }

    nonisolated private static let timestampRegex = try! NSRegularExpression(pattern: "(\\d{14})")

    nonisolated static func synchronizeRecursively(in rootURL: URL) -> SynchronizationResult {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return SynchronizationResult()
        }

        var result = SynchronizationResult()
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory != true else { continue }
            switch synchronizeFileDates(for: fileURL) {
            case .updated:
                result.updatedCount += 1
            case .skippedAlreadyMatched:
                result.skippedUnchangedCount += 1
            case .failed:
                result.failedCount += 1
            case .skippedNoTimestamp:
                break
            }
        }
        return result
    }

    enum SynchronizationOutcome: Sendable {
        case updated
        case skippedAlreadyMatched
        case failed
        case skippedNoTimestamp
    }

    nonisolated static func synchronizeFileDates(for fileURL: URL) -> SynchronizationOutcome {
        guard let timestampDate = extractTimestampDate(from: fileURL.lastPathComponent) else {
            return .skippedNoTimestamp
        }

        let fileManager = FileManager.default
        let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
        let modificationDate = attributes?[.modificationDate] as? Date
        let creationDate = attributes?[.creationDate] as? Date

        if datesMatch(modificationDate, timestampDate) && datesMatch(creationDate, timestampDate) {
            return .skippedAlreadyMatched
        }

        var updated = false

        if !datesMatch(modificationDate, timestampDate) {
            do {
                try fileManager.setAttributes([.modificationDate: timestampDate], ofItemAtPath: fileURL.path)
                updated = true
            } catch {
                NSLog("Failed to update modification date for %@: %@", fileURL.path, error.localizedDescription)
            }
        }

        if !datesMatch(creationDate, timestampDate) {
            do {
                try fileManager.setAttributes([.creationDate: timestampDate], ofItemAtPath: fileURL.path)
                updated = true
            } catch {
                NSLog("Failed to update creation date for %@: %@", fileURL.path, error.localizedDescription)
            }
        }

        return updated ? .updated : .failed
    }

    nonisolated static func extractTimestampDate(from fileName: String) -> Date? {
        let range = NSRange(fileName.startIndex..<fileName.endIndex, in: fileName)
        guard let match = timestampRegex.firstMatch(in: fileName, options: [], range: range),
              match.numberOfRanges > 1,
              let timestampRange = Range(match.range(at: 1), in: fileName) else {
            return nil
        }

        let timestamp = String(fileName[timestampRange])
        guard timestamp.count == 14 else {
            return nil
        }

        let components = DateComponents(
            year: Int(timestamp.prefix(4)),
            month: Int(timestamp.dropFirst(4).prefix(2)),
            day: Int(timestamp.dropFirst(6).prefix(2)),
            hour: Int(timestamp.dropFirst(8).prefix(2)),
            minute: Int(timestamp.dropFirst(10).prefix(2)),
            second: Int(timestamp.dropFirst(12).prefix(2))
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar.date(from: components)
    }

    nonisolated private static func datesMatch(_ lhs: Date?, _ rhs: Date) -> Bool {
        guard let lhs else {
            return false
        }

        return abs(lhs.timeIntervalSince(rhs)) < 1
    }
}
