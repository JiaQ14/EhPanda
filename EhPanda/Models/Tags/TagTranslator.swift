//
//  TagTranslator.swift
//  EhPanda
//

import Foundation

struct TagTranslator: Codable, Equatable {
    struct RenderRevision: Equatable, Hashable {
        let languageCode: String?
        let hasCustomTranslations: Bool
        let updatedDate: Date
        let translationsCount: Int
    }

    var language: TranslatableLanguage?
    var hasCustomTranslations = false
    var updatedDate: Date = .distantPast
    var translations = [String: TagTranslation]()

    var renderRevision: RenderRevision {
        .init(
            languageCode: language?.languageCode,
            hasCustomTranslations: hasCustomTranslations,
            updatedDate: updatedDate,
            translationsCount: translations.count
        )
    }

    func lookup(word: String, returnOriginal: Bool) -> (String, TagTranslation?) {
        guard !returnOriginal else { return (word, nil) }
        let (lhs, rhs) = word.stringsBesideColon

        var key = rhs
        if let lhs = lhs {
            key = lhs + rhs
        }
        guard let translation = translations[key] else { return (word, nil) }

        var result = translation.displayValue
        if let lhs = lhs {
            result = [lhs, ":", result].joined()
        }
        return (result, translation)
    }
}

extension TagTranslator: CustomStringConvertible {
    var description: String {
        let params = String(describing: [
            "language": language as Any,
            "updatedDate": updatedDate,
            "translationsCount": translations.count,
            "hasCustomTranslations": hasCustomTranslations
        ])
        return "TagTranslator(\(params))"
    }
}
