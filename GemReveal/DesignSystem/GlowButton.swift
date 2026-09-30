import SwiftUI

struct GlowButton: ButtonStyle {
    let isAttracting: Bool
    
    public init(isAttracting: Bool) {
        self.isAttracting = isAttracting
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        GlowEffectLayer(isAttracting: isAttracting, isPulsing: true) {
            configuration.label
                .font(.system(size: 16, weight: .bold))
                .kerning(-0.5)
                .padding(.vertical, 12)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Capsule())
        .brightness(configuration.isPressed ? -0.02 : 0.00)
    }
}

#Preview {
    @State @Previewable var isAttracting = false
    
    VStack(alignment: .center) {
        Button(action: {
            print("Pressed")
        }, label: {
            HStack(spacing: 4) {
                Text("Chat")
            }
        })
        .buttonStyle(GlowButton(isAttracting: isAttracting))
        
        HStack {
            Spacer()
            Toggle(isOn: $isAttracting.animation(), label: {
                Text("Attract")
            })
            Spacer()
        }
    }
    .padding(.horizontal)
    .preferredColorScheme(.dark)
}
