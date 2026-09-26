-- ============================================================
-- Pages.lua — Gloom's Auras
-- The Auras tab, THIRD redesign ("Glass", 2026-09-25), from the owner's six
-- Figma screens "Glass Auras, …" on the page "GloomSuite UI 2":
--   769:15294 Aura Triggers · 774:16482 Appearance, Position & Size ·
--   775:17583 Bar Fill & Readouts · 775:18435 Text ·
--   776:19400 Effects, Motion & Sound · 776:19944 Aura Load Conditions
--
-- The Suite window draws the top bar (tool switcher, profile row, close), the
-- six page buttons, UI Scale, and each page's GLASS — the owner's own export of
-- the page's background with its glass panels baked in (Media/glass/*.png).
-- This file draws everything that sits ON the glass: the Aura Groups panel,
-- the aura header, "Hide Blizzard CDM", and one page at a time.
-- ★ The container is the WHOLE window, so every number below is the mock's own
-- window coordinate (the owner: "I put things where they are for a reason").
-- The panels are baked, so nothing may grow past one: a list that can run long
-- (the aura list, the triggers) scrolls INSIDE its panel.
--
-- It is DRAWING only. Every setting still goes through Config.lua's logic —
-- the trigger tree, the pickers, selection, profiles — exported as C.X. The old
-- editor's section builders in Config.lua are no longer mounted; they are kept
-- as the record of how each control behaves until this one is approved.
--
-- ⚠ Every widget here is the Hub's GLASS KIT (LibGloomSkin MINOR 14).
-- ============================================================

local GA = GloomsAuras
local C = GA and GA.Config
local X = C and C.X
-- ⚠ Not `LibStub and LibStub(...)`: an `and` keeps only the call's FIRST value,
-- so the version number would always come back nil.
local Skin, skinMinor
if LibStub then Skin, skinMinor = LibStub("LibGloomSkin-1.0", true) end
if not (X and Skin) then return end
if (skinMinor or 0) < 14 then
  print("|cffff5555Gloom's Auras|r: the Auras pages need Gloom's Hub with LibGloomSkin 14 or newer — update Gloom's Hub.")
  return
end

local UI, COLOR, FONT = Skin.UI, Skin.COLOR, Skin.FONT
local MEDIA = GA.MEDIA
local VIOLET, LILAC, LIME, CORAL = COLOR.violet, COLOR.lilac, COLOR.lime, COLOR.coral
local DB, Cfg, rows = X.DB, X.Cfg, X.rows
local GLASS = MEDIA .. "glass\\"

-- The Aura Groups panel's list (the mock's Frame 436, below its title).
local LIST_X, LIST_W, LIST_TOP, LIST_BOTTOM = 50, 210, 338, 646
local LIST_ROW_H, LIST_GAP = 18, 20
-- The triggers (inside the Aura Triggers panel, between its title row and its
-- two buttons).
local TRIG_X, TRIG_Y, TRIG_W, TRIG_BOTTOM = 340, 236, 670, 654

local P = { pages = {}, cur = "triggers", listOffset = 0 }
C.P = P

local function Sel() return X.Selected() end
local function Reapply() X.ReapplySelected() end
local function Poke()
  if GA.CDM then GA.CDM:UpdateVisibilityPoll(); GA.CDM:RefreshDisplays() end
end

-- One refresh for everything: what SetSelected already does to the shared rows.
-- Called after any change that another control's enabled state depends on.
function P.sync()
  local on = Cfg() ~= nil
  for _, r in ipairs(rows) do
    if r.refresh then r:refresh() end
    if r.setEnabled then r:setEnabled(on) end
  end
end

-- A row for the shared list: `ctrl` is a glass-kit control (it has refresh /
-- setEnabled); `gate` (optional) is an extra condition for being usable. A
-- control that is not usable DIMS to 50% — never hides (the suite's rule).
local function add(ctrl, gate)
  local r = {}
  function r:refresh() if ctrl.refresh then ctrl:refresh() end end
  function r:setEnabled(on)
    local ok = on and (not gate or gate())
    if ctrl.setEnabled then ctrl:setEnabled(ok)
    elseif ctrl.SetEnabled then ctrl:SetEnabled(ok); ctrl:SetAlpha(ok and 1 or 0.5) end
    -- a control's label dims with it (the mock's greyed Countdown column)
    if ctrl._label then ctrl._label:SetAlpha(ok and 1 or 0.5) end
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
-- The mocks' labelled controls. Every one is a Saira 12 label at (x, y) and its
-- control 23 below — the mocks' 19-tall label line plus a 4px gap.
-- ---------------------------------------------------------------------------
local function Label(parent, x, y, text, size, c)
  local l = UI.gLabel(parent, text, size or 12, c); l:SetPoint("TOPLEFT", x, -y)
  return l
end

local function Title(parent, x, y, text, size)
  local t = UI.gTitle(parent, text, size); t:SetPoint("TOPLEFT", x, -y)
  return t
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
      for _, v in ipairs(list()) do out[#out + 1] = { value = v[1], label = v[2], disabled = v[3] } end
      return out
    end,
    get, function(v) set(v) end)
  d:SetPoint("TOPLEFT", x, -(y + (label and 23 or 0)))
  d._label = lbl
  return d
end

-- A dropdown that opens one of GA's own pickers (texture, shape, font, sound).
-- getLabel returning nil reads CHOOSE.
local function PickerDrop(parent, x, y, w, label, getLabel, onClick)
  local lbl = label and Label(parent, x, y, label)
  local d = UI.gDrop(parent, w, getLabel, nil, nil, nil, { onClick = onClick })
  d:SetPoint("TOPLEFT", x, -(y + (label and 23 or 0)))
  d._label = lbl
  return d
end

local function Dial(parent, x, y, opts)
  local d = UI.gDial(parent, opts)
  d:SetPoint("TOPLEFT", x, -y)
  return d
end

local OFFON = { { false, "OFF" }, { true, "ON" } }
local function Switch(parent, x, y, label, choices, get, set)
  local lbl = label and Label(parent, x, y, label)
  local s = UI.gSwitch(parent, choices, get, set)
  s:SetPoint("TOPLEFT", x, -(y + (label and 23 or 0)))
  s._label = lbl
  return s
end

local function Color(parent, x, y, label, opts)
  local lbl = label and Label(parent, x, y, label)
  opts.title = opts.title or label
  local c = UI.gColor(parent, opts)
  c:SetPoint("TOPLEFT", x, -(y + (label and 23 or 0)))
  c._label = lbl
  -- A colour control dims its own label too when it is not in the shared rows.
  local se = c.setEnabled
  function c:setEnabled(on) se(self, on); if self._label then self._label:SetAlpha(on and 1 or 0.5) end end
  return c
end

-- A page: a frame over the whole window, shown one at a time.
local function Page(id)
  local f = CreateFrame("Frame", nil, P.c)
  f:SetAllPoints(); f:Hide()
  P.pages[id] = f
  return f
end

-- ===========================================================================
-- THE AURA GROUPS PANEL (the mock's "Aura Groups Box", 30,284, 250 × 418)
-- ===========================================================================
-- "Aura Groups" in Michroma 14 at 50,304; then the list, 18 to a line: a group
-- header (the lime ▾, the name in Saira Bold 12 at x 68), its auras (the icon at
-- x 50, the name in Saira 11 at x 68 — the selected one Bold in lilac — a coral
-- warning triangle after the name when the aura needs one, the eye at x 246),
-- then "+ ADD NEW AURA" in lime; 20 between groups. NEW AURA and NEW GROUP at
-- the foot.
-- ★ A GROUP is managed from its RIGHT-CLICK menu (the owner, 2026-09-25: "I don't
-- want to put all that stuff in the main panel") and REORDERED BY DRAGGING its
-- header. A plain click folds it.

local listRows = {}

local function listRow(i)
  local r = listRows[i]
  if r then return r end
  r = CreateFrame("Button", nil, P.listClip)
  r:SetSize(LIST_W, LIST_ROW_H)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.hl = r:CreateTexture(nil, "BACKGROUND"); r.hl:SetAllPoints(); r.hl:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0.2); r.hl:Hide()
  r.tri = r:CreateTexture(nil, "ARTWORK"); r.tri:SetTexture(UI.G_TRI); r.tri:SetSize(10, 7)
  r.tri:SetPoint("CENTER", r, "LEFT", 6, 0)
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(12, 12); r.icon:SetPoint("LEFT", 0, 0)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.name = UI.newText(r, FONT.sa, 11, COLOR.paper, "LEFT"); r.name:SetPoint("LEFT", 18, 0)
  r.name:SetWordWrap(false)
  -- The warning: an aura whose cooldown trigger points at a spell the Cooldown
  -- Manager has not bound reads READY forever and shows at every pull (Hub
  -- backlog item 6, "the silent yes"). The hover says what to do about it.
  r.warn = CreateFrame("Button", nil, r); r.warn:SetSize(12, 12)
  local wt = r.warn:CreateTexture(nil, "ARTWORK"); wt:SetAllPoints()
  wt:SetTexture(UI.G_WARN); wt:SetTexCoord(0, 12 / 16, 0, 12 / 16); UI.tint(wt, CORAL)
  UI.attachTip(r.warn, "Not in your Cooldown Manager", function() return r.warnText or "" end)
  -- The eye: on screen = lime, hidden = white at 40%. ONE icon; the colour says
  -- which. The selected aura counts as on screen.
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
  r:SetScript("OnEnter", function(self) if self.kind == "aura" or self.kind == "add" then self.hl:Show() end end)
  r:SetScript("OnLeave", function(self) self.hl:Hide() end)
  r:SetScript("OnClick", function(self, button)
    if self.kind == "group" then
      if button == "RightButton" then P.groupContext(self.gid, self); return end
      local g = X.Groups() and X.Groups()[self.gid]
      if g then g.collapsed = (not g.collapsed) or nil; X.RefreshList() end
    elseif self.kind == "ungrouped" then
      GA.db.ungroupedCollapsed = (not GA.db.ungroupedCollapsed) or nil; X.RefreshList()
    elseif button ~= "LeftButton" then return
    elseif self.kind == "aura" then X.SetSelected(self.id)
    elseif self.kind == "add" then P.newAuraMenu(self, self.gid) end
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
      for _, id in ipairs(X.AurasInGroup(gid)) do out[#out + 1] = { kind = "aura", id = id } end
      out[#out + 1] = { kind = "add", gid = gid }
    end
    out[#out + 1] = { kind = "gap" }
  end
  local ung = X.AurasInGroup(nil)
  if #groups > 0 then
    out[#out + 1] = { kind = "ungrouped" }
    if not (GA.db and GA.db.ungroupedCollapsed) then
      for _, id in ipairs(ung) do out[#out + 1] = { kind = "aura", id = id } end
      out[#out + 1] = { kind = "add" }
    end
  else
    for _, id in ipairs(ung) do out[#out + 1] = { kind = "aura", id = id } end
    out[#out + 1] = { kind = "add" }
  end
  return out
end

local function entryH(e) return e.kind == "gap" and LIST_GAP or LIST_ROW_H end

function P.renderList()
  if not P.listClip then return end
  local entries = listEntries()
  local total = 0
  for _, e in ipairs(entries) do total = total + entryH(e) end
  local view = LIST_BOTTOM - LIST_TOP
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
    if e.kind ~= "gap" then
      n = n + 1
      local r = listRow(n)
      r.kind, r.id, r.gid = e.kind, e.id, e.gid
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", P.listClip, "TOPLEFT", 0, -y)
      r.tri:Hide(); r.icon:Hide(); r.warn:Hide(); r.eye:Hide()
      r.name:ClearAllPoints(); r.name:SetPoint("LEFT", 18, 0); r.name:SetWidth(0)
      r.name:SetAlpha(1); r:SetAlpha(1)
      if e.kind == "group" or e.kind == "ungrouped" then
        local g = e.gid and X.Groups()[e.gid]
        local collapsed = (e.kind == "group" and g and g.collapsed) or (e.kind == "ungrouped" and GA.db and GA.db.ungroupedCollapsed)
        r.tri:Show(); r.tri:SetRotation(collapsed and (math.pi / 2) or 0); UI.tint(r.tri, LIME)
        UI.setFont(r.name, FONT.saB, 12)
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
        UI.setFont(r.name, isSel and FONT.saB or FONT.sa, 11)
        r.name:SetText((cfg and cfg.label) or ("Spell " .. tostring(e.id)))
        if isSel then r.name:SetTextColor(LILAC.r, LILAC.g, LILAC.b) else r.name:SetTextColor(1, 1, 1) end
        -- a disabled aura greys (Load Conditions → Disabled)
        if cfg and cfg.enabled == false then r.name:SetAlpha(0.5) end
        local warnText = cfg and C:SilentYesText(cfg)
        r.warnText = warnText
        -- Cap a name only when it is too long for the row: pinning every name to its
        -- own measured width lets rounding shave the last letter (or add a "…").
        local maxW = LIST_W - 14 - 18 - (warnText and 22 or 6)
        local w = math.ceil(r.name:GetStringWidth())
        if w > maxW then w = maxW; r.name:SetWidth(maxW) end
        if warnText then r.warn:ClearAllPoints(); r.warn:SetPoint("LEFT", 18 + w + 4, 0); r.warn:Show() end
        r.eye:Show()
        local on = isSel or (cfg and cfg.preview)
        if on then UI.tint(r.eye.t, LIME) else r.eye.t:SetVertexColor(1, 1, 1, 0.4) end
      elseif e.kind == "add" then
        UI.setFont(r.name, FONT.sa, 11)
        r.name:SetText("+ ADD NEW AURA"); r.name:SetTextColor(LIME.r, LIME.g, LIME.b)
      end
      r:Show()
    end
    y = y + h
  end
  for i = n + 1, #listRows do listRows[i]:Hide() end
  -- the list's bar
  local track, thumb = P.listTrack, P.listThumb
  if maxOff > 0 then
    track:Show()
    local th = math.max(24, view * view / total)
    thumb:SetHeight(th)
    thumb:ClearAllPoints(); thumb:SetPoint("TOP", track, "TOP", 0, -(view - th) * (P.listOffset / maxOff))
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
-- Delete Group. (The glass kit's list, opened at the mouse.)
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
      P.groupLoad:open(gid)
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
-- Reordering groups by DRAG (the owner, 2026-09-25: "I want it to be a
-- click-drag to move"). A ghost of the header follows the cursor, a lilac line
-- shows where it will land, and letting go writes the new order.
-- ---------------------------------------------------------------------------
-- The visible group headers other than the dragged one, top to bottom, and
-- how many of them sit above the cursor.
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
    gh = CreateFrame("Frame", nil, UIParent); gh:SetFrameStrata("TOOLTIP"); gh:SetSize(LIST_W, LIST_ROW_H)
    local b = gh:CreateTexture(nil, "BACKGROUND"); b:SetAllPoints(); b:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0.5)
    gh.text = UI.newText(gh, FONT.saB, 12, COLOR.paper, "LEFT"); gh.text:SetPoint("LEFT", 18, 0)
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
    -- the line sits just above the header it would land in front of, or under
    -- the list's last line when it would go last
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

local function BuildList(c)
  local f = CreateFrame("Frame", nil, c)
  f:SetAllPoints()
  P.listFrame = f
  Title(f, 50, 304, "Aura Groups", 14)
  local clip = CreateFrame("Frame", nil, f)
  clip:SetPoint("TOPLEFT", LIST_X, -LIST_TOP); clip:SetSize(LIST_W, LIST_BOTTOM - LIST_TOP)
  P.listClip = clip
  clip:EnableMouseWheel(true)
  clip:SetScript("OnMouseWheel", function(_, d)
    P.listOffset = math.max(0, math.min(P.listMax or 0, (P.listOffset or 0) - d)); P.renderList()
  end)
  -- the scrollbar, in the panel's right margin, only while the list overflows
  local track = CreateFrame("Frame", nil, f); track:SetWidth(3)
  track:SetPoint("TOPLEFT", LIST_X + LIST_W + 6, -LIST_TOP); track:SetHeight(LIST_BOTTOM - LIST_TOP)
  local tt = track:CreateTexture(nil, "BACKGROUND"); tt:SetAllPoints(); tt:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0.2)
  local thumb = CreateFrame("Button", nil, track); thumb:SetWidth(3)
  local th = thumb:CreateTexture(nil, "ARTWORK"); th:SetAllPoints(); th:SetColorTexture(LILAC.r, LILAC.g, LILAC.b, 0.8)
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
    local range = (LIST_BOTTOM - LIST_TOP) - self:GetHeight()
    if range <= 0 or (P.listMax or 0) <= 0 then return end
    local _, cy = GetCursorPosition()
    local want = math.floor(startOff + (startY - cy / self:GetEffectiveScale()) / range * P.listMax + 0.5)
    if want ~= P.listOffset then P.listOffset = math.max(0, math.min(P.listMax, want)); P.renderList() end
  end)

  local newA = UI.gButton(f, "New Aura")
  newA:SetPoint("TOPLEFT", 50, -666)
  newA:SetScript("OnClick", function(self) P.newAuraMenu(self, nil) end)
  UI.attachTip(newA, "New aura", "Creates a blank aura and opens it for editing. Pick the kind: Icon, Texture or Bar.")
  local newG = UI.gButton(f, "New Group")
  newG:SetPoint("TOPRIGHT", f, "TOPLEFT", 260, -666)
  newG:SetScript("OnClick", function()
    X.OpenNameDialog("New Group", "", function(nm)
      if not nm or nm:gsub("%s", "") == "" then return end
      local gid = X.CreateGroup(nm)
      if gid then X.RefreshList() end
    end)
  end)
  UI.attachTip(newG, "New group", "Groups hold a set of auras that load together: one load rule and one on/off switch gate every aura inside. Right-click a group's name for its settings; drag it to move it.")

  -- HIDE BLIZZARD CDM (the mock's Frame 330, 30,711) — a PROFILE setting, not an
  -- aura's. Drives viewer alpha only, never Hide(), so GA's mirror keeps working.
  Label(f, 30, 711, "Hide Blizzard CDM")
  local hide = UI.gSwitch(f, OFFON,
    function() return (GA.db and GA.db.hideBlizzardCDM) and true or false end,
    function(on) if GA.CDM and GA.CDM.ToggleBlizzardHide then GA.CDM:ToggleBlizzardHide(on) end end)
  hide:SetPoint("TOPLEFT", 143, -712.5)
  UI.attachTip(hide, "Hide Blizzard's Cooldown Manager", "Hides Blizzard's own cooldown bars while Gloom's Auras reads them. For this profile.")
  function hide:Set() self:refresh() end   -- C:OnProfileSwitched re-syncs it this way
  C._hideCDM = hide
  P.hideCDM = hide
end

-- ===========================================================================
-- THE HEADER (the mock's Frame 441, 320,80, 710 × 68)
-- ===========================================================================
-- The selected aura's icon (28px at 340,100), its name (Saira 14) and its group
-- (Saira 10) at x 378 — click the name to rename it, the group line to move it
-- to another group. DUPLICATE AURA and DELETE AURA end at x 1010.

function P.syncHeader()
  local h = P.header; if not h then return end
  local cfg = Cfg()
  if not cfg then h:Hide(); return end
  h:Show()
  h.icon:SetTexture(AuraIcon(cfg))
  h.name:SetText(cfg.label or "Aura"); h.group:SetText("Group: " .. GroupName(cfg.group))
  h.nameHit:SetWidth(math.max(10, h.name:GetStringWidth())); h.groupHit:SetWidth(math.max(10, h.group:GetStringWidth()))
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
  end, { minW = 160 })
end

local function BuildHeader(c)
  local h = CreateFrame("Frame", nil, c)
  h:SetAllPoints()
  P.header = h
  h.icon = h:CreateTexture(nil, "ARTWORK"); h.icon:SetSize(28, 28); h.icon:SetPoint("TOPLEFT", 340, -100)
  h.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  h.name = UI.newText(h, FONT.sa, 14, COLOR.paper, "LEFT"); h.name:SetWordWrap(false)
  h.name:SetPoint("TOPLEFT", 378, -101); h.name:SetWidth(420)
  h.group = UI.newText(h, FONT.sa, 10, COLOR.paper, "LEFT")
  h.group:SetPoint("TOPLEFT", 378, -115)
  h.nameHit = CreateFrame("Button", nil, h); h.nameHit:SetHeight(14)
  h.nameHit:SetPoint("TOPLEFT", 378, -100)
  h.nameHit:SetScript("OnClick", function() C:RenameSelected() end)
  UI.attachTip(h.nameHit, "Rename", "Click to rename this aura in the list. (The text it draws on screen is a separate setting, on the Text page.)")
  h.groupHit = CreateFrame("Button", nil, h); h.groupHit:SetHeight(12)
  h.groupHit:SetPoint("TOPLEFT", 378, -115)
  h.groupHit:SetScript("OnClick", function(self) P.groupMenu(self) end)
  UI.attachTip(h.groupHit, "Group", "Click to move this aura to another group.")

  h.del = UI.gButton(h, "Delete Aura", { danger = true })
  h.del:SetPoint("TOPRIGHT", h, "TOPLEFT", 1010, -106)
  h.dup = UI.gButton(h, "Duplicate Aura")
  h.dup:SetPoint("TOPRIGHT", h.del, "TOPLEFT", -10, 0)
  h.dup:SetScript("OnClick", function()
    local id = Sel(); if not (id and DB() and DB()[id]) then return end
    local copy = X.DeepCopy(DB()[id]); copy.label = (copy.label or "Aura") .. " (copy)"
    local p = copy.point or { "CENTER", 0, 0 }; copy.point = { "CENTER", (p[2] or 0) + 24, (p[3] or 0) - 24 }
    local nid = X.NewDisplayID(); DB()[nid] = copy
    if GA.CDM then GA.CDM:Discover() end
    X.SetSelected(nid)
  end)
  -- Deleting CONFIRMS (CONTRACTS §4).
  h.del:SetScript("OnClick", function()
    local id, cfg = Sel(), Cfg(); if not (id and cfg) then return end
    C:OpenConfirm(("Delete the aura \"%s\"?  This can't be undone."):format(cfg.label or "this aura"), function()
      if not (DB() and DB()[id]) then return end
      DB()[id] = nil
      if GA.Displays and GA.Displays.frames[id] then GA.Displays.frames[id]:Hide() end
      if GA.CDM then GA.CDM:Discover() end
      X.SetSelected(X.DisplayList()[1])
    end)
  end)
end

-- ===========================================================================
-- PAGE · AURA TRIGGERS (the mock's Frame 422, 320,178, 710 × 532)
-- ===========================================================================
-- "Aura Triggers" (Michroma 18) with MATCH ALL / ANY / NONE on its right; then
-- the conditions, 20 apart, scrolling inside the panel when they run long: a
-- condition is a 35-tall row of violet 20% — its spell, the spell's icon, "is",
-- the state as a DROPDOWN, the X; a TRIGGER GROUP is a violet 20% box, padded
-- 10, with "Trigger Group" in lilac, its own MATCH buttons and X, holding its
-- conditions as darker rows 10 apart. ADD A TRIGGER and CREATE TRIGGER GROUP at
-- the panel's foot.
--
-- ★ Grouping is by DRAG (the owner, 2026-09-23): make a group at any time, then
-- drag conditions into it — or back out onto the page. A group's X deletes the
-- GROUP only: its conditions drop back to the top level. The engine already
-- ignores an empty group, so one waiting to be filled never changes whether the
-- aura shows.
local TR = { rows = {}, groups = {} }
P.TR = TR
local TRIG_ROW_H = 35

-- "ACTIVE on Target (Debuff)" → "ACTIVE ON TARGET (DEBUFF)" — the mocks' casing
-- is capitals, and the kit capitalises it.
local function StateText(state, k)
  local main, suf = X.TrigPill(state, k)
  return (main or "?") .. (suf or "")
end

local function StateDrop(parent, r)
  local d = CreateFrame("Button", nil, parent); d:SetHeight(16)
  d.fill = d:CreateTexture(nil, "BACKGROUND"); d.fill:SetAllPoints(); d.fill:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0.2)
  local e = UI.addEdges(d, LILAC, 1)
  d.text = UI.newText(d, FONT.saM, 10, COLOR.paper, "LEFT"); d.text:SetPoint("LEFT", 5, -UI.G_NUDGE)
  d.tri = UI.gCaret(d); d.tri:SetPoint("LEFT", d.text, "RIGHT", 6, 0)
  function d:SetLabel(s) self.text:SetText(tostring(s or ""):upper()); self:SetWidth(math.ceil(self.text:GetStringWidth()) + 5 + 6 + 7 + 5) end
  d:SetScript("OnEnter", function(self) self.fill:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0.35) end)
  d:SetScript("OnLeave", function(self) self.fill:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0.2) end)
  d:SetScript("OnClick", function(self)
    local list = {}
    local node = r._node
    for _, st in ipairs(C:TrigStates(r._ti, r._ci)) do list[#list + 1] = { value = st, label = StateText(st, node and node.k) } end
    UI.gList(self, list, node and node.state, function(v) C:TrigSetState(r._ti, r._ci, v) end)
  end)
  UI.attachTip(d, "Condition", "What this condition checks for.")
  d.edge = e
  return d
end

local function MakeLeaf(parent, nested)
  local r = CreateFrame("Button", nil, parent); r:SetHeight(TRIG_ROW_H)
  r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
  if nested then r.bg:SetColorTexture(COLOR.deep.r, COLOR.deep.g, COLOR.deep.b, 0.75)
  else r.bg:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0.2) end
  local x0 = nested and 20 or 10
  r.name = UI.newText(r, FONT.sa, 11, COLOR.paper, "LEFT"); r.name:SetPoint("LEFT", x0, 0)
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(12, 12)
  r.icon:SetPoint("LEFT", r.name, "RIGHT", 4, 0); r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.is = UI.newText(r, FONT.sa, 11, COLOR.paper, "LEFT"); r.is:SetText("is"); r.is:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
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

-- MATCH ALL / ANY / NONE, right-aligned so the last one ends at `anchor`.
local function MatchButtons(parent, onPick)
  local out, prev = {}, nil
  for i = #LOGICS, 1, -1 do
    local lg = LOGICS[i]
    local b = UI.gButton(parent, "Match " .. lg[2])
    b._logic = lg[1]
    b:SetScript("OnClick", function() onPick(lg[1]) end)
    out[i] = b
    if prev then b:SetPoint("RIGHT", prev, "LEFT", -10, 0) end
    prev = b
  end
  return out
end

local function MakeGroup(parent)
  local g = CreateFrame("Frame", nil, parent)
  g.bg = g:CreateTexture(nil, "BACKGROUND"); g.bg:SetAllPoints(); g.bg:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0.2)
  g.label = UI.newText(g, FONT.saB, 12, LILAC, "LEFT"); g.label:SetText("Trigger Group")
  g.x = UI.gX(g, function() P.dissolveGroup(g._ti) end)
  -- The header row is 23 tall: padded 10 when the group holds conditions, 6
  -- when it is empty (the mock's two groups). P.renderTriggers places it.
  function g:placeHeader(top)
    self.label:ClearAllPoints(); self.label:SetPoint("LEFT", self, "TOPLEFT", 10, -(top + 11.5))
    self.x:ClearAllPoints(); self.x:SetPoint("TOPRIGHT", -10, -top)
  end
  g:placeHeader(10)
  UI.attachTip(g.x, "Delete group", "Deletes the group. Its conditions stay — they move back to the top level.")
  g.match = MatchButtons(g, function(logic)
    if not g._node then return end
    g._node.logic = logic
    if GA.CDM then GA.CDM:RefreshDisplays() end
    P.renderTriggers()
  end)
  g.match[1]:ClearAllPoints(); g.match[1]:SetPoint("LEFT", g.label, "RIGHT", 10, 0)
  -- (the three are chained to each other from the right; re-chain them from the left)
  g.match[2]:ClearAllPoints(); g.match[2]:SetPoint("LEFT", g.match[1], "RIGHT", 10, 0)
  g.match[3]:ClearAllPoints(); g.match[3]:SetPoint("LEFT", g.match[2], "RIGHT", 10, 0)
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
-- the page, at the top level).
function P.trigDragStart(row)
  if not row._node then return end
  local gh = TR.ghost
  if not gh then
    gh = CreateFrame("Frame", nil, UIParent); gh:SetFrameStrata("TOOLTIP"); gh:SetSize(220, 25)
    local b = gh:CreateTexture(nil, "BACKGROUND"); b:SetAllPoints(); b:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 0.5)
    gh.text = UI.newText(gh, FONT.sa, 11, COLOR.paper, "LEFT"); gh.text:SetPoint("LEFT", 12, 0)
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
  local toTop = (not target) and TR.pane:IsMouseOver()
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
  local pane = TR.pane; if not pane then return end
  local body = pane.child
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
      g:placeHeader((#node.conditions > 0) and 10 or 6)
      local gy = 43                               -- 10 padding + the 23 header + 10
      for ci, child in ipairs(node.conditions) do
        local r = g.rows[ci]; if not r then r = MakeLeaf(g, true); g.rows[ci] = r end
        FillLeaf(r, ti, ci, child)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 10, -gy); r:SetPoint("TOPRIGHT", -10, -gy); r:Show()
        gy = gy + TRIG_ROW_H + 10
      end
      for i = #node.conditions + 1, #g.rows do g.rows[i]:Hide() end
      local gh = (#node.conditions > 0) and gy or 35
      g:ClearAllPoints(); g:SetPoint("TOPLEFT", 0, -y); g:SetSize(TRIG_W, gh); g:Show()
      y = y + gh + 20
    else
      nr = nr + 1
      local r = TR.rows[nr]; if not r then r = MakeLeaf(body, false); TR.rows[nr] = r end
      FillLeaf(r, ti, nil, node)
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetWidth(TRIG_W); r:Show()
      y = y + TRIG_ROW_H + 20
    end
  end
  for i = nr + 1, #TR.rows do TR.rows[i]:Hide() end
  for i = ng + 1, #TR.groups do TR.groups[i]:Hide() end
  TR.addT:SetEnabled(cfg ~= nil); TR.addG:SetEnabled(cfg ~= nil)
  pane:SetContentHeight(math.max(10, y - 20))
end

local function BuildTriggers()
  local pg = Page("triggers"); TR.page = pg
  Title(pg, 340, 198, "Aura Triggers")
  TR.match = MatchButtons(pg, function(logic)
    local tr = C:TrigTree(); if not tr then return end
    tr.logic = logic
    if GA.CDM then GA.CDM:RefreshDisplays() end
    P.renderTriggers()
  end)
  TR.match[3]:SetPoint("TOPRIGHT", pg, "TOPLEFT", 1010, -199)
  local pane = UI.gScroll(pg, { w = TRIG_W, barGap = 3 })
  pane:SetPoint("TOPLEFT", TRIG_X, -TRIG_Y); pane:SetSize(TRIG_W, TRIG_BOTTOM - TRIG_Y)
  TR.pane = pane
  TR.addT = UI.gButton(pg, "Add a Trigger")
  TR.addT:SetPoint("TOPLEFT", 340, -674)
  TR.addT:SetScript("OnClick", function() X.OpenPicker(function(item) C:TrigAddLeaf(item, nil) end) end)
  TR.addG = UI.gButton(pg, "Create Trigger Group")
  TR.addG:SetPoint("TOPRIGHT", pg, "TOPLEFT", 1010, -674)
  TR.addG:SetScript("OnClick", function() C:TrigAddGroup() end)
  UI.attachTip(TR.addG, "Trigger group", "Adds an empty group. Drag conditions into it; its own Match decides how they combine.")
end

-- ===========================================================================
-- PAGE · APPEARANCE, POSITION & SIZE — three panels: Appearance (320,178),
-- Position (320,385), Size (800,385)
-- ===========================================================================
local function BuildAppearance()
  local pg = Page("appearance")
  Title(pg, 340, 198, "Appearance")

  -- Icon/Art: the texture — a file path or an icon ID — typed, or chosen. Blank
  -- means "the first trigger's icon". (A number typed here is stored as a
  -- number, which is what an ID is.)
  Label(pg, 340, 234, "Icon/Art")
  local tf = UI.gField(pg, 166, {
    placeholder = "Blank = the first trigger's icon",
    commit = function(txt)
      local c = Cfg(); if not c then return end
      local v = (txt or ""):match("^%s*(.-)%s*$")
      if v == "" then v = nil elseif tonumber(v) then v = tonumber(v) end
      if v ~= c.texture then c.texture = v; Reapply(); X.RefreshList(); P.syncHeader() end
    end,
    revert = function(self) self:refresh() end,
  })
  tf:SetPoint("TOPLEFT", 340, -257)
  function tf:refresh() local c = Cfg(); local v = c and c.texture; self:SetText(v ~= nil and tostring(v) or ""); self:SetCursorPosition(0) end
  add(tf)
  local choose = UI.gButton(pg, "Choose", { w = 50 })
  choose:SetPoint("TOPLEFT", 510, -257)
  choose:SetScript("OnClick", function()
    local c = Cfg(); if not c then return end
    X.OpenTexturePicker(function(tex) c.texture = tex; Reapply(); P.sync(); X.RefreshList(); P.syncHeader() end, c.texture)
  end)
  add(choose)

  -- Shape: a STENCIL cut through that texture — it draws nothing itself, and it
  -- is what an animation traces. (Most shapes crop very little off an icon; see
  -- FINDINGS §14 before calling one broken.)
  add(PickerDrop(pg, 580, 234, 430, "Shape/Silhouette",
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

  -- Effects only: no artwork, just the glow and the animation — for laying over
  -- a real action button. Distinct from a blank texture, which means "work it out".
  local eo = add(Switch(pg, 340, 283, "Effects Only", OFFON,
    function() local c = Cfg(); return (c and c.noArt) and true or false end,
    function(on) local c = Cfg(); if c then c.noArt = on or nil; Reapply(); P.sync() end end))
  UI.attachTip(eo, "Effects only", "The aura draws no artwork — just its glow and animation. For laying over a real action button.")
  add(Drop(pg, 470, 283, 100, "Blend Mode", X.BLEND_MODES,
    function() local c = Cfg(); return (c and c.blend) or "BLEND" end,
    function(v) local c = Cfg(); if c then c.blend = (v ~= "BLEND") and v or nil; Reapply() end end))
  add(Dial(pg, 620.5, 283, { label = "Opacity", min = 0, max = 100, step = 1, unit = "%", dragPx = 500,
    get = function() local c = Cfg(); return c and math.floor(((c.alpha or 1) * 100) + 0.5) end,
    set = function(v) local c = Cfg(); if c then c.alpha = v / 100; Reapply() end end }))
  add(Color(pg, 835, 283, "Recolor:", { title = "Recolor",
    get = function() local c = Cfg(); return c and c.color end,
    set = function(v) local c = Cfg(); if c then c.color = v; Reapply() end end }))
  add(Switch(pg, 930, 283, "Desaturate", OFFON,
    function() local c = Cfg(); return (c and c.desaturate) and true or false end,
    function(on) local c = Cfg(); if c then c.desaturate = on or nil; Reapply() end end))

  -- POSITION
  Title(pg, 340, 405, "Position")
  add(Dial(pg, 340, 441, { label = "Horizontal Offset", min = -2000, max = 2000, step = 1, unit = "px", dragPx = 1600,
    get = function() local c = Cfg(); return c and c.point and c.point[2] or 0 end,
    set = function(v) local c = Cfg(); if c then c.point = { "CENTER", v, (c.point and c.point[3]) or 0 }; Reapply() end end }))
  add(Dial(pg, 340, 492, { label = "Vertical Offset", min = -2000, max = 2000, step = 1, unit = "px", dragPx = 1600,
    get = function() local c = Cfg(); return c and c.point and c.point[3] or 0 end,
    set = function(v) local c = Cfg(); if c then c.point = { "CENTER", (c.point and c.point[2]) or 0, v }; Reapply() end end }))
  -- Fixed rotation, positive = clockwise; it shares one AnimationGroup with the
  -- spin (Effects page), so the angle is where a spin starts from.
  add(Dial(pg, 340, 543, { label = "Rotation", min = 0, max = 359, step = 1, unit = "°", dragPx = 720,
    get = function() local c = Cfg(); return (c and c.angle) or 0 end,
    set = function(v) local c = Cfg(); if c then c.angle = (v ~= 0) and v or nil; Reapply() end end }))
  add(Drop(pg, 554, 441, 130, "Strata", X.STRATA_MODES,
    function() local c = Cfg(); return (c and c.strata) or "HIGH" end,
    function(v) local c = Cfg(); if c then c.strata = (v ~= "HIGH") and v or nil; Reapply() end end))
  -- LEVEL (2026-09-23; Displays.lua applies it): 0 = Auto, the frame's own level.
  add(Dial(pg, 554, 490, { label = "Level", min = 0, max = 500, step = 1, dragPx = 1000,
    fmt = function(v) v = math.floor(v + 0.5); return v == 0 and "Auto" or tostring(v) end,
    get = function() local c = Cfg(); return (c and c.level) or 0 end,
    set = function(v) local c = Cfg(); if c then c.level = (v > 0) and v or nil; Reapply() end end }))

  -- SIZE. Width and height can be LINKED — the bracket joining their two boxes
  -- (the owner's design, 2026-09-25: white at 40% when free, full lilac when
  -- linked; click it to switch).
  Title(pg, 820, 405, "Size")
  local wDial, hDial
  local function clampDim(n) return math.max(8, math.min(8192, math.floor(n + 0.5))) end
  wDial = add(Dial(pg, 820, 441, { label = "Width", min = 8, max = 8192, step = 1, unit = "px", dragPx = 4000,
    get = function() local c = Cfg(); return c and (c.width or c.size) or 64 end,
    set = function(v)
      local c = Cfg(); if not c then return end
      c.width = v
      if c.lockAspect then c.height = clampDim(v / (c.aspect or 1)); if hDial then hDial:refresh() end end
      Reapply()
    end }))
  hDial = add(Dial(pg, 820, 492, { label = "Height", min = 8, max = 8192, step = 1, unit = "px", dragPx = 4000,
    get = function() local c = Cfg(); return c and (c.height or c.size) or 64 end,
    set = function(v)
      local c = Cfg(); if not c then return end
      c.height = v
      if c.lockAspect then c.width = clampDim(v * (c.aspect or 1)); if wDial then wDial:refresh() end end
      Reapply()
    end }))
  -- The bracket: across from the Width box's middle (y 472) to the Height box's
  -- (y 523), 10 right of them — the mock's Frame 509.
  local link = CreateFrame("Button", nil, pg); link:SetSize(16, 58)
  link:SetPoint("TOPLEFT", 991, -468)
  local function seg(x, y, w, h) local t = link:CreateTexture(nil, "ARTWORK"); t:SetPoint("TOPLEFT", x, -y); t:SetSize(w, h); return t end
  local segs = { seg(3, 3.5, 10, 1), seg(13, 3.5, 1, 52), seg(3, 54.5, 10, 1) }
  function link:refresh()
    local c = Cfg(); local on = c and c.lockAspect
    for _, t in ipairs(segs) do
      if on then t:SetColorTexture(LILAC.r, LILAC.g, LILAC.b, 1) else t:SetColorTexture(1, 1, 1, 0.4) end
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
end

-- ===========================================================================
-- PAGE · BAR FILL & READOUTS — Bar Settings (320,178), Text Settings (320,385)
-- ===========================================================================
-- Everything here only means something on a BAR aura; on any other it all dims.
-- ⚠ On 12.1 the fill of a duration bar is drawn by the ENGINE's own Blizzard
-- button (FINDINGS §1), so every change routes through ApplyConfig → the
-- engine's style push, which is only legal out of combat: an edit made in
-- combat lands when combat ends.
local BAR = {}

local function BuildBar()
  local pg = Page("bar"); BAR.page = pg
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

  Title(pg, 340, 198, "Bar Settings")
  -- Said where it is useful rather than left as a page that silently does nothing.
  local note = UI.gLabel(pg, "", 11); note:SetPoint("TOPRIGHT", pg, "TOPLEFT", 1010, -204); note:SetJustifyH("RIGHT"); note:SetAlpha(0.6)
  BAR.note = note

  local MODES = { { "aura_dur", "Aura Duration" }, { "cd_dur", "Cooldown" }, { "stacks", "Stack Count" } }
  add(Drop(pg, 340, 234, 150, "Bar Type", MODES, mode, function(v)
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
  add(Drop(pg, 520, 234, 150, "Orientation", ORIENT,
    function() local b = get(); return (b and b.orientation == "VERTICAL") and "VERTICAL" or "HORIZONTAL" end,
    function(v)
      local c = Cfg(); local b = ensure(); if not (b and c) then return end
      local wasVert, nowVert = (b.orientation == "VERTICAL"), (v == "VERTICAL")
      b.orientation = nowVert and "VERTICAL" or nil
      if wasVert ~= nowVert then c.width, c.height = (c.height or 24), (c.width or 220) end
      repaint(); P.sync()
    end), isBar)

  -- The fill texture (Shared Media bar textures only). RIGHT-CLICK clears it back
  -- to a plain colour fill — the picker has no "none" row, and without a way back
  -- a texture was a one-way door (the old editor's Clear button; not in the mock).
  local function texName(p)
    if type(p) ~= "string" or p == "" then return nil end
    return p:match("([^\\/]+)%.%w+$") or p:match("([^\\/]+)$") or p
  end
  local tex
  tex = add(PickerDrop(pg, 700, 234, 198, "Bar Texture",
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
  add(Switch(pg, 928, 234, "Rotate Texture", OFFON,
    function() local b = get(); return (b and b.rotateTexture) == true end,
    function(on) local b = ensure(); if b then b.rotateTexture = on or nil; repaint() end end), isBar)

  local DIRS = { { "drain", "Drains Down" }, { "fill", "Fills Up" } }
  add(Drop(pg, 340, 283, 178, "Bar Fill Direction", DIRS,
    function() local b = get(); return (b and b.fill == "fill") and "fill" or "drain" end,
    function(v) local b = ensure(); if b then b.fill = (v == "fill") and "fill" or nil; repaint() end end), isBar)
  add(Switch(pg, 548, 283, "Reverse Fill", OFFON,
    function() local b = get(); return (b and b.reverse) == true end,
    function(on) local b = ensure(); if b then b.reverse = on or nil; repaint() end end), isBar)
  local function colorAt(x, label, key)
    add(Color(pg, x, 283, label, {
      get = function() local b = get(); return b and b[key] end,
      set = function(v) local b = ensure(); if b then b[key] = v; repaint() end end }), isBar)
  end
  colorAt(658, "Bar Fill Color", "color")
  colorAt(758, "Background Color", "bg")
  -- The BACKDROP turns this colour while the DoT is in its pandemic window — the
  -- backdrop, not the fill: the fill is the engine's and cannot be recoloured in
  -- combat (HANDOFF, 2026-09-19 — do not re-offer the fill).
  colorAt(886, "Pandemic Background", "pandemicBg")

  -- TEXT SETTINGS — the two readouts a bar can carry. One font for both: two
  -- typefaces on one 22px bar would read as an accident.
  Title(pg, 340, 405, "Text Settings")
  add(PickerDrop(pg, 340, 441, 222, "Font",
    function() local b = get(); return X.fontNameFor(b and b.font) end,
    function()
      local b = ensure(); if not b then return end
      X.OpenFontPicker(function(path) local b2 = ensure(); if b2 then b2.font = path; repaint(); P.sync() end end, b.font)
    end), isBar)
  -- the two column rules (the mock's Line 89 / Line 90)
  for _, x in ipairs({ 592, 816 }) do
    local l = pg:CreateTexture(nil, "ARTWORK"); l:SetPoint("TOPLEFT", x, -441); l:SetSize(1, 200)
    l:SetColorTexture(VIOLET.r, VIOLET.g, VIOLET.b, 1)
  end
  local ANCHORS = { { "CENTER", "Center" }, { "TOP", "Top" }, { "BOTTOM", "Bottom" }, { "LEFT", "Left" }, { "RIGHT", "Right" } }
  local function readout(x, label, showKey, colorKey, sizeKey, anchorKey, anchorDefault, gate)
    add(Switch(pg, x, 441, label, OFFON,
      function() local b = get(); return (b and b[showKey]) == true end,
      function(v) local b = ensure(); if b then b[showKey] = v or nil; repaint(); P.sync() end end), isBar)
    add(Color(pg, x + 109, 441, "Text Color", { title = label .. " Color",
      get = function() local b = get(); return b and b[colorKey] end,
      set = function(v) local b = ensure(); if b then b[colorKey] = v; repaint() end end }), gate)
    add(Dial(pg, x, 490, { label = label .. " Size", min = 8, max = 32, step = 1, unit = "px", dragPx = 300,
      get = function() local b = get(); return (b and b[sizeKey]) or 14 end,
      set = function(v) local b = ensure(); if b then b[sizeKey] = v; repaint() end end }), gate)
    add(Drop(pg, x, 541, 150, label .. " Position", ANCHORS,
      function() local b = get(); return (b and b[anchorKey]) or anchorDefault end,
      function(v) local b = ensure(); if b then b[anchorKey] = v; repaint() end end), gate)
  end
  -- Stacks default to TOP and the countdown to CENTER, so switched on together
  -- they never print on top of each other.
  readout(622, "Stack Text", "showStacks", "stackColor", "stackSize", "stackAnchor", "TOP", stacksOn)
  readout(846, "Countdown Text", "showTimer", "timerColor", "timerSize", "timerAnchor", "CENTER", timerOn)

  -- MAX STACKS — how many stacks make a FULL bar (with Max 6, three stacks is
  -- half a bar). The game does not tell an addon an aura's maximum, so it is set
  -- here. It only means something in Stack Count mode: dimmed to 50% otherwise
  -- (the owner, 2026-09-25), where he placed it, under the stack readout.
  add(Dial(pg, 622, 590, { label = "Max Stacks", min = 1, max = 40, step = 1, dragPx = 300,
    get = function() local b = get(); return (b and b.max) or 10 end,
    set = function(v) local b = ensure(); if b then b.max = v; repaint() end end }),
    function() return isBar() and mode() == "stacks" end)

  rows[#rows + 1] = {
    refresh = function()
      local c = Cfg()
      note:SetText((c and not isBar()) and "This aura isn't a bar." or "")
    end,
    setEnabled = function() end,
  }
end

-- ===========================================================================
-- PAGE · TEXT — Custom Text (320,178), Size & Position (320,333), Appearance
-- (750,178)
-- ===========================================================================
-- The words an aura draws on screen (cfg.text) — NOT its name in the list.
-- Reads never create cfg.text; writes do.
local function BuildText()
  local pg = Page("text")
  local function txt() local c = Cfg(); return c and c.text end
  local function ensure() local c = Cfg(); if not c then return nil end
    if not c.text then c.text = { show = (c.showLabel ~= false) } end; return c.text end
  local function showing()
    local c = Cfg(); if not c then return false end
    if c.text then return c.text.show ~= false end
    return c.showLabel ~= false
  end

  Title(pg, 340, 198, "Custom Text")
  add(Switch(pg, 340, 234, "Show Text", OFFON, showing,
    function(v) local t = ensure(); if t then t.show = v; Reapply(); P.sync() end end))
  local dfl = Label(pg, 450, 234, "Displayed Text")
  local df = UI.gField(pg, 250, { placeholder = "The aura's name",
    commit = function(s) local t = ensure(); if t then t.str = (s ~= "" and s) or nil; Reapply() end end,
    revert = function(self) self:refresh() end })
  df:SetPoint("TOPLEFT", 450, -257)
  df._label = dfl
  function df:refresh()
    local t, c = txt(), Cfg()
    self:SetText((t and t.str) or ""); self:SetCursorPosition(0)
    if self.placeholder then self.placeholder:SetText((c and c.label) or "The aura's name") end
  end
  add(df, showing)

  Title(pg, 340, 353, "Size & Position")
  add(Dial(pg, 340, 389, { label = "Font Size", min = 6, max = 300, step = 1, unit = "px", dragPx = 900,
    get = function() local t = txt(); return (t and t.size) or 14 end,
    set = function(v) local t = ensure(); if t then t.size = v; Reapply() end end }), showing)
  add(Drop(pg, 340, 440, 164, "Anchor", X.TE_ANCHOR,
    function() local t = txt(); return (t and t.anchor) or "BOTTOM" end,
    function(v) local t = ensure(); if t then t.anchor = (v ~= "BOTTOM") and v or nil; Reapply() end end), showing)
  add(Dial(pg, 534, 389, { label = "Horizontal Offset", min = -400, max = 400, step = 1, unit = "px", dragPx = 800,
    get = function() local t = txt(); return (t and t.x) or 0 end,
    set = function(v) local t = ensure(); if t then t.x = (v ~= 0) and v or nil; Reapply() end end }), showing)
  add(Dial(pg, 534, 440, { label = "Vertical Offset", min = -400, max = 400, step = 1, unit = "px", dragPx = 800,
    get = function() local t = txt(); return (t and t.y) or 0 end,
    set = function(v) local t = ensure(); if t then t.y = (v ~= 0) and v or nil; Reapply() end end }), showing)

  Title(pg, 770, 198, "Appearance")
  add(PickerDrop(pg, 770, 234, 240, "Font",
    function() local t = txt(); return X.fontNameFor(t and t.font) end,
    function()
      local t = txt()
      X.OpenFontPicker(function(path) local t2 = ensure(); if t2 then t2.font = path; Reapply(); P.sync() end end, t and t.font)
    end), showing)
  add(Color(pg, 770, 283, "Text Color", {
    get = function() local t = txt(); return t and t.color end,
    set = function(v) local t = ensure(); if t then t.color = v; Reapply() end end }), showing)
  add(Drop(pg, 855, 283, 155, "Outline Type", X.TE_OUTLINE,
    function() local t = txt(); return (t and t.outline) or "OUTLINE" end,
    function(v) local t = ensure(); if t then t.outline = (v ~= "OUTLINE") and v or nil; Reapply() end end), showing)
  -- The live charge count, in place of the text — which is why turning it on
  -- also turns the text on.
  add(Switch(pg, 770, 332, "Show Charge Count", OFFON,
    function() local t = txt(); return (t and t.showCount) == true end,
    function(v) local t = ensure(); if t then t.showCount = v or nil; if v then t.show = true end; Reapply(); P.sync() end end))
end

-- ===========================================================================
-- PAGE · EFFECTS, MOTION & SOUND — Animations (320,178), Glows (640,178),
-- Rotation (640,333), Sounds (320,539)
-- ===========================================================================
local EF = { blocks = {} }
P.EF = EF

local function BuildEffects()
  local pg = Page("effects"); EF.page = pg
  local E = _G.GloomsHub and _G.GloomsHub.Effects

  -- ANIMATIONS — one of the Hub's eight shaped animations, and its own settings,
  -- built from the module's `params` schema so a module added in the Hub grows
  -- its controls here with no GA change. Numbers become dials, choices
  -- dropdowns, a colour sits beside the type (its checkbox off = the module's
  -- own colour). Fractional params show ×100 as a percentage. Only the chosen
  -- animation's settings show: every animation has different ones.
  Title(pg, 340, 198, "Animations")
  local ANIMS = { { "none", "None" } }
  if E then E:Each(function(m) ANIMS[#ANIMS + 1] = { m.id, m.label or m.id } end) end
  local function animID() local c = Cfg(); return (c and c.effects and c.effects.anim) or "none" end
  add(Drop(pg, 340, 234, 181, "Animation Type", ANIMS, animID, function(v)
    local c = Cfg(); if not c then return end
    c.effects = c.effects or {}; c.effects.anim = (v ~= "none") and v or nil
    Reapply(); P.layoutEffects(); P.sync()
  end))
  -- Every animation traces the aura's SHAPE; with none set there is nothing to
  -- draw and the engine skips it. Said, so it never looks broken.
  local need = UI.gLabel(pg, "", 10); need:SetPoint("TOPRIGHT", pg, "TOPLEFT", 590, -205); need:SetJustifyH("RIGHT")
  need:SetTextColor(CORAL.r, CORAL.g, CORAL.b)

  local function block(id)
    if EF.blocks[id] then return EF.blocks[id] end
    local mod = E and E:Get(id); if not mod then return nil end
    local b = CreateFrame("Frame", nil, pg); b:SetAllPoints()
    b.rows = {}
    local y, colorPlaced = 283, false
    for _, p in ipairs(mod.params or {}) do
      local function set(v) local t = X.AnimParams(Cfg(), id); if t then t[p.key] = v end; Reapply() end
      local function get() return X.AnimGet(id, p.key) end
      if p.kind == "color" then
        -- the SAVED colour only: unset = the module's own, shown as the dashed ring
        local function saved()
          local c = Cfg(); local s = c and c.effects and c.effects.params and c.effects.params[id]
          return s and s[p.key]
        end
        local d
        if not colorPlaced then
          colorPlaced = true
          d = Color(b, 551, 234, "Color", { title = p.label, get = saved, set = function(v) set(v) end })
        else
          d = Color(b, 340, y, p.label, { title = p.label, get = saved, set = function(v) set(v) end }); y = y + 51
        end
        b.rows[#b.rows + 1] = d
      elseif p.kind == "choice" then
        local vals = {}
        for _, ch in ipairs(p.choices or {}) do vals[#vals + 1] = { ch[1], ch[2] } end
        b.rows[#b.rows + 1] = Drop(b, 340, y, 250, p.label, vals, get, set); y = y + 51
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
        local d = Dial(b, 340, y, { label = p.label, min = lo, max = hi, step = st, unit = (sc ~= 1) and "%" or "",
          dragPx = 400, get = function() return (get() or 0) * sc end, set = function(v) set(v / sc) end })
        if p.kind == "bispeed" then
          UI.attachTip(d.strip, p.label, ("−100%% = %s · 0 = still · +100%% = %s"):format(p.neg or "counter-clockwise", p.pos or "clockwise"))
        end
        b.rows[#b.rows + 1] = d
        y = y + 51
      end
    end
    -- An animation with no colour of its own still shows the Color spot, dimmed,
    -- so the panel keeps the mock's shape.
    if not colorPlaced then
      local d = Color(b, 551, 234, "Color", { get = function() return nil end, set = function() end })
      d:setEnabled(false); b.fixedOff = d
    end
    b:Hide()
    EF.blocks[id] = b
    return b
  end
  -- With None, the Color spot is there and dimmed.
  local noneColor = Color(pg, 551, 234, "Color", { get = function() return nil end, set = function() end })
  noneColor:setEnabled(false)

  -- GLOWS — the glow while the aura is on screen; Color off = the glow's own colour.
  Title(pg, 660, 198, "Glows")
  local GLOW = { { "none", "None" }, { "autocast", "Autocast Shine" }, { "pixel", "Pixel Glow" },
                 { "proc", "Proc Glow" }, { "button", "Action Button Glow" } }
  local function glowType() local c = Cfg(); return (c and c.glow and c.glow.type) or "none" end
  add(Drop(pg, 660, 234, 281, "Glow Type", GLOW, glowType, function(v)
    local c = Cfg(); if not c then return end
    c.glow = c.glow or {}; c.glow.type = (v ~= "none") and v or nil
    Reapply(); P.sync()
  end))
  add(Color(pg, 971, 234, "Color", { title = "Glow Color",
    get = function() local c = Cfg(); return c and c.glow and c.glow.customColor and c.glow.color end,
    set = function(v)
      local c = Cfg(); if not c then return end
      c.glow = c.glow or {}; c.glow.color = v; c.glow.customColor = (v ~= nil) or nil; Reapply()
    end }), function() return glowType() ~= "none" end)

  -- ROTATION — spins the aura's own artwork, so it needs one: a bar has none and
  -- "Effects Only" hides it on purpose. Dimmed then, rather than left looking live.
  Title(pg, 660, 353, "Rotation")
  local function rot() local c = Cfg(); return c and c.rotate end
  local function ensureRot() local c = Cfg(); if not c then return nil end; c.rotate = c.rotate or {}; return c.rotate end
  local function isIcon() local c = Cfg(); return c ~= nil and c.kind ~= "bar" and not c.noArt end
  local function spinning() local r = rot(); return isIcon() and r ~= nil and r.on == true end
  add(Switch(pg, 660, 390, "Rotation", OFFON,
    function() local r = rot(); return isIcon() and (r and r.on) == true end,
    function(v) local r = ensureRot(); if r then r.on = v or nil; Reapply(); P.sync() end end), isIcon)
  -- A percentage: 100% = one turn every 3 seconds.
  add(Dial(pg, 770, 389, { label = "Rotation Speed", min = 10, max = 500, step = 10, unit = "%", dragPx = 500,
    get = function() local r = rot(); return (r and r.speed) or 100 end,
    set = function(v) local r = ensureRot(); if r then r.speed = (v ~= 100) and v or nil; Reapply() end end }), spinning)
  add(Drop(pg, 660, 440, 350, "Rotation Direction", { { "cw", "Clockwise" }, { "ccw", "Counter-Clockwise" } },
    function() local r = rot(); return (r and r.dir) or "cw" end,
    function(v) local r = ensureRot(); if r then r.dir = (v ~= "cw") and v or nil; Reapply() end end), spinning)

  -- SOUNDS
  Title(pg, 340, 559, "Sounds")
  local function soundLabel() local c = Cfg(); return (c and c.sound and c.sound.name) or "None" end
  add(PickerDrop(pg, 340, 595, 320, "Sound Effect", soundLabel, function()
    local c = Cfg(); if not c then return end
    X.OpenSoundPicker(function(item)
      if item.file then c.sound = c.sound or {}; c.sound.file = item.file; c.sound.name = item.name; c.sound.channel = "Master"
      else c.sound = nil end
      P.sync()
    end, c.sound and c.sound.file)
  end))
  local play = UI.gButton(pg, "Play", { w = 35 })
  play:SetPoint("TOPLEFT", 670, -618)
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
  add(Drop(pg, 735, 595, 275, "Sound Trigger",
    function() local out = {}; for _, v in ipairs(ON) do out[#out + 1] = { v[1], v[2], alertOff(v[1]) } end; return out end,
    function() local c = Cfg(); return (c and c.sound and c.sound.on) or "trigger" end,
    function(v) local c = Cfg(); if c and c.sound then c.sound.on = v; P.sync() end end), hasSound)
  -- A timing already SET to something impossible has to be said out loud.
  local warn = UI.gLabel(pg, "", 10); warn:SetPoint("TOPLEFT", 735, -638); warn:SetWidth(275)
  warn:SetTextColor(CORAL.r, CORAL.g, CORAL.b); warn:SetJustifyH("LEFT")
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
    if b then
      b:Show()
      local on = Cfg() ~= nil
      for _, r in ipairs(b.rows) do r:refresh(); r:setEnabled(on) end
    end
    local c = Cfg()
    need:SetText((b and c and not c.shape) and "Needs a Shape" or "")
  end
  rows[#rows + 1] = { refresh = function() P.layoutEffects() end, setEnabled = function() end }
  P.layoutEffects()
end

-- ===========================================================================
-- LOAD CONDITIONS (the mock's Frame 466, 320,178, 710 × 390) — built twice from
-- one implementation: for the selected AURA (cfg.visibility, on its page) and
-- for a GROUP (group.visibility, in the pop-up its right-click menu opens).
-- Same engine gate either way.
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
        if ctrl.setEnabled then ctrl:setEnabled(ok) else ctrl:SetEnabled(ok); ctrl:SetAlpha(ok and 1 or 0.5) end
        if ctrl._label then ctrl._label:SetAlpha(ok and 1 or 0.5) end
      end,
    }
    return ctrl
  end
  local function vis() local t = target(); return t and t.visibility end
  local function visW() local t = target(); if not t then return nil end; t.visibility = t.visibility or {}; return t.visibility end

  local title = Title(p, 340, 198, noun .. " Load Conditions")

  -- The master switch: NOT a "load when" — this aura (or group) at all.
  put(Switch(p, 340, 234, "This " .. noun, { { true, "ENABLED" }, { false, "DISABLED" } },
    function() local t = target(); return not (t and t.enabled == false) end,
    function(v)
      local t = target(); if not t then return end
      -- NEVER `t.enabled = v and nil or false` — that is false both ways (the 2026-07-08 wall).
      if v then t.enabled = nil else t.enabled = false end
      if GA.CDM then GA.CDM:Discover() end
      Poke(); X.RefreshList()
    end))

  -- A checkbox row: the box at (x, y + 3.5), the label 10 right of it. 23 apart.
  local function at(b, x, i, y0) b:SetPoint("TOPLEFT", x, -((y0 or 283) + 3.5 + 23 * i)) end
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
    b1 = put(UI.gCheck(p, label1, function() local a = st(); return a end, function(on) local _, b = st(); write(on, b) end))
    b2 = put(UI.gCheck(p, label2, function() local _, b = st(); return b end, function(on) local a = st(); write(a, on) end))
    at(b1, x, i); at(b2, x, i + 1)
  end
  local function single(x, i, label, key)
    at(put(UI.gCheck(p, label, function() local v = vis(); return v and v[key] end,
      function(on) local w = visW(); if w then w[key] = on or nil; Poke() end end)), x, i)
  end
  local L, R = 340, 496
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

  -- The class's specs, one to a line under the left column (the mock's Frame
  -- 372: 21 apart from y 475).
  local specs = X.PlayerSpecs()
  local sboxes = {}
  local function specOn(id) local v = vis(); return (not (v and v.specs)) or (v.specs[id] and true or false) end
  for i, sp in ipairs(specs) do
    local b = put(UI.gCheck(p, sp.name, function() return specOn(sp.id) end, function(on)
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
    b:SetPoint("TOPLEFT", L, -(478.5 + 21 * (i - 1)))
    sboxes[#sboxes + 1] = b
  end

  -- SPELL / TALENT KNOWN — a spell ID; talents count. Commits on Enter and on
  -- losing focus (item 7's lesson: Enter-only left a stale value behind).
  Label(p, 636, 234, "Spell/Talent Known")
  local help = UI.gLabel(p, "", 10); help:SetPoint("TOPLEFT", 636, -277); help:SetAlpha(0.6)
  local function helpText()
    local v = vis(); local id = v and v.spellKnown
    if id then
      local nm = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
      help:SetText(((nm or ("Spell " .. id)) .. " — " .. noun .. " Enabled Only If Known"))
    else
      help:SetText("A spell ID (talents count). Blank = don't check.")
    end
  end
  local sk = UI.gField(p, 374, { numeric = true,
    commit = function(s)
      local w = visW(); if not w then return end
      local id = tonumber(s)
      if id ~= w.spellKnown then w.spellKnown = id; helpText(); Poke() end
    end,
    revert = function(self) self:refresh() end })
  sk:SetPoint("TOPLEFT", 636, -257)
  function sk:refresh() local v = vis(); self:SetText(v and v.spellKnown and tostring(v.spellKnown) or ""); helpText() end
  put(sk)

  -- PLAYER POWER — whole units (UnitPower's fragments are a different scale and
  -- a different question). The type seeds the rule; Off removes it.
  local pwVal
  put(Drop(p, 636, 303, 164, "Player Power", POWERS,
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
  put(Drop(p, 810, 326, 130, nil, OPS,
    function() local v = vis(); return (v and v.power and v.power.op) or "ge" end,
    function(x) local v = visW(); if v and v.power then v.power.op = x; Poke() end end), hasPower)
  pwVal = UI.gField(p, 60, { numeric = true, justify = "CENTER",
    commit = function(s) local v = visW(); if v and v.power then v.power.value = tonumber(s) or 0; Poke() end end,
    revert = function(self) self:refresh() end })
  pwVal:SetPoint("TOPLEFT", 950, -326)
  pwVal:SetTextInsets(0, 0, 0, 0)
  function pwVal:refresh() local v = vis(); self:SetText(v and v.power and v.power.value and tostring(v.power.value) or "") end
  put(pwVal, hasPower)
  return title
end

local function BuildLoad()
  local pg = Page("load")
  P.buildLoad(pg, { sink = rows, target = Cfg, noun = "Aura" })
end

-- The GROUP's load conditions, in a pop-up over the page panel (its right-click
-- menu's "Load Conditions…"). Not mocked: the page's own layout on an opaque
-- plate of the same size and place, with its own X.
local function BuildGroupLoad(c)
  local f = CreateFrame("Frame", nil, c)
  f:SetAllPoints(); f:SetFrameLevel(c:GetFrameLevel() + 60); f:Hide()
  f:EnableMouse(true)   -- the page underneath must not take clicks through it
  local plate = CreateFrame("Frame", nil, f); plate:SetPoint("TOPLEFT", 320, -178); plate:SetSize(710, 390)
  plate:EnableMouse(true)
  local bg = plate:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(COLOR.list.r, COLOR.list.g, COLOR.list.b, 0.98)
  UI.addEdges(plate, VIOLET, 1)
  -- A click anywhere OFF the plate closes it (the rest of the window stays live
  -- underneath the scrim only where the plate is not).
  f:SetScript("OnMouseDown", function(self) self:Hide() end)
  local function grp() local gid = f.gid; return gid and X.Groups() and X.Groups()[gid] end
  local body = CreateFrame("Frame", nil, f); body:SetAllPoints(); body:SetFrameLevel(plate:GetFrameLevel() + 2)
  C._grows = C._grows or {}
  local title = P.buildLoad(body, { sink = C._grows, target = grp, noun = "Group" })
  local x = UI.gX(body, function() f:Hide() end); x:SetPoint("TOPRIGHT", body, "TOPLEFT", 1022, -186)
  local note = UI.gLabel(body, "These gate every aura in the group, ahead of each aura's own conditions.", 11)
  note:SetPoint("TOPLEFT", 636, -370); note:SetWidth(374); note:SetJustifyH("LEFT"); note:SetAlpha(0.6)
  function f:open(gid)
    self.gid = gid
    title:SetText(GroupName(gid) .. " — Load Conditions")
    for _, r in ipairs(C._grows) do r:refresh(); r:setEnabled(true) end
    self:Show()
  end
  f:SetScript("OnHide", function(self) self.gid = nil end)
  P.groupLoad = f
end

-- ===========================================================================
-- Showing a page, and the old editor's hooks
-- ===========================================================================
function P.show(id)
  if id and P.pages[id] then P.cur = id end
  if not P.c then return end
  C.groupSel = nil        -- groups are no longer "selected": they have a menu
  for _, f in pairs(P.pages) do f:Hide() end
  P.empty:Hide()
  if X.DisplayList()[1] == nil then
    P.empty:Show()
  else
    local f = P.pages[P.cur]
    if P.cur == "triggers" then P.renderTriggers()
    elseif P.cur == "effects" then P.layoutEffects() end
    if f then f:Show() end
    if TR.pane then TR.pane:ScrollTo(0) end
  end
  P.syncHeader()
end

-- The previous editor's accordion is gone; its callers find these instead.
function C:AccordionLayout() end
function C:AccordionSetHeight() end
function C:AccordionOpen() end
function C:AccordionToggle() end
function C:TrigInlineRender() P.renderTriggers() end
function C:ShowGroupPane() P.show() end
function C:UpdateEmptyState() P.show() end
function C:SyncRailButtons() P.syncHeader() end
function C:RefreshGroupButton() P.syncHeader() end
function C:OnListRefresh() P.renderList(); P.syncHeader() end
function C:RefreshGroupPane()
  for _, r in ipairs(C._grows or {}) do r:refresh(); r:setEnabled(true) end
  P.syncHeader()
end
-- Anything that still asks to SELECT a group gets its load conditions instead.
function C:SelectGroup(gid)
  if gid and X.Groups() and X.Groups()[gid] and P.groupLoad then P.groupLoad:open(gid) end
end

-- ===========================================================================
-- The tab
-- ===========================================================================
local function BuildTab(c)
  P.c = c
  X.SetContainer(c)
  BuildList(c)
  BuildHeader(c)
  BuildTriggers(); BuildAppearance(); BuildBar(); BuildText(); BuildEffects(); BuildLoad()
  BuildGroupLoad(c)
  -- With no auras there is nothing to edit: one line saying what to click.
  P.empty = UI.gLabel(c, "No auras in this profile yet.\n\nClick New Aura to make one.", 12)
  P.empty:SetPoint("TOPLEFT", 340, -198); P.empty:SetJustifyH("LEFT"); P.empty:SetAlpha(0.7)
  P.empty:Hide()

  -- These fire when the tab gains/loses the window (open/close AND tool switches).
  c:HookScript("OnShow", function()
    if P.hideCDM then P.hideCDM:refresh() end
    if GA.Displays then GA.Displays.forced = true; GA.Displays:SetInteractive(true) end
    C:SelectInitial()   -- straight into the last-edited aura
  end)
  c:HookScript("OnHide", function()
    X.CloseSubWindows()   -- a docked picker must not linger
    if P.groupLoad then P.groupLoad:Hide() end
    if GA.Displays then GA.Displays.forced = false; GA.Displays:SetSelectedDisplay(nil) end
    if GA.CDM and GA.CDM.Discover then GA.CDM:Discover() end
  end)
end

-- The profile row in the Suite window's top bar (same api as before).
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
  title    = "AURAS",
  wordmark = "AURAS",
  order    = 10,
  pages    = {
    { id = "triggers",   title = "Aura Triggers",               bg = GLASS .. "triggers" },
    { id = "appearance", title = "Appearance, Position & Size", bg = GLASS .. "appearance" },
    { id = "bar",        title = "Bar Fill & Readouts",         bg = GLASS .. "bar" },
    { id = "text",       title = "Text",                        bg = GLASS .. "text" },
    { id = "effects",    title = "Effects, Motion & Sound",     bg = GLASS .. "effects" },
    { id = "load",       title = "Aura Load Conditions",        bg = GLASS .. "load" },
  },
  profile  = PROFILE,
  build    = BuildTab,
  showPage = function(id) P.show(id) end,
}
