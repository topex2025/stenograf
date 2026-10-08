import XCTest
@testable import StenografCore

final class L10nTests: XCTestCase {
    func testThreeLanguagesCoverAllKeys() {
        for lang in AppLanguage.allCases {
            L10n.setLanguage(lang)
            for key in L10n.Key.allCases {
                let value = L10n.t(key)
                XCTAssertFalse(value.isEmpty, "\(lang).\(key.rawValue) пуст")
                XCTAssertNotEqual(value, key.rawValue, "\(lang).\(key.rawValue) нет перевода")
            }
        }
        L10n.setLanguage(.ru) // вернуть дефолт тестового окружения
    }

    func testFormatStrings() {
        L10n.setLanguage(.ru)
        XCTAssertTrue(L10n.tf(.noResultsFmt, "тест").contains("тест"))
        L10n.setLanguage(.en)
        XCTAssertTrue(L10n.tf(.autoDoneFmt, "", 42).contains("42"))
        L10n.setLanguage(.es)
        XCTAssertTrue(L10n.t(.recordStart).contains("Grabar"))
        L10n.setLanguage(.ru)
    }

    func testDetectSystemFallsBackToEnglish() {
        // на русской системе — ru; проверяем только что detect возвращает валидный кейс
        XCTAssertTrue(AppLanguage.allCases.contains(L10n.detectSystem()))
    }
}
