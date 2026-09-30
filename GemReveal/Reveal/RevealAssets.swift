//
//  RevealAssets.swift
//  GemReveal
//

import Foundation
import Observation
import RealityKit
import OpalContent

/// Loads the rock and every gem once, ahead of the reveal.
///
/// Loading takes about a second, so it happens while the gem menu is up. The reveal adds clones of
/// these entities, which share their meshes, textures and materials, so opening it doesn't wait.
@Observable
final class RevealAssets {
    private(set) var rock: Entity?
    private(set) var gems: [GemDefinition: Entity] = [:]
    private(set) var loadError: String?

    var isLoaded: Bool { rock != nil }

    func load() async {
        guard !isLoaded else { return }
        do {
            async let rock = Entity(contentsOf: try Self.bundleURL("RockReveal"))
            var gems: [GemDefinition: Entity] = [:]
            for gem in GemDefinition.allCases {
                gems[gem] = try await Entity(named: gem.assetName, in: opalContentBundle)
            }
            self.gems = gems
            self.rock = try await rock
        } catch {
            loadError = error.localizedDescription
        }
    }

    private static func bundleURL(_ name: String) throws -> URL {
        guard let url = Bundle.main.url(forResource: name, withExtension: "usdz") else {
            throw LoadError.missingFile("\(name).usdz")
        }
        return url
    }
}
