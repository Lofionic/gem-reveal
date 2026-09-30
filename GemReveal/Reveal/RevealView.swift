import SwiftUI
import RealityKit

@Observable
final class RevealViewModel {
    let gemDefinition: GemDefinition
    /// When the gem was first revealed, or nil while it's still in the rock.
    var unlockDate: Date?
    
    var isRevealed: Bool { unlockDate != nil }
    
    init(gemDefinition: GemDefinition, unlockDate: Date? = nil) {
        self.gemDefinition = gemDefinition
        self.unlockDate = unlockDate
    }
}

struct RevealView: View {
    @Environment(RevealAssets.self) private var assets
    
    @State var viewModel: RevealViewModel
    
    @State private var revealStage: Int = 0
    
    @State private var isShowingGemDetail = false
    
    @State private var isShowingTapAgain = false
    @State private var showTapAgainTask: Task<Void, Never>?
    
    @State private var gemDetailHeight: CGFloat = 0
    
#if DEBUG
    /// The debug panel's values, seeded from the gem the first time the panel opens.
    @State private var tuning: GemTuning?
    @State private var isShowingTuning = false
#endif
    
    private var isShowingRevealButton: Bool {
        revealStage == 0
    }
    
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            if
                let rock = assets.rock,
                let gem = assets.gems[viewModel.gemDefinition]
            {
                sceneView(rock: rock, gem: gem)
                .offset(y: isShowingGemDetail ? -gemDetailHeight * 0.5 : 0)
                .ignoresSafeArea()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                backButton
            }
            .sharedBackgroundVisibility(.hidden)
#endif
#if DEBUG
            ToolbarItem(placement: .primaryAction) {
                tuningButton
            }
#endif
        }
#if DEBUG
        .sheet(isPresented: $isShowingTuning) {
            if let tuning = Binding($tuning), let gem = assets.gems[viewModel.gemDefinition] {
                GemTuningPanel(
                    tuning: tuning,
                    original: GemTuning(gem: gem, definition: viewModel.gemDefinition)
                )
                // Short enough to watch the gem above it while tuning. One fixed height: the
                // controls scroll within it, and swipes scroll them rather than resize the sheet.
                .presentationDetents([.fraction(0.4)])
                .presentationContentInteraction(.scrolls)
                .presentationBackgroundInteraction(.enabled)
            }
        }
#endif
        .overlayPreferenceValue(GemAnchorPreferenceKey.self) { anchor in
            GeometryReader { geometry in
                anchor.map {
                    Rectangle()
                        .fill(.clear)
                        .overlay(alignment: .top) {
                            GemDetailView(gem: viewModel.gemDefinition)
                                .padding(20)
                                .onGeometryChange(for: CGFloat.self, of: \.size.height) {
                                    gemDetailHeight = $0
                                }
                        }
                        .frame(
                            width: geometry.frame(in: .local).width,
                            height: geometry.frame(in: .local) .height - geometry[$0].maxY
                        )
                        .position(
                            x: geometry.frame(in: .local).midX,
                            y: geometry[$0].maxY + (geometry.frame(in: .local).height - geometry[$0].maxY) * 0.5
                        )
                }
            }
            .opacity(isShowingGemDetail ? 1 : 0)
            // Invisible until the reveal, so keep it from VoiceOver until then too
            .accessibilityHidden(!isShowingGemDetail)
        }
        .onAppear {
            if viewModel.isRevealed {
                isShowingGemDetail = true
                revealStage = 3
            }
        }
        .onChange(of: revealStage) { _, newValue in
            isShowingTapAgain = false
            showTapAgainTask?.cancel()
            showTapAgainTask = nil
            
            if newValue == 3 {
                // Keep the first date: reopening a revealed gem replays the burst too
                if viewModel.unlockDate == nil {
                    viewModel.unlockDate = .now
                }
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    withAnimation(.easeInOut(duration: 1)) {
                        isShowingGemDetail = true
                    }
                    AccessibilityNotification.Announcement("Gem revealed").post()
                }
            } else {
                showTapAgainTask = Task {
                    try? await Task.sleep(for: .seconds(1.0))
                    if Task.isCancelled { return }
                    withAnimation { isShowingTapAgain = true }
                    showTapAgainTask = nil
                }
            }
        }
        .overlay(alignment: .top) {
                unlockedView
                .opacity(isShowingGemDetail ? 1 : 0)
        }
        .safeAreaInset(edge: .bottom) {
            ZStack {
                Button("Apply Theme", action: onDismiss)
                    .buttonStyle(GlowButton(isAttracting: true))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    .opacity(isShowingGemDetail ? 1 : 0)
                    .allowsHitTesting(isShowingGemDetail)
                    .accessibilityHidden(!isShowingGemDetail)
                
                Button("Reveal") {
                    revealStage = 1
                }
                .buttonStyle(GlowButton(isAttracting: true))
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .opacity(isShowingRevealButton ? 1 : 0)
                .allowsHitTesting(isShowingRevealButton)
                .accessibilityHidden(!isShowingRevealButton)
            }
            
            Text("TAP AGAIN")
                .font(.caption.bold())
                .frame(maxWidth: .infinity, alignment: .center)
                .foregroundStyle(.gemGreen)
                .opacity(isShowingTapAgain ? 1 : 0)
        }
        .preference(key: BackgroundLevelPreferenceKey.self, value: revealStage >= 2 ? .fullyZoomed : .zoomed)
    }
    
    /// The scene, given the debug panel's values in Debug builds.
    private func sceneView(rock: Entity, gem: Entity) -> RevealSceneView {
#if DEBUG
        if let tuning {
            return RevealSceneView(
                rockModel: rock,
                gemModel: gem,
                glowColor: tuning.glowColor,
                glowStrength: tuning.glowStrength,
                debugTuning: tuning,
                stage: $revealStage
            )
        }
#endif
        return RevealSceneView(
            rockModel: rock,
            gemModel: gem,
            glowColor: viewModel.gemDefinition.glowColor,
            glowStrength: viewModel.gemDefinition.glowStrength,
            stage: $revealStage
        )
    }
    
#if DEBUG
    private var tuningButton: some View {
        Button("Tune Gem", systemImage: "slider.horizontal.3") {
            if tuning == nil, let gem = assets.gems[viewModel.gemDefinition] {
                tuning = GemTuning(gem: gem, definition: viewModel.gemDefinition)
            }
            isShowingTuning = true
        }
    }
#endif
    
    private var unlockedView: some View {
        HStack {
            Image(systemName: "calendar.day")
            Text("Unlocked on \((viewModel.unlockDate ?? .now).formatted(.dateTime.day().month().year()))")
        }
        .foregroundStyle(.white.opacity(0.6))
        .font(.caption)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.2))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(lineWidth: 1)
                .foregroundStyle(.white.opacity(0.1))
        }
        .padding(.horizontal, 20)
    }
    
    private var backButton: some View {
        Button(action: {
            resetAndGoBack()
        }, label: {
            Label("Back", systemImage: "chevron.left")
        })
    }
    
    private func resetAndGoBack() {
        let wasOpened = revealStage > 0 && revealStage < 3
        if wasOpened { revealStage = 0 }
        Task {
            defer {
                onDismiss()
            }
            if wasOpened {
                try? await Task.sleep(for: .seconds(0.5))
            }
        }
    }
}

private struct GemDetailView: View {
    let gem: GemDefinition
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text(gem.title)
                    .font(.title3)
                    .kerning(-0.5)
                
                Text(gem.achievement)
                    .multilineTextAlignment(.center)
                    .font(.body)
                    .opacity(0.6)
                    .kerning(-0.5)
            }
            HStack(spacing: 4) {
                Image(systemName: "trophy.circle")
                    .accessibilityHidden(true)
                Text("Owned by \(gem.ownedByPercent)%")
                    .kerning(-0.5)
            }
            .font(.caption)
            .bold()
            .foregroundStyle(.gemGreen.opacity(0.6))
        }
        .foregroundStyle(.white)
        // One element, read as a whole
        .accessibilityElement(children: .combine)
    }
}

#Preview("Unrevealed") {
    let assets = RevealAssets()
    NavigationStack {
        RevealView(viewModel: .init(gemDefinition: .opal), onDismiss: {})
            .background(.black)
            .environment(assets)
            .task { await assets.load() }
    }
    .preferredColorScheme(.dark)
}

#Preview("Revealed") {
    let assets = RevealAssets()
    NavigationStack {
        RevealView(viewModel: .init(gemDefinition: .opal, unlockDate: .now.addingTimeInterval(-3 * 24 * 60 * 60)), onDismiss: {})
            .background(.black)
            .environment(assets)
            .task { await assets.load() }
    }
    .preferredColorScheme(.dark)
}

#Preview("Gem Detail") {
    VStack {
        Spacer()
        GemDetailView(gem: .opal)
        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.black)
}
