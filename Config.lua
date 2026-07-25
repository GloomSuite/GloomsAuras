-- Config.lua — Gloom's Auras: options panel
--
-- A control panel (opened with /ga) skinned to match Gloom's Build Barn: a
-- near-black navy plate, bright-purple accents, bundled Khand/GeneralSans fonts,
-- flat alpha-driven buttons. Two-pane master/detail layout:
--   • LEFT  — a scrollable list of every display you've created (icon + name);
--             click one to edit it, "+ Add aura" opens the picker.
--   • RIGHT — the settings for the selected display: Texture, Position & Size,
--             Trigger. Each numeric setting is a slider + −/+ steppers + a typed
--             value box, all driving the same saved config live.
-- Displays are force-shown (and draggable) while the panel is open.

local ADDON_NAME = ...
local GA = _G.GloomsAuras

local C = {}
GA.Config = C

local issecret = _G.issecretvalue or function() return false end

-- --------------------------------------------------------------------------
-- Toolkit + tokens — CONSUMED from LibGloomSkin-1.0 (Phase D; the shared lib
-- shipped by GloomsHub, our hard dependency, so it is always loaded first).
-- The local names mirror the old GA-local copies exactly, so everything below
-- reads unchanged. FONT here = the Hub's font paths (pre-warmed against the
-- cold-pair blank-text quirk); GA.FONT (GA's own files) remains for on-screen
-- aura text + the font-picker entries users store in their configs. MEDIA
-- stays GA's own art (triangle/eye/lock/checkmark icons, logo, shapes).
-- Surface pinned in GloomsHub/docs/CONTRACTS.md §4.
-- --------------------------------------------------------------------------
-- --------------------------------------------------------------------------
-- ★ SHARED-TOOLKIT VERSION GATE — see GloomsHub/docs/CONTRACTS.md §6.
-- LibGloomSkin lives in GloomsHub and GROWS: each MINOR adds widgets this file
-- may call. WoW's "## Dependencies: GloomsHub" only checks that the Hub is
-- PRESENT, never that it is NEW ENOUGH — so a Hub a release or two behind would
-- let this file load and then die on the first nil widget, spraying Lua errors
-- at someone who has no idea what a MINOR is. Check first, and fail with ONE
-- actionable sentence instead.
-- ★ BUMP SKIN_NEEDS IN THE SAME COMMIT that first calls a newer widget.
-- --------------------------------------------------------------------------
local SKIN_MAJOR, SKIN_NEEDS = "LibGloomSkin-1.0", 4   -- 4: UI.tabHeader (the rail header)

local Skin, skinMinor = LibStub(SKIN_MAJOR, true)
if not Skin or (skinMinor or 0) < SKIN_NEEDS then
  local found = Skin and ("v" .. tostring(skinMinor or 0)) or "none"
  local warn = CreateFrame("Frame")
  warn:RegisterEvent("PLAYER_LOGIN")
  warn:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    print("|cffff7729Gloom's Auras:|r please update |cff936bffGloom's Hub|r. This version of "
      .. "Auras needs a newer Hub toolkit (needs v" .. SKIN_NEEDS .. ", found " .. found
      .. "), so the AURAS tab is unavailable. Your auras keep working normally.")
  end)
  return   -- chunk-level return: the tab is never registered; the display/CDM ENGINES are untouched
end
local UI = Skin.UI
local COLOR, FONT, MEDIA = Skin.COLOR, Skin.FONT, GA.MEDIA
local TEXT, MUTE = COLOR.text, COLOR.mute      -- lib tokens (promoted from the old locals)
local DEFAULT_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local setFont, newText, addEdges = UI.setFont, UI.newText, UI.addEdges
local skinPlate, flatButton = UI.skinPlate, UI.flatButton
local flatEditBox, makeToggle = UI.flatEditBox, UI.makeToggle

-- Every (Hub font, size) pair this tab draws BEYOND the Hub's own warm list —
-- a cold (font file, size) pair renders BLANK on its first draw each session
-- (CONTRACTS §4). Queued now; warmed with the Hub's batch at PLAYER_ENTERING_WORLD.
UI.RegisterWarmPairs({
  { FONT.title, 13 }, { FONT.title, 16 }, { FONT.title, 17 }, { FONT.title, 18 }, { FONT.title, 20 },  -- picker headers / drawer + dialog titles / the aura NAME field
  { FONT.head, 12 }, { FONT.head, 13 },   -- list header / section subheads / MakeSlider ± glyphs (16 is in the Hub's list)
  { FONT.label, 11 }, { FONT.label, 12 }, -- two-weight labels / switches / left-pane buttons
})

local container, selectedID
local pickerFrame, pickerOnPick
local rows = {}
-- Trigger editor state hangs on C._trig (chunk-local cap): { editID, frame, title,
-- logicBtn, rows, offset, ROWS }. See the grouped trigger editor below.

-- Pop-up editors (Trigger, Visibility, Sound, Texture, aura picker) are mutually
-- exclusive so they don't stack on top of each other. Each registers here when built;
-- opening one closes the rest, except any passed as `keep` (the aura picker opened
-- from the Trigger editor keeps that editor open underneath it).
local subWindows = {}
local function RegisterSubWindow(f) subWindows[#subWindows + 1] = f end
local function CloseSubWindows(...)
  local keep = {}
  for i = 1, select("#", ...) do local f = select(i, ...); if f then keep[f] = true end end
  for _, f in ipairs(subWindows) do
    if not keep[f] and f:IsShown() then f:Hide() end
  end
end

-- Dock an editor flush against the Suite window's right edge (parented to the
-- Auras tab container, so it hides with the tab AND the window). Flips to the
-- LEFT side if docking right would run off the screen. Drag is disabled (it's
-- attached now).
local function DockRight(f)
  if not container then return end
  f:SetParent(container)
  f:SetMovable(false)
  f:SetClampedToScreen(false)
  f:ClearAllPoints()
  local pr, sw, fw = container:GetRight(), UIParent:GetRight(), (f:GetWidth() or 0)
  if pr and sw and (pr + fw + 2) > sw then
    f:SetPoint("TOPRIGHT", container, "TOPLEFT", 1, 0)    -- flip: dock on the left
  else
    f:SetPoint("TOPLEFT", container, "TOPRIGHT", -1, 0)   -- dock on the right (flush)
  end
end

local listFrame, listRows, listData, listOffset = nil, {}, {}, 0
local LIST_ROWS = 11   -- rail rows above the button stack (the profile block owns the rail's top)
local LIST_ROW_H = 24

-- Texture blend modes (SetBlendMode) + friendly labels; frame strata choices.
local BLEND_MODES = {
  { "BLEND", "Normal" }, { "ADD", "Add (glow)" }, { "MOD", "Modulate" },
}
local STRATA_MODES = {
  { "LOW", "Low" }, { "MEDIUM", "Medium" }, { "HIGH", "High" },
  { "DIALOG", "Dialog" }, { "TOOLTIP", "Tooltip" },
}

-- Collapse caret for group / Ungrouped headers AND the editor's section headers:
-- the SUITE's shared art (UI.CARET, the Hub's Media/ui/caret.png) at the shared
-- 9×9, tinted COLOR.orange — same glyph, size and colour as Bars and Overlays
-- (the owner, 2026-07-25). Drawn pointing RIGHT when collapsed, rotated 90° to
-- point DOWN when expanded. NO native Blizzard art / unicode triangles (the game
-- fonts lack ▼/▶ → tofu boxes). GA's own Media/triangle.png is no longer drawn.
local CARET_DOWN = UI.CARET_DOWN   -- rotate a right-pointing source to point down (expanded)

local STATE_ORDER = { "buff_active", "buff_inactive", "cd_ready", "cd_oncd", "charges_max", "charges_notmax" }
local STATE_LABEL = {
  buff_active    = "buff is active",
  buff_inactive  = "buff is NOT active",
  cd_ready       = "cooldown is ready",
  cd_oncd        = "cooldown is NOT ready",
  charges_max    = "at max charges",
  charges_notmax = "NOT at max charges",
}
-- Word a condition's state per the leaf's kind: cooldowns stay "cooldown …"; an aura's two
-- buff states become buff (on you) / debuff (on target) / proc, from the picked entry's kind
-- (selfAura + hasAura). Keeps the picker tags and the condition wording aligned.
local function StateLabel(state, k)
  if state == "cd_ready" or state == "cd_oncd"
     or state == "charges_max" or state == "charges_notmax" then return STATE_LABEL[state] or "?" end
  local active = (state == "buff_active")
  if k == "proc" then
    return active and "proc is active" or "proc is NOT active"
  elseif k == "debuff" then
    return active and "debuff is active (on target)" or "debuff is NOT active (on target)"
  else
    return active and "buff is active (on you)" or "buff is NOT active (on you)"
  end
end

-- Trigger state PILL wording (redesign): a bold main part + a regular "(suffix)".
-- e.g. buff_active+debuff → "ACTIVE on Target" , " (Debuff)".
local function TrigPill(state, k)
  if state == "cd_ready" then return "READY", " (Cooldown)"
  elseif state == "cd_oncd" then return "ON COOLDOWN", " (Cooldown)"
  elseif state == "charges_max" then return "AT MAX", " (Charges)"
  elseif state == "charges_notmax" then return "NOT AT MAX", " (Charges)" end
  local active = (state == "buff_active")
  local unit = (k == "debuff") and "Target" or "You"
  local kind = (k == "debuff") and "Debuff" or (k == "proc") and "Proc" or "Buff"
  return (active and "ACTIVE on " or "NOT ACTIVE on ") .. unit, " (" .. kind .. ")"
end

-- --------------------------------------------------------------------------
-- Skin toolkit — the shared primitives (setFont, newText, addEdges, skinPlate,
-- flatButton, flatEditBox, makeToggle) come from LibGloomSkin now (aliased at
-- the top of this file). Only GA-specific composites remain below.
-- --------------------------------------------------------------------------

-- Two-weight inline label: a Regular-weight prefix + a Semibold value, centered as a
-- group inside `parent`. The "Profile: ‹Name›" convention (Regular label + Semibold value)
-- recurs across buttons/headers, so it lives here. :Set(prefix, value) re-lays it out.
-- swap=true puts the Semibold part first (used by the trigger state pills:
-- "ACTIVE on Target" bold + " (Debuff)" regular).
local function twoWeightLabel(parent, size, cc, swap)
  cc = cc or { r = 1, g = 1, b = 1 }
  local pre = newText(parent, swap and FONT.label or FONT.body,  size, cc, "LEFT")
  local val = newText(parent, swap and FONT.body  or FONT.label, size, cc, "LEFT")
  local h = { pre = pre, val = val }
  function h:Set(prefix, value)
    pre:SetText(prefix or ""); val:SetText(value or "")
    local total = (pre:GetStringWidth() or 0) + 4 + (val:GetStringWidth() or 0)
    pre:ClearAllPoints(); pre:SetPoint("LEFT", parent, "CENTER", -total / 2, 0)
    val:ClearAllPoints(); val:SetPoint("LEFT", pre, "RIGHT", 4, 0)
  end
  return h
end

-- --------------------------------------------------------------------------
-- Data helpers
-- --------------------------------------------------------------------------
local function DB() return GA.db and GA.db.displays end

local function DisplayList()
  local out = {}
  local db = DB()
  if db then for id in pairs(db) do out[#out + 1] = id end end
  -- Keys are a spellID (number) for the original of a spell, or a "dN" string for a
  -- duplicate. Sort by tracked spell then by key so number/string keys never compare
  -- directly (that would error) and duplicates group under their source spell.
  table.sort(out, function(a, b)
    local sa = (db and db[a] and db[a].spellID) or 0
    local sb = (db and db[b] and db[b].spellID) or 0
    if sa ~= sb then return sa < sb end
    return tostring(a) < tostring(b)
  end)
  return out
end

local function Cfg()
  local db = DB()
  return db and selectedID and db[selectedID]
end

-- Deep-copy a display's config (nested tables: point, color, trigger, visibility, sound).
local function DeepCopy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = DeepCopy(v) end
  return o
end

-- A fresh, unique display id — a "dN" STRING so it never collides with a numeric
-- spellID key (originals stay keyed by their spellID; duplicates get these).
local function NewDisplayID()
  local db = GA.db
  db.seq = (db.seq or 0) + 1
  local id = "d" .. db.seq
  while DB() and DB()[id] ~= nil do db.seq = db.seq + 1; id = "d" .. db.seq end
  return id
end

local function ReapplySelected()
  if GA.Displays and selectedID then GA.Displays:ApplyConfig(selectedID) end
end

-- --------------------------------------------------------------------------
-- Groups (Phase 1): named buckets of auras carrying one load rule (a visibility
-- table) + an on/off switch. Stored in GA.db.groups[groupID]; an aura joins via
-- cfg.group. groupID = a "gN" string (own counter, never collides with display ids).
-- --------------------------------------------------------------------------
local function Groups() return GA.db and GA.db.groups end

local function GroupList()   -- group ids sorted by order, then name
  local out = {}
  local g = Groups()
  if g then for id in pairs(g) do out[#out + 1] = id end end
  table.sort(out, function(a, b)
    local ga, gb = g[a], g[b]
    local oa, ob = ga.order or 0, gb.order or 0
    if oa ~= ob then return oa < ob end
    return tostring(ga.name or a) < tostring(gb.name or b)
  end)
  return out
end

local function NewGroupID()
  local db = GA.db
  db.groupSeq = (db.groupSeq or 0) + 1
  local id = "g" .. db.groupSeq
  while Groups() and Groups()[id] ~= nil do db.groupSeq = db.groupSeq + 1; id = "g" .. db.groupSeq end
  return id
end

local function CreateGroup(name)
  local g = Groups(); if not g then return nil end
  local id = NewGroupID()
  local maxOrder = -1
  for _, grp in pairs(g) do maxOrder = math.max(maxOrder, grp.order or 0) end
  g[id] = { id = id, name = (name and name ~= "" and name) or ("Group " .. id),
            order = maxOrder + 1, enabled = true }
  return id
end

-- Delete a group; its member auras fall back to Ungrouped (auras are never deleted —
-- approved rule). Returns the group's name for a confirmation message.
local function DeleteGroup(gid)
  local g = Groups(); if not g or not g[gid] then return nil end
  local name = g[gid].name or gid
  local db = DB()
  if db then for _, cfg in pairs(db) do if cfg.group == gid then cfg.group = nil end end end
  g[gid] = nil
  return name
end

-- Reorder groups by swapping normalized `order` values (up = -1, down = +1).
local function MoveGroup(gid, dir)
  local list = GroupList()
  local g = Groups(); if not g then return end
  for i, id in ipairs(list) do g[id].order = i - 1 end   -- normalize to 0..n-1 first
  local idx
  for i, id in ipairs(list) do if id == gid then idx = i; break end end
  local j = idx and (idx + dir)
  if not idx or not j or j < 1 or j > #list then return end
  g[list[idx]].order, g[list[j]].order = g[list[j]].order, g[list[idx]].order
end

-- Display ids assigned to a group (gid), or the Ungrouped set (gid == nil). A stale
-- group id (points at a deleted group) counts as Ungrouped. Sorted like DisplayList.
local function AurasInGroup(gid)
  local out, db = {}, DB()
  if db then
    for id, cfg in pairs(db) do
      local cg = cfg.group
      if cg ~= nil and not (Groups() and Groups()[cg]) then cg = nil end  -- stale → Ungrouped
      if cg == gid then out[#out + 1] = id end
    end
  end
  table.sort(out, function(a, b)
    local sa = (db and db[a] and db[a].spellID) or 0
    local sb = (db and db[b] and db[b].spellID) or 0
    if sa ~= sb then return sa < sb end
    return tostring(a) < tostring(b)
  end)
  return out
end

-- The left pane as a flat list of typed rows: group headers (+ their auras when
-- expanded), then an Ungrouped header (+ its auras). With NO groups defined it's just
-- a flat aura list (no headers) — identical to the pre-groups look.
local function BuildLeftPaneEntries()
  local entries = {}
  local groups = GroupList()
  for _, gid in ipairs(groups) do
    local g = Groups()[gid]
    entries[#entries + 1] = { kind = "group", gid = gid }
    if not g.collapsed then
      for _, id in ipairs(AurasInGroup(gid)) do entries[#entries + 1] = { kind = "aura", id = id } end
    end
  end
  local ung = AurasInGroup(nil)
  if #groups == 0 then
    for _, id in ipairs(ung) do entries[#entries + 1] = { kind = "aura", id = id } end
  elseif #ung > 0 then
    entries[#entries + 1] = { kind = "ungrouped" }
    if not (GA.db and GA.db.ungroupedCollapsed) then
      for _, id in ipairs(ung) do entries[#entries + 1] = { kind = "aura", id = id } end
    end
  end
  return entries
end

-- The skinned text-entry dialog (for naming/renaming a group) is LibGloomSkin's
-- shared widget as of MINOR 3 (Phase E). GA and GB each carried a near-identical
-- private copy and Overlays would have been a third; there is now exactly ONE.
-- Same signature, so the call sites below are unchanged.
local OpenNameDialog = UI.nameDialog


-- --------------------------------------------------------------------------
-- Numeric row: label + [−] + slider (best-effort) + [+] + value box.
-- --------------------------------------------------------------------------
-- Redesign slider (Figma): [label] [− pill] [track] [+ pill] [value box], 20px row.
-- label = General Sans 12 white; −/+ = heroic-50% pills w/ Khand "−"/"+"; track =
-- heroic-20% 166×6 with a 4×20 PURPLE thumb; value box = heroic-8% fill, centred.
-- Positions match the mock at a ~360-wide parent. "Alpha %" shows a % in its box.
local function MakeSlider(parent, yOff, label, minV, maxV, step, get, set)
  local H = COLOR.heroic
  local suffix = label:find("%%") and "%" or ""

  local title = newText(parent, FONT.body, 12, TEXT, "LEFT")
  title:SetPoint("LEFT", parent, "TOPLEFT", 4, yOff - 10); title:SetText(label)

  -- The row SPANS ITS PANE rather than sitting at a fixed 360 (the width the retired
  -- Figma column dictated): label · − · track · + · value box, with the track taking
  -- all the slack. Measured off the parent, so this one line widened every slider in
  -- the tab when the editor pane grew — and a longer track is finer control, which
  -- matters most on the ±2000 X/Y offsets. Falls back to the old 360 geometry exactly.
  local W = math.max(360, parent:GetWidth() or 0)
  local trackW = W - 194
  local plusX, editX = 100 + trackW + 10, 100 + trackW + 40

  local minus = flatButton(parent, 20, 20, H, "−", 16); minus:SetBase(0.5)
  minus:SetPoint("TOPLEFT", 70, yOff); setFont(minus.text, FONT.head, 16)

  local slider
  pcall(function() slider = CreateFrame("Slider", nil, parent) end)
  if slider then
    slider:SetOrientation("HORIZONTAL"); slider:SetSize(trackW, 20)
    slider:SetPoint("TOPLEFT", 100, yOff); slider:SetHitRectInsets(0, 0, -6, -6)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", 0, 0); track:SetPoint("RIGHT", 0, 0); track:SetHeight(6)
    track:SetColorTexture(H.r, H.g, H.b, 0.20)
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b, 1); thumb:SetSize(4, 20)
    slider:SetThumbTexture(thumb)
    slider:SetMinMaxValues(minV, maxV); slider:SetValueStep(step); slider:SetObeyStepOnDrag(true)
  end

  local plus = flatButton(parent, 20, 20, H, "+", 16); plus:SetBase(0.5)
  plus:SetPoint("TOPLEFT", plusX, yOff); setFont(plus.text, FONT.head, 16)

  local edit = CreateFrame("EditBox", nil, parent)
  edit:SetSize(54, 20); edit:SetPoint("TOPLEFT", editX, yOff); edit:SetAutoFocus(false)
  setFont(edit, FONT.body, 11); edit:SetTextColor(1, 1, 1); edit:SetJustifyH("CENTER"); edit:SetTextInsets(2, 2, 0, 0)
  local ebg = edit:CreateTexture(nil, "BACKGROUND"); ebg:SetAllPoints(); ebg:SetColorTexture(H.r, H.g, H.b, 0.08)

  local applying = false
  local function clamp(v) return math.max(minV, math.min(maxV, math.floor(v + 0.5))) end
  local function show(v) edit:SetText(tostring(v) .. suffix); edit:SetCursorPosition(0) end
  local function apply(v)
    v = clamp(v); applying = true
    if slider then slider:SetValue(v) end
    show(v); applying = false
    set(v); ReapplySelected()
  end
  if slider then slider:SetScript("OnValueChanged", function(_, v) if not applying then apply(v) end end) end
  edit:SetScript("OnEnterPressed", function(self) local v = tonumber((self:GetText() or ""):match("%-?%d+")); if v then apply(v) end self:ClearFocus() end)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  minus:SetScript("OnClick", function() apply((get() or minV) - step) end)
  plus:SetScript("OnClick",  function() apply((get() or minV) + step) end)

  local row = {}
  function row:refresh() local v = clamp(get() or minV); applying = true; if slider then slider:SetValue(v) end; show(v); applying = false end
  function row:setEnabled(on) if slider then slider:SetEnabled(on) end edit:SetEnabled(on); minus:SetEnabled(on); plus:SetEnabled(on) end
  return row
end

-- Text row: label + wide entry box (used for the texture path).
local function MakeText(parent, yOff, label, get, set, w)
  local title = newText(parent, FONT.body, 12, TEXT, "LEFT")
  title:SetPoint("TOPLEFT", 16, yOff); title:SetText(label)

  local edit = flatEditBox(parent, w or 330, 20); edit:SetPoint("TOPLEFT", 22, yOff - 18)
  edit:SetScript("OnEnterPressed", function(self)
    local t = self:GetText(); if t == "" then t = nil end
    set(t); ReapplySelected(); self:ClearFocus()
  end)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

  local row = {}
  function row:refresh() local v = get(); edit:SetText(v ~= nil and tostring(v) or ""); edit:SetCursorPosition(0) end
  function row:setEnabled(on) edit:SetEnabled(on) end
  return row
end

-- Small flat checkbox: a 16px box + label. :Set/:Get + OnClick callback.
local function flatCheck(parent, label)
  local c = CreateFrame("Button", nil, parent)
  c:SetSize(20, 20)   -- Figma: 20px box, white 10% fill, orange ✓, no border
  local box = c:CreateTexture(nil, "ARTWORK"); box:SetAllPoints(); box:SetColorTexture(1, 1, 1, 0.10)
  -- the owner's checkmark_white.png fills the 20x20 box (its canvas = the Figma node), tinted orange.
  c.mark = c:CreateTexture(nil, "OVERLAY"); c.mark:SetAllPoints()
  c.mark:SetTexture(MEDIA .. "checkmark_white.png")
  c.mark:SetVertexColor(COLOR.orange.r, COLOR.orange.g, COLOR.orange.b, 1); c.mark:Hide()
  c.label = newText(c, FONT.body, 12, TEXT, "LEFT"); c.label:SetPoint("LEFT", c, "RIGHT", 8, 0); c.label:SetText(label)
  c._on = false
  function c:Get() return self._on end
  function c:Set(v) self._on = v and true or false; self.mark:SetShown(self._on) end
  return c
end

-- Binary sliding switch (matches GloomsBuildBarn's makeSwitch): [leftLabel]
-- [track+knob] [rightLabel]. value=false→left, true→right; the selected label is
-- accented (purple), the other dimmed, and the knob slides to that side. onChange(v)
-- fires only on a USER toggle (not on :Set). :Set / :Refresh / :SetEnabled provided.
local function makeSwitch(parent, leftText, rightText, onChange)
  local s = CreateFrame("Frame", nil, parent)
  s:SetSize(120, 22)
  s.value = false

  s.left = CreateFrame("Button", nil, s)
  s.left.text = newText(s.left, FONT.label, 12, TEXT, "RIGHT")
  s.left.text:SetText(leftText); s.left.text:SetAllPoints()
  s.left:SetSize((s.left.text:GetStringWidth() or 20) + 2, 16)
  s.left:SetPoint("LEFT", 0, 0)

  s.track = CreateFrame("Button", nil, s)
  s.track:SetSize(46, 20)
  s.track:SetPoint("LEFT", s.left, "RIGHT", 10, 0)
  s.track.fill = s.track:CreateTexture(nil, "BACKGROUND")
  s.track.fill:SetAllPoints(); s.track.fill:SetColorTexture(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b, 0.16)
  s.track.knob = s.track:CreateTexture(nil, "ARTWORK"); s.track.knob:SetSize(18, 14)
  s.track.knob:SetColorTexture(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b, 1)

  s.right = CreateFrame("Button", nil, s)
  s.right.text = newText(s.right, FONT.label, 12, TEXT, "LEFT")
  s.right.text:SetText(rightText); s.right.text:SetAllPoints()
  s.right:SetSize((s.right.text:GetStringWidth() or 20) + 2, 16)
  s.right:SetPoint("LEFT", s.track, "RIGHT", 10, 0)

  local function refresh()
    local k = s.track.knob
    k:ClearAllPoints()
    if s.value then k:SetPoint("RIGHT", -3, 0) else k:SetPoint("LEFT", 3, 0) end
    local on, off = COLOR.purple, MUTE
    if s.value then
      s.left.text:SetTextColor(off.r, off.g, off.b);  s.right.text:SetTextColor(on.r, on.g, on.b)
    else
      s.left.text:SetTextColor(on.r, on.g, on.b);     s.right.text:SetTextColor(off.r, off.g, off.b)
    end
  end
  local function set(v)
    v = v and true or false
    if s.value == v then return end
    s.value = v; refresh(); if onChange then onChange(v) end
  end
  s.track:SetScript("OnClick", function() set(not s.value) end)
  s.left:SetScript("OnClick", function() set(false) end)
  s.right:SetScript("OnClick", function() set(true) end)
  function s:Set(v) s.value = v and true or false; refresh() end
  function s:Refresh() refresh() end
  function s:SetEnabled(on)
    s.track:SetEnabled(on); s.left:SetEnabled(on); s.right:SetEnabled(on)
    s:SetAlpha(on and 1 or 0.4)
  end
  refresh()
  return s
end

-- (makeToggle — the single on/off sliding switch — comes from LibGloomSkin;
-- aliased at the top of this file.)

-- Colour control: [✓ <label>] + a swatch. Clicking either opens the game
-- ColorPickerFrame; unchecking clears the colour (set(nil)). Label defaults to
-- "Tint" (reused for the glow drawer's "Custom Color").
local function MakeColor(parent, x, yOff, get, set, label)
  local chk = flatCheck(parent, label or "Tint")
  chk:SetPoint("TOPLEFT", x, yOff)
  local swatch = CreateFrame("Button", nil, parent); swatch:SetSize(29, 20)   -- Figma: 29x20 solid
  swatch:SetPoint("LEFT", chk.label, "RIGHT", 8, 0)
  local sw = swatch:CreateTexture(nil, "ARTWORK"); sw:SetAllPoints()

  local function updateSwatch()
    local col = get()
    if col then sw:SetColorTexture(col[1] or 1, col[2] or 1, col[3] or 1, 1)
    else sw:SetColorTexture(0.28, 0.28, 0.32, 1) end
  end
  local function openPicker()
    local col = get() or { 1, 1, 1 }
    local function apply()
      local r, g, b = ColorPickerFrame:GetColorRGB()
      set({ r, g, b }); chk:Set(true); updateSwatch(); ReapplySelected()
    end
    local info = { hasOpacity = false, r = col[1], g = col[2], b = col[3], swatchFunc = apply }
    if ColorPickerFrame.SetupColorPickerAndShow then
      ColorPickerFrame:SetupColorPickerAndShow(info)
    else  -- pre-10.2.5 fallback
      ColorPickerFrame.func = apply
      ColorPickerFrame:SetColorRGB(col[1], col[2], col[3]); ColorPickerFrame:Show()
    end
  end
  swatch:SetScript("OnClick", openPicker)
  chk:SetScript("OnClick", function()
    if get() then set(nil); chk:Set(false); updateSwatch(); ReapplySelected() else openPicker() end
  end)

  local row = {}
  function row:refresh() chk:Set(get() ~= nil); updateSwatch() end
  function row:setEnabled(on) chk:SetEnabled(on); swatch:SetEnabled(on) end
  return row
end

-- Cycle button: click to advance through `values` = { {stored, label}, ... }.
local function MakeCycle(parent, x, yOff, w, prefix, values, get, set)
  local b = flatButton(parent, w, 20, COLOR.heroic, "", 12)
  b:SetPoint("TOPLEFT", x, yOff)
  local function label()
    local cur = get()
    for _, v in ipairs(values) do if v[1] == cur then return prefix .. v[2] end end
    return prefix .. values[1][2]
  end
  b:SetScript("OnClick", function()
    local cur, idx = get(), 1
    for i, v in ipairs(values) do if v[1] == cur then idx = i; break end end
    set(values[(idx % #values) + 1][1]); b:SetText(label()); ReapplySelected()
  end)
  local row = {}
  function row:refresh() b:SetText(label()) end
  function row:setEnabled(on) b:SetEnabled(on) end
  return row
end

-- Proper dropdown menu (same signature as MakeCycle): a button showing the current
-- value that opens a list of options below it. Only one dropdown menu is open at a
-- time. values = { {storedValue, label}, ... }.
local openDropdownMenu
-- Redesign dropdown (Figma): a heroic-50% pill (28px tall) with a centred two-weight
-- label — Regular "Prefix:" + Semibold value — opening a list below.
local function MakeDropdown(parent, x, yOff, w, prefix, values, get, set)
  local H = COLOR.heroic
  prefix = (prefix or ""):gsub("%s+$", "")
  local b = flatButton(parent, w, 28, H, "", 11); b:SetBase(0.5); b:SetPoint("TOPLEFT", x, yOff)
  b.text:Hide()
  local lbl = twoWeightLabel(b, 11)
  local function curLabel() local cur = get(); for _, v in ipairs(values) do if v[1] == cur then return v[2] end end return values[1][2] end
  local function refreshLabel() lbl:Set(prefix, curLabel()) end
  local menu = CreateFrame("Frame", nil, parent)
  menu:SetSize(w, #values * 22 + 8)
  menu:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
  menu:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)  -- draw above the rows below
  skinPlate(menu); addEdges(menu, COLOR.rim, 1); menu:Hide()
  for i, v in ipairs(values) do
    local item = flatButton(menu, w - 8, 20, H, v[2], 12); item:SetBase(0.12)
    item:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 22)
    item:SetScript("OnClick", function()
      menu:Hide(); openDropdownMenu = nil
      set(v[1]); refreshLabel(); ReapplySelected()
    end)
  end
  b:SetScript("OnClick", function()
    if menu:IsShown() then menu:Hide(); openDropdownMenu = nil
    else
      if openDropdownMenu and openDropdownMenu ~= menu then openDropdownMenu:Hide() end
      menu:Show(); openDropdownMenu = menu
    end
  end)
  refreshLabel()
  local row = {}
  function row:refresh() refreshLabel() end
  function row:setEnabled(on) b:SetEnabled(on); if not on then menu:Hide() end end
  return row
end

-- --------------------------------------------------------------------------
-- Left pane: the list of created displays.
-- --------------------------------------------------------------------------
local function RefreshList()
  listData = BuildLeftPaneEntries()
  local n = #listData
  local maxOff = math.max(0, n - LIST_ROWS)
  if listOffset > maxOff then listOffset = maxOff end
  if listOffset < 0 then listOffset = 0 end
  for i = 1, LIST_ROWS do
    local row = listRows[i]
    if not row then break end
    local e = listData[i + listOffset]
    -- reset the shared sub-widgets each render (rows switch between kinds)
    row.kind, row.id, row.gid, row.spellID = nil, nil, nil, nil
    if not e then
      row:Hide()
    elseif e.kind == "aura" then
      local sid = e.id
      local cfg = DB() and DB()[sid]
      row.kind, row.id, row.spellID = "aura", sid, sid
      if row.arrow then row.arrow:Hide() end
      if row.caretBtn then row.caretBtn:Hide() end
      row.icon:Show()
      -- Show what the aura LOOKS like: its own texture first (appearance-first model),
      -- else its tracked spell's icon (legacy auras with no custom texture), else a fallback.
      local icon = (cfg and cfg.texture)
        or (cfg and cfg.spellID and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(cfg.spellID))
        or 134400
      row.icon:SetTexture(icon)
      if row.eye then
        row.eye:Show()
        -- The eye states what is ACTUALLY on screen, not just what was toggled. The
        -- preview engine draws `selected OR preview` (Displays:RefreshForced), so the
        -- SELECTED aura reads as visible without being toggled, and reverts the moment
        -- another aura is picked. On = orange, no slash; off = purple, slashed.
        -- The owner re-exported both eyes as WHITE art (2026-07-25) precisely so they
        -- tint exactly, the way the shared caret does. Don't re-bake a colour into
        -- these two files: SetVertexColor multiplies, so coloured art can only ever
        -- darken (the purple originals tinted orange came out #873F15, a muddy brown).
        local on = (sid == selectedID) or (cfg and cfg.preview)
        local tint = on and COLOR.orange or COLOR.purple
        row.eye.icon:SetTexture(MEDIA .. (on and "unhidden.png" or "hidden.png"))
        row.eye.icon:SetVertexColor(tint.r, tint.g, tint.b)
      end
      row.name:ClearAllPoints(); row.name:SetPoint("LEFT", 40, 0); row.name:SetPoint("RIGHT", -24, 0)
      row.name:SetText((cfg and cfg.label) or ("Spell " .. tostring(sid)))
      local dim = cfg and cfg.enabled == false   -- disabled in-game (Visibility → Disabled) greys the row
      row.name:SetTextColor(dim and 0.5 or TEXT.r, dim and 0.5 or TEXT.g, dim and 0.5 or TEXT.b)
      row.sel:SetShown(sid == selectedID)
      row:Show()
    elseif e.kind == "group" then
      local g = Groups() and Groups()[e.gid]
      row.kind, row.gid = "group", e.gid
      row.icon:Hide()
      if row.eye then row.eye:Hide() end
      if row.arrow then row.arrow:Show(); row.arrow:SetRotation((g and g.collapsed) and 0 or CARET_DOWN) end
      if row.caretBtn then row.caretBtn:Show() end
      row.name:ClearAllPoints(); row.name:SetPoint("LEFT", 26, 0); row.name:SetPoint("RIGHT", -26, 0)
      -- A group SHOWS what it is doing: dimmed + "(off)" when its switch is off, and a
      -- dot when it carries a load rule — so the mechanism is visible, not remembered.
      local off = g and g.enabled == false
      local ruled = g and g.visibility and next(g.visibility) ~= nil
      row.name:SetText((g and g.name or "Group") .. (off and "  |cff888888(off)|r" or (ruled and "  |cffff7729•|r" or "")))
      if off then
        row.name:SetTextColor(MUTE.r, MUTE.g, MUTE.b)
      else
        row.name:SetTextColor(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b)
      end
      row.sel:SetShown(e.gid == C.groupSel)   -- a selected group highlights like a selected aura
      row:Show()
    elseif e.kind == "ungrouped" then
      row.kind = "ungrouped"
      row.icon:Hide(); row.sel:Hide()
      if row.eye then row.eye:Hide() end
      if row.arrow then row.arrow:Show(); row.arrow:SetRotation((GA.db and GA.db.ungroupedCollapsed) and 0 or CARET_DOWN) end
      if row.caretBtn then row.caretBtn:Show() end
      row.name:ClearAllPoints(); row.name:SetPoint("LEFT", 26, 0); row.name:SetPoint("RIGHT", -4, 0)
      row.name:SetText("Ungrouped")
      row.name:SetTextColor(MUTE.r, MUTE.g, MUTE.b)
      row:Show()
    end
  end
end

-- --------------------------------------------------------------------------
-- Selection
-- --------------------------------------------------------------------------
local function SetSelected(sid)
  selectedID = sid
  C.groupSel = nil                           -- an aura and a group are never both selected
  if C._trig then C._trig.editID = sid end   -- inline Trigger section edits the selected aura
  if GA.Displays then GA.Displays:SetSelectedDisplay(sid) end  -- only this one is draggable
  local cfg = Cfg()
  for _, r in ipairs(rows) do r:refresh(); r:setEnabled(cfg ~= nil) end
  if C.ShowGroupPane then C:ShowGroupPane(false) end      -- back to the aura accordion
  if C.SyncRailButtons then C:SyncRailButtons() end
  if C.RefreshGroupButton then C:RefreshGroupButton() end -- the aura's GROUP row label
  if C.TrigInlineRender then C:TrigInlineRender() end     -- inline Trigger section follows selection
  if C.UpdateEmptyState then C:UpdateEmptyState() end     -- no auras ⇒ prompt instead of a dead editor
  RefreshList()
  if GA.Displays then GA.Displays:RefreshForced() end   -- preview: show the selected + eye-on, hide the rest
end

-- Back-door for building/QAing Bar displays before the type-aware editor exists (the polished
-- bar UI is coming from the owner's Figma pass — see docs/BARS-DESIGN.md). `/ga bar <spellID>` makes
-- a new Aura-Duration bar bound to a spell that's placed in the Cooldown Manager (Tracked Bars /
-- Buffs). Reuses the whole display pipeline: cfg.spellID drives show/hide via the normal auto-path;
-- kind="bar" only swaps the rendering + adds the duration feed.
function C:AddBar(arg)
  local db = DB()
  if not db then GA.msg("no active profile yet — open the panel first."); return end
  -- Parse: "[stacks] <spellID> [max]".  No keyword ⇒ aura_dur (a duration timer).
  local tokens = {}
  for t in tostring(arg or ""):gmatch("%S+") do tokens[#tokens + 1] = t end
  local mode, sidTok, maxTok = "aura_dur", tokens[1], nil
  if tokens[1] == "stacks" then mode, sidTok, maxTok = "stacks", tokens[2], tokens[3]
  elseif tokens[1] == "cd" or tokens[1] == "cooldown" then mode, sidTok = "cd_dur", tokens[2] end
  local sid = tonumber(sidTok and sidTok:match("%d+"))
  if not sid then
    GA.msg("usage: |cffffd200/ga bar <spellID>|r (aura duration)  •  |cffffd200/ga bar cd <spellID>|r (cooldown)  •  |cffffd200/ga bar stacks <spellID> [max]|r (stacks)")
    return
  end
  local nm = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid)) or ("Bar " .. sid)
  local barcfg = { mode = mode }
  if mode == "stacks" then
    barcfg.max = tonumber(maxTok and maxTok:match("%d+")) or 10
    barcfg.showValue = true                          -- show the live count number on the bar
  end
  local id = NewDisplayID()
  db[id] = {
    kind = "bar", spellID = sid, label = nm, enabled = true,
    width = 220, height = 24, point = { "CENTER", 0, -120 }, alpha = 1, showLabel = true,
    bar = barcfg,
  }
  if GA.CDM then GA.CDM:Discover() end
  if container then SetSelected(id) end
  if mode == "stacks" then
    GA.msg(("created a STACKS Bar for |cffffd200%s|r (%d, max %d). It fills with the aura's stack count. Move it with the panel or |cffffd200/ga pos %s x y|r.")
      :format(tostring(nm), sid, barcfg.max, id))
  elseif mode == "cd_dur" then
    GA.msg(("created a COOLDOWN Bar for |cffffd200%s|r (%d). It shows while the spell is on cooldown and drains as it comes back up. Move it with the panel or |cffffd200/ga pos %s x y|r.")
      :format(tostring(nm), sid, id))
  else
    GA.msg(("created a Bar for |cffffd200%s|r (%d). It shows while that aura is on you/your target and drains with its duration. Move it with the panel or |cffffd200/ga pos %s x y|r.")
      :format(tostring(nm), sid, id))
  end
end

-- --------------------------------------------------------------------------
-- Aura picker: a scrollable list of the CDM registry (icon + name); click to
-- add a display. Scrolls with the mouse wheel (no scrollbar thumb to drag).
-- --------------------------------------------------------------------------
local PICK_ROWS = 12
local PICK_ROW_H = 24
local PICK_COL_W = 208               -- width of each of the two columns
-- Two-panel picker state, hung on C to stay under Config.lua's chunk-local cap: a Cooldowns
-- column + a Buffs/Debuffs column, each filtered by the shared search and scrolled on its own.
C._pick = { cd = { rows = {}, data = {}, offset = 0 }, au = { rows = {}, data = {}, offset = 0 },
            allCd = {}, allAu = {}, search = "" }

-- Build the two source lists from the CDM's SETTINGS DATA PROVIDER — the exact ORDERED,
-- displayed cooldownID set each viewer lays out (CooldownViewer.lua RefreshLayout calls
-- `CooldownViewerSettings:GetDataProvider():GetOrderedCooldownIDsForCategory(cat)`). This is the
-- authoritative "trackable" set and the right source for THREE reasons the alternatives got wrong:
--   1. FRAME-INDEPENDENT — a frame clears its cooldownID the instant it's released/hidden
--      (Blizzard's itemFramePool reset callback → ClearCooldownID → cooldownInfo=nil), and the
--      Essential viewer hides items while inactive (`hideWhenInactive`); so a frame-scan dropped
--      every ready-out-of-combat Essential cooldown (Rapid Fire, Aimed Shot, …).
--   2. Respects the SAVED LAYOUT + Blizzard's HideByDefault→Hidden remap + isKnown — so it lists
--      exactly what's displayed. The raw `GetCooldownViewerCategorySet` does NONE of that: it
--      returns raw pre-remap IDs, which under-returned the tracked buffs, and pairing it with a
--      manual HideByDefault filter then dropped known buffs the user DOES display (Lock and Load,
--      Trueshot, Aspects — anything HideByDefault-by-default but placed into a tracked category).
-- Essential/Utility → Cooldowns column; TrackedBuff/TrackedBar → Buffs/Debuffs (tagged Buff vs
-- Debuff via `selfAura`: true = on you, false/nil = on target). Each item carries its default
-- trigger `state` + semantic `k`, so the column you pick from sets the right condition + wording.
-- Rebuilt on every open. Falls back to the raw category set (with our own isKnown + HideByDefault
-- filtering) only if the data provider is somehow unavailable.
local function BuildAuraLists()
  wipe(C._pick.allCd); wipe(C._pick.allAu)
  local E = Enum and Enum.CooldownViewerCategory
  if not E then return end
  local dp = CooldownViewerSettings and CooldownViewerSettings.GetDataProvider
             and CooldownViewerSettings:GetDataProvider()
  local HIDE = Enum.CooldownSetSpellFlags and Enum.CooldownSetSpellFlags.HideByDefault
  local seen = {}
  local cats = {
    { E.Essential, "cd" }, { E.Utility, "cd" },
    { E.TrackedBuff, "au" }, { E.TrackedBar, "au" },
  }
  for _, c in ipairs(cats) do
    local cat, bucket = c[1], c[2]
    -- Primary: the viewer's own ordered/displayed list (already isKnown- + HideByDefault-filtered).
    local ids, viaDP = nil, false
    if dp and dp.GetOrderedCooldownIDsForCategory then
      pcall(function() ids = dp:GetOrderedCooldownIDsForCategory(cat, false); viaDP = true end)
    end
    -- Fallback: raw category set (we filter unlearned + HideByDefault ourselves below).
    if type(ids) ~= "table" and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet then
      viaDP = false
      pcall(function() ids = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true) end)
    end
    if type(ids) == "table" then
      for _, id in ipairs(ids) do
        if id ~= nil and not issecret(id) then
          local info
          if dp and dp.GetCooldownInfoForID then pcall(function() info = dp:GetCooldownInfoForID(id) end) end
          if not info and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
            pcall(function() info = C_CooldownViewer.GetCooldownViewerCooldownInfo(id) end)
          end
          local sid = info and info.spellID
          -- Only the fallback (raw set) path needs manual filtering; the DP list is pre-filtered.
          local skip = false
          if not viaDP and info then
            if info.isKnown == false then skip = true end
            local fl = info.flags
            if HIDE and fl ~= nil and not issecret(fl) and FlagsUtil and FlagsUtil.IsSet
               and FlagsUtil.IsSet(fl, HIDE) then skip = true end
          end
          if sid and not issecret(sid) and not skip then
            local k, tag = "cooldown", nil
            if bucket == "au" then
              -- selfAura is the reliable axis: true = on you (buff), false/nil = on target (debuff).
              -- (hasAura is NOT a reliable proc signal — it also flags cooldown-granted buffs like
              -- Aspect of the Turtle — so we don't tag procs separately.)
              local sa = info.selfAura
              local isBuff = (sa ~= nil and not issecret(sa) and sa == true)
              k   = isBuff and "buff" or "debuff"
              tag = isBuff and "Buff" or "Debuff"
            end
            local key = bucket .. ":" .. sid .. ":" .. k
            if not seen[key] then
              seen[key] = true
              local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid)) or ("Spell " .. sid)
              local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)
              local item = { spellID = sid, name = name, icon = icon,
                state = (bucket == "cd") and "cd_ready" or "buff_active", k = k, tag = tag }
              if bucket == "cd" then C._pick.allCd[#C._pick.allCd + 1] = item
              else C._pick.allAu[#C._pick.allAu + 1] = item end
            end
          end
        end
      end
    end
  end
end

local function RefreshPicker()
  local q = (C._pick.search or ""):lower()
  local trackH = PICK_ROWS * PICK_ROW_H
  for _, key in ipairs({ "cd", "au" }) do
    local p = C._pick[key]
    wipe(p.data)
    for _, it in ipairs((key == "cd") and C._pick.allCd or C._pick.allAu) do
      if q == "" or (it.name and it.name:lower():find(q, 1, true)) then p.data[#p.data + 1] = it end
    end
    local n = #p.data
    local maxOff = math.max(0, n - PICK_ROWS)
    if p.offset > maxOff then p.offset = maxOff end
    if p.offset < 0 then p.offset = 0 end
    for i = 1, PICK_ROWS do
      local row, item = p.rows[i], p.data[i + p.offset]
      if row then
        if item then
          row.item = item
          row.icon:SetTexture(item.icon or 134400)
          row.text:SetText(item.tag and ("%s  |cff888888(%s)|r"):format(item.name, item.tag) or item.name)
          row:Show()
        else
          row.item = nil; row:Hide()
        end
      end
    end
    if p.thumb and p.track then
      if n <= PICK_ROWS then
        p.thumb:Hide()
      else
        p.thumb:Show()
        local thumbH = math.max(24, trackH * (PICK_ROWS / n))
        p.thumb:SetHeight(thumbH)
        p.thumb:ClearAllPoints()
        p.thumb:SetPoint("TOP", p.track, "TOP", 0, -(trackH - thumbH) * (p.offset / maxOff))
      end
    end
  end
end

local function BuildPicker()
  local GAP = 14
  local colX = { cd = GAP, au = GAP + PICK_COL_W + GAP }
  local ROWS_TOP = -104
  local W = GAP + PICK_COL_W + GAP + PICK_COL_W + GAP
  local H = -ROWS_TOP + PICK_ROWS * PICK_ROW_H + 28
  local f = CreateFrame("Frame", "GloomsAurasPicker", UIParent)
  f:SetSize(W, H); f:SetPoint("CENTER"); f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:EnableMouse(true)
  skinPlate(f)

  local title = newText(f, FONT.title, 18, COLOR.purple, "CENTER")
  title:SetPoint("TOP", 0, -12); title:SetText("Choose a spell to track")
  local close = flatButton(f, 22, 20, COLOR.heroic, "X", 12)
  close:SetPoint("TOPRIGHT", -8, -8); close:SetScript("OnClick", function() f:Hide() end)

  -- Movable title bar (standard hold-drag).
  f:SetMovable(true); f:SetClampedToScreen(true)
  local ptb = CreateFrame("Frame", nil, f)
  ptb:SetPoint("TOPLEFT", 2, -2); ptb:SetPoint("TOPRIGHT", -34, -2); ptb:SetHeight(28)
  ptb:EnableMouse(true); ptb:RegisterForDrag("LeftButton")
  ptb:SetScript("OnDragStart", function() if f:IsMovable() then f:StartMoving() end end)
  ptb:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

  -- Search box (filters BOTH columns by name).
  local sb = flatEditBox(f, W - 2 * GAP, 22); sb:SetPoint("TOPLEFT", GAP, -46)
  sb:SetScript("OnTextChanged", function(self) C._pick.search = self:GetText() or ""; RefreshPicker() end)
  sb:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  local sl = newText(f, FONT.body, 11, MUTE, "LEFT"); sl:SetPoint("BOTTOMLEFT", sb, "TOPLEFT", 2, 3); sl:SetText("Search")

  -- Two columns: Cooldowns (cd) + Buffs & Debuffs (au). Each is a mouse-wheel container
  -- whose child rows propagate the wheel up to it, so each column scrolls independently.
  local headers = { cd = "Cooldowns", au = "Buffs & Debuffs" }
  for _, key in ipairs({ "cd", "au" }) do
    local p, x = C._pick[key], colX[key]
    local hdr = newText(f, FONT.title, 13, COLOR.purple, "LEFT")
    hdr:SetPoint("TOPLEFT", x, -84); hdr:SetText(headers[key])

    local col = CreateFrame("Frame", nil, f)
    col:SetPoint("TOPLEFT", x, ROWS_TOP); col:SetSize(PICK_COL_W, PICK_ROWS * PICK_ROW_H)
    col:EnableMouseWheel(true)
    col:SetScript("OnMouseWheel", function(_, delta) p.offset = p.offset - delta; RefreshPicker() end)

    local track = col:CreateTexture(nil, "ARTWORK"); track:SetColorTexture(1, 1, 1, 0.08)
    track:SetPoint("TOPRIGHT", 0, 0); track:SetSize(6, PICK_ROWS * PICK_ROW_H); p.track = track
    p.thumb = col:CreateTexture(nil, "OVERLAY"); p.thumb:SetColorTexture(COLOR.orange.r, COLOR.orange.g, COLOR.orange.b, 1)
    p.thumb:SetWidth(6); p.thumb:SetPoint("TOP", track, "TOP")

    for i = 1, PICK_ROWS do
      local row = CreateFrame("Button", nil, col)
      row:SetSize(PICK_COL_W - 12, 22); row:SetPoint("TOPLEFT", 0, -(i - 1) * PICK_ROW_H)
      local hl = row:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b, 0.20)
      local icon = row:CreateTexture(nil, "ARTWORK"); icon:SetSize(18, 18); icon:SetPoint("LEFT", 2, 0); row.icon = icon
      local text = newText(row, FONT.body, 12, TEXT, "LEFT"); text:SetPoint("LEFT", 24, 0); text:SetPoint("RIGHT", -4, 0); row.text = text
      row:SetScript("OnClick", function(self)
        local item = self.item; if not item then return end
        if pickerOnPick then                 -- picking for a trigger condition
          local cb = pickerOnPick; pickerOnPick = nil
          f:Hide(); cb(item)
        end
      end)
      p.rows[i] = row
    end
  end

  local footer = newText(f, FONT.body, 11, MUTE, "CENTER")
  footer:SetPoint("BOTTOM", 0, 8); footer:SetText("mouse-wheel a column to scroll")

  f:SetScript("OnShow", function()
    BuildAuraLists()
    C._pick.search = ""; if sb then sb:SetText("") end
    C._pick.cd.offset = 0; C._pick.au.offset = 0
    RefreshPicker()
  end)
  tinsert(UISpecialFrames, "GloomsAurasPicker")
  f:Hide()  -- created hidden so the first OpenPicker transitions + fires OnShow
  pickerFrame = f; RegisterSubWindow(f)
  return f
end

local function OpenPicker(onPick)
  pickerOnPick = onPick  -- nil = default (add a display); set = return spellID to caller
  if not pickerFrame then
    local ok, err = pcall(BuildPicker)
    if not ok then GA.msg("|cffff5555aura picker failed to build|r: " .. tostring(err)); return end
  end
  -- Picked FROM the Trigger editor (onPick set) → keep it open underneath.
  CloseSubWindows(pickerFrame, onPick and C._trig.frame or nil)
  pickerFrame:Show(); pickerFrame:Raise()
end

-- --------------------------------------------------------------------------
-- Texture picker: browse game icons + textures other addons registered into
-- LibSharedMedia (StoneTweaks' custom textures, etc.); click one to set the
-- selected display's art. Category via a dropdown; search filters by name where
-- names exist (LSM). Scrolls with the mouse wheel.
-- --------------------------------------------------------------------------
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local texPickerFrame, texPickerOnPick, texCatButton, texCatMenu, texSearchBox, texSearchLabel
local texCells, texData, texOffset, texCurrentCat, texCurrentTex = {}, {}, 0, nil, nil
local TEX_COLS, TEX_ROWS, TEX_CELL = 6, 5, 58
local TEX_PER = TEX_COLS * TEX_ROWS

-- Category providers: each returns an array of { tex = fileID|path, name = str }.
local function CatGameIcons()
  local out, raw = {}, {}
  if GetLooseMacroIcons then GetLooseMacroIcons(raw) end
  if GetMacroIcons then GetMacroIcons(raw) end
  if GetLooseMacroItemIcons then GetLooseMacroItemIcons(raw) end
  if GetMacroItemIcons then GetMacroItemIcons(raw) end
  for _, v in ipairs(raw) do
    local n = tonumber(v)
    if n then out[#out + 1] = { tex = n, name = "" }
    else out[#out + 1] = { tex = "Interface\\ICONS\\" .. v, name = tostring(v) } end
  end
  return out
end

local function CatLSM()
  local out = {}
  if LSM then
    for _, mt in ipairs({ "statusbar", "background", "border" }) do
      local tbl = LSM.HashTable and LSM:HashTable(mt)
      if tbl then for name, path in pairs(tbl) do out[#out + 1] = { tex = path, name = name } end end
    end
    table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
  end
  return out
end

-- The suite's custom Graphics + Textures — the Hub's media catalog (GloomsHubDB,
-- copy-migrated from StoneTweaks in Hub Phase A; managed in the Media tab).
-- GloomsHub:ListMedia already returns picker-shaped rows ({ name=, tex=path })
-- with paths under the Hub (CONTRACTS §3) — GA never builds media paths again.
-- (Replaces the old CatStoneTweaks, which read _G.StoneTweaksDB directly and
-- hardcoded Interface\AddOns\StoneTweaks\ paths — Phase D, per SUITE-PLAN §4.4.)
local function CatSuiteMedia()
  local out = {}
  for _, kind in ipairs({ "graphics", "textures" }) do
    for _, row in ipairs(GloomsHub:ListMedia(kind)) do out[#out + 1] = row end
  end
  return out
end

-- Category order: bundled aura shapes first (Shapes, PowerAuras, Beams…), then
-- game icons, your suite media catalog (the Hub's), and LSM bar textures.
local TEX_CATS = {}
if GA.TextureShapes then
  for _, group in ipairs(GA.TextureShapes) do
    local items = group.items
    TEX_CATS[#TEX_CATS + 1] = { key = "shape:" .. group.cat, label = group.cat,
      searchable = true, cache = true, provider = function() return items end }
  end
end
-- Game icons come from the client as fileIDs with NO names, so a name search can't
-- work. Instead the search box becomes a "Spell ID" lookup: type a spell ID to show
-- that spell's icon. Empty box = browse the full grid.
TEX_CATS[#TEX_CATS + 1] = { key = "icons",  label = "Game Icons",          provider = CatGameIcons,   searchMode = "spellid", cache = true }
TEX_CATS[#TEX_CATS + 1] = { key = "suite",  label = "Suite Graphics",      provider = CatSuiteMedia,  searchable = true }
TEX_CATS[#TEX_CATS + 1] = { key = "lsm",    label = "Shared Media (bars)", provider = CatLSM,         searchable = true }

local DEFAULT_TEX_CAT = TEX_CATS[1] and TEX_CATS[1].key or "icons"

local function TexCat(key)
  for _, c in ipairs(TEX_CATS) do if c.key == key then return c end end
  return TEX_CATS[1]
end

local function catItems(cat)
  if cat.cache then
    if not cat._cache then cat._cache = cat.provider() or {} end
    return cat._cache
  end
  return cat.provider() or {}
end

local function RefreshTexGrid()
  local n = #texData
  local maxOff = math.max(0, n - TEX_PER)
  if texOffset > maxOff then texOffset = maxOff end
  if texOffset < 0 then texOffset = 0 end
  local cur = texCurrentTex and tostring(texCurrentTex)
  for i = 1, TEX_PER do
    local cell, item = texCells[i], texData[i + texOffset]
    if item then
      cell.item = item
      cell.tex:SetTexture(item.tex)
      cell.sel:SetShown(cur ~= nil and tostring(item.tex) == cur)
      cell:Show()
    else
      cell.item = nil; cell:Hide()
    end
  end
end

local function RebuildTexData()
  local cat = TexCat(texCurrentCat)
  local all = catItems(cat)
  local q = texSearchBox and texSearchBox:GetText()
  q = (q and q ~= "") and q or nil
  if cat.searchMode == "spellid" then
    -- Type a spell ID → show that spell's icon; empty = browse all game icons.
    if q then
      local id = tonumber(q)
      local tx = id and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
      texData = tx and { { tex = tx, name = "" } } or {}
    else
      texData = all
    end
  elseif cat.searchable and q then
    local ql = q:lower()
    texData = {}
    for _, it in ipairs(all) do
      if it.name and it.name:lower():find(ql, 1, true) then texData[#texData + 1] = it end
    end
  else
    texData = all
  end
  texOffset = 0
  RefreshTexGrid()
end

local function SetTexCat(key)
  texCurrentCat = key
  local cat = TexCat(key)
  if texCatButton then texCatButton:SetText(cat.label) end
  if texSearchBox then texSearchBox:SetText("") end
  if texSearchLabel then texSearchLabel:SetText(cat.searchMode == "spellid" and "Spell ID" or "Search") end
  RebuildTexData()
end

local function BuildTexturePicker()
  local GX = 26
  local W = GX * 2 + TEX_COLS * TEX_CELL
  local H = 96 + TEX_ROWS * TEX_CELL + 20
  local f = CreateFrame("Frame", "GloomsAurasTexPicker", UIParent)
  f:SetSize(W, H); f:SetPoint("CENTER"); f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:EnableMouse(true); f:EnableMouseWheel(true)
  skinPlate(f)

  local title = newText(f, FONT.title, 18, COLOR.purple, "CENTER"); title:SetPoint("TOP", 0, -12)
  title:SetText("Choose a texture")
  local close = flatButton(f, 22, 20, COLOR.heroic, "X", 12)
  close:SetPoint("TOPRIGHT", -8, -8); close:SetScript("OnClick", function() f:Hide() end)

  f:SetMovable(true); f:SetClampedToScreen(true)
  local tb = CreateFrame("Frame", nil, f); tb:SetPoint("TOPLEFT", 2, -2); tb:SetPoint("TOPRIGHT", -34, -2)
  tb:SetHeight(28); tb:EnableMouse(true); tb:RegisterForDrag("LeftButton")
  tb:SetScript("OnDragStart", function() if f:IsMovable() then f:StartMoving() end end)
  tb:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

  -- Category dropdown (button + drop-down menu).
  texCatButton = flatButton(f, 168, 20, COLOR.heroic, "Shapes", 12)
  texCatButton:SetPoint("TOPLEFT", GX, -40)
  texCatMenu = CreateFrame("Frame", nil, f); texCatMenu:SetFrameStrata("FULLSCREEN_DIALOG")
  texCatMenu:SetSize(200, #TEX_CATS * 22 + 8)
  texCatMenu:SetPoint("TOPLEFT", texCatButton, "BOTTOMLEFT", 0, -2)
  texCatMenu:SetFrameLevel((f:GetFrameLevel() or 1) + 20)  -- render above the grid cells
  skinPlate(texCatMenu); texCatMenu:Hide()
  for i, cat in ipairs(TEX_CATS) do
    local item = flatButton(texCatMenu, 192, 20, COLOR.heroic, cat.label, 12); item:SetBase(0.12)
    item:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 22)
    item:SetScript("OnClick", function() texCatMenu:Hide(); SetTexCat(cat.key) end)
  end
  texCatButton:SetScript("OnClick", function() texCatMenu:SetShown(not texCatMenu:IsShown()) end)

  -- Search box (filters the current category by name, where names exist).
  texSearchBox = flatEditBox(f, 110, 20)
  texSearchBox:SetPoint("TOPRIGHT", -20, -40)
  texSearchBox:SetScript("OnTextChanged", function() RebuildTexData() end)
  texSearchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  local sl = newText(f, FONT.body, 11, MUTE, "RIGHT"); sl:SetPoint("RIGHT", texSearchBox, "LEFT", -8, 0)
  sl:SetText("Search")

  -- Grid of texture cells.
  for i = 1, TEX_PER do
    local col, rown = (i - 1) % TEX_COLS, math.floor((i - 1) / TEX_COLS)
    local cell = CreateFrame("Button", nil, f)
    cell:SetSize(TEX_CELL - 6, TEX_CELL - 6)
    cell:SetPoint("TOPLEFT", GX + col * TEX_CELL, -70 - rown * TEX_CELL)
    local sel = cell:CreateTexture(nil, "BACKGROUND")
    sel:SetPoint("TOPLEFT", -2, 2); sel:SetPoint("BOTTOMRIGHT", 2, -2)
    sel:SetColorTexture(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b, 1); sel:Hide(); cell.sel = sel
    local t = cell:CreateTexture(nil, "ARTWORK"); t:SetAllPoints(); cell.tex = t
    local hl = cell:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.25)
    cell:SetScript("OnClick", function(self)
      if not self.item then return end
      texCurrentTex = self.item.tex
      if texPickerOnPick then texPickerOnPick(self.item.tex) end
      RefreshTexGrid()
    end)
    cell:SetScript("OnEnter", function(self)
      if self.item and self.item.name and self.item.name ~= "" then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.item.name); GameTooltip:Show()
      end
    end)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    texCells[i] = cell
  end

  local footer = newText(f, FONT.body, 11, MUTE, "CENTER")
  footer:SetPoint("BOTTOM", 0, 8); footer:SetText("mouse-wheel to scroll · click to apply")

  f:SetScript("OnMouseWheel", function(_, d) texOffset = texOffset - d * TEX_COLS; RefreshTexGrid() end)
  tinsert(UISpecialFrames, "GloomsAurasTexPicker")
  f:Hide()
  texPickerFrame = f; RegisterSubWindow(f)
  return f
end

local function OpenTexturePicker(onPick, current)
  texPickerOnPick = onPick
  texCurrentTex = current
  if not texPickerFrame then
    local ok, err = pcall(BuildTexturePicker)
    if not ok then GA.msg("|cffff5555texture picker failed to build|r: " .. tostring(err)); return end
  end
  if texCatMenu then texCatMenu:Hide() end
  SetTexCat(texCurrentCat or DEFAULT_TEX_CAT)
  CloseSubWindows(texPickerFrame)
  DockRight(texPickerFrame)
  texPickerFrame:Show(); texPickerFrame:Raise()
end

-- --------------------------------------------------------------------------
-- Sound picker: browse sounds registered into LibSharedMedia (BigWigs packs,
-- etc.) plus "None". Click to apply + preview. Stored per display as
-- cfg.sound = { file, name, channel }; CDM:PlaySound fires it on hidden→shown.
-- --------------------------------------------------------------------------
local SND_ROWS = 12
local soundPickerFrame, soundPickerOnPick, soundSearchBox
local soundRows, soundData, soundAll, soundOffset, soundCurrent = {}, {}, nil, 0, nil

local function BuildSoundList()
  local out = { { name = "None", file = nil } }
  if LSM and LSM.HashTable then
    local t = LSM:HashTable("sound")
    if t then
      local names = {}
      for name in pairs(t) do names[#names + 1] = name end
      table.sort(names, function(a, b) return a:lower() < b:lower() end)
      for _, name in ipairs(names) do out[#out + 1] = { name = name, file = t[name] } end
    end
  end
  return out
end

local function RefreshSoundList()
  local n = #soundData
  local maxOff = math.max(0, n - SND_ROWS)
  if soundOffset > maxOff then soundOffset = maxOff end
  if soundOffset < 0 then soundOffset = 0 end
  for i = 1, SND_ROWS do
    local row, item = soundRows[i], soundData[i + soundOffset]
    if item then
      row.item = item
      row.name:SetText(item.name)
      local isCur = (item.file == nil and soundCurrent == nil)
                 or (item.file ~= nil and tostring(item.file) == tostring(soundCurrent))
      row.sel:SetShown(isCur)
      row:Show()
    else
      row.item = nil; row:Hide()
    end
  end
  -- Reposition the scrollbar thumb.
  local sb = soundPickerFrame and soundPickerFrame.sb
  if sb then
    if n <= SND_ROWS then
      sb.thumb:Hide()
    else
      sb.thumb:Show()
      local thumbH = math.max(20, sb.h * SND_ROWS / n)
      sb.thumb:SetHeight(thumbH)
      local frac = maxOff > 0 and (soundOffset / maxOff) or 0
      sb.thumb:ClearAllPoints()
      sb.thumb:SetPoint("TOPRIGHT", soundPickerFrame, "TOPRIGHT", sb.x, sb.top - (sb.h - thumbH) * frac)
    end
  end
end

local function RebuildSoundData()
  if not soundAll then soundAll = BuildSoundList() end
  local q = soundSearchBox and soundSearchBox:GetText()
  q = (q and q ~= "") and q:lower() or nil
  if q then
    soundData = {}
    for _, it in ipairs(soundAll) do if it.name:lower():find(q, 1, true) then soundData[#soundData + 1] = it end end
  else
    soundData = soundAll
  end
  soundOffset = 0
  RefreshSoundList()
end

local function BuildSoundPicker()
  local W, H = 320, 68 + SND_ROWS * 24 + 30
  local f = CreateFrame("Frame", "GloomsAurasSoundPicker", UIParent)
  f:SetSize(W, H); f:SetPoint("CENTER"); f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:EnableMouse(true); f:EnableMouseWheel(true)
  skinPlate(f)

  local title = newText(f, FONT.title, 18, COLOR.purple, "CENTER"); title:SetPoint("TOP", 0, -12)
  title:SetText("Choose a sound")
  local close = flatButton(f, 22, 20, COLOR.heroic, "X", 12)
  close:SetPoint("TOPRIGHT", -8, -8); close:SetScript("OnClick", function() f:Hide() end)

  f:SetMovable(true); f:SetClampedToScreen(true)
  local tb = CreateFrame("Frame", nil, f); tb:SetPoint("TOPLEFT", 2, -2); tb:SetPoint("TOPRIGHT", -34, -2)
  tb:SetHeight(28); tb:EnableMouse(true); tb:RegisterForDrag("LeftButton")
  tb:SetScript("OnDragStart", function() if f:IsMovable() then f:StartMoving() end end)
  tb:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

  soundSearchBox = flatEditBox(f, 150, 20); soundSearchBox:SetPoint("TOPRIGHT", -14, -38)
  soundSearchBox:SetScript("OnTextChanged", function() RebuildSoundData() end)
  soundSearchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  local sl = newText(f, FONT.body, 11, MUTE, "LEFT"); sl:SetPoint("TOPLEFT", 14, -42); sl:SetText("Search")

  for i = 1, SND_ROWS do
    local row = CreateFrame("Button", nil, f); row:SetSize(W - 28, 22)
    row:SetPoint("TOPLEFT", 14, -66 - (i - 1) * 24)
    local sel = row:CreateTexture(nil, "BACKGROUND"); sel:SetAllPoints()
    sel:SetColorTexture(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b, 0.28); sel:Hide(); row.sel = sel
    local hl = row:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.10)
    local name = newText(row, FONT.body, 12, TEXT, "LEFT"); name:SetPoint("LEFT", 8, 0); name:SetPoint("RIGHT", -8, 0); row.name = name
    row:SetScript("OnClick", function(self)
      if not self.item then return end
      soundCurrent = self.item.file
      if soundPickerOnPick then soundPickerOnPick(self.item) end
      if self.item.file then pcall(PlaySoundFile, self.item.file, "Master") end
      RefreshSoundList()
    end)
    soundRows[i] = row
  end

  -- Scrollbar: a draggable ORANGE thumb on the right (the wheel also scrolls).
  local SB_X, SB_TOP, SB_H = -6, -66, SND_ROWS * 24 - 2
  local track = f:CreateTexture(nil, "ARTWORK"); track:SetColorTexture(1, 1, 1, 0.06)
  track:SetPoint("TOPRIGHT", SB_X, SB_TOP); track:SetSize(6, SB_H)
  local thumb = CreateFrame("Button", nil, f); thumb:SetWidth(6); thumb:EnableMouse(true)
  local tt = thumb:CreateTexture(nil, "OVERLAY"); tt:SetAllPoints()
  tt:SetColorTexture(COLOR.orange.r, COLOR.orange.g, COLOR.orange.b, 1)
  thumb:SetPoint("TOPRIGHT", SB_X, SB_TOP)
  f.sb = { thumb = thumb, top = SB_TOP, h = SB_H, x = SB_X }

  local dragging, startCursorY, startOffset = false, 0, 0
  thumb:SetScript("OnMouseDown", function()
    dragging = true; startOffset = soundOffset
    local _, cy = GetCursorPosition(); startCursorY = cy / f:GetEffectiveScale()
  end)
  thumb:SetScript("OnMouseUp", function() dragging = false end)
  thumb:SetScript("OnUpdate", function()
    if not dragging then return end
    local n = #soundData; local maxOff = math.max(0, n - SND_ROWS)
    local range = SB_H - thumb:GetHeight()
    if maxOff <= 0 or range <= 0 then return end
    local _, cyRaw = GetCursorPosition()
    local movedDown = startCursorY - (cyRaw / f:GetEffectiveScale())  -- cursor down = scroll down
    soundOffset = math.max(0, math.min(maxOff, math.floor(startOffset + (movedDown / range) * maxOff + 0.5)))
    RefreshSoundList()
  end)

  local footer = newText(f, FONT.body, 11, MUTE, "CENTER"); footer:SetPoint("BOTTOM", 0, 8)
  footer:SetText("click to apply + preview · drag the bar or use the wheel")
  f:SetScript("OnMouseWheel", function(_, d) soundOffset = soundOffset - d; RefreshSoundList() end)
  tinsert(UISpecialFrames, "GloomsAurasSoundPicker")
  f:Hide()
  soundPickerFrame = f; RegisterSubWindow(f)
  return f
end

local function OpenSoundPicker(onPick, current)
  soundPickerOnPick = onPick
  soundCurrent = current
  soundAll = nil  -- re-read the LSM sound list each open
  if not soundPickerFrame then
    local ok, err = pcall(BuildSoundPicker)
    if not ok then GA.msg("|cffff5555sound picker failed to build|r: " .. tostring(err)); return end
  end
  if soundSearchBox then soundSearchBox:SetText("") end
  RebuildSoundData()
  CloseSubWindows(soundPickerFrame)
  DockRight(soundPickerFrame)
  soundPickerFrame:Show(); soundPickerFrame:Raise()
end

-- --------------------------------------------------------------------------
-- Trigger editor: one-level GROUPED boolean logic. cfg.trigger =
--   { logic, conditions = { <leaf> | <group>, ... } }
-- leaf  = { spellID, state, name };  group = { logic, conditions = { <leaf>, ... } }.
-- logic ∈ AND (all) / OR (any) / NONE (nor = NOT any). Groups nest ONE level in the
-- UI (the engine recurses regardless). State/functions hang on C._trig to keep
-- Config.lua under Lua's 200-locals-per-chunk cap.
-- --------------------------------------------------------------------------
C._trig = { rows = {}, offset = 0, ROWS = 9 }

function C:LogicLabel(l)
  if l == "OR" then return "Match Any (OR)"
  elseif l == "NONE" then return "Match None (NOR)"
  else return "Match All (AND)" end
end
function C:LogicNext(l)
  if l == "OR" then return "NONE" elseif l == "NONE" then return "AND" else return "OR" end
end

function C:TrigCfg() return C._trig.editID and DB() and DB()[C._trig.editID] end
function C:TrigTree()
  local cfg = self:TrigCfg(); if not cfg then return nil end
  cfg.trigger = cfg.trigger or { logic = "AND", conditions = {} }
  return cfg.trigger
end
-- The node at a path: (ti) = top item (leaf or group); (ti, ci) = a group's child leaf.
function C:TrigNode(ti, ci)
  local t = self:TrigTree(); if not t then return nil end
  local top = t.conditions[ti]; if not top then return nil end
  if ci then return top.conditions and top.conditions[ci] end
  return top
end

function C:TrigRebind()   -- watch set changed → rebind spells, then re-render
  if GA.CDM then GA.CDM:Discover() end
  self:TrigRender()
end

function C:TrigAddLeaf(item, ti)
  local t = self:TrigTree(); if not t then return end
  if type(item) == "number" then item = { spellID = item } end   -- back-compat / safety
  local spellID = item.spellID; if not spellID then return end
  local list = (ti and t.conditions[ti] and t.conditions[ti].conditions) or t.conditions
  local state = item.state
  if not state then                                              -- fell through without a picked column
    local kind = GA.CDM and GA.CDM.kind and GA.CDM.kind[spellID]
    state = (kind == "cooldown") and "cd_ready" or "buff_active"
  end
  local name = item.name or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID))
  local leaf = { spellID = spellID, state = state, name = name }
  if item.k then leaf.k = item.k end                             -- buff/debuff/proc → wording
  table.insert(list, leaf)
  self:TrigRebind()
end
function C:TrigAddGroup()
  local t = self:TrigTree(); if not t then return end
  table.insert(t.conditions, { logic = "OR", conditions = {} })   -- OR is the usual reason to group
  self:TrigRender()   -- empty group: no watch-set change yet
end
function C:TrigRemove(ti, ci)
  local t = self:TrigTree(); if not t then return end
  if ci then
    local grp = t.conditions[ti]
    if grp and grp.conditions then table.remove(grp.conditions, ci) end
  else
    table.remove(t.conditions, ti)   -- a group removes with its conditions
  end
  self:TrigRebind()
end
function C:TrigCycleState(ti, ci)
  local leaf = self:TrigNode(ti, ci); if not leaf or not leaf.state then return end
  -- Cycle within the leaf's own FAMILY (never let a debuff become a nonsensical "cooldown ready"):
  --  • aura     → active <-> inactive
  --  • cooldown → ready <-> on-cd, and for a CHARGE spell also at-max <-> not-at-max charges
  --    (the charge states are only reachable on a spell that actually uses charges).
  local cdStates = (leaf.state == "cd_ready" or leaf.state == "cd_oncd"
                    or leaf.state == "charges_max" or leaf.state == "charges_notmax")
  local list
  if cdStates then
    local isCharge = GA.CDM and GA.CDM.isCharge and GA.CDM.isCharge[leaf.spellID]
    list = isCharge and { "cd_ready", "cd_oncd", "charges_max", "charges_notmax" }
                     or { "cd_ready", "cd_oncd" }
  else
    list = { "buff_active", "buff_inactive" }
  end
  local idx = 1
  for i, s in ipairs(list) do if s == leaf.state then idx = i; break end end
  leaf.state = list[(idx % #list) + 1]   -- advance, wrapping
  if GA.CDM then GA.CDM:RefreshDisplays() end
  self:TrigRender()
end
function C:TrigCycleLogic(ti)
  local t = self:TrigTree(); if not t then return end
  local node = ti and t.conditions[ti] or t
  node.logic = self:LogicNext(node.logic)
  if GA.CDM then GA.CDM:RefreshDisplays() end
  self:TrigRender()
end

-- Flatten the tree into render descriptors: leaf | ghead | gleaf | gadd.
function C:TrigEntries()
  local out, t = {}, self:TrigTree()
  if not t then return out end
  for ti, node in ipairs(t.conditions) do
    if node.conditions then
      out[#out + 1] = { kind = "ghead", ti = ti }
      for ci in ipairs(node.conditions) do out[#out + 1] = { kind = "gleaf", ti = ti, ci = ci } end
      out[#out + 1] = { kind = "gadd", ti = ti }
    else
      out[#out + 1] = { kind = "leaf", ti = ti }
    end
  end
  return out
end

function C:RenderTrigRow(row, e)
  row.kind, row.ti, row.ci = nil, nil, nil
  if not e then row:Hide(); return end
  row.kind, row.ti, row.ci = e.kind, e.ti, e.ci
  row.bracket:SetShown(e.kind ~= "leaf")   -- bracket on group rows only
  if e.kind == "leaf" or e.kind == "gleaf" then
    local indented = (e.kind == "gleaf")
    local leaf = self:TrigNode(e.ti, e.ci)
    row.icon:ClearAllPoints(); row.icon:SetPoint("LEFT", indented and 20 or 2, 0); row.icon:Show()
    local ic = leaf and leaf.spellID and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(leaf.spellID)
    row.icon:SetTexture(ic or 134400)
    row.name:ClearAllPoints(); row.name:SetPoint("LEFT", indented and 46 or 28, 0); row.name:SetWidth(indented and 96 or 114)
    row.name:SetText((leaf and (leaf.name or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(leaf.spellID)))) or tostring(leaf and leaf.spellID or "?"))
    row.name:SetTextColor(TEXT.r, TEXT.g, TEXT.b); row.name:Show()
    row.mid:SetText(StateLabel(leaf and leaf.state, leaf and leaf.k)); row.mid:Show()
    row.rem:Show(); row.add:Hide()
  elseif e.kind == "ghead" then
    local grp = self:TrigNode(e.ti)
    row.icon:Hide()
    row.name:ClearAllPoints(); row.name:SetPoint("LEFT", 20, 0); row.name:SetWidth(120)
    row.name:SetText("GROUP"); row.name:SetTextColor(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b); row.name:Show()
    row.mid:SetText(self:LogicLabel(grp and grp.logic)); row.mid:Show()
    row.rem:Show(); row.add:Hide()
  else  -- gadd
    row.icon:Hide(); row.name:Hide(); row.mid:Hide(); row.rem:Hide()
    row.addText:SetTextColor(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b)
    row.add:Show()
  end
  row:Show()
end

function C:TrigRender()
  if C.TrigInlineRender then C:TrigInlineRender() end   -- inline accordion section (redesign)
  if not C._trig.frame then return end
  local cfg = self:TrigCfg(); if not cfg then return end
  local t = self:TrigTree()
  C._trig.title:SetText("Trigger: " .. (cfg.label or tostring(C._trig.editID)))
  C._trig.logicBtn:SetText(self:LogicLabel(t.logic))
  local entries = self:TrigEntries()
  local maxOff = math.max(0, #entries - C._trig.ROWS)
  if C._trig.offset > maxOff then C._trig.offset = maxOff end
  if C._trig.offset < 0 then C._trig.offset = 0 end
  for i = 1, C._trig.ROWS do
    self:RenderTrigRow(C._trig.rows[i], entries[i + C._trig.offset])
  end
end

function C:BuildTriggerEditor()
  local W, H = 388, 384
  local f = CreateFrame("Frame", "GloomsAurasTrigger", UIParent)
  f:SetSize(W, H); f:SetPoint("CENTER"); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:EnableMouse(true); f:EnableMouseWheel(true)
  skinPlate(f)
  C._trig.title = newText(f, FONT.title, 18, COLOR.purple, "CENTER"); C._trig.title:SetPoint("TOP", 0, -12); C._trig.title:SetText("Trigger")
  local close = flatButton(f, 22, 20, COLOR.heroic, "X", 12); close:SetPoint("TOPRIGHT", -8, -8); close:SetScript("OnClick", function() f:Hide() end)
  f:SetMovable(true); f:SetClampedToScreen(true)
  local tb = CreateFrame("Frame", nil, f); tb:SetPoint("TOPLEFT", 2, -2); tb:SetPoint("TOPRIGHT", -34, -2); tb:SetHeight(28); tb:EnableMouse(true); tb:RegisterForDrag("LeftButton")
  tb:SetScript("OnDragStart", function() if f:IsMovable() then f:StartMoving() end end); tb:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

  C._trig.logicBtn = flatButton(f, 150, 22, COLOR.purple, "Match All (AND)", 12)
  C._trig.logicBtn:SetPoint("TOPLEFT", 16, -40)
  C._trig.logicBtn:SetScript("OnClick", function() C:TrigCycleLogic(nil) end)
  local lh = newText(f, FONT.body, 11, MUTE, "LEFT"); lh:SetPoint("LEFT", C._trig.logicBtn, "RIGHT", 8, 0); lh:SetText("how the rows below combine")

  f:SetScript("OnMouseWheel", function(_, d) C._trig.offset = C._trig.offset - d; C:TrigRender() end)

  for i = 1, C._trig.ROWS do
    local row = CreateFrame("Frame", nil, f); row:SetSize(354, 24); row:SetPoint("TOPLEFT", 16, -70 - (i - 1) * 26)
    local bracket = row:CreateTexture(nil, "ARTWORK"); bracket:SetColorTexture(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b, 0.5)
    bracket:SetPoint("TOPLEFT", 4, 3); bracket:SetSize(2, 26); row.bracket = bracket
    local icon = row:CreateTexture(nil, "ARTWORK"); icon:SetSize(20, 20); icon:SetPoint("LEFT", 2, 0); row.icon = icon
    local name = newText(row, FONT.body, 12, TEXT, "LEFT"); name:SetPoint("LEFT", 28, 0); name:SetWidth(114); name:SetWordWrap(false); row.name = name
    local mid = flatButton(row, 152, 20, COLOR.heroic, "", 11); mid:SetPoint("LEFT", 154, 0); row.mid = mid
    mid:SetScript("OnClick", function()
      if row.kind == "ghead" then C:TrigCycleLogic(row.ti)
      elseif row.kind == "leaf" or row.kind == "gleaf" then C:TrigCycleState(row.ti, row.ci) end
    end)
    local rem = flatButton(row, 22, 20, COLOR.orange, "X", 12); rem:SetPoint("RIGHT", 0, 0); row.rem = rem
    rem:SetScript("OnClick", function()
      if row.kind == "leaf" or row.kind == "ghead" then C:TrigRemove(row.ti, nil)
      elseif row.kind == "gleaf" then C:TrigRemove(row.ti, row.ci) end
    end)
    -- "+ Add to group" is a purple TEXT LINK (not a full button) so the grouped
    -- rows don't read as a wall of buttons; it brightens to white on hover.
    local add = CreateFrame("Button", nil, row); add:SetSize(120, 18); add:SetPoint("LEFT", 46, 0); row.add = add
    row.addText = newText(add, FONT.bodyM, 12, COLOR.purple, "LEFT"); row.addText:SetPoint("LEFT", 0, 0); row.addText:SetText("+ Add to group")
    add:SetFontString(row.addText)
    add:SetScript("OnEnter", function() row.addText:SetTextColor(1, 1, 1) end)
    add:SetScript("OnLeave", function() row.addText:SetTextColor(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b) end)
    add:SetScript("OnClick", function() local ti = row.ti; OpenPicker(function(item) C:TrigAddLeaf(item, ti) end) end)
    row:Hide()
    C._trig.rows[i] = row
  end

  local addC = flatButton(f, 140, 24, COLOR.purple, "+ Add Condition", 12)
  addC:SetPoint("BOTTOMLEFT", 16, 44)
  addC:SetScript("OnClick", function() OpenPicker(function(item) C:TrigAddLeaf(item, nil) end) end)
  local addG = flatButton(f, 120, 24, COLOR.heroic, "+ Add Group", 12)
  addG:SetPoint("LEFT", addC, "RIGHT", 8, 0)
  addG:SetScript("OnClick", function() C:TrigAddGroup() end)

  local ah = newText(f, FONT.body, 11, MUTE, "CENTER"); ah:SetWidth(W - 32); ah:SetPoint("BOTTOM", 0, 14)
  ah:SetText("No conditions = shows on its own state · click a state or logic label to change it")

  f:SetScript("OnShow", function() C:TrigRender() end)
  tinsert(UISpecialFrames, "GloomsAurasTrigger")
  f:Hide()
  C._trig.frame = f; RegisterSubWindow(f)
  return f
end

function C:OpenTriggerEditor(id)
  if not id then return end
  C._trig.editID = id
  C._trig.offset = 0
  if not C._trig.frame then
    local ok, err = pcall(function() C:BuildTriggerEditor() end)
    if not ok then GA.msg("|cffff5555trigger editor failed to build|r: " .. tostring(err)); return end
  end
  CloseSubWindows(C._trig.frame)
  DockRight(C._trig.frame)
  C._trig.frame:Show(); C._trig.frame:Raise()
  C:TrigRender()
end

-- --------------------------------------------------------------------------
-- Build the Auras tab: LEFT RAIL | editor pane.
-- Layout rework 2026-07-25. The tab used to be a 620-wide column floated in the
-- middle of the container with ~120px of dead margin each side — a leftover of the
-- old standalone window, and the reason the owner called the whole layout wrong.
-- It now owns the full container the way Bars and Overlays do: a flush-left rail
-- (tab header · profile · the aura tree · the buttons that act on the selection)
-- beside an editor pane that fills everything to the right.
--
-- Container content is PINNED at 860×626 minimum (CONTRACTS §2), so these are
-- deterministic. The pane anchors stretch to the right/bottom edges, so if the
-- shell ever GROWS, the extra width lands in the editor pane and nothing re-flows.
-- The Figma mocks these were once pixel-matched to are retired (the owner,
-- 2026-07-25: "the mocks no longer matter and are now hopelessly out of date...
-- I'd prefer the suite be consistent with itself"), so the numbers below come
-- from GB's and Overlays' rails, not from a mock.
-- --------------------------------------------------------------------------
local CONTENT_W = 860                     -- the PINNED content width (CONTRACTS §2 minimum)
local CONTENT_TOP = -12                   -- top margin inside the container
local RAIL_W = 240                        -- left rail — Overlays' width (it also carries a list)
local RAIL_X = 14                         -- rail content inset: ALL FOUR TABS use 14. The owner
                                          -- compares tabs by tabbing between them and caught a
                                          -- 2px difference — do not "improve" this one value.
local LIST_W = RAIL_W - RAIL_X * 2        -- 212 — rail content width (list rows + buttons)
local LIST_TOP = -190                     -- tree top: below the header (48) + profile block + divider
local EDITOR_X = RAIL_W + 30              -- editor content x (30px right of the rail divider)
local EDITOR_W = CONTENT_W - EDITOR_X - 30 -- 560 — fills the pane; the old 360 column is retired
local FOOTER_H = 52                       -- footer strip (GB's height; was 86 when it held Profile)
local PANE_H = 626 + CONTENT_TOP - FOOTER_H  -- 562: editor pane height
-- Two-column geometry inside the editor pane. Paired controls (Blend|Strata,
-- Outline|Anchor, the Load Conditions toggles) sit one per column instead of
-- crowding the left half — which is how the pane fills without dead space.
local COL_W = math.floor((EDITOR_W - 20) / 2)   -- 270
local COL2_X = COL_W + 20                       -- second column x

-- The player's specs, for the Load Conditions spec multi-select. (It lived inside
-- the Visibility drawer that the group pane retired; the inline Load Conditions
-- block — the drawer's replacement, now built for BOTH auras and groups — is its
-- only caller, so it moved out here rather than dying with the drawer.)
local function PlayerSpecs()
  local out = {}
  local n = (GetNumSpecializations and GetNumSpecializations()) or 0
  for i = 1, n do
    local id, name, _, icon = GetSpecializationInfo(i)
    if id then out[#out + 1] = { id = id, name = name, icon = icon } end
  end
  return out
end

-- --------------------------------------------------------------------------
-- Profiles (Phase 3B): named, switchable configs with a per-character default.
-- A docked drawer (opened from the bottom-strip "Profile:" button) lists every
-- profile — click one to switch — plus New / Copy / Rename / Delete. The switch
-- itself lives in Core (GA:SwitchProfile repoints GA.db); the panel is refreshed
-- via C:OnProfileSwitched, called back from Core after any repoint.
-- --------------------------------------------------------------------------
-- State + UI hang on the C table (not module-level locals) — the file chunk is
-- near Lua's 200-locals-per-function cap, so new module locals would overflow it.
C._prof = {}

-- The skinned yes/no confirm is LibGloomSkin's shared widget as of MINOR 3
-- (Phase E) — the same modal GB and Overlays use for their deletes.
function C:OpenConfirm(bodyText, onYes)
  UI.confirm(bodyText, onYes)
end

function C:RefreshProfileList()
  local pr = C._prof
  if pr.block then pr.block:refresh() end
end

-- THE PROFILE DRAWER IS GONE (2026-07-25, the owner: "we've got to get rid of the
-- drawer"). The shared profileBlock (LibGloomSkin MINOR 3) now sits permanently at
-- the TOP OF THE LEFT RAIL, exactly where GB and Overlays put theirs — so the rail
-- reads down the real hierarchy: profile → groups → auras. Same control, same
-- plumbing as before; only its host changed (was a docked, draggable sub-window
-- opened from a footer "Profile: <name>" button, both now deleted).
function C:BuildProfileBlock(rail, X, W, y)
  local pr = C._prof
  pr.block = UI.profileBlock(rail, W, {
    noun   = "profile",
    names  = function() return GA:ProfileNames() end,
    active = function() return GA:ActiveProfileName() or "?" end,
    switch = function(v) if v ~= GA:ActiveProfileName() then GA:SwitchProfile(v) end end,
    create = function(name)
      local ok, why = GA:CreateProfile(name)
      if ok then return true end
      return false, (why == "exists") and "A profile with that name already exists." or "Enter a profile name."
    end,
    copy = function(name)
      local ok, why = GA:CopyProfile(name)
      if ok then return true end
      return false, (why == "exists") and "A profile with that name already exists." or "Enter a profile name."
    end,
    rename = function(name)
      local ok, why = GA:RenameActiveProfile(name)
      if ok then return true end
      return false, (why == "exists") and "A profile with that name already exists." or "Enter a profile name."
    end,
    delete = function()
      if #GA:ProfileNames() <= 1 then return false, "Can't delete your only profile." end
      local active = GA:ActiveProfileName()
      if not GA:DeleteProfile(active) then return false, "" end
      GA.msg(("deleted profile |cffffffff%s|r."):format(active))
      return true
    end,
    -- Core calls C:OnProfileSwitched after any repoint, which rebuilds the pane
    -- and refreshes this block — no extra work needed here.
    tips = {
      dropdown = "The active profile. Each character defaults to its own.",
      new      = "Creates a profile and switches to it.",
      copy     = "Duplicates this profile — every aura and group — and switches to the copy.",
      rename   = "Renames this profile. Characters using it follow the new name.",
      delete   = "Deletes this profile (you'll be asked to confirm). Your only profile can't be deleted.",
    },
  })
  pr.block.frame:SetPoint("TOPLEFT", X, y)
  return pr.block
end

-- Called by Core (RefreshForProfile) after GA.db is repointed. Rebuilds the left
-- pane + editor for the new profile and re-shows its auras (while the panel is open).
function C:OnProfileSwitched()
  if not container then return end
  listOffset = 0
  selectedID = nil
  if container:IsVisible() and GA.Displays then
    GA.Displays.forced = true
    GA.Displays:SetInteractive(true)
  end
  C.groupSel = nil    -- the old profile's groups are gone
  C:SelectInitial()   -- first aura of the new profile; refreshes list + editor + empty state
  if self._hideCDM then self._hideCDM:Set(GA.db and GA.db.hideBlizzardCDM) end
  C:RefreshProfileList()   -- the rail block re-reads the active profile name
end

-- --------------------------------------------------------------------------
-- Text editor drawer: the aura's on-screen text overlay (show · content · size ·
-- outline · anchor · color · offset). Edits the SELECTED aura's cfg.text, applied
-- live via ReapplySelected → Displays:ApplyConfig. Docks like the other editors.
-- (Font picker comes next.)
-- --------------------------------------------------------------------------
local TE_ANCHOR = { { "BOTTOM", "Below" }, { "TOP", "Above" }, { "CENTER", "On aura" }, { "LEFT", "Left" }, { "RIGHT", "Right" } }
local TE_OUTLINE = { { "NONE", "None" }, { "OUTLINE", "Outline" }, { "THICKOUTLINE", "Thick" } }

local function TE_Text()
  local c = Cfg(); if not c then return nil end
  if not c.text then c.text = { show = (c.showLabel ~= false) } end   -- seed from legacy showLabel
  return c.text
end


-- Font picker: bundled fonts (GeneralSans / Khand) + LSM "font" media, each row
-- previewed in its own typeface. Opened from the Text drawer (which stays open).
local FONT_ROWS = 12
local fontPickerFrame, fontPickerOnPick, fontData, fontOffset, fontCurrent
local fontRows = {}

local function BuildFontData()
  local out = { { name = "Default", path = nil } }
  if GA.FONT then
    out[#out + 1] = { name = "GeneralSans", path = GA.FONT.body }
    out[#out + 1] = { name = "GeneralSans Medium", path = GA.FONT.bodyM }
    out[#out + 1] = { name = "GeneralSans Semibold", path = GA.FONT.label }
    out[#out + 1] = { name = "Khand Medium", path = GA.FONT.head }
    out[#out + 1] = { name = "Khand SemiBold", path = GA.FONT.title }
  end
  if LSM and LSM.HashTable then
    local t = LSM:HashTable("font")
    if t then
      local names = {}
      for n in pairs(t) do names[#names + 1] = n end
      table.sort(names, function(a, b) return a:lower() < b:lower() end)
      for _, n in ipairs(names) do out[#out + 1] = { name = n, path = t[n] } end
    end
  end
  return out
end

local function fontNameFor(path)
  if not path then return "Default" end
  for _, it in ipairs(BuildFontData()) do
    if it.path and tostring(it.path) == tostring(path) then return it.name end
  end
  return "Custom"
end

local function RefreshFontList()
  local n = #fontData
  local maxOff = math.max(0, n - FONT_ROWS)
  if fontOffset > maxOff then fontOffset = maxOff end
  if fontOffset < 0 then fontOffset = 0 end
  for i = 1, FONT_ROWS do
    local row, item = fontRows[i], fontData[i + fontOffset]
    if item then
      row.item = item
      setFont(row.text, item.path or (GA.FONT and GA.FONT.body) or DEFAULT_FONT, 14)
      row.text:SetText(item.name)
      local isCur = (item.path == nil and fontCurrent == nil)
                 or (item.path ~= nil and tostring(item.path) == tostring(fontCurrent))
      row.sel:SetShown(isCur)
      row:Show()
    else
      row.item = nil; row:Hide()
    end
  end
end

local function BuildFontPicker()
  local W, H = 300, 56 + FONT_ROWS * 24 + 24
  local f = CreateFrame("Frame", "GloomsAurasFontPicker", UIParent)
  f:SetSize(W, H); f:SetPoint("CENTER"); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:EnableMouse(true); f:EnableMouseWheel(true)
  skinPlate(f)
  local title = newText(f, FONT.title, 18, COLOR.purple, "CENTER"); title:SetPoint("TOP", 0, -12); title:SetText("Choose a font")
  local close = flatButton(f, 22, 20, COLOR.heroic, "X", 12); close:SetPoint("TOPRIGHT", -8, -8); close:SetScript("OnClick", function() f:Hide() end)
  f:SetMovable(true); f:SetClampedToScreen(true)
  local tb = CreateFrame("Frame", nil, f); tb:SetPoint("TOPLEFT", 2, -2); tb:SetPoint("TOPRIGHT", -34, -2)
  tb:SetHeight(28); tb:EnableMouse(true); tb:RegisterForDrag("LeftButton")
  tb:SetScript("OnDragStart", function() if f:IsMovable() then f:StartMoving() end end)
  tb:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
  for i = 1, FONT_ROWS do
    local row = CreateFrame("Button", nil, f); row:SetSize(W - 28, 22); row:SetPoint("TOPLEFT", 14, -40 - (i - 1) * 24)
    local sel = row:CreateTexture(nil, "BACKGROUND"); sel:SetAllPoints(); sel:SetColorTexture(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b, 0.28); sel:Hide(); row.sel = sel
    local hl = row:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.10)
    local text = row:CreateFontString(nil, "OVERLAY"); text:SetPoint("LEFT", 8, 0); text:SetPoint("RIGHT", -8, 0); text:SetJustifyH("LEFT"); text:SetTextColor(TEXT.r, TEXT.g, TEXT.b); row.text = text
    row:SetScript("OnClick", function(self)
      if not self.item then return end
      fontCurrent = self.item.path
      if fontPickerOnPick then fontPickerOnPick(self.item.path) end
      RefreshFontList()
    end)
    fontRows[i] = row
  end
  local footer = newText(f, FONT.body, 11, MUTE, "CENTER"); footer:SetPoint("BOTTOM", 0, 8); footer:SetText("mouse-wheel to scroll · click to apply")
  f:SetScript("OnMouseWheel", function(_, d) fontOffset = fontOffset - d; RefreshFontList() end)
  tinsert(UISpecialFrames, "GloomsAurasFontPicker")
  f:Hide()
  fontPickerFrame = f; RegisterSubWindow(f)
  return f
end

local function OpenFontPicker(onPick, current)
  fontPickerOnPick = onPick; fontCurrent = current
  if not fontPickerFrame then
    local ok, err = pcall(BuildFontPicker)
    if not ok then GA.msg("|cffff5555font picker failed to build|r: " .. tostring(err)); return end
  end
  fontData = BuildFontData(); fontOffset = 0
  CloseSubWindows(fontPickerFrame)
  fontPickerFrame:Show(); fontPickerFrame:Raise()
  RefreshFontList()
end



-- ---------------------------------------------------------------------------
-- Opening the tab. The LANDING SPLASH IS RETIRED (2026-07-25, the owner: "the splash
-- page is going to have to go away") — with it went `ga_logo_full.png`, the three
-- "Add ‹type› Aura" buttons, "View All Auras" and the landing/editor mode switch.
-- The tab now opens straight into the editor on the last-edited aura (or the first
-- one), and creating an aura happens at "+ New Aura" in the left pane. The only
-- special state left is "this profile has no auras yet" — see C:UpdateEmptyState.
-- These live on the C table (methods, not chunk locals) to stay under the Lua caps.
-- ---------------------------------------------------------------------------
function C:SelectInitial()
  local db = DB()
  local keep = (selectedID and db and db[selectedID]) and selectedID or DisplayList()[1]
  C.groupSel = nil
  RefreshList()
  SetSelected(keep)      -- nil is fine: the empty state takes over
  C:AccordionLayout()    -- recompute the scroll extent + show the scrollbar if it overflows
end

-- With no auras in the profile there is nothing to edit, so the accordion would sit
-- there fully disabled. Swap it for one line telling the owner what to click.
function C:UpdateEmptyState()
  -- A group with no auras in it still has settings to show, so a selected group
  -- keeps the pane alive even when the profile holds no auras at all.
  local empty = (DisplayList()[1] == nil) and not C.groupSel
  if C._empty then C._empty:SetShown(empty) end
  if C._editor then C._editor:SetShown(not empty) end
  if empty and C._editorTrack then C._editorTrack:Hide(); C._editorThumb:Hide() end
end

-- Create a blank aura of the chosen type and open it in the editor. Icon + Texture are
-- both texture-kind displays (they differ only in which editor sections lead); Bar is a
-- StatusBar display. Spells/sources are added later, inside the editor.
function C:CreateAura(uiType)
  local db = DB(); if not db then return end
  local id = NewDisplayID()
  if uiType == "bar" then
    db[id] = {
      kind = "bar", uiType = "bar", label = "New Bar Aura", enabled = true,
      width = 220, height = 24, point = { "CENTER", 0, -120 }, alpha = 1, showLabel = false,
      bar = { mode = "aura_dur" },
    }
  else
    db[id] = {
      uiType = uiType, label = (uiType == "texture") and "New Texture Aura" or "New Icon Aura",
      enabled = true, width = 64, height = 64, point = { "CENTER", 0, 120 }, alpha = 1,
      showLabel = false, texture = MEDIA .. "Textures\\Circle_Smooth",   -- neutral placeholder
    }
  end
  if GA.CDM then GA.CDM:Discover() end
  RefreshList()
  SetSelected(id)          -- also clears the empty state via C:UpdateEmptyState
  C:AccordionLayout()
end

-- The type menu behind "+ New Aura" (opens upward from the button, same shape as the
-- group-assign menu). Replaces the splash's three "Add ‹type› Aura" buttons.
function C:OpenNewAuraMenu(anchor)
  local menu = C._newMenu
  if menu and menu:IsShown() then menu:Hide(); return end
  if not menu then
    menu = CreateFrame("Frame", nil, container); C._newMenu = menu
    menu:SetFrameStrata("FULLSCREEN_DIALOG"); skinPlate(menu); addEdges(menu, COLOR.rim, 1)
    menu._rows = {}
  end
  local items = { { "icon", "Icon Aura" }, { "texture", "Texture Aura" }, { "bar", "Bar Aura" } }
  local W = anchor:GetWidth()
  menu:SetSize(W, #items * 24 + 8)
  menu:ClearAllPoints(); menu:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 4)
  for i, it in ipairs(items) do
    local r = menu._rows[i]
    if not r then r = flatButton(menu, W - 8, 20, COLOR.heroic, "", 11); r:SetBase(0.15); menu._rows[i] = r end
    r:SetText(it[2]); r:ClearAllPoints(); r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 24); r:Show()
    local uiType = it[1]
    r:SetScript("OnClick", function() menu:Hide(); C:CreateAura(uiType) end)
  end
  menu:Show()
end

-- ===========================================================================
-- ACCORDION EDITOR (redesign). The right pane is the aura NAME field followed by a
-- one-open-at-a-time accordion of collapsible sections. Each section = an orange
-- caret + Khand-uppercase header (click to expand) + a content frame; expanding one
-- collapses the others and the stack reflows. Built as C-methods (own upvalue budgets)
-- so Build() stays under Lua 5.1's 60-upvalue cap.  [Slice 2: Appearance is inline;
-- the other sections open their existing drawers for now — inlined in Slice 3.]
-- ===========================================================================
local ACC_HDR_H, ACC_GAP = 20, 10

-- Add a section under the name field. builder(content) populates it; height = its
-- fixed content height. Sections live on C._acc.sections in insertion order.
function C:AccordionAddSection(key, title, height, builder)
  local editor = C._acc.editor
  local hdr = CreateFrame("Button", nil, editor); hdr:SetSize(EDITOR_W, ACC_HDR_H)
  -- Caret = the SUITE's shared art, size and colour (the owner, 2026-07-25: same
  -- glyph, same size, same colour as the other modules). GB's accordion is the
  -- reference: UI.CARET at 9×9, explicitly tinted orange, label 11px to its right.
  -- GA used its own Media/triangle.png at 8×9 with the colour baked into the file.
  local caret = hdr:CreateTexture(nil, "OVERLAY"); caret:SetSize(9, 9); caret:SetPoint("LEFT", 2, 0)
  caret:SetTexture(UI.CARET); caret:SetVertexColor(COLOR.orange.r, COLOR.orange.g, COLOR.orange.b)
  local lbl = newText(hdr, FONT.head, 16, COLOR.purple, "LEFT")   -- Khand Medium 16, purple
  lbl:SetPoint("LEFT", caret, "RIGHT", 11, 0); lbl:SetText((title or ""):upper())
  local content = CreateFrame("Frame", nil, editor); content:SetSize(EDITOR_W, height); content:Hide()
  local s = { key = key, header = hdr, caret = caret, content = content, height = height, expanded = false }
  hdr:SetScript("OnClick", function() C:AccordionToggle(key) end)
  if builder then builder(content) end
  C._acc.sections[#C._acc.sections + 1] = s
  return s
end

-- Click a header: toggle it, collapse the rest (one open at a time), reflow.
function C:AccordionToggle(key)
  local secs = C._acc.sections
  local wasOpen
  for _, s in ipairs(secs) do if s.key == key then wasOpen = s.expanded end end
  for _, s in ipairs(secs) do s.expanded = (s.key == key) and (not wasOpen) or false end
  C:AccordionLayout()
end

function C:AccordionOpen(key)   -- force exactly one section open
  for _, s in ipairs(C._acc.sections) do s.expanded = (s.key == key) end
  C:AccordionLayout()
end

-- Reflow: stack headers top-to-bottom; an expanded section inserts its content.
function C:AccordionLayout()
  local y = C._acc.top
  for _, s in ipairs(C._acc.sections) do
    s.header:ClearAllPoints(); s.header:SetPoint("TOPLEFT", 0, y)
    s.caret:SetRotation(s.expanded and CARET_DOWN or 0)
    y = y - ACC_HDR_H
    if s.expanded then
      s.content:ClearAllPoints(); s.content:SetPoint("TOPLEFT", 0, y - 13); s.content:Show()
      y = y - 13 - s.height
    else
      s.content:Hide()
    end
    y = y - ACC_GAP
  end
  C:LayoutEditorScroll(-y + 12)   -- size the scroll child to the content + update the scrollbar
end

-- Update a section's content height (used by the Trigger section, which grows/shrinks
-- with its conditions) and reflow.
function C:AccordionSetHeight(key, h)
  for _, s in ipairs(C._acc.sections) do
    if s.key == key then s.height = h; s.content:SetHeight(h); break end
  end
  C:AccordionLayout()
end

-- Editor scroll. The accordion can exceed the pane height when a tall section (e.g. Aura
-- Load Conditions) is open, so the editor is a ScrollFrame; the scrollbar shows only on
-- overflow and lives in the right margin so it never covers content.
function C:SetEditorScroll(v)
  local maxS = C._editorMaxScroll or 0
  v = math.max(0, math.min(maxS, v or 0)); C._editorScroll = v
  if C._editor then C._editor:SetVerticalScroll(v) end
  local track, thumb = C._editorTrack, C._editorThumb
  if track and thumb and thumb:IsShown() then
    local range = PANE_H - thumb:GetHeight()
    local frac = (maxS > 0) and (v / maxS) or 0
    thumb:ClearAllPoints(); thumb:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, -range * frac)
  end
end

-- Size the scroll child to the laid-out content + (un)show the scrollbar. `total` = content height.
function C:LayoutEditorScroll(total)
  local child = C._editorChild; if not child then return end
  child:SetHeight(math.max(PANE_H, total))
  C._editorMaxScroll = math.max(0, total - PANE_H)
  local track, thumb = C._editorTrack, C._editorThumb
  if track and thumb then
    if C._editorMaxScroll <= 0 then track:Hide(); thumb:Hide()
    else track:Show(); thumb:Show(); thumb:SetHeight(math.max(24, PANE_H * PANE_H / total)) end
  end
  C:SetEditorScroll(C._editorScroll or 0)
end

-- The Appearance, Position & Size section — texture + recolor/desaturate + blend/strata
-- + alpha + width/height (aspect-linked) + X/Y. Reuses the shipped controls; laid out
-- to the mock's vertical rhythm (internal pixel polish is an iteration item).
function C:BuildAppearanceSection(ct)
  local H = COLOR.heroic

  -- Texture field (heroic-8% fill, placeholder when empty) + Choose pill. The field
  -- takes the pane's width less the pill — texture paths are long, and this is the
  -- control that most wanted the room the wider pane freed up.
  local tfield = CreateFrame("EditBox", nil, ct); tfield:SetSize(EDITOR_W - 90, 28); tfield:SetPoint("TOPLEFT", 0, 0)
  tfield:SetAutoFocus(false); setFont(tfield, FONT.body, 11); tfield:SetTextColor(1, 1, 1); tfield:SetTextInsets(10, 10, 0, 0)
  local tbg = tfield:CreateTexture(nil, "BACKGROUND"); tbg:SetAllPoints(); tbg:SetColorTexture(H.r, H.g, H.b, 0.08)
  local tph = newText(tfield, FONT.body, 11, TEXT, "LEFT"); tph:SetPoint("LEFT", 10, 0); tph:SetAlpha(0.3)
  tph:SetText("Leave blank to adopt the first trigger's icon")
  local function tUpdPH() tph:SetShown((tfield:GetText() or "") == "") end
  tfield:SetScript("OnTextChanged", tUpdPH)
  tfield:SetScript("OnEnterPressed", function(self)
    local c = Cfg(); if c then local t = self:GetText(); if t == "" then t = nil end; c.texture = t; ReapplySelected(); RefreshList() end
    self:ClearFocus()
  end)
  tfield:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  rows[#rows + 1] = {
    refresh = function() local c = Cfg(); local v = c and c.texture; tfield:SetText(v ~= nil and tostring(v) or ""); tfield:SetCursorPosition(0); tUpdPH() end,
    setEnabled = function(_, on) tfield:SetEnabled(on) end }

  local choose = flatButton(ct, 80, 28, H, "Choose", 11); choose:SetBase(0.5); choose:SetPoint("TOPLEFT", EDITOR_W - 80, 0)
  setFont(choose.text, FONT.body, 11)
  choose:SetScript("OnClick", function()
    local c = Cfg(); if not c then return end
    OpenTexturePicker(function(tex) c.texture = tex; ReapplySelected(); C:RefreshCurrent(); RefreshList() end, c.texture)
  end)
  rows[#rows + 1] = { refresh = function() end, setEnabled = function(_, on) choose:SetEnabled(on) end }

  -- Recolor (check + swatch) + Desaturate (check).
  rows[#rows + 1] = MakeColor(ct, 0, -48,
    function() local c = Cfg(); return c and c.color end,
    function(v) local c = Cfg(); if c then c.color = v end end, "Recolor")
  local desat = flatCheck(ct, "Desaturate"); desat:SetPoint("TOPLEFT", COL2_X, -48)
  desat:SetScript("OnClick", function()
    local c = Cfg(); if not c then return end
    desat:Set(not desat:Get()); c.desaturate = desat:Get() or nil; ReapplySelected()
  end)
  rows[#rows + 1] = { refresh = function() local c = Cfg(); desat:Set(c and c.desaturate) end,
                      setEnabled = function(_, on) desat:SetEnabled(on) end }

  -- Blend / Strata pills.
  rows[#rows + 1] = MakeDropdown(ct, 0, -88, COL_W, "Blend Mode:", BLEND_MODES,
    function() local c = Cfg(); return (c and c.blend) or "BLEND" end,
    function(v) local c = Cfg(); if c then c.blend = (v ~= "BLEND") and v or nil end end)
  rows[#rows + 1] = MakeDropdown(ct, COL2_X, -88, COL_W, "Strata:", STRATA_MODES,
    function() local c = Cfg(); return (c and c.strata) or "HIGH" end,
    function(v) local c = Cfg(); if c then c.strata = (v ~= "HIGH") and v or nil end end)

  -- Alpha.
  rows[#rows + 1] = MakeSlider(ct, -136, "Alpha %", 0, 100, 5,
    function() local c = Cfg(); return c and ((c.alpha or 1) * 100) end,
    function(v) local c = Cfg(); if c then c.alpha = v / 100 end end)

  -- Width / Height (aspect-linked) + a link toggle sitting between the two rows.
  local widthRow, heightRow
  local function clampDim(n) return math.max(8, math.min(8192, math.floor(n + 0.5))) end
  widthRow = MakeSlider(ct, -189, "Width", 8, 8192, 2,
    function() local c = Cfg(); return c and (c.width or c.size) end,
    function(v) local c = Cfg(); if not c then return end c.width = v; if c.lockAspect then c.height = clampDim(v / (c.aspect or 1)); if heightRow then heightRow:refresh() end end end)
  rows[#rows + 1] = widthRow
  heightRow = MakeSlider(ct, -222, "Height", 8, 8192, 2,
    function() local c = Cfg(); return c and (c.height or c.size) end,
    function(v) local c = Cfg(); if not c then return end c.height = v; if c.lockAspect then c.width = clampDim(v * (c.aspect or 1)); if widthRow then widthRow:refresh() end end end)
  rows[#rows + 1] = heightRow

  local aspectBtn = CreateFrame("Button", nil, ct); aspectBtn:SetSize(16, 16); aspectBtn:SetPoint("TOPLEFT", 48, -199)
  local alock = aspectBtn:CreateTexture(nil, "ARTWORK"); alock:SetAllPoints()
  local LOCK_ON, LOCK_OFF = MEDIA .. "lock_locked.png", MEDIA .. "lock_unlocked.png"
  local function alockRefresh() local c = Cfg(); alock:SetTexture((c and c.lockAspect) and LOCK_ON or LOCK_OFF); alock:SetVertexColor(1, 1, 1, 1) end
  aspectBtn:SetScript("OnClick", function()
    local c = Cfg(); if not c then return end
    local on = not c.lockAspect; c.lockAspect = on or nil
    if on then local w, h = (c.width or c.size or 64), (c.height or c.size or 64); c.aspect = (h > 0) and (w / h) or 1 end
    alockRefresh()
  end)
  rows[#rows + 1] = { refresh = alockRefresh, setEnabled = function(_, on) aspectBtn:SetEnabled(on); alock:SetDesaturated(not on) end }

  -- X / Y offset.
  rows[#rows + 1] = MakeSlider(ct, -255, "X Offset", -2000, 2000, 5,
    function() local c = Cfg(); return c and c.point and c.point[2] end,
    function(v) local c = Cfg(); if c then c.point = { "CENTER", v, (c.point and c.point[3]) or 0 } end end)
  rows[#rows + 1] = MakeSlider(ct, -288, "Y Offset", -2000, 2000, 5,
    function() local c = Cfg(); return c and c.point and c.point[3] end,
    function(v) local c = Cfg(); if c then c.point = { "CENTER", (c.point and c.point[2]) or 0, v } end end)
end

-- Build the editor: the icon-section accordion.
-- The big Khand-20 aura-NAME banner with "CLICK TO RENAME" is GONE (the owner,
-- 2026-07-25: "a waste of space and, more importantly, confusing and nonintuitive").
-- Renaming is now a rail action on the SELECTED aura — the Rename button in the left
-- pane (and double-clicking its row), through the suite's shared UI.nameDialog, which
-- is the same gesture GB's profile/preset blocks use. The accordion starts at the top.
function C:BuildEditor(editor)
  C._acc = { editor = editor, sections = {}, top = -42 }   -- top = first header y (below the GROUP row)

  C:BuildAuraGroupRow(editor)   -- "GROUP  [ Group: <name> ]" — this aura's place in the hierarchy

  -- Icon-aura sections. Appearance is inline; the rest bridge to their drawers for now.
  C:AccordionAddSection("trigger", "Aura Trigger(s)", 120, function(ct) C:BuildTriggerSection(ct) end)
  C:AccordionAddSection("appearance", "Appearance, Position & Size", 310, function(ct) C:BuildAppearanceSection(ct) end)
  C:AccordionAddSection("text", "Text", 285, function(ct) C:BuildTextSection(ct) end)
  C:AccordionAddSection("effects", "Effects & Motion", 78, function(ct) C:BuildEffectsSection(ct) end)
  C:AccordionAddSection("sounds", "Sounds", 72, function(ct) C:BuildSoundSection(ct) end)
  -- Load Conditions sizes itself: its height depends on how many SPECS the class has,
  -- which the 420 guess only happened to fit. The builder returns its real height.
  local loadH
  C:AccordionAddSection("load", "Aura Load Conditions", 420, function(ct) loadH = C:BuildLoadConditionsSection(ct) end)
  if loadH then C:AccordionSetHeight("load", loadH) end

  C:AccordionOpen("trigger")   -- an aura opens on its Trigger section
end

-- ===========================================================================
-- THE GROUP PANE — a group's own settings, in the SAME pane an aura's settings
-- use. Clicking a group's name in the rail selects it exactly the way clicking an
-- aura does, and this replaces the accordion.
--
-- This is what retired the ⚙ gear and its "Manage Group" drawer (the owner,
-- 2026-07-25: the old Group control "has always been extraordinarily confusing").
-- The confusion was structural, not cosmetic: a group's settings were split
-- between a green button in the left pane (assign) and a floating drawer behind a
-- gear (everything else), so nothing in the UI said that a profile holds groups
-- and a group holds auras. Now the rail IS the hierarchy — profile at the top,
-- groups with their auras nested under it — and both kinds of row open their
-- settings in the same place.
-- ===========================================================================
C._grows = {}   -- the group pane's own refresh list (auras use the shared `rows`)

local function GrpSel() local gid = C.groupSel; return gid and Groups() and Groups()[gid] end

function C:BuildGroupPane(parent)
  local pane = CreateFrame("Frame", nil, parent)
  pane:SetPoint("TOPLEFT", 0, -6); pane:SetWidth(EDITOR_W)
  pane:Hide(); C._gpane = pane

  local hdr = newText(pane, FONT.head, 12, MUTE, "LEFT")
  hdr:SetPoint("TOPLEFT", 0, -2); hdr:SetText("GROUP")
  local name = newText(pane, FONT.title, 20, COLOR.purple, "LEFT")
  name:SetPoint("TOPLEFT", 0, -20); name:SetWidth(EDITOR_W - 200); name:SetWordWrap(false)
  C._gpaneName = name

  -- Order (a group's place in the rail) — right-aligned on the name's row.
  local dn = flatButton(pane, 92, 22, COLOR.heroic, "Move Down", 11); dn:SetBase(0.2)
  dn:SetPoint("TOPRIGHT", 0, -20)
  dn:SetScript("OnClick", function() if C.groupSel then MoveGroup(C.groupSel, 1); RefreshList() end end)
  local up = flatButton(pane, 92, 22, COLOR.heroic, "Move Up", 11); up:SetBase(0.2)
  up:SetPoint("TOPRIGHT", dn, "TOPLEFT", -4, 0)
  up:SetScript("OnClick", function() if C.groupSel then MoveGroup(C.groupSel, -1); RefreshList() end end)

  local ren = flatButton(pane, 92, 22, COLOR.heroic, "Rename", 11); ren:SetBase(0.2)
  ren:SetPoint("TOPLEFT", 0, -52)
  ren:SetScript("OnClick", function()
    local g = GrpSel(); if not g then return end
    OpenNameDialog("Rename Group", g.name or "", function(nm)
      if not nm or nm:gsub("%s", "") == "" then return end
      g.name = nm; RefreshList(); C:RefreshGroupPane(); C:RefreshGroupButton()
    end)
  end)

  -- Delete CONFIRMS (CONTRACTS §4). Auras are never deleted with their group.
  local del = flatButton(pane, 110, 22, COLOR.red, "Delete Group", 11); del:SetBase(0.3)
  del:SetPoint("TOPLEFT", ren, "TOPRIGHT", 4, 0)
  del:SetScript("OnClick", function()
    local g, gid = GrpSel(), C.groupSel; if not g then return end
    C:OpenConfirm(("Delete the group \"%s\"?  Its auras aren't deleted — they move to Ungrouped."):format(g.name or "?"),
      function()
        local gone = DeleteGroup(gid)
        if gone then GA.msg(("deleted group |cffffffff%s|r — its auras moved to Ungrouped."):format(gone)) end
        C.groupSel = nil
        RefreshList(); C:SelectInitial()
        if GA.CDM then GA.CDM:UpdateVisibilityPoll(); GA.CDM:RefreshDisplays() end
      end)
  end)

  local div = pane:CreateTexture(nil, "ARTWORK"); div:SetColorTexture(COLOR.rim.r, COLOR.rim.g, COLOR.rim.b, COLOR.rim.a)
  div:SetPoint("TOPLEFT", 0, -86); div:SetPoint("TOPRIGHT", 0, -86); div:SetHeight(1)

  local lch = newText(pane, FONT.head, 16, COLOR.purple, "LEFT")
  lch:SetPoint("TOPLEFT", 0, -100); lch:SetText("LOAD THIS GROUP WHEN…")
  local lhint = newText(pane, FONT.body, 11, MUTE, "LEFT")
  lhint:SetPoint("TOPLEFT", 0, -122); lhint:SetWidth(EDITOR_W)
  lhint:SetText("These gate EVERY aura in the group, in front of each aura's own conditions.")

  -- The SAME load-conditions block the aura editor uses — pointed at the group.
  local lc = CreateFrame("Frame", nil, pane); lc:SetPoint("TOPLEFT", 0, -146); lc:SetWidth(EDITOR_W)
  local lcH = C:BuildLoadConditionsSection(lc, { sink = C._grows, target = GrpSel, noun = "group" })
  lc:SetHeight(lcH)
  pane:SetHeight(146 + lcH)
  C._gpaneH = 146 + lcH + 20
end

-- Select a GROUP — the mirror of SetSelected for auras.
function C:SelectGroup(gid)
  if not (gid and Groups() and Groups()[gid]) then return end
  C.groupSel = gid
  selectedID = nil
  if C._trig then C._trig.editID = nil end
  if GA.Displays then GA.Displays:SetSelectedDisplay(nil); GA.Displays:RefreshForced() end
  C:SyncRailButtons()
  C:UpdateEmptyState()   -- a group is editable even in a profile with no auras
  C:ShowGroupPane(true)
  C:RefreshGroupPane()
  RefreshList()
end

function C:RefreshGroupPane()
  local g = GrpSel(); if not g then return end
  if C._gpaneName then C._gpaneName:SetText(g.name or "Group") end
  for _, r in ipairs(C._grows) do r:refresh(); r:setEnabled(true) end
end

-- Swap the pane between the aura accordion and the group pane.
function C:ShowGroupPane(on)
  if C._gpane then C._gpane:SetShown(on) end
  if C._auraTop then C._auraTop:SetShown(not on) end
  for _, s in ipairs(C._acc and C._acc.sections or {}) do
    s.header:SetShown(not on)
    if on then s.content:Hide() end
  end
  if on then
    C:SetEditorScroll(0)
    C:LayoutEditorScroll(C._gpaneH or 520)
  else
    C:AccordionLayout()
  end
end

-- Left-pane button stack, restyled to the SUITE's button language (the owner,
-- 2026-07-25: "the buttons should match the button styling from the other addons.
-- GA predates them, and things evolved"). GB and Overlays both use 22px-tall,
-- Title Case, 11px GeneralSans-Medium (flatButton's own default — no setFont
-- override), heroic @0.2 for secondary actions and the ONE create action in
-- purple @0.35 ("+ New Overlay" is the reference). Delete keeps its red @0.3 —
-- the owner explicitly kept that. Was: 28px tall, ALL CAPS, semibold, heroic @0.5.
function C:BuildLeftButtons(listFrame)
  local H = COLOR.heroic
  local function mk(label, cc, base, w, x, yBot, onClick)
    local b = flatButton(listFrame, w, 22, cc, label, 11); b:SetBase(base)
    b:SetPoint("BOTTOMLEFT", x, yBot); b:SetScript("OnClick", onClick)
    return b
  end
  local half = math.floor((LIST_W - 4) / 2)
  local rest = LIST_W - half - 4

  -- The two CREATE actions sit together, both purple: this is where the hierarchy
  -- gets made. (The green "Group: <name>" button that used to live down here is
  -- gone — assigning an aura to a group is a property of the aura, so it moved to
  -- the top of the aura pane. The owner, 2026-07-25: that button "has always been
  -- extraordinarily confusing".)
  local newBtn = mk("+ New Aura", COLOR.purple, 0.35, half, 0, 62, nil)
  newBtn:SetScript("OnClick", function() C:OpenNewAuraMenu(newBtn) end)
  UI.attachTip(newBtn, "New aura", "Creates a blank aura in this profile and opens it for editing. Pick the kind: Icon, Texture or Bar.")

  local newGrp = mk("+ New Group", COLOR.purple, 0.35, rest, half + 4, 62, function()
    OpenNameDialog("New Group", "", function(nm)
      if not nm or nm:gsub("%s", "") == "" then return end
      local gid = CreateGroup(nm)
      if gid then RefreshList(); C:SelectGroup(gid) end
    end)
  end)
  UI.attachTip(newGrp, "New group", "Groups hold a set of auras that load together: one load rule and one on/off switch gate every aura inside. Click a group's name to edit it.")

  local ren = mk("Rename", H, 0.2, half, 0, 34, function() C:RenameSelected() end)
  UI.attachTip(ren, "Rename aura", "Renames the selected aura in this list. (The on-screen text an aura draws is a separate setting, under Text.)")
  C._btnRename = ren

  C._btnDupe = mk("Duplicate", H, 0.2, rest, half + 4, 34, function()
    if not (selectedID and DB() and DB()[selectedID]) then return end
    local copy = DeepCopy(DB()[selectedID]); copy.label = (copy.label or "Aura") .. " (copy)"
    local p = copy.point or { "CENTER", 0, 0 }; copy.point = { "CENTER", (p[2] or 0) + 24, (p[3] or 0) - 24 }
    local id = NewDisplayID(); DB()[id] = copy
    if GA.CDM then GA.CDM:Discover() end
    SetSelected(id)
  end)

  -- ★ Delete CONFIRMS. It used to delete on the click, with no way back and no undo —
  -- the owner caught it during the layout rework, 2026-07-25. The suite's rule
  -- (CONTRACTS §4) is that every destructive action goes through the shared
  -- UI.confirm modal, which has a Cancel and an ESC. This one predates that rule.
  C._btnDel = mk("Delete Aura", COLOR.red, 0.3, LIST_W, 0, 6, function()
    local c = Cfg(); if not (selectedID and c) then return end
    local gone, name = selectedID, c.label or "this aura"
    C:OpenConfirm(("Delete the aura \"%s\"?  This can't be undone."):format(name), function()
      if not (DB() and DB()[gone]) then return end
      DB()[gone] = nil
      if GA.Displays and GA.Displays.frames[gone] then GA.Displays.frames[gone]:Hide() end
      if GA.CDM then GA.CDM:Discover() end
      SetSelected(DisplayList()[1])
    end)
  end)

  C:SyncRailButtons()
end

-- Rename / Duplicate / Delete act on the selected AURA, so they grey out while a
-- GROUP is selected (a group's own Rename / Delete live in its pane, where its
-- other settings are). flatButton's OnDisable does the greying.
function C:SyncRailButtons()
  local on = (selectedID ~= nil)
  for _, b in ipairs({ C._btnRename, C._btnDupe, C._btnDel }) do
    if b then b:SetEnabled(on) end
  end
end

-- Rename the SELECTED aura through the suite's shared name dialog — the replacement
-- for the retired editor name banner. Renames cfg.label (the list name) ONLY; the
-- on-screen text an aura draws is cfg.text.str, a deliberately separate field.
function C:RenameSelected()
  local c = Cfg(); if not c then return end
  OpenNameDialog("Rename Aura", c.label or "", function(nm)
    if not nm or nm:gsub("%s", "") == "" then return end
    c.label = nm
    RefreshList(); ReapplySelected()
  end)
end

-- The aura's GROUP assignment — one row at the top of the aura pane, above the
-- accordion. It reads as what it is: a property of this aura ("which group is it
-- in?"), sitting with the aura's other properties. It replaces the green
-- "Group: <name>" button in the left pane, which read like a status label but was
-- actually an action, and was nowhere near the group it talked about.
function C:BuildAuraGroupRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetPoint("TOPLEFT", 0, -6); row:SetSize(EDITOR_W, 24)
  C._auraTop = row

  local lbl = newText(row, FONT.head, 12, MUTE, "LEFT")
  lbl:SetPoint("TOPLEFT", 0, -4); lbl:SetText("GROUP")

  local gb = flatButton(row, 220, 22, COLOR.heroic, "", 11); gb:SetBase(0.2)
  gb:SetPoint("TOPLEFT", 62, -1); gb.text:Hide()
  C._groupBtn, C._groupLabel = gb, twoWeightLabel(gb, 11)
  gb:SetScript("OnClick", function() C:OpenGroupAssignMenu(gb) end)
  UI.attachTip(gb, "Group", "Which group this aura belongs to. A group's load rule and on/off switch gate every aura inside it — click the group's name in the list to edit those.")

  rows[#rows + 1] = {
    refresh = function() C:RefreshGroupButton() end,
    setEnabled = function(_, on) gb:SetEnabled(on) end,
  }
end

-- Group button label = the selected aura's group (Ungrouped if none). Hidden with no selection.
function C:RefreshGroupButton()
  if not C._groupLabel then return end
  local c = Cfg()
  local name = (c and c.group and Groups() and Groups()[c.group] and Groups()[c.group].name) or "Ungrouped"
  C._groupLabel:Set("Group:", name)
  if C._groupBtn then C._groupBtn:SetShown(c ~= nil) end
end

-- Pop-up (opens below the Group button) to assign the selected aura to a group:
-- Ungrouped + each group + "+ New Group…".
function C:OpenGroupAssignMenu(anchor)
  local c = Cfg(); if not c then return end
  local menu = C._grpMenu
  if menu and menu:IsShown() then menu:Hide(); return end
  if not menu then
    menu = CreateFrame("Frame", nil, container); C._grpMenu = menu
    menu:SetFrameStrata("FULLSCREEN_DIALOG"); skinPlate(menu); addEdges(menu, COLOR.rim, 1)
    menu._rows = {}
  end
  local items = { { nil, "Ungrouped" } }
  for _, gid in ipairs(GroupList()) do items[#items + 1] = { gid, Groups()[gid].name or "Group" } end
  items[#items + 1] = { "__new", "+ New Group…" }
  local W = anchor:GetWidth()
  menu:SetSize(W, #items * 24 + 8)
  menu:ClearAllPoints(); menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
  for _, r in ipairs(menu._rows) do r:Hide() end
  for i, it in ipairs(items) do
    local r = menu._rows[i]
    if not r then r = flatButton(menu, W - 8, 20, COLOR.heroic, "", 11); r:SetBase(0.15); menu._rows[i] = r end
    r:SetText(it[2]); r:ClearAllPoints(); r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 24); r:Show()
    local val = it[1]
    r:SetScript("OnClick", function()
      menu:Hide(); local cur = Cfg(); if not cur then return end
      if val == "__new" then
        OpenNameDialog("New Group", "", function(nm) local gid = CreateGroup(nm); if gid then cur.group = gid; RefreshList(); C:RefreshGroupButton() end end)
      else
        cur.group = val; RefreshList(); C:RefreshGroupButton()
      end
    end)
  end
  menu:Show()
end

-- ===========================================================================
-- Inline AURA TRIGGER(S) section (redesign). Match ALL/ANY/NONE segmented control +
-- a bordered box of condition rows + an "Add a Trigger" bar. Reuses the trigger engine
-- (C:TrigTree / TrigAddLeaf / TrigRemove / TrigCycleState); this is just the inline UI.
-- The box grows/shrinks with the conditions, so it drives C:AccordionSetHeight to reflow.
-- [Slice 3a-i: flat conditions. Nested TRIGGER GROUP rendering comes in 3a-ii.]
-- ===========================================================================
local TRIG_LOGICS = { { "AND", "ALL" }, { "OR", "ANY" }, { "NONE", "NONE" } }

-- The word drawn on the chip BETWEEN two conditions. Purely a label — it reports the
-- containing group's Match setting, it doesn't set it (the owner, 2026-07-25).
-- ★ NONE reads "NOR", not "AND NOT": NONE negates BOTH sides equally, while "AND NOT"
-- reads as "the first thing and not the second" (the owner spotted exactly this).
-- Per-CONDITION negation never needs a chip — the state pill already carries it
-- ("INACTIVE on You", "ON COOLDOWN", "CHARGES NOT MAX").
local TRIG_JOIN = { AND = "AND", OR = "OR", NONE = "NOR" }

-- One condition CARD: right-aligned [name] [icon] = [STATE pill] [X] on its own filled
-- block, plus the operator chip that sits above it (every card but the first shows one).
-- Works at the top level (ci=nil, purple) and inside a group (ci set, orange).
-- Shift-clicking a TOP-LEVEL card selects it (→ "Add a TRIGGER GROUP" groups them).
-- ★ THE NESTING RULE (the owner's second mock, 2026-07-25). Every operand — a plain
-- condition card OR a whole group box — is inset the SAME 52px from its container's
-- left edge and 14 from its right. That gutter is what the operator lives in: a
-- bracket ties the two operands it joins, with the AND/OR/NOR chip sitting on it.
-- So a group aligns exactly with the sibling cards it sits among, and its own cards
-- inset again inside it — the indentation IS the hierarchy. The first mock had the
-- chips floating beside full-width rows, which is what read as unclear.
local TRIG_INSET_L, TRIG_INSET_R = 52, 14
local TRIG_ROW_H, TRIG_ROW_GAP = 40, 8
local TRIG_ROW_PITCH = TRIG_ROW_H + TRIG_ROW_GAP
local TRIG_CHIP_W, TRIG_CHIP_H = 30, 16
local TRIG_LINE_X = 24       -- the bracket's vertical, in the gutter left of the operands
-- ★ THE RULE (the owner, 2026-07-25): the bracket's vertical must show a stub ABOVE
-- and BELOW the label roughly as tall as the label itself — that is what makes it read
-- as connective tissue rather than a shape stuck to the chip. Stated as a relationship,
-- not a magic number, so it stays true if the chip is ever resized:
--   stub = (vertical − chip) / 2  and  vertical = 2·bite + gap,  so  stub = chip
--   ⇒ bite = (3·chip − gap) / 2 = 20, which lands the arms on each card's centre line.
local TRIG_BITE = (3 * TRIG_CHIP_H - TRIG_ROW_GAP) / 2

function C:MakeTrigRow(parent, inGroup)
  local H = COLOR.heroic
  local A = inGroup and COLOR.orange or H          -- the context's accent
  local row = CreateFrame("Button", nil, parent); row:SetHeight(TRIG_ROW_H); row:RegisterForClicks("LeftButtonUp")
  -- The card itself. Cards replaced bare rows so each condition reads as one object
  -- and the operator chips have something to sit between.
  local card = row:CreateTexture(nil, "BACKGROUND")
  card:SetAllPoints(); card:SetColorTexture(A.r, A.g, A.b, inGroup and 0.14 or 0.22)
  local selTex = row:CreateTexture(nil, "BORDER"); selTex:SetAllPoints()
  selTex:SetColorTexture(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b, 0.3); selTex:Hide(); row.selTex = selTex

  local x = flatButton(row, 20, 20, A, "X", 11); x:SetBase(inGroup and 1 or 0.5)
  x:SetPoint("RIGHT", -12, 0); row.x = x
  local pill = flatButton(row, 190, 24, A, "", 11); pill:SetBase(inGroup and 1 or 0.85)
  pill:SetPoint("RIGHT", x, "LEFT", -10, 0); pill.text:Hide()
  row.pillLbl = twoWeightLabel(pill, 11, nil, true); row.pill = pill
  local eq = newText(row, FONT.body, 11, TEXT, "LEFT"); eq:SetPoint("RIGHT", pill, "LEFT", -6, 0); eq:SetText("="); row.eq = eq
  local icon = row:CreateTexture(nil, "ARTWORK"); icon:SetSize(20, 19); icon:SetPoint("RIGHT", eq, "LEFT", -6, 0)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92); row.icon = icon
  local name = newText(row, FONT.body, 12, TEXT, "RIGHT"); name:SetPoint("RIGHT", icon, "LEFT", -8, 0); name:SetWordWrap(false); row.name = name

  x:SetScript("OnClick", function() C:TrigRemove(row._ti, row._ci) end)
  pill:SetScript("OnClick", function() C:TrigCycleState(row._ti, row._ci) end)
  row:SetScript("OnClick", function()
    if row._ci or not row._leaf then return end        -- only top-level leaves are groupable
    if IsShiftKeyDown() then
      local sel = C._trigUI.selected
      sel[row._leaf] = (not sel[row._leaf]) or nil
      C:TrigInlineRender()
    end
  end)
  return row
end

-- One JOIN: the orange bracket tying two adjacent operands together, with the operator
-- chip sitting on its vertical. Lives in the gutter the operands are inset for, and is
-- owned by the CONTAINER (the trigger box, or a group box) — not by either operand —
-- because it belongs to both of them.
function C:MakeTrigJoin(parent)
  local O = COLOR.orange
  local function line()
    local t = parent:CreateTexture(nil, "OVERLAY"); t:SetColorTexture(O.r, O.g, O.b, 1); return t
  end
  local j = { v = line(), top = line(), bot = line() }
  local chip = CreateFrame("Frame", nil, parent); chip:SetSize(TRIG_CHIP_W, TRIG_CHIP_H)
  chip:SetFrameLevel((parent:GetFrameLevel() or 1) + 6)   -- sits ON the line it labels
  local cbg = chip:CreateTexture(nil, "ARTWORK"); cbg:SetAllPoints(); cbg:SetColorTexture(O.r, O.g, O.b, 1)
  chip.text = newText(chip, FONT.label, 11, { r = 1, g = 1, b = 1 }, "CENTER"); chip.text:SetPoint("CENTER")
  j.chip = chip
  return j
end

-- `aBottom` = distance from the container's top down to the bottom of the upper operand,
-- `bTop` = down to the top of the lower one. The arms bite TRIG_BITE into each so the
-- bracket visibly grips both, rather than floating in the gap between them.
function C:PlaceTrigJoin(j, aBottom, bTop, word)
  local y1, y2 = aBottom - TRIG_BITE, bTop + TRIG_BITE
  local armW = TRIG_INSET_L - TRIG_LINE_X
  j.v:ClearAllPoints();   j.v:SetPoint("TOPLEFT", TRIG_LINE_X, -y1);   j.v:SetSize(1, math.max(1, y2 - y1))
  j.top:ClearAllPoints(); j.top:SetPoint("TOPLEFT", TRIG_LINE_X, -y1); j.top:SetSize(armW, 1)
  j.bot:ClearAllPoints(); j.bot:SetPoint("TOPLEFT", TRIG_LINE_X, -y2); j.bot:SetSize(armW, 1)
  j.chip:ClearAllPoints()
  j.chip:SetPoint("CENTER", j.chip:GetParent(), "TOPLEFT", TRIG_LINE_X, -(y1 + y2) / 2)
  j.chip.text:SetText(word)
  j.v:Show(); j.top:Show(); j.bot:Show(); j.chip:Show()
end

function C:HideTrigJoin(j) j.v:Hide(); j.top:Hide(); j.bot:Hide(); j.chip:Hide() end


function C:FillTrigRow(row, ti, ci, leaf)
  row._ti, row._ci, row._leaf = ti, ci, leaf
  local ic = leaf.spellID and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(leaf.spellID)
  row.icon:SetTexture(ic or 134400)
  row.name:SetText(leaf.name or (leaf.spellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(leaf.spellID)) or "?")
  local main, suf = TrigPill(leaf.state, leaf.k)
  row.pillLbl:Set(main, suf)
  row.selTex:SetShown(ci == nil and C._trigUI.selected[leaf] and true or false)
end

-- A nested TRIGGER GROUP box (orange). Header: "Match: ALL/ANY/NONE" on the LEFT,
-- "TRIGGER GROUP N" on the RIGHT with "Add Trigger | Delete Group" links beneath it
-- (the owner's mock, 2026-07-25 — they replace the header X and the old bottom
-- "+ Add to Group" bar, so a group's two actions live with its name).
-- Its own row pool lives on g._rows.
local TRIG_GHDR_H = 52

-- A text hyperlink in the group header: orange label, brightens on hover.
local function TrigLink(parent, text, onClick)
  local O = COLOR.orange
  local b = CreateFrame("Button", nil, parent)
  local fs = newText(b, FONT.body, 11, O, "LEFT"); fs:SetPoint("LEFT"); fs:SetText(text)
  b:SetSize(math.max(10, fs:GetStringWidth() + 2), 16)
  b:SetScript("OnEnter", function() fs:SetTextColor(1, 1, 1) end)
  b:SetScript("OnLeave", function() fs:SetTextColor(O.r, O.g, O.b) end)
  b:SetScript("OnClick", onClick)
  return b
end

function C:MakeTrigGroupBox(parent)
  local O = COLOR.orange
  local g = CreateFrame("Frame", nil, parent)
  local bg = g:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(O.r, O.g, O.b, 0.1)
  -- The group's NAME is white; the two links under it stay orange (the owner's mock).
  -- White reads as a title, orange as "this is clickable" — so the label stops
  -- competing with its own actions for the same colour.
  g.label = newText(g, FONT.label, 12, { r = 1, g = 1, b = 1 }, "RIGHT"); g.label:SetPoint("TOPRIGHT", -14, -12)

  -- Add Trigger | Delete Group. Delete CONFIRMS — it discards every condition in the
  -- group, and CONTRACTS §4 puts destructive actions behind the shared modal.
  g.delLink = TrigLink(g, "Delete Group", function()
    local n = g._n or 1
    C:OpenConfirm(("Delete TRIGGER GROUP %d?  Its conditions are removed with it."):format(n),
      function() C:TrigRemove(g._ti, nil) end)
  end)
  g.delLink:SetPoint("TOPRIGHT", -14, -28)   -- tight under the name: they belong to it
  local sep = newText(g, FONT.body, 11, MUTE, "RIGHT"); sep:SetText("|")
  sep:SetPoint("RIGHT", g.delLink, "LEFT", -6, 0)
  g.addLink = TrigLink(g, "Add Trigger", function() C:TrigAddToExistingGroup(g._ti) end)
  g.addLink:SetPoint("RIGHT", sep, "LEFT", -6, 0)

  local ml = newText(g, FONT.label, 11, { r = 1, g = 1, b = 1 }, "LEFT"); ml:SetPoint("TOPLEFT", 14, -16); ml:SetText("Match:")
  g.mpills = {}
  -- Deliberately SMALL (the owner, 2026-07-25): the top-level Match buttons are
  -- 113×28, and a second near-identical trio right under them read as clutter. These
  -- are a group's local setting, so they're sized as one.
  local mx = 62
  for _, lg in ipairs(TRIG_LOGICS) do
    local logic, w = lg[1], ({ ALL = 40, ANY = 40, NONE = 50 })[lg[2]] or 40
    local mp = CreateFrame("Button", nil, g); mp:SetSize(w, 20); mp:SetPoint("TOPLEFT", mx, -14); mx = mx + w + 6
    mp.fill = mp:CreateTexture(nil, "BACKGROUND"); mp.fill:SetAllPoints(); mp.fill:SetColorTexture(O.r, O.g, O.b, 0.8)
    mp.edges = addEdges(mp, { r = O.r, g = O.g, b = O.b, a = 1 }, 1)
    local ll = newText(mp, FONT.label, 11, { r = 1, g = 1, b = 1 }, "CENTER"); ll:SetPoint("CENTER"); ll:SetText(lg[2])
    mp._logic = logic
    mp:SetScript("OnClick", function()
      local grp = C:TrigNode(g._ti); if not grp then return end
      grp.logic = logic
      if GA.CDM then GA.CDM:RefreshDisplays() end
      C:TrigRender()
    end)
    g.mpills[#g.mpills + 1] = mp
  end
  g._rows = {}
  return g
end

function C:FillTrigGroupBox(g, ti, n, group)
  g._ti, g._n = ti, n
  g.label:SetText("TRIGGER GROUP " .. n)
  local logic = group.logic or "OR"
  for _, mp in ipairs(g.mpills) do
    local sel = (mp._logic == logic)
    mp.fill:SetShown(sel); mp:SetAlpha(sel and 1 or 0.5)
    for _, key in ipairs({ "top", "bottom", "left", "right" }) do mp.edges[key]:SetShown(not sel) end
  end
  local join = TRIG_JOIN[logic] or "OR"
  local leaves = group.conditions or {}
  g._joins = g._joins or {}
  for i, leaf in ipairs(leaves) do
    local row = g._rows[i]; if not row then row = C:MakeTrigRow(g, true); g._rows[i] = row end
    C:FillTrigRow(row, ti, i, leaf)
    local top = TRIG_GHDR_H + (i - 1) * TRIG_ROW_PITCH
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", TRIG_INSET_L, -top); row:SetPoint("TOPRIGHT", -TRIG_INSET_R, -top)
    row:Show()
    if i > 1 then
      local j = g._joins[i - 1]; if not j then j = C:MakeTrigJoin(g); g._joins[i - 1] = j end
      C:PlaceTrigJoin(j, top - TRIG_ROW_GAP, top, join)
    end
  end
  for i = #leaves + 1, #g._rows do g._rows[i]:Hide() end
  for i = math.max(1, #leaves), #g._joins do C:HideTrigJoin(g._joins[i]) end
  local h = TRIG_GHDR_H + #leaves * TRIG_ROW_PITCH + 8
  g:SetHeight(h)
  return h
end

function C:BuildTriggerSection(ct)
  local H = COLOR.heroic
  C._trigUI = { pills = {}, rows = {}, groups = {}, selected = {} }

  -- Match ALL / ANY / NONE segmented control (sets the top-level logic).
  for i, lg in ipairs(TRIG_LOGICS) do
    local logic = lg[1]
    local pill = flatButton(ct, 113, 28, H, "", 11); pill:SetBase(0.5); pill.text:Hide()
    pill:SetPoint("TOPLEFT", (i - 1) * 123, 0)
    pill._logic = logic; pill._lbl = twoWeightLabel(pill, 11); pill._lbl:Set("Match", lg[2])
    pill:SetScript("OnClick", function()
      local t = C:TrigTree(); if not t then return end
      t.logic = logic
      if GA.CDM then GA.CDM:RefreshDisplays() end
      C:TrigRender()
    end)
    C._trigUI.pills[i] = pill
  end

  -- Bordered trigger box (heroic@0.05 fill + purple@0.2 border), dynamic height.
  local box = CreateFrame("Frame", nil, ct); box:SetPoint("TOPLEFT", 0, -48); box:SetSize(EDITOR_W, 66)
  local bbg = box:CreateTexture(nil, "BACKGROUND"); bbg:SetAllPoints(); bbg:SetColorTexture(H.r, H.g, H.b, 0.05)
  addEdges(box, { r = COLOR.purple.r, g = COLOR.purple.g, b = COLOR.purple.b, a = 0.2 }, 1)
  C._trigUI.box = box

  -- The two add-buttons sit BELOW the box, side by side (the owner's mock): purple
  -- "Add a TRIGGER", orange "Add a TRIGGER GROUP" — the colour saying which context
  -- each one creates. "Add a Trigger" used to be a bar inside the box.
  local addT = flatButton(ct, COL_W, 34, H, "Add a TRIGGER", 12); addT:SetBase(0.5)
  setFont(addT.text, FONT.label, 12)
  addT:SetScript("OnClick", function() OpenPicker(function(item) C:TrigAddLeaf(item, nil) end) end)
  C._trigUI.addTrig = addT

  local addG = flatButton(ct, COL_W, 34, COLOR.orange, "Add a TRIGGER GROUP", 12); addG:SetBase(0.5)
  setFont(addG.text, FONT.label, 12)
  addG:SetScript("OnClick", function() C:TrigAddToGroup() end)
  C._trigUI.addGroup = addG

  local hint = newText(ct, FONT.body, 11, MUTE, "CENTER"); hint:SetWidth(EDITOR_W)
  hint:SetText("When adding a Trigger GROUP, use SHIFT+CLICK to select multiple triggers.")
  C._trigUI.hint = hint
end

-- "Add to Trigger Group": move shift-selected TOP-LEVEL conditions into a new group;
-- with nothing selected, create an empty group and pick its first condition.
function C:TrigAddToGroup()
  local cfg = C:TrigCfg(); if not cfg then return end
  local t = C:TrigTree(); if not t then return end
  local sel = C._trigUI.selected
  local moving, keep = {}, {}
  for _, node in ipairs(t.conditions) do
    if (not node.conditions) and sel[node] then moving[#moving + 1] = node else keep[#keep + 1] = node end
  end
  if #moving == 0 then
    C:TrigAddGroup()
    local gi = #C:TrigTree().conditions
    OpenPicker(function(item) C:TrigAddLeaf(item, gi) end)
    return
  end
  keep[#keep + 1] = { logic = "OR", conditions = moving }
  t.conditions = keep
  wipe(C._trigUI.selected)
  self:TrigRebind()
end

-- Add to an EXISTING group (its "+ Add to Group" button): move the shift-selection into
-- this group, or — with nothing selected — pick a new condition straight into it.
function C:TrigAddToExistingGroup(ti)
  local t = C:TrigTree(); if not t then return end
  local group = t.conditions[ti]; if not (group and group.conditions) then return end
  local sel = C._trigUI.selected
  local moving = {}
  for _, node in ipairs(t.conditions) do
    if (not node.conditions) and sel[node] then moving[#moving + 1] = node end
  end
  if #moving == 0 then
    OpenPicker(function(item) C:TrigAddLeaf(item, ti) end)   -- add a fresh condition to this group
    return
  end
  local keep = {}
  for _, node in ipairs(t.conditions) do
    if not ((not node.conditions) and sel[node]) then keep[#keep + 1] = node end
  end
  for _, node in ipairs(moving) do table.insert(group.conditions, node) end   -- group is a live ref
  t.conditions = keep
  wipe(C._trigUI.selected)
  self:TrigRebind()
end

-- Render the current aura's trigger tree (top-level leaves + nested group boxes) + size.
function C:TrigInlineRender()
  local ui = C._trigUI; if not ui then return end
  local cfg = C:TrigCfg()
  if not cfg then C:AccordionSetHeight("trigger", 40); return end
  local t = cfg.trigger                          -- may be nil — DON'T auto-create by viewing
  local logic = (t and t.logic) or "AND"
  local conditions = (t and t.conditions) or {}

  for _, pill in ipairs(ui.pills) do
    local sel = (pill._logic == logic)
    pill:SetBase(sel and 0.8 or 0.5); pill:SetAlpha(sel and 1 or 0.5)
  end

  -- Cards and group boxes stack in one column, each carrying the operator chip that
  -- joins it to the one above. `first` (not the index) decides whether a chip is drawn,
  -- because a top-level GROUP counts as an operand too.
  -- Cards and group boxes stack in one column as equal operands, each inset the same
  -- 52px so the bracket that joins it to the one above has a gutter to live in.
  -- `prevBottom` (not the index) drives the joins, because a GROUP is an operand too
  -- and its box is a different height from a card.
  local join = TRIG_JOIN[logic] or "AND"
  local y, nr, ng, nj, prevBottom = 12, 0, 0, 0, nil
  ui.joins = ui.joins or {}
  for ti, node in ipairs(conditions) do
    if prevBottom then
      nj = nj + 1
      local j = ui.joins[nj]; if not j then j = C:MakeTrigJoin(ui.box); ui.joins[nj] = j end
      C:PlaceTrigJoin(j, prevBottom, y, join)
    end
    if node.conditions then
      ng = ng + 1
      local gbox = ui.groups[ng]; if not gbox then gbox = C:MakeTrigGroupBox(ui.box); ui.groups[ng] = gbox end
      local gh = C:FillTrigGroupBox(gbox, ti, ng, node)
      gbox:ClearAllPoints()
      gbox:SetPoint("TOPLEFT", TRIG_INSET_L, -y); gbox:SetPoint("TOPRIGHT", -TRIG_INSET_R, -y); gbox:Show()
      prevBottom = y + gh
      y = prevBottom + TRIG_ROW_GAP
    else
      nr = nr + 1
      local row = ui.rows[nr]; if not row then row = C:MakeTrigRow(ui.box); ui.rows[nr] = row end
      C:FillTrigRow(row, ti, nil, node)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", TRIG_INSET_L, -y); row:SetPoint("TOPRIGHT", -TRIG_INSET_R, -y); row:Show()
      prevBottom = y + TRIG_ROW_H
      y = prevBottom + TRIG_ROW_GAP
    end
  end
  for i = nr + 1, #ui.rows do ui.rows[i]:Hide() end
  for i = ng + 1, #ui.groups do ui.groups[i]:Hide() end
  for i = nj + 1, #ui.joins do C:HideTrigJoin(ui.joins[i]) end

  local boxH = (prevBottom or 12) + 16      -- content + bottom pad (the add-bars are outside)
  ui.box:SetHeight(boxH)
  local btnY = -(48 + boxH + 16)
  ui.addTrig:ClearAllPoints();  ui.addTrig:SetPoint("TOPLEFT", 0, btnY)
  ui.addGroup:ClearAllPoints(); ui.addGroup:SetPoint("TOPLEFT", COL2_X, btnY)
  ui.hint:ClearAllPoints(); ui.hint:SetPoint("TOP", 0, btnY - 34 - 14)

  C:AccordionSetHeight("trigger", 48 + boxH + 16 + 34 + 14 + 26)   -- box + buttons + hint
end

-- Inline TEXT section (redesign). Content field + Show/Charge toggles + Font pill +
-- Text Color + Size + Outline/Anchor + X/Y. Reuses the shipped text engine (cfg.text,
-- OpenFontPicker, TE_OUTLINE/TE_ANCHOR); reads are NON-seeding (so merely viewing the
-- section never creates cfg.text) while writes seed it.
function C:BuildTextSection(ct)
  local H = COLOR.heroic
  local function txt() local c = Cfg(); return c and c.text end                          -- read, no seed
  local function ensure() local c = Cfg(); if not c then return nil end
    if not c.text then c.text = { show = (c.showLabel ~= false) } end; return c.text end  -- write, seeds

  -- Content field (heroic-8%, placeholder = the aura's name).
  local cf = CreateFrame("EditBox", nil, ct); cf:SetSize(EDITOR_W, 28); cf:SetPoint("TOPLEFT", 0, 0)
  cf:SetAutoFocus(false); setFont(cf, FONT.body, 13); cf:SetTextColor(1, 1, 1); cf:SetTextInsets(10, 10, 0, 0)
  local cbg = cf:CreateTexture(nil, "BACKGROUND"); cbg:SetAllPoints(); cbg:SetColorTexture(H.r, H.g, H.b, 0.08)
  local cph = newText(cf, FONT.body, 13, TEXT, "LEFT"); cph:SetPoint("LEFT", 10, 0); cph:SetAlpha(0.3); cph:SetText("Text (blank = the aura's name)")
  local function cUpd() cph:SetShown((cf:GetText() or "") == "") end
  cf:SetScript("OnTextChanged", cUpd)
  cf:SetScript("OnEnterPressed", function(self) local t = ensure(); if t then local s = self:GetText(); t.str = (s ~= "" and s) or nil; ReapplySelected() end; self:ClearFocus() end)
  cf:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  rows[#rows + 1] = { refresh = function() local t = txt(); cf:SetText((t and t.str) or ""); cf:SetCursorPosition(0); cUpd() end,
                      setEnabled = function(_, on) cf:SetEnabled(on) end }

  -- Show Text + Show Charge Count toggles (one row).
  local sLbl = newText(ct, FONT.body, 11, { r = 1, g = 1, b = 1 }, "LEFT"); sLbl:SetPoint("TOPLEFT", 0, -50); sLbl:SetText("Show Text Above")
  local sTog = makeToggle(ct,
    function() local c = Cfg(); if not c then return false end; local t = c.text; if t then return t.show ~= false end; return c.showLabel ~= false end,
    function(v) local t = ensure(); if t then t.show = v; ReapplySelected() end end)
  sTog:SetPoint("TOPLEFT", 94, -48)
  rows[#rows + 1] = { refresh = function() sTog:refresh() end, setEnabled = function() end }

  local cLbl = newText(ct, FONT.body, 11, { r = 1, g = 1, b = 1 }, "LEFT"); cLbl:SetPoint("TOPLEFT", COL2_X, -50); cLbl:SetText("Show Charge Count")
  local cTog = makeToggle(ct,
    function() local t = txt(); return t and t.showCount == true end,
    function(v) local t = ensure(); if t then t.showCount = v or nil; if v then t.show = true; sTog:refresh() end; ReapplySelected() end end)
  cTog:SetPoint("TOPLEFT", COL2_X + 108, -48)
  rows[#rows + 1] = { refresh = function() cTog:refresh() end, setEnabled = function() end }

  -- Font pill + Text Color.
  local fb = flatButton(ct, 220, 28, H, "", 11); fb:SetBase(0.5); fb.text:Hide(); fb:SetPoint("TOPLEFT", 0, -88)
  local fLbl = twoWeightLabel(fb, 11)
  fb:SetScript("OnClick", function()
    local t = txt()
    OpenFontPicker(function(path) local t2 = ensure(); if t2 then t2.font = path; ReapplySelected(); fLbl:Set("Font:", fontNameFor(path)) end end, t and t.font)
  end)
  rows[#rows + 1] = { refresh = function() local t = txt(); fLbl:Set("Font:", fontNameFor(t and t.font)) end, setEnabled = function(_, on) fb:SetEnabled(on) end }

  rows[#rows + 1] = MakeColor(ct, COL2_X, -91,
    function() local t = txt(); return t and t.color end,
    function(v) local t = ensure(); if t then t.color = v end end, "Text Color")

  -- Size (max well above the old 48 so big display text is possible; type an exact value too).
  rows[#rows + 1] = MakeSlider(ct, -136, "Size", 6, 300, 1,
    function() local t = txt(); return t and t.size or 14 end,
    function(v) local t = ensure(); if t then t.size = v end end)

  -- Outline + Anchor.
  rows[#rows + 1] = MakeDropdown(ct, 0, -176, COL_W, "Outline:", TE_OUTLINE,
    function() local t = txt(); return (t and t.outline) or "OUTLINE" end,
    function(v) local t = ensure(); if t then t.outline = (v ~= "OUTLINE") and v or nil end end)
  rows[#rows + 1] = MakeDropdown(ct, COL2_X, -176, COL_W, "Anchor:", TE_ANCHOR,
    function() local t = txt(); return (t and t.anchor) or "BOTTOM" end,
    function(v) local t = ensure(); if t then t.anchor = (v ~= "BOTTOM") and v or nil end end)

  -- X / Y offset.
  rows[#rows + 1] = MakeSlider(ct, -224, "X Offset", -400, 400, 2,
    function() local t = txt(); return t and t.x or 0 end,
    function(v) local t = ensure(); if t then t.x = (v ~= 0) and v or nil end end)
  rows[#rows + 1] = MakeSlider(ct, -257, "Y Offset", -400, 400, 2,
    function() local t = txt(); return t and t.y or 0 end,
    function(v) local t = ensure(); if t then t.y = (v ~= 0) and v or nil end end)
end

-- Inline EFFECTS & MOTION section (redesign). Glow only for now (Motion parked — low
-- priority). Reuses the shipped glow engine (cfg.glow + Displays ApplyGlow via ReapplySelected).
function C:BuildEffectsSection(ct)
  local GLOW = { { "none", "None" }, { "autocast", "Autocast Shine" }, { "pixel", "Pixel Glow" },
                 { "proc", "Proc Glow" }, { "button", "Action Button Glow" } }
  rows[#rows + 1] = MakeDropdown(ct, 0, 0, 220, "Glow:", GLOW,
    function() local c = Cfg(); return (c and c.glow and c.glow.type) or "none" end,
    function(v) local c = Cfg(); if not c then return end; c.glow = c.glow or {}; c.glow.type = (v ~= "none") and v or nil end)
  -- Custom Color sits BESIDE the dropdown again. It was banished to its own row when
  -- the pane was 360 wide (checkbox + label + swatch is ~157px, and the swatch fell off
  -- the right edge); the wider pane fits both on one row, so the section lost 34px.
  rows[#rows + 1] = MakeColor(ct, COL2_X, -3,
    function() local c = Cfg(); return c and c.glow and c.glow.customColor and c.glow.color end,
    function(v) local c = Cfg(); if not c then return end; c.glow = c.glow or {}; c.glow.color = v; c.glow.customColor = (v ~= nil) or nil end,
    "Custom Color")
  local hint = newText(ct, FONT.body, 11, MUTE, "LEFT"); hint:SetPoint("TOPLEFT", 0, -40); hint:SetWidth(EDITOR_W); hint:SetJustifyH("LEFT")
  hint:SetText("Glow shows while the aura is on screen. Custom Color off = the glow's own colour.")
end

-- The Sounds section — a sound pick + Test, plus WHEN it plays: on trigger (aura
-- applied / cooldown ready), on wear-off, or on entering the pandemic window. The
-- timing writes cfg.sound.on; CDM fires it from the matching Blizzard alert event
-- (auto-path displays) or the shown/hidden edge (compound-trigger / decoration).
function C:BuildSoundSection(ct)
  local sb = flatButton(ct, 150, 22, COLOR.heroic, "None", 12); sb:SetBase(0.4); sb:SetPoint("TOPLEFT", 2, -6)
  local function soundLabel() local c = Cfg(); return (c and c.sound and c.sound.name) or "None" end

  -- The "Play:" timing dropdown — only meaningful with a sound set, so its enabled state
  -- follows both the selection AND whether a sound is chosen.
  local ON = { { "trigger", "When it triggers" }, { "untrigger", "When it wears off" }, { "pandemic", "Pandemic window" } }
  local onRow = MakeDropdown(ct, COL2_X, -3, COL_W, "Play:", ON,
    function() local c = Cfg(); return (c and c.sound and c.sound.on) or "trigger" end,
    function(v) local c = Cfg(); if c and c.sound then c.sound.on = v end end)
  local function refreshOnEnabled() local c = Cfg(); onRow:setEnabled((c and c.sound) and true or false) end

  sb:SetScript("OnClick", function()
    local c = Cfg(); if not c then return end
    OpenSoundPicker(function(item)
      if item.file then c.sound = c.sound or {}; c.sound.file = item.file; c.sound.name = item.name; c.sound.channel = "Master"
      else c.sound = nil end
      sb:SetText(soundLabel()); onRow:refresh(); refreshOnEnabled()
    end, c.sound and c.sound.file)
  end)
  local tb = flatButton(ct, 52, 22, COLOR.heroic, "Test", 12); tb:SetBase(0.4); tb:SetPoint("LEFT", sb, "RIGHT", 8, 0)
  tb:SetScript("OnClick", function() local c = Cfg(); if c and c.sound and c.sound.file then pcall(PlaySoundFile, c.sound.file, c.sound.channel or "Master") end end)

  local hint = newText(ct, FONT.body, 11, MUTE, "LEFT"); hint:SetPoint("TOPLEFT", 2, -36); hint:SetWidth(EDITOR_W - 4); hint:SetJustifyH("LEFT")
  hint:SetText("Triggers = when the aura is applied (no re-fire on target swap). Pandemic works for DoT/debuff auras.")

  rows[#rows + 1] = {
    refresh = function() sb:SetText(soundLabel()); onRow:refresh(); refreshOnEnabled() end,
    setEnabled = function(_, on) sb:SetEnabled(on); tb:SetEnabled(on); if on then refreshOnEnabled() else onRow:setEnabled(false) end end,
  }
end

-- The Load Conditions block — a visibility gate (Combat/Target state, context toggles,
-- spec multi-select, known-spell) + the master Disabled/Enabled switch.
--
-- ★ BUILT TWICE, from one implementation: once in the AURA editor (gating cfg.visibility)
-- and once in the GROUP pane (gating group.visibility — a group's "load rule"). That is
-- what retired the docked Visibility drawer outright: it was the last thing group rules
-- needed a floating window for. `o.target` says WHICH table is being gated, `o.sink`
-- which refresh list the rows join (auras use the shared `rows`, driven by SetSelected;
-- the group pane keeps its own). Engine unchanged — same visibility model, same
-- CDM:VisibilityGate, which never cared whose table it was reading.
-- Reads are NON-SEEDING: viewing must not create a .visibility on a bare/decoration aura.
function C:BuildLoadConditionsSection(ct, o)
  o = o or {}
  local sink = o.sink or rows
  local target = o.target or Cfg                      -- the aura/group being gated
  local noun = o.noun or "aura"
  local function vis() local t = target(); return t and t.visibility end               -- read (no seed)
  local function visW() local t = target(); if not t then return nil end; t.visibility = t.visibility or {}; return t.visibility end
  local function poke() if GA.CDM then GA.CDM:UpdateVisibilityPoll(); GA.CDM:RefreshDisplays() end end

  local COMBAT = { { "any", "Any" }, { "in", "In Combat" }, { "out", "Out of Combat" } }
  local TARGET = { { "any", "Any" }, { "has", "Has Target" }, { "none", "No Target" } }
  sink[#sink + 1] = MakeDropdown(ct, 0, -6, COL_W, "Combat:", COMBAT,
    function() local v = vis(); return (v and v.combat) or "any" end,
    function(x) local v = visW(); if v then v.combat = (x ~= "any") and x or nil; poke() end end)
  sink[#sink + 1] = MakeDropdown(ct, COL2_X, -6, COL_W, "Target:", TARGET,
    function() local v = vis(); return (v and v.target) or "any" end,
    function(x) local v = visW(); if v then v.target = (x ~= "any") and x or nil; poke() end end)

  -- Context toggles (each ANDs in — require it true). Two columns.
  local function toggle(key, label, x, y)
    local c = flatCheck(ct, label); c:SetPoint("TOPLEFT", x, y)
    c:SetScript("OnClick", function()
      local v = visW(); if not v then return end
      c:Set(not c:Get()); v[key] = c:Get() or nil; poke()
    end)
    sink[#sink + 1] = { refresh = function() local v = vis(); c:Set(v and v[key]) end,
                        setEnabled = function(_, on) c:SetEnabled(on) end }
  end
  local L, R, ty, dy = 0, COL2_X, -44, 25
  toggle("casting",   "While casting",     L, ty)
  toggle("mounted",   "Mounted",           L, ty - dy)
  toggle("vehicle",   "In vehicle",        L, ty - dy * 2)
  toggle("instance",  "In instance",       L, ty - dy * 3)
  toggle("encounter", "In boss encounter", L, ty - dy * 4)
  toggle("resting",   "Resting",           L, ty - dy * 5)
  toggle("stealthed", "Stealthed",         R, ty)
  toggle("group",     "In a group",        R, ty - dy)
  toggle("raid",      "In a raid",         R, ty - dy * 2)
  toggle("warmode",   "War Mode",          R, ty - dy * 3)
  toggle("alive",     "Alive (not dead)",  R, ty - dy * 4)

  -- Specialization (multi-select; none = all specs). 2-column grid.
  local specHdr = newText(ct, FONT.head, 13, COLOR.purple, "LEFT"); specHdr:SetPoint("TOPLEFT", 0, -200); specHdr:SetText("SPECIALIZATION")
  local specHint = newText(ct, FONT.body, 11, MUTE, "LEFT"); specHint:SetPoint("LEFT", specHdr, "RIGHT", 8, 0); specHint:SetText("(none = all specs)")
  local specs = PlayerSpecs()
  for i, sp in ipairs(specs) do
    local col, r = (i - 1) % 2, math.floor((i - 1) / 2)
    local c = flatCheck(ct, sp.name); c:SetPoint("TOPLEFT", col * COL2_X, -224 - r * 25)
    c:SetScript("OnClick", function()
      local v = visW(); if not v then return end
      v.specs = v.specs or {}; c:Set(not c:Get()); v.specs[sp.id] = c:Get() or nil
      if not next(v.specs) then v.specs = nil end
      poke()
    end)
    sink[#sink + 1] = { refresh = function() local v = vis(); c:Set(v and v.specs and v.specs[sp.id]) end,
                        setEnabled = function(_, on) c:SetEnabled(on) end }
  end
  local skTop = -224 - math.max(1, math.ceil(#specs / 2)) * 25 - 14

  -- Spell / talent known.
  local skHdr = newText(ct, FONT.head, 13, COLOR.purple, "LEFT"); skHdr:SetPoint("TOPLEFT", 0, skTop); skHdr:SetText("SPELL / TALENT KNOWN")
  local skBox = flatEditBox(ct, 80, 22); skBox:SetPoint("TOPLEFT", 0, skTop - 22); skBox:SetNumeric(true)
  local skName = newText(ct, FONT.body, 12, TEXT, "LEFT"); skName:SetPoint("LEFT", skBox, "RIGHT", 8, 0); skName:SetWidth(EDITOR_W - 92); skName:SetJustifyH("LEFT")
  local function skRefreshName()
    local v = vis(); local id = v and v.spellKnown
    if id then
      local nm = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
      skName:SetText(nm and ("|cffffffff" .. nm .. "|r — shows only if known") or ("spell " .. id))
    else
      skName:SetText("|cff888888enter a spell ID (talents count)|r")
    end
  end
  skBox:SetScript("OnEnterPressed", function(self)
    local v = visW(); if not v then return end
    v.spellKnown = tonumber(self:GetText()); skRefreshName(); self:ClearFocus(); poke()
  end)
  skBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  sink[#sink + 1] = { refresh = function() local v = vis(); skBox:SetText(v and v.spellKnown and tostring(v.spellKnown) or ""); skRefreshName() end,
                      setEnabled = function(_, on) skBox:SetEnabled(on) end }

  -- Master off-switch (NOT a "show when" condition — sits apart under a divider). ON =
  -- Enabled; OFF = Disabled (cfg.enabled=false → dropped from tracking + greyed in the list).
  local div = ct:CreateTexture(nil, "ARTWORK"); div:SetColorTexture(COLOR.rim.r, COLOR.rim.g, COLOR.rim.b, COLOR.rim.a)
  div:SetPoint("TOPLEFT", 0, skTop - 56); div:SetPoint("TOPRIGHT", 0, skTop - 56); div:SetHeight(1)
  local disLbl = newText(ct, FONT.bodyM, 13, TEXT, "LEFT"); disLbl:SetPoint("TOPLEFT", 0, skTop - 72)
  disLbl:SetText("This " .. noun .. " in the game:")
  local disSwitch = makeSwitch(ct, "Disabled", "Enabled", function(v)
    local t = target(); if not t then return end
    -- NEVER `t.enabled = v and nil or false` — for v==true that evaluates FALSE in both
    -- directions (the 2026-07-08 wall: `a and b or c` breaks when b is nil).
    if v then t.enabled = nil else t.enabled = false end
    if GA.CDM then GA.CDM:Discover(); GA.CDM:UpdateVisibilityPoll(); GA.CDM:RefreshDisplays() end
    RefreshList()
  end)
  -- Own row (the switch's labels extend ~166px, too wide to sit beside the label).
  disSwitch:SetPoint("TOPLEFT", 0, skTop - 98)
  -- MUST provide setEnabled too — SetSelected calls r:refresh() AND r:setEnabled() on every
  -- row; a row missing either throws and aborts the rest of SetSelected (trigger + group UI).
  sink[#sink + 1] = {
    refresh = function() local t = target(); disSwitch:Set(not (t and t.enabled == false)) end,
    setEnabled = function(_, on) disSwitch:SetEnabled(on) end,
  }
  return -(skTop - 98) + 40   -- content height, so the group pane can size itself
end

-- Phase D: the standalone window (GloomsAurasConfig — chrome, glow, drag,
-- panelPos, UISpecialFrames entry) is DELETED. The shell owns the window; this
-- builds the Auras tab INSIDE the shell-provided container: a flush-left rail
-- beside an editor pane that fills the rest (layout rework, 2026-07-25).
local function BuildTab(c)
  container = c

  -- ---- LEFT RAIL: header · profile · the aura tree · the selection's buttons ----
  local rail = CreateFrame("Frame", nil, c)
  rail:SetPoint("TOPLEFT", 0, 0); rail:SetPoint("BOTTOMLEFT", 0, FOOTER_H); rail:SetWidth(RAIL_W)

  -- The shared tab header (LibGloomSkin MINOR 4) — GA was the LAST tab without one,
  -- held back deliberately because the retired splash sat exactly where it goes.
  -- The SQUARE 512×512 mark (Media/logo.png), NOT the old portrait ga_logo_full.png.
  -- x = 14 like the other three: the owner compares tabs by tabbing between them.
  UI.tabHeader(rail, {
    texture = MEDIA .. "logo.png",
    label   = "GLOOM'S AURAS",
    x       = RAIL_X,
  })

  -- PROFILE — the shared profileBlock, permanently visible (its drawer is deleted).
  C:BuildProfileBlock(rail, RAIL_X, LIST_W, -60)
  local pdiv = UI.hLine(rail)
  pdiv:SetPoint("TOPLEFT", RAIL_X, -180); pdiv:SetPoint("TOPRIGHT", -RAIL_X, -180)

  -- Vertical divider between the rail and the editor pane, down to the footer.
  local divider = c:CreateTexture(nil, "ARTWORK")
  divider:SetColorTexture(COLOR.rim.r, COLOR.rim.g, COLOR.rim.b, COLOR.rim.a)
  divider:SetPoint("TOPLEFT", RAIL_W, 0)
  divider:SetPoint("BOTTOMLEFT", RAIL_W, FOOTER_H)
  divider:SetWidth(1)

  -- ---- The aura tree (groups + their auras), inside the rail ----
  listFrame = CreateFrame("Frame", nil, rail)
  listFrame:SetPoint("TOPLEFT", RAIL_X, LIST_TOP); listFrame:SetPoint("BOTTOMLEFT", RAIL_X, 0)
  listFrame:SetWidth(LIST_W)
  listFrame:EnableMouse(true); listFrame:EnableMouseWheel(true)
  listFrame:SetScript("OnMouseWheel", function(_, delta) listOffset = listOffset - delta; RefreshList() end)

  local listHead = newText(listFrame, FONT.head, 12, MUTE, "LEFT")   -- rail section label, like PROFILE
  listHead:SetPoint("TOPLEFT", 0, -2); listHead:SetText("GROUPS & AURAS")

  for i = 1, LIST_ROWS do
    local row = CreateFrame("Button", nil, listFrame)
    row:SetSize(LIST_W, LIST_ROW_H); row:SetPoint("TOPLEFT", 0, -24 - (i - 1) * LIST_ROW_H)
    local sel = row:CreateTexture(nil, "BACKGROUND"); sel:SetAllPoints(); sel:SetColorTexture(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b, 0.28); sel:Hide(); row.sel = sel
    local hl = row:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
    -- Collapse caret — the SUITE's shared art at the shared size/colour (points right =
    -- collapsed, rotated to point down = expanded). Shown on group header rows only.
    local arrow = row:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(9, 9); arrow:SetPoint("LEFT", 4, 0)
    arrow:SetTexture(UI.CARET); arrow:SetVertexColor(COLOR.orange.r, COLOR.orange.g, COLOR.orange.b)
    arrow:Hide(); row.arrow = arrow
    local icon = row:CreateTexture(nil, "ARTWORK"); icon:SetSize(18, 18); icon:SetPoint("LEFT", 18, 0); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92); row.icon = icon
    local name = newText(row, FONT.body, 12, TEXT, "LEFT"); name:SetPoint("LEFT", 40, 0); name:SetPoint("RIGHT", -4, 0); row.name = name
    name:SetWordWrap(false)   -- long names truncate on one line (bounded width), never wrap
    -- Caret hit-area (group rows): clicking the CARET expands/collapses, clicking the
    -- NAME selects the group and opens its settings — standard tree behaviour, and what
    -- you'd try. The ⚙ gear that used to sit on the right of every group header is GONE
    -- with its drawer; a group's settings live in the pane now.
    local caretBtn = CreateFrame("Button", nil, row)
    caretBtn:SetPoint("TOPLEFT", 0, 0); caretBtn:SetSize(20, LIST_ROW_H)
    caretBtn:SetScript("OnClick", function()
      if row.kind == "group" then
        local g = Groups() and Groups()[row.gid]
        if g then g.collapsed = (not g.collapsed) or nil; RefreshList() end
      elseif row.kind == "ungrouped" then
        GA.db.ungroupedCollapsed = (not GA.db.ungroupedCollapsed) or nil; RefreshList()
      end
    end)
    caretBtn:Hide(); row.caretBtn = caretBtn
    -- Per-aura EYE (aura rows only): the owner's eye icons — unhidden = previewed on
    -- screen while the panel is open, hidden = not. Editor-only (cfg.preview); it does
    -- NOT affect whether the aura runs in gameplay (that's Visibility → Disabled).
    local eye = flatButton(row, 18, 18, COLOR.purple, "", 12); eye:SetBase(0.0)
    eye:SetPoint("RIGHT", -3, 0)
    local eicon = eye:CreateTexture(nil, "OVERLAY"); eicon:SetSize(14, 14); eicon:SetPoint("CENTER")
    eicon:SetVertexColor(1, 1, 1, 1); eye.icon = eicon
    eye:SetScript("OnClick", function()
      if row.kind ~= "aura" or not row.id then return end
      local cfg = DB() and DB()[row.id]; if not cfg then return end
      cfg.preview = (not cfg.preview) or nil     -- toggle on-screen editor preview
      if GA.Displays then GA.Displays:RefreshForced() end
      RefreshList()
    end)
    eye:Hide(); row.eye = eye
    -- Double-click an aura row = rename it (the gesture people try first; the
    -- Rename button below is the discoverable one). OnClick still fires first,
    -- so the row is selected before the dialog opens.
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnDoubleClick", function(self)
      if self.kind == "aura" and self.id then SetSelected(self.id); C:RenameSelected() end
    end)
    row:SetScript("OnClick", function(self)
      if self.kind == "aura" then
        SetSelected(self.id)
      elseif self.kind == "group" then
        C:SelectGroup(self.gid)          -- its settings open in the pane, like an aura's
      elseif self.kind == "ungrouped" then
        -- "Ungrouped" is not a real group (no rule, no switch, nothing to edit), so its
        -- row only ever collapses.
        GA.db.ungroupedCollapsed = (not GA.db.ungroupedCollapsed) or nil; RefreshList()
      end
    end)
    listRows[i] = row
  end

  -- Rail button stack (New Aura / New Group · Rename / Duplicate · Delete Aura).
  C:BuildLeftButtons(listFrame)

  -- ---- EDITOR PANE: the settings accordion (see C:BuildEditor) ----
  -- A ScrollFrame so a tall open section (Aura Load Conditions) scrolls inside the pane
  -- instead of spilling into the footer. The scrollbar sits in the right margin, clear of
  -- content. Anchored to the container's right edge, so a wider shell widens the pane.
  local editor = CreateFrame("ScrollFrame", nil, c)
  editor:SetPoint("TOPLEFT", EDITOR_X, CONTENT_TOP)
  editor:SetPoint("BOTTOMRIGHT", -30, FOOTER_H)
  editor:EnableMouseWheel(true)
  local scrollChild = CreateFrame("Frame", nil, editor)
  scrollChild:SetSize(EDITOR_W, PANE_H)
  editor:SetScrollChild(scrollChild)
  C._editor = editor; C._editorChild = scrollChild   -- hidden by the empty state
  local sbTrack = c:CreateTexture(nil, "ARTWORK"); sbTrack:SetColorTexture(1, 1, 1, 0.06); sbTrack:SetWidth(6)
  sbTrack:SetPoint("TOPLEFT", editor, "TOPRIGHT", 8, 0); sbTrack:SetPoint("BOTTOMLEFT", editor, "BOTTOMRIGHT", 8, 0)
  local sbThumb = CreateFrame("Button", nil, c); sbThumb:SetWidth(6); sbThumb:EnableMouse(true)
  local stt = sbThumb:CreateTexture(nil, "OVERLAY"); stt:SetAllPoints(); stt:SetColorTexture(COLOR.orange.r, COLOR.orange.g, COLOR.orange.b, 1)
  sbThumb:SetPoint("TOPRIGHT", sbTrack, "TOPRIGHT", 0, 0)
  C._editorTrack = sbTrack; C._editorThumb = sbThumb
  editor:SetScript("OnMouseWheel", function(_, d) C:SetEditorScroll((C._editorScroll or 0) - d * 40) end)
  local dragging, startCY, startScroll = false, 0, 0
  sbThumb:SetScript("OnMouseDown", function() dragging = true; startScroll = C._editorScroll or 0; local _, cy = GetCursorPosition(); startCY = cy / editor:GetEffectiveScale() end)
  sbThumb:SetScript("OnMouseUp", function() dragging = false end)
  sbThumb:SetScript("OnUpdate", function()
    if not dragging then return end
    local maxS, range = C._editorMaxScroll or 0, PANE_H - sbThumb:GetHeight()
    if maxS <= 0 or range <= 0 then return end
    local _, cy = GetCursorPosition(); local moved = startCY - (cy / editor:GetEffectiveScale())
    C:SetEditorScroll(startScroll + (moved / range) * maxS)
  end)
  C:BuildEditor(scrollChild)
  C:BuildGroupPane(scrollChild)   -- the same pane, showing a GROUP's settings

  -- ---- Footer strip ----
  -- Divider + the one control left down here. (The "Profile: <name>" button that used
  -- to sit bottom-right is GONE with its drawer — profiles live in the rail now, so
  -- the footer shrank 86 → 52, matching GB's, and the panes got the 34px.)
  local footDiv = c:CreateTexture(nil, "ARTWORK")
  footDiv:SetColorTexture(COLOR.rim.r, COLOR.rim.g, COLOR.rim.b, COLOR.rim.a)
  footDiv:SetPoint("BOTTOMLEFT", 0, FOOTER_H); footDiv:SetPoint("BOTTOMRIGHT", 0, FOOTER_H); footDiv:SetHeight(1)

  -- Hide Blizzard's own Cooldown Manager (drives viewer alpha only, not Hide(), so our
  -- state mirror keeps working). A checkbox, bottom-left — GB's footer inset is 16.
  local hideCDM = flatCheck(c, "Hide Blizzard's Cooldown Manager")
  hideCDM:SetPoint("BOTTOMLEFT", 16, 16)
  hideCDM:SetScript("OnClick", function()
    local on = not hideCDM:Get()
    hideCDM:Set(on)
    if GA.CDM and GA.CDM.ToggleBlizzardHide then GA.CDM:ToggleBlizzardHide(on) end
  end)
  C._hideCDM = hideCDM   -- so C:OnProfileSwitched can re-sync it (hideBlizzardCDM is per-profile)

  -- Empty state: shown in place of the accordion when the profile has no auras
  -- (the splash used to cover this case). Parented to the container, not the scroll
  -- frame, so it survives that frame being hidden.
  local empty = newText(c, FONT.body, 12, MUTE, "CENTER")
  empty:SetPoint("TOPLEFT", EDITOR_X, CONTENT_TOP - 40); empty:SetWidth(EDITOR_W)
  empty:SetText("No auras in this profile yet.\n\nClick |cff936bff+ New Aura|r to make one.")
  empty:Hide(); C._empty = empty

  -- OnShow/OnHide live on the CONTAINER: they fire when the tab gains/loses
  -- visibility — window open/close AND tab switches — which is exactly when
  -- the old window showed/hid. (Escape-close + window position are the
  -- SHELL's job now; the old panelPos repositioning is gone with the window.)
  c:HookScript("OnShow", function()
    hideCDM:Set(GA.db and GA.db.hideBlizzardCDM)
    C:RefreshProfileList()   -- rail block re-reads the active profile
    if GA.Displays then
      GA.Displays.forced = true
      GA.Displays:SetInteractive(true)
    end
    C:SelectInitial()   -- straight into the editor on the last-edited aura (splash retired)
  end)
  c:HookScript("OnHide", function()
    CloseSubWindows()   -- close any docked drawer so it doesn't linger/reappear
    if GA.Displays then GA.Displays.forced = false; GA.Displays:SetSelectedDisplay(nil) end
    if GA.CDM and GA.CDM.Discover then GA.CDM:Discover() end
  end)
end

function C:RefreshCurrent()
  for _, r in ipairs(rows) do r:refresh() end
end

-- C:SavePanelPos and C:Toggle are GONE (Phase D, locked decision: hard
-- dependency, no second window path). The shell owns the window's position
-- and open/close/switch semantics; /ga and the suite minimap button route
-- through GloomsHub:ToggleWindow("auras"). Stale GA.global.panelPos data is
-- harmless leftover.

-- Mount the Auras tab (CONTRACTS §2). Registration is cheap and immediate;
-- BuildTab runs ONCE, lazily, the first time the tab is shown. No `refresh`
-- handler — the container's OnShow hook (above) already re-syncs on every
-- focus, exactly like the old window's OnShow did.
GloomsHub:RegisterTab{
  id    = "auras",
  title = "AURAS",
  order = 10,
  build = BuildTab,
}
