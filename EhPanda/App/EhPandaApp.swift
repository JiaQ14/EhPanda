//
//  EhPandaApp.swift
//  EhPanda
//

import SwiftUI
import UIKit
import ComposableArchitecture

struct GallerySceneValue: Codable, Hashable {
    let gid: String
}

enum GallerySceneActivity {
    static let activityType = "com.zjq9714.ehpanda.gallery"
    static let targetContentIdentifier = "gallery"
    static let didDetachSceneNotification = Notification.Name(
        "GallerySceneActivity.didDetachScene"
    )
    private static let galleryIDKey = "gid"
    private static let detachmentTokenKey = "detachmentToken"

    static func make(
        gid: String,
        title: String? = nil,
        detachmentToken: UUID? = nil
    ) -> NSUserActivity {
        let activity = NSUserActivity(activityType: activityType)
        activity.title = title
        activity.targetContentIdentifier = targetContentIdentifier
        var userInfo = [galleryIDKey: gid]
        var requiredUserInfoKeys = [galleryIDKey]
        if let detachmentToken {
            userInfo[detachmentTokenKey] = detachmentToken.uuidString
            requiredUserInfoKeys.append(detachmentTokenKey)
        }
        activity.userInfo = userInfo
        activity.requiredUserInfoKeys = Set(requiredUserInfoKeys)
        activity.isEligibleForHandoff = true
        return activity
    }

    static func sceneValue(from activity: NSUserActivity) -> GallerySceneValue? {
        guard activity.activityType == activityType,
              let gid = activity.userInfo?[galleryIDKey] as? String,
              !gid.isEmpty
        else { return nil }
        return GallerySceneValue(gid: gid)
    }

    static func detachmentToken(from activity: NSUserActivity) -> UUID? {
        guard let value = activity.userInfo?[detachmentTokenKey] as? String else {
            return nil
        }
        return UUID(uuidString: value)
    }

    @MainActor
    static func openWindow(gid: String, title: String? = nil) {
        let options = UIWindowScene.ActivationRequestOptions()
        options.placement = UIWindowSceneProminentPlacement()
        let request = UISceneSessionActivationRequest(
            role: .windowApplication,
            userActivity: make(gid: gid, title: title),
            options: options
        )
        UIApplication.shared.activateSceneSession(for: request)
    }

    static func itemProvider(
        gid: String,
        url: URL?,
        detachmentToken: UUID? = nil
    ) -> NSItemProvider {
        let provider: NSItemProvider
        if let url {
            provider = NSItemProvider(object: url as NSURL)
        } else if detachmentToken != nil,
                  let image = UIImage(systemName: "rectangle.portrait.on.rectangle.portrait") {
            provider = NSItemProvider(object: image)
        } else {
            provider = NSItemProvider()
        }
        provider.registerObject(
            make(gid: gid, detachmentToken: detachmentToken),
            visibility: .all
        )
        return provider
    }
}

@Reducer
private struct GallerySceneReducer {
    private enum CancelID {
        case loadEnvironment
        case systemSearchIndex
    }

    @ObservableState
    struct State: Equatable {
        var appLockState = AppLockReducer.State()
        var detailState = DetailReducer.State()
        var setting = Setting()
        var tagTranslator = TagTranslator()
        var user = User()
        var hasLoadedEnvironment = false
        var isLoadingEnvironment = false
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case loadEnvironment
        case environmentLoaded(AppEnv)
        case onScenePhaseChange(ScenePhase)
        case syncSystemSearchIndex
        case teardown

        case appLock(AppLockReducer.Action)
        case detail(DetailReducer.Action)
    }

    @Dependency(\.databaseClient) private var databaseClient
    @Dependency(\.dfClient) private var dfClient
    @Dependency(\.uiApplicationClient) private var uiApplicationClient
    @Dependency(\.userDefaultsClient) private var userDefaultsClient

    var body: some Reducer<State, Action> {
        BindingReducer()
            .onChange(of: \.setting) { _, newValue in
                Reduce { _, _ in
                    .merge(
                        .run { _ in
                            await databaseClient.updateSetting(newValue)
                        },
                        .run { _ in
                            AppIntentPreferences.update(using: newValue)
                        }
                    )
                }
            }

        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .loadEnvironment:
                guard !state.hasLoadedEnvironment,
                      !state.isLoadingEnvironment
                else { return .none }
                state.isLoadingEnvironment = true
                return .run { send in
                    let appEnv = await databaseClient.fetchAppEnv()
                    await send(.environmentLoaded(appEnv))
                }
                .cancellable(id: CancelID.loadEnvironment, cancelInFlight: true)

            case .environmentLoaded(let appEnv):
                state.isLoadingEnvironment = false
                state.setting = appEnv.setting
                state.tagTranslator = appEnv.tagTranslator
                state.user = appEnv.user
                if let value: String = userDefaultsClient.getValue(.galleryHost),
                   let galleryHost = GalleryHost(rawValue: value) {
                    state.setting.galleryHost = galleryHost
                }
                state.hasLoadedEnvironment = true

                let setting = state.setting
                var effects: [Effect<Action>] = [
                    .run { _ in
                        await uiApplicationClient.setUserInterfaceStyle(
                            setting.preferredColorScheme.userInterfaceStyle
                        )
                    },
                    .run { _ in
                        dfClient.setActive(setting.bypassesSNIFiltering)
                        AppIntentPreferences.update(using: setting)
                    }
                ]
                let threshold = setting.autoLockPolicy.rawValue
                if threshold >= 0 {
                    state.appLockState.becameInactiveDate = .distantPast
                    effects.append(
                        .send(.appLock(.onBecomeActive(
                            threshold,
                            setting.backgroundBlurRadius
                        )))
                    )
                }
                return .merge(effects)

            case .onScenePhaseChange(let scenePhase):
                guard state.hasLoadedEnvironment else { return .none }
                switch scenePhase {
                case .active:
                    return .send(.appLock(.onBecomeActive(
                        state.setting.autoLockPolicy.rawValue,
                        state.setting.backgroundBlurRadius
                    )))
                case .inactive:
                    return .send(.appLock(.onBecomeInactive(
                        state.setting.backgroundBlurRadius
                    )))
                default:
                    return .none
                }

            case .syncSystemSearchIndex:
                let setting = state.setting
                return .run { _ in
                    try await Task.sleep(for: .milliseconds(500))
                    await SystemSearchIndexService.shared.synchronize(using: setting)
                }
                .cancellable(
                    id: CancelID.systemSearchIndex,
                    cancelInFlight: true
                )

            case .teardown:
                return .merge(
                    .send(.detail(.teardown)),
                    .cancel(id: CancelID.loadEnvironment),
                    .cancel(id: CancelID.systemSearchIndex)
                )

            case .detail(.saveGalleryHistory):
                return .send(.syncSystemSearchIndex)

            case .detail, .appLock:
                return .none
            }
        }

        Scope(state: \.appLockState, action: \.appLock, child: AppLockReducer.init)
        Scope(state: \.detailState, action: \.detail, child: DetailReducer.init)
    }
}

@main struct EhPandaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            AppSceneRoot(bootstrapStore: appDelegate.store)
        }
        .commands { EhPandaCommands() }
        WindowGroup("Gallery", id: "gallery", for: GallerySceneValue.self) { value in
            GallerySceneEntry(
                bootstrapStore: appDelegate.store,
                sceneValue: value
            )
        }
        .handlesExternalEvents(matching: [GallerySceneActivity.targetContentIdentifier])
    }
}

private struct GallerySceneEntry: View {
    let bootstrapStore: StoreOf<AppDelegateReducer>
    @Binding var sceneValue: GallerySceneValue?
    @State private var activitySceneValue: GallerySceneValue?
    @SceneStorage("galleryScene.gid") private var storedGalleryID = ""

    private var resolvedSceneValue: GallerySceneValue? {
        if let activitySceneValue {
            return activitySceneValue
        }
        if let sceneValue {
            return sceneValue
        }
        guard !storedGalleryID.isEmpty else { return nil }
        return GallerySceneValue(gid: storedGalleryID)
    }

    var body: some View {
        Group {
            if let resolvedSceneValue {
                GallerySceneRoot(
                    bootstrapStore: bootstrapStore,
                    sceneValue: resolvedSceneValue
                )
                .id(resolvedSceneValue)
            } else {
                LoadingView()
            }
        }
        .onChange(of: sceneValue, initial: true) { _, value in
            if let value {
                activitySceneValue = value
            }
            remember(value)
        }
        .onContinueUserActivity(GallerySceneActivity.activityType) { activity in
            let value = GallerySceneActivity.sceneValue(from: activity)
            activitySceneValue = value
            remember(value)
            if let token = GallerySceneActivity.detachmentToken(from: activity) {
                NotificationCenter.default.post(
                    name: GallerySceneActivity.didDetachSceneNotification,
                    object: token
                )
            }
        }
    }

    private func remember(_ value: GallerySceneValue?) {
        guard let value else { return }
        storedGalleryID = value.gid
    }
}

private struct AppSceneRoot: View {
    let bootstrapStore: StoreOf<AppDelegateReducer>

    @State private var store: StoreOf<AppReducer>
    @State private var didPrepareScene = false

    init(bootstrapStore: StoreOf<AppDelegateReducer>) {
        self.bootstrapStore = bootstrapStore
        _store = State(initialValue: Store(initialState: .init()) { AppReducer() })
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                let databaseState = bootstrapStore.migrationState.databaseState

                if databaseState == .idle {
                    TabBarView(store: store)
                        .onAppear(perform: prepareScene)
                        .accentColor(.primary)
                }
                MigrationView(
                    store: bootstrapStore.scope(
                        state: \.migrationState,
                        action: \.migration
                    )
                )
                .opacity(databaseState != .idle ? 1 : 0)
                .animation(.linear(duration: 0.5), value: databaseState)
            }
            .environment(\.windowSize, proxy.size)
            .background(WindowTouchCaptureView().frame(width: 0, height: 0))
            .navigationViewStyle(.stack)
        }
    }

    private func prepareScene() {
        guard !didPrepareScene else { return }
        didPrepareScene = true
        store.send(.onDatabaseReady(nil))
    }
}

private struct GallerySceneRoot: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.scenePhase) private var scenePhase

    let bootstrapStore: StoreOf<AppDelegateReducer>
    let sceneValue: GallerySceneValue

    @State private var store: StoreOf<GallerySceneReducer>
    @State private var didPrepareScene = false
    @State private var sceneSession: UISceneSession?

    init(
        bootstrapStore: StoreOf<AppDelegateReducer>,
        sceneValue: GallerySceneValue
    ) {
        self.bootstrapStore = bootstrapStore
        self.sceneValue = sceneValue
        _store = State(
            initialValue: Store(initialState: .init()) {
                GallerySceneReducer()
            }
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                let databaseState = bootstrapStore.migrationState.databaseState

                if databaseState == .idle {
                    Group {
                        if store.hasLoadedEnvironment {
                            GallerySceneContent(
                                store: store,
                                sceneValue: sceneValue,
                                closeAction: closeWindow
                            )
                        } else {
                            LoadingView()
                        }
                    }
                    .onAppear(perform: prepareScene)
                }
                MigrationView(
                    store: bootstrapStore.scope(
                        state: \.migrationState,
                        action: \.migration
                    )
                )
                .opacity(databaseState != .idle ? 1 : 0)
                .animation(.linear(duration: 0.5), value: databaseState)
            }
            .environment(\.windowSize, proxy.size)
            .background(WindowTouchCaptureView().frame(width: 0, height: 0))
            .navigationViewStyle(.stack)
        }
        .onChange(of: scenePhase) { _, newValue in
            store.send(.onScenePhaseChange(newValue))
        }
        .onDisappear {
            store.send(.teardown)
        }
        .background(
            SceneSessionCaptureView { session in
                if sceneSession !== session {
                    sceneSession = session
                }
            }
            .frame(width: 0, height: 0)
        )
    }

    private func prepareScene() {
        guard !didPrepareScene else { return }
        didPrepareScene = true
        store.send(.loadEnvironment)
    }

    private func closeWindow() {
        store.send(.teardown)
        if let sceneSession {
            UIApplication.shared.requestSceneSessionDestruction(
                sceneSession,
                options: nil
            )
        } else {
            dismissWindow(id: "gallery", value: sceneValue)
        }
    }
}

private struct SceneSessionCaptureView: UIViewRepresentable {
    let resolve: (UISceneSession) -> Void

    func makeUIView(context: Context) -> ResolverView {
        ResolverView(resolve: resolve)
    }

    func updateUIView(_ uiView: ResolverView, context: Context) {
        uiView.resolve = resolve
        uiView.resolveSession()
    }

    final class ResolverView: UIView {
        var resolve: (UISceneSession) -> Void

        init(resolve: @escaping (UISceneSession) -> Void) {
            self.resolve = resolve
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            resolveSession()
        }

        func resolveSession() {
            guard let session = window?.windowScene?.session else { return }
            DispatchQueue.main.async { [resolve] in
                resolve(session)
            }
        }
    }
}

private struct GallerySceneContent: View {
    @Bindable var store: StoreOf<GallerySceneReducer>
    let sceneValue: GallerySceneValue
    let closeAction: () -> Void

    var body: some View {
        ZStack {
            NavigationStack {
                DetailView(
                    store: store.scope(state: \.detailState, action: \.detail),
                    gid: sceneValue.gid,
                    user: store.user,
                    setting: $store.setting,
                    blurRadius: store.appLockState.blurRadius,
                    tagTranslator: store.tagTranslator
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: closeAction) {
                            Image(systemSymbol: .xmark)
                        }
                    }
                }
            }
            .accentColor(store.setting.accentColor)
            .autoBlur(radius: store.appLockState.blurRadius)

            Button {
                store.send(.appLock(.authorize))
            } label: {
                Image(systemSymbol: .lockFill)
            }
            .font(.system(size: 80))
            .opacity(store.appLockState.isAppLocked ? 1 : 0)
        }
        .environment(
            \.galleryContextMenuConfiguration,
            .standard(
                user: store.user,
                setting: store.setting,
                blurRadius: store.appLockState.blurRadius,
                tagTranslator: store.tagTranslator
            )
        )
        .environment(\.isStandaloneGalleryWindow, true)
    }
}

// MARK: TouchHandler
final class TouchHandler: NSObject, UIGestureRecognizerDelegate {
    static let shared = TouchHandler()
    var currentPoint: CGPoint?

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        currentPoint = touch.location(in: touch.window)
        return false
    }
}

private struct WindowTouchCaptureView: UIViewRepresentable {
    func makeUIView(context: Context) -> WindowTouchCaptureUIView {
        WindowTouchCaptureUIView()
    }

    func updateUIView(_ uiView: WindowTouchCaptureUIView, context: Context) {}
}

private final class WindowTouchCaptureUIView: UIView {
    private weak var installedWindow: UIWindow?
    private var tapGesture: UITapGestureRecognizer?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard installedWindow !== window else { return }
        if let tapGesture {
            installedWindow?.removeGestureRecognizer(tapGesture)
        }
        installedWindow = window
        guard let window else {
            tapGesture = nil
            return
        }
        let tapGesture = UITapGestureRecognizer(target: nil, action: nil)
        tapGesture.delegate = TouchHandler.shared
        window.addGestureRecognizer(tapGesture)
        self.tapGesture = tapGesture
    }
}

private struct EhPandaCommands: Commands {
    @FocusedValue(\.ehPandaCommandActions) private var actions

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(AppNavigationItem.search.title) {
                actions?.navigate(.search)
            }
            .keyboardShortcut("f", modifiers: .command)

            Button(L10n.Localizable.refresh) {
                actions?.refresh()
            }
            .keyboardShortcut("r", modifiers: .command)
        }

        CommandMenu(L10n.Localizable.navigate) {
            navigationButton(.home, key: "1")
            navigationButton(.search, key: "2")
            navigationButton(DeviceUtil.isPad ? .favorites : .more, key: "3")
            Divider()
            navigationButton(.setting, key: "0")
        }
    }

    private func navigationButton(_ item: AppNavigationItem, key: KeyEquivalent) -> some View {
        Button(item.title) {
            actions?.navigate(item)
        }
        .keyboardShortcut(key, modifiers: .command)
    }
}
