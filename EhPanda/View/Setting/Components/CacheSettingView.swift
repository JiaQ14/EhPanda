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
            } header: {
                Text(L10n.Localizable.CacheSettingView.Section.Title.storage)
            } footer: {
                Text(L10n.Localizable.CacheSettingView.Section.Footer.storage)
            }
        }
        .navigationTitle(L10n.Localizable.CacheSettingView.Title.cache)
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
