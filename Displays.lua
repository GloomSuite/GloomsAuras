-- Displays.lua — Gloom's Auras: display objects
--
-- A "display" is one custom on-screen texture (+ label) bound to a tracked spell.
-- Config lives in GloomsAurasDB.displays[<id>], keyed by an opaque DISPLAY ID (a
-- spellID for the original of each spell, a unique "dN" string for duplicates);
-- the tracked spell is always cfg.spellID. Every function here takes that display
-- id (param named `spellID` for history) and reads the real spell from cfg.spellID.
-- This module turns config into a frame and owns HOW it looks + WHERE it sits. CDM
-- decides WHEN. Position and size are set with
-- numeric /ga commands (reliable on every client — no mouse dragging). CDM.lua
-- decides WHEN each display is shown.

local ADDON_NAME = ...
local GA = _G.GloomsAuras

local issecret = _G.issecretvalue or function() return false end

local D = {}
GA.Displays = D

D.frames = {}       -- display id -> frame
D.forced = false    -- true while previewing/testing: ignore CDM show/hide
D.selectedID = nil  -- the aura selected in the panel; only it is draggable (nil = all)

-- On-screen text anchor → { labelPoint, framePoint, baseX, baseY }. The text's
-- labelPoint attaches to the aura frame's framePoint, with a small base gap; the
-- user's cfg.text.x/y offsets add on top. Default = BOTTOM (text under the aura).
local LABEL_ANCHOR = {
  BOTTOM = { "TOP", "BOTTOM", 0, -4 },
  TOP    = { "BOTTOM", "TOP", 0, 4 },
  CENTER = { "CENTER", "CENTER", 0, 0 },
  LEFT   = { "RIGHT", "LEFT", -4, 0 },
  RIGHT  = { "LEFT", "RIGHT", 4, 0 },
}

local function DB()
  return GA.db and GA.db.displays
end

function D:Config(spellID)
  local db = DB()
  return db and db[spellID]
end

-- --------------------------------------------------------------------------
-- ★ COLOR CHANGE (2026-10-06, the owner: "change tint color at 6+ combo points"
-- — one aura, not a duplicate per color). `cfg.colorChange = { power = <power
-- type>, at = N, color = {r,g,b} }`: at N or more of that resource the art
-- wears `color`, below it its own Recolor. Player power reads PLAIN (FINDINGS'
-- player-power entry, TESTED 2026-10-05); a secret read keeps the own color.
-- Re-tinted on every power change — a vertex colour, nothing more.
-- --------------------------------------------------------------------------
-- …or a STATE (2026-10-06, the owner): `cc.state` = "combat" | "nocombat" |
-- "target" | "casting" | "stealth" — all plain to read, in combat too. One
-- condition, one color (the owner: multi-rule "too complex for a color change").
local inCombat = false
local function StateOn(state)
  if state == "combat" then return inCombat or InCombatLockdown() end
  if state == "nocombat" then return not (inCombat or InCombatLockdown()) end
  if state == "target" then return UnitExists("target") end
  if state == "casting" then return (UnitCastingInfo("player") or UnitChannelInfo("player")) ~= nil end
  if state == "stealth" then return IsStealthed() and true or false end
  return false
end
function D:TintFor(cfg)
  local cc = cfg and cfg.colorChange
  if cc and cc.color then
    if cc.state then
      if StateOn(cc.state) then return cc.color end
    elseif cc.power ~= nil then
      local cur = UnitPower("player", cc.power)
      if not (issecretvalue and issecretvalue(cur)) and type(cur) == "number" and cur >= (tonumber(cc.at) or 1) then
        return cc.color
      end
    end
  end
  return cfg and cfg.color
end
function D:RefreshTints()
  local db = DB(); if not db then return end
  for id, f in pairs(self.frames) do
    local cfg = db[id]
    if cfg and cfg.colorChange and cfg.kind ~= "bar" and f.tex then
      local c = self:TintFor(cfg)
      if c then f.tex:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1) else f.tex:SetVertexColor(1, 1, 1) end
    end
  end
end
do
  local tintEv = CreateFrame("Frame")
  tintEv:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
  tintEv:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
  tintEv:RegisterUnitEvent("UNIT_MAXPOWER", "player")
  tintEv:RegisterEvent("PLAYER_ENTERING_WORLD")
  -- the states: combat edges (InCombatLockdown can still read the old state
  -- inside these, so the edge itself is remembered), target, casting, stealth
  tintEv:RegisterEvent("PLAYER_REGEN_DISABLED"); tintEv:RegisterEvent("PLAYER_REGEN_ENABLED")
  tintEv:RegisterEvent("PLAYER_TARGET_CHANGED"); tintEv:RegisterEvent("UPDATE_STEALTH")
  for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_START",
                       "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED" }) do
    tintEv:RegisterUnitEvent(e, "player")
  end
  tintEv:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then inCombat = false end
    D:RefreshTints()
  end)
end

-- --------------------------------------------------------------------------
-- ★ GROUPS AS ANCHORS (2026-10-05, the owner: "work more like overlays" — Gloom's
-- UI's groups, GloomsOverlays.lua). A group has a POSITION: `g.x / g.y` from the
-- screen's centre, or from the centre of the frame it is ATTACHED to (`g.attach`,
-- a Hub anchor id — Unit Frames' frames), and a `g.scale` (nil = 1) that sizes
-- every member and the spaces between them. A member's `cfg.point` is then its
-- OFFSET from the group's anchor (in unscaled units); an ungrouped aura's is from
-- the screen's centre, as always. A group from before this has no x / y (= 0) and
-- no attach, so every member's old absolute point reads unchanged as its offset.
-- Joining or leaving a group KEEPS the aura where it is on screen (SetGroup).
-- --------------------------------------------------------------------------
local function GroupsT() return GA.db and GA.db.groups end
function D:GroupOf(cfg)
  local gid = cfg and cfg.group
  local g = gid and GroupsT() and GroupsT()[gid]
  return g
end
-- what a group is pinned to: the anchor's frame, or the screen
function D:GroupRel(g)
  local f = g and g.attach and GloomsHub and GloomsHub.AnchorFrame and GloomsHub:AnchorFrame(g.attach)
  return f or UIParent
end
local function GroupScale(g) return (g and g.scale) or 1 end
D.GroupScale = GroupScale
-- where a frame's centre is, from the screen's centre, in UIParent units
local function CenterOffset(f)
  if f == UIParent then return 0, 0 end
  local cx, cy = f:GetCenter()
  local ux, uy = UIParent:GetCenter()
  if not (cx and ux) then return 0, 0 end
  local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
  return cx * k - ux, cy * k - uy
end
function D:GroupOrigin(g)
  local ax, ay = CenterOffset(self:GroupRel(g))
  return ax + (g.x or 0), ay + (g.y or 0)
end
-- where an aura is PINNED: the frame, its centre's offset from that frame's
-- centre (UIParent units), and its group's scale
function D:Place(cfg)
  local p = cfg.point or { "CENTER", 0, 0 }
  local px, py = p[2] or 0, p[3] or 0
  local g = self:GroupOf(cfg)
  if not g then return UIParent, px, py, 1 end
  local k = GroupScale(g)
  return self:GroupRel(g), (g.x or 0) + px * k, (g.y or 0) + py * k, k
end
-- where an aura SITS on screen, from the screen's centre
function D:Pos(cfg)
  local rel, x, y = self:Place(cfg)
  local ax, ay = CenterOffset(rel)
  return ax + x, ay + y
end
-- an aura's box on screen (its size times its group's scale)
function D:BoxSize(cfg)
  local k = GroupScale(self:GroupOf(cfg))
  return (cfg.width or cfg.size or 64) * k, (cfg.height or cfg.size or 64) * k
end
-- into a group (nil = out of every group), KEEPING its place on screen
function D:SetGroup(cfg, gid)
  local x, y = self:Pos(cfg)
  local g = gid and GroupsT() and GroupsT()[gid]
  cfg.group = g and gid or nil
  if g then
    local ox, oy = self:GroupOrigin(g)
    local k = GroupScale(g)
    cfg.point = { "CENTER", math.floor((x - ox) / k + 0.5), math.floor((y - oy) / k + 0.5) }
  else
    cfg.point = { "CENTER", math.floor(x + 0.5), math.floor(y + 0.5) }
  end
end
-- attach a group to an anchor (nil = the screen), KEEPING it where it is
function D:SetAttach(g, id)
  local ox, oy = self:GroupOrigin(g)
  g.attach = id
  local ax, ay = CenterOffset(self:GroupRel(g))
  g.x, g.y = math.floor(ox - ax + 0.5), math.floor(oy - ay + 0.5)
end
-- the display ids in a group
function D:GroupMembers(gid)
  local out, db = {}, DB()
  if db then for id, cfg in pairs(db) do if cfg.group == gid then out[#out + 1] = id end end end
  return out
end
-- re-place every member of a group (its anchor, attach or scale moved)
function D:ApplyGroup(gid)
  for _, id in ipairs(self:GroupMembers(gid)) do
    if self.frames[id] then self:ApplyConfig(id) end
  end
  if self.RefreshGroupHandle then self:RefreshGroupHandle() end
end
-- THE GROUP'S HANDLE (Gloom's UI's, GloomsOverlays.lua MakeHandle): while the
-- windows have a GROUP selected, green corner brackets round every member —
-- drag them to move the whole group. Moved from the SAVED numbers, never from
-- what a frame reports (Hub FINDINGS §21). An empty group is a 40 square at its
-- anchor.
local groupHandle
local moveListeners = {}
function D:OnGroupMoved(fn) moveListeners[#moveListeners + 1] = fn end
local function Cursor()
  local x, y = GetCursorPosition()
  local sc = UIParent:GetEffectiveScale()
  return x / sc, y / sc
end
local function EnsureGroupHandle()
  if groupHandle then return groupHandle end
  local h = CreateFrame("Frame", nil, UIParent)
  h:SetFrameStrata("HIGH"); h:SetFrameLevel(1000)
  h:EnableMouse(true); h:Hide()
  if GloomsHub and GloomsHub.UI and GloomsHub.UI.gBrackets then GloomsHub.UI.gBrackets(h, 0.2, 0.8, 0.4, 0.9) end
  local function finish(self)
    self:SetScript("OnUpdate", nil)
    if not self.moving then return end
    self.moving = false
    for _, fn in ipairs(moveListeners) do fn() end
    D:RefreshGroupHandle()
  end
  h:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then return end
    local g = D.editGroup and GroupsT() and GroupsT()[D.editGroup]
    if not g then return end
    local cx, cy = Cursor()
    local ox, oy = g.x or 0, g.y or 0
    self.moving = true
    self:SetScript("OnUpdate", function(me)
      if not IsMouseButtonDown("LeftButton") then finish(me); return end
      local x, y = Cursor()
      g.x = math.floor(ox + (x - cx) + 0.5)
      g.y = math.floor(oy + (y - cy) + 0.5)
      D:ApplyGroup(D.editGroup)
      for _, fn in ipairs(moveListeners) do fn(true) end
    end)
  end)
  h:SetScript("OnMouseUp", function(self) finish(self) end)
  groupHandle = h
  return h
end
function D:RefreshGroupHandle()
  local gid = self.forced and self.editGroup
  local g = gid and GroupsT() and GroupsT()[gid]
  if not g then
    if groupHandle and not groupHandle.moving then groupHandle:Hide() end
    return
  end
  local h = EnsureGroupHandle()
  local rel = self:GroupRel(g)
  local l, r, b, t
  local db = DB()
  for _, id in ipairs(self:GroupMembers(gid)) do
    local cfg = db[id]
    local _, x, y = self:Place(cfg)
    local w, hh = self:BoxSize(cfg)
    l = math.min(l or math.huge, x - w / 2); r = math.max(r or -math.huge, x + w / 2)
    b = math.min(b or math.huge, y - hh / 2); t = math.max(t or -math.huge, y + hh / 2)
  end
  local gx, gy = g.x or 0, g.y or 0
  if not l then l, r, b, t = gx - 20, gx + 20, gy - 20, gy + 20
  else l, r, b, t = l - 4, r + 4, b - 4, t + 4 end
  h:SetSize(r - l, t - b)
  h:ClearAllPoints()
  h:SetPoint("CENTER", rel, "CENTER", (l + r) / 2, (b + t) / 2)
  h:Show()
end
-- ★ MULTI-SELECT (2026-10-06, the owner: "position some of the individual
-- pieces in concert within the group"). Shift-click in the list builds
-- `D.multi` (display ids); with two or more, lime brackets round all of them
-- move them TOGETHER — each by the same screen distance, in its own group's
-- offset units (÷ its group's scale). The settings dim meanwhile (the owner:
-- "fine if it disables settings"). Moved from the saved numbers, like the group.
local multiHandle
local function MultiIDs()
  local out, db = {}, DB()
  for _, id in ipairs(D.multi or {}) do if db and db[id] then out[#out + 1] = id end end
  return out
end
function D:RefreshMultiHandle()
  local ids = self.forced and MultiIDs() or {}
  if #ids < 2 then
    if multiHandle and not multiHandle.moving then multiHandle:Hide() end
    return
  end
  if not multiHandle then
    local h = CreateFrame("Frame", nil, UIParent)
    h:SetFrameStrata("HIGH"); h:SetFrameLevel(1001)
    h:EnableMouse(true); h:Hide()
    if GloomsHub and GloomsHub.UI and GloomsHub.UI.gBrackets then GloomsHub.UI.gBrackets(h, 0.44, 0.93, 0.25, 0.9) end
    local function finish(self)
      self:SetScript("OnUpdate", nil)
      if not self.moving then return end
      self.moving = false
      for _, fn in ipairs(moveListeners) do fn() end
      D:RefreshMultiHandle()
    end
    h:SetScript("OnMouseDown", function(self, button)
      if button ~= "LeftButton" then return end
      local cx, cy = Cursor()
      local db = DB()
      local start = {}
      for _, id in ipairs(MultiIDs()) do
        local p = db[id].point or { "CENTER", 0, 0 }
        start[id] = { p[2] or 0, p[3] or 0, GroupScale(D:GroupOf(db[id])) }
      end
      self.moving = true
      self:SetScript("OnUpdate", function(me)
        if not IsMouseButtonDown("LeftButton") then finish(me); return end
        local x, y = Cursor()
        for id, st in pairs(start) do
          local cfg = db[id]
          if cfg then
            cfg.point = { "CENTER", math.floor(st[1] + (x - cx) / st[3] + 0.5), math.floor(st[2] + (y - cy) / st[3] + 0.5) }
            if D.frames[id] then D:ApplyConfig(id) end
          end
        end
        D:RefreshMultiHandle(); D:RefreshGroupHandle()
        for _, fn in ipairs(moveListeners) do fn(true) end
      end)
    end)
    h:SetScript("OnMouseUp", function(self) finish(self) end)
    multiHandle = h
  end
  local db = DB()
  local l, r, b, t
  for _, id in ipairs(ids) do
    local x, y = self:Pos(db[id])
    local w, hh = self:BoxSize(db[id])
    l = math.min(l or math.huge, x - w / 2); r = math.max(r or -math.huge, x + w / 2)
    b = math.min(b or math.huge, y - hh / 2); t = math.max(t or -math.huge, y + hh / 2)
  end
  multiHandle:SetSize(r - l + 8, t - b + 8)
  multiHandle:ClearAllPoints()
  multiHandle:SetPoint("CENTER", UIParent, "CENTER", (l + r) / 2, (b + t) / 2)
  multiHandle:Show()
end
-- the list's multi-selection (nil / fewer than 2 = none)
function D:SetMulti(ids)
  self.multi = (ids and #ids >= 2) and ids or nil
  self:ApplyInteractivity()
  self:RefreshForced()
  self:RefreshMultiHandle()
end
function D:NudgeMulti(dx, dy)
  for _, id in ipairs(MultiIDs()) do self:NudgeAura(id, dx, dy) end
  self:RefreshMultiHandle()
end

-- The windows call this when a group is selected (nil: none, or closed).
function D:SetEditGroup(gid)
  self.editGroup = gid
  self:ApplyInteractivity()
  self:RefreshGroupHandle()
end
-- arrow-key nudges: a group, or one aura, by (dx, dy) screen units; a member of
-- a scaled group moves 1/scale of its own offset units, so a press is one pixel
function D:NudgeGroup(gid, dx, dy)
  local g = gid and GroupsT() and GroupsT()[gid]; if not g then return end
  g.x, g.y = (g.x or 0) + dx, (g.y or 0) + dy
  self:ApplyGroup(gid)
  for _, fn in ipairs(moveListeners) do fn(true) end
end
function D:NudgeAura(id, dx, dy)
  local cfg = self:Config(id); if not cfg then return end
  local k = GroupScale(self:GroupOf(cfg))
  local p = cfg.point or { "CENTER", 0, 0 }
  cfg.point = { "CENTER", (p[2] or 0) + dx / k, (p[3] or 0) + dy / k }
  self:ApplyConfig(id)
  self:RefreshGroupHandle()
  for _, fn in ipairs(moveListeners) do fn(true) end
end

-- Unit Frames' frames arrive after us: place everything again so an attached
-- group finds its frame.
if GloomsHub and GloomsHub.OnAnchorsChanged then
  GloomsHub:OnAnchorsChanged(function()
    local db = DB(); if not db then return end
    for id in pairs(db) do if D.frames and D.frames[id] then D:ApplyConfig(id) end end
  end)
end

-- --------------------------------------------------------------------------
-- Glow effects (LibCustomGlow). Pure rendering — never touches aura data. A glow
-- is active while the aura FRAME is shown AND cfg.glow.type is set: started on the
-- frame's OnShow, stopped on OnHide, re-applied on any config change. All calls are
-- pcall-guarded so a bad arg combo degrades to "no glow", never a Lua error.
-- --------------------------------------------------------------------------
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)   -- bar (statusbar) textures
local GLOW_KEY = "GloomsAuras"   -- our key, so we start/stop only our own glow

local function StopGlow(f)
  if not LCG then return end
  pcall(LCG.PixelGlow_Stop, f, GLOW_KEY)
  pcall(LCG.AutoCastGlow_Stop, f, GLOW_KEY)
  pcall(LCG.ButtonGlow_Stop, f)
  pcall(LCG.ProcGlow_Stop, f, GLOW_KEY)
end

local function StartGlow(f, gtype, color)
  if not LCG then return end
  local col = color and { color[1] or 1, color[2] or 1, color[3] or 1, 1 } or nil
  if gtype == "pixel" then
    pcall(LCG.PixelGlow_Start, f, col, nil, nil, nil, nil, nil, nil, nil, GLOW_KEY)
  elseif gtype == "autocast" then
    pcall(LCG.AutoCastGlow_Start, f, col, nil, nil, nil, nil, nil, GLOW_KEY)
  elseif gtype == "button" then
    pcall(LCG.ButtonGlow_Start, f, col)
  elseif gtype == "proc" then
    pcall(LCG.ProcGlow_Start, f, { color = col, key = GLOW_KEY, startAnim = false })
  end
end

-- (Re)apply the glow for one display id, honoring the frame's current shown state.
function D:ApplyGlow(displayID)
  local f = self.frames[displayID]; if not f then return end
  StopGlow(f)   -- clear any current glow (type/color may have changed, or we're hiding)
  local cfg = self:Config(displayID)
  local g = cfg and cfg.glow
  if f:IsShown() and g and g.type and g.type ~= "none" then
    StartGlow(f, g.type, g.customColor and g.color or nil)
  end
end

-- --------------------------------------------------------------------------
-- Rotation — a FIXED angle (cfg.angle, degrees) and/or a continuous SPIN
-- (cfg.rotate = { on, dir, speed }). Pure rendering; never reads aura data.
--
-- ⚠ Both go through an AnimationGroup, deliberately NOT Texture:SetRotation.
-- SetRotation is implemented through the texture COORDINATES, so it fights the
-- SetTexCoord(0.08, 0.92, …) border trim that every spell icon carries — which
-- is exactly why "texture transforms (Mirror, Rotation, Texture Wrap)" sat
-- parked in the handoff. A Rotation animation transforms the region's GEOMETRY
-- instead and leaves texcoords untouched, so the trim, the tint, the blend mode
-- and the desaturation all survive. The fixed angle rides the same mechanism as
-- the spin rather than taking the tempting SetRotation shortcut, because that
-- shortcut is the parked trap.
--
-- HOW ONE GROUP SERVES BOTH: a completed animation inside a still-running group
-- holds its end state, so order 1 snaps to the fixed angle and order 2 spins on
-- from there. With the spin off, order 2 becomes a long zero-degree hold leg and
-- the icon simply sits at the angle. Looping is REPEAT in both cases; the
-- re-snap at the top of each loop lands on the same angle, so it is invisible.
--
-- ⚠ A rotated texture is NOT clipped to its frame — WoW frames don't clip their
-- regions — so a square icon sweeps out to ~1.41× its width at 45°. That is the
-- correct look, not a sizing bug. Size the aura for the swept circle.
--
-- The label and the cooldown swipe are separate regions and stay upright.
-- --------------------------------------------------------------------------
local ROT_BASE_REV = 3.0     -- seconds per revolution at Speed 100%
local ROT_HOLD     = 3600    -- the no-spin hold leg; re-snaps hourly to the same angle

-- ⚠ ApplyConfig runs HOT (suite backlog item 4: ApplyStyle was seen firing dozens
-- of times for one user action). Restarting the animation on every call would
-- snap the icon back to 0° each time and read as a stutter, so the applied
-- settings are cached on the frame and an unchanged push is a no-op — the same
-- redundant-push guard the duration bars already carry.
local function RotKey(cfg)
  -- Nothing to turn: a bar's texture is hidden, and cfg.noArt hides it deliberately.
  -- Rotation drives f.tex and ONLY f.tex (SetChildKey("tex")), so in either state a
  -- running animation would be pure cost for zero pixels.
  if not cfg or cfg.kind == "bar" or cfg.noArt then return "off" end
  local angle = tonumber(cfg.angle) or 0
  local r = cfg.rotate
  local spin = (r and r.on) and ((r.dir == "ccw" and "ccw" or "cw") .. ":" .. tostring(tonumber(r.speed) or 100)) or "-"
  if angle == 0 and spin == "-" then return "off" end
  return angle .. "|" .. spin
end

function D:ApplyRotation(displayID)
  local f = self.frames[displayID]; if not f then return end
  local cfg = self:Config(displayID)
  local key = RotKey(cfg)

  -- Hidden frames never animate: an animation on a hidden region is wasted work,
  -- and OnShow re-applies. Clearing the cached key is what makes that land.
  if not f:IsShown() then
    if f.rotAG then f.rotAG:Stop() end
    f.__rotKey = nil
    return
  end
  if f.__rotKey == key and (key == "off" or (f.rotAG and f.rotAG:IsPlaying())) then return end
  f.__rotKey = key

  if key == "off" then
    if f.rotAG then f.rotAG:Stop() end   -- Stop() snaps the region back to 0°
    return
  end

  local ag = f.rotAG
  if not ag then
    if not f.tex then return end
    -- The group belongs to the FRAME and each animation is pointed at the texture
    -- by its key (f.tex) — LibCustomGlow's own pattern, right there in Libs/, so
    -- this is the shape the client is known to accept rather than the one that
    -- reads nicest.
    ag = f:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    ag.base = ag:CreateAnimation("Rotation")   -- order 1: the fixed angle
    ag.base:SetOrder(1); ag.base:SetDuration(0)
    ag.base:SetChildKey("tex"); ag.base:SetOrigin("CENTER", 0, 0)
    ag.spin = ag:CreateAnimation("Rotation")   -- order 2: the continuous spin, or a hold
    ag.spin:SetOrder(2)
    ag.spin:SetChildKey("tex"); ag.spin:SetOrigin("CENTER", 0, 0)
    f.rotAG = ag
  end

  -- WoW rotation is CCW-positive (GB's Anims carry the same note), so a positive
  -- user-facing angle/direction — which reads as CLOCKWISE — is negated here.
  ag:Stop()                                    -- durations/degrees are read at Play()
  ag.base:SetDegrees(-(tonumber(cfg.angle) or 0))

  local r = cfg.rotate
  if r and r.on then
    local pct = tonumber(r.speed) or 100
    if pct < 10 then pct = 10 end
    ag.spin:SetDuration(ROT_BASE_REV / (pct / 100))
    ag.spin:SetDegrees((r.dir == "ccw") and 360 or -360)
  else
    ag.spin:SetDuration(ROT_HOLD)              -- park at the fixed angle
    ag.spin:SetDegrees(0)
  end
  ag:Play()
end

-- --------------------------------------------------------------------------
-- Shape (cfg.shape = a GloomsHub.SHAPES key). Clips the aura's texture to one of
-- the suite's 21 silhouettes — the SAME catalog and the SAME art Gloom's Bars
-- masks its action buttons with, so an aura parked over a button can wear that
-- button's own outline instead of being a square sitting on top of it.
--
-- ⚠ Anchored with GloomsHub:GrowAnchor, NOT SetAllPoints. The art is 512×512 with
-- the silhouette occupying the central HALF (a 128px transparent margin all round
-- — GB's ART-SPEC), so the file has to be anchored to a rect twice the icon's size
-- for the shape itself to land exactly on the icon. GrowAnchor at grow 0 is
-- precisely that rect, and it is the same helper every shaped effect uses.
--
-- ⚠ AddMaskTexture SILENTLY FAILS on a texture that has never rendered (GB's
-- API-NOTES §2, verified) — and ApplyConfig routinely runs while an aura is
-- hidden, which is exactly that case. So OnShow re-runs this one frame later, by
-- which point f.tex has drawn and accepts the mask. The remove-before-add keeps
-- the attachment count at 1: the documented hard cap is 3 per texture.
--
-- ⚠ A mask does NOT rotate with the texture it clips. A shaped aura that also
-- spins turns INSIDE a static silhouette — art moving behind a shaped window,
-- which is a real effect but is NOT "a spinning rounded square".
-- --------------------------------------------------------------------------
function D:ApplyShape(displayID)
  local f = self.frames[displayID]; if not (f and f.tex) then return end
  local cfg = self:Config(displayID)
  local hub = _G.GloomsHub
  -- A bar display's texture is hidden, so there is nothing to clip.
  local key = (cfg and cfg.kind ~= "bar") and cfg.shape or nil
  local path = key and hub and hub.ShapeAsset and hub:ShapeAsset(key, "base")

  if not path then
    if f.shapeMask then
      if f.__maskAdded then f.tex:RemoveMaskTexture(f.shapeMask); f.__maskAdded = nil end
      f.shapeMask:Hide()
    end
    f.__shapeKey = nil
    return
  end

  local mask = f.shapeMask
  if not mask then mask = f:CreateMaskTexture(); f.shapeMask = mask end
  -- CLAMPTOBLACKADDITIVE on both axes, and the art is WHITE: a mask reads
  -- LUMINANCE, not alpha, and a black-rgb mask does not clip at all (API-NOTES §2).
  mask:SetTexture(path, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  mask:Show()
  -- Anchored to the FRAME, not to f.tex: f:SetSize was just called with explicit
  -- numbers, whereas f.tex is SetAllPoints and its size is resolved from anchors.
  hub:GrowAnchor(mask, f, 0)
  if f.__maskAdded then f.tex:RemoveMaskTexture(mask) end
  f.tex:AddMaskTexture(mask)
  f.__maskAdded = true
  f.__shapeKey = key
end

-- --------------------------------------------------------------------------
-- Shaped animations (cfg.effects = { anim = <id>, params = { [id] = {..} } }).
-- The modules are GloomsHub.Effects — the SAME eight Gloom's Bars runs on its
-- action buttons, rendering here against an aura display instead of a button.
-- They were written host-agnostic from the start, so nothing about them had to
-- change to serve GA.
--
-- ⚠ EVERY module needs a silhouette key; with no cfg.shape there is nothing to
-- trace and they are skipped. The Effects UI says so rather than letting a switch
-- turn on and do nothing.
--
-- The host AND the icon reference are both `f`, deliberately: f:SetSize was called
-- with explicit numbers, while f.tex is SetAllPoints and resolves its size from
-- anchors — and with cfg.noArt, f.tex is hidden and has no useful size at all.
-- --------------------------------------------------------------------------
-- A stable signature of "what should be running": the module, the silhouette, and
-- every merged param value. Colour tables are flattened so a table identity change
-- with the same three channels does not read as a change.
local function EffectsKey(id, shapeKey, merged)
  if not id then return "off" end
  local keys = {}
  for k in pairs(merged) do keys[#keys + 1] = k end
  table.sort(keys)
  local parts = { id, tostring(shapeKey) }
  for _, k in ipairs(keys) do
    local v = merged[k]
    if type(v) == "table" then
      parts[#parts + 1] = k .. "=" .. tostring(v[1]) .. "," .. tostring(v[2]) .. "," .. tostring(v[3])
    else
      parts[#parts + 1] = k .. "=" .. tostring(v)
    end
  end
  return table.concat(parts, "|")
end

function D:ApplyEffects(displayID)
  local f = self.frames[displayID]; if not f then return end
  local E = _G.GloomsHub and _G.GloomsHub.Effects
  if not E then return end
  local cfg = self:Config(displayID)
  local fx = (cfg and cfg.kind ~= "bar") and cfg.effects or nil
  local key = cfg and cfg.shape
  local want = (f:IsShown() and key and fx and fx.anim) or nil
  local merged = want and E:MergeParams(want, fx.params and fx.params[want]) or nil
  if want and not merged then want = nil end   -- unknown module id (a Hub downgrade)

  -- ⚠ REDUNDANT-PUSH GUARD, and it is not an optimisation. ApplyConfig runs HOT
  -- (suite backlog item 4: dozens of calls for a single user action), and every
  -- Start re-primes its textures to PRIME_ALPHA and only reveals them a frame
  -- later — so an unguarded re-push storm leaves an animation flickering or
  -- invisible rather than merely costing time. GB never met this because its
  -- Reconcile skips when the winning trigger is unchanged; this is GA's equivalent.
  local sig = EffectsKey(want, key, merged or {})
  if f.__fxKey == sig then return end
  f.__fxKey = sig

  E:Each(function(mod)
    if want == mod.id then
      mod:Start(f, f, key, merged)
    else
      mod:Stop(f)
    end
  end)
end

-- --------------------------------------------------------------------------
-- Frame creation + config application
-- --------------------------------------------------------------------------
function D:GetOrCreate(spellID)
  local cfg = self:Config(spellID)
  if not cfg then return nil end

  local f = self.frames[spellID]
  if not f then
    f = CreateFrame("Frame", "GloomsAurasDisplay" .. spellID, UIParent)
    f:SetFrameStrata("HIGH")
    f.spellID = cfg.spellID or spellID   -- the tracked spell (the key may be a duplicate id)

    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    f.tex = tex

    -- The on-screen text gets a frame of its OWN above everything the aura draws.
    -- A FontString on `f` sat UNDER a bar aura's bar (a child frame) and the
    -- engine's fill button over it (bar level +1) — seen by the owner 2026-09-27,
    -- "fdsa … is UNDER the bar". Same fix as the bar's value text (EnsureBar).
    -- Its level is re-set in ApplyConfig, after the aura's own Level.
    local textTop = CreateFrame("Frame", nil, f)
    textTop:SetAllPoints(f)
    f.textTop = textTop
    local label = textTop:CreateFontString(nil, "OVERLAY")
    f.label = label   -- font/size/outline/color/anchor all set in ApplyConfig (cfg.text)

    -- Native cooldown swipe (used for cooldown-type displays). The game draws
    -- the sweep + countdown from a (possibly secret) duration — we never read it.
    local ok, cd = pcall(CreateFrame, "Cooldown", nil, f, "CooldownFrameTemplate")
    if ok and cd then
      cd:SetAllPoints()
      cd:SetDrawSwipe(true); cd:SetDrawEdge(true)
      if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(false) end
      cd:Hide()
      f.cd = cd
    end

    -- Drag-to-position (active only while the options panel is open = forced).
    -- NOT clamped to screen: auras may be positioned/dragged partially (or fully)
    -- off-screen on purpose (e.g. a huge texture bleeding past the edges). Recover a
    -- lost one via the X/Y boxes or the list (force-shown while the panel is open).
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self2)
      -- Only the selected aura drags (nil selection = preview back-door: any drags).
      if not D.forced then return end
      if D.selectedID and D.frames[D.selectedID] ~= self2 then return end
      self2.__dragging = true; self2:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self2)
      self2:StopMovingOrSizing(); self2.__dragging = false
      D:SavePositionFromFrame(spellID)
      if GA.Config and GA.Config.RefreshCurrent then GA.Config:RefreshCurrent() end
    end)

    -- Glow and rotation follow the frame's shown state (OnShow starts them,
    -- OnHide stops them) — neither costs anything while the aura is off screen.
    f.displayID = spellID   -- the frames key, so the hooks can look up cfg
    f:SetScript("OnShow", function(self2)
      D:ApplyGlow(self2.displayID); D:ApplyRotation(self2.displayID); D:ApplyEffects(self2.displayID)
      -- Deferred by one frame ON PURPOSE: the mask cannot attach to a texture that
      -- has never rendered, and until this OnShow returns, f.tex never has.
      local id = self2.displayID
      C_Timer.After(0, function() D:ApplyShape(id) end)
    end)
    f:SetScript("OnHide", function(self2)
      StopGlow(self2)
      if self2.rotAG then self2.rotAG:Stop() end
      self2.__rotKey = nil   -- so the next OnShow re-arms the spin
      self2.__fxKey = nil               -- so the next OnShow re-arms them
      D:ApplyEffects(self2.displayID)   -- f:IsShown() is already false here, so this stops them
      -- A bar keeps its last fill while hidden; flag it so the next feed SNAPS to the correct
      -- value (Immediate) instead of easing from the stale one — kills the target-swap catch-up.
      if self2.bar then self2.bar.__needSnap = true end
    end)

    f:Hide()
    self.frames[spellID] = f
  end

  self:ApplyConfig(spellID)
  f:EnableMouse((self.forced and (self.selectedID == nil or spellID == self.selectedID)) and true or false)
  return f
end

-- The charge-count string for a count-mode text overlay: the exact number when it's secret-safely
-- known (the endpoints max/0 always are; the middle only for 2-charge spells), else "" (a 3+
-- charge spell mid-recharge is genuinely unreadable). Resolves the spell via DisplayChargeSpell.
function D:CountString(cfg)
  if not (GA.CDM and GA.CDM.DisplayChargeSpell) then return "" end
  local sid = GA.CDM:DisplayChargeSpell(cfg)
  if not sid then return "" end
  local n = GA.CDM:ChargeCount(sid)
  return (n ~= nil) and tostring(n) or ""
end

-- Live-refresh a count-mode overlay's number without redoing font/anchor — called from
-- RefreshDisplays on charge transitions. No-op unless the display is shown + in count mode.
function D:RefreshCountText(spellID)
  local f = self.frames[spellID]
  if not f or not f.label then return end
  local cfg = self:Config(spellID); local t = cfg and cfg.text
  if not (t and t.show ~= false and t.showCount) then return end
  f.label:SetText(self:CountString(cfg))
end

-- --------------------------------------------------------------------------
-- Bar displays (cfg.kind == "bar"): a StatusBar child instead of the icon texture.
-- The FILL is driven by a secret-safe duration OBJECT fed via SetTimerDuration (the bar
-- animates itself; we never read the time — see CDM:UpdateBar / BarDurationObject). Styling
-- (texture/colour/orientation) is pure rendering. See docs/BARS-DESIGN.md.
-- --------------------------------------------------------------------------
local function EnsureBar(f)
  if f.bar then return f.bar end
  local bar = CreateFrame("StatusBar", nil, f)
  bar:SetAllPoints(f)
  -- A self-contained white fill (SetStatusBarColor tints it) — no Blizzard chrome. An LSM
  -- statusbar texture can replace it per-bar (cfg.bar.texture).
  local fill = bar:CreateTexture(nil, "ARTWORK")
  fill:SetColorTexture(1, 1, 1, 1)
  bar:SetStatusBarTexture(fill)
  bar.fill = fill
  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(bar)
  bar.bg = bg
  -- Value text (stacks count). Its own FontString (NOT the shared name label) centred on the bar;
  -- fed the raw applications via SetText, which accepts a SECRET value (renders it in combat).
  -- ⚠ The value text needs its own frame ABOVE the bar, not a FontString on the bar itself.
  -- On 12.1 the duration engine anchors a Blizzard AuraButton over this bar to render the fill
  -- (AuraDuration.lua), at bar level +1 — so anything drawn ON the bar is buried by the fill
  -- whenever the bar is full. A FontString can never out-draw a higher FRAME level, no matter
  -- its draw layer, so the text gets a frame of its own that outranks the button.
  local top = CreateFrame("Frame", nil, bar)
  top:SetAllPoints(bar)
  top:SetFrameLevel(bar:GetFrameLevel() + 5)
  bar.top = top
  local vt = top:CreateFontString(nil, "OVERLAY")
  vt:SetPoint("CENTER", top, "CENTER", 0, 0)
  vt:Hide()
  bar.valueText = vt
  f.bar = bar
  return bar
end

-- Where a bar READOUT sits. Shared by both of them: the stack count (GA's own FontString,
-- below) and the countdown (a FontString the engine's AuraButton owns — AuraDuration.lua
-- calls this too, so the two can never drift apart or land on top of each other by default).
-- Anchors are inset a few px so text never kisses the bar's edge.
local READOUT = {
  CENTER = { "CENTER",       0,   0 },
  LEFT   = { "LEFT",         5,   0 },
  RIGHT  = { "RIGHT",       -5,   0 },
  TOP    = { "TOP",          0,  -3 },
  BOTTOM = { "BOTTOM",       0,   3 },
}
-- The fill texture a bar config asks for, as a PATH — or nil for "use the plain colour fill".
-- ⚠ Resolve from CONFIG, never by reading a live bar's texture back with GetTexture(): that
-- returns nil for a colour texture, and on 12.1 the engine can re-bind its own StatusBar and
-- drop whatever we last pushed. Both the GA bar and the engine's overlay call this, so they
-- can never disagree about what the fill should look like.
-- cfg.bar.texture may be an LSM statusbar NAME (what /ga and older configs store) or a full
-- path (what the texture picker hands back).
function D:BarTexturePath(b)
  local t = b and b.texture
  if type(t) ~= "string" or t == "" then return nil end
  return (LSM and LSM.Fetch and LSM:Fetch("statusbar", t, true)) or t
end

-- The backdrop behind the fill. Split out of ApplyBarStyle because it is the ONE part of a
-- bar's look that changes MID-COMBAT: while the tracked DoT is in its pandemic window the
-- backdrop wears cfg.bar.pandemicBg instead of cfg.bar.bg (CDM.inPandemic, set from the
-- same cleaned-up alert that drives the pandemic sound). The FILL cannot do this on 12.1 —
-- the drained fill belongs to the duration engine's Blizzard button, a forbidden object
-- whenever auras are secret, so a fill recolour would queue until combat ends and never
-- be seen. The backdrop is GA's own texture on GA's own frame, touchable at any time —
-- and by the pandemic point the bar is mostly drained, so the backdrop IS most of what
-- is on screen. Called with the display KEY (not cfg.spellID) because that is what
-- CDM.inPandemic is keyed on.
function D:ApplyBarBackground(f, cfg, id)
  local bar = f and f.bar
  if not (bar and bar.bg) then return end
  local b   = (cfg and cfg.bar) or {}
  local bgc = b.bg or { 0, 0, 0, 0.55 }
  local pan = b.pandemicBg
  if pan and id and GA.CDM and GA.CDM.inPandemic and GA.CDM.inPandemic[id] then
    -- The pandemic colour has no alpha of its own (the swatch picker returns RGB), so it
    -- borrows the normal backdrop's — the tint changes, the weight does not.
    bgc = { pan[1] or 0, pan[2] or 0, pan[3] or 0, pan[4] or bgc[4] or 0.55 }
  end
  bar.bg:SetColorTexture(bgc[1] or 0, bgc[2] or 0, bgc[3] or 0, bgc[4] or 0.55)
end

-- Repaint ONLY the backdrop of one display, by key. This is what the pandemic flag flip
-- calls: it must not go through ApplyConfig, which re-pushes the engine style and would
-- defer the whole thing to PLAYER_REGEN_ENABLED.
function D:RefreshBarBackground(id)
  local f, cfg = self.frames[id], self:Config(id)
  if f and cfg and cfg.kind == "bar" then self:ApplyBarBackground(f, cfg, id) end
end

function D:AnchorReadout(fs, parent, anchor)
  if not (fs and parent) then return end
  local a = READOUT[anchor or "CENTER"] or READOUT.CENTER
  fs:ClearAllPoints()
  fs:SetPoint(a[1], parent, a[1], a[2], a[3])
end

function D:ApplyBarStyle(f, cfg, id)
  local bar = EnsureBar(f)
  local b = cfg.bar or {}
  -- Fill texture: an LSM statusbar name if set + resolvable, else our white fill.
  -- cfg.bar.texture may be an LSM statusbar NAME (what /ga and older configs store) or a
  -- full PATH (what the Bar section's texture picker hands back, since the picker deals in
  -- paths). Try the name first, fall back to treating it as a path, then to our white fill.
  -- ⚠ Setting a PATH overwrites the texture object currently in the statusbar slot — which is
  -- bar.fill, the colour texture created in EnsureBar. So handing bar.fill back later restores
  -- an object whose texture is now a FILE, and the plain colour fill never comes back. Re-assert
  -- the colour every time we fall back to it; that is what makes "Default" actually work.
  local texPath = self:BarTexturePath(b)
  if texPath then
    bar:SetStatusBarTexture(texPath)
  else
    bar:SetStatusBarTexture(bar.fill)
    bar.fill:SetColorTexture(1, 1, 1, 1)
  end
  bar:SetOrientation((b.orientation == "VERTICAL") and "VERTICAL" or "HORIZONTAL")
  bar:SetReverseFill(b.reverse and true or false)
  -- Rotate the fill art with the bar. A gradient drawn for a horizontal bar reads wrong
  -- stood on end, so a vertical bar usually wants this on — but it is a choice, not a
  -- consequence, since a plain or symmetric texture looks the same either way.
  if bar.SetRotatesTexture then bar:SetRotatesTexture(b.rotateTexture and true or false) end
  local oc = GA.COLOR and GA.COLOR.orange
  local col = b.color or (oc and { oc.r, oc.g, oc.b }) or { 1, 0.47, 0.16 }
  bar:SetStatusBarColor(col[1] or 1, col[2] or 1, col[3] or 1)
  self:ApplyBarBackground(f, cfg, id)
  -- Initial state depends on mode: a stacks bar spans 0..max and starts empty; a duration bar
  -- spans 0..1 and starts full — both are corrected by the first CDM:UpdateBar feed.
  if b.mode == "stacks" then
    bar:SetMinMaxValues(0, b.max or 10)
    bar:SetValue(0)
  else
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
  end
  bar.__needSnap = true            -- first duration feed snaps to actual remaining (/reload mid-fight)
  -- Value text (stacks count) — its own font, shown only when the bar asks for it.
  local vt = bar.valueText
  if vt then
    -- showStacks prints the stack count on ANY bar — a ramping DoT like Agony drains and
    -- stacks at the same time. (It replaced the old mode-dependent `showValue`; Core.lua
    -- migrates that at login.)
    if b.showStacks then
      -- cfg.bar.font is shared by BOTH readouts (see the Bar section) so a bar's numbers
      -- always match each other; AuraDuration reads the same field for the countdown.
      local font = b.font or (GA.FONT and GA.FONT.body) or (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")
      local size = b.stackSize or b.valueSize or 14
      if not GA.SetFontSafe(vt, font, size, "OUTLINE") then
        GA.SetFontSafe(vt, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "OUTLINE")
      end
      local sc = b.stackColor
      vt:SetTextColor(sc and sc[1] or 1, sc and sc[2] or 1, sc and sc[3] or 1)
      -- ★ Defaults to TOP, not CENTER — on a duration bar the countdown already owns the
      -- centre, and two readouts defaulting to the same spot print one over the other.
      self:AnchorReadout(vt, bar, b.stackAnchor or (b.mode == "stacks" and "CENTER" or "TOP"))
      vt:Show()
    else
      vt:Hide()
    end
  end
  bar:SetAlpha(cfg.alpha or 1)
  bar:Show()
end

-- Feed the source aura's live duration OBJECT so the bar drains itself (no polling). Resolved
-- + validated secret-safely in CDM:BarDurationObject. No-op if the object isn't resolvable yet
-- (e.g. a secret auraInstanceID in instances) — the bar just stays full rather than erroring.
-- REMOVED 2026-08-03 — the Tracked-Bar MIRROR (StartMirror/StopMirror + CDM:BarMirrorValues).
-- It polled a Blizzard Tracked-Bar frame's .Bar on an OnUpdate and copied the secret value
-- across. It worked, but AuraContainer superseded it outright: the mirror required the user to
-- add every aura to Blizzard's "Tracked Bars" list by hand (which also removes it from Tracked
-- Buffs), and it became unreachable once the engine started attaching first. Full record in
-- ~/GloomsHub/docs/FINDINGS.md §1 — do not rebuild it.

-- The stack count on a DURATION bar (cfg.bar.showStacks). Kept separate from the fill: the
-- engine owns the drain, we own the number. The value arrives as a SECRET on 12.1, so it goes
-- straight into SetText — which renders a secret — and is never compared or formatted.
function D:UpdateStackText(spellID, cfg)
  local f = self.frames[spellID]; if not f or not f.bar then return end
  local b = cfg.bar or {}
  local vt = f.bar.valueText
  if not vt or not b.showStacks then return end
  if not (GA.CDM and GA.CDM.BarStackValue) then return end
  local v = GA.CDM:BarStackValue(cfg)
  if v == nil then vt:SetText("") return end
  pcall(function()
    if issecret(v) then vt:SetText(v)          -- SetText accepts the secret directly
    else vt:SetText(tostring(v)) end
  end)
end

function D:UpdateBar(spellID)
  local f = self.frames[spellID]; if not f or not f.bar then return end
  local cfg = self:Config(spellID); if not cfg or cfg.kind ~= "bar" then return end
  if not GA.CDM then return end
  local b = cfg.bar or {}

  if b.mode == "stacks" then
    -- Stacks: feed the (possibly SECRET) applications count straight to SetValue + SetText.
    -- We never operate on it; both sinks are AllowedWhenTainted so they render a secret in combat.
    if not GA.CDM.BarStackValue then return end
    local v = GA.CDM:BarStackValue(cfg)
    if v == nil then return end
    pcall(function()
      f.bar:SetMinMaxValues(0, b.max or 10)
      f.bar:SetValue(v)
      local vt = f.bar.valueText
      if vt and b.showStacks then
        if issecret(v) then vt:SetText(v)              -- SetText accepts the secret directly
        else vt:SetText(tostring(v)) end               -- plain (out of combat)
      end
    end)
    return
  end

  -- Duration modes (aura_dur / cd_dur): feed a duration OBJECT so the bar self-drains. Same feed
  -- code — only the object's source differs (the source aura's remaining vs the spell's cooldown).
  local durObj
  if b.mode == "cd_dur" then
    -- Resolve through DisplaySpellID: a display built in the Auras tab keeps its spell in
    -- the first trigger condition, not in cfg.spellID.
    local cdSid = GA.CDM.DisplaySpellID and GA.CDM:DisplaySpellID(cfg) or cfg.spellID
    durObj = cdSid and GA.CDM.CdDurationObject and GA.CDM:CdDurationObject(cdSid)
  else
    durObj = GA.CDM.BarDurationObject and GA.CDM:BarDurationObject(cfg)
  end
  if not durObj then
    -- 12.1 ROUTE: hand the bar to the AuraContainer engine, which renders the drain into
    -- regions a Blizzard AuraButton owns (AuraDuration.lua). This is the ONLY route now —
    -- the Tracked-Bar mirror that used to sit below was removed 2026-08-03.
    if b.mode ~= "cd_dur" and GA.AuraDuration and GA.AuraDuration:Attach(spellID, f, cfg) then
      -- ⚠ EMPTY OUR OWN FILL — but NOT while the editor is open. Once the engine drives
      -- this bar it owns the fill, and leaving ours full underneath masks the drain
      -- completely. In PREVIEW though there is usually no live aura, so the engine draws
      -- nothing and a zeroed bar means the user is styling something invisible: texture,
      -- colour and rotation all apply correctly and show nothing at all. Measured
      -- 2026-08-03 — that is why picking a texture appeared to do nothing, while nudging a
      -- slider "fixed" it (MakeSlider fires an extra ReapplySelected AFTER this, which
      -- re-fills the bar). Keeping it full while forced makes the preview honest.
      if not self.forced then pcall(function() f.bar:SetValue(0) end) end
      -- Paint AFTER the attach: a re-parse can hand the slot a different button whose
      -- regions have never been styled, and Attach clears the style fingerprint precisely
      -- so this push is not skipped as redundant.
      -- (An earlier version of this comment claimed the engine RESETS the region and wiped
      -- our paint. That was disproved 2026-08-03 by reading the texture back — it always
      -- returned what we last set. The real cause of "the texture does nothing" was the
      -- preview blanking GA's own bar, fixed just above.)
      if GA.AuraDuration.ApplyStyle then GA.AuraDuration:ApplyStyle(spellID, f, cfg) end
      self:UpdateStackText(spellID, cfg)
      return
    end
    -- No duration object and no engine attach: nothing can drive this bar. It keeps whatever
    -- ApplyBarStyle last set rather than erroring — the usual cause is a bar with no
    -- cfg.spellID, which Attach refuses outright.
    return
  end
  if not (Enum and Enum.StatusBarInterpolation and Enum.StatusBarTimerDirection and f.bar.SetTimerDuration) then return end
  local dir = (b.fill == "fill") and Enum.StatusBarTimerDirection.ElapsedTime
                                 or  Enum.StatusBarTimerDirection.RemainingTime
  -- Snap (Immediate) on the first feed after a (re)show so a stale fill doesn't visibly catch up;
  -- ease (ExponentialEaseOut) on live re-feeds (a DoT refresh grows smoothly). Either way the
  -- StatusBar self-animates the drain from the duration object — the interp only affects jumps.
  local snap = f.bar.__needSnap
  f.bar.__needSnap = nil
  local interp = snap and Enum.StatusBarInterpolation.Immediate or Enum.StatusBarInterpolation.ExponentialEaseOut
  pcall(function()
    f.bar:SetMinMaxValues(0, 1)
    f.bar:SetTimerDuration(durObj, interp, dir)
  end)
end

-- Instrument (Hub backlog item 4, measured 2026-09-20): who calls ApplyConfig /
-- ApplyStyle, how often. OFF unless `/ga hot on`; `/ga hot` prints the tally and
-- resets it; `/ga hot off` stops it. debugstack per call is not free, so it never
-- runs in normal play. Diagnostic only — no behaviour.
function GA.HotCount(what)
  local h = GA.hot; if not h then return end
  local who = (debugstack(3, 1, 0) or ""):match("[^\n]*") or "?"
  who = who:gsub("^Interface/AddOns/", ""):gsub("^%[string \"", ""):gsub("%]:", ":"):gsub(": in function.*$", "")
  local key = what .. " <- " .. who
  h[key] = (h[key] or 0) + 1
end

function D:ApplyConfig(spellID)
  GA.HotCount("ApplyConfig")
  local f = self.frames[spellID]
  local cfg = self:Config(spellID)
  if not f or not cfg then return end

  local w = cfg.width or cfg.size or 64
  local h = cfg.height or cfg.size or 64
  f:SetSize(w, h)

  -- point = { "CENTER", x, y }: offsets from the screen's centre (up/right +),
  -- or from its GROUP's anchor (D:Place). A group's scale is the frame's scale,
  -- so everything the aura draws — art, text, glow, bar — grows with it; the
  -- offset is divided back out because SetPoint works in the frame's own scale.
  local rel, px, py, k = self:Place(cfg)
  f:SetScale(k)
  if not f.__dragging then  -- don't snap it back mid-drag
    f:ClearAllPoints()
    f:SetPoint("CENTER", rel, "CENTER", px / k, py / k)
  end

  if cfg.kind == "bar" then
    -- Bar display: a StatusBar drives the visual; hide the icon texture + cooldown swipe.
    f.tex:Hide()
    if f.cd then f.cd:Hide() end
    self:ApplyBarStyle(f, cfg, spellID)
    -- On 12.1 the visible fill of a duration bar belongs to the engine's button, not to
    -- f.bar — so restyling f.bar alone changes nothing the user can see. Push the same
    -- look onto the engine's region too (it no-ops unless this display is attached, and
    -- defers itself if auras are currently secret).
    if GA.AuraDuration and GA.AuraDuration.ApplyStyle then
      GA.AuraDuration:ApplyStyle(spellID, f, cfg)
    end
    self:UpdateStackText(spellID, cfg)
  else
    -- Icon/texture display (default). Hide any bar child a kind-switch left behind.
    if f.bar then f.bar:Hide() end
    -- cfg.noArt — the aura draws NOTHING and contributes only its effects, so a glow
    -- can sit over a live action button without covering the button's own icon. This
    -- is a distinct state from "no texture chosen": an empty cfg.texture means GUESS
    -- (spell icon, then the loud magenta panel when even that fails), and that panel
    -- is right for an aura meant to show art. It is exactly wrong for an overlay,
    -- which is why "unset" could never be made to mean this.
    f.tex:SetShown(not cfg.noArt)

    -- Texture: a custom file path / fileID if set, else the spell's own icon.
    -- ★ Since 2026-10-05 (the owner: "select those for texture auras, just like
    -- I can for overlays") it is ANYTHING the Hub's texture browser hands back —
    -- a Suite media name, an atlas, a file ID or a path — and `cfg.sheet` (the
    -- Hub's SheetFor: cols × rows > 1) plays it as a FLIPBOOK, frame by frame,
    -- exactly as Gloom's UI does. The stepping runs on a child frame, so a
    -- hidden aura costs nothing.
    local custom = cfg.texture
    if type(custom) == "string" and custom:match("^%d+$") then custom = tonumber(custom) end  -- a typed/stored fileID
    local sh = cfg.sheet
    if not (sh and sh.fileID and (sh.cols or 1) * (sh.rows or 1) > 1) then sh = nil end
    if f.flip then f.flip:SetScript("OnUpdate", nil) end
    if custom and custom ~= "" and sh then
      f.tex:SetTexture(sh.fileID)
      local cols, rows = sh.cols or 1, sh.rows or 1
      local uL, vT = sh.uLeft or 0, sh.vTop or 0
      local cw, rh = ((sh.uRight or 1) - uL) / cols, ((sh.vBottom or 1) - vT) / rows
      f.tex:SetTexCoord(uL, uL + cw, vT, vT + rh)
      -- which frame: the Hub's ONE timing (Forward / Reverse / eased Ping-Pong,
      -- GloomsHub:SheetFrame — 2026-10-06), so every tool plays alike
      local elapsed, shown = 0, -1
      local function show(frame)
        if frame == shown then return end
        shown = frame
        local col, row = frame % cols, math.floor(frame / cols)
        f.tex:SetTexCoord(uL + col * cw, uL + (col + 1) * cw, vT + row * rh, vT + (row + 1) * rh)
      end
      show(GloomsHub:SheetFrame(sh, 0))
      f.flip = f.flip or CreateFrame("Frame", nil, f)
      f.flip:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        show(GloomsHub:SheetFrame(sh, elapsed))
      end)
    elseif custom and custom ~= "" then
      -- a Suite media name, then a file ID, then an ATLAS (its file, cut to its
      -- coordinates), else a path
      local path = type(custom) == "string" and GloomsHub and GloomsHub.ResolveAssetPath and GloomsHub:ResolveAssetPath(custom)
      local info = type(custom) == "string" and not path and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(custom)
      if path then f.tex:SetTexture(path); f.tex:SetTexCoord(0, 1, 0, 1)
      elseif info then
        f.tex:SetTexture(info.file)
        f.tex:SetTexCoord(info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord)
      else
        f.tex:SetTexture(custom)
        f.tex:SetTexCoord(0, 1, 0, 1)
      end
    else
      -- The display's spell as the engine resolves it (its first trigger, for an aura
      -- built in the tab — cfg.spellID is nil there, and `spellID` is the display KEY,
      -- "d18", so this lookup always failed and every texture-less aura drew magenta).
      -- The owner ruled 2026-09-20: a texture-less aura shows its spell's icon; an
      -- explicit texture pick always wins (the branch above).
      local sid = (GA.CDM and GA.CDM.DisplaySpellID and GA.CDM:DisplaySpellID(cfg)) or cfg.spellID or spellID
      local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)
      if icon then
        f.tex:SetTexture(icon)
        f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- trim the default icon border
      elseif cfg.uiType ~= "texture" then
        -- An ICON aura with no trigger yet shows the game's red question mark
        -- (the owner, 2026-09-27) — the same placeholder the aura list uses. An
        -- aura from before the type was saved counts as an icon aura.
        f.tex:SetTexture(134400)
        f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      else
        f.tex:SetColorTexture(0.9, 0.2, 0.6)  -- a TEXTURE aura with no art: unmistakable magenta
        f.tex:SetTexCoord(0, 1, 0, 1)
      end
    end
    f.tex:SetAlpha(cfg.alpha or 1.0)

    -- Recolour / blend / desaturate — pure rendering, no combat data involved.
    f.tex:SetBlendMode((cfg.blend and cfg.blend ~= "" and cfg.blend) or "BLEND")
    f.tex:SetDesaturated(cfg.desaturate and true or false)
    local c = self:TintFor(cfg)
    if c then
      f.tex:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1)
    else
      f.tex:SetVertexColor(1, 1, 1)
    end
  end

  -- Frame strata (how the aura layers against other UI).
  f:SetFrameStrata((cfg.strata and cfg.strata ~= "" and cfg.strata) or "HIGH")
  -- …and the level within it (the Appearance page's LEVEL, 2026-09-23). nil = the
  -- frame's own natural level, remembered the first time through so that clearing
  -- the setting puts it back rather than leaving the last number in place.
  f._baseLevel = f._baseLevel or f:GetFrameLevel()
  f:SetFrameLevel(cfg.level or f._baseLevel)
  -- the text's frame above the bar (+1), the engine's fill (+2) and its holder (+2)
  if f.textTop then f.textTop:SetFrameStrata(f:GetFrameStrata()); f.textTop:SetFrameLevel(f:GetFrameLevel() + 10) end

  -- On-screen text overlay. cfg.text = { show, str, font, size, color, outline, anchor, x, y }.
  -- Backward-compat: no cfg.text ⇒ legacy behavior (show the aura's name via cfg.showLabel).
  local t = cfg.text
  local show
  if t then show = (t.show ~= false) else show = (cfg.showLabel ~= false) end
  if show then
    local str
    if t and t.showCount then
      str = self:CountString(cfg)                 -- live charge count (Pass 2), overrides custom text
    else
      str = (t and t.str and t.str ~= "" and t.str) or cfg.label or tostring(cfg.spellID or spellID)
    end
    local font = (t and t.font) or (GA.FONT and GA.FONT.body) or (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")
    local fallbackFont = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local size = (t and t.size) or 14
    local flags = (t and t.outline == "NONE") and "" or (t and t.outline) or "OUTLINE"
    local col = t and t.color
    local a = LABEL_ANCHOR[(t and t.anchor) or "BOTTOM"] or LABEL_ANCHOR.BOTTOM
    local ux, uy = (t and t.x) or 0, (t and t.y) or 0

    if not GA.SetFontSafe(f.label, font, size, flags) then
      GA.SetFontSafe(f.label, fallbackFont, size, flags)
    end
    f.label:SetTextColor(col and col[1] or 1, col and col[2] or 1, col and col[3] or 1)
    f.label:SetText(str)
    f.label:ClearAllPoints()
    f.label:SetPoint(a[1], f, a[2], a[3] + ux, a[4] + uy)
    f.label:Show()
  else
    f.label:Hide()
  end

  self:ApplyShape(spellID)      -- clip the texture to its silhouette (no-op without cfg.shape)
  self:ApplyEffects(spellID)    -- run the shaped animation, if one is picked
  self:ApplyGlow(spellID)       -- (re)apply the glow effect for this display's current config
  self:ApplyRotation(spellID)   -- ...and the spin (no-op unless the settings actually changed)
end

-- Create/refresh every enabled display frame (starts hidden; CDM decides shown).
function D:RefreshAll()
  local db = DB()
  if not db then return end
  for spellID, cfg in pairs(db) do
    if cfg.enabled ~= false then
      self:GetOrCreate(spellID)
    else
      local f = self.frames[spellID]
      if f then f:Hide() end
    end
  end
end

-- --------------------------------------------------------------------------
-- Show/hide (called by CDM). No-op while forced (preview/test).
-- --------------------------------------------------------------------------
function D:SetShown(spellID, value)
  if self.forced then return end
  local f = self.frames[spellID] or self:GetOrCreate(spellID)
  if f then pcall(f.SetShown, f, value) end
  -- ⚠ The 12.1 duration engine draws into a button owned by the AuraContainer, not by this
  -- frame — hiding `f` hides the label and the stack count but NOT the countdown, which keeps
  -- drawing over nothing. Tell the engine to release its button too, or a hidden display
  -- leaves a floating timer behind (seen after a mid-fight /reload, 2026-08-03).
  if GA.AuraDuration and GA.AuraDuration.SetSlotActive then
    GA.AuraDuration:SetSlotActive(spellID, value)
  end
end
-- The interrupt filter's alpha (CDM:KickGate): 1, 0, or a secret 0/1 the game
-- made from a target's "not interruptible" flag. On the display's own frame,
-- which nothing else fades; ignored (full) while previewing.
function D:SetGate(spellID, a)
  self.gate = self.gate or {}
  self.gate[spellID] = a
  if self.forced then return end
  local f = self.frames[spellID]
  if f then pcall(f.SetAlpha, f, a) end
end
function D:Show(spellID) self:SetShown(spellID, true) end
function D:Hide(spellID) self:SetShown(spellID, false) end

-- Save position from the frame's current (dragged) location; re-anchor cleanly.
function D:SavePositionFromFrame(spellID)
  local f, cfg = self.frames[spellID], self:Config(spellID)
  if not f or not cfg then return end
  local fx, fy = f:GetCenter()
  local ux, uy = UIParent:GetCenter()
  if not (fx and ux) then return end
  -- the frame's centre in UIParent units (a grouped aura's frame is scaled)
  local fk = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
  local x, y = fx * fk - ux, fy * fk - uy
  local g = self:GroupOf(cfg)
  if g then
    local ox, oy = self:GroupOrigin(g)
    local k = GroupScale(g)
    cfg.point = { "CENTER", math.floor((x - ox) / k + 0.5), math.floor((y - oy) / k + 0.5) }
  else
    cfg.point = { "CENTER", math.floor(x + 0.5), math.floor(y + 0.5) }
  end
  self:ApplyConfig(spellID)
  if self.RefreshGroupHandle then self:RefreshGroupHandle() end
end

-- Enable/disable mouse on all display frames (draggable while the panel is open).
-- Enable mouse (= draggable) only on the selected display while forced; the rest
-- stay visible but click-through so overlapping auras don't fight for the cursor.
-- With no selection (e.g. the /ga preview back-door) every display is draggable.
function D:ApplyInteractivity()
  local sel = self.selectedID
  local haveSel = sel ~= nil and self.frames[sel] ~= nil
  -- a GROUP selected: only its green box moves things (2026-10-05)
  local grp = self.editGroup ~= nil or self.multi ~= nil
  for id, f in pairs(self.frames) do
    f:EnableMouse((self.forced and not grp and (not haveSel or id == sel)) and true or false)
  end
end

function D:SetInteractive(on)
  self:ApplyInteractivity()
end

-- Panel selection changed → re-apply which single display is draggable.
-- THE EYE (the owner, 2026-09-27): each aura's saved eye (cfg.preview) is its
-- state while NOT selected. Selecting an aura shows it at once whatever that
-- says (`selShow`, fresh on every new selection); the eye on the selected aura
-- toggles only `selShow`, and when the selection moves on the aura goes back
-- to its saved eye.
function D:SetSelectedDisplay(id)
  if id ~= self.selectedID then self.selShow = true end
  self.selectedID = id
  self:ApplyInteractivity()
end

-- While the panel is open (forced) the on-screen preview shows ONLY the auras
-- whose eye is lit (D:EyeOn — the selected one's own switch, the rest their
-- saved cfg.preview) — so editing isn't buried
-- under every aura at once. Purely an editor convenience; in-game (not forced) is
-- unaffected, and cfg.preview has nothing to do with whether the aura runs.
function D:EyeOn(id)
  if id == nil then return false end
  if self.multi then for _, m in ipairs(self.multi) do if m == id then return true end end end
  if id == self.selectedID then return self.selShow ~= false end
  local db = DB(); local cfg = db and db[id]
  return (cfg and cfg.preview) and true or false
end
function D:ToggleEye(id)
  if id == self.selectedID then self.selShow = not self:EyeOn(id)
  else
    local db = DB(); local cfg = db and db[id]; if not cfg then return end
    cfg.preview = (not cfg.preview) or nil
  end
  self:RefreshForced()
end

function D:RefreshForced()
  if not self.forced then return end
  local db = DB(); if not db then return end
  for id in pairs(db) do
    if self:EyeOn(id) then
      local f = self:GetOrCreate(id); if f then f:SetAlpha(1); f:Show() end
    else
      local f = self.frames[id]; if f then f:Hide() end
    end
  end
end

-- Cooldown swipe (for cooldown-type displays). The game draws the sweep +
-- countdown from a possibly-secret duration; we never read the number.
function D:SetCooldownEnabled(spellID, on)
  local f = self.frames[spellID]
  if f and f.cd then f.cd:SetShown(on and true or false) end
end

function D:UpdateCooldown(spellID)
  local f = self.frames[spellID]
  if not f or not f.cd then return end
  local cfg = self:Config(spellID)
  local sid = (cfg and cfg.spellID) or spellID
  pcall(function()
    local info = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(sid)
    if not info then return end
    -- Cooldown setters are "AllowedWhenUntainted": an addon may pass PLAIN values
    -- (out of combat) but NOT secret ones (in combat) — that throws. So only draw
    -- the sweep when the values are readable; otherwise leave the icon bare.
    if issecret(info.startTime) or issecret(info.duration) then
      if f.cd.Clear then f.cd:Clear() end
      return
    end
    f.cd:SetCooldown(info.startTime, info.duration, info.modRate)
  end)
end

-- --------------------------------------------------------------------------
-- Position / size (numeric, live). Return true on success.
-- --------------------------------------------------------------------------
function D:SetPosition(spellID, x, y)
  local cfg = self:Config(spellID)
  if not cfg then return false end
  cfg.point = { "CENTER", x, y }
  self:ApplyConfig(spellID)
  return true
end

function D:SetDisplaySize(spellID, size)
  local cfg = self:Config(spellID)
  if not cfg then return false end
  cfg.size = size
  self:ApplyConfig(spellID)
  return true
end

-- --------------------------------------------------------------------------
-- Preview (toggle force-show so you can see displays while positioning them)
-- and test (force-show for a few seconds).
-- --------------------------------------------------------------------------
function D:Preview()
  self.forced = not self.forced
  self:SetInteractive(self.forced)
  if self.forced then
    local db = DB()
    if db then
      for spellID, cfg in pairs(db) do
        if cfg.enabled ~= false then
          local f = self:GetOrCreate(spellID)
          if f then f:SetAlpha(1); f:Show() end
        end
      end
    end
    GA.msg("preview |cff55ff55ON|r — all displays shown so you can position them. |cffffd200/ga preview|r again to turn off.")
  else
    GA.msg("preview |cffff5555OFF|r.")
    if GA.CDM and GA.CDM.Discover then GA.CDM:Discover() end
  end
  return self.forced
end

function D:Test(seconds)
  seconds = seconds or 5
  self.forced = true
  local db, n = DB(), 0
  if db then
    for spellID, cfg in pairs(db) do
      if cfg.enabled ~= false then
        local f = self:GetOrCreate(spellID)
        if f then f:Show(); n = n + 1 end
      end
    end
  end
  GA.msg(("test: showing %d display(s) for %ds."):format(n, seconds))
  C_Timer.After(seconds, function()
    D.forced = false
    if GA.CDM and GA.CDM.Discover then GA.CDM:Discover() end
  end)
end
