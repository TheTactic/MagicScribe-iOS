import Foundation

nonisolated enum ProductIdentifiers {
    // Placeholder — real App Store Connect product ids pending (iOS v1
    // ships a single product, Voice Pro, monthly + yearly).
    static let voiceProMonthly = "tech.magicscribe.voicepro.monthly"
    static let voiceProYearly = "tech.magicscribe.voicepro.yearly"

    static let all: [String] = [voiceProMonthly, voiceProYearly]
}
