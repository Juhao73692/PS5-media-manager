//
//  ContentView.swift
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

import SwiftUI
internal import UniformTypeIdentifiers

struct ContentView: View {
    @State private var isProcessing = false
    @State private var message = "准备就绪"
    var body: some View {
        VStack(spacing: 20) {
            Text("PS5 Media Manager")
                .font(.title)
            
            Button("测试转码视频") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.movie, .video]
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    
                    if panel.runModal() == .OK, let url = panel.url {
                        let videoPath = url.path
                        let homeDir = FileManager.default.homeDirectoryForCurrentUser
                        let outputDir = homeDir.appendingPathComponent("Movies/PS5-media-manager/converted")
                        let outputPath = outputDir
                            .appendingPathComponent(url.deletingPathExtension().lastPathComponent)
                            .appendingPathExtension("mov")
                            .path
                        
                        startConvert(videoPath: videoPath, outputPath: outputPath)
                    }
            }
            .disabled(isProcessing)
            Text(message)
            
        }
        .padding()
    }
    func startConvert(videoPath: String, outputPath: String) {
        isProcessing = true
        message = "正在转码……"
        Task.detached(priority: .userInitiated) {
            FFmpegWrapper().transcodeToMOV(withInput: videoPath, andOutput: outputPath)
            await MainActor.run {
                message = "任务完成！"
                isProcessing = false
            }
        }
    }
}

#Preview {
    ContentView()
}
