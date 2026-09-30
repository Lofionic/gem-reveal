//
//  BackgroundView.swift
//  GemReveal
//
//  Created by Chris Rivers on 01/10/2026.
//

import SwiftUI

struct BackgroundLevelPreferenceKey: PreferenceKey {
    static var defaultValue: BackgroundLevel { .full }
    
    static func reduce(value: inout BackgroundLevel, nextValue: () -> BackgroundLevel) {
        //
    }
}

enum BackgroundLevel: Int {
    case full = 0
    case zoomed
    case fullyZoomed
}

struct BackgroundView: View {
    let level: BackgroundLevel
    
    var body: some View {
        Rectangle()
            .fill(.black)
            .overlay {
                Image(decorative: "background", bundle: .main)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .offset(x: 0, y: -level.yOffset)
                    .padding(-level.yOffset)
                    .opacity(0.5)
            }
            .overlay(alignment: .bottom) {
                ParallaxOverlay(level: level)
            }
        .ignoresSafeArea()    }
}

struct ParallaxOverlay: View {
    let level: BackgroundLevel
    
    var body: some View {
        GeometryReader { geometry in
            let frameSize = min(geometry.size.width, geometry.size.height)
            
            Rectangle()
                .fill(.clear)
                .frame(width: frameSize, height: frameSize)
                .overlay {
                    Image(decorative: "parallaxLeft", bundle: .main)
                        .resizable()
                        .scaledToFit()
                }
                .position(
                    x: geometry.size.width * 0.1 - level.yOffset,
                    y: geometry.size.height - frameSize * 0.5 + level.yOffset * 0.5
                )
            
            
            Rectangle()
                .fill(.clear)
                .frame(width: frameSize, height: frameSize)
                .overlay {
                    Image(decorative: "parallaxRight", bundle: .main)
                        .resizable()
                        .scaledToFit()
                }
                .position(
                    x: geometry.size.width - (
                        geometry.size.width * 0.1
                    )  + level.yOffset,
                    y: geometry.size.height - frameSize * 0.5 + level.yOffset * 0.5
                )
            
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension BackgroundLevel {
    var yOffset: CGFloat {
        switch self {
        case .full: 0
        case .zoomed: 80
        case .fullyZoomed: 120
        }
    }
}

#Preview {
    @State @Previewable var level: BackgroundLevel = .full
    BackgroundView(level: level)
        .ignoresSafeArea()
        .overlay {
            VStack {
                Button("Full") { withAnimation { level = .full } }
                Button("Zoom") { withAnimation { level = .zoomed } }
                Button("Fully Zoomed") { withAnimation { level = .fullyZoomed } }
                
            }
        }
}
