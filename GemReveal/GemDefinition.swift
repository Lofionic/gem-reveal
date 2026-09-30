//
//  GemDefinition.swift
//  GemReveal
//

import Foundation

/// The gems, easiest to earn first. `allCases` is the menu's order. Opal is the top reward.
enum GemDefinition: String, CaseIterable, Hashable {
    case cherryQuartz
    case amethyst
    case blueQuartz
    case amazonite
    case jade
    case opal

    var assetName: String {
        switch self {
        case .cherryQuartz: "cherry_quartz_01"
        case .amethyst: "amethyst_01"
        case .blueQuartz: "blue_quartz_01"
        case .amazonite: "amazonite_01"
        case .jade: "jade_01"
        case .opal: "opal_01"
        }
    }

    /// The colour of the light the gem gives off inside the rock, linear RGB. Richer than the
    /// material's `RimColor` so it reads on the dark rock.
    var glowColor: SIMD3<Float> {
        switch self {
        case .cherryQuartz: [1, 0.45, 0.55]
        case .amethyst: [0.75, 0.45, 1]
        case .blueQuartz: [0.35, 0.55, 1]
        case .amazonite: [0.45, 1, 0.85]
        case .jade: [0.35, 0.9, 0.45]
        case .opal: [0.55, 0.85, 1]
        }
    }

    /// How strongly the gem glows as the rock opens, scaling its light and halo. Rarer gems glow
    /// more, and opal, the top reward, well past the rest.
    var glowStrength: Float {
        switch self {
        case .cherryQuartz: 0.35
        case .amethyst: 0.45
        case .blueQuartz: 0.55
        case .amazonite: 0.65
        case .jade: 0.8
        case .opal: 1.3
        }
    }

    /// The gem's name, shown when it's revealed.
    var title: String {
        switch self {
        case .cherryQuartz: "Ember Heart"
        case .amethyst: "Quiet Hours"
        case .blueQuartz: "First Light"
        case .amazonite: "Tidewatcher"
        case .jade: "Deep Groove"
        case .opal: "Luminous Mind"
        }
    }

    /// The focus achievement that earned the gem.
    var achievement: String {
        switch self {
        case .cherryQuartz: "You kept a 7-day focus streak burning."
        case .amethyst: "You kept your screen time under 2 hours a day for a whole week."
        case .blueQuartz: "You started 5 days in a row with a focus session before 8am."
        case .amazonite: "You blocked distractions every day for a month."
        case .jade: "You completed a 4-hour deep focus session without a break."
        case .opal: "You've reached 100 hours of focus with Opal."
        }
    }

    /// The share of people who own the gem, as a percentage. Harder achievements are rarer.
    var ownedByPercent: Int {
        switch self {
        case .cherryQuartz: 41
        case .amethyst: 33
        case .blueQuartz: 27
        case .amazonite: 18
        case .jade: 9
        case .opal: 4
        }
    }
}
