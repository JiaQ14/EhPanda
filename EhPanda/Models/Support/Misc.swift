//
//  Misc.swift
//  EhPanda
//

import CasePaths
import Foundation
import SwiftyBeaver

typealias Logger = SwiftyBeaver
typealias FavoritesSortOrder = EhSetting.FavoritesSortOrder

protocol DateFormattable {
    var originalDate: Date { get }
}
extension DateFormattable {
    var formattedDateString: String {
        originalDate.formatted(
            Date.FormatStyle(
                date: .numeric,
                time: .shortened,
                locale: .autoupdatingCurrent,
                calendar: .autoupdatingCurrent,
                timeZone: .autoupdatingCurrent
            )
        )
    }
}

struct PageNumber: Equatable {
    var current = 0
    var maximum = 0
    var lastItemTimestamp: String?
    var isNextButtonEnabled = false

    var isSinglePage: Bool {
        current == 0 && maximum == 0
    }
    func hasNextPage(isNumericBased: Bool = false) -> Bool {
        isNumericBased ? current < maximum : isNextButtonEnabled
    }
    mutating func resetPages() {
        self = Self()
    }
}

struct QuickSearchWord: Codable, Equatable, Identifiable {
    static var empty: Self { .init(name: "", content: "") }

    var id: UUID = .init()
    var name: String
    var content: String
}

@dynamicMemberLookup @CasePathable
enum LoadingState: Equatable, Hashable {
    case idle
    case loading
    case failed(AppError)
}
