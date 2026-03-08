import SwiftUI

struct TranslationPopoverView: View {
    @EnvironmentObject private var appState: AppState

    private var captureButtonTitle: String {
        appState.isLoading && appState.lastTriggerSource != "manual" ? "翻译中..." : "取词翻译"
    }

    private var manualButtonTitle: String {
        appState.isLoading && appState.lastTriggerSource == "manual" ? "翻译中..." : "翻译输入内容"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Flash Translate")
                        .font(.headline)
                    Text("支持划词取词，也支持手动修改后直接翻译")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(captureButtonTitle) {
                    appState.captureAndTranslateSelection(triggerSource: "button")
                }
                .disabled(appState.isLoading)
            }

            if let errorMessage = appState.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            GroupBox("原文") {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $appState.originalText)
                        .font(.body)
                        .frame(minHeight: 110)

                    HStack {
                        Spacer()

                        Button(manualButtonTitle) {
                            appState.translateManually()
                        }
                        .disabled(appState.isLoading || appState.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            GroupBox("翻译") {
                ScrollView {
                    Text(appState.translatedText.isEmpty ? "这里会显示翻译结果" : appState.translatedText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
                .frame(minHeight: 110)
            }

            HStack {
                Text(appState.lastTriggerSource.isEmpty ? "等待触发" : "触发来源：\(appState.lastTriggerSource)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                SettingsLink {
                    Text("打开设置")
                }
                .disabled(appState.isLoading)

                Button("复制结果") {
                    appState.copyTranslation()
                }
                .disabled(appState.translatedText.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}
