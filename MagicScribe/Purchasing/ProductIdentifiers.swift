import Foundation

nonisolated enum ProductIdentifiers {
    static let fillerProMonthly = "tech.magicscribe.fillerpro.monthly"
    static let fillerProYearly = "tech.magicscribe.fillerpro.yearly"
    static let builderProMonthly = "tech.magicscribe.builderpro.monthly"
    static let builderProYearly = "tech.magicscribe.builderpro.yearly"
    static let businessMonthly = "tech.magicscribe.business.monthly"
    static let businessYearly = "tech.magicscribe.business.yearly"

    static let all: [String] = [
        fillerProMonthly, fillerProYearly,
        builderProMonthly, builderProYearly,
        businessMonthly, businessYearly,
    ]

    static func monthlyID(for tier: PricingTierID) -> String? {
        switch tier {
        case .fillerPro: fillerProMonthly
        case .builderPro: builderProMonthly
        case .business: businessMonthly
        case .businessPlus, .enterprise: nil
        }
    }

    static func yearlyID(for tier: PricingTierID) -> String? {
        switch tier {
        case .fillerPro: fillerProYearly
        case .builderPro: builderProYearly
        case .business: businessYearly
        case .businessPlus, .enterprise: nil
        }
    }
}
