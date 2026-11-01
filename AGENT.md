# ==============================================================================
# CRYSTAL RUSH — AI AGENT PROJECT SPECIFICATION & CONTEXT (.agent)
# ==============================================================================
# This file provides full architectural context, conventions, state, and
# technical guidelines so any AI agent or developer can continue development.
# ==============================================================================

[PROJECT_METADATA]
ProjectName      = "Crystal Rush"
Genre            = "3D Low-Poly Sci-Fi Adventure / Exploration / Survival"
Engine           = "Godot Engine 4.7.2 (stable, official)"
Language         = "Pure GDScript (NO C#, NO .NET, NO external third-party addons)"
RenderPipeline   = "Mobile / Forward+ PBR"
PhysicsEngine    = "Jolt Physics 3D"
MainScene        = "res://ui/main_menu.tscn"
SaveFilePath     = "user://crystal_rush_save.json"
Repository       = "https://github.com/12Ahm-webSite/test-mcp"
DefaultBranch    = "main"

# ==============================================================================
# 1. GAME LORE & DESIGN OVERVIEW
# ==============================================================================
# You are Unit-07, an agile exploration automaton investigating the ruins of
# an ancient civilization whose central reactor suffered catastrophic collapse.
# Your objective is to collect Chrono Energy Crystals scattered across each sector
# to charge and power the extraction portal, all while evading the relentless
# Sentinel AI guarding the ruins.

# ==============================================================================
# 2. DIRECTORY STRUCTURE & FILE MANIFEST
# ==============================================================================
# res://
# ├── assets/
# │   └── materials/
# │       ├── mat_grass.tres              # Sector 1 ground material
# │       ├── mat_canyon_ground.tres      # Sector 2 ground material
# │       ├── mat_cavern_ground.tres      # Sector 3 ground material
# │       ├── mat_wall.tres               # Perimeter boundary walls
# │       ├── mat_crystal.tres            # Type 0 Energy Crystal (Cyan)
# │       ├── mat_crystal_speed.tres      # Type 1 Overdrive Speed (Gold)
# │       ├── mat_crystal_shield.tres     # Type 2 Energy Barrier (Green)
# │       ├── mat_crystal_rare.tres       # Type 3 Rare Chrono-Relic (Purple)
# │       ├── mat_neon_accent.tres        # Emissive cyan accent for monoliths
# │       ├── mat_player_body.tres        # Unit-07 base hull
# │       ├── mat_player_accent.tres      # Unit-07 glowing visor/joints
# │       ├── mat_enemy_body.tres         # Sentinel armored hull
# │       └── mat_enemy_eye.tres          # Sentinel reactive sensor eye
# ├── scenes/
# │   ├── levels/
# │   │   ├── level_1_ruins.tscn          # Sector 1 (10 crystals quota, Daylight)
# │   │   ├── level_2_canyon.tscn         # Sector 2 (12 crystals quota, Twilight)
# │   │   └── level_3_caverns.tscn        # Sector 3 (15 crystals quota, Neon Cavern)
# │   ├── player.tscn                     # Unit-07 with 3rd-person camera rig
# │   ├── enemy.tscn                      # Sentinel automaton with sensors
# │   ├── crystal.tscn                    # Dynamic collectible crystal
# │   ├── portal.tscn                     # Extraction gate with energy vortex
# │   ├── prop_ruins_arch.tscn            # Low-poly ancient ruin archway
# │   ├── prop_tech_pillar.tscn           # Low-poly reactor power pillar
# │   ├── prop_platform.tscn              # Parkour stone platform
# │   ├── prop_tree.tscn                  # Low-poly stylized tree
# │   ├── prop_rock.tscn                  # Low-poly boulder
# │   ├── vfx_crystal_burst.tscn          # GPUParticles3D burst on pickup
# │   └── main.tscn                       # Legacy prototype scene
# ├── scripts/
# │   ├── player.gd                       # Unit-07 locomotion, acrobatics, camera
# │   ├── enemy.gd                        # Sentinel 5-state AI, vision & hearing
# │   ├── crystal.gd                      # Collectible behaviors & burst VFX
# │   ├── portal.gd                       # Portal spin, beam pulse & trigger
# │   ├── game_manager.gd                 # Objectives, timers, score, level logic
# │   ├── save_manager.gd                 # JSON progress persistence
# │   ├── audio_manager.gd                # Procedural 16-bit PCM sound synthesizer
# │   └── vfx_crystal_burst.gd            # Dynamic color-tinted particle emission
# ├── ui/
# │   ├── main_menu.tscn                  # Start Expedition, Archive, Settings
# │   ├── main_menu.gd                    # Menu controller & settings sync
# │   ├── game_ui.tscn                    # In-game HUD, modals & pause menu
# │   └── game_ui.gd                      # HUD bindings, telemetry & toasts
# └── project.godot                       # Engine configuration & input actions

# ==============================================================================
# 3. CORE TECHNICAL STANDARDS & INVARIANTS
# ==============================================================================

1. 3D COORDINATE CONVENTIONS (GODOT 4):
   - Forward  = -Z
   - Backward = +Z
   - Right    = +X
   - Left     = -X
   - Up       = +Y
   - When aligning a model to a movement vector `dir`:
     `model.rotation.y = atan2(-dir.x, -dir.z)`

2. PHYSICS & COLLISION LAYERS:
   - Layer 1 (Mask 1): Static Environment & Level Geometry
   - Layer 2 (Mask 2): Player (CharacterBody3D)
   - Layer 4 (Mask 4): Enemy Sentinel (CharacterBody3D)
   - Layer 8 (Mask 8): Collectible Crystals (Area3D monitoring Layer 2)
   - Jolt Physics: Static bodies MUST be scaled uniformly (e.g. Vector3(1.2, 1.2, 1.2)).
     Non-uniform scaling of collision bodies triggers Jolt engine warnings.

3. GDSCRIPT STRICT TYPE ANNOTATIONS:
   - Godot 4.7.2 has strict type inference. Never use `:=` with dynamically resolved
     Node properties.
   - ALWAYS declare explicit types:
     `var dist: float = _player.global_position.distance_to(_enemy.global_position)`
     `var target_lean: float = clampf(...)`

4. COLLECTIBLES & PROGRESSION:
   - CrystalType enum: 0 = ENERGY, 1 = SPEED, 2 = SHIELD, 3 = RARE.
   - INVARIANT: ALL crystals collected MUST increment `collected_energy_crystals`
     by 1 and trigger `energy_updated` signal, while also conferring their buff:
     * Speed: +Speed for 8s
     * Shield: Absorbs 1 Sentinel hit & staggers Sentinel
     * Rare: +500 PTS
   - Collection is single-guarantee via `_collected` boolean check before queue_free().

5. PROCEDURAL AUDIO (NO EXTERNAL AUDIO FILES):
   - All sound effects (SFX) are synthesized on the fly via `scripts/audio_manager.gd`.
   - AudioStreamWAV format: 16-bit signed PCM, 22050Hz sample rate, mono.
   - Polyphonic audio player pool (8 players) prevents sound cutting off.

6. SAVE SYSTEM:
   - Data stored in JSON format at `user://crystal_rush_save.json`.
   - Tracks `unlocked_levels` (1 to 3), `high_scores` dictionary, `best_times`
     dictionary, and player settings (e.g. `mouse_sensitivity`).

# ==============================================================================
# 4. PLAYER (UNIT-07) ARCHITECTURE & CONTROLS
# ==============================================================================
- Camera Rig:
  * `CameraPivot` (Node3D) has `top_level = true` to decouple orientation from player.
  * Child `SpringArm3D` has length 4.5m with collision margin to prevent wall clipping.
  * Pitch clamped between -65° and +25°.
- Movement & Acrobatics:
  * WASD relative to camera yaw.
  * Space: Thruster Jump (Tap twice for Double Jump).
  * Shift: Overclock Sprint (Walk 6.5m/s -> Run 9.8m/s, Dynamic FOV 70° -> 78°).
  * Q / E: Phase Dash (Speed 22m/s, Duration 0.22s, Cooldown 1.2s, FOV kick 86°).
  * Procedural Animation: Limb pivots (`ArmL_Pivot`, `ArmR_Pivot`, `LegL_Pivot`, `LegR_Pivot`)
    swing dynamically with speed, body banks/leans into sharp turns, landing squash bump.
  * Trauma-based Camera Shake: Decays exponentially (`_shake_trauma = clampf(...)`).

# ==============================================================================
# 5. SENTINEL AI STATE MACHINE
# ==============================================================================
- States:
  * `PATROL`    : Wanders between points, turns away from walls using 3 RayCast3D probes.
  * `CHASE`     : 110° vision cone up to 24m, eyes pulse red, runs at player (speeds 5.8 to 7.4m/s).
  * `SEARCH`    : Investigates last-seen position for 4.5s upon line-of-sight break.
  * `RETURN`    : Retreats back to designated patrol anchor point.
  * `STAGGERED` : Paralyzed for 1.6s if colliding with a player possessing an active Shield.
- Acoustic Hearing:
  * Detects player running (Sprint) or Dashing within 12m even without line-of-sight.

# ==============================================================================
# 6. HOW TO RUN TESTS & VERIFY CODE
# ==============================================================================
Always verify scene integrity, flow, and absence of syntax errors before committing:
```bash
/home/pc/Downloads/Compressed/Godot_v4.7.2-stable_linux.x86_64 --headless -s scratch/test_levels_and_flow.gd
```
Expected output:
`🎉 ALL FLOW & INTEGRATION TESTS PASSED 100%! 🎉`

# ==============================================================================
# 7. ROADMAP & REMAINING OPTIONAL ENHANCEMENTS
# ==============================================================================
COMPLETED ENHANCEMENTS:
✓ Background Ambient Music (BGM):
  - Procedural 16-bit PCM multi-track synthesizer added to `audio_manager.gd`.
  - 3 custom seamless looping tracks generated specifically for Sector 1 (Ruins), Sector 2 (Canyon), and Sector 3 (Caverns).
  - Integrated with `game_manager.gd` with automatic playback and game-over ducking.
✓ Visual & Atmosphere Overhaul:
  - Enabled Forward+ desktop rendering with full Screen Space Ambient Occlusion (SSAO) and ACES tonemapping.
  - Added stylized Rim lighting to all terrain, rock, foliage, and barrier materials.
  - Upgraded perimeter boundaries with glowing Holographic Forcefields (`mat_forcefield.tres`).
  - Added ambient atmospheric floating motes (`scenes/vfx_ambient_motes.tscn`).
  - Tuned volumetric fog, depth, and soft lighting for each sector.

PRIORITIZED NEXT STEPS:
1. Character Visual Redesign:
   - Upgrade Unit-07 player robot with modular beveled armor, reactor core glow, and thruster VFX.
   - Upgrade Sentinel enemy drone with menacing hunter chassis and hover repulsor ring.
2. Mini-Radar / HUD Compass:
   - Add a compass bar or top-down circular radar in `ui/game_ui.tscn` showing
     dots for nearby crystals (cyan/gold/green) and a red skull/dot for Sentinel.
3. Exporting & Distribution:
   - Windows 64-bit Desktop (.exe).
   - Linux x86_64 Desktop executable.
   - Mobile Android APK with onscreen touch controls.

# ==============================================================================
# END OF SPECIFICATION
# ==============================================================================
