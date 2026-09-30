//
//  RevealSceneView.swift
//  GemReveal
//

import SwiftUI
import RealityKit

/// The RealityKit scene: the rock and gem, tap to break open, drag to orbit.
struct RevealSceneView: View {
    /// The rock and the gem, already loaded (see `RevealAssets`). The scene adds clones, which
    /// share their meshes, textures and materials, so opening the reveal doesn't load anything.
    let rockModel: Entity
    let gemModel: Entity
    /// The colour of the gem's glow, linear RGB (see `GemDefinition.glowColor`).
    let glowColor: SIMD3<Float>
    /// How strongly the gem glows, scaling its light and halo (see `GemDefinition.glowStrength`).
    let glowStrength: Float
#if DEBUG
    /// Values from the debug tuning panel, applied to this scene's gem as they change.
    var debugTuning: GemTuning?
#endif
    /// Set if the models can't be set up; shown by the parent.
    @State private var loadError: String?
    /// 0 = intact, 3 = burst. Taps move it on a stage at a time. Setting it plays the stages in
    /// turn to a higher one, or rewinds to a lower one (0 resets the rock).
    @Binding var stage: Int

    // MARK: Entities

    /// Fixed, facing the rock. Only its position ever moves, for the crack shake.
    @State private var camera = PerspectiveCamera()

    /// Holds the scene's image-based light: the dark, top-lit environment the rock and gem reflect.
    @State private var imageBasedLight = Entity()
    
    /// Turned by dragging. Everything that rotates hangs off it.
    @State private var pivot = Entity()
    
    /// Between `pivot` and the rock; turned by the burst spin so it doesn't fight the drag.
    @State private var spinner = Entity()
    
    /// RockReveal.usdz as loaded. It owns the baked break-open clip.
    @State private var rock: Entity?
    
    /// The Shard_XX entities. The fade goes on these, not on an ancestor, so the gem stays opaque.
    @State private var shards: [Entity] = []
    
    /// The opacity last set on every shard. The fade is set frame by frame from playback position,
    /// not animated: RealityKit logs "Failed to set override status for bind point component member"
    /// for each shard whenever an animation bound to opacity ends or is torn down.
    @State private var shardOpacity: Float = 1
    
    /// The gem's clone in the scene.
    @State private var gem: Entity?
    
    /// The gem's inner light: a point light at the cavity centre. With no shadows, it lights only
    /// surfaces that face it, so the rock's outside stays dark and the crack faces and the shards'
    /// insides catch the glow as the rock opens.
    @State private var glowLight: PointLight?
    
    /// A soft camera-facing halo around the gem, faking bloom. The intact rock hides it; it shows
    /// through the cracks as they open.
    @State private var halo: ModelEntity?
    
    /// `glowColor` and `glowStrength`, mirrored into state so the per-frame update closure reads the
    /// current values: they change live in Debug builds, from the tuning panel.
    @State private var liveGlowColor: SIMD3<Float> = .one
    @State private var liveGlowStrength: Float = 1
    
    /// Faint dust drifting up from behind the gem once the rock has fully burst. In world space, not
    /// under the pivot, so it stays behind the gem as seen from the camera however the gem turns.
    @State private var dust = Entity()
    
    /// The gem's largest dimension, which sizes the dust's spawn volume. Zero until the gem is placed.
    @State private var gemSize: Float = 0
    
    /// Whether the dust is emitting, as last set on its component.
    @State private var isDustEmitting = false
    
    /// Plays the break sounds. Non-spatial, so they sound the same wherever the rock has turned.
    @State private var audioSource = Entity()
    
    /// One sound per stage, played as the stage starts (see `breakSounds()`).
    @State private var breakSounds: [AudioFileResource] = []

    /// Played as the break-open rewinds.
    @State private var rewindSound: AudioFileResource?
    
    /// Seconds the scene has run, for the glow's flicker.
    @State private var glowClock: TimeInterval = 0
    
    /// A world-space box that holds the gem at any yaw, for its anchor. See `turnProofBounds(of:)`.
    @State private var gemAnchorBounds: BoundingBox?
    
    /// The gem's on-screen bounds in this view, published as `GemAnchorPreferenceKey`.
    @State private var gemRect: CGRect?
    
    /// The intact rock's bounds in its own space, measured before any shard moves.
    @State private var intactRockBounds: BoundingBox?
    
    /// The intact rock's on-screen bounds in this view, published as `RockAnchorPreferenceKey`.
    @State private var rockRect: CGRect?
    
    /// This view's size, for projecting the gem onto it.
    @State private var viewSize: CGSize = .zero
    
    // MARK: Animation state
    
    /// The whole baked clip; reset scrubs it backwards.
    @State private var clip: AnimationResource?
    
    /// The clip trimmed to each stage.
    @State private var stageClips: [AnimationResource] = []
    
    /// 0 = intact, 3 = burst. What the rock has actually played, which trails `stage` while
    /// following a stage set by the parent.
    @State private var stagesPlayed = 0

    /// A stage set through the binding that the rock hasn't reached yet. Taps are ignored until it has.
    @State private var requestedStage: Int?

    /// Seconds left in the running stage, counted down on scene updates. The controller's
    /// `isPlaying` can't be used: with `.forwards` fill it keeps "playing" to hold the last frame.
    @State private var stageTimeRemaining: TimeInterval = 0
    
    /// Set while reset is playing the break-open backwards.
    @State private var rewind: Rewind?
    
    /// Seconds into the burst spin, or nil when it isn't running.
    @State private var spinElapsed: TimeInterval?
    
    /// The running camera shake, if any.
    @State private var activeShake: ActiveShake?
    
    /// The camera's current distance from the rock. It eases towards `targetCameraDistance`.
    @State private var cameraDistance = Self.wideCameraDistance
    
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    /// `accessibilityReduceMotion`, mirrored into state so the per-frame update closure reads the
    /// current value. With it on, there's no camera shake or burst spin, and the zoom cuts.
    @State private var reduceMotion = false

    /// Drives the rewind, the spin and the shake each frame. Kept alive for the life of the view.
    @State private var updateSubscription: EventSubscription?
    
    @State private var dragStartYaw: Float?
    
    // MARK: Tuning
    
    /// Shake amplitudes are in metres at the camera. Tap 2's shake must stay stronger than tap 1's
    private static let stages = [
        // loosened
        Stage(frames: 1...20, shake: Shake(amplitude: 0.003, duration: 0.4)),
        // more loosened (starts after the hold, so taps respond at once)
        Stage(frames: 40...70, shake: Shake(amplitude: 0.008, duration: 0.4)),
        // burst
        Stage(frames: 90...150, shake: Shake(amplitude: 0.004, duration: 2.0)),
    ]
    private static var burst: Stage { stages[2] }
    /// Let the shards fly clear for a moment before they start to fade.
    private static let fadeDelay = burst.length * 0.25
    /// Where the fade starts, in played time (see `Rewind.position`).
    private static let fadeStart = stages[0].length + stages[1].length + fadeDelay
    /// Longer than the burst, so the gem keeps turning after the shards have gone.
    private static let spinDuration: TimeInterval = 4
    private static let rewindSpeed = 3.0
    /// How fast the camera shake judders, in swings per second. Lower is slower and heavier.
    private static let shakeSpeed: Float = 5
    /// From the rock towards the camera: slightly above centre, looking at the rock.
    private static let cameraDirection = simd_normalize(SIMD3<Float>(0, 0.05, 0.75))
    /// Camera distance in metres while the rock is intact or loosened.
    private static let wideCameraDistance: Float = 0.95
    /// Camera distance from the second tap on, closing in for the burst.
    private static let closeCameraDistance: Float = 0.8
    /// How fast the camera eases between distances: the share of the gap closed per second, roughly.
    private static let zoomRate: Float = 5
    /// Above the rock's origin, in metres.
    private static let cavityCentre: SIMD3<Float> = [0, 0.135, 0]
    private static let radiansPerPoint: Float = 0.01
    /// The glow light at full strength, in lumens, for a gem of `glowStrength` 1. Its share of this
    /// is `glowLevel(atPlayed:)`.
    private static let glowIntensity: Float = 800
    /// How far the glow light reaches, in metres. A little past the shards at the end of the burst.
    private static let glowReach: Float = 0.5
    /// The halo's width across, as a multiple of the gem's largest dimension.
    private static let haloScale: Float = 3.5
    /// The halo's opacity at full glow, for a gem of `glowStrength` 1.
    private static let haloOpacity: Float = 0.7
    /// Dust particles a second, for a gem of `glowStrength` 1.
    private static let dustBirthRate: Float = 12
    /// How fast the dust rises, in metres a second.
    private static let dustSpeed: Float = 0.005
    /// The dust's particle size, in metres.
    private static let dustSize: Float = 0.002
    
    var body: some View {
        RealityView { content in
#if os(iOS)
            content.camera = .virtual
#endif
            setUpCamera()
            content.add(camera)
            content.add(Self.makeLight())
            if let environment = await Self.dramaticEnvironment() {
                imageBasedLight.components.set(ImageBasedLightComponent(source: .single(environment),
                                                                        intensityExponent: Self.environmentIntensityExponent))
                content.add(imageBasedLight)
            }
            content.add(pivot)
            content.add(dust)
            pivot.addChild(spinner)
            let haloTexture = await Self.haloTexture()
            audioSource.components.set(ChannelAudioComponent())
            content.add(audioSource)
            // Loaded before the models, so they're ready for the first tap
            breakSounds = await Self.breakSounds()
            rewindSound = await Self.sound(named: "rock_break_reversed.wav")
            
            updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
                stageTimeRemaining = max(0, stageTimeRemaining - event.deltaTime)
                stepRewind(by: event.deltaTime)
                stepFade()
                stepGlow(by: event.deltaTime)
                stepDust()
                followRequestedStage()
                stepSpin(by: event.deltaTime)
                stepZoom(by: event.deltaTime)
                stepShake(by: event.deltaTime)
#if !os(visionOS)
                updateAnchorRects()
#endif
            }
            
            do {
                try addModels(haloTexture: haloTexture)
            } catch {
                loadError = error.localizedDescription
            }
        }
        .onGeometryChange(for: CGSize.self, of: \.size) { viewSize = $0 }
        .anchorPreference(key: GemAnchorPreferenceKey.self, value: .rect(gemRect ?? .zero)) { anchor in
            gemRect == nil ? nil : anchor
        }
        .anchorPreference(key: RockAnchorPreferenceKey.self, value: .rect(rockRect ?? .zero)) { anchor in
            rockRect == nil ? nil : anchor
        }
        .gesture(orbitGesture)
        .onTapGesture(perform: tapRock)
        .accessibilityElement()
        .accessibilityLabel(stagesPlayed < Self.stages.count ? "Rock" : "Gem")
        .accessibilityValue(Self.accessibilityStageNames[min(stagesPlayed, Self.stages.count)])
        .accessibilityHint(stagesPlayed < Self.stages.count ? "Double-tap to crack it open. Swipe up or down to turn it." : "Swipe up or down to turn it.")
        .accessibilityAddTraits(stagesPlayed < Self.stages.count ? .isButton : [])
        .accessibilityAction(.default, tapRock)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: turn(by: .pi / 4)
            case .decrement: turn(by: -.pi / 4)
            @unknown default: break
            }
        }
        .onChange(of: accessibilityReduceMotion, initial: true) { _, newValue in
            reduceMotion = newValue
        }
        .onChange(of: glowColor, initial: true) { _, newValue in
            liveGlowColor = newValue
            updateGlowColor()
        }
        .onChange(of: glowStrength, initial: true) { _, newValue in
            liveGlowStrength = newValue
            updateHaloSize()
        }
#if DEBUG
        .onChange(of: debugTuning) { _, newValue in
            if let gem, let newValue {
                newValue.apply(to: gem)
            }
        }
#endif

        .onChange(of: stage) { _, newStage in
            // Taps write the stage the rock is already at, which this leaves alone
            let clamped = min(max(newStage, 0), Self.stages.count)
            requestedStage = clamped == stagesPlayed && rewind == nil ? nil : clamped
        }
    }
    
    /// What VoiceOver reads as the rock's value, by stages played.
    private static let accessibilityStageNames = ["Intact", "Cracked", "Breaking apart", "Burst open"]
    
    /// A tap on the rock, or VoiceOver's double-tap: plays the next stage.
    private func tapRock() {
        guard requestedStage == nil, stage > 0 else { return }
        advanceStage()
        stage = stagesPlayed
    }
    
    // MARK: - Scene setup
    
    private func setUpCamera() {
        camera.camera.fieldOfViewInDegrees = 45
        camera.look(at: .zero, from: cameraRestPosition, relativeTo: nil)
    }
    
    /// Where the camera sits when it isn't shaking. It returns here after a shake.
    private var cameraRestPosition: SIMD3<Float> {
        Self.cameraDirection * cameraDistance
    }
    
    /// Close in from the second tap, for the burst; wide before it.
    private var targetCameraDistance: Float {
        stagesPlayed >= 2 ? Self.closeCameraDistance : Self.wideCameraDistance
    }
    
    /// Eases the camera towards its target distance along its line of sight, so it keeps facing the
    /// rock. Rewinding below the second stage eases it back out.
    private func stepZoom(by deltaTime: TimeInterval) {
        let gap = targetCameraDistance - cameraDistance
        guard abs(gap) > 0.0001 else { return }
        cameraDistance += reduceMotion ? gap : gap * (1 - exp(-Self.zoomRate * Float(deltaTime)))
        if activeShake == nil {
            camera.position = cameraRestPosition
        }
    }
    
    /// Hard key light from overhead, a little to the front-left, cool grey-green like the image-based
    /// light, so the rock's top catches the light and its underside falls into shadow.
    /// Also used by `ShaderWarmUpView`, so the warm-up compiles the same pipeline as the reveal.
    static func makeLight() -> Entity {
        let light = DirectionalLight()
        light.light.intensity = 2500
        light.light.color = .init(red: 0.85, green: 0.95, blue: 0.9, alpha: 1)
        light.look(at: .zero, from: [-0.3, 1.0, 0.45], relativeTo: nil)
        return light
    }
    
    /// Lights every model in `entity` with the scene's image-based light.
    private func receiveImageBasedLight(in entity: Entity) {
        if entity.components.has(ModelComponent.self) {
            entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: imageBasedLight))
        }
        entity.children.forEach(receiveImageBasedLight(in:))
    }
    
    /// Brightens the environment's highlights: each step doubles them.
    private static let environmentIntensityExponent: Float = 1.5
    
    /// The environment for the image-based light, made once and shared by every reveal. Dramatic and
    /// sci-fi: near-black all round, a hard softbox straight overhead, a faint cool rim from behind,
    /// all tinted grey-green. Its skybox is never drawn; the view's background stays clear.
    private static var cachedEnvironment: EnvironmentResource?
    
    private static func dramaticEnvironment() async -> EnvironmentResource? {
        if let cachedEnvironment { return cachedEnvironment }
        guard let image = makeEnvironmentImage(),
              let cube = try? await TextureResource(cubeFromEquirectangular: image, quality: .normal,
                                                    options: .init(semantic: .hdrColor)),
              let environment = try? await EnvironmentResource(cube: cube, options: .init()) else { return nil }
        cachedEnvironment = environment
        return environment
    }
    
    /// The environment as a small equirectangular image (longitude across, latitude down).
    private static func makeEnvironmentImage(width: Int = 256, height: Int = 128) -> CGImage? {
        let tint = SIMD3<Double>(0.82, 0.95, 0.88)
        let overhead = simd_normalize(SIMD3<Double>(-0.15, 1, 0.1))
        let behind = simd_normalize(SIMD3<Double>(0, 0.25, -1))
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let latitude = Double.pi / 2 - Double(y) / Double(height - 1) * .pi    // +90° at the top
            for x in 0..<width {
                let longitude = Double(x) / Double(width) * 2 * .pi
                let direction = SIMD3(cos(latitude) * cos(longitude), sin(latitude), cos(latitude) * sin(longitude))
                let softbox = smoothstep(0.82, 0.93, simd_dot(direction, overhead))      // hard-edged, ~30° wide
                let rim = pow(max(simd_dot(direction, behind), 0), 6) * 0.12
                let ambient = 0.015
                let value = tint * min(ambient + softbox + rim, 1)
                let i = (y * width + x) * 4
                pixels[i] = UInt8(value.x * 255); pixels[i + 1] = UInt8(value.y * 255); pixels[i + 2] = UInt8(value.z * 255)
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
    
    private static func smoothstep(_ low: Double, _ high: Double, _ x: Double) -> Double {
        let t = min(max((x - low) / (high - low), 0), 1)
        return t * t * (3 - 2 * t)
    }
    
    private func addModels(haloTexture: TextureResource?) throws {
        let rock = rockModel.clone(recursive: true)
        receiveImageBasedLight(in: rock)
        // Centre on the pivot so the rock turns around its middle
        rock.position = -rock.visualBounds(relativeTo: nil).center
        spinner.addChild(rock)
        intactRockBounds = rock.visualBounds(relativeTo: rock)
        
        guard let rockReveal = rock.findEntity(named: "RockReveal") else {
            throw LoadError.missingEntity("RockReveal")
        }
        try setUpBreakOpen(rock, shardsIn: rockReveal)
        let gem = gemModel.clone(recursive: true)
        receiveImageBasedLight(in: gem)
        placeGem(gem, in: rockReveal)
        self.gem = gem
        gemAnchorBounds = turnProofBounds(of: gem)
        addGlow(around: gem, in: rockReveal, haloTexture: haloTexture)
    }
    
    /// A world-aligned box around `entity` that holds it however far the pivot and spinner turn it.
    ///
    /// Everything turns only about the pivot's Y axis, which runs up through the world origin. So the
    /// box reaches out as far as the entity's furthest corner from that axis, in X and Z, and spans its
    /// height in Y. Projected, it gives the same rect at every yaw, so its anchor stays put while the
    /// gem turns.
    private func turnProofBounds(of entity: Entity) -> BoundingBox {
        let corners = Self.corners(of: entity.visualBounds(relativeTo: entity)).map {
            entity.convert(position: $0, to: pivot)
        }
        let radius = corners.map { simd_length(SIMD2($0.x, $0.z)) }.max() ?? 0
        let ys = corners.map(\.y)
        return BoundingBox(min: [-radius, ys.min() ?? 0, -radius], max: [radius, ys.max() ?? 0, radius])
    }
    
    private static func corners(of bounds: BoundingBox) -> [SIMD3<Float>] {
        let (lo, hi) = (bounds.min, bounds.max)
        return [
            [lo.x, lo.y, lo.z], [hi.x, lo.y, lo.z], [lo.x, hi.y, lo.z], [hi.x, hi.y, lo.z],
            [lo.x, lo.y, hi.z], [hi.x, lo.y, hi.z], [lo.x, hi.y, hi.z], [hi.x, hi.y, hi.z],
        ]
    }
    
#if !os(visionOS)
    /// Projects the gem's and the intact rock's bounding boxes into the view.
    ///
    /// The gem's is fixed: its box holds the gem at any yaw and it ignores the camera shake, so
    /// content laid out around it stays still. The rock's follows the rock as it turns and shakes
    /// with the camera, and stays the intact rock's however far the shards have flown.
    ///
    /// Done by hand from the camera, not with the RealityView content's `project`: holding on to that
    /// content past the make closure keeps the first scene's renderer alive, and later scenes then
    /// render nothing.
    private func updateAnchorRects() {
        if let gemAnchorBounds, let rect = projectedRect(of: gemAnchorBounds, in: nil, ignoringShake: true),
           rect != gemRect {
            gemRect = rect
        }
        if let rock, let intactRockBounds, let rect = projectedRect(of: intactRockBounds, in: rock), rect != rockRect {
            rockRect = rect
        }
    }
    
    /// The view rect around a box given in `entity`'s space, or in world space if `entity` is nil.
    private func projectedRect(of bounds: BoundingBox, in entity: Entity?, ignoringShake: Bool = false) -> CGRect? {
        guard viewSize.width > 0, viewSize.height > 0 else { return nil }
        let corners = Self.corners(of: bounds)
        let points = corners.compactMap {
            project(entity?.convert(position: $0, to: nil) ?? $0, ignoringShake: ignoringShake)
        }
        guard points.count == corners.count,
              let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    /// A world-space point in view coordinates, or nil if it's behind the camera. The camera's field
    /// of view is vertical (the default), so its horizontal extent follows the view's aspect ratio.
    /// `ignoringShake` projects from the camera's rest position: the shake only moves the camera.
    /// The rest position still follows the zoom, so the rect grows as the camera closes in.
    private func project(_ point: SIMD3<Float>, ignoringShake: Bool = false) -> CGPoint? {
        var cameraToWorld = camera.transformMatrix(relativeTo: nil)
        if ignoringShake {
            cameraToWorld.columns.3 = SIMD4(cameraRestPosition, 1)
        }
        let p = cameraToWorld.inverse * SIMD4(point, 1)
        guard p.z < 0 else { return nil }
        let tanHalfFOV = tan(camera.camera.fieldOfViewInDegrees * .pi / 360)
        let aspect = Float(viewSize.width / viewSize.height)
        let x = p.x / -p.z / (tanHalfFOV * aspect)
        let y = p.y / -p.z / tanHalfFOV
        return CGPoint(x: CGFloat(x + 1) / 2 * viewSize.width, y: CGFloat(1 - y) / 2 * viewSize.height)
    }
#endif
    
    private func setUpBreakOpen(_ rock: Entity, shardsIn rockReveal: Entity) throws {
        guard let clip = Self.breakOpenClip(in: rock) else { throw LoadError.noAnimation }
        self.rock = rock
        self.clip = clip
        stageClips = try Self.stages.map { try $0.animation(from: clip) }
        
        // Direct children only: each Shard_XX Xform has a Shard_XX mesh child of the same name
        shards = rockReveal.children.filter { $0.name.hasPrefix("Shard_") }

        // Opened already burst: show the gem alone, as the burst leaves it. The shards are faded
        // out, not removed, so setting a lower stage can rewind them back in.
        let alreadyBurst = stage == Self.stages.count
        if alreadyBurst {
            stagesPlayed = Self.stages.count
            cameraDistance = Self.closeCameraDistance
            camera.position = cameraRestPosition
        }
        shardOpacity = alreadyBurst ? 0 : 1
        shards.forEach { $0.components.set(OpacityComponent(opacity: shardOpacity)) }
    }
    
    /// The break-open timeline, picked by duration (it runs to the end of the burst), not by index.
    ///
    /// RealityKit lists two clips for this file, "global scene animation" and "default subtree
    /// animation", with the same duration and both bound to "root". Until that's resolved, take the
    /// first that matches.
    private static func breakOpenClip(in rock: Entity) -> AnimationResource? {
        rock.availableAnimations.first { abs($0.definition.duration - burst.end) < 0.01 }
    }

    /// Parents the gem to "RockReveal" at the cavity centre, so it turns with the rock.
    ///
    /// "RockReveal" sits under the file's Z-up to Y-up conversion, so its own frame is Z-up.
    /// Placing relative to the pivot, which is always Y-up, keeps the numbers Y-up.
    private func placeGem(_ gem: Entity, in rockReveal: Entity) {
        let loadedOrientation = gem.orientation  // carries the gem file's own Y-up conversion
        rockReveal.addChild(gem)
        gem.setOrientation(loadedOrientation, relativeTo: pivot)
        gem.setPosition(rockReveal.position(relativeTo: pivot) + Self.cavityCentre, relativeTo: pivot)
    }
    
    // MARK: - Glow
    
    /// Puts the glow light and halo at the gem's centre, beside it under "RockReveal" so they turn
    /// and spin with it. They hang off an entity scaled to metres, whatever "RockReveal"'s scale.
    private func addGlow(around gem: Entity, in rockReveal: Entity, haloTexture: TextureResource?) {
        let glow = Entity()
        rockReveal.addChild(glow)
        glow.setScale(.one, relativeTo: pivot)
        glow.setPosition(gem.visualBounds(relativeTo: pivot).center, relativeTo: pivot)
        
        let light = PointLight()
        light.light.intensity = 0
        light.light.attenuationRadius = Self.glowReach
        glow.addChild(light)
        glowLight = light
        
        if let haloTexture {
            var material = UnlitMaterial()
            material.color = .init(texture: .init(haloTexture))
            material.blending = .transparent(opacity: .init(floatLiteral: 1))
            // Sized for a glow strength of 1; `updateHaloSize()` scales it
            let size = gem.visualBounds(relativeTo: pivot).extents.max() * Self.haloScale
            let halo = ModelEntity(mesh: .generatePlane(width: size, height: size), materials: [material])
            halo.components.set(BillboardComponent())
            halo.components.set(OpacityComponent(opacity: 0))
            glow.addChild(halo)
            self.halo = halo
        }
        // Behind the gem, as the camera sees it: the camera looks down -Z
        gemSize = gem.visualBounds(relativeTo: pivot).extents.max()
        dust.position = gem.visualBounds(relativeTo: nil).center + [0, 0, -gemSize * 0.5]
        
        updateGlowColor()
        updateHaloSize()
    }
    
    /// Tints the light and halo with `liveGlowColor`.
    private func updateGlowColor() {
        let color = PointLightComponent.Color(red: CGFloat(liveGlowColor.x), green: CGFloat(liveGlowColor.y),
                                              blue: CGFloat(liveGlowColor.z), alpha: 1)
        glowLight?.light.color = color
        if let halo, var material = halo.model?.materials.first as? UnlitMaterial {
            material.color.tint = color
            halo.model?.materials = [material]
        }
        updateDust()
    }
    
    /// Stronger glows spread wider, not just brighter.
    private func updateHaloSize() {
        halo?.scale = .init(repeating: liveGlowStrength.squareRoot())
        updateDust()
    }
    
    /// Sets up the dust from the glow: its colour, and as much of it as the glow is strong.
    /// Particles already in the air finish their drift when it stops.
    private func updateDust() {
        guard gemSize > 0 else { return }
        let color = ParticleEmitterComponent.ParticleEmitter.Color(
            red: CGFloat(liveGlowColor.x), green: CGFloat(liveGlowColor.y), blue: CGFloat(liveGlowColor.z), alpha: 0.35)
        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .sphere
        emitter.birthLocation = .volume
        emitter.emitterShapeSize = .init(repeating: gemSize * 0.6)
        emitter.emissionDirection = [0, 1, 0]
        emitter.speed = Self.dustSpeed
        emitter.speedVariation = Self.dustSpeed * 0.5
        emitter.isEmitting = isDustEmitting
        emitter.mainEmitter.birthRate = Self.dustBirthRate * liveGlowStrength
        emitter.mainEmitter.lifeSpan = 5
        emitter.mainEmitter.lifeSpanVariation = 1.5
        emitter.mainEmitter.size = Self.dustSize
        emitter.mainEmitter.sizeVariation = Self.dustSize * 0.5
        emitter.mainEmitter.color = .constant(.single(color))
        emitter.mainEmitter.opacityCurve = .gradualFadeInOut
        emitter.mainEmitter.blendMode = .additive
        emitter.mainEmitter.isLightingEnabled = false
        // A little wander, so it drifts like dust rather than rising in straight lines
        emitter.mainEmitter.noiseStrength = 0.01
        emitter.mainEmitter.noiseScale = 1
        emitter.mainEmitter.noiseAnimationSpeed = 0.2
        emitter.mainEmitter.dampingFactor = 0.5
        dust.components.set(emitter)
    }
    
    /// Emits dust once the burst has finished, and stops it on a rewind or with Reduce Motion.
    private func stepDust() {
        let shouldEmit = stagesPlayed == Self.stages.count && stageTimeRemaining == 0 && rewind == nil && !reduceMotion
        guard shouldEmit != isDustEmitting else { return }
        isDustEmitting = shouldEmit
        dust.components[ParticleEmitterComponent.self]?.isEmitting = shouldEmit
    }
    
    /// How strongly the gem glows, 0 to 1, at a point in played time. Dark while intact, it builds
    /// as the cracks open, flares as the rock bursts, then settles to a steady glow. Following
    /// played time means the rewind dims it back down too.
    private static func glowLevel(atPlayed position: TimeInterval) -> Float {
        let crack = stages[0].length, loosen = crack + stages[1].length, burstEnd = loosen + burst.length
        let keys: [(time: TimeInterval, level: Float)] = [
            (0, 0), (crack, 0.25), (loosen, 0.5), (loosen + 0.15, 1), (burstEnd, 0.6),
        ]
        guard let next = keys.firstIndex(where: { $0.time > position }) else { return keys.last!.level }
        guard next > 0 else { return keys[0].level }
        let (a, b) = (keys[next - 1], keys[next])
        let t = Float(smoothstep(a.time, b.time, position))
        return a.level + (b.level - a.level) * t
    }
    
    /// Sets the light and halo from the glow level, with a slow uneven flicker so it feels alive.
    private func stepGlow(by deltaTime: TimeInterval) {
        guard let glowLight else { return }
        glowClock += deltaTime
        let position = rewind?.position ?? (stagesPlayed == 0 ? 0 : playedTime())
        var level = Self.glowLevel(atPlayed: position)
        if !reduceMotion {
            let t = Float(glowClock)
            level *= 1 + 0.08 * (sin(t * 2.3) + sin(t * 3.7)) / 2
        }
        glowLight.light.intensity = level * liveGlowStrength * Self.glowIntensity
        halo?.components.set(OpacityComponent(opacity: min(level * liveGlowStrength * Self.haloOpacity, 1)))
    }
    
    /// The halo's texture, made once: white, fading out from the middle. The material tints it.
    private static var cachedHaloTexture: TextureResource?
    
    private static func haloTexture(size: Int = 128) async -> TextureResource? {
        if let cachedHaloTexture { return cachedHaloTexture }
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let dx = (Double(x) + 0.5) / Double(size) * 2 - 1
                let dy = (Double(y) + 0.5) / Double(size) * 2 - 1
                let falloff = max(1 - (dx * dx + dy * dy).squareRoot(), 0)
                let alpha = UInt8(pow(falloff, 2.5) * 255)    // premultiplied: white at this alpha
                let i = (y * size + x) * 4
                pixels[i] = alpha; pixels[i + 1] = alpha; pixels[i + 2] = alpha; pixels[i + 3] = alpha
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent),
              let texture = try? await TextureResource(image: image, options: .init(semantic: .color)) else { return nil }
        cachedHaloTexture = texture
        return texture
    }
    
    // MARK: - Sound
    
    /// Every sound loaded so far, by file name, shared by every reveal.
    private static var cachedSounds: [String: AudioFileResource] = [:]

    /// A sound from the app bundle, loaded once. Nil if it fails to load.
    private static func sound(named name: String) async -> AudioFileResource? {
        if let sound = cachedSounds[name] { return sound }
        guard let sound = try? await AudioFileResource(named: name) else { return nil }
        cachedSounds[name] = sound
        return sound
    }

    /// rock_break1 to 3, for the three stages. Empty if any fails to load, so the stages play
    /// silently rather than with a sound missing.
    private static func breakSounds() async -> [AudioFileResource] {
        var sounds: [AudioFileResource] = []
        for number in 1...stages.count {
            guard let sound = await sound(named: "rock_break\(number).wav") else { return [] }
            sounds.append(sound)
        }
        return sounds
    }
    
    // MARK: - Stages
    
    /// Plays the next stage, unless a stage or rewind is running or the rock has already burst.
    private func advanceStage() {
        guard let rock, rewind == nil, stageTimeRemaining == 0, stagesPlayed < stageClips.count else { return }
        let stage = Self.stages[stagesPlayed]
        rock.playAnimation(stageClips[stagesPlayed])
        if breakSounds.indices.contains(stagesPlayed) {
            audioSource.playAudio(breakSounds[stagesPlayed])
        }
        stageTimeRemaining = stage.length
        if let shake = stage.shake, !reduceMotion {
            activeShake = ActiveShake(shake: shake)
        }
        stagesPlayed += 1
        
        if stagesPlayed == stageClips.count {
            startBurst()
        }
    }
    
    /// Moves the rock a step towards `requestedStage`: plays the next stage once the running one
    /// has finished, or rewinds if the request is behind the rock.
    private func followRequestedStage() {
        guard let requestedStage, rock != nil, rewind == nil else { return }
        if requestedStage > stagesPlayed {
            if stageTimeRemaining == 0 { advanceStage() }
        } else if requestedStage < stagesPlayed {
            startRewind(to: requestedStage)
        } else {
            self.requestedStage = nil
        }
    }

    private func startBurst() {
        if !reduceMotion {
            spinElapsed = 0
        }
    }
    
    /// Shard opacity at a point in played time: 1 until `fadeStart`, then easing in to 0 by the end
    /// of the burst.
    private static func shardOpacity(atPlayed position: TimeInterval) -> Float {
        let progress = min(max((position - fadeStart) / (burst.length - fadeDelay), 0), 1)
        return Float(1 - progress * progress)
    }
    
    /// Fades the shards while the burst plays forwards (the rewind sets them as it scrubs).
    private func stepFade() {
        guard rewind == nil, stagesPlayed == Self.stages.count else { return }
        setShardOpacity(Self.shardOpacity(atPlayed: playedTime()))
    }
    
    private func setShardOpacity(_ opacity: Float) {
        guard opacity != shardOpacity else { return }
        shardOpacity = opacity
        shards.forEach { $0.components.set(OpacityComponent(opacity: opacity)) }
    }
    
    /// One full turn of the rock and gem, quartic ease-out: full speed with the burst, then a long
    /// settle. Driven per frame because a 360 degree turn starts and ends on the same rotation, so
    /// an interpolated transform animation wouldn't move.
    private func stepSpin(by deltaTime: TimeInterval) {
        guard let elapsed = spinElapsed else { return }
        let t = min(elapsed + deltaTime, Self.spinDuration)
        let progress = Float(t / Self.spinDuration)
        let eased = 1 - pow(1 - progress, 4)
        spinner.orientation = yRotation(eased * 2 * .pi)
        spinElapsed = t < Self.spinDuration ? t : nil
    }

    private struct ActiveShake {
        let shake: Shake
        var elapsed: TimeInterval = 0
    }

    /// Judders the camera in its own right/up plane, fading out fast. Only the position moves: the
    /// camera keeps facing the rock and the light is fixed, so the lighting doesn't change.
    private func stepShake(by deltaTime: TimeInterval) {
        guard var active = activeShake else { return }
        active.elapsed += deltaTime
        guard active.elapsed < active.shake.duration else { return endShake() }
        activeShake = active

        let t = Float(active.elapsed)
        let decay = pow(1 - t / Float(active.shake.duration), 2)
        // Two unrelated multiples of the speed per axis, so the judder doesn't look periodic
        let phase = 2 * .pi * Self.shakeSpeed * t
        let x = (sin(phase) + sin(phase * 1.55)) / 2
        let y = (sin(phase * 1.18) + sin(phase * 1.73)) / 2
        let offset = camera.orientation.act([x, y, 0]) * active.shake.amplitude * decay
        camera.position = cameraRestPosition + offset
    }

    private func endShake() {
        activeShake = nil
        camera.position = cameraRestPosition
    }

    // MARK: - Reset
    
    /// Paused controllers that the rewind scrubs back to 0, one frame at a time.
    private struct Rewind {
        let clip: AnimationPlaybackController
        /// Position in played time: the stage windows laid end to end, holds left out.
        var position: TimeInterval
        /// Where the rewind stops, in played time: the end of the stage it rewinds to.
        let end: TimeInterval
    }

    /// Plays the break-open backwards to the end of `target` (0 is the intact rock), fading the
    /// shards back in on the way.
    ///
    /// Restoring transforms directly doesn't stick: the stop only applies on the next animation
    /// update, where the stopped clip writes its held last frame once more. So the clip is held
    /// paused instead and scrubbed back, where it stays, owning the pose, until the next stage
    /// replaces it. Opacity isn't animated, so the scrub sets it directly.
    private func startRewind(to target: Int) {
        guard let rock, let clip, rewind == nil, target < stagesPlayed else { return }
        let position = playedTime()

        rock.stopAllAnimations(recursive: true)
        endShake()
        stageTimeRemaining = 0
        stagesPlayed = target
        // Cut off any break sound still ringing, so the two don't overlap
        audioSource.stopAllAudio()
        if let rewindSound {
            audioSource.playAudio(rewindSound)
        }

        let clipController = rock.playAnimation(clip, startsPaused: true)
        let rewind = Rewind(clip: clipController, position: position, end: Self.playedLength(ofStages: target))
        self.rewind = rewind
        scrub(rewind)
    }

    /// How far playback has got, in played time.
    private func playedTime() -> TimeInterval {
        let current = stagesPlayed - 1
        return Self.playedLength(ofStages: current) + Self.stages[current].length - stageTimeRemaining
    }

    /// The played time of the first `count` stages.
    private static func playedLength(ofStages count: Int) -> TimeInterval {
        stages.prefix(count).reduce(0) { $0 + $1.length }
    }
    
    private func stepRewind(by deltaTime: TimeInterval) {
        guard var rewind else { return }
        rewind.position = max(rewind.end, rewind.position - deltaTime * Self.rewindSpeed)
        self.rewind = rewind.position > rewind.end ? rewind : nil
        scrub(rewind)
    }
    
    private func scrub(_ rewind: Rewind) {
        rewind.clip.time = Self.clipTime(atPlayed: rewind.position)
        setShardOpacity(Self.shardOpacity(atPlayed: rewind.position))
    }
    
    /// Maps played time to a time in the full clip.
    private static func clipTime(atPlayed position: TimeInterval) -> TimeInterval {
        var remaining = position
        for stage in stages {
            if remaining <= stage.length { return stage.start + remaining }
            remaining -= stage.length
        }
        return burst.end
    }
    
    // MARK: - Drag to orbit
    
    private var orbitGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if dragStartYaw == nil {
                    // Stop any fling in progress and pick up from where the rock actually is
                    pivot.stopAllAnimations(recursive: false)
                    dragStartYaw = currentYaw()
                }
                pivot.orientation = yRotation(dragYaw(value.translation.width))
            }
            .onEnded { value in
                // Momentum: carry on in the fling direction, then ease out.
                // Capped under 180 degrees so the rotation takes the short way round.
                let fling = Float(value.predictedEndTranslation.width - value.translation.width) * Self.radiansPerPoint
                var target = pivot.transform
                target.rotation = yRotation(dragYaw(value.translation.width) + min(max(fling, -2.5), 2.5))
                dragStartYaw = nil
                pivot.move(to: target, relativeTo: pivot.parent, duration: 0.6, timingFunction: .easeOut)
            }
    }
    
    /// Turns the rock by `angle` radians, for VoiceOver's adjustable action. Picks up from where a
    /// fling has got to, like a drag does.
    private func turn(by angle: Float) {
        pivot.stopAllAnimations(recursive: false)
        var target = pivot.transform
        target.rotation = yRotation(currentYaw() + angle)
        if reduceMotion {
            pivot.transform = target
        } else {
            pivot.move(to: target, relativeTo: pivot.parent, duration: 0.4, timingFunction: .easeOut)
        }
    }
    
    private func dragYaw(_ translation: CGFloat) -> Float {
        (dragStartYaw ?? currentYaw()) + Float(translation) * Self.radiansPerPoint
    }
    
    /// The pivot's current yaw, read back from its orientation.
    private func currentYaw() -> Float {
        let q = pivot.orientation
        return q.axis.y >= 0 ? q.angle : -q.angle
    }
    
    private func yRotation(_ angle: Float) -> simd_quatf {
        simd_quatf(angle: angle, axis: [0, 1, 0])
    }
}

/// The gem's on-screen bounds in `RevealSceneView`, as an anchor, for laying out content above and
/// below it. Nil until the gem has been placed, and on visionOS, which has no projection.
struct GemAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// The intact rock's on-screen bounds in `RevealSceneView`, as an anchor. It keeps the intact rock's
/// frame as the rock breaks and after the burst. Nil until the rock has been placed, and on visionOS.
struct RockAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// A window of the rock's baked clip, given in Blender frames (60 fps, numbered from 1).
private struct Stage {
    let start: TimeInterval
    let end: TimeInterval
    /// Camera shake when the stage starts, if any.
    let shake: Shake?

    init(frames: ClosedRange<Int>, shake: Shake? = nil) {
        start = TimeInterval(frames.lowerBound - 1) / 60
        end = TimeInterval(frames.upperBound - 1) / 60
        self.shake = shake
    }
    
    var length: TimeInterval { end - start }
    
    /// This window of the clip. `.forwards` holds the last frame once it finishes.
    func animation(from clip: AnimationResource) throws -> AnimationResource {
        let view = AnimationView(source: clip.definition, fillMode: .forwards, trimStart: start, trimEnd: end)
        return try AnimationResource.generate(with: view)
    }
}

/// A camera judder that fades out over `duration`.
private struct Shake {
    /// Peak offset of the camera, in metres.
    let amplitude: Float
    let duration: TimeInterval
}

enum LoadError: LocalizedError {
    case missingFile(String)
    case missingEntity(String)
    case noAnimation
    
    var errorDescription: String? {
        switch self {
        case .missingFile(let name): "\(name) not found in bundle"
        case .missingEntity(let name): "'\(name)' not found in RockReveal.usdz"
        case .noAnimation: "RockReveal.usdz has no break-open animation of the expected length"
        }
    }
}
