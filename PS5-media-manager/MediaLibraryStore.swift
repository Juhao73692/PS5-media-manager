//
//  MediaLibraryStore.swift
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
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class MediaLibraryStore: ObservableObject {
    @Published var isScanning = false
    @Published var statusMessage = "未选择PS5文件夹"
    @Published var selectedFolderURL: URL? = nil
    @Published var library: PS5MediaScanner.PS5MediaLibrary? = nil
    @Published var mediaTree: [MediaTreeNode] = []
    @Published var selectedNodeID: UUID? = nil
    @Published var selectedMediaItemIDs: Set<UUID> = []

    var selectedItem: MediaItem? {
        guard let selectedNodeID else {
            return nil
        }
        return nodeLookup[selectedNodeID]?.item
    }

    var selectedMediaItems: [MediaItem] {
        selectedMediaItemIDs.compactMap { itemLookup[$0] }
    }

    private var nodeLookup: [UUID: MediaTreeNode] = [:]
    private var itemLookup: [UUID: MediaItem] = [:]
    private var nodeDescendantItemIDs: [UUID: Set<UUID>] = [:]

    func selectPS5Folder() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.folder]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        if panel.runModal() == .OK, let folderURL = panel.url {
            guard DirectoryWriteAuthorization.isWritableDirectory(folderURL) else {
                statusMessage = "所选文件夹不可写，无法同步文件时间或清理重复文件"
                return
            }
            selectedFolderURL = folderURL
            scanLibrary(at: folderURL)
        } else {
            statusMessage = "未选择PS5文件夹"
        }
    }

    func scanLibrary(at folderURL: URL) {
        isScanning = true
        statusMessage = "正在扫描 \(folderURL.lastPathComponent)…"
        Task.detached(priority: .userInitiated) {
            let isSecurityScoped = folderURL.startAccessingSecurityScopedResource()
            defer {
                if isSecurityScoped {
                    folderURL.stopAccessingSecurityScopedResource()
                }
            }

            let timestampResult = FileTimestampSynchronizer.synchronizeRecursively(in: folderURL)
            let scannedLibrary = PS5MediaScanner.scanLibrary(rootURL: folderURL)
            let screenshotCount = scannedLibrary.screenshots.reduce(0) { $0 + $1.items.count }
            let videoCount = scannedLibrary.videoClips.reduce(0) { $0 + $1.items.count }
            let tree = MediaTreeBuilder.build(from: scannedLibrary)
            await MainActor.run {
                self.library = scannedLibrary
                self.mediaTree = tree
                self.nodeLookup = MediaTreeBuilder.buildLookup(from: tree)
                self.itemLookup = MediaTreeBuilder.buildItemLookup(from: tree)
                self.nodeDescendantItemIDs = MediaTreeBuilder.buildDescendantItemIDs(from: tree)
                self.selectedMediaItemIDs = self.selectedMediaItemIDs.intersection(Set(self.itemLookup.keys))
//                self.statusMessage = "截图 \(screenshotCount) 张，视频 \(videoCount) 个，已更新 \(timestampResult.updatedCount) 个文件时间，跳过 \(timestampResult.skippedUnchangedCount) 个，失败 \(timestampResult.failedCount) 个"
                self.statusMessage = ""
                self.isScanning = false
            }
        }
    }

    func selectionState(for nodeID: UUID) -> NodeSelectionState {
        guard let itemIDs = nodeDescendantItemIDs[nodeID], !itemIDs.isEmpty else {
            return .none
        }

        let selectedCount = itemIDs.intersection(selectedMediaItemIDs).count
        if selectedCount == 0 {
            return .none
        }
        if selectedCount == itemIDs.count {
            return .full
        }
        return .partial
    }

    func toggleSelection(for nodeID: UUID) {
        guard let itemIDs = nodeDescendantItemIDs[nodeID], !itemIDs.isEmpty else {
            return
        }

        if itemIDs.isSubset(of: selectedMediaItemIDs) {
            selectedMediaItemIDs.subtract(itemIDs)
        } else {
            selectedMediaItemIDs.formUnion(itemIDs)
        }
    }
}

enum NodeSelectionState {
    case none
    case partial
    case full
}

struct MediaTreeNode: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let item: MediaItem?
    let children: [MediaTreeNode]?

    nonisolated init(title: String, item: MediaItem? = nil, children: [MediaTreeNode]? = nil) {
        self.id = UUID()
        self.title = title
        self.item = item
        self.children = children
    }

    static func == (lhs: MediaTreeNode, rhs: MediaTreeNode) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum MediaTreeBuilder {
    nonisolated static func build(from library: PS5MediaScanner.PS5MediaLibrary) -> [MediaTreeNode] {
        let screenshotNodes = library.screenshots.map { group in
            MediaTreeNode(
                title: group.title,
                children: group.items.map { item in
                    MediaTreeNode(
                        title: "\(item.name) · \(item.typeLabel)",
                        item: item
                    )
                }
            )
        }

        let videoNodes = library.videoClips.map { group in
            MediaTreeNode(
                title: group.title,
                children: group.items.map { item in
                    MediaTreeNode(
                        title: "\(item.name) · \(item.typeLabel)",
                        item: item
                    )
                }
            )
        }

        return [
            MediaTreeNode(title: "Screenshots", children: screenshotNodes),
            MediaTreeNode(title: "Video Clips", children: videoNodes)
        ]
    }

    nonisolated static func buildLookup(from nodes: [MediaTreeNode]) -> [UUID: MediaTreeNode] {
        var lookup: [UUID: MediaTreeNode] = [:]
        for node in nodes {
            lookup[node.id] = node
            if let children = node.children {
                let childLookup = buildLookup(from: children)
                for (key, value) in childLookup {
                    lookup[key] = value
                }
            }
        }
        return lookup
    }

    nonisolated static func buildItemLookup(from nodes: [MediaTreeNode]) -> [UUID: MediaItem] {
        var lookup: [UUID: MediaItem] = [:]
        for node in nodes {
            if let item = node.item {
                lookup[item.id] = item
            }
            if let children = node.children {
                let childLookup = buildItemLookup(from: children)
                for (key, value) in childLookup {
                    lookup[key] = value
                }
            }
        }
        return lookup
    }

    nonisolated static func buildDescendantItemIDs(from nodes: [MediaTreeNode]) -> [UUID: Set<UUID>] {
        var lookup: [UUID: Set<UUID>] = [:]
        for node in nodes {
            _ = collectDescendantItemIDs(for: node, into: &lookup)
        }
        return lookup
    }

    nonisolated private static func collectDescendantItemIDs(
        for node: MediaTreeNode,
        into lookup: inout [UUID: Set<UUID>]
    ) -> Set<UUID> {
        var descendants: Set<UUID> = []
        if let item = node.item {
            descendants.insert(item.id)
        }
        if let children = node.children {
            for child in children {
                descendants.formUnion(collectDescendantItemIDs(for: child, into: &lookup))
            }
        }

        lookup[node.id] = descendants
        return descendants
    }
}
