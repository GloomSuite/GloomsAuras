-- ============================================================
-- Pages.lua — Gloom's Auras
-- The Auras tab, SECOND redesign (2026-09-23), from the owner's Figma page
-- "GloomSuite UI 2" (screens 722:130 Aura Triggers · 724:1226 Appearance ·
-- 726:1963 Bar Fill & Readouts · 736:2645 Text · 736:3132 Effects & Sound ·
-- 736:3639 Load Conditions).
--
-- The Suite window draws the sidebar (the tool switcher, the six page names,
-- the profile control); this file draws what sits right of it: the AURA LIST
-- (x 290–540 in the mocks), the selected aura's HEADER, and one PAGE at a time.
-- ★ Coordinates are the mocks' own, minus the 250 the sidebar takes: every
-- control sits at the mock's x/y (the owner: "I put things where they are for a
-- reason"). Page content is laid out from y = 110, where the scrolling starts.
--
-- It is DRAWING only. Every setting still goes through Config.lua's logic —
-- the trigger tree, the pickers, selection, profiles — exported as C.X. The old
-- editor's section builders in Config.lua are no longer mounted; they are kept
-- as the record of how each control behaves until this one is approved.
--
-- ⚠ Every widget here is the Hub's DARK KIT (LibGloomSkin MINOR 13). It takes
-- its colour from the container the Suite window hands over (Auras' green), so
-- nothing below names the accent unless it means a different colour on purpose.
-- ============================================================

local GA = GloomsAuras
local C = GA and GA.Config
local X = C and C.X
-- ⚠ Not `LibStub and LibStub(...)`: an `and` keeps only the call's FIRST value,
-- so the version number would always come back nil.
local Skin, skinMinor
if LibStub then Skin, skinMinor = LibStub("LibGloomSkin-1.0", true) end
if not (X and Skin) then return end
if (skinMinor or 0) < 13 then
  print("|cffff5555Gloom's Auras|r: the Auras pages need Gloom's Hub with LibGloomSkin 13 or newer — update Gloom's Hub.")
  return
end

local UI, COLOR, FONT = Skin.UI, Skin.COLOR, Skin.FONT
local MEDIA = GA.MEDIA
local JADE, FLAME, CORAL = COLOR.jade, COLOR.flame, COLOR.coral
local DB, Cfg, rows = X.DB, X.Cfg, X.rows

-- The mocks' columns, in the container's coordinates (window x − 250).
local LIST_X, LIST_Y, LIST_W, LIST_H = 40, 60, 250, 640
local COL_X, COL_W = 330, 440          -- the content column (mock x 580–1020)
local PAGE_TOP = 110                   -- the pages scroll from here (window y)
local LIST_ROW_H = 18                  -- the list's line pitch (Saira at leading 18)
local LIST_TOP, LIST_BOTTOM = 104, 615 -- the list's rows live in this band

local P = { pages = {}, order = {}, cur = "triggers", listOffset = 0 }
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

-- A row for the shared list: `ctrl` is a dark-kit control (it has refresh /
-- setEnabled); `gate` (optional) is an extra condition for being usable.
local function add(ctrl, gate)
  local r = {}
  function r:refresh() if ctrl.refresh then ctrl:refresh() end end
  function r:setEnabled(on)
    local ok = on and (not gate or gate())
    if ctrl.setEnabled then ctrl:setEnabled(ok)
    elseif ctrl.SetEnabled then ctrl:SetEnabled(ok); ctrl:SetAlpha(ok and 1 or 0.5) end
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

-- A label + a picker pill underneath it (the mocks' "Frame 316"/"Frame 318":
-- Saira 12, then the pill 23 below). values = { {stored, label[, disabled]} }.
local function Picker(parent, x, y, w, label, values, get, set)
  if label then local l = UI.text(parent, label, 12); l:SetPoint("TOPLEFT", x, -y) end
  local function lbl()
    local cur = get()
    for _, v in ipairs(type(values) == "function" and values() or values) do if v[1] == cur then return v[2] end end
    local first = (type(values) == "function" and values() or values)[1]
    return first and first[2] or "?"
  end
  local p = UI.pillPick(parent, w, lbl,
    function()
      local out = {}
      for _, v in ipairs(type(values) == "function" and values() or values) do
        out[#out + 1] = { value = v[1], label = v[2], disabled = v[3] }
      end
      return out
    end,
    get, function(v) set(v) end)
  p:SetPoint("TOPLEFT", x, -(y + (label and 23 or 0)))
  function p:setEnabled(on) self:SetEnabled(on and true or false); self:SetAlpha(on and 1 or 0.5) end
  return p
end

-- A pill that opens one of GA's own pickers (texture, shape, font, sound).
local function ActionPill(parent, x, y, w, label, getLabel, onClick)
  if label then local l = UI.text(parent, label, 12); l:SetPoint("TOPLEFT", x, -y) end
  local b = UI.pill(parent, "", { w = w, onClick = onClick })
  b:SetPoint("TOPLEFT", x, -(y + (label and 23 or 0)))
  function b:refresh() self:SetLabel(getLabel()) end
  function b:setEnabled(on) self:SetEnabled(on and true or false) end
  b:refresh()
  return b
end

local function Dial(parent, x, y, opts)
  opts.dark = true
  local d = UI.dial(parent, opts)
  d:SetPoint("TOPLEFT", x, -y)
  return d
end

local function Label(parent, x, y, text, size, bold)
  local l = UI.text(parent, text, size or 12, bold); l:SetPoint("TOPLEFT", x, -y)
  return l
end

-- ===========================================================================
-- THE AURA LIST (mock "Group 1": x 290, y 60, 250 × 640)
-- ===========================================================================
-- Rows are the mock's lines, 18 apart: a group header (a white ▾ at x 310, the
-- name in Saira Bold 12 at x 328), its auras (a 12px icon at x 310, the name in
-- Saira 11 at x 328 — the selected one Bold in flame — a red warning triangle
-- after the name when the aura needs one, and the eye at x 506), then
-- "+ ADD NEW AURA" in the accent; 20px between groups.

local listRows = {}

local function listRow(i)
  local r = listRows[i]
  if r then return r end
  r = CreateFrame("Button", nil, P.list)
  r:SetSize(210, LIST_ROW_H)
  r:RegisterForClicks("LeftButtonUp")
  r.tri = r:CreateTexture(nil, "ARTWORK"); r.tri:SetTexture(UI.TRI); r.tri:SetSize(10, 10)
  r.tri:SetPoint("LEFT", 0, 0)
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(12, 12); r.icon:SetPoint("LEFT", 0, 0)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.name = UI.newText(r, FONT.sa, 11, COLOR.paper, "LEFT"); r.name:SetPoint("LEFT", 18, 0)
  r.name:SetWordWrap(false)
  -- The caret's hit area: clicking the ▾ folds a group, clicking its NAME selects it.
  r.fold = CreateFrame("Button", nil, r); r.fold:SetSize(16, LIST_ROW_H); r.fold:SetPoint("LEFT", -3, 0)
  r.fold:SetScript("OnClick", function()
    if r.kind == "group" then
      local g = X.Groups() and X.Groups()[r.gid]
      if g then g.collapsed = (not g.collapsed) or nil; X.RefreshList() end
    elseif r.kind == "ungrouped" then
      GA.db.ungroupedCollapsed = (not GA.db.ungroupedCollapsed) or nil; X.RefreshList()
    end
  end)
  -- The warning: an aura whose cooldown trigger points at a spell the Cooldown
  -- Manager has not bound reads READY forever and shows at every pull (Hub
  -- backlog item 6, "the silent yes"). The owner's triangle, 2026-09-23; the
  -- hover still says what to do about it.
  r.warn = CreateFrame("Button", nil, r); r.warn:SetSize(12, 12)
  local wt = r.warn:CreateTexture(nil, "ARTWORK"); wt:SetAllPoints(); wt:SetTexture(MEDIA .. "warn.png")
  wt:SetVertexColor(CORAL.r, CORAL.g, CORAL.b, 1)
  UI.attachTip(r.warn, "Not in your Cooldown Manager", function() return r.warnText or "" end)
  -- The eye: on screen = flame, hidden = white at 40%. ONE icon; the colour says
  -- which (the owner, 2026-09-23). The selected aura counts as on screen.
  r.eye = CreateFrame("Button", nil, r); r.eye:SetSize(14, 14); r.eye:SetPoint("LEFT", 196, 0)
  r.eye.t = r.eye:CreateTexture(nil, "ARTWORK"); r.eye.t:SetAllPoints(); r.eye.t:SetTexture(MEDIA .. "eye.png")
  r.eye:SetScript("OnClick", function()
    if r.kind ~= "aura" then return end
    local cfg = DB() and DB()[r.id]; if not cfg then return end
    cfg.preview = (not cfg.preview) or nil
    if GA.Displays then GA.Displays:RefreshForced() end
    X.RefreshList()
  end)
  UI.attachTip(r.eye, "Show on screen", "Shows this aura on screen while the panel is open, so you can place it. It does not change whether the aura runs in play.")
  r:SetScript("OnClick", function(self)
    if self.kind == "aura" then X.SetSelected(self.id)
    elseif self.kind == "group" then C:SelectGroup(self.gid)
    elseif self.kind == "ungrouped" then
      GA.db.ungroupedCollapsed = (not GA.db.ungroupedCollapsed) or nil; X.RefreshList()
    elseif self.kind == "add" then P.newAuraMenu(self, self.gid) end
  end)
  r:SetScript("OnDoubleClick", function(self)
    if self.kind == "aura" and self.id then X.SetSelected(self.id); C:RenameSelected() end
  end)
  listRows[i] = r
  return r
end

-- The list as typed lines: every group (header · auras · "+ ADD NEW AURA" · gap),
-- then Ungrouped the same way. With no groups at all it is a flat list and an
-- add line, as before.
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

local function entryH(e) return e.kind == "gap" and 20 or LIST_ROW_H end

function P.renderList()
  if not P.list then return end
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
  local selID, selG = Sel(), C.groupSel
  local y, n = 0, 0
  for i = P.listOffset + 1, #entries do
    local e = entries[i]
    local h = entryH(e)
    if y + h > view then break end
    if e.kind ~= "gap" then
      n = n + 1
      local r = listRow(n)
      r.kind, r.id, r.gid = e.kind, e.id, e.gid
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", P.list, "TOPLEFT", 20, -(LIST_TOP - LIST_Y + y))
      r.tri:Hide(); r.icon:Hide(); r.warn:Hide(); r.eye:Hide(); r.fold:Hide()
      r.name:ClearAllPoints(); r.name:SetPoint("LEFT", 18, 0); r.name:SetWidth(0)
      r.name:SetAlpha(1)
      if e.kind == "group" or e.kind == "ungrouped" then
        local g = e.gid and X.Groups()[e.gid]
        local collapsed = (e.kind == "group" and g and g.collapsed) or (e.kind == "ungrouped" and GA.db and GA.db.ungroupedCollapsed)
        r.tri:Show(); r.tri:SetRotation(collapsed and (math.pi / 2) or 0); r.tri:SetVertexColor(1, 1, 1, 1)
        r.fold:Show()
        UI.setFont(r.name, FONT.saB, 12)
        local txt = (e.kind == "group") and (g and g.name or "Group") or "Ungrouped"
        -- A group SHOWS what it is doing: "(off)" when its switch is off, a dot
        -- when it carries a load rule (kept from the previous list).
        if g and g.enabled == false then txt = txt .. "  |cff888888(off)|r"
        elseif g and g.visibility and next(g.visibility) ~= nil then txt = txt .. ("  |cff%s•|r"):format(JADE.hex) end
        r.name:SetText(txt)
        if e.kind == "group" and e.gid == selG then r.name:SetTextColor(FLAME.r, FLAME.g, FLAME.b)
        else r.name:SetTextColor(1, 1, 1) end
        if g and g.enabled == false then r.name:SetAlpha(0.5) end
      elseif e.kind == "aura" then
        local cfg = DB() and DB()[e.id]
        r.icon:Show(); r.icon:SetTexture(AuraIcon(cfg))
        local isSel = (e.id == selID)
        UI.setFont(r.name, isSel and FONT.saB or FONT.sa, 11)
        r.name:SetText((cfg and cfg.label) or ("Spell " .. tostring(e.id)))
        if isSel then r.name:SetTextColor(FLAME.r, FLAME.g, FLAME.b) else r.name:SetTextColor(1, 1, 1) end
        -- a disabled aura greys (Load Conditions → Disabled)
        if cfg and cfg.enabled == false then r.name:SetAlpha(0.5) end
        local warnText = cfg and C:SilentYesText(cfg)
        r.warnText = warnText
        -- Cap a name only when it is too long for the row: pinning every name to its
        -- own measured width lets rounding shave the last letter (or add a "…").
        local maxW = 196 - 18 - (warnText and 20 or 6)
        local w = math.ceil(r.name:GetStringWidth())
        if w > maxW then w = maxW; r.name:SetWidth(maxW) end
        if warnText then r.warn:ClearAllPoints(); r.warn:SetPoint("LEFT", 18 + w + 4, 0); r.warn:Show() end
        r.eye:Show()
        local on = isSel or (cfg and cfg.preview)
        if on then r.eye.t:SetVertexColor(FLAME.r, FLAME.g, FLAME.b, 1) else r.eye.t:SetVertexColor(1, 1, 1, 0.4) end
      elseif e.kind == "add" then
        UI.setFont(r.name, FONT.sa, 11)
        r.name:SetText("+ ADD NEW AURA"); r.name:SetTextColor(JADE.r, JADE.g, JADE.b)
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
  UI.openList(anchor, { { value = "icon", label = "Icon Aura" }, { value = "texture", label = "Texture Aura" },
                        { value = "bar", label = "Bar Aura" } }, nil,
    function(uiType)
      C:CreateAura(uiType)
      local cfg = Cfg()
      if cfg and gid then cfg.group = gid; X.RefreshList(); P.syncHeader() end
    end)
end

local function BuildList(c)
  local list = UI.plate(c)
  list:SetPoint("TOPLEFT", LIST_X, -LIST_Y); list:SetSize(LIST_W, LIST_H)
  P.list = list
  Label(list, 20, 20, "Aura Groups", 14)
  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", function(_, d)
    P.listOffset = math.max(0, math.min(P.listMax or 0, (P.listOffset or 0) - d)); P.renderList()
  end)
  -- the scrollbar, in the plate's right margin, only while the list overflows
  local track = CreateFrame("Frame", nil, list); track:SetWidth(4)
  track:SetPoint("TOPRIGHT", -8, -(LIST_TOP - LIST_Y)); track:SetHeight(LIST_BOTTOM - LIST_TOP)
  local tt = track:CreateTexture(nil, "BACKGROUND"); tt:SetAllPoints(); tt:SetColorTexture(JADE.r, JADE.g, JADE.b, 0.1)
  local thumb = CreateFrame("Button", nil, track); thumb:SetWidth(4)
  local th = thumb:CreateTexture(nil, "ARTWORK"); th:SetAllPoints(); th:SetColorTexture(JADE.r, JADE.g, JADE.b, 0.7)
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

  -- Hide Blizzard's own Cooldown Manager — a PROFILE setting, not an aura's, so
  -- it lives with the list rather than on any page. (Not in the mocks: it sat in
  -- the old footer, which the new window does not have.) Drives viewer alpha
  -- only, never Hide(), so GA's mirror keeps working.
  local hide = UI.box(list, "Hide Blizzard's Cooldown Manager",
    function() return GA.db and GA.db.hideBlizzardCDM end,
    function(on) if GA.CDM and GA.CDM.ToggleBlizzardHide then GA.CDM:ToggleBlizzardHide(on) end end)
  hide:SetPoint("TOPLEFT", 20, -(627 - LIST_Y))
  function hide:Set() self:refresh() end   -- C:OnProfileSwitched re-syncs it this way
  C._hideCDM = hide
  P.hideCDM = hide

  local newA = UI.pill(list, "New Aura", { w = 100 })
  newA:SetPoint("TOPLEFT", 20, -(655 - LIST_Y))
  newA:SetScript("OnClick", function(self) P.newAuraMenu(self, nil) end)
  UI.attachTip(newA, "New aura", "Creates a blank aura and opens it for editing. Pick the kind: Icon, Texture or Bar.")
  local newG = UI.pill(list, "New Group", { w = 100 })
  newG:SetPoint("TOPLEFT", 130, -(655 - LIST_Y))
  newG:SetScript("OnClick", function()
    X.OpenNameDialog("New Group", "", function(nm)
      if not nm or nm:gsub("%s", "") == "" then return end
      local gid = X.CreateGroup(nm)
      if gid then X.RefreshList(); C:SelectGroup(gid) end
    end)
  end)
  UI.attachTip(newG, "New group", "Groups hold a set of auras that load together: one load rule and one on/off switch gate every aura inside. Click a group's name to edit it.")
end

-- ===========================================================================
-- THE HEADER (mock "Frame 295" at 580,60 · Duplicate/Delete at 831/938,60)
-- ===========================================================================
-- The selected aura's icon (28px), its name (Saira 14) and its group (Saira 10)
-- — click the name to rename it, the group line to move it to another group.
-- With a GROUP selected the same place names the group and its buttons become
-- Rename Group / Delete Group.

function P.syncHeader()
  local h = P.header; if not h then return end
  local cfg, gid = Cfg(), C.groupSel
  if gid and X.Groups() and X.Groups()[gid] then
    h:Show(); h.icon:Hide()
    h.name:ClearAllPoints(); h.name:SetPoint("TOPLEFT", h, "TOPLEFT", 0, -1)
    h.name:SetText(GroupName(gid)); h.group:SetText("Group settings")
    h.nameHit:SetScript("OnClick", nil); h.groupHit:SetScript("OnClick", nil)
    h.dup:SetLabel("Rename Group"); h.del:SetLabel("Delete Group")
  elseif cfg then
    h:Show(); h.icon:Show(); h.icon:SetTexture(AuraIcon(cfg))
    h.name:ClearAllPoints(); h.name:SetPoint("TOPLEFT", h, "TOPLEFT", 38, -1)
    h.name:SetText(cfg.label or "Aura"); h.group:SetText("Group: " .. GroupName(cfg.group))
    h.nameHit:SetScript("OnClick", function() C:RenameSelected() end)
    h.groupHit:SetScript("OnClick", function(self) P.groupMenu(self) end)
    h.dup:SetLabel("Duplicate Aura"); h.del:SetLabel("Delete Aura")
  else
    h:Hide(); return
  end
  h.del:ClearAllPoints(); h.del:SetPoint("TOPRIGHT", P.c, "TOPLEFT", COL_X + COL_W, -60)
  h.dup:ClearAllPoints(); h.dup:SetPoint("TOPRIGHT", h.del, "TOPLEFT", -10, 0)
  h.nameHit:SetWidth(math.max(10, h.name:GetStringWidth())); h.groupHit:SetWidth(math.max(10, h.group:GetStringWidth()))
end

-- Move the selected aura to another group (or out of every group, or into a new one).
function P.groupMenu(anchor)
  local cfg = Cfg(); if not cfg then return end
  local items = { { value = "__none", label = "Ungrouped" } }
  for _, gid in ipairs(X.GroupList()) do items[#items + 1] = { value = gid, label = GroupName(gid) } end
  items[#items + 1] = { value = "__new", label = "+ New Group…" }
  UI.openList(anchor, items, cfg.group or "__none", function(v)
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
  end)
end

local function BuildHeader(c)
  local h = CreateFrame("Frame", nil, c)
  h:SetPoint("TOPLEFT", COL_X, -60); h:SetSize(COL_W - 210, 28)
  P.header = h
  h.icon = h:CreateTexture(nil, "ARTWORK"); h.icon:SetSize(28, 28); h.icon:SetPoint("TOPLEFT", 0, 0)
  h.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  h.name = UI.newText(h, FONT.sa, 14, COLOR.paper, "LEFT"); h.name:SetWordWrap(false)
  h.group = UI.newText(h, FONT.sa, 10, COLOR.paper, "LEFT")
  h.group:SetPoint("TOPLEFT", h.name, "BOTTOMLEFT", 0, -2)
  h.nameHit = CreateFrame("Button", nil, h); h.nameHit:SetHeight(16)
  h.nameHit:SetPoint("TOPLEFT", h.name, "TOPLEFT", 0, 1)
  UI.attachTip(h.nameHit, "Rename", "Click to rename this aura in the list. (The text it draws on screen is a separate setting, on the Text page.)")
  h.groupHit = CreateFrame("Button", nil, h); h.groupHit:SetHeight(12)
  h.groupHit:SetPoint("TOPLEFT", h.group, "TOPLEFT", 0, 0)
  UI.attachTip(h.groupHit, "Group", "Click to move this aura to another group.")

  -- The two buttons ride on the header, so they hide with it when nothing is selected.
  h.dup = UI.pill(h, "Duplicate Aura")
  h.dup:SetScript("OnClick", function()
    if C.groupSel then
      local g = X.Groups() and X.Groups()[C.groupSel]; if not g then return end
      X.OpenNameDialog("Rename Group", g.name or "", function(nm)
        if not nm or nm:gsub("%s", "") == "" then return end
        g.name = nm; X.RefreshList(); P.syncHeader()
      end)
      return
    end
    local id = Sel(); if not (id and DB() and DB()[id]) then return end
    local copy = X.DeepCopy(DB()[id]); copy.label = (copy.label or "Aura") .. " (copy)"
    local p = copy.point or { "CENTER", 0, 0 }; copy.point = { "CENTER", (p[2] or 0) + 24, (p[3] or 0) - 24 }
    local nid = X.NewDisplayID(); DB()[nid] = copy
    if GA.CDM then GA.CDM:Discover() end
    X.SetSelected(nid)
  end)
  -- Deleting CONFIRMS (CONTRACTS §4); a group's auras are never deleted with it.
  h.del = UI.pill(h, "Delete Aura", { danger = true })
  h.del:SetScript("OnClick", function()
    if C.groupSel then
      local gid = C.groupSel; local g = X.Groups() and X.Groups()[gid]; if not g then return end
      C:OpenConfirm(("Delete the group \"%s\"?  Its auras aren't deleted — they move to Ungrouped."):format(g.name or "?"), function()
        local gone = X.DeleteGroup(gid)
        if gone then GA.msg(("deleted group |cffffffff%s|r — its auras moved to Ungrouped."):format(gone)) end
        C.groupSel = nil
        X.RefreshList(); C:SelectInitial()
        Poke()
      end)
      return
    end
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

-- A page: a frame on the scrolling pane, 440 wide, shown one at a time.
local function Page(id)
  local f = CreateFrame("Frame", nil, P.pane.child)
  f:SetPoint("TOPLEFT", 0, 0); f:SetSize(COL_W, 10); f:Hide()
  P.pages[id] = f
  return f
end

-- ===========================================================================
-- PAGE · AURA TRIGGERS (722:130)
-- ===========================================================================
-- Match ALL / ANY / NONE (the chosen one at 30%), then the conditions in one
-- column: a condition is a 39-tall row — its spell, the spell's icon, "is", the
-- state in a pill (click to change it), the X; a TRIGGER GROUP is a plate with
-- its own Match pills and X, holding its conditions as rows. 20 between items,
-- 10 between a group's rows. Then Add a Trigger and Create Trigger Group.
--
-- ★ Grouping is by DRAG (the owner, 2026-09-23): make a group at any time, then
-- drag conditions into it — or back out onto the page. Shift+click is gone. A
-- group's X deletes the GROUP only: its conditions drop back to the top level,
-- where each can still be deleted on its own. The engine already ignores an
-- empty group, so one waiting to be filled never changes whether the aura shows.
local TR = { rows = {}, groups = {} }
P.TR = TR
local TRIG_ROW_H = 39

-- "ACTIVE on Target (Debuff)" → "Active on Target (Debuff)" — the mocks' casing.
local function StateText(state, k)
  local main, suf = X.TrigPill(state, k)
  main = (main or "?"):gsub("(%u)(%u+)", function(a, b) return a .. b:lower() end)
  return main .. (suf or "")
end

local function MakeLeaf(parent)
  local r = CreateFrame("Button", nil, parent); r:SetHeight(TRIG_ROW_H)
  r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(JADE.r, JADE.g, JADE.b, 0.1)
  local edge = CreateFrame("Frame", nil, r); edge:SetAllPoints()
  UI.addEdges(edge, { r = JADE.r, g = JADE.g, b = JADE.b, a = 0.1 }, 1)
  r.name = UI.text(r, "", 11); r.name:SetPoint("LEFT", 20, 0)
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(12, 12)
  r.icon:SetPoint("LEFT", r.name, "RIGHT", 4, 0); r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.is = UI.text(r, "is", 11); r.is:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
  r.pill = UI.pill(r, "", { selected = true })
  r.pill:SetPoint("LEFT", r.is, "RIGHT", 4, 0)
  r.pill:SetScript("OnClick", function() C:TrigCycleState(r._ti, r._ci) end)
  UI.attachTip(r.pill, "Condition", "Click to step through what this condition checks for.")
  r.x = UI.xbtn(r, function() C:TrigRemove(r._ti, r._ci) end); r.x:SetPoint("RIGHT", -10, 0)
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

local function MakeGroup(parent)
  local g = CreateFrame("Frame", nil, parent)
  g.bg = g:CreateTexture(nil, "BACKGROUND"); g.bg:SetAllPoints(); g.bg:SetColorTexture(JADE.r, JADE.g, JADE.b, 0.1)
  g.label = UI.text(g, "Trigger Group", 12, true); g.label:SetTextColor(JADE.r, JADE.g, JADE.b)
  g.label:SetPoint("TOPLEFT", 16, -10)
  g.x = UI.xbtn(g, function() P.dissolveGroup(g._ti) end); g.x:SetPoint("TOPRIGHT", -16, -10.5)
  UI.attachTip(g.x, "Delete group", "Deletes the group. Its conditions stay — they move back to the top level.")
  g.match = {}
  local prev = g.x
  for i = #LOGICS, 1, -1 do
    local lg = LOGICS[i]
    local b = UI.pill(g, "Match " .. lg[2], { h = 22 })
    b:SetPoint("RIGHT", prev, "LEFT", -6, 0)
    b._logic = lg[1]
    b:SetScript("OnClick", function()
      if not g._node then return end
      g._node.logic = lg[1]
      if GA.CDM then GA.CDM:RefreshDisplays() end
      P.renderTriggers()
    end)
    g.match[i] = b
    prev = b
  end
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
    local b = gh:CreateTexture(nil, "BACKGROUND"); b:SetAllPoints(); b:SetColorTexture(JADE.r, JADE.g, JADE.b, 0.35)
    gh.text = UI.text(gh, "", 11); gh.text:SetPoint("LEFT", 12, 0)
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
      if g:IsShown() then g.bg:SetColorTexture(JADE.r, JADE.g, JADE.b, g:IsMouseOver() and 0.25 or 0.1) end
    end
  end)
  gh:Show()
end

function P.trigDragStop(row)
  local d = TR.dragging; TR.dragging = nil
  if TR.ghost then TR.ghost:Hide() end
  if not d then return end
  local t = C:TrigTree(); if not t then P.renderTriggers(); return end
  local target
  for _, g in ipairs(TR.groups) do
    if g:IsShown() and g:IsMouseOver() then target = g._node end
  end
  local toTop = (not target) and TR.page:IsMouseOver()
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
  local pg = TR.page; if not pg then return end
  local cfg = Cfg()
  local t = cfg and cfg.trigger                -- may be nil: viewing never creates one
  local logic = (t and t.logic) or "AND"
  for _, b in ipairs(TR.match) do b:SetSelected(b._logic == logic); b:SetEnabled(cfg ~= nil) end
  local conds = (t and t.conditions) or {}
  local y, nr, ng = 73, 0, 0
  for ti, node in ipairs(conds) do
    if node.conditions then
      ng = ng + 1
      local g = TR.groups[ng]; if not g then g = MakeGroup(pg); TR.groups[ng] = g end
      g._ti, g._node = ti, node
      g.bg:SetColorTexture(JADE.r, JADE.g, JADE.b, 0.1)
      for _, b in ipairs(g.match) do b:SetSelected(b._logic == (node.logic or "AND")) end
      local gy = 42
      for ci, child in ipairs(node.conditions) do
        local r = g.rows[ci]; if not r then r = MakeLeaf(g); g.rows[ci] = r end
        FillLeaf(r, ti, ci, child)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 16, -gy); r:SetPoint("TOPRIGHT", -16, -gy); r:Show()
        gy = gy + TRIG_ROW_H + 10
      end
      for i = #node.conditions + 1, #g.rows do g.rows[i]:Hide() end
      local gh = (#node.conditions > 0) and (gy - 10 + 20) or 42
      g:ClearAllPoints(); g:SetPoint("TOPLEFT", 0, -y); g:SetSize(COL_W, gh); g:Show()
      y = y + gh + 20
    else
      nr = nr + 1
      local r = TR.rows[nr]; if not r then r = MakeLeaf(pg); TR.rows[nr] = r end
      FillLeaf(r, ti, nil, node)
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetWidth(COL_W); r:Show()
      y = y + TRIG_ROW_H + 20
    end
  end
  for i = nr + 1, #TR.rows do TR.rows[i]:Hide() end
  for i = ng + 1, #TR.groups do TR.groups[i]:Hide() end
  local by = (#conds > 0) and (y - 20 + 30) or 73
  TR.addT:ClearAllPoints(); TR.addT:SetPoint("TOPLEFT", 0, -by)
  TR.addG:ClearAllPoints(); TR.addG:SetPoint("TOPRIGHT", pg, "TOPLEFT", COL_W, -by)
  TR.addT:SetEnabled(cfg ~= nil); TR.addG:SetEnabled(cfg ~= nil)
  pg.height = by + 25 + 20
  pg:SetHeight(pg.height)
  if P.cur == "triggers" and P.pane and not C.groupSel then P.pane:SetContentHeight(pg.height) end
end

local function BuildTriggers()
  local pg = Page("triggers"); TR.page = pg
  TR.match = {}
  local x = 0
  for i, lg in ipairs(LOGICS) do
    local b = UI.pill(pg, "Match " .. lg[2])
    b:SetPoint("TOPLEFT", x, -18)
    b._logic = lg[1]
    b:SetScript("OnClick", function()
      local tr = C:TrigTree(); if not tr then return end
      tr.logic = lg[1]
      if GA.CDM then GA.CDM:RefreshDisplays() end
      P.renderTriggers()
    end)
    TR.match[i] = b
    x = x + b:GetWidth() + 10
  end
  TR.addT = UI.pill(pg, "Add a Trigger")
  TR.addT:SetScript("OnClick", function() X.OpenPicker(function(item) C:TrigAddLeaf(item, nil) end) end)
  TR.addG = UI.pill(pg, "Create Trigger Group")
  TR.addG:SetScript("OnClick", function() C:TrigAddGroup() end)
  UI.attachTip(TR.addG, "Trigger group", "Adds an empty group. Drag conditions into it; its own Match decides how they combine.")
end

-- ===========================================================================
-- PAGE · APPEARANCE, POSITION & SIZE (724:1226)
-- ===========================================================================
local function BuildAppearance()
  local pg = Page("appearance")
  local ap = UI.plate(pg, "APPEARANCE"); ap:SetPoint("TOPLEFT", 0, -18); ap:SetSize(COL_W, 334)

  -- Icon/Art: the texture — a file path or an icon ID — typed, or chosen. Blank
  -- means "the first trigger's icon". (A number typed here is stored as a
  -- number, which is what an ID is.)
  Label(ap, 16, 42, "Icon/Art")
  local tf = UI.pillField(ap, 230, {
    placeholder = "Blank = the first trigger's icon",
    button = { label = "Choose", onClick = function()
      local c = Cfg(); if not c then return end
      X.OpenTexturePicker(function(tex) c.texture = tex; Reapply(); P.sync(); X.RefreshList(); P.syncHeader() end, c.texture)
    end },
    commit = function(txt)
      local c = Cfg(); if not c then return end
      local v = (txt or ""):match("^%s*(.-)%s*$")
      if v == "" then v = nil elseif tonumber(v) then v = tonumber(v) end
      if v ~= c.texture then c.texture = v; Reapply(); X.RefreshList(); P.syncHeader() end
    end,
    revert = function(self) self:refresh() end,
  })
  tf:SetPoint("TOPLEFT", 16, -65)
  function tf:refresh() local c = Cfg(); local v = c and c.texture; self:SetText(v ~= nil and tostring(v) or ""); self:SetCursorPosition(0) end
  add(tf)

  -- Shape: a STENCIL cut through that texture — it draws nothing itself, and it
  -- is what an animation traces. (Most shapes crop very little off an icon; see
  -- FINDINGS §14 before calling one broken.)
  add(ActionPill(ap, 273, 42, 151, "Shape/Silhouette",
    function()
      local c = Cfg(); local k = c and c.shape
      if not k then return "None" end
      local info = GloomsHub.ShapeInfo and GloomsHub:ShapeInfo(k)
      return (info and info.label) or k
    end,
    function()
      local c = Cfg(); if not c then return end
      X.OpenShapePicker(function(key) c.shape = key; Reapply(); P.sync() end, c.shape)
    end))

  local r1 = UI.rule(ap); r1:SetPoint("TOPLEFT", 16, -109.5); r1:SetPoint("TOPRIGHT", -16, -109.5)

  add(UI.colorDot(ap, { label = "Recolor:", title = "Recolor",
    get = function() local c = Cfg(); return c and c.color end,
    set = function(v) local c = Cfg(); if c then c.color = v; Reapply() end end })):SetPoint("TOPLEFT", 16, -129)
  add(UI.box(ap, "Desaturate",
    function() local c = Cfg(); return c and c.desaturate end,
    function(on) local c = Cfg(); if c then c.desaturate = on or nil; Reapply() end end)):SetPoint("TOPLEFT", 180, -131.5)
  -- Effects only: no artwork, just the glow and the animation — for laying over
  -- a real action button. Distinct from a blank texture, which means "work it out".
  local eo = add(UI.box(ap, "Effects Only",
    function() local c = Cfg(); return c and c.noArt end,
    function(on) local c = Cfg(); if c then c.noArt = on or nil; Reapply(); P.sync() end end))
  eo:SetPoint("TOPLEFT", 331, -131.5)
  UI.attachTip(eo, "Effects only", "The aura draws no artwork — just its glow and animation. For laying over a real action button.")

  local r2 = UI.rule(ap); r2:SetPoint("TOPLEFT", 16, -169.5); r2:SetPoint("TOPRIGHT", -16, -169.5)

  add(Picker(ap, 16, 190, 168, "Blend Mode", X.BLEND_MODES,
    function() local c = Cfg(); return (c and c.blend) or "BLEND" end,
    function(v) local c = Cfg(); if c then c.blend = (v ~= "BLEND") and v or nil; Reapply() end end))
  add(Dial(ap, 16, 248, { label = "Opacity", min = 0, max = 100, step = 1, unit = "%", dragPx = 500,
    get = function() local c = Cfg(); return c and math.floor(((c.alpha or 1) * 100) + 0.5) end,
    set = function(v) local c = Cfg(); if c then c.alpha = v / 100; Reapply() end end }))

  -- Strata and the level within it, on their own inset plate (the mock's).
  local sub = UI.plate(ap); sub:SetPoint("TOPLEFT", 214, -190); sub:SetSize(200, 124)
  add(Picker(sub, 16, 10, 168, "Strata", X.STRATA_MODES,
    function() local c = Cfg(); return (c and c.strata) or "HIGH" end,
    function(v) local c = Cfg(); if c then c.strata = (v ~= "HIGH") and v or nil; Reapply() end end))
  -- LEVEL is new with this page (2026-09-23; Displays.lua applies it): 0 = Auto,
  -- the frame's own level.
  add(Dial(sub, 16, 68, { label = "Level", min = 0, max = 500, step = 1, dragPx = 1000,
    fmt = function(v) v = math.floor(v + 0.5); return v == 0 and "Auto" or tostring(v) end,
    get = function() local c = Cfg(); return (c and c.level) or 0 end,
    set = function(v) local c = Cfg(); if c then c.level = (v > 0) and v or nil; Reapply() end end }))

  -- POSITION
  local pos = UI.plate(pg, "POSITION"); pos:SetPoint("TOPLEFT", 0, -380); pos:SetSize(205, 202)
  add(Dial(pos, 16, 42, { label = "Horizontal Offset", min = -2000, max = 2000, step = 1, unit = "px", dragPx = 1600,
    get = function() local c = Cfg(); return c and c.point and c.point[2] or 0 end,
    set = function(v) local c = Cfg(); if c then c.point = { "CENTER", v, (c.point and c.point[3]) or 0 }; Reapply() end end }))
  add(Dial(pos, 16, 92, { label = "Vertical Offset", min = -2000, max = 2000, step = 1, unit = "px", dragPx = 1600,
    get = function() local c = Cfg(); return c and c.point and c.point[3] or 0 end,
    set = function(v) local c = Cfg(); if c then c.point = { "CENTER", (c.point and c.point[2]) or 0, v }; Reapply() end end }))
  -- Fixed rotation, positive = clockwise; it shares one AnimationGroup with the
  -- spin (Effects page), so the angle is where a spin starts from.
  add(Dial(pos, 16, 142, { label = "Rotation", min = 0, max = 359, step = 1, unit = "°", dragPx = 720,
    get = function() local c = Cfg(); return (c and c.angle) or 0 end,
    set = function(v) local c = Cfg(); if c then c.angle = (v ~= 0) and v or nil; Reapply() end end }))

  -- SIZE. Width and height can be LOCKED together — the lock beside the title
  -- (not in the mock; the old editor had it, and an aura saved locked would
  -- otherwise have no way to come unlocked).
  local size = UI.plate(pg, "SIZE"); size:SetPoint("TOPLEFT", 235, -380); size:SetSize(205, 152)
  local wDial, hDial
  local function clampDim(n) return math.max(8, math.min(8192, math.floor(n + 0.5))) end
  wDial = add(Dial(size, 16, 42, { label = "Width", min = 8, max = 8192, step = 1, unit = "px", dragPx = 4000,
    get = function() local c = Cfg(); return c and (c.width or c.size) or 64 end,
    set = function(v)
      local c = Cfg(); if not c then return end
      c.width = v
      if c.lockAspect then c.height = clampDim(v / (c.aspect or 1)); if hDial then hDial:refresh() end end
      Reapply()
    end }))
  hDial = add(Dial(size, 16, 92, { label = "Height", min = 8, max = 8192, step = 1, unit = "px", dragPx = 4000,
    get = function() local c = Cfg(); return c and (c.height or c.size) or 64 end,
    set = function(v)
      local c = Cfg(); if not c then return end
      c.height = v
      if c.lockAspect then c.width = clampDim(v * (c.aspect or 1)); if wDial then wDial:refresh() end end
      Reapply()
    end }))
  local lock = CreateFrame("Button", nil, size); lock:SetSize(14, 14); lock:SetPoint("TOPRIGHT", -16, -12)
  local lt = lock:CreateTexture(nil, "ARTWORK"); lt:SetAllPoints()
  function lock:refresh()
    local c = Cfg(); local on = c and c.lockAspect
    lt:SetTexture(MEDIA .. (on and "lock_locked.png" or "lock_unlocked.png"))
    if on then lt:SetVertexColor(JADE.r, JADE.g, JADE.b, 1) else lt:SetVertexColor(1, 1, 1, 0.4) end
  end
  lock:SetScript("OnClick", function(self)
    local c = Cfg(); if not c then return end
    local on = not c.lockAspect; c.lockAspect = on or nil
    if on then local w, h = (c.width or c.size or 64), (c.height or c.size or 64); c.aspect = (h > 0) and (w / h) or 1 end
    self:refresh()
  end)
  UI.attachTip(lock, "Lock the proportions", "While locked, changing the width changes the height with it, and the other way round.")
  add(lock)

  pg.height = 380 + 202 + 20
end

-- ===========================================================================
-- PAGE · BAR FILL & READOUTS (726:1963)
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

  local bs = UI.plate(pg, "BAR SETTINGS"); bs:SetPoint("TOPLEFT", 0, -18); bs:SetSize(COL_W, 311)
  BAR.settings = bs
  -- Said where it is useful rather than left as a page that silently does nothing.
  local note = UI.text(bs, "", 11); note:SetPoint("TOPRIGHT", -16, -13); note:SetAlpha(0.6)
  BAR.note = note

  local MODES = { { "aura_dur", "Aura Duration" }, { "cd_dur", "Cooldown" }, { "stacks", "Stack Count" } }
  add(Picker(bs, 16, 42, 230, "Bar Type", MODES, mode, function(v)
    local b = ensure(); if not b then return end
    b.mode = v
    -- Leaving duration mode must RELEASE the engine's slot, or its button keeps
    -- painting a drain over a bar that now means something else.
    if GA.AuraDuration and Sel() then GA.AuraDuration:Detach(Sel()) end
    repaint(); P.layoutBar(); P.sync()
  end), isBar)
  -- Changing the axis SWAPS width and height: a 220 × 24 bar stood on end is 24
  -- wide and 220 tall, which is what anyone means by it.
  local ORIENT = { { "HORIZONTAL", "Horizontal" }, { "VERTICAL", "Vertical" } }
  add(Picker(bs, 276, 42, 148, "Orientation", ORIENT,
    function() local b = get(); return (b and b.orientation == "VERTICAL") and "VERTICAL" or "HORIZONTAL" end,
    function(v)
      local c = Cfg(); local b = ensure(); if not (b and c) then return end
      local wasVert, nowVert = (b.orientation == "VERTICAL"), (v == "VERTICAL")
      b.orientation = nowVert and "VERTICAL" or nil
      if wasVert ~= nowVert then c.width, c.height = (c.height or 24), (c.width or 220) end
      repaint(); P.sync()
    end), isBar)
  local DIRS = { { "drain", "Drains Down" }, { "fill", "Fills Up" } }
  add(Picker(bs, 16, 100, 230, "Bar Fill Direction", DIRS,
    function() local b = get(); return (b and b.fill == "fill") and "fill" or "drain" end,
    function(v) local b = ensure(); if b then b.fill = (v == "fill") and "fill" or nil; repaint() end end), isBar)
  add(UI.box(bs, "Reverse Fill",
    function() local b = get(); return (b and b.reverse) == true end,
    function(on) local b = ensure(); if b then b.reverse = on or nil; repaint() end end), isBar):SetPoint("TOPLEFT", 276, -126.5)

  -- The fill texture (Shared Media bar textures only). RIGHT-CLICK clears it back
  -- to a plain colour fill — the picker has no "none" row, and without a way back
  -- a texture was a one-way door (the old editor's Clear button; not in the mock).
  local function texName(p)
    if type(p) ~= "string" or p == "" then return "Plain color" end
    return p:match("([^\\/]+)%.%w+$") or p:match("([^\\/]+)$") or p
  end
  local tex = add(ActionPill(bs, 16, 158, 230, "Bar Texture",
    function() local b = get(); return texName(b and b.texture) end,
    function() end), isBar)
  tex:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  tex:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
      local b2 = ensure(); if b2 then b2.texture = nil; self:refresh(); repaint() end
      return
    end
    local b = get(); if not b and not ensure() then return end
    X.OpenTexturePicker(function(path)
      local b2 = ensure(); if not b2 then return end
      b2.texture = (type(path) == "string" and path ~= "") and path or nil
      tex:refresh(); repaint()
    end, (get() or {}).texture, "lsm")
  end)
  UI.attachTip(tex, "Bar texture", "Click to choose a fill texture. Right-click to go back to a plain color fill.")
  -- Rotate Texture: without it a gradient drawn for a horizontal bar stays
  -- horizontal when the bar is stood on end.
  add(UI.box(bs, "Rotate Texture",
    function() local b = get(); return (b and b.rotateTexture) == true end,
    function(on) local b = ensure(); if b then b.rotateTexture = on or nil; repaint() end end), isBar):SetPoint("TOPLEFT", 276, -184.5)

  local r1 = UI.rule(bs); r1:SetPoint("TOPLEFT", 16, -225.5); r1:SetPoint("TOPRIGHT", -16, -225.5)

  local function colorAt(x, label, key, title)
    Label(bs, x, 246, label)
    add(UI.colorDot(bs, { title = title or label,
      get = function() local b = get(); return b and b[key] end,
      set = function(v) local b = ensure(); if b then b[key] = v; repaint() end end }), isBar):SetPoint("TOPLEFT", x, -269)
  end
  colorAt(16, "Bar Fill Color", "color")
  colorAt(126, "Background Color", "bg")
  -- The BACKDROP turns this colour while the DoT is in its pandemic window — the
  -- backdrop, not the fill: the fill is the engine's and cannot be recoloured in
  -- combat (HANDOFF, 2026-09-19 — do not re-offer the fill).
  colorAt(264, "Pandemic Background", "pandemicBg")

  -- Stacks Max — the count a full bar stands for. Only in Stack Count mode, so
  -- it only EXISTS then (it is that mode's own face). Not in the mock.
  local mx = add(Dial(bs, 16, 311, { label = "Stacks Max", min = 1, max = 40, step = 1, dragPx = 300,
    get = function() local b = get(); return (b and b.max) or 10 end,
    set = function(v) local b = ensure(); if b then b.max = v; repaint() end end }), isBar)
  BAR.max = mx

  -- TEXT SETTINGS — the two readouts a bar can carry. One font for both: two
  -- typefaces on one 22px bar would read as an accident.
  local ts = UI.plate(pg, "TEXT SETTINGS"); ts:SetSize(COL_W, 302)
  BAR.text = ts
  add(ActionPill(ts, 16, 42, 408, "Font",
    function() local b = get(); return X.fontNameFor(b and b.font) end,
    function()
      local b = ensure(); if not b then return end
      X.OpenFontPicker(function(path) local b2 = ensure(); if b2 then b2.font = path; repaint(); P.sync() end end, b.font)
    end), isBar)
  local sub = UI.plate(ts); sub:SetPoint("TOPLEFT", 16, -100); sub:SetSize(408, 182)
  local ANCHORS = { { "CENTER", "Center" }, { "TOP", "Top" }, { "BOTTOM", "Bottom" }, { "LEFT", "Left" }, { "RIGHT", "Right" } }
  local OFFON = { { false, "Off" }, { true, "On" } }
  local function readout(x, label, showKey, colorKey, sizeKey, anchorKey, anchorDefault, gate)
    Label(sub, x, 10, label)
    add(UI.toggle2(sub, OFFON,
      function() local b = get(); return (b and b[showKey]) == true end,
      function(v) local b = ensure(); if b then b[showKey] = v or nil; repaint(); P.sync() end end), isBar):SetPoint("TOPLEFT", x, -33)
    Label(sub, x + 118, 10, "Text Color")
    add(UI.colorDot(sub, { title = label .. " Color",
      get = function() local b = get(); return b and b[colorKey] end,
      set = function(v) local b = ensure(); if b then b[colorKey] = v; repaint() end end }), gate):SetPoint("TOPLEFT", x + 118, -33)
    add(Dial(sub, x, 68, { label = label .. " Size", min = 8, max = 32, step = 1, unit = "px", dragPx = 300,
      get = function() local b = get(); return (b and b[sizeKey]) or 14 end,
      set = function(v) local b = ensure(); if b then b[sizeKey] = v; repaint() end end }), gate)
    add(Picker(sub, x, 118, 118, "Position", ANCHORS,
      function() local b = get(); return (b and b[anchorKey]) or anchorDefault end,
      function(v) local b = ensure(); if b then b[anchorKey] = v; repaint() end end), gate)
  end
  -- Stacks default to TOP and the countdown to CENTER, so switched on together
  -- they never print on top of each other.
  readout(16, "Stack Text", "showStacks", "stackColor", "stackSize", "stackAnchor", "TOP", stacksOn)
  readout(219, "Countdown Text", "showTimer", "timerColor", "timerSize", "timerAnchor", "CENTER", timerOn)

  function P.layoutBar()
    local stacks = isBar() and mode() == "stacks"
    BAR.max:SetShown(stacks)
    bs:SetHeight(stacks and 371 or 311)
    local ty = 18 + bs:GetHeight() + 30
    ts:ClearAllPoints(); ts:SetPoint("TOPLEFT", 0, -ty)
    local c = Cfg()
    note:SetText((c and not isBar()) and "This aura isn't a bar." or "")
    pg.height = ty + 302 + 20
    pg:SetHeight(pg.height)
    if P.cur == "bar" and P.pane and not C.groupSel then P.pane:SetContentHeight(pg.height) end
  end
  rows[#rows + 1] = { refresh = function() P.layoutBar() end, setEnabled = function() end }
  P.layoutBar()
end

-- ===========================================================================
-- PAGE · TEXT (736:2645)
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
  local OFFON = { { false, "Off" }, { true, "On" } }

  local tp = UI.plate(pg, "TEXT"); tp:SetPoint("TOPLEFT", 0, -18); tp:SetSize(COL_W, 110)
  Label(tp, 16, 42, "Show Text")
  add(UI.toggle2(tp, OFFON, showing,
    function(v) local t = ensure(); if t then t.show = v; Reapply(); P.sync() end end)):SetPoint("TOPLEFT", 16, -65)
  Label(tp, 120, 42, "Displayed Text")
  local df = UI.pillField(tp, 304, { placeholder = "The aura's name",
    commit = function(s) local t = ensure(); if t then t.str = (s ~= "" and s) or nil; Reapply() end end,
    revert = function(self) self:refresh() end })
  df:SetPoint("TOPLEFT", 120, -65)
  function df:refresh()
    local t, c = txt(), Cfg()
    self:SetText((t and t.str) or ""); self:SetCursorPosition(0)
    if self.placeholder then self.placeholder:SetText((c and c.label) or "The aura's name") end
  end
  add(df, showing)

  local sp = UI.plate(pg, "SIZE & POSITION"); sp:SetPoint("TOPLEFT", 0, -158); sp:SetSize(205, 260)
  add(Dial(sp, 16, 42, { label = "Font Size", min = 6, max = 300, step = 1, unit = "px", dragPx = 900,
    get = function() local t = txt(); return (t and t.size) or 14 end,
    set = function(v) local t = ensure(); if t then t.size = v; Reapply() end end }), showing)
  add(Dial(sp, 16, 92, { label = "Horizontal Offset", min = -400, max = 400, step = 1, unit = "px", dragPx = 800,
    get = function() local t = txt(); return (t and t.x) or 0 end,
    set = function(v) local t = ensure(); if t then t.x = (v ~= 0) and v or nil; Reapply() end end }), showing)
  add(Dial(sp, 16, 142, { label = "Vertical Offset", min = -400, max = 400, step = 1, unit = "px", dragPx = 800,
    get = function() local t = txt(); return (t and t.y) or 0 end,
    set = function(v) local t = ensure(); if t then t.y = (v ~= 0) and v or nil; Reapply() end end }), showing)
  add(Picker(sp, 16, 192, 148, "Anchor", X.TE_ANCHOR,
    function() local t = txt(); return (t and t.anchor) or "BOTTOM" end,
    function(v) local t = ensure(); if t then t.anchor = (v ~= "BOTTOM") and v or nil; Reapply() end end), showing)

  local ta = UI.plate(pg, "APPEARANCE"); ta:SetPoint("TOPLEFT", 235, -158); ta:SetSize(205, 226)
  add(ActionPill(ta, 16, 42, 173, "Font",
    function() local t = txt(); return X.fontNameFor(t and t.font) end,
    function()
      local t = txt()
      X.OpenFontPicker(function(path) local t2 = ensure(); if t2 then t2.font = path; Reapply(); P.sync() end end, t and t.font)
    end), showing)
  Label(ta, 16, 100, "Text Color")
  add(UI.colorDot(ta, { title = "Text Color",
    get = function() local t = txt(); return t and t.color end,
    set = function(v) local t = ensure(); if t then t.color = v; Reapply() end end }), showing):SetPoint("TOPLEFT", 16, -123)
  add(Picker(ta, 101, 100, 88, "Outline Type", X.TE_OUTLINE,
    function() local t = txt(); return (t and t.outline) or "OUTLINE" end,
    function(v) local t = ensure(); if t then t.outline = (v ~= "OUTLINE") and v or nil; Reapply() end end), showing)
  -- The live charge count, in place of the text — which is why turning it on
  -- also turns the text on.
  Label(ta, 16, 158, "Show Charge Count")
  add(UI.toggle2(ta, OFFON,
    function() local t = txt(); return (t and t.showCount) == true end,
    function(v) local t = ensure(); if t then t.showCount = v or nil; if v then t.show = true end; Reapply(); P.sync() end end)):SetPoint("TOPLEFT", 16, -181)

  pg.height = 158 + 260 + 20
end

-- ===========================================================================
-- PAGE · EFFECTS, MOTION & SOUND (736:3132)
-- ===========================================================================
local EF = { blocks = {} }
P.EF = EF

local function BuildEffects()
  local pg = Page("effects"); EF.page = pg
  local E = _G.GloomsHub and _G.GloomsHub.Effects

  -- GLOW APPEARANCE — the glow while the aura is on screen; Color off = the
  -- glow's own colour.
  local gp = UI.plate(pg, "GLOW APPEARANCE"); gp:SetPoint("TOPLEFT", 0, -18); gp:SetSize(COL_W, 110)
  local GLOW = { { "none", "None" }, { "autocast", "Autocast Shine" }, { "pixel", "Pixel Glow" },
                 { "proc", "Proc Glow" }, { "button", "Action Button Glow" } }
  local function glowType() local c = Cfg(); return (c and c.glow and c.glow.type) or "none" end
  add(Picker(gp, 16, 42, 332, "Glow Type", GLOW, glowType, function(v)
    local c = Cfg(); if not c then return end
    c.glow = c.glow or {}; c.glow.type = (v ~= "none") and v or nil
    Reapply(); P.sync()
  end))
  Label(gp, 378, 43.5, "Color")
  add(UI.colorDot(gp, { title = "Glow Color",
    get = function() local c = Cfg(); return c and c.glow and c.glow.customColor and c.glow.color end,
    set = function(v)
      local c = Cfg(); if not c then return end
      c.glow = c.glow or {}; c.glow.color = v; c.glow.customColor = (v ~= nil) or nil; Reapply()
    end }), function() return glowType() ~= "none" end):SetPoint("TOPLEFT", 378, -66.5)

  -- ANIMATION SETTINGS — one of the Hub's eight shaped animations, and its own
  -- settings INLINE (the mock), built from the module's `params` schema so a
  -- module added in the Hub grows its controls here with no GA change. Numbers
  -- become dials, choices pickers, a colour sits beside the type (its checkbox
  -- off = the module's own colour). Fractional params show ×100 as a percentage.
  local anp = UI.plate(pg, "ANIMATION SETTINGS"); anp:SetPoint("TOPLEFT", 0, -158); anp:SetSize(COL_W, 100)
  EF.plate = anp
  local ANIMS = { { "none", "None" } }
  if E then E:Each(function(m) ANIMS[#ANIMS + 1] = { m.id, m.label or m.id } end) end
  local function animID() local c = Cfg(); return (c and c.effects and c.effects.anim) or "none" end
  add(Picker(anp, 16, 42, 332, "Animation Type", ANIMS, animID, function(v)
    local c = Cfg(); if not c then return end
    c.effects = c.effects or {}; c.effects.anim = (v ~= "none") and v or nil
    Reapply(); P.layoutEffects(); P.sync()
  end))
  -- Every animation traces the aura's SHAPE; with none set there is nothing to
  -- draw and the engine skips it. Said, so it never looks broken.
  local need = UI.text(anp, "", 11); need:SetPoint("TOPRIGHT", -16, -13); need:SetAlpha(0.6)

  local function block(id)
    if EF.blocks[id] then return EF.blocks[id] end
    local mod = E and E:Get(id); if not mod then return nil end
    local b = CreateFrame("Frame", nil, anp); b:SetPoint("TOPLEFT"); b:SetSize(COL_W, 10)
    b.rows = {}
    local i, colorPlaced = 0, false
    for _, p in ipairs(mod.params or {}) do
      local function set(v) local t = X.AnimParams(Cfg(), id); if t then t[p.key] = v end; Reapply() end
      local function get() return X.AnimGet(id, p.key) end
      if p.kind == "color" then
        -- the SAVED colour only: unset = the module's own, shown as the dashed ring
        local function saved()
          local c = Cfg(); local s = c and c.effects and c.effects.params and c.effects.params[id]
          return s and s[p.key]
        end
        local d = UI.colorDot(b, { title = p.label, get = saved, set = function(v) set(v) end })
        if not colorPlaced then
          colorPlaced = true
          Label(b, 378, 43.5, "Color"); d:SetPoint("TOPLEFT", 378, -66.5)
        else
          local x, y = (i % 2 == 0) and 16 or 260, 100 + math.floor(i / 2) * 50; i = i + 1
          Label(b, x, y, p.label); d:SetPoint("TOPLEFT", x, -(y + 23))
        end
        b.rows[#b.rows + 1] = d
      else
        local x, y = (i % 2 == 0) and 16 or 260, 100 + math.floor(i / 2) * 50; i = i + 1
        if p.kind == "choice" then
          local vals = {}
          for _, ch in ipairs(p.choices or {}) do vals[#vals + 1] = { ch[1], ch[2] } end
          b.rows[#b.rows + 1] = Picker(b, x, y, 164, p.label, vals, get, set)
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
          local d = Dial(b, x, y, { label = p.label, min = lo, max = hi, step = st, unit = (sc ~= 1) and "%" or "",
            dragPx = 400, get = function() return (get() or 0) * sc end, set = function(v) set(v / sc) end })
          if p.kind == "bispeed" then
            UI.attachTip(d.strip, p.label, ("−100%% = %s · 0 = still · +100%% = %s"):format(p.neg or "counter-clockwise", p.pos or "clockwise"))
          end
          b.rows[#b.rows + 1] = d
        end
      end
    end
    b.nrows = math.ceil(i / 2)
    b:Hide()
    EF.blocks[id] = b
    return b
  end

  -- SOUND (the mock's plate carries no title) and ROTATION, side by side under it.
  local sp = UI.plate(pg); sp:SetSize(208, 147); EF.sound = sp
  local function soundLabel() local c = Cfg(); return (c and c.sound and c.sound.name) or "None" end
  local sb = add(ActionPill(sp, 16, 10, 122, "Sound", soundLabel, function()
    local c = Cfg(); if not c then return end
    X.OpenSoundPicker(function(item)
      if item.file then c.sound = c.sound or {}; c.sound.file = item.file; c.sound.name = item.name; c.sound.channel = "Master"
      else c.sound = nil end
      P.sync()
    end, c.sound and c.sound.file)
  end))
  local play = UI.pill(sp, "PLAY", { w = 49, accent = FLAME })
  play:SetPoint("TOPLEFT", 142.5, -33)
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
  add(Picker(sp, 16, 79, 176, "Sound Trigger",
    function() local out = {}; for _, v in ipairs(ON) do out[#out + 1] = { v[1], v[2], alertOff(v[1]) } end; return out end,
    function() local c = Cfg(); return (c and c.sound and c.sound.on) or "trigger" end,
    function(v) local c = Cfg(); if c and c.sound then c.sound.on = v; P.sync() end end), hasSound)
  -- A timing already SET to something impossible has to be said out loud.
  local warn = UI.text(sp, "", 10); warn:SetPoint("TOPLEFT", 16, -131); warn:SetWidth(176)
  warn:SetTextColor(CORAL.r, CORAL.g, CORAL.b); warn:SetJustifyH("LEFT")
  EF.warn = warn
  rows[#rows + 1] = {
    refresh = function()
      local c = Cfg(); local cur = c and c.sound and c.sound.on or "trigger"
      local bad = c and c.sound and alertOff(cur)
      warn:SetText(bad and "This spell never sends that signal, so the sound can't play. Pick another timing." or "")
      sp:SetHeight(bad and 175 or 147)
    end,
    setEnabled = function() end,
  }

  -- ROTATION — spins the aura's own artwork, so it needs one: a bar has none and
  -- "Effects Only" hides it on purpose. Greyed then, rather than left looking live.
  local rp = UI.plate(pg, "ROTATION"); rp:SetSize(208, 218); EF.rot = rp
  local function rot() local c = Cfg(); return c and c.rotate end
  local function ensureRot() local c = Cfg(); if not c then return nil end; c.rotate = c.rotate or {}; return c.rotate end
  local function isIcon() local c = Cfg(); return c ~= nil and c.kind ~= "bar" and not c.noArt end
  local function spinning() local r = rot(); return isIcon() and r ~= nil and r.on == true end
  Label(rp, 16, 42, "Rotation")
  add(UI.toggle2(rp, { { false, "Off" }, { true, "On" } },
    function() local r = rot(); return isIcon() and (r and r.on) == true end,
    function(v) local r = ensureRot(); if r then r.on = v or nil; Reapply(); P.sync() end end), isIcon):SetPoint("TOPLEFT", 16, -65)
  -- A percentage: 100% = one turn every 3 seconds.
  add(Dial(rp, 16, 100, { label = "Rotation Speed", min = 10, max = 500, step = 10, unit = "%", dragPx = 500,
    get = function() local r = rot(); return (r and r.speed) or 100 end,
    set = function(v) local r = ensureRot(); if r then r.speed = (v ~= 100) and v or nil; Reapply() end end }), spinning)
  add(Picker(rp, 16, 150, 148, "Direction", { { "cw", "Clockwise" }, { "ccw", "Counter-Clockwise" } },
    function() local r = rot(); return (r and r.dir) or "cw" end,
    function(v) local r = ensureRot(); if r then r.dir = (v ~= "cw") and v or nil; Reapply() end end), spinning)

  function P.layoutEffects()
    local id = animID()
    for _, b in pairs(EF.blocks) do b:Hide() end
    local b = (id ~= "none") and block(id) or nil
    local n = 0
    if b then
      b:Show(); n = b.nrows
      local on = Cfg() ~= nil
      for _, r in ipairs(b.rows) do r:refresh(); r:setEnabled(on) end
    end
    local c = Cfg()
    need:SetText((b and c and not c.shape) and "Needs a Shape — Appearance page" or "")
    local h = (n > 0) and (100 + n * 50 + 18) or 100
    anp:SetHeight(h)
    local sy = 158 + h + 30
    sp:ClearAllPoints(); sp:SetPoint("TOPLEFT", 0, -sy)
    rp:ClearAllPoints(); rp:SetPoint("TOPLEFT", 232.5, -sy)
    pg.height = sy + 218 + 20
    pg:SetHeight(pg.height)
    if P.cur == "effects" and P.pane and not C.groupSel then P.pane:SetContentHeight(pg.height) end
  end
  rows[#rows + 1] = { refresh = function() P.layoutEffects() end, setEnabled = function() end }
  P.layoutEffects()
end

-- ===========================================================================
-- LOAD CONDITIONS (736:3639) — built twice from one implementation: for the
-- selected AURA (cfg.visibility, on its page) and for the selected GROUP
-- (group.visibility, in the group pane). Same engine gate either way.
-- ===========================================================================
-- ★ The owner's rule (2026-09-23): a tick means "only while this is true"; a
-- box left clear means "doesn't matter"; ALL ticked conditions must hold at
-- once. The two PAIRS — In/Out of Combat, Has/No Target — and the specs row
-- read as "any of these": tick both to not care, one to require it; the last
-- one can't be unticked, because then nothing could ever load. That is exactly
-- the model GA already stores (combat/target = "in"/"out"/nil, specs = a set
-- or nil), so nothing saved changes meaning.
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

function P.buildLoad(parent, o)
  local sink, target, noun = o.sink, o.target, o.noun or "Aura"
  local function put(ctrl, gate)
    sink[#sink + 1] = {
      refresh = function() if ctrl.refresh then ctrl:refresh() end end,
      setEnabled = function(_, on)
        local ok = on and (not gate or gate())
        if ctrl.setEnabled then ctrl:setEnabled(ok) else ctrl:SetEnabled(ok); ctrl:SetAlpha(ok and 1 or 0.5) end
      end,
    }
    return ctrl
  end
  local function vis() local t = target(); return t and t.visibility end
  local function visW() local t = target(); if not t then return nil end; t.visibility = t.visibility or {}; return t.visibility end

  local p = UI.plate(parent); p:SetPoint("TOPLEFT", 0, -18); p:SetSize(COL_W, 477)

  -- The master switch: NOT a "load when" — this aura (or group) at all.
  Label(p, 16, 10, "This " .. noun)
  put(UI.toggle2(p, { { true, "Enabled" }, { false, "Disabled" } },
    function() local t = target(); return not (t and t.enabled == false) end,
    function(v)
      local t = target(); if not t then return end
      -- NEVER `t.enabled = v and nil or false` — that is false both ways (the 2026-07-08 wall).
      if v then t.enabled = nil else t.enabled = false end
      if GA.CDM then GA.CDM:Discover() end
      Poke(); X.RefreshList()
    end)):SetPoint("TOPLEFT", 16, -33)

  -- a pair: `key` holds v1 (only the first), v2 (only the second) or nil (both)
  local function pair(x, y, label1, label2, key, v1, v2)
    local b1, b2
    local function st() local v = vis(); local cur = v and v[key]; return (cur == nil or cur == v1), (cur == nil or cur == v2) end
    local function write(a, b)
      if not a and not b then return end
      local w = visW(); if not w then return end
      w[key] = (a and b) and nil or (a and v1 or v2)
      Poke(); b1:refresh(); b2:refresh()
    end
    b1 = put(UI.box(p, label1, function() local a = st(); return a end, function(on) local _, b = st(); write(on, b) end))
    b2 = put(UI.box(p, label2, function() local _, b = st(); return b end, function(on) local a = st(); write(a, on) end))
    b1:SetPoint("TOPLEFT", x, -(81.5 + 23 * y))
    b2:SetPoint("TOPLEFT", x, -(81.5 + 23 * (y + 1)))
  end
  local function single(x, y, label, key)
    put(UI.box(p, label, function() local v = vis(); return v and v[key] end,
      function(on) local w = visW(); if w then w[key] = on or nil; Poke() end end)):SetPoint("TOPLEFT", x, -(81.5 + 23 * y))
  end
  local L, R = 16, 172
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

  -- The class's specs in one row, spread edge to edge (the mock's justify-between).
  local specs = X.PlayerSpecs()
  local sboxes = {}
  local function specOn(id) local v = vis(); return (not (v and v.specs)) or (v.specs[id] and true or false) end
  for _, sp in ipairs(specs) do
    local b = put(UI.box(p, sp.name, function() return specOn(sp.id) end, function(on)
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
    sboxes[#sboxes + 1] = b
  end
  do
    local total = 0
    for _, b in ipairs(sboxes) do total = total + b:GetWidth() end
    local gap = (#sboxes > 1) and ((408 - total) / (#sboxes - 1)) or 0
    local x = 16
    for _, b in ipairs(sboxes) do b:SetPoint("TOPLEFT", x, -283.5); x = x + b:GetWidth() + gap end
  end

  -- SPELL / TALENT KNOWN — a spell ID; talents count. Commits on Enter and on
  -- losing focus (item 7's lesson: Enter-only left a stale value behind).
  Label(p, 16, 321, "Spell/Talent Known")
  local help = UI.text(p, "", 10); help:SetPoint("TOPLEFT", 16, -373); help:SetAlpha(0.6)
  local function helpText()
    local v = vis(); local id = v and v.spellKnown
    if id then
      local nm = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
      help:SetText(((nm or ("Spell " .. id)) .. " — " .. noun .. " enabled only if known"))
    else
      help:SetText("A spell ID (talents count). Blank = don't check.")
    end
  end
  local sk = UI.pillField(p, 408, { numeric = true,
    commit = function(s)
      local w = visW(); if not w then return end
      local id = tonumber(s)
      if id ~= w.spellKnown then w.spellKnown = id; helpText(); Poke() end
    end,
    revert = function(self) self:refresh() end })
  sk:SetPoint("TOPLEFT", 16, -344)
  function sk:refresh() local v = vis(); self:SetText(v and v.spellKnown and tostring(v.spellKnown) or ""); helpText() end
  put(sk)

  -- PLAYER POWER — whole units (UnitPower's fragments are a different scale and
  -- a different question). The type seeds the rule; Off removes it.
  local pwVal
  put(Picker(p, 16, 409, 288, "Player Power", POWERS,
    function() local v = vis(); return (v and v.power and v.power.type) or "off" end,
    function(x)
      local v = visW(); if not v then return end
      if x == "off" then v.power = nil
      else
        v.power = v.power or {}
        v.power.type = x; v.power.op = v.power.op or "ge"; v.power.value = v.power.value or 1
      end
      Poke(); if pwVal then pwVal:refresh() end
      P.sync(); if C._grows then for _, r in ipairs(C._grows) do r:refresh() end end
    end))
  local function hasPower() local v = vis(); return v and v.power and v.power.type ~= nil end
  put(Picker(p, 314, 432, 60, nil, OPS,
    function() local v = vis(); return (v and v.power and v.power.op) or "ge" end,
    function(x) local v = visW(); if v and v.power then v.power.op = x; Poke() end end), hasPower)
  pwVal = UI.pillField(p, 40, { numeric = true, justify = "CENTER",
    commit = function(s) local v = visW(); if v and v.power then v.power.value = tonumber(s) or 0; Poke() end end,
    revert = function(self) self:refresh() end })
  pwVal:SetPoint("TOPLEFT", 384, -432)
  pwVal:SetTextInsets(0, 0, 0, 0)
  function pwVal:refresh() local v = vis(); self:SetText(v and v.power and v.power.value and tostring(v.power.value) or "") end
  put(pwVal, hasPower)
  return p
end

local function BuildLoad()
  local pg = Page("load")
  P.buildLoad(pg, { sink = rows, target = Cfg, noun = "Aura" })
  pg.height = 18 + 477 + 20
end

-- The GROUP pane: shown in place of any page while a group is selected. Its
-- rename/delete live in the header's two buttons; here are its order and the
-- load rule that gates every aura inside it.
local function BuildGroupPage()
  local gp = CreateFrame("Frame", nil, P.pane.child)
  gp:SetPoint("TOPLEFT", 0, 0); gp:SetSize(COL_W, 10); gp:Hide()
  P.groupPage = gp
  local function grp() local gid = C.groupSel; return gid and X.Groups() and X.Groups()[gid] end
  local lp = P.buildLoad(gp, { sink = C._grows, target = grp, noun = "Group" })
  local down = UI.pill(lp, "Move Down")
  down:SetPoint("TOPRIGHT", -16, -33)
  down:SetScript("OnClick", function() if C.groupSel then X.MoveGroup(C.groupSel, 1); X.RefreshList() end end)
  local up = UI.pill(lp, "Move Up")
  up:SetPoint("TOPRIGHT", down, "TOPLEFT", -10, 0)
  up:SetScript("OnClick", function() if C.groupSel then X.MoveGroup(C.groupSel, -1); X.RefreshList() end end)
  local note = UI.text(gp, "These gate every aura in the group, ahead of each aura's own conditions.", 11)
  note:SetPoint("TOPLEFT", 0, -(18 + 477 + 12)); note:SetAlpha(0.6)
  gp.height = 18 + 477 + 12 + 14 + 20
end

-- ===========================================================================
-- Showing a page, and the old editor's hooks
-- ===========================================================================
function P.show(id)
  if id and P.pages[id] then P.cur = id end
  if not P.pane then return end
  for _, f in pairs(P.pages) do f:Hide() end
  P.groupPage:Hide(); P.empty:Hide()
  local f
  if C.groupSel and X.Groups() and X.Groups()[C.groupSel] then
    f = P.groupPage
  elseif X.DisplayList()[1] == nil then
    P.empty:Show()
  else
    f = P.pages[P.cur]
    if P.cur == "triggers" then P.renderTriggers()
    elseif P.cur == "bar" then P.layoutBar()
    elseif P.cur == "effects" then P.layoutEffects() end
  end
  -- The frame is sized to its content: the drag-and-drop hit test reads it.
  if f then f:SetHeight(f.height or 10); f:Show() end
  P.pane:SetContentHeight(f and f.height or 10)
  P.pane:ScrollTo(0)
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
  for _, r in ipairs(C._grows) do r:refresh(); r:setEnabled(true) end
  P.syncHeader()
end

-- ===========================================================================
-- The tab
-- ===========================================================================
local function BuildTab(c)
  P.c = c
  X.SetContainer(c)
  BuildList(c)
  BuildHeader(c)
  P.pane = UI.scrollPane(c, { w = COL_W, barGap = 8 })
  P.pane:SetPoint("TOPLEFT", COL_X, -PAGE_TOP); P.pane:SetSize(COL_W, 740 - PAGE_TOP - 10)
  BuildTriggers(); BuildAppearance(); BuildBar(); BuildText(); BuildEffects(); BuildLoad(); BuildGroupPage()
  -- With no auras there is nothing to edit: one line saying what to click.
  P.empty = UI.text(c, "No auras in this profile yet.\n\nClick New Aura to make one.", 12)
  P.empty:SetPoint("TOPLEFT", COL_X, -128); P.empty:SetJustifyH("LEFT"); P.empty:SetAlpha(0.7)
  P.empty:Hide()

  -- These fire when the tab gains/loses the window (open/close AND tool switches).
  c:HookScript("OnShow", function()
    if P.hideCDM then P.hideCDM:refresh() end
    if GA.Displays then GA.Displays.forced = true; GA.Displays:SetInteractive(true) end
    C:SelectInitial()   -- straight into the last-edited aura
  end)
  c:HookScript("OnHide", function()
    X.CloseSubWindows()   -- a docked picker must not linger
    if GA.Displays then GA.Displays.forced = false; GA.Displays:SetSelectedDisplay(nil) end
    if GA.CDM and GA.CDM.Discover then GA.CDM:Discover() end
  end)
end

-- The profile control in the Suite window's sidebar (same api as before).
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
  accent   = COLOR.jade,
  pages    = {
    { id = "triggers",   title = "Aura Triggers" },
    { id = "appearance", title = "Appearance, Position & Size" },
    { id = "bar",        title = "Bar Fill & Readouts" },
    { id = "text",       title = "Text" },
    { id = "effects",    title = "Effects, Motion & Sound" },
    { id = "load",       title = "Aura Load Conditions" },
  },
  profile  = PROFILE,
  build    = BuildTab,
  showPage = function(id) P.show(id) end,
}
