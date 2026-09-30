import SwiftUI

struct GlowEffectLayer<V: View>: View {
    @State private var pulseAnimation: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    let isAttracting: Bool
    let isPulsing: Bool
    
    @ViewBuilder let content: () -> V
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.clear)
                .background {
                    ZStack {
                        background
                            .opacity(isAttracting ? 0 : 1)
                        attractBackground
                            .opacity(isAttracting ? 1 : 0)
                    }
                }
                .mask(mask)
            
            if #available(iOS 26.0, *) {
                Rectangle()
                    .fill(.clear)
                    .glassEffect(.regular, in: .capsule)
            }
            
            content()
        }
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            // The pulse and the turning gradients run forever, so they stay still with Reduce Motion
            guard !reduceMotion else { return }
            withAnimation(
                Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)
            ) {
                pulseAnimation = 1
            }
        }
    }
    
    private var attractBackground: some View {
        ZStack {
            Rectangle()
                .fill(AngularGradient(
                    colors: [
                        Color.gemGreen.opacity(0.5),
                        Color.gemGreen.opacity(0.75),
                        Color.white,
                        Color.gemGreen.opacity(0.75),
                        Color.gemGreen.opacity(0.5),
                    ],
                    center: .center
                ))
                .padding(-16)
                .aspectRatio(1, contentMode: .fill)
                .keyframeAnimator(initialValue: 0.0, repeating: !reduceMotion, content: { [reduceMotion] content, value in
                    content.rotationEffect(.radians(reduceMotion ? 0 : value))
                }, keyframes: { _ in
                    LinearKeyframe(-Double.pi, duration: 1.0)
                    LinearKeyframe(-Double.pi * 2.0, duration: 1.0)
                })
            
            Rectangle()
                .fill(AngularGradient(
                    colors: [
                        Color.gemGreen.opacity(0.5),
                        Color.gemGreen.opacity(0.75),
                        Color.white,
                        Color.gemGreen.opacity(0.75),
                        Color.gemGreen.opacity(0.5),
                    ],
                    center: .center
                ))
                .padding(-16)
                .aspectRatio(1, contentMode: .fill)
                .opacity(0.5)
        }
    }
    
    private var background: some View {
        Rectangle()
            .fill(AngularGradient(
                colors: [
                    Color.gemGreen.opacity(0.5),
                    Color.gemGreen.opacity(0.626),
                    Color.gemGreen.opacity(0.75),
                    Color.gemGreen.opacity(1.0),
                    Color.gemGreen.opacity(1.0),
                    Color.gemGreen.opacity(0.75),
                    Color.gemGreen.opacity(0.625),
                    Color.gemGreen.opacity(0.5),
                ],
                center: .center
            ))
            .padding(-16)
            .aspectRatio(1, contentMode: .fill)
            .keyframeAnimator(initialValue: 0.0, repeating: !reduceMotion, content: { [reduceMotion] content, value in
                content.rotationEffect(.radians(reduceMotion ? 0 : value))
            }, keyframes: { _ in
                LinearKeyframe(-Double.pi, duration: 8.0)
                LinearKeyframe(-Double.pi * 2.0, duration: 8.0)
            })
            .saturation(0)
    }
    
    private var mask: some View {
        ZStack {
            Capsule()
                .stroke(lineWidth: isAttracting ? 3 : 2)
            
            if isPulsing {
                Capsule()
                    .stroke(lineWidth: 3.0 + 2.0 * pulseAnimation)
                    .blur(radius: 4.0 + 2.0 * pulseAnimation)
                    .opacity(isAttracting ? 1 : 0)
            }
            
            Capsule()
                .opacity(0.5)
                .blendMode(.destinationOut)
                .padding(2)
        }
    }
}
