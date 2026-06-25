struct AccessibilityPromptGate {
    private var didPrompt = false

    mutating func markPrompted() {
        didPrompt = true
    }

    mutating func shouldPromptAutomatically(isTrusted: Bool) -> Bool {
        if isTrusted {
            didPrompt = false
            return false
        }

        guard !didPrompt else {
            return false
        }

        didPrompt = true
        return true
    }
}
