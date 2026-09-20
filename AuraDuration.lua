-- AuraDuration.lua — Gloom's Auras: the 12.1 duration engine
--
-- WHY THIS EXISTS. On 12.1 an addon cannot READ an aura's remaining duration:
-- every instance-ID call (GetAuraDataByAuraInstanceID, GetAuraDuration, stacks)
-- throws while tainted and auras are secret. `TESTED` 2026-08-03 — see
-- ~/GloomsHub/docs/FINDINGS.md §1. That kills the SetTimerDuration feed in
-- Displays:UpdateBar, because there is no duration object to feed it.
--
-- THE ROUTE THAT SURVIVES. The only object allowed to hold an aura's duration is
-- a Blizzard AuraButton. So we borrow one as an INVISIBLE ENGINE: per tracked
-- aura we add a spell-ID-filtered slot to an AuraContainer, and inside that
-- slot's initializeFrame we point the button's OWN regions (declared in
-- AuraDuration.xml) at our display's bar. Blizzard renders the drain and the
-- countdown into regions it owns; GA never obtains a number, which is exactly
-- why it survives secrecy. Proven on this client by ArcUI's implementation,
-- which reports rawReads=0.
--
-- ⚠ THE FOUR RULES THAT MAKE OR BREAK IT — all four are load-bearing:
--   1. Containers are created OUT OF COMBAT ONLY. In-combat creation is a hard
--      Lua error, not a soft failure. (Adding a SLOT to an existing container
--      mid-combat is fine — only creation is locked.)
--   2. EVERY button API call happens inside initializeFrame and NOWHERE else.
--      That is the one window in which the button is not a forbidden object.
--      Afterwards, any call on it errors whenever auras are secret.
--   3. The bar/text regions must be OWNED BY THE BUTTON — declared in the XML
--      template, reached by parentKey. An addon-created frame is refused, and
--      reparenting one detaches the duration binding.
--   4. Detach NEVER touches the button. Park the slot's filter on a spell ID
--      that can never match and let the ENGINE release and hide it; engine-side
--      hides are always legal.
--
-- ⚠ AND ONE TRAP WITH NO PROBE. There is no reliable test for "is the button
-- touchable right now". IsForbidden() reads FALSE while the very next call
-- throws. The gate is environmental — aura secrecy tracks combat/encounter — so
-- anything that must touch a button defers on InCombatLockdown/IsEncounterInProgress
-- and re-runs on PLAYER_REGEN_ENABLED. Do not add an object probe; it will lie.

local ADDON_NAME = ...
local GA = _G.GloomsAuras

local issecret = _G.issecretvalue or function() return false end

local AD = {}
GA.AuraDuration = AD

AD.debug = false
local function Log(fmt, ...)
  if not AD.debug then return end
  print("|cff936bff[GA:auradur]|r " .. ((select("#", ...) > 0) and fmt:format(...) or fmt))
end

-- Counters, not booleans. FINDINGS §1 records that these failures are SILENT —
-- BugSack stays clean while nothing happens — so the diagnostic has to show
-- WHERE the chain stopped, not just that it did. `/ga auradur` prints these.
local diag = { attach = 0, containerNew = 0, slotNew = 0, retarget = 0, initFired = 0,
               combatDefer = 0, combatCreate = 0, noCandidates = 0, detach = 0,
               styleApplied = 0, styleDefer = 0, styleThrew = 0, styleSkipped = 0 }
AD.diag = diag

local containers    = {}   -- [unit]      -> AuraContainer
local attached      = {}   -- [displayID] -> { spellID, unit, key, sub, spellIDs, dir }
local pending       = {}   -- [displayID] -> { f, cfg } awaiting out-of-combat
local styleDeferred = {}   -- [displayID] -> { f, cfg } style push that arrived while secret
local seq           = 0

-- --------------------------------------------------------------------------
-- Availability. The AuraContainer/AuraButton intrinsics do not exist before
-- 12.1, so on any older client this module has to stay completely inert rather
-- than error. Settled once, lazily, by trying the create — there is no version
-- constant we control that is honest about a PTR build.
-- --------------------------------------------------------------------------
local available   -- nil = not yet determined, then true/false
function AD:IsAvailable()
  if available ~= nil then return available end
  -- ⚠ No combat guard here any more. It used to refuse to answer in combat, which meant a
  -- /reload DURING a fight left `available` undetermined and every attach queued — no duration
  -- bars for the rest of that fight. The probe below is a pcall'd CreateFrame, which is safe to
  -- attempt in combat: worst case it fails and we answer false, which is the old behaviour.
  -- The direction/interpolation enums are as required as the intrinsic itself:
  -- without them WireButton would nil-index INSIDE initializeFrame, where a throw
  -- is expensive. Displays:UpdateBar guards them the same way before SetTimerDuration.
  if not (Enum and Enum.StatusBarInterpolation and Enum.StatusBarTimerDirection) then
    available = false
    return false
  end
  local ok, frame = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
  available = (ok and frame ~= nil and frame.AddAuraSlot ~= nil) and true or false
  if ok and frame then frame:Hide() end
  Log("IsAvailable → %s", tostring(available))
  return available
end

-- --------------------------------------------------------------------------
-- The candidate spell-ID set.
--
-- ⚠ cfg.spellID alone is NOT enough. The aura that actually lands can carry the
-- base spell ID, an override, an override-tooltip ID, or any of linkedSpellIDs —
-- CDM:InfoMatchesSpell already tests all four in the other direction. The slot
-- filter needs the WHOLE set or the button never populates and the bar sits dead
-- with nothing in BugSack to say why.
--
-- All config reads off a C_CooldownViewer struct: taint-safe, no aura touched.
-- --------------------------------------------------------------------------
function AD:CandidateSpellIDs(spellID)
  local set = {}
  if not (spellID and spellID > 0) then return set end
  set[spellID] = true

  local cdm = GA.CDM
  if not (cdm and cdm.frameToSpell and C_CooldownViewer
          and C_CooldownViewer.GetCooldownViewerCooldownInfo) then return set end

  for frame, fsid in pairs(cdm.frameToSpell) do
    if fsid == spellID and frame.GetCooldownID then
      local ok, cid = pcall(frame.GetCooldownID, frame)
      if ok and cid ~= nil and not issecret(cid) then
        local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cid)
        if info then
          if info.spellID and info.spellID > 0 then set[info.spellID] = true end
          if info.overrideSpellID and info.overrideSpellID > 0 then set[info.overrideSpellID] = true end
          if info.overrideTooltipSpellID and info.overrideTooltipSpellID > 0 then
            set[info.overrideTooltipSpellID] = true
          end
          if type(info.linkedSpellIDs) == "table" then
            for _, id in ipairs(info.linkedSpellIDs) do
              if id and not issecret(id) and id > 0 then set[id] = true end
            end
          end
        end
        break
      end
    end
  end

  -- ⚠ REGISTRY FALLBACK — no frame required. Frame binding is not dependable (the CDM never
  -- bound an already-applied aura across 52 passes, TESTED 2026-08-03), and a display built in
  -- the Auras tab may have no bound frame at all. Without this the filter would carry only the
  -- base spell ID, and an aura that lands under an override would never match the slot.
  local E = Enum and Enum.CooldownViewerCategory
  if E and C_CooldownViewer.GetCooldownViewerCategorySet then
    for _, cat in ipairs({ E.Essential, E.Utility, E.TrackedBuff, E.TrackedBar }) do
      local ids = cat and C_CooldownViewer.GetCooldownViewerCategorySet(cat)
      if type(ids) == "table" then
        for _, cid in ipairs(ids) do
          local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cid)
          if info and (info.spellID == spellID or info.overrideSpellID == spellID
                       or info.overrideTooltipSpellID == spellID) then
            if info.spellID and info.spellID > 0 then set[info.spellID] = true end
            if info.overrideSpellID and info.overrideSpellID > 0 then set[info.overrideSpellID] = true end
            if info.overrideTooltipSpellID and info.overrideTooltipSpellID > 0 then
              set[info.overrideTooltipSpellID] = true
            end
            if type(info.linkedSpellIDs) == "table" then
              for _, id in ipairs(info.linkedSpellIDs) do
                if id and not issecret(id) and id > 0 then set[id] = true end
              end
            end
          end
        end
      end
    end
  end
  return set
end

local function SetKeys(set)
  local t = {}
  for id in pairs(set) do t[#t + 1] = id end
  table.sort(t)
  return table.concat(t, ",")
end

-- --------------------------------------------------------------------------
-- Container lifecycle. One per unit, shown + enabled so it self-registers
-- UNIT_AURA. It draws nothing (1×1, no regions of its own) — it exists purely
-- to own slots.
-- --------------------------------------------------------------------------
local function EnsureContainer(unit)
  local c = containers[unit]
  if c then return c end
  if not AD:IsAvailable() then return nil end

  -- ⚠ WE TRY IN COMBAT, ON PURPOSE. ArcUI's implementation comments that in-combat container
  -- creation is a hard Lua error, and FINDINGS §1 repeats it — but neither claim was ever
  -- tested by us, and taking it on faith has a real cost: after a mid-fight /reload nothing
  -- could be created, so every bar stayed dead until the fight ended. A pcall'd attempt is
  -- safe either way. `/ga auradur` reports combatCreate so we find out which it is from
  -- evidence rather than from a comment in someone else's addon.
  local inCombat = InCombatLockdown() and true or false
  local ok, made = pcall(CreateFrame, "AuraContainer", "GloomAuraDurContainer_" .. unit,
                         UIParent, "CustomAuraContainerTemplate")
  if not (ok and made) then
    if inCombat then diag.combatDefer = diag.combatDefer + 1 end
    Log("EnsureContainer(%s): creation FAILED (inCombat=%s) %s", unit, tostring(inCombat), tostring(made))
    return nil
  end
  if inCombat then diag.combatCreate = diag.combatCreate + 1 end
  c = made
  if c.SetUnit then c:SetUnit(unit) end
  if c.SetEnabled then c:SetEnabled(true) end
  c:ClearAllPoints()
  c:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  c:SetSize(1, 1)
  c:Show()   -- must be shown AND enabled or it never registers UNIT_AURA
  containers[unit] = c
  diag.containerNew = diag.containerNew + 1
  Log("EnsureContainer(%s): created", unit)
  return c
end

-- --------------------------------------------------------------------------
-- initializeFrame — THE window. Everything that touches the button happens here
-- and is unreachable afterwards. Read rule 2 at the top of this file before
-- adding a line to this function.
-- --------------------------------------------------------------------------
-- Paint the ENGINE's StatusBar to match the display's bar config. Driven entirely from
-- cfg.bar — never by reading f.bar's live texture back — so the look survives the engine
-- re-binding its own region, and a colour fill (which has no file path to read) still works.
-- Called from BOTH initializeFrame and ApplyStyle so the two can never drift.
local function PaintBar(gbar, b)
  if not gbar then Log("PaintBar: NO gbar — nothing to paint"); return end
  local path = GA.Displays and GA.Displays.BarTexturePath and GA.Displays:BarTexturePath(b)
  -- ⚠ DIAGNOSTIC (2026-08-03): read the texture back BEFORE overwriting it. If `was` keeps
  -- returning something we did not set — WHITE8X8, nil, or a Blizzard asset — then the
  -- ENGINE is re-asserting its own fill texture and a custom one can never survive on this
  -- region, which would make bar textures a different job entirely rather than a bug.
  local was = gbar.GetStatusBarTexture and gbar:GetStatusBarTexture()
  Log("PaintBar was=%s -> set=%s (rotate=%s orient=%s)",
      tostring(was and was.GetTexture and was:GetTexture()), tostring(path),
      tostring(b.rotateTexture), tostring(b.orientation))
  -- WHITE8X8 is a real white ASSET, not a colour texture: SetStatusBarColor tints it the
  -- same way GA's own fill is tinted, and unlike a colour texture it has a path.
  if gbar.SetStatusBarTexture then gbar:SetStatusBarTexture(path or "Interface\\Buttons\\WHITE8X8") end
  if gbar.SetOrientation then
    gbar:SetOrientation((b.orientation == "VERTICAL") and "VERTICAL" or "HORIZONTAL")
  end
  if gbar.SetReverseFill then gbar:SetReverseFill(b.reverse and true or false) end
  if gbar.SetRotatesTexture then gbar:SetRotatesTexture(b.rotateTexture and true or false) end
  -- ⚠ Colour from CONFIG, never f.bar:GetStatusBarColor() — on 12.1 that getter can hand
  -- back a secret, and it also reflects any dimming applied to the real bar.
  local oc  = GA.COLOR and GA.COLOR.orange
  local col = b.color or (oc and { oc.r, oc.g, oc.b }) or { 1, 0.47, 0.16 }
  if gbar.SetStatusBarColor then gbar:SetStatusBarColor(col[1] or 1, col[2] or 1, col[3] or 1) end
end

-- A cheap fingerprint of everything PaintBar and the text block actually read. ApplyStyle is
-- driven off ApplyConfig and UpdateBar, which CDM re-runs on every display refresh — dozens of
-- times per action — and almost all of those pushes are identical. Skipping the identical ones
-- is safe ONLY because the fingerprint is cleared on every attach (see Attach): a re-attach can
-- hand us a brand-new button whose regions have never been painted.
local function StyleSig(b)
  local function rgb(c) return c and (tostring(c[1]) .. "," .. tostring(c[2]) .. "," .. tostring(c[3])) or "-" end
  return table.concat({
    tostring(b.texture), tostring(b.rotateTexture), tostring(b.orientation), tostring(b.reverse),
    tostring(b.fill), tostring(b.font),
    tostring(b.showTimer), tostring(b.timerSize), tostring(b.timerAnchor),
    rgb(b.color), rgb(b.timerColor),
  }, "|")
end

local function WireButton(button, f, cfg, sub)
  sub.initFired = true
  diag.initFired = diag.initFired + 1

  local b      = cfg.bar or {}
  local gbar   = button.GloomBar
  local holder = button.GloomTextHolder
  local timer  = holder and holder.GloomTimer
  sub.button, sub.gbar, sub.timer, sub.holder = button, gbar, timer, holder

  -- Same direction rule the object-fed path uses (Displays:UpdateBar): "fill"
  -- grows with elapsed time, anything else drains the remaining time.
  local dir = (b.fill == "fill") and Enum.StatusBarTimerDirection.ElapsedTime
                                 or  Enum.StatusBarTimerDirection.RemainingTime
  Log("initializeFrame FIRED (%s/%s) bar=%s timer=%s",
      tostring(sub.unit), tostring(sub.filter), tostring(gbar ~= nil), tostring(timer ~= nil))

  -- ⚠ ORDER IS DELIBERATE: BINDING and ANCHORING first, cosmetics last.
  -- This window is one-shot — if anything in here throws, everything after it is
  -- lost for the life of that button and there is no second chance to run it.
  -- On 2026-08-03 a cosmetic texture call threw here and took the anchoring down
  -- with it, leaving a correctly-bound bar parked off-screen. So the two calls
  -- that decide whether anything appears at all go FIRST, and every call that
  -- only decides how it LOOKS goes after them.

  -- 1 · BIND the fill. The engine drains the button's own StatusBar.
  if gbar and f.bar and button.SetDurationBar then
    button:SetDurationBar(gbar, { interpolation = Enum.StatusBarInterpolation.ExponentialEaseOut,
                                  direction = dir })
    gbar:Show()
  end

  -- 2 · BIND the countdown text, opt-in per bar (cfg.bar.showTimer), into the
  -- button's own FontString. Its holder frame is raised to the display's level so
  -- the number sits above the fill — done by LEVEL, never by reparenting.
  if b.showTimer and timer and button.SetDurationText then
    button:SetDurationText(timer, { zeroDurationText = "", expiredText = "" })
    if GA.Displays and GA.Displays.AnchorReadout then
      GA.Displays:AnchorReadout(timer, f.bar or f, b.timerAnchor)
    end
    if holder and holder.SetFrameLevel then
      holder:SetFrameStrata(f:GetFrameStrata())
      holder:SetFrameLevel(f:GetFrameLevel() + 2)
    end
    timer:Show()
  end

  -- 3 · ANCHOR the button over the display's bar. Post-init, ClearAllPoints on it
  -- errors like everything else, so it can only happen here. Anchors survive the
  -- engine's own hide/show, and a re-attach always builds a fresh sub.
  button:ClearAllPoints()
  button:SetAllPoints(f.bar or f)
  button:SetFrameStrata(f:GetFrameStrata())
  button:SetFrameLevel((f.bar and f.bar:GetFrameLevel() or f:GetFrameLevel()) + 1)
  if button.EnableMouse then button:EnableMouse(false) end

  -- 4 · COSMETICS. Everything below is appearance only; a failure here must never
  -- cost the bindings above.
  -- ⚠ The engine's fill is the ONLY fill the user sees — Displays:UpdateBar empties GA's
  -- own the moment an attach succeeds, because a full bar underneath masks the drain
  -- completely (that is exactly how this looked broken on 2026-08-03: a working drain
  -- hidden behind an identical static bar). So this is not decoration; it IS the bar.
  PaintBar(gbar, b)
  if b.showTimer and timer then
    if timer.SetDrawLayer then timer:SetDrawLayer("OVERLAY", 7) end
    local font = b.font or (GA.FONT and GA.FONT.body) or (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")
    if GA.SetFontSafe then GA.SetFontSafe(timer, font, b.timerSize or 14, "OUTLINE") end
    local tc = b.timerColor
    timer:SetTextColor(tc and tc[1] or 1, tc and tc[2] or 1, tc and tc[3] or 1)
  end
  -- This button now carries the current style: tell ApplyStyle's guard so a fresh
  -- button handed over MID-FIGHT is not deferred on every feed until regen (441
  -- deferrals in one dummy session, 2026-09-20, after the guard first learned to
  -- key on the button).
  sub.paintedButton, sub.paintedSig = button, StyleSig(b)
end

-- --------------------------------------------------------------------------
-- Attach / Detach
--
-- `unit` routing: GA has no explicit buff-vs-debuff picker for a bar, so
-- cfg.bar.unit wins if the user set it, else the selfAura-derived CDM:auraUnit,
-- else "target". ⚠ selfAura is known to LIE (CDM.lua:406 — Freezing/Shatter says
-- player while the debuff is on the target). One slot for now; if a mis-routed
-- aura shows up, the fix is a second slot on the other unit driving the same
-- bar, NOT trusting selfAura harder.
-- --------------------------------------------------------------------------
function AD:Attach(displayID, f, cfg)
  if not (f and cfg) then return false end
  if not self:IsAvailable() then return false end
  -- ⚠ NOT cfg.spellID. A display created in the Auras tab has none — its spell lives in the
  -- first trigger condition — so keying on cfg.spellID meant a bar built through the UI could
  -- never get a duration, and `/ga bar <spellID>` was the only route to a working timer.
  local sid = GA.CDM and GA.CDM.DisplaySpellID and GA.CDM:DisplaySpellID(cfg) or cfg.spellID
  if not sid then return false end
  diag.attach = diag.attach + 1

  local spellIDs = self:CandidateSpellIDs(sid)
  if not next(spellIDs) then
    diag.noCandidates = diag.noCandidates + 1
    Log("Attach %s: EMPTY candidate set", tostring(displayID))
    return false
  end

  -- Already driving this display for this spell? Just re-point the filter at the
  -- (possibly refreshed) candidate set — container methods stay callable.
  local prev = attached[displayID]
  if prev and prev.spellID == sid then
    local c = containers[prev.unit]
    if c and c.SetAuraSlotCandidateFilters then
      c:SetAuraSlotCandidateFilters(prev.key, { includeSpellIDs = spellIDs })
      if c.UpdateAllAuras then c:UpdateAllAuras() end
      prev.spellIDs = spellIDs
      -- The style fingerprint is NOT cleared here (it was, until 2026-09-20). UpdateBar
      -- re-attaches on every feed — per UNIT_AURA per shown bar, 1,643 retargets in
      -- one 30s dummy fight — so clearing it repainted the bar on every feed out of
      -- combat and queued a deferral on every feed in combat (Hub backlog item 4).
      -- A fresh button is still never skipped: ApplyStyle's guard compares the
      -- painted BUTTON as well as the style, and WireButton paints it at init anyway.
      diag.retarget = diag.retarget + 1
    end
    return true
  end

  local unit = (cfg.bar and cfg.bar.unit)
            or (GA.CDM and GA.CDM.auraUnit and GA.CDM.auraUnit[sid])
            or "target"
  local c = EnsureContainer(unit)
  if not (c and c.AddAuraSlot) then
    pending[displayID] = { f = f, cfg = cfg }
    Log("Attach %s: container(%s) not ready → pending", tostring(displayID), unit)
    return false
  end

  local assist = (unit == "player") or (UnitCanAssist and UnitCanAssist("player", unit))
  local filter = assist and "HELPFUL" or "HARMFUL"

  seq = seq + 1
  local key = "gloomauradur" .. seq
  local sub = { unit = unit, filter = filter, key = key, initFired = false }
  c:AddAuraSlot(key, filter, {
    candidateFilters = { includeSpellIDs = spellIDs },
    templateNames    = { "GloomAuraDurButtonTemplate" },
    initializeFrame  = function(button) WireButton(button, f, cfg, sub) end,
  })
  -- Parse auras that are ALREADY up rather than waiting for the next UNIT_AURA —
  -- otherwise a /reload mid-fight leaves the bar dead until the DoT is refreshed.
  if c.UpdateAllAuras then c:UpdateAllAuras() end
  -- NOTHING may touch the button past this point. See rule 2.

  -- active=true: a freshly attached slot is already matching, so the first Show is a no-op.
  attached[displayID] = { spellID = sid, unit = unit, key = key, sub = sub,
                          spellIDs = spellIDs, active = true }
  diag.slotNew = diag.slotNew + 1
  Log("Attach %s: %s/%s {%s}", tostring(displayID), unit, filter, SetKeys(spellIDs))
  return true
end

-- --------------------------------------------------------------------------
-- ApplyStyle — re-push the CURRENT appearance onto a LIVE engine button.
--
-- Without this, every appearance control in the Bar section is dead on a bar that is
-- already attached: the engine owns the visible fill, and its look is copied across
-- inside initializeFrame, which has long since closed.
--
-- ⚠ WHY THIS IS LEGAL. Outside initializeFrame the button and its regions are forbidden
-- WHENEVER AURAS ARE SECRET — but secrecy tracks combat/encounter, so out of combat they
-- become touchable again. That is the entire reason live config editing can work. The gate
-- is ENVIRONMENTAL and there is no object probe for it (IsForbidden reads FALSE while the
-- very next call throws), so anything arriving in combat is queued for PLAYER_REGEN_ENABLED
-- rather than tested for. Every push is pcall'd and failures are COUNTED, not swallowed —
-- `/ga auradur` reports styleThrew so a dead control can never look like a working one.
-- --------------------------------------------------------------------------
function AD:ApplyStyle(displayID, f, cfg)
  if GA.HotCount then GA.HotCount("ApplyStyle") end
  local a = attached[displayID]
  if not (a and a.sub and f and f.bar and cfg) then
    Log("ApplyStyle %s: SKIPPED (attached=%s sub=%s frame=%s)", tostring(displayID),
        tostring(a ~= nil), tostring(a and a.sub ~= nil), tostring(f and f.bar ~= nil))
    return
  end
  Log("ApplyStyle %s: entering", tostring(displayID))
  -- Nothing changed since the last push onto THIS button? Don't repaint it — and
  -- don't DEFER it either. The combat check used to come first, so every feed in a
  -- fight (UpdateBar runs per UNIT_AURA per shown bar — 1,165 in one 30s dummy
  -- session, measured 2026-09-20) was logged as a deferred style change when
  -- nothing had changed. That was Hub backlog item 4's "600 deferrals".
  -- "Unchanged" means the same style on the SAME button: a re-parse can hand the
  -- slot a fresh button, and that one's first paint must never be skipped (its
  -- wiring paints it too, but this keeps the guard exact rather than trusting it).
  local sig = StyleSig(cfg.bar or {})
  if a.sub.paintedButton == a.sub.button and a.sub.paintedSig == sig then
    diag.styleSkipped = diag.styleSkipped + 1
    return
  end
  if InCombatLockdown() or (IsEncounterInProgress and IsEncounterInProgress()) then
    styleDeferred[displayID] = { f = f, cfg = cfg }
    diag.styleDefer = diag.styleDefer + 1
    return
  end
  styleDeferred[displayID] = nil

  local sub    = a.sub
  local b      = cfg.bar or {}
  local gbar   = sub.gbar
  local timer  = sub.timer
  local button = sub.button
  local dir = (b.fill == "fill") and Enum.StatusBarTimerDirection.ElapsedTime
                                 or  Enum.StatusBarTimerDirection.RemainingTime

  local ok, err = pcall(function()
    if gbar then
      PaintBar(gbar, b)
      -- Direction lives in the BINDING, not the region, so it needs the bind re-run.
      if button and button.SetDurationBar and a.dir ~= dir then
        button:SetDurationBar(gbar, { interpolation = Enum.StatusBarInterpolation.ExponentialEaseOut,
                                      direction = dir })
        a.dir = dir
      end
    end
    -- The countdown can be switched on for a bar that started without it, so bind on
    -- demand rather than assuming initializeFrame already did it.
    if timer and button then
      if b.showTimer then
        if button.SetDurationText then
          button:SetDurationText(timer, { zeroDurationText = "", expiredText = "" })
        end
        if timer.SetDrawLayer then timer:SetDrawLayer("OVERLAY", 7) end
        local font = b.font or (GA.FONT and GA.FONT.body) or (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")
        if GA.SetFontSafe then GA.SetFontSafe(timer, font, b.timerSize or 14, "OUTLINE") end
        local tc = b.timerColor
        timer:SetTextColor(tc and tc[1] or 1, tc and tc[2] or 1, tc and tc[3] or 1)
        if GA.Displays and GA.Displays.AnchorReadout then
          GA.Displays:AnchorReadout(timer, f.bar or f, b.timerAnchor)
        end
        timer:Show()
      else
        timer:Hide()
      end
    end
  end)

  if ok then
    diag.styleApplied = diag.styleApplied + 1
    a.sub.paintedButton, a.sub.paintedSig = a.sub.button, sig
  else
    diag.styleThrew = diag.styleThrew + 1
    Log("ApplyStyle %s THREW: %s", tostring(displayID), tostring(err))
    -- A throw here is a control that silently does nothing; say so ONCE per display
    -- per session whether or not debug is on (the flag does not survive a /reload,
    -- so "turn debug on, reload, read the throw" could never work — 2026-09-20).
    a.threwSaid = a.threwSaid or {}
    local head = tostring(err):match("^[^\n]*")
    if not a.threwSaid[head] then
      a.threwSaid[head] = true
      GA.msg(("bar style push for |cffffffff%s|r threw: %s"):format(tostring(cfg.label or displayID), head))
    end
  end
end

-- --------------------------------------------------------------------------
-- Follow the DISPLAY's visibility.
--
-- ⚠ The engine's button is a child of the AuraContainer, NOT of GA's display frame — it is
-- only ANCHORED over it (reparenting is forbidden and detaches the duration binding). So
-- hiding a GA display hides its label and its stack count, both real children, while the
-- engine's countdown keeps right on drawing over empty screen. Seen 2026-08-03 after a
-- mid-fight /reload: a floating countdown with no bar, no stacks and no name.
--
-- We cannot hide the button ourselves (forbidden object once auras are secret), but parking
-- the slot's filter on a spell ID that can never match makes the ENGINE release and hide it,
-- and container methods stay callable at all times. The slot is REUSED rather than detached,
-- so a DoT going on and off through a long fight doesn't accumulate dead slots.
-- --------------------------------------------------------------------------
function AD:SetSlotActive(displayID, on)
  local a = attached[displayID]
  if not a then return end
  on = on and true or false
  if a.active == on then return end
  a.active = on
  local c = containers[a.unit]
  if not (c and c.SetAuraSlotCandidateFilters) then return end
  c:SetAuraSlotCandidateFilters(a.key, { includeSpellIDs = on and a.spellIDs or { [0] = true } })
  if c.UpdateAllAuras then c:UpdateAllAuras() end
  -- (Re-showing can hand us a fresh button; ApplyStyle's guard keys on the button, so
  -- its first paint is never skipped without clearing the fingerprint here.)
  Log("SetSlotActive %s → %s", tostring(displayID), tostring(on))
end

function AD:Detach(displayID)
  pending[displayID] = nil
  local a = attached[displayID]
  if not a then return end
  attached[displayID] = nil
  diag.detach = diag.detach + 1
  -- Rule 4: never touch the button. Parking the include set on a spell ID that
  -- cannot match makes the ENGINE release and hide it, which is always legal.
  local c = containers[a.unit]
  if c and c.SetAuraSlotCandidateFilters then
    c:SetAuraSlotCandidateFilters(a.key, { includeSpellIDs = { [0] = true } })
    if c.UpdateAllAuras then c:UpdateAllAuras() end
  end
end

-- --------------------------------------------------------------------------
-- Events
--   PLAYER_TARGET_CHANGED — ⚠ a target container does NOT self-refresh on a
--   target swap; it only reacts to its own unit's UNIT_AURA, so a debuff bar
--   goes stale until the new target happens to fire one. Force a re-parse.
--   (FINDINGS §1 currently claims AuraContainer follows target swaps by itself.
--   It does not — ArcUI carries this same workaround for the same reason.)
--   PLAYER_REGEN_ENABLED — the only time containers can be created, so build
--   both eagerly and flush anything that had to wait.
-- --------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_TARGET_CHANGED" then
    for unit, c in pairs(containers) do
      if unit ~= "player" and c.UpdateAllAuras then c:UpdateAllAuras() end
    end
    return
  end
  if InCombatLockdown() then return end
  if not AD:IsAvailable() then return end
  EnsureContainer("player")
  EnsureContainer("target")
  if next(pending) then
    local q = pending
    pending = {}
    for id, req in pairs(q) do AD:Attach(id, req.f, req.cfg) end
  end
  -- Appearance changes made mid-combat: the buttons were untouchable then, so re-push now.
  if next(styleDeferred) then
    local q = styleDeferred
    styleDeferred = {}
    for id, req in pairs(q) do AD:ApplyStyle(id, req.f, req.cfg) end
  end
end)

-- --------------------------------------------------------------------------
-- /ga auradur — the instrument. Says which link in the chain is cold.
-- --------------------------------------------------------------------------
function AD:Report(rest)
  rest = (rest or ""):gsub("%s+", ""):lower()
  if rest == "debug" or rest == "on" then AD.debug = true;  GA.msg("auradur debug ON");  return end
  if rest == "off"                    then AD.debug = false; GA.msg("auradur debug OFF"); return end

  GA.msg("12.1 duration engine:")
  print(("  available=%s  inCombat=%s"):format(tostring(self:IsAvailable()), tostring(InCombatLockdown())))
  print(("  counters: attach=%d newSlots=%d retarget=%d |cffffd200initFired=%d|r newContainers=%d combatDefer=%d noCandidates=%d detach=%d")
        :format(diag.attach, diag.slotNew, diag.retarget, diag.initFired,
                diag.containerNew, diag.combatDefer, diag.noCandidates, diag.detach))
  print(("  style: |cffffd200applied=%d|r skipped=%d deferred=%d %s"):format(
        diag.styleApplied, diag.styleSkipped, diag.styleDefer,
        (diag.styleThrew > 0) and ("|cffff5555threw=" .. diag.styleThrew .. "|r") or "threw=0"))
  if diag.combatCreate > 0 then
    print(("  |cff55ff55containers created IN COMBAT: %d|r — the 'combat blocks creation' claim is FALSE")
          :format(diag.combatCreate))
  end
  for unit, c in pairs(containers) do
    print(("  container[%s]: shown=%s"):format(unit, tostring(c:IsShown())))
  end
  local n = 0
  for id, a in pairs(attached) do
    n = n + 1
    print(("  driving %s: spellID=%s %s/%s init=%s ids={%s}"):format(
      tostring(id), tostring(a.spellID), a.unit, a.sub and a.sub.filter or "?",
      tostring(a.sub and a.sub.initFired), SetKeys(a.spellIDs)))
  end
  if n == 0 then print("  driving: |cffff5555(none)|r") end
  if diag.initFired == 0 and diag.slotNew > 0 then
    print("  |cffff5555initFired=0 with slots created — the filter never matched an aura.|r")
  end
end
