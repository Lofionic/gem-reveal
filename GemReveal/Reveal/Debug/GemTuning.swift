//
//  GemTuning.swift
//  GemReveal
//

#if DEBUG
import CoreGraphics
import RealityKit

/// Live values for a gem's shader graph inputs and its glow, set from `GemTuningPanel` in Debug
/// builds. Applied to the reveal's clone of the gem only, so they reset when the reveal closes.
struct GemTuning: Equatable {
    /// The Opal shader graph's float inputs, named as in OpalContent's `Scene.usda`.
    enum Parameter: String, CaseIterable, Identifiable {
        case flashStrength = "FlashStrength"
        case flashSwing = "FlashSwing"
        case rimStrength = "RimStrength"
        case hueRange = "HueRange"
        case patchScale = "PatchScale"
        case shimmerSpeed = "ShimmerSpeed"
        case roughness = "Roughness"

        var id: Self { self }

        var title: String {
            switch self {
            case .flashStrength: "Flash strength"
            case .flashSwing: "Flash swing"
            case .rimStrength: "Rim strength"
            case .hueRange: "Hue range"
            case .patchScale: "Patch scale"
            case .shimmerSpeed: "Shimmer speed"
            case .roughness: "Roughness"
            }
        }

        var range: ClosedRange<Float> {
            switch self {
            case .flashStrength: 0...3
            case .flashSwing: 0...6
            case .rimStrength: 0...2
            case .hueRange: 0...1
            case .patchScale: 1...50
            case .shimmerSpeed: 0...1
            case .roughness: 0...1
            }
        }
    }

    static let rimColorName = "RimColor"

    var floats: [Parameter: Float]
    var rimColor: CGColor
    var glowStrength: Float
    /// Linear RGB, like `GemDefinition.glowColor`.
    var glowColor: SIMD3<Float>

    /// Seeds every value from the gem as loaded, so the controls start at its real look: its own
    /// overrides, or the graph's defaults where it has none. The glow comes from its definition.
    init(gem: Entity, definition: GemDefinition) {
        let material = Self.shaderGraphMaterials(in: gem).first
        floats = Dictionary(uniqueKeysWithValues: Parameter.allCases.map { parameter in
            guard case .float(let value) = material?.getParameter(name: parameter.rawValue) else {
                return (parameter, parameter.range.lowerBound)
            }
            return (parameter, value)
        })
        if case .color(let color) = material?.getParameter(name: Self.rimColorName) {
            rimColor = color
        } else {
            rimColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        }
        glowStrength = definition.glowStrength
        glowColor = definition.glowColor
    }

    /// Sets the material values on every shader graph material in `gem`. Each model entity gets its
    /// own copy of its model component, so other clones of the gem keep their look.
    func apply(to gem: Entity) {
        if var model = gem.components[ModelComponent.self] {
            model.materials = model.materials.map { material in
                guard var material = material as? ShaderGraphMaterial else { return material }
                for (parameter, value) in floats {
                    try? material.setParameter(name: parameter.rawValue, value: .float(value))
                }
                try? material.setParameter(name: Self.rimColorName, value: .color(rimColor))
                return material
            }
            gem.components.set(model)
        }
        gem.children.forEach(apply(to:))
    }

    private static func shaderGraphMaterials(in entity: Entity) -> [ShaderGraphMaterial] {
        let own = entity.components[ModelComponent.self]?.materials.compactMap { $0 as? ShaderGraphMaterial } ?? []
        return own + entity.children.flatMap(shaderGraphMaterials(in:))
    }
}
#endif
