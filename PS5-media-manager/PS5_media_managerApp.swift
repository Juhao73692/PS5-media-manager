//
//  PS5_media_managerApp.swift
//  PS5-media-manager
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

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct PS5_media_managerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var libraryStore = MediaLibraryStore()

    var body: some Scene {
        Window("PS5 Media Manager", id: "main") {
            ContentView()
                .environmentObject(libraryStore)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("选择PS5文件夹") {
                    libraryStore.selectPS5Folder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }
}
