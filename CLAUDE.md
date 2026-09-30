# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

GemReveal is a SwiftUI + RealityKit app that shows a 3D rock model (`GemReveal/RockReveal.usdz`) which the user spins around its vertical axis by dragging. It's a single multiplatform target (iOS/iPadOS, macOS, visionOS), deployment target 27.0, bundle ID `com.lofionic.GemReveal`.

## Build

One target and one scheme, both `GemReveal`. There are no tests, packages or linters.

```sh
# macOS
xcodebuild -scheme GemReveal -destination 'platform=macOS' build

# iOS Simulator
xcodebuild -scheme GemReveal -destination 'generic/platform=iOS Simulator' build

# visionOS Simulator
xcodebuild -scheme GemReveal -destination 'generic/platform=visionOS Simulator' build
```

## Project setup notes

- The project uses **file-system synchronized groups**: any file dropped into `GemReveal/` is automatically part of the target and bundled. You don't need to edit `project.pbxproj` to add sources or assets.
- Build settings `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES` are on, so types are main-actor by default.
- App resources are flattened into one bundle folder, so names must be unique across subfolders.
- `Packages/OpalContent` is a local Swift package and a Reality Composer Pro project (open `Package.realitycomposerpro`). It holds every gem. Keep RCP packages outside `GemReveal/`, or the synced folder pulls their files into the app target.
  - `OpalContent.rkassets/Scene.usda` holds the shared Opal shader graph at `/Root/OpalMaterial`, used by every gem (no per-gem graphs). Edit the graph only here. Its inputs are the two textures, `RimColor`, and the floats `RimStrength`, `HueRange`, `FlashStrength`, `FlashSwing`, `PatchScale`, `ShimmerSpeed` and `Roughness`; the defaults are opal's look.
  - Each gem is a scene named after its asset name, e.g. `opal_01.usda`, `jade_01.usda`, with gem-prefixed files (`<name>_model.usdz`, `<name>_base.png`, `<name>_emission.png`). Its material references `Scene.usda`'s `OpalMaterial` and overrides the two textures plus whichever inputs it changes; the rest keep the graph's defaults. The mesh prim is bound to that material, and its `over` path must match the prim names in the model (`Gem/Gem` for opal, `Gem_<name>/Gem_<name>` for the others).
  - Gems: opal, cherry quartz, amazonite, blue quartz, jade, amethyst. Their geometry and textures come from the Blender master (see `Blender/README.txt`).
  - To add a gem: model it in the Blender master and run `check_gem_fit`, `bake_gem_textures` and `export_gem` on it; copy one of the gem `.usda` files under the new name, matching its prim names; reference it from `Scene.usda`; then add a case and `assetName` to `GemDefinition`.

## Architecture

`ContentView.swift` is the screen around the scene: background, load-error label and Reset button. It hosts `RevealSceneView.swift`, which owns the RealityKit scene, its gestures and all animation logic. The scene's `stage` binding (0 = intact, 3 = burst) follows taps; the parent can also set it, and the scene plays forward to a higher stage or rewinds to a lower one (0 resets).

The scene is given a `GemDefinition` (an enum in `GemDefinition.swift`). Its `assetName` names the gem's scene in OpalContent, and the scene loads it with `Entity(named:in: opalContentBundle)`, with the material already bound. There's no runtime material code: textures and parameter tweaks are baked into each gem's scene. One rock serves every gem: each gem asset is guaranteed to fit the rock's standard cavity with its origin at the cavity centre, so only the gem is swapped.

In `RevealSceneView.swift`:

- **Scene graph:** a `RealityView` sets up a fixed `PerspectiveCamera`, a `DirectionalLight` and a `pivot` entity. The USDZ loads asynchronously from the bundle and is added under `pivot` (via the `spinner` entity used for the burst spin), offset by `-visualBounds.center` so it spins around its visual centre instead of its model origin. Load failures show up as red text over the view.
- **iOS camera:** on iOS, `content.camera = .virtual` is set (inside `#if os(iOS)`) so the scene uses the custom camera and not AR passthrough. Put any per-platform differences behind `#if os(...)` in the same way.
- **Rotation model:** only `pivot` rotates, and only about Y. `yaw` is the committed angle. During a drag the pivot's orientation is set directly from `dragStartYaw + translation * radiansPerPoint`. When the drag ends, a momentum term (from `predictedEndTranslation`, clamped to ±2.5 rad so the quaternion interpolation goes the short way round) is added, then animated with `pivot.move(..., .easeOut)`.
- **Interrupting a fling:** when a new drag starts, it calls `stopAllAnimations` and reads the real angle back from the quaternion (`currentYaw()`), so a mid-animation grab picks up exactly where the rock is. Keep this pattern if you change the gesture handling.
