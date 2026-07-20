//
//  SettingView.swift
//  EhPanda
//

import SwiftUI
import SFSafeSymbols
import ComposableArchitecture

struct SettingView: View {
    @Bindable private var store: StoreOf<SettingReducer>
    private let blurRadius: Double
    private let embedsInNavigationStack: Bool

    init(
        store: StoreOf<SettingReducer>,
        blurRadius: Double,
        embedsInNavigationStack: Bool = true
    ) {
        self.store = store
        self.blurRadius = blurRadius
        self.embedsInNavigationStack = embedsInNavigationStack
    }

    // MARK: SettingView
    @ViewBuilder var body: some View {
        if embedsInNavigationStack {
            NavigationStack {
                navigationContent
            }
        } else {
            navigationContent
        }
    }

    private var navigationContent: some View {
        List {
            Section {
                ForEach(primaryRoutes) { route in
                    settingRow(for: route)
                }
            }
            Section {
                settingRow(for: .laboratory)
            }
            Section {
                settingRow(for: .about)
            }
        }
        .listStyle(.insetGrouped)
        .modifier(SettingPageLayoutModifier())
        .navigationTitle(L10n.Localizable.SettingView.Title.setting)
        .navigationDestination(item: $store.route.sending(\.setNavigation)) { route in
            settingDestination(for: route)
                .modifier(SettingDestinationPageModifier(title: route.value))
        }
    }

    private var primaryRoutes: [SettingReducer.Route] {
        [.account, .general, .appearance, .cache, .reading]
    }

    private func settingRow(for route: SettingReducer.Route) -> some View {
        SettingRow(rowType: route) {
            store.send(.setNavigation($0))
        }
    }
}

// MARK: Navigation
private extension SettingView {
    @ViewBuilder
    func settingDestination(for route: SettingReducer.Route) -> some View {
        switch route {
        case .account:
            AccountSettingView(
                store: store.scope(state: \.accountSettingState, action: \.account),
                galleryHost: $store.setting.galleryHost,
                showsNewDawnGreeting: $store.setting.showsNewDawnGreeting,
                bypassesSNIFiltering: store.setting.bypassesSNIFiltering,
                blurRadius: blurRadius
            )
            .tint(store.setting.accentColor)

        case .general:
            GeneralSettingView(
                store: store.scope(state: \.generalSettingState, action: \.general),
                tagTranslatorLoadingState: store.tagTranslatorLoadingState,
                tagTranslatorEmpty: store.tagTranslator.translations.isEmpty,
                tagTranslatorHasCustomTranslations: store.tagTranslator.hasCustomTranslations,
                enablesTagsExtension: $store.setting.enablesTagsExtension,
                translatesTags: $store.setting.translatesTags,
                showsTagsSearchSuggestion: $store.setting.showsTagsSearchSuggestion,
                showsImagesInTags: $store.setting.showsImagesInTags,
                redirectsLinksToSelectedHost: $store.setting.redirectsLinksToSelectedHost,
                detectsLinksFromClipboard: $store.setting.detectsLinksFromClipboard,
                backgroundBlurRadius: $store.setting.backgroundBlurRadius,
                autoLockPolicy: $store.setting.autoLockPolicy,
                enablesSystemContentSearch: $store.setting.enablesSystemContentSearch,
                displaysCoversInSystemSearch: $store.setting.displaysCoversInSystemSearch,
                enablesVisualSearch: $store.setting.enablesVisualSearch
            )
            .tint(store.setting.accentColor)

        case .appearance:
            AppearanceSettingView(
                store: store.scope(state: \.appearanceSettingState, action: \.appearance),
                preferredColorScheme: $store.setting.preferredColorScheme,
                accentColor: $store.setting.accentColor,
                appIconType: $store.setting.appIconType,
                listDisplayMode: $store.setting.listDisplayMode,
                showsTagsInList: $store.setting.showsTagsInList,
                listTagsNumberMaximum: $store.setting.listTagsNumberMaximum,
                displaysJapaneseTitle: $store.setting.displaysJapaneseTitle
            )
            .tint(store.setting.accentColor)

        case .reading:
            ReadingSettingView(
                readingDirection: $store.setting.readingDirection,
                prefetchLimit: $store.setting.prefetchLimit,
                enablesLandscape: $store.setting.enablesLandscape,
                avoidsStatusBarInVerticalMode: $store.setting.avoidsStatusBarInVerticalMode,
                contentDividerHeight: $store.setting.contentDividerHeight,
                maximumScaleFactor: $store.setting.maximumScaleFactor,
                doubleTapScaleFactor: $store.setting.doubleTapScaleFactor
            )
            .tint(store.setting.accentColor)

        case .cache:
            CacheSettingView(
                imageQuality: $store.setting.cacheImageQuality,
                concurrentDownloads: $store.setting.cacheConcurrentDownloads,
                allowsCellularAccess: $store.setting.cacheAllowsCellularAccess,
                resumesAutomatically: $store.setting.cacheResumesAutomatically,
                isRefreshingLibrary: store.isRefreshingCacheLibrary,
                refreshLibraryAction: {
                    store.send(.refreshCacheLibrary)
                }
            )
            .tint(store.setting.accentColor)

        case .laboratory:
            LaboratorySettingView(
                bypassesSNIFiltering: $store.setting.bypassesSNIFiltering
            )
            .tint(store.setting.accentColor)

        case .about:
            AboutView().tint(store.setting.accentColor)
        }
    }
}

// MARK: SettingRow
private struct SettingRow: View {
    private let rowType: SettingReducer.Route
    private let tapAction: (SettingReducer.Route) -> Void

    init(rowType: SettingReducer.Route, tapAction: @escaping (SettingReducer.Route) -> Void) {
        self.rowType = rowType
        self.tapAction = tapAction
    }

    var body: some View {
        Button {
            tapAction(rowType)
        } label: {
            HStack(spacing: 12) {
                Image(systemSymbol: rowType.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(rowType.tintColor, in: .rect(cornerRadius: 7))
                Text(rowType.value)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemSymbol: .chevronForward)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct SettingPageLayoutModifier: ViewModifier {
    func body(content: Content) -> some View {
        if DeviceUtil.isPad {
            content
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color(uiColor: .systemGroupedBackground))
        } else {
            content
        }
    }
}

private struct SettingDestinationPageModifier: ViewModifier {
    let title: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if DeviceUtil.isPad {
            content
                .modifier(SettingPageLayoutModifier())
                .safeAreaInset(edge: .top, spacing: 0) {
                    HStack {
                        Text(title)
                            .font(.largeTitle.bold())
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                    .background(Color(uiColor: .systemGroupedBackground))
                }
        } else {
            content
        }
    }
}

extension View {
    func settingRootNavigationTitle(_ title: String) -> some View {
        modifier(SettingRootNavigationTitleModifier(title: title))
    }
}

private struct SettingRootNavigationTitleModifier: ViewModifier {
    let title: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if DeviceUtil.isPad {
            content
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
        } else {
            content.navigationTitle(title)
        }
    }
}

// MARK: Definition
extension SettingReducer.Route {
    var value: String {
        switch self {
        case .account:
            return L10n.Localizable.Enum.SettingStateRoute.Value.account
        case .general:
            return L10n.Localizable.Enum.SettingStateRoute.Value.general
        case .appearance:
            return L10n.Localizable.Enum.SettingStateRoute.Value.appearance
        case .cache:
            return L10n.Localizable.Enum.SettingStateRoute.Value.cache
        case .reading:
            return L10n.Localizable.Enum.SettingStateRoute.Value.reading
        case .laboratory:
            return L10n.Localizable.Enum.SettingStateRoute.Value.laboratory
        case .about:
            return L10n.Localizable.Enum.SettingStateRoute.Value.about
        }
    }
    var symbol: SFSymbol {
        switch self {
        case .account:
            return .personFill
        case .general:
            return .switch2
        case .appearance:
            return .circleRighthalfFilled
        case .cache:
            return .squareAndArrowDown
        case .reading:
            return .newspaperFill
        case .laboratory:
            return .testtube2
        case .about:
            return .pCircleFill
        }
    }
    var tintColor: Color {
        switch self {
        case .account:
            return .blue
        case .general:
            return .gray
        case .appearance:
            return .purple
        case .cache:
            return .cyan
        case .reading:
            return .orange
        case .laboratory:
            return .green
        case .about:
            return .indigo
        }
    }
}

struct SettingView_Previews: PreviewProvider {
    static var previews: some View {
        SettingView(
            store: .init(initialState: .init(), reducer: SettingReducer.init),
            blurRadius: 0
        )
    }
}
