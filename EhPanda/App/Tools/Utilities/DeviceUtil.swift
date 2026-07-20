//
//  DeviceUtil.swift
//  EhPanda
//

import SwiftUI
import Foundation

private struct WindowSizeKey: EnvironmentKey {
    static let defaultValue = CGSize.zero
}

extension EnvironmentValues {
    var windowSize: CGSize {
        get { self[WindowSizeKey.self] }
        set { self[WindowSizeKey.self] = newValue }
    }
}

struct DeviceUtil {
    static var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    static var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    static var isPadWidth: Bool {
        windowW >= 744
    }

    static var isSEWidth: Bool {
        windowW <= 320
    }

    static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .filter({ $0.activationState == .foregroundActive })
            .compactMap({ $0 as? UIWindowScene }).last?
            .windows.filter({ $0.isKeyWindow }).last
    }
    static var anyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).last?
            .windows.last
    }

    static var isLandscape: Bool {
        [.landscapeLeft, .landscapeRight]
            .contains(keyWindow?.windowScene?.effectiveGeometry.interfaceOrientation)
    }

    static var isPortrait: Bool {
        [.portrait, .portraitUpsideDown]
            .contains(keyWindow?.windowScene?.effectiveGeometry.interfaceOrientation)
    }

    static func isWindowed(_ windowSize: CGSize) -> Bool {
        guard isPad,
              let window = keyWindow,
              let screenSize = window.windowScene?.screen.bounds.size,
              windowSize.width > 0,
              windowSize.height > 0
        else { return false }

        let windowArea = windowSize.width * windowSize.height
        let screenArea = screenSize.width * screenSize.height
        return windowArea < screenArea * 0.98
    }

    static var windowW: CGFloat {
        min(absWindowW, absWindowH)
    }

    static var windowH: CGFloat {
        max(absWindowW, absWindowH)
    }

    static var screenW: CGFloat {
        min(absScreenW, absScreenH)
    }

    static var screenH: CGFloat {
        max(absScreenW, absScreenH)
    }

    static var absWindowW: CGFloat {
        keyWindow?.frame.size.width ?? absScreenW
    }

    static var absWindowH: CGFloat {
        keyWindow?.frame.size.height ?? absScreenH
    }

    static var absScreenW: CGFloat {
        anyWindow?.windowScene?.screen.bounds.size.width ?? 0
    }

    static var absScreenH: CGFloat {
        anyWindow?.windowScene?.screen.bounds.size.height ?? 0
    }
}
