import Foundation

@main
@MainActor
struct EmojiKeywordTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if !condition {
            print("FAIL: \(label)")
            failures += 1
        }
    }

    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("emoji-keyword-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let frequent = FrequentEmojiStore(
            fileURL: directory.appendingPathComponent("frequency.json"))
        let index = EmojiIndex()
        await index.load("A|party popper|ac|0|celebration\nB|birthday cake|fd|0|cake")
        guard let party = EmojiKeyword(glyph: "A", value: "festivity") else {
            print("FAIL: valid keyword rejected")
            exit(1)
        }
        expect(party.value == "festivity", "keyword is normalized")
        expect(EmojiKeyword(glyph: "A", value: "") == nil, "empty keyword rejected")
        expect(EmojiKeyword(glyph: "A", value: "one,two") == nil, "comma keyword rejected")

        let results = index.search("fest", frequent: frequent, customKeywords: [party])
        expect(results.first?.glyph == "A", "custom keyword finds its glyph")
        expect(
            index.search("festivity cake", frequent: frequent, customKeywords: [party]).isEmpty,
            "every multiword term remains required")

        let keywordURL = directory.appendingPathComponent("keywords.json")
        let store = EmojiKeywordStore(fileURL: keywordURL)
        expect(store.add(glyph: "A", keyword: "celebration"), "store accepts a keyword")
        expect(!store.add(glyph: "A", keyword: " celebration "), "store deduplicates keywords")
        let expected = [EmojiKeyword(glyph: "A", value: "celebration")].compactMap { $0 }
        expect(store.records == expected, "store sorts records")
        let reloaded = EmojiKeywordStore(fileURL: keywordURL)
        expect(reloaded.records == store.records, "store round-trips its versioned archive")
        if let record = store.records.first {
            expect(store.remove(record), "store removes a keyword")
        } else {
            expect(false, "store has a keyword to remove")
        }

        if failures == 0 {
            print("emoji-keyword-test: all checks passed")
        } else {
            print("emoji-keyword-test: \(failures) failure(s)")
            exit(1)
        }
    }
}
