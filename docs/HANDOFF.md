# GloomsAuras — Session Handoff  (last updated 2026-08-03)

> ## ▶▶ 2026-08-03 — 12.1 DURATION BARS ARE SOLVED. The route is `AuraContainer`.
> **The suite-wide record lives in `~/GloomsHub/docs/FINDINGS.md` §1 (the ANSWERED block) and §10.
> Read those; they are not restated here.** What follows is GA-specific only.
>
> **Corrected, and repeated in this file until today:** *"the owner's Warlock profile is genuinely
> broken."* **It is not.** Every display in it triggers on presence, and all four DoTs were watched
> on screen in combat — lighting on application, following target swaps, clearing on expiry. The
> sticky-value risk flagged at `CDM.lua:550` was predicted again and **did not occur**, tested on
> target debuffs (the harder case than the Hunter's player buffs).
>
> **What is genuinely lost on 12.1:** reading duration/stacks. Every instance-ID call throws.
> **What is recoverable:** the visible countdown, via `AuraContainer` — Blizzard renders it into
> regions the aura BUTTON owns and GA never touches a number.
>
> ### Code that landed here 2026-08-03 (uncommitted work is now committed; QA state varies)
> | Change | State |
> |---|---|
> | `Core.lua` — **`/ga remove` fixed.** It did `tonumber(arg)` against string-keyed displays, so it could **never delete anything**. Now takes the `d11`-style id `/ga list` prints, still accepts a spellID. | owner-QA'd |
> | `Config.lua` — `/ga bar` **staggers** each new bar 34px below the last instead of stacking them all at `CENTER 0,-120`. | owner-QA'd |
> | `CDM.lua` — **`spec=?` fixed** (falls back to the spec ID when 12.1 returns an empty name). | fixed, low risk |
> | `CDM.lua` + `Core.lua` — **`/ga alertlog`**, a new diagnostic recording every CDM alert event as it ARRIVES and at each filter that drops it. Off by default; resets on `/reload`; capped at 400 lines. | owner-QA'd, produced FINDINGS §10 |
> | `CDM.lua` — `/ga probe` gained `cdframe:`, `playerAura:`, `barwidget:` and `durRemaining:` lines. Probe-only. **The StatusBar it creates is pooled and hidden — deliberately NOT the leaking pattern the charge probe still has.** | owner-QA'd |
> | `CDM:BarMirrorValues` + `Displays.lua` `StartMirror`/`StopMirror` — the **Tracked-Bar mirror**. Works, drains correctly. **Superseded by `AuraContainer` and not yet decided on — see backlog item 1.** | works, fate undecided |
>
> ⚠ **The mirror's icon-frame fallback is a dead end and is documented as such in the code.** Both
> `GetCooldownDuration` and `GetCooldownDisplayDuration` on the icon frame's Cooldown widget return
> the **total**, not the remaining — mirrored to a bar they pin full and never move. Tested twice.
> Don't retry it.


> ## ▶▶ THE AURAS TAB LAYOUT REWORK IS DONE — QA'd by the owner, 2026-07-25.
> Suite to-do item 1 is closed. Every step below was verified in-game by the owner before the next
> one started. **Do not re-litigate these; they are settled decisions, not defaults.**
>
> **What the tab is now:** a flush-left **240 rail** (shared `UI.tabHeader` · the shared
> `UI.profileBlock`, permanently visible · the GROUPS & AURAS tree · the buttons that act on the
> selection) beside an **editor pane that fills the rest** of the 860×626 container. The old
> centred 620 column, with ~120px of dead margin each side, is gone.
>
> **The six things that changed, and why they can't be undone casually:**
> 1. **The landing splash is RETIRED** — `ga_logo_full.png` is no longer drawn anywhere. The tab
>    opens straight onto the last-edited aura. `C:SelectInitial` replaced the landing/editor mode
>    switch; `C:UpdateEmptyState` covers the only state the splash genuinely carried ("no auras yet").
> 2. **The editor's big aura-NAME banner is GONE** (the owner: "a waste of space and, more
>    importantly, confusing and nonintuitive"). Renaming is a RAIL action — the Rename button or a
>    double-click on the row — through the shared `UI.nameDialog`. It renames `cfg.label` only; the
>    on-screen text an aura draws is still `cfg.text.str`, deliberately separate.
> 3. **Profiles moved OUT of their drawer** into the rail's top, so the rail reads down the real
>    hierarchy: profile → groups → auras.
> 4. **★ GROUPS ARE A FIRST-CLASS SELECTION.** Clicking a group's NAME selects it and its settings
>    fill the editor pane exactly as an aura's do; the caret alone collapses. That retired the ⚙ gear,
>    the Manage Group drawer, AND the green "Group: <name>" button (the owner: "extraordinarily
>    confusing" — it read as a status label but was an action, and sat nowhere near the group it
>    named). An aura's group is now a dropdown at the top of the aura pane. Groups also SHOW what
>    they do: dimmed + "(off)" when switched off, an orange dot when they carry a load rule.
> 5. **The Trigger section is a bracketed tree.** Every operand — a condition card OR a whole group
>    box — is inset the same 52px from its container's left edge and 14 from its right; the gutter
>    holds a bracket tying each pair, with an AND/OR/**NOR** chip on it. See the trigger notes below.
> 6. **Delete Aura CONFIRMS** (and Delete Group, and Delete Trigger Group). It used to delete on the
>    click with no undo — the owner caught it mid-rework. CONTRACTS §4 requires the shared modal.
>
> **`SKIN_NEEDS` is now MINOR 4** (`Config.lua` ~line 41) — GA calls `UI.tabHeader`. Bumped in the
> same commit, per CONTRACTS §6. **GA is no longer the tab without a header.**
>
> **FOUR DRAWERS ARE DELETED** — Manage Group, Visibility, Text and Glow. The accordion and the group
> pane replaced them; nothing opened the last two at all. What REMAINS drawer-based is correct and
> deliberate: the spell/trigger picker, the texture picker, the sound picker and the font picker,
> which are transient pick-one-thing windows. `Config.lua` chunk locals went **193 → ~170 of Lua's
> 200** as a result — the most headroom this file has had in months. Spend it carefully.
>
> ### ⚠ THE TRAP THAT COST THIS SESSION A BUILD FAILURE — READ BEFORE DELETING ANY BLOCK
> Deleting the Visibility drawer orphaned `PlayerSpecs()`, a module-local that happened to live
> inside it and is still called by the inline Load Conditions block. The call silently became a nil
> GLOBAL, `BuildTab` threw on first show, and because the shell calls `build(container)` BEFORE
> showing and focusing, **the entire tab came up blank with no tab highlighted** — not just the
> broken section. **`luac -p` cannot catch this** (calling an undefined global is valid Lua). The
> check that does, in one line — run it after ANY block deletion:
> ```
> luac -l Config.lua | grep -oE '_ENV "[A-Za-z_][A-Za-z0-9_]*"' | sort -u
> ```
> Diff that against a known-good revision. Anything a deletion orphaned appears as a NEW global.
> (Against the pre-rework commit, GA's list now differs only by `GetNumSpecializations` /
> `GetSpecializationInfo` — real WoW APIs — so nothing else was lost with the ~400 deleted lines.)
>
> ### Settled UI facts from this session
> - **Suite button language:** 22px tall, Title Case, GeneralSans-Medium 11 (flatButton's own
>   default — do NOT `setFont` over it), heroic @0.2 for secondary actions, the ONE create action in
>   purple @0.35. Delete keeps red @0.3. GA's 28px ALL-CAPS semibold buttons predated the suite.
> - **Carets** are the shared `UI.CARET` at 9×9 tinted `COLOR.orange` — list rows AND section
>   headers. GA's own `Media/triangle.png` is no longer drawn.
> - **★ Eye icons are WHITE art** (`Media/hidden.png` / `unhidden.png`, re-exported by the owner).
>   `SetVertexColor` MULTIPLIES, so coloured art can only darken — the old purple #936bff tinted
>   orange came out #873F15, a muddy brown. **Never re-bake a colour into those two files.** The eye
>   reports `selected OR preview`, the same rule `Displays:RefreshForced` draws by, so a selected
>   aura reads as visible without being toggled.
> - **The retired Figma mocks are NOT the spec any more** (the owner, 2026-07-25: "the mocks no
>   longer matter and are now hopelessly out of date... I'd prefer the suite be consistent with
>   itself"). GB and Overlays are the reference. `EDITOR_W` is 560, not the old 360 column.
> - **Trigger bracket rule:** the vertical must show a stub above and below the operator label
>   roughly as tall as the label itself. Encoded as a relationship, not a number
>   (`bite = (3·chip − gap)/2`), which lands the arms on each card's centre line.
> - **NONE renders as "NOR", never "AND NOT"** — NONE negates both sides equally, while "AND NOT"
>   reads as "the first thing and not the second". Per-condition negation never needs a chip: the
>   state pill already carries it ("INACTIVE on You", "ON COOLDOWN", "CHARGES NOT MAX").
> - **The rail tree's scrollbar is NOT `UI.makeScrollbar`** — that shared widget drives a real
>   ScrollFrame, and the tree is a fixed pool of rows windowed by `listOffset` (group headers and
>   auras are different row kinds, so the pool stays). It's a track+thumb driven by the offset,
>   orange, in the rail's right margin, shown only when the entries exceed `LIST_ROWS`.
> - **Measure in the same units as the owner.** Two rounds of "make the bracket read better" missed
>   because his mock files render at ~2.5× the game's pixels. When he gives a px number, convert it,
>   or better, ask for the RULE (he gave one — "stub ≈ label height" — and it landed first try).

> **SUITE UPDATE (2026-07-24, Phase D):** the options panel now renders ONLY as the AURAS
> tab of the Suite window (GloomsHub — hard dependency; standalone window + minimap button
> deleted; toolkit = LibGloomSkin-1.0; media picker reads `GloomsHub:ListMedia`). Everything
> below about the CDM engine/displays still holds; anything about the standalone panel
> window is superseded — see `~/GloomsHub/docs/SUITE-STATE.md` + ARCHIVE.md.

**New session: read this file first, then `docs/API-NOTES.md`, then `docs/REQUIREMENTS.md`,
then `CLAUDE.md`.** The vendored WoW skill lives in `docs/wow-addon-dev/`. This file is the
single source of "where we are + what not to relitigate."

> **Restructured 2026-07-26.** The build log, the completed NEXT list and the session records moved
> to [ARCHIVE.md](ARCHIVE.md) — nothing was deleted. The old "NEXT / pending" section had become a
> record of finished work: nearly every entry was already ✅ DONE, one heading appeared twice, and it
> still opened with a "START HERE (session 12)" block from 2026-07-13 that the July 25 layout rework
> had entirely superseded. The items genuinely still parked are below.
>
> **Open work for the whole suite lives in `~/GloomsHub/docs/BACKLOG.md`**; unproven diagnosis in
> `~/GloomsHub/docs/FINDINGS.md`. Do not restate suite-wide facts here — point at the Hub.
> **Keep this file re-readable**; if it passes ~450 lines, archive something. The handoff ritual
> (`~/GloomsHub/.claude/skills/handoff-ritual/`) maintains it.

---

## GA's colour controls — the private picker is GONE (2026-07-26)

`MakeColor` (the `[✓ label] + swatch` control behind **Recolor**, **Text Color** and glow **Custom
Color**) no longer drives Blizzard's `ColorPickerFrame`. It calls the suite's own `UI.colorPicker`.
**`ColorPickerFrame` now appears nowhere in this repo.** `SKIN_NEEDS` is **6**.

Two GA-specific things worth knowing before touching that code:

- **Cancelling must be able to leave a colour UNSET.** `MakeColor` seeds white when the colour is
  nil, so a plain "restore what we opened with" would leave white applied. It captures `wasUnset`
  and clears back to nil in `onCancel`. ✅ **Owner-QA'd 2026-07-26** — cancelling an unset Recolor
  leaves the checkbox off, the swatch on its grey placeholder and the aura untinted. **Don't
  "simplify" this into a plain restore**; a plain restore applies white.
- **`AuraColorSources` walks EVERY display**, and the Hub's picker uses it for its "in use" palette
  and its "where is this colour used" tooltip. It exists because the editor has **one** Recolor
  swatch that re-points at the selected aura, so a per-control getter could only ever report that
  one — and recolouring a texture per aura is the owner's main workflow. Names come from
  `cfg.label`, else the spell name via `cfg.spellID` (duplicates are keyed `"dN"` and have no
  numeric key, which is why `cfg.spellID` is tried first), else `"Display <id>"`.

**The contract itself lives in `~/GloomsHub/docs/CONTRACTS.md` §4 — do not restate it here.**

---

## ⚠ READ THIS BEFORE ANY DoT / DURATION WORK

**12.1 makes aura instance IDs SECRET in combat, and every read call throws.** GA keeps aura
*presence* but loses duration, stacks and expiry — silently, with a clean BugSack. That is
`TESTED`, and it invalidates the duration/countdown direction the parked items below assume.

**Do not build on the DoT-duration path without reading `~/GloomsHub/docs/FINDINGS.md` §1 first.**
It is the suite's biggest open item and needs a design decision (`AuraContainer` vs combat-log
tracking vs presence-only degradation), not a patch.

**★ But know how far it actually reaches, proven 2026-07-26 (`~/GloomsHub/docs/FINDINGS.md` §7).**
Only the **data** path is dead. A display that triggers on presence — `buff_active`,
`buff_inactive`, `cd_ready` — is **unaffected**, because `CDM:EvalCondition` (`CDM.lua:213`) reads
the `buffActive` boolean table and never an aura. The owner's MM Hunter profile is entirely
presence-driven and works correctly on 12.1. ~~his Warlock profile is the one that is broken~~ —
**struck 2026-08-03: the Warlock profile works too**, watched on screen. Do not describe §1 as "GA
is broken in combat"; it is far narrower than that.

~~⚠ **The one place presence could still fail is `CDM.lua:550`.**~~ **`TESTED` 2026-08-03 and it did
not happen.** `RepollBuffPresence` falls back to `frame:IsActive()` when the aura read throws; the
worry was that a *secret* `IsActive` would pin the previous value and leave an expired buff lit
forever. Checked on the Warlock's four target debuffs — structurally the harder case — through
application, target swap and natural expiry: every display cleared correctly. Keep it only as the
first thing to check if presence ever does go sticky.

---

## The `/ga probe` diagnostic — one bug left (2026-07-26, half fixed 2026-08-03)

Dev-tool only, no user impact — but this probe is the instrument the whole 12.1 investigation runs
on, and a misleading instrument costs more than a cosmetic bug should. Both were `TESTED`.
**Bug 2 (`spec=?`) is FIXED as of 2026-08-03. Bug 1 (the frame leak) is still open** — see backlog
item 3. Note the new probe code added the same day pools its StatusBar correctly; copy that, or
`_ProbeShadows`, when fixing bug 1.

1. **It paints a full-screen cooldown sweep on every CAPTURE click.** `CDM.lua:1567` creates two
   fresh `CooldownFrameTemplate` frames per charge-spell per capture with **no `SetSize`** (so they
   inherit UIParent), no `SetDrawEdge(false)` and no `SetDrawBling(false)` — hence a screen-wide gold
   wedge and a completion flash. They are never reused or hidden either, so each click leaks two
   more; a 24-capture session parks a couple of hundred. `_ProbeShadows` (`CDM.lua:1375`) already
   does this correctly — pool them the same way.
2. **`spec=?` in every header.** `CDM.lua:1455` takes the **second** return of
   `GetSpecializationInfo` (the name), which comes back empty on 12.1. The spec **ID** is fine and
   the globals are alive — verified in-client: `GetSpecialization` → `function`, index `2`, ID
   `254`. This cost a false alarm about spec-gated groups failing closed; see FINDINGS §7's
   `KILLED` list.

---

## Parked / deferred — owner-requested, none of it active

Lifted out of the archived NEXT list so it isn't lost. **None of this is open work** — the owner
parked each item explicitly. Anything genuinely actionable lives in the Hub's backlog.

- **Sound trigger MODES** (2026-07-09) — *"its own small project, NOT now."* Today a display's sound
  fires on every hidden→shown edge, so a target-DoT aura re-fires the sound every time you target
  away and back. He wants: (1) on initial application only, (2) on wear-off, (3) in the pandemic
  window. **He explicitly parked it — don't pay attention to it now.** Note that (3) is time math,
  which §1 above now makes much harder.
- **Auto-icon a new aura from its first trigger** (2026-07-09) — adopt the first trigger condition's
  spell icon when no texture is explicitly set, WeakAuras-style. Fallback only; an explicit
  `cfg.texture` always wins. Open question: does an explicit pick set `cfg.texture`?
- **Override display polish** — show a spell's override name+icon in the picker when
  `info.overrideSpellID ~= spellID` (e.g. "Black Arrow" not "Kill Shot"), storing the base spellID.
  Cosmetic; tracking already follows overrides. **Offered, the owner didn't decide.**
- **Deferred texture transforms** — Mirror, Rotation, Texture Wrap (`SetRotation` interacts with
  `SetTexCoord`).
- **Visibility Phase 2** — rarer load conditions (Race/Faction/Level, Zone/Instance/difficulty, M+
  affix, Equipment, Spec Role, PvP talent). Skyriding was dropped: no reliable "am I skyriding now" API.
- **Export/import strings** for sharing — naturally follows Profiles.
- **KNOWN ISSUE, minor, deferred by the owner — reappear LAG.** Swapping back to a DoTted target
  occasionally lags ~0.5s. Root cause is the CDM's own target re-scan latency; re-polling cannot beat
  it (its flag flips and fires its event simultaneously). The only lever is scanning the target
  ourselves on `PLAYER_TARGET_CHANGED` — `UNVERIFIED` for secret-safety, and §1 above makes it
  unlikely. ArcUI has the same constraint.

---

## How to work with the owner (the owner) — READ THIS
- **Non-developer.** He sets requirements, answers domain questions, and does in-game QA.
  Claude writes all code and does its own research. Don't ask him to read Lua.
- **ONE instruction at a time** for testing. Never hand him a batch of commands — he tunes
  out. State the single next action + what to look for, then stop.
- **VERIFY before claiming.** Never say "it works" until confirmed in the API docs AND
  in-game. Frame builds as "the source says this should work — test it," not as done. (This
  rule exists because repeated over-claims eroded trust; see the walls below.)
- **He runs BugGrabber/BugSack.** When something misbehaves, ASK FOR THE ERROR TEXT FIRST —
  WoW hides Lua errors, so silent throws look like "nothing happens." A `StopMovingAndSizing`
  typo cost hours because I didn't ask for the error early.
- These are also saved as memories (owner-non-developer, one-instruction-at-a-time,
  enable-lua-errors-during-qa, verify-before-claiming).


## Project & environment
- **GloomsAuras**: bespoke WoW **Midnight (Interface 120007)** addon — custom textures/sounds
  that trigger on Cooldown Manager state. Sibling to GloomsBuildBarn (same author "Gloom",
  guild Hand of Devastation). Spec origin: `~/Downloads/HoDTracker-SPEC.md` (ignore the name).
- **Repo root = addon folder**: `~/GloomsAuras` (the primary cwd).
- **Live in client via symlink**: `/Applications/World of Warcraft/_retail_/Interface/AddOns/GloomsAuras`
  → repo root. Edits are live; the owner just `/reload`s. No copy step.
- **Blizzard source on disk** for verifying APIs: `_retail_/BlizzardInterfaceCode/Interface/AddOns/`
  (esp. `Blizzard_CooldownViewer/` and `Blizzard_APIDocumentationGenerated/`). USE IT.
- **Always `luac -p <file>`** before handing code to the owner.


## The core idea (do NOT relitigate)
Midnight makes combat aura/cooldown data **secret** (`issecretvalue`); tainted addon code
throws if it does arithmetic/compare/etc. on a secret. **GloomsAuras never reads that data —
it MIRRORS the Blizzard Cooldown Manager**, whose state is computed in Blizzard's *secure*
context and exposed as plain frame state / transitions we can hook. **Only spells actually
PLACED in a CDM viewer are trackable** (registry ≠ placed).

> **UPDATE 2026-07-08 (VERIFIED — the rule was too strict; stop apologizing for "breaking" it).**
> The real constraint is ONLY "no arithmetic/compare/truth-test on a secret." We MAY read an aura's
> **presence** (via the CDM item's native `frame.auraInstanceID` — secret or not, its *existence* is
> the signal) and **duration** (via `C_UnitAuras.GetAuraDuration` duration OBJECTS), choosing the unit
> from `info.selfAura`. This is **PROVEN for target DoTs** (Warlock, open-world, 8 `/ga probe` captures
> across target swaps) and is how we'll fix DoT tracking — the pure `IsActive()` mirror gets target
> swaps WRONG. Mirroring is still correct for buffs/cooldowns; this just adds a sanctioned, tested path
> for auras the mirror can't handle. A charge variant (shadow-cooldown) is FOUND but UNVERIFIED. Full
> write-up + verification status: **API-NOTES §9**. Reference impl: **ArcUI** (installed, readable).


## Files
- `GloomsAuras.toc` — Interface 120007; load order: `Libs\*` → Core → Displays → CDM →
  `Media\TextureManifest.lua` → Config.
- `Core.lua` — namespace `GA` (`_G.GloomsAuras`), SavedVariables `GloomsAurasDB`, `/ga` router,
  **design tokens** `GA.COLOR / GA.FONT / GA.MEDIA` (matched to Build Barn).
- `Displays.lua` — `GA.Displays`: on-screen frames (texture/size/pos/alpha + tint/desaturate/blend/
  strata), **glow** (`ApplyGlow` via LibCustomGlow, OnShow/OnHide-driven), drag-to-move while panel open
  (NOT clamped), Cooldown swipe (OOC), **`RefreshForced`** (editor preview = selected + eye-on only).
- `CDM.lua` — `GA.CDM`: the mirror engine — state tracking, **recursive grouped trigger eval** (AND/OR/
  NONE), discovery, hooks.
- `Config.lua` — `GA.Config`: the Auras TAB (layout rework, 2026-07-25) — a flush-left **rail**
  (`UI.tabHeader` + the shared `UI.profileBlock` + the GROUPS & AURAS tree + New/Rename/Duplicate/
  Delete) beside an **editor pane** that fills the container. The pane shows the ACCORDION for a
  selected aura or the **GROUP PANE** for a selected group. Local helpers on top of LibGloomSkin
  (`MakeSlider/MakeColor/MakeCycle/MakeDropdown/twoWeightLabel`) + the four remaining PICKERS
  (spell/trigger · texture · sound · font — transient by nature, so still docked windows).
  **The Manage Group, Visibility, Text and Glow drawers are DELETED**; their content is inline.
  Much editor state hangs on the `C` table (chunk-local cap — ~170/200, watch it).
- `Media/TextureManifest.lua` — auto-generated `GA.TextureShapes` (254 aura shapes). Regenerate via
  `scratchpad/gen_manifest.py` if the bundled art changes.
- `Media/` — bundled Khand/GeneralSans fonts, `bg_flame.png`, `minimap.png`, the owner's custom UI icons
  (`lock_locked/unlocked.png`, `triangle.png` = collapse caret, `settings.png` = group gear,
  `hidden/unhidden.png` = per-aura eye), `Textures/` (107 shape files) + `PowerAurasMedia/Auras/`
  (145 curls) — copied from ThisWeeksAuras.
- `MinimapButton.lua` — `GA:InitMinimapButton` / `GA:ToggleMinimapButton` (LibDBIcon launcher).
- `Libs/` — embedded LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0,
  LibSharedMedia-3.0, **LibCustomGlow-1.0** (aura glow effects) — source: TWA's copies. `Libs/` is
  gitignored (packager fetches all libs at release); the local working copy keeps them.


## Hard-won LEARNINGS (verified — do NOT rediscover)
- **The `a and b or c` idiom BREAKS when `b` is `nil`/`false` — never use it to assign nil.** A "Disabled"
  switch set `cfg.enabled = v and nil or false`: for `v==true` that's `(true and nil)`→nil→`(nil or false)`→
  **false**, so it evaluated `false` in BOTH directions — could disable an aura but never re-enable it, which
  looked like "auras don't show in combat" (they were stranded off). Use an explicit `if v then x=nil else
  x=false end`. Lesson: for any assignment whose "true" value is `nil` or `false`, write the `if`, not the
  ternary. (2026-07-08; also mirrored a symptom into a scary-looking display bug — always suspect data state
  before the render path.)
- **`FontString:SetShadowColor` / `SetShadowOffset` render NOTHING in this client** — a drop shadow via
  the shadow API is invisible at any offset. We dropped the shadow option (outline flags are the text
  styling). If a shadow is ever truly needed, draw it manually (a black text copy offset behind), but
  even a behind-sublevel copy layered awkwardly — not worth it; outline suffices.
- **★ `SetFont` RAISES on a missing font asset — it does NOT return false** (proven in-client on live
  12.0.7, 2026-07-26). Three sites here were written on the opposite assumption, so the fallback never
  ran and the enclosing function aborted mid-way. **Always go through `GA.SetFontSafe(fs, path, size,
  flags)`** (`Core.lua`) — it `pcall`s the set and treats a raise *or* an explicit `false` as failure,
  returning a plain boolean so the caller can fall back. Now used at `Displays.lua:379` (aura label),
  `Displays.lua:238` (bar value text) and `Core.lua:66` (`PreloadFonts`). **Never call `SetFont`
  bare in this repo again.**
  ★ **There was a FOURTH exposed site, missed on 2026-07-26 and fixed later the same day:**
  `Config.lua:1833` (the font-picker flyout row) hands a **saved raw path** — `item.path` — to the
  *shared* `setFont`, i.e. `LibGloomSkin`'s helper, not GA's. `GA.SetFontSafe` never covered it
  because it is not GA's function. The lib's `UI.setFont` now `pcall`s and returns success as well
  (Hub CONTRACTS §4, MINOR 5), so this route is closed — but the lesson stands: **a repo-local
  "always use our safe wrapper" rule does not cover the calls that go through the shared toolkit.**
  ⚠ **Why GA was hit hardest: GA stores the resolved font PATH in SavedVariables** (e.g.
  `Interface\AddOns\NiceDamage\fonts\pepsi_modern.ttf`), so an aura's font can point into an addon
  the user doesn't have. If the font picker is ever reworked, **saving the name instead of the path
  would remove most of this class of bug.**
  ⚠⚠ **CORRECTED 2026-07-26 — this used to read "and the other tools weren't", claiming GB and the
  Hub were safe because they store an LSM NAME and fall back to a bundled file. That was wrong**, and
  it was the reasoning that got the follow-up deferred as a tidy-up. `Fetch(name, true)`'s silent-nil
  rescue only fires when the lookup **misses**; anything that registers a name for a file it never
  verified — including the Hub's own Media tab, which *cannot* verify, as WoW exposes no filesystem
  API — makes the lookup **succeed** and return a dead path. Both other tools were exposed too. See
  the Hub's FINDINGS §5 `KILLED` list.
  ⚠ **The blast radius was profile-wide, not one display.** `Displays.lua:151` is outside the
  `if not f then` create-branch, so `ApplyConfig` re-runs for every display on every `GetOrCreate`,
  and `RefreshAll` is called unguarded at the top of `CDM:Discover()` — so one dead font aborted
  Discover before anything was bound. Full record + the killed theories: the Hub's
  `docs/FINDINGS.md` §2.
- **Lua 5.1 caps a function at 60 UPVALUES (`local`s captured from enclosing scope).** `Config.lua`'s
  giant `Build()` hit exactly 60 after Phase 1; one more (a `DEFAULT_FONT` ref) → `function ... has
  more than 60 upvalues` at LOAD time and the panel wouldn't open. luac 5.5's `-p` does NOT enforce the
  60 cap, **but `luac -l -l Config.lua` prints each function's `N upvalues` count** — subtract 1 for
  `_ENV` (5.5 has it, 5.1 doesn't) to get the 5.1 number. Build's prototype count = every module-scope
  `local` referenced by Build OR any closure nested in it. Fix pattern: extract chunks of `Build` into
  their own module-level functions (`BuildGroupSection`, `BuildGroupManager`) so each gets its own 60
  budget — OR hang new state/helpers on the `C` table (a field access, not an upvalue). **Build sits at
  57 (Lua 5.1) after Phase 3; keep it there.**
- **Lua caps a function at 200 LOCALS too — and the file CHUNK (top-level) counts (hit 2026-07-08).**
  Every module-scope `local` (constants, `local function` helpers, forward-decls) counts toward the main
  chunk's 200. Phase-3B's first draft added ~11 module locals and overflowed: `luac -p` → `too many
  local variables (limit is 200) in main function`. **Unlike the 60-upvalue cap, luac 5.5's `-p` DOES
  catch this** (same limit). `Config.lua`'s chunk is at **198/200** — essentially full. Fix pattern used:
  put ALL new profile state + UI functions on the **`C` table** (`C._prof`, `function C:OpenProfileManager`…)
  instead of module locals → zero new chunk locals. Do the same for any future Config.lua feature.
- **Game fonts lack the ▼/▶ unicode triangles → they render as a tofu box.** Don't use unicode
  glyphs (or native Blizzard textures — the owner's rule) for UI marks. Use the owner's bundled PNG icons in
  `Media/` shown untinted (`SetVertexColor(1,1,1,1)`): `triangle.png` (collapse caret, rotated via
  `Texture:SetRotation` — right=collapsed, -pi/2=down=expanded), `settings.png` (gear), `hidden/
  unhidden.png` (eye), `lock_locked/unlocked.png`. Ask the owner to make an icon rather than reaching for
  a glyph or Blizzard art.
- **StaticPopup edit box is `dialog.EditBox` (PascalCase) in Midnight, NOT `dialog.editBox`** — the
  lowercase alias is GONE (GameDialog.xml system), so `OnShow`/`OnAccept` referencing `self.editBox`
  throw `attempt to index field 'editBox' (a nil value)`. We sidestepped StaticPopup entirely with a
  small **skinned** `OpenNameDialog` (flatEditBox + OK/Cancel) — nicer chrome AND no client-field
  fragility. If StaticPopup is ever needed, use `dialog.EditBox or dialog.editBox`.
- **1-charge spells are NORMAL cooldowns, not the "unreadable charge" wall (fixed 2026-07-07):**
  `cooldownInfo.charges` just means "uses the charge system". What matters is **maxCharges**:
  **1 ⇒ track like any cooldown** (Kill Shot, most executes); **≥2 ⇒ genuinely unreadable in combat**
  (Aimed Shot). We were bucketing *any* charge flag as unreadable, so a 1-charge cd's availability
  stayed `nil` forever and never wired into the cooldown-widget hook path → `cd_ready` was stuck.
  Fix: read `GetSpellCharges().maxCharges` (readable OOC), cache it in `CDM.maxCharges` (persists
  across Discover), classify `isCharge = maxCharges>=2`. **This also transparently handles spell
  OVERRIDES** (Black Arrow replacing Kill Shot via a hero talent): the CDM item's cooldown widget
  reflects the override, and we match the item by base spellID (`InfoMatchesSpell` checks
  spellID/override/linked), so tracking Kill Shot mirrors Black Arrow with no override-specific code.
- **`item.isOnActualCooldown` is SECRET in combat when off-GCD (verified via /ga trace 2026-07-07):**
  it's `not isOnGCD and cooldownIsActive`; on the GCD it short-circuits to a plain `false`, but OFF
  the GCD it evaluates `cooldownIsActive` (a secret in combat) → returns SECRET *exactly when the real
  cooldown matters*. So it is NOT a combat availability source (unlike `item:IsActive()` for buffs).
  `CDM:SyncCooldowns` uses it only as an OUT-OF-COMBAT accuracy pass; **in-combat availability comes
  from the `CooldownFrame_Set/Clear` widget hooks.** TRADE-OFF still stands: right after casting the
  tracked cd spell, during its ~1.5s GCD the hook skips (isOnGCD) so it briefly reads "available".
- **Blank labels on the FIRST login of a session (2026-07-07):** WoW sometimes hasn't finished
  loading a bundled runtime TTF when the panel is built on an early `/ga`, so *some* labels render
  BLANK (button backgrounds fine, glyphs missing) until a `/reload` caches the font. `setFont`'s
  fallback only catches an *invalid* path, not "valid path, glyphs not ready yet". Fix: `GA.PreloadFonts`
  in Core.lua draws+measures a throwaway string in each `GA.FONT` face at `PLAYER_LOGIN`, warming the
  cache before any panel builds. Only reproduces on a true fresh login (a `/reload` already has the
  fonts cached), so verify by logging out to char-select and back in, then opening `/ga` immediately.
- The frame method is **`StopMovingOrSizing`**, NOT `StopMovingAndSizing` (nonexistent). The
  typo made every drag "stick to the cursor." Cross-check method names against GloomsBuildBarn.
- **Create frames HIDDEN** (`f:Hide()` at end of build) so the first `:Show()` actually
  transitions and fires `OnShow` — otherwise "have to open it twice to populate" bugs.
- `Button:SetScript("OnClick", fn)` calls `fn(button, ...)` — passing a bare function whose
  first param means something else gets the button as that arg (caused the OpenPicker crash).
  Wrap: `function() fn() end`.
- **Buff active-state**: `item:IsActive()` is a **plain bool in open-world combat** (confirmed).
  Mirror via `hooksecurefunc(itemFrame, "OnActiveStateChanged", …)`.
- **Non-charge cooldown availability WORKS**: hook globals `CooldownFrame_Set`/`CooldownFrame_Clear`
  filtered to `item:GetCooldownFrame()`, plus `item:OnCooldownDone`. Seed initial state OOC via
  `GetSpellCooldown`. Never reads a secret.
- **DoTs / target debuffs — the `IsActive()` mirror is NOT enough (VERIFIED 2026-07-08, Warlock, 8
  captures):** the Tracked-Bar `IsActive()` reads correctly when POLLED, but (1) nothing re-polls it on
  a target SWAP (no `OnActiveStateChanged` fires) → it goes stale on screen, and (2) a spell enrolled in
  TWO viewers (Haunt in Essential `cat=0` + BuffBar `cat=3`) makes `Discover` map both frames to one
  spellID → they fight over the shared `buffActive/available[]` var = the "goes random" symptom. The
  proven fix: read `frame.auraInstanceID` + `C_UnitAuras` on the `selfAura` unit, re-eval on
  `PLAYER_TARGET_CHANGED`, and disambiguate matching by cooldownID. **Proven correct across 8 target-swap
  captures; NOT yet built or QA'd. UNVERIFIED in instance/M+/raid.** Detail: API-NOTES §9.
- **Trigger `nil`-availability default (fixed 2026-07-07):** an idle-available cooldown never fires
  a transition and is secret in combat, so `available[sid]` stays **nil**. `EvalDisplay` (auto,
  no-trigger) already defaulted nil→ready, but `EvalCondition` (cd_ready as a trigger condition)
  defaulted nil→NOT-ready — same value, opposite meaning. Compound "RF cd_ready AND …" silently
  failed. Fix: `cd_ready` now defaults nil→READY **for non-charge only** (charge stays nil→not-ready,
  since charges are genuinely unreadable). Lesson: the two eval paths must agree on unknown-state.
- **GCD false-positive on `CooldownFrame_Set` (fixed 2026-07-07):** every cast triggers the global
  cooldown, and the CDM re-runs `CooldownFrame_Set` on each item's widget to redraw — even for a
  spell NOT on its own cd. The hook was marking it unavailable, sticking it "on cooldown" until a
  real off-cd transition (this is why casting Aimed Shot/Multi-Shot broke Rapid Fire's condition).
  Fix: the Set hook now **skips while `item.isOnGCD == true`** (plain bool, guarded), keyed via a
  new `cdFrameToItem` map. Also reseed availability on `PLAYER_REGEN_ENABLED`. TRADE-OFF: casting
  the tracked cd spell *itself* now leaves its aura lit ~1.5s (the GCD) before it flips to on-cd.
- **`/ga trace`** (new): focused per-display dump — shown?, our `buffActive`/`available` mirror,
  the item's cached `isOnGCD`/`isOnActualCooldown`/`cooldownIsActive`, and each trigger condition's
  evaluated result. Ask the owner to run it IN the failing state — it makes trigger bugs a 30-sec find.
- **WALLS (confirmed from client docs — cannot out-code):**
  - **Cooldown timers in combat**: every `SetCooldown*` is `AllowedWhenUntainted` → an addon
    can't feed a secret duration to a timer widget. Works out of combat only.
  - **Charge-spell availability**: `GetSpellCharges` AND `GetSpellCastCount` are both
    `SecretWhenCooldownsRestricted`; `IsSpellUsable` ignores cooldown AND charges (always true).
    So directly READING "do I have a charge" is unknowable in combat. **✅ BUT (2026-07-08) the DOOR is
    CONFIRMED — the "shadow cooldown" technique: route a duration OBJECT through a hidden Cooldown widget
    and read its `IsShown()` to DERIVE availability without reading the count. VERIFIED on Aimed Shot
    (2→1→0→1→2): `mainShown==false` ⇔ ≥1 charge castable; the object feed does NOT throw in combat. This
    RETIRES the wall for AVAILABILITY (gives "≥1", not exact count). Details: API-NOTES §9.3. NOT yet
    built into the addon.**
  - Only partial charge signal: `C_SpellActivationOverlay` detects **procs** — but procs that
    grant a buff (e.g. Lock and Load) are already trackable as a **buff-active** condition, so
    that path is redundant.
- **Placement requirement (CONFIRMED from CDM source 2026-07-08)**: a spell must be in a TRACKED CDM
  section — Essential / Utility / Tracked Buffs / Tracked Bars — to be tracked. "Not Displayed" items get
  moved to a separate **Hidden** category (`HiddenSpell`/`HiddenAura`, via a `HideByDefault` flag + saved
  layout — `CooldownViewerSettingsDataProvider.lua`), so they have **no item frame** and GloomsAuras can't
  hook them. `/ga debug` = "verify tracking" (FOUND/NOT FOUND per display); `/ga charges`
  reports charge status. (Bonus source find: `CooldownViewerMixin:RefreshActiveFramesForTargetChange` — the
  CDM DOES re-scan on target change; relevant to the DoT reappear-lag known issue.)
- **Trigger picker MUST source from the data provider — NOT live frames, NOT the raw category set (VERIFIED
  2026-07-08, sixth session; three approaches tried, do NOT relitigate).** The trigger picker (`BuildAuraLists`
  in Config.lua) lists trackable spells; the ONLY correct source is
  `CooldownViewerSettings:GetDataProvider():GetOrderedCooldownIDsForCategory(cat, false)` +
  `:GetCooldownInfoForID(id)` — the exact ordered set each viewer lays out (CooldownViewer.lua RefreshLayout).
  Why the other two FAIL: **(a) live item frames** — a frame clears its cooldownID the instant it's
  released/hidden (Blizzard's itemFramePool reset callback → `ClearCooldownID` → `cooldownInfo=nil`), and the
  Essential viewer HIDES items while inactive (`hideWhenInactive`), so out of combat every READY Essential
  cooldown (Rapid Fire, Aimed Shot…) reports no spellID and silently vanished from the picker. **(b) raw
  `GetCooldownViewerCategorySet(cat, …)`** — returns raw PRE-remap IDs + flags: it under-returns Tracked Buffs
  AND, paired with a manual HideByDefault filter, DROPS known buffs the user actually displays (Lock and Load,
  Trueshot, Aspects — HideByDefault-by-default but placed into a tracked category). The data-provider list is
  frame-independent, respects the saved layout + HideByDefault remap + `isKnown`, so it lists exactly what's
  displayed. Fallback to the raw set (with our own isKnown + HideByDefault filter) only if the provider is nil.


## Diagnostics / commands
- `/ga` — open the options panel. `/ga help` — list commands.
- `/ga debug` — CDM state dump (availability/kind/charge/IsSpellUsable per display). Ask the owner
  to paste this (or BugSack) when diagnosing.
- `/ga profile [name]` — list profiles (active marked), or switch to one. Panel is primary.
- `/ga minimap` — show/hide the minimap button (persisted).
- `/ga hidecdm` — hide/show Blizzard's Cooldown Manager (alpha-0, tracking stays live; persisted).
- `/ga charges` — which cooldowns support availability tracking (charge spells flagged). Run OOC.
- `/ga trace` — per-display trigger diagnostic (shown?, buffActive/available mirror, item cooldown
  fields, each condition's eval). Run IN the failing state; makes trigger bugs a 30-sec find.
- `/ga probe [filter]` — EXHAUSTIVE read-only secret-safe-signals dump (per CDM item: `selfAura`,
  `auraInstanceID` present?, `C_UnitAuras` player/target presence + duration, which hook methods the
  frame exposes, shadow-cooldown readiness). **Writes each capture to the SavedVariables file**
  (`WTF/Account/AELWYN/SavedVariables/GloomsAuras.lua` → `GloomsAurasDB.probeLog`, last 40) so Claude
  reads it straight off disk after a `/reload` — no transcription, and captures can be taken at exact
  states. `/ga probe clear` wipes the log.
- `/ga capture` — a movable **CAPTURE button**: click it at each game state (mid-combat, right after a
  target swap) to fire a probe without typing. Built for the §9 investigation.
- `/ga add|remove|list|pos|size|preview|test` — legacy/back-door commands (panel is primary).


## SavedVariables data model  (schema 2 — profiles, since 2026-07-08)
> **Two layers (Phase 3).** `GA.global` = the raw SV `GloomsAurasDB`; `GA.db` = the ACTIVE PROFILE
> `GloomsAurasDB.profiles[activeName]`, REPOINTED on a switch. So `GA.db.displays/groups/seq/groupSeq/
> hideBlizzardCDM/ungroupedCollapsed` all read the active profile; only `panelPos` + `minimap` live on
> `GA.global` (account-wide). Active profile resolved at **PLAYER_LOGIN** (`GA.SetupActiveProfile`), which
> also runs the one-time schema 1→2 migration. Profile ops are `GA:SwitchProfile/Create/Copy/
> RenameActive/Delete/ProfileNames/ActiveProfileName` in `Core.lua`.
```
GloomsAurasDB = {                                     -- = GA.global (account-wide)
  schema = 2,
  profiles    = { ["Name - Realm"] = <PROFILE>, … },  -- GA.db points at the active one
  profileKeys = { ["Name - Realm"] = "profileName" }, -- which profile each character uses
  minimap  = { hide, minimapPos },                    -- LibDBIcon (account-wide)
  panelPos = { x, y },                                -- panel window position (account-wide)
}
PROFILE = { displays = { [id]=<AURA_CFG> }, groups = { [gid]=<GROUP> }, seq, groupSeq,
            hideBlizzardCDM = bool/nil, ungroupedCollapsed = bool/nil }   -- = GA.db
```
> **Keying (unchanged from 2026-07-07 Duplicate work):** each profile's `displays` key is an opaque
> **display id**, NOT
> the spellID. Originals keep a numeric **spellID** key (so existing data is untouched); **duplicates**
> get a unique `"dN"` **string** key (counter `GloomsAurasDB.seq`). The tracked spell is ALWAYS
> `cfg.spellID`. Rule of thumb: `GA.Displays.frames[]`, `CDM.lastShown[]`, `lastPlay[]`, `selectedID`,
> and every `db.displays` iteration key = **display id**; `CDM.kind/available/buffActive/isCharge[]`,
> `frameToSpell` values, and all `C_Spell.*` calls = **cfg.spellID**. `DisplayList()` sorts by
> `cfg.spellID` then key (never compares number vs string → no error; existing order unchanged).
```
{ spellID = <tracked spell or NIL — optional since 2026-07-08; nil = decoration>, label,
  enabled = true (false ⇒ "Disabled" in gameplay, set via Visibility editor; greys the list row),
  preview = bool/nil (the EYE icon: show this aura on screen while the panel is open — editor only),
  width=64, height=64, point={"CENTER",x,y}, alpha=1,
  lockAspect = bool/nil,  aspect = <w/h ratio captured at lock time> or nil,
  showLabel=true, texture = <path/fileID or nil=spell icon>,
  color = {r,g,b} or nil,  desaturate = bool/nil,  blend = <mode or nil=BLEND>,
  strata = <mode or nil=HIGH>,  sound = { file, name, channel } or nil,
  trigger = { logic="AND"|"OR"|"NONE", conditions = { <leaf> | <group>, ... } },  -- one-level groups
    -- leaf = { spellID, state, name };  group = { logic="AND"|"OR"|"NONE", conditions={ <leaf>,... } }
    -- AND=all, OR=any, NONE=nor(NOT any). EvalTrigger recurses; WatchedSpells recurses (CollectCondSpells).
  visibility = { combat="in"|"out"|nil, target="has"|"none"|nil, casting/mounted/vehicle/
    instance/encounter/resting/stealthed/group/raid/warmode/alive = true/nil,
    specs = { [specID]=true } or nil, spellKnown = spellID or nil },
  group = <groupID> or nil,   -- which group this aura belongs to (nil = Ungrouped)
  text = { show=bool, str="custom text"|nil(=aura name), font=path|nil, size=N|nil,
    outline="NONE"|"OUTLINE"|"THICKOUTLINE"|nil, anchor="BOTTOM"|"TOP"|"CENTER"|"LEFT"|"RIGHT"|nil,
    x=N|nil, y=N|nil, color={r,g,b}|nil },   -- on-screen label; nil ⇒ legacy showLabel+name
  glow = { type="autocast"|"pixel"|"proc"|"button"|nil(=none), customColor=bool|nil,
    color={r,g,b}|nil },   -- LibCustomGlow effect; active while the frame is shown
  kind = "texture"(default/nil) | "bar",   -- display KIND (since 2026-07-09). nil/"texture" = the icon
                                           -- display (all existing displays); "bar" = a StatusBar.
  bar = { mode="aura_dur"|"stacks"(|"cd_dur" later), texture=<LSM statusbar name|nil=white fill>,
    color={r,g,b}|nil(=orange), bg={r,g,b,a}|nil, orientation="HORIZONTAL"(default)|"VERTICAL",
    reverse=bool|nil, fill="fill"|nil(=drain), unit="player"|"target"|nil(=auto-resolve),
    max=N|nil(stacks: bar span, default 10), showValue=bool|nil(stacks: overlay the count number) } }
    -- Bar rendering + source config. The bar's SOURCE spell = cfg.spellID (NOT cfg.bar.spellID — that
    -- design-doc field was dropped: cfg.spellID is the single source of truth, so show/hide reuses the
    -- normal auto-path). aura_dur feeds the source aura's duration OBJECT to SetTimerDuration; stacks
    -- feeds the aura's (secret-in-combat) `applications` to SetValue + SetText. UNIT is auto-resolved
    -- (CDM:ResolveAuraUnit): selfAura is a hint, but if the aura isn't on that unit while the item's
    -- auraInstanceID is present it flips to the other unit — auto-corrects selfAura LIARS (Freezing).
```
`GA.db.groups[<groupID>] = { id, name, order, enabled (false=off), collapsed (bool),
visibility = <same shape as an aura's visibility> or nil }` and `GA.db.groupSeq` (the "gN"
id counter) + `GA.db.ungroupedCollapsed` (bool) — all now PER-PROFILE (moved off the top level in the
schema-2 migration). A grouped aura shows only when its **group is on AND the group's load rule passes**
— ANDed in front of the aura's own Visibility + Trigger.
`GA.db.hideBlizzardCDM = true/nil` (PER-PROFILE; hides the four Blizzard CDM viewers via alpha-0).
`GA.global.minimap = { hide, minimapPos }` (LibDBIcon, account-wide). Display shows when its **Trigger**
passes AND its **Visibility** gate passes (no visibility set ⇒ always eligible); an `enabled=false`
(Disabled) aura never shows/tracks. **Editor preview:** while the panel is open, `Displays:RefreshForced`
shows ONLY the selected aura + `preview`-on (eye) auras — NOT all of them (was "all enabled" before 2026-07-08).
`state` ∈ `buff_active | buff_inactive | cd_ready | cd_oncd`. **No trigger** (after Group+Visibility pass):
if `cfg.spellID` set ⇒ auto-behavior (its own spell: buff→active, cooldown→available); if NO `spellID` ⇒
**decoration, always shown**. New auras (`+ Add Aura`) are blank/decoration; spells are added via the
Trigger only. Width/Height range 8–8192, offset slider ±2000 (drag/`/ga pos` un-clamped).
`GA.global.panelPos` stores the panel location (account-wide); `GA.global.schema = 2`. (The old
top-level `displays/groups/seq/groupSeq/hideBlizzardCDM/ungroupedCollapsed/media` keys are removed by the
migration.)


## Texture picker sourcing (verified 2026-07-07 — do NOT relitigate)
- **Game icons** are enumerable from the client: `GetMacroIcons`/`GetLooseMacroIcons`(+Item variants)
  fill a table with fileIDs + loose `Interface\ICONS\<name>` strings (Blizzard's own IconDataProvider
  pattern). No names to search by → browse-only.
- **The pretty aura shapes are NOT game files** — they're bundled inside WeakAuras/PowerAuras/TWA.
  We bundled them (copied TWA's `Media/Textures` + `PowerAurasMedia/Auras`, generated the manifest
  from TWA's `Private.texture_types`, rewrote paths TWA→GloomsAuras). No-extension `.tga` paths
  render fine in this client (mirrors TWA's working setup verbatim).
- **LibSharedMedia only carries bar/border/background textures**, not aura shapes — so its category
  is bar textures. StoneTweaks registers its *Textures* there as `statusbar`.
- **StoneTweaks Graphics** (the useful custom art) are NOT in LSM; they're files listed in
  `StoneTweaksDB.graphics` = array of `{name,file}`, path `Interface\AddOns\StoneTweaks\Graphics\<file>`.
  We read that table live at picker-open (reading another addon's SavedVariables global is fine).


## Current in-game context
- **the owner's MAIN this season is Affliction Warlock** (added 2026-07-08) — char **"Gloomwick - Stormrage"**
  (CORRECTED 2026-07-08 sixth session — the handoff previously said "Gloomvale"; that's actually his HUNTER.
  Confirmed from SavedVariables: the **Gloomwick** profile holds the Warlock DoT auras, the **Gloomvale** profile
  holds the Hunter auras), account `AELWYN`. His CDM **Tracked Bars** hold Haunt (48181), Corruption (146739), Agony (980), Unstable
  Affliction (1259790), Seed of Corruption (27243) + the Curses; **Tracked Buffs** incl. Nightfall (264571);
  Burning Rush (111400, a self-buff that sits in BuffBar → `selfAura=true`). He also runs **ArcUI**, which
  tracks these DoTs correctly — the reference implementation for the §9 approach. The Hunter below is still
  relevant for the charge (Aimed Shot) work. **QA discipline reminder: he wants to be thorough; frame every
  build as a hypothesis to verify in-game, never as done.**
- The owner also plays a **Frost Mage** (added 2026-07-09, for the stacks/bars work). Core mechanic: **Freezing**,
  a stacking **target debuff** (spellID **1246769**; the CDM lists it under the linked cooldown **"Shatter",
  cooldownID 93744**; stacks to **20**, consumed 6-at-a-time by Ice Lance). He has an ArcUI segmented bar for
  it. This is the reference case for the Stacks bar mode (see the Stacks investigation above + BARS-DESIGN.md).
- The owner plays **Marksmanship Hunter** (**Dark Ranger** hero talents) on char **"Gloomvale - Stormrage"** (its
  profile holds the Hunter auras). Relevant IDs: Trick Shots buff
  **257621**, Rapid Fire **257044** (non-charge cd, works), Aimed Shot **19434** (2 charges — availability
  walled), Precise Shots **260240** (buff), **Kill Shot 53351 → override Black Arrow 466930** (Black Arrow
  replaces Kill Shot; a **1-charge** cd — see the charge learning above; his working aura = "Precise Shots
  active AND Kill Shot cd_ready"). His SavedVariables has displays incl. Trick Shots, Rapid Fire, Kill Shot,
  Aimed Shot, plus experiments. He now also has an **"MM Hunter"** group (load rule = spec).
- His Warlock (main) character/profile is **"Gloomwick - Stormrage"**; his Hunter is **"Gloomvale - Stormrage"**
  (account folder `AELWYN`; both profiles exist and are correctly populated). After Phase-3 QA he may have
  leftover test profiles (e.g. "Copy Test") — harmless; deletable from the Profiles drawer.


## Git / packaging
Now a **git repo** (initialized 2026-07-07). Mirrors GloomsBuildBarn's setup:
- `.gitignore` excludes `.DS_Store`, `/.release/`, `Libs/` (see below), `.claude/settings.local.json`.
- `.pkgmeta` (BigWigs packager) `package-as: GloomsAuras`; **`Libs/` is NOT committed** — the packager
  fetches **LibStub / CallbackHandler / LibSharedMedia / LibCustomGlow** into `Libs/` at release time.
  (LibDataBroker + LibDBIcon were **dropped in Phase D** with GA's minimap button — the Hub owns the one
  suite launcher now.) The owner's live working copy keeps its `Libs/` (gitignore doesn't delete), so
  nothing breaks locally.
- **`.github/workflows/release.yml` added in Phase G (2026-07-24)** — GA had a `.pkgmeta` but no workflow
  to run it, so it could never publish. It must keep `permissions: contents: write`; the org sets
  `default_workflow_permissions: read` and a workflow without that block fails at publish time.
- ★ **Release state is a SUITE fact — home of record `~/GloomsHub/docs/SUITE-STATE.md` (Phase G row).**
  GA shipped its first release, `v1.0.0`, on 2026-07-24 alongside the rest of the suite.
- **Committed** bundled art: `Media/` (fonts, `bg_flame.png`, `minimap.png`, `Textures/`,
  `TextureManifest.lua`) + `PowerAurasMedia/Auras/`. These are ours, not packager-fetched.
- **Push status:** LIVE on GitHub — https://github.com/GloomSuite/GloomsAuras (created + pushed
  at the end of the 2026-07-07 session, after the handoff was first written). `origin` is
  `https://github.com/GloomSuite/GloomsAuras.git`, tracking `main`. NOTE before making it public/
  wide: the repo bundles WeakAuras/PowerAuras textures (GPL-family) — fine for guild use, worth a
  license glance if published widely.

