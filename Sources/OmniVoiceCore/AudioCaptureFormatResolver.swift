import Foundation

public enum AudioCaptureFormatResolver {
    public static func sampleRate(selectedDeviceSampleRate: Double?, nodeSampleRate: Double) -> Double {
        if let selectedDeviceSampleRate, selectedDeviceSampleRate > 0 {
            return selectedDeviceSampleRate
        }

        if nodeSampleRate > 0 {
            return nodeSampleRate
        }

        return 16_000
    }
}
