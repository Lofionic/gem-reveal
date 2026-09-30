"""GemReveal pipeline tools. Run inside Blender:  exec(bpy.data.texts["gemreveal_tools.py"].as_string())
Then use:  tag_materials(), key_all(), check_collisions(gem), gem_visibility(frame, gem), export_gated(),
           check_gem_fit(gem), bake_gem_textures(gem, asset_id), export_gem(gem, asset_id)
Gems are passed as objects (default: the opal, "Gem"); asset_id names its files in OpalContent, e.g. "jade_01".
All state comes from the text block gemreveal_state.json."""
import bpy, bmesh, json, math, random, os, shutil, itertools
from mathutils import Vector, Euler
from mathutils.bvhtree import BVHTree

STATE = json.loads(bpy.data.texts["gemreveal_state.json"].as_string())
C = Vector(STATE["cavity_centre"])
SEEDS = [Vector(s) for s in STATE["surface_seeds"]]
# All paths are relative to this .blend, which lives in <repo>/Blender/
if not bpy.data.filepath: raise RuntimeError("Save or open GemReveal_master.blend before running the tools")
OUT_DIR = os.path.dirname(bpy.path.abspath(bpy.data.filepath))   # <repo>/Blender
STAGE_DIR = os.path.join(OUT_DIR, "_staging")
REPO = os.path.dirname(OUT_DIR)
PROJECT_ASSET = os.path.join(REPO, "GemReveal", "usdz", "RockReveal.usdz")
# Each gem's scene in OpalContent (<asset_id>.usda) references <asset_id>_model.usdz for its geometry
# and <asset_id>_base.png / <asset_id>_emission.png for its textures.
GEM_ASSET_DIR = os.path.join(REPO, "Packages", "OpalContent", "Sources", "OpalContent", "OpalContent.rkassets")

def gem_asset_path(asset_id, suffix="_model.usdz"):
    return os.path.join(GEM_ASSET_DIR, asset_id + suffix)

def shards():
    return [bpy.data.objects[f"Shard_{i:02d}"] for i in range(20)]

def _wbvh(ob):
    # Parentless helpers (cutters) may live in an excluded collection, whose matrix_world is not
    # refreshed after a file load. matrix_basis is always the stored transform; use it when unparented.
    M = ob.matrix_basis if ob.parent is None else ob.matrix_world
    b = bmesh.new(); b.from_mesh(ob.data); b.transform(M)
    t = BVHTree.FromBMesh(b); b.free(); return t

def tag_materials(tol=1e-4):
    """Dark (RockInner) ONLY if a face lies on a cut plane or the hollow/gem cavity. Everything else RockOuter."""
    bpy.context.scene.frame_set(1)
    bvh_in = _wbvh(bpy.data.objects["InnerBody"])   # standard hollow; no gem-specific cutter
    for i, ob in enumerate(shards()):
        me, mw = ob.data, ob.matrix_world; r3 = mw.to_3x3(); s = SEEDS[i]
        planes = [((s + o) / 2, (o - s).normalized()) for j, o in enumerate(SEEDS) if j != i]
        names = [m.name for m in me.materials]; oi, ii = names.index("RockOuter"), names.index("RockInner")
        for p in me.polygons:
            vs = [mw @ me.vertices[v].co for v in p.vertices]; n = (r3 @ p.normal).normalized()
            on_cut = any(all(abs((v - c).dot(pn)) < tol for v in vs) and abs(n.dot(pn)) > 0.99 for c, pn in planes)
            on_cav = all(bvh_in.find_nearest(v)[3] < tol for v in vs)
            p.material_index = ii if (on_cut or on_cav) else oi
        me.update()

def key_shard(i):
    ob = shards()[i]; s = STATE["shards"][ob.name]
    rest = Vector(s["rest"]); rad = (rest - C).normalized(); t = s["tilt_factor"]
    r1 = Vector(s["tap1_rot"]) * t; r2 = Vector(s["tap2_rot"]) * t
    ob.animation_data_clear()
    keys = [(1, rest, Vector()), (20, rest + rad * s["tap1_dist"], r1), (40, rest + rad * s["tap1_dist"], r1),
            (70, rest + rad * s["tap2_dist"], r2), (90, rest + rad * s["tap2_dist"], r2),
            (150, rest + Vector(s["burst_dir"]) * s["burst_dist"], Vector(s["burst_rot"]))]
    for f, loc, rot in keys:
        ob.location = loc; ob.rotation_euler = Euler(rot)
        ob.keyframe_insert("location", frame=f); ob.keyframe_insert("rotation_euler", frame=f)
    for layer in ob.animation_data.action.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                for fc in cb.fcurves:
                    for kp in fc.keyframe_points:
                        if round(kp.co[0]) in (40, 90): kp.interpolation = 'EXPO'; kp.easing = 'EASE_OUT'
                    fc.update()

def key_all():
    for i in range(20): key_shard(i)

def check_collisions(gem_obj=None):
    """Shard-vs-shard (frames 2-150) and shard-vs-gem (1-150). Returns (pairs, gem_hits, closest_gem_mm)."""
    scene = bpy.context.scene; sh = shards(); gem = gem_obj or bpy.data.objects["Gem"]
    bvh_gem = _wbvh(gem); pairs, gem_hits, closest = {}, 0, 1.0
    for f in range(1, 151):
        scene.frame_set(f); data = []
        for s in sh:
            b = bmesh.new(); b.from_mesh(s.data); b.transform(s.matrix_world)
            t = BVHTree.FromBMesh(b); pts = [v.co.copy() for v in b.verts]; b.free()
            c = sum(pts, Vector()) / len(pts); data.append((t, pts, c, max((q - c).length for q in pts)))
        for t, pts, c, r in data:
            if bvh_gem.overlap(t): gem_hits += 1
            closest = min(closest, min(bvh_gem.find_nearest(q)[3] for q in pts))
        if f == 1: continue
        for i, j in itertools.combinations(range(20), 2):
            ti, _, ci, ri = data[i]; tj, _, cj, rj = data[j]
            if (ci - cj).length <= ri + rj and ti.overlap(tj): pairs.setdefault((i, j), []).append(f)
    scene.frame_set(1)
    return pairs, gem_hits, closest * 1000

def gem_visibility(frame, gem_obj=None, n=400):
    """% of gem sample points visible from 168 views at 0.75 m."""
    scene = bpy.context.scene; scene.frame_set(frame)
    bm = bmesh.new()
    for s in shards():
        b = bmesh.new(); b.from_mesh(s.data); b.transform(s.matrix_world)
        tmp = bpy.data.meshes.new("tmp"); b.to_mesh(tmp); b.free(); bm.from_mesh(tmp); bpy.data.meshes.remove(tmp)
    bvh = BVHTree.FromBMesh(bm); bm.free()
    gem = gem_obj or bpy.data.objects["Gem"]; random.seed(1)
    pts = random.sample([gem.matrix_world @ v.co for v in gem.data.vertices], n)
    per = []
    for el in (-30, -15, 0, 15, 30, 45, 60):
        for az in range(0, 360, 15):
            e, a = math.radians(el), math.radians(az)
            cam = Vector((0, 0, 0.14)) + 0.75 * Vector((math.cos(e)*math.cos(a), math.cos(e)*math.sin(a), math.sin(e)))
            per.append(sum(1 for p in pts if bvh.ray_cast(cam, (p - cam).normalized(), (p - cam).length - 1e-4)[0] is None) / n)
    scene.frame_set(1)
    return 100 * sum(per) / len(per), 100 * max(per)

def usd_marker_gate(path, n_rays=100000):
    """Reload an exported usdz and ray-test it: any ray from outside hitting a non-RockOuter face fails."""
    from pxr import Usd, UsdGeom, UsdShade
    st = Usd.Stage.Open(path); xc = UsdGeom.XformCache(Usd.TimeCode(1))
    verts, polys, mats = [], [], []
    for prim in st.Traverse():
        if not prim.IsA(UsdGeom.Mesh): continue
        mesh = UsdGeom.Mesh(prim); M = xc.GetLocalToWorldTransform(prim)
        pts = mesh.GetPointsAttr().Get(Usd.TimeCode(1))
        counts = mesh.GetFaceVertexCountsAttr().Get(); idx = mesh.GetFaceVertexIndicesAttr().Get()
        subs = UsdGeom.Subset.GetAllGeomSubsets(UsdGeom.Imageable(prim)); fm = {}
        for s in subs:
            m = UsdShade.MaterialBindingAPI(s.GetPrim()).GetDirectBinding().GetMaterial().GetPrim().GetName()
            for fi in s.GetIndicesAttr().Get(): fm[fi] = m
        if not subs:
            m = UsdShade.MaterialBindingAPI(prim).GetDirectBinding().GetMaterial()
            dflt = m.GetPrim().GetName() if m else "?"
        base = len(verts); verts += [Vector(M.Transform(p)) for p in pts]; k = 0
        for fi, c in enumerate(counts):
            polys.append([base + idx[k + j] for j in range(c)]); k += c
            mats.append(fm.get(fi, "?") if subs else dflt)
    bvh = BVHTree.FromPolygons(verts, polys); random.seed(9)
    centre = Vector((0, 0.14, 0)); hits = dark = 0
    for _ in range(n_rays):
        d = Vector((random.gauss(0, 1), random.gauss(0, 1), random.gauss(0, 1))).normalized(); o = centre + d * 0.6
        t = centre + Vector((random.uniform(-.09, .09), random.uniform(-.14, .14), random.uniform(-.085, .085)))
        loc, n, fi, dist = bvh.ray_cast(o, (t - o).normalized())
        if loc is None: continue
        hits += 1; dark += mats[fi] != "RockOuter"
    return hits, dark, sum(1 for m in mats if m == "?")

def _inner_layers(path):
    import zipfile
    with zipfile.ZipFile(path) as z:
        return [i.filename for i in z.infolist() if i.filename.endswith((".usdc", ".usda"))]

def export_gated(deliver=True):
    """Export RockReveal.usdz to staging, run the marker gate on the file, copy into the Xcode project only if it passes.
    deliver=False is a dry run: the checked file stays in Blender/_staging/."""
    scene = bpy.context.scene; scene.frame_set(1)
    # Stage under the FINAL filename (in a separate folder): the usdc layer inside a usdz is named
    # after the file it was exported as, and the app should only ever see "RockReveal.usdc".
    os.makedirs(STAGE_DIR, exist_ok=True)
    staging = os.path.join(STAGE_DIR, os.path.basename(PROJECT_ASSET))
    bpy.ops.object.select_all(action='DESELECT')
    for ob in bpy.data.collections["Shards"].objects: ob.select_set(True)
    bpy.context.view_layer.objects.active = bpy.data.objects["RockReveal"]
    bpy.ops.wm.usd_export(filepath=staging, check_existing=False, selected_objects_only=True,
        export_animation=True, export_materials=True, export_cameras=False, export_lights=False,
        convert_orientation=True, export_global_up_selection='Y', export_global_forward_selection='NEGATIVE_Z',
        convert_scene_units='METERS')
    bpy.ops.object.select_all(action='DESELECT')
    hits, dark, unknown = usd_marker_gate(staging)
    if dark or unknown:
        return {"passed": False, "dark_hits": dark, "unmaterialed_faces": unknown}
    inner = _inner_layers(staging)
    if inner != ["RockReveal.usdc"]:
        return {"passed": False, "reason": f"unexpected package layers {inner}"}
    if not deliver:
        return {"passed": True, "rays": hits, "staged": staging}
    final = os.path.join(OUT_DIR, "RockReveal.usdz"); shutil.move(staging, final); shutil.copy2(final, PROJECT_ASSET)
    return {"passed": True, "rays": hits, "delivered": PROJECT_ASSET}


def check_gem_fit(gem_obj=None):
    """Standard envelope rule: gem entirely inside InnerBody, >= min_clearance_m from it. Returns (ok, min_clearance_mm)."""
    gem_obj = gem_obj or bpy.data.objects["Gem"]
    bvh = _wbvh(bpy.data.objects["InnerBody"])
    M = gem_obj.matrix_basis if gem_obj.parent is None else gem_obj.matrix_world
    def inside(p):
        hits, o, d = 0, p.copy(), Vector((1, 0.0001, 0.0002)).normalized()
        while True:
            loc, n, i, dist = bvh.ray_cast(o, d)
            if loc is None: break
            hits += 1; o = loc + d * 1e-5
        return hits % 2 == 1
    mc = 1.0
    for v in gem_obj.data.vertices:
        p = M @ v.co
        if not inside(p): return False, -1.0
        mc = min(mc, bvh.find_nearest(p)[3])
    return mc >= STATE["gem_envelope"]["min_clearance_m"], mc * 1000

def bake_gem_textures(gem_obj, asset_id, size=1024):
    """Bakes the gem material's Base Color and Emission Color inputs (procedural nodes and all) into
    <asset_id>_base.png and <asset_id>_emission.png in OpalContent, through the gem's active UV map.
    The images stay packed in the .blend as <asset_id>_base / <asset_id>_emission."""
    scene = bpy.context.scene; mat = gem_obj.active_material; nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL" and n.is_active_output)
    surface_link = out.inputs["Surface"].links[0].from_socket
    saved_engine = scene.render.engine
    try:
        scene.render.engine = "CYCLES"
    except TypeError:
        pass
    scene.cycles.samples = 4
    bpy.ops.object.select_all(action='DESELECT'); gem_obj.select_set(True)
    bpy.context.view_layer.objects.active = gem_obj
    emit = nt.nodes.new("ShaderNodeEmission"); img_node = nt.nodes.new("ShaderNodeTexImage")
    results = {}
    try:
        for suffix, socket_name in (("_base", "Base Color"), ("_emission", "Emission Color")):
            name = asset_id + suffix
            img = bpy.data.images.get(name) or bpy.data.images.new(name, size, size)
            img.scale(size, size)
            img_node.image = img; nt.nodes.active = img_node
            src = bsdf.inputs[socket_name]
            # Bake what feeds the socket, or its flat value, as pure emission
            if src.links:
                nt.links.new(src.links[0].from_socket, emit.inputs["Color"])
            else:
                for l in list(emit.inputs["Color"].links): nt.links.remove(l)
                emit.inputs["Color"].default_value = src.default_value
            nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
            bpy.ops.object.bake(type='EMIT', margin=8, use_clear=True)
            path = gem_asset_path(asset_id, suffix + ".png")
            img.filepath_raw = path; img.file_format = 'PNG'; img.save()
            img.pack()
            results[suffix] = path
    finally:
        nt.links.new(surface_link, out.inputs["Surface"])
        nt.nodes.remove(emit); nt.nodes.remove(img_node)
        scene.render.engine = saved_engine
        gem_obj.select_set(False)
    return results

def export_gem(gem_obj=None, asset_id="opal_01", deliver=True):
    """Gated: refuses gems outside the standard envelope. Exports with origin at the gem centre to
    OpalContent's <asset_id>_model.usdz. deliver=False is a dry run: the checked file stays in Blender/_staging/."""
    gem_obj = gem_obj or bpy.data.objects["Gem"]
    ok, mc = check_gem_fit(gem_obj)
    if not ok:
        return {"passed": False, "reason": f"gem outside envelope (min clearance {mc:.2f} mm)"}
    # Stage under the final filename, as export_gated does: the inner layer takes the file's name
    os.makedirs(STAGE_DIR, exist_ok=True)
    dest = gem_asset_path(asset_id); name = os.path.basename(dest); staging = os.path.join(STAGE_DIR, name)
    # A gem hidden in the viewport can't be selected, so it would export as an empty file
    saved = gem_obj.matrix_basis.copy(); was_hidden = gem_obj.hide_get(); gem_obj.location = (0, 0, 0)
    gem_obj.hide_set(False)
    bpy.ops.object.select_all(action='DESELECT'); gem_obj.select_set(True)
    bpy.context.view_layer.objects.active = gem_obj
    bpy.ops.wm.usd_export(filepath=staging, check_existing=False, selected_objects_only=True,
        export_animation=False, export_materials=True, generate_preview_surface=True, export_textures_mode='NEW',
        export_cameras=False, export_lights=False, convert_orientation=True,
        export_global_up_selection='Y', export_global_forward_selection='NEGATIVE_Z', convert_scene_units='METERS')
    gem_obj.matrix_basis = saved; gem_obj.select_set(False); gem_obj.hide_set(was_hidden)
    inner = _inner_layers(staging)
    if inner != [os.path.splitext(name)[0] + ".usdc"]:
        return {"passed": False, "reason": f"unexpected package layers {inner}"}
    from pxr import Usd, UsdGeom
    stage = Usd.Stage.Open(staging)   # keep the stage alive while traversing it
    meshes = [p for p in stage.Traverse() if p.IsA(UsdGeom.Mesh)]
    if len(meshes) != 1:
        return {"passed": False, "reason": f"expected one mesh in the export, found {len(meshes)}"}
    if not deliver:
        return {"passed": True, "min_clearance_mm": round(mc, 2), "staged": staging}
    final = os.path.join(OUT_DIR, name); shutil.move(staging, final); shutil.copy2(final, dest)
    return {"passed": True, "min_clearance_mm": round(mc, 2), "delivered": dest}
