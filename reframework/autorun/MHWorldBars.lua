--[[
    MH World HUD gauges for MH Wilds (d2d)

    SOURCE OF TRUTH — copied verbatim from MH World:
      gui file      ui\hud\hud_gauge.gui
      texture page  ui\hud\tex\hud02_ID

      node                 rect (x0,y0)-(x1,y1)      size     used as
      tex_eGaugeL0         (0,55)-(24,88)            11x20    gw_hp_L  (arrow cap)
      tex_eGaugeC0         (22,55)-(502,88)          403x20   gw_hp_C  (stretch)
      tex_eGaugeR0         (502,55)-(512,88)         11x20    gw_hp_R  (end)
      tex_sGaugeL0         (0,172)-(22,205)          11x20    gw_st_L  (diamond cap)
      tex_eGaugeC0         (22,172)-(502,205)        403x20   gw_st_C
      tex_eGaugeR0         (502,172)-(512,205)       11x20    gw_st_R
      tex_eBace0           (0,93)-(64,131)           65x38    gw_bg_L  (track)
      tex_eBace1           (64,93)-(374,131)         32x29    gw_bg_C
      tex_eBace2           (461,93)-(511,131)        50x38    gw_bg_R
      tex_kBace            (0,133)-(113,166)         113x33   gw_sword
      tex_sharpGauge       (114,134)-(187,166)       72x34    gw_bar*  (tinted per tier)
      tex_sharpGaugeEff    (296,205)-(373,238)       76x32    gw_glow  (alpha 160)

    The src bands are 33 px tall but the art inside is 20 px, hence SRC_BAR.
    Layout fractions are re-read from data/mhw_bars.json every ~30 frames.
]]

local M = { enabled = true }

local F = {
    x = 0.095, y = 0.061,
    hp_w = 0.351, hp_h = 0.00955, hp_low = 0.40,
    st_w = 0.350, st_h = 0.00521,
    gap = 0.020,
    pad = 1,
    base_h = 2.2,          -- track height / bar height
    bracket_on = 1, bracket_h = 1.8, bracket_dx = 0.0035,
    sw_hl = 0.0176, sw_bw = 0.0434, sw_dx = 0.0063,
    sw_bx = 0.30, sw_bw_frac = 0.66, sw_bh = 0.97,
    sw_halo_w = 1.0, sw_halo_h = 1.0,
}

local SRC_BAR   = 20    -- bar height inside the 33 px band
local SRC_BAND  = 33
local SRC_BASE  = 38    -- tx_eBace height

local hp_L, hp_C, hp_R, st_L, st_C, st_R
local bg_L, bg_C, bg_R
local sword, bracket, glow_imgs, track
local bar_imgs = {}

local seg_rates, seg_tick = nil, 0

local function player_hud()
    local pm = sdk.get_managed_singleton("app.PlayerManager")
    if pm == nil then return nil end
    local ok, info = pcall(function() return pm:call("getMasterPlayerInfo") end)
    if not ok or info == nil then return nil end
    local ok2, ch = pcall(function() return info:get_field("<Character>k__BackingField") end)
    if not ok2 then return nil end
    return ch
end

local function read_sharpness()
    local step = "start"
    local ok, res = pcall(function()
        local ch = player_hud();                    step = "player";   if ch == nil then return nil end
        local wh = ch:call("get_WeaponHandling");   step = "handling"; if wh == nil then return nil end
        local k = wh:get_field("_Kireaji");         step = "kireaji";  if k == nil then return nil end
        local arr = k:call("get_KireajiData");      step = "data";     if arr == nil then return nil end
        step = "count"
        local n = arr:get_Count()
        step = "items"
        local vals = {}
        for i = 0, math.min(n - 1, 5) do vals[#vals + 1] = arr:get_Item(i) end
        step = "cur"
        local cur = 0
        local okc, v = pcall(function() return k:call("get_CurrentValue") end)
        if okc and type(v) == "number" then cur = v end

        -- the game tells us the tier directly: CurrentType is the active sharpness
        -- level, CurrentRate is the fraction of that level still remaining.
        step = "type"
        local ctype = nil
        local okt, tv = pcall(function() return k:call("get_CurrentType") end)
        if okt then
            if type(tv) == "number" then
                ctype = math.floor(tv)
            elseif tv ~= nil then
                ctype = tonumber(tostring(tv):match("%((%d+)%)"))
            end
        end
        step = "rate"
        local rate = nil
        local okr, rv = pcall(function() return k:call("get_CurrentRate") end)
        if okr and type(rv) == "number" then rate = rv end
        step = "done"
        return { vals = vals, cur = cur, type = ctype, rate = rate }
    end)
    if ok and res then return res end
    if not M.sharp_err then
        M.sharp_err = true
        log.info("[MHWorldBars] sharpness read failed at " .. step .. ": " .. tostring(res))
    end
    return nil
end

-- Critically damped follower. A per-tick ease restarts its curve on every stamina
-- tick (fast then crawling), which reads as stutter; a spring keeps its velocity
-- across ticks, so the bar glides continuously while still snapping on big hits.
-- dt must be the real overlay update interval: the d2d surface can update far faster
-- than 60 Hz, and a fixed dt makes the spring 3-4x too stiff (it then follows each
-- regen tick instantly, which is exactly the stepping we are trying to remove).
local function spring_step(cur, vel, target, k, dt)
    k  = k or 30.0
    dt = dt or (1.0 / 90.0)
    if dt > 0.05 then dt = 0.05 end
    local c = 2.0 * math.sqrt(k)
    local acc = (target - cur) * k - vel * c
    vel = vel + acc * dt
    cur = cur + vel * dt
    if math.abs(target - cur) < 0.0004 and math.abs(vel) < 0.002 then
        return target, 0.0
    end
    if cur < 0 then cur, vel = 0.0, 0.0 end
    if cur > 1 then cur, vel = 1.0, 0.0 end
    return cur, vel
end

-- rough overlay update rate (updates per second), refreshed every second
local function update_rate()
    local now = os.time()
    if M.t_sec == nil then
        M.t_sec, M.t_cnt = now, 0
    end
    M.t_cnt = M.t_cnt + 1
    local elapsed = now - M.t_sec
    if elapsed >= 1 then
        M.rate = M.t_cnt / elapsed
        M.t_sec, M.t_cnt = now, 0
    end
    return (M.rate and M.rate > 5) and (1.0 / M.rate) or (1.0 / 90.0)
end

local function draw_bracket(sw, rightx, midy, barh)
    if not bracket or (F.bracket_on or 1) == 0 then return end
    local bh = barh * (F.bracket_h or 1.8)
    local bw = bh * (10 / 17)
    d2d.image(bracket, rightx + (F.bracket_dx or 0.0035) * sw, midy - bh * 0.5, bw, bh)
end

-- translucent track across the gauge's full width (game: tex_eBace)
local function draw_track(x, midy, fullw, barh, pad)
    if not (bg_L and bg_C and bg_R) then return end
    local bh = barh * (F.base_h or 2.2)
    local by = midy - bh * 0.5
    local k = bh / SRC_BASE
    local kl = (64 / SRC_BASE) * bh
    local kr = (50 / SRC_BASE) * bh
    local ltip = 23 * k
    local rtail = 28 * k
    local left, right = x - pad, x + fullw + pad
    d2d.image(bg_L, left - ltip, by, kl, bh)
    local cx0 = left - ltip + kl - 2
    local cx1 = right - rtail + 4
    d2d.image(bg_C, cx0, by, math.max(1, cx1 - cx0), bh)
    d2d.image(bg_R, right - rtail, by, kr, bh)
end

-- 9-sliced fill: diamond cap at the left, centre stretched to the fill width, and the
-- tapered right cap at the FILL TIP (the point travels with the fill, as in World).
local function draw_fill(L, C, R, x, midy, fullw, barh, ratio, src_h, cap_h, capL_w, capR_w)
    local k  = barh / src_h
    local fw = fullw * ratio
    local kl = capL_w * k
    local kr = capR_w * k
    local chh = cap_h * k
    if fw > kl then
        local rw = math.min(kr, fw - kl)      -- cap shrinks with a very short fill
        local cw = fw - kl - rw
        -- centre stops 2 px under the cap: the cap keeps its pointed right edge, and
        -- since the cap sits at a fractional x its left column blends with the fill
        -- instead of the empty track (that blend was the visible seam line).
        if cw > 0 then
            d2d.image(C, x + kl - 1, midy - barh * 0.5, cw + 2, barh)
        end
        if R and rw > 0 then
            d2d.image(R, x + fw - rw, midy - barh * 0.5, rw, barh)
        end
    end
    d2d.image(L, x, midy - chh * 0.5, math.max(1, math.min(fw, kl)), chh)
end

-- (visibility of the overlay is driven by MHWorldUI's GUI hooks via _G.MHW_HUD_OFF)

d2d.register(
    function()
        pcall(function() d2d.detail.set_max_updaterate(240) end)
        hp_L = d2d.Image.new("mhw/gw3_hp_L.png")
        hp_C = d2d.Image.new("mhw/gw3_hp_C.png")
        hp_R = d2d.Image.new("mhw/gw3_hp_R.png")
        st_L = d2d.Image.new("mhw/gw3_st_L.png")
        st_C = d2d.Image.new("mhw/gw3_st_C.png")
        st_R = d2d.Image.new("mhw/gw3_st_R.png")
        bg_L = d2d.Image.new("mhw/gw_bg_L.png")
        bg_C = d2d.Image.new("mhw/gw_bg_C.png")
        bg_R = d2d.Image.new("mhw/gw_bg_R.png")
        sword  = d2d.Image.new("mhw/gw_sword.png")
        track  = d2d.Image.new("mhw/gw3_track.png")
        -- pre-composited halos, tinted per sharpness tier (d2d has no additive blend)
        glow_imgs = {
            d2d.Image.new("mhw/gw_glow_red.png"),    d2d.Image.new("mhw/gw_glow_orange.png"),
            d2d.Image.new("mhw/gw_glow_yellow.png"), d2d.Image.new("mhw/gw_glow_green.png"),
            d2d.Image.new("mhw/gw_glow_blue.png"),   d2d.Image.new("mhw/gw_glow_white.png"),
        }
        bracket = d2d.Image.new("mhw/gauge_bracket.png")
        bar_imgs = {
            d2d.Image.new("mhw/gw_bar_red.png"),    d2d.Image.new("mhw/gw_bar_orange.png"),
            d2d.Image.new("mhw/gw_bar_yellow.png"), d2d.Image.new("mhw/gw_bar_green.png"),
            d2d.Image.new("mhw/gw_bar_blue.png"),   d2d.Image.new("mhw/gw_bar_white.png"),
        }
    end,
    function()
        if not M.enabled then return end
        local ch = player_hud()
        if ch == nil then
            -- loading screen / no player HUD: clear the surface (d2d keeps the last frame)
            d2d.fill_rect(-20000, -20000, 2, 2, 0xFF000000)
            return
        end

        -- skip drawing while the game shows the map, a menu or a quest screen
        -- (flag maintained by MHWorldUI's GUI hooks - no engine calls on the render thread)
        if _G.MHW_HUD_OFF == true or (F.hud_off or 0) == 1 then
            -- d2d has no clear() and skips uploading when nothing is drawn, which leaves
            -- the previous frame on screen. Emit one off-screen quad so the surface is
            -- rebuilt empty while the map / a menu / a dialogue is up.
            d2d.fill_rect(-20000, -20000, 2, 2, 0xFF000000)
            return
        end

        local sw, sh = d2d.surface_size()

        M.tick = (M.tick or 0) + 1
        -- adaptive redraw rate: 120 Hz only while a gauge is animating (running / damage),
        -- 45 Hz when everything is settled - keeps d2d cost off the idle frame time
        if M.tick % 30 == 0 and M.moving ~= nil then
            pcall(function() d2d.detail.set_max_updaterate(M.moving and 120 or 45) end)
        end
        M.moving = (math.abs((M.st_target or 0) - (M.st_v or 0)) > 0.002)
                or (math.abs((M.hp_target or 0) - (M.hp_v or 0)) > 0.002)
        if M.tick % 30 == 0 then
            local okc, cfg = pcall(function() return json.load_file("mhw_bars.json") end)
            if okc and type(cfg) == "table" then
                for k, v in pairs(cfg) do
                    if type(v) == "number" and F[k] ~= v then F[k] = v end
                end
            end
        end
        if not M.logged then
            M.logged = true
            log.info(string.format("[MHWorldBars] drawing (surface=%dx%d)", sw, sh))
            local okr, rate = pcall(function() return d2d.detail.get_max_updaterate() end)
            if okr then log.info("[MHWorldBars] d2d max update rate = " .. tostring(rate)) end
        end

        -- Sample the game values every 4th frame and cache the manager objects: this
        -- was ~8 managed calls per frame (~1000/s at 120 Hz) for no visible benefit,
        -- the spring interpolates between samples anyway.
        if M.tick % 4 == 1 or M.hp_max == nil then
            local ok, hp, maxhp = pcall(function()
                if M.hm == nil or M.tick % 600 == 0 then
                    M.hm = ch:get_HunterHealth():get_HealthMgr()
                end
                return M.hm:get_Health(), M.hm:get_MaxHealth()
            end)
            if ok then
                M.hp_cur, M.hp_max = hp, maxhp
            end
            local ok2, st, maxst = pcall(function()
                if M.hs == nil or M.tick % 600 == 0 then
                    M.hs = ch:get_HunterStamina()
                end
                return M.hs:get_Stamina(), M.hs:get_MaxStamina()
            end)
            if ok2 then
                M.st_cur, M.st_max = st, maxst
            end
            M.st_ok = ok2
        end
        local hp, maxhp = M.hp_cur, M.hp_max
        local st, maxst = M.st_cur, M.st_max
        if maxhp == nil then return end

        local pad = F.pad or 1
        local xi = math.floor(F.x * sw + 0.5)
        local yi = math.floor(F.y * sh + 0.5)
        local gap = F.gap * sh

        ---------------------------------------------------------------- health
        local hph = F.hp_h * sh
        local hp_full = math.floor(F.hp_w * sw + 0.5)
        local ratio = 0
        if maxhp and maxhp > 0 then ratio = hp / maxhp end
        ratio = math.max(0, math.min(1, ratio))

        -- per-frame smoothing: the game reports health in coarse steps, so ease toward it
        local dt = update_rate()
        M.hp_target = ratio
        M.hp_v   = M.hp_v or ratio
        M.hp_vel = M.hp_vel or 0.0
        M.hp_v, M.hp_vel = spring_step(M.hp_v, M.hp_vel, ratio, F.k_hp or 55.0, dt)
        local draw_ratio = math.max(0, math.min(1, M.hp_v))

        draw_track(xi, yi + hph * 0.5, hp_full, hph, pad)
        if draw_ratio > 0 then
            if draw_ratio < (F.hp_low or 0.40) then
                -- low health: World switches its fill to energy_gaugeRED (CRISIS)
                d2d.fill_rect(xi + 1, yi, math.max(1, hp_full * draw_ratio - 2), hph, 0xFFE24A44)
            else
                draw_fill(hp_L, hp_C, hp_R, xi, yi + hph * 0.5, hp_full, hph, draw_ratio, 10, 18, 21, 8)
            end
            draw_bracket(sw, xi + hp_full, yi + hph * 0.5, hph)
        end

        --------------------------------------------------------------- stamina
        local sth = F.st_h * sh
        local sy = math.floor(yi + hph + gap + 0.5)
        local st_full = math.floor(F.st_w * sw + 0.5)

        if M.st_ok then
            local sratio = 0
            if maxst and maxst > 0 then sratio = st / maxst end
            sratio = math.max(0, math.min(1, sratio))
            M.st_target = sratio
            M.st_v   = M.st_v or sratio
            M.st_vel = M.st_vel or 0.0
            -- softer spring for stamina: regen arrives in coarse integer ticks, so a
            -- long settle time turns the steps into one continuous glide
            M.st_v, M.st_vel = spring_step(M.st_v, M.st_vel, sratio, F.k_st or 18.0, dt)
            local st_draw = math.max(0, math.min(1, M.st_v))
            -- the backing stays visible even at 0 stamina (sprint-until-empty bug)
            draw_track(xi, sy + sth * 0.5, st_full, sth, pad)
            if st_draw > 0 then
                draw_fill(st_L, st_C, st_R, xi, sy + sth * 0.5, st_full, sth, st_draw, 6, 18, 19, 8)
            end
            draw_bracket(sw, xi + st_full, sy + sth * 0.5, sth)
        end

        ------------------------------------------------------------- sharpness
        local swy = sy + sth + gap
        local gw  = (F.sw_hl + F.sw_bw) * sw
        -- .gui: tex_kBace is 113x33, so keep the sprite's own box aspect
        local gh  = gw * (33 / 113)
        local cy  = swy + gh * 0.5
        local sx0 = xi - F.sw_dx * sw

        seg_tick = seg_tick + 1
        if seg_tick % 60 == 0 or seg_rates == nil then seg_rates = read_sharpness() end

        local total, cur = 0, 0
        if seg_rates and seg_rates.vals then
            for i = 1, #seg_rates.vals do total = total + (seg_rates.vals[i] or 0) end
            cur = seg_rates.cur or 0
        end
        if total <= 0 then return end       -- bow / bowguns: no sharpness gauge

        d2d.image(sword, sx0, cy - gh * 0.5, gw, gh)

        -- The gauge is a stack of tiers (red -> white). CurrentType says which tier is
        -- active, CurrentRate how much of it is left, so every lower tier is full and
        -- the active one is partial. Bands vanish right-to-left as sharpness drops.
        local vals = seg_rates.vals
        local n    = #vals
        local t    = seg_rates.type          -- 0-based tier index from the game
        local rate = seg_rates.rate

        if t == nil or t < 0 or t >= n or (vals[t + 1] or 0) <= 0 then
            -- fallback: capacity = CurrentValue / CurrentRate, match it to a tier
            t = nil
            if rate and rate > 0 and cur > 0 then
                local cap = math.floor(cur / rate + 0.5)
                for i = n, 1, -1 do
                    if (vals[i] or 0) == cap then t = i - 1 break end
                end
            end
            if t == nil then t = 0 end
        end
        if rate == nil then
            local cap = vals[t + 1] or 0
            rate = (cap > 0) and math.max(0, math.min(1, cur / cap)) or 0
        end
        rate = math.max(0, math.min(1, rate))

        local filled = 0
        for i = 1, t do filled = filled + (vals[i] or 0) end   -- lower tiers are full
        filled = filled + (vals[t + 1] or 0) * rate            -- active tier is partial
        local len = math.max(0, math.min(1, filled / total))

        if not M.slogged or M.slast ~= t .. ":" .. math.floor(len * 100) then
            M.slogged = true
            M.slast = t .. ":" .. math.floor(len * 100)
            log.info(string.format("[MHWorldBars] sharp tier=%d rate=%.3f len=%.3f cur=%d filled=%d total=%d",
                t + 1, rate, len, cur, filled, total))
        end

        local bx   = sx0 + gw * (F.sw_bx or 0.30)
        local blen = gw * (F.sw_bw_frac or 0.66)
        local bh   = gh * (F.sw_bh or 0.97)
        local bw   = blen * len
        if bw > 1 then
            local gimg = glow_imgs and glow_imgs[t + 1]
            if gimg and (F.glow_on or 1) ~= 0 then
                -- halo sprite is 101x60 with a 14 px pad around the 73x32 blade box
                local gs = (bh / 32.0) * (F.glow_scale or 1.0)
                d2d.image(gimg,
                    bx - 18 * gs, cy - bh * 0.5 - 18 * gs,
                    bw + 36 * gs, 68 * gs)
            end
            -- World tints ONE tex_sharpGauge with the active tier colour; the sprite
            -- carries the pointed right tip, so the fill is a single stretched blade.
            local img = bar_imgs[t + 1]
            if img then
                d2d.image(img, bx, cy - bh * 0.5, bw, bh)
            end
        end
    end
)

return M
