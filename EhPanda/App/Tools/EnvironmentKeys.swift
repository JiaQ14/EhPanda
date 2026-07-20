//
//  EnvironmentKeys.swift
//  EhPanda
//

import SwiftUI

struct InSheetKey: EnvironmentKey {
    static let defaultValue = false
}

private struct StandaloneGalleryWindowKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var inSheet: Bool {
        get { self[InSheetKey.self] }
        set { self[InSheetKey.self] = newValue }
    }

    var isStandaloneGalleryWindow: Bool {
        get { self[StandaloneGalleryWindowKey.self] }
        set { self[StandaloneGalleryWindowKey.self] = newValue }
    }
}
