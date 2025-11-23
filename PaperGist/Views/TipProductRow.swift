//
// TipProductRow.swift
// PaperGist
//
// StoreKit product row for displaying and purchasing tip jar items.
// Handles product loading, purchase flow, and transaction verification.
//
// Created by Aidan Cornelius-Bell on 15/01/2025.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import StoreKit
import OSLog

/// In-app purchase row for tip jar products
struct TipProductRow: View {
    let productId: String
    let iconName: String
    let title: String

    @State private var product: Product?
    @State private var isPurchasing = false
    @State private var purchaseError: Error?

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(Color.terracotta)
                .frame(width: 32)

            // Title
            Text(title)
                .font(.bodySourceSans)

            Spacer()

            // Purchase button
            if let product = product {
                Button {
                    purchase(product)
                } label: {
                    if isPurchasing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(product.displayPrice)
                            .font(.subheadlineSourceSans)
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.terracotta)
                .disabled(isPurchasing)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .task {
            await loadProduct()
        }
        .alert("Purchase Error", isPresented: .constant(purchaseError != nil)) {
            Button("OK") {
                purchaseError = nil
            }
        } message: {
            if let error = purchaseError {
                Text(error.localizedDescription)
            }
        }
    }

    private func loadProduct() async {
        do {
            let products = try await Product.products(for: [productId])
            product = products.first
        } catch {
            AppLogger.general.error("Failed to load product \(productId): \(error.localizedDescription)")
        }
    }

    private func purchase(_ product: Product) {
        Task {
            isPurchasing = true
            defer { isPurchasing = false }

            do {
                let result = try await product.purchase()

                switch result {
                case .success(let verification):
                    switch verification {
                    case .verified(let transaction):
                        // Transaction is verified, finish it
                        await transaction.finish()
                    case .unverified:
                        // Transaction failed verification
                        purchaseError = NSError(
                            domain: "PaperGist",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Purchase could not be verified"]
                        )
                    }
                case .pending:
                    // Purchase is pending (e.g., requires parental approval)
                    break
                case .userCancelled:
                    // User cancelled the purchase
                    break
                @unknown default:
                    break
                }
            } catch {
                purchaseError = error
            }
        }
    }
}

#Preview {
    List {
        TipProductRow(
            productId: "com.papergist.tip.small",
            iconName: "cup.and.saucer",
            title: "Small tip"
        )

        TipProductRow(
            productId: "com.papergist.tip.medium",
            iconName: "mug",
            title: "Medium tip"
        )

        TipProductRow(
            productId: "com.papergist.tip.large",
            iconName: "takeoutbag.and.cup.and.straw",
            title: "Large tip"
        )
    }
}
