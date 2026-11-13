# Character Asset Report — Rigged Human (Phase 2)

**Status: integrated and verified locally** (import, 50-level gate, 8/8 smoke,
39/39 touch E2E, animation state machine 5/5 states). CI gates re-run on push.

## Source and license

- **Model:** Quaternius "Universal Animated Men (Feb 2019)" — `Male_Casual`
  variant, downloaded from quaternius.com's public Google Drive pack.
- **License:** **CC0 1.0** (https://creativecommons.org/publicdomain/zero/1.0/)
  — confirmed on the pack page. Fully redistributable in this repo and APK.
- Honest scope note: this is a clean, rigged, clothed, realistic-proportioned
  human with original PBR micro-detail materials — a large upgrade from the
  box robot. It is NOT a photorealistic scanned human; truly photorealistic
  humans (Mixamo/Renderpeople/Fab) cannot be legally redistributed in this
  public repository. The integration (one GLB + AnimationTree state machine)
  is designed so a licensed photoreal model can replace this GLB later with
  zero gameplay code changes.

## Files

| File | Role | Size |
|---|---|---|
| `assets/characters/human/human_male.glb` | character: mesh (6 prims / 3,956 verts), 31-joint skeleton, 11 animations, 10 embedded PBR textures | ~1.28 MB |
| `assets/characters/human/human_male.glb.import` | **tuned import settings** — must stay committed | tiny |
| `assets/textures/character/` | original micro-detail + per-material tinted albedos (generators checked in) | ~130 KB |
| `scripts-dev/gen_textures_human.py` | deterministic texture generator (pure numpy+zlib) | — |
| `scripts-dev/export_human_glb.py` | Blender headless export pipeline (documented, reproducible) | — |
| `scripts/game/human_character.gd` | AnimationTree state machine; public API identical to the old robot | — |

## The GLB

- **Rig:** `HumanArmature` → 31 joints, skinned.
- **Animations (11):** Idle, Walk, Run, Jump, RunningJump, Clapping (=victory),
  Death (=electrocution), Standing, Sitting, Punch, SwordSlash.
  Missing dedicated fall/land clips are covered by the jump arcs + procedural
  air/land handling (documented deviation from the 10-clip wishlist).
- **Scale:** normalized from authored 4.83 m to **1.80 m**, Y-up, feet at y≈0
  (glTF bbox: 0.0012 → 1.8066).
- **Materials:** Skin / Hair / Shirt / Pants / Socks / Shoes / Eyes — rebuilt
  as Principled BSDF with baked tinted albedos (skin pores, knit fabric
  weave, leather grain, hair strands) + tangent-space normals, tuned
  roughness (skin 0.55, cloth 0.85, leather 0.45, hair 0.65).

## Engine integration traps solved (documented for posterity)

1. **`export_optimize_animation_size=False`** — Quaternius actions are
   pose-keyed (mostly constant channels); Blender's optimizer would drop the
   constant pose curves, leaving a 1-track animation and a T-pose body.
2. **Node TRS = REST, not the evaluated NLA stack** — Godot's importer drops
   "immutable" tracks (keys identical to the node TRS). We disable
   `animation/remove_immutable_tracks=false` in the committed `.import` so
   every fresh checkout (and CI) keeps all 93 channels per clip.
3. **`add_child(tree)` before `tree.get_path_to(player)`** — resolving the
   anim player path from a parentless node silently fails.
4. **`SWITCH_MODE_IMMEDIATE`** on all state-machine transitions — AT_END
   never fires from looping locomotion clips, freezing travel().
5. **Facing:** the GLB faces +Z, so `FACING_OFFSET = -PI` converts the old
   robot-facing contract (`atan2(v.x, v.z) + PI`) into "face = velocity".

## Local rendering caveat (honest evidence note)

This sandbox renders screenshots through Mesa llvmpipe (software OpenGL) +
Godot's Compatibility renderer, where GPU skinning does not apply — skinned
meshes render in bind pose there (reproduced with a minimal hand-built
skeleton + box: llvmpipe ignores bone poses entirely). All pose/animation
logic above is instead verified headlessly (bone pose values, state machine
travels, AnimationPlayer advancement). Real Android devices use the Vulkan
Mobile renderer, which skins normally; CI screenshot evidence will be
upgraded to Vulkan + lavapipe so screenshots show the posed character.
