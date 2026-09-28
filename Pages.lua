-- ============================================================
-- Pages.lua — Gloom's Auras
-- ★ THE TWO-WINDOW DESIGN (2026-09-27), from the owner's Figma page
-- "GloomSuite UI 3": "gloomAuras, main selector" and the settings frames
-- "gloomAuras, Aura Triggers" … "Global Settings".
-- The Hub (Windows.lua) owns the windows: the SELECTOR (240 wide), the
-- SETTINGS window (400 wide) with its TAB, the pop-outs, the headers, the
-- scrolling, the resize bars and Global Settings. This file draws:
--   the selector's list — the groups and their auras, New Aura / New Group;
--   the tab — the aura being edited (click its name to switch auras; right-click
--     for Rename · Duplicate · Move to Group · Delete);
--   the six SECTIONS — Aura Triggers · Appearance, Position & Size · Bar Fill &
--     Readouts · Text · Effects, Motion & Sound · Aura Load Conditions.
-- ★ A section is its own 360-wide frame and every number in it is the mock's
-- own coordinate inside the section (the owner: "I put things where they are
-- for a reason"): a labelled control is 33 tall (label, 4, the 16-tall
-- control), rows 41 apart, blocks 30 apart, two columns of 170 at 0 and 190.
--
-- It is DRAWING only. Every setting still goes through Config.lua's logic —
-- the trigger tree, the pickers, selection, profiles — exported as C.X. The old
-- editor's section builders in Config.lua are no longer mounted.
-- ⚠ Every widget here is the Hub's kit (LibGloomSkin MINOR 16).
-- ============================================================

local GA = GloomsAuras
local C = GA and GA.Config
local X = C and C.X
-- ⚠ Not `LibStub and LibStub(...)`: an `and` keeps only the call's FIRST value,
-- so the version number would always come back nil.
local Skin, skinMinor
if LibStub then Skin, skinMinor = LibStub("LibGloomSkin-1.0", true) end
if not (X and Skin) then return end
if (skinMinor or 0) < 17 then
  print("|cffff5555Gloom's Auras|r: the Auras windows need Gloom's Hub with LibGloomSkin 17 or newer — update Gloom's Hub.")
  return
end

local UI, COLOR, FONT = Skin.UI, Skin.COLOR, Skin.FONT
local VIOLET, LILAC, LIME, CORAL = COLOR.violet, COLOR.lilac, COLOR.lime, COLOR.coral
local DB, Cfg, rows = X.DB, X.Cfg, X.rows

local P = { listOffset = 0 }
C.P = P

local function Sel() return X.Selected() end
local function Reapply() X.ReapplySelected() end
local function Poke()
  if GA.CDM then GA.CDM:UpdateVisibilityPoll(); GA.CDM:RefreshDisplays() end
end
local function Relayout() if GloomsHub.RefreshWindows then GloomsHub:RefreshWindows("auras") end end

-- One refresh for everything: what SetSelected already does to the shared rows.
-- Called after any change that another control's enabled state depends on.
function P.sync()
  local on = Cfg() ~= nil
  for _, r in ipairs(rows) do
    if r.refresh then r:refresh() end
    if r.setEnabled then r:setEnabled(on) end
  end
end

-- A row for the shared list: `ctrl` is a kit control (it has refresh /
-- setEnabled); `gate` (optional) is an extra condition for being usable. A
-- control that is not usable DIMS to 30% — never hides (the suite's rule).
local function add(ctrl, gate)
  local r = {}
  function r:refresh() if ctrl.refresh then ctrl:refresh() end end
  function r:setEnabled(on)
    local ok = on and (not gate or gate())
    if ctrl.setEnabled then ctrl:setEnabled(ok)
    elseif ctrl.SetEnabled then ctrl:SetEnabled(ok); ctrl:SetAlpha(ok and 1 or UI.G_DIM) end
    -- a control's label dims with it
    if ctrl._label then ctrl._label:SetAlpha(ok and 1 or UI.G_DIM) end
  end
  rows[#rows + 1] = r
  return ctrl
end

-- The aura's icon: its own texture first, else its tracked spell's, else the
-- question mark — the same rule as the on-screen fallback (Hub backlog item 9).
local function AuraIcon(cfg)
  local tex = cfg and cfg.texture
  if tex == "" then tex = nil end
  local sid = cfg and GA.CDM and GA.CDM.DisplaySpellID and GA.CDM:DisplaySpellID(cfg)
  return tex or (sid and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)) or 134400
end

local function GroupName(gid)
  local g = gid and X.Groups() and X.Groups()[gid]
  return g and (g.name or "Group") or "Ungrouped"
end

-- ---------------------------------------------------------------------------
-- The mocks' labelled controls, placed at (x, y) inside a section: the label
-- (Sansation 10) at y, the control 15 under it (the label's box, 11, + the
-- mocks' 4 gap; it was 17 = 13 + 4 while labels were 12). `w` is the
-- column: 170 (two columns, at 0 and 190), 107/106/107 (three, at 0 / 127 / 253),
-- 360 (full width).
-- ---------------------------------------------------------------------------
local C1, C2 = 0, 190                 -- the two columns
local T1, T2, T3 = 0, 127, 253        -- the three
local function Label(parent, x, y, text, size, c)
  local l = UI.gLabel(parent, text, size, c); l:SetPoint("TOPLEFT", x, -y)
  return l
end

-- A dropdown of fixed values. values = { {stored, label[, disabled]} } or a
-- function returning that.
local function Drop(parent, x, y, w, label, values, get, set)
  local lbl = label and Label(parent, x, y, label)
  local function list() return type(values) == "function" and values() or values end
  local d = UI.gDrop(parent, w,
    function()
      local cur = get()
      for _, v in ipairs(list()) do if v[1] == cur then return v[2] end end
      local first = list()[1]
      return first and first[2] or nil
    end,
    function()
      local out = {}
      for _, v in ipairs(list()) do out[#out + 1] = { value = v[1], label = v[2], disabled = v[3], font = v.font } end
      return out
    end,
    get, function(v) set(v) end)
  d:SetPoint("TOPLEFT", x, -(y + (label and 15 or 0)))
  d._label = lbl
  return d
end

-- The FONT dropdown: the kit's list, as Bars' (the owner, 2026-09-27: "it
-- should basically look like the dropdown menu"). Values are font paths, ""
-- for Default; a path the list no longer has shows as "Custom". Each name is
-- drawn in its own font (the owner, 2026-09-27: "fonts show as previews").
local function FontDrop(parent, x, y, w, get, set)
  local function values()
    local cur, o, found = get(), {}, false
    for _, it in ipairs(X.fontData()) do
      o[#o + 1] = { it.path and tostring(it.path) or "", it.name, font = it.path }
      if cur and it.path and tostring(it.path) == tostring(cur) then found = true end
    end
    if cur and not found then o[#o + 1] = { tostring(cur), "Custom" } end
    return o
  end
  return Drop(parent, x, y, w, "Font", values,
    function() local cur = get(); return cur and tostring(cur) or "" end,
    function(v) set((v ~= "") and v or nil) end)
end

-- A dropdown that opens one of GA's own pickers (texture, shape, sound).
-- getLabel returning nil reads "Choose".
local function PickerDrop(parent, x, y, w, label, getLabel, onClick)
  local lbl = label and Label(parent, x, y, label)
  local d = UI.gDrop(parent, w, getLabel, nil, nil, nil, { onClick = onClick })
  d:SetPoint("TOPLEFT", x, -(y + (label and 15 or 0)))
  d._label = lbl
  return d
end

local function Dial(parent, x, y, w, opts)
  opts.w = w
  local d = UI.gDial(parent, opts)
  d:SetPoint("TOPLEFT", x, -y)
  return d
end

local OFFON = { { false, "Off" }, { true, "On" } }
local function Switch(parent, x, y, w, label, choices, get, set)
  local lbl = label and Label(parent, x, y, label)
  local s = UI.gSwitch(parent, choices, get, set, { w = w })
  s:SetPoint("TOPLEFT", x, -(y + (label and 15 or 0)))
  s._label = lbl
  return s
end

local function Color(parent, x, y, w, label, opts)
  local lbl = label and Label(parent, x, y, label)
  opts.title = opts.title or label
  opts.w = w
  local c = UI.gColor(parent, opts)
  c:SetPoint("TOPLEFT", x, -(y + (label and 15 or 0)))
  c._label = lbl
  -- A color control dims its own label too when it is not in the shared rows.
  local se = c.setEnabled
  function c:setEnabled(on) se(self, on); if self._label then self._label:SetAlpha(on and 1 or UI.G_DIM) end end
  return c
end

-- A section's frame: 360 wide, its own height; parented by the Hub.
local function Section(parent, h)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(360, h)
  return f
end

-- ===========================================================================
-- THE SELECTOR (the mock's "gloomAuras, main selector", 240 × 480)
-- ===========================================================================
-- Under the wordmark (the Hub's), the list from y 52, 18 to a line: a group
-- header (the lime ▾, 4 on the name in Sansation Bold 12), 6 under it its auras
-- (the icon, 12, at x 20; 6 on the name in Sansation 10; the eye at x 206), then
-- "+ ADD NEW AURA" in Sansation Bold 10 lime; 20 between groups. The selected
-- aura's line is violet 30% across the whole window, 20 tall. New Aura and New
-- Group at the foot, 20 in from the sides and the bottom. The list scrolls by
-- whole lines when the window is too short for it.
-- ★ A GROUP is managed from its RIGHT-CLICK menu and REORDERED BY DRAGGING its
-- header; a plain click folds it. An AURA's right-click menu has Rename ·
-- Duplicate · Move to Group · Delete (the owner, 2026-09-27).
local LIST_TOP, LIST_ROW_H, LIST_GAP, LIST_FOOT = 52, 18, 20, 55
local listRows = {}

local function listRow(i)
  local r = listRows[i]
  if r then return r end
  r = CreateFrame("Button", nil, P.listClip)
  r:SetSize(200, LIST_ROW_H)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  -- the highlight spans the whole window (the mock's Rectangle 277), 1 above and below
  r.hl = r:CreateTexture(nil, "BACKGROUND"); r.hl:SetPoint("TOPLEFT", -20, 1); r.hl:SetPoint("BOTTOMRIGHT", 20, -1)
  r.hl:Hide()
  r.tri = r:CreateTexture(nil, "ARTWORK"); r.tri:SetTexture(UI.G_TRI); r.tri:SetSize(7, 6)
  r.tri:SetPoint("CENTER", r, "LEFT", 4, 0)
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(12, 12); r.icon:SetPoint("LEFT", 0, 0)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.name = UI.newText(r, FONT.sa, 10, COLOR.paper, "LEFT"); r.name:SetPoint("LEFT", 18, 0)
  r.name:SetWordWrap(false)
  -- The warning: an aura whose cooldown trigger points at a spell the Cooldown
  -- Manager has not bound reads READY forever and shows at every pull (Hub
  -- backlog item 6, "the silent yes"). The hover says what to do about it.
  r.warn = CreateFrame("Button", nil, r); r.warn:SetSize(12, 12)
  local wt = r.warn:CreateTexture(nil, "ARTWORK"); wt:SetAllPoints()
  wt:SetTexture(UI.G_WARN); wt:SetTexCoord(0, 12 / 16, 0, 12 / 16); UI.tint(wt, CORAL)
  UI.attachTip(r.warn, "Not in your Cooldown Manager", function() return r.warnText or "" end)
  -- The eye: on screen = lime, hidden = white at 40%. The selected aura counts as on screen.
  r.eye = CreateFrame("Button", nil, r); r.eye:SetSize(14, 14); r.eye:SetPoint("RIGHT", 0, 0)
  r.eye.t = r.eye:CreateTexture(nil, "ARTWORK"); r.eye.t:SetSize(14, 8.5); r.eye.t:SetPoint("CENTER", 0, 0)
  r.eye.t:SetTexture(UI.G_EYE); r.eye.t:SetTexCoord(0, 56 / 64, 0, 34 / 64)
  r.eye:SetScript("OnClick", function()
    if r.kind ~= "aura" then return end
    local cfg = DB() and DB()[r.id]; if not cfg then return end
    cfg.preview = (not cfg.preview) or nil
    if GA.Displays then GA.Displays:RefreshForced() end
    X.RefreshList()
  end)
  UI.attachTip(r.eye, "Show on screen", "Shows this aura on screen while the panel is open, so you can place it. It does not change whether the aura runs in play.")
  r:SetScript("OnEnter", function(self)
    if (self.kind == "aura" and self.id ~= Sel()) or self.kind == "add" then
      self.hl:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0.15); self.hl:Show()
    end
  end)
  r:SetScript("OnLeave", function(self) if not (self.kind == "aura" and self.id == Sel()) then self.hl:Hide() end end)
  r:SetScript("OnClick", function(self, button)
    if self.kind == "group" then
      if button == "RightButton" then P.groupContext(self.gid, self); return end
      local g = X.Groups() and X.Groups()[self.gid]
      if g then g.collapsed = (not g.collapsed) or nil; X.RefreshList() end
    elseif self.kind == "ungrouped" then
      GA.db.ungroupedCollapsed = (not GA.db.ungroupedCollapsed) or nil; X.RefreshList()
    elseif self.kind == "aura" then
      if button == "RightButton" then X.SetSelected(self.id); P.auraContext(self); return end
      X.SetSelected(self.id)
    elseif button == "LeftButton" and self.kind == "add" then P.newAuraMenu(self, self.gid) end
  end)
  r:SetScript("OnDoubleClick", function(self)
    if self.kind == "aura" and self.id then X.SetSelected(self.id); C:RenameSelected() end
  end)
  r:RegisterForDrag("LeftButton")
  r:SetScript("OnDragStart", function(self) if self.kind == "group" then P.groupDragStart(self) end end)
  r:SetScript("OnDragStop", function(self) if self.kind == "group" then P.groupDragStop(self) end end)
  listRows[i] = r
  return r
end

-- The list as typed lines: every group (header · auras · "+ ADD NEW AURA" · gap),
-- then Ungrouped the same way. With no groups at all it is a flat list and an
-- add line.
local function listEntries()
  local out = {}
  local groups = X.GroupList()
  for _, gid in ipairs(groups) do
    local g = X.Groups()[gid]
    out[#out + 1] = { kind = "group", gid = gid }
    if not g.collapsed then
      out[#out + 1] = { kind = "sub" }
      for _, id in ipairs(X.AurasInGroup(gid)) do out[#out + 1] = { kind = "aura", id = id } end
      out[#out + 1] = { kind = "add", gid = gid }
    end
    out[#out + 1] = { kind = "gap" }
  end
  local ung = X.AurasInGroup(nil)
  if #groups > 0 then
    out[#out + 1] = { kind = "ungrouped" }
    if not (GA.db and GA.db.ungroupedCollapsed) then
      out[#out + 1] = { kind = "sub" }
      for _, id in ipairs(ung) do out[#out + 1] = { kind = "aura", id = id } end
      out[#out + 1] = { kind = "add" }
    end
  else
    for _, id in ipairs(ung) do out[#out + 1] = { kind = "aura", id = id } end
    out[#out + 1] = { kind = "add" }
  end
  return out
end

-- "sub" is the mock's 6 between a group's header and its first aura.
local function entryH(e) return (e.kind == "gap" and LIST_GAP) or (e.kind == "sub" and 6) or LIST_ROW_H end

function P.renderList()
  if not P.listClip then return end
  local entries = listEntries()
  local total = 0
  for _, e in ipairs(entries) do total = total + entryH(e) end
  -- the list's height from the WINDOW's (the clip is anchored to it)
  local view = math.max(LIST_ROW_H, math.floor((P.listHost:GetHeight() or 0) - LIST_TOP - LIST_FOOT))
  -- Scrolled by whole lines; the bar only exists while there is more to see.
  local maxOff = 0
  do
    local h, n = total, 0
    while h > view and n < #entries do n = n + 1; h = h - entryH(entries[n]) end
    maxOff = n
  end
  P.listOffset = math.max(0, math.min(maxOff, P.listOffset or 0))
  local selID = Sel()
  local y, n = 0, 0
  for i = P.listOffset + 1, #entries do
    local e = entries[i]
    local h = entryH(e)
    if y + h > view then break end
    if e.kind ~= "gap" and e.kind ~= "sub" then
      n = n + 1
      local r = listRow(n)
      r.kind, r.id, r.gid = e.kind, e.id, e.gid
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", P.listClip, "TOPLEFT", 0, -y)
      r.tri:Hide(); r.icon:Hide(); r.warn:Hide(); r.eye:Hide(); r.hl:Hide()
      r.name:ClearAllPoints(); r.name:SetPoint("LEFT", 18, 0); r.name:SetWidth(0)
      r.name:SetAlpha(1); r:SetAlpha(1)
      if e.kind == "group" or e.kind == "ungrouped" then
        local g = e.gid and X.Groups()[e.gid]
        local collapsed = (e.kind == "group" and g and g.collapsed) or (e.kind == "ungrouped" and GA.db and GA.db.ungroupedCollapsed)
        r.tri:Show(); r.tri:SetRotation(collapsed and (math.pi / 2) or 0); UI.tint(r.tri, LIME)
        UI.setFont(r.name, FONT.saB, 12)
        r.name:ClearAllPoints(); r.name:SetPoint("LEFT", 12, 0)
        local txt = (e.kind == "group") and (g and g.name or "Group") or "Ungrouped"
        -- A group SHOWS what it is doing: "(off)" when its switch is off, a dot
        -- when it carries a load rule.
        if g and g.enabled == false then txt = txt .. "  |cff888888(off)|r"
        elseif g and g.visibility and next(g.visibility) ~= nil then txt = txt .. ("  |cff%s•|r"):format(LIME.hex) end
        r.name:SetText(txt); r.name:SetTextColor(1, 1, 1)
        if g and g.enabled == false then r.name:SetAlpha(0.5) end
        if P.dragGid and e.gid == P.dragGid then r:SetAlpha(0.4) end
      elseif e.kind == "aura" then
        local cfg = DB() and DB()[e.id]
        r.icon:Show(); r.icon:SetTexture(AuraIcon(cfg))
        local isSel = (e.id == selID)
        UI.setFont(r.name, FONT.sa, 10)
        r.name:SetText((cfg and cfg.label) or ("Spell " .. tostring(e.id))); r.name:SetTextColor(1, 1, 1)
        if isSel then r.hl:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0.3); r.hl:Show() end
        -- a disabled aura greys (Load Conditions → Disabled)
        if cfg and cfg.enabled == false then r.name:SetAlpha(0.5) end
        local warnText = cfg and C:SilentYesText(cfg)
        r.warnText = warnText
        -- Cap a name only when it is too long for the row: pinning every name to its
        -- own measured width lets rounding shave the last letter (or add a "…").
        local maxW = 200 - 14 - 18 - (warnText and 22 or 6)
        local w = math.ceil(r.name:GetStringWidth())
        if w > maxW then w = maxW; r.name:SetWidth(maxW) end
        if warnText then r.warn:ClearAllPoints(); r.warn:SetPoint("LEFT", 18 + w + 4, 0); r.warn:Show() end
        r.eye:Show()
        local on = isSel or (cfg and cfg.preview)
        if on then UI.tint(r.eye.t, LIME) else r.eye.t:SetVertexColor(1, 1, 1, 0.4) end
      elseif e.kind == "add" then
        UI.setFont(r.name, FONT.saB, 10)
        r.name:SetText("+ ADD NEW AURA"); r.name:SetTextColor(LIME.r, LIME.g, LIME.b)
      end
      r:Show()
    end
    y = y + h
  end
  for i = n + 1, #listRows do listRows[i]:Hide() end
  -- the list's bar (the settings windows' style: 3 wide, round)
  local track, thumb = P.listTrack, P.listThumb
  if maxOff > 0 then
    track:Show()
    local th = math.max(24, math.floor(view * view / total + 0.5))
    thumb:SetHeight(th)
    thumb:ClearAllPoints(); thumb:SetPoint("TOP", track, "TOP", 0, -math.floor((view - th) * (P.listOffset / maxOff) + 0.5))
  else
    track:Hide()
  end
  P.listMax = maxOff
end

-- The type menu behind New Aura and "+ ADD NEW AURA" (the latter files the new
-- aura straight into its group).
function P.newAuraMenu(anchor, gid)
  UI.gList(anchor, { { value = "icon", label = "Icon Aura" }, { value = "texture", label = "Texture Aura" },
                     { value = "bar", label = "Bar Aura" } }, nil,
    function(uiType)
      C:CreateAura(uiType)
      local cfg = Cfg()
      if cfg and gid then cfg.group = gid; X.RefreshList(); P.syncHeader() end
    end, { minW = 120 })
end

-- ---------------------------------------------------------------------------
-- A group's RIGHT-CLICK menu: Rename · Enable/Disable · Load Conditions… ·
-- Delete Group. (The kit's list, opened at the mouse.)
-- ---------------------------------------------------------------------------
function P.groupContext(gid, anchor)
  local g = gid and X.Groups() and X.Groups()[gid]; if not g then return end
  local off = (g.enabled == false)
  UI.gList(anchor, {
    { value = "rename", label = "Rename" },
    { value = "toggle", label = off and "Enable Group" or "Disable Group" },
    { value = "load", label = "Load Conditions…" },
    { value = "delete", label = "Delete Group", danger = true, divider = true },
  }, nil, function(v)
    local grp = X.Groups() and X.Groups()[gid]; if not grp then return end
    if v == "rename" then
      X.OpenNameDialog("Rename Group", grp.name or "", function(nm)
        if not nm or nm:gsub("%s", "") == "" then return end
        grp.name = nm; X.RefreshList(); P.syncHeader()
        if P.groupLoad and P.groupLoad.gid == gid then P.groupLoad:open(gid) end
      end)
    elseif v == "toggle" then
      -- NEVER `g.enabled = v and nil or false` — that is false both ways (the 2026-07-08 wall).
      if grp.enabled == false then grp.enabled = nil else grp.enabled = false end
      if GA.CDM then GA.CDM:Discover() end
      Poke(); X.RefreshList()
    elseif v == "load" then
      P.groupLoadWindow():open(gid)
    elseif v == "delete" then
      -- Deleting CONFIRMS (CONTRACTS §4); a group's auras are never deleted with it.
      C:OpenConfirm(("Delete the group \"%s\"?  Its auras aren't deleted — they move to Ungrouped."):format(grp.name or "?"), function()
        local gone = X.DeleteGroup(gid)
        if gone then GA.msg(("deleted group |cffffffff%s|r — its auras moved to Ungrouped."):format(gone)) end
        if P.groupLoad and P.groupLoad.gid == gid then P.groupLoad:Hide() end
        X.RefreshList(); P.syncHeader()
        Poke()
      end)
    end
  end, { cursor = true, minW = 150 })
end

-- ---------------------------------------------------------------------------
-- An AURA's actions (the owner, 2026-09-27: "Duplicate and Delete Auras should
-- be a dropdown-style menu that occurs on right-click on the aura name") — on the
-- tab's name and on its line in the list.
-- ---------------------------------------------------------------------------
function P.duplicateSelected()
  local id = Sel(); if not (id and DB() and DB()[id]) then return end
  local copy = X.DeepCopy(DB()[id]); copy.label = (copy.label or "Aura") .. " (copy)"
  local p = copy.point or { "CENTER", 0, 0 }; copy.point = { "CENTER", (p[2] or 0) + 24, (p[3] or 0) - 24 }
  local nid = X.NewDisplayID(); DB()[nid] = copy
  if GA.CDM then GA.CDM:Discover() end
  X.SetSelected(nid)
end
-- Deleting CONFIRMS (CONTRACTS §4).
function P.deleteSelected()
  local id, cfg = Sel(), Cfg(); if not (id and cfg) then return end
  C:OpenConfirm(("Delete the aura \"%s\"?  This can't be undone."):format(cfg.label or "this aura"), function()
    if not (DB() and DB()[id]) then return end
    DB()[id] = nil
    if GA.Displays and GA.Displays.frames[id] then GA.Displays.frames[id]:Hide() end
    if GA.CDM then GA.CDM:Discover() end
    X.SetSelected(X.DisplayList()[1])
  end)
end
-- Move the selected aura to another group (or out of every group, or into a new one).
function P.groupMenu(anchor)
  local cfg = Cfg(); if not cfg then return end
  local items = { { value = "__none", label = "Ungrouped" } }
  for _, gid in ipairs(X.GroupList()) do items[#items + 1] = { value = gid, label = GroupName(gid) } end
  items[#items + 1] = { value = "__new", label = "+ New Group…", divider = true }
  UI.gList(anchor, items, cfg.group or "__none", function(v)
    local cur = Cfg(); if not cur then return end
    if v == "__new" then
      X.OpenNameDialog("New Group", "", function(nm)
        if not nm or nm:gsub("%s", "") == "" then return end
        local gid = X.CreateGroup(nm); if gid then cur.group = gid; X.RefreshList(); P.syncHeader() end
      end)
    else
      cur.group = (v ~= "__none") and v or nil
      X.RefreshList(); P.syncHeader()
    end
  end, { cursor = true, minW = 160 })
end
-- The tab name's LEFT-click: every aura in the selector's order (groups first,
-- folded or not, then Ungrouped), a divider where a group starts, the one being
-- edited marked. Picking one selects it, exactly as clicking it in the list.
function P.auraSwitch(anchor)
  local db = DB(); if not db then return end
  local opts = {}
  local function add(ids)
    for i, id in ipairs(ids) do
      local cfg = db[id]
      opts[#opts + 1] = { value = id, label = (cfg and cfg.label) or ("Spell " .. tostring(id)), divider = (i == 1 and #opts > 0) }
    end
  end
  for _, gid in ipairs(X.GroupList()) do add(X.AurasInGroup(gid)) end
  add(X.AurasInGroup(nil))
  if #opts == 0 then return end
  UI.gList(anchor, opts, Sel(), function(id) X.SetSelected(id) end, { minW = 200 })
end
function P.auraContext(anchor)
  if not Cfg() then return end
  UI.gList(anchor, {
    { value = "rename", label = "Rename" },
    { value = "dup", label = "Duplicate Aura" },
    { value = "group", label = "Move to Group…" },
    { value = "delete", label = "Delete Aura", danger = true, divider = true },
  }, nil, function(v)
    if v == "rename" then C:RenameSelected()
    elseif v == "dup" then P.duplicateSelected()
    elseif v == "group" then P.groupMenu(anchor)
    elseif v == "delete" then P.deleteSelected() end
  end, { cursor = true, minW = 150 })
end

-- ---------------------------------------------------------------------------
-- Reordering groups by DRAG (the owner, 2026-09-25: "I want it to be a
-- click-drag to move"). A ghost of the header follows the cursor, a lilac line
-- shows where it will land, and letting go writes the new order.
-- ---------------------------------------------------------------------------
local function groupDrop()
  local _, cy = GetCursorPosition()
  cy = cy / P.listClip:GetEffectiveScale()
  local heads = {}
  for _, r in ipairs(listRows) do
    if r:IsShown() and r.kind == "group" and r.gid ~= P.dragGid then heads[#heads + 1] = r end
  end
  table.sort(heads, function(a, b) return (a:GetTop() or 0) > (b:GetTop() or 0) end)
  local above = 0
  for _, r in ipairs(heads) do
    if ((r:GetTop() or 0) + (r:GetBottom() or 0)) / 2 > cy then above = above + 1 end
  end
  return heads, above
end

function P.groupDragStart(row)
  P.dragGid = row.gid
  local gh = P.ghost
  if not gh then
    gh = CreateFrame("Frame", nil, UIParent); gh:SetFrameStrata("TOOLTIP"); gh:SetSize(200, LIST_ROW_H)
    local b = gh:CreateTexture(nil, "BACKGROUND"); b:SetAllPoints(); b:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0.5)
    gh.text = UI.newText(gh, FONT.saB, 12, COLOR.paper, "LEFT"); gh.text:SetPoint("LEFT", 12, 0)
    P.ghost = gh
    local line = P.listClip:CreateTexture(nil, "OVERLAY"); line:SetHeight(2)
    line:SetColorTexture(LILAC.r, LILAC.g, LILAC.b, 1); line:Hide()
    P.dropLine = line
  end
  gh:SetScale(row:GetEffectiveScale() / UIParent:GetEffectiveScale())
  gh.text:SetText(GroupName(row.gid))
  row:SetAlpha(0.4)
  gh:SetScript("OnUpdate", function(self)
    local x, y = GetCursorPosition(); local s = self:GetEffectiveScale()
    self:ClearAllPoints(); self:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x / s + 8, y / s)
    local heads, above = groupDrop()
    local line = P.dropLine
    line:ClearAllPoints()
    local nextHead = heads[above + 1]
    if nextHead then
      line:SetPoint("BOTTOMLEFT", nextHead, "TOPLEFT", 0, 2); line:SetPoint("BOTTOMRIGHT", nextHead, "TOPRIGHT", 0, 2)
    else
      local last
      for _, r in ipairs(listRows) do if r:IsShown() and (not last or (r:GetBottom() or 0) < (last:GetBottom() or 0)) then last = r end end
      if last then line:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -1); line:SetPoint("TOPRIGHT", last, "BOTTOMRIGHT", 0, -1) end
    end
    line:Show()
  end)
  gh:Show()
end

function P.groupDragStop()
  local gid = P.dragGid; P.dragGid = nil
  if P.ghost then P.ghost:Hide(); P.ghost:SetScript("OnUpdate", nil) end
  if P.dropLine then P.dropLine:Hide() end
  if not gid then return end
  local list, groups = X.GroupList(), X.Groups()
  local others = {}
  for _, id in ipairs(list) do if id ~= gid then others[#others + 1] = id end end
  -- Headers scrolled out of view above the list count as above the cursor.
  local heads, above = groupDrop()
  local hidden = 0
  if heads[1] then for i, id in ipairs(others) do if id == heads[1].gid then hidden = i - 1 end end
  else hidden = #others end
  table.insert(others, math.max(1, math.min(#others + 1, hidden + above + 1)), gid)
  for i, id in ipairs(others) do groups[id].order = i - 1 end
  X.RefreshList()
end

local function BuildSelector(c, api)
  local clip = CreateFrame("Frame", nil, c)
  clip:SetPoint("TOPLEFT", 20, -LIST_TOP); clip:SetPoint("BOTTOMRIGHT", -20, LIST_FOOT)
  P.listClip, P.listHost = clip, (api and api.window) or c
  clip:EnableMouseWheel(true)
  clip:SetScript("OnMouseWheel", function(_, d)
    P.listOffset = math.max(0, math.min(P.listMax or 0, (P.listOffset or 0) - d)); P.renderList()
  end)
  P.listHost:HookScript("OnSizeChanged", function() P.renderList() end)
  -- the scrollbar, in the window's right margin, only while the list overflows
  local track = CreateFrame("Frame", nil, c); track:SetWidth(3)
  track:SetPoint("TOPLEFT", c, "TOPLEFT", 230.5, -LIST_TOP); track:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 230.5, LIST_FOOT)
  local tt = track:CreateTexture(nil, "BACKGROUND"); tt:SetAllPoints(); tt:SetColorTexture(0, 0, 0, 0.5)
  local thumb = CreateFrame("Button", nil, track); thumb:SetWidth(3)
  local th = thumb:CreateTexture(nil, "ARTWORK"); th:SetAllPoints(); th:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0.5)
  track:Hide()
  P.listTrack, P.listThumb = track, thumb
  local dragging, startY, startOff = false, 0, 0
  thumb:SetScript("OnMouseDown", function(self)
    dragging = true; startOff = P.listOffset or 0
    local _, cy = GetCursorPosition(); startY = cy / self:GetEffectiveScale()
  end)
  thumb:SetScript("OnMouseUp", function() dragging = false end)
  thumb:SetScript("OnUpdate", function(self)
    if not dragging then return end
    if not IsMouseButtonDown("LeftButton") then dragging = false; return end
    local range = (clip:GetHeight() or 0) - self:GetHeight()
    if range <= 0 or (P.listMax or 0) <= 0 then return end
    local _, cy = GetCursorPosition()
    local want = math.floor(startOff + (startY - cy / self:GetEffectiveScale()) / range * P.listMax + 0.5)
    if want ~= P.listOffset then P.listOffset = math.max(0, math.min(P.listMax, want)); P.renderList() end
  end)

  local newA = UI.gButton(c, "New Aura")
  newA:SetPoint("BOTTOMLEFT", 20, 20)
  newA:SetScript("OnClick", function(self) P.newAuraMenu(self, nil) end)
  UI.attachTip(newA, "New aura", "Creates a blank aura and opens it for editing. Pick the kind: Icon, Texture or Bar.")
  local newG = UI.gButton(c, "New Group")
  newG:SetPoint("BOTTOMRIGHT", -20, 20)
  newG:SetScript("OnClick", function()
    X.OpenNameDialog("New Group", "", function(nm)
      if not nm or nm:gsub("%s", "") == "" then return end
      local gid = X.CreateGroup(nm)
      if gid then X.RefreshList() end
    end)
  end)
  UI.attachTip(newG, "New group", "Groups hold a set of auras that load together: one load rule and one on/off switch gate every aura inside. Right-click a group's name for its settings; drag it to move it.")
  P.renderList()
end

-- ===========================================================================
-- THE TAB (the mock's Frame 519/295): the aura's icon (16) at 20,6 and, 10 on,
-- its name in Sansation 12 lilac. Click the name for the list of auras (switch
-- to another — the owner, 2026-09-27: "not rename the current one"); right-click
-- it for the aura's menu. One tab per window (the settings window's and each
-- pop-out's), all kept in step.
-- ===========================================================================
local tabs = {}
function P.syncHeader()
  for _, t in ipairs(tabs) do t:refresh() end
end

local function BuildTab(tab)
  local t = {}
  local icon = tab:CreateTexture(nil, "ARTWORK"); icon:SetSize(16, 16); icon:SetPoint("TOPLEFT", 20, -6)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local name = UI.newText(tab, FONT.sa, 12, LILAC, "LEFT"); name:SetWordWrap(false)
  name:SetPoint("TOPLEFT", 46, -8); name:SetWidth(270)
  local hit = CreateFrame("Button", nil, tab); hit:SetHeight(16); hit:SetPoint("TOPLEFT", 46, -6)
  hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  hit:SetScript("OnClick", function(self, button)
    if not Cfg() then return end
    if button == "RightButton" then P.auraContext(self) else P.auraSwitch(self) end
  end)
  UI.attachTip(hit, "The aura you're editing", "Click to switch to another aura. Right-click to rename, duplicate, move or delete this one.")
  function t:refresh()
    local cfg = Cfg()
    if cfg then
      icon:SetTexture(AuraIcon(cfg)); icon:Show()
      name:SetText(cfg.label or "Aura"); name:SetAlpha(1)
    else
      icon:Hide(); name:SetText("No aura yet — click New Aura"); name:SetAlpha(0.6)
    end
    hit:SetWidth(math.max(10, math.min(270, name:GetStringWidth())))
  end
  tabs[#tabs + 1] = t
  return t
end

-- ===========================================================================
-- SECTION · AURA TRIGGERS (the mock's "gloomAuras, Aura Triggers")
-- ===========================================================================
-- Match All / Any / None at the top; 20 under them the conditions: a condition
-- is a 27-tall line of violet 20% — its spell (Sansation 10), the spell's icon,
-- "is", the state as a dropdown, the X at the right; a TRIGGER GROUP is a violet
-- 20% box with "Trigger Group" (Sansation Bold 12, lilac), its own Match
-- buttons and X on a line 10 in, then its conditions as darker lines 37 apart.
-- Add a Trigger and Create Trigger Group sit at the WINDOW's foot (the mock's
-- Footer Buttons) while the section is open.
--
-- ★ Grouping is by DRAG (the owner, 2026-09-23): make a group at any time, then
-- drag conditions into it — or back out onto the page. A group's X deletes the
-- GROUP only: its conditions drop back to the top level. The engine already
-- ignores an empty group, so one waiting to be filled never changes whether the
-- aura shows.
local TR = { rows = {}, groups = {} }
P.TR = TR
local TRIG_ROW_H, TRIG_TOP, TRIG_GAP, TRIG_W = 27, 35, 15, 360

-- "ACTIVE on Target (Debuff)" → "Active on Target (Debuff)": the mocks are
-- sentence case now.
local function StateText(state, k)
  local main, suf = X.TrigPill(state, k)
  main = main or "?"
  if main:upper() == main then main = main:sub(1, 1) .. main:sub(2):lower() end
  return main .. (suf or "")
end

local function StateDrop(parent, r)
  local d = CreateFrame("Button", nil, parent); d:SetHeight(15)
  d.fill = d:CreateTexture(nil, "BACKGROUND"); d.fill:SetAllPoints(); d.fill:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0)
  UI.gOutline(d, VIOLET)
  d.text = UI.newText(d, FONT.sa, 9, COLOR.paper, "LEFT"); d.text:SetPoint("LEFT", 4.5, -UI.G_NUDGE)
  d.tri = UI.gCaret(d); d.tri:SetPoint("RIGHT", -5.5, -0.5)
  function d:SetLabel(s) self.text:SetText(tostring(s or "")); self:SetWidth(math.ceil(self.text:GetStringWidth()) + 4.5 + 6 + 9 + 4.5) end
  d:SetScript("OnEnter", function(self) self.fill:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0.2) end)
  d:SetScript("OnLeave", function(self) self.fill:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0) end)
  d:SetScript("OnClick", function(self)
    local list = {}
    local node = r._node
    for _, st in ipairs(C:TrigStates(r._ti, r._ci)) do list[#list + 1] = { value = st, label = StateText(st, node and node.k) } end
    UI.gList(self, list, node and node.state, function(v) C:TrigSetState(r._ti, r._ci, v) end)
  end)
  UI.attachTip(d, "Condition", "What this condition checks for.")
  return d
end

local function MakeLeaf(parent, nested)
  local r = CreateFrame("Button", nil, parent); r:SetHeight(TRIG_ROW_H)
  r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
  if nested then r.bg:SetColorTexture(COLOR.deep.r, COLOR.deep.g, COLOR.deep.b, 0.75)
  else r.bg:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0.2) end
  local x0 = nested and 20 or 10
  r.name = UI.newText(r, FONT.sa, 10, COLOR.paper, "LEFT"); r.name:SetPoint("LEFT", x0, 0)
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(12, 12)
  r.icon:SetPoint("LEFT", r.name, "RIGHT", 4, 0); r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.is = UI.newText(r, FONT.sa, 10, COLOR.paper, "LEFT"); r.is:SetText("is"); r.is:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
  r.pill = StateDrop(r, r)
  r.pill:SetPoint("LEFT", r.is, "RIGHT", 4, 0)
  r.x = UI.gX(r, function() C:TrigRemove(r._ti, r._ci) end); r.x:SetPoint("RIGHT", nested and 0 or -10, 0)
  UI.attachTip(r.x, "Remove", "Removes this condition.")
  r:RegisterForDrag("LeftButton")
  r:SetScript("OnDragStart", function(self) P.trigDragStart(self) end)
  r:SetScript("OnDragStop", function(self) P.trigDragStop(self) end)
  return r
end

local function FillLeaf(r, ti, ci, leaf)
  r._ti, r._ci, r._node = ti, ci, leaf
  local sid = leaf.spellID
  r.name:SetText(leaf.name or (sid and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid)) or "?")
  r.icon:SetTexture((sid and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)) or 134400)
  r.pill:SetLabel(StateText(leaf.state, leaf.k))
  r:SetAlpha(1)
end

local LOGICS = { { "AND", "ALL" }, { "OR", "ANY" }, { "NONE", "NONE" } }

-- Match ALL / ANY / NONE, 10 apart from `x`.
local function MatchButtons(parent, onPick)
  local out, prev = {}, nil
  for i, lg in ipairs(LOGICS) do
    local b = UI.gButton(parent, "Match " .. lg[2])
    b._logic = lg[1]
    b:SetScript("OnClick", function() onPick(lg[1]) end)
    out[i] = b
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 10, 0) end
    prev = b
  end
  return out
end

local function MakeGroup(parent)
  local g = CreateFrame("Frame", nil, parent)
  g.bg = g:CreateTexture(nil, "BACKGROUND"); g.bg:SetAllPoints(); g.bg:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0.2)
  g.label = UI.newText(g, FONT.saB, 12, LILAC, "LEFT"); g.label:SetText("Trigger Group")
  g.label:SetPoint("LEFT", g, "TOPLEFT", 10, -21.5)
  g.x = UI.gX(g, function() P.dissolveGroup(g._ti) end)
  g.x:SetPoint("TOPRIGHT", -10, -10)
  UI.attachTip(g.x, "Delete group", "Deletes the group. Its conditions stay — they move back to the top level.")
  g.match = MatchButtons(g, function(logic)
    if not g._node then return end
    g._node.logic = logic
    if GA.CDM then GA.CDM:RefreshDisplays() end
    P.renderTriggers()
  end)
  g.match[1]:SetPoint("TOPLEFT", 93, -14)
  g.rows = {}
  return g
end

-- Delete a group but keep what was in it: its conditions take its place.
function P.dissolveGroup(ti)
  local t = C:TrigTree(); local g = t and ti and t.conditions[ti]
  if not (g and g.conditions) then return end
  table.remove(t.conditions, ti)
  for i, n in ipairs(g.conditions) do table.insert(t.conditions, ti + i - 1, n) end
  C:TrigRebind()
end

-- Dragging a condition: a ghost of it follows the cursor, the group under the
-- cursor lights up, and letting go files it there (or, off every group but on
-- the section, at the top level).
function P.trigDragStart(row)
  if not row._node then return end
  local gh = TR.ghost
  if not gh then
    gh = CreateFrame("Frame", nil, UIParent); gh:SetFrameStrata("TOOLTIP"); gh:SetSize(220, 25)
    local b = gh:CreateTexture(nil, "BACKGROUND"); b:SetAllPoints(); b:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0.5)
    gh.text = UI.newText(gh, FONT.sa, 10, COLOR.paper, "LEFT"); gh.text:SetPoint("LEFT", 12, 0)
    TR.ghost = gh
  end
  gh:SetScale(row:GetEffectiveScale() / UIParent:GetEffectiveScale())
  gh.text:SetText(row.name:GetText() or "")
  TR.dragging = { ti = row._ti, ci = row._ci, node = row._node, row = row }
  row:SetAlpha(0.4)
  gh:SetScript("OnUpdate", function(self)
    local x, y = GetCursorPosition(); local s = self:GetEffectiveScale()
    self:ClearAllPoints(); self:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x / s + 8, y / s)
    for _, g in ipairs(TR.groups) do
      if g:IsShown() then g.bg:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, g:IsMouseOver() and 0.4 or 0.2) end
    end
  end)
  gh:Show()
end

function P.trigDragStop()
  local d = TR.dragging; TR.dragging = nil
  if TR.ghost then TR.ghost:Hide() end
  if not d then return end
  local t = C:TrigTree(); if not t then P.renderTriggers(); return end
  local target
  for _, g in ipairs(TR.groups) do
    if g:IsShown() and g:IsMouseOver() then target = g._node end
  end
  local toTop = (not target) and TR.body:IsMouseOver()
  local from = d.ci and t.conditions[d.ti] or nil      -- the group it came out of, if any
  if (target and target == from) or (toTop and not from) or (not target and not toTop) then
    P.renderTriggers(); return                          -- dropped where it already was
  end
  if from then table.remove(from.conditions, d.ci) else table.remove(t.conditions, d.ti) end
  if target then table.insert(target.conditions, d.node) else table.insert(t.conditions, d.node) end
  if GA.CDM then GA.CDM:RefreshDisplays() end
  C:TrigRender()
end

function P.renderTriggers()
  local body = TR.body; if not body then return end
  local cfg = Cfg()
  local t = cfg and cfg.trigger                -- may be nil: viewing never creates one
  local logic = (t and t.logic) or "AND"
  for _, b in ipairs(TR.match) do b:SetSelected(b._logic == logic); b:SetEnabled(cfg ~= nil) end
  local conds = (t and t.conditions) or {}
  local y, nr, ng = 0, 0, 0
  for ti, node in ipairs(conds) do
    if node.conditions then
      ng = ng + 1
      local g = TR.groups[ng]; if not g then g = MakeGroup(body); TR.groups[ng] = g end
      g._ti, g._node = ti, node
      g.bg:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0.2)
      for _, b in ipairs(g.match) do b:SetSelected(b._logic == (node.logic or "AND")) end
      local gy = 43                               -- 10 padding + the 23 header + 10
      for ci, child in ipairs(node.conditions) do
        local r = g.rows[ci]; if not r then r = MakeLeaf(g, true); g.rows[ci] = r end
        FillLeaf(r, ti, ci, child)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 10, -gy); r:SetPoint("TOPRIGHT", -10, -gy); r:Show()
        gy = gy + TRIG_ROW_H + 10
      end
      for i = #node.conditions + 1, #g.rows do g.rows[i]:Hide() end
      local gh = gy
      g:ClearAllPoints(); g:SetPoint("TOPLEFT", 0, -y); g:SetSize(TRIG_W, gh); g:Show()
      y = y + gh + TRIG_GAP
    else
      nr = nr + 1
      local r = TR.rows[nr]; if not r then r = MakeLeaf(body, false); TR.rows[nr] = r end
      FillLeaf(r, ti, nil, node)
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetWidth(TRIG_W); r:Show()
      y = y + TRIG_ROW_H + TRIG_GAP
    end
  end
  for i = nr + 1, #TR.rows do TR.rows[i]:Hide() end
  for i = ng + 1, #TR.groups do TR.groups[i]:Hide() end
  if TR.addT then TR.addT:SetEnabled(cfg ~= nil); TR.addG:SetEnabled(cfg ~= nil) end
  local h = TRIG_TOP + math.max(16, y - TRIG_GAP)
  body:SetHeight(math.max(16, y - TRIG_GAP))
  if TR.sec and math.abs((TR.sec:GetHeight() or 0) - h) > 0.5 then TR.sec:SetHeight(h); Relayout() end
end

local function BuildTriggers(parent)
  local f = Section(parent, 100)
  TR.sec = f
  TR.match = MatchButtons(f, function(logic)
    local tr = C:TrigTree(); if not tr then return end
    tr.logic = logic
    if GA.CDM then GA.CDM:RefreshDisplays() end
    P.renderTriggers()
  end)
  TR.match[1]:SetPoint("TOPLEFT", 0, 0)
  local body = CreateFrame("Frame", nil, f)
  body:SetPoint("TOPLEFT", 0, -TRIG_TOP); body:SetSize(TRIG_W, 16)
  TR.body = body
  P.renderTriggers()
  return f
end

local function BuildTriggersFooter(parent)
  local f = CreateFrame("Frame", nil, parent); f:SetSize(360, 15)
  TR.addT = UI.gButton(f, "Add a Trigger")
  TR.addT:SetPoint("TOPLEFT", 0, 0)
  TR.addT:SetScript("OnClick", function() X.OpenPicker(function(item) C:TrigAddLeaf(item, nil) end) end)
  TR.addG = UI.gButton(f, "Create Trigger Group")
  TR.addG:SetPoint("TOPRIGHT", 0, 0)
  TR.addG:SetScript("OnClick", function() C:TrigAddGroup() end)
  UI.attachTip(TR.addG, "Trigger group", "Adds an empty group. Drag conditions into it; its own Match decides how they combine.")
  local on = Cfg() ~= nil
  TR.addT:SetEnabled(on); TR.addG:SetEnabled(on)
  return f
end

-- ===========================================================================
-- SECTION · APPEARANCE, POSITION & SIZE (the mock's Frame 530, 317 tall)
-- ===========================================================================
local function BuildAppearance(parent)
  local f = Section(parent, 317)

  -- Icon/Art: the texture — a file path or an icon ID — typed, or chosen. Blank
  -- means "the first trigger's icon". (A number typed here is stored as a
  -- number, which is what an ID is.)
  Label(f, C1, 0, "Icon/Art")
  local choose = UI.gButton(f, "Choose", { h = 16 })
  choose:SetPoint("TOPLEFT", C1 + 170 - choose:GetWidth(), -15)
  local tf = UI.gField(f, 170 - 4 - choose:GetWidth(), {
    placeholder = "Blank = the first trigger's icon",
    commit = function(txt)
      local c = Cfg(); if not c then return end
      local v = (txt or ""):match("^%s*(.-)%s*$")
      if v == "" then v = nil elseif tonumber(v) then v = tonumber(v) end
      if v ~= c.texture then c.texture = v; Reapply(); X.RefreshList(); P.syncHeader() end
    end,
    revert = function(self) self:refresh() end,
  })
  tf:SetPoint("TOPLEFT", C1, -15)
  function tf:refresh() local c = Cfg(); local v = c and c.texture; self:SetText(v ~= nil and tostring(v) or ""); self:SetCursorPosition(0) end
  add(tf)
  choose:SetScript("OnClick", function()
    local c = Cfg(); if not c then return end
    X.OpenTexturePicker(function(tex) c.texture = tex; Reapply(); P.sync(); X.RefreshList(); P.syncHeader() end, c.texture)
  end)
  add(choose)

  -- Shape: a STENCIL cut through that texture — it draws nothing itself, and it
  -- is what an animation traces. (Most shapes crop very little off an icon; see
  -- FINDINGS §14 before calling one broken.)
  add(PickerDrop(f, C2, 0, 170, "Shape/Silhouette",
    function()
      local c = Cfg(); local k = c and c.shape
      if not k then return nil end
      local info = GloomsHub.ShapeInfo and GloomsHub:ShapeInfo(k)
      return (info and info.label) or k
    end,
    function()
      local c = Cfg(); if not c then return end
      X.OpenShapePicker(function(key) c.shape = key; Reapply(); P.sync() end, c.shape)
    end))

  add(Dial(f, C1, 41, 170, { label = "Opacity", min = 0, max = 100, step = 1, unit = "%", dragPx = 500,
    get = function() local c = Cfg(); return c and math.floor(((c.alpha or 1) * 100) + 0.5) end,
    set = function(v) local c = Cfg(); if c then c.alpha = v / 100; Reapply() end end }))
  add(Drop(f, C2, 41, 170, "Blend Mode", X.BLEND_MODES,
    function() local c = Cfg(); return (c and c.blend) or "BLEND" end,
    function(v) local c = Cfg(); if c then c.blend = (v ~= "BLEND") and v or nil; Reapply() end end))

  add(Color(f, T1, 82, 107, "Recolor:", { title = "Recolor",
    get = function() local c = Cfg(); return c and c.color end,
    set = function(v) local c = Cfg(); if c then c.color = v; Reapply() end end }))
  add(Switch(f, T2, 82, 106, "Desaturate", OFFON,
    function() local c = Cfg(); return (c and c.desaturate) and true or false end,
    function(on) local c = Cfg(); if c then c.desaturate = on or nil; Reapply() end end))
  -- Effects only: no artwork, just the glow and the animation — for laying over
  -- a real action button. Distinct from a blank texture, which means "work it out".
  local eo = add(Switch(f, T3, 82, 107, "Effects Only", OFFON,
    function() local c = Cfg(); return (c and c.noArt) and true or false end,
    function(on) local c = Cfg(); if c then c.noArt = on or nil; Reapply(); P.sync() end end))
  UI.attachTip(eo, "Effects only", "The aura draws no artwork — just its glow and animation. For laying over a real action button.")

  -- POSITION (the left column)
  add(Dial(f, C1, 143, 170, { label = "Horizontal Offset", min = -2000, max = 2000, step = 1, unit = "px", dragPx = 1600,
    get = function() local c = Cfg(); return c and c.point and c.point[2] or 0 end,
    set = function(v) local c = Cfg(); if c then c.point = { "CENTER", v, (c.point and c.point[3]) or 0 }; Reapply() end end }))
  add(Dial(f, C1, 184, 170, { label = "Vertical Offset", min = -2000, max = 2000, step = 1, unit = "px", dragPx = 1600,
    get = function() local c = Cfg(); return c and c.point and c.point[3] or 0 end,
    set = function(v) local c = Cfg(); if c then c.point = { "CENTER", (c.point and c.point[2]) or 0, v }; Reapply() end end }))
  -- Fixed rotation, positive = clockwise; it shares one AnimationGroup with the
  -- spin (Effects section), so the angle is where a spin starts from.
  add(Dial(f, C1, 225, 170, { label = "Rotation", min = 0, max = 359, step = 1, unit = "°", dragPx = 720,
    get = function() local c = Cfg(); return (c and c.angle) or 0 end,
    set = function(v) local c = Cfg(); if c then c.angle = (v ~= 0) and v or nil; Reapply() end end }))

  -- SIZE (the right column). Width and height can be LINKED — the bracket
  -- joining their two boxes (the owner's design: white at 40% when free, lime
  -- when linked in these mocks; click it to switch).
  local wDial, hDial
  local function clampDim(n) return math.max(8, math.min(8192, math.floor(n + 0.5))) end
  wDial = add(Dial(f, C2, 143, 156, { label = "Width", min = 8, max = 8192, step = 1, unit = "px", dragPx = 4000,
    get = function() local c = Cfg(); return c and (c.width or c.size) or 64 end,
    set = function(v)
      local c = Cfg(); if not c then return end
      c.width = v
      if c.lockAspect then c.height = clampDim(v / (c.aspect or 1)); if hDial then hDial:refresh() end end
      Reapply()
    end }))
  hDial = add(Dial(f, C2, 184, 156, { label = "Height", min = 8, max = 8192, step = 1, unit = "px", dragPx = 4000,
    get = function() local c = Cfg(); return c and (c.height or c.size) or 64 end,
    set = function(v)
      local c = Cfg(); if not c then return end
      c.height = v
      if c.lockAspect then c.width = clampDim(v * (c.aspect or 1)); if wDial then wDial:refresh() end end
      Reapply()
    end }))
  -- The bracket: the mock's Frame 509, 10 wide at x 349, its arms level with
  -- the middles of the Width and Height boxes (18.5 and 66.5 down; 20.5 and
  -- 72.5 while labels were 12).
  local link = CreateFrame("Button", nil, f); link:SetSize(11, 70)
  link:SetPoint("TOPLEFT", 349, -143)
  local function seg(x, y, w, h) local t = link:CreateTexture(nil, "ARTWORK"); t:SetPoint("TOPLEFT", x, -y); t:SetSize(w, h); return t end
  local segs = { seg(0, 18, 10, 1), seg(9.5, 18, 1, 49), seg(0, 66, 10, 1) }
  function link:refresh()
    local c = Cfg(); local on = c and c.lockAspect
    for _, t in ipairs(segs) do
      if on then t:SetColorTexture(LIME.r, LIME.g, LIME.b, 1) else t:SetColorTexture(1, 1, 1, 0.4) end
    end
  end
  link:SetScript("OnClick", function(self)
    local c = Cfg(); if not c then return end
    local on = not c.lockAspect; c.lockAspect = on or nil
    if on then local w, h = (c.width or c.size or 64), (c.height or c.size or 64); c.aspect = (h > 0) and (w / h) or 1 end
    self:refresh()
  end)
  UI.attachTip(link, "Link width and height", "While linked, changing the width changes the height with it, and the other way round. Click to switch.")
  add(link)

  add(Drop(f, C1, 286, 170, "Strata", X.STRATA_MODES,
    function() local c = Cfg(); return (c and c.strata) or "HIGH" end,
    function(v) local c = Cfg(); if c then c.strata = (v ~= "HIGH") and v or nil; Reapply() end end))
  -- LEVEL (2026-09-23; Displays.lua applies it): 0 = Auto, the frame's own level.
  add(Dial(f, C2, 286, 170, { label = "Level", min = 0, max = 500, step = 1, dragPx = 1000,
    fmt = function(v) v = math.floor(v + 0.5); return v == 0 and "Auto" or tostring(v) end,
    get = function() local c = Cfg(); return (c and c.level) or 0 end,
    set = function(v) local c = Cfg(); if c then c.level = (v > 0) and v or nil; Reapply() end end }))
  return f
end

-- ===========================================================================
-- SECTION · BAR FILL & READOUTS (the mock's Frame 533, 419 tall)
-- ===========================================================================
-- Everything here only means something on a BAR aura; on any other it all dims.
-- ⚠ On 12.1 the fill of a duration bar is drawn by the ENGINE's own Blizzard
-- button (FINDINGS §1), so every change routes through ApplyConfig → the
-- engine's style push, which is only legal out of combat: an edit made in
-- combat lands when combat ends.
local function BuildBar(parent)
  local f = Section(parent, 419)
  local function get() local c = Cfg(); return c and c.bar end            -- reads never seed
  local function ensure() local c = Cfg(); if not c then return nil end; c.bar = c.bar or {}; return c.bar end
  local function repaint()
    Reapply()
    local id = Sel()
    if GA.Displays and GA.Displays.UpdateBar and id then GA.Displays:UpdateBar(id) end
  end
  local function isBar() local c = Cfg(); return c and c.kind == "bar" end
  local function mode() local b = get(); return (b and b.mode) or "aura_dur" end
  local function stacksOn() local b = get(); return isBar() and (b and b.showStacks) == true end
  local function timerOn() local b = get(); return isBar() and (b and b.showTimer) == true end

  local MODES = { { "aura_dur", "Aura Duration" }, { "cd_dur", "Cooldown" }, { "stacks", "Stack Count" } }
  add(Drop(f, C1, 0, 170, "Bar Type", MODES, mode, function(v)
    local b = ensure(); if not b then return end
    b.mode = v
    -- Leaving duration mode must RELEASE the engine's slot, or its button keeps
    -- painting a drain over a bar that now means something else.
    if GA.AuraDuration and Sel() then GA.AuraDuration:Detach(Sel()) end
    repaint(); P.sync()
  end), isBar)
  -- Changing the axis SWAPS width and height: a 220 × 24 bar stood on end is 24
  -- wide and 220 tall, which is what anyone means by it.
  local ORIENT = { { "HORIZONTAL", "Horizontal" }, { "VERTICAL", "Vertical" } }
  add(Drop(f, C2, 0, 170, "Orientation", ORIENT,
    function() local b = get(); return (b and b.orientation == "VERTICAL") and "VERTICAL" or "HORIZONTAL" end,
    function(v)
      local c = Cfg(); local b = ensure(); if not (b and c) then return end
      local wasVert, nowVert = (b.orientation == "VERTICAL"), (v == "VERTICAL")
      b.orientation = nowVert and "VERTICAL" or nil
      if wasVert ~= nowVert then c.width, c.height = (c.height or 24), (c.width or 220) end
      repaint(); P.sync()
    end), isBar)

  -- The fill texture (Shared Media bar textures only). RIGHT-CLICK clears it back
  -- to a plain color fill — the picker has no "none" row.
  local function texName(p)
    if type(p) ~= "string" or p == "" then return nil end
    return p:match("([^\\/]+)%.%w+$") or p:match("([^\\/]+)$") or p
  end
  local tex
  tex = add(PickerDrop(f, C1, 41, 170, "Bar Texture",
    function() local b = get(); return texName(b and b.texture) end,
    function(self, button)
      if button == "RightButton" then
        local b2 = ensure(); if b2 then b2.texture = nil; tex:refresh(); repaint() end
        return
      end
      if not get() and not ensure() then return end
      X.OpenTexturePicker(function(path)
        local b2 = ensure(); if not b2 then return end
        b2.texture = (type(path) == "string" and path ~= "") and path or nil
        tex:refresh(); repaint()
      end, (get() or {}).texture, "lsm")
    end), isBar)
  UI.attachTip(tex, "Bar texture", "Click to choose a fill texture. Right-click to go back to a plain color fill.")
  -- Rotate Texture: without it a gradient drawn for a horizontal bar stays
  -- horizontal when the bar is stood on end.
  add(Switch(f, C2, 41, 170, "Rotate Texture", OFFON,
    function() local b = get(); return (b and b.rotateTexture) == true end,
    function(on) local b = ensure(); if b then b.rotateTexture = on or nil; repaint() end end), isBar)

  local DIRS = { { "drain", "Drains Down" }, { "fill", "Fills Up" } }
  add(Drop(f, C1, 82, 170, "Bar Fill Direction", DIRS,
    function() local b = get(); return (b and b.fill == "fill") and "fill" or "drain" end,
    function(v) local b = ensure(); if b then b.fill = (v == "fill") and "fill" or nil; repaint() end end), isBar)
  add(Switch(f, C2, 82, 170, "Reverse Fill", OFFON,
    function() local b = get(); return (b and b.reverse) == true end,
    function(on) local b = ensure(); if b then b.reverse = on or nil; repaint() end end), isBar)
  local function colorAt(x, w, label, key)
    add(Color(f, x, 123, w, label, {
      get = function() local b = get(); return b and b[key] end,
      set = function(v) local b = ensure(); if b then b[key] = v; repaint() end end }), isBar)
  end
  colorAt(T1, 107, "Bar Fill Color", "color")
  colorAt(T2, 106, "Background Color", "bg")
  -- The BACKDROP turns this color while the DoT is in its pandemic window — the
  -- backdrop, not the fill: the fill is the engine's and cannot be recolored in
  -- combat (HANDOFF, 2026-09-19 — do not re-offer the fill).
  colorAt(T3, 107, "Pandemic Color", "pandemicBg")

  -- THE READOUTS — one font for both: two typefaces on one 22px bar would read
  -- as an accident.
  add(FontDrop(f, 0, 184, 238,
    function() local b = get(); return b and b.font end,
    function(path) local b2 = ensure(); if b2 then b2.font = path; repaint(); P.sync() end end), isBar)
  -- MAX STACKS — how many stacks make a FULL bar (with Max 6, three stacks is
  -- half a bar). The game does not tell an addon an aura's maximum, so it is set
  -- here. It only means something in Stack Count mode: dimmed otherwise.
  local mxl = Label(f, 258, 184, "Max Stacks")
  local mx = UI.gField(f, 102, { numeric = true,
    commit = function(s) local b = ensure(); local n = tonumber(s); if b and n then b.max = math.max(1, math.min(40, n)); repaint() end; P.sync() end,
    revert = function(self) self:refresh() end })
  mx:SetPoint("TOPLEFT", 258, -199)
  function mx:refresh() local b = get(); self:SetText(tostring((b and b.max) or 10)) end
  mx._label = mxl
  add(mx, function() return isBar() and mode() == "stacks" end)

  local ANCHORS = { { "CENTER", "Center" }, { "TOP", "Top" }, { "BOTTOM", "Bottom" }, { "LEFT", "Left" }, { "RIGHT", "Right" } }
  local function readout(y, label, showKey, colorKey, sizeKey, anchorKey, anchorDefault, gate)
    add(Switch(f, C1, y, 170, label, OFFON,
      function() local b = get(); return (b and b[showKey]) == true end,
      function(v) local b = ensure(); if b then b[showKey] = v or nil; repaint(); P.sync() end end), isBar)
    add(Color(f, C2, y, 170, "Text Color", { title = label .. " Color",
      get = function() local b = get(); return b and b[colorKey] end,
      set = function(v) local b = ensure(); if b then b[colorKey] = v; repaint() end end }), gate)
    add(Dial(f, C1, y + 41, 170, { label = label .. " Size", min = 8, max = 32, step = 1, unit = "px", dragPx = 300,
      get = function() local b = get(); return (b and b[sizeKey]) or 14 end,
      set = function(v) local b = ensure(); if b then b[sizeKey] = v; repaint() end end }), gate)
    add(Drop(f, C2, y + 41, 170, label .. " Position", ANCHORS,
      function() local b = get(); return (b and b[anchorKey]) or anchorDefault end,
      function(v) local b = ensure(); if b then b[anchorKey] = v; repaint() end end), gate)
  end
  -- Stacks default to TOP and the countdown to CENTER, so switched on together
  -- they never print on top of each other.
  readout(245, "Stack Text", "showStacks", "stackColor", "stackSize", "stackAnchor", "TOP", stacksOn)
  readout(347, "Countdown Text", "showTimer", "timerColor", "timerSize", "timerAnchor", "CENTER", timerOn)
  return f
end

-- ===========================================================================
-- SECTION · TEXT (the mock's Frame 536; 235 tall by the 10-label spacing — that
-- frame in the mock kept the 12-label rows)
-- ===========================================================================
-- The words an aura draws on screen (cfg.text) — NOT its name in the list.
-- Reads never create cfg.text; writes do.
local function BuildText(parent)
  local f = Section(parent, 235)
  local function txt() local c = Cfg(); return c and c.text end
  local function ensure() local c = Cfg(); if not c then return nil end
    if not c.text then c.text = { show = (c.showLabel ~= false) } end; return c.text end
  local function showing()
    local c = Cfg(); if not c then return false end
    if c.text then return c.text.show ~= false end
    return c.showLabel ~= false
  end

  add(Switch(f, 0, 0, 102, "Show Text", OFFON, showing,
    function(v) local t = ensure(); if t then t.show = v; Reapply(); P.sync() end end))
  local dfl = Label(f, 122, 0, "Displayed Text")
  local df = UI.gField(f, 238, { placeholder = "The aura's name",
    commit = function(s) local t = ensure(); if t then t.str = (s ~= "" and s) or nil; Reapply() end end,
    revert = function(self) self:refresh() end })
  df:SetPoint("TOPLEFT", 122, -15)
  df._label = dfl
  function df:refresh()
    local t, c = txt(), Cfg()
    self:SetText((t and t.str) or ""); self:SetCursorPosition(0)
    if self.placeholder then self.placeholder:SetText((c and c.label) or "The aura's name") end
  end
  -- Show Charge Count REPLACES these words, so while it is on they dim (the owner,
  -- 2026-09-27: with both on, the text "wasn't there" and nothing said why).
  local function countOn() local t = txt(); return (t and t.showCount) == true end
  add(df, function() return showing() and not countOn() end)

  add(Dial(f, C1, 61, 170, { label = "Font Size", min = 6, max = 300, step = 1, unit = "px", dragPx = 900,
    get = function() local t = txt(); return (t and t.size) or 14 end,
    set = function(v) local t = ensure(); if t then t.size = v; Reapply() end end }), showing)
  add(Dial(f, C2, 61, 170, { label = "Horizontal Offset", min = -400, max = 400, step = 1, unit = "px", dragPx = 800,
    get = function() local t = txt(); return (t and t.x) or 0 end,
    set = function(v) local t = ensure(); if t then t.x = (v ~= 0) and v or nil; Reapply() end end }), showing)
  add(Drop(f, C1, 102, 170, "Anchor", X.TE_ANCHOR,
    function() local t = txt(); return (t and t.anchor) or "BOTTOM" end,
    function(v) local t = ensure(); if t then t.anchor = (v ~= "BOTTOM") and v or nil; Reapply() end end), showing)
  add(Dial(f, C2, 102, 170, { label = "Vertical Offset", min = -400, max = 400, step = 1, unit = "px", dragPx = 800,
    get = function() local t = txt(); return (t and t.y) or 0 end,
    set = function(v) local t = ensure(); if t then t.y = (v ~= 0) and v or nil; Reapply() end end }), showing)

  add(FontDrop(f, C1, 163, 170,
    function() local t = txt(); return t and t.font end,
    function(path) local t2 = ensure(); if t2 then t2.font = path; Reapply(); P.sync() end end), showing)
  add(Color(f, C2, 163, 170, "Text Color", {
    get = function() local t = txt(); return t and t.color end,
    set = function(v) local t = ensure(); if t then t.color = v; Reapply() end end }), showing)
  add(Drop(f, C1, 204, 170, "Outline Type", X.TE_OUTLINE,
    function() local t = txt(); return (t and t.outline) or "OUTLINE" end,
    function(v) local t = ensure(); if t then t.outline = (v ~= "OUTLINE") and v or nil; Reapply() end end), showing)
  -- The live charge count, in place of the text — which is why turning it on
  -- also turns the text on.
  local cc = add(Switch(f, C2, 204, 170, "Show Charge Count", OFFON,
    function() local t = txt(); return (t and t.showCount) == true end,
    function(v) local t = ensure(); if t then t.showCount = v or nil; if v then t.show = true end; Reapply(); P.sync() end end))
  UI.attachTip(cc, "Show charge count", "Shows the spell's charges in place of the Displayed Text. A spell without charges shows nothing.")
  return f
end

-- ===========================================================================
-- SECTION · EFFECTS, MOTION & SOUND (the mock's Frame 540; 337 tall with two
-- animation rows by the 10-label spacing — that frame in the mock kept the 12-label rows)
-- ===========================================================================
local EF = { blocks = {} }
P.EF = EF

local function BuildEffects(parent)
  local f = Section(parent, 337)
  EF.sec = f
  local E = _G.GloomsHub and _G.GloomsHub.Effects

  -- ANIMATIONS — one of the Hub's eight shaped animations, and its own settings,
  -- built from the module's `params` schema so a module added in the Hub grows
  -- its controls here with no GA change. Numbers become dials, choices
  -- dropdowns, a color sits beside the type (its checkbox off = the module's
  -- own color). Fractional params show ×100 as a percentage. Only the chosen
  -- animation's settings show, two to a row under the type: every animation has
  -- different ones — so this block, and the section, grow and shrink with it.
  local ANIMS = { { "none", "None" } }
  if E then E:Each(function(m) ANIMS[#ANIMS + 1] = { m.id, m.label or m.id } end) end
  local function animID() local c = Cfg(); return (c and c.effects and c.effects.anim) or "none" end
  local at = add(Drop(f, C1, 0, 170, "Animation Type", ANIMS, animID, function(v)
    local c = Cfg(); if not c then return end
    c.effects = c.effects or {}; c.effects.anim = (v ~= "none") and v or nil
    Reapply(); P.layoutEffects(); P.sync()
  end))
  -- Every animation traces the aura's SHAPE; with none set there is nothing to
  -- draw and the engine skips it. Said, so it never looks broken.
  local need = UI.gLabel(f, "", 10, CORAL); need:SetPoint("TOPRIGHT", f, "TOPLEFT", 170, -1)
  need:SetJustifyH("RIGHT")

  -- The rest of the section is ONE frame that moves down as the animation's
  -- settings take rows.
  local rest = CreateFrame("Frame", nil, f); rest:SetSize(360, 194)
  EF.rest = rest

  local function block(id)
    if EF.blocks[id] then return EF.blocks[id] end
    local mod = E and E:Get(id); if not mod then return nil end
    local b = CreateFrame("Frame", nil, f); b:SetPoint("TOPLEFT", 0, 0); b:SetSize(360, 10)
    b.rows = {}
    local slot = 0            -- 0,1 = row 1's columns …; the color takes the slot beside the type
    local colorPlaced = false
    local function place() local x = (slot % 2 == 0) and C1 or C2; local y = 41 + math.floor(slot / 2) * 41; slot = slot + 1; return x, y end
    for _, p in ipairs(mod.params or {}) do
      local function set(v) local t = X.AnimParams(Cfg(), id); if t then t[p.key] = v end; Reapply() end
      local function get() return X.AnimGet(id, p.key) end
      if p.kind == "color" then
        -- the SAVED color only: unset = the module's own, shown as the dashed pill
        local function saved()
          local c = Cfg(); local s = c and c.effects and c.effects.params and c.effects.params[id]
          return s and s[p.key]
        end
        local d
        if not colorPlaced then
          colorPlaced = true
          d = Color(b, C2, 0, 170, "Animation Color", { title = p.label, get = saved, set = function(v) set(v) end })
        else
          local x, y = place()
          d = Color(b, x, y, 170, p.label, { title = p.label, get = saved, set = function(v) set(v) end })
        end
        b.rows[#b.rows + 1] = d
      elseif p.kind == "choice" then
        local vals = {}
        for _, ch in ipairs(p.choices or {}) do vals[#vals + 1] = { ch[1], ch[2] } end
        local x, y = place()
        b.rows[#b.rows + 1] = Drop(b, x, y, 170, p.label, vals, get, set)
      else
        -- "range" and "bispeed" are one dial each; a bispeed is a SIGNED speed in
        -- [-1, 1] (sign = direction, 0 = still), so it spans -100..100.
        local sc = (p.kind == "bispeed") and 100 or X.ParamScale(p)
        local lo, hi, st
        if p.kind == "bispeed" then lo, hi, st = -100, 100, 5
        else
          lo = math.floor((p.min or 0) * sc + 0.5); hi = math.floor((p.max or 1) * sc + 0.5)
          st = math.max(1, math.floor((p.step or 1) * sc + 0.5))
        end
        local x, y = place()
        local d = Dial(b, x, y, 170, { label = p.label, min = lo, max = hi, step = st, unit = (sc ~= 1) and "%" or "",
          dragPx = 400, get = function() return (get() or 0) * sc end, set = function(v) set(v / sc) end })
        if p.kind == "bispeed" then
          UI.attachTip(d.strip, p.label, ("−100%% = %s · 0 = still · +100%% = %s"):format(p.neg or "counter-clockwise", p.pos or "clockwise"))
        end
        b.rows[#b.rows + 1] = d
      end
    end
    -- An animation with no color of its own still shows the color spot, dimmed,
    -- so the section keeps the mock's shape.
    if not colorPlaced then
      local d = Color(b, C2, 0, 170, "Animation Color", { get = function() return nil end, set = function() end })
      d:setEnabled(false); b.fixedOff = d
    end
    b.extra = (slot > 0) and (math.ceil(slot / 2) * 41) or 0
    b:Hide()
    EF.blocks[id] = b
    return b
  end
  -- With None, the color spot is there and dimmed.
  local noneColor = Color(f, C2, 0, 170, "Animation Color", { get = function() return nil end, set = function() end })
  noneColor:setEnabled(false)

  -- GLOWS — the glow while the aura is on screen; Color off = the glow's own color.
  local GLOW = { { "none", "None" }, { "autocast", "Autocast Shine" }, { "pixel", "Pixel Glow" },
                 { "proc", "Proc Glow" }, { "button", "Action Button Glow" } }
  local function glowType() local c = Cfg(); return (c and c.glow and c.glow.type) or "none" end
  add(Drop(rest, C1, 0, 170, "Glow Type", GLOW, glowType, function(v)
    local c = Cfg(); if not c then return end
    c.glow = c.glow or {}; c.glow.type = (v ~= "none") and v or nil
    Reapply(); P.sync()
  end))
  add(Color(rest, C2, 0, 170, "Glow Color", { title = "Glow Color",
    get = function() local c = Cfg(); return c and c.glow and c.glow.customColor and c.glow.color end,
    set = function(v)
      local c = Cfg(); if not c then return end
      c.glow = c.glow or {}; c.glow.color = v; c.glow.customColor = (v ~= nil) or nil; Reapply()
    end }), function() return glowType() ~= "none" end)

  -- ROTATION — spins the aura's own artwork, so it needs one: a bar has none and
  -- "Effects Only" hides it on purpose. Dimmed then, rather than left looking live.
  local function rot() local c = Cfg(); return c and c.rotate end
  local function ensureRot() local c = Cfg(); if not c then return nil end; c.rotate = c.rotate or {}; return c.rotate end
  local function isIcon() local c = Cfg(); return c ~= nil and c.kind ~= "bar" and not c.noArt end
  local function spinning() local r = rot(); return isIcon() and r ~= nil and r.on == true end
  add(Switch(rest, C1, 61, 170, "Rotation", OFFON,
    function() local r = rot(); return isIcon() and (r and r.on) == true end,
    function(v) local r = ensureRot(); if r then r.on = v or nil; Reapply(); P.sync() end end), isIcon)
  -- A percentage: 100% = one turn every 3 seconds.
  add(Dial(rest, C2, 61, 170, { label = "Rotation Speed", min = 10, max = 500, step = 10, unit = "%", dragPx = 500,
    get = function() local r = rot(); return (r and r.speed) or 100 end,
    set = function(v) local r = ensureRot(); if r then r.speed = (v ~= 100) and v or nil; Reapply() end end }), spinning)
  add(Drop(rest, C1, 102, 170, "Rotation Direction", { { "cw", "Clockwise" }, { "ccw", "Counter-Clockwise" } },
    function() local r = rot(); return (r and r.dir) or "cw" end,
    function(v) local r = ensureRot(); if r then r.dir = (v ~= "cw") and v or nil; Reapply() end end), spinning)

  -- SOUNDS
  local function soundLabel() local c = Cfg(); return (c and c.sound and c.sound.name) or "None" end
  add(PickerDrop(rest, C1, 163, 127, "Sound Effect", soundLabel, function()
    local c = Cfg(); if not c then return end
    X.OpenSoundPicker(function(item)
      if item.file then c.sound = c.sound or {}; c.sound.file = item.file; c.sound.name = item.name; c.sound.channel = "Master"
      else c.sound = nil end
      P.sync()
    end, c.sound and c.sound.file)
  end))
  local play = UI.gButton(rest, "Play", { w = 39, h = 16 })
  play:SetPoint("TOPLEFT", 131, -178)
  play:SetScript("OnClick", function()
    local c = Cfg(); if c and c.sound and c.sound.file then pcall(PlaySoundFile, c.sound.file, c.sound.channel or "Master") end
  end)
  local function hasSound() local c = Cfg(); return c and c.sound ~= nil end
  add(play, hasSound)
  -- WHEN it plays. The CDM only sends the alerts a spell actually has, so a timing
  -- the spell never emits can never play: those grey out in the list — the
  -- PANDEMIC one only; the CDM's answer for the other two is unreliable (HANDOFF,
  -- 2026-08-03) and removing a working option is worse than offering a dead one.
  local function alertOff(v)
    if v ~= "pandemic" then return false end
    local c = Cfg()
    local sid = c and GA.CDM and GA.CDM.DisplaySpellID and GA.CDM:DisplaySpellID(c)
    if not (sid and GA.CDM.ValidAlerts) then return false end
    local ok = GA.CDM:ValidAlerts(sid)
    return (ok ~= nil) and (ok.pandemic == false) or false
  end
  local ON = { { "trigger", "When it triggers" }, { "ready", "When it comes off cooldown" },
               { "untrigger", "When it wears off" }, { "pandemic", "Pandemic window" } }
  add(Drop(rest, C2, 163, 170, "Sound Trigger",
    function() local out = {}; for _, v in ipairs(ON) do out[#out + 1] = { v[1], v[2], alertOff(v[1]) } end; return out end,
    function() local c = Cfg(); return (c and c.sound and c.sound.on) or "trigger" end,
    function(v) local c = Cfg(); if c and c.sound then c.sound.on = v; P.sync() end end), hasSound)
  -- A timing already SET to something impossible has to be said out loud.
  local warn = UI.gLabel(rest, "", 10, CORAL); warn:SetPoint("TOPLEFT", C2, -198); warn:SetWidth(170)
  warn:SetJustifyH("LEFT"); warn:SetWordWrap(true)
  EF.warn = warn
  rows[#rows + 1] = {
    refresh = function()
      local c = Cfg(); local cur = c and c.sound and c.sound.on or "trigger"
      local bad = c and c.sound and alertOff(cur)
      warn:SetText(bad and "This spell never sends that signal, so the sound can't play." or "")
    end,
    setEnabled = function() end,
  }

  function P.layoutEffects()
    local id = animID()
    for _, b in pairs(EF.blocks) do b:Hide() end
    local b = (id ~= "none") and block(id) or nil
    noneColor:SetShown(b == nil)
    local extra = 0
    if b then
      b:Show()
      local on = Cfg() ~= nil
      for _, r in ipairs(b.rows) do r:refresh(); r:setEnabled(on) end
      extra = b.extra
    end
    -- the Glow block starts 30 under the animation's last row
    rest:ClearAllPoints(); rest:SetPoint("TOPLEFT", 0, -(41 + extra + 20))
    local h = 41 + extra + 20 + 194
    if math.abs((f:GetHeight() or 0) - h) > 0.5 then f:SetHeight(h); Relayout() end
    local c = Cfg()
    need:SetText((b and c and not c.shape) and "Needs a Shape" or "")
  end
  rows[#rows + 1] = { refresh = function() P.layoutEffects() end, setEnabled = function() end }
  P.layoutEffects()
  return f
end

-- ===========================================================================
-- LOAD CONDITIONS (the mock's Frame 541, 395 tall) — built twice from one
-- implementation: for the selected AURA (cfg.visibility, its section) and for
-- a GROUP (group.visibility, in the window its right-click menu opens). Same
-- engine gate either way.
-- ===========================================================================
-- ★ The owner's rule (2026-09-23): a tick means "only while this is true"; a
-- box left clear means "doesn't matter"; ALL ticked conditions must hold at
-- once. The two PAIRS — In/Out of Combat, Has/No Target — and the specs read
-- as "any of these": tick both to not care, one to require it; the last one
-- can't be unticked, because then nothing could ever load. That is exactly the
-- model GA already stores (combat/target = "in"/"out"/nil, specs = a set or
-- nil), so nothing saved changes meaning.
local POWERS = {
  { "off", "Off" },
  { 7,  "Soul Shards" },   { 4,  "Combo Points" },   { 9,  "Holy Power" },
  { 12, "Chi" },           { 16, "Arcane Charges" }, { 19, "Essence" },
  { 5,  "Runes" },         { 6,  "Runic Power" },    { 8,  "Astral Power" },
  { 11, "Maelstrom" },     { 13, "Insanity" },       { 17, "Fury" },
  { 18, "Pain" },          { 0,  "Mana" },           { 1,  "Rage" },
  { 3,  "Energy" },        { 2,  "Focus" },
}
local OPS = { { "ge", "at least" }, { "le", "at most" }, { "eq", "exactly" } }

function P.buildLoad(p, o)
  local sink, target, noun = o.sink, o.target, o.noun or "Aura"
  local function put(ctrl, gate)
    sink[#sink + 1] = {
      refresh = function() if ctrl.refresh then ctrl:refresh() end end,
      setEnabled = function(_, on)
        local ok = on and (not gate or gate())
        if ctrl.setEnabled then ctrl:setEnabled(ok) else ctrl:SetEnabled(ok); ctrl:SetAlpha(ok and 1 or UI.G_DIM) end
        if ctrl._label then ctrl._label:SetAlpha(ok and 1 or UI.G_DIM) end
      end,
    }
    return ctrl
  end
  local function vis() local t = target(); return t and t.visibility end
  local function visW() local t = target(); if not t then return nil end; t.visibility = t.visibility or {}; return t.visibility end

  -- The master switch: NOT a "load when" — this aura (or group) at all.
  put(Switch(p, 0, 0, 360, "This " .. noun, { { true, "Enabled" }, { false, "Disabled" } },
    function() local t = target(); return not (t and t.enabled == false) end,
    function(v)
      local t = target(); if not t then return end
      -- NEVER `t.enabled = v and nil or false` — that is false both ways (the 2026-07-08 wall).
      if v then t.enabled = nil else t.enabled = false end
      if GA.CDM then GA.CDM:Discover() end
      Poke(); X.RefreshList()
    end))

  -- A checkbox row (the mock's Frame 366): 18 tall, 20 apart from y 51 (53 while
  -- labels were 12), the box 2 down, its label (Sansation 10) 10 right of it.
  local function at(b, x, i, y0) b:SetPoint("TOPLEFT", x, -((y0 or 51) + 2 + 20 * i)) end
  local function check(label, get, set) return UI.gCheck(p, label, get, set, 10) end
  -- a pair: `key` holds v1 (only the first), v2 (only the second) or nil (both)
  local function pair(x, i, label1, label2, key, v1, v2)
    local b1, b2
    local function st() local v = vis(); local cur = v and v[key]; return (cur == nil or cur == v1), (cur == nil or cur == v2) end
    local function write(a, b)
      if not a and not b then return end
      local w = visW(); if not w then return end
      w[key] = (a and b) and nil or (a and v1 or v2)
      Poke(); b1:refresh(); b2:refresh()
    end
    b1 = put(check(label1, function() local a = st(); return a end, function(on) local _, b = st(); write(on, b) end))
    b2 = put(check(label2, function() local _, b = st(); return b end, function(on) local a = st(); write(a, on) end))
    at(b1, x, i); at(b2, x, i + 1)
  end
  local function single(x, i, label, key)
    at(put(check(label, function() local v = vis(); return v and v[key] end,
      function(on) local w = visW(); if w then w[key] = on or nil; Poke() end end)), x, i)
  end
  local L, R = 0, 139
  pair(L, 0, "In Combat", "Out of Combat", "combat", "in", "out")
  single(L, 2, "While Casting", "casting")
  single(L, 3, "While Mounted", "mounted")
  single(L, 4, "In Vehicle", "vehicle")
  single(L, 5, "In Instance", "instance")
  single(L, 6, "In Boss Encounter", "encounter")
  single(L, 7, "Resting", "resting")
  pair(R, 0, "No Target", "Has Target", "target", "none", "has")
  single(R, 2, "Stealthed", "stealthed")
  single(R, 3, "In a Group", "group")
  single(R, 4, "In a Raid", "raid")
  single(R, 5, "In War Mode", "warmode")
  single(R, 6, "Alive", "alive")

  -- The class's specs (the mock's Frame 372): 18 apart from y 229.
  local specs = X.PlayerSpecs()
  local sboxes = {}
  local function specOn(id) local v = vis(); return (not (v and v.specs)) or (v.specs[id] and true or false) end
  for i, sp in ipairs(specs) do
    local b = put(check(sp.name, function() return specOn(sp.id) end, function(on)
      local keep, n = {}, 0
      for _, s2 in ipairs(specs) do
        local want = (s2.id == sp.id) and on or ((s2.id ~= sp.id) and specOn(s2.id))
        if want then keep[s2.id] = true; n = n + 1 end
      end
      if n == 0 then return end                         -- the last one stays ticked
      local w = visW(); if not w then return end
      w.specs = (n < #specs) and keep or nil
      Poke()
      for _, o2 in ipairs(sboxes) do o2:refresh() end
    end))
    b:SetPoint("TOPLEFT", L, -(231 + 18 * (i - 1)))
    sboxes[#sboxes + 1] = b
  end
  local specH = math.max(3, #specs) * 18

  -- SPELL / TALENT KNOWN — a spell ID; talents count. Commits on Enter and on
  -- losing focus (item 7's lesson: Enter-only left a stale value behind).
  local y0 = 229 + specH + 20
  Label(p, 0, y0, "Spell/Talent Known")
  local help = UI.gLabel(p, "", 10); help:SetPoint("TOPLEFT", 0, -(y0 + 35)); help:SetAlpha(0.4)
  local function helpText()
    local v = vis(); local id = v and v.spellKnown
    if id then
      local nm = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
      help:SetText(((nm or ("Spell " .. id)) .. " — " .. noun .. " Enabled Only If Known"))
    else
      help:SetText("A spell ID (talents count). Blank = don't check.")
    end
  end
  local sk = UI.gField(p, 360, { numeric = true,
    commit = function(s)
      local w = visW(); if not w then return end
      local id = tonumber(s)
      if id ~= w.spellKnown then w.spellKnown = id; helpText(); Poke() end
    end,
    revert = function(self) self:refresh() end })
  sk:SetPoint("TOPLEFT", 0, -(y0 + 15))
  function sk:refresh() local v = vis(); self:SetText(v and v.spellKnown and tostring(v.spellKnown) or ""); helpText() end
  put(sk)

  -- PLAYER POWER — whole units (UnitPower's fragments are a different scale and
  -- a different question). The type seeds the rule; Off removes it.
  local y1 = y0 + 56
  local pwVal
  put(Drop(p, 0, y1, 149, "Player Power", POWERS,
    function() local v = vis(); return (v and v.power and v.power.type) or "off" end,
    function(x)
      local v = visW(); if not v then return end
      if x == "off" then v.power = nil
      else
        v.power = v.power or {}
        v.power.type = x; v.power.op = v.power.op or "ge"; v.power.value = v.power.value or 1
      end
      Poke(); if pwVal then pwVal:refresh() end
      P.sync(); if C._grows then for _, r in ipairs(C._grows) do r:refresh(); r:setEnabled(true) end end
    end))
  local function hasPower() local v = vis(); return v and v.power and v.power.type ~= nil end
  put(Drop(p, 159, y1 + 15, 130, nil, OPS,
    function() local v = vis(); return (v and v.power and v.power.op) or "ge" end,
    function(x) local v = visW(); if v and v.power then v.power.op = x; Poke() end end), hasPower)
  pwVal = UI.gField(p, 60, { numeric = true, justify = "CENTER",
    commit = function(s) local v = visW(); if v and v.power then v.power.value = tonumber(s) or 0; Poke() end end,
    revert = function(self) self:refresh() end })
  pwVal:SetPoint("TOPLEFT", 300, -(y1 + 15))
  pwVal:SetTextInsets(0, 0)
  function pwVal:refresh() local v = vis(); self:SetText(v and v.power and v.power.value and tostring(v.power.value) or "") end
  put(pwVal, hasPower)
  return y1 + 31
end

local function BuildLoad(parent)
  local f = Section(parent, 395)
  local h = P.buildLoad(f, { sink = rows, target = Cfg, noun = "Aura" })
  f:SetHeight(h)
  return f
end

-- The GROUP's load conditions, in a window of their own (its right-click menu's
-- "Load Conditions…"). Not mocked: the settings window's look, the section's
-- layout, "<group> — Load Conditions" as its title.
function P.groupLoadWindow()
  if P.groupLoad then return P.groupLoad end
  local root = GloomsHub.SuiteRoot and GloomsHub:SuiteRoot() or UIParent
  local w
  w = UI.gWindow({ parent = root, w = 400, h = 480, minH = 160,
    onFocus = function(self) if GloomsHub.SuiteManage then GloomsHub:SuiteManage(self) end end })
  local sa = UI.gScrollArea(w.content)
  local title = UI.gTitle(sa.child, "", 14); title:SetPoint("TOPLEFT", 20, -24)
  local body = CreateFrame("Frame", nil, sa.child); body:SetPoint("TOPLEFT", 20, -58); body:SetSize(360, 400)
  local function grp() local gid = w.gid; return gid and X.Groups() and X.Groups()[gid] end
  C._grows = C._grows or {}
  local h = P.buildLoad(body, { sink = C._grows, target = grp, noun = "Group" })
  local note = UI.gLabel(body, "These gate every aura in the group, ahead of each aura's own conditions.", 10)
  note:SetPoint("TOPLEFT", 0, -(h + 12)); note:SetWidth(360); note:SetWordWrap(true); note:SetAlpha(0.6)
  body:SetHeight(h + 30)
  sa:SetContentHeight(58 + h + 30 + 30)
  function w:open(gid)
    self.gid = gid
    title:SetText(GroupName(gid) .. " — Load Conditions")
    for _, r in ipairs(C._grows) do r:refresh(); r:setEnabled(true) end
    local set = GloomsHub:SuiteWindow("auras", "set")
    if not self._placed and set and set:GetRight() then
      self._placed = true
      self:ClearAllPoints(); self:SetPoint("TOPLEFT", set, "TOPRIGHT", 20, 0); UI.gSnap(self)
    end
    self:Show()
    if GloomsHub.SuiteManage then GloomsHub:SuiteManage(self) end
  end
  w:SetScript("OnHide", function(self) self.gid = nil end)
  w:Hide()
  P.groupLoad = w
  return w
end

-- ===========================================================================
-- Refreshing, and the old editor's hooks
-- ===========================================================================
function P.show()
  P.renderList()
  P.syncHeader()
  P.renderTriggers()
  if P.layoutEffects then P.layoutEffects() end
end

-- The previous editors' callers find these instead.
function C:AccordionLayout() end
function C:AccordionSetHeight() end
function C:AccordionOpen() end
function C:AccordionToggle() end
function C:TrigInlineRender() P.renderTriggers() end
function C:ShowGroupPane() end
function C:UpdateEmptyState() P.syncHeader() end
function C:SyncRailButtons() P.syncHeader() end
function C:RefreshGroupButton() P.syncHeader() end
function C:OnListRefresh() P.renderList(); P.syncHeader() end
function C:RefreshGroupPane()
  for _, r in ipairs(C._grows or {}) do r:refresh(); r:setEnabled(true) end
  P.syncHeader()
end
-- Anything that still asks to SELECT a group gets its load conditions instead.
function C:SelectGroup(gid)
  if gid and X.Groups() and X.Groups()[gid] then P.groupLoadWindow():open(gid) end
end
-- C:OnProfileSwitched re-syncs "Hide Blizzard CDM" this way (it lives in Global
-- Settings now).
C._hideCDM = { Set = function() GloomsHub:RefreshWindows("auras") end }

-- The profile api Global Settings shows (same as every profile control).
local function nameErr(why) return (why == "exists") and "A profile with that name already exists." or "Enter a profile name." end
local PROFILE = {
  noun   = "profile",
  names  = function() return GA:ProfileNames() end,
  active = function() return GA:ActiveProfileName() or "?" end,
  switch = function(v) if v ~= GA:ActiveProfileName() then GA:SwitchProfile(v) end end,
  users  = function(name)
    local o = {}
    for char, p in pairs((GA.global and GA.global.profileKeys) or {}) do if p == name then o[#o + 1] = char end end
    return o
  end,
  create = function(name) local ok, why = GA:CreateProfile(name); if ok then return true end; return false, nameErr(why) end,
  copy   = function(name) local ok, why = GA:CopyProfile(name); if ok then return true end; return false, nameErr(why) end,
  rename = function(name) local ok, why = GA:RenameActiveProfile(name); if ok then return true end; return false, nameErr(why) end,
  delete = function()
    if #GA:ProfileNames() <= 1 then return false, "Can't delete your only profile." end
    local active = GA:ActiveProfileName()
    if not GA:DeleteProfile(active) then return false, "" end
    GA.msg(("deleted profile |cffffffff%s|r."):format(active))
    return true
  end,
  tips = {
    dropdown = "The active profile. Each character defaults to its own.",
    new      = "Creates a profile and switches to it.",
    copy     = "Duplicates this profile — every aura and group — and switches to the copy.",
    rename   = "Renames this profile. Characters using it follow the new name.",
    delete   = "Deletes this profile (you'll be asked to confirm). Your only profile can't be deleted.",
  },
}

GloomsHub:RegisterTab{
  id       = "auras",
  title    = "Auras",
  wordmark = "AURAS",
  product  = "GloomAuras",
  order    = 10,
  windows  = true,
  profile  = PROFILE,
  selector = { build = BuildSelector },
  tab      = { w = 340, build = BuildTab },
  sections = {
    { id = "triggers",   title = "Aura Triggers",               build = BuildTriggers, footer = BuildTriggersFooter,
      onShow = function() P.renderTriggers() end },
    { id = "appearance", title = "Appearance, Position & Size", build = BuildAppearance },
    { id = "bar",        title = "Bar Fill & Readouts",         build = BuildBar },
    { id = "text",       title = "Text",                        build = BuildText },
    { id = "effects",    title = "Effects, Motion & Sound",     build = BuildEffects,
      onShow = function() if P.layoutEffects then P.layoutEffects() end end },
    { id = "load",       title = "Aura Load Conditions",        build = BuildLoad },
  },
  -- HIDE BLIZZARD CDM — a PROFILE setting, in Global Settings. Drives the
  -- viewer's alpha only, never Hide(), so GA's mirror keeps working.
  globals  = {
    { label = "Hide Blizzard CDM", choices = { { true, "Yes" }, { false, "No" } },
      get = function() return (GA.db and GA.db.hideBlizzardCDM) and true or false end,
      set = function(on) if GA.CDM and GA.CDM.ToggleBlizzardHide then GA.CDM:ToggleBlizzardHide(on) end end,
      tip = "Hides Blizzard's own cooldown bars while Gloom's Auras reads them. For this profile." },
  },
  onBuilt  = function(sel, set) X.SetContainer(set) end,
  onOpen   = function()
    if GA.Displays then GA.Displays.forced = true; GA.Displays:SetInteractive(true) end
    C:SelectInitial()   -- straight into the last-edited aura
    P.show()
  end,
  onClose  = function()
    X.CloseSubWindows()   -- a docked picker must not linger
    if P.groupLoad then P.groupLoad:Hide() end
    if GA.Displays then GA.Displays.forced = false; GA.Displays:SetSelectedDisplay(nil) end
    if GA.CDM and GA.CDM.Discover then GA.CDM:Discover() end
  end,
}
