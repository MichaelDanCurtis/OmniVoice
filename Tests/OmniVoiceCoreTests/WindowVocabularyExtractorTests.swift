import Foundation
import XCTest
@testable import OmniVoiceCore

final class WindowVocabularyExtractorTests: XCTestCase {
    func testExtractsBrandAndCodeIdentifiersAndFiltersChromeWords() {
        let texts = [
            "Google Chrome",
            "NeroNook — Dashboard | Settings · Inbox",
            "Working on OmniSpeak and FuegoDev inside CoreMLPunctuationService.swift with SwiftUI on macOS and iPhone. Using OmniVault, Parakeet, and Sortformer for Untitled Document Window Search in Safari and Finder from Apple and Google.",
        ]

        let extracted = WindowVocabularyExtractor.extractTerms(from: texts)
        let extractedSet = Set(extracted)

        // Brand / CamelCase / PascalCase / distinctive proper nouns must be extracted
        for expected in ["NeroNook", "OmniSpeak", "FuegoDev", "CoreMLPunctuationService", "SwiftUI", "macOS", "iPhone", "OmniVault", "Parakeet", "Sortformer"] {
            XCTAssertTrue(extractedSet.contains(expected), "Expected '\(expected)' in \(extracted)")
        }

        // Common English and standard UI chrome words must be excluded
        for excluded in ["Untitled", "Document", "Window", "Settings", "Search", "Inbox", "Chrome", "Safari", "Finder", "Apple", "Google", "Working"] {
            XCTAssertFalse(extractedSet.contains(excluded), "Did not expect UI chrome/common word '\(excluded)' in \(extracted)")
        }
    }

    func testDeduplicatesCaseInsensitivelyAndCapsAtFortyTerms() {
        var chunks: [String] = ["NeroNook neronook NERONOOK OmniSpeak omnispeak"]
        for idx in 1...60 {
            chunks.append("CustomBrand\(idx)Service")
        }

        let extracted = WindowVocabularyExtractor.extractTerms(from: chunks)
        XCTAssertLessThanOrEqual(extracted.count, WindowVocabularyExtractor.maxExtractedTerms)

        let lowercased = extracted.map { $0.lowercased() }
        XCTAssertEqual(lowercased.count, Set(lowercased).count, "Extracted terms must be deduplicated case-insensitively")
        XCTAssertTrue(extracted.contains("NeroNook"))
        XCTAssertTrue(extracted.contains("OmniSpeak"))
    }

    func testEphemeralWindowTermsSpellMisheardBrandOnFirstTry() {
        let ephemeralTerms = WindowVocabularyExtractor.extractTerms(from: [
            "NeroNook — Workspace",
            "Building OmniSpeak and FuegoDev integrations.",
        ])
        XCTAssertTrue(ephemeralTerms.contains("NeroNook"))
        XCTAssertTrue(ephemeralTerms.contains("OmniSpeak"))
        XCTAssertTrue(ephemeralTerms.contains("FuegoDev"))

        // Zero prior learned entries: ephemeral active-window vocabulary alone fixes first-try ASR mishearings
        XCTAssertEqual(
            DictionaryMatcher.apply(
                to: "Open neuron's and check nero nook right now.",
                dictionaryTerms: ephemeralTerms,
                dictionaryEntries: []
            ),
            "Open NeroNook and check NeroNook right now."
        )

        XCTAssertEqual(
            DictionaryMatcher.apply(
                to: "Ship omni speak with fuego dev today.",
                dictionaryTerms: ephemeralTerms,
                dictionaryEntries: []
            ),
            "Ship OmniSpeak with FuegoDev today."
        )

        // Normal English words remain untouched
        XCTAssertEqual(
            DictionaryMatcher.apply(
                to: "Read a new book near the nook.",
                dictionaryTerms: ephemeralTerms,
                dictionaryEntries: []
            ),
            "Read a new book near the nook."
        )
    }

    func testDictionaryMatcherPreservesNewlinesInNumberedLists() {
        let list = """
        Tell me what you got.
        1. Check neuron's latency.
        2. Test nero nook search.
        3. Verify fuego dev builds?
        """
        let matched = DictionaryMatcher.apply(
            to: list,
            dictionaryTerms: ["NeroNook", "FuegoDev"],
            dictionaryEntries: []
        )
        XCTAssertEqual(
            matched,
            """
            Tell me what you got.
            1. Check NeroNook latency.
            2. Test NeroNook search.
            3. Verify FuegoDev builds?
            """
        )
    }
}
