//
//  GemTuningPanel.swift
//  GemReveal
//

#if DEBUG
import SwiftUI

/// Debug controls for the revealed gem's shader graph inputs and glow. Changes apply live.
struct GemTuningPanel: View {
    @Binding var tuning: GemTuning
    /// The gem's values as loaded, for Reset.
    let original: GemTuning

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Material") {
                    ForEach(GemTuning.Parameter.allCases) { parameter in
                        slider(parameter.title, value: floatBinding(parameter), in: parameter.range)
                    }
                    ColorPicker("Rim colour", selection: $tuning.rimColor, supportsOpacity: false)
                }
                Section("Glow") {
                    slider("Strength", value: $tuning.glowStrength, in: 0...2)
                    ColorPicker("Colour", selection: glowColorBinding, supportsOpacity: false)
                }
            }
            .navigationTitle("Tune Gem")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { tuning = original }
                        .disabled(tuning == original)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func slider(_ title: String, value: Binding<Float>, in range: ClosedRange<Float>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .accessibilityLabel(title)
        }
    }

    private func floatBinding(_ parameter: GemTuning.Parameter) -> Binding<Float> {
        Binding {
            tuning.floats[parameter] ?? parameter.range.lowerBound
        } set: {
            tuning.floats[parameter] = $0
        }
    }

    /// The glow colour, stored as linear RGB, as a colour the picker can edit.
    private var glowColorBinding: Binding<CGColor> {
        let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        return Binding {
            let c = tuning.glowColor
            return CGColor(colorSpace: linear, components: [CGFloat(c.x), CGFloat(c.y), CGFloat(c.z), 1])!
        } set: { color in
            guard let components = color.converted(to: linear, intent: .defaultIntent, options: nil)?.components,
                  components.count >= 3 else { return }
            tuning.glowColor = [Float(components[0]), Float(components[1]), Float(components[2])]
        }
    }
}
#endif
