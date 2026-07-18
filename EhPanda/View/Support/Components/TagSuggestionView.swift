//
//  TagSuggestionView.swift
//  EhPanda
//

import SwiftUI
import Kingfisher

enum TagSuggestionStyle {
    case list
    case bubbles
}

struct TagSuggestionView: View {
    @Binding private var keyword: String
    private let translations: [String: TagTranslation]
    private let showsImages: Bool
    private let isEnabled: Bool
    private let style: TagSuggestionStyle
    private let maximumCount: Int?

    @StateObject private var translationHandler = TagTranslationHandler()

    init(
        keyword: Binding<String>,
        translations: [String: TagTranslation],
        showsImages: Bool,
        isEnabled: Bool,
        style: TagSuggestionStyle = .list,
        maximumCount: Int? = nil
    ) {
        _keyword = keyword
        self.translations = translations
        self.showsImages = showsImages
        self.isEnabled = isEnabled
        self.style = style
        self.maximumCount = maximumCount
    }

    var body: some View {
        if isEnabled {
            Group {
                switch style {
                case .list:
                    listSuggestions
                case .bubbles:
                    bubbleSuggestions
                }
            }
            .onAppear(perform: analyze)
            .onChange(of: keyword) {
                analyze()
            }
        }
    }

    @ViewBuilder private var listSuggestions: some View {
        if DeviceUtil.isPhone {
            Text(L10n.Localizable.Searchable.Title.matchesCount(translationHandler.suggestions.count))
                .foregroundColor(.secondary)
                .font(.subheadline)
        }

        let suggestions = translationHandler.suggestions
        ForEach(suggestions.prefix(min(suggestions.count, 10))) { suggestion in
            SuggestionCell(
                suggestion: suggestion,
                showsImages: showsImages,
                action: { translationHandler.autoComplete(suggestion: suggestion, keyword: &keyword) }
            )
        }
    }

    private var bubbleSuggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(translationHandler.suggestions) { suggestion in
                BubbleSuggestionCell(
                    suggestion: suggestion,
                    showsImages: showsImages,
                    action: {
                        translationHandler.autoComplete(
                            suggestion: suggestion,
                            keyword: &keyword
                        )
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func analyze() {
        translationHandler.analyze(
            text: &keyword,
            translations: translations,
            maximumCount: maximumCount
        )
    }
}

// MARK: SuggestionCell
private struct SuggestionCell: View {
    private let suggestion: TagSuggestion
    private let showsImages: Bool
    private let action: () -> Void

    init(suggestion: TagSuggestion, showsImages: Bool, action: @escaping () -> Void) {
        self.suggestion = suggestion
        self.showsImages = showsImages
        self.action = action
    }

    private var displayValue: String {
        let value = suggestion.displayValue
        return showsImages ? value : value.emojisRipped
    }

    var body: some View {
        if DeviceUtil.isPhone {
            HStack(spacing: 20) {
                Image(systemSymbol: .magnifyingglass)

                VStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        Text(displayValue.localizedKey)

                        if let imageURL = suggestion.tag.valueImageURL, showsImages {
                            Image(systemSymbol: .photo)
                                .opacity(0)
                                .overlay(
                                    KFImage(imageURL)
                                        .resizable()
                                        .scaledToFit()
                                )
                        }
                    }
                    .font(.callout)
                    .lineLimit(1)

                    Text(suggestion.displayKey.localizedKey)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .allowsHitTesting(false)

                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
        } else {
            VStack(alignment: .leading) {
                Text(displayValue.localizedKey)
                Text(suggestion.displayKey.localizedKey)
            }
            .searchCompletion(suggestion.tag.searchKeyword)
        }
    }
}

// MARK: BubbleSuggestionCell
private struct BubbleSuggestionCell: View {
    private let suggestion: TagSuggestion
    private let showsImages: Bool
    private let action: () -> Void

    init(
        suggestion: TagSuggestion,
        showsImages: Bool,
        action: @escaping () -> Void
    ) {
        self.suggestion = suggestion
        self.showsImages = showsImages
        self.action = action
    }

    private var displayValue: String {
        let value = suggestion.tag.displayValue
        return showsImages ? value : value.emojisRipped
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "tag.fill")
                    .font(.callout)
                    .foregroundStyle(.tint)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: suggestion.tag.searchKeyword)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)

                    HStack(spacing: 3) {
                        Text(verbatim: displayValue)
                            .lineLimit(1)

                        if let imageURL = suggestion.tag.valueImageURL, showsImages {
                            KFImage(imageURL)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: 420, alignment: .leading)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel(
            Text(verbatim: suggestion.tag.searchKeyword + ", " + displayValue)
        )
    }
}

// MARK: TagTranslationHandler
final class TagTranslationHandler: ObservableObject {
    @Published var suggestions = [TagSuggestion]()

    func analyze(
        text: inout String,
        translations: [String: TagTranslation],
        maximumCount: Int? = nil
    ) {
        let keyword = TagSuggestionEngine.normalizedText(text)
        text = keyword
        suggestions = TagSuggestionEngine.suggestions(
            for: keyword,
            translations: translations,
            maximumCount: maximumCount
        )
    }

    func autoComplete(suggestion: TagSuggestion, keyword: inout String) {
        keyword = TagSuggestionEngine.completing(
            keyword,
            with: suggestion
        )
    }
}

// MARK: TagSuggestionEngine
enum TagSuggestionEngine {
    static func normalizedText(_ text: String) -> String {
        text.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "：", with: ":")
    }

    static func suggestions(
        for text: String,
        translations: [String: TagTranslation],
        maximumCount: Int? = nil
    ) -> [TagSuggestion] {
        guard maximumCount.map({ $0 > 0 }) ?? true else { return [] }
        guard let regex = Defaults.Regex.tagSuggestion else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let keywords: [String] = regex.matches(in: text, range: range)
            .compactMap {
                if let range = Range($0.range, in: text) {
                    return .init(text[range])
                } else {
                    return nil
                }
            }
        guard !keywords.isEmpty else { return [] }

        var result = [TagSuggestion]()
        var existingWords = Set<String>()
        let lastCompletedTagIndex = keywords.lastIndex(where: { ["\"", "$"].contains($0.last) })
        let startIndex = lastCompletedTagIndex.map { $0 + 1 } ?? 0
        guard startIndex < keywords.count else { return [] }

        for index in startIndex..<keywords.count {
            let keywordList = keywords[index...]
            if !keywordList.isEmpty {
                let keyword = keywordList.joined(separator: " ")
                rankedSuggestions(
                    translations: translations,
                    keyword: keyword,
                    maximumCount: maximumCount
                ).forEach {
                    if !existingWords.contains($0.tag.searchKeyword) {
                        existingWords.insert($0.tag.searchKeyword)
                        result.append($0)
                    }
                }
            }
            if let maximumCount, result.count >= maximumCount {
                return Array(result.prefix(maximumCount))
            }
        }
        return result
    }

    static func completing(
        _ keyword: String,
        with suggestion: TagSuggestion
    ) -> String {
        guard keyword.hasSuffix(suggestion.originalKeyword) else { return keyword }
        return String(keyword.dropLast(suggestion.originalKeyword.count))
            + suggestion.tag.searchKeyword
            + " "
    }

    private static func rankedSuggestions(
        translations: [String: TagTranslation],
        keyword: String,
        maximumCount: Int?
    ) -> [TagSuggestion] {
        let originalKeyword = keyword
        var keyword = keyword
        var namespace: String?
        let namespaceAbbreviations = TagNamespace.abbreviations

        if let colon = keyword.firstIndex(of: ":") {
            let key = String(keyword[keyword.startIndex..<colon])
            if let index = namespaceAbbreviations.firstIndex(where: {
                $0.caseInsensitiveEqualsTo(key) || $1.caseInsensitiveEqualsTo(key)
            }) {
                namespace = namespaceAbbreviations[index].key
                keyword = .init(keyword[keyword.index(colon, offsetBy: 1)..<keyword.endIndex])
            }
        }

        let candidates = translations.values.lazy.filter {
            namespace == nil || $0.namespace.rawValue == namespace
        }
        if namespace != nil && keyword.isEmpty {
            let suggestions = candidates
                .map {
                    .init(
                        tag: $0, weight: 0, keyRange: nil, valueRange: nil,
                        originalKeyword: originalKeyword, matchesNamespace: true
                    )
                }
                .sorted(by: areInIncreasingRank)
            return maximumCount.map { Array(suggestions.prefix($0)) } ?? suggestions
        } else {
            var suggestions = [TagSuggestion]()
            for translation in candidates {
                let suggestion = translation.getSuggestion(
                    keyword: keyword,
                    originalKeyword: originalKeyword,
                    matchesNamespace: namespace != nil
                )
                guard suggestion.weight > 0 else { continue }
                suggestions.append(suggestion)
                if let maximumCount {
                    suggestions.sort(by: areInIncreasingRank)
                    if suggestions.count > maximumCount {
                        suggestions.removeLast()
                    }
                }
            }
            if maximumCount == nil {
                suggestions.sort(by: areInIncreasingRank)
            }
            return suggestions
        }
    }

    private static func areInIncreasingRank(
        _ lhs: TagSuggestion,
        _ rhs: TagSuggestion
    ) -> Bool {
        if lhs.weight != rhs.weight {
            return lhs.weight > rhs.weight
        }
        return lhs.tag.searchKeyword.localizedStandardCompare(
            rhs.tag.searchKeyword
        ) == .orderedAscending
    }
}
