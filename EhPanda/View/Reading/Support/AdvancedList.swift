//
//  AdvancedList.swift
//  EhPanda
//

import SwiftUI
import SwiftUIPager

struct AdvancedList<Element, ID, PageView>: View
where PageView: View, Element: Equatable, ID: Hashable {
    @State var performingChanges = false
    @State var scrollPositionID: Int?

    private let pagerModel: Page
    private let data: [Element]
    private let id: KeyPath<Element, ID>
    private let spacing: CGFloat
    private let topContentInset: CGFloat
    private let content: (Element) -> PageView

    init<Data: RandomAccessCollection>(
        page: Page, data: Data,
        id: KeyPath<Element, ID>, spacing: CGFloat, topContentInset: CGFloat,
        @ViewBuilder content: @escaping (Element) -> PageView
    ) where Data.Index == Int, Data.Element == Element {
        self.pagerModel = page
        self.data = .init(data)
        self.id = id
        self.spacing = spacing
        self.topContentInset = topContentInset
        self.content = content
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: spacing) {
                    ForEach(data, id: id) { index in
                        content(index)
                    }
                }
                .padding(.top, topContentInset)
                .scrollTargetLayout()
                .onAppear(perform: { tryScrollTo(id: pagerModel.index + 1, proxy: proxy) })
            }
            .scrollPosition(id: $scrollPositionID, anchor: .center)
            .onScrollPhaseChange { _, newValue in
                if newValue == .idle, let index = scrollPositionID {
                    performingChanges = true
                    pagerModel.update(.new(index: index - 1))
                    DispatchQueue.main.async {
                        performingChanges = false
                    }
                }
            }
            .onChange(of: pagerModel.index) { _, newValue in
                tryScrollTo(id: newValue + 1, proxy: proxy)
            }
        }
    }

    private func tryScrollTo(id: Int, proxy: ScrollViewProxy) {
        if !performingChanges {
            scrollPositionID = id
        }
    }
}
