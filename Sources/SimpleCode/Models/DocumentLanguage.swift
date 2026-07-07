import Foundation

typealias DocumentLanguage = LanguageID

extension LanguageID {
    static func detect(from url: URL, content: String = "") -> LanguageID {
        LanguageDetector.detect(url: url, content: content)
    }
}
