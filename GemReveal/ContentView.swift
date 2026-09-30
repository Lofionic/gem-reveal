//
//  ContentView.swift
//  GemReveal
//
//  Created by Chris Rivers on 30/09/2026.
//

import SwiftUI
import RealityKit

struct ContentView: View {
    @Environment(ViewModel.self) private var viewModel
    @Environment(RevealAssets.self) private var assets
    
    @State private var resetTrigger = 0
    
    var body: some View {
        ZStack {
            if let gemReveal = viewModel.gemReveal {
                revealView(gemReveal: gemReveal)
            } else if assets.isLoaded {
                menuView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .backgroundPreferenceValue(BackgroundLevelPreferenceKey.self, alignment: .top) {
            BackgroundView(level: $0)
                .animation(.snappy(duration: 0.6), value: $0 == .fullyZoomed)
        }
        .task { await assets.load() }
        .animation(.default, value: assets.isLoaded)
    }
    
    @ViewBuilder
    private func revealView(gemReveal: RevealViewModel) -> some View {
        RevealView(viewModel: gemReveal) {
            withAnimation {
                viewModel.gemReveal = nil
            }
        }
        .transition(.opacity)
        .id(gemReveal.gemDefinition)
    }
    
    @ViewBuilder
    private var menuView: some View {
        GemMenuView()
            .preference(key: BackgroundLevelPreferenceKey.self, value: .full)
            .transition(.opacity)
    }
}

#Preview {
    ContentView()
        .environment(ViewModel())
        .environment(RevealAssets())
}
