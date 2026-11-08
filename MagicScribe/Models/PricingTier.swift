import Foundation

enum PricingTierID: String, CaseIterable, Identifiable {
    case fillerPro
    case builderPro
    case business
    case businessPlus
    case enterprise

    var id: String { rawValue }

    /// Only these three are surfaced anywhere in the iOS UI right now.
    /// Business+ and Enterprise are shelved for this version but kept as real data.
    var isPurchasableNow: Bool {
        switch self {
        case .fillerPro, .builderPro, .business: true
        case .businessPlus, .enterprise: false
        }
    }
}

struct PricingTier: Identifiable {
    let id: PricingTierID
    let displayName: String
    /// Nil only for Enterprise (custom pricing) — see `isCustomPricing`.
    let monthlyPrice: Decimal?
    let yearlyPrice: Decimal?
    let seats: Int?
    let isCustomPricing: Bool
    let highlights: [FeatureHighlight]

    var monthlyPriceText: String {
        guard let monthlyPrice else { return "Custom" }
        return monthlyPrice.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    var yearlyPriceText: String {
        guard let yearlyPrice else { return "Custom" }
        return yearlyPrice.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    /// Equivalent monthly cost when paying yearly, e.g. "$6/mo" for Filler Pro.
    var yearlyEquivalentMonthlyPriceText: String? {
        guard let yearlyPrice else { return nil }
        let equivalent = yearlyPrice / 12
        return equivalent.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    var yearlySavingsPercent: Int? {
        guard let monthlyPrice, let yearlyPrice, monthlyPrice > 0 else { return nil }
        let monthlyAnnualized = monthlyPrice * 12
        let savings = (monthlyAnnualized - yearlyPrice) / monthlyAnnualized
        return Int(truncating: (savings * 100) as NSDecimalNumber)
    }
}

extension PricingTier {
    static let fillerPro = PricingTier(
        id: .fillerPro,
        displayName: "Filler Pro",
        monthlyPrice: 8,
        yearlyPrice: 72,
        seats: 1,
        isCustomPricing: false,
        highlights: [
            FeatureHighlight(systemImageName: "mic.fill", text: "Voice form filling"),
            FeatureHighlight(systemImageName: "waveform", text: "Voice dictation & editing"),
            FeatureHighlight(systemImageName: "square.and.pencil", text: "Form building"),
        ]
    )

    static let builderPro = PricingTier(
        id: .builderPro,
        displayName: "Builder Pro",
        monthlyPrice: 20,
        yearlyPrice: 180,
        seats: 1,
        isCustomPricing: false,
        highlights: [
            FeatureHighlight(systemImageName: "mic.fill", text: "Voice form filling"),
            FeatureHighlight(systemImageName: "waveform", text: "Voice dictation & editing"),
            FeatureHighlight(systemImageName: "sparkles", text: "AI-assisted form building"),
        ]
    )

    static let business = PricingTier(
        id: .business,
        displayName: "Business",
        monthlyPrice: 49,
        yearlyPrice: 441,
        seats: 5,
        isCustomPricing: false,
        highlights: [
            FeatureHighlight(systemImageName: "checkmark.seal.fill", text: "Everything in Builder Pro"),
            FeatureHighlight(systemImageName: "person.3.fill", text: "Team management"),
            FeatureHighlight(systemImageName: "person.2.badge.plus", text: "5 seats"),
        ]
    )

    static let businessPlus = PricingTier(
        id: .businessPlus,
        displayName: "Business+",
        monthlyPrice: 99,
        yearlyPrice: 891,
        seats: 15,
        isCustomPricing: false,
        highlights: [
            FeatureHighlight(systemImageName: "building.2.fill", text: "Medium agencies/practices"),
        ]
    )

    static let enterprise = PricingTier(
        id: .enterprise,
        displayName: "Enterprise",
        monthlyPrice: nil,
        yearlyPrice: nil,
        seats: nil,
        isCustomPricing: true,
        highlights: [
            FeatureHighlight(systemImageName: "infinity", text: "Everything + Sheets"),
            FeatureHighlight(systemImageName: "lock.shield.fill", text: "SSO"),
        ]
    )

    static let all: [PricingTier] = [.fillerPro, .builderPro, .business, .businessPlus, .enterprise]

    static func tier(for id: PricingTierID) -> PricingTier {
        guard let match = all.first(where: { $0.id == id }) else {
            fatalError("No PricingTier data for \(id)")
        }
        return match
    }
}
