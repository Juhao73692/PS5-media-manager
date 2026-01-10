//
//  ContentView.swift
//  PS5-media-manager
//
//  Created by 赵亦涵 on 2026/1/10.
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
