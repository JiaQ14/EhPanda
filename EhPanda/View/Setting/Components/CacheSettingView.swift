//
//  CacheSettingView.swift
//  EhPanda
//

import SwiftUI

struct CacheSettingView: View {
    @Binding var imageQuality: CacheImageQuality
    @Binding var concurrentDownloads: Int
    @Binding var allowsCellularAccess: Bool
    @Binding var resumesAutomatically: Bool
    let isRefreshingLibrary: Bool
    let refreshLibraryAction: () -> Void

    var body: some View {
        Form {
            Section {
                Picker(
                    L10n.Localizable.CacheSettingView.Title.imageQuality,
                    selection: $imageQuality
                ) {
                    ForEach(CacheImageQuality.allCases) {
                        Text($0.value).tag($0)
                    }
                }
                .pickerStyle(.menu)

                Stepper(value: $concurrentDownloads, in: 1...6) {
                    LabeledContent(
                        L10n.Localizable.CacheSettingView.Title.concurrentDownloads,
                        value: "\(concurrentDownloads)"
                    )
                }

                Toggle(
                    L10n.Localizable.CacheSettingView.Title.allowsCellularAccess,
                    isOn: $allowsCellularAccess
                )

                Toggle(
                    L10n.Localizable.CacheSettingView.Title.resumesAutomatically,
                    isOn: $resumesAutomatically
                )
            } header: {
                Text(L10n.Localizable.CacheSettingView.Section.Title.download)
            } footer: {
                Text(L10n.Localizable.CacheSettingView.Section.Footer.download)
            }

            Section {
                LabeledContent(
                    L10n.Localizable.CacheSettingView.Title.location,
                    value: "Downloads"
                )
                Button(action: refreshLibraryAction) {
                    HStack {
                        Label(
                            L10n.Localizable.CacheSettingView.Title.refreshLibrary,
                            systemImage: "arrow.clockwise"
                        )
                        Spacer()
                        if isRefreshingLibrary {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(isRefreshingLibrary)
            } header: {
                Text(L10n.Localizable.CacheSettingView.Section.Title.storage)
            } footer: {
                Text(L10n.Localizable.CacheSettingView.Section.Footer.storage)
            }
        }
        .settingRootNavigationTitle(L10n.Localizable.CacheSettingView.Title.cache)
    }
}

extension CacheImageQuality {
    var value: String {
        switch self {
        case .standard:
            return L10n.Localizable.CacheSettingView.Value.standard
        case .original:
            return L10n.Localizable.CacheSettingView.Value.original
        }
    }
}
