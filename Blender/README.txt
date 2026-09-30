GemReveal Blender source
========================
Master file: GemReveal_master.blend  (textures packed, self-contained)

Inside the .blend:
- Shards collection: RockReveal (empty, root) > Shard_00..19, animated frames 1-150 @ 60fps
- Gem collection (each origin at its bounds centre, placed at cavity centre 0,0,0.135):
  Gem (opal), Gem_cherry_quartz, Gem_amazonite, Gem_blue_quartz, Gem_jade, Gem_amethyst.
  The new gems carry procedural materials (CherryQuartz, Amazonite, BlueQuartz, Jade, Amethyst)
  that bake_gem_textures turns into their base/emission PNGs.
- Remodel collection (excluded): RockNew, the solid outer rock the shards are cut from: the old Rock
  remeshed, given outward-only relief (lumps, tilted strata, crags) and planar chips no deeper than
  the old surface, so the hollow (InnerBody) and every gem's fit are unchanged. Shards are its
  Voronoi cells (same seeds and origins as before) minus InnerBody.
- Shard materials: RockOuter / RockInner both use one shared UV atlas (Rock_BaseColor, Rock_Roughness,
  Rock_Normal, 2K, packed). Each material keeps its disconnected bake source graph (Poly Haven
  rock_boulder_dry / dark_rock box-projected, graded, AO, bump + grain) for rebaking.
- Preview collection (excluded): camera and key light framed like the app, for look-dev renders.
- Backup collection (hidden): Rock (original solid rock), InnerBody (6mm shell cutter),
  CavityCutter2 (gem cavity cutter, gem + 3.2mm), CavityCutter (old)
- Text: gemreveal_state.json  (seeds, per-shard animation plan, frames)
- Text: gemreveal_tools.py    (tag_materials, key_all, check_collisions, gem_visibility, export_gated,
                                 check_gem_fit, bake_gem_textures, export_gem)

To resume: open the master file, then in Blender's Python console:
  exec(bpy.data.texts["gemreveal_tools.py"].as_string())
  export_gated()     # exports RockReveal.usdz, runs the dark-face ray gate, copies into the Xcode project only if it passes
  gem = bpy.data.objects["Gem_jade"]
  check_gem_fit(gem); check_collisions(gem)   # >= 2 mm inside InnerBody; no shard touches it
  bake_gem_textures(gem, "jade_01")           # writes jade_01_base.png / jade_01_emission.png into OpalContent
  export_gem(gem, "jade_01")                  # exports jade_01_model.usdz if it fits (default: the opal as opal_01)
  (pass deliver=False to export_gated/export_gem for a dry run that stops in Blender/_staging/)

Delivered assets (paths relative to the repo root, resolved from the .blend's location):
  GemReveal/usdz/RockReveal.usdz
  Packages/OpalContent/Sources/OpalContent/OpalContent.rkassets/<asset>_model.usdz, <asset>_base.png,
  <asset>_emission.png for opal_01, cherry_quartz_01, amazonite_01, blue_quartz_01, jade_01, amethyst_01
Numbered .blend files in this folder are history snapshots; the master is the current state.
