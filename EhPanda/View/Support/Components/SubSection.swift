//
//  SubSection.swift
//  EhPanda
//

import SwiftUI

struct SubSection<Content: View>: View {
    private let title: String
    private let showAll: Bool
    private let tint: Color?
    private let isLoading: Bool?
    private let reloadAction: (() -> Void)?
    private let showAllAction: () -> Void
    private let content: Content

    init(
        title: String, showAll: Bool = true,
        tint: Color? = nil, isLoading: Bool? = nil,
        reloadAction: (() -> Void)? = nil,
        showAllAction: @escaping () -> Void = {},
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.showAll = showAll
        self.tint = tint
        self.isLoading = isLoading
        self.reloadAction = reloadAction
        self.showAllAction = showAllAction
        self.content = content()
    }

    @ViewBuilder private var titleControl: some View {
        if let reloadAction {
            Button {
                reloadAction()
                HapticsUtil.generateFeedback(style: .soft)
            } label: {
                titleLabel
            }
            .buttonStyle(.plain)
        } else {
            titleLabel
        }
    }

    private var titleLabel: some View {
        HStack(spacing: 8) {
            Text(title)
            if isLoading == true {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .font(.title3.bold())
        .foregroundStyle(.primary)
    }

    private var showAllControl: some View {
        Button(action: showAllAction) {
            HStack(spacing: 4) {
                Text(L10n.Localizable.SubSection.Button.showAll)
                Image(systemSymbol: .chevronRight)
                    .imageScale(.small)
            }
            .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint ?? .secondary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    titleControl
                        .fixedSize(horizontal: true, vertical: false)

                    Spacer(minLength: 8)

                    if showAll {
                        showAllControl
                            .fixedSize()
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    titleControl

                    if showAll {
                        HStack {
                            Spacer(minLength: 0)
                            showAllControl
                        }
                    }
                }
            }
            .padding(.horizontal)

            content
        }
        .animation(.default, value: isLoading)
    }
}

struct SubSection_Previews: PreviewProvider {
    static var previews: some View {
        SubSection(title: "Title") {
            Text("Content")
        }
    }
}
