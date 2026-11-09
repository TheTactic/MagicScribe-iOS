import StoreKit
import SwiftUI

/// Real StoreKit purchase, not a web link-out to Stripe — see the plan's note on
/// why a reader-app link-out was rejected (anti-steering risk for a feature-unlock
/// app) in favor of real IAP.
struct PaywallView: View {
    let coordinator: OnboardingCoordinator
    @Environment(StoreKitManager.self) private var storeKit

    @State private var billingPeriod: BillingPeriod = .yearly
    @State private var isPurchasing = false
    @State private var errorMessage: String?

    private enum BillingPeriod {
        case monthly
        case yearly
    }

    private let tier = PricingTier.voicePro

    private var productID: String {
        switch billingPeriod {
        case .monthly: ProductIdentifiers.voiceProMonthly
        case .yearly: ProductIdentifiers.voiceProYearly
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text(tier.displayName)
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.magicNavy)
                if let percent = tier.yearlySavingsPercent, billingPeriod == .yearly {
                    Text("Save \(percent)% with yearly")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.magicGold)
                }
            }

            Picker("Billing period", selection: $billingPeriod) {
                Text("Yearly").tag(BillingPeriod.yearly)
                Text("Monthly").tag(BillingPeriod.monthly)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            VStack(spacing: 4) {
                Text(billingPeriod == .yearly ? tier.yearlyPriceText : tier.monthlyPriceText)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Color.magicNavy)
                Text(billingPeriod == .yearly ? "per year" : "per month")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if billingPeriod == .yearly, let equivalent = tier.yearlyEquivalentMonthlyPriceText {
                    Text("equivalent to \(equivalent)/mo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(tier.highlights) { highlight in
                    Label(highlight.text, systemImage: highlight.systemImageName)
                        .foregroundStyle(Color.magicNavy)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task { await purchase() }
                } label: {
                    if isPurchasing {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text(tier.isCustomPricing ? "Contact sales" : "Subscribe")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.magicBlue)
                .disabled(isPurchasing)

                Text("Cancel anytime in Settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Continue with demo") {
                    coordinator.declinePaywall()
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .task {
            if storeKit.products.isEmpty {
                await storeKit.loadProducts()
            }
        }
    }

    private func purchase() async {
        guard let product = storeKit.product(for: productID) else {
            errorMessage = "This plan isn't available to purchase yet."
            return
        }
        errorMessage = nil
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await storeKit.purchase(product)
            switch result {
            case .success:
                coordinator.finishOnboarding()
            case .userCancelled:
                break
            case .pending:
                errorMessage = "Purchase is pending approval."
            }
        } catch let StoreKitManagerError.serverVerificationFailed(message) {
            errorMessage = message
        } catch {
            errorMessage = "Something went wrong — please try again."
        }
    }
}

#Preview {
    PaywallView(coordinator: OnboardingCoordinator(startingAt: .paywall))
        .environment(StoreKitManager())
}
