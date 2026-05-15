import Foundation

public enum PCM16WAVEncoder {
    public static func encode(samples: [Int16], sampleRate: Int) -> Data {
        let bytesPerSample = 2
        let channelCount = 1
        let dataByteCount = samples.count * bytesPerSample
        let byteRate = sampleRate * channelCount * bytesPerSample
        let blockAlign = channelCount * bytesPerSample

        var data = Data()
        data.reserveCapacity(44 + dataByteCount)
        data.appendASCII("RIFF")
        data.appendLittleEndian(UInt32(36 + dataByteCount))
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(channelCount))
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(UInt32(byteRate))
        data.appendLittleEndian(UInt16(blockAlign))
        data.appendLittleEndian(UInt16(16))
        data.appendASCII("data")
        data.appendLittleEndian(UInt32(dataByteCount))

        for sample in samples {
            data.appendLittleEndian(UInt16(bitPattern: sample))
        }

        return data
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }
}
