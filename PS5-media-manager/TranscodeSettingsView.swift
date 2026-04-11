//
//  TranscodeSettingsView.swift
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

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TranscodeSettingsView: View {
    @AppStorage(TranscodeSettings.bitratePresetUserDefaultsKey)
    private var bitratePresetRawValue = TranscodeSettings.defaultBitratePreset.rawValue

    @State private var cacheDirectoryPath = ""
    @State private var isUsingCustomCacheDirectory = false
    @State private var errorAlertMessage: String? = nil

    var body: some View {
        Form {
            Section("转码 Cache 位置") {

                VStack(alignment: .leading, spacing: 6) {
//                    Text("当前目录")
//                        .font(.subheadline)
//                        .foregroundStyle(.secondary)

                    Text(cacheDirectoryPath)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                HStack(spacing: 10) {
                    Button("选择目录") {
                        chooseCacheDirectory()
                    }

                    Button("恢复默认") {
                        TranscodeSettings.clearCustomCacheRootDirectoryURL()
                        reloadCacheDirectoryPath()
                    }
                    .disabled(!isUsingCustomCacheDirectory)
                }
            }

            Section("转码码率倍率") {
                Picker("码率", selection: $bitratePresetRawValue) {
                    ForEach(TranscodeBitratePreset.allCases) { preset in
                        Text(displayName(for: preset))
                            .tag(preset.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 520)
        .onAppear {
            reloadCacheDirectoryPath()
            sanitizeBitrateSelectionIfNeeded()
        }
        .alert(
            "设置失败",
            isPresented: errorAlertIsPresented,
            presenting: errorAlertMessage
        ) { _ in
            Button("确定", role: .cancel) {
                errorAlertMessage = nil
            }
        } message: { message in
            Text(message)
        }
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(
            get: { errorAlertMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorAlertMessage = nil
                }
            }
        )
    }

    private func chooseCacheDirectory() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.folder]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "选择"

        guard panel.runModal() == .OK, let directoryURL = panel.url else {
            return
        }

        do {
            try TranscodeSettings.setCustomCacheRootDirectoryURL(directoryURL)
            reloadCacheDirectoryPath()
        } catch {
            errorAlertMessage = error.localizedDescription
        }
    }

    private func reloadCacheDirectoryPath() {
        do {
            let isCustom = TranscodeSettings.isUsingCustomCacheDirectory
            let directoryURL = try TranscodeSettings.currentCacheRootDirectoryURL()
            isUsingCustomCacheDirectory = isCustom
            cacheDirectoryPath = isCustom ? directoryURL.path : "默认"
        } catch {
            cacheDirectoryPath = "读取失败：\(error.localizedDescription)"
            isUsingCustomCacheDirectory = false
        }
    }

    private func sanitizeBitrateSelectionIfNeeded() {
        if TranscodeBitratePreset(rawValue: bitratePresetRawValue) == nil {
            bitratePresetRawValue = TranscodeSettings.defaultBitratePreset.rawValue
        }
    }

    private func displayName(for preset: TranscodeBitratePreset) -> String {
        switch preset {
        case .low:
            return "低（1.0x）"
        case .medium:
            return "中（1.8x）"
        case .high:
            return "高（2.5x）"
        case .ultra:
            return "超高（3.4x）"
        }
    }
}
#Preview {
    TranscodeSettingsView()
}

