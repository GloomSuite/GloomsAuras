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

    local label = f:CreateFontString(nil, "OVERLAY")
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

  -- point = { "CENTER", x, y } ; x/y are offsets from screen centre (up/right +).
  local p = cfg.point or { "CENTER", 0, 0 }
  if not f.__dragging then  -- don't snap it back mid-drag
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", p[2] or 0, p[3] or 0)
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
    local custom = cfg.texture
    if type(custom) == "string" and custom:match("^%d+$") then custom = tonumber(custom) end  -- a typed/stored fileID
    if custom and custom ~= "" then
      f.tex:SetTexture(custom)
      f.tex:SetTexCoord(0, 1, 0, 1)
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
      else
        f.tex:SetColorTexture(0.9, 0.2, 0.6)  -- fallback: unmistakable magenta panel
        f.tex:SetTexCoord(0, 1, 0, 1)
      end
    end
    f.tex:SetAlpha(cfg.alpha or 1.0)

    -- Recolour / blend / desaturate — pure rendering, no combat data involved.
    f.tex:SetBlendMode((cfg.blend and cfg.blend ~= "" and cfg.blend) or "BLEND")
    f.tex:SetDesaturated(cfg.desaturate and true or false)
    if cfg.color then
      f.tex:SetVertexColor(cfg.color[1] or 1, cfg.color[2] or 1, cfg.color[3] or 1)
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
function D:Show(spellID) self:SetShown(spellID, true) end
function D:Hide(spellID) self:SetShown(spellID, false) end

-- Save position from the frame's current (dragged) location; re-anchor cleanly.
function D:SavePositionFromFrame(spellID)
  local f, cfg = self.frames[spellID], self:Config(spellID)
  if not f or not cfg then return end
  local fx, fy = f:GetCenter()
  local ux, uy = UIParent:GetCenter()
  if not (fx and ux) then return end
  cfg.point = { "CENTER", math.floor(fx - ux + 0.5), math.floor(fy - uy + 0.5) }
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", cfg.point[2], cfg.point[3])
end

-- Enable/disable mouse on all display frames (draggable while the panel is open).
-- Enable mouse (= draggable) only on the selected display while forced; the rest
-- stay visible but click-through so overlapping auras don't fight for the cursor.
-- With no selection (e.g. the /ga preview back-door) every display is draggable.
function D:ApplyInteractivity()
  local sel = self.selectedID
  local haveSel = sel ~= nil and self.frames[sel] ~= nil
  for id, f in pairs(self.frames) do
    f:EnableMouse((self.forced and (not haveSel or id == sel)) and true or false)
  end
end

function D:SetInteractive(on)
  self:ApplyInteractivity()
end

-- Panel selection changed → re-apply which single display is draggable.
function D:SetSelectedDisplay(id)
  self.selectedID = id
  self:ApplyInteractivity()
end

-- While the panel is open (forced) the on-screen preview shows ONLY the selected
-- aura + any aura the user has 'eyed' on (cfg.preview) — so editing isn't buried
-- under every aura at once. Purely an editor convenience; in-game (not forced) is
-- unaffected, and cfg.preview has nothing to do with whether the aura runs.
function D:RefreshForced()
  if not self.forced then return end
  local db = DB(); if not db then return end
  local sel = self.selectedID
  for id, cfg in pairs(db) do
    if (id == sel) or cfg.preview then
      local f = self:GetOrCreate(id); if f then f:Show() end
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
          if f then f:Show() end
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
