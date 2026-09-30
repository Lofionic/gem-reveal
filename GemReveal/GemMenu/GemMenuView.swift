//
//  GemMenuView.swift
//  GemReveal
//

import SwiftUI
import RealityKit

struct GemMenuView: View {
    @Environment(ViewModel.self) var viewModel
    
    /// Easiest gem first, in `GemDefinition`'s order. The view models are keyed by gem, which has no order.
    var rows: [GemGridRow] {
        GemDefinition.allCases.map {
            .init(gemDefinition: $0, isLocked: viewModel.gemViewModels[$0]?.isRevealed != true)
        }
    }
    
    var body: some View {
        ZStack {
            GemGrid(items: rows) { gem in
                withAnimation {
                    viewModel.openGem(gem)
                }
            }
        }
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                resetButton
            }
            .sharedBackgroundVisibility(.hidden)
#endif
        }
    }
    
    @ViewBuilder private var resetButton: some View {
        Button(action: {
            withAnimation { viewModel.resetAll() }
        }, label: {
            Label("Reset", systemImage: "arrow.counterclockwise")
        })
    }
}

#Preview {
    let assets = RevealAssets()
    
    GemMenuView()
        .environment(ViewModel())
        .task { await assets.load() }
}
