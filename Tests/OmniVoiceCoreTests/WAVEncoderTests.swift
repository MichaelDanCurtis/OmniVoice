import XCTest
@testable import OmniVoiceCore

final class WAVEncoderTests: XCTestCase {
    func testPCM16EncoderWritesStandardMonoWAVHeader() throws {
        let data = PCM16WAVEncoder.encode(samples: [0, Int16.max, Int16.min], sampleRate: 48_000)

        XCTAssertEqual(String(decoding: data[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(String(decoding: data[12..<16], as: UTF8.self), "fmt ")
        XCTAssertEqual(readUInt16(data, offset: 20), 1)
        XCTAssertEqual(readUInt16(data, offset: 22), 1)
        XCTAssertEqual(readUInt32(data, offset: 24), 48_000)
        XCTAssertEqual(readUInt16(data, offset: 34), 16)
        XCTAssertEqual(String(decoding: data[36..<40], as: UTF8.self), "data")
        XCTAssertEqual(readUInt32(data, offset: 40), 6)
        XCTAssertEqual(data.count, 50)
    }

    func testPCM16EncoderWritesValidEmptyWAV() throws {
        let data = PCM16WAVEncoder.encode(samples: [], sampleRate: 16_000)

        XCTAssertEqual(String(decoding: data[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(String(decoding: data[36..<40], as: UTF8.self), "data")
        XCTAssertEqual(readUInt32(data, offset: 40), 0)
        XCTAssertEqual(data.count, 44)
    }

    private func readUInt16(_ data: Data, offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func readUInt32(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
