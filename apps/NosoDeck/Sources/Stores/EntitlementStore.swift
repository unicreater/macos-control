import DeckKit
import Foundation
import Observation
import StoreKit

/// Premium, via StoreKit 2 (FR-18).
///
/// Entitlement is cached so the deck behaves sensibly offline: a paid user who opens the
/// app on a plane keeps their pages. The cache is only ever *widened* by StoreKit —
/// losing network never downgrades anyone.
@MainActor
@Observable
final class EntitlementStore {
    /// $2.99/month after a 7-day free trial (D17). The introductory offer is configured
    /// in App Store Connect, not here; this is only its identifier.
    static let monthlyProductID = "com.noso.nosodeck.premium.monthly"

    private static let cacheKey = "com.noso.nosodeck.entitlement"

    private(set) var entitlement: Entitlement
    private(set) var product: Product?
    private(set) var isPurchasing = false
    private(set) var lastError: String?

    nonisolated(unsafe) private var updatesTask: Task<Void, Never>?

    init() {
        let cached = UserDefaults.standard.string(forKey: Self.cacheKey)
        entitlement = cached.flatMap(Entitlement.init(rawValue:)) ?? .free
    }

    deinit {
        updatesTask?.cancel()
    }

    func start() async {
        listenForTransactions()
        await loadProduct()
        await refresh()
    }

    /// The price and trial as the App Store actually has them, so the paywall never
    /// hard-codes a number that App Review can contradict.
    var displayPrice: String { product?.displayPrice ?? "$2.99" }

    var trialDescription: String {
        guard let offer = product?.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else {
            return "7 days free, then \(displayPrice)/month"
        }
        let unitCount = offer.period.value
        let unit: String
        switch offer.period.unit {
        case .day: unit = unitCount == 1 ? "day" : "days"
        case .week: unit = unitCount == 1 ? "week" : "weeks"
        case .month: unit = unitCount == 1 ? "month" : "months"
        case .year: unit = unitCount == 1 ? "year" : "years"
        @unknown default: unit = "days"
        }
        return "\(unitCount) \(unit) free, then \(displayPrice)/month"
    }

    // MARK: - Purchase

    func purchase() async {
        guard let product else {
            lastError = "The subscription isn't available right now. Try again in a moment."
            return
        }

        isPurchasing = true
        lastError = nil
        defer { isPurchasing = false }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified = verification {
                    await refresh()
                } else {
                    // An unverified transaction is not proof of anything.
                    lastError = "That purchase couldn't be verified."
                }
            case .userCancelled:
                break
            case .pending:
                lastError = "Your purchase is waiting for approval."
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// FR-18: restore recovers premium after a reinstall.
    func restore() async {
        isPurchasing = true
        lastError = nil
        defer { isPurchasing = false }

        do {
            try await AppStore.sync()
            await refresh()
            if entitlement == .free {
                lastError = "No previous purchase found on this Apple ID."
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refresh() async {
        var isPremium = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productID == Self.monthlyProductID else { continue }
            if transaction.revocationDate == nil {
                isPremium = true
            }
        }
        apply(isPremium ? .premium : .free)
    }

    private func loadProduct() async {
        product = try? await Product.products(for: [Self.monthlyProductID]).first
    }

    /// Renewals, revocations and purchases made on another device all land here.
    private func listenForTransactions() {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self?.refresh()
            }
        }
    }

    private func apply(_ entitlement: Entitlement) {
        self.entitlement = entitlement
        UserDefaults.standard.set(entitlement.rawValue, forKey: Self.cacheKey)
    }
}
