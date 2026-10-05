# GloomsAuras — Session Handoff  (last updated 2026-10-04)

> ## ▶▶▶ 2026-10-01 → 04 — TRIGGERS THAT DON'T COME FROM THE COOLDOWN MANAGER, PICKERS, FIXES
> - **Other Triggers** (the triggers footer's middle button, a menu): three leaf kinds outside the CDM,
>   each with its own `k` and NO `spellID` (so Discover never tries to bind it):
>   - **Target Casting** (`k = "tcast"`, `tcast_any` / `tcast_kick` / `tcast_nokick`). Casting is
>     PLAIN (cast events + a nil test). The interrupt flag is SECRET even in the open world (Hub
>     FINDINGS §26): `CDM:KickGate` turns it into the display frame's alpha via
>     `EvaluateColorValueFromBoolean` (`D:SetGate`; ignored while previewing), and `CDM:KickSecret`
>     SKIPS the trigger sound then — a sound can't be gated by a secret. A plain flag (none measured so
>     far) is a real condition in `EvalCondition`.
>   - **Buff Running Low** (`k = "blow"`, `blowN` = missing or under N minutes; `name` + `buffID`):
>     OUT OF COMBAT ONLY (your own buffs read plain then; in combat it's false). Polled every 5 s.
>   - **Trinket Ready** (`k = "item"`, `item_ready` / `item_oncd`; `itemID` + `useSpell`): reads the
>     ITEM's cooldown (`CDM:ItemOnCooldown`) — plain out of combat; in combat the secret start /
>     duration go into a hidden Cooldown widget (fallback: the use-spell's duration object). The CDM
>     leaves trinkets out inside delves (FINDINGS §27). `/ga trace` prints `route=`.
> - **Late CDM icons:** `CDM:Discover` is wrapped — while any watched spell is unbound it retries at
>   1 / 3 / 8 / 20 s; PLAYER_EQUIPMENT_CHANGED re-runs it; the aura list redraws after each (its
>   "not in your Cooldown Manager" warning is worked out when the list draws).
> - **Load-condition pairs fixed** (`P.buildLoad`'s `pair`: `if a and b then w[key] = nil else …`);
>   the old `(a and b) and nil or …` meant neither box of a pair could change since 2026-09-24.
> - **Bar auras go down to 1 px** (others stay at 8; the dials go to 1, the setters hold non-bars).
> - **The spell / shape / texture / sound pickers are Suite windows** — `KitWindow(name, W, H, title)`
>   + `ShowKitWindow(win)` in Config.lua: `UI.gWindow` on the Suite root, built like the Hub's Texture
>   Browser, opened beside the settings window. Build any future picker the same way (Hub LESSONS).
>
> ## ▶▶▶ 2026-09-27 (late) — TYPES, THE EYE, DIMMING, TYPE SWITCHING
> - **Icon / Texture / Bar are real types** (`P.AuraType`: `kind == "bar"`, else `uiType == "texture"`,
>   else Icon — an aura from before `uiType` was saved counts as Icon). An Icon is CREATED with no
>   `texture` (its first trigger's spell icon; the red question mark `134400` until then — Displays.lua's
>   fallback, magenta only for a Texture aura); a Texture on the white sphere. The tab shows the type.
>   The owner REJECTED merging Icon and Texture.
> - **Right-click → Duplicate As… / Change Type…** — `P.convert(id, cfg, to)`: every type's fields are
>   kept (switching back restores the look); the size is remembered per side (`cfg.barSize` /
>   `cfg.artSize`, defaults 220 × 24 / 64 × 64); leaving a bar Detaches the duration engine; a copy lands
>   just right of the original.
> - **The eye** — `D:EyeOn(id)` / `D:ToggleEye(id)` in Displays.lua: `cfg.preview` is the saved eye while
>   NOT selected; the selected aura shows regardless (`D.selShow`, fresh on each new selection) and its
>   eye toggles only that.
> - **Dimming by type (the audit — every control traced to its read site):** a bar dims the art
>   settings (Icon/Art, Shape, Blend, Recolor, Desaturate, Rotation, Effects Only) and Animation; Effects
>   Only dims the art ones; Countdown needs Bar Type Aura Duration; Stack Text dims on Cooldown; Fill
>   Direction on Stack Count; Font unless a readout shows; Pandemic Color unless the spell sends the
>   pandemic alert. **Bar Fill & Readouts is LOCKED shut** on a non-bar (the Hub's section `locked`).
>   A section now syncs its dimming when BUILT and when shown (`Synced` + `onShow` — it used to wait
>   for the next aura switch). Stack Text Position's unset default now reads Center in Stack Count mode.
> - **A tooltip on every setting** (`tip(ctrl, title, body)`; the kit waits 1 s).
> - Leftovers: Hub BACKLOG 20 (a Bar Type mismatch note; Opacity vs the engine's drain fill, unproven).


> ## ▶▶▶ 2026-09-27 — THE AURAS TAB IS NOW TWO WINDOWS (`Pages.lua`, rewritten again)
> **Suite-wide facts live in the Hub: BACKLOG 16, CONTRACTS §2 (the two-window block) and §4 ("THE
> TWO-WINDOW KIT"), FINDINGS §22. Not restated here.** Status: built, harness-verified, owner testing.
>
> - `RegisterTab{ windows = true, selector, tab, sections, globals, onBuilt/onOpen/onClose }`. Each
>   section is its own 360-wide frame at the mock's coordinates INSIDE the section (two columns 0/190).
> - The **selector** is the old Aura Groups list (same rows, menus, drag), sized from the WINDOW
>   (`P.listHost`) — the list re-renders on resize. New Aura / New Group at its foot.
> - The **tab** (one per window — settings + each pop-out; `P.syncHeader` refreshes them all): icon +
>   name; click = the LIST of auras to switch to (`P.auraSwitch` — the owner, 2026-09-27: "not rename
>   the current one"), right-click = `P.auraContext` (Rename · Duplicate · Move to Group · Delete).
> - 2026-09-27, the owner's first in-game round: the Font controls are the kit's list (`FontDrop`,
>   each name in its own face — `X.fontData`); Displayed Text DIMS while Show Charge Count is on (the
>   count replaces it); an aura's on-screen text draws on its own frame (`f.textTop`, display level
>   +10) because it sat UNDER a bar aura's bar; colors offer "Use Class Color" (`Core.lua` stamps them
>   at login — CONTRACTS §4). `Pages.lua` needs LibGloomSkin 17.
>   Duplicate/Delete/Move moved here from the old header (`P.duplicateSelected`, `P.deleteSelected`,
>   `P.groupMenu`).
> - **Triggers**' Add a Trigger / Create Trigger Group are its section FOOTER (pinned to the window's
>   foot). `P.renderTriggers` sets the section's height and calls `GloomsHub:RefreshWindows("auras")`.
> - **Effects** grows/shrinks with the animation's params (two to a row); **Max Stacks** is a FIELD now.
> - A group's Load Conditions is `P.groupLoadWindow()` — a `UI.gWindow` of its own (joins the focus
>   stacking via `GloomsHub:SuiteManage`).
> - **Hide Blizzard CDM** moved to Global Settings (`globals`); `C._hideCDM:Set()` → RefreshWindows.
> - `X.SetContainer(settingsWindow)` (onBuilt): pickers dock to the settings window's right edge.
>
> *(The 2026-09-25/26 glass block below is superseded.)*


> ## ▶▶▶ 2026-09-25/26 — THE AURAS TAB IS REBUILT AGAIN: the GLASS design (`Pages.lua`, rewritten)
> **Suite-wide facts live in the Hub: BACKLOG 16 (status, decisions, what is un-mocked), CONTRACTS
> §2 (the glass shell) and §4 "THE GLASS KIT", FINDINGS §22 (sharpness). Not restated here.**
> **Status: built, harness-verified (0 errors), SEEN in game by the owner; page-by-page review open.**
>
> - `Pages.lua` draws at the mocks' WINDOW coordinates (the container is the whole window now — no
>   more "x − 250"). Each page registers `bg = GLASS .. "<page>"`; the tiles are `Media/glass/<page>-a|b|c|d.png`
>   (made by `~/GloomsHub/tools/gen-glass-art.py bg` from the owner's exports — never edit them by hand).
> - **Groups are no longer "selected".** A plain click folds; RIGHT-CLICK → Rename · Enable/Disable ·
>   Load Conditions… (a pop-up, `P.groupLoad`, built by the same `P.buildLoad` as the Load page, over
>   the page panel) · Delete Group; DRAG a group header to reorder (writes `groups[id].order`).
>   `C:SelectGroup` now opens that pop-up; `P.show` clears `C.groupSel`. The old group PANE is gone.
> - The trigger state is a DROPDOWN: `Config.lua` gained `C:TrigStates(ti, ci)` (the same family
>   rule `TrigCycleState` walks) and `C:TrigSetState(ti, ci, state)`.
> - `STRATA_MODES` gained **BACKGROUND** (the mock shows it). Width/Height are linked by the
>   BRACKET (same `cfg.lockAspect`/`cfg.aspect` as the old padlock).
> - **Max Stacks** sits in the Stack Text column and DIMS unless Bar Type = Stack Count (it used to
>   hide). A control's label dims with it (`ctrl._label`).
> - Hide Blizzard CDM is an OFF/ON switch at 30,711 (still `C._hideCDM` with `:Set()`).
>
> *(The 2026-09-23 block below describes the SECOND design's Pages.lua — superseded; kept for its
> reasoning about `C.X` and the unmounted old editor, which still holds.)*


> ## ▶▶ 2026-09-23 — (SUPERSEDED 2026-09-25) the SECOND design's six pages (`Pages.lua`)
> **Suite-wide facts live in the Hub: BACKLOG 16 (status, what is un-mocked, the decisions),
> CONTRACTS §2 (the paged shell) and §4 "THE DARK KIT". Not restated here.** GA detail only.
> **Status: built and verified OUTSIDE the game (`~/GloomsHub/tools/harness`) — the owner has NOT
> reviewed it in game yet.** Expect his fixes first.
>
> **The shape of it.** `Pages.lua` (new, after `Config.lua` in the TOC) registers the tab as a PAGED
> tool (`pages` + `accent = jade` + `showPage` + the profile api for the sidebar) and DRAWS: the
> aura list, the selected aura's header, and six pages at the mocks' coordinates (window x − 250).
> **Every setting still goes through `Config.lua`'s logic**, exported as ONE table, `C.X` (DB, Cfg,
> SetSelected, RefreshList, the trigger tree via `C:Trig…`, the pickers, profiles, `rows`…) —
> Config.lua's main chunk is near the 200-locals cap, so it stays one table.
> - `Config.lua` NO LONGER registers the tab. Its previous editor (`BuildTab`, the accordion, every
>   `Build*Section`, the old list) is **unmounted but kept** until the owner approves — the record of
>   how each control behaves. `RefreshList` now ends in `C:OnListRefresh()`.
> - `Pages.lua` REPLACES these `C` methods (the old editor's callers find them): `AccordionLayout /
>   SetHeight / Open / Toggle` (no-ops), `TrigInlineRender`, `ShowGroupPane`, `RefreshGroupPane`,
>   `UpdateEmptyState`, `SyncRailButtons`, `RefreshGroupButton`, `OnListRefresh`.
> - Controls join the shared `rows` (refresh + setEnabled, driven by `SetSelected`); `P.sync()` re-runs
>   them after a change another control's enabled state depends on (dim, never hide).
> - It gates itself on LibGloomSkin **13** (prints "update Gloom's Hub" and does not register below).
>
> **What changed in behaviour** (the owner's rulings, 2026-09-23 — BACKLOG 16 has them):
> - **Trigger groups by DRAG** — a condition row drags into a group box or back onto the page;
>   `P.dissolveGroup` (a group's X) puts its conditions back at the top level. Shift+click grouping,
>   the AND/OR brackets and chips are gone. Each group shows its own Match pills.
> - **Load Conditions** are checkboxes over the SAME storage: combat/target pairs map to
>   `"in"/"out"/nil` and `"has"/"none"/nil`, specs to a set-or-nil; the last of a pair / of the specs
>   can't be unticked. Nothing saved changes meaning.
> - **Animation settings are INLINE** (the popup is unused): a block per module, built once from its
>   `params` schema and cached (`EF.blocks`); a colour param sits beside the type (unticked = the
>   module's own colour).
> - **Level** — new `cfg.level` (Displays.lua; `_baseLevel` remembered so clearing restores it).
> - Placed without a mock (listed in BACKLOG 16 for his review): Hide Blizzard's CDM at the list's
>   foot, the width/height lock by SIZE, Stacks Max only in Stack Count mode, right-click clears a
>   bar texture, the group pane, rename = click the header name, move group = click "Group:".
> - The eye is `Media/eye.png` for both states (tinted); the silent-yes mark is `Media/warn.png`.
>
> ⚠ **Traps met building it:** `LibStub and LibStub(x, true)` drops the minor (Hub LESSONS);
> a page frame must be SIZED to its content (`pg:SetHeight`) or `IsMouseOver` — the drop target
> for a dragged condition — only covers its top 10px; a pillField's placeholder must also hide on a
> CODE `SetText`. The pickers (texture/sound/font/shape/spell), dialogs and colour picker still wear
> the first design — no mocks yet.


> ## ▶ 2026-09-21 — the Suite window went light (Hub BACKLOG 16, stage 1); GA's tab is untouched
> **The whole Suite UI is being rebuilt from the owner's Figma mocks; GA's seven panels are
> stage 4.** Until then the Auras tab draws through the Hub's TRANSITION THEME (dark text tokens,
> light plates — Hub CONTRACTS §1). The one GA edit: **19 hard-coded white labels / edit-box
> texts in `Config.lua` became the `TEXT` token** (they were invisible on the light plate). No
> behaviour changed. **Do not restyle or tidy the tab on its own** — it is rebuilt from its mocks
> in its stage.

> ## ▶▶▶ 2026-09-20 — the clearing session: `ApplyConfig` heat FIXED, five backlog items closed
> **The measured records are `~/GloomsHub/docs/FINDINGS.md` §1 (the heat), §12 (the silent-yes
> trace) and §14 (the icon fallback). Read those; not restated here.** GA detail only.
>
> **`ApplyStyle`'s guard changed shape (`AuraDuration.lua`).** It keys on the painted BUTTON + style
> fingerprint, both stored on the SLOT (`sub.paintedButton` / `sub.paintedSig`) and written by
> `WireButton` at init AND by `ApplyStyle` on a successful paint. The fingerprint check now runs
> BEFORE the combat deferral. `Attach`'s retarget path and `SetSlotActive` **no longer clear
> anything** — the old `styleSig = nil` lines were the heat (1,165 repaints / deferrals per 30 s
> fight). ⚠ A fresh button is still never skipped: its identity differs. A style throw now says
> so in chat once per display per session — the debug flag does not survive `/reload`, so
> "turn on debug, reload, read the throw" could never work.
>
> **Instruments, both OFF by default:** `/ga hot on` → `/ga hot` → `/ga hot off` (caller-keyed
> counts of `ApplyConfig` / `ApplyStyle`; `debugstack` per call is not free) · `/ga known` (every
> display's spell next to the three known-calls, its override, and whether the CDM bound it —
> read-only).
>
> **The silent-yes mark (`Config.lua`, `C:SilentYesText`):** an orange `!` beside the eye on an
> aura row whose cooldown-state trigger points at a spell the CDM has NOT bound and which carries
> no Spell-Known / Specialization rule; for `cd_castable` only while `IsSpellUsable` says yes.
> Informational only. The engine known-check is DISPROVED (FINDINGS §12) — do not build it.
>
> **Boxes that commit on focus-lost now (they were Enter-only):** PLAYER POWER's value (item 7's
> "shows at any combo points"), SPELL / TALENT KNOWN's ID, `MakeText`'s texture path. Escape
> restores the stored value first. The power box also steps live on Up / Down (Hub MINOR 10
> `stepper`). `SKIN_NEEDS` stays 6 — the field is ignored by an older lib.
>
> **Icons:** a texture-less display shows its spell's icon (`DisplaySpellID`, the owner's ruling);
> the list rows resolve the same way (their `?` had the same cause). `CDM:Debug` resolves through
> `DisplaySpellID` too — item 8. That is FOUR `cfg.spellID` sites fixed; treat any new one as suspect.
>
> **Profile delete gate:** the rail's profile block passes `users(name)` from `GA.global.profileKeys`
> (Hub CONTRACTS §4).
>
> **Closed on owner evidence, no code:** Corruption / UA bars (item 1 — "using it for weeks"),
> the PLAYER POWER condition on a display and on a group (item 7, Rogue combo points), live raids
> for weeks (item 2). Item 3 (`/ga probe` leak) stays deprioritised and unfixed.

> ## ▶▶▶ 2026-09-19 — PANDEMIC BACKGROUND on bars
> **The measured record is `~/GloomsHub/docs/FINDINGS.md` §15 (the refresh signal) with §12 (the
> pandemic guard it rides). Read those; not restated here.** GA detail only.
>
> **What shipped, owner-QA'd on a Rogue with Garrote:** `cfg.bar.pandemicBg` (nil = off) — a
> "Pandemic Background" swatch under Background in the Bar section. While the tracked DoT is in its
> pandemic window the bar's BACKDROP wears that colour; it reverts the instant a refresh lands and
> is plain on a fresh cast.
>
> **How it is wired — four places, deliberately small:**
> - `CDM.inPandemic[displayKey]` — a plain boolean GA owns. SET in the deferred pandemic timer in
>   `OnItemAlertEvent`, right after `FireBucketSounds("pandemic")`, so both spurious-alert guards
>   have already passed (never hook `PandemicTime` a second time). CLEARED on the aura's own
>   apply/remove alerts, on hide (`RefreshDisplays`' hidden edge), on `Discover`, and — the one that
>   actually matters — on **`UNIT_SPELLCAST_SUCCEEDED` for the spell** (`CDM:OnPlayerCast`),
>   matched through `AuraDuration:CandidateSpellIDs`. `CDM:CastSince` keeps a refresh that lands
>   inside the 0.3s settle window from being painted over by the alert that preceded it.
> - `Displays:ApplyBarBackground(f, cfg, id)` — the backdrop paint split out of `ApplyBarStyle`,
>   picks `pandemicBg` when the flag is set. `Displays:RefreshBarBackground(id)` repaints ONLY that,
>   in combat, and must never route through `ApplyConfig` (that re-pushes the engine style, which
>   queues to end of combat). `ApplyBarStyle` now takes the display KEY as a third argument.
> - `Config.lua` — the swatch; every row below it in the Bar section moved down 37px and the
>   accordion height went 428 → 465.
>
> ### ⚠ Why the BACKDROP and not the fill — a wall, not a preference
> The visible fill of a duration bar is the engine's Blizzard `AuraButton` (§1 / this file's
> "READ THIS BEFORE ANY DoT WORK"): forbidden in combat, and a pandemic window happens nowhere else.
> A fill recolour would queue to `PLAYER_REGEN_ENABLED` — i.e. never be seen. The backdrop is GA's
> own texture on GA's own frame, already written in combat every fight. **The owner chose it on
> design grounds too:** by the pandemic point the bar is mostly drained, so the backdrop IS what is
> on screen. **Do not re-offer the fill.** Whether `SetStatusBarColor` alone would throw on the
> engine's region is `UNTESTED` and nothing depends on it.
>
> ### Traps
> - **`OnAuraApplied` does NOT fire on a refresh** (four of five measured refreshes were silent). The
>   first build keyed the clear on it and the owner saw the bar stay red. FINDINGS §15.
> - **`RefreshData` on the item frame fires on every tick of every tracked spell.** Useless as any
>   kind of signal; the probe was removed the same day.
> - **A cast that does not land** (dodge/miss) clears the colour early, and the alert cannot re-fire
>   for that instance. Accepted; cosmetic; the next real refresh fixes it.
> - Coverage is the pandemic SOUND's: only spells Blizzard emits `PandemicTime` for (UA stacks, so
>   never). `/ga trace` prints PANDEMIC / noPANDEMIC per bar.

> ## ▶▶ 2026-08-25 — SHAPES, SHAPED ANIMATIONS, EFFECTS-ONLY, ROTATION
> **The measured record is `~/GloomsHub/docs/FINDINGS.md` §14, and the API is Hub CONTRACTS §7-§8.
> Read those; they are not restated here.** GA detail only.
>
> ### What shipped, all owner-QA'd in game
> **Rotation** — `cfg.angle` (a fixed 0-359°, in Appearance) and `cfg.rotate = {on, dir, speed}`
> (a continuous spin, in Effects & Motion). Both share ONE AnimationGroup on `f.tex`: order 1 snaps
> to the angle, order 2 spins on from there, and with the spin off order 2 becomes a long
> zero-degree hold leg. ⚠ **This RETIRES the "deferred texture transforms" item below.**
> **`Texture:SetRotation` was deliberately NOT used** — it works through texture COORDINATES and
> would fight the `SetTexCoord(0.08, 0.92, …)` border trim every spell icon carries, which is
> exactly why rotation sat parked. A Rotation *animation* transforms geometry and leaves texcoords
> alone. The group is frame-owned with `SetChildKey("tex")` — LibCustomGlow's own pattern, checked
> in `Libs/` rather than guessed at. Mirror and Texture Wrap are still deferred.
>
> **`cfg.shape`** — clips the texture to one of the Hub's 21 silhouettes, via a grouped thumbnail
> picker whose geometry mirrors GB's so the two read as one control.
>
> **`cfg.noArt` ("Effects only")** — the aura draws NOTHING and contributes only its effects, so it
> can sit over a live action button and let the button's own icon show through. ⚠ **This is a
> distinct state from an empty `cfg.texture`**, which means "work it out" and ends at the loud
> magenta panel. That panel is right for an aura meant to show art and wrong for an overlay, which
> is why "unset" could never be made to mean this. **This is the feature the owner actually wanted**
> when he asked for a glow on his Cataclysm button.
>
> **`cfg.effects`** — the Hub's eight animation modules, with a settings popup built from each
> module's own `params` schema, so a module added in the Hub grows controls here with no GA change.
>
> ### Traps this cost real time on — do not re-learn them
> - **`AddMaskTexture` silently fails on a never-rendered texture** (GB API-NOTES §2), and
>   `ApplyConfig` routinely runs while an aura is hidden. `OnShow` re-runs `ApplyShape` one frame
>   later. Without that, shapes work on visible auras and mysteriously not on hidden ones.
> - **`ApplyConfig` runs HOT** (suite backlog item 4). Rotation and effects BOTH carry
>   redundant-push guards. For effects that is a **correctness** fix, not an optimisation: every
>   `Start` primes its textures to alpha 0.02 and reveals a frame later, so an unguarded re-push
>   storm makes an animation invisible. FINDINGS §14.
> - **`MakeSlider` is INTEGER-only** (`math.floor(v + 0.5)`), so fractional module params are shown
>   ×100 as a percentage and divided back. It also lays out to `max(360, parent width)` and parks
>   its minus button at **x=70** with the title at x=4 — **any label past ~66px runs under the
>   control.** Both bit this session. Keep new labels short.
> - **A mask does not rotate with the texture it clips** — a shaped aura that also spins turns
>   inside a static silhouette. Real effect, but it is not "a spinning rounded square".
> - **Rotation drives `f.tex` and only `f.tex`.** With `noArt` it is inert, so the whole MOTION
>   block greys out. Leaving it live is how the owner got a Direction and a Speed that saved fine
>   and moved nothing.
>
> ### Ruled out by the owner, 2026-08-25 — do not re-offer
> **GA driving GB's glow on a real action button.** Offered twice as the exact fix for the Cataclysm
> case. *"I don't really want an aura telling GB what to do — that's a level of complexity that I
> suspect would introduce more problems than it solved."* He is content aligning by hand.
>
> ### Known, not fixed
> A texture-less aura draws the magenta panel instead of its spell's icon — `ApplyConfig` reads
> `cfg.spellID`, nil for everything built in the tab. Suite backlog item 9; the fix is the parked
> auto-icon feature and he has not decided it.

> ## ▶▶▶ 2026-08-24 — TRIGGERS + SOUND TIMING. Read this before the 08-12 block.
> **The measured record is `~/GloomsHub/docs/FINDINGS.md` §12. Read it; it is not restated here.**
> Everything below was driven by `/ga alertlog`, run four times across two talent builds.
>
> ### Three features shipped
> **`cd_castable` — a new trigger state, "castable right now."** `cd_ready AND IsSpellUsable`.
> `cd_ready` mirrors the COOLDOWN only and is blind to resource cost, target requirements and the
> procs that waive them — Shadowburn read "ready" for all of combat while being uncastable. Wired
> into `STATE_ORDER`, `STATE_LABEL`, `StateLabel`, `TrigPill` and the pill's cycle list (`READY →
> CASTABLE → ON COOLDOWN`, plus the two charge states on a charge spell).
> ⚠ **`IsSpellUsable` is still banned as a standalone availability signal** (API-NOTES). It is only
> ever used here to NARROW a cooldown answer GA already trusts. Do not loosen that.
>
> **PLAYER POWER — a new load condition.** `v.power = { type, op, value }` in `VisibilityGate`,
> whole units only (`UnitPower`'s partial third arg would give Destruction's shard FRAGMENTS, a
> different scale answering a different question). 17 power types in the dropdown. No new event: a
> power condition makes `HasVisibilityConstraints` true, which switches on the existing 0.2s poll.
> **⚠ NEVER RUN IN GAME — backlog item 7.**
>
> **"When it comes off cooldown" — a fourth sound timing (`sound.on = "ready"`).** Fires on a real
> `available` false→true transition, never on the display's shown edge, so entering combat with
> everything off cooldown is silent. Gated on Group + Visibility.
>
> ### The two traps this session cost most
> **`CDM:SetAvailable` is now the ONLY writer of `available`** — nine call sites converted. It
> judges a transition by **how long the cooldown lasted** (≥2s), NOT by which writer noticed.
> ⚠ Two earlier attempts failed here and both are recorded in FINDINGS §12: letting every writer
> speak double-fired, and "only real events may speak" silenced a REAL completion because
> `CooldownFrame_Clear` is not reliably fired. **Do not re-split by source.** A settle timer was
> also tried and REMOVED — it swallowed real sounds.
>
> **Discovery now prefers an EXACT `info.spellID` match.** `InfoMatchesSpell` also accepts
> override/linked IDs, and Blizzard links Malevolence's cooldown entry to Summon Infernal — so
> Infernal bound to Malevolence's widget and mirrored the wrong cooldown. The loose match remains
> the fallback for spells that only appear via an override; do not remove it.
>
> ### Also
> The alert path (`OnItemAlertEvent`) had **no visibility check at all** — alert-driven sounds fired
> wherever the spell fired, ignoring the display's own `combat = in`. Now Group + Visibility gated,
> via the extracted `CDM:FireBucketSounds`.
> A spurious `PandemicTime` lands within ~0.15s of `OnAuraRemoved` **on either side** — guarded both
> ways (a timestamp check after, a 0.3s deferral before). A one-sided guard was tried first and
> caught only half.
> `/ga alertlog` now also records `available` transitions and each ready-sound fire.

> ## ▶▶▶ 2026-08-12 — DURATION BARS ARE BUILT AND OWNER-QA'd. Read this before the 08-03 block.
> **The suite-wide record is `~/GloomsHub/docs/FINDINGS.md` §1 (the SHIPPED block) and §10. Read
> those; they are not restated here.** GA-specific detail follows.
>
> ### The two new files
> **`AuraDuration.lua` + `AuraDuration.xml`** — GA's first XML, and it exists only because
> `SetDurationBar`/`SetDurationText` refuse any region the AuraButton does not OWN. The four rules
> that make the engine work are written at the top of the `.lua`; **read them before touching it.**
> `/ga auradur` reports counters (attach / initFired / style applied-skipped-deferred-threw), and
> `/ga auradur debug` logs each paint. Those counters are the only instrument — the failures here
> are silent.
>
> ### What the Bar section looks like now
> A new accordion section, **"Bar Fill & Readouts"**, between Appearance and Text. Bars previously
> had **no editor UI at all**. It carries: fill mode · direction · texture (+ **Clear**) · bar colour
> · orientation (which SWAPS width/height) · background · reverse fill · rotate texture · both
> readouts with independent position / colour / size · a shared font · Stacks Max (hidden outside
> stacks mode). `Config.lua`'s main chunk stayed at **173 of Lua's 200 locals** — every local in the
> builder is function-scoped on purpose. **Check that count after any edit to this file.**
>
> ### Config keys that changed
> **`cfg.bar.showValue` is RETIRED.** Two flags now: **`showTimer`** (the engine's countdown) and
> **`showStacks`** (the count, on any bar). `Core.lua`'s login path migrates old configs across
> **every profile**, and it is idempotent. New keys: `timerAnchor`/`stackAnchor`,
> `timerColor`/`stackColor`, `timerSize`/`stackSize`, `font`, `rotateTexture`.
>
> ### ★ `CDM:DisplaySpellID` — use it, never `cfg.spellID`
> A display created in the Auras tab has **no `cfg.spellID`**; its spell lives in the first trigger
> condition. That silently disabled anything keyed on `cfg.spellID` — bars built in the UI could
> never get a duration, and the sound warning never fired for Unstable Affliction. The resolver is
> wired into `AuraDuration:Attach`, `CandidateSpellIDs`, `BarSource`, `BarStackValue` and the
> `cd_dur` feed. ⚠ **This last change is the one thing from the session the owner never tested.**
>
> ### Deleted, do not rebuild
> The Tracked-Bar mirror — `CDM:BarMirrorValues`, `Displays:StartMirror`/`StopMirror`. It worked but
> required the user to add each aura to Blizzard's Tracked Bars by hand. Both files carry a comment
> saying so.
>
> ### Two traps this session paid for, in GA's own code
> - **The editor preview blanks GA's bar.** `UpdateBar` calls `f.bar:SetValue(0)` on a successful
>   attach so the engine's fill isn't masked — but NOT while `Displays.forced` (the panel is open),
>   or the user styles an invisible bar. Removing that guard re-creates a three-theory bug.
> - **`MakeSlider` labels have a 66px budget** — the "−" button is pinned at x=70. "Countdown Size"
>   ran underneath it. Keep slider labels short, like every other one in the tab.
>
> ### ⚠ Known limitation, closed as not-our-bug
> **A display does not come back after a mid-combat `/reload`** until the aura is re-applied. The CDM
> never re-binds an already-applied aura to its item frame — `TESTED` over 52 passes. Three fixes
> were attempted in `RepollBuffPresence` and all failed; the function carries a comment. **Do not
> attempt a fourth there.** FINDINGS §1 names the only viable route if it ever matters.

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

## Undo (2026-09-30) — the Hub's
The Hub's suite-wide UNDO covers Auras through the `undo` block in `Pages.lua`'s RegisterTab: a
snapshot is a deep copy of `GA.db` (the active profile); putting one back patches it in place and
calls `GA.RefreshForProfile()`. Nothing else in Auras changed.

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

**12.1 makes aura instance IDs SECRET in combat, and every read call throws.** GA can never READ a
duration. That is `TESTED` and permanent.

~~It is the suite's biggest open item and needs a design decision.~~ **CLOSED 2026-08-12 — the
design decision was made and BUILT.** GA now DISPLAYS durations and stacks without reading them, via
`AuraDuration.lua` (the engine) and `frame.auraDataCached` (stacks). See the block at the top of
this file and `~/GloomsHub/docs/FINDINGS.md` §1.

**The rule that still stands: never try to obtain the number.** Every fix on this path works by
handing a sink something Blizzard computed, or by letting Blizzard render into a region it owns.

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

⚠ **The owner explicitly deprioritised this on 2026-08-12.** It is a dev tool, it cannot bite
a Warlock, and he does not want it raised unless it affects normal play. Fix it silently if you
are already in the file.

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
- **Deferred texture transforms** — ~~Rotation~~ **SHIPPED 2026-08-25** (see the block at the top:
  an AnimationGroup Rotation, never `Texture:SetRotation`). **Mirror and Texture Wrap are still
  deferred**, and for the same reason: both go through `SetTexCoord`, which fights the icon border
  trim. If either is ever built, look at whether an animation or a second texture can carry it
  instead of touching texcoords.
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

