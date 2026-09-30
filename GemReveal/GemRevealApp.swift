//
//  GemRevealApp.swift
//  GemReveal
//
//  Created by Chris Rivers on 30/09/2026.
//

import SwiftUI
#if os(iOS)
import AVFAudio
#endif

@main
struct GemRevealApp: App {
#if os(iOS)
    init() {
        // Playback, not the default solo ambient, so the sound effects play with the Ring/Silent
        // switch on silent, as it often is while recording the screen. Mixing leaves any other
        // app's audio playing alongside.
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
    }
#endif
    
    var body: some Scene {
        WindowGroup {
#if os(iOS)
            NavigationView {
                ContentView()
                    .environment(ViewModel())
                    .environment(RevealAssets())
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarRole(.navigationStack)
                    .preferredColorScheme(.dark)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text("X GEMS")
                                .foregroundStyle(.clear)
                                .overlay {
                                    Image("logo")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                }
                        }
                    }
            }
#else
            ContentView()
                .environment(ViewModel())
                .environment(RevealAssets())
                .preferredColorScheme(.dark)
#endif
        }
    }
}
