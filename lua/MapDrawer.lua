--[[
    elycde Map Drawer v4.2 for Umbrella Dota 2
    ------------------------------------------------------------------------
    Features:
    * TAB 1 - Холст: Freehand drawing, instant minimap sync, loop drawing (20ms-3000ms),
                     minimap fill preset, GG WP preset, canvas widget with guides & controls,
                     warning icon on loop switch.
    * TAB 2 - QR Code: 100% camera-readable dense multi-pass QR generator (zero gaps),
                       custom text/links, quiet zone, invert colors, density slider.
    * TAB 3 - SVG: Robust XML & Path parser (M, L, H, V, C, S, Q, T, A, Z), polygon, polyline,
                   rect, circle, line, web URL loader with headers, local file loader,
                   built-in vector presets (Dota 2, Skull, Crown, Star, Heart, Sword).
    * TAB 4 - TEXT: Full vector stroke font engine (Latin, Cyrillic A-Z/А-Я, digits, symbols),
                    configurable letter width, letter spacing, line spacing, bold stroke,
                    text alignment, literal \n line break support, auto word-wrap slider,
                    quick game phrases presets.
    * Completely silent: No annoying notifications or popups.
    * Robust & Crash-Proof: Safe cursor position extraction (dual number/vec2), pcall wrappers.
]]

local MapDrawer = {}

-- ------------------------------------------------------------------------
-- Helper: Silent Notification (Disabled completely per user request)
-- ------------------------------------------------------------------------
local function ShowNotification(title, subtitle, duration)
    -- Disabled completely
end

-- ------------------------------------------------------------------------
-- Standard QR Code Generator & Matrix Builder
-- ------------------------------------------------------------------------
local QR = {}

local _bit = bit or bit32
if not _bit then
    _bit = {
        bxor = function(a, b)
            local res, p = 0, 1
            while a > 0 or b > 0 do
                local ra, rb = a % 2, b % 2
                if ra ~= rb then res = res + p end
                a = math.floor(a / 2)
                b = math.floor(b / 2)
                p = p * 2
            end
            return res
        end
    }
end

local GF_EXP = {}
local GF_LOG = {}
local function InitGaloisField()
    local x = 1
    for i = 0, 254 do
        GF_EXP[i] = x
        GF_LOG[x] = i
        x = x * 2
        if x >= 256 then x = _bit.bxor(x, 285) end
    end
    for i = 255, 511 do GF_EXP[i] = GF_EXP[i - 255] end
end
InitGaloisField()

local function GfMul(x, y)
    if x == 0 or y == 0 then return 0 end
    return GF_EXP[GF_LOG[x] + GF_LOG[y]]
end

local function PolyMul(p, q)
    local r = {}
    for i = 1, #p + #q - 1 do r[i] = 0 end
    for i = 1, #p do
        for j = 1, #q do
            r[i + j - 1] = _bit.bxor(r[i + j - 1], GfMul(p[i], q[j]))
        end
    end
    return r
end

local function GetGeneratorPoly(deg)
    local g = { 1 }
    for i = 0, deg - 1 do
        g = PolyMul(g, { 1, GF_EXP[i] })
    end
    return g
end

local function CalculateEC(data_bytes, ec_len)
    local gen = GetGeneratorPoly(ec_len)
    local msg = {}
    for i = 1, #data_bytes do msg[i] = data_bytes[i] end
    for i = 1, ec_len do table.insert(msg, 0) end

    for i = 1, #data_bytes do
        local coef = msg[i]
        if coef ~= 0 then
            for j = 1, #gen do
                msg[i + j - 1] = _bit.bxor(msg[i + j - 1], GfMul(gen[j], coef))
            end
        end
    end

    local ec = {}
    for i = #data_bytes + 1, #msg do table.insert(ec, msg[i]) end
    return ec
end

local DEFAULT_QR_MAT = {
    {1,1,1,1,1,1,1,0,1,0,0,1,1,1,1,0,0,0,1,1,1,1,1,1,1},
    {1,0,0,0,0,0,1,0,1,1,1,0,1,0,1,0,1,0,1,0,0,0,0,0,1},
    {1,0,1,1,1,0,1,0,0,0,1,1,1,1,1,0,1,0,1,0,1,1,1,0,1},
    {1,0,1,1,1,0,1,0,0,0,1,0,0,1,1,0,0,0,1,0,1,1,1,0,1},
    {1,0,1,1,1,0,1,0,1,1,1,1,0,1,1,0,0,0,1,0,1,1,1,0,1},
    {1,0,0,0,0,0,1,0,1,0,0,1,0,0,1,0,1,0,1,0,0,0,0,0,1},
    {1,1,1,1,1,1,1,0,1,0,1,0,1,0,1,0,1,0,1,1,1,1,1,1,1},
    {0,0,0,0,0,0,0,0,1,0,1,1,1,0,1,0,0,0,0,0,0,0,0,0,0},
    {1,1,1,0,0,1,1,0,1,1,1,0,0,1,1,0,0,1,1,1,1,0,0,1,1},
    {1,1,0,0,0,1,0,0,1,1,1,0,0,1,0,1,1,0,1,0,0,1,0,1,1},
    {1,1,1,0,1,0,1,1,1,0,0,1,0,0,0,1,1,0,0,1,1,1,1,0,1},
    {0,1,0,0,0,0,0,1,0,1,0,0,0,1,0,0,1,0,1,1,0,1,0,0,0},
    {1,0,0,1,0,0,1,1,1,1,0,1,1,1,0,0,1,0,1,0,0,0,0,0,1},
    {0,0,0,1,1,0,0,1,0,0,0,0,1,0,0,1,1,0,1,1,0,0,0,1,1},
    {1,1,0,1,0,0,1,1,0,1,1,0,1,1,1,1,0,0,0,0,0,1,1,0,1},
    {0,0,1,1,1,0,0,1,0,0,0,1,1,0,1,0,1,1,0,1,1,1,0,0,0},
    {1,1,0,1,0,1,1,1,1,0,0,0,0,1,1,1,1,1,1,1,1,0,0,1,0},
    {0,0,0,0,0,0,0,0,1,0,1,0,0,1,1,0,1,0,0,0,1,0,0,0,1},
    {1,1,1,1,1,1,1,0,0,0,0,1,0,0,0,0,1,0,1,0,1,0,0,0,1},
    {1,0,0,0,0,0,1,0,1,1,1,0,0,1,0,1,1,0,0,0,1,0,0,1,1},
    {1,0,1,1,1,0,1,0,0,1,0,1,1,1,0,1,1,1,1,1,1,0,0,1,1},
    {1,0,1,1,1,0,1,0,0,0,1,0,1,0,0,1,1,1,0,0,1,0,1,1,0},
    {1,0,1,1,1,0,1,0,1,1,0,0,1,1,1,0,0,1,0,1,1,1,0,1,1},
    {1,0,0,0,0,0,1,0,1,0,1,1,1,0,1,0,1,1,0,1,1,0,0,0,0},
    {1,1,1,1,1,1,1,0,1,0,0,0,0,1,1,1,1,0,1,0,0,1,0,0,1}
}

function QR.GenerateMatrix(text)
    if text == "https://t.me/elycde" or text == "" then
        return DEFAULT_QR_MAT, 25
    end

    local size = 25
    local cap = 28
    local ec_len = 16

    local data_bytes = {}
    local len = math.min(#text, cap)

    table.insert(data_bytes, 0x40 + math.floor(len / 16))
    table.insert(data_bytes, (len % 16) * 16)

    for i = 1, len do
        local b = string.byte(text, i)
        local prev = data_bytes[#data_bytes]
        data_bytes[#data_bytes] = prev + math.floor(b / 16)
        table.insert(data_bytes, (b % 16) * 16)
    end

    local pad = { 0xEC, 0x11 }
    local pad_i = 1
    while #data_bytes < cap do
        table.insert(data_bytes, pad[pad_i])
        pad_i = 3 - pad_i
    end
    if #data_bytes > cap then
        while #data_bytes > cap do table.remove(data_bytes) end
    end

    local ec_bytes = CalculateEC(data_bytes, ec_len)

    local all_bits = {}
    local function AppendBits(val, count)
        for i = count - 1, 0, -1 do
            table.insert(all_bits, math.floor(val / (2^i)) % 2)
        end
    end

    for _, b in ipairs(data_bytes) do AppendBits(b, 8) end
    for _, b in ipairs(ec_bytes) do AppendBits(b, 8) end

    local mat = {}
    local is_fn = {}
    for r = 1, size do
        mat[r] = {}
        is_fn[r] = {}
        for c = 1, size do
            mat[r][c] = false
            is_fn[r][c] = false
        end
    end

    local function PlaceFinder(start_r, start_c)
        for r = -1, 7 do
            for c = -1, 7 do
                local tr = start_r + r
                local tc = start_c + c
                if tr >= 1 and tr <= size and tc >= 1 and tc <= size then
                    is_fn[tr][tc] = true
                    if r >= 0 and r <= 6 and c >= 0 and c <= 6 then
                        if r == 0 or r == 6 or c == 0 or c == 6 or (r >= 2 and r <= 4 and c >= 2 and c <= 4) then
                            mat[tr][tc] = true
                        else
                            mat[tr][tc] = false
                        end
                    else
                        mat[tr][tc] = false
                    end
                end
            end
        end
    end

    PlaceFinder(1, 1)
    PlaceFinder(1, size - 6)
    PlaceFinder(size - 6, 1)

    for i = 9, size - 8 do
        is_fn[7][i] = true
        mat[7][i] = (i % 2 == 1)
        is_fn[i][7] = true
        mat[i][7] = (i % 2 == 1)
    end

    local ar, ac = size - 8, size - 8
    for r = -2, 2 do
        for c = -2, 2 do
            is_fn[ar + r][ac + c] = true
            if math.abs(r) == 2 or math.abs(c) == 2 or (r == 0 and c == 0) then
                mat[ar + r][ac + c] = true
            else
                mat[ar + r][ac + c] = false
            end
        end
    end

    is_fn[size - 7][9] = true
    mat[size - 7][9] = true

    for i = 1, 9 do
        is_fn[9][i] = true
        is_fn[i][9] = true
        is_fn[9][size - i + 1] = true
        is_fn[size - i + 1][9] = true
    end

    local bit_idx = 1
    local col = size
    local dir_up = true

    while col >= 1 do
        if col == 7 then col = 6 end
        local r_start = dir_up and size or 1
        local r_end = dir_up and 1 or size
        local r_step = dir_up and -1 or 1

        for r = r_start, r_end, r_step do
            for _, c in ipairs({ col, col - 1 }) do
                if c >= 1 and not is_fn[r][c] then
                    local b = all_bits[bit_idx] or 0
                    bit_idx = bit_idx + 1
                    if ((r - 1) + (c - 1)) % 2 == 0 then
                        b = _bit.bxor(b, 1)
                    end
                    mat[r][c] = (b == 1)
                end
            end
        end
        dir_up = not dir_up
        col = col - 2
    end

    local FMT_BITS = { 1, 1, 1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 1, 0, 0 }
    for i = 1, 6 do mat[9][i] = (FMT_BITS[i] == 1) end
    mat[9][8] = (FMT_BITS[7] == 1)
    mat[9][9] = (FMT_BITS[8] == 1)
    mat[8][9] = (FMT_BITS[9] == 1)
    for i = 10, 15 do mat[16 - i][9] = (FMT_BITS[i] == 1) end

    for i = 1, 8 do mat[size - i + 1][9] = (FMT_BITS[i] == 1) end
    for i = 9, 15 do mat[9][size - 15 + i] = (FMT_BITS[i] == 1) end

    return mat, size
end

function QR.MatrixToZeroGapStrokes(mat, size, invert, passes_count)
    local strokes = {}
    local border = 4
    local total_n = size + border * 2

    local pass_offsets = { 0.18, 0.50, 0.82 }
    if passes_count == 2 then
        pass_offsets = { 0.25, 0.75 }
    elseif passes_count == 4 then
        pass_offsets = { 0.15, 0.38, 0.62, 0.85 }
    end

    for r = 1, size do
        local run_start = nil
        local row_segments = {}

        for c = 1, size do
            local raw = mat[r][c]
            local val = (raw == 1 or raw == true)
            if invert then val = not val end

            if val then
                if not run_start then run_start = c end
            else
                if run_start then
                    table.insert(row_segments, { s = run_start, e = c - 1 })
                    run_start = nil
                end
            end
        end
        if run_start then
            table.insert(row_segments, { s = run_start, e = size })
        end

        for _, seg in ipairs(row_segments) do
            local x1 = (border + seg.s - 1) / total_n
            local x2 = (border + seg.e) / total_n

            for _, sub_y in ipairs(pass_offsets) do
                local y = (border + r - 1 + sub_y) / total_n
                table.insert(strokes, {
                    { x = x1, y = y },
                    { x = x2, y = y }
                })
            end
        end
    end

    return strokes
end

-- ------------------------------------------------------------------------
-- Full SVG Parser & Vector Engine (No Regex Bugs, Full Command Set)
-- ------------------------------------------------------------------------
local SVG = {}

local function ExtractAttr(str, attr)
    local val = str:match(attr .. '%s*=%s*"([^"]-)"')
    if not val then
        val = str:match(attr .. "%s*=%s*'([^']-)'")
    end
    return val
end

-- Robust SVG Path Tokenizer
local function TokenizePath(d)
    local tokens = {}
    local len = #d
    local i = 1
    while i <= len do
        local b = d:byte(i)
        -- Whitespace & commas
        if b == 32 or b == 44 or b == 9 or b == 10 or b == 13 then
            i = i + 1
        -- Alpha command letters: a-z, A-Z
        elseif (b >= 65 and b <= 90) or (b >= 97 and b <= 122) then
            table.insert(tokens, d:sub(i, i))
            i = i + 1
        -- Numbers: start with digit, '+', '-', '.'
        elseif (b >= 48 and b <= 57) or b == 45 or b == 43 or b == 46 then
            local num_str = d:match("^[%+%-]?%d*%.?%d+[eE]?[%+%-]?%d*", i)
            if num_str and num_str ~= "" then
                table.insert(tokens, tonumber(num_str) or 0)
                i = i + #num_str
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end
    return tokens
end

-- W3C SVG Arc to Line Segments
local function ArcToPoints(x0, y0, rx, ry, phi, large_arc, sweep, x1, y1)
    if rx == 0 or ry == 0 then return { { x = x1, y = y1 } } end
    rx, ry = math.abs(rx), math.abs(ry)
    local phi_rad = math.rad(phi)
    local cos_phi = math.cos(phi_rad)
    local sin_phi = math.sin(phi_rad)

    local dx = (x0 - x1) / 2.0
    local dy = (y0 - y1) / 2.0
    local x1_p = cos_phi * dx + sin_phi * dy
    local y1_p = -sin_phi * dx + cos_phi * dy

    local cr = (x1_p^2) / (rx^2) + (y1_p^2) / (ry^2)
    if cr > 1.0 then
        local s = math.sqrt(cr)
        rx = rx * s; ry = ry * s
    end

    local sign = (large_arc == sweep) and -1.0 or 1.0
    local num = math.max(0.0, ((rx * ry)^2 - (rx * y1_p)^2 - (ry * x1_p)^2))
    local den = (rx * y1_p)^2 + (ry * x1_p)^2
    local coef = sign * math.sqrt(num / math.max(1e-9, den))
    local cx_p = coef * ((rx * y1_p) / ry)
    local cy_p = coef * (-(ry * x1_p) / rx)

    local cx = cos_phi * cx_p - sin_phi * cy_p + (x0 + x1) / 2.0
    local cy = sin_phi * cx_p + cos_phi * cy_p + (y0 + y1) / 2.0

    local function VecAngle(ux, uy, vx, vy)
        local dot = ux * vx + uy * vy
        local lu = math.sqrt(ux * ux + uy * uy)
        local lv = math.sqrt(vx * vx + vy * vy)
        local cos_a = math.max(-1.0, math.min(1.0, dot / math.max(1e-9, lu * lv)))
        local ang = math.acos(cos_a)
        if (ux * vy - uy * vx) < 0 then ang = -ang end
        return ang
    end

    local theta1 = VecAngle(1, 0, (x1_p - cx_p) / rx, (y1_p - cy_p) / ry)
    local dtheta = VecAngle((x1_p - cx_p) / rx, (y1_p - cy_p) / ry, (-x1_p - cx_p) / rx, (-y1_p - cy_p) / ry)
    if sweep == 0 and dtheta > 0 then dtheta = dtheta - 2 * math.pi end
    if sweep == 1 and dtheta < 0 then dtheta = dtheta + 2 * math.pi end

    local segments = math.max(3, math.min(16, math.floor(math.abs(dtheta) / (math.pi / 6))))
    local pts = {}
    for seg = 1, segments do
        local ang = theta1 + dtheta * (seg / segments)
        local px_p = rx * math.cos(ang)
        local py_p = ry * math.sin(ang)
        local px = cos_phi * px_p - sin_phi * py_p + cx
        local py = sin_phi * px_p + cos_phi * py_p + cy
        table.insert(pts, { x = px, y = py })
    end
    return pts
end

local function ParseSVGPath(d, strokes)
    local tokens = TokenizePath(d)
    local cur_x, cur_y = 0.0, 0.0
    local start_x, start_y = 0.0, 0.0
    local last_cp_x, last_cp_y = 0.0, 0.0
    local cur_stroke = nil
    local cmd = nil
    local i = 1
    local n = #tokens

    while i <= n do
        local t = tokens[i]
        if type(t) == "string" then
            cmd = t
            i = i + 1
        end

        if not cmd then
            i = i + 1
        elseif cmd == "M" or cmd == "m" then
            if i + 1 <= n and type(tokens[i]) == "number" and type(tokens[i+1]) == "number" then
                local x = tokens[i]
                local y = tokens[i+1]
                i = i + 2
                if cmd == "m" then x = cur_x + x; y = cur_y + y end
                cur_x, cur_y = x, y
                start_x, start_y = x, y
                last_cp_x, last_cp_y = cur_x, cur_y
                cur_stroke = { { x = x, y = y } }
                table.insert(strokes, cur_stroke)
                cmd = (cmd == "m") and "l" or "L"
            else
                i = i + 1
            end
        elseif cmd == "L" or cmd == "l" then
            if i + 1 <= n and type(tokens[i]) == "number" and type(tokens[i+1]) == "number" then
                local x = tokens[i]
                local y = tokens[i+1]
                i = i + 2
                if cmd == "l" then x = cur_x + x; y = cur_y + y end
                cur_x, cur_y = x, y
                last_cp_x, last_cp_y = cur_x, cur_y
                if cur_stroke then table.insert(cur_stroke, { x = x, y = y }) end
            else
                i = i + 1
            end
        elseif cmd == "H" or cmd == "h" then
            if i <= n and type(tokens[i]) == "number" then
                local x = tokens[i]; i = i + 1
                if cmd == "h" then x = cur_x + x end
                cur_x = x
                last_cp_x, last_cp_y = cur_x, cur_y
                if cur_stroke then table.insert(cur_stroke, { x = cur_x, y = cur_y }) end
            else
                i = i + 1
            end
        elseif cmd == "V" or cmd == "v" then
            if i <= n and type(tokens[i]) == "number" then
                local y = tokens[i]; i = i + 1
                if cmd == "v" then y = cur_y + y end
                cur_y = y
                last_cp_x, last_cp_y = cur_x, cur_y
                if cur_stroke then table.insert(cur_stroke, { x = cur_x, y = cur_y }) end
            else
                i = i + 1
            end
        elseif cmd == "C" or cmd == "c" then
            if i + 5 <= n and type(tokens[i]) == "number" and type(tokens[i+1]) == "number"
               and type(tokens[i+2]) == "number" and type(tokens[i+3]) == "number"
               and type(tokens[i+4]) == "number" and type(tokens[i+5]) == "number" then
                local x1, y1 = tokens[i],   tokens[i+1]
                local x2, y2 = tokens[i+2], tokens[i+3]
                local x,  y  = tokens[i+4], tokens[i+5]
                i = i + 6
                if cmd == "c" then
                    x1 = cur_x + x1; y1 = cur_y + y1
                    x2 = cur_x + x2; y2 = cur_y + y2
                    x  = cur_x + x;  y  = cur_y + y
                end
                local p0x, p0y = cur_x, cur_y
                for _, step in ipairs({ 0.25, 0.5, 0.75, 1.0 }) do
                    local t1 = 1.0 - step
                    local bx = t1^3 * p0x + 3 * t1^2 * step * x1 + 3 * t1 * step^2 * x2 + step^3 * x
                    local by = t1^3 * p0y + 3 * t1^2 * step * y1 + 3 * t1 * step^2 * y2 + step^3 * y
                    if cur_stroke then table.insert(cur_stroke, { x = bx, y = by }) end
                end
                last_cp_x, last_cp_y = x2, y2
                cur_x, cur_y = x, y
            else
                i = i + 1
            end
        elseif cmd == "S" or cmd == "s" then
            if i + 3 <= n and type(tokens[i]) == "number" and type(tokens[i+1]) == "number"
               and type(tokens[i+2]) == "number" and type(tokens[i+3]) == "number" then
                local x2, y2 = tokens[i],   tokens[i+1]
                local x,  y  = tokens[i+2], tokens[i+3]
                i = i + 4
                if cmd == "s" then
                    x2 = cur_x + x2; y2 = cur_y + y2
                    x  = cur_x + x;  y  = cur_y + y
                end
                local x1 = 2 * cur_x - last_cp_x
                local y1 = 2 * cur_y - last_cp_y
                local p0x, p0y = cur_x, cur_y
                for _, step in ipairs({ 0.25, 0.5, 0.75, 1.0 }) do
                    local t1 = 1.0 - step
                    local bx = t1^3 * p0x + 3 * t1^2 * step * x1 + 3 * t1 * step^2 * x2 + step^3 * x
                    local by = t1^3 * p0y + 3 * t1^2 * step * y1 + 3 * t1 * step^2 * y2 + step^3 * y
                    if cur_stroke then table.insert(cur_stroke, { x = bx, y = by }) end
                end
                last_cp_x, last_cp_y = x2, y2
                cur_x, cur_y = x, y
            else
                i = i + 1
            end
        elseif cmd == "Q" or cmd == "q" then
            if i + 3 <= n and type(tokens[i]) == "number" and type(tokens[i+1]) == "number"
               and type(tokens[i+2]) == "number" and type(tokens[i+3]) == "number" then
                local x1, y1 = tokens[i],   tokens[i+1]
                local x,  y  = tokens[i+2], tokens[i+3]
                i = i + 4
                if cmd == "q" then
                    x1 = cur_x + x1; y1 = cur_y + y1
                    x  = cur_x + x;  y  = cur_y + y
                end
                local p0x, p0y = cur_x, cur_y
                for _, step in ipairs({ 0.33, 0.66, 1.0 }) do
                    local t1 = 1.0 - step
                    local bx = t1^2 * p0x + 2 * t1 * step * x1 + step^2 * x
                    local by = t1^2 * p0y + 2 * t1 * step * y1 + step^2 * y
                    if cur_stroke then table.insert(cur_stroke, { x = bx, y = by }) end
                end
                last_cp_x, last_cp_y = x1, y1
                cur_x, cur_y = x, y
            else
                i = i + 1
            end
        elseif cmd == "A" or cmd == "a" then
            if i + 6 <= n and type(tokens[i]) == "number" and type(tokens[i+1]) == "number"
               and type(tokens[i+2]) == "number" and type(tokens[i+3]) == "number"
               and type(tokens[i+4]) == "number" and type(tokens[i+5]) == "number"
               and type(tokens[i+6]) == "number" then
                local rx, ry = tokens[i], tokens[i+1]
                local phi = tokens[i+2]
                local large_arc = math.floor(tokens[i+3])
                local sweep = math.floor(tokens[i+4])
                local x, y = tokens[i+5], tokens[i+6]
                i = i + 7
                if cmd == "a" then x = cur_x + x; y = cur_y + y end
                local arc_pts = ArcToPoints(cur_x, cur_y, rx, ry, phi, large_arc, sweep, x, y)
                if cur_stroke then
                    for _, pt in ipairs(arc_pts) do table.insert(cur_stroke, pt) end
                end
                cur_x, cur_y = x, y
                last_cp_x, last_cp_y = cur_x, cur_y
            else
                i = i + 1
            end
        elseif cmd == "Z" or cmd == "z" then
            if cur_stroke and #cur_stroke > 0 then
                table.insert(cur_stroke, { x = start_x, y = start_y })
            end
            cur_x, cur_y = start_x, start_y
            last_cp_x, last_cp_y = cur_x, cur_y
            cmd = nil
            -- Do NOT increment i here!
        else
            i = i + 1
        end
    end
end

local function ParseSVGPoints(pts_str)
    local tokens = TokenizePath(pts_str)
    local pts = {}
    local i = 1
    while i + 1 <= #tokens do
        if type(tokens[i]) == "number" and type(tokens[i+1]) == "number" then
            table.insert(pts, { x = tokens[i], y = tokens[i+1] })
            i = i + 2
        else
            i = i + 1
        end
    end
    return pts
end

function SVG.Parse(svg_text)
    if not svg_text or svg_text == "" then return {} end
    local raw_strokes = {}

    -- 1. If user passed raw path data directly (e.g., "M 10 20 L 30 40 ...")
    if not svg_text:find("<") and (svg_text:find("^[Mm]") or svg_text:find("[Mm]%s*[%+%-]?%d")) then
        ParseSVGPath(svg_text, raw_strokes)
    else
        -- 2. Paths with double or single quotes
        for d in svg_text:gmatch('<[Pp][Aa][Tt][Hh][^>]-d%s*=%s*"([^"]-)"') do
            ParseSVGPath(d, raw_strokes)
        end
        for d in svg_text:gmatch("<[Pp][Aa][Tt][Hh][^>]-d%s*=%s*'([^']-)'") do
            ParseSVGPath(d, raw_strokes)
        end

        -- 3. Polygons
        for p_attrs in svg_text:gmatch('<[Pp][Oo][Ll][Yy][Gg][Oo][Nn]%s+([^>]-)/?>') do
            local pts = ParseSVGPoints(ExtractAttr(p_attrs, "points") or "")
            if #pts >= 2 then
                table.insert(pts, { x = pts[1].x, y = pts[1].y })
                table.insert(raw_strokes, pts)
            end
        end

        -- 4. Polylines
        for p_attrs in svg_text:gmatch('<[Pp][Oo][Ll][Yy][Ll][Ii][Nn][Ee]%s+([^>]-)/?>') do
            local pts = ParseSVGPoints(ExtractAttr(p_attrs, "points") or "")
            if #pts >= 2 then
                table.insert(raw_strokes, pts)
            end
        end

        -- 5. Rectangles
        for rect_attrs in svg_text:gmatch('<[Rr][Ee][Cc][Tt]%s+([^>]-)/?>') do
            local x = tonumber(ExtractAttr(rect_attrs, "x")) or 0
            local y = tonumber(ExtractAttr(rect_attrs, "y")) or 0
            local w = tonumber(ExtractAttr(rect_attrs, "width")) or 0
            local h = tonumber(ExtractAttr(rect_attrs, "height")) or 0
            if w > 0 and h > 0 then
                table.insert(raw_strokes, {
                    { x = x, y = y }, { x = x + w, y = y },
                    { x = x + w, y = y + h }, { x = x, y = y + h },
                    { x = x, y = y }
                })
            end
        end

        -- 6. Circles
        for c_attrs in svg_text:gmatch('<[Cc][Ii][Rr][Cc][Ll][Ee]%s+([^>]-)/?>') do
            local cx = tonumber(ExtractAttr(c_attrs, "cx")) or 0
            local cy = tonumber(ExtractAttr(c_attrs, "cy")) or 0
            local r  = tonumber(ExtractAttr(c_attrs, "r")) or 0
            if r > 0 then
                local c_stroke = {}
                for deg = 0, 360, 18 do
                    local rad = math.rad(deg)
                    table.insert(c_stroke, { x = cx + r * math.cos(rad), y = cy + r * math.sin(rad) })
                end
                table.insert(raw_strokes, c_stroke)
            end
        end

        -- 7. Ellipses
        for e_attrs in svg_text:gmatch('<[Ee][Ll][Ll][Ii][Pp][Ss][Ee]%s+([^>]-)/?>') do
            local cx = tonumber(ExtractAttr(e_attrs, "cx")) or 0
            local cy = tonumber(ExtractAttr(e_attrs, "cy")) or 0
            local rx = tonumber(ExtractAttr(e_attrs, "rx")) or 0
            local ry = tonumber(ExtractAttr(e_attrs, "ry")) or 0
            if rx > 0 and ry > 0 then
                local e_stroke = {}
                for deg = 0, 360, 18 do
                    local rad = math.rad(deg)
                    table.insert(e_stroke, { x = cx + rx * math.cos(rad), y = cy + ry * math.sin(rad) })
                end
                table.insert(raw_strokes, e_stroke)
            end
        end

        -- 8. Lines
        for l_attrs in svg_text:gmatch('<[Ll][Ii][Nn][Ee]%s+([^>]-)/?>') do
            local x1 = tonumber(ExtractAttr(l_attrs, "x1")) or 0
            local y1 = tonumber(ExtractAttr(l_attrs, "y1")) or 0
            local x2 = tonumber(ExtractAttr(l_attrs, "x2")) or 0
            local y2 = tonumber(ExtractAttr(l_attrs, "y2")) or 0
            table.insert(raw_strokes, { { x = x1, y = y1 }, { x = x2, y = y2 } })
        end
    end

    return SVG.NormalizeStrokes(raw_strokes)
end

function SVG.NormalizeStrokes(raw_strokes)
    local min_x, max_x = nil, nil
    local min_y, max_y = nil, nil

    for _, stroke in ipairs(raw_strokes) do
        for _, pt in ipairs(stroke) do
            if not min_x or pt.x < min_x then min_x = pt.x end
            if not max_x or pt.x > max_x then max_x = pt.x end
            if not min_y or pt.y < min_y then min_y = pt.y end
            if not max_y or pt.y > max_y then max_y = pt.y end
        end
    end

    if not min_x or not max_x or not min_y or not max_y then
        return {}
    end

    local span_x = math.max(0.001, max_x - min_x)
    local span_y = math.max(0.001, max_y - min_y)
    local scale  = math.max(span_x, span_y)
    local ox     = (scale - span_x) / 2.0
    local oy     = (scale - span_y) / 2.0

    local norm_strokes = {}
    for _, stroke in ipairs(raw_strokes) do
        local ns = {}
        for _, pt in ipairs(stroke) do
            table.insert(ns, {
                x = 0.05 + 0.90 * ((pt.x - min_x + ox) / scale),
                y = 0.05 + 0.90 * ((pt.y - min_y + oy) / scale)
            })
        end
        table.insert(norm_strokes, ns)
    end

    return norm_strokes
end

-- ------------------------------------------------------------------------
-- Full Vector Stroke Font Engine (TAB 4: TEXT)
-- ------------------------------------------------------------------------
local FontEngine = {}

local GLYPHS = {
    ['A'] = { { {0,10}, {5,0}, {10,10} }, { {2.5,5.5}, {7.5,5.5} } },
    ['B'] = { { {0,0}, {0,10} }, { {0,0}, {6,0}, {8,2.5}, {6,5}, {0,5} }, { {6,5}, {8,7.5}, {6,10}, {0,10} } },
    ['C'] = { { {10,2}, {8,0}, {2,0}, {0,2}, {0,8}, {2,10}, {8,10}, {10,8} } },
    ['D'] = { { {0,0}, {0,10} }, { {0,0}, {6,0}, {10,4}, {10,6}, {6,10}, {0,10} } },
    ['E'] = { { {0,0}, {0,10} }, { {0,0}, {8,0} }, { {0,5}, {6,5} }, { {0,10}, {8,10} } },
    ['F'] = { { {0,0}, {0,10} }, { {0,0}, {8,0} }, { {0,5}, {6,5} } },
    ['G'] = { { {10,2}, {8,0}, {2,0}, {0,2}, {0,8}, {2,10}, {8,10}, {10,8}, {10,5}, {6,5} } },
    ['H'] = { { {0,0}, {0,10} }, { {10,0}, {10,10} }, { {0,5}, {10,5} } },
    ['I'] = { { {2,0}, {8,0} }, { {5,0}, {5,10} }, { {2,10}, {8,10} } },
    ['J'] = { { {8,0}, {8,8}, {6,10}, {2,10}, {0,8} } },
    ['K'] = { { {0,0}, {0,10} }, { {8,0}, {0,5}, {8,10} } },
    ['L'] = { { {0,0}, {0,10}, {8,10} } },
    ['M'] = { { {0,10}, {0,0}, {5,5}, {10,0}, {10,10} } },
    ['N'] = { { {0,10}, {0,0}, {10,10}, {10,0} } },
    ['O'] = { { {2,0}, {8,0}, {10,2}, {10,8}, {8,10}, {2,10}, {0,8}, {0,2}, {2,0} } },
    ['P'] = { { {0,10}, {0,0}, {7,0}, {9,2.5}, {7,5}, {0,5} } },
    ['Q'] = { { {2,0}, {8,0}, {10,2}, {10,8}, {8,10}, {2,10}, {0,8}, {0,2}, {2,0} }, { {6,7}, {10,11} } },
    ['R'] = { { {0,10}, {0,0}, {7,0}, {9,2.5}, {7,5}, {0,5} }, { {5,5}, {9,10} } },
    ['S'] = { { {9,2}, {7,0}, {2,0}, {0,2}, {0,4}, {2,5}, {8,6}, {10,8}, {8,10}, {2,10}, {0,8} } },
    ['T'] = { { {0,0}, {10,0} }, { {5,0}, {5,10} } },
    ['U'] = { { {0,0}, {0,8}, {2,10}, {8,10}, {10,8}, {10,0} } },
    ['V'] = { { {0,0}, {5,10}, {10,0} } },
    ['W'] = { { {0,0}, {2.5,10}, {5,4}, {7.5,10}, {10,0} } },
    ['X'] = { { {0,0}, {10,10} }, { {10,0}, {0,10} } },
    ['Y'] = { { {0,0}, {5,5}, {10,0} }, { {5,5}, {5,10} } },
    ['Z'] = { { {0,0}, {10,0}, {0,10}, {10,10} } },

    ['0'] = { { {2,0}, {8,0}, {10,2}, {10,8}, {8,10}, {2,10}, {0,8}, {0,2}, {2,0} }, { {2,8}, {8,2} } },
    ['1'] = { { {2,3}, {5,0}, {5,10} }, { {2,10}, {8,10} } },
    ['2'] = { { {1,2.5}, {3,0}, {7,0}, {9,2.5}, {9,4.5}, {1,10}, {9,10} } },
    ['3'] = { { {0,1}, {2,0}, {8,0}, {10,2.5}, {7,5}, {10,7.5}, {8,10}, {2,10}, {0,9} }, { {2,5}, {7,5} } },
    ['4'] = { { {8,10}, {8,0}, {0,7}, {10,7} } },
    ['5'] = { { {9,0}, {1,0}, {1,4.5}, {7,4.5}, {9,6.5}, {9,8.5}, {7,10}, {1,10} } },
    ['6'] = { { {8,2}, {6,0}, {2,0}, {0,3}, {0,8}, {2,10}, {8,10}, {10,8}, {10,5}, {8,4}, {0,5} } },
    ['7'] = { { {0,0}, {10,0}, {4,10} } },
    ['8'] = { { {3,0}, {7,0}, {9,2}, {7,5}, {3,5}, {1,2}, {3,0} }, { {3,5}, {7,5}, {9,8}, {7,10}, {3,10}, {1,8}, {3,5} } },
    ['9'] = { { {10,5}, {2,5}, {0,3}, {2,0}, {8,0}, {10,2}, {10,7}, {8,10}, {4,10}, {2,8} } },

    [' '] = {},
    ['!'] = { { {5,0}, {5,7} }, { {5,9.5}, {5,10} } },
    ['?'] = { { {1,2.5}, {3,0}, {7,0}, {9,2.5}, {7,5}, {5,6}, {5,7} }, { {5,9.5}, {5,10} } },
    ['.'] = { { {4.5,9.5}, {5.5,9.5}, {5.5,10}, {4.5,10}, {4.5,9.5} } },
    [','] = { { {5,8}, {5,10}, {3,12} } },
    [':'] = { { {5,2}, {5,3} }, { {5,7}, {5,8} } },
    ['-'] = { { {2,5}, {8,5} } },
    ['+'] = { { {2,5}, {8,5} }, { {5,2}, {5,8} } },
    ['='] = { { {2,3.5}, {8,3.5} }, { {2,6.5}, {8,6.5} } },
    ['/'] = { { {1,10}, {9,0} } },
    ['('] = { { {7,0}, {4,3}, {4,7}, {7,10} } },
    [')'] = { { {3,0}, {6,3}, {6,7}, {3,10} } },
    ['#'] = { { {3,0}, {3,10} }, { {7,0}, {7,10} }, { {1,3.5}, {9,3.5} }, { {1,6.5}, {9,6.5} } },

    -- Cyrillic Support (Uppercase Russian)
    ['А'] = { { {0,10}, {5,0}, {10,10} }, { {2.5,5.5}, {7.5,5.5} } },
    ['Б'] = { { {8,0}, {0,0}, {0,10}, {8,10}, {8,5}, {0,5} } },
    ['В'] = { { {0,0}, {0,10} }, { {0,0}, {6,0}, {8,2.5}, {6,5}, {0,5} }, { {6,5}, {8,7.5}, {6,10}, {0,10} } },
    ['Г'] = { { {8,0}, {0,0}, {0,10} } },
    ['Д'] = { { {2,7}, {2,0}, {8,0}, {8,7} }, { {0,7}, {10,7} }, { {1,7}, {1,10} }, { {9,7}, {9,10} } },
    ['Е'] = { { {0,0}, {0,10} }, { {0,0}, {8,0} }, { {0,5}, {6,5} }, { {0,10}, {8,10} } },
    ['Ё'] = { { {0,0}, {0,10} }, { {0,0}, {8,0} }, { {0,5}, {6,5} }, { {0,10}, {8,10} }, { {3,-2}, {4,-2} }, { {6,-2}, {7,-2} } },
    ['Ж'] = { { {5,0}, {5,10} }, { {0,0}, {10,10} }, { {10,0}, {0,10} }, { {0,5}, {10,5} } },
    ['З'] = { { {1,2}, {3,0}, {7,0}, {9,2.5}, {6,5}, {9,7.5}, {7,10}, {2,10}, {0,8} } },
    ['И'] = { { {0,0}, {0,10} }, { {10,0}, {10,10} }, { {10,0}, {0,10} } },
    ['Й'] = { { {0,0}, {0,10} }, { {10,0}, {10,10} }, { {10,0}, {0,10} }, { {3,-2}, {5,-1}, {7,-2} } },
    ['К'] = { { {0,0}, {0,10} }, { {8,0}, {0,5}, {8,10} } },
    ['Л'] = { { {0,10}, {2,10}, {5,0}, {8,10}, {10,10} } },
    ['М'] = { { {0,10}, {0,0}, {5,5}, {10,0}, {10,10} } },
    ['Н'] = { { {0,0}, {0,10} }, { {10,0}, {10,10} }, { {0,5}, {10,5} } },
    ['О'] = { { {2,0}, {8,0}, {10,2}, {10,8}, {8,10}, {2,10}, {0,8}, {0,2}, {2,0} } },
    ['П'] = { { {0,10}, {0,0}, {10,0}, {10,10} } },
    ['Р'] = { { {0,10}, {0,0}, {7,0}, {9,2.5}, {7,5}, {0,5} } },
    ['С'] = { { {10,2}, {8,0}, {2,0}, {0,2}, {0,8}, {2,10}, {8,10}, {10,8} } },
    ['Т'] = { { {0,0}, {10,0} }, { {5,0}, {5,10} } },
    ['У'] = { { {0,0}, {5,5}, {10,0} }, { {5,5}, {2,10} } },
    ['Ф'] = { { {5,0}, {5,10} }, { {5,2}, {2,2}, {0,4}, {0,6}, {2,8}, {5,8}, {8,8}, {10,6}, {10,4}, {8,2}, {5,2} } },
    ['Х'] = { { {0,0}, {10,10} }, { {10,0}, {0,10} } },
    ['Ц'] = { { {0,0}, {0,10}, {9,10}, {9,0} }, { {9,10}, {11,10}, {11,12} } },
    ['Ч'] = { { {0,0}, {0,5}, {10,5} }, { {10,0}, {10,10} } },
    ['Ш'] = { { {0,0}, {0,10}, {10,10}, {10,0} }, { {5,0}, {5,10} } },
    ['Щ'] = { { {0,0}, {0,10}, {10,10}, {10,0} }, { {5,0}, {5,10} }, { {10,10}, {12,10}, {12,12} } },
    ['Ъ'] = { { {0,0}, {3,0}, {3,10}, {9,10}, {9,5}, {3,5} } },
    ['Ы'] = { { {0,0}, {0,10}, {6,10}, {6,5}, {0,5} }, { {9,0}, {9,10} } },
    ['Ь'] = { { {0,0}, {0,10}, {6,10}, {6,5}, {0,5} } },
    ['Э'] = { { {2,0}, {8,0}, {10,2}, {10,8}, {8,10}, {2,10} }, { {3,5}, {9,5} } },
    ['Ю'] = { { {0,0}, {0,10} }, { {0,5}, {4,5} }, { {6,0}, {9,0}, {11,2}, {11,8}, {9,10}, {6,10}, {4,8}, {4,2}, {6,0} } },
    ['Я'] = { { {0,10}, {8,10}, {8,0} }, { {8,0}, {2,0}, {0,2.5}, {2,5}, {8,5} }, { {4,5}, {0,10} } }
}

local CYR_UPPER = {
    ["а"]="А", ["б"]="Б", ["в"]="В", ["г"]="Г", ["д"]="Д", ["е"]="Е", ["ё"]="Ё",
    ["ж"]="Ж", ["з"]="З", ["и"]="И", ["й"]="Й", ["к"]="К", ["л"]="Л", ["м"]="М",
    ["н"]="Н", ["о"]="О", ["п"]="П", ["р"]="Р", ["с"]="С", ["т"]="Т", ["у"]="У",
    ["ф"]="Ф", ["х"]="Х", ["ц"]="Ц", ["ч"]="Ч", ["ш"]="Ш", ["щ"]="Щ", ["ъ"]="Ъ",
    ["ы"]="Ы", ["ь"]="Ь", ["э"]="Э", ["ю"]="Ю", ["я"]="Я"
}

local function SplitUtf8(str)
    local chars = {}
    local i = 1
    local len = #str
    while i <= len do
        local b = str:byte(i)
        local clen = 1
        if b >= 0xC0 and b <= 0xDF then clen = 2
        elseif b >= 0xE0 and b <= 0xEF then clen = 3
        elseif b >= 0xF0 and b <= 0xF7 then clen = 4 end
        table.insert(chars, str:sub(i, i + clen - 1))
        i = i + clen
    end
    return chars
end

local function WrapTextLines(text, max_chars)
    -- Support literal \n and /n as line breaks
    text = text:gsub("\\n", "\n"):gsub("/n", "\n")

    local raw_lines = {}
    for line in (text .. "\n"):gmatch("(.-)\r?\n") do
        table.insert(raw_lines, line)
    end
    if #raw_lines == 0 then table.insert(raw_lines, text) end

    if not max_chars or max_chars <= 0 then
        return raw_lines
    end

    local wrapped = {}
    for _, line_str in ipairs(raw_lines) do
        local chars = SplitUtf8(line_str)
        if #chars <= max_chars then
            table.insert(wrapped, line_str)
        else
            local words = {}
            for w in line_str:gmatch("%S+") do table.insert(words, w) end
            if #words == 0 then
                table.insert(wrapped, "")
            else
                local cur_line = ""
                local cur_len = 0
                for _, word in ipairs(words) do
                    local w_chars = SplitUtf8(word)
                    local w_len = #w_chars
                    if cur_len == 0 then
                        cur_line = word
                        cur_len = w_len
                    elseif (cur_len + 1 + w_len) <= max_chars then
                        cur_line = cur_line .. " " .. word
                        cur_len = cur_len + 1 + w_len
                    else
                        table.insert(wrapped, cur_line)
                        cur_line = word
                        cur_len = w_len
                    end
                end
                if cur_line ~= "" then
                    table.insert(wrapped, cur_line)
                end
            end
        end
    end
    return wrapped
end

function FontEngine.GenerateTextStrokes(text, width_pct, letter_spacing, line_spacing, align, is_bold, max_wrap)
    width_pct = (width_pct or 100) / 100.0
    letter_spacing = letter_spacing or 3.0
    line_spacing = line_spacing or 6.0
    align = align or 1

    local lines_raw = WrapTextLines(text, max_wrap or 0)
    local char_w = 10.0 * width_pct
    local char_h = 10.0

    local line_data = {}
    local max_line_w = 0.0

    for _, line_str in ipairs(lines_raw) do
        local chars = SplitUtf8(line_str)
        local count = #chars
        local total_w = 0
        if count > 0 then
            total_w = count * char_w + (count - 1) * letter_spacing
        end
        if total_w > max_line_w then max_line_w = total_w end
        table.insert(line_data, { chars = chars, width = total_w })
    end

    max_line_w = math.max(10.0, max_line_w)

    local raw_strokes = {}
    local y_cursor = 0.0

    for _, ld in ipairs(line_data) do
        local x_start = 0.0
        if align == 1 then
            x_start = (max_line_w - ld.width) / 2.0
        elseif align == 3 then
            x_start = max_line_w - ld.width
        end

        local x_cursor = x_start
        for _, ch in ipairs(ld.chars) do
            local upper_ch = CYR_UPPER[ch] or string.upper(ch)
            local glyph = GLYPHS[upper_ch] or GLYPHS['?']
            if glyph then
                for _, stroke in ipairs(glyph) do
                    local s = {}
                    for _, pt in ipairs(stroke) do
                        table.insert(s, {
                            x = x_cursor + pt[1] * width_pct,
                            y = y_cursor + pt[2]
                        })
                    end
                    table.insert(raw_strokes, s)

                    if is_bold then
                        local sb = {}
                        for _, pt in ipairs(stroke) do
                            table.insert(sb, {
                                x = x_cursor + pt[1] * width_pct + 0.35,
                                y = y_cursor + pt[2] + 0.35
                            })
                        end
                        table.insert(raw_strokes, sb)
                    end
                end
            end
            x_cursor = x_cursor + char_w + letter_spacing
        end
        y_cursor = y_cursor + char_h + line_spacing
    end

    return SVG.NormalizeStrokes(raw_strokes)
end

-- ------------------------------------------------------------------------
-- Fonts
-- ------------------------------------------------------------------------
local font_ui = nil
local font_small = nil
local font_title = nil

pcall(function()
    local flags = 0
    if Enum and Enum.FontCreate and Enum.FontCreate.FONTFLAG_ANTIALIAS then
        flags = Enum.FontCreate.FONTFLAG_ANTIALIAS
    end
    font_ui = Render.LoadFont("MuseoSansEx", flags, 500)
    font_small = Render.LoadFont("MuseoSansEx", flags, 400)
    font_title = Render.LoadFont("MuseoSansEx", flags, 600)
end)

if not font_ui then font_ui = Render.LoadFont("Arial", 0, 500) end
if not font_small then font_small = Render.LoadFont("Arial", 0, 400) end
if not font_title then font_title = font_ui end

-- ------------------------------------------------------------------------
-- Pre-allocated Static Colors
-- ------------------------------------------------------------------------
local COL_SHADOW        = Color(0, 0, 0, 150)
local COL_GLASS_BG      = Color(16, 18, 22, 175)
local COL_GLASS_BORDER  = Color(255, 255, 255, 22)
local COL_CARD_BG       = Color(0, 0, 0, 120)
local COL_CARD_BORDER   = Color(255, 255, 255, 18)
local COL_GRID_LINE     = Color(255, 255, 255, 12)
local COL_RIVER_LINE    = Color(255, 255, 255, 8)
local COL_LABEL         = Color(255, 255, 255, 50)
local COL_STROKE        = Color(245, 250, 255, 240)
local COL_DRAWING       = Color(255, 235, 140, 240)
local COL_TEXT_TITLE    = Color(240, 245, 250, 240)
local COL_TEXT_MUTED    = Color(165, 170, 180, 200)
local COL_LOOP_ON       = Color(255, 190, 50, 230)
local COL_LOOP_OFF      = Color(110, 115, 125, 180)
local COL_BTN_BG        = Color(255, 255, 255, 14)
local COL_BTN_HOVER     = Color(255, 255, 255, 28)
local COL_BTN_BORDER    = Color(255, 255, 255, 22)
local COL_BTN_B_HOVER   = Color(255, 255, 255, 55)
local COL_BTN_TEXT      = Color(200, 205, 215, 220)
local COL_BTN_T_HOVER   = Color(255, 255, 255, 255)
local COL_BTN_CLEAR_H   = Color(255, 160, 160, 255)
local COL_PRIMARY_BG    = Color(255, 255, 255, 32)
local COL_PRIMARY_H     = Color(255, 255, 255, 50)
local COL_PRIMARY_B     = Color(255, 255, 255, 65)
local COL_PRIMARY_BH    = Color(255, 255, 255, 110)
local COL_WHITE         = Color(255, 255, 255, 255)
local COL_QR_PLATE      = Color(255, 255, 255, 255)
local COL_QR_STROKE     = Color(10, 10, 10, 255)
local COL_CLOSE_MUTED   = Color(150, 155, 165, 180)
local COL_CLOSE_BG      = Color(255, 255, 255, 25)

-- ------------------------------------------------------------------------
-- Menu Registration (Scripts -> elycde -> Map Drawer -> [Canvas | QR Code | SVG | TEXT])
-- ------------------------------------------------------------------------
local mapDrawerTab = Menu.Create("Scripts", "elycde", "Map Drawer")
mapDrawerTab:Icon("\u{f040}")

-- CThirdTab
local tab_settings = mapDrawerTab:Create("Настройки")
tab_settings:Icon("\u{f013}")

local tab_canvas  = mapDrawerTab:Create("Холст")
tab_canvas:Icon("\u{f040}")

local tab_qrcode  = mapDrawerTab:Create("QR Code")
tab_qrcode:Icon("\u{f029}")

local tab_svg     = mapDrawerTab:Create("SVG")
tab_svg:Icon("\u{f1fc}")

local tab_text    = mapDrawerTab:Create("TEXT")
tab_text:Icon("\u{f031}")

-- Авто-добавление в Избранное (Favorites) чита
pcall(function()
    local path = "Scripts/elycde/Map Drawer"
    local f = io.open("gui.json", "r")
    if not f then f = io.open("C:/Umbrella/gui.json", "r") end
    if f then
        local content = f:read("*a")
        f:close()
        if content and not content:find(path, 1, true) then
            local new_content = content:gsub('("FavoriteTabs"%s*:%s*%[)', '%1\n        "' .. path .. '",')
            if new_content and new_content ~= content then
                local fw = io.open("gui.json", "w")
                if not fw then fw = io.open("C:/Umbrella/gui.json", "w") end
                if fw then
                    fw:write(new_content)
                    fw:close()
                end
            end
        end
    end
end)

-- Forward declarations
local user_strokes = {}
local current_stroke = nil
local was_mouse_down = false
local last_draw_time = 0
local is_qr_mode = false

local InvalidateDrawCache = function() end
local TriggerInstantDraw = function() end
local ClearAllStrokes = function() end

-- ========================================================================
-- TAB 0: Настройки (Основное и позиционирование)
-- ========================================================================
local group_main = tab_settings:Create("Основное")
local ui_enable = group_main:Switch("Включить скрипт", true, "\u{f00c}")
local ui_broadcast = group_main:Switch("Видно союзникам на миникарте", true, "\u{f0ac}")

-- Желтый warning у зацикливания через native :Unsafe(true)
local ui_loop = group_main:Switch("Зациклить рисовку", false)
pcall(function() if ui_loop and ui_loop.Unsafe then ui_loop:Unsafe(true) end end)
ui_loop:ToolTip("Внимание: частое зацикливание спамит сетевые пакеты. Рекомендуется интервал от 150-300 мс во избежание просадки FPS и бана/кика от сервера.")

local ui_loop_interval = group_main:Slider("Интервал цикла (мс)", 100, 3000, 250, "%d мс")
pcall(function() if ui_loop_interval and ui_loop_interval.Unsafe then ui_loop_interval:Unsafe(true) end end)
ui_loop_interval:ToolTip("Интервал повторной отправки рисунка. Порог ограничен от 100 мс (рекомендуется 250-500 мс), чтобы не падал FPS и не было лагов.")

local group_pos = tab_settings:Create("Позиция и Масштаб")
local ui_pos_x = group_pos:Slider("Позиция X центра", -8000, 8000, 0, "%d")
local ui_pos_y = group_pos:Slider("Позиция Y центра", -8000, 8000, 0, "%d")
local ui_scale = group_pos:Slider("Размер на миникарте", 500, 20000, 3000, "%d")

local ui_btn_reset = group_pos:Button("Сброс в центр карты (0, 0)", function()
    if ui_pos_x and ui_pos_y then
        ui_pos_x:Set(0)
        ui_pos_y:Set(0)
        InvalidateDrawCache()
    end
end)

if ui_pos_x and ui_pos_x.SetCallback then ui_pos_x:SetCallback(function() InvalidateDrawCache() end) end
if ui_pos_y and ui_pos_y.SetCallback then ui_pos_y:SetCallback(function() InvalidateDrawCache() end) end
if ui_scale and ui_scale.SetCallback then ui_scale:SetCallback(function() InvalidateDrawCache() end) end

-- ========================================================================
-- TAB 1: Холст (Интерактивное рисование и пресеты)
-- ========================================================================
local group_ctrl = tab_canvas:Create("Управление холстом")
local ui_canvas_show = group_ctrl:Switch("Отображать холст", true, "\u{f06e}")
ui_canvas_show:ToolTip("Включить или выключить плавающее окно интерактивного холста")

local ui_presets = group_ctrl:Combo("Заготовки", { "Свой рисунок", "GG WP", "Закрасить всю карту" }, 1)

local ui_btn_draw = group_ctrl:Button("Нарисовать на миникарте", function()
    TriggerInstantDraw()
end)
local ui_btn_clear = group_ctrl:Button("Очистить всё", function()
    ClearAllStrokes()
    is_qr_mode = false
end)

-- ========================================================================
-- TAB 2: QR Code (Плотный, жирный, 100% читаемый камерой QR-код)
-- ========================================================================
local group_qr = tab_qrcode:Create("Генератор QR-кода")
local ui_qr_text = group_qr:Input("Текст или ссылка", "https://t.me/elycde")
local ui_qr_scale = group_qr:Slider("Размер на миникарте", 1000, 20000, 16000, "%d")
local ui_qr_density = group_qr:Slider("Плотность линий (проходов на блок)", 2, 4, 3, "%d прохода")
local ui_qr_invert = group_qr:Switch("Инвертировать цвета", false, "\u{f042}")

local function GenerateAndApplyQR()
    local text = (ui_qr_text and ui_qr_text:Get()) or "https://t.me/elycde"
    if text == "" then text = "https://t.me/elycde" end
    local invert = (ui_qr_invert and ui_qr_invert:Get()) or false
    local passes = (ui_qr_density and ui_qr_density:Get()) or 3

    local ok, mat, size = pcall(QR.GenerateMatrix, text)
    if not ok or not mat then
        mat = DEFAULT_QR_MAT
        size = 25
    end

    user_strokes = QR.MatrixToZeroGapStrokes(mat, size, invert, passes)
    if ui_scale then ui_scale:Set((ui_qr_scale and ui_qr_scale:Get()) or 16000) end
    if ui_pos_x then ui_pos_x:Set(0) end
    if ui_pos_y then ui_pos_y:Set(0) end
    is_qr_mode = true
    if ui_canvas_show then ui_canvas_show:Set(true) end
    TriggerInstantDraw()
end

local ui_btn_qr_draw = group_qr:Button("Сгенерировать QR-код", function()
    GenerateAndApplyQR()
end)

local ui_btn_qr_send = group_qr:Button("Нарисовать на миникарте", function()
    GenerateAndApplyQR()
end)

-- ========================================================================
-- TAB 3: SVG (URL по ссылке, XML код, файлы на диске, пресеты)
-- ========================================================================
local group_svg = tab_svg:Create("SVG Импорт и Рисование")
local ui_svg_url = group_svg:Input("Ссылка (URL) на SVG", "https://raw.githubusercontent.com/FortAwesome/Font-Awesome/6.x/svgs/solid/skull.svg")
local ui_svg_file = group_svg:Input("Файл на диске (svg)", "scripts/image.svg")
local ui_svg_code = group_svg:Input("Код SVG (XML или Path d)", "<path d=\"M10,10 L90,10 L90,90 Z\"/>")
local ui_svg_scale = group_svg:Slider("Размер на миникарте", 1000, 20000, 8000, "%d")

local SVG_BUILTIN_PRESETS = {
    -- 1: Dota 2 Logo
    [[<svg viewBox="0 0 100 100">
        <path d="M22,78 L78,22 L86,30 L30,86 Z"/>
        <path d="M16,66 L42,40 L38,34 L12,48 Z"/>
        <path d="M58,62 L84,36 L88,44 L64,72 Z"/>
    </svg>]],
    -- 2: Skull
    [[<path d="M416 398.9c58.5-41.1 96-104.1 96-174.9C512 100.3 397.4 0 256 0S0 100.3 0 224c0 70.7 37.5 133.8 96 174.9c0 .4 0 .7 0 1.1l0 64c0 26.5 21.5 48 48 48l48 0 0-48c0-8.8 7.2-16 16-16s16 7.2 16 16l0 48 64 0 0-48c0-8.8 7.2-16 16-16s16 7.2 16 16l0 48 48 0c26.5 0 48-21.5 48-48l0-64c0-.4 0-.7 0-1.1zM96 256a64 64 0 1 1 128 0A64 64 0 1 1 96 256zm256-64a64 64 0 1 1 0 128 64 64 0 1 1 0-128z"/>]],
    -- 3: Crown
    [[<path d="M50,15 L20,75 L80,75 Z M20,75 L0,30 L25,45 Z M80,75 L100,30 L75,45 Z M20,75 L80,75 L80,85 L20,85 Z"/>]],
    -- 4: Star
    [[<polygon points="50,5 64,35 96,38 72,61 78,95 50,78 22,95 28,61 4,38 36,35"/>]],
    -- 5: Heart
    [[<path d="M50,30 C50,15 35,0 20,0 C8,0 0,10 0,22 C0,38 35,65 50,80 C65,65 100,38 100,22 C100,10 92,0 80,0 C65,0 50,15 50,30 Z"/>]],
    -- 6: Sword
    [[<path d="M48,5 L52,5 L54,60 L65,60 L65,66 L53,66 L53,85 L57,88 L57,95 L43,95 L43,88 L47,85 L47,66 L35,66 L35,60 L46,60 Z"/>]]
}

local ui_svg_presets = group_svg:Combo("Встроенные SVG вектор-рисунки", {
    "Выбрать готовый вектор",
    "Логотип Dota 2",
    "Череп (Skull)",
    "Корона (Crown)",
    "Пятиконечная звезда",
    "Сердце (Heart)",
    "Меч (Sword)"
}, 1)

local function ApplyStrokesFromSVG(strokes)
    if #strokes > 0 then
        user_strokes = strokes
        if ui_scale then ui_scale:Set((ui_svg_scale and ui_svg_scale:Get()) or 8000) end
        if ui_pos_x then ui_pos_x:Set(0) end
        if ui_pos_y then ui_pos_y:Set(0) end
        is_qr_mode = false
        if ui_canvas_show then ui_canvas_show:Set(true) end
        TriggerInstantDraw()
    end
end

if ui_svg_presets and ui_svg_presets.SetCallback then
    ui_svg_presets:SetCallback(function()
        local idx = ui_svg_presets:Get()
        if idx > 1 and SVG_BUILTIN_PRESETS[idx - 1] then
            local strokes = SVG.Parse(SVG_BUILTIN_PRESETS[idx - 1])
            ApplyStrokesFromSVG(strokes)
        end
    end)
end

local ui_btn_svg_load_url = group_svg:Button("Загрузить по ссылке (URL)", function()
    local url = (ui_svg_url and ui_svg_url:Get()) or ""
    if url == "" then return end

    url = url:gsub("^%s+", ""):gsub("%s+$", "")
    url = url:gsub("github%.com/([^/]+)/([^/]+)/blob/", "raw.githubusercontent.com/%1/%2/")

    if not HTTP or not HTTP.Request then return end

    HTTP.Request("GET", url, {
        headers = {
            ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/122.0.0.0 Safari/537.36",
            ["Accept"] = "*/*",
            ["Accept-Encoding"] = "identity"
        },
        timeout = 15
    }, function(res)
        if not res then return end
        local code = tonumber(res.code) or 200
        if code ~= 200 and code ~= 301 and code ~= 302 then return end
        local body = res.response or res.body or res.data or ""
        if body == "" then return end
        local strokes = SVG.Parse(body)
        ApplyStrokesFromSVG(strokes)
    end)
end)

local ui_btn_svg_load_file = group_svg:Button("Загрузить из файла на диске", function()
    local filepath = (ui_svg_file and ui_svg_file:Get()) or ""
    if filepath == "" then return end

    local file = io.open(filepath, "r")
    if not file then file = io.open("scripts/" .. filepath, "r") end
    if not file then return end

    local content = file:read("*a")
    file:close()
    if not content or content == "" then return end

    local strokes = SVG.Parse(content)
    ApplyStrokesFromSVG(strokes)
end)

local ui_btn_svg_load_code = group_svg:Button("Применить введенный код SVG", function()
    local code_text = (ui_svg_code and ui_svg_code:Get()) or ""
    if code_text == "" then return end

    local strokes = SVG.Parse(code_text)
    ApplyStrokesFromSVG(strokes)
end)

local ui_btn_svg_draw = group_svg:Button("Нарисовать на миникарте", function()
    local code_text = (ui_svg_code and ui_svg_code:Get()) or ""
    if code_text ~= "" and #user_strokes == 0 then
        local strokes = SVG.Parse(code_text)
        ApplyStrokesFromSVG(strokes)
    else
        TriggerInstantDraw()
    end
end)

-- ========================================================================
-- TAB 4: TEXT (Векторный вывод текста, \n перенос)
-- ========================================================================
local group_text = tab_text:Create("Генератор Текста")
local ui_text_content = group_text:Input("Текст для вывода (\\n - перенос)", "DOTA 2")
local ui_text_scale = group_text:Slider("Размер на миникарте", 1000, 20000, 8000, "%d")
local ui_text_char_spacing = group_text:Slider("Межбуквенный интервал", -2, 20, 2, "%d")
local ui_text_line_spacing = group_text:Slider("Межстрочный интервал", 0, 25, 4, "%d")
local ui_text_bold = group_text:Switch("Жирный шрифт", false, "\u{f032}")

local function GenerateAndApplyText()
    local text = (ui_text_content and ui_text_content:Get()) or "DOTA 2"
    if text == "" then text = "DOTA 2" end

    local w_pct = 100
    local c_space = (ui_text_char_spacing and ui_text_char_spacing:Get()) or 2
    local l_space = (ui_text_line_spacing and ui_text_line_spacing:Get()) or 4
    local align_idx = 1
    local is_bold = (ui_text_bold and ui_text_bold:Get()) or false
    local max_wrap = 0

    local strokes = FontEngine.GenerateTextStrokes(text, w_pct, c_space, l_space, align_idx, is_bold, max_wrap)
    if #strokes > 0 then
        user_strokes = strokes
        if ui_scale then ui_scale:Set((ui_text_scale and ui_text_scale:Get()) or 8000) end
        if ui_pos_x then ui_pos_x:Set(0) end
        if ui_pos_y then ui_pos_y:Set(0) end
        is_qr_mode = false
        if ui_canvas_show then ui_canvas_show:Set(true) end
        TriggerInstantDraw()
    end
end

local ui_btn_text_draw = group_text:Button("Нарисовать на миникарте", function()
    GenerateAndApplyText()
end)

-- ------------------------------------------------------------------------
-- Master Switch Dependency Management (All 4 Tabs)
-- ------------------------------------------------------------------------
local subordinate_controls = {
    ui_broadcast,
    ui_loop,
    ui_loop_interval,
    ui_pos_x,
    ui_pos_y,
    ui_scale,
    ui_btn_reset,
    ui_presets,
    ui_canvas_show,
    ui_btn_draw,
    ui_btn_clear,
    ui_qr_text,
    ui_qr_scale,
    ui_qr_density,
    ui_qr_invert,
    ui_btn_qr_draw,
    ui_btn_qr_send,
    ui_svg_url,
    ui_svg_file,
    ui_svg_code,
    ui_svg_scale,
    ui_svg_presets,
    ui_btn_svg_load_url,
    ui_btn_svg_load_file,
    ui_btn_svg_load_code,
    ui_btn_svg_draw,
    ui_text_content,
    ui_text_scale,
    ui_text_char_spacing,
    ui_text_line_spacing,
    ui_text_bold,
    ui_btn_text_draw
}

local function UpdateEnableState()
    local enabled = ui_enable and ui_enable:Get() or false
    for _, ctrl in ipairs(subordinate_controls) do
        if ctrl and type(ctrl.Disabled) == "function" then
            pcall(function() ctrl:Disabled(not enabled) end)
        end
    end
    if enabled and ui_loop and ui_loop_interval and type(ui_loop_interval.Disabled) == "function" then
        pcall(function() ui_loop_interval:Disabled(not ui_loop:Get()) end)
    end
end

if ui_enable and ui_enable.SetCallback then
    ui_enable:SetCallback(function()
        UpdateEnableState()
    end, true)
else
    UpdateEnableState()
end

-- ------------------------------------------------------------------------
-- Presets
-- ------------------------------------------------------------------------
local MOUSE_LEFT_CODE = (Enum.ButtonCode and Enum.ButtonCode.KEY_MOUSE1) or 107

if ui_loop and ui_loop.SetCallback then
    ui_loop:SetCallback(function()
        if ui_loop:Get() then
            last_draw_time = 0
        end
        if ui_enable and ui_enable:Get() and ui_loop_interval and type(ui_loop_interval.Disabled) == "function" then
            pcall(function() ui_loop_interval:Disabled(not ui_loop:Get()) end)
        end
    end)
end

if ui_loop_interval and ui_loop_interval.SetCallback then
    ui_loop_interval:SetCallback(function()
        last_draw_time = 0
    end)
end

local function GetPresetStrokes(preset_idx)
    local s = {}

    if preset_idx == 1 then
        -- Preset 1: GG WP
        table.insert(s, {
            { x = 0.26, y = 0.35 }, { x = 0.20, y = 0.30 }, { x = 0.14, y = 0.35 },
            { x = 0.14, y = 0.45 }, { x = 0.20, y = 0.50 }, { x = 0.26, y = 0.50 },
            { x = 0.26, y = 0.40 }, { x = 0.20, y = 0.40 }
        })
        table.insert(s, {
            { x = 0.44, y = 0.35 }, { x = 0.38, y = 0.30 }, { x = 0.32, y = 0.35 },
            { x = 0.32, y = 0.45 }, { x = 0.38, y = 0.50 }, { x = 0.44, y = 0.50 },
            { x = 0.44, y = 0.40 }, { x = 0.38, y = 0.40 }
        })
        table.insert(s, {
            { x = 0.52, y = 0.30 }, { x = 0.56, y = 0.50 }, { x = 0.61, y = 0.38 },
            { x = 0.66, y = 0.50 }, { x = 0.70, y = 0.30 }
        })
        table.insert(s, {
            { x = 0.76, y = 0.50 }, { x = 0.76, y = 0.30 }, { x = 0.86, y = 0.30 },
            { x = 0.86, y = 0.40 }, { x = 0.76, y = 0.40 }
        })

    elseif preset_idx == 2 then
        -- Preset 2: Закрасить всю карту
        if ui_scale then ui_scale:Set(16000) end
        if ui_pos_x then ui_pos_x:Set(0) end
        if ui_pos_y then ui_pos_y:Set(0) end

        local total_lines = 64
        local lines_per_chunk = 16
        local num_chunks = 4

        for chunk = 0, num_chunks - 1 do
            local stroke = {}
            local start_line = chunk * lines_per_chunk
            local end_line = start_line + lines_per_chunk - 1
            for line_i = start_line, end_line do
                local y = 0.01 + (line_i / (total_lines - 1)) * 0.98
                if line_i % 2 == 0 then
                    table.insert(stroke, { x = 0.01, y = y })
                    table.insert(stroke, { x = 0.99, y = y })
                else
                    table.insert(stroke, { x = 0.99, y = y })
                    table.insert(stroke, { x = 0.01, y = y })
                end
            end
            table.insert(s, stroke)
        end

        table.insert(s, {
            { x = 0.005, y = 0.005 },
            { x = 0.995, y = 0.005 },
            { x = 0.995, y = 0.995 },
            { x = 0.005, y = 0.995 },
            { x = 0.005, y = 0.005 }
        })
    end

    return s
end

ClearAllStrokes = function()
    user_strokes = {}
    current_stroke = nil
    InvalidateDrawCache()
end

local last_preset_idx = 0
local function CheckPresetUpdate()
    local cur_idx = ui_presets:Get()
    if cur_idx ~= last_preset_idx then
        last_preset_idx = cur_idx
        if cur_idx > 0 then
            user_strokes = GetPresetStrokes(cur_idx)
            is_qr_mode = false
            TriggerInstantDraw()
        end
    end
end

-- Pre-cached world lines for ultra-fast, zero-allocation drawing
local cached_world_lines = {}
local cached_is_dirty = true

InvalidateDrawCache = function()
    cached_is_dirty = true
end

local function RebuildDrawCache()
    cached_world_lines = {}
    if #user_strokes == 0 then
        cached_is_dirty = false
        return
    end

    local origin_x = (ui_pos_x and ui_pos_x:Get()) or 0
    local origin_y = (ui_pos_y and ui_pos_y:Get()) or 0
    local scale = (ui_scale and ui_scale:Get()) or 3000

    -- Point reduction & zero-allocation caching
    for _, stroke in ipairs(user_strokes) do
        local n = #stroke
        if n > 0 then
            local last_px, last_py = nil, nil
            for i = 1, n do
                local pt = stroke[i]
                local skip = false
                -- Skip redundant micro-points on dense strokes to stop packet flood and FPS drop
                if n > 12 and i > 1 and i < n and last_px and last_py then
                    local dx = math.abs(pt.x - last_px)
                    local dy = math.abs(pt.y - last_py)
                    if dx < 0.0025 and dy < 0.0025 then
                        skip = true
                    end
                end

                if not skip then
                    local wx = origin_x + (pt.x - 0.5) * scale
                    local wy = origin_y + (0.5 - pt.y) * scale
                    table.insert(cached_world_lines, {
                        vec = Vector(wx, wy, 128),
                        is_first = (i == 1)
                    })
                    last_px = pt.x
                    last_py = pt.y
                end
            end
        end
    end
    cached_is_dirty = false
end

-- Synchronous SendLine to Minimap (0 allocations in loop)
TriggerInstantDraw = function()
    if not ui_enable or not ui_enable:Get() then return end
    if cached_is_dirty then
        RebuildDrawCache()
    end
    if #cached_world_lines == 0 then return end

    local is_clientside = not (ui_broadcast and ui_broadcast:Get())
    for _, item in ipairs(cached_world_lines) do
        MiniMap.SendLine(item.vec, item.is_first, is_clientside)
    end
end

-- ------------------------------------------------------------------------
-- Canvas Widget (Smooth, Crash-Proof, Perfectly Aligned Grid Lines)
-- ------------------------------------------------------------------------
local function RenderCanvasWidget()
    if not ui_enable or not ui_enable:Get() or not Menu.Opened() then
        return
    end
    if not ui_canvas_show or not ui_canvas_show:Get() then
        return
    end

    local menu_pos = Menu.Pos()
    local menu_size = Menu.Size()
    if not menu_pos or not menu_size then
        return
    end

    local screen = Render.ScreenSize()
    local canvas_w = 276
    local canvas_h = 368
    local pad = 12
    local box_size = 252

    local posX = menu_pos.x + menu_size.x + 8
    local posY = menu_pos.y

    if posX + canvas_w > screen.x - 5 then
        posX = menu_pos.x - canvas_w - 8
    end
    if posX < 5 then posX = 5 end
    if posY + canvas_h > screen.y - 5 then posY = screen.y - canvas_h - 5 end
    if posY < 5 then posY = 5 end

    local tl = Vec2(posX, posY)
    local br = Vec2(posX + canvas_w, posY + canvas_h)

    -- 0. Blur
    if Render.Blur then
        pcall(function() Render.Blur(tl, br, 0.30, 0.85, 8) end)
    end

    -- 1. Glass Shadow & Card
    pcall(Render.Shadow, tl, br, COL_SHADOW, 22, 8)
    Render.FilledRect(tl, br, COL_GLASS_BG, 8)
    Render.Rect(tl, br, COL_GLASS_BORDER, 8, 0, 1.0)

    -- 2. Title
    Render.Text(font_title, 13, "Холст миникарты", Vec2(posX + pad, posY + 10), COL_TEXT_TITLE)

    -- Close Button [✕]
    local close_btn_x = posX + canvas_w - 26
    local close_btn_y = posY + 7
    local close_hover = Input.IsCursorInRect(close_btn_x, close_btn_y, 20, 20)
    if close_hover then
        Render.FilledRect(Vec2(close_btn_x, close_btn_y), Vec2(close_btn_x + 20, close_btn_y + 20), COL_CLOSE_BG, 4)
    end
    Render.Text(font_title, 12, "✕", Vec2(close_btn_x + 5, close_btn_y + 3), close_hover and COL_WHITE or COL_CLOSE_MUTED)

    -- 3. Drawing Box
    local box_x = posX + pad
    local box_y = posY + 38
    local box_w = box_size
    local box_h = box_size

    if is_qr_mode then
        Render.FilledRect(Vec2(box_x, box_y), Vec2(box_x + box_w, box_y + box_h), COL_QR_PLATE, 6)
        Render.Rect(Vec2(box_x, box_y), Vec2(box_x + box_w, box_y + box_h), COL_CARD_BORDER, 6, 0, 1.0)
    else
        Render.FilledRect(Vec2(box_x, box_y), Vec2(box_x + box_w, box_y + box_h), COL_CARD_BG, 6)
        Render.Rect(Vec2(box_x, box_y), Vec2(box_x + box_w, box_y + box_h), COL_CARD_BORDER, 6, 0, 1.0)

        -- Fixed Axis Lines: Perfect Horizontal & Vertical Centerlines
        Render.Line(Vec2(box_x + box_w / 2, box_y), Vec2(box_x + box_w / 2, box_y + box_h), COL_GRID_LINE, 1)
        Render.Line(Vec2(box_x, box_y + box_h / 2), Vec2(box_x + box_w, box_y + box_h / 2), COL_GRID_LINE, 1)
        Render.Line(Vec2(box_x + 25, box_y + 25), Vec2(box_x + box_w - 25, box_y + box_h - 25), COL_RIVER_LINE, 1)

        Render.Text(font_small, 9, "Radiant", Vec2(box_x + 6, box_y + box_h - 15), COL_LABEL)
        Render.Text(font_small, 9, "Dire", Vec2(box_x + box_w - 24, box_y + 5), COL_LABEL)
    end

    -- 4. Draw Strokes
    local stroke_color = is_qr_mode and COL_QR_STROKE or COL_STROKE
    local stroke_width = 2.0

    for _, stroke in ipairs(user_strokes) do
        local n_pts = #stroke
        if n_pts == 1 then
            local p = stroke[1]
            Render.FilledCircle(Vec2(box_x + p.x * box_w, box_y + p.y * box_h), is_qr_mode and 2.0 or 1.5, stroke_color)
        elseif n_pts > 1 then
            for i = 1, n_pts - 1 do
                local p1 = stroke[i]
                local p2 = stroke[i + 1]
                Render.Line(
                    Vec2(box_x + p1.x * box_w, box_y + p1.y * box_h),
                    Vec2(box_x + p2.x * box_w, box_y + p2.y * box_h),
                    stroke_color,
                    stroke_width
                )
            end
        end
    end

    if current_stroke then
        if #current_stroke == 1 then
            local p = current_stroke[1]
            Render.FilledCircle(Vec2(box_x + p.x * box_w, box_y + p.y * box_h), 2.0, COL_DRAWING)
        elseif #current_stroke > 1 then
            for i = 1, #current_stroke - 1 do
                local p1 = current_stroke[i]
                local p2 = current_stroke[i + 1]
                Render.Line(
                    Vec2(box_x + p1.x * box_w, box_y + p1.y * box_h),
                    Vec2(box_x + p2.x * box_w, box_y + p2.y * box_h),
                    COL_DRAWING,
                    2.5
                )
            end
        end
    end

    -- 5. Information String & Loop Status
    local pos_x_val = (ui_pos_x and ui_pos_x:Get()) or 0
    local pos_y_val = (ui_pos_y and ui_pos_y:Get()) or 0
    local scale_val = (ui_scale and ui_scale:Get()) or 3000
    local info_y = box_y + box_h + 8

    local info_text = string.format("X: %d  Y: %d  |  Размер: %d", pos_x_val, pos_y_val, scale_val)
    Render.Text(font_small, 10, info_text, Vec2(posX + pad, info_y), COL_TEXT_MUTED)

    local is_looping = ui_loop and ui_loop:Get()
    local interval_val = (ui_loop_interval and ui_loop_interval:Get()) or 150
    local loop_str = is_looping and string.format("⚠ %d мс", interval_val) or "○ Пауза"
    local loop_col = is_looping and COL_LOOP_ON or COL_LOOP_OFF
    Render.Text(font_small, 10, loop_str, Vec2(posX + canvas_w - pad - 60, info_y), loop_col)

    -- 6. Bottom Buttons
    local btn_y = info_y + 20
    local btn_h = 28
    local btn_w = math.floor((canvas_w - pad * 2 - 12) / 3)

    -- Button [Очистить]
    local b1_x = posX + pad
    local h1 = Input.IsCursorInRect(b1_x, btn_y, btn_w, btn_h)
    Render.FilledRect(Vec2(b1_x, btn_y), Vec2(b1_x + btn_w, btn_y + btn_h), h1 and COL_BTN_HOVER or COL_BTN_BG, 5)
    Render.Rect(Vec2(b1_x, btn_y), Vec2(b1_x + btn_w, btn_y + btn_h), h1 and COL_BTN_B_HOVER or COL_BTN_BORDER, 5, 0, 1.0)
    Render.Text(font_ui, 11, "Очистить", Vec2(b1_x + 9, btn_y + 7), h1 and COL_BTN_CLEAR_H or COL_BTN_TEXT)

    -- Button [Отмена]
    local b2_x = b1_x + btn_w + 6
    local h2 = Input.IsCursorInRect(b2_x, btn_y, btn_w, btn_h)
    Render.FilledRect(Vec2(b2_x, btn_y), Vec2(b2_x + btn_w, btn_y + btn_h), h2 and COL_BTN_HOVER or COL_BTN_BG, 5)
    Render.Rect(Vec2(b2_x, btn_y), Vec2(b2_x + btn_w, btn_y + btn_h), h2 and COL_BTN_B_HOVER or COL_BTN_BORDER, 5, 0, 1.0)
    Render.Text(font_ui, 11, "Отмена", Vec2(b2_x + 13, btn_y + 7), h2 and COL_BTN_T_HOVER or COL_BTN_TEXT)

    -- Button [Нарисовать]
    local b3_x = b2_x + btn_w + 6
    local h3 = Input.IsCursorInRect(b3_x, btn_y, btn_w, btn_h)
    Render.FilledRect(Vec2(b3_x, btn_y), Vec2(b3_x + btn_w, btn_y + btn_h), h3 and COL_PRIMARY_H or COL_PRIMARY_BG, 5)
    Render.Rect(Vec2(b3_x, btn_y), Vec2(b3_x + btn_w, btn_y + btn_h), h3 and COL_PRIMARY_BH or COL_PRIMARY_B, 5, 0, 1.0)
    Render.Text(font_ui, 11, "Нарисовать", Vec2(b3_x + 6, btn_y + 7), COL_WHITE)

    -- 7. Mouse Input Handling (Supports menu-open state, dual cursor format & fluid dragging)
    local is_down = false
    if Input and Input.IsKeyDown then
        local ok, d = pcall(Input.IsKeyDown, MOUSE_LEFT_CODE, true)
        if ok and d then
            is_down = true
        else
            local ok2, d2 = pcall(Input.IsKeyDown, MOUSE_LEFT_CODE)
            if ok2 and d2 then is_down = true end
        end
    end

    local cur_x, cur_y = 0, 0
    if Input and Input.GetCursorPos then
        local ok, a, b = pcall(Input.GetCursorPos)
        if ok then
            if type(a) == "table" or type(a) == "userdata" then
                cur_x = tonumber(a.x or a[1]) or 0
                cur_y = tonumber(a.y or a[2]) or 0
            else
                cur_x = tonumber(a) or 0
                cur_y = tonumber(b) or 0
            end
        end
    end

    local in_box = false
    if Input and Input.IsCursorInRect then
        local ok, hit = pcall(Input.IsCursorInRect, box_x, box_y, box_w, box_h)
        if ok and hit then in_box = true end
    end
    if not in_box and cur_x and cur_y then
        in_box = (cur_x >= box_x and cur_x <= box_x + box_w and cur_y >= box_y and cur_y <= box_y + box_h)
    end

    local nx = math.max(0.0, math.min(1.0, (cur_x - box_x) / box_w))
    local ny = math.max(0.0, math.min(1.0, (cur_y - box_y) / box_h))

    if is_down then
        if not was_mouse_down then
            if close_hover then
                if ui_canvas_show then ui_canvas_show:Set(false) end
            elseif h1 then
                ClearAllStrokes()
                is_qr_mode = false
            elseif h2 then
                if #user_strokes > 0 then
                    table.remove(user_strokes)
                    InvalidateDrawCache()
                end
            elseif h3 then
                TriggerInstantDraw()
            elseif in_box then
                is_qr_mode = false
                current_stroke = { { x = nx, y = ny } }
            end
        elseif current_stroke then
            local last_p = current_stroke[#current_stroke]
            local dx = (nx - last_p.x) * box_w
            local dy = (ny - last_p.y) * box_h
            if (dx * dx + dy * dy) >= 4.0 then
                table.insert(current_stroke, { x = nx, y = ny })
            end
        end
    else
        if was_mouse_down and current_stroke then
            if #current_stroke > 0 then
                table.insert(user_strokes, current_stroke)
                InvalidateDrawCache()
            end
            current_stroke = nil
        end
    end

    was_mouse_down = is_down
end

function MapDrawer.OnDraw()
    pcall(CheckPresetUpdate)
    pcall(RenderCanvasWidget)

    if not ui_enable or not ui_enable:Get() then return end
    if not ui_loop or not ui_loop:Get() then return end
    if #user_strokes == 0 then return end

    local interval_ms = (ui_loop_interval and ui_loop_interval:Get()) or 250
    -- Hard safety floor: no faster than 100ms (prevents packet spam and FPS drops)
    local interval_sec = math.max(0.100, interval_ms / 1000.0)

    local now = os.clock()
    if (now - last_draw_time) >= interval_sec then
        last_draw_time = now
        TriggerInstantDraw()
    end
end

return MapDrawer
