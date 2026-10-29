addon.name    = 'chadcoremenu';
addon.author  = 'ChadBrowick';
addon.version = '3.16.12';
addon.desc    = 'ChadcoreMenu by ChadBrowick: the game\'s main menu, Status and Equipment windows redrawn in the YunaUI style.';
addon.link    = '';

--[[
ChadcoreMenu by ChadBrowick: a VanaCore addon (VanaCore\addons\vanacore\chadcoremenu), a companion to YunaUI.

How it works
  * The game's menus stay the game's: they still run, read your keys / pad and do everything they always did.
    ChadcoreMenu only stops their graphics from being drawn (the same +0x69 "draw" byte YunaUI / UIBegone use) and
    draws its own panel in their place, following the game's cursor every frame.
  * Mouse: a click on a row / slot moves the game's own cursor there and presses OK, through the game's own
    functions (CTkMenuCtrlData::SetCursol and CTkMenuMng::OnKeyDown). Right-click is Cancel, the wheel moves the cursor.
  * Menu structures (window list, name, cursor, button count, menu area) follow sruon's Ashita4-MenuManager (MIT).
  * Anything that fails (a pattern not found, a draw error) gives the game's own window back at once.
--]]

if rawget(_G, 'vana') == nil then
    print('ChadcoreMenu is a VanaCore addon: it goes in VanaCore\\addons\\vanacore\\chadcoremenu (then /addon load chadcoremenu vanacore).');
    return;
end
if rawget(_G, 'AshitaCore') == nil then
    local src = (debug.getinfo(1, 'S').source or ''):gsub('^@', '');
    local dir = src:match('^(.*)[\\/][^\\/]+$') or (vana.paths.addons .. '\\vanacore\\chadcoremenu');
    assert(loadfile(dir .. '\\native.lua'))(dir);
end

require('common');
local imgui    = require('imgui');
local settings = require('settings');
local chat     = require('chat');
local ffi      = require('ffi');
local d3d      = require('d3d8');

----------------------------------------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------------------------------------
local defaults = T{
    enabled      = true,
    main         = true,          -- replace the main menu (Commands)
    char         = true,          -- replace the Status / Equipment windows
    clicks       = true,          -- mouse clicks drive the game's menu
    wheel        = true,          -- mouse wheel moves the cursor
    follow       = true,          -- sit where the game's own window would be (off = your own spot)
    scale        = 1.0,
    alpha        = 1.0,           -- panels are solid: nothing of the game's window shows through
    hide_mode    = 'draw',        -- 'draw' (don't draw the game's window), 'move' (push it below the screen) or 'both'
    main_hide    = 'both',        -- the same for the main menu (its draw switch alone doesn't hide it)
    trace        = true,
    survey       = true,          -- write chadcoremenu-survey.txt: every game window as it opens, and its cursor moves          -- write chadcoremenu-dump.txt (the main menu's buttons and cursor moves) by itself
    main_order   = '',            -- the main menu's order, learned with /cmenu learn (the game's button numbers)
    main_x = -1, main_y = -1, char_x = -1, char_y = -1,   -- where each panel was dragged to (-1 = its own place)
    swap_x = -1, swap_y = -1, browse_x = -1, browse_y = -1, storage_x = -1, storage_y = -1, act_x = -1, act_y = -1,
    action       = true,
    inspect      = true,
    bazaar       = true,          -- another player's bazaar (View Wares): prices, your gil, item cards
    baz_x = -1, baz_y = -1,
    trade        = true,
    warp         = true,          -- Home Points / Survival Guides: every place in one list
    warp_x = -1, warp_y = -1,
    warp_map     = true,          -- the map card beside the place picked (true / 'game': always the game's own maps / false)
    warp_zoom    = true,          -- the map card zoomed in round the spot (false: the whole map)
    statcmd      = true,          -- the Status screen's list (Profile, Job Levels ... Job Points) in the new look
    merits       = true,          -- the Merit Points screens' first choice in the new look
    meritcat_on  = false,         -- the Merit Categories list in the new look (off until tested: /cmenu meritcat on)
    moogle       = true,          -- the Moogle's menu in your Mog House (Storage, Delivery Box, Change Jobs...)
    chat         = true,          -- the chat menu (Say, Tell, Party, Linkshell...) from Chat in the action menu
    chat_x = -1, chat_y = -1,          -- trading an NPC: ChadcoreMenu's own trade list (sent with the game's own trade request)
    trade_x = -1, trade_y = -1,          -- the Check window on another player (gear, linkshell, bazaar)
    ins_x = -1, ins_y = -1,
    act_hide     = 'park',        -- how the game's action menu is hidden ('park' = off screen, like the game's own unused windows)          -- the action menu you get on a target (Attack, Magic, Abilities, Trust, Items, Check)
    locked       = false,         -- panels can't be dragged (the lock in each panel's corner, or /cmenu lock)
    main_name    = 'menuwind',    -- the game's id for the main menu (/cmenu windows shows them all)
    equip_name   = 'equip',
    status_names = 'persona,money,iteminfo,statcom,status',   -- the other windows of the Status / Equipment screen (CatsEyeXI: persona, money, iteminfo)
    list         = true,          -- the swap menu next to the equipment panel
    browse       = true,
    pad          = true,          -- the controller (and arrow keys) drive ChadcoreMenu's own panels while one is open
    pad_ok       = '',            -- the confirm / cancel buttons, learned from how you use the game's menus ('' = Cross / A, Circle / B)
    pad_back     = '',          -- ChadcoreMenu's own Magic / Abilities / Items / Key Items panels
    win_magic    = '',            -- the game's window ids for those menus, learned when you open them from the game's menu
    win_abilities = 'abiselec',
    win_items    = 'bank',
    win_keyitems = '',
    win_status   = 'statcom2',
    storage      = true,          -- replace the storage picker (mnstorag)
    always_hide  = '',            -- game windows kept hidden all the time (/cmenu hide <id>), e.g. ones VanaCore's HUD Manager can't hide
    extra_hide   = '',            -- more window ids to hide while the character panel is up (comma list)
    labels       = '',            -- your own main menu labels (comma list), '' = the built-in ones
    anim         = true,
    hint         = true,          -- the selected command's description under the list
    theme        = 'YunaUI',      -- the highlight colours (/cmenu settings, Look)
    panel_bg     = 'Violet night',
};
local cfg = settings.load(defaults);
if cfg.pad_v == nil then cfg.pad_v = 1; cfg.pad_ok, cfg.pad_back = '', ''; end   -- (once: the first learning rule was too loose)
if cfg.learn_v == nil then                                           -- (once: forget windows learned by mistake - the equipment screen,
    cfg.learn_v = 1;                                                 --  the action menu - and keep the right ones)
    local NEVER = { equip = true, persona = true, money = true, iteminfo = true, playermo = true, menuwind = true, mnstorag = true,
            inline = true, logwindo = true, logwin2 = true, chatctrl = true, mcr1long = true, mcr2long = true, targetwi = true, gmtell = true, query = true };   -- (the chat line and other windows that can take the focus: never a menu's)
    for _, k in ipairs({ 'magic', 'abilities', 'items', 'keyitems', 'status' }) do
        local out = {};
        for n in tostring(cfg['win_' .. k] or ''):gmatch('[^,%s]+') do if not NEVER[n] then out[#out + 1] = n; end end
        cfg['win_' .. k] = table.concat(out, ',');
    end
    if cfg.win_abilities == '' then cfg.win_abilities = 'abiselec,abimenu'; end
    if (cfg.win_status or '') == '' then cfg.win_status = 'statcom2'; end
end
if (cfg.learn_v or 0) < 2 then                                       -- (once: the chat line was learned as the Key Items window - typing a
    cfg.learn_v = 2;                                                 --  /tell opened Key Items - so it, and the like, are taken out)
    local BAD = { inline = true, logwindo = true, logwin2 = true, chatctrl = true, mcr1long = true, mcr2long = true, targetwi = true, gmtell = true, query = true };
    for _, k in ipairs({ 'magic', 'abilities', 'items', 'keyitems', 'status' }) do
        local out = {};
        for n in tostring(cfg['win_' .. k] or ''):gmatch('[^,%s]+') do if not BAD[n] then out[#out + 1] = n; end end
        cfg['win_' .. k] = table.concat(out, ',');
    end
end
if cfg.status_v == nil then cfg.status_v = 1; if (cfg.win_status or '') == '' then cfg.win_status = 'statcom2'; end end
if cfg.names_v == nil then                                           -- (once: CatsEyeXI's real window ids, from the survey)
    cfg.names_v = 1;
    cfg.status_names = 'persona,money,iteminfo,statcom,status';
end
if cfg.items_v == nil then                                           -- (once: the Mog House storage list "bank" is an Items list)
    cfg.items_v = 1;
    local have = false;
    for n in tostring(cfg.win_items or ''):gmatch('[^,%s]+') do if n == 'bank' then have = true; end end
    if not have then cfg.win_items = ((cfg.win_items or '') ~= '') and (cfg.win_items .. ',bank') or 'inventor,bank'; end
end
if cfg.alpha_v == nil then cfg.alpha_v = 1; if tonumber(cfg.alpha) == 0.94 then cfg.alpha = 1.0; end end
settings.register('settings', 'ccm_settings', function(s) if s ~= nil then cfg = s; end end);
local function save() settings.save(); end
local function msg(t) print(chat.header(addon.name):append(chat.message(t))); end
function GAMEUI_LOG()                                                -- VanaCore's own interface elements (for hiding the game's menus its way)
    local n = 0;
    pcall(function()
        if vana == nil or vana.gameui == nil or vana.gameui.elements == nil then return; end
        local f = io.open(addon.path .. 'chadcoremenu-survey.txt', 'a');
        if f then f:write(('GAMEUI VanaCore %s\n'):format(tostring(vana.version))); end
        for _, e in ipairs(vana.gameui.elements() or {}) do
            n = n + 1;
            local acts = type(e.actions) == 'table' and table.concat(e.actions, ',') or tostring(e.actions);
            if f then f:write(('GAMEUI %s | %s | %s\n'):format(tostring(e.id), tostring(e.name), acts)); end
        end
        if f then f:close(); end
    end);
    return n;
end
local function errlog(where, err)
    pcall(function()
        local f = io.open(addon.path .. 'chadcoremenu-errors.txt', 'a');
        if f then f:write(os.date('%Y-%m-%d %H:%M:%S') .. '  [' .. where .. ']  ' .. tostring(err) .. '\n'); f:close(); end
    end);
end
local function split(s)
    local out = {};
    for part in tostring(s or ''):gmatch('[^,]+') do
        part = part:gsub('^%s+', ''):gsub('%s+$', '');
        if part ~= '' then out[#out + 1] = part; end
    end
    return out;
end

----------------------------------------------------------------------------------------------------
-- Look: YunaUI's palette
----------------------------------------------------------------------------------------------------
local C = {
    pbg   = { 0.068, 0.066, 0.088 },       -- panels: near-black with a hint of violet
    text  = { 0.93, 0.92, 0.98, 1 },
    muted = { 0.62, 0.60, 0.72, 1 },
    dim   = { 0.42, 0.40, 0.52, 1 },
    acc   = { 0.74, 0.66, 0.95, 1 },       -- soft lavender
    pink  = { 1.00, 0.36, 0.62 },
    vio   = { 0.62, 0.40, 1.00 },
    mag   = { 0.86, 0.24, 0.86 },
    mp1   = { 0.40, 0.55, 1.00 },
    mp2   = { 0.62, 0.40, 1.00 },
    tp1   = { 1.00, 0.80, 0.42 },
    tp2   = { 1.00, 0.55, 0.30 },
    good  = { 0.55, 1.00, 0.72, 1 },
    bad   = { 1.00, 0.45, 0.45, 1 },
    gold  = { 0.95, 0.76, 0.31, 1 },
};
local U4, DL;
do
    local c4, P1, P2, P3, P4 = { 0, 0, 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 };
    U4 = function(r, g, b, a) c4[1], c4[2], c4[3], c4[4] = r, g, b, a; return imgui.GetColorU32(c4); end
    DL = {};
    function DL.L(d, a, b, c, e, ...) P1[1], P1[2], P2[1], P2[2] = a, b, c, e; return d:AddLine(P1, P2, ...); end
    function DL.R(d, a, b, c, e, ...) P1[1], P1[2], P2[1], P2[2] = a, b, c, e; return d:AddRect(P1, P2, ...); end
    function DL.RF(d, a, b, c, e, ...) P1[1], P1[2], P2[1], P2[2] = a, b, c, e; return d:AddRectFilled(P1, P2, ...); end
    function DL.RFM(d, a, b, c, e, ...) P1[1], P1[2], P2[1], P2[2] = a, b, c, e; return d:AddRectFilledMultiColor(P1, P2, ...); end
    function DL.C(d, a, b, ...) P1[1], P1[2] = a, b; return d:AddCircle(P1, ...); end
    function DL.CF(d, a, b, ...) P1[1], P1[2] = a, b; return d:AddCircleFilled(P1, ...); end
    function DL.T(d, a, b, ...) P1[1], P1[2] = a, b; return d:AddText(P1, ...); end
    function DL.TF(d, a, b, c, e, f, g, ...) P1[1], P1[2], P2[1], P2[2], P3[1], P3[2] = a, b, c, e, f, g; return d:AddTriangleFilled(P1, P2, P3, ...); end
    function DL.I(d, t, a, b, c, e, f, g, h, k, ...) P1[1], P1[2], P2[1], P2[2], P3[1], P3[2], P4[1], P4[2] = a, b, c, e, f, g, h, k; return d:AddImage(t, P1, P2, P3, P4, ...); end
end
local function col(c, a) return U4(c[1], c[2], c[3], a or c[4] or 1); end
local function lerp(a, b, t) return a + (b - a) * t; end
local function mix(c1, c2, t, a) return U4(lerp(c1[1], c2[1], t), lerp(c1[2], c2[2], t), lerp(c1[3], c2[3], t), a or 1); end
local function ease(t) t = math.max(0, math.min(1, t)); return 1 - (1 - t) ^ 3; end
local function screen()
    local ds = imgui.GetIO().DisplaySize;
    return math.floor((ds and tonumber(ds.x)) or 1920), math.floor((ds and tonumber(ds.y)) or 1080);
end
local function mouse()
    local a, b = imgui.GetMousePos();
    if type(a) == 'table' then return a.x or a[1] or 0, a.y or a[2] or 0; end
    return a or 0, b or 0;
end
local function inside(mx, my, x0, y0, x1, y1) return mx >= x0 and mx < x1 and my >= y0 and my < y1; end

----------------------------------------------------------------------------------------------------
-- Fonts: the AvantGarde-style face YunaUI uses (TeX Gyre Adventor), made at a few sizes
----------------------------------------------------------------------------------------------------
local fonts = { list = {} };
local FS = 1;
local function newfont(f)
    if f == nil then return false; end
    local ok, ls = pcall(function() return f.LegacySize; end);
    return ok and ls ~= nil;
end
local function load_fonts()
    local cands = { addon.path .. 'fonts\\texgyreadventor-regular.otf',
                    vana.paths.addons .. '\\vanacore\\yunaui\\fonts\\texgyreadventor-regular.otf',
                    (os.getenv('WINDIR') or 'C:\\Windows') .. '\\Fonts\\GOTHIC.TTF',
                    (os.getenv('WINDIR') or 'C:\\Windows') .. '\\Fonts\\segoeui.ttf' };
    local file = nil;
    for _, p in ipairs(cands) do
        local f = io.open(p, 'rb');
        if f then f:close(); file = p; break; end
    end
    if file == nil then return; end
    for _, px in ipairs({ 12, 14, 17, 21, 27, 34 }) do
        local ok, font = pcall(imgui.AddFontFromFileTTF, file, px);
        if ok and font then fonts.list[#fonts.list + 1] = { font, px }; end
    end
end
-- push the face at `size` px (nearest made size at or above, scaled down a touch); returns a token for unfont().
-- Pushes nest: unfont() puts back the size that was in use before (a small tag inside a row keeps the row's size).
local FSTACK = {};
local function font(size)
    FSTACK[#FSTACK + 1] = FS;
    local list = fonts.list;
    if #list == 0 then FS = size / 13; imgui.SetWindowFontScale(FS); return false; end
    local pick = list[#list];
    for _, e in ipairs(list) do if e[2] >= size - 0.5 then pick = e; break; end end
    if newfont(pick[1]) then
        local ok = pcall(imgui.PushFont, pick[1], size);
        FS = 1;
        imgui.SetWindowFontScale(1);
        if ok then fonts.depth = (fonts.depth or 0) + 1; end
        return ok;
    end
    local ok = pcall(imgui.PushFont, pick[1]);
    if ok then fonts.depth = (fonts.depth or 0) + 1; end
    FS = ok and (size / pick[2]) or (size / 13);
    imgui.SetWindowFontScale(FS);
    return ok;
end
local function unfont(tok)
    if tok then imgui.PopFont(); fonts.depth = math.max(0, (fonts.depth or 0) - 1); end
    FS = table.remove(FSTACK) or 1;
    imgui.SetWindowFontScale(FS);
end
local function tw(s) local w = imgui.CalcTextSize(s); if type(w) == 'table' then w = w.x or w[1]; end return w or 0; end
local function text(dl, x, y, s, c, a)
    a = a or 1;
    DL.T(dl, x + 1, y + 1, U4(0, 0, 0, 0.75 * a), s);
    DL.T(dl, x, y, col(c, (c[4] or 1) * a), s);
end
-- spaced small capitals: "C O M M A N D S"
local function caps(dl, x, y, s, c, gap, a)
    local cx = x;
    for i = 1, #s do
        local ch = s:sub(i, i);
        text(dl, cx, y, ch, c, a);
        cx = cx + tw(ch) + gap;
    end
    return cx - x - gap;
end
local function caps_w(s, gap) local w = 0; for i = 1, #s do w = w + tw(s:sub(i, i)) + gap; end return w - gap; end

----------------------------------------------------------------------------------------------------
-- Pictures (images folder) and item icons (from the game's own files)
----------------------------------------------------------------------------------------------------
local texs, icons = {}, {};
local function tex_from(data, size, key, store)
    local ptr = ffi.new('IDirect3DTexture8*[1]');
    if ffi.C.D3DXCreateTextureFromFileInMemoryEx(d3d.get_device(), data, size, 0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
            ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED, ffi.C.D3DX_DEFAULT, ffi.C.D3DX_DEFAULT, 0xFF000000, nil, nil, ptr) == ffi.C.S_OK then
        local t = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', ptr[0]));
        store[key] = { tex = t, ptr = tonumber(ffi.cast('uint32_t', t)) };
    end
end
local function tex(name)
    if texs[name] ~= nil then return texs[name] or nil; end
    texs[name] = false;
    pcall(function()
        local f = io.open(addon.path .. 'images\\' .. name, 'rb');
        if f == nil then return; end
        local data = f:read('*a'); f:close();
        tex_from(data, #data, name, texs);
    end);
    return texs[name] or nil;
end
local function item_icon(id)
    if id == nil or id == 0 or id == 65535 then return nil; end
    if icons[id] ~= nil then return icons[id] or nil; end
    icons[id] = false;
    pcall(function()
        local it = AshitaCore:GetResourceManager():GetItemById(id);
        if it == nil or it.Bitmap == nil or (it.ImageSize or 0) <= 0 then return; end
        tex_from(it.Bitmap, it.ImageSize, id, icons);
    end);
    return icons[id] or nil;
end
local function image(dl, t, x0, y0, x1, y1, a)
    if t == nil then return false; end
    return (pcall(function() DL.I(dl, t.ptr, x0, y0, x1, y1, 0, 0, 1, 1, U4(1, 1, 1, a or 1)); end));
end

----------------------------------------------------------------------------------------------------
-- The game's menus (layouts after sruon's Ashita4-MenuManager, MIT)
--   CTkMenuMng:      +0x00 open windows (linked list head), +0x54 focused window, +0x7C menu area (4 x int16)
--   list node:       +0x00 next, +0x10 window, +0x14 removed flag
--   CTkMenuCtrlData: +0x04 menu data (id "menu    xxxxxxxx" at +0x46), +0x10 status (0xE closing),
--                    +0x3A rect (4 x int16), +0x4C cursor (1-based), +0x58 buttons, +0x69 draw byte (UIBegone)
----------------------------------------------------------------------------------------------------
local FLOOR = 0x10000;
pcall(ffi.cdef, [[
typedef void    (__thiscall* YM_SetCursolFn)(void* self, int32_t button, int32_t moveMouse);
typedef int32_t (__thiscall* YM_KeyDownFn)(void* self, int32_t key);
]]);
local KEY = { up = 1, down = 2, right = 3, left = 4, ok = 5, cancel = 6 };
local M = { ok = nil, tries = 0, next_try = 0, hidden = {}, wins = {}, open = {}, frame = 0 };
local function rd32(a) return ashita.memory.read_uint32(a) or 0; end
local function rd16(a) return ashita.memory.read_int16(a) or 0; end
local function rd8(a) return ashita.memory.read_uint8(a) or 0; end

function M.init()
    if M.ok then return true; end
    if M.ok == false and (M.tries >= 5 or os.clock() < M.next_try) then return false; end
    M.tries, M.next_try = M.tries + 1, os.clock() + 3;
    M.ok = false;
    local site = ashita.memory.find('FFXiMain.dll', 0, '32DBB9????????E8????????85C08944240C743A', 0, 0);
    if site == nil or site == 0 then M.err = 'menu manager pattern not found'; return false; end
    local mgr = rd32(site + 3);
    if mgr < FLOOR then M.err = 'menu manager address unreadable'; return false; end
    M.mgr = mgr;
    local kd = ashita.memory.find('FFXiMain.dll', 0, '568BF1E8????????84C0753A8BCEE8????????84C07420', 0, 0);
    local sc = ashita.memory.find('FFXiMain.dll', 0, '83EC0856578B7C24148BF16685FF7F05BF01000000668B4658', 0, 0);
    if kd and kd ~= 0 then pcall(function() M.keydown = ffi.cast('YM_KeyDownFn', kd); end); end
    if sc and sc ~= 0 then pcall(function() M.setcur = ffi.cast('YM_SetCursolFn', sc); end); end
    if M.keydown == nil or M.setcur == nil then M.err = 'menu functions not found: mouse clicks are off'; end
    M.ok = true;
    return true;
end

function M.name_of(win)
    local md = rd32(win + 0x04);
    if md < FLOOR then return ''; end
    local s = ashita.memory.read_string(md + 0x46, 16) or '';
    s = s:gsub('%z.*$', '');
    if #s > 8 then s = s:sub(9); end
    return (s:gsub('%s+$', ''));
end

-- every open window: { addr, name, cursor, buttons, closing, rect = { l, t, r, b } }
function M.scan()
    local wins, open = {}, {};
    local node, n = rd32(M.mgr), 0;
    while node >= FLOOR and n < 64 do
        n = n + 1;
        local ob = rd32(node + 0x10);
        if rd8(node + 0x14) == 0 and ob >= FLOOR then
            local w = { addr = ob, name = M.name_of(ob), cursor = rd16(ob + 0x4C), buttons = rd16(ob + 0x58),
                        status = rd32(ob + 0x10), closing = rd32(ob + 0x10) == 0xE,
                        rect = { rd16(ob + 0x3A), rd16(ob + 0x3C), rd16(ob + 0x3E), rd16(ob + 0x40) } };
            local h = M.hidden[ob];
            if h and h.rect then w.rect = h.rect; end                -- (moved below the screen by us: its real place)
            wins[#wins + 1] = w;
            open[ob] = w;
        end
        node = rd32(node);
    end
    M.wins, M.open = wins, open;
    M.focus = rd32(M.mgr + 0x54);
    M.area = { rd16(M.mgr + 0x7C), rd16(M.mgr + 0x7E), rd16(M.mgr + 0x80), rd16(M.mgr + 0x82) };
end
-- The window's buttons in screen order (top to bottom, then left to right): { button number, ... }, or nil.
-- The game numbers buttons its own way (the equipment grid down each column, the main menu its own order), so
-- each button's number and place are read from the window's draw list (CTkDrawCtrlButton: +0x00 kind (1 = button),
-- +0x2A x, +0x2C y, +0x3A number, after Ashita4-MenuManager)
M.ord = {};
function M.buttons(w)                                                -- every button: { no, x, y, shape, status }
    local btn = {};
    local node, n = rd32(w.addr + 0x14), 0;
    while node >= FLOOR and n < 128 do
        n = n + 1;
        local ob = rd32(node + 0x10);
        if rd8(node + 0x14) == 0 and ob >= FLOOR and rd16(ob) == 1 then
            local bp = M.bp[ob];                                     -- (one we moved off screen: where it really is)
            btn[#btn + 1] = { no = rd16(ob + 0x3A), x = bp and bp.x or rd16(ob + 0x2A), y = bp and bp.y or rd16(ob + 0x2C), w = rd16(ob + 0x2E), h = rd16(ob + 0x30),
                              shape = rd32(ob + 0x04), user = rd32(ob + 0x08), status = rd32(ob + 0x10), obj = ob };
        end
        node = rd32(node);
    end
    return btn;
end
function M.order(w)
    local c = M.ord[w.addr];
    local now = os.clock();
    if c and c.list and c.buttons == w.buttons and now - c.at < 0.5 then return c.list; end   -- (a failed read is tried again next frame)
    local all = M.buttons(w);
    local btn = {};
    for _, b in ipairs(all) do if b.shape ~= 0 or b.user ~= 0 then btn[#btn + 1] = b; end end   -- (only the ones the game draws:
    if #btn == 0 then btn = all; end                                                               --  hidden commands have no art)
    local list = nil;
    if #btn > 0 then
        table.sort(btn, function(p, q)
            if p.y ~= q.y then return p.y < q.y; end
            if p.x ~= q.x then return p.x < q.x; end
            return p.no < q.no;
        end);
        list = {};
        local seen = {};
        for i, b in ipairs(btn) do
            if b.no < 1 or b.no > w.buttons or seen[b.no] then list = nil; break; end
            seen[b.no] = true;
            list[i] = b.no;
        end
    end
    M.ord[w.addr] = { buttons = w.buttons, at = now, list = list };
    return list;
end
-- CatsEyeXI's main menu: 27 buttons, 24 shown. Pressing Down walks the game's cursor through these button numbers
-- (read from a recording of the game's own cursor); 13, 14 and 15 are hidden commands it never visits.
local CEXI_MAIN = { 1, 2, 3, 4, 10, 5, 6, 7, 8, 9, 11, 12, 16, 17, 18, 19, 20, 21, 22, 23, 25, 24, 26, 27 };
local function parse_order(str, max)
    local own = {};
    for _, v in ipairs(split(str)) do
        local nb = tonumber(v);
        if nb == nil or nb < 1 or nb > max then return {}; end
        own[#own + 1] = nb;
    end
    return own;
end
-- the main menu's order: learned (/cmenu learn), CatsEyeXI's own, else read from the buttons
local function main_order(w)
    local own = parse_order(cfg.main_order, w.buttons);
    if #own > 0 then return own, true; end
    if w.buttons == 27 then return CEXI_MAIN, true; end
    return M.order(w), false;
end
-- screen place (1..n) of the game's button `b`, and back
local function to_place(list, b) if list then for i, v in ipairs(list) do if v == b then return i; end end end return b; end
local function to_button(list, i) return (list and list[i]) or i; end
function M.chat_open()                                              -- (the chat line up: Ctrl there is for typing, not macros)
    local fw = M.open[M.focus or 0];
    return fw ~= nil and (fw.name == 'inline' or fw.name == 'chatctrl');
end
function M.find(name)
    for _, w in ipairs(M.wins) do if w.name == name then return w; end end
    return nil;
end
-- a window's rect on screen (menu pixels scaled to the screen), or nil
function M.to_screen(r)
    local a = M.area;
    if a == nil or r == nil then return nil; end
    local aw, ah = a[3] - a[1], a[4] - a[2];
    if aw < 64 or ah < 64 or r[3] <= r[1] or r[4] <= r[2] then return nil; end
    local sw, sh = screen();
    local sx, sy = sw / aw, sh / ah;
    return { (r[1] - a[1]) * sx, (r[2] - a[2]) * sy, (r[3] - a[1]) * sx, (r[4] - a[2]) * sy };
end

-- Hide a window for this frame (it comes back by itself once nobody asks for it)
-- (a hidden window's buttons: the game draws some menus' boxes where their buttons say, not where the window is - so
--  those move off screen too, and come back when the window does. Settings > General: "Hide old menus completely")
M.bp = {};
function M.park_buttons(w)
    local node, n = rd32(w.addr + 0x14), 0;
    while node >= FLOOR and n < 128 do
        n = n + 1;
        local ob = rd32(node + 0x10);
        if rd8(node + 0x14) == 0 and ob >= FLOOR and rd16(ob) == 1 then
            if not M.bp[ob] then M.bp[ob] = { x = rd16(ob + 0x2A), y = rd16(ob + 0x2C), win = w.addr, name = w.name }; end
            if rd16(ob + 0x2A) ~= -4000 then ashita.memory.write_uint16(ob + 0x2A, 65536 - 4000); end
            if rd16(ob + 0x2C) ~= -4000 then ashita.memory.write_uint16(ob + 0x2C, 65536 - 4000); end
        end
        node = rd32(node);
    end
end
function M.unpark(a)                                                 -- (a window's buttons back - only while it's still open)
    local w = a and M.open[a];
    for ob, v in pairs(M.bp) do
        if a == nil or v.win == a then
            local w_ = M.open[v.win];
            if w_ and w_.name == v.name then                          -- (still in the game's list, even marked closing: still there)
                pcall(function()
                    ashita.memory.write_uint16(ob + 0x2A, (v.x < 0) and (v.x + 65536) or v.x);
                    ashita.memory.write_uint16(ob + 0x2C, (v.y < 0) and (v.y + 65536) or v.y);
                end);
            end
            M.bp[ob] = nil;
        end
    end
end
function M.hide(w, mode, keep_buttons)
    local a = w.addr;
    local h = M.hidden[a];
    if h and mode and h.mode ~= mode and h.seen ~= M.frame then M.unhide(a); h = nil; end   -- (hidden another way from now on: put
                                                                     --  back first - not when two calls in one frame differ)
    if h == nil then
        h = { name = w.name, mode = mode or cfg.hide_mode };
        h.move = (h.mode == 'move' or h.mode == 'both' or h.mode == 'park');
        h.nodraw = (h.mode ~= 'move');
        if h.mode == 'park' then
            h.park = {};
            for _, off in ipairs({ 0x3A, 0x3C, 0x3E, 0x40, 0x8C, 0x8E }) do h.park[off] = ashita.memory.read_uint16(a + off); end
        end
        if h.move then
            h.y1, h.y2 = ashita.memory.read_uint16(a + 0x3C), ashita.memory.read_uint16(a + 0x8E);
            h.rect = { w.rect[1], w.rect[2], w.rect[3], w.rect[4] };
        end
        if h.nodraw then h.draw = rd8(a + 0x69); end
        M.hidden[a] = h;
    end
    h.seen = M.frame;
    if cfg.hide_buttons ~= false and not keep_buttons then pcall(M.park_buttons, w); end
    if h.park then                                                   -- (the whole box at -4000, -4000, keeping its size)
        local rw, rh = (h.rect[3] - h.rect[1]), (h.rect[4] - h.rect[2]);
        local function i16(v) if v < 0 then v = v + 65536; end return v; end
        ashita.memory.write_uint16(a + 0x3A, i16(-4000)); ashita.memory.write_uint16(a + 0x3C, i16(-4000));
        ashita.memory.write_uint16(a + 0x3E, i16(-4000 + rw)); ashita.memory.write_uint16(a + 0x40, i16(-4000 + rh));
        ashita.memory.write_uint16(a + 0x8C, i16(-4000)); ashita.memory.write_uint16(a + 0x8E, i16(-4000));
    elseif h.move then
        ashita.memory.write_uint16(a + 0x3C, 0x3000);
        ashita.memory.write_uint16(a + 0x8E, 0x3000);
    end
    if h.nodraw and h.draw ~= 0 and rd8(a + 0x69) ~= 0 then
        ashita.memory.write_uint8(a + 0x69, 0);
    end
end
function M.unhide(a)                                                 -- (one window put back as it was)
    local h = M.hidden[a];
    if not h then return; end
    local w = M.open[a];
    if w and w.name == h.name then
        pcall(function()
            if h.park then
                for off, v in pairs(h.park) do ashita.memory.write_uint16(a + off, v); end
            elseif h.move then
                ashita.memory.write_uint16(a + 0x3C, h.y1);
                ashita.memory.write_uint16(a + 0x8E, h.y2);
            end
            if h.nodraw and (h.draw or 0) ~= 0 and rd8(a + 0x69) == 0 then ashita.memory.write_uint8(a + 0x69, h.draw); end
        end);
        if h.rect then w.rect = h.rect; end
    end
    M.hidden[a] = nil;
end
-- Give back every window not hidden this frame (all = every one)
function M.release(all)
    for a, h in pairs(M.hidden) do
        if all or h.seen ~= M.frame then
            local w = M.open[a];
            if w and w.name == h.name then                           -- (still open: put it back as it was)
                pcall(function()
                    if h.park then
                        for off, v in pairs(h.park) do ashita.memory.write_uint16(a + off, v); end
                    elseif h.move then
                        ashita.memory.write_uint16(a + 0x3C, h.y1);
                        ashita.memory.write_uint16(a + 0x8E, h.y2);
                    end
                    if h.nodraw and (h.draw or 0) ~= 0 and rd8(a + 0x69) == 0 then
                        ashita.memory.write_uint8(a + 0x69, h.draw);
                    end
                end);
            end
            M.unpark(a);
            M.hidden[a] = nil;
        end
    end
end

-- chadcoremenu-dump.txt, written by itself: the main menu's buttons the first time it opens, then each cursor move
-- (so the order can be checked without typing anything). Stops after 300 lines; /cmenu trace off turns it off.
M.tr = { lines = 0 };
function M.trace(w)
    local T = M.tr;
    if T.lines > 300 then return; end
    local out = {};
    if not T.head then
        T.head = true;
        out[#out + 1] = ('ChadcoreMenu %s  %s'):format(addon.version, os.date());
        out[#out + 1] = ('main menu "%s"  buttons %d  cursor %d  rect %d,%d %d,%d'):format(w.name, w.buttons, w.cursor, w.rect[1], w.rect[2], w.rect[3], w.rect[4]);
        local mp = rd32(w.addr + 0x0C);
        if mp >= FLOOR then
            local f = {};
            for off = 0x16, 0x2A, 2 do f[#f + 1] = tostring(rd16(mp + off)); end
            out[#out + 1] = 'list fields (col page start end top count scroll last h x y): ' .. table.concat(f, ' ');
        end
        for _, b in ipairs(M.buttons(w)) do
            out[#out + 1] = ('  button %2d  x %4d y %4d  w %3d h %3d  shape %08X user %08X status %08X'):format(b.no, b.x, b.y, b.w, b.h, b.shape, b.user, b.status);
        end
        local o = M.order(w);
        out[#out + 1] = 'order read from the buttons: ' .. (o and table.concat(o, ',') or '(none)');
        out[#out + 1] = 'cursor moves:';
        T.last = nil;
    end
    if T.last ~= w.cursor then
        T.last = w.cursor;
        out[#out + 1] = ('  %.2f  cursor %d'):format(os.clock(), w.cursor);
    end
    if #out == 0 then return; end
    T.lines = T.lines + #out;
    local f = io.open(addon.path .. 'chadcoremenu-dump.txt', T.opened and 'a' or 'w');
    T.opened = true;
    if f then f:write(table.concat(out, '\n') .. '\n'); f:close(); end
end

-- chadcoremenu-survey.txt: each time a game window opens (its id, buttons with their places, list numbers) and each
-- time the focused window's cursor or scroll moves. It's how new menus get mapped without screenshots. Stops at
-- 30000 lines; /cmenu survey off turns it off.
M.sv = { lines = 0, known = {}, focus = nil, cur = nil, at = 0 };
local function list_fields(w)
    local mp = rd32(w.addr + 0x0C);
    if mp < FLOOR then return nil; end
    local f = {};
    for off = 0x16, 0x2A, 2 do f[#f + 1] = rd16(mp + off); end
    return f;                                                        -- col page start end top count scroll last h x y
end
-- one line in the survey whenever a panel's state changes (why it took over or not)
M.notes = {};
function M.note(key, txt)
    if M.notes[key] == txt then return; end
    M.notes[key] = txt;
    if not cfg.survey then return; end
    local f = io.open(addon.path .. 'chadcoremenu-survey.txt', 'a');
    if f then f:write(('%.2f PANEL %s: %s\n'):format(os.clock(), key, txt)); f:close(); end
end
function M.survey()
    local S = M.sv;
    if S.lines > 30000 then return; end
    local now = os.clock();
    if now - S.at < 0.05 then return; end
    S.at = now;
    local out = {};
    local open_now = {};
    for _, w in ipairs(M.wins) do
        open_now[w.addr] = true;
        if not S.known[w.addr] then
            S.known[w.addr] = w.name;
            out[#out + 1] = ('%.2f OPEN "%s" addr %08X buttons %d cursor %d rect %d,%d %d,%d%s'):format(now, w.name, w.addr, w.buttons,
                w.cursor, w.rect[1], w.rect[2], w.rect[3], w.rect[4], (w.addr == M.focus) and ' FOCUSED' or '');
            local lf = list_fields(w);
            if lf then out[#out + 1] = '    list: ' .. table.concat(lf, ' '); end
            -- (the quest and Records of Eminence screens: what their list memory holds, once a window name - to find the
            --  quest numbers and the progress figures in it, for drawing them ourselves)
            if w.name == 'link4' or w.name == 'link13' or w.name == 'link12' then   -- (which pearl our list had lit as the game went on)
                out[#out + 1] = ('    linkshell picked on our list: %s'):format(LNK.sel and (LNK.sel.name .. (LNK.sel.no and (' No.' .. LNK.sel.no) or '')) or '-');
            end
            if cfg.survey_mem ~= false and (w.name:find('^quest') or w.name:find('^evitem') or w.name:find('^roe') or w.name:find('^emin') or w.name:find('^faq') or w.name == 'link12' or w.name == 'link6') then
                S.dumped = S.dumped or {};
                local dk = w.name .. ':' .. w.buttons .. ':' .. ((w.name == 'link12') and tostring(math.floor(os.clock())) or '');
                if not S.dumped[dk] then
                    S.dumped[dk] = true;
                    pcall(function()
                        local mp = rd32(w.addr + 0x0C);
                        local blob = (mp >= FLOOR) and MCR.read(mp, (w.name == 'link12') and 0x6000 or 0x1000) or nil;
                        if blob then out[#out + 1] = ('    listmem %08X: %s'):format(mp, (blob:gsub('.', function(c) return ('%02X'):format(c:byte()); end))); end
                        local wb = MCR.read(w.addr, 0x200);
                        if wb then out[#out + 1] = ('    winmem: %s'):format((wb:gsub('.', function(c) return ('%02X'):format(c:byte()); end))); end
                    end);
                end
            end
            for _, b in ipairs(M.buttons(w)) do
                out[#out + 1] = ('    button %2d  x %4d y %4d  w %3d h %3d  art %s  status %X'):format(b.no, b.x, b.y, b.w, b.h,
                    (b.shape ~= 0 or b.user ~= 0) and 'yes' or 'no', b.status);
            end
        end
    end
    for a, name in pairs(S.known) do
        if not open_now[a] then out[#out + 1] = ('%.2f CLOSE "%s"'):format(now, name); S.known[a] = nil; end
    end
    local fw = M.open[M.focus or 0];
    if fw and (fw.name == 'query' or fw.name == 'mogdoor') then        -- (a question box's list header as it changes: where it keeps its scroll)
        pcall(function()
            local h = MCR.read(rd32(fw.addr + 0x0C), 0x60);
            local wh = MCR.read(fw.addr, 0x100);
            local key = (h or '') .. (wh or '');
            if key ~= S.qhdr and (S.qn or 0) < 300 then
                S.qhdr = key; S.qn = (S.qn or 0) + 1;
                local hx = function(b) return b and (b:gsub('.', function(ch) return ('%02X'):format(ch:byte()); end)) or '-'; end;
                out[#out + 1] = ('%.2f   %s cursor %d header %s window %s'):format(now, fw.name, fw.cursor, hx(h), hx(wh));
            end
        end);
    end
    if fw then
        local lf = list_fields(fw);
        local key = fw.addr .. ':' .. fw.cursor .. ':' .. (lf and (lf[5] .. '/' .. lf[6]) or '');
        if key ~= S.cur then
            S.cur = key;
            out[#out + 1] = ('%.2f   focus "%s" cursor %d%s'):format(now, fw.name, fw.cursor,
                lf and ('  top %d count %d page %d'):format(lf[5], lf[6], lf[2]) or '');
        end
    end
    if #out == 0 then return; end
    S.lines = S.lines + #out;
    local f = io.open(addon.path .. 'chadcoremenu-survey.txt', S.opened and 'a' or 'w');
    if f then
        if not S.opened then f:write(('ChadcoreMenu %s survey  %s\n'):format(addon.version, os.date())); end
        local first = not S.opened;
        S.opened = true;
        f:write(table.concat(out, '\n') .. '\n'); f:close();
        if first then GAMEUI_LOG(); pcall(QST.ask); end              -- (once a session: what VanaCore's interface API offers; the Records asked for)
    end
end

-- Mouse actions run at the start of the next frame, through the game's own functions
function M.act(win, button, key)
    M.queue = { win = win, btn = button, key = key };
end
function M.run_queue()
    local q = M.queue;
    M.queue = nil;
    if q == nil or not cfg.clicks then return; end
    local w = q.win and M.open[q.win] or nil;
    if q.win and (w == nil or w.closing) then return; end
    local ok, err = pcall(function()
        if w and q.btn and M.setcur and q.btn >= 1 and q.btn <= w.buttons then
            M.setcur(ffi.cast('void*', w.addr), q.btn, 0);
        end
        local fwq = M.open[M.focus or 0];
        if q.key and M.keydown and fwq and (q.win == nil or M.focus == q.win) then
            M.keydown(ffi.cast('void*', M.mgr), q.key);
            M.auto_t = os.clock();                                   -- (a key ChadcoreMenu pressed itself: not for learning your buttons)
        end
    end);
    if not ok then errlog('click', err); end
end

----------------------------------------------------------------------------------------------------
-- Shared drawing pieces
----------------------------------------------------------------------------------------------------
-- A YunaUI panel: soft shadow, near-black violet body, thin violet edge, pink-to-violet line along the top
local function panel(dl, x0, y0, x1, y1, a, s)
    local r = 10 * s;
    for i = 4, 1, -1 do DL.RF(dl, x0 - i * 2, y0 - i * 2 + 3, x1 + i * 2, y1 + i * 2 + 3, U4(0, 0, 0, 0.06 * a), r + i * 2); end
    DL.RF(dl, x0, y0, x1, y1, U4(C.pbg[1], C.pbg[2], C.pbg[3], cfg.alpha * a), r);
    local top, bot = U4(0.62, 0.40, 1.0, 0.07 * a), U4(0.62, 0.40, 1.0, 0.0);
    DL.RFM(dl, x0 + 2, y0 + 2, x1 - 2, y0 + (y1 - y0) * 0.35, top, top, bot, bot);
    DL.R(dl, x0, y0, x1, y1, U4(0.62, 0.40, 1.0, 0.28 * a), r, 0, 1);
    local p1, p2 = col(C.pink, 0.95 * a), col(C.vio, 0.95 * a);
    DL.RFM(dl, x0 + 14 * s, y0, x1 - 14 * s, y0 + 2, p1, p2, p2, p1);
    local g1, g2 = col(C.pink, 0.0), col(C.pink, 0.16 * a);
    DL.RFM(dl, x0 + 14 * s, y0 + 2, x1 - 14 * s, y0 + 10 * s, g2, U4(C.vio[1], C.vio[2], C.vio[3], 0.16 * a), g1, g1);
    pcall(PANEL_GRIP, dl, x0, y0, x1, y1, a, s);
end
-- A thin living bar (YunaUI's glow bar, lighter)
local function bar(dl, x, y, w, h, v, c1, c2, a, seed)
    v = math.max(0, math.min(1, v or 0));
    DL.RF(dl, x, y, x + w, y + h, U4(0.05, 0.04, 0.07, 0.85 * a), h / 2);
    if v <= 0 then return; end
    local fw = math.max(h, w * v);
    DL.RF(dl, x - 1, y - 2, x + fw + 1, y + h + 2, col(c1, 0.12 * a), h);   -- (the glow)
    DL.RFM(dl, x, y, x + fw, y + h, col(c1, a), col(c2, a), col(c2, a), col(c1, a));
    DL.RF(dl, x + 1, y, x + fw - 1, y + math.max(1, h * 0.35), U4(1, 1, 1, 0.22 * a), h / 2);
    if cfg.anim then                                                 -- (a sheen gliding along now and then)
        local t = (os.clock() * 0.35 + (seed or 0) * 0.37) % 1.6;
        if t < 1 then
            local sx = x + fw * t;
            local s0, s1 = math.max(x, sx - 18), math.min(x + fw, sx + 18);
            if s1 > s0 then
                local c0, cm = U4(1, 1, 1, 0), U4(1, 1, 1, 0.35 * a);
                local mid = (s0 + s1) / 2;
                DL.RFM(dl, s0, y, mid, y + h, c0, cm, cm, c0);
                DL.RFM(dl, mid, y, s1, y + h, cm, c0, c0, cm);
            end
        end
    end
end
-- a glowing selection frame (pulsing pink-to-violet)
local function sel_frame(dl, x0, y0, x1, y1, r, a)
    local p = cfg.anim and (0.5 + 0.5 * math.sin(os.clock() * 4)) or 0.7;
    for i = 3, 1, -1 do DL.R(dl, x0 - i, y0 - i, x1 + i, y1 + i, mix(C.pink, C.vio, p, (0.10 + 0.05 * p) * a), r + i, 0, 2); end
    DL.R(dl, x0, y0, x1, y1, mix(C.pink, C.vio, p, 0.95 * a), r, 0, 1.6);
end

----------------------------------------------------------------------------------------------------
-- The main menu (Commands)
----------------------------------------------------------------------------------------------------
local MAIN = {
    { 'Status',        'Your attributes, jobs and experience.' },
    { 'Equipment',     'Change the gear you are wearing.' },
    { 'Magic',         'Cast spells you know.' },
    { 'Items',         'Use or look at your items.' },
    { 'Synthesis',     'Craft with a crystal.' },
    { 'Abilities',     'Job abilities, weapon skills and more.' },
    { 'Party',         'Invite, leave or manage your party.' },
    { 'Trade',         'Trade with your target.' },
    { 'Search',        'Find other adventurers.' },
    { 'Linkshell',     'Your linkshells and pearls.' },
    { 'Region Info',   'Who holds each region, and its rates.' },
    { 'Map',           'The map of this area.' },
    { 'Missions',      'Your mission progress.' },
    { 'Quests',        'Quests by region.' },
    { 'Key Items',     'Important things you carry.' },
    { 'View House',    'Your Mog House.' },
    { 'Bazaar',        'Set up your bazaar.' },
    { 'Macros',        'Edit your macro palettes.' },
    { 'Config',        'Game settings.' },
    { 'Help Desk',     'Help, reports and the GM call.' },
    { 'Current Time',  'Vana\'diel and Earth time.' },
    { 'Communication', 'Mail, chat filters, blacklist.' },
    { 'Shut Down',     'Close the game.' },
    { 'Log Out',       'Return to the title screen.' },
};
local MAIN_BREAKS = { [6] = true, [10] = true, [15] = true, [19] = true };   -- thin lines between groups
local UI = { main = { y = nil, t0 = nil, warned = false }, char = { t0 = nil }, drag = nil, move = false };
-- (each panel's size: the overall Size times its own, set by dragging its corner while panels are unlocked)
function PSCALE() return (tonumber(cfg.scale) or 1) * (UI.pmul or 1); end
-- the resize corner (bottom right, while panels are unlocked): drag it to make that panel bigger or smaller
function PANEL_GRIP(dl, x0, y0, x1, y1, a, s)
    local key = UI.pwhere;
    if not key then return; end
    local rs = UI.rs;
    if cfg.locked and not (rs and rs.key == key) then return; end
    local g = 14 * s;
    local mx, my = imgui.GetMousePos();
    if type(mx) == 'table' then mx, my = mx.x or mx[1], mx.y or mx[2]; end
    local over = mx and mx >= x1 - g and mx <= x1 + 2 and my >= y1 - g and my <= y1 + 2 and imgui.IsWindowHovered();
    local c_ = (over or (rs and rs.key == key)) and col(C.pink, a) or col(C.vio, 0.55 * a);
    for i = 1, 3 do                                                  -- (three little diagonal lines)
        local d = i * 4 * s;
        DL.L(dl, x1 - d - 2 * s, y1 - 3 * s, x1 - 3 * s, y1 - d - 2 * s, c_, 1.4 * s);
    end
    if over and not rs then
        pcall(imgui.SetTooltip, 'Drag to resize this panel (right-click: back to normal)');
        if imgui.IsMouseClicked(0) then
            UI.rs = { key = key, mx = mx, w = math.max(40, x1 - x0), m = UI.pmul or 1, move = UI.move, f = os.clock() };
            UI.move = true;                                          -- (no clicks on the panel's rows meanwhile)
        elseif imgui.IsMouseClicked(1) then
            cfg['sz_' .. key] = nil; pcall(save);
        end
    end
    rs = UI.rs;
    if rs and rs.key == key then
        if imgui.IsMouseDown(0) or os.clock() - (rs.f or 0) < 0.05 then
            local m = rs.m * (rs.w + (mx - rs.mx)) / rs.w;
            cfg['sz_' .. key] = math.floor(math.max(0.5, math.min(2.5, m)) * 100 + 0.5) / 100;
        else
            UI.move = rs.move; UI.rs = nil; pcall(save);
        end
    end
end

local function main_labels(n)
    local own = split(cfg.labels);
    local out, breaks = {}, MAIN_BREAKS;
    if #own > 0 then breaks = {}; end
    for i = 1, n do
        if #own > 0 then out[i] = { own[i] or ('Command ' .. i), '' };
        else out[i] = MAIN[i] or { 'Command ' .. i, '' }; end
    end
    return out, breaks;
end

local NOFRAME = nil;
local function win_flags()
    if NOFRAME == nil then
        NOFRAME = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoResize, ImGuiWindowFlags_NoScrollbar,
            ImGuiWindowFlags_NoCollapse, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoSavedSettings,
            ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoMove,
            ImGuiWindowFlags_NoScrollWithMouse or 0);
    end
    return NOFRAME;
end
-- where a panel goes: on the game's window (follow), your own spot, or a default
local function place(key, w, h, native, anchor, dx, dy)
    local sw, sh = screen();
    local x, y;
    local cx, cy = tonumber(cfg[key .. '_x']) or -1, tonumber(cfg[key .. '_y']) or -1;
    if cx >= 0 then x, y = cx, cy;
    elseif native then
        if anchor == 'right' then x, y = native[3] - w, native[2]; else x, y = native[1], native[2]; end
    elseif cx >= 0 then x, y = cx, cy;
    else x, y = dx, dy; end
    x = math.max(4, math.min(sw - w - 4, x));
    y = math.max(4, math.min(sh - h - 4, y));
    return math.floor(x), math.floor(y);
end
-- a panel's own place, or where it was dragged to (kept on screen)
local function saved_pos(key, x, y, w, h)
    local cx, cy = tonumber(cfg[key .. '_x']) or -1, tonumber(cfg[key .. '_y']) or -1;
    if cx >= 0 then x, y = cx, cy; end
    local sw, sh = screen();
    return math.floor(math.max(4, math.min(sw - w - 4, x))), math.floor(math.max(4, math.min(sh - h - 4, y)));
end
-- dragging a panel by its header (not over its buttons in the right corner) while panels are unlocked
local function drag(key, x, y, hx0, hy0, hx1, hy1)
    if cfg.locked and not UI.move then UI.drag = nil; return x, y; end
    local mx, my = mouse();
    local s_ = PSCALE();
    if UI.drag == nil and imgui.IsMouseClicked(0) and inside(mx, my, hx0, hy0, hx1 - 60 * s_, hy1) and imgui.IsWindowHovered() then
        UI.drag = { key = key, ox = mx - x, oy = my - y };
    end
    if UI.drag and UI.drag.key == key then
        if imgui.IsMouseDown(0) then
            x, y = math.floor(mx - UI.drag.ox), math.floor(my - UI.drag.oy);
            cfg[key .. '_x'], cfg[key .. '_y'] = x, y;
        else
            UI.drag = nil;
            save();
        end
    end
    return x, y;
end
-- the lock in a panel's corner: closed = locked; a click switches every panel
local function lock_button(dl, x, y, s, a, hov_win)
    local mx, my = mouse();
    local w_, h_ = 16 * s, 16 * s;
    local hv = hov_win and inside(mx, my, x - 2 * s, y - 2 * s, x + w_ + 2 * s, y + h_ + 2 * s);
    local c_ = hv and col(C.pink, a) or (cfg.locked and col(C.muted, a) or col(C.acc, a));
    local bx0, by0, bx1, by1 = x + 3 * s, y + 7 * s, x + 13 * s, y + 15 * s;
    DL.RF(dl, bx0, by0, bx1, by1, c_, 2 * s);                        -- the body
    local sx0, sx1 = x + 5 * s, x + 11 * s;                          -- the shackle: open (lifted to one side) when unlocked
    local top = y + 2 * s;
    if cfg.locked then
        DL.L(dl, sx0, by0, sx0, top + 2 * s, c_, 1.6 * s); DL.L(dl, sx1, by0, sx1, top + 2 * s, c_, 1.6 * s);
        DL.L(dl, sx0, top + 2 * s, sx0 + 1 * s, top, c_, 1.6 * s); DL.L(dl, sx1, top + 2 * s, sx1 - 1 * s, top, c_, 1.6 * s);
        DL.L(dl, sx0 + 1 * s, top, sx1 - 1 * s, top, c_, 1.6 * s);
    else
        DL.L(dl, sx1, by0, sx1, top + 2 * s, c_, 1.6 * s);
        DL.L(dl, sx1, top + 2 * s, sx1 + 1 * s, top, c_, 1.6 * s); DL.L(dl, sx1 + 1 * s, top, sx1 + 6 * s, top, c_, 1.6 * s);
        DL.L(dl, sx1 + 6 * s, top, sx1 + 7 * s, top + 2 * s, c_, 1.6 * s);
    end
    if hv then
        pcall(imgui.SetTooltip, cfg.locked and 'Locked: click to unlock and move the menus' or 'Drag a menu by its top.  Click to lock them');
        if imgui.IsMouseClicked(0) then cfg.locked = not cfg.locked; save(); end
    end
end

local function draw_main(w)
    local s = PSCALE();
    local ord, learned = main_order(w);
    local rows = ord and #ord or w.buttons;
    if ord == nil and #split(cfg.labels) == 0 then rows = math.min(rows, #MAIN); end
    local items, breaks = main_labels(math.max(1, rows));
    if #items ~= #MAIN and #split(cfg.labels) == 0 and not learned and not UI.main.warned then
        UI.main.warned = true;
        msg(('The main menu shows %d commands here (ChadcoreMenu knows %d). If the order is off: /cmenu learn'):format(#items, #MAIN));
    end
    local n = #items;
    local ngame = n;                                                 -- (ChadcoreMenu's own "UI Settings" row at the bottom)
    if cfg.settings_row ~= false and SET then
        local it2 = {}; for i = 1, n do it2[i] = items[i]; end
        local br2 = {}; for k_, v_ in pairs(breaks) do br2[k_] = v_; end
        it2[n + 1] = { 'UI Settings', 'ChadcoreMenu: size, colours, menus.' };
        br2[n] = true;
        items, breaks, n = it2, br2, n + 1;
    end
    UI.main.ngame, UI.main.ord, UI.main.addr = ngame, ord, w.addr;
    if UI.main.setsel and (M.focus ~= w.addr or n == ngame) then UI.main.setsel = false; end
    local RH, HEAD, PAD = math.floor(23 * s), math.floor(46 * s), math.floor(10 * s);
    local nb = 0; for i = 1, n - 1 do if breaks[i] then nb = nb + 1; end end
    local hint = cfg.hint and math.floor(40 * s) or 0;
    local W = math.floor(232 * s);
    local LOGO = (cfg.logo ~= false) and math.floor(W - 12 * s) or 0;  -- (as wide as the menu)      -- (the animated Chadbrowick logo under the rows)
    local H = HEAD + n * RH + nb * math.floor(7 * s) + PAD + LOGO + hint + PAD;
    local native = cfg.follow and M.to_screen(w.rect) or nil;
    local sw = screen();
    local x, y = place('main', W, H, native, 'right', sw - W - 24, 110);

    local now = os.clock();
    UI.main.t0 = UI.main.t0 or now;
    local k = cfg.anim and ease((now - UI.main.t0) / 0.20) or 1;
    local focused = (M.focus == w.addr);
    local a = k * (focused and 1 or 0.72);
    x = x + math.floor((1 - k) * 16 * s);

    imgui.SetNextWindowPos({ x, y }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ W + 8, H + 8 }, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    UI.pushed = 2;
    local opened = imgui.Begin('##ym_main', { true }, win_flags());
    UI.began = true;
    if opened then
        local dl = imgui.GetWindowDrawList();
        x, y = drag('main', x, y, x, y, x + W, y + HEAD);
        local hov_win = imgui.IsWindowHovered();
        panel(dl, x, y, x + W, y + H, a, s);
        -- header: COMMANDS, your name, a live dot
        local tk = font(12 * s);
        caps(dl, x + 16 * s, y + 10 * s, 'COMMANDS', C.acc, 2.5 * s, a);
        unfont(tk);
        tk = font(17 * s);
        local nm = '';
        pcall(function() nm = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0) or ''; end);
        text(dl, x + 16 * s, y + 23 * s, nm, C.text, a);
        unfont(tk);
        local pulse = 0.6 + 0.4 * math.sin(now * 3);
        lock_button(dl, x + W - 46 * s, y + 8 * s, s, a, hov_win);
        DL.CF(dl, x + W - 18 * s, y + 16 * s, 6 * s, U4(0.35, 1.0, 0.55, 0.18 * pulse * a), 16);
        DL.CF(dl, x + W - 18 * s, y + 16 * s, 3 * s, U4(0.45, 1.0, 0.62, a), 12);
        if UI.move then
            tk = font(12 * s); text(dl, x + W - 70 * s, y + 26 * s, 'DRAG ME', C.pink, a); unfont(tk);
        end
        -- rows
        local cur = nil;
        if ord then for i, v in ipairs(ord) do if v == w.cursor then cur = i; end end end
        if cur == nil then cur = (ord == nil) and w.cursor or (UI.main.cur or 1); end
        cur = math.max(1, math.min(ngame, cur));
        UI.main.gcur = cur;
        if UI.main.setsel then cur = n; end
        UI.main.cur = cur;
        UI.main.label = items[cur] and items[cur][1] or nil;
        UI.mainbox = { x, y, W, H };
        local ry, rows = y + HEAD, {};
        for i = 1, n do
            rows[i] = ry;
            ry = ry + RH;
            if breaks[i] and i < n then ry = ry + math.floor(7 * s); end
        end
        local target = rows[cur];
        UI.main.y = (UI.main.y == nil or not cfg.anim) and target or lerp(UI.main.y, target, math.min(1, 0.35 * 60 * (UI.dt or 0.016)));
        local mx, my = mouse();
        local hover = nil;
        if hov_win and not UI.move then
            for i = 1, n do if inside(mx, my, x + 6 * s, rows[i], x + W - 6 * s, rows[i] + RH) then hover = i; end end
        end
        -- the selection band, sliding to the cursor
        do
            local by = UI.main.y;
            local p1, p2 = col(C.pink, 0.34 * a), U4(C.vio[1], C.vio[2], C.vio[3], 0.0);
            DL.RFM(dl, x + 8 * s, by + 1, x + W - 8 * s, by + RH - 1, p1, p2, p2, p1);
            DL.RF(dl, x + 8 * s, by + 3, x + 10.5 * s, by + RH - 3, col(C.pink, a), 2);
            DL.RF(dl, x + 6 * s, by + 1, x + 13 * s, by + RH - 1, col(C.pink, 0.18 * a), 4);
            local ar = tex('sel_arrow.png');
            local bob = cfg.anim and math.sin(now * 5) * 1.5 * s or 0;
            local asz = RH * 0.62;
            if not image(dl, ar, x - asz * 0.55 + bob, by + (RH - asz) / 2, x + asz * 0.45 + bob, by + (RH + asz) / 2, a) then
                DL.TF(dl, x - 4 * s + bob, by + 5 * s, x - 4 * s + bob, by + RH - 5 * s, x + 6 * s + bob, by + RH / 2, col(C.pink, a));
            end
        end
        tk = font(15.5 * s);
        for i = 1, n do
            local yy = rows[i];
            if hover == i and i ~= cur then DL.RF(dl, x + 8 * s, yy + 1, x + W - 8 * s, yy + RH - 1, U4(1, 1, 1, 0.05 * a), 4 * s); end
            local sel = (i == cur);
            local tx = x + (sel and 24 or 20) * s;
            local ty = yy + (RH - imgui.GetTextLineHeight()) / 2;
            DL.CF(dl, x + 14.5 * s, yy + RH / 2, (sel and 0 or 1.5) * s, col(C.dim, a), 8);
            text(dl, tx, ty, items[i][1], sel and C.text or (hover == i and { 0.85, 0.83, 0.93, 1 } or C.muted), a);
            if breaks[i] and i < n then
                local ly = yy + RH + math.floor(3.5 * s);
                DL.RFM(dl, x + 16 * s, ly, x + W - 16 * s, ly + 1, U4(1, 1, 1, 0.07 * a), U4(1, 1, 1, 0.0), U4(1, 1, 1, 0.0), U4(1, 1, 1, 0.07 * a));
            end
        end
        unfont(tk);
        -- the logo: 90 frames of 204 px, 10 to a row on a 2048 px sheet, 60 ms each; round (nothing outside its circle)
        if LOGO > 0 then
            -- (in two layers: the logo with its purple greyed, then the purple parts alone, tinted the menu's colour)
            local lt, lk = tex('logo_base.png'), tex('logo_tint.png');
            if lt then
                local fi = math.floor(now / 0.06) % 90;
                local cw = 204 / 2048;
                local u0, v0 = (fi % 10) * cw, math.floor(fi / 10) * cw;
                local sz = LOGO - 8 * s;
                local lx = x + (W - sz) / 2;
                local ly = ry + 2 * s;
                local mxl, myl = mouse();
                local lhov = hov_win and not UI.move and inside(mxl, myl, lx, ly, lx + sz, ly + sz);
                pcall(function() DL.I(dl, lt.ptr, lx, ly, lx + sz, ly + sz, u0, v0, u0 + cw, v0 + cw, U4(1, 1, 1, a)); end);
                if lhov then                                         -- (a click on the logo: refresh the UI)
                    pcall(imgui.SetTooltip, 'Click to refresh the UI');
                    if imgui.IsMouseClicked(0) then SET.refresh(); end
                end
                if lk then
                    local tr, tg, tb = C.pink[1], C.pink[2], C.pink[3];   -- (the menu's highlight colour)
                    local tm = math.max(tr, tg, tb, 0.01);
                    pcall(function() DL.I(dl, lk.ptr, lx, ly, lx + sz, ly + sz, u0, v0, u0 + cw, v0 + cw, U4(tr / tm, tg / tm, tb / tm, a)); end);
                end
            end
        end
        -- the selected command's description
        if hint > 0 then
            local hy = y + H - PAD - hint;
            DL.RF(dl, x + 10 * s, hy, x + W - 10 * s, hy + hint, U4(0, 0, 0, 0.28 * a), 6 * s);
            tk = font(12 * s);
            local shown = items[hover or cur] or { '', '' };
            caps(dl, x + 18 * s, hy + 6 * s, (shown[1] or ''):upper(), C.acc, 1.5 * s, a);
            text(dl, x + 18 * s, hy + 21 * s, shown[2] or '', C.muted, a);
            unfont(tk);
        end
        -- mouse: click = go there and OK, right-click = back, wheel = move
        if hov_win and not UI.move then
            if hover and hover > ngame and imgui.IsMouseClicked(0) then
                SET.toggle(true);
            elseif hover and imgui.IsMouseClicked(0) then
                local kind = cfg.browse and BROWSE_KIND and BROWSE_KIND[items[hover][1]] or nil;
                if kind == 'status' and cfg.statcmd ~= false then kind = nil; end   -- (Status: the game's screen, with ChadcoreMenu's list and pages)
                if kind then UI.browse = { kind = kind, via = 'main', t0 = os.clock() };   -- (ChadcoreMenu's own panel)
                else M.act(w.addr, to_button(ord, hover), KEY.ok); end
            end
            if imgui.IsMouseClicked(1) then M.act(nil, nil, KEY.cancel); end
            local wheel = imgui.GetIO().MouseWheel or 0;
            if cfg.wheel and wheel ~= 0 and focused then
                UI.main.setsel = false;
                local to = math.min(cur, ngame) - (wheel > 0 and 1 or -1);
                if to < 1 then to = ngame elseif to > ngame then to = 1 end
                M.act(w.addr, to_button(ord, to), nil);
            end
        end
    end
    imgui.End();
    UI.began = false;
    imgui.PopStyleVar(2);
    UI.pushed = 0;
end

----------------------------------------------------------------------------------------------------
-- Status / Equipment: one character panel
----------------------------------------------------------------------------------------------------
local JOBS = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG', 'SAM', 'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP', 'DNC', 'SCH', 'GEO', 'RUN' };
-- the game's equipment order (its 16 buttons): slot ids
local GRID = { 0x00, 0x01, 0x02, 0x03, 0x04, 0x09, 0x0B, 0x0C, 0x05, 0x06, 0x0D, 0x0E, 0x0F, 0x0A, 0x07, 0x08 };
local SLOTN = { [0] = 'Main', 'Sub', 'Range', 'Ammo', 'Head', 'Body', 'Hands', 'Legs', 'Feet', 'Neck', 'Waist', 'Ear', 'Ear', 'Ring', 'Ring', 'Back' };
local SLOTS = { [0] = 'MAIN', 'SUB', 'RANGE', 'AMMO', 'HEAD', 'BODY', 'HANDS', 'LEGS', 'FEET', 'NECK', 'WAIST', 'EAR', 'EAR', 'RING', 'RING', 'BACK' };
local WARDROBE = { [8] = 1, [10] = 2, [11] = 3, [12] = 4, [13] = 5, [14] = 6, [15] = 7, [16] = 8 };
local STATS = { 'STR', 'DEX', 'VIT', 'AGI', 'INT', 'MND', 'CHR' };
-- resistances as the game's window lays them out: Fire Wind Thunder Light / Ice Earth Water Dark
local ELEM = {
    { 0, 'Fire',    { 1.00, 0.36, 0.30 } }, { 2, 'Wind',  { 0.40, 0.95, 0.50 } }, { 4, 'Thunder', { 0.80, 0.50, 1.00 } }, { 6, 'Light', { 1.00, 1.00, 0.95 } },
    { 1, 'Ice',     { 0.50, 0.85, 1.00 } }, { 3, 'Earth', { 1.00, 0.85, 0.30 } }, { 5, 'Water',   { 0.35, 0.50, 1.00 } }, { 7, 'Dark',  { 0.45, 0.40, 0.55 } },
};

local function char_data()
    local d = { stats = {}, mods = {}, res = {} };
    local mm = AshitaCore:GetMemoryManager();
    pcall(function()
        local pt, pl = mm:GetParty(), mm:GetPlayer();
        d.name = pt:GetMemberName(0) or '';
        d.hp, d.mp, d.tp = pt:GetMemberHP(0) or 0, pt:GetMemberMP(0) or 0, pt:GetMemberTP(0) or 0;
        d.hpp, d.mpp = (pt:GetMemberHPPercent(0) or 0) / 100, (pt:GetMemberMPPercent(0) or 0) / 100;
        d.job, d.lv = pl:GetMainJob() or 0, pl:GetMainJobLevel() or 0;
        d.sjob, d.slv = pl:GetSubJob() or 0, pl:GetSubJobLevel() or 0;
    end);
    pcall(function() local pl = mm:GetPlayer(); d.hpmax, d.mpmax = pl:GetHPMax(), pl:GetMPMax(); end);
    pcall(function() local pl = mm:GetPlayer(); for i = 1, 7 do d.stats[i] = pl:GetStat(i - 1); d.mods[i] = pl:GetStatModifier(i - 1); end end);
    pcall(function() local pl = mm:GetPlayer(); d.atk, d.def = pl:GetAttack(), pl:GetDefense(); end);
    pcall(function() local pl = mm:GetPlayer(); for i = 0, 7 do d.res[i] = pl:GetResist(i); end end);
    if (d.hpmax or 0) > 0 then d.hpp = (d.hp or 0) / d.hpmax; end
    if (d.mpmax or 0) > 0 then d.mpp = (d.mp or 0) / d.mpmax; end
    return d;
end
local GEAR = { at = 0, slots = {} };
local function gear()
    local now = os.clock();
    if now - GEAR.at < 0.2 then return GEAR.slots; end
    GEAR.at = now;
    local out = {};
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        for _, slot in ipairs(GRID) do
            local e = inv:GetEquippedItem(slot);
            if e ~= nil and (e.Index or 0) ~= 0 then
                local bag, idx = bit.rshift(bit.band(e.Index, 0xFF00), 8), bit.band(e.Index, 0xFF);
                local it = inv:GetContainerItem(bag, idx);
                if it ~= nil and it.Id ~= 0 and it.Id ~= 65535 then out[slot] = { id = it.Id, count = it.Count or 1, bag = bag, idx = idx, ext = ext_string(it.Extra) }; end
            end
        end
    end);
    GEAR.slots = out;
    return out;
end
-- (the game's element symbols - 0xEF and one of 0x1F..0x26 - as their names: "Fire+15" rather than "+15")
local ELEM_SYM = { [0x1F] = 'Fire', [0x20] = 'Ice', [0x21] = 'Wind', [0x22] = 'Earth', [0x23] = 'Lightning', [0x24] = 'Water', [0x25] = 'Light', [0x26] = 'Dark' };
local function clean(s, dots)
    s = tostring(s or ''):gsub('\x81\x60', '~'):gsub('\xEF(.)', function(c)
        local v = c:byte();
        if not ELEM_SYM[v] then return ''; end
        return dots and ('\1' .. string.char(48 + v - 0x1E)) or ELEM_SYM[v];      -- (dots: a mark the item card draws as a coloured dot)
    end):gsub('[\x80-\xFF][\x40-\xFF]?', '');
    return s;
end
-- (the elements' dots, coloured as in the equipment panel's resistances)
local EDOT = { { 1.00, 0.36, 0.30 }, { 0.50, 0.85, 1.00 }, { 0.40, 0.95, 0.50 }, { 1.00, 0.85, 0.30 }, { 0.80, 0.50, 1.00 }, { 0.35, 0.50, 1.00 }, { 1.00, 1.00, 0.95 }, { 0.45, 0.40, 0.55 } };
function ETEXT(dl, x, y, ln, c, a)                                   -- (a line with element marks in it: text, dot, text...)
    if ln:find('[\2\3]') then                                       -- (auto-translate brackets: a green < and a red >)
        local cx = x;
        for seg, mk in (ln .. '\0'):gmatch('([^\2\3%z]*)([\2\3%z])') do
            if seg ~= '' then ETEXT(dl, cx, y, seg, c, a); cx = cx + tw(seg); end
            if mk ~= '\0' then
                local br = (mk == '\2') and '<' or '>';
                local bc = (mk == '\2') and { 0.35, 0.95, 0.45, 1 } or { 1.0, 0.40, 0.40, 1 };
                text(dl, cx, y, br, bc, a); cx = cx + tw(br) + 1;
            end
        end
        return;
    end
    if not ln:find('\1', 1, true) then return text(dl, x, y, ln, c, a); end
    local lh = imgui.GetTextLineHeight();
    local r = math.max(3, lh * 0.30);
    local cx = x;
    for seg, mk in (ln .. '\1\0'):gmatch('([^\1]*)\1(.)') do
        if seg ~= '' then text(dl, cx, y, seg, c, a); cx = cx + tw(seg); end
        local k = mk:byte() - 48;
        if EDOT[k] then
            local ec = EDOT[k];
            DL.CF(dl, cx + r + 1, y + lh / 2 + 1, r, U4(ec[1], ec[2], ec[3], (a or 1)), 16);
            DL.CF(dl, cx + r + 1 - r * 0.35, y + lh / 2 + 1 - r * 0.35, r * 0.35, U4(1, 1, 1, 0.45 * (a or 1)), 8);
            cx = cx + r * 2 + 3;
        end
    end
end
-- Augments: read from the item's own extra data, the way Windower's extdata library does (its tables are in augments.lua)
local AUG = { t = nil, tried = false };
local function aug_table()
    if not AUG.tried then
        AUG.tried = true;
        pcall(function() local f = loadfile(addon.path .. 'augments.lua'); if f then AUG.t = f(); end end);
    end
    return AUG.t;
end
function ext_string(e)                                               -- (an item's extra data, as a string of bytes)
    if e == nil then return nil; end
    if type(e) == 'string' then return e; end
    if type(e) == 'userdata' or type(e) == 'cdata' then          -- (a raw array: copy its 28 bytes)
        local ok, str = pcall(function() local ffi_ = require('ffi'); return ffi_.string(ffi_.cast('const char*', e), 28); end);
        if ok and str then return str; end
    end
    local out = {};
    pcall(function()
        local base = (e[0] ~= nil) and 0 or 1;
        for i = 0, 27 do local v = e[base + i]; if v == nil then break; end out[#out + 1] = string.char(tonumber(v) % 256); end
    end);
    return (#out > 0) and table.concat(out) or nil;
end
function item_extra(bag, idx)
    local ext, raw = nil, nil;
    local ok, err = pcall(function() local it = AshitaCore:GetMemoryManager():GetInventory():GetContainerItem(bag, idx); raw = it and it.Extra; ext = ext_string(raw); end);
    -- (what the item's extra data looked like, to the survey: for fixing it)
    pcall(function()
        local hex = ext and (ext:sub(1, 16):gsub('.', function(c) return ('%02X'):format(c:byte()); end)) or 'none';
        M.note('ext', ('bag %d slot %d: %s -> %s %s'):format(bag, idx, type(raw), hex, ok and '' or tostring(err)));
    end);
    return ext;
end
-- enchanted gear: charges, and when it can be used (its recast, and the delay after putting it on), as Windower reads them
-- (times are seconds from the game's own start date: + 1009792800 is the real time)
local function fmt_left(sec)
    sec = math.max(0, math.floor(sec));
    local h, m, s_ = math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60;
    if h > 0 then return ('%d:%02d:%02d'):format(h, m, s_); end
    return ('%d:%02d'):format(m, s_);
end
-- when each piece of gear was put on (for the wait before enchanted gear works: the item's cast delay)
local WORN_AT, WORN_T, WORN_FIRST = {}, -10, true;
local function track_worn()
    local now_ = os.clock();
    if now_ - WORN_T < 0.5 then return; end
    WORN_T = now_;
    local seen = {};
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        for slot = 0, 15 do
            local e = inv:GetEquippedItem(slot);
            if e ~= nil and (e.Index or 0) ~= 0 then
                local bag, idx = bit.rshift(bit.band(e.Index, 0xFF00), 8), bit.band(e.Index, 0xFF);
                local it = inv:GetContainerItem(bag, idx);
                if it and (it.Id or 0) ~= 0 then
                    local k = bag * 256 + idx;
                    seen[k] = true;
                    if not WORN_AT[k] or WORN_AT[k].id ~= it.Id then WORN_AT[k] = { id = it.Id, t = WORN_FIRST and 0 or os.time() }; end
                end
            end
        end
    end);
    for k in pairs(WORN_AT) do if not seen[k] then WORN_AT[k] = nil; end end
    WORN_FIRST = false;
end
-- LandSandBoat (the server) keeps the time it was LAST used there, in seconds from 1009810800; retail keeps the time it can
-- next be used. So: a time still to come is when it's ready; a time gone by + the item's reuse delay is when it's ready.
function ench_info(ext, id, bag, idx)
    if type(ext) ~= 'string' or #ext < 12 or ext:byte(1) ~= 1 then return nil; end
    local function u32(o) return ext:byte(o) + ext:byte(o + 1) * 256 + ext:byte(o + 2) * 65536 + ext:byte(o + 3) * 16777216; end
    local now = os.time();
    local reuse = 0;
    if id then pcall(function() local r = AshitaCore:GetResourceManager():GetItemById(id); reuse = tonumber(r.RecastDelay or r.ReuseDelay or r.Recast) or 0; end); end
    local t1, t2 = u32(5), u32(9);
    local recast = 0;
    if t1 > 0 then
        local at = t1 + 1009810800;
        recast = (at > now) and (at - now) or (at + reuse - now);
    end
    local equip = (t2 > 0) and (t2 + 1009810800 - now) or 0;
    local w = bag and idx and WORN_AT[bag * 256 + idx];                -- (put on just now: the wait before it works)
    if w and w.t > 0 and id then
        local cd = 0;
        pcall(function() cd = tonumber(AshitaCore:GetResourceManager():GetItemById(id).CastDelay) or 0; end);
        equip = math.max(equip, w.t + cd - now);
    end
    return { charges = ext:byte(2), recast = recast, equip = equip, left = math.max(recast, equip, 0), reuse = reuse };
end
function ench_label(ext, id, bag, idx)                               -- (short: for a list row)
    local e = ench_info(ext, id, bag, idx);
    if not e then return nil; end
    if e.charges == 0 then return 'no charges'; end
    return (e.left > 0) and fmt_left(e.left) or 'READY';
end
function aug_lines(ext, id, bag, idx)
    if type(ext) ~= 'string' or #ext < 12 then return nil; end
    local b1, f2 = ext:byte(1), ext:byte(2);
    if b1 == 1 then                                                  -- (enchanted: charges, and the countdown before it can be used)
        local e = ench_info(ext, id, bag, idx);
        local out = { ('Charges left: %d'):format(e.charges) };
        if e.charges > 0 then
            if e.left <= 0 then out[#out + 1] = 'Ready to use';
            else
                if e.recast > 0 then out[#out + 1] = 'Recast: ' .. fmt_left(e.recast); end
                if e.equip > 0 then out[#out + 1] = 'Ready after putting it on in: ' .. fmt_left(e.equip); end
                out[#out + 1] = 'Usable in ' .. fmt_left(e.left);
            end
        end
        return out;
    end
    if b1 ~= 2 and b1 ~= 3 then return nil; end
    local T = aug_table();
    if not T then return nil; end
    local function unpack_(sys, a, b)
        if sys == 1 then return a + (b % 8) * 256, math.floor(b / 8);
        elseif sys == 3 then return a + (b % 8) * 256, math.floor((b % 128) / 8);
        else return a, b; end
    end
    local function name_(sys, id, val)
        local at = T.values[sys] and T.values[sys][id];
        if at and at.Secondary_Handling then at = T.sp390[(id - 0x390) * 16 + 545 + val]; end
        if not at then return nil; end
        if sys == 3 then
            local pot = at[1].potency and at[1].potency[val] or 0;
            return at[1].stat .. ((pot > 0) and '+' or '') .. pot;
        end
        local out = nil;
        for i, v in ipairs(at) do
            local stat = v.stat or '';
            local pot = (val + (v.offset or 0)) * (v.multiplier or 1);
            local one = stat .. ((pot > 0) and ('+' .. pot) or ((pot < 0) and tostring(pot) or '')) .. ((v.percent and pot ~= 0) and '%' or '');
            out = out and (out .. ' ' .. one) or one;
        end
        return out;
    end
    local sys, first, last;
    if bit.band(f2, 8) ~= 0 then return nil;                         -- (crafting shields)
    elseif bit.band(f2, 32) ~= 0 then sys, first, last = 2, 7, 12;
    elseif f2 == 131 then return nil;
    elseif f2 >= 128 then sys, first, last = 3, 3, 8;
    else sys, first, last = 1, 3, (bit.band(f2, 64) ~= 0) and 10 or 12; end
    local lines = {};
    for i = first, last - 1, 2 do
        local id, val = unpack_(sys, ext:byte(i), ext:byte(i + 1));
        if id ~= 0 then
            local n = name_(sys, id, val);
            if n and n ~= 'none' and n ~= '' and not n:match('^%-+$') then lines[#lines + 1] = n; end
        end
    end
    return (#lines > 0) and lines or nil;
end
local function item_info(id)
    local ok, it = pcall(function() return AshitaCore:GetResourceManager():GetItemById(id); end);
    if not ok or it == nil then return nil; end
    local i = { name = (it.Name and it.Name[1]) or '?', desc = clean(it.Description and it.Description[1], true) };
    local lv, jobs, races, fl = tonumber(it.Level) or 0, tonumber(it.Jobs) or 0, tonumber(it.Races) or 0, tonumber(it.Flags) or 0;
    local js;
    if bit.band(jobs, 0x007FFFFE) == 0x007FFFFE then js = 'All Jobs';
    else local t_ = {}; for j = 1, 22 do if bit.band(jobs, bit.lshift(1, j)) ~= 0 then t_[#t_ + 1] = JOBS[j]; end end; js = table.concat(t_, ' '); end
    i.lv, i.jobs = (lv > 0) and ('Lv.' .. lv) or '', js;
    i.races = (bit.band(races, 0x1FE) == 0x1FE or races == 0) and 'All Races' or 'Some Races';
    i.rare, i.ex = bit.band(fl, 0x8000) ~= 0, bit.band(fl, 0x6040) ~= 0;
    return i;
end
local function wrap(s, maxw)
    local lines = {};
    for para in (s .. '\n'):gmatch('([^\n]*)\n') do
        local line = '';
        for word in para:gmatch('%S+') do
            local try = (line == '') and word or (line .. ' ' .. word);
            if tw(try) > maxw and line ~= '' then lines[#lines + 1] = line; line = word; else line = try; end
        end
        lines[#lines + 1] = line;
    end
    while #lines > 0 and lines[#lines] == '' do lines[#lines] = nil; end
    return lines;
end

----------------------------------------------------------------------------------------------------
-- Storage: the game's storage picker (mnstorag) has 9 buttons, in this order
----------------------------------------------------------------------------------------------------
local BAGS = {
    { 0,  'Inventory',      'INV' }, { 8,  'Mog Wardrobe',   'W1' }, { 10, 'Mog Wardrobe 2', 'W2' },
    { 11, 'Mog Wardrobe 3', 'W3' },  { 12, 'Mog Wardrobe 4', 'W4' }, { 13, 'Mog Wardrobe 5', 'W5' },
    { 14, 'Mog Wardrobe 6', 'W6' },  { 15, 'Mog Wardrobe 7', 'W7' }, { 16, 'Mog Wardrobe 8', 'W8' },
};
UI.bag = nil;                                                        -- which BAGS entry the item list shows (nil = not known yet)
local function slot_mask(slot)
    if slot == 11 or slot == 12 then return bit.bor(bit.lshift(1, 11), bit.lshift(1, 12)); end
    if slot == 13 or slot == 14 then return bit.bor(bit.lshift(1, 13), bit.lshift(1, 14)); end
    return bit.lshift(1, slot);
end
-- the items in a bag that go in `slot`: { all = {...}, free = {...} (not worn) }, each { id, idx, count, worn }
local CAND = { at = 0, cache = {} };
local function candidates(bagid, slot)
    local key = bagid .. ':' .. slot;
    local now = os.clock();
    if now - CAND.at > 0.25 then CAND.at, CAND.cache = now, {}; end
    if CAND.cache[key] then return CAND.cache[key]; end
    local all, free = {}, {};
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        local res = AshitaCore:GetResourceManager();
        local mask = slot_mask(slot);
        local max = 80;
        pcall(function() max = inv:GetContainerCountMax(bagid) or 80; end);
        for i = 1, math.max(1, math.min(80, max)) do
            local it = inv:GetContainerItem(bagid, i);
            if it ~= nil and (it.Id or 0) ~= 0 and it.Id ~= 65535 then
                local r = res:GetItemById(it.Id);
                if r and bit.band(tonumber(r.Slots) or 0, mask) ~= 0 then
                    local e = { id = it.Id, idx = i, count = it.Count or 1, worn = (it.Flags == 5) };
                    all[#all + 1] = e;
                    if not e.worn then free[#free + 1] = e; end
                end
            end
        end
    end);
    CAND.cache[key] = { all = all, free = free };
    return CAND.cache[key];
end
-- The game's item list for the equipment slot: which bag it shows and its items, worked out by matching the game's own
-- item count (the bag we last saw picked first, then every bag). Returns the list, its bag, and a reason when unsure.
local function equip_list(inv_w, slot)
    local mp = rd32(inv_w.addr + 0x0C);
    if mp < FLOOR then return nil, nil, 'no list data'; end
    local count, top, page = rd16(mp + 0x20), rd16(mp + 0x1E), rd16(mp + 0x18);
    if page <= 0 or count < 0 or top < 0 then return nil, nil, 'list data not valid'; end
    local function try(b)                                            -- (whether the game lists worn pieces is learned the first
        local c = candidates(BAGS[b][1], slot);                      --  time only one answer fits, then kept)
        local va, vf = (#c.all == count), (#c.free == count);
        if UI.variant == 'all' then return va and c.all or nil, 'all'; end
        if UI.variant == 'free' then return vf and c.free or nil, 'free'; end
        if va and vf then return c.all, nil; end
        if va then return c.all, 'all'; end
        if vf then return c.free, 'free'; end
        return nil;
    end
    if UI.bag then
        local l, v = try(UI.bag);
        if l then
            if v and UI.variant == nil and count > 0 then UI.variant = v; M.note('variant', 'game lists ' .. ((v == 'all') and 'worn pieces too' or 'only unworn pieces')); end
            return l, UI.bag, nil, count, top, page;
        end
    end
    local hit, hits = nil, 0;
    for b = 1, #BAGS do
        local l, v = try(b);
        if l then hits = hits + 1; if hit == nil then hit = { l, b, v }; end end
    end
    if hits == 1 or (hits > 1 and count == 0) then
        UI.bag = hit[2];
        if hit[3] and UI.variant == nil and count > 0 and hits == 1 then UI.variant = hit[3]; M.note('variant', 'game lists ' .. ((hit[3] == 'all') and 'worn pieces too' or 'only unworn pieces')); end
        return hit[1], hit[2], nil, count, top, page;
    end
    return nil, nil, (hits == 0) and ('no bag has ' .. count .. ' items for this slot') or (hits .. ' bags have ' .. count .. ' items'), count, top, page;
end

local function draw_char(eq, natives)
    local s = PSCALE();
    local d = char_data();
    local slots = gear();
    local W = math.floor(560 * s);
    local HEAD = math.floor(70 * s);
    local BODY = math.floor(300 * s);
    local CARD = math.max(math.floor(104 * s), math.floor(UI.card_need or 0));   -- (grows to fit the item, measured last frame)
    local P = math.floor(16 * s);
    local H = HEAD + BODY + CARD + P;
    local sw, sh = screen();
    local x, y = place('char', W, H, natives, 'left', math.floor((sw - W) / 2), math.floor(sh * 0.12));

    local now = os.clock();
    UI.char.t0 = UI.char.t0 or now;
    local k = cfg.anim and ease((now - UI.char.t0) / 0.22) or 1;
    local focused = eq ~= nil and M.focus == eq.addr;
    local a = k;
    y = y + math.floor((1 - k) * 12 * s);

    imgui.SetNextWindowPos({ x, y }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ W + 8, H + 8 }, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    UI.pushed = 2;
    local opened = imgui.Begin('##ym_char', { true }, win_flags());
    UI.began = true;
    if opened then
        local dl = imgui.GetWindowDrawList();
        x, y = drag('char', x, y, x, y, x + W, y + HEAD);
        local hov_win = imgui.IsWindowHovered();
        UI.char_lock = { x + W - P - 16 * s, y + 4 * s };
        local mx, my = mouse();
        panel(dl, x, y, x + W, y + H, a, s);
        lock_button(dl, UI.char_lock[1], UI.char_lock[2], s, a, hov_win);

        -- header: job emblem, name, jobs
        local jn = JOBS[d.job or 0];
        local js = 52 * s;
        local jx, jy = x + P, y + (HEAD - js) / 2 + 2 * s;
        DL.CF(dl, jx + js / 2, jy + js / 2, js * 0.55, col(C.vio, 0.10 * a), 32);
        if not (jn and image(dl, tex('jobs\\' .. jn:lower() .. '.png'), jx, jy, jx + js, jy + js, a)) then
            DL.C(dl, jx + js / 2, jy + js / 2, js * 0.42, col(C.acc, 0.6 * a), 32, 1.5);
            local tk = font(15 * s); text(dl, jx + js / 2 - tw(jn or '?') / 2, jy + js / 2 - 8 * s, jn or '?', C.text, a); unfont(tk);
        end
        local tk = font(12 * s);
        caps(dl, x + P + js + 14 * s, y + 13 * s, (eq ~= nil) and 'EQUIPMENT' or 'STATUS', C.acc, 2.5 * s, a);
        unfont(tk);
        do                                                           -- gil (the game's money window is hidden too)
            local gil = nil;
            pcall(function() local g = AshitaCore:GetMemoryManager():GetInventory():GetContainerItem(0, 0); gil = g and g.Count; end);
            if gil then
                local gs = tostring(gil):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '') .. ' G';
                tk = font(13 * s);
                text(dl, x + W - P - tw(gs), y + 42 * s, gs, C.gold, a);
                unfont(tk);
            end
        end
        UI.charbox = { x, y, W, H, s };
        tk = font(24 * s);
        text(dl, x + P + js + 14 * s, y + 26 * s, d.name or '', C.text, a);
        unfont(tk);
        tk = font(14 * s);
        do
            local jx2 = x + W - P;
            local parts = {};
            if jn then parts[#parts + 1] = { 'Lv', C.dim }; parts[#parts + 1] = { tostring(d.lv or 0) .. ' ', C.acc }; parts[#parts + 1] = { jn, C.text }; end
            if JOBS[d.sjob or 0] and (d.slv or 0) > 0 then
                parts[#parts + 1] = { '   /   ', C.dim };
                parts[#parts + 1] = { 'Lv', C.dim }; parts[#parts + 1] = { tostring(d.slv) .. ' ', C.acc }; parts[#parts + 1] = { JOBS[d.sjob], C.text };
            end
            local total = 0; for _, p in ipairs(parts) do total = total + tw(p[1]); end
            local cx = jx2 - total;
            for _, p in ipairs(parts) do text(dl, cx, y + 20 * s, p[1], p[2], a); cx = cx + tw(p[1]); end
        end
        unfont(tk);
        local ly = y + HEAD - 2;
        DL.RFM(dl, x + P, ly, x + W - P, ly + 1, U4(1, 1, 1, 0.0), U4(1, 1, 1, 0.10 * a), U4(1, 1, 1, 0.10 * a), U4(1, 1, 1, 0.0));

        -- left: HP / MP / TP, attributes, attack / defence, resistances
        local lx, lw = x + P, math.floor(258 * s);
        local cy = y + HEAD + 12 * s;
        local function vbar(label, cur, max, frac, c1, c2, seed)
            local tk2 = font(13 * s);
            caps(dl, lx, cy, label, c1, 1.5 * s, a);
            local v = max and (tostring(cur) .. ' / ' .. tostring(max)) or tostring(cur);
            text(dl, lx + lw - tw(v), cy, v, C.text, a);
            unfont(tk2);
            bar(dl, lx, cy + 18 * s, lw, math.max(3, 4 * s), frac, c1, c2, a, seed);
            cy = cy + 30 * s;
        end
        vbar('HP', d.hp or 0, d.hpmax, d.hpp or 0, C.pink, C.mag, 1);
        vbar('MP', d.mp or 0, d.mpmax, d.mpp or 0, C.mp1, C.mp2, 2);
        vbar('TP', d.tp or 0, nil, (d.tp or 0) / 3000, C.tp1, C.tp2, 3);
        cy = cy + 4 * s;
        tk = font(14 * s);
        local rowh = 19 * s;
        local colw = lw / 2;
        for i = 1, 7 do                                              -- two columns: STR DEX VIT AGI / INT MND CHR
            local c_ = (i <= 4) and 0 or 1;
            local r_ = (i <= 4) and (i - 1) or (i - 5);
            local sx_, sy_ = lx + c_ * colw, cy + r_ * rowh;
            text(dl, sx_, sy_, STATS[i], C.muted, a);
            local base = d.stats[i];
            local bs = base and tostring(base) or '--';
            text(dl, sx_ + 44 * s, sy_, bs, C.text, a);
            local m = tonumber(d.mods[i]) or 0;
            if m ~= 0 then text(dl, sx_ + 44 * s + tw(bs) + 6 * s, sy_, (m > 0 and '+' or '') .. m, m > 0 and C.good or C.bad, a); end
        end
        cy = cy + 4 * rowh + 8 * s;
        do                                                           -- attack / defence chips
            local cw_ = (lw - 8 * s) / 2;
            for j, it in ipairs({ { 'ATTACK', d.atk }, { 'DEFENSE', d.def } }) do
                local cx0 = lx + (j - 1) * (cw_ + 8 * s);
                DL.RF(dl, cx0, cy, cx0 + cw_, cy + 26 * s, U4(1, 1, 1, 0.04 * a), 6 * s);
                DL.RF(dl, cx0, cy + 5 * s, cx0 + 2, cy + 21 * s, col(j == 1 and C.pink or C.vio, a), 1);
                local tk2 = font(11.5 * s); caps(dl, cx0 + 10 * s, cy + 7 * s, it[1], C.muted, 1.2 * s, a); unfont(tk2);
                local v = it[2] and tostring(it[2]) or '--';
                text(dl, cx0 + cw_ - tw(v) - 10 * s, cy + 5 * s, v, C.text, a);
            end
            cy = cy + 34 * s;
        end
        do                                                           -- resistances: 4 x 2 gems
            local gw = lw / 4;
            for i, e in ipairs(ELEM) do
                local c_, r_ = (i - 1) % 4, math.floor((i - 1) / 4);
                local gx, gy = lx + c_ * gw, cy + r_ * 22 * s;
                local gc = e[3];
                DL.CF(dl, gx + 7 * s, gy + 8 * s, 7 * s, col(gc, 0.16 * a), 16);
                DL.CF(dl, gx + 7 * s, gy + 8 * s, 4.2 * s, col(gc, 0.95 * a), 16);
                DL.CF(dl, gx + 6 * s, gy + 6.5 * s, 1.4 * s, U4(1, 1, 1, 0.7 * a), 8);
                local v = d.res[e[1]];
                text(dl, gx + 18 * s, gy, v and tostring(v) or '--', (v or 0) > 0 and C.text or C.dim, a);
                if hov_win and inside(mx, my, gx, gy, gx + gw, gy + 18 * s) then
                    pcall(imgui.SetTooltip, e[2] .. ' resistance');
                end
            end
        end
        unfont(tk);

        -- right: the gear, 4 x 4 in the game's order
        local cell, gap = math.floor(54 * s), math.floor(7 * s);
        local gx0 = x + W - P - (4 * cell + 3 * gap);
        local gy0 = y + HEAD + 14 * s;
        local eord = eq and M.order(eq) or nil;
        if eq and eord == nil then                                   -- (no button places read: the game's usual order, down each column)
            eord = {}; for v = 1, 16 do eord[v] = ((v - 1) % 4) * 4 + math.floor((v - 1) / 4) + 1; end
        end
        local cur = (eq and eq.cursor >= 1 and eq.cursor <= 16) and to_place(eord, eq.cursor) or nil;
        local hover = nil;
        for b = 1, 16 do
            local c_, r_ = (b - 1) % 4, math.floor((b - 1) / 4);   -- (b = the place on screen, row by row)
            local cx0, cy0 = gx0 + c_ * (cell + gap), gy0 + r_ * (cell + gap);
            local cx1, cy1 = cx0 + cell, cy0 + cell;
            local slot = GRID[b];
            local e = slots[slot];
            local hov = hov_win and not UI.move and inside(mx, my, cx0, cy0, cx1, cy1);
            if hov then hover = b; end
            DL.RF(dl, cx0, cy0, cx1, cy1, U4(0.115, 0.105, 0.155, 0.92 * a), 7 * s);
            local t1, t2 = U4(1, 1, 1, 0.05 * a), U4(1, 1, 1, 0);
            DL.RFM(dl, cx0 + 1, cy0 + 1, cx1 - 1, cy0 + cell * 0.5, t1, t1, t2, t2);
            DL.R(dl, cx0, cy0, cx1, cy1, hov and U4(1, 1, 1, 0.30 * a) or U4(0.62, 0.40, 1.0, 0.18 * a), 7 * s, 0, 1);
            if e then
                local ic = item_icon(e.id);
                local is = cell * 0.74;
                local ix, iy = cx0 + (cell - is) / 2, cy0 + (cell - is) / 2;
                if not image(dl, ic, ix, iy, ix + is, iy + is, a) then
                    local tk2 = font(11 * s); text(dl, cx0 + 6 * s, cy0 + cell / 2 - 6 * s, '?', C.muted, a); unfont(tk2);
                end
                local tk2 = font(11.5 * s);
                local wn = WARDROBE[e.bag];
                if wn then                                           -- which wardrobe it lives in
                    local bx = cx1 - 13 * s;
                    DL.RF(dl, bx - 1 * s, cy0 + 2 * s, cx1 - 2 * s, cy0 + 15 * s, U4(0, 0, 0, 0.55 * a), 4 * s);
                    text(dl, bx + 2 * s, cy0 + 2 * s, tostring(wn), C.acc, a);
                end
                if (e.count or 1) > 1 then
                    local cs = tostring(e.count);
                    text(dl, cx1 - tw(cs) - 4 * s, cy1 - 15 * s, cs, C.text, a);
                end
                unfont(tk2);
            else
                local tk2 = font(10.5 * s);
                local lab = SLOTS[slot] or '';
                text(dl, cx0 + (cell - tw(lab)) / 2, cy0 + cell / 2 - 6 * s, lab, C.dim, a);
                unfont(tk2);
            end
            if cur == b then sel_frame(dl, cx0, cy0, cx1, cy1, 7 * s, focused and a or a * 0.5); end
        end
        -- under the grid: how many pieces are on, and the mouse controls
        do
            local tk2 = font(11.5 * s);
            local gy1 = gy0 + 4 * (cell + gap) + 1 * s;
            local count = 0; for _ in pairs(slots) do count = count + 1; end
            caps(dl, gx0, gy1, ('%d / 16 EQUIPPED'):format(count), C.dim, 1.4 * s, a);
            if eq and cfg.clicks then
                text(dl, gx0, gy1 + 16 * s, 'Pick a slot, then a piece on the right', C.dim, a * 0.85);
            end
            unfont(tk2);
        end

        -- bottom: the item card (the item list's pick while it's in use, else the hovered slot, else the game's cursor)
        local show = hover or cur;
        local cy0 = y + HEAD + BODY;
        DL.RF(dl, x + 10 * s, cy0, x + W - 10 * s, cy0 + CARD - 2, U4(0, 0, 0, 0.30 * a), 8 * s);
        local e = show and slots[GRID[show]] or nil;
        if UI.list_pick and not hover then e = { id = UI.list_pick }; end
        local info = e and item_info(e.id) or nil;
        if info then
            local ac = info.rare and C.gold or (info.ex and C.acc or { 0.45, 0.70, 1.0, 1 });
            DL.RF(dl, x + 10 * s, cy0 + 10 * s, x + 12.5 * s, cy0 + CARD - 12 * s, col(ac, a), 2);
            local is = 36 * s;
            local ix, iy = x + 24 * s, cy0 + 12 * s;
            DL.RF(dl, ix - 3 * s, iy - 3 * s, ix + is + 3 * s, iy + is + 3 * s, U4(1, 1, 1, 0.05 * a), 6 * s);
            image(dl, item_icon(e.id), ix, iy, ix + is, iy + is, a);
            local tx = ix + is + 14 * s;
            tk = font(17 * s);
            text(dl, tx, cy0 + 9 * s, info.name, { 0.62, 1.0, 0.70, 1 }, a);
            local px = tx + tw(info.name) + 10 * s;
            unfont(tk);
            tk = font(11 * s);
            for _, pill in ipairs({ { info.rare, 'RARE', C.gold }, { info.ex, 'EX', C.acc } }) do
                if pill[1] then
                    local pw = tw(pill[2]) + 12 * s;
                    DL.RF(dl, px, cy0 + 12 * s, px + pw, cy0 + 26 * s, col(pill[3], 0.18 * a), 7 * s);
                    DL.R(dl, px, cy0 + 12 * s, px + pw, cy0 + 26 * s, col(pill[3], 0.6 * a), 7 * s, 0, 1);
                    text(dl, px + 6 * s, cy0 + 13 * s, pill[2], pill[3], a);
                    px = px + pw + 6 * s;
                end
            end
            unfont(tk);
            if info.lv ~= '' then                                -- the level, top right, on its own
                tk = font(14 * s);
                text(dl, x + W - 24 * s - tw(info.lv), cy0 + 11 * s, info.lv, C.acc, a);
                unfont(tk);
            end
            tk = font(13.5 * s);
            local maxw = W - (tx - x) - 24 * s;
            local sub = '[' .. (SLOTN[GRID[show]] or '') .. ']  ' .. info.races;
            text(dl, tx, cy0 + 31 * s, sub, C.muted, a);
            local yy = cy0 + 50 * s;
            for _, ln in ipairs(wrap(info.desc, maxw)) do ETEXT(dl, tx, yy, ln, C.text, a); yy = yy + 16 * s; end
            for _, au in ipairs(aug_lines(e.ext, e.id, e.bag, e.idx) or {}) do            -- (its augments)
                for _, ln in ipairs(wrap(au, maxw)) do text(dl, tx, yy, ln, { 0.45, 0.85, 1.0, 1 }, a); yy = yy + 16 * s; end
            end
            unfont(tk);
            tk = font(12.5 * s);                                     -- the jobs, wrapped, under the description
            yy = yy + 4 * s;
            for _, ln in ipairs(wrap(info.jobs, maxw)) do text(dl, tx, yy, ln, C.acc, a * 0.9); yy = yy + 15 * s; end
            unfont(tk);
            UI.card_need = (yy - cy0) + 12 * s;
        else
            tk = font(13.5 * s);
            UI.card_need = nil;
            local t_ = show and ((SLOTN[GRID[show]] or '') .. ': nothing equipped') or 'Pick a slot to see the item.';
            text(dl, x + 26 * s, cy0 + CARD / 2 - 9 * s, t_, C.dim, a);
            unfont(tk);
        end

        UI.eq_slot = cur and GRID[cur] or nil;                       -- (the slot the item list is for)

        -- mouse: a slot = the game's cursor there and OK (its own item list opens); right-click = back
        if hov_win and not UI.move and eq then
            if hover and imgui.IsMouseClicked(0) then M.act(eq.addr, to_button(eord, hover), KEY.ok); end
            if imgui.IsMouseClicked(1) then M.act(nil, nil, KEY.cancel); end
            local wheel = imgui.GetIO().MouseWheel or 0;
            if cfg.wheel and wheel ~= 0 and focused and cur then
                local to = cur + ((wheel > 0) and -4 or 4);
                if to >= 1 and to <= 16 then M.act(eq.addr, to_button(eord, to), nil); end
            end
        end
    end
    imgui.End();
    UI.began = false;
    imgui.PopStyleVar(2);
    UI.pushed = 0;
end

----------------------------------------------------------------------------------------------------
-- A plain list panel in the main menu's look (the storage picker and the item list use it)
--   rows: { { label, sub, icon_id, dim } ... } for the visible rows; cur: the highlighted row (1-based)
----------------------------------------------------------------------------------------------------
local function list_panel(id, x, y, W, title, sub, rows, cur, opts)
    local s = PSCALE();
    opts = opts or {};
    local RH = math.floor((opts.icons and 30 or 23) * s);
    local HEAD = math.floor((opts.cols and 60 or 44) * s);
    local nrows = math.max(#rows, opts.min_rows or 0);
    local H = HEAD + nrows * RH + math.floor((opts.foot and 28 or 10) * s);
    local sw, sh = screen();
    x, y = saved_pos(id, x, y, W, H);
    local st = UI[id] or {};
    UI[id] = st;
    local now = os.clock();
    st.t0 = st.t0 or now;
    local k = cfg.anim and ease((now - st.t0) / 0.18) or 1;
    local a = k * (opts.focused == false and 0.75 or 1);
    local clicked, wheel_dir = nil, 0;
    imgui.SetNextWindowPos({ x, y }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ W + 8, H + 8 }, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    UI.pushed = 2;
    local opened = imgui.Begin('##ccm_' .. id, { true }, win_flags());
    UI.began = true;
    if opened then
        local dl = imgui.GetWindowDrawList();
        local hov_win = imgui.IsWindowHovered();
        local mx, my = mouse();
        x, y = drag(id, x, y, x, y, x + W, y + HEAD);
        panel(dl, x, y, x + W, y + H, a, s);
        lock_button(dl, x + W - 26 * s, y + 8 * s, s, a, hov_win);
        local tk = font(12 * s);
        caps(dl, x + 16 * s, y + 10 * s, title, C.acc, 2.5 * s, a);
        unfont(tk);
        if sub and sub ~= '' then
            tk = font(15 * s); text(dl, x + 16 * s, y + 22 * s, sub, C.text, a); unfont(tk);
        end
        if opts.scroll then                                          -- where the page is in the list
            local top, count, page = opts.scroll[1], opts.scroll[2], opts.scroll[3];
            tk = font(12 * s);
            local t_ = count > 0 and (('%d-%d / %d'):format(top + 1, math.min(count, top + page), count)) or 'empty';
            text(dl, x + W - 16 * s - tw(t_), y + 26 * s, t_, C.dim, a);
            if opts.pill then                                        -- (a small button beside it, e.g. sort)
                local tk5 = font(10 * s);
                local lab = opts.pill[1];
                local pw = tw(lab) + 14 * s;
                local px1 = x + W - 24 * s - tw(t_);
                local px0, py0 = px1 - pw, y + 25 * s;
                local hv = hov_win and not UI.move and inside(mx, my, px0, py0, px1, py0 + 16 * s);
                DL.RF(dl, px0, py0, px1, py0 + 16 * s, hv and col(C.pink, 0.40 * a) or U4(1, 1, 1, 0.07 * a), 6 * s);
                DL.R(dl, px0, py0, px1, py0 + 16 * s, col(C.vio, 0.6 * a), 6 * s, 0, 1);
                text(dl, px0 + 7 * s, py0 + 2 * s, lab, hv and C.text or C.acc, a);
                unfont(tk5);
                if hv and imgui.IsMouseClicked(0) then opts.pill[2](); end
            end
            unfont(tk);
            if count > page then
                local tx0, ty0, ty1 = x + W - 6 * s, y + HEAD, y + HEAD + nrows * RH;
                DL.RF(dl, tx0, ty0, tx0 + 2 * s, ty1, U4(1, 1, 1, 0.06 * a), 2);
                local h_ = (ty1 - ty0) * page / count;
                local o_ = (ty1 - ty0 - h_) * top / math.max(1, count - page);
                DL.RF(dl, tx0, ty0 + o_, tx0 + 2 * s, ty0 + o_ + h_, mix(C.pink, C.vio, 0.5, 0.9 * a), 2);
            end
        end
        if opts.cols then                                            -- (the columns' names, over the rows)
            tk = font(10.5 * s);
            for _, c in ipairs(opts.cols) do caps(dl, x + c[2], y + HEAD - 13 * s, c[1], C.dim, 1.6 * s, a); end
            unfont(tk);
        end
        local target = y + HEAD + (math.max(1, cur or 1) - 1) * RH;
        st.y = (st.y == nil or not cfg.anim) and target or lerp(st.y, target, math.min(1, 0.35 * 60 * (UI.dt or 0.016)));
        if cur and cur >= 1 and cur <= #rows then
            local by = st.y;
            local p1, p2 = col(C.pink, 0.34 * a), U4(C.vio[1], C.vio[2], C.vio[3], 0.0);
            DL.RFM(dl, x + 8 * s, by + 1, x + W - 8 * s, by + RH - 1, p1, p2, p2, p1);
            DL.RF(dl, x + 8 * s, by + 3, x + 10.5 * s, by + RH - 3, col(C.pink, a), 2);
            local ar = tex('sel_arrow.png');
            local asz = math.min(RH, 23 * s) * 0.62;
            local bob = cfg.anim and math.sin(now * 5) * 1.5 * s or 0;
            image(dl, ar, x - asz * 0.55 + bob, by + (RH - asz) / 2, x + asz * 0.45 + bob, by + (RH + asz) / 2, a);
        end
        local hover = nil;
        tk = font(15 * s);
        for i, r in ipairs(rows) do
            local yy = y + HEAD + (i - 1) * RH;
            if hov_win and not UI.move and inside(mx, my, x + 6 * s, yy, x + W - 6 * s, yy + RH) then hover = i; end
            if hover == i and i ~= cur then DL.RF(dl, x + 8 * s, yy + 1, x + W - 8 * s, yy + RH - 1, U4(1, 1, 1, 0.05 * a), 4 * s); end
            local tx = x + 20 * s;
            if opts.icons then
                local is = RH - 6 * s;
                if r[3] then image(dl, item_icon(r[3]), tx, yy + 3 * s, tx + is, yy + 3 * s + is, r[4] and a * 0.5 or a); end
                tx = tx + is + 8 * s;
            end
            if r.dot then                                            -- (a linkpearl in its linkshell's colour)
                local cx_, cy_ = tx + 7 * s, yy + RH / 2;
                DL.CF(dl, cx_, cy_, 8 * s, col(r.dot, 0.22 * a), 16);
                DL.CF(dl, cx_, cy_, 5.5 * s, col(r.dot, a), 16);
                DL.CF(dl, cx_ - 1.6 * s, cy_ - 1.6 * s, 1.7 * s, U4(1, 1, 1, 0.75 * a), 8);
                tx = tx + 20 * s;
            end
            local tk1 = font(15 * s);                                -- (each row its own size: the right-hand tag's smaller one doesn't carry on)
            local ty = yy + (RH - imgui.GetTextLineHeight()) / 2;
            local c_ = (i == cur) and C.text or (r[4] and C.dim or C.muted);
            ETEXT(dl, tx + ((i == cur) and 4 * s or 0), ty, r[1] or '', c_, a);
            unfont(tk1);
            if r.cols and opts.cols then                             -- (more columns: each at its own place, as the header)
                local tk3 = font(13.5 * s);
                local ty3 = yy + (RH - imgui.GetTextLineHeight()) / 2;
                for k, txt in ipairs(r.cols) do
                    local cx = opts.cols[k + 1] and opts.cols[k + 1][2];
                    if cx and txt and txt ~= '' then text(dl, x + cx, ty3, txt, (i == cur) and C.text or C.muted, a); end
                end
                unfont(tk3);
            end
            if r.bar then                                            -- (a thin bar of progress along the row's foot)
                local bx0, bx1, byy = tx, x + W - 18 * s, yy + RH - 3 * s;
                DL.RF(dl, bx0, byy, bx1, byy + 2 * s, U4(1, 1, 1, 0.08 * a), 1);
                if r.bar > 0 then DL.RF(dl, bx0, byy, bx0 + (bx1 - bx0) * math.min(1, r.bar), byy + 2 * s, (r.bar >= 1) and col(C.pink, 0.9 * a) or col(C.vio, 0.9 * a), 1); end
            end
            if r[2] and r[2] ~= '' then
                local tk2 = font((r.same and 15 or 12) * s);         -- (r.same: the right-hand text as big as the left, e.g. Prev / Next)
                local c2 = r.same and ((i == cur) and C.text or (r[4] and C.dim or C.muted)) or ((r[2] == 'WORN') and C.pink or C.acc);
                text(dl, x + W - 18 * s - tw(r[2]), yy + (RH - imgui.GetTextLineHeight()) / 2, r[2], c2, a);
                unfont(tk2);
            end
        end
        unfont(tk);
        if opts.foot then
            tk = font(12 * s);
            text(dl, x + 16 * s, y + H - 22 * s, opts.foot, C.dim, a);
            unfont(tk);
        end
        if hov_win and not UI.move then
            if hover and imgui.IsMouseClicked(0) then clicked = hover; end
            if imgui.IsMouseClicked(1) then if opts.on_cancel then opts.on_cancel(); else M.act(nil, nil, KEY.cancel); end end
            local wheel = imgui.GetIO().MouseWheel or 0;
            if cfg.wheel and wheel ~= 0 then wheel_dir = (wheel > 0) and -1 or 1; end
        end
    end
    imgui.End();
    UI.began = false;
    imgui.PopStyleVar(2);
    UI.pushed = 0;
    return clicked, wheel_dir, { x, y, W, H };
end

-- the storage picker: Inventory, Mog Wardrobe, Mog Wardrobe 2-8
-- The action menu on a target (the game's "playermo"): like the main menu, it follows the game's own cursor, so the
-- controller works it as always; a click puts the game's cursor there and presses OK. Its commands are read in the
-- order the game draws them (the little title tab is left out).
local ACTION_LABELS = {
    [6] = { 'Attack', 'Magic', 'Abilities', 'Trust', 'Items', 'Check' },                              -- out of combat
    [7] = { 'Switch Target', 'Magic', 'Abilities', 'Trust', 'Items', 'Disengage', 'Check' },          -- in combat
    [5] = { 'Attack', 'Magic', 'Abilities', 'Items', 'Check' },
};
-- On yourself: ChadcoreMenu's own menu, like the one on another player (the game's own differs by what you're doing);
-- Chat first, as in the game's (its first command)
local SELF_ROWS = { { 'Chat', 'chat' }, { 'Magic', 'magic' }, { 'Abilities', 'abilities' }, { 'Items', 'items' }, { 'Check', 'check' } };
-- on another player: Chat (the game's own first command: confirm types to them, Right picks the kind of chat), then the same
local PC_ROWS = { { 'Chat', 'chat' }, { 'Magic', 'magic' }, { 'Abilities', 'abilities' }, { 'Items', 'items' }, { 'Check', 'check' } };
local function self_exec(i, key)
    local r = (UI.own_rows or SELF_ROWS)[i];
    if not r then return; end
    if r[2] == 'treasure' then if key ~= KEY.right then TRE.open(); end return; end
    if r[2] == 'chat' then
        local w_, o_ = UI.own_win, UI.own_ord;
        if w_ and o_ and o_[1] then M.act(w_, o_[1], key or KEY.ok); end
        return;
    end
    if key == KEY.right and r[2] == 'check' then return; end
    if r[2] == 'check' then pcall(function() AshitaCore:GetChatManager():QueueCommand(1, UI.own_pc and '/check <t>' or '/check <me>'); end); return; end
    UI.browse = { kind = r[2], via = 'cmd', t0 = os.clock(), from_act = true };
    if r[2] == 'items' then UI.browse.usable = true; else UI.browse.stage, UI.browse.menu = 'menu', true; end
end
local ACTION_SUB = { Magic = true, Abilities = true, Trust = true, Items = true, Disengage = true, Chat = true };
local function action_order(w)
    local b = {};
    for _, x in ipairs(M.buttons(w)) do                              -- (the game keeps spare button slots below the window:
        if (x.h or 0) >= 12 and (x.y or 0) > -1000 and (x.shape ~= 0 or x.user ~= 0)   --  only the ones it says are in use)
            and x.no >= 1 and x.no <= w.buttons then b[#b + 1] = x; end
    end
    table.sort(b, function(p, q) if p.y ~= q.y then return p.y < q.y; end return p.no < q.no; end);
    local ord = {};
    for i, x in ipairs(b) do ord[i] = x.no; end
    if #ord == 0 then for i = 1, w.buttons do ord[i] = i; end end
    return ord;
end
local function draw_action(w)
    local s = PSCALE();
    local ord = action_order(w);
    local labels = ACTION_LABELS[#ord] or {};
    local engaged = false;
    pcall(function()
        local idx = AshitaCore:GetMemoryManager():GetParty():GetMemberTargetIndex(0);
        engaged = AshitaCore:GetMemoryManager():GetEntity():GetStatus(idx) == 1;
    end);
    local pc = false;                                                -- (on another player the first command is Chat:
    pcall(function()                                                 --  confirm types to them, Right picks the kind of chat)
        local ti = AshitaCore:GetMemoryManager():GetTarget():GetTargetIndex(0) or 0;
        local me = AshitaCore:GetMemoryManager():GetParty():GetMemberTargetIndex(0) or -1;
        pc = ti >= 0x400 and ti < 0x700 and ti ~= me;                -- (0x700 and up: Trusts and pets, not players)
    end);
    -- (after a kill the game can keep the fight's 7 commands about while you're no longer fighting: the commands follow
    --  whether you're fighting - out of a fight on a monster or NPC it's the 6 of the out-of-combat menu)
    if not pc and not engaged and #ord == 7 then
        local o6 = {}; for i = 1, 6 do o6[i] = ord[i]; end
        ord, labels = o6, ACTION_LABELS[6];
    elseif not pc and engaged and #ord == 6 then
        labels = ACTION_LABELS[6];
    end
    -- (a menu ChadcoreMenu doesn't know the commands of - e.g. on yourself, 8 commands - stays the game's own)
    local self_ = false;
    pcall(function()
        local ti = AshitaCore:GetMemoryManager():GetTarget():GetTargetIndex(0) or 0;
        self_ = ti == (AshitaCore:GetMemoryManager():GetParty():GetMemberTargetIndex(0) or -1);
    end);
    UI.act_self = self_ or pc;
    if self_ or pc then                                              -- (on yourself or another player: the own menu, its own cursor)
        UI.selfm = UI.selfm or { cur = 1 };
        local key_ = self_ and 'me' or 'pc';
        if UI.selfm.kind ~= key_ then UI.selfm.kind, UI.selfm.cur = key_, 1; end
        local foc_ = (M.focus == w.addr);
        if foc_ and (not UI.selfm.foc or UI.selfm.win ~= w.addr) then   -- (just opened: the cursor on Magic, not Chat, and the
            UI.selfm.win, UI.selfm.ft = w.addr, os.clock();               --  press that opened it isn't taken as a pick)
            UI.selfm.cur = self_ and 2 or 1;
            M.note('selfm', ('action menu on %s opened: cursor %d'):format(self_ and 'yourself' or 'a player', UI.selfm.cur));
        end
        UI.selfm.foc = foc_;
        local base_ = pc and PC_ROWS or SELF_ROWS;
        local own_ = {};
        for i, r in ipairs(base_) do own_[i] = r; end
        local ntr = (cfg.treasure ~= false) and TRE.count() or 0;
        if ntr > 0 then own_[#own_ + 1] = { 'Treasure', 'treasure' }; end   -- (while anything is in the pool)
        UI.own_rows, UI.own_win, UI.own_ord, UI.own_pc = own_, w.addr, ord, pc;
        if UI.selfm.cur > #own_ then UI.selfm.cur = #own_; end
        local rows_ = {};
        for i, r in ipairs(UI.own_rows) do rows_[i] = { r[1], (r[2] == 'treasure') and tostring(ntr) or ((r[2] ~= 'check') and '>' or '') }; end
        local W_ = math.floor(200 * s);
        local nat = cfg.follow and M.to_screen(w.rect) or nil;
        local tname = 'You';
        if pc then pcall(function() tname = AshitaCore:GetMemoryManager():GetEntity():GetName(AshitaCore:GetMemoryManager():GetTarget():GetTargetIndex(0)) or 'Player'; end); end
        local clicked_, wd_, box_ = list_panel('act', nat and nat[1] or 40, nat and nat[2] or 600, W_, 'ACTION', tname, rows_, UI.selfm.cur,
            { focused = (M.focus == w.addr) });
        UI.actbox, UI.actbox_f = box_, M.frame;
        if clicked_ then UI.selfm.cur = clicked_; self_exec(clicked_); end
        if wd_ ~= 0 then UI.selfm.cur = math.max(1, math.min(#rows_, UI.selfm.cur + wd_)); end
        return;
    end
    if not pc and #labels < #ord then
        UI.act_skip = true;
        M.note('act', ('unknown menu (%d commands%s): the game\'s own'):format(#ord, self_ and ', on yourself' or ''));
        return;
    end
    local rows = {};
    for i = 1, #ord do
        local lab = labels[i] or ('Command ' .. i);
        if pc and i == 1 then lab = 'Chat'; end
        rows[i] = { lab, ACTION_SUB[lab] and '>' or '' };
    end
    local cur = 1;
    for i, v in ipairs(ord) do if v == w.cursor then cur = i; end end
    local ntr = (cfg.treasure ~= false) and TRE.count() or 0;       -- (Treasure, below the game's commands, while anything is in the pool)
    UI.actg = UI.actg or {};
    if UI.actg.win ~= w.addr then UI.actg.win, UI.actg.tr = w.addr, false; end
    UI.actg.ord, UI.actg.cur, UI.actg.n = ord, cur, ntr;
    if ntr == 0 then UI.actg.tr = false; end
    do                                                               -- (what the action menu showed, to the survey: for fixing it)
        local tn = '';
        pcall(function() local ti = AshitaCore:GetMemoryManager():GetTarget():GetTargetIndex(0) or 0; tn = (AshitaCore:GetMemoryManager():GetEntity():GetName(ti) or '') .. '#' .. ti; end);
        local labs = {}; for i, r in ipairs(rows) do labs[i] = r[1] .. '=' .. tostring(ord[i]); end
        M.note('act', ('%s buttons %d engaged %s pc %s: %s'):format(tn, w.buttons, tostring(engaged), tostring(pc), table.concat(labs, ',')));
    end
    local W = math.floor(200 * s);
    local native = cfg.follow and M.to_screen(w.rect) or nil;
    local x = native and native[1] or 40;
    local y = native and native[2] or 600;
    local target = '';
    pcall(function()
        local t = AshitaCore:GetMemoryManager():GetTarget();
        local ti = t:GetTargetIndex(0);
        target = AshitaCore:GetMemoryManager():GetEntity():GetName(ti) or '';
    end);
    if ntr > 0 then rows[#rows + 1] = { 'Treasure', tostring(ntr) }; end
    local clicked, wd, box = list_panel('act', x, y, W, 'ACTION', target ~= '' and target or 'Target', rows, UI.actg.tr and (#ord + 1) or cur,
        { focused = (M.focus == w.addr) });
    UI.actbox, UI.actbox_f = box, M.frame;
    if clicked and clicked > #ord then TRE.open(); clicked = nil; end
    if clicked then M.act(w.addr, ord[clicked], KEY.ok); end
    if wd ~= 0 then local to = cur + wd; if to >= 1 and to <= #ord then M.act(w.addr, ord[to], nil); end end
end

-- The chat menu (the game's "chatctrl": Right on Chat in the action menu): Say, Tell, Party, Linkshell, Linkshell 2,
-- Unity, Shout. It follows the game's own cursor, so the controller works it as always.
local CHAT_LABELS = { 'Say', 'Tell', 'Party', 'Linkshell', 'Linkshell 2', 'Unity', 'Shout' };
local CHAT_DESC = { 'Talk to everyone nearby.', 'A private message.', 'Your party.', 'Your linkshell.', 'Your second linkshell.', 'Your Unity.', 'Everyone in the area.' };
local function draw_chat(w)
    local s = PSCALE();
    local b = {};
    for _, x in ipairs(M.buttons(w)) do
        if (x.h or 0) >= 12 and (x.w or 0) >= 40 and (x.y or 0) > -1000 and x.no >= 1 and x.no <= 7 then b[#b + 1] = x; end
    end
    table.sort(b, function(p, q) if p.y ~= q.y then return p.y < q.y; end return p.no < q.no; end);
    local ord = {};
    for i, x in ipairs(b) do ord[i] = x.no; end
    if #ord == 0 then for i = 1, math.min(7, w.buttons) do ord[i] = i; end end
    local target = '';
    pcall(function()
        local ti = AshitaCore:GetMemoryManager():GetTarget():GetTargetIndex(0) or 0;
        if ti >= 0x400 then target = AshitaCore:GetMemoryManager():GetEntity():GetName(ti) or ''; end
    end);
    local rows, cur = {}, 1;
    for i, no in ipairs(ord) do
        rows[i] = { CHAT_LABELS[no] or ('Chat ' .. no), (no == 2 and target ~= '') and target or '' };
        if no == w.cursor then cur = i; end
    end
    local W = math.floor(220 * s);
    local native = cfg.follow and M.to_screen(w.rect) or nil;
    local x = native and native[1] or 40;
    local y = native and native[2] or 600;
    if UI.actbox and M.frame - (UI.actbox_f or -9) <= 1 then         -- (beside the action menu it came from)
        x, y = UI.actbox[1] + UI.actbox[3] + 10 * s, UI.actbox[2];
        local sw = screen();
        if x + W > sw - 4 then x = UI.actbox[1] - W - 10 * s; end
    end
    local clicked, wd = list_panel('chat', x, y, W, 'CHAT', CHAT_DESC[ord[cur] or 1] or 'Pick the kind of chat', rows, cur,
        { focused = (M.focus == w.addr) });
    if clicked then M.act(w.addr, ord[clicked], KEY.ok); end
    if wd ~= 0 then local to = cur + wd; if to >= 1 and to <= #ord then M.act(w.addr, ord[to], nil); end end
end

-- The Mog House storage menu ("mogcont": View House): the bags, with how full each is. It follows the game's own cursor,
-- so the controller works it as always; a click picks that bag.
local MOGC_BAGS = { { 1, 'Mog Safe' }, { 9, 'Mog Safe 2' }, { 2, 'Storage' }, { 4, 'Mog Locker' }, { 5, 'Mog Satchel' }, { 6, 'Mog Sack' },
                    { 7, 'Mog Case' }, { 8, 'Mog Wardrobe' }, { 10, 'Mog Wardrobe 2' }, { 11, 'Mog Wardrobe 3' }, { 12, 'Mog Wardrobe 4' },
                    { 13, 'Mog Wardrobe 5' }, { 14, 'Mog Wardrobe 6' }, { 15, 'Mog Wardrobe 7' }, { 16, 'Mog Wardrobe 8' } };
-- (away from home - "!mog", Storage: "storage2" - the same bags without Storage itself)
local MOGC_AWAY = {};
for _, bg in ipairs(MOGC_BAGS) do if bg[1] ~= 2 then MOGC_AWAY[#MOGC_AWAY + 1] = bg; end end
local function draw_mogcont(w, bags)
    local s = PSCALE();
    local MOGC_BAGS = bags or MOGC_BAGS;
    local b = {};
    for _, x in ipairs(M.buttons(w)) do
        -- (no check on where they are: while ChadcoreMenu keeps the game's menu off screen, its buttons are off screen too)
        if (x.h or 0) >= 12 and (x.w or 0) >= 40 and x.no >= 1 and x.no <= w.buttons then b[#b + 1] = x; end
    end
    table.sort(b, function(p, q) if p.y ~= q.y then return p.y < q.y; end return p.no < q.no; end);
    local ord = {};
    for i, x in ipairs(b) do ord[i] = x.no; end
    if #ord == 0 then for i = 1, w.buttons do ord[i] = i; end end
    local rows, cur = {}, 1;
    local inv = nil;
    pcall(function() inv = AshitaCore:GetMemoryManager():GetInventory(); end);
    for i, no in ipairs(ord) do
        local bg = MOGC_BAGS[i];
        local right = '';
        if bg and inv then
            pcall(function()
                local n = 0;
                for k = 1, 80 do local it = inv:GetContainerItem(bg[1], k); if it and (it.Id or 0) ~= 0 and it.Id ~= 65535 then n = n + 1; end end
                local mx = tonumber(inv:GetContainerCountMax(bg[1])) or 0;
                right = (mx > 0) and (n .. ' / ' .. mx) or '--';
            end);
        end
        rows[i] = { bg and bg[2] or ('Bag ' .. i), right, nil, right == '--' };
        if no == w.cursor then cur = i; end
    end
    local W = math.floor(240 * s);
    local native = cfg.follow and M.to_screen(w.rect) or nil;
    local sw = screen();
    local x = native and (native[3] - W) or (sw - W - 24);
    local y = native and native[2] or 60;
    local clicked, wd = list_panel('mogc', x, y, W, 'STORAGE', 'Which bag?', rows, cur, { focused = (M.focus == w.addr) });
    if clicked then M.act(w.addr, ord[clicked], KEY.ok); end
    if wd ~= 0 then local to = cur + wd; if to >= 1 and to <= #ord then M.act(w.addr, ord[to], nil); end end
end

-- The Moogle's menu in your Mog House ("myroom"): Storage, Delivery Box, Change Jobs, Gardening, Layout, Open Mog,
-- Remodel. It follows the game's own cursor (the controller works it as always); a click picks, the wheel moves.
local MYROOM = { { 'Storage', 'Your Mog House bags: put things in, take them out.' }, { 'Delivery Box', 'Send items to others, and collect what was sent.' },
                 { 'Change Jobs', 'Change your main job and support job.' }, { 'Gardening', 'See how your flowerpots are doing.' },
                 { 'Layout', 'Move your furniture around.' }, { 'Open Mog', 'Let others visit your Mog House.' },
                 { 'Remodel', 'Change how your Mog House looks.' } };
function MYROOM.draw(w)
    local s = PSCALE();
    local b = {};
    for _, x in ipairs(M.buttons(w)) do
        if (x.h or 0) >= 12 and (x.w or 0) >= 40 and x.no >= 1 and x.no <= w.buttons then b[#b + 1] = x; end
    end
    table.sort(b, function(p, q) if p.y ~= q.y then return p.y < q.y; end return p.no < q.no; end);
    local ord = {};
    for i, x in ipairs(b) do ord[i] = x.no; end
    if #ord == 0 then for i = 1, w.buttons do ord[i] = i; end end
    local rows, cur = {}, 1;
    for i, no in ipairs(ord) do
        local m = (w.buttons == #MYROOM) and MYROOM[i] or nil;
        rows[i] = { m and m[1] or ('Command ' .. i), '' };
        if no == w.cursor then cur = i; end
    end
    local d = (w.buttons == #MYROOM and MYROOM[cur]) and MYROOM[cur][2] or nil;
    local W = math.floor(300 * s);
    local native = cfg.follow and M.to_screen(w.rect) or nil;
    local sw, sh = screen();
    local x = native and native[1] or 60;
    local y = native and math.min(native[2], sh - (44 + #rows * 23 + 28 + 60) * s) or 200;
    local clicked, wd = list_panel('myroom', x, y, W, 'MOOGLE', 'Mog House', rows, cur,
        { focused = (M.focus == w.addr), foot = d, min_rows = 0 });
    if M.focus ~= w.addr then return; end                            -- (a sub-menu is up: this one just shows where you are)
    if clicked then M.act(w.addr, ord[clicked], KEY.ok); end
    if wd ~= 0 then local to = cur + wd; if to >= 1 and to <= #ord then M.act(w.addr, ord[to], nil); end end
end
MYROOM.FULL = { 'Warrior', 'Monk', 'White Mage', 'Black Mage', 'Red Mage', 'Thief', 'Paladin', 'Dark Knight', 'Beastmaster', 'Bard',
                'Ranger', 'Samurai', 'Ninja', 'Dragoon', 'Summoner', 'Blue Mage', 'Corsair', 'Puppetmaster', 'Dancer', 'Scholar',
                'Geomancer', 'Rune Fencer' };
-- The Status screen's own list ("statcom2": Profile, Job Levels ... Job Points), top to bottom as the game draws it
-- (its button numbers aren't in that order; the little title tab is left out). It follows the game's cursor.
MYROOM.STATUS = { { 'Profile', 'Your name, race, nation, rank and title.' }, { 'Job Levels', 'Every job and its level.' },
                  { 'Master Levels', 'Your master levels.' }, { 'Combat Skills', 'Your weapon and combat skills.' },
                  { 'Magic Skills', 'Your magic skills.' }, { 'Craft Skills', 'Your crafting and fishing skills.' },
                  { 'Currencies', 'Conquest points, seals, sparks...' }, { 'Currencies 2', 'The second page of currencies.' },
                  { 'Unity', 'Your Unity Concord and accolades.' }, { 'Play Time', 'How long you have played.' },
                  { 'Merit Points', 'Spend merits, or switch EXP / limit points.' },
                  { 'Job Points', 'Spend job points.' } };
function MYROOM.status(w)
    local s = PSCALE();
    local b = {};
    for _, x in ipairs(M.buttons(w)) do
        if (x.h or 0) >= 12 and (x.w or 0) >= 40 and x.no >= 1 and x.no <= w.buttons then b[#b + 1] = x; end
    end
    table.sort(b, function(p, q) if p.y ~= q.y then return p.y < q.y; end return p.no < q.no; end);
    UI.statcmd_drew = false;
    UI.statcmd_n = #b;
    if #b == 0 then return; end
    UI.statcmd_drew = true;
    local rows, ord, cur = {}, {}, 1;
    local known = (#b == #MYROOM.STATUS);
    for i, x in ipairs(b) do
        ord[i] = x.no;
        rows[i] = { known and MYROOM.STATUS[i][1] or ('Command ' .. i), '' };
        if x.no == w.cursor then cur = i; end
    end
    if M.focus == w.addr then UI.statcmd_cur = cur; end
    cur = (M.focus == w.addr) and cur or (UI.statcmd_cur or cur);
    local d = known and MYROOM.STATUS[cur][2] or nil;
    local W = math.floor(270 * s);
    local native = cfg.follow and M.to_screen(w.rect) or nil;
    local sw = screen();
    local x = native and (native[3] - W) or (sw - W - 24);
    local y = native and native[2] or 60;
    local clicked, wd, rect = list_panel('statcmd', x, y, W, 'STATUS', 'Pick a page', rows, cur, { focused = (M.focus == w.addr), foot = d });
    if known and MYROOM.page then MYROOM.page(cur, rect or { x, y, W, 0 }); end
    if M.focus ~= w.addr then return; end
    if clicked then M.act(w.addr, ord[clicked], KEY.ok); end
    if wd ~= 0 then local to = cur + wd; if to >= 1 and to <= #ord then M.act(w.addr, ord[to], nil); end end
end
-- Merit Points: the first choice ("merit1": the categories, or the earning mode) and the categories ("meritcat": a
-- scrolling list, 11 rows at a time; its points box "meritinf" and description "bluehelp" folded in). Both follow the
-- game's own cursor and scroll, so the controller works them as always.
MYROOM.MERIT1 = { { 'Merit Categories', 'Spend your merit points.' }, { 'Earning Mode', 'Earn experience points, or limit points for merits.' } };
MYROOM.MERITCAT = { { 'HP / MP', 'Raise your maximum HP and MP.' }, { 'Attributes', 'Raise your attributes (STR, DEX...).' },
    { 'Combat Skills', 'Adjust your combat skills.' }, { 'Magic Skills', 'Adjust your magic skills.' },
    { 'Others', 'Adjust other abilities.' }, { 'Weapon Skills', 'Enhance your weapon skills.' } };
for _, j in ipairs({ 'Warrior', 'Monk', 'White Mage', 'Black Mage', 'Red Mage', 'Thief', 'Paladin', 'Dark Knight', 'Beastmaster', 'Bard',
                     'Ranger', 'Samurai', 'Ninja', 'Dragoon', 'Summoner', 'Blue Mage', 'Corsair', 'Puppetmaster', 'Dancer', 'Scholar',
                     'Geomancer', 'Rune Fencer' }) do
    MYROOM.MERITCAT[#MYROOM.MERITCAT + 1] = { j, 'Enhance ' .. j .. ' abilities.' };
end
-- the merit categories' lists, as the game shows them (job categories: Group 1 and Group 2 under headings):
-- { name, merit id, most points in it (retail caps, as CatsEyeXI's server uses), what it does (nil: the game's own text for that ability / weapon skill), ability? }
-- after LandSandBoat's data/merits.yaml (GPL-3.0)
MERIT_TREE = {
    { { 'Max HP', 64, 15, 'Raises your maximum HP by 10 per level.' }, { 'Max MP', 66, 15, 'Raises your maximum MP by 10 per level.' }, { 'Max Merit', 68, 45, 'Raises how many merit points you can hold.' } },
    { { 'STR', 128, 15, 'Raises your STR by 1 per level.' }, { 'DEX', 130, 15, 'Raises your DEX by 1 per level.' }, { 'VIT', 132, 15, 'Raises your VIT by 1 per level.' }, { 'AGI', 134, 15, 'Raises your AGI by 1 per level.' }, { 'INT', 136, 15, 'Raises your INT by 1 per level.' }, { 'MND', 138, 15, 'Raises your MND by 1 per level.' }, { 'CHR', 140, 15, 'Raises your CHR by 1 per level.' } },
    { { 'Hand-to-Hand Skill', 192, 8, 'Raises your hand-to-hand skill by 2 per level.' }, { 'Dagger Skill', 194, 8, 'Raises your dagger skill by 2 per level.' }, { 'Sword Skill', 196, 8, 'Raises your sword skill by 2 per level.' }, { 'Great Sword Skill', 198, 8, 'Raises your great sword skill by 2 per level.' }, { 'Axe Skill', 200, 8, 'Raises your axe skill by 2 per level.' }, { 'Great Axe Skill', 202, 8, 'Raises your great axe skill by 2 per level.' }, { 'Scythe Skill', 204, 8, 'Raises your scythe skill by 2 per level.' }, { 'Polearm Skill', 206, 8, 'Raises your polearm skill by 2 per level.' }, { 'Katana Skill', 208, 8, 'Raises your katana skill by 2 per level.' }, { 'Great Katana Skill', 210, 8, 'Raises your great katana skill by 2 per level.' }, { 'Club Skill', 212, 8, 'Raises your club skill by 2 per level.' }, { 'Staff Skill', 214, 8, 'Raises your staff skill by 2 per level.' }, { 'Archery Skill', 216, 8, 'Raises your archery skill by 2 per level.' }, { 'Marksmanship Skill', 218, 8, 'Raises your marksmanship skill by 2 per level.' }, { 'Throwing Skill', 220, 8, 'Raises your throwing skill by 2 per level.' }, { 'Guarding Skill', 222, 8, 'Raises your guarding skill by 2 per level.' }, { 'Evasion Skill', 224, 8, 'Raises your evasion skill by 2 per level.' }, { 'Shield Skill', 226, 8, 'Raises your shield skill by 2 per level.' }, { 'Parrying Skill', 228, 8, 'Raises your parrying skill by 2 per level.' } },
    { { 'Divine Magic Skill', 256, 8, 'Raises your divine magic skill by 2 per level.' }, { 'Healing Magic Skill', 258, 8, 'Raises your healing magic skill by 2 per level.' }, { 'Enhancing Magic Skill', 260, 8, 'Raises your enhancing magic skill by 2 per level.' }, { 'Enfeebling Magic Skill', 262, 8, 'Raises your enfeebling magic skill by 2 per level.' }, { 'Elemental Magic Skill', 264, 8, 'Raises your elemental magic skill by 2 per level.' }, { 'Dark Magic Skill', 266, 8, 'Raises your dark magic skill by 2 per level.' }, { 'Summoning Magic Skill', 268, 8, 'Raises your summoning magic skill by 2 per level.' }, { 'Ninjutsu Skill', 270, 8, 'Raises your ninjutsu skill by 2 per level.' }, { 'Singing Skill', 272, 8, 'Raises your singing skill by 2 per level.' }, { 'String Instrument Skill', 274, 8, 'Raises your string instrument skill by 2 per level.' }, { 'Wind Instrument Skill', 276, 8, 'Raises your wind instrument skill by 2 per level.' }, { 'Blue Magic Skill', 278, 8, 'Raises your blue magic skill by 2 per level.' }, { 'Geomancy Skill', 280, 8, 'Raises your geomancy skill by 2 per level.' }, { 'Handbell Skill', 282, 8, 'Raises your handbell skill by 2 per level.' } },
    { { 'Enmity Increase', 320, 5, 'Raises the enmity you generate.' }, { 'Enmity Decrease', 322, 5, 'Lowers the enmity you generate.' }, { 'Critical Hit Rate', 324, 5, 'Raises the critical hit rate by 1% per level.' }, { 'Enemy Critical Hit Rate', 326, 5, 'Lowers the enemy critical hit rate by 1% per level.' }, { 'Spell Interruption Rate', 328, 5, 'Lowers the spell interruption rate by 2% per level.' } },
    { { 'Shijin Spiral', 1664, 5, nil, true }, { 'Exenterator', 1666, 5, nil, true }, { 'Requiescat', 1668, 5, nil, true }, { 'Resolution', 1670, 5, nil, true }, { 'Ruinator', 1672, 5, nil, true }, { 'Upheaval', 1674, 5, nil, true }, { 'Entropy', 1676, 5, nil, true }, { 'Stardiver', 1678, 5, nil, true }, { 'Blade: Shun', 1680, 5, nil, true }, { 'Tachi: Shoha', 1682, 5, nil, true }, { 'Realmrazer', 1684, 5, nil, true }, { 'Shattersoul', 1686, 5, nil, true }, { 'Apex Arrow', 1688, 5, nil, true }, { 'Last Stand', 1690, 5, nil, true } },
    { { 'Group 1' }, { 'Berserk Recast', 384, 5, 'Shortens Berserk\'s recast time by 10 seconds per level.' }, { 'Defender Recast', 386, 5, 'Shortens Defender\'s recast time by 6 seconds per level.' }, { 'Warcry Recast', 388, 5, 'Shortens Warcry\'s recast time by 10 seconds per level.' }, { 'Aggressor Recast', 390, 5, 'Shortens Aggressor\'s recast time by 10 seconds per level.' }, { 'Double Attack Rate', 392, 5, 'Raises the double attack rate by 1% per level.' }, { 'Group 2' }, { 'Warrior\'s Charge', 2048, 5, nil, true }, { 'Tomahawk', 2050, 5, nil, true }, { 'Savagery', 2052, 5, nil, true }, { 'Aggressive Aim', 2054, 5, nil, true } },
    { { 'Group 1' }, { 'Focus Recast', 448, 5, 'Shortens Focus\'s recast time by 4 seconds per level.' }, { 'Dodge Recast', 450, 5, 'Shortens Dodge\'s recast time by 4 seconds per level.' }, { 'Chakra Recast', 452, 5, 'Shortens Chakra\'s recast time by 6 seconds per level.' }, { 'Counter Rate', 454, 5, 'Raises the counter rate by 1% per level.' }, { 'Kick Attack Rate', 456, 5, 'Raises the kick attack rate by 1% per level.' }, { 'Group 2' }, { 'Mantra', 2112, 5, nil, true }, { 'Formless Strikes', 2114, 5, nil, true }, { 'Invigorate', 2116, 5, nil, true }, { 'Penance', 2118, 5, nil, true } },
    { { 'Group 1' }, { 'Divine Seal Recast', 512, 5, 'Shortens Divine Seal\'s recast time by 20 seconds per level.' }, { 'Cure Cast Time', 514, 5, nil }, { 'Bar Spell Effect', 516, 5, 'Enhances the effect of Bar Spell.' }, { 'Banish Effect', 518, 5, 'Enhances the effect of Banish.' }, { 'Regen Effect', 520, 5, 'Enhances the effect of Regen.' }, { 'Group 2' }, { 'Martyr', 2176, 5, nil, true }, { 'Devotion', 2178, 5, nil, true }, { 'Animus Solace', 2184, 5, nil, true }, { 'Animus Misery', 2186, 5, nil, true } },
    { { 'Group 1' }, { 'Elemental Seal Recast', 576, 5, 'Shortens Elemental Seal\'s recast time by 20 seconds per level.' }, { 'Fire Magic Potency', 578, 5, 'Enhances the potency of fire magic.' }, { 'Ice Magic Potency', 580, 5, 'Enhances the potency of ice magic.' }, { 'Wind Magic Potency', 582, 5, 'Enhances the potency of wind magic.' }, { 'Earth Magic Potency', 584, 5, 'Enhances the potency of earth magic.' }, { 'Lightning Magic Potency', 586, 5, 'Enhances the potency of lightning magic.' }, { 'Water Magic Potency', 588, 5, 'Enhances the potency of water magic.' }, { 'Group 2' }, { 'Ancient Magic Attack Bonus', 2252, 5, nil, true }, { 'Ancient Magic Burst Damage', 2254, 5, nil, true }, { 'Elemental Magic Accuracy', 2256, 5, 'Raises the accuracy of elemental magic.', true }, { 'Elemental Debuff Duration', 2258, 5, 'Extends the duration of elemental debuff.', true }, { 'Elemental Debuff Effect', 2260, 5, 'Enhances the effect of Elemental Debuff.', true }, { 'Aspir Absorption Amount', 2262, 5, nil, true } },
    { { 'Group 1' }, { 'Convert Recast', 640, 5, 'Shortens Convert\'s recast time by 20 seconds per level.' }, { 'Fire Magic Accuracy', 642, 5, 'Raises the accuracy of fire magic.' }, { 'Ice Magic Accuracy', 644, 5, 'Raises the accuracy of ice magic.' }, { 'Wind Magic Accuracy', 646, 5, 'Raises the accuracy of wind magic.' }, { 'Earth Magic Accuracy', 648, 5, 'Raises the accuracy of earth magic.' }, { 'Lightning Magic Accuracy', 650, 5, 'Raises the accuracy of lightning magic.' }, { 'Water Magic Accuracy', 652, 5, 'Raises the accuracy of water magic.' }, { 'Group 2' }, { 'Enfeebling Magic Duration', 2316, 5, 'Extends the duration of enfeebling magic.', true }, { 'Magic Accuracy', 2318, 5, 'Raises the accuracy of magic.', true }, { 'Enhancing Magic Duration', 2320, 5, 'Extends the duration of enhancing magic.', true }, { 'Immunobreak Chance', 2322, 5, nil, true }, { 'Enspell Damage', 2324, 5, nil, true }, { 'Accuracy', 2326, 5, nil, true } },
    { { 'Group 1' }, { 'Flee Recast', 704, 5, 'Shortens Flee\'s recast time by 10 seconds per level.' }, { 'Hide Recast', 706, 5, 'Shortens Hide\'s recast time by 10 seconds per level.' }, { 'Sneak Attack Recast', 708, 5, 'Shortens Sneak Attack\'s recast time by 2 seconds per level.' }, { 'Trick Attack Recast', 710, 5, 'Shortens Trick Attack\'s recast time by 2 seconds per level.' }, { 'Triple Attack Rate', 712, 5, 'Raises the triple attack rate by 1% per level.' }, { 'Group 2' }, { 'Assassin\'s Charge', 2368, 5, nil, true }, { 'Feint', 2370, 5, nil, true }, { 'Aura Steal', 2372, 5, nil, true }, { 'Ambush', 2374, 5, nil, true } },
    { { 'Group 1' }, { 'Shield Bash Recast', 768, 5, 'Shortens Shield Bash\'s recast time by 2 seconds per level.' }, { 'Holy Circle Recast', 770, 5, 'Shortens Holy Circle\'s recast time by 10 seconds per level.' }, { 'Sentinel Recast', 772, 5, 'Shortens Sentinel\'s recast time by 10 seconds per level.' }, { 'Cover Effect Length', 774, 5, nil }, { 'Rampart Recast', 776, 5, 'Shortens Rampart\'s recast time by 10 seconds per level.' }, { 'Group 2' }, { 'Fealty', 2432, 5, nil, true }, { 'Chivalry', 2434, 5, nil, true }, { 'Iron Will', 2436, 5, nil, true }, { 'Guardian', 2438, 5, nil, true } },
    { { 'Group 1' }, { 'Souleater Recast', 832, 5, 'Shortens Souleater\'s recast time by 12 seconds per level.' }, { 'Arcane Circle Recast', 834, 5, 'Shortens Arcane Circle\'s recast time by 10 seconds per level.' }, { 'Last Resort Recast', 836, 5, 'Shortens Last Resort\'s recast time by 10 seconds per level.' }, { 'Last Resort Effect', 838, 5, 'Enhances the effect of Last Resort.' }, { 'Weapon Bash Effect', 840, 5, 'Enhances the effect of Weapon Bash.' }, { 'Group 2' }, { 'Dark Seal', 2496, 5, nil, true }, { 'Diabolic Eye', 2498, 5, nil, true }, { 'Muted Soul', 2500, 5, nil, true }, { 'Desperate Blows', 2502, 5, nil, true } },
    { { 'Group 1' }, { 'Killer Effects', 896, 5, nil }, { 'Reward Recast', 898, 5, 'Shortens Reward\'s recast time by 3 seconds per level.' }, { 'Call Beast Recast', 900, 5, 'Shortens Call Beast\'s recast time by 10 seconds per level.' }, { 'Sic Recast', 902, 5, 'Shortens Sic\'s recast time by 2 seconds per level.' }, { 'Tame Recast', 904, 5, 'Shortens Tame\'s recast time by 20 seconds per level.' }, { 'Group 2' }, { 'Feral Howl', 2560, 5, nil, true }, { 'Killer Instinct', 2562, 5, nil, true }, { 'Beast Affinity', 2564, 5, nil, true }, { 'Beast Healer', 2566, 5, nil, true } },
    { { 'Group 1' }, { 'Lullaby Recast', 960, 5, 'Shortens Lullaby\'s recast time by 1 seconds per level.' }, { 'Finale Recast', 962, 5, 'Shortens Finale\'s recast time by 1 seconds per level.' }, { 'Minne Effect', 964, 5, 'Enhances the effect of Minne.' }, { 'Minuet Effect', 966, 5, 'Enhances the effect of Minuet.' }, { 'Madrigal Effect', 968, 5, 'Enhances the effect of Madrigal.' }, { 'Group 2' }, { 'Nightingale', 2624, 5, nil, true }, { 'Troubadour', 2626, 5, nil, true }, { 'Con Anima', 2632, 5, nil, true }, { 'Con Brio', 2634, 5, nil, true } },
    { { 'Group 1' }, { 'Scavenge Effect', 1024, 5, 'Enhances the effect of Scavenge.' }, { 'Camouflage Recast', 1026, 5, 'Shortens Camouflage\'s recast time by 10 seconds per level.' }, { 'Sharpshot Recast', 1028, 5, 'Shortens Sharpshot\'s recast time by 10 seconds per level.' }, { 'Unlimited Shot Recast', 1030, 5, 'Shortens Unlimited Shot\'s recast time by 6 seconds per level.' }, { 'Rapid Shot Rate', 1032, 5, 'Raises the rapid shot rate by 1% per level.' }, { 'Group 2' }, { 'Stealth Shot', 2688, 5, nil, true }, { 'Flashy Shot', 2690, 5, nil, true }, { 'Snapshot', 2692, 5, nil, true }, { 'Recycle', 2694, 5, nil, true } },
    { { 'Group 1' }, { 'Third Eye Recast', 1088, 5, 'Shortens Third Eye\'s recast time by 2 seconds per level.' }, { 'Warding Circle Recast', 1090, 5, 'Shortens Warding Circle\'s recast time by 10 seconds per level.' }, { 'Store TP Effect', 1092, 5, 'Enhances the effect of Store TP.' }, { 'Meditate Recast', 1094, 5, 'Shortens Meditate\'s recast time by 6 seconds per level.' }, { 'Zanshin Attack Rate', 1096, 5, 'Raises the zanshin attack rate by 1% per level.' }, { 'Group 2' }, { 'Shikikoyo', 2752, 5, nil, true }, { 'Blade Bash', 2754, 5, nil, true }, { 'Ikishoten', 2756, 5, nil, true }, { 'Overwhelm', 2758, 5, nil, true } },
    { { 'Group 1' }, { 'Subtle Blow Effect', 1152, 5, 'Enhances the effect of Subtle Blow.' }, { 'Katon Effect', 1154, 5, 'Enhances the effect of Katon.' }, { 'Hyoton Effect', 1156, 5, 'Enhances the effect of Hyoton.' }, { 'Huton Effect', 1158, 5, 'Enhances the effect of Huton.' }, { 'Doton Effect', 1160, 5, 'Enhances the effect of Doton.' }, { 'Raiton Effect', 1162, 5, 'Enhances the effect of Raiton.' }, { 'Suiton Effect', 1164, 5, 'Enhances the effect of Suiton.' }, { 'Group 2' }, { 'Sange', 2816, 5, nil, true }, { 'Ninja Tool Expertise', 2818, 5, nil, true }, { 'Yonin Effect', 2832, 5, 'Enhances the effect of Yonin.', true }, { 'Innin Effect', 2834, 5, 'Enhances the effect of Innin.', true }, { 'Ninjutsu Magic Accuracy', 2836, 5, 'Raises the accuracy of ninjutsu magic.', true }, { 'Ninjutsu Magic Bonus', 2838, 5, nil, true } },
    { { 'Group 1' }, { 'Ancient Circle Recast', 1216, 5, 'Shortens Ancient Circle\'s recast time by 10 seconds per level.' }, { 'Jump Recast', 1218, 5, 'Shortens Jump\'s recast time by 2 seconds per level.' }, { 'High Jump Recast', 1220, 5, 'Shortens High Jump\'s recast time by 4 seconds per level.' }, { 'Super Jump Recast', 1222, 5, 'Shortens Super Jump\'s recast time by 6 seconds per level.' }, { 'Spirit Link Recast', 1224, 5, 'Shortens Spirit Link\'s recast time by 3 seconds per level.' }, { 'Group 2' }, { 'Deep Breathing', 2880, 5, nil, true }, { 'Angon', 2882, 5, nil, true }, { 'Empathy', 2884, 5, nil, true }, { 'Strafe Effect', 2886, 5, 'Enhances the effect of Strafe.', true } },
    { { 'Group 1' }, { 'Avatar Physical Accuracy', 1280, 5, 'Raises the accuracy of avatar physical.' }, { 'Avatar Physical Attack', 1282, 5, nil }, { 'Avatar Magical Accuracy', 1284, 5, 'Raises the accuracy of avatar magical.' }, { 'Avatar Magical Attack', 1286, 5, nil }, { 'Summoning Magic Cast Time', 1288, 5, nil }, { 'Group 2' }, { 'Meteor Strike', 2944, 5, nil, true }, { 'Heavenly Strike', 2946, 5, nil, true }, { 'Wind Blade', 2948, 5, nil, true }, { 'Geocrush', 2950, 5, nil, true }, { 'Thunderstorm', 2952, 5, nil, true }, { 'Grandfall', 2954, 5, nil, true } },
    { { 'Group 1' }, { 'Chain Affinity Recast', 1344, 5, 'Shortens Chain Affinity\'s recast time by 4 seconds per level.' }, { 'Burst Affinity Recast', 1346, 5, 'Shortens Burst Affinity\'s recast time by 4 seconds per level.' }, { 'Monster Correlation', 1348, 5, nil }, { 'Physical Potency', 1350, 5, 'Enhances the potency of physical.' }, { 'Magical Accuracy', 1352, 5, 'Raises the accuracy of magical.' }, { 'Group 2' }, { 'Convergence', 3008, 5, nil, true }, { 'Diffusion', 3010, 5, nil, true }, { 'Enchainment', 3012, 5, nil, true }, { 'Assimilation', 3014, 5, nil, true } },
    { { 'Group 1' }, { 'Phantom Roll Recast', 1408, 5, 'Shortens Phantom Roll\'s recast time by 2 seconds per level.' }, { 'Quick Draw Recast', 1410, 5, 'Shortens Quick Draw\'s recast time by 2 seconds per level.' }, { 'Quick Draw Accuracy', 1412, 5, 'Raises the accuracy of quick draw.' }, { 'Random Deal Recast', 1414, 5, 'Shortens Random Deal\'s recast time by 40 seconds per level.' }, { 'Bust Duration', 1416, 5, 'Extends the duration of bust.' }, { 'Group 2' }, { 'Snake Eye', 3072, 5, nil, true }, { 'Fold', 3074, 5, nil, true }, { 'Winning Streak', 3076, 5, nil, true }, { 'Loaded Deck', 3078, 5, nil, true } },
    { { 'Group 1' }, { 'Automaton Skills', 1472, 5, nil }, { 'Maintenance Recast', 1474, 5, 'Shortens Maintenance\'s recast time by 3 seconds per level.' }, { 'Repair Effect', 1476, 5, 'Enhances the effect of Repair.' }, { 'Activate Recast', 1478, 5, 'Shortens Activate\'s recast time by 40 seconds per level.' }, { 'Repair Recast', 1480, 5, 'Shortens Repair\'s recast time by 3 seconds per level.' }, { 'Group 2' }, { 'Role Reversal', 3136, 5, nil, true }, { 'Ventriloquy', 3138, 5, nil, true }, { 'Fine Tuning', 3140, 5, nil, true }, { 'Optimization', 3142, 5, nil, true } },
    { { 'Group 1' }, { 'Step Accuracy', 1536, 5, 'Raises the accuracy of step.' }, { 'Haste Samba Effect', 1538, 5, 'Enhances the effect of Haste Samba.' }, { 'Reverse Flourish Effect', 1540, 5, 'Enhances the effect of Reverse Flourish.' }, { 'Building Flourish Effect', 1542, 5, 'Enhances the effect of Building Flourish.' }, { 'Group 2' }, { 'Saber Dance', 3200, 5, nil, true }, { 'Fan Dance', 3202, 5, nil, true }, { 'No Foot Rise', 3204, 5, nil, true }, { 'Closed Position', 3206, 5, nil, true } },
    { { 'Group 1' }, { 'Grimoire Recast', 1600, 5, 'Shortens Grimoire\'s recast time by 2 seconds per level.' }, { 'Modus Veritas Duration', 1602, 5, 'Extends the duration of modus veritas.' }, { 'Helix Magic Acc. / Att.', 1604, 5, nil }, { 'Max Sublimation', 1606, 5, nil }, { 'Group 2' }, { 'Altruism', 3264, 5, nil, true }, { 'Focalization', 3266, 5, nil, true }, { 'Tranquility', 3268, 5, nil, true }, { 'Equanimity', 3270, 5, nil, true }, { 'Enlightenment', 3272, 5, nil, true }, { 'Stormsurge', 3274, 5, nil, true } },
    { { 'Group 1' }, { 'Full Circle Effect', 1728, 5, 'Enhances the effect of Full Circle.' }, { 'Ecliptic Attrition Recast', 1730, 5, 'Shortens Ecliptic Attrition\'s recast time by 10 seconds per level.' }, { 'Life Cycle Recast', 1732, 5, 'Shortens Life Cycle\'s recast time by 20 seconds per level.' }, { 'Blaze Of Glory Recast', 1734, 5, 'Shortens Blaze Of Glory\'s recast time by 20 seconds per level.' }, { 'Dematerialize Recast', 1736, 5, 'Shortens Dematerialize\'s recast time by 20 seconds per level.' }, { 'Group 2' }, { 'Mending Halation', 3392, 5, nil, true }, { 'Radial Arcana', 3394, 5, nil, true }, { 'Curative Recantation', 3396, 5, nil, true }, { 'Primeval Zeal', 3398, 5, nil, true } },
    { { 'Group 1' }, { 'Rune Enhance', 1792, 5, nil }, { 'Vallation Effect', 1794, 5, 'Enhances the effect of Vallation.' }, { 'Lunge Effect', 1796, 5, 'Enhances the effect of Lunge.' }, { 'Pflug Effect', 1798, 5, 'Enhances the effect of Pflug.' }, { 'Gambit Effect', 1800, 5, 'Enhances the effect of Gambit.' }, { 'Group 2' }, { 'Battuta', 3456, 5, nil, true }, { 'Rayke', 3458, 5, nil, true }, { 'Inspiration', 3460, 5, nil, true }, { 'Sleight Of Sword', 3462, 5, nil, true } },
};
MERIT_TOTAL = { 45, 105, 152, 112, 10, 15, { 10, 10 }, { 10, 10 }, { 10, 10 }, { 10, 10 }, { 10, 10 }, { 10, 10 }, { 10, 10 }, { 10, 10 }, { 10, 10 }, { 10, 10 }, { 10, 10 }, { 10, 10 }, { 10, 10 }, { 10, 10 }, { 10, 10 }, { 10, 10 }, { 10, 10 }, { 10, 10 }, { 10, 10 }, { 10, 10 }, { 10, 10 }, { 10, 10 } };   -- (each category's most points in all; job categories: per group)
function MYROOM.merit_desc(e)                                         -- what a merit does: its line, or the game's own text for the ability
    if e[4] then return e[4]; end
    if MYROOM.desc_cache == nil then MYROOM.desc_cache = {}; end
    local c = MYROOM.desc_cache[e[2]];
    if c ~= nil then return c or nil; end
    local d = nil;
    pcall(function()
        local r = AshitaCore:GetResourceManager():GetAbilityByName(e[1], 0);
        if r and r.Description and r.Description[1] and r.Description[1] ~= '' then d = clean(r.Description[1]); end
    end);
    if d == nil then d = e[5] and ('Learn ' .. e[1] .. ', or make it stronger.') or nil; end
    MYROOM.desc_cache[e[2]] = d or false;
    return d;
end
function MYROOM.merit_tip(x, y, e, m, grp)                           -- the card beside the list, on its right
    local s = PSCALE() * 1.1;
    local fg = imgui.GetForegroundDrawList();
    local sw, sh = screen();
    local W = math.floor(330 * s);
    local d = MYROOM.merit_desc(e) or '';
    local tk = font(13 * s);
    local lines = wrap(d, W - 32 * s);
    unfont(tk);
    local H = math.floor((78 + #lines * 16 + (grp and 18 or 0)) * s);
    if x + W > sw - 4 then x = sw - W - 4; end
    y = math.max(4, math.min(sh - H - 4, y));
    for i = 3, 1, -1 do DL.RF(fg, x - i * 2, y - i * 2 + 3, x + W + i * 2, y + H + i * 2 + 3, U4(0, 0, 0, 0.08), 10 * s + i * 2); end
    DL.RF(fg, x, y, x + W, y + H, U4(0.045, 0.040, 0.065, 0.97), 9 * s);
    DL.R(fg, x, y, x + W, y + H, U4(0.62, 0.40, 1.0, 0.45), 9 * s, 0, 1);
    local p1, p2 = col(C.pink, 0.9), col(C.vio, 0.9);
    DL.RFM(fg, x + 10 * s, y, x + W - 10 * s, y + 2, p1, p2, p2, p1);
    DL.RF(fg, x + 6 * s, y + 12 * s, x + 8.5 * s, y + H - 12 * s, col(C.pink, 1), 2);
    tk = font(16 * s); text(fg, x + 16 * s, y + 10 * s, e[1], { 0.62, 1.0, 0.70, 1 }, 1); unfont(tk);
    local have, nxt = m and m[1] or 0, m and m[2] or 0;
    if nxt == 0 then nxt = UI.merit_next_cur or 0; end              -- (the cost the list worked out, when the server hasn't said)
    tk = font(13 * s);
    local mx_ = MYROOM.merit_cap(e, m);
    local pts = (e[3] == 0) and 'Not available on this server' or ('Points  %d / %d'):format(have, mx_);
    text(fg, x + 16 * s, y + 32 * s, pts, (e[3] == 0) and C.dim or C.gold, 1);
    local ns = (e[3] == 0) and '' or ((have >= mx_) and 'Maxed' or ((nxt > 0) and ('Next level: %d merit points'):format(nxt) or ''));
    text(fg, x + 16 * s, y + 49 * s, ns, C.acc, 1);
    local yy = y + 70 * s;
    for _, ln in ipairs(lines) do ETEXT(fg, x + 16 * s, yy, ln, C.text, 1); yy = yy + 16 * s; end
    if grp then text(fg, x + 16 * s, yy + 2 * s, grp, C.muted, 1); end
    unfont(tk);
end
MYROOM.MERITS = {};                                                 -- [merit id] = { count, next cost } from the server (packet 0x08C)
function MYROOM.merit_packet(d)
    local function b(o) return d:byte(o + 1) or 0; end
    local n = b(4) + b(5) * 256;
    for i = 0, math.min(n, 61) - 1 do
        local o = 8 + i * 4;
        MYROOM.MERITS[b(o) + b(o + 1) * 256] = { b(o + 3), b(o + 2) };
    end
end
function MYROOM.merit_level(id)                                      -- { points in it, next cost }: the game's own data, else the packet
    local now = os.clock();
    if MYROOM.vm_t == nil or now - MYROOM.vm_t > 0.5 then
        MYROOM.vm_t, MYROOM.vm = now, nil;
        pcall(function() if vana and vana.game and vana.game.merits then MYROOM.vm = vana.game.merits(); end end);
    end
    local v = MYROOM.vm and MYROOM.vm[id];
    if v then return { tonumber(v.count) or 0, tonumber(v.next) or 0 }; end
    return MYROOM.MERITS[id];
end
-- (what each next level costs, after LandSandBoat's upgrade_costs: used when the server hasn't said)
MERIT_COSTS = { { 1, 2, 3, 4, 5, 5, 5, 5, 5, 7, 7, 7, 9, 9, 9 }, { 3, 6, 9, 9, 9, 12, 12, 12, 12, 15, 15, 15, 15, 18, 18 },
                { 1, 2, 3, 3, 3, 3, 3, 3 }, { 1, 2, 3, 3, 3, 3, 3, 3 }, { 1, 2, 3, 4, 5 }, { 20, 22, 24, 27, 30 } };
MERIT_COSTS_JOB = { { 1, 2, 3, 4, 5 }, { 3, 4, 5, 5, 5 } };
-- CatsEyeXI's caps (from its players): per merit, by category; job categories 5 each
MERIT_CAT_CAP = { { [64] = 10, [66] = 10, [68] = 25 }, 10, 8, 16, 5 };
function MYROOM.merit_cap(e, m)                                       -- a merit's most points on CatsEyeXI
    local mx = e[3] or 0;
    local c = UI.merit_cat and MERIT_CAT_CAP[UI.merit_cat];
    if type(c) == 'table' then mx = c[e[2]] or mx; elseif c then mx = c; elseif (UI.merit_cat or 0) > 6 then mx = math.min(mx, 5); end
    m = m or MYROOM.merit_level(e[2]);
    if m and m[1] > mx then mx = m[1]; end                            -- (never less than what's in it)
    return mx;
end
function MYROOM.merit_points()
    local mp, mx, lp = 0, 0, 0;
    pcall(function() local pl = AshitaCore:GetMemoryManager():GetPlayer(); mp, mx, lp = pl:GetMeritPoints() or 0, pl:GetMeritPointsMax() or 0, pl:GetLimitPoints() or 0; end);
    return mp, mx, lp;
end
function MYROOM.merit1(w)
    local s = PSCALE();
    local cur = math.max(1, math.min(2, w.cursor));
    local mp, mx = MYROOM.merit_points();
    local lon = false;
    pcall(function() local v = AshitaCore:GetMemoryManager():GetPlayer():GetIsLimitModeEnabled(); lon = (v == true or v == 1); end);
    local rows = { { MYROOM.MERIT1[1][1], ('%d / %d'):format(mp, mx) }, { MYROOM.MERIT1[2][1], lon and 'Limit points' or 'Experience' } };
    local W = math.floor(300 * s);
    local native = cfg.follow and M.to_screen(w.rect) or nil;
    local sw = screen();
    local x, y = native and (native[3] - W) or (sw - W - 24), native and native[2] or 60;
    local clicked, wd = list_panel('merit1', x, y, W, 'MERIT POINTS', 'What to do?', rows, cur,
        { focused = (M.focus == w.addr), foot = MYROOM.MERIT1[cur][2] });
    if M.focus ~= w.addr then return; end
    if clicked then M.act(w.addr, clicked, (clicked == cur) and KEY.ok or nil); end
    if wd ~= 0 then local to = cur + wd; if to >= 1 and to <= 2 then M.act(w.addr, to, nil); end end
end
function MYROOM.meritcat(w)
    local s = PSCALE();
    local lf = list_fields(w);
    local top, count, page = 0, #MYROOM.MERITCAT, math.max(1, w.buttons);
    if lf then
        if (lf[5] or -1) >= 0 and (lf[5] or 0) < 200 then top = lf[5]; end
        if (lf[6] or 0) > 0 and (lf[6] or 0) < 200 then count = lf[6]; end
    end
    local cur = top + math.max(1, w.cursor);
    local cats = (count == #MYROOM.MERITCAT);                        -- (the same window shows the categories, then a category's merits)
    if cats and M.focus == w.addr then UI.merit_cat = cur; end
    local tree = (not cats) and UI.merit_cat and MERIT_TREE[UI.merit_cat] or nil;
    if tree and #tree ~= count then
        M.note('meritcat', ('category %s: the game lists %d, ChadcoreMenu knows %d: numbered'):format(tostring(UI.merit_cat), count, #tree)); tree = nil;
    end
    local rows = {};
    UI.merit_g2, UI.merit_next_cur = nil, nil;
    if tree then for i, e in ipairs(tree) do if e[2] == nil and e[1] == 'Group 2' then UI.merit_g2 = i; end end end
    for i = top + 1, math.min(count, top + page) do
        if cats then rows[#rows + 1] = { MYROOM.MERITCAT[i][1], '' };
        elseif tree then
            local e = tree[i];
            if e[2] == nil then rows[#rows + 1] = { '- ' .. e[1] .. ' -', '', nil, true };   -- (a group's heading)
            else
                local m = MYROOM.merit_level(e[2]);
                local right = '--';
                if e[3] ~= 0 then                                    -- (points / most, and what the next level costs - or MAX)
                    local have, cap = m and m[1] or 0, MYROOM.merit_cap(e, m);
                    if have >= cap and cap > 0 then right = ('%d / %d   MAX'):format(have, cap);
                    elseif m and m[2] > 0 then right = ('%d / %d   next %d'):format(have, cap, m[2]); if i == cur then UI.merit_next_cur = m[2]; end
                    elseif have < cap then                           -- (no word from the server: the standard cost)
                        local list = (UI.merit_cat or 0) <= 6 and MERIT_COSTS[UI.merit_cat] or MERIT_COSTS_JOB[(i > (UI.merit_g2 or 99)) and 2 or 1];
                        local c = list and list[have + 1];
                        right = c and ('%d / %d   next %d'):format(have, cap, c) or ('%d / %d'):format(have, cap);
                        if i == cur then UI.merit_next_cur = c; end
                    else right = ('%d / %d'):format(have, cap); end
                end
                rows[#rows + 1] = { e[1], right, nil, e[3] == 0 };
            end
        else rows[#rows + 1] = { 'Merit ' .. i, '' }; end
    end
    local mp, mx, lp = MYROOM.merit_points();
    local desc;
    if cats then desc = MYROOM.MERITCAT[cur] and MYROOM.MERITCAT[cur][2];
    else desc = (UI.merit_cat and MYROOM.MERITCAT[UI.merit_cat]) and MYROOM.MERITCAT[UI.merit_cat][1] or nil; end
    local W = math.floor(340 * s);
    -- (VanaCore draws these windows even when told not to, and moving them crashed the game: the panel sits over all three -
    --  the list, its points box and the description - so they're covered)
    local box = M.to_screen(w.rect);
    for _, w2 in ipairs(M.wins) do
        if w2.name == 'meritinf' or w2.name == 'bluehelp' then
            local r2 = M.to_screen(w2.rect);
            if r2 and box then box = { math.min(box[1], r2[1]), math.min(box[2], r2[2]), math.max(box[3], r2[3]), math.max(box[4], r2[4]) }; end
        end
    end
    local x, y = box and box[1] or 40, box and box[2] or 60;
    if box then W = math.max(W, math.floor((box[3] - box[1]) / 1.1) + 2); end
    UI.merit_box = box;
    local foot = ('Merit points %d / %d   Limit points %d'):format(mp, mx, lp);
    local grp = nil;
    if not cats and tree then                                        -- (the points used in the category / the group, of its most)
        local tot = MERIT_TOTAL[UI.merit_cat];
        local used, g, gi = { 0, 0 }, 1, 1;
        for i, e in ipairs(tree) do
            if e[2] == nil then g = (e[1] == 'Group 2') and 2 or 1;
            else local m = MYROOM.merit_level(e[2]); used[g] = used[g] + (m and m[1] or 0); end
            if i == cur then gi = g; end
        end
        if type(tot) == 'table' then
            foot = ('Group 1  %d / %d    Group 2  %d / %d    Merits %d'):format(used[1], tot[1], used[2], tot[2], mp);
            grp = ('Group %d: %d / %d points used'):format(gi, used[gi], tot[gi]);
        elseif tot then foot = ('Used %d / %d    Merit points %d / %d'):format(used[1], tot, mp, mx); end
    end
    local old_scale = cfg.scale;                                     -- (this list 10% bigger)
    cfg.scale = (tonumber(old_scale) or 1) * 1.1;
    local minr = page;
    if box then                                                      -- (tall enough to cover the description under the list)
        local s2 = cfg.scale;
        while (44 * s2 + minr * math.floor(23 * s2) + 28 * s2) < (box[4] - box[2]) + 6 and minr < 40 do minr = minr + 1; end
    end
    local sx_, sy_ = cfg.meritcat_x, cfg.meritcat_y;                 -- (always over the game's windows: not where it was dragged)
    cfg.meritcat_x, cfg.meritcat_y = -1, -1;
    local ok_, clicked, wd, rect = pcall(list_panel, 'meritcat', x, y, math.floor(W * 1.1), cats and 'MERIT CATEGORIES' or 'MERITS', desc or 'Spend your merit points', rows, cur - top,
        { focused = (M.focus == w.addr), foot = foot, min_rows = minr, scroll = { top, count, page } });
    cfg.scale = old_scale;
    cfg.meritcat_x, cfg.meritcat_y = sx_, sy_;
    if not ok_ then error(clicked); end
    if not cats and tree and tree[cur] and tree[cur][2] and rect then   -- (what the picked merit does: a card on the right)
        local RH = math.floor(23 * PSCALE() * 1.1);
        local ry = rect[2] + math.floor(44 * PSCALE() * 1.1) + (cur - top - 1) * RH;
        local tx, ty, te, tm = rect[1] + rect[3] + 12, ry - 10, tree[cur], MYROOM.merit_level(tree[cur][2]);
        imgui.SetNextWindowPos({ -10000, -10000 }, ImGuiCond_Always);     -- (a window to draw the card's text in: font calls outside one
        imgui.SetNextWindowSize({ 4, 4 }, ImGuiCond_Always);              --  make ImGui's Debug box)
        local o_ = imgui.Begin('##ccm_merittip', { true }, win_flags());
        UI.began = true;
        if o_ then MYROOM.merit_tip(tx, ty, te, tm, grp); end
        imgui.End();
        UI.began = false;
    end
    if M.focus ~= w.addr then return; end
    if clicked then M.act(w.addr, clicked, (top + clicked == cur) and KEY.ok or nil); end
    if wd ~= 0 then M.act(w.addr, nil, (wd < 0) and KEY.up or KEY.down); end
end
function MYROOM.jobinfo()
    local pl = AshitaCore:GetMemoryManager():GetPlayer();
    local mj, sj = pl:GetMainJob() or 0, pl:GetSubJob() or 0;
    return pl, mj, sj, pl:GetMainJobLevel() or 0, pl:GetSubJobLevel() or 0;
end
-- Change Jobs: Main Job / Support Job ("jobchang"), with what you are now
function MYROOM.jobchange(w)
    local s = PSCALE();
    local ok, pl, mj, sj, ml, sl = pcall(MYROOM.jobinfo);
    local function jl(j, l) return (ok and JOBS[j]) and (('%s  Lv.%d'):format(JOBS[j], l)) or ''; end
    local rows = { { 'Main Job', ok and jl(mj, ml) or '' }, { 'Support Job', ok and jl(sj, sl) or '' } };
    local cur = math.max(1, math.min(2, w.cursor));
    if M.focus == w.addr then UI.jobmode = cur; end                  -- (which one the job list is for: 1 main, 2 support)
    local W = math.floor(300 * s);
    local native = cfg.follow and M.to_screen(w.rect) or nil;
    local x, y = native and native[1] or 60, native and (native[2] - 40 * s) or 300;
    local clicked, wd = list_panel('jobchang', x, y, W, 'CHANGE JOBS', 'Which one?', rows, cur,
        { focused = (M.focus == w.addr), foot = (cur == 1) and 'Your main job.' or 'Your support job (half its level, up to your main\'s).' });
    if M.focus ~= w.addr then return; end
    if clicked then M.act(w.addr, clicked, KEY.ok); end
    if wd ~= 0 then local to = cur + wd; if to >= 1 and to <= 2 then M.act(w.addr, to, nil); end end
end
-- the Delivery Box's first choice ("mogpost"): Receive / Send. It follows the game's cursor.
function MYROOM.mogpost(w)
    local s = PSCALE();
    local rows = { { 'Receive', '>' }, { 'Send', '>' } };
    local cur = math.max(1, math.min(2, w.cursor));
    local n1 = 0; for _ in pairs(DLV.box[1]) do n1 = n1 + 1; end
    if n1 > 0 then rows[1][2] = tostring(n1); end
    local native = cfg.follow and M.to_screen(w.rect) or nil;
    local x, y = native and native[1] or 400, native and (native[2] - 60 * s) or 600;
    local clicked, wd = list_panel('mogpost', x, y, math.floor(260 * s), 'DELIVERY BOX', 'Receive or send?', rows, cur,
        { focused = (M.focus == w.addr), foot = (cur == 1) and 'Items others sent you.' or 'Send items to someone.' });
    if M.focus ~= w.addr then return; end
    if clicked then M.act(w.addr, clicked, KEY.ok); end
    if wd ~= 0 then local to = cur + wd; if to >= 1 and to <= 2 then M.act(w.addr, to, nil); end end
end
-- the moogle's menu outside the Mog House ("mogext", !mog): Storage / Delivery Box / Change Jobs. It follows the game's cursor.
MYROOM.EXT = { { 'Storage', 'Your Mog House storage.' }, { 'Delivery Box', 'Receive or send items.' }, { 'Change Jobs', 'Change your main or support job.' } };
function MYROOM.mogext(w)
    local s = PSCALE();
    local rows = {};
    for i, r in ipairs(MYROOM.EXT) do rows[i] = { r[1], '>' }; end
    local n1 = 0; pcall(function() for _ in pairs(DLV.box[1]) do n1 = n1 + 1; end end);
    if n1 > 0 then rows[2][2] = tostring(n1); end
    local cur = math.max(1, math.min(3, w.cursor));
    local native = cfg.follow and M.to_screen(w.rect) or nil;
    local x, y = native and native[1] or 400, native and (native[2] - 60 * s) or 600;
    local clicked, wd = list_panel('mogext', x, y, math.floor(260 * s), 'MOOGLE', 'What can I do for you, kupo?', rows, cur,
        { focused = (M.focus == w.addr), foot = MYROOM.EXT[cur][2] });
    if M.focus ~= w.addr then return; end
    if clicked then M.act(w.addr, clicked, KEY.ok); end
    if wd ~= 0 then local to = cur + wd; if to >= 1 and to <= 3 then M.act(w.addr, to, nil); end end
end
-- the job list ("jobcsel..."): every job with its emblem and level, two columns as the game lays them out; jobs you
-- haven't unlocked show as ???; your main job's level in gold, your support job's in blue. It follows the game's cursor.
function MYROOM.jobgrid(w)
    local s = PSCALE();
    local okp, pl, mj, sj = pcall(MYROOM.jobinfo);
    local bs = M.buttons(w);
    local list = {};
    for _, b in ipairs(bs) do if b.no >= 1 and b.no <= w.buttons then list[#list + 1] = b; end end
    table.sort(list, function(p, q) if p.y ~= q.y then return p.y < q.y; end return p.x < q.x; end);
    local cells = {};                                                -- (in the game's order: row by row, left then right = WAR, MNK, ...)
    for i, b in ipairs(list) do cells[i] = { no = b.no, job = i, locked = (b.status == 5) }; end
    if #cells == 0 then for i = 1, w.buttons do cells[i] = { no = i, job = i }; end end
    local P, RH = math.floor(16 * s), math.floor(34 * s);
    local CW = math.floor(214 * s);
    local nrow = math.ceil(#cells / 2);
    local HEAD = math.floor(50 * s);
    local W, H = 2 * CW + 2 * P + 8 * s, HEAD + nrow * RH + math.floor(34 * s);
    local native = cfg.follow and M.to_screen(w.rect) or nil;
    local sw, sh = screen();
    local x, y = saved_pos('jobgrid', native and native[1] or math.floor((sw - W) / 2), native and math.min(native[2], sh - H - 8) or 200, W, H);
    UI.jobgrid = UI.jobgrid or {};
    local st = UI.jobgrid;
    imgui.SetNextWindowPos({ x, y }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ W + 8, H + 8 }, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    UI.pushed = 2;
    local opened = imgui.Begin('##ccm_jobgrid', { true }, win_flags());
    UI.began = true;
    if opened then
        local dl = imgui.GetWindowDrawList();
        x, y = drag('jobgrid', x, y, x, y, x + W, y + HEAD);
        local hov_win = imgui.IsWindowHovered();
        local mx, my = mouse();
        panel(dl, x, y, x + W, y + H, 1, s);
        lock_button(dl, x + W - 26 * s, y + 8 * s, s, 1, hov_win);
        local tk = font(12 * s); caps(dl, x + P, y + 10 * s, 'CHANGE JOBS', C.acc, 2.5 * s, 1); unfont(tk);
        local mode = UI.jobmode;
        tk = font(16 * s); text(dl, x + P, y + 24 * s, (mode == 1) and 'Pick a main job' or ((mode == 2) and 'Pick a support job' or 'Pick a job'), C.text, 1); unfont(tk);
        local other = okp and ((mode == 1) and sj or ((mode == 2) and mj or nil)) or nil;   -- (the job in the other slot: a glowing dot)
        local hover, curi = nil, nil;
        for i, c in ipairs(cells) do
            local cc, rr = (i - 1) % 2, math.floor((i - 1) / 2);
            local cx0, cy0 = x + P + cc * (CW + 8 * s), y + HEAD + rr * RH;
            local cx1, cy1 = cx0 + CW, cy0 + RH - 4 * s;
            local lv = 0;
            if okp then pcall(function() lv = pl:GetJobLevel(c.job) or 0; end); end
            local locked = c.locked or (okp and lv == 0);
            local on = (c.no == w.cursor);
            if on then curi = i; end
            local hv = hov_win and not UI.move and inside(mx, my, cx0, cy0, cx1, cy1);
            if hv then hover = i; end
            if on then
                local p1, p2 = col(C.pink, 0.34), U4(C.vio[1], C.vio[2], C.vio[3], 0.0);
                DL.RFM(dl, cx0, cy0, cx1, cy1, p1, p2, p2, p1);
                DL.RF(dl, cx0, cy0 + 3, cx0 + 2.5 * s, cy1 - 3, col(C.pink, 1), 2);
            else
                DL.RF(dl, cx0, cy0, cx1, cy1, hv and U4(1, 1, 1, 0.07) or U4(1, 1, 1, 0.03), 6 * s);
            end
            local is = RH - 10 * s;
            local jx, jy = cx0 + 8 * s, cy0 + (RH - 4 * s - is) / 2;
            local jn = JOBS[c.job];
            if not locked and jn then image(dl, tex('jobs\\' .. jn:lower() .. '.png'), jx, jy, jx + is, jy + is, (c.job == mj) and 1 or 0.85); end
            tk = font(14.5 * s);
            local name = locked and '???' or (MYROOM.FULL[c.job] or ('Job ' .. c.job));
            local ty = cy0 + (RH - 4 * s - imgui.GetTextLineHeight()) / 2;
            text(dl, jx + is + 8 * s, ty, name, locked and C.dim or (on and C.text or { 0.84, 0.82, 0.92, 1 }), 1);
            local nw = tw(name);
            unfont(tk);
            if okp and (c.job == mj or c.job == sj) and not locked then  -- (glowing dots: gold your main job, blue your support job)
                local dc = (c.job == mj) and C.gold or { 1.00, 0.24, 0.72 };   -- (support: neon pink)
                local px_, py_ = jx + is + 8 * s + nw + 10 * s, cy0 + (RH - 4 * s) / 2;
                local pulse = 0.5 + 0.5 * math.sin(os.clock() * 3.2);
                DL.CF(dl, px_, py_, (6 + 2 * pulse) * s, col(dc, 0.18 + 0.12 * pulse), 16);
                DL.CF(dl, px_, py_, 3.2 * s, col(dc, 1), 12);
                DL.CF(dl, px_ - 0.9 * s, py_ - 0.9 * s, 1.1 * s, U4(1, 1, 1, 0.8), 8);
            end
            if not locked and lv > 0 then
                tk = font(12.5 * s);
                local ls = 'Lv.' .. lv;
                local lc = (c.job == mj) and C.gold or ((c.job == sj) and { 1.00, 0.36, 0.78, 1 } or C.acc);
                text(dl, cx1 - 10 * s - tw(ls), ty + 1.5 * s, ls, lc, 1);
                unfont(tk);
            end
        end
        if curi then                                                 -- (the arrow on the game's cursor)
            local cc, rr = (curi - 1) % 2, math.floor((curi - 1) / 2);
            local by = y + HEAD + rr * RH;
            local ax = x + P + cc * (CW + 8 * s);
            local asz = 23 * s * 0.62;
            local bob = cfg.anim and math.sin(os.clock() * 5) * 1.5 * s or 0;
            image(dl, tex('sel_arrow.png'), ax - asz - 2 * s + bob, by + (RH - 4 * s - asz) / 2, ax - 2 * s + bob, by + (RH - 4 * s + asz) / 2, 1);
        end
        tk = font(12 * s);
        local legend = 'Gold dot: your main job now.  Pink dot: your support job now.  ???: locked.';
        text(dl, x + P, y + H - 24 * s, legend, C.dim, 1);
        unfont(tk);
        if hov_win and not UI.move and M.focus == w.addr then
            if hover and imgui.IsMouseClicked(0) then
                local c = cells[hover];
                if c.no == w.cursor then M.act(w.addr, c.no, KEY.ok); else M.act(w.addr, c.no, nil); end
            end
            if imgui.IsMouseClicked(1) then M.act(nil, nil, KEY.cancel); end
        end
    end
    imgui.End();
    UI.began = false;
    imgui.PopStyleVar(2);
    UI.pushed = 0;
end

local function draw_storage(w)
    local s = PSCALE();
    local rows = {};
    for i = 1, math.min(w.buttons, #BAGS) do
        local c = UI.eq_slot and candidates(BAGS[i][1], UI.eq_slot) or nil;
        rows[i] = { BAGS[i][2], c and tostring(#c.all) or '' };
    end
    local W = math.floor(232 * s);
    local native = cfg.follow and M.to_screen(w.rect) or nil;
    local sw = screen();
    local x = native and (native[3] - W) or (sw - W - 24);
    local y = native and native[2] or 110;
    local cur = math.max(1, math.min(#rows, w.cursor));
    local clicked, wd = list_panel('storage', x, y, W, 'STORAGE', 'Pick a bag', rows, cur,
        { focused = (M.focus == w.addr), foot = cfg.clicks and 'Click a bag   Right-click: back' or nil });
    UI.store_cur = cur;
    if clicked then M.act(w.addr, clicked, KEY.ok); end
    if wd ~= 0 then local to = cur + wd; if to >= 1 and to <= #rows then M.act(w.addr, to, nil); end end
end

-- Check (another player): their gear, linkshell and bazaar. The game sends what the Check window shows in two packets:
-- 0x0C9 (mode 1: linkshell, jobs; mode 3: up to 8 pieces of gear at a time, with the slot) and 0x0CA (bazaar flag,
-- bazaar message, name, title). Layouts after LandSandBoat / atom0s's XiPackets. The game's own window ("inspect":
-- 16 gear buttons down each column, then View Wares) keeps running underneath, so the pad works it as always.
local item_tooltip;                                                  -- (further down)
local INS = { id = 0, gear = {}, t = -10 };
local INSM = { t = -10 };
local function ls_name(raw)                                          -- the 6-bit packed linkshell name (high bits first)
    local out = {};
    for i = 0, 19 do
        local bp = i * 6;
        local bi, off = math.floor(bp / 8) + 1, bp % 8;
        local w16 = (raw:byte(bi) or 0) * 256 + (raw:byte(bi + 1) or 0);
        local v = bit.band(bit.rshift(w16, 10 - off), 63);
        if v == 0 or v >= 60 then break; end
        local c;
        if v <= 26 then c = string.char(96 + v); elseif v <= 52 then c = string.char(64 + v - 26); else c = string.char(47 + v - 52); end
        out[#out + 1] = c;
    end
    return table.concat(out);
end
local function cstr(raw) return (raw:gsub('%z.*$', '')); end
-- The Linkshell menu (Commands > Linkshell: the game's "link5" list, "link6" its header): the linkshells and pearls in
-- your Inventory, the last slot first (as the game lists them), then the server's own pearl (CatsEyeXI's, always there). Each in its linkshell's colour
-- with its name (from the item's extra data: colour at +6, the 6-bit packed name at +9). Used only when that comes to
-- as many as the game lists and every name reads; it follows the game's cursor, a click picks.
LNK = {};
if cfg.lnk_swap == nil then cfg.lnk_swap = false; end            -- (off unless turned on)
LNK.KIND = { [513] = 'Linkshell', [514] = 'Pearlsack', [515] = 'Linkpearl' };
function LNK.decode(ext)
    if not ext or #ext < 0x18 then return nil; end
    local c = ext:byte(7) + ext:byte(8) * 256;                       -- (+6: red, green, blue, 4 bits each)
    local colr = { bit.band(c, 15) / 15, bit.band(bit.rshift(c, 4), 15) / 15, bit.band(bit.rshift(c, 8), 15) / 15, 1 };
    local nm = ls_name(ext:sub(0x0A, 0x0A + 15));
    if not nm or #nm < 1 or not nm:match('^[%w]+$') then return nil; end
    return nm, colr;
end
function LNK.list()
    local out, ok_all = {}, true;
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        for i = 1, 80 do
            local it = inv:GetContainerItem(0, i);
            if it and LNK.KIND[it.Id] then
                local ex = ext_string(it.Extra);
                local nm, colr = LNK.decode(ex);
                if not nm then ok_all = false; end
                if LNK.logged ~= os.date('%H%M') then                -- (what each pearl holds, to the log - once a minute at most)
                    M.note('lnkx' .. i .. os.clock(), ('linkshell item slot %d id %d name "%s" flags %d extra %s'):format(i, it.Id, tostring(nm), it.Flags or -1,
                        ex and (ex:gsub('.', function(ch) return ('%02X'):format(ch:byte()); end)) or '-'));
                end
                local lsid = ex and #ex >= 4 and (ex:byte(1) + ex:byte(2) * 256 + ex:byte(3) * 65536) or 0;
                out[#out + 1] = { kind = LNK.KIND[it.Id], name = nm or '?', color = colr, slot = i, on = (it.Flags or 0) == 19, id = it.Id, lsid = lsid };
            end
        end
    end);
    LNK.logged = os.date('%H%M');
    -- (the server's pearl: a linkshell you have on that isn't one of these)
    local have = {}; for _, e in ipairs(out) do have[e.name:lower()] = e; end
    pcall(function()                                                 -- (the ones you have on: by the linkshells you're in now)
        for sl = 1, 2 do
            local l = vana.game.linkshell(sl);
            local e_ = l and l.name and have[l.name:lower()];        -- (which slot: only for one the game marks as worn - what it
            if e_ and e_.on then e_.no = sl; end                      --  reports of linkshells can be from before)
        end
        if not LNK.vlog then
            LNK.vlog = true;
            local parts = {};
            for sl = 1, 2 do
                local l = vana.game.linkshell(sl);
                if l then local f = {}; for k, v in pairs(l) do f[#f + 1] = tostring(k) .. '=' .. tostring(v); end parts[#parts + 1] = sl .. ': ' .. table.concat(f, ' '); end
            end
            M.note('lnkv' .. os.clock(), 'vana linkshells: ' .. table.concat(parts, ' ; '));
        end
    end);
    local srv = nil;
    pcall(function()
        for sl = 1, 2 do
            local l = vana.game.linkshell(sl);
            if l and l.name and l.name ~= '' and not have[l.name:lower()] then
                local c = l.color;
                local colr = nil;
                if type(c) == 'table' then
                    local r_, g_, b_ = c.r or c.red or c[1] or 255, c.g or c.green or c[2] or 255, c.b or c.blue or c[3] or 255;
                    local mx_ = math.max(r_, g_, b_) <= 15 and 15 or 255;
                    colr = { r_ / mx_, g_ / mx_, b_ / mx_, 1 };
                elseif type(c) == 'number' then
                    colr = { bit.band(c, 15) / 15, bit.band(bit.rshift(c, 4), 15) / 15, bit.band(bit.rshift(c, 8), 15) / 15, 1 };
                end
                srv = { kind = 'Linkpearl', name = l.name, color = colr, server = true, on = true };
            end
        end
    end);
    LNK.sort(out);
    out[#out + 1] = srv or { kind = 'Linkpearl', name = 'CatsEyeXI', server = true };
    return ok_all and out or nil;
end
-- The order the game lists them in. Not the inventory slots (65 / 78 came up both ways round): the names are looked
-- for in the list window's own memory (as letters, or as the game's 2-byte glyphs) and taken in that order; if they
-- aren't there, last slot first with your No. 1 pearl after the others. The game's header (link6: the name of the row the
-- cursor is on) then checks it - a different name there and the order is turned round, for the rest of the session.
function LNK.sort(out)
    table.sort(out, function(a, b)                                   -- (No. 1, No. 2, then the rest by slot - what the game showed
        local ka, kb = a.no or 9, b.no or 9;                         --  last; it has shown the same two both ways round, so the
        if ka ~= kb then return ka < kb; end                         --  order can be swapped by hand: Settings, or /cmenu lsswap)
        return a.slot < b.slot;
    end);
    if cfg.lnk_swap == true then for i = 1, math.floor(#out / 2) do out[i], out[#out + 1 - i] = out[#out + 1 - i], out[i]; end end
    local w = M.find('link5');
    local pos, all = {}, false;
    if w and #out > 1 then
        local okp = pcall(function()
            all = true;
            local mp = rd32(w.addr + 0x0C);
            local blob = (mp >= FLOOR) and MCR.read(mp, 0x2000) or nil;
            if not blob then all = false; return; end
            for _, e in ipairs(out) do
                pos[e] = nil;
                local g = e.name:gsub('.', function(c) return string.char(c:byte() - 0x20, 0); end);
                local u = e.name:gsub('.', function(c) return c .. '\0'; end);
                local p_ = blob:find('\0' .. e.name .. '\0', 1, true) or blob:find(g, 1, true) or blob:find(u, 1, true);
                if not p_ then all = false; end
                pos[e] = p_ or 0;
            end
            if LNK.dumped ~= w.addr then
                LNK.dumped = w.addr;
                local f = {}; for _, e in ipairs(out) do f[#f + 1] = ('%s@%s'):format(e.name, tostring(pos[e])); end
                M.note('lnkord' .. os.clock(), ('link5 names in its memory: %s; head %s'):format(table.concat(f, ' '),
                    (blob:sub(1, 0x100):gsub('.', function(c) return ('%02X'):format(c:byte()); end))));
            end
        end);
        if not okp then all = false; end
    end
    if all then
        local seen = {}; for _, e in ipairs(out) do if seen[pos[e]] then all = false; end seen[pos[e]] = true; end
    end
    if all then table.sort(out, function(a, b) return pos[a] < pos[b]; end);
    elseif LNK.rev then for i = 1, math.floor(#out / 2) do out[i], out[#out + 1 - i] = out[#out + 1 - i], out[i]; end end
    LNK.from_mem = all;
end
function LNK.check(L, cur)                                           -- (the game's header against the row we have under the cursor)
    if LNK.from_mem then return; end
    local h6 = M.find('link6');
    if not h6 or not L[cur] or L[cur].server then return; end
    local gt = nil;
    pcall(function()
        local mp = rd32(h6.addr + 0x0C);
        if mp >= FLOOR then gt = QRY.gtitle(MCR.read(mp, 0x400)); end
    end);
    if not gt then return; end
    gt = gt:lower();
    local now = os.clock();                                          -- (the header can be a frame behind the cursor: only a
    if not LNK.ck or LNK.ck.cur ~= cur or LNK.ck.addr ~= h6.addr then LNK.ck = { cur = cur, t = now, addr = h6.addr }; return; end   --  difference that stays counts, once per opening)
    if now - LNK.ck.t < 0.4 or LNK.ck.done then return; end
    if gt == L[cur].name:lower() then LNK.ck.done = true; return; end
    LNK.ck.done = true;
    for _, e in ipairs(L) do
        if not e.server and e.name:lower() == gt then
            LNK.rev = not LNK.rev;
            M.note('lnkrev' .. os.clock(), ('linkshell header "%s", ours "%s": order turned round'):format(gt, L[cur].name));
            return;
        end
    end
end
-- The member list (Link List: the game's "link12"). The game keeps the members it was sent as 76-byte records, one
-- after another (found by searching its memory for names on the list): from the name (16 bytes) on, +0x18 nation
-- (0 San d'Oria, 1 Bastok, 2 Windurst), +0x19 race (1-8), +0x1A rank, +0x1C/1D main and sub job, +0x1E/1F their
-- levels, +0x24 zone, +0x38 / +0x3C the member's linkshells (their numbers). The list is found once a session (your
-- own name is always in it, among the records of the linkshell that's open), a little memory each frame so nothing
-- stalls; then it's read where it was. The linkshell all its members share is the one open: if that isn't the pearl
-- picked on our list, the pearls are the other way round (put right at once).
LNKM = { recs = nil };
LNKM.STRIDE = 0x4C;
LNKM.RACE = { 'Hum', 'Hum', 'Elv', 'Elv', 'Tar', 'Tar', 'Mit', 'Gal' };
LNKM.NATION = { [0] = { 0.95, 0.35, 0.35, 1 }, [1] = { 0.40, 0.60, 1.0, 1 }, [2] = { 0.45, 0.90, 0.45, 1 } };
function LNKM.rec(n)                                                 -- (the record whose name is at n, or nil)
    local b = MCR.read(n, 0x48);
    if not b or #b < 0x48 then return nil; end
    local nm = b:sub(1, 16):match('^([%w]+)%z');
    if not nm or #nm < 2 or #nm > 15 then return nil; end
    local nat, race, rank, mj, sj, ml, sl = b:byte(0x19), b:byte(0x1A), b:byte(0x1B), b:byte(0x1D), b:byte(0x1E), b:byte(0x1F), b:byte(0x20);
    if race > 8 or nat > 3 or mj > 22 or ml > 99 or sj > 22 or sl > 99 then return nil; end   -- (jobs 0: someone /anon)
    local function u32(o) local x, y, z, w = b:byte(o + 1, o + 4); return x + y * 256 + z * 65536 + w * 16777216; end
    return { name = nm, nation = nat, race = race, rank = rank, mj = mj, sj = sj, ml = ml, sl = sl, zone = b:byte(0x25) + b:byte(0x26) * 256,
             ls1 = u32(0x38), ls2 = u32(0x3C), at = n };
end
function LNKM.walk(n, myls)                                          -- (every record next to this one; the linkshell they share)
    local first = n;
    while LNKM.rec(first - LNKM.STRIDE) do first = first - LNKM.STRIDE; if n - first > LNKM.STRIDE * 400 then break; end end
    local L, cnt = {}, {};
    local at = first;
    while #L < 400 do
        local r = LNKM.rec(at);
        if not r then break; end
        L[#L + 1] = r;
        if r.ls1 ~= 0 then cnt[r.ls1] = (cnt[r.ls1] or 0) + 1; end
        if r.ls2 ~= 0 and r.ls2 ~= r.ls1 then cnt[r.ls2] = (cnt[r.ls2] or 0) + 1; end
        at = at + LNKM.STRIDE;
    end
    local shared = nil;
    for id, c in pairs(cnt) do if c == #L and (not myls or myls[id]) then shared = id; end end
    return L, shared, first;
end
function LNKM.myls()
    local t = {};
    pcall(function() for sl = 1, 2 do local l = vana.game.linkshell(sl); if l and l.id then t[l.id] = l.name or true; end end end);
    return t;
end
function LNKM.me()
    local me = '';
    pcall(function() me = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0) or ''; end);
    return me;
end
-- (the search: a slice of memory a frame; done = found or the whole of it looked through)
function LNKM.search_step()
    local S = LNKM.srch;
    if not S then return; end
    local mbi = ffi.new('CCM_MBI');
    local budget = 0x6000000;                                        -- (96 MB a frame)
    while budget > 0 do
        if not S.base or S.off >= S.size then
            if S.a >= 0x7FFF0000 then                                -- (from where it was last time to the end, then the rest)
                if S.start and S.start > 0x10000 and not S.wrapped then S.wrapped = true; S.a = 0x10000; S.stop = S.start;
                else S.done = true; return; end
            end
            if S.stop and S.a >= S.stop then S.done = true; return; end
            if ffi.C.VirtualQuery(ffi.cast('const void*', S.a), mbi, ffi.sizeof(mbi)) == 0 then S.done = true; return; end
            local base, size = tonumber(ffi.cast('uint32_t', mbi.BaseAddress)), tonumber(mbi.RegionSize);
            if size <= 0 then S.done = true; return; end
            S.a = base + size;
            local pr = mbi.Protect;
            if mbi.State == 0x1000 and bit.band(pr, 0x101) == 0 and bit.band(pr, 0xCC) ~= 0 and size < 0x10000000 then
                S.base, S.size, S.off = base, size, 0;
            else S.base = nil; end
        else
            local n = math.min(0x100000, S.size - S.off);
            local ok, chunk = pcall(ffi.string, ffi.cast('const char*', S.base + S.off), n);
            if ok and chunk then
                local at = 1;
                while true do
                    local p_ = chunk:find(S.key, at, true);
                    if not p_ then break; end
                    local addr = S.base + S.off + p_ - 1;          -- (the name: a record's start)
                    local L, shared = LNKM.walk(addr, S.myls);
                    S.hits = (S.hits or 0) + 1;
                    if S.hits <= 8 then
                        local r = LNKM.rec(addr);
                        local raw = MCR.read(addr, 0x4C);
                        M.note('lnkmhit' .. S.hits .. os.clock(), ('own name at %08X: record %s, %d in a row, shared %s; %s'):format(addr, r and 'yes' or 'no', #L, tostring(shared),
                            raw and (raw:gsub('.', function(c) return ('%02X'):format(c:byte()); end)) or '-'));
                    end
                    if shared and #L >= 1 then S.found = addr; S.done = true; return; end
                    at = p_ + 4;
                end
            end
            S.off = S.off + n;
            budget = budget - n;
        end
    end
end
function LNKM.update(w)
    local me = LNKM.me();
    if #me < 3 then return nil; end
    local myls = LNKM.myls();
    if LNKM.base then                                                -- (where it was last time: still a list with you in it?)
        local r = LNKM.rec(LNKM.base);
        if r then
            local L, shared, first = LNKM.walk(LNKM.base, myls);
            for _, x in ipairs(L) do if x.name == me and shared then LNKM.base = first; return L, shared; end end
        end
    end
    if not LNKM.srch then
        local hint = tonumber(cfg.lnkm_hint or 0) or 0;               -- (the list's place last time: looked at first)
        local st0 = (hint > 0x10000) and (hint - (hint % 0x1000000)) or 0x10000;
        LNKM.srch = { a = st0, start = st0, key = me .. string.rep('\0', 16 - #me), myls = myls, t = os.clock() };
    end
    if not LNKM.srch.done then
        pcall(LNKM.search_step);
        return nil;
    end
    local S = LNKM.srch;
    LNKM.srch = nil;
    if S.found then
        local L, shared, first = LNKM.walk(S.found, myls);
        LNKM.base = first;
        if cfg.lnkm_hint ~= first then cfg.lnkm_hint = first; pcall(save); end
        M.note('lnkmfound' .. os.clock(), ('member list found at %08X: %d members, linkshell %s (%.1f s)'):format(first, #L, tostring(shared), os.clock() - S.t));
        return L, shared;
    end
    M.note('lnkmfound' .. os.clock(), ('member list: not found in memory (%d places with your name; your linkshells %s)'):format(S.hits or 0,
        (function() local t = {}; for k, v in pairs(S.myls or {}) do t[#t + 1] = tostring(k) .. '=' .. tostring(v); end return table.concat(t, ','); end)()));
    LNKM.failed = (LNKM.failed or 0) + 1;
    return nil;
end
function LNKM.draw(w)
    local lf = list_fields(w);
    if not lf then return false; end
    if LNKM.win ~= w.addr then LNKM.win, LNKM.failed, LNKM.stable = w.addr, 0, nil; end   -- (each list a fresh try)
    if (LNKM.failed or 0) >= 2 then return false; end
    local cnt_ = lf[6] or 0;                                         -- (the game fills its list over a second or so: looked for
    if not LNKM.stable or LNKM.stable.n ~= cnt_ then LNKM.stable = { n = cnt_, t = os.clock() }; end   --  once it stops growing -
    local known = LNKM.base and LNKM.rec(LNKM.base);                  --  unless its place is known: then at once, filling as it fills)
    if cnt_ == 0 or (not known and os.clock() - LNKM.stable.t < 0.25) then return false; end
    local L, shared = LNKM.update(w);
    if not L then return false; end
    if #L == 0 then return false; end
    -- (the linkshell that's open: the pearl our list had picked should be it)
    local myls = LNKM.myls();
    local lname = (type(myls[shared]) == 'string') and myls[shared] or '';
    if LNKM.checked ~= w.addr and LNK.picked_ls and shared then
        LNKM.checked = w.addr;
        if LNK.picked_ls ~= shared then
            cfg.lnk_swap = not (cfg.lnk_swap == true); pcall(save);
            M.note('lnkswap' .. os.clock(), ('picked linkshell %d, the game opened %d: order swapped'):format(LNK.picked_ls, shared));
            msg('Linkpearl order corrected: the game had them the other way round.');
        end
    end
    local s = PSCALE();
    local top = (lf[5] or 0);
    local cur = top + math.max(1, w.cursor);
    local VIS = 10;
    local rows = {};
    for i = 1, VIS do
        local r = L[top + i];
        if r then
            local zn = '';
            pcall(function() zn = AshitaCore:GetResourceManager():GetString('zones.names', r.zone) or ''; end);
            local job = ('%s%d/%s%d'):format(JOBS[r.mj] or '?', r.ml, (r.sj > 0) and (JOBS[r.sj] or '?') or '', r.sl);
            if r.sj == 0 then job = ('%s%d'):format(JOBS[r.mj] or '?', r.ml); end
            if r.mj == 0 then job = 'anon'; end
            rows[i] = { r.name, '', dot = LNKM.NATION[r.nation] or C.acc, cols = { job, LNKM.RACE[r.race] or '', zn } };
        end
    end
    local nat = cfg.follow and M.to_screen(w.rect) or nil;
    local x, y = nat and nat[1] or 60, nat and (nat[2] - 60 * s) or 160;
    local sel = L[cur];
    local cols_ = { { 'NAME', 40 * s }, { 'JOB / LEVEL', 200 * s }, { 'RACE', 330 * s }, { 'LOCATION', 390 * s } };
    local clicked, wd = list_panel('linklist', x, y, math.floor(600 * s), 'LINK LIST', ((lname ~= '') and lname or 'Linkshell') .. ('   %d members'):format(#L), rows, cur - top,
        { focused = (M.focus == w.addr), foot = sel and ('%s  -  rank %d, %s'):format(sel.name, sel.rank, ({ [0] = 'San d\'Oria', 'Bastok', 'Windurst' })[sel.nation] or '') or nil, min_rows = VIS, cols = cols_ });
    if M.focus ~= w.addr then return true; end
    if clicked then M.act(w.addr, clicked, (top + clicked == cur) and KEY.ok or nil); end
    if wd ~= 0 then M.act(w.addr, nil, (wd > 0) and KEY.down or KEY.up); end
    return true;
end
-- What to do with a pearl (the game's "link4").
LNK.SUB = { { 'Set as No. 1', 'Wear it as your first linkshell.' }, { 'Set as No. 2', 'Wear it as your second linkshell.' }, { 'Drop', 'Throw this pearl away.' } };
LNK.SUB_ON = { { 'Link List', 'Who is in this linkshell.' }, { 'Unequip', 'Take this pearl off.' } };
-- (a pearl you have on: "link4", two buttons - Link List / Unequip; one you don't: "link13", three - Set as No. 1 / No. 2
--  / Drop, in the order they're drawn top to bottom. The little title tab is a button too, but a short one. Anything
--  else stays the game's)
function LNK.sub(w)
    local e = LNK.sel or {};
    local b = {};
    for _, x in ipairs(M.buttons(w)) do
        if (x.h or 0) >= 12 and (x.shape ~= 0 or x.user ~= 0) and x.no >= 1 and x.no <= w.buttons then b[#b + 1] = x; end
    end
    table.sort(b, function(p_, q_) if p_.y ~= q_.y then return p_.y < q_.y; end return p_.no < q_.no; end);
    local SUB = (#b == 3) and LNK.SUB or ((#b == 2) and LNK.SUB_ON or nil);
    if not SUB then
        if LNK.subnote ~= w.addr then LNK.subnote = w.addr; M.note('lnksub' .. os.clock(), ('link4: %d of %d buttons drawn: left to the game'):format(#b, w.buttons or -1)); end
        return false;
    end
    local s = PSCALE();
    local rows, cur = {}, 1;
    for i, r in ipairs(SUB) do rows[i] = { r[1], '' }; if b[i].no == w.cursor then cur = i; end end
    local native = cfg.follow and M.to_screen(w.rect) or nil;
    local W = math.floor(260 * s);
    local x, y = native and (native[3] - W) or 400, native and native[2] or 200;
    local clicked, wd = list_panel('linksub', x, y, W, 'LINKSHELL', e.name or 'Linkpearl', rows, cur,
        { focused = (M.focus == w.addr), foot = SUB[cur][2] });
    LNK.sub_ok = true;
    if M.focus ~= w.addr then return true; end
    if clicked then M.act(w.addr, b[clicked].no, KEY.ok); end
    if wd ~= 0 then local to = cur + wd; if to >= 1 and to <= #SUB then M.act(w.addr, b[to].no, nil); end end
    return true;
end
-- A small menu of the game's (a title tab and a few buttons) in the new style: its buttons as drawn top to bottom
-- (the title tab, a short button, left out) must come to as many as the labels given, or it stays the game's.
function SMALLMENU(w, key, title, sub, items)
    local b = {};
    for _, x in ipairs(M.buttons(w)) do
        if (x.h or 0) >= 12 and (x.shape ~= 0 or x.user ~= 0) and x.no >= 1 and x.no <= w.buttons then b[#b + 1] = x; end
    end
    table.sort(b, function(p_, q_) if p_.y ~= q_.y then return p_.y < q_.y; end return p_.no < q_.no; end);
    if #b ~= #items then return false; end
    local s = PSCALE();
    local rows, cur = {}, 1;
    for i, r in ipairs(items) do
        local off = (b[i].status == 5);                              -- (one the game greys out, e.g. Paste with nothing copied)
        rows[i] = { r[1], off and 'n/a' or '', nil, off };
        if b[i].no == w.cursor then cur = i; end
    end
    if type(sub) == 'function' then sub = sub(); end
    local native = cfg.follow and M.to_screen(w.rect) or nil;
    local W = math.floor(260 * s);
    local x, y = native and (native[3] - W) or 400, native and native[2] or 200;
    local clicked, wd = list_panel(key, x, y, W, title, sub, rows, cur, { focused = (M.focus == w.addr), foot = items[cur][2] });
    if M.focus ~= w.addr then return true; end
    if clicked then M.act(w.addr, b[clicked].no, KEY.ok); end
    if wd ~= 0 then local to = cur + wd; if to >= 1 and to <= #items then M.act(w.addr, b[to].no, nil); end end
    return true;
end
-- The macro book picker ("mcrselec": Commands > Macro > Edit Macro): 20 books a page, two pages (Left / Right). The
-- books' names are the game's own, from your character's mcr.ttl / mcr_2.ttl (24 bytes, then 20 names of 16). The
-- panel has the controller while it's up, so it knows which page is showing: Up / Down / Confirm / Cancel go to the
-- game's list as they are, Left / Right turn the page there too.
MSEL = { page = 1 };
function MSEL.names(page)
    MSEL.cache = MSEL.cache or {};
    local fo = (MCR.found and MCR.found.folder) or cfg.mcr_folder;
    if not fo then                                                   -- (your character's folder is its id in hex, e.g. 53312: d040)
        pcall(function()
            local id = AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0) or 0;
            local u_ = MCR.userdir();
            for _, cand in ipairs({ ('%x'):format(id), ('%x'):format(bit.band(id, 0xFFFF)) }) do
                local f_ = u_ and io.open(u_ .. cand .. '\\mcr.ttl', 'rb');
                if f_ then f_:close(); fo = cand; cfg.mcr_folder = cand; pcall(save); break; end
            end
        end);
    end
    if not fo then
        if not MSEL.noted then MSEL.noted = true; M.note('mcrsel' .. os.clock(), 'macro books: your character\'s folder not found: the game\'s list'); end
        return nil;
    end
    local key = fo .. page;
    local c = MSEL.cache[key];
    if c and os.clock() - c.t < 1.0 then return c.L; end            -- (read again every second: a book renamed shows at once)
    local u = MCR.userdir();
    if not u then return nil; end
    local f = io.open(u .. fo .. '\\' .. ((page == 1) and 'mcr.ttl' or 'mcr_2.ttl'), 'rb');
    if not f then return nil; end
    local d = f:read('*a'); f:close();
    if not d or #d < 24 + 20 * 16 then return nil; end
    local L = {};
    for i = 0, 19 do
        local nm = d:sub(25 + i * 16, 24 + (i + 1) * 16):gsub('%z.*', '');
        L[i + 1] = (nm ~= '') and nm or ('Book' .. string.format('%02d', (page - 1) * 20 + i + 1));
    end
    MSEL.cache[key] = { L = L, t = os.clock() };
    return L;
end
function MSEL.draw(w)
    if w.buttons ~= 23 then return false; end
    if MSEL.addr ~= w.addr then MSEL.addr, MSEL.page = w.addr, 1; end   -- (it opens on the first page)
    local L = MSEL.names(MSEL.page);
    if not L then return false; end
    local s = PSCALE();
    local cur = math.max(1, math.min(20, w.cursor));
    MSEL.book = (MSEL.page - 1) * 20 + cur;                          -- (the book picked: for its macros' screen)
    local now_book = MCR.found and MCR.found.book;
    local rows = {};
    for i, nm in ipairs(L) do
        local bk = (MSEL.page - 1) * 20 + i;
        rows[i] = { nm, (bk == now_book) and 'IN USE' or tostring(bk) };
    end
    local native = cfg.follow and M.to_screen(w.rect) or nil;
    local W = math.floor(280 * s);
    local x, y = native and (native[3] - W) or 400, native and native[2] or 120;
    local clicked, wd = list_panel('mcrsel', x, y, W, 'MACRO BOOKS', ('Page %d of 2  (books %d-%d)'):format(MSEL.page, (MSEL.page - 1) * 20 + 1, MSEL.page * 20), rows, cur,
        { focused = (M.focus == w.addr), foot = 'Left / Right: the other page.  Confirm: open the book.' });
    UI.msel_drawn = true;
    if M.focus ~= w.addr then return true; end
    if clicked then M.act(w.addr, clicked, (clicked == cur) and KEY.ok or nil); end
    if wd ~= 0 then local to = cur + wd; if to >= 1 and to <= 20 then M.act(w.addr, to, nil); end end
    return true;
end
function MSEL.pad(acts, w)
    for _, act in ipairs(acts) do
        local cur = math.max(1, math.min(20, w.cursor));
        if act == 'up' then M.act(w.addr, (cur > 1) and (cur - 1) or 20, nil); w.cursor = (cur > 1) and (cur - 1) or 20;
        elseif act == 'down' then M.act(w.addr, (cur < 20) and (cur + 1) or 1, nil); w.cursor = (cur < 20) and (cur + 1) or 1;
        elseif act == 'left' or act == 'right' or act == 'tabl' or act == 'tabr' then
            M.act(w.addr, nil, (act == 'left' or act == 'tabl') and KEY.left or KEY.right);
            MSEL.page = 3 - MSEL.page;
        elseif act == 'ok' then M.act(w.addr, cur, KEY.ok);
        elseif act == 'back' then M.act(nil, nil, KEY.cancel); end
    end
end
-- A macro's own page ("macro": Prev / Next, its name, its 6 lines; the game's "mcrledit" beside it). Which macro it is:
-- the one picked on the rows, and Prev / Next from there - the panel has the controller while it's up (Up / Down / Left /
-- Right / Confirm / Cancel go on to the game's page as they are), so it knows. Its name and lines are read from memory
-- (the set's own, as the rows were), so what you type shows as soon as the game takes it.
MED = {};
function MED.data()
    if not EDM.live_addr or not EDM.live_set then return nil; end
    local m = MCR.live_m(MCR.read(EDM.live_addr, 0x2000));
    return m;
end
function MED.draw(w)
    if w.buttons ~= 9 or not EDM.slot then return false; end
    if MED.addr ~= w.addr then MED.addr, MED.slot = w.addr, EDM.slot; end
    local m = MED.data();
    local mac = m and m[MED.slot] or { title = '', lines = {} };
    local s = PSCALE();
    local half, k = (MED.slot > 10) and 'Alt' or 'Ctrl', (MED.slot - 1) % 10 + 1;
    local label = ('%s %d'):format(half, k % 10);
    local cur = math.max(1, math.min(9, w.cursor));
    -- (Prev and Next on one line: the game's buttons 1 and 2; the line after it is button 3, and so on)
    local rows = { { (cur == 1) and '<  [ Prev ]' or '<  Prev', (cur == 2) and '[ Next ]  >' or 'Next  >', same = true },
                   { (mac.title ~= '') and mac.title or '(no name)', 'NAME', nil, mac.title == '' } };
    for l = 1, 6 do
        local t = mac.lines[l] or '';
        rows[#rows + 1] = { (t ~= '') and t or '-', 'LINE ' .. l, nil, t == '' };
    end
    local native = cfg.follow and M.to_screen(w.rect) or nil;
    local W = math.floor(460 * s);
    local x, y = native and native[1] or 60, native and native[2] or 120;
    local set = EDM.live_set;
    local sub = label .. (set and set.book and ('   Book %d%s'):format(set.book, set.set and ('  Set ' .. set.set) or '') or '');
    local row = (cur <= 2) and 1 or (cur - 1);
    local clicked, wd = list_panel('macroed', x, y, W, 'MACRO', sub, rows, row,
        { focused = (M.focus == w.addr), foot = (cur <= 2) and 'Left / Right: Prev or Next.  Confirm: turn to it.' or 'Confirm: type it.  Cancel: back.' });
    UI.med_drawn = true;
    if M.focus ~= w.addr then return true; end
    if clicked then
        local b = (clicked == 1) and ((cur <= 2) and cur or 1) or (clicked + 1);
        if b == cur then MED.press(w, cur); else M.act(w.addr, b, nil); end
    end
    return true;
end
function MED.press(w, b)                                             -- (Confirm on a button: Prev / Next turn the macro)
    if b == 1 then MED.slot = (MED.slot - 2) % 20 + 1; elseif b == 2 then MED.slot = MED.slot % 20 + 1; end
    M.act(w.addr, b, KEY.ok);
end
function MED.pad(acts, w)
    for _, act in ipairs(acts) do
        local cur = math.max(1, math.min(9, w.cursor));
        local row = (cur <= 2) and 1 or (cur - 1);                    -- (8 lines: Prev / Next, the name, 6 lines)
        if act == 'up' or act == 'down' then
            local r2 = (act == 'up') and ((row > 1) and (row - 1) or 8) or ((row < 8) and (row + 1) or 1);
            local to = (r2 == 1) and 1 or (r2 + 1);
            M.act(w.addr, to, nil); w.cursor = to;                   -- (the cursor put there directly)
        elseif act == 'left' and cur == 2 then M.act(w.addr, 1, nil); w.cursor = 1;
        elseif act == 'right' and cur == 1 then M.act(w.addr, 2, nil); w.cursor = 2;
        elseif act == 'tabl' then MED.press(w, 1);
        elseif act == 'tabr' then MED.press(w, 2);
        elseif act == 'ok' then MED.press(w, cur);
        elseif act == 'back' then M.act(nil, nil, KEY.cancel); end
    end
end
-- The equipment set picker ("mcres20": Commands > Macro > Edit Equip. Set): 200 sets, 20 a page, 10 pages (Left /
-- Right). Their names from your character's es0.dat - es9.dat (24 bytes, then 20 sets of 80: the name first, 16 letters;
-- no name: the game shows "Set014" and so on). Like the macro books: the panel has the controller, so it knows the page.
ESEL = { page = 1 };
function ESEL.names(page)
    ESEL.cache = ESEL.cache or {};
    local fo = (MCR.found and MCR.found.folder) or cfg.mcr_folder;
    if not fo then MSEL.names(1); fo = cfg.mcr_folder; end           -- (the folder found the books' way, if not yet known)
    if not fo then return nil; end
    local key = fo .. page;
    local c = ESEL.cache[key];
    if c and os.clock() - c.t < 1.0 then return c.L; end
    local u = MCR.userdir();
    if not u then return nil; end
    local f = io.open(u .. fo .. '\\es' .. (page - 1) .. '.dat', 'rb');
    local d = f and f:read('*a'); if f then f:close(); end
    local L = {};
    for i = 0, 19 do
        local nm = (d and #d >= 24 + (i + 1) * 80) and d:sub(25 + i * 80, 24 + i * 80 + 16):gsub('%z.*', '') or '';
        L[i + 1] = (nm ~= '' and not nm:find('[^\32-\126]')) and nm or ('Set%03d'):format((page - 1) * 20 + i + 1);
    end
    ESEL.cache[key] = { L = L, t = os.clock() };
    return L;
end
function ESEL.draw(w)
    if w.buttons ~= 23 then return false; end
    if ESEL.addr ~= w.addr then ESEL.addr, ESEL.page = w.addr, 1; end
    local L = ESEL.names(ESEL.page);
    if not L then return false; end
    local s = PSCALE();
    local cur = math.max(1, math.min(20, w.cursor));
    ESEL.set = (ESEL.page - 1) * 20 + cur;                           -- (the set picked: for its gear's screen)
    local rows = {};
    for i, nm in ipairs(L) do rows[i] = { nm, tostring((ESEL.page - 1) * 20 + i) }; end
    local native = cfg.follow and M.to_screen(w.rect) or nil;
    local W = math.floor(280 * s);
    local x, y = native and (native[3] - W) or 400, native and native[2] or 120;
    local clicked, wd = list_panel('eqsel', x, y, W, 'EQUIPMENT SETS', ('Page %d of 10  (sets %d-%d)'):format(ESEL.page, (ESEL.page - 1) * 20 + 1, ESEL.page * 20), rows, cur,
        { focused = (M.focus == w.addr), foot = 'Left / Right: other pages.  Confirm: edit the set.' });
    UI.esel_drawn = true;
    if M.focus ~= w.addr then return true; end
    if clicked then M.act(w.addr, clicked, (clicked == cur) and KEY.ok or nil); end
    if wd ~= 0 then local to = cur + wd; if to >= 1 and to <= 20 then M.act(w.addr, to, nil); end end
    return true;
end
function ESEL.pad(acts, w)
    for _, act in ipairs(acts) do
        local cur = math.max(1, math.min(20, w.cursor));
        if act == 'up' then M.act(w.addr, (cur > 1) and (cur - 1) or 20, nil); w.cursor = (cur > 1) and (cur - 1) or 20;
        elseif act == 'down' then M.act(w.addr, (cur < 20) and (cur + 1) or 1, nil); w.cursor = (cur < 20) and (cur + 1) or 1;
        elseif act == 'left' or act == 'tabl' then M.act(w.addr, nil, KEY.left); ESEL.page = (ESEL.page - 2) % 10 + 1;
        elseif act == 'right' or act == 'tabr' then M.act(w.addr, nil, KEY.right); ESEL.page = ESEL.page % 10 + 1;
        elseif act == 'ok' then M.act(w.addr, cur, KEY.ok);
        elseif act == 'back' then M.act(nil, nil, KEY.cancel); end
    end
end
-- A set's gear ("mcresed": Edit): the game's 16 boxes, 4 by 4 - its buttons go down each column (1-4 the first) - in
-- the equipment panel's style, each with the item in it. What's in the set: from its es#.dat (80 bytes a set: the name,
-- 16, then a 4-byte entry for each slot in the game's slot order, the item's number in its top 2 bytes; 0 or 2 =
-- nothing). Read again every second, so a change shows as soon as the game has saved it.
ESED = { shr = {} };
ESED.GRID = { { { 'Main', 0 }, { 'Sub', 1 }, { 'Range', 2 }, { 'Ammo', 3 } }, { { 'Head', 4 }, { 'Neck', 9 }, { 'Ear 1', 11 }, { 'Ear 2', 12 } },
              { { 'Body', 5 }, { 'Hands', 6 }, { 'Ring 1', 13 }, { 'Ring 2', 14 } }, { { 'Back', 15 }, { 'Waist', 10 }, { 'Legs', 7 }, { 'Feet', 8 } } };
function ESED.items(set)
    ESED.cache = ESED.cache or {};
    local c = ESED.cache[set];
    if c and os.clock() - c.t < 1.0 then return c.it; end
    local fo = cfg.mcr_folder;
    local u = MCR.userdir();
    local it = {};
    if fo and u then
        local f = io.open(u .. fo .. '\\es' .. math.floor((set - 1) / 20) .. '.dat', 'rb');
        local d = f and f:read('*a'); if f then f:close(); end
        local o = 24 + ((set - 1) % 20) * 80 + 16;
        if d and #d >= o + 64 then
            for k = 0, 15 do
                local b1, b2, b3, b4 = d:byte(o + k * 4 + 1, o + k * 4 + 4);
                local id = b3 + b4 * 256;
                if bit.band(b1, 1) == 1 and id > 0 and id < 65535 then it[k] = id; end
            end
        end
    end
    ESED.cache[set] = { it = it, t = os.clock() };
    return it;
end
function ESED.draw(w)
    if w.buttons ~= 16 or not ESEL.set then return false; end
    local s = PSCALE() * 1.25;                                       -- (a little bigger than the rest)
    local it = ESED.items(ESEL.set);
    local CS, G, P = math.floor(46 * s), math.floor(6 * s), math.floor(14 * s);
    local HEAD = math.floor(48 * s);
    local W = 4 * CS + 3 * G + 2 * P;
    local H = HEAD + 4 * (CS + math.floor(14 * s)) + 3 * G + P;
    local native = cfg.follow and M.to_screen(w.rect) or nil;
    local x, y = native and native[1] or 40, native and native[2] or 120;
    x, y = saved_pos('eqset', x, y, W, H);
    imgui.SetNextWindowPos({ x, y }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ W + 8, H + 8 }, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    UI.pushed = 2;
    local opened = imgui.Begin('##ccm_eqset', { true }, win_flags());
    UI.began = true;
    if opened then
        local dl = imgui.GetWindowDrawList();
        local hov_win = imgui.IsWindowHovered();
        local mx, my = mouse();
        x, y = drag('eqset', x, y, x, y, x + W, y + HEAD);
        panel(dl, x, y, x + W, y + H, 1, s);
        local tk = font(12 * s); caps(dl, x + P, y + 10 * s, 'EQUIPMENT SET', C.acc, 2.5 * s, 1); unfont(tk);
        local L = ESEL.names(math.floor((ESEL.set - 1) / 20) + 1);
        local nm = L and L[(ESEL.set - 1) % 20 + 1] or ('Set%03d'):format(ESEL.set);
        tk = font(15 * s); text(dl, x + P, y + 24 * s, nm, C.text, 1); unfont(tk);
        local cur = math.max(1, math.min(16, w.cursor));
        local hover, show = nil, nil;
        for r = 1, 4 do
            for c_ = 1, 4 do
                local b = (c_ - 1) * 4 + r;                          -- (the game's button: down each column)
                local g = ESED.GRID[r][c_];
                local bx, by = x + P + (c_ - 1) * (CS + G), y + HEAD + (r - 1) * (CS + math.floor(14 * s) + G);
                local hv = hov_win and not UI.move and inside(mx, my, bx, by, bx + CS, by + CS);
                if hv then hover = b; end
                local id = it[g[2]];
                DL.RF(dl, bx, by, bx + CS, by + CS, U4(0.115, 0.105, 0.155, 0.92), 7 * s);
                DL.R(dl, bx, by, bx + CS, by + CS, hv and U4(1, 1, 1, 0.30) or U4(0.62, 0.40, 1.0, 0.20), 7 * s, 0, 1);
                if id then image(dl, item_icon(id), bx + 5 * s, by + 5 * s, bx + CS - 5 * s, by + CS - 5 * s, 1); end
                local t_ = font(10.5 * s);
                text(dl, bx + (CS - tw(g[1])) / 2, by + CS + 1 * s, g[1], (b == cur) and C.pink or C.dim, 1);
                unfont(t_);
                if b == cur then sel_frame(dl, bx, by, bx + CS, by + CS, 7 * s, (M.focus == w.addr) and 1 or 0.5); end
                if (hv or (b == cur and not hover)) and id then show = id; end
            end
        end
        if hover and imgui.IsMouseClicked(0) then M.act(w.addr, hover, (hover == cur) and KEY.ok or nil); end
        if show and (M.focus == w.addr or hover) then item_tooltip(show, mx, my, { x + W + 8 * s, y, y }); end
    end
    imgui.End();
    UI.began = false;
    imgui.PopStyleVar(2);
    UI.pushed = 0;
    UI.esed_drawn = true;
    return true;
end
function ESED.shrink(w)                                              -- (its boxes at no size: the game finds its way by where they are)
    for _, b in ipairs(M.buttons(w)) do
        local ob = b.obj;
        if ob and not ESED.shr[ob] then ESED.shr[ob] = { w = b.w, h = b.h, win = w.addr }; end
        if ob and (b.w ~= 0 or b.h ~= 0) then ashita.memory.write_uint16(ob + 0x2E, 0); ashita.memory.write_uint16(ob + 0x30, 0); end
    end
end
function ESED.unshrink(open_)                                        -- (back to size while it's open; a closed one's are just forgotten)
    for ob, v in pairs(ESED.shr) do
        local w = M.open[v.win];
        if open_ and w and w.name == 'mcresed' then
            pcall(function() ashita.memory.write_uint16(ob + 0x2E, v.w); ashita.memory.write_uint16(ob + 0x30, v.h); end);
        end
    end
    ESED.shr = {};
end
SMALL = {                                                            -- (window, its panel: title, line under it, choices)
    mcrbedit = { 'MACRO', 'Lines', { { 'Copy Line', 'Copy this macro\'s line.' }, { 'Paste Line', 'Paste the copied line here.' },
                 { 'Delete Line', 'Clear this line.' } }, always = true, mode = 'nodraw', keep = true },   -- (beside the macros all the
                                                                     --  time while editing; the game finds its way between it and the
                                                                     --  rows by where they are: left in place, only not drawn)
    mcresmn = { 'EQUIPMENT SET', function()                           -- (what to do with the set picked)
            local w_ = M.find('mcres20');
            local L = ESEL.names(ESEL.page);
            return (w_ and L and L[math.max(1, math.min(20, w_.cursor))]) or 'Options';
        end, { { 'Edit', 'Change the gear in this set.' }, { 'Change Name', 'Rename this set.' }, { 'Copy', 'Copy this set.' },
              { 'Paste', 'Paste a copied set over this one.' }, { 'Delete', 'Clear this set.' },
              { 'Use Current', 'Save what you have on now as this set.' }, { 'Equip', 'Put this set on.' },
              { 'Style Lock', 'Lock your look to this set.' } } },
    mcrledit = { 'MACRO', 'Line', { { 'Copy Line', 'Copy this line.' }, { 'Paste Line', 'Paste the copied line here.' },
                 { 'Delete Line', 'Clear this line.' } }, always = true, mode = 'nodraw', keep = true },
    mcrmenu = { 'MACROS', 'Which to edit?', { { 'Edit Macro', 'Change a macro: its name and lines.' }, { 'Edit Equip. Set', 'Change an equipment set.' } } },
    mcrselop = { 'MACRO BOOK', function()                            -- (what to do with the book picked)
            local w_ = M.find('mcrselec');
            local L = MSEL.names(MSEL.page);
            return (w_ and L and L[math.max(1, math.min(20, w_.cursor))]) or 'Options';
        end, { { 'Confirm', 'Open this book to edit its macros.' }, { 'Change Name', 'Rename this book.' }, { 'Copy', 'Copy this book.' },
              { 'Paste', 'Paste a copied book over this one.' }, { 'Delete', 'Clear this book.' } } },
};
function LNK.draw(w)
    local s = PSCALE();
    local L = LNK.list();
    local lf = list_fields(w);
    if not L or not lf or lf[6] ~= #L then
        if LNK.noted ~= w.addr then LNK.noted = w.addr; M.note('lnk' .. os.clock(), ('linkshell list: game %s, ours %s: left to the game'):format(tostring(lf and lf[6]), tostring(L and #L))); end
        return false;
    end
    LNK.ok_now = true;
    local top = lf[5] or 0;
    local cur = math.max(1, math.min(#L, top + math.max(1, w.cursor)));
    local rows = {};
    for i, e in ipairs(L) do
        local tag = e.server and '   SERVER' or (e.no and ('   No. ' .. e.no) or (e.on and '   ON' or ''));
        rows[i] = { e.kind, e.name .. tag, nil, false, dot = e.color or (e.server and { 1.0, 0.45, 0.50, 1 }) or C.acc };
    end
    local native = cfg.follow and M.to_screen(w.rect) or nil;
    local x, y = native and native[1] or 60, native and (native[2] - 60 * s) or 160;
    LNK.check(L, cur);
    local sel = L[cur];
    LNK.sel = sel;
    local clicked, wd = list_panel('linkshell', x, y, math.floor(330 * s), 'LINKSHELL', sel and sel.name or 'Your linkshells', rows, cur,
        { focused = (M.focus == w.addr), foot = sel and (sel.server and 'The server\'s linkshell: always here.' or ((sel.on and 'Equipped.  ' or '') .. 'Wrong pearl opens? /cmenu lsswap')) or nil });
    if M.focus ~= w.addr then return true; end
    if clicked then
        local b = clicked - top;
        if b >= 1 and b <= (w.buttons or 10) then M.act(w.addr, b, (clicked == cur) and KEY.ok or nil); end
    end
    if wd ~= 0 then M.act(w.addr, nil, (wd > 0) and KEY.down or KEY.up); end
    return true;
end
function INS.packet(id, d)
    local function b(o) return d:byte(o + 1) or 0; end
    local function u16(o) return b(o) + b(o + 1) * 256; end
    local now = os.clock();
    if id == 0x0C9 then
        local uid = u16(4) + u16(6) * 65536;
        if uid ~= INS.id or now - INS.t > 3 then
            INS.id, INS.index, INS.gear, INS.ls, INS.lscol, INS.job, INS.ext = uid, u16(8), {}, nil, nil, nil, {};
        end
        INS.t = now;
        local mode = b(0x0A);
        if mode == 3 then
            for i = 0, math.min(8, b(0x0B)) - 1 do
                local o = 0x0C + i * 0x1C;
                local item, slot = u16(o), b(o + 2);
                if item > 0 and item ~= 65535 and slot < 16 then INS.gear[slot] = item; INS.ext = INS.ext or {}; INS.ext[slot] = d:sub(o + 5, o + 4 + 24); end
            end
        elseif mode == 1 then
            local name = (u16(0x0E) > 0) and ls_name(d:sub(0x11, 0x20)) or '';
            INS.ls = (name ~= '') and name or nil;
            local c = u16(0x20);
            INS.lscol = { bit.band(c, 15) / 15, bit.band(bit.rshift(c, 4), 15) / 15, bit.band(bit.rshift(c, 8), 15) / 15, 1 };
            INS.job, INS.sjob, INS.lv, INS.slv = b(0x22), b(0x23), b(0x24), b(0x25);
            pcall(function() M.note('check', ('ls "%s" raw %s'):format(INS.ls or '', (d:sub(0x0F, 0x22):gsub('.', function(c) return ('%02X'):format(c:byte()); end)))); end);
        end
    elseif id == 0x0CA then
        INSM.t = now;
        INSM.msg = cstr(d:sub(0x05, 0x05 + 122)):gsub('[\r\n\v]+', ' ');
        local f = b(0x04 + 123);
        INSM.bazaar = bit.band(f, 1) ~= 0;
        INSM.name = cstr(d:sub(0x81, 0x90));
        INSM.title = u16(0x90);
    end
end
-- the game's buttons: 1-16 the gear down each column, 17 View Wares; on screen row by row in GRID's order
local function ins_button(place) local c_, r_ = (place - 1) % 4, math.floor((place - 1) / 4); return c_ * 4 + r_ + 1; end
local function ins_place(btn) if btn < 1 or btn > 16 then return nil; end local c_, r_ = math.floor((btn - 1) / 4), (btn - 1) % 4; return r_ * 4 + c_ + 1; end
-- Trade with an NPC: the game's trade window ("handover": 8 item boxes, gil, Trade) is replaced by a list of your
-- Inventory. Confirm puts a stack in the trade (or takes it out), left / right change how many, and TRADE sends it all
-- with the game's own NPC trade request (packet 0x36: the NPC, then each inventory slot and count; gil is slot 0),
-- like Ashita / Windower trade addons do. The server checks it as usual. Trades with players keep the game's window.
local TRADE_MAX = 8;
local function trade_inv()
    local out = {};
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        local res = AshitaCore:GetResourceManager();
        for i = 1, 80 do
            local it = inv:GetContainerItem(0, i);
            if it and (it.Id or 0) ~= 0 and it.Id ~= 65535 and (it.Flags or 0) == 0 then
                local r = res:GetItemById(it.Id);
                out[#out + 1] = { idx = i, id = it.Id, count = it.Count or 1, name = (r and r.Name and r.Name[1]) or '?', stack = (r and tonumber(r.StackSize)) or 1, lv = r and tonumber(r.Level) };
            end
        end
    end);
    if sort_rows then out = sort_rows('trade', out, function(e) return e.name; end, function(e) return e.lv; end); end
    return out;
end
local function trade_send()
    local T_ = UI.trade;
    local qty, slots = {}, {};
    if (T_.gil or 0) > 0 then qty[#qty + 1], slots[#slots + 1] = T_.gil, 0; end
    for _, idx in ipairs(T_.order) do
        if #slots < 9 and (T_.items[idx] or 0) > 0 then qty[#qty + 1], slots[#slots + 1] = T_.items[idx], idx; end
    end
    if #slots == 0 then msg('Trade: nothing picked yet.'); return false; end
    local p = {};
    for i = 1, 0x40 do p[i] = 0; end
    local function put32(o, v) for b = 0, 3 do p[o + b + 1] = bit.band(bit.rshift(v, b * 8), 0xFF); end end
    put32(0x04, T_.npc_id);
    for i = 1, #slots do put32(0x08 + (i - 1) * 4, qty[i]); p[0x30 + (i - 1) + 1] = slots[i]; end
    p[0x3A + 1], p[0x3B + 1] = bit.band(T_.npc_idx, 0xFF), bit.rshift(T_.npc_idx, 8);
    p[0x3C + 1] = #slots;
    local ok, err = pcall(function() AshitaCore:GetPacketManager():AddOutgoingPacket(0x36, p); end);
    M.note('trade', ('%s: %d entries %s'):format(T_.npc_name or '?', #slots, ok and 'sent' or ('FAILED ' .. tostring(err))));
    if not ok then msg('Trade: could not send it (' .. tostring(err) .. ').'); end
    return ok;
end
local function trade_gil()
    local gil = 0;
    pcall(function() local g = AshitaCore:GetMemoryManager():GetInventory():GetContainerItem(0, 0); gil = g and g.Count or 0; end);
    return gil;
end
local function trade_count()
    local n = 0; for _ in pairs(UI.trade.items) do n = n + 1; end
    return n;
end
-- your Inventory (left window)
local function trade_rows()
    local T_ = UI.trade;
    local inv = trade_inv();
    T_.inv = inv;
    local rows = {};
    for _, e in ipairs(inv) do
        local q = T_.items[e.idx];
        rows[#rows + 1] = { e.name, q and (('IN TRADE x%d'):format(q)) or ((e.count > 1) and ('x' .. e.count) or ''), e.id, q ~= nil, idx = e.idx };
    end
    if #rows == 0 then rows[1] = { 'Nothing to trade', '', nil, true }; end
    return rows;
end
-- what you're trading (right window): the picked items, then Gil, then TRADE
local function trade_box_rows()
    local T_ = UI.trade;
    local rows = {};
    local by = {};
    for _, e in ipairs(T_.inv or {}) do by[e.idx] = e; end
    for _, idx in ipairs(T_.order) do
        local e = by[idx];
        if e then rows[#rows + 1] = { e.name, 'x' .. (T_.items[idx] or 0), e.id, false, idx = idx }; end
    end
    for i = #T_.order + 1, TRADE_MAX do rows[#rows + 1] = { '(empty)', '', nil, true, empty = true }; end
    rows[#rows + 1] = { 'Gil', ((T_.gil or 0) > 0) and tostring(T_.gil) or '0', nil, (T_.gil or 0) == 0, gil = true };
    rows[#rows + 1] = { 'TRADE', '', nil, trade_count() == 0 and (T_.gil or 0) == 0, send = true };
    rows[#rows + 1] = { 'Cancel', 'back out', nil, false, quit = true };
    return rows;
end
-- the amount picker: up / down 1, left / right 10 (gil 100), L1 / R1 100 (gil 10,000)
local function trade_open_pick(kind, e)
    local T_ = UI.trade;
    if kind == 'gil' then
        T_.pick = { kind = 'gil', max = trade_gil(), n = T_.gil or 0, name = 'Gil' };
    else
        if not T_.items[e.idx] and trade_count() >= TRADE_MAX then msg('Trade: 8 items at most.'); return; end
        if e.count <= 1 and not T_.items[e.idx] then                 -- (a single item: straight in)
            T_.items[e.idx] = 1; T_.order[#T_.order + 1] = e.idx;
            return;
        end
        T_.pick = { kind = 'item', idx = e.idx, id = e.id, name = e.name, max = e.count, n = T_.items[e.idx] or e.count };
    end
end
local function trade_pick_step(d)
    local P = UI.trade.pick;
    if P then P.n = math.max(0, math.min(P.max, P.n + d)); P.typed = true; end
end
local function trade_pick_done(ok)
    local T_ = UI.trade;
    local P = T_.pick;
    T_.pick = nil;
    if not ok or not P then return; end
    if P.kind == 'gil' then T_.gil = P.n; return; end
    local had = T_.items[P.idx] ~= nil;
    if P.n <= 0 then
        T_.items[P.idx] = nil;
        for i, v in ipairs(T_.order) do if v == P.idx then table.remove(T_.order, i); break; end end
    else
        T_.items[P.idx] = P.n;
        if not had then T_.order[#T_.order + 1] = P.idx; end
    end
end
local function trade_box_pick(r)                                     -- confirm on a row of the trade window
    local T_ = UI.trade;
    if not r or r.empty then return; end
    if r.quit then T_.closing, T_.close_at = 4, 0; return; end
    if r.send then
        if trade_send() then T_.closing, T_.close_at = 4, 0; end
    elseif r.gil then
        trade_open_pick('gil');
    elseif r.idx then
        for _, e in ipairs(T_.inv or {}) do
            if e.idx == r.idx then
                if e.count <= 1 then                                 -- (a single item: confirm takes it back out)
                    T_.items[e.idx] = nil;
                    for i, v in ipairs(T_.order) do if v == e.idx then table.remove(T_.order, i); break; end end
                else
                    trade_open_pick('item', e);
                end
            end
        end
    end
end
local function draw_trade_pick(x, y, W, s, P_, step_, done_, inwin)   -- (inwin: drawn inside the panel's own window, so it's on top of it)
    local P = P_ or (UI.trade and UI.trade.pick);
    if not P then return; end
    local trade_pick_step, trade_pick_done = step_ or trade_pick_step, done_ or trade_pick_done;
    local H = math.floor((P.unit and 172 or 150) * s);
    local px, py = x + 20 * s, y + 60 * s;
    local PW = W - 40 * s;
    local opened = true;
    if not inwin then
        imgui.SetNextWindowPos({ px, py }, ImGuiCond_Always);
        imgui.SetNextWindowSize({ PW + 8, H + 8 }, ImGuiCond_Always);
        imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
        imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
        UI.pushed = 2;
        opened = imgui.Begin('##ccm_tradepick', { true }, win_flags());
        UI.began = true;
    end
    if opened then
        local dl = imgui.GetWindowDrawList();
        local hov_win = imgui.IsWindowHovered();
        local mx, my = mouse();
        panel(dl, px, py, px + PW, py + H, 1, s);
        local tk = font(12 * s); caps(dl, px + 16 * s, py + 10 * s, 'HOW MANY?', C.acc, 2.5 * s, 1); unfont(tk);
        local tx = px + 16 * s;
        if P.id then image(dl, item_icon(P.id), tx, py + 28 * s, tx + 26 * s, py + 54 * s, 1); tx = tx + 34 * s; end
        tk = font(15 * s); text(dl, tx, py + 32 * s, P.name or '', C.text, 1); unfont(tk);
        -- the number, big, with - and + either side
        local ns = tostring(P.n);
        tk = font(30 * s);
        local cx, cy = px + PW / 2, py + 64 * s;
        text(dl, cx - tw(ns) / 2, cy, ns, (P.n > 0) and C.text or C.dim, 1);
        unfont(tk);
        tk = font(13 * s);
        local mt = '/ ' .. tostring(P.max);
        text(dl, cx - tw(mt) / 2, cy + 36 * s, mt, C.muted, 1);
        if P.unit then                                               -- (buying: what it comes to)
            local tot = P.unit * P.n;
            local ts = 'Total  ' .. tostring(math.floor(tot)):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '') .. ' G';
            text(dl, cx - tw(ts) / 2, cy + 56 * s, ts, C.gold, 1);
        end
        local big = (P.kind == 'gil') and 100 or 10;
        for _, bt in ipairs({ { -1, '-', px + 18 * s }, { 1, '+', px + PW - 48 * s } }) do
            local bx0, by0 = bt[3], cy + 2 * s;
            local hv = hov_win and inside(mx, my, bx0, by0, bx0 + 30 * s, by0 + 30 * s);
            DL.RF(dl, bx0, by0, bx0 + 30 * s, by0 + 30 * s, hv and col(C.pink, 0.45) or U4(1, 1, 1, 0.06), 6 * s);
            local tk2 = font(20 * s); text(dl, bx0 + 15 * s - tw(bt[2]) / 2, by0 + 3 * s, bt[2], C.text, 1); unfont(tk2);
            if hv and imgui.IsMouseClicked(0) then trade_pick_step(bt[1]); end
        end
        do                                                           -- OK
            local ox1, oy0 = px + PW - 14 * s, py + 10 * s;
            local ox0, oy1 = ox1 - 52 * s, oy0 + 24 * s;
            local hv = hov_win and inside(mx, my, ox0, oy0, ox1, oy1);
            DL.RF(dl, ox0, oy0, ox1, oy1, hv and col(C.pink, 0.50) or col(C.pink, 0.24), 7 * s);
            DL.R(dl, ox0, oy0, ox1, oy1, col(C.pink, 0.9), 7 * s, 0, 1);
            local lab = P.buy and 'BUY' or 'OK';
            local tk2 = font(12 * s); caps(dl, (ox0 + ox1) / 2 - caps_w(lab, 3 * s) / 2, oy0 + 5 * s, lab, C.text, 3 * s, 1); unfont(tk2);
            if hv and imgui.IsMouseClicked(0) then trade_pick_done(true); end
        end
        local hint = (P.kind == 'gil') and 'Type it, or Up / Down 1  Left / Right 100  L1 / R1 10k' or 'Type it, or Up / Down 1  Left / Right 10  L1 / R1 100';
        text(dl, px + PW / 2 - tw(hint) / 2, py + H - 24 * s, hint, C.dim, 1);
        unfont(tk);
        if hov_win then
            local wheel = imgui.GetIO().MouseWheel or 0;
            if wheel ~= 0 then trade_pick_step((wheel > 0) and 1 or -1); end
            if imgui.IsMouseClicked(1) then trade_pick_done(false); end
        end
        UI.trade_pick_big = big;
    end
    if inwin then return; end
    imgui.End();
    UI.began = false;
    imgui.PopStyleVar(2);
    UI.pushed = 0;
end
local function draw_trade(w)
    local s = PSCALE();
    local T_ = UI.trade;
    local rows = trade_rows();
    local box = trade_box_rows();
    local NV = 14;
    T_.focus = T_.focus or 'list';
    T_.cur = math.max(1, math.min(#rows, T_.cur or 1));
    T_.bcur = math.max(1, math.min(#box, T_.bcur or (#box - 1)));   -- (first time: on TRADE)
    if T_.cur < T_.off + 1 then T_.off = T_.cur - 1; elseif T_.cur > T_.off + NV then T_.off = T_.cur - NV; end
    T_.off = math.max(0, math.min(math.max(0, #rows - NV), T_.off));
    local vis = {};
    for i = T_.off + 1, math.min(#rows, T_.off + NV) do vis[#vis + 1] = rows[i]; end
    local W = math.floor(320 * s);
    local native = cfg.follow and M.to_screen(w.rect) or nil;
    local x = native and native[1] or 40;
    local y = native and native[2] or 120;
    local on_list, on_box = (T_.focus == 'list' and not T_.pick), (T_.focus == 'box' and not T_.pick);
    local cancel = function() if T_.pick then trade_pick_done(false); else T_.closing, T_.close_at = 4, 0; end end
    local clicked, wd, rect = list_panel('trade', x, y, W, 'INVENTORY', T_.npc_name and ('Trade with ' .. T_.npc_name) or 'Trade',
        vis, on_list and (T_.cur - T_.off) or nil,
        { icons = true, focused = on_list, min_rows = NV, scroll = { T_.off, #T_.inv, NV }, on_cancel = cancel,
          pill = { 'SORT ' .. (({ default = 'GAME', az = 'A-Z', level = 'LEVEL' })[cfg.sort_trade or 'default']), function() sort_next('trade'); end },
          foot = 'Confirm: pick how many.  Right: the trade.' });
    if clicked and not T_.pick then
        T_.focus, T_.cur = 'list', T_.off + clicked;
        local e = T_.inv[T_.cur];
        if e then trade_open_pick('item', e); end
    end
    if wd ~= 0 and not T_.pick then T_.cur = math.max(1, math.min(#rows, T_.cur + wd)); end
    local bx = rect and (rect[1] + rect[3] + 10 * s) or (x + W + 10 * s);
    local by = rect and rect[2] or y;
    local BW = math.floor(280 * s);
    local n = trade_count();
    local bclick, bwd = list_panel('tradebox', bx, by, BW, 'TRADING', ('%d / %d items'):format(n, TRADE_MAX), box, on_box and T_.bcur or nil,
        { icons = true, focused = on_box, on_cancel = cancel, foot = 'Confirm: change.  Left: items.  Cancel: back out.' });
    if bclick and not T_.pick then T_.focus, T_.bcur = 'box', bclick; trade_box_pick(box[bclick]); end
    if bwd ~= 0 and not T_.pick then T_.focus = 'box'; T_.bcur = math.max(1, math.min(#box, T_.bcur + bwd)); end
    T_.box = box;
    if T_.pick then draw_trade_pick(rect and rect[1] or x, rect and rect[2] or y, W, s); end
end

-- Home Points and Survival Guides: one big list of every place you can go (in columns, so nothing scrolls or pages).
-- The game's own menus are paged by the NPC's event; ChadcoreMenu reads the same event data the game gets (packet 0x34:
-- which places you've unlocked, your gil, the fee discount) and answers the event the way the game does when you pick
-- a place (packet 0x5B: Home Point "teleport" 2 + place << 16, Survival Guide "teleport" 1 + place << 16), after
-- LandSandBoat's homepoint / survival_guide scripts. The server checks everything as usual (unlocked, gil, distance).
local HP_DATA = {
    [0] = { 1, 1, 'Southern San d\'Oria #1' },
    [1] = { 1, 1, 'Southern San d\'Oria #2' },
    [2] = { 1, 1, 'Southern San d\'Oria #3' },
    [3] = { 1, 1, 'Northern San d\'Oria #1' },
    [4] = { 1, 1, 'Northern San d\'Oria #2' },
    [5] = { 1, 1, 'Northern San d\'Oria #3' },
    [6] = { 1, 1, 'Port San d\'Oria #1' },
    [7] = { 1, 1, 'Port San d\'Oria #2' },
    [8] = { 1, 1, 'Port San d\'Oria #3' },
    [9] = { 2, 1, 'Bastok Mines #1' },
    [10] = { 2, 1, 'Bastok Mines #2' },
    [11] = { 2, 1, 'Bastok Markets #1' },
    [12] = { 2, 1, 'Bastok Markets #2' },
    [13] = { 2, 1, 'Bastok Markets #3' },
    [14] = { 2, 1, 'Port Bastok #1' },
    [15] = { 2, 1, 'Port Bastok #2' },
    [16] = { 2, 1, 'Metalworks #1' },
    [17] = { 3, 1, 'Windurst Waters #1' },
    [18] = { 3, 1, 'Windurst Waters #2' },
    [19] = { 3, 1, 'Windurst Walls #1' },
    [20] = { 3, 1, 'Windurst Walls #2' },
    [21] = { 3, 1, 'Windurst Walls #3' },
    [22] = { 3, 1, 'Port Windurst #1' },
    [23] = { 3, 1, 'Port Windurst #2' },
    [24] = { 3, 1, 'Port Windurst #3' },
    [25] = { 3, 1, 'Windurst Woods #1' },
    [26] = { 3, 1, 'Windurst Woods #2' },
    [27] = { 3, 1, 'Windurst Woods #3' },
    [28] = { 3, 1, 'Windurst Woods #4' },
    [29] = { 4, 1, 'Ru\'Lude Gardens #1' },
    [30] = { 4, 1, 'Ru\'Lude Gardens #2' },
    [31] = { 4, 1, 'Ru\'Lude Gardens #3' },
    [32] = { 4, 1, 'Upper Jeuno #1' },
    [33] = { 4, 1, 'Upper Jeuno #2' },
    [34] = { 4, 1, 'Upper Jeuno #3' },
    [35] = { 4, 1, 'Lower Jeuno #1' },
    [36] = { 4, 1, 'Lower Jeuno #2' },
    [37] = { 4, 1, 'Port Jeuno #1' },
    [38] = { 4, 1, 'Port Jeuno #2' },
    [39] = { 0, 1, 'Kazham #1' },
    [40] = { 0, 1, 'Mhaura #1' },
    [41] = { 8, 1, 'Norg #1' },
    [42] = { 9, 1, 'Rabao #1' },
    [43] = { 0, 1, 'Selbina #1' },
    [44] = { 5, 1, 'Western Adoulin #1' },
    [45] = { 5, 1, 'Eastern Adoulin #1' },
    [46] = { 0, 2, 'Ceizak Battlegrounds #1' },
    [47] = { 0, 2, 'Foret de Hennetiel #1' },
    [48] = { 0, 2, 'Morimar Basalt Fields #1' },
    [49] = { 0, 2, 'Yorcia Weald #1' },
    [50] = { 0, 2, 'Marjami Ravine #1' },
    [51] = { 0, 2, 'Kamihr Drifts #1' },
    [52] = { 0, 2, 'Yughott Grotto #1' },
    [53] = { 0, 2, 'Palborough Mines #1' },
    [54] = { 0, 2, 'Giddeus #1' },
    [55] = { 0, 2, 'Fei\'Yin #1' },
    [56] = { 0, 2, 'Quicksand Caves #1' },
    [57] = { 0, 2, 'Den of Rancor #1' },
    [58] = { 0, 2, 'Castle Zvahl Keep #1' },
    [59] = { 0, 2, 'Ru\'Aun Gardens #1' },
    [60] = { 0, 2, 'Ru\'Aun Gardens #3' },
    [61] = { 0, 2, 'Ru\'Aun Gardens #2' },
    [62] = { 0, 2, 'Ru\'Aun Gardens #4' },
    [63] = { 0, 2, 'Ru\'Aun Gardens #5' },
    [64] = { 6, 1, 'Tavnazian Safehold #1' },
    [65] = { 7, 1, 'Aht Urhgan Whitegate #1' },
    [66] = { 0, 1, 'Nashmau #1' },
    [67] = { 0, 1, 'Al Zahbi #1 (DOESN\'T CURRENTLY EXIST)' },
    [68] = { 0, 1, 'Southern San d\'Oria [S] #1' },
    [69] = { 0, 1, 'Bastok Markets [S] #1' },
    [70] = { 0, 1, 'Windurst Waters [S] #1' },
    [71] = { 0, 2, 'Upper Delkfutt\'s Tower #1' },
    [72] = { 0, 2, 'The Shrine of Ru\'Avitau #1' },
    [73] = { 0, 2, 'Riverne - Site #B01 #1' },
    [74] = { 0, 2, 'Bhaflau Thickets #1' },
    [75] = { 0, 2, 'Caedarva Mire #1' },
    [76] = { 0, 2, 'Uleguerand Range #1' },
    [77] = { 0, 2, 'Uleguerand Range #2' },
    [78] = { 0, 2, 'Uleguerand Range #3' },
    [79] = { 0, 2, 'Uleguerand Range #4' },
    [80] = { 0, 2, 'Uleguerand Range #5' },
    [81] = { 0, 2, 'Attohwa Chasm #1' },
    [82] = { 0, 2, 'Pso\'Xja #1' },
    [83] = { 0, 2, 'Newton Movalpolos #1' },
    [84] = { 0, 2, 'Riverne - Site #A01 #1' },
    [85] = { 0, 2, 'Al\'Taieu #1' },
    [86] = { 0, 2, 'Al\'Taieu #2' },
    [87] = { 0, 2, 'Al\'Taieu #3' },
    [88] = { 0, 2, 'Grand Palace of Hu\'Xzoi #1' },
    [89] = { 0, 2, 'The Garden of Ru\'Hmet #1' },
    [90] = { 0, 2, 'Mount Zhayolm #1' },
    [91] = { 0, 2, 'Cape Teriggan #1' },
    [92] = { 0, 2, 'The Boyahda Tree #1' },
    [93] = { 0, 2, 'Den of Rancor #2' },
    [94] = { 0, 2, 'Fei\'Yin #2' },
    [95] = { 0, 2, 'Ifrit\'s Cauldron #1' },
    [96] = { 0, 2, 'Quicksand Caves #2' },
    [97] = { 1, 1, 'Southern San d\'Oria #4' },
    [98] = { 1, 1, 'Northern San d\'Oria #4' },
    [99] = { 2, 1, 'Bastok Mines #3' },
    [100] = { 2, 1, 'Bastok Markets #4' },
    [101] = { 2, 1, 'Port Bastok #3' },
    [102] = { 2, 1, 'Metalworks #2' },
    [103] = { 3, 1, 'Windurst Waters #3' },
    [104] = { 8, 1, 'Norg #2' },
    [105] = { 9, 1, 'Rabao #2' },
    [106] = { 7, 1, 'Aht Urhgan Whitegate #2' },
    [107] = { 7, 1, 'Aht Urhgan Whitegate #3' },
    [108] = { 7, 1, 'Aht Urhgan Whitegate #4' },
    [109] = { 5, 1, 'Western Adoulin #2' },
    [110] = { 5, 1, 'Eastern Adoulin #2' },
    [111] = { 0, 2, 'Xarcabard [S] #1' },
    [112] = { 0, 2, 'Leafallia #1' },
    [113] = { 0, 2, 'Castle Zvahl Keep [S] #1' },
    [114] = { 0, 1, 'Qufim Island #1' },
    [115] = { 0, 1, 'Toraimorai Canal #1' },
    [116] = { 0, 2, 'Ra\'Kaznar Inner Court #1' },
    [117] = { 0, 2, 'Misareaux Coast #1' },
    [118] = { 3, 1, 'Windurst Waters #4' },
    [119] = { 3, 1, 'Windurst Woods #5' },
    [120] = { 6, 1, 'Tavnazian Safehold #2' },
    [121] = { 6, 1, 'Tavnazian Safehold #3' },
};
local SG_DATA = {   -- [menu id] = { zone (LSB name), group, bit in the group }
    [6] = { 'WEST_RONFAURE', 1, 1 },
    [11] = { 'VALKURM_DUNES', 1, 2 },
    [16] = { 'JUGNER_FOREST', 1, 3 },
    [20] = { 'NORTH_GUSTABERG', 1, 4 },
    [24] = { 'PASHHOW_MARSHLANDS', 1, 5 },
    [28] = { 'WEST_SARUTABARUTA', 1, 6 },
    [33] = { 'BUBURIMU_PENINSULA', 1, 7 },
    [40] = { 'BEAUCEDINE_GLACIER', 1, 8 },
    [42] = { 'XARCABARD', 1, 9 },
    [44] = { 'QUFIM_ISLAND', 1, 10 },
    [36] = { 'MERIPHATAUD_MOUNTAINS', 1, 11 },
    [47] = { 'THE_SANCTUARY_OF_ZITAH', 1, 12 },
    [50] = { 'EASTERN_ALTEPA_DESERT', 1, 13 },
    [53] = { 'CAPE_TERIGGAN', 1, 14 },
    [57] = { 'YUHTUNGA_JUNGLE', 1, 15 },
    [61] = { 'YHOATOR_JUNGLE', 1, 16 },
    [66] = { 'LUFAISE_MEADOWS', 1, 17 },
    [64] = { 'RUAUN_GARDENS', 1, 18 },
    [65] = { 'OLDTON_MOVALPOLOS', 1, 19 },
    [8] = { 'BOSTAUNIEUX_OUBLIETTE', 1, 20 },
    [29] = { 'TORAIMARAI_CANAL', 1, 21 },
    [19] = { 'THE_ELDIEME_NECROPOLIS', 1, 22 },
    [27] = { 'CRAWLERS_NEST', 1, 23 },
    [39] = { 'GARLAIGE_CITADEL', 1, 24 },
    [0] = { 'NORTHERN_SAN_DORIA', 1, 25 },
    [1] = { 'BASTOK_MINES', 1, 26 },
    [2] = { 'PORT_WINDURST', 1, 27 },
    [3] = { 'RULUDE_GARDENS', 1, 28 },
    [10] = { 'LA_THEINE_PLATEAU', 1, 29 },
    [17] = { 'BATALLIA_DOWNS', 1, 30 },
    [12] = { 'KONSCHTAT_HIGHLANDS', 1, 31 },
    [25] = { 'ROLANBERRY_FIELDS', 1, 32 },
    [32] = { 'TAHRONGI_CANYON', 2, 1 },
    [37] = { 'SAUROMUGUE_CHAMPAIGN', 2, 2 },
    [7] = { 'FORT_GHELSBA', 2, 3 },
    [26] = { 'BEADEAUX', 2, 4 },
    [18] = { 'DAVOI', 2, 5 },
    [38] = { 'CASTLE_OZTROJA', 2, 6 },
    [43] = { 'CASTLE_ZVAHL_BAILEYS', 2, 7 },
    [41] = { 'RANGUEMONT_PASS', 2, 8 },
    [46] = { 'LOWER_DELKFUTTS_TOWER', 2, 9 },
    [9] = { 'KING_RANPERRES_TOMB', 2, 10 },
    [23] = { 'DANGRUF_WADI', 2, 11 },
    [30] = { 'INNER_HORUTOTO_RUINS', 2, 12 },
    [13] = { 'ORDELLES_CAVES', 2, 13 },
    [14] = { 'GUSGEN_MINES', 2, 14 },
    [34] = { 'MAZE_OF_SHAKHRAMI', 2, 15 },
    [48] = { 'ROMAEVE', 2, 16 },
    [51] = { 'WESTERN_ALTEPA_DESERT', 2, 17 },
    [62] = { 'TEMPLE_OF_UGGALEPIH', 2, 18 },
    [22] = { 'KORROLOKA_TUNNEL', 2, 19 },
    [55] = { 'KUFTAL_TUNNEL', 2, 20 },
    [58] = { 'SEA_SERPENT_GROTTO', 2, 21 },
    [56] = { 'GUSTAV_TUNNEL', 2, 22 },
    [35] = { 'LABYRINTH_OF_ONZOZO', 2, 23 },
    [15] = { 'CARPENTERS_LANDING', 2, 24 },
    [31] = { 'BIBIKI_BAY', 2, 25 },
    [67] = { 'MISAREAUX_COAST', 2, 26 },
    [68] = { 'PHOMIUNA_AQUEDUCTS', 2, 27 },
    [69] = { 'SACRARIUM', 2, 28 },
    [70] = { 'WAJAOM_WOODLANDS', 2, 29 },
    [71] = { 'MAMOOK', 2, 30 },
    [72] = { 'AYDEEWA_SUBTERRANE', 2, 31 },
    [78] = { 'EAST_RONFAURE_S', 2, 32 },
    [79] = { 'JUGNER_FOREST_S', 3, 1 },
    [85] = { 'VUNKERL_INLET_S', 3, 2 },
    [80] = { 'BATALLIA_DOWNS_S', 3, 3 },
    [83] = { 'NORTH_GUSTABERG_S', 3, 4 },
    [84] = { 'GRAUBERG_S', 3, 5 },
    [86] = { 'PASHHOW_MARSHLANDS_S', 3, 6 },
    [87] = { 'ROLANBERRY_FIELDS_S', 3, 7 },
    [90] = { 'WEST_SARUTABARUTA_S', 3, 8 },
    [91] = { 'FORT_KARUGO_NARUGO_S', 3, 9 },
    [92] = { 'MERIPHATAUD_MOUNTAINS_S', 3, 10 },
    [93] = { 'SAUROMUGUE_CHAMPAIGN_S', 3, 11 },
    [95] = { 'BEAUCEDINE_GLACIER_S', 3, 12 },
    [96] = { 'CASTLE_ZVAHL_BAILEYS_S', 3, 13 },
    [94] = { 'GARLAIGE_CITADEL_S', 3, 14 },
    [88] = { 'CRAWLERS_NEST_S', 3, 15 },
    [81] = { 'THE_ELDIEME_NECROPOLIS_S', 3, 16 },
    [59] = { 'KAZHAM', 3, 17 },
    [60] = { 'NORG', 3, 18 },
    [52] = { 'RABAO', 3, 19 },
    [4] = { 'TAVNAZIAN_SAFEHOLD', 3, 20 },
    [5] = { 'AHT_URHGAN_WHITEGATE', 3, 21 },
    [74] = { 'NASHMAU', 3, 22 },
    [77] = { 'SOUTHERN_SAN_DORIA_S', 3, 23 },
    [82] = { 'BASTOK_MARKETS_S', 3, 24 },
    [89] = { 'WINDURST_WATERS_S', 3, 25 },
    [76] = { 'CAEDARVA_MIRE', 3, 26 },
    [75] = { 'ARRAPAGO_REEF', 3, 27 },
    [73] = { 'HALVUNG', 3, 28 },
    [45] = { 'BEHEMOTHS_DOMINION', 3, 29 },
    [49] = { 'DRAGONS_AERY', 3, 30 },
    [54] = { 'VALLEY_OF_SORROWS', 3, 31 },
    [63] = { 'IFRITS_CAULDRON', 3, 32 },
    [21] = { 'ZERUHN_MINES', 4, 1 },
    [97] = { 'EASTERN_ADOULIN', 4, 2 },
};

local WARP = { ev = nil };
function WARP.packet(d)
    local function b(o) return d:byte(o + 1) or 0; end
    local function u16(o) return b(o) + b(o + 1) * 256; end
    local function u32(o) return u16(o) + u16(o + 2) * 65536; end
    local ev = { uid = u32(4), p = {}, idx = u16(0x28), zone = u16(0x2A), event = u16(0x2C), t = os.clock() };
    for i = 0, 7 do ev.p[i] = u32(0x08 + i * 4); end
    local nm = '';
    pcall(function() nm = AshitaCore:GetMemoryManager():GetEntity():GetName(ev.idx) or ''; end);
    if ev.event == 8500 or nm:find('Survival Guide', 1, true) then ev.kind = 'sg';
    elseif nm:find('Home Point', 1, true) or nm:find('HomePoint', 1, true) then ev.kind = 'hp'; end
    ev.name = nm;
    WARP.ev = ev.kind and ev or nil;
    if ev.kind then WARP.pending, WARP.cur, WARP.closing = nil, nil, nil; M.note('warp', ('%s event %d from %s'):format(ev.kind, ev.event, nm)); end
end
local function bitset(v, n) return bit.band(bit.rshift(v, n), 1) == 1; end
local ZONE_IDS = nil;
local function zone_id(lsbname)                                      -- (the game's own zone names, matched to LSB's)
    if ZONE_IDS == nil then
        ZONE_IDS = {};
        pcall(function()
            local res = AshitaCore:GetResourceManager();
            for id = 0, 300 do
                local n = res:GetString('zones.names', id);
                if n and n ~= '' then
                    local k = n:upper():gsub("['%.%-]", ''):gsub('%[S%]', 'S'):gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', '');
                    ZONE_IDS[k] = ZONE_IDS[k] or { id, n };
                end
            end
        end);
    end
    return ZONE_IDS[lsbname];
end
local function warp_rows()
    local ev = WARP.ev;
    local rows = {};
    if ev.kind == 'hp' then
        local p7 = ev.p[7];
        local origin = bit.band(p7, 0xFFFF);
        local ki = bitset(p7, 17);
        rows[#rows + 1] = { 'Set as your home point', '', opt = 1, set = true };
        local o = HP_DATA[origin];
        local first = {};                                            -- (each place's home points together, in the game's region order)
        for i = 0, 121 do local d = HP_DATA[i]; if d then local base = d[3]:gsub('%s*#%d+$', ''); first[base] = first[base] or i; end end
        local order = {};
        for i = 0, 121 do if HP_DATA[i] then order[#order + 1] = i; end end
        table.sort(order, function(a_, b_)
            local da, db = HP_DATA[a_][3], HP_DATA[b_][3];
            local fa, fb = first[da:gsub('%s*#%d+$', '')], first[db:gsub('%s*#%d+$', '')];
            if fa ~= fb then return fa < fb; end
            return (tonumber(da:match('#(%d+)$')) or 0) < (tonumber(db:match('#(%d+)$')) or 0);
        end);
        for _, i in ipairs(order) do
            local d = HP_DATA[i];
            if d and i ~= origin and bitset(ev.p[1 + math.floor(i / 32)], i % 32) then
                local cost = (o and d[1] == o[1] and d[1] ~= 0) and 0 or (500 * d[2]) / (ki and 5 or 1);
                rows[#rows + 1] = { d[3], (cost == 0) and 'free' or (math.floor(cost) .. 'g'), opt = 2 + i * 65536, cost = cost, hp = i };
            end
        end
        WARP.gil = ev.p[5];
    else
        local param = ev.p[1];
        local cur = bit.band(param, 0xFF);
        local ki, free = bitset(param, 13), bitset(param, 10);
        local cost = free and 0 or (ki and 200 or 1000);
        local list = {};
        for m, d in pairs(SG_DATA) do
            if m ~= cur and bitset(ev.p[2 + d[2]], d[3] - 1) then
                local z = zone_id(d[1]);
                local name = z and z[2] or d[1]:gsub('_', ' '):lower():gsub('(%a)(%w*)', function(a_, b_) return a_:upper() .. b_; end);
                list[#list + 1] = { m = m, g = d[2], gi = d[3], name = name };
            end
        end
        table.sort(list, function(a_, b_) if a_.g ~= b_.g then return a_.g < b_.g; end return a_.gi < b_.gi; end);
        for _, e in ipairs(list) do rows[#rows + 1] = { e.name, (cost == 0) and 'free' or (cost .. 'g'), opt = 1 + e.m * 65536, cost = cost, sg = e.m }; end
        WARP.gil = ev.p[2];
    end
    return rows;
end
local function warp_send(opt, update_first)
    local ev = WARP.ev;
    local function pk(mode)
        local p = {};
        for i = 1, 0x14 do p[i] = 0; end
        local function put(o, v, n) for b_ = 0, n - 1 do p[o + b_ + 1] = bit.band(bit.rshift(v, b_ * 8), 0xFF); end end
        put(0x04, ev.uid, 4); put(0x08, opt, 4); put(0x0C, ev.idx, 2); put(0x0E, mode, 2); put(0x10, ev.zone, 2); put(0x12, ev.event, 2);
        return p;
    end
    -- (as the game does it: the choice as an update first, then the same choice to finish)
    local ok, err = pcall(function()
        if update_first then AshitaCore:GetPacketManager():AddOutgoingPacket(0x5B, pk(1)); end
        AshitaCore:GetPacketManager():AddOutgoingPacket(0x5B, pk(0));
    end);
    M.note('warp', ('sent option 0x%X to %s: %s'):format(opt, ev.name or '?', ok and 'ok' or tostring(err)));
    return ok;
end
local function warp_pick(i)
    local rows = WARP.rows or {};
    local r = rows[i];
    if not r then return; end
    if WARP.pending ~= i then WARP.pending = i; return; end           -- (first confirm: asks; second: goes)
    if r.cost and (r.cost > (WARP.gil or 0)) then msg('Not enough gil for that.'); WARP.pending = nil; return; end
    if warp_send(r.opt, not r.set) then WARP.sent = true; WARP.closing, WARP.close_at = 8, os.clock() + 0.3; end
end
-- The teleport menus' map card: the place you're on, on its zone's map, with a glowing mark where the Home Point or
-- Survival Guide stands. Positions: warp_pos.lua (from LandSandBoat). The map: YunaUI's dark maps when YunaUI is
-- installed next to ChadcoreMenu and has that zone (read from its folder, never copied), else the game's own map from
-- its data files. Which map and where on it: the game's map table (zone, floor, scale, offset, map file), found in
-- FFXiMain.dll as boussole does (loonsies, github.com/loonsies/boussole); a map is 512 "map pixels" and a world spot
-- is at X * |scale| / 5, -Y * |scale| / 5, less the map's offset.
local WMAP = { tex = {}, order = {}, ents = {}, pick = {} };
function WMAP.data()
    if WMAP.pos == nil then
        WMAP.pos = false;
        pcall(function() local t = dofile(addon.path .. 'warp_pos.lua'); if type(t) == 'table' then WMAP.pos = t; end end);
    end
    return WMAP.pos or nil;
end
function WMAP.ydir()                                                 -- YunaUI's map folder, if it's installed
    if WMAP.yd == nil then
        WMAP.yd = false;
        for _, d in ipairs({ addon.path .. '..\\yunaui\\mapsimg\\', addon.path .. '..\\..\\vanacore\\yunaui\\mapsimg\\' }) do
            local f = io.open(d .. 'cover.lua', 'rb');
            if f then f:close(); WMAP.yd = d; break; end
        end
    end
    return WMAP.yd or nil;
end
function WMAP.cover(zone)                                            -- (YunaUI: which parts of each map have something drawn)
    if WMAP.cov == nil then
        WMAP.cov = false;
        local d = WMAP.ydir();
        if d then pcall(function() local t = dofile(d .. 'cover.lua'); if type(t) == 'table' then WMAP.cov = t; end end); end
    end
    return WMAP.cov and WMAP.cov[zone] or nil;
end
function WMAP.table_ptr()
    if WMAP.tp == nil then
        WMAP.tp = 0;
        pcall(function()
            local at = ashita.memory.find('FFXiMain.dll', 0, '8A0D????????5333C05684C95774??8A5424188B7424148B7C2410B9', 0, 0);
            if at ~= 0 then WMAP.tp = ashita.memory.read_uint32(at + 0x1C); end
        end);
    end
    return WMAP.tp;
end
function WMAP.entries(zone)                                          -- the map table's lines for this zone (one per floor)
    if WMAP.ents[zone] then return WMAP.ents[zone]; end
    local out = {};
    local tp = WMAP.table_ptr();
    if tp ~= 0 then
        pcall(function()
            for i = 0, 1999 do
                local b = tp + i * 0x0E;
                local z = ashita.memory.read_uint16(b);
                local dat = ashita.memory.read_uint16(b + 8);
                if z == 0 and dat == 0 and i > 10 then break; end
                if z == zone then
                    local sv = ashita.memory.read_uint8(b + 5);
                    out[#out + 1] = { zone = z, floor = ashita.memory.read_uint8(b + 2), flags = ashita.memory.read_uint8(b + 4),
                                      scale = (sv >= 0x80) and (sv - 0x100) or sv, dat = dat,
                                      ox = ashita.memory.read_int16(b + 0x0A), oy = ashita.memory.read_int16(b + 0x0C) };
                end
            end
        end);
    end
    WMAP.ents[zone] = out;
    return out;
end
function WMAP.to_map(e, wx, wy)
    local k = math.abs(e.scale) / 2560 * 512;
    return wx * k - e.ox, -wy * k - e.oy;
end
function WMAP.covered(e, wx, wy)
    local cv = WMAP.cover(e.zone);
    local h = cv and cv[e.floor];
    if not h then return nil; end                                    -- (nothing known)
    local mx, my = WMAP.to_map(e, wx, wy);
    local cx, cy = math.floor(mx / 8), math.floor(my / 8);
    for y_ = cy - 2, cy + 2 do
        for x_ = cx - 2, cx + 2 do
            if x_ >= 0 and x_ < 64 and y_ >= 0 and y_ < 64 then
                local b = y_ * 64 + x_;
                local nib = tonumber(h:sub(math.floor(b / 4) + 1, math.floor(b / 4) + 1), 16) or 0;
                if bit.band(nib, bit.lshift(1, 3 - b % 4)) ~= 0 then return true; end
            end
        end
    end
    return false;
end
function WMAP.best(zone, wx, wy)                                     -- the zone's map that shows the spot
    local key = zone .. ':' .. wx .. ':' .. wy;
    if WMAP.pick[key] ~= nil then return WMAP.pick[key] or nil; end
    local inb, first, cov = nil, nil, nil;
    for _, e in ipairs(WMAP.entries(zone)) do
        if e.scale ~= 0 then
            first = first or e;
            local mx, my = WMAP.to_map(e, wx, wy);
            if mx >= 8 and mx <= 504 and my >= 8 and my <= 504 then
                inb = inb or e;
                if cov == nil and WMAP.covered(e, wx, wy) then cov = e; end
            end
        end
    end
    local e = cov or inb or first;
    WMAP.pick[key] = e or false;
    return e;
end
function WMAP.texture(data, key)                               -- a picture in memory to a texture (kept, a few at a time)
    local ptr = ffi.new('IDirect3DTexture8*[1]');
    if ffi.C.D3DXCreateTextureFromFileInMemoryEx(d3d.get_device(), data, #data, 0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
            ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED, ffi.C.D3DX_DEFAULT, ffi.C.D3DX_DEFAULT, 0, nil, nil, ptr) == ffi.C.S_OK then
        local t = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', ptr[0]));
        return { tex = t, ptr = tonumber(ffi.cast('uint32_t', t)) };
    end
    return nil;
end
function WMAP.le32(v) return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256); end
function WMAP.dds_header(w, h, fourcc, pitch)                       -- a DDS file's header (DXT, or 32-bit colour with alpha)
    local flags = 0x1 + 0x2 + 0x4 + 0x1000 + (fourcc and 0x80000 or 0x8);
    local pf;
    if fourcc then pf = WMAP.le32(32) .. WMAP.le32(0x4) .. fourcc .. WMAP.le32(0) .. WMAP.le32(0) .. WMAP.le32(0) .. WMAP.le32(0) .. WMAP.le32(0);
    else pf = WMAP.le32(32) .. WMAP.le32(0x41) .. WMAP.le32(0) .. WMAP.le32(32) .. WMAP.le32(0x00FF0000) .. WMAP.le32(0x0000FF00) .. WMAP.le32(0x000000FF) .. WMAP.le32(0xFF000000); end
    return 'DDS ' .. WMAP.le32(124) .. WMAP.le32(flags) .. WMAP.le32(h) .. WMAP.le32(w) .. WMAP.le32(pitch) .. WMAP.le32(0) .. WMAP.le32(1) .. string.rep('\0', 44)
        .. pf .. WMAP.le32(0x1000) .. string.rep('\0', 16);
end
pcall(ffi.cdef, [[
    typedef struct FILE FILE;
    int fopen_s(FILE** pFile, const char* filename, const char* mode);
    int fclose(FILE* stream);
    int fseek(FILE* stream, long offset, int origin);
    long ftell(FILE* stream);
    size_t fread(void* buffer, size_t size, size_t count, FILE* stream);
]]);
function WMAP.read_file(path)                                        -- (the C runtime's fopen, as boussole does: works with XIPivot)
    local ok, data = pcall(function()
        local fp = ffi.new('FILE*[1]');
        if ffi.C.fopen_s(fp, path, 'rb') ~= 0 or fp[0] == nil then return nil; end
        local f = fp[0];
        ffi.C.fseek(f, 0, 2);
        local n = tonumber(ffi.C.ftell(f));
        ffi.C.fseek(f, 0, 0);
        if n == nil or n <= 0 then ffi.C.fclose(f); return nil; end
        local buf = ffi.new('uint8_t[?]', n);
        local got = tonumber(ffi.C.fread(buf, 1, n, f));
        ffi.C.fclose(f);
        if got ~= n then return nil; end
        return ffi.string(buf, n);
    end);
    if ok and data then return data; end
    local f = io.open(path, 'rb');
    if f == nil then return nil; end
    local d = f:read('*a'); f:close();
    return d;
end
function WMAP.dat_index(e)
    local low = bit.band(e.flags, 0x0F);
    return (low == 0) and (e.dat + 5312) or ((low == 1) and (e.dat + 53295) or ((low == 2) and (e.dat + 54295) or 5522));
end
function WMAP.game_map(e)                                            -- the game's own map picture (its data file), as a DDS
    local idx = WMAP.dat_index(e);                                   -- (returns nil and why, when it can't)
    local path = AshitaCore:GetResourceManager():GetFilePath(idx);
    if path == nil or path == '' then return nil, ('no file for dat %d'):format(idx); end
    local d = WMAP.read_file(path);
    if d == nil then return nil, ('could not read %s (dat %d)'):format(path, idx); end
    if #d < 0x41 + 44 then return nil, ('too small: %d bytes, %s'):format(#d, path); end
    local function u32(o) local a, b, c, e_ = d:byte(o + 1, o + 4); return a + b * 256 + c * 65536 + e_ * 16777216; end
    local w, h, bits, typ = u32(0x45), u32(0x49), d:byte(0x50) + d:byte(0x51) * 256, u32(0x41 + 40);
    local what = ('dat %d %s: %dx%d %d-bit type %08X, %d bytes'):format(idx, path, w, h, bits, typ, #d);
    if w <= 0 or h <= 0 or w > 4096 or h > 4096 then return nil, 'odd size, ' .. what; end
    local off = 0x41 + 44;                                           -- (the picture's header is 44 bytes)
    local DXT = { [0x44585431] = 'DXT1', [0x44585432] = 'DXT2', [0x44585433] = 'DXT3', [0x44585434] = 'DXT4', [0x44585435] = 'DXT5' };
    if DXT[typ] then                                                 -- DXT: as is
        local n = math.max(1, w / 4) * math.max(1, h / 4) * ((typ == 0x44585431) and 8 or 16);
        if #d < off + 8 + n then return nil, 'cut short, ' .. what; end
        return WMAP.dds_header(w, h, DXT[typ], n) .. d:sub(off + 8 + 1, off + 8 + n);
    end
    if typ ~= 0x0A or not (bits == 8 or bits == 16 or bits == 24 or bits == 32) then return nil, 'unknown kind, ' .. what; end
    local src = ffi.cast('const uint8_t*', d);
    local pal, po = nil, off;
    if bits == 8 then pal = po; po = po + 1024; end
    local bpp = bits / 8;
    if #d < po + w * h * bpp then return nil, 'cut short, ' .. what; end
    local f = 1;                                                     -- (HD maps, 2048 across: kept at 1024, plenty for the card)
    while w / f > 1024 and (w / f) % 2 == 0 and (h / f) % 2 == 0 do f = f * 2; end
    local ow, oh = w / f, h / f;
    local out = ffi.new('uint8_t[?]', ow * oh * 4);
    local function px(x, y)                                          -- (b, g, r, a of one source pixel; rows stored bottom first)
        local q = po + ((h - 1 - y) * w + x) * bpp;
        if bits == 8 then local s_ = pal + src[q] * 4; return src[s_], src[s_ + 1], src[s_ + 2], (src[s_ + 3] > 0) and 255 or 0; end
        if bits == 32 then return src[q], src[q + 1], src[q + 2], (src[q + 3] > 0) and 255 or 0; end
        if bits == 24 then return src[q], src[q + 1], src[q + 2], 255; end
        local v = src[q] + src[q + 1] * 256;
        return math.floor(bit.band(v, 0x1F) * 255 / 31), math.floor(bit.band(bit.rshift(v, 5), 0x3F) * 255 / 63),
               math.floor(bit.band(bit.rshift(v, 11), 0x1F) * 255 / 31), 255;
    end
    local n2 = f * f;
    for y = 0, oh - 1 do
        for x = 0, ow - 1 do
            local o = (y * ow + x) * 4;
            if f == 1 then
                out[o], out[o + 1], out[o + 2], out[o + 3] = px(x, y);
            else
                local sb, sg, sr, sa = 0, 0, 0, 0;
                for yy = y * f, y * f + f - 1 do
                    for xx = x * f, x * f + f - 1 do local b_, g_, r_, a_ = px(xx, yy); sb, sg, sr, sa = sb + b_, sg + g_, sr + r_, sa + a_; end
                end
                out[o], out[o + 1], out[o + 2], out[o + 3] = sb / n2, sg / n2, sr / n2, sa / n2;
            end
        end
    end
    return { w = ow, h = oh, buf = out };
end
function WMAP.raw_texture(img)                                       -- pixels straight into a texture (as boussole does)
    local t = nil;
    local ok = pcall(function()
        local dev = d3d.get_device();
        local hr, tx = dev:CreateTexture(img.w, img.h, 1, 0, ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED);
        if hr ~= ffi.C.S_OK or tx == nil then return; end
        local lr, rect = tx:LockRect(0, nil, 0);
        if lr ~= ffi.C.S_OK or rect == nil or rect.pBits == nil then tx:Release(); return; end
        local dst = ffi.cast('uint8_t*', rect.pBits);
        for y = 0, img.h - 1 do ffi.copy(dst + y * rect.Pitch, img.buf + y * img.w * 4, img.w * 4); end
        tx:UnlockRect(0);
        local g = d3d.gc_safe_release(tx);
        t = { tex = g, ptr = tonumber(ffi.cast('uint32_t', g)) };
    end);
    if ok and t then return t; end
    -- (no texture calls here: as a DDS file, else as a plain 32-bit bitmap)
    local t2 = WMAP.texture(WMAP.dds_header(img.w, img.h, nil, img.w * 4) .. ffi.string(img.buf, img.w * img.h * 4), 'raw');
    if t2 then return t2; end
    local n = img.w * img.h * 4;
    local rows = {};
    for y = img.h - 1, 0, -1 do rows[#rows + 1] = ffi.string(img.buf + y * img.w * 4, img.w * 4); end   -- (bitmaps: bottom row first)
    local le = WMAP.le32;
    local bmp = 'BM' .. le(54 + n) .. le(0) .. le(54) .. le(40) .. le(img.w) .. le(img.h) .. string.char(1, 0, 32, 0) .. le(0) .. le(n)
        .. le(2835) .. le(2835) .. le(0) .. le(0) .. table.concat(rows);
    return WMAP.texture(bmp, 'raw');
end
function WMAP.why(r)                                                 -- (for /cmenu warpmap test: what the card would show, or why not)
    local P_ = WMAP.data();
    if P_ == nil then return 'warp_pos.lua missing'; end
    local p = (r.hp and P_.hp[r.hp]) or (r.sg and P_.sg[r.sg]);
    if p == nil then return 'no position known'; end
    if WMAP.table_ptr() == 0 then return 'map table not found'; end
    local ents = WMAP.entries(p[1]);
    if #ents == 0 then return ('zone %d: no maps in the map table'):format(p[1]); end
    local e = WMAP.best(p[1], p[2], p[3]);
    if e == nil then return ('zone %d: %d maps, none usable'):format(p[1], #ents); end
    local mx, my = WMAP.to_map(e, p[2], p[3]);
    local head = ('zone %d floor %d (of %d) scale %d at %.0f,%.0f'):format(p[1], e.floor, #ents, e.scale, mx, my);
    local yd = (cfg.warp_map ~= 'game') and WMAP.ydir() or nil;
    if yd then local f = io.open(yd .. e.zone .. '_' .. e.floor .. '.png', 'rb'); if f then f:close(); return head .. ': YunaUI map'; end end
    local data, why = WMAP.game_map(e);
    if data then return head .. (': game map ok (dat %d)'):format(WMAP.dat_index(e)); end
    return head .. ': ' .. tostring(why);
end
function WMAP.test()
    local n, bad = 0, 0;
    local function one(label, r) n = n + 1; local ok, w_ = pcall(WMAP.why, r); w_ = ok and w_ or ('error ' .. tostring(w_)); if not w_:find(' ok ') and not w_:find('YunaUI') then bad = bad + 1; end M.note('warpmap', label .. ': ' .. w_); end
    for i = 0, 121 do if HP_DATA[i] then one(HP_DATA[i][3], { hp = i }); end end
    for m, d in pairs(SG_DATA) do one('SG ' .. d[1], { sg = m }); end
    msg(('Map card test: %d places, %d without a map. Details in chadcoremenu-survey.txt (warpmap lines).'):format(n, bad));
end
function WMAP.get(key, loader)                                       -- a cached texture (one new one a frame; 16 kept)
    local t = WMAP.tex[key];
    if t ~= nil then return t or nil; end
    if WMAP.frame_loads and WMAP.frame_loads > 0 then return nil; end
    WMAP.frame_loads = 1;
    t = false;
    local ok, err = pcall(function()
        local data, why = loader();
        if type(data) == 'table' then
            t = WMAP.raw_texture(data) or false;
            if not t then why = ('texture not made (%dx%d pixels)'):format(data.w, data.h); end
        elseif data then t = WMAP.texture(data, key) or false; if not t then why = 'texture not made (' .. #data .. ' bytes)'; end end
        if not t then M.note('warpmap', key .. ': ' .. tostring(why or 'no data')); end
    end);
    if not ok then errlog('warp map', err); end
    WMAP.tex[key] = t;
    WMAP.order[#WMAP.order + 1] = key;
    if #WMAP.order > 10 then local old = table.remove(WMAP.order, 1); WMAP.tex[old] = nil; end
    return t or nil;
end
function WMAP.file_data(path) return WMAP.read_file(path); end
function WMAP.layers(e)                                              -- what to draw for this map: YunaUI's layers, or the game's map
    local yd = (cfg.warp_map ~= 'game') and WMAP.ydir() or nil;
    if yd then
        local base = yd .. e.zone .. '_' .. e.floor;
        if WMAP.has_y == nil then WMAP.has_y = {}; end
        if WMAP.has_y[base] == nil then local f = io.open(base .. '.png', 'rb'); WMAP.has_y[base] = (f ~= nil); if f then f:close(); end end
        if WMAP.has_y[base] then
            return { style = 'yuna',
                     WMAP.get(base .. '.png', function() return WMAP.file_data(base .. '.png'); end),
                     WMAP.get(base .. '_l.png', function() return WMAP.file_data(base .. '_l.png'); end),
                     WMAP.get(base .. '_n.png', function() return WMAP.file_data(base .. '_n.png'); end) };
        end
    end
    return { style = 'game', WMAP.get('dat:' .. e.zone .. ':' .. e.floor .. ':' .. e.dat, function() return WMAP.game_map(e); end) };
end
-- the card, beside the place picked (rx, ry, rw, rh: its row on screen)
function WMAP.card(r, rx, ry, rw, rh, s, px0, px1)
    if cfg.warp_map == false or cfg.warp_map == 'off' then return; end
    local P_ = WMAP.data();
    local p = P_ and ((r.hp and P_.hp[r.hp]) or (r.sg and P_.sg[r.sg])) or nil;
    if p == nil and r.zone then p = { r.zone }; end                  -- (a zone with no spot: its whole map, no pin)
    if p == nil then return; end
    local e;
    if p[2] then e = WMAP.best(p[1], p[2], p[3]);
    else for _, e_ in ipairs(WMAP.entries(p[1])) do if e_.scale ~= 0 then e = e_; break; end end end
    if e == nil then return; end
    local L = WMAP.layers(e);
    if L[1] == nil then return; end
    local sw, sh = screen();
    local fg = imgui.GetForegroundDrawList();
    local M = math.floor(300 * s);
    local PAD = math.floor(12 * s);
    local HEAD = math.floor(48 * s);
    local W, H = M + 2 * PAD, HEAD + M + PAD;
    local x;                                                         -- (beside the whole panel if there's room, else beside the row)
    if px1 and px1 + 10 * s + W <= sw - 4 then x = px1 + 10 * s;
    elseif px0 and px0 - 10 * s - W >= 4 then x = px0 - 10 * s - W;
    else x = rx + rw + 10 * s; if x + W > sw - 4 then x = rx - W - 10 * s; end end
    x = math.max(4, math.min(sw - W - 4, x));
    local y = math.max(4, math.min(sh - H - 4, ry + rh / 2 - H / 2));
    for i = 3, 1, -1 do DL.RF(fg, x - i * 2, y - i * 2 + 3, x + W + i * 2, y + H + i * 2 + 3, U4(0, 0, 0, 0.08), 10 * s + i * 2); end
    DL.RF(fg, x, y, x + W, y + H, U4(0.045, 0.040, 0.065, 0.97), 9 * s);
    DL.R(fg, x, y, x + W, y + H, U4(0.62, 0.40, 1.0, 0.45), 9 * s, 0, 1);
    local p1, p2 = col(C.pink, 0.9), col(C.vio, 0.9);
    DL.RFM(fg, x + 10 * s, y, x + W - 10 * s, y + 2, p1, p2, p2, p1);
    local zn = '';
    pcall(function() zn = AshitaCore:GetResourceManager():GetString('zones.names', p[1]) or ''; end);
    local tk = font(11 * s); caps(fg, x + PAD, y + 9 * s, r.kind_label or (r.hp and 'HOME POINT' or 'SURVIVAL GUIDE'), C.acc, 2.2 * s, 1); unfont(tk);
    tk = font(15.5 * s);
    local nm = r[1];
    while tw(nm) > W - 2 * PAD - 60 * s and #nm > 4 do nm = nm:sub(1, #nm - 1); end
    text(fg, x + PAD, y + 22 * s, nm, C.text, 1);
    unfont(tk);
    if r[2] and r[2] ~= '' then
        tk = font(12 * s); text(fg, x + W - PAD - tw(r[2]), y + 26 * s, r[2], (r[2] == 'free') and C.good or C.gold, 1); unfont(tk);
    end
    -- the map: a window of it round the spot (zoomed in a little), kept inside the map
    local mx, my = 256, 256;
    if p[2] then mx, my = WMAP.to_map(e, p[2], p[3]); end
    local V = (cfg.warp_zoom == false or not p[2]) and 512 or 320;   -- (map pixels shown across)
    local u0 = math.max(0, math.min(512 - V, mx - V / 2));
    local v0 = math.max(0, math.min(512 - V, my - V / 2));
    local x0, y0 = x + PAD, y + HEAD;
    DL.RF(fg, x0, y0, x0 + M, y0 + M, U4(0.075, 0.068, 0.10, 1), 6 * s);
    local U0, V0, U1, V1 = u0 / 512, v0 / 512, (u0 + V) / 512, (v0 + V) / 512;
    pcall(function()
        if L.style == 'yuna' then
            DL.I(fg, L[1].ptr, x0, y0, x0 + M, y0 + M, U0, V0, U1, V1, U4(1, 1, 1, 1));
            if L[2] then DL.I(fg, L[2].ptr, x0, y0, x0 + M, y0 + M, U0, V0, U1, V1, U4(0.92, 0.80, 1.0, 1)); end
            if L[3] then DL.I(fg, L[3].ptr, x0, y0, x0 + M, y0 + M, U0, V0, U1, V1, U4(0.80, 0.74, 0.92, 0.85)); end
        else
            DL.I(fg, L[1].ptr, x0, y0, x0 + M, y0 + M, U0, V0, U1, V1, U4(1, 1, 1, 1));
        end
    end);
    DL.R(fg, x0, y0, x0 + M, y0 + M, U4(0.62, 0.40, 1.0, 0.35), 6 * s, 0, 1);
    -- the spot: a glowing pin that pulses
    local k = M / V;
    local px, py = x0 + (mx - u0) * k, y0 + (my - v0) * k;
    if p[2] and px > x0 and px < x0 + M and py > y0 and py < y0 + M then
        local t_ = (os.clock() * 1.4) % 1;
        DL.C(fg, px, py, (6 + 16 * t_) * s, col(C.pink, 0.9 * (1 - t_)), 24, 2 * s);
        DL.CF(fg, px, py, 9 * s, col(C.pink, 0.25), 20);
        DL.CF(fg, px, py, 5.5 * s, U4(0, 0, 0, 0.8), 16);
        DL.CF(fg, px, py, 4.5 * s, col(C.pink, 1), 16);
        DL.CF(fg, px - 1.2 * s, py - 1.2 * s, 1.6 * s, U4(1, 1, 1, 0.9), 8);
    end
    if zn ~= '' and r.hp then
        tk = font(11.5 * s);
        local zw = tw(zn) + 12 * s;
        DL.RF(fg, x0 + 6 * s, y0 + M - 24 * s, x0 + 6 * s + zw, y0 + M - 6 * s, U4(0.045, 0.040, 0.065, 0.85), 5 * s);
        text(fg, x0 + 12 * s, y0 + M - 22 * s, zn, C.muted, 1);
        unfont(tk);
    end
end

local function draw_warp(w)
    local s = PSCALE();
    local rows = warp_rows();
    WARP.rows = rows;
    WMAP.frame_loads = 0;
    local sw, sh = screen();
    local RH = math.floor(22 * s);
    local HEAD = math.floor(52 * s);
    local FOOT = math.floor(26 * s);
    local RPC = math.max(6, math.floor((sh * 0.86 - HEAD - FOOT) / RH));
    local cols = math.max(1, math.ceil(#rows / RPC));
    if cols == 1 then RPC = #rows; end
    local CW = math.floor(250 * s);
    while cols * CW + 32 * s > sw - 8 and CW > 170 * s do CW = CW - 10 * s; end
    local W = math.floor(cols * CW + 32 * s);
    local H = math.floor(HEAD + RPC * RH + FOOT + 8 * s);
    WARP.rpc, WARP.n = RPC, #rows;
    WARP.cur = math.max(1, math.min(#rows, WARP.cur or ((WARP.ev.kind == 'hp' and #rows > 1) and 2 or 1)));   -- (Home Point: on the first place, not 'set')
    local x, y = saved_pos('warp', math.floor((sw - W) / 2), math.floor((sh - H) / 2), W, H);
    imgui.SetNextWindowPos({ x, y }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ W + 8, H + 8 }, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    UI.pushed = 2;
    local opened = imgui.Begin('##ccm_warp', { true }, win_flags());
    UI.began = true;
    if opened then
        local dl = imgui.GetWindowDrawList();
        local hov_win = imgui.IsWindowHovered();
        local mx, my = mouse();
        x, y = drag('warp', x, y, x, y, x + W, y + HEAD);
        panel(dl, x, y, x + W, y + H, 1, s);
        lock_button(dl, x + W - 26 * s, y + 8 * s, s, 1, hov_win);
        local tk = font(12 * s);
        caps(dl, x + 16 * s, y + 10 * s, (WARP.ev.kind == 'hp') and 'HOME POINT' or 'SURVIVAL GUIDE', C.acc, 2.5 * s, 1);
        unfont(tk);
        tk = font(16 * s);
        local sub = ('%d places'):format(#rows - ((WARP.ev.kind == 'hp') and 1 or 0));
        text(dl, x + 16 * s, y + 24 * s, sub, C.text, 1);
        unfont(tk);
        tk = font(13 * s);
        local gs = tostring(WARP.gil or 0):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '') .. ' G';
        text(dl, x + W - 44 * s - tw(gs), y + 28 * s, gs, C.gold, 1);
        unfont(tk);
        local hover = nil;
        tk = font(13.5 * s);
        for i, r in ipairs(rows) do
            local c_, r_ = math.floor((i - 1) / RPC), (i - 1) % RPC;
            local rx, ry = x + 16 * s + c_ * CW, y + HEAD + r_ * RH;
            local hv = hov_win and not UI.move and inside(mx, my, rx, ry, rx + CW - 6 * s, ry + RH);
            if hv then hover = i; end
            local on = (i == WARP.cur);
            local pend = (i == WARP.pending);
            if pend then DL.RF(dl, rx, ry + 1, rx + CW - 8 * s, ry + RH - 1, col(C.pink, 0.45), 5 * s);
            elseif on then
                local p1, p2 = col(C.pink, 0.34), U4(C.vio[1], C.vio[2], C.vio[3], 0.0);
                DL.RFM(dl, rx, ry + 1, rx + CW - 8 * s, ry + RH - 1, p1, p2, p2, p1);
                DL.RF(dl, rx, ry + 3, rx + 2.5 * s, ry + RH - 3, col(C.pink, 1), 2);
            elseif hv then DL.RF(dl, rx, ry + 1, rx + CW - 8 * s, ry + RH - 1, U4(1, 1, 1, 0.06), 4 * s); end
            local nm = r[1];
            local right = pend and 'GO?' or r[2];
            local tk2 = font(11 * s); local rw = tw(right); unfont(tk2);
            while tw(nm) > CW - 30 * s - rw and #nm > 4 do nm = nm:sub(1, #nm - 1); end
            local ccol = r.set and C.gold or ((r.cost and r.cost > (WARP.gil or 0)) and C.dim or (on and C.text or { 0.84, 0.82, 0.92, 1 }));
            text(dl, rx + 8 * s, ry + (RH - imgui.GetTextLineHeight()) / 2, nm, ccol, 1);
            tk2 = font(11 * s);
            text(dl, rx + CW - 14 * s - tw(right), ry + (RH - imgui.GetTextLineHeight()) / 2, right, pend and C.text or ((right == 'free') and C.good or C.acc), 1);
            unfont(tk2);
            if i == (hover or WARP.cur) then WARP.card_at = { rx, ry, CW - 8 * s, RH }; end
        end
        unfont(tk);
        local cr = rows[hover or WARP.cur];                          -- (the map card: the place under the mouse, or the cursor's)
        if cr and WARP.card_at and (cr.hp or cr.sg) then
            local ok_, err_ = pcall(WMAP.card, cr, WARP.card_at[1], WARP.card_at[2], WARP.card_at[3], WARP.card_at[4], s, x, x + W);
            if not ok_ then errlog('warp map', err_); end
        end
        tk = font(12 * s);
        text(dl, x + 16 * s, y + H - 22 * s, 'Confirm a place, then confirm again to go.  Left / Right: columns.  Cancel: back.', C.dim, 1);
        unfont(tk);
        if hov_win and not UI.move then
            if hover and imgui.IsMouseClicked(0) then WARP.cur = hover; warp_pick(hover); end
            if imgui.IsMouseClicked(1) then if WARP.pending then WARP.pending = nil; else WARP.closing, WARP.close_at = 8, 0; end end
        end
    end
    imgui.End();
    UI.began = false;
    imgui.PopStyleVar(2);
    UI.pushed = 0;
end

-- NPC menus the server builds itself (LandSandBoat's custom menus: CatsEyeXI's EXP Guide (S) and the like). The server
-- sends the title and the choices as one GM-prompt chat line from "_CUSTOM_MENU" ("title""choice 1""choice 2"...), the
-- game shows them in its small 3-line "gmtell" box, and answers with a tell back to "_CUSTOM_MENU" naming the choice.
-- ChadcoreMenu reads the line, shows every choice at once in the Home Point style, and picks through the game's own box
-- (its cursor and Confirm), so the game sends its own answer. That answer is checked on the way out: if it doesn't
-- name the choice you picked it isn't sent at all (talk to the NPC again).
GMT = { t = -10, opts = {}, steps = {} };
function GMT.packet(d)                                               -- in 0x017: a chat line
    if #d < 0x19 then return; end
    local name = d:sub(0x09, 0x17):gsub('%z.*', '');
    if name ~= '_CUSTOM_MENU' then return; end
    local m = d:sub(0x18):gsub('%z.*', '');
    local parts = {};
    for q in m:gmatch('"(.-)"') do parts[#parts + 1] = q; end
    M.note('gmt_in' .. os.clock(), ('custom menu: %s'):format(m));
    if #parts < 2 then return; end
    local npc = nil;
    pcall(function()
        local ti = (GMT.talk and os.clock() - GMT.talk[2] < 10) and GMT.talk[1] or AshitaCore:GetMemoryManager():GetTarget():GetTargetIndex(0);
        if ti and ti > 0 then npc = AshitaCore:GetMemoryManager():GetEntity():GetName(ti); end
    end);
    GMT.title, GMT.npc, GMT.opts = parts[1], npc, {};
    for i = 2, #parts do GMT.opts[#GMT.opts + 1] = parts[i]; end
    GMT.t, GMT.addr, GMT.cur, GMT.pending, GMT.sent, GMT.want, GMT.steps = os.clock(), nil, 1, nil, nil, nil, {};
end
function GMT.out(e)                                                  -- out 0x0B6: a tell; the game's answer to the menu
    local d = e.data_modified or e.data;
    if #d < 0x16 then return; end
    local name = d:sub(0x07, 0x15):gsub('%z.*', '');
    if name ~= '_CUSTOM_MENU' then return; end
    local m = d:sub(0x16):gsub('%z.*', '');
    M.note('gmt_out' .. os.clock(), ('custom menu answer: %s'):format(m));
    -- (picked through the panel: its choice. Confirmed on the game's box itself - a controller button ChadcoreMenu hasn't
    --  learned as Confirm goes straight to the game - while the panel was up: the row highlighted on the panel)
    local want = GMT.want;
    local hl = GMT.hl;
    if not want and not GMT.sent and hl and os.clock() - hl.t < 3 then want = hl.opt; end
    GMT.hl = nil;
    GMT.want, GMT.sent = nil, true;
    if not want then return; end
    local res = m:match(': Result %((.*)%)%s*$');
    if res and res ~= want and not res:find('Cancel', 1, true) then
        -- (the game's box only answers with the line it's on, and won't be moved from outside: its answer goes with
        --  your choice in it instead - the same tell, naming the option you picked, which is all the server reads)
        e.blocked = true;                                            -- (want: one of this menu's options, taken when you picked it)
        local m2 = m:gsub(': Result %(.*%)%s*$', function() return ': Result (' .. want .. ')'; end);
        local p = { 0, 0, 0, 0, d:byte(5) or 0, d:byte(6) or 0 };
        local nm = '_CUSTOM_MENU';
        for i = 1, 15 do p[#p + 1] = nm:byte(i) or 0; end
        for i = 1, #m2 do p[#p + 1] = m2:byte(i); end
        p[#p + 1] = 0;
        while #p % 4 ~= 0 do p[#p + 1] = 0; end
        local ok = pcall(function() AshitaCore:GetPacketManager():AddOutgoingPacket(0xB6, p); end);
        M.note('gmt_fix' .. os.clock(), ('answer sent as "%s": %s'):format(want, ok and 'ok' or 'failed'));
        if not ok then msg('The choice could not be sent. Talk to the NPC again.'); end
    end
end
function GMT.zone(name, s_menu)                                      -- a zone's id from its name ("East Ronfaure", or its [S] one)
    if GMT.zones == nil then
        GMT.zones = {};
        pcall(function()
            local rm = AshitaCore:GetResourceManager();
            for id = 0, 300 do
                local z = rm:GetString('zones.names', id);
                if z and z ~= '' then local k = z:lower(); if GMT.zones[k] == nil then GMT.zones[k] = id; end end
            end
        end);
    end
    local k = name:lower():gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s*%(s%)$', ' [s]');
    if s_menu and GMT.zones[k .. ' [s]'] then return GMT.zones[k .. ' [s]']; end
    return GMT.zones[k] or GMT.zones[(k:gsub('%s*%[s%]$', '')) .. ' [s]'];
end
function GMT.rows()
    local s_menu = ((GMT.title or '') .. ' ' .. (GMT.npc or '')):find('%(S%)') ~= nil;
    local rows = {};
    for i, o in ipairs(GMT.opts) do
        local nm, lo, hi = o:match('^(.-)%s*%((%d+)%s*%-%s*(%d+)%)%s*$');
        local r = { o, '', opt = o, i = i };
        if nm then r[1], r[2] = nm, ('Lv %s-%s'):format(lo, hi); end
        r.zone = GMT.zone(r[1], s_menu);
        r.place = (nm ~= nil) or (r.zone ~= nil);                    -- (a place: asks once before going)
        r.kind_label = (GMT.npc and GMT.npc ~= '') and GMT.npc:upper() or 'DESTINATION';
        rows[#rows + 1] = r;
    end
    return rows;
end
function GMT.pick(i, w)                                              -- through the game's box: its cursor, then Confirm
    local r = GMT.rows()[i];
    if not r or GMT.sent or not w then return; end
    if r.place and GMT.pending ~= i then GMT.pending = i; return; end
    GMT.want, GMT.sent, GMT.pending = r.opt, true, nil;
    -- (the box doesn't take a cursor put on it: it's moved with Up / Down from where it is - the top when it opens -
    --  then Confirm. Below its 3 lines Down scrolls it on)
    -- (the box can't be moved from outside: Confirm on whatever line it's on, and its answer is made to name your choice)
    local st = { { nil, KEY.ok } };
    GMT.steps, GMT.step_at = st, 0;
end
function GMT.back()
    if GMT.pending then GMT.pending = nil; return; end
    GMT.sent, GMT.old = true, GMT.addr;
    M.act(nil, nil, KEY.cancel);
end
function GMT.run(w)                                                  -- one step a few frames apart
    local st = GMT.steps;
    if #st == 0 then return; end
    local now = os.clock();
    if now < (GMT.step_at or 0) then return; end
    local s1 = table.remove(st, 1);
    M.act(w.addr, s1[1], s1[2]);
    GMT.step_at = now + 0.09;
    if #st == 0 then GMT.old = w.addr; end                          -- (answered: that box is on its way out)
end
function GMT.pad(acts, w)
    local n = math.max(1, #GMT.opts);
    for _, act in ipairs(acts) do
        local c = GMT.cur or 1;
        if act == 'up' then c = (c > 1) and (c - 1) or n;
        elseif act == 'down' then c = (c < n) and (c + 1) or 1;
        elseif act == 'ok' then GMT.pick(c, w);
        elseif act == 'back' then GMT.back(); end
        if c ~= GMT.cur then GMT.pending = nil; end
        GMT.cur = c;
    end
end
function GMT.draw(w)
    local s = PSCALE();
    local rows = GMT.rows();
    WMAP.frame_loads = 0;
    local sw, sh = screen();
    local RH = math.floor(26 * s);
    local HEAD = math.floor(56 * s);
    local FOOT = math.floor(28 * s);
    local W = math.floor(340 * s);
    local H = math.floor(HEAD + #rows * RH + FOOT + 8 * s);
    GMT.cur = math.max(1, math.min(#rows, GMT.cur or 1));
    -- (over the game's box, covering it: the game draws that box whatever's done to it)
    local nat = M.to_screen(w.rect);
    local x, y;
    if nat then
        W = math.max(W, math.floor(nat[3] - nat[1] + 24 * s));
        x = math.floor((nat[1] + nat[3]) / 2 - W / 2);
        y = math.floor(nat[4] + 8 * s - H);
    else
        x, y = math.floor((sw - W) / 2), math.floor((sh - H) / 2);
    end
    x = math.max(4, math.min(sw - W - 4, x));
    y = math.max(4, math.min(sh - H - 4, y));
    imgui.SetNextWindowPos({ x, y }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ W + 8, H + 8 }, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    UI.pushed = 2;
    local opened = imgui.Begin('##ccm_gmt', { true }, win_flags());
    UI.began = true;
    if opened then
        local dl = imgui.GetWindowDrawList();
        local hov_win = imgui.IsWindowHovered();
        local mx, my = mouse();
        DL.RF(dl, x, y, x + W, y + H, U4(0.035, 0.030, 0.050, 1), 10 * s);   -- (solid: the game's box doesn't show through)
        panel(dl, x, y, x + W, y + H, 1, s);
        local tk = font(12 * s);
        local head = (GMT.npc and GMT.npc ~= '') and GMT.npc:upper() or 'CHOOSE';
        caps(dl, x + 16 * s, y + 10 * s, head, C.acc, 2.5 * s, 1);
        unfont(tk);
        tk = font(16 * s);
        local sub = GMT.title or '';
        while tw(sub) > W - 60 * s and #sub > 4 do sub = sub:sub(1, #sub - 1); end
        text(dl, x + 16 * s, y + 26 * s, sub, C.text, 1);
        unfont(tk);
        local hover = nil;
        local card = nil;
        tk = font(14 * s);
        for i, r in ipairs(rows) do
            local rx, ry = x + 16 * s, y + HEAD + (i - 1) * RH;
            local rw = W - 32 * s;
            local hv = hov_win and not UI.move and inside(mx, my, rx, ry, rx + rw, ry + RH);
            if hv then hover = i; end
            local on = (i == GMT.cur);
            local pend = (i == GMT.pending);
            if pend then DL.RF(dl, rx, ry + 1, rx + rw, ry + RH - 1, col(C.pink, 0.45), 5 * s);
            elseif on then
                local p1, p2 = col(C.pink, 0.34), U4(C.vio[1], C.vio[2], C.vio[3], 0.0);
                DL.RFM(dl, rx, ry + 1, rx + rw, ry + RH - 1, p1, p2, p2, p1);
                DL.RF(dl, rx, ry + 3, rx + 2.5 * s, ry + RH - 3, col(C.pink, 1), 2);
            elseif hv then DL.RF(dl, rx, ry + 1, rx + rw, ry + RH - 1, U4(1, 1, 1, 0.06), 4 * s); end
            local right = pend and 'GO?' or r[2];
            local tk2 = font(12 * s); local rtw = tw(right); unfont(tk2);
            local nm = r[1];
            while tw(nm) > rw - 24 * s - rtw and #nm > 4 do nm = nm:sub(1, #nm - 1); end
            local ccol = r.place and (on and C.text or { 0.84, 0.82, 0.92, 1 }) or C.muted;
            text(dl, rx + 10 * s, ry + (RH - imgui.GetTextLineHeight()) / 2, nm, ccol, 1);
            tk2 = font(12 * s);
            text(dl, rx + rw - 8 * s - tw(right), ry + (RH - imgui.GetTextLineHeight()) / 2, right, pend and C.text or C.acc, 1);
            unfont(tk2);
            if i == (hover or GMT.cur) then card = { r, rx, ry, rw, RH }; end
        end
        unfont(tk);
        if card and card[1].zone then
            local ok_, err_ = pcall(WMAP.card, card[1], card[2], card[3], card[4], card[5], s, x, x + W);
            if not ok_ then errlog('menu map', err_); end
        end
        tk = font(12 * s);
        local anyp = false; for _, r in ipairs(rows) do if r.place then anyp = true; end end
        text(dl, x + 16 * s, y + H - 22 * s, anyp and 'Confirm a place, then confirm again to go.  Cancel: back.' or 'Confirm: choose.  Cancel: back.', C.dim, 1);
        unfont(tk);
        if hov_win and not UI.move then
            if hover and imgui.IsMouseClicked(0) then GMT.cur = hover; GMT.pick(hover, w); end
            if imgui.IsMouseClicked(1) then GMT.back(); end
        end
    end
    imgui.End();
    UI.began = false;
    imgui.PopStyleVar(2);
    UI.pushed = 0;
    return true;
end

-- The treasure pool: what's in it (from the server's "item found" 0x0D2 and "lot / pass / won" 0x0D3 lines, and the
-- game's own pool when ChadcoreMenu loads), a Treasure command in the action menu while anything is in it, and a panel
-- to lot or pass - the same 0x041 (lot) / 0x042 (pass) the game's own Treasure window sends.
TRE = { items = {} };
TRE.ui = UI;                                                         -- (for the tests)
TRE.LIFE = 300;                                                -- (an item stays 5 minutes)
function TRE.name(id)
    local nm = '?';
    pcall(function() local r = AshitaCore:GetResourceManager():GetItemById(id); nm = (r and r.Name and r.Name[1]) or '?'; end);
    return nm;
end
function TRE.me()
    local id = 0;
    pcall(function() id = AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0) or 0; end);
    return id;
end
function TRE.seed()                                                  -- (once: what the game already has in its pool)
    if TRE.seeded then return; end
    TRE.seeded = true;
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        for i = 0, 9 do
            local it = inv:GetTreasurePoolItem(i);
            if it and (it.ItemId or 0) > 0 and TRE.items[i] == nil then
                local lot = tonumber(it.Lot) or 0;
                TRE.items[i] = { id = it.ItemId, t = os.clock(), mylot = (lot == 65535) and 'pass' or ((lot > 0) and lot or nil),
                                 best = tonumber(it.WinningLot) or 0, bestname = it.WinningEntityName or '' };
            end
        end
    end);
end
function TRE.packet(id, d)
    local function u(o, n) local v = 0; for i = n - 1, 0, -1 do v = v * 256 + (d:byte(o + i + 1) or 0); end return v; end
    local function str(o, n) return d:sub(o + 1, o + n):gsub('%z.*', ''); end
    if id == 0x00A then TRE.items = {}; return; end                  -- (a new zone: the pool is gone)
    if id == 0x0D2 then
        local item, slot = u(0x10, 2), u(0x14, 1);
        if item == 0 or item == 0xFFFF or slot > 9 then return; end
        local e = { id = item, t = os.clock(), best = u(0x26, 2), bestname = str(0x28, 16) };
        if u(0x1C, 2) ~= 0 then local p = u(0x1E, 2); e.mylot = (p == 65535) and 'pass' or p; end
        local old = TRE.items[slot];
        if old and old.id == item and u(0x15, 1) == 1 then e.t = old.t; e.mylot = e.mylot or old.mylot; end   -- (sent again: keeps its time)
        TRE.items[slot] = e;
    elseif id == 0x0D3 then
        local slot, judge = u(0x14, 1), u(0x15, 1);
        local e = TRE.items[slot];
        if judge ~= 0 then TRE.items[slot] = nil; return; end        -- (won, lost, or nobody could take it: gone)
        if not e then return; end
        e.best, e.bestname = u(0x0E, 2), str(0x16, 16);
        local who, pt_ = str(0x26, 16), u(0x12, 2);                  -- (each roll as it comes: who, and their lot or a pass)
        if who ~= '' then
            e.rolls = e.rolls or {};
            local found = false;
            for _, r_ in ipairs(e.rolls) do if r_[1] == who then r_[2] = pt_; found = true; end end
            if not found then e.rolls[#e.rolls + 1] = { who, pt_ }; end
        end
        if u(0x08, 4) == TRE.me() and u(0x08, 4) ~= 0 then
            local p = u(0x12, 2);
            e.mylot = (p == 65535) and 'pass' or p;
            e.wait = nil;
        end
    end
end
function TRE.list()
    TRE.seed();
    local now, out = os.clock(), {};
    for slot = 0, 9 do
        local e = TRE.items[slot];
        if e and now - e.t > TRE.LIFE + 10 then TRE.items[slot] = nil; e = nil; end
        if e then e.slot = slot; out[#out + 1] = e; end
    end
    return out;
end
function TRE.count() return #TRE.list(); end
function TRE.open()
    UI.tre = { cur = 1, t0 = os.clock() };
    M.act(nil, nil, KEY.cancel);                                     -- (the action menu closes; the pool panel stays)
end
function TRE.send(pid, slot)
    local ok = pcall(function() AshitaCore:GetPacketManager():AddOutgoingPacket(pid, { 0, 0, 0, 0, slot, 0, 0, 0 }); end);
    M.note('treasure', ('%s slot %d: %s'):format((pid == 0x41) and 'lot' or 'pass', slot, ok and 'sent' or 'failed'));
    return ok;
end
function TRE.lot(e)
    if not e or e.mylot or e.wait then return; end
    if TRE.send(0x41, e.slot) then e.wait = os.clock(); end
end
function TRE.pass(e)
    if not e or e.mylot == 'pass' or e.wait then return; end
    if TRE.send(0x42, e.slot) then e.wait = os.clock(); end
end
function TRE.pad(acts)
    local st = UI.tre;
    local L = TRE.list();
    local n = math.max(1, #L);
    for _, act in ipairs(acts) do
        if act == 'up' then st.cur = (st.cur > 1) and (st.cur - 1) or n;
        elseif act == 'down' then st.cur = (st.cur < n) and (st.cur + 1) or 1;
        elseif act == 'ok' then TRE.lot(L[st.cur]);
        elseif act == 'sort' or act == 'right' then TRE.pass(L[st.cur]);
        elseif act == 'back' then UI.tre = nil; return; end
    end
end
function TRE.draw()
    local st = UI.tre;
    local L = TRE.list();
    if #L == 0 then UI.tre = nil; return false; end
    local s = PSCALE();
    local now = os.clock();
    st.cur = math.max(1, math.min(#L, st.cur or 1));
    for _, e in ipairs(L) do if e.wait and now - e.wait > 3 then e.wait = nil; end end
    local sw, sh = screen();
    local anyr = false;
    for _, e in ipairs(L) do if e.rolls and #e.rolls > 0 then anyr = true; end end
    local RH = math.floor((anyr and 62 or 46) * s);
    local HEAD = math.floor(54 * s);
    local FOOT = math.floor(28 * s);
    local W = math.floor(500 * s);
    local H = math.floor(HEAD + #L * RH + FOOT + 6 * s);
    local x, y = saved_pos('tre', math.floor(sw * 0.5 - W / 2), math.floor(sh * 0.32), W, H);
    imgui.SetNextWindowPos({ x, y }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ W + 8, H + 8 }, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    UI.pushed = 2;
    local opened = imgui.Begin('##ccm_treasure', { true }, win_flags());
    UI.began = true;
    if opened then
        local dl = imgui.GetWindowDrawList();
        local hov_win = imgui.IsWindowHovered();
        local mx, my = mouse();
        x, y = drag('tre', x, y, x, y, x + W, y + HEAD);
        panel(dl, x, y, x + W, y + H, 1, s);
        lock_button(dl, x + W - 26 * s, y + 8 * s, s, 1, hov_win);
        local tk = font(12 * s); caps(dl, x + 16 * s, y + 10 * s, 'TREASURE', C.acc, 2.5 * s, 1); unfont(tk);
        tk = font(16 * s); text(dl, x + 16 * s, y + 25 * s, ('%d item%s in the pool'):format(#L, (#L == 1) and '' or 's'), C.text, 1); unfont(tk);
        local click_lot, click_pass, hover = nil, nil, nil;
        for i, e in ipairs(L) do
            local rx, ry, rw = x + 12 * s, y + HEAD + (i - 1) * RH, W - 24 * s;
            local hv = hov_win and not UI.move and inside(mx, my, rx, ry, rx + rw, ry + RH);
            if hv then hover = i; end
            if i == st.cur then
                local p1, p2 = col(C.pink, 0.30), U4(C.vio[1], C.vio[2], C.vio[3], 0.0);
                DL.RFM(dl, rx, ry + 2, rx + rw, ry + RH - 2, p1, p2, p2, p1);
                DL.RF(dl, rx, ry + 5, rx + 2.5 * s, ry + RH - 5, col(C.pink, 1), 2);
            elseif hv then DL.RF(dl, rx, ry + 2, rx + rw, ry + RH - 2, U4(1, 1, 1, 0.05), 5 * s); end
            local is = math.floor(32 * s);
            local ix, iy = rx + 10 * s, ry + (RH - is) / 2;
            DL.RF(dl, ix - 2, iy - 2, ix + is + 2, iy + is + 2, U4(0.115, 0.105, 0.155, 0.9), 5 * s);
            image(dl, item_icon(e.id), ix, iy, ix + is, iy + is, 1);
            -- the buttons: LOT / PASS
            local bw, bh = math.floor(46 * s), math.floor(22 * s);
            local by = ry + 9 * s;
            local px1 = rx + rw - 8 * s;
            local px0 = px1 - bw;
            local lx1 = px0 - 6 * s;
            local lx0 = lx1 - bw;
            local can_lot, can_pass = (e.mylot == nil) and not e.wait, (e.mylot ~= 'pass') and not e.wait;
            local function pill(x0, x1, label, on, good)
                local h_ = hov_win and not UI.move and inside(mx, my, x0, by, x1, by + bh);
                local c_ = on and (good and C.pink or C.vio) or { 0.4, 0.4, 0.45, 1 };
                DL.RF(dl, x0, by, x1, by + bh, col(c_, on and (h_ and 0.55 or 0.30) or 0.12), bh / 2);
                DL.R(dl, x0, by, x1, by + bh, col(c_, on and 0.9 or 0.3), bh / 2, 0, 1);
                local t2 = font(11 * s);
                text(dl, x0 + (x1 - x0 - tw(label)) / 2, by + (bh - imgui.GetTextLineHeight()) / 2, label, on and C.text or C.dim, 1);
                unfont(t2);
                return h_ and on;
            end
            if pill(lx0, lx1, 'LOT', can_lot, true) and imgui.IsMouseClicked(0) then click_lot = i; end
            if pill(px0, px1, 'PASS', can_pass, false) and imgui.IsMouseClicked(0) then click_pass = i; end
            local tx = ix + is + 12 * s;
            local maxw = lx0 - 8 * s - tx;
            local t1 = font(14.5 * s);
            local nm = TRE.name(e.id);
            while tw(nm) > maxw and #nm > 4 do nm = nm:sub(1, #nm - 1); end
            text(dl, tx, ry + 6 * s, nm, (i == st.cur) and C.text or { 0.86, 0.84, 0.94, 1 }, 1);
            unfont(t1);
            t1 = font(11.5 * s);
            local left = math.max(0, TRE.LIFE - (now - e.t));
            local mine = e.wait and '...' or ((e.mylot == 'pass') and 'Passed' or (e.mylot and ('Your lot ' .. e.mylot)) or 'Not lotted');
            local info = mine;
            if (e.best or 0) > 0 and e.best ~= 65535 and (e.bestname or '') ~= '' then info = info .. ('   Top: %s %d'):format(e.bestname, e.best); end
            while tw(info) > maxw - 34 * s and #info > 4 do info = info:sub(1, #info - 1); end
            text(dl, tx, ry + 25 * s, info, (e.mylot == 'pass') and C.dim or (e.mylot and C.good or C.muted), 1);
            local ts = ('%d:%02d'):format(math.floor(left / 60), math.floor(left % 60));
            text(dl, lx0 - 8 * s - tw(ts), ry + 25 * s, ts, (left < 60) and C.pink or C.dim, 1);
            if e.rolls and #e.rolls > 0 then                         -- (everyone's rolls, highest first; passes after)
                local rs = {};
                for _, r_ in ipairs(e.rolls) do rs[#rs + 1] = r_; end
                table.sort(rs, function(p_, q_)
                    local a_ = (p_[2] == 65535) and -1 or p_[2]; local b_ = (q_[2] == 65535) and -1 or q_[2]; return a_ > b_; end);
                local parts = {};
                for _, r_ in ipairs(rs) do parts[#parts + 1] = (r_[2] == 65535) and (r_[1] .. ' pass') or (r_[1] .. ' ' .. r_[2]); end
                local rl = 'Rolls: ' .. table.concat(parts, ',  ');
                while tw(rl) > rw - (tx - rx) - 10 * s and #rl > 8 do rl = rl:sub(1, #rl - 1); end
                text(dl, tx, ry + 42 * s, rl, C.acc, 1);
            end
            unfont(t1);
        end
        tk = font(12 * s);
        text(dl, x + 16 * s, y + H - 22 * s, 'Confirm: lot.  Right or Square / X: pass.  Cancel: close.', C.dim, 1);
        unfont(tk);
        if hov_win and not UI.move then
            if click_lot then st.cur = click_lot; TRE.lot(L[click_lot]);
            elseif click_pass then st.cur = click_pass; TRE.pass(L[click_pass]);
            elseif hover and imgui.IsMouseClicked(0) then st.cur = hover; end
            if imgui.IsMouseClicked(1) then UI.tre = nil; end
        end
        local show = L[hover or st.cur];                             -- (the item under the mouse, or the cursor: its card below)
        if show and UI.tre then item_tooltip(show.id, mx, my, { x, y + H + 6 * s, y - 6 * s }); end
    end
    imgui.End();
    UI.began = false;
    imgui.PopStyleVar(2);
    UI.pushed = 0;
    return true;
end

-- The macro bars (the game's "mcr1long" = Ctrl, "mcr2long" = Alt): ten macros in a row that the game's own cursor moves
-- along. Their names and lines come from the game's macro files (USER\<character>\mcr*.dat: one file a set, 20 macros,
-- Ctrl 1-10 then Alt 1-10). Which book and set is up: found by looking for the macro names in the game's memory near
-- the bar (only memory Windows says is readable), and matching them against the files. Until that's found the game's
-- own bar stays. A click puts the game's cursor there and presses Confirm, so the game runs its own macro.
MCR = { sets = nil, found = nil, at = 0, chain = nil };
pcall(ffi.cdef, [[
typedef struct { void* BaseAddress; void* AllocationBase; uint32_t AllocationProtect; size_t RegionSize; uint32_t State; uint32_t Protect; uint32_t Type; } CCM_MBI;
size_t VirtualQuery(const void* lpAddress, CCM_MBI* lpBuffer, size_t dwLength);
]]);
function MCR.readable(a, n)
    if a < 0x10000 or a > 0x7FFF0000 then return false; end
    local mbi = ffi.new('CCM_MBI');
    if ffi.C.VirtualQuery(ffi.cast('const void*', a), mbi, ffi.sizeof(mbi)) == 0 then return false; end
    if mbi.State ~= 0x1000 then return false; end
    local pr = mbi.Protect;
    if bit.band(pr, 0x101) ~= 0 then return false; end              -- (no access, guard page)
    if bit.band(pr, 0xEE) == 0 then return false; end
    local base = tonumber(ffi.cast('uint32_t', mbi.BaseAddress));
    return a + n <= base + tonumber(mbi.RegionSize);
end
function MCR.read(a, n)
    if not MCR.readable(a, n) then
        -- (across a memory region's end: as much as can be read, page by page - the next region is often there too;
        --  halving it lost text near the end, e.g. a question at +0xEB5 when its region stopped at +0xF00)
        local got = 0;
        while got < n do
            local pe = math.min(n, (math.floor((a + got) / 0x1000) + 1) * 0x1000 - a);
            if not MCR.readable(a + got, pe - got) then break; end
            got = pe;
        end
        if got < 64 then
            while n > 64 and not MCR.readable(a, n) do n = math.floor(n / 2); end
            if not MCR.readable(a, n) then return nil; end
        else
            n = got;
        end
    end
    return ffi.string(ffi.cast('const char*', a), n);
end
function MCR.userdir()
    local g = nil;
    pcall(function() if vana and vana.paths and vana.paths.game and vana.paths.game ~= '' then g = vana.paths.game; end end);
    if not g then
        pcall(function()
            local p = AshitaCore:GetResourceManager():GetFilePath(5312) or '';
            g = p:match('^(.-)\\[Rr][Oo][Mm]%d*\\');
        end);
    end
    return g and (g .. '\\USER\\') or nil;
end
function MCR.load()                                                  -- every set's 20 macros, from the files (once)
    if MCR.sets then return MCR.sets; end
    MCR.sets = {};
    local u = MCR.userdir();
    if not u then M.note('macro', 'game folder not found'); return MCR.sets; end
    local folders = {};
    pcall(function() folders = vana.fs.list(u, nil, 'folders') or {}; end);
    if #folders == 0 then
        pcall(function() local p = io.popen('dir /b /ad "' .. u .. '"'); if p then for l in p:lines() do folders[#folders + 1] = l; end p:close(); end end);
    end
    local n = 0;
    for _, fo in ipairs(folders) do
        for k = 0, 199 do
            local fn = u .. fo .. '\\mcr' .. ((k == 0) and '' or tostring(k)) .. '.dat';
            local f = io.open(fn, 'rb');
            if f then
                local d = f:read('*a'); f:close();
                if d and #d >= 24 + 20 * 380 then
                    local set = { folder = fo, file = k, book = math.floor(k / 10) + 1, set = k % 10 + 1, m = {} };
                    for i = 0, 19 do
                        local o = 24 + i * 380;
                        local lines, raw = {}, {};
                        for l = 0, 5 do
                            local s_ = d:sub(o + 4 + l * 61 + 1, o + 4 + l * 61 + 61):gsub('%z.*', '');
                            if s_ ~= '' then lines[#lines + 1] = MCR.atx(s_); raw[#raw + 1] = s_; end
                        end
                        set.m[i + 1] = { title = d:sub(o + 370 + 1, o + 370 + 10):gsub('%z.*', ''), lines = lines, raw = raw };
                    end
                    MCR.sets[#MCR.sets + 1] = set;
                    n = n + 1;
                end
            end
        end
    end
    M.note('macro', ('%d macro sets read from %s (%d character folders)'):format(n, u, #folders));
    return MCR.sets;
end
function MCR.reread(set)                                             -- (one set's macros from its file again, in place)
    local u = MCR.userdir();
    if not u then return; end
    local f = io.open(u .. set.folder .. '\\mcr' .. ((set.file == 0) and '' or tostring(set.file)) .. '.dat', 'rb');
    if not f then return; end
    local d = f:read('*a'); f:close();
    if not d or #d < 24 + 20 * 380 then return; end
    for i = 0, 19 do
        local o = 24 + i * 380;
        local lines = {};
        for l = 0, 5 do
            local s_ = d:sub(o + 4 + l * 61 + 1, o + 4 + l * 61 + 61):gsub('%z.*', '');
            if s_ ~= '' then lines[#lines + 1] = MCR.atx(s_); end
        end
        set.m[i + 1] = { title = d:sub(o + 370 + 1, o + 370 + 10):gsub('%z.*', ''), lines = lines };
    end
end
-- The set's macros as the game has them in memory (where the names were found: the same layout as the file, 380 bytes a
-- macro - its 6 lines of 61, then its 10-letter name - from +8): read live, a macro you've just changed shows at once,
-- not when the game gets round to saving its file. Anything that doesn't read as plain text: not used.
-- (a macro line as you'd read it: the game's auto-translate phrases - FD, 4 bytes, FD - spelled out, in braces)
function MCR.atx(t)
    if not t or not t:find('\xFD', 1, true) then return t; end
    local ok, r = pcall(function() return vana.ashita.parse_auto_translate(t, true); end);
    if not (ok and type(r) == 'string' and r ~= '') then             -- (Ashita's own, if VanaCore's isn't there)
        ok, r = pcall(function() return AshitaCore:GetChatManager():ParseAutoTranslate(t, true); end);
    end
    if ok and type(r) == 'string' and r ~= '' then t = r; end
    t = t:gsub('\xFD.....', '?');                                      -- (one that couldn't be read)
    -- (the game's own brackets round a phrase - green open, red close: marks the panels draw as coloured < >)
    t = t:gsub('\xEF\x27', '\2'):gsub('\xEF%(', '\3');            -- (0x28 is "(": escaped in the pattern)
    local open_ = true;
    t = t:gsub('[\128-\255]+', function() local m = open_ and '\2' or '\3'; open_ = not open_; return m; end);
    return t;
end
function MCR.live_m(blob)
    if not blob or #blob < 0x8 + 19 * 380 + 366 + 10 then return nil; end
    local m = {};
    for i = 0, 19 do
        local o = 0x8 + i * 380;
        local t = blob:sub(o + 366 + 1, o + 366 + 10):gsub('%z.*', '');
        if t:find('[^\32-\126]') then return nil; end
        local lines, raw = {}, {};
        for l = 0, 5 do
            local s_ = blob:sub(o + l * 61 + 1, o + l * 61 + 61):gsub('%z.*', '');
            if s_ ~= '' then lines[#lines + 1] = MCR.atx(s_); raw[#raw + 1] = s_; end
        end
        m[i + 1] = { title = t, lines = lines, raw = raw };
    end
    return m;
end
function MCR.live(w, chain, set)                                     -- (the set, its names from memory when they read)
    if not set or not chain or chain == '*' then return set; end
    local m = MCR.live_m(MCR.follow(w, chain));
    if not m then return set; end
    local named, same = 0, 0;                                         -- (it must be the same set: most of its names where they were -
    for i = 1, 20 do                                                  --  one or two just changed is fine)
        local t = set.m[i] and set.m[i].title or '';
        if t ~= '' then named = named + 1; if m[i].title == t then same = same + 1; end end
    end
    if named > 0 and same < math.max(1, math.ceil(named * 0.5)) then return set; end
    return { book = set.book, set = set.set, folder = set.folder, file = set.file, m = m, blank = set.blank };
end
function MCR.strings(blob, into)                                     -- the short texts in a piece of memory
    for s_ in blob:gmatch('([%w%p ][%w%p ]+)%z') do if #s_ <= 9 then into[s_] = (into[s_] or 0) + 1; end end
end
function MCR.score(strs)                                             -- the set whose names are there (its Ctrl half or its Alt half:
    local best, bs = nil, 0;                                         --  either tells the set, and so both bars)
    for _, set in ipairs(MCR.load()) do
        for h = 1, 2 do
            local sc, any = 0, 0;
            for i = 1, 10 do
                local t = set.m[(h - 1) * 10 + i].title;
                if #t >= 2 then any = any + 1; if strs[t] then sc = sc + 1; end end
            end
            if any >= 2 and sc >= math.max(2, math.ceil(any * 0.6)) and sc > bs then best, bs = set, sc; end
        end
    end
    return best, bs;
end
function MCR.scan(w, half)                                           -- from the bar's window: pointers, three deep
    local seen, queue, regions = {}, { { w.addr, '' } }, 0;
    local strs = {};
    local hits = {};
    while #queue > 0 and regions < 600 do
        local q = table.remove(queue, 1);
        local a, path = q[1], q[2];
        local blob = MCR.read(a, 0x2000);
        regions = regions + 1;
        if blob then
            local local_ = {};
            MCR.strings(blob, local_);
            local set_, sc = MCR.score(local_);
            if set_ then hits[#hits + 1] = { path = path, set = set_, sc = sc, a = a }; end
            for k, v in pairs(local_) do strs[k] = (strs[k] or 0) + v; end
            local depth = select(2, path:gsub('>', ''));
            if depth < 3 then
                for off = 0, math.min(#blob, 0x200) - 4, 4 do
                    local p = blob:byte(off + 1) + blob:byte(off + 2) * 256 + blob:byte(off + 3) * 65536 + blob:byte(off + 4) * 16777216;
                    if p >= 0x01000000 and p < 0x7FFF0000 and p % 4 == 0 and not seen[p] then
                        seen[p] = true;
                        queue[#queue + 1] = { p, path .. '>' .. ('%X'):format(off) };
                    end
                end
            end
        end
    end
    table.sort(hits, function(p_, q_) if p_.sc ~= q_.sc then return p_.sc > q_.sc; end return #p_.path < #q_.path; end);
    local h = hits[1];
    if not h then                                                    -- (not in one place: everything near it, together)
        local s2, sc2 = MCR.score(strs);
        if s2 then h = { path = '*', set = s2, sc = sc2 }; end
    end
    M.note('macro_scan' .. half, h and ('%s: book %d set %d (%s mcr%s.dat), %d names, path %s, %d places looked at'):format(w.name, h.set.book, h.set.set, h.set.folder, (h.set.file == 0) and '' or h.set.file, h.sc, h.path, regions)
        or ('%s: names not found (%d places looked at, %d sets known)'):format(w.name, regions, #MCR.load()));
    return h;
end
function MCR.follow(w, path)                                         -- the remembered path again: the piece of memory it leads to
    local a = MCR.follow_addr(w, path);
    return a and MCR.read(a, 0x2000) or nil;
end
function MCR.follow_addr(w, path)
    if not path or path == '*' then return nil; end
    local a = w.addr;
    for off in path:gmatch('>(%x+)') do
        local b = MCR.read(a + tonumber(off, 16), 4);
        if not b then return nil; end
        a = b:byte(1) + b:byte(2) * 256 + b:byte(3) * 65536 + b:byte(4) * 16777216;
    end
    return a;
end
function MCR.active(w, half)                                         -- which set is up (every frame: a set change shows at once)
    local now = os.clock();
    local key = w.addr .. ':' .. half;
    local fresh = (MCR.key ~= key);
    MCR.key = key;
    if MCR.chain and MCR.chain ~= '*' then                       -- (the same path from either bar's window)
        local blob = MCR.follow(w, MCR.chain);
        if blob then
            if blob == MCR.last_blob and MCR.found then return MCR.found; end   -- (nothing changed there: the same set)
            local strs = {}; MCR.strings(blob, strs);
            local s_ = MCR.score(strs);
            if s_ then MCR.found, MCR.last_blob = s_, blob; return s_; end
        end
    end
    if not fresh and now - MCR.at < 0.5 then return MCR.found; end
    MCR.at = now;
    if MCR.found and MCR.chain then return MCR.found; end         -- (known: no long look again; the set stays till it's seen to change)
    if not fresh and MCR.tried == key then return MCR.found; end   -- (a full look once per opening)
    if (MCR.fails or 0) >= 3 then return nil; end                   -- (not found three times: the game's own bar from now on)
    MCR.tried = key;
    local h = MCR.scan(w, half);
    if h then MCR.chain = h.path; MCR.found = h.set; MCR.fails = 0;
        if h.set and h.set.folder and cfg.mcr_folder ~= h.set.folder then cfg.mcr_folder = h.set.folder; pcall(save); end   -- (your character's folder, kept)
    else MCR.found = nil; MCR.fails = (MCR.fails or 0) + 1; end
    return MCR.found;
end
-- When the game's bar won't come up (see the force check) ours does the work: a macro's lines sent as if typed, with
-- "/wait N" lines and "<wait N>" at a line's end kept as pauses; Up / Down (keyboard or D-pad) change the set in the book.
MCRF = { cur = 1, q = {}, on_t = -1, half = 1 };
function MCRF.active() return os.clock() - MCRF.on_t < 0.25 and MCR.held() ~= nil; end   -- (drawn just now, and still held)
function MCRF.run(i)
    local set = MCR.remembered();
    local m = set and set.m[(MCRF.half - 1) * 10 + i];
    if not m then return; end
    MCRF.cur = i;
    local raw = m.raw or m.lines or {};
    if #raw == 0 then return; end
    MCRF.q, MCRF.t = {}, os.clock();
    for _, l in ipairs(raw) do MCRF.q[#MCRF.q + 1] = l; end
    M.note('macro_run' .. os.clock(), ('ran macro %d (%s) of book %d set %s: %d lines'):format(i, m.title or '', set.book or 0, tostring(set.set), #raw));
end
function MCRF.tick()
    while #MCRF.q > 0 and os.clock() >= (MCRF.t or 0) do
        local l = table.remove(MCRF.q, 1);
        local w_ = l:match('^%s*/wait%s+([%d%.]+)');
        if w_ then MCRF.t = os.clock() + math.min(30, tonumber(w_) or 1);
        elseif not l:match('^%s*/wait%s*$') then
            local tail = l:match('<wait%s+([%d%.]+)>%s*$');
            local cmd = l:gsub('%s*<wait%s+[%d%.]+>%s*$', '');
            if cmd ~= '' then pcall(function() AshitaCore:GetChatManager():QueueCommand(1, cmd); end); end
            if tail then MCRF.t = os.clock() + math.min(30, tonumber(tail) or 1); end
        end
    end
end
function MCRF.step(d)                                                -- (the next / last set in the book; 1 after 10)
    local set = MCR.remembered();
    if not set or not set.file then return; end
    local bk = math.floor(set.file / 10);
    local n = (set.file % 10 + d) % 10;
    local want = bk * 10 + n;
    local got = nil;
    for _, s_ in ipairs(MCR.load()) do if s_.file == want and s_.folder == set.folder then got = s_; end end
    if not got then                                                  -- (a set never saved: empty)
        got = { folder = set.folder, file = want, book = bk + 1, set = n + 1, m = {} };
        for k = 1, 20 do got.m[k] = { title = '', lines = {}, raw = {} }; end
    end
    MCR.found, MCR.last_blob = got, nil;
    MCR.remembered();
end
-- (the set last seen on the bar, kept between sessions: the force check can show it before the game's bar has come up once)
function MCR.remembered()
    local f_ = MCR.found;
    if f_ then
        if f_.folder and f_.file and (cfg.mcr_last_file ~= f_.file or cfg.mcr_last_folder ~= f_.folder) then
            cfg.mcr_last_file, cfg.mcr_last_folder = f_.file, f_.folder; pcall(save);
        end
        return f_;
    end
    if cfg.mcr_last_file == nil then                                 -- (never seen: the set last opened in Edit Macro, else your first)
        local e_ = EDM and EDM.st and ((EDM.st[1] and EDM.st[1].set) or (EDM.st[2] and EDM.st[2].set));
        if e_ and e_.file then return e_; end
        for _, set in ipairs(MCR.load()) do
            if set.file == 0 and (cfg.mcr_folder == nil or set.folder == cfg.mcr_folder) then return set; end
        end
        return nil;
    end
    for _, set in ipairs(MCR.load()) do
        if set.file == cfg.mcr_last_file and (cfg.mcr_last_folder == nil or set.folder == cfg.mcr_last_folder) then MCR.found = set; return set; end
    end
    return nil;
end
function MCR.draw(w, half, set)
    local s = PSCALE();
    local nat = M.to_screen(w.rect);
    local sw, sh = screen();
    local SW, SH, G = math.floor(92 * s), math.floor(46 * s), math.floor(6 * s);
    local P = math.floor(10 * s);
    local HEAD = math.floor(20 * s);
    local W = 10 * SW + 9 * G + 2 * P;
    local H = HEAD + SH + P;
    local x = nat and math.floor((nat[1] + nat[3]) / 2 - W / 2) or math.floor((sw - W) / 2);
    local y = nat and math.floor(nat[2]) or math.floor(30 * s);
    x = math.max(4, math.min(sw - W - 4, x));
    imgui.SetNextWindowPos({ x, y }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ W + 8, H + 8 }, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    UI.pushed = 2;
    local opened = imgui.Begin('##ccm_macro' .. (MCR.wid or ''), { true }, win_flags());
    UI.began = true;
    if opened then
        local dl = imgui.GetWindowDrawList();
        local hov_win = imgui.IsWindowHovered();
        local mx, my = mouse();
        DL.RF(dl, x, y, x + W, y + H, U4(0.035, 0.030, 0.050, 1), 10 * s);   -- (solid: covers the game's bar if it's still drawn)
        panel(dl, x, y, x + W, y + H, 1, s);
        local tk = font(11 * s);
        caps(dl, x + P + 2 * s, y + 6 * s, (half == 1) and 'CTRL' or 'ALT', C.acc, 2.2 * s, 1);
        local bs = set.set and ('BOOK %d   SET %d'):format(set.book, set.set) or ('BOOK %d'):format(set.book);
        text(dl, x + W - P - tw(bs), y + 5 * s, bs, C.dim, 1);
        unfont(tk);
        local hover = nil;
        for i = 1, 10 do
            local m = set.m[(half - 1) * 10 + i];
            local bx, by = x + P + (i - 1) * (SW + G), y + HEAD;
            local hv = hov_win and inside(mx, my, bx, by, bx + SW, by + SH);
            if hv then hover = i; end
            local on = (w.cursor == i);
            DL.RF(dl, bx, by, bx + SW, by + SH, U4(0.115, 0.105, 0.155, 0.92), 7 * s);
            local t1, t2 = U4(1, 1, 1, 0.05), U4(1, 1, 1, 0);
            DL.RFM(dl, bx + 1, by + 1, bx + SW - 1, by + SH * 0.5, t1, t1, t2, t2);
            DL.R(dl, bx, by, bx + SW, by + SH, hv and U4(1, 1, 1, 0.30) or U4(0.62, 0.40, 1.0, 0.20), 7 * s, 0, 1);
            local t_ = font(10.5 * s);
            text(dl, bx + 6 * s, by + 4 * s, tostring(i % 10), on and C.pink or C.acc, 1);
            unfont(t_);
            t_ = font(13.5 * s);
            local nm = (m and m.title ~= '') and m.title or '';
            local empty = (nm == '' and (not m or #m.lines == 0));
            if empty then nm = '-'; end
            while tw(nm) > SW - 10 * s and #nm > 1 do nm = nm:sub(1, #nm - 1); end
            text(dl, bx + (SW - tw(nm)) / 2, by + SH - 8 * s - imgui.GetTextLineHeight(), nm, empty and C.dim or (on and C.text or { 0.86, 0.84, 0.94, 1 }), 1);
            unfont(t_);
            if on then sel_frame(dl, bx, by, bx + SW, by + SH, 7 * s, (M.focus == w.addr) and 1 or 0.5); end
        end
        if hover and not UI.move and imgui.IsMouseClicked(0) then
            if w.ghost then MCRF.run(hover); else M.act(w.addr, hover, KEY.ok); end
        end
    end
    imgui.End();
    UI.began = false;
    imgui.PopStyleVar(2);
    UI.pushed = 0;
    return true;
end
-- Editing a book's macros (Commands > Macro > Edit Macro > a book > Confirm): the game's two rows, "mcr1edlo" (Ctrl)
-- and "mcr2edlo" (Alt), drawn like the macro bars - the set shown found from the names near them, as for the bars,
-- and checked again whenever they change (another set picked). The game's rows still do the work underneath.
EDM = { st = {} };
function EDM.set(w, half)
    local st = EDM.st[half];
    if not st or st.addr ~= w.addr then                              -- (the game makes the rows again after a line's edited: the set
        local old = st;                                              --  known a moment ago stands - no new look, no flicker)
        st = { addr = w.addr, book = MSEL.book };
        if old and old.set and old.book == MSEL.book then st.set, st.chain, st.tried = old.set, old.chain, true; end
        EDM.st[half] = st;
    end
    if st.chain and st.chain ~= '*' then
        local blob = MCR.follow(w, st.chain);
        if blob then
            if blob == st.blob and st.set then return st.set; end
            local strs = {}; MCR.strings(blob, strs);
            local s_ = MCR.score(strs);
            if s_ then st.set, st.blob = s_, blob; return s_; end
        end
    end
    if st.tried then return st.set; end
    st.tried = true;
    local h = MCR.scan(w, half);
    if h and not EDM.dumped and h.path ~= '*' then                  -- (once: the memory the names were found in, to the log - to
        EDM.dumped = true;                                           --  read them from there, as you change them)
        pcall(function()
            local b = MCR.follow(w, h.path);
            if b then M.note('edmdump' .. os.clock(), ('%s path %s: %s'):format(w.name, h.path, (b:sub(1, 0xC00):gsub('.', function(c) return ('%02X'):format(c:byte()); end)))); end
        end);
    end
    if h then st.chain, st.set = h.path, h.set;
    else st.set = EDM.blank(); end                                   -- (no names to know it by: a book still empty)
    return st.set;
end
-- (a book whose macros have no names yet - Book08 and on, say: the book picked in the list, its macros as they are
--  in its file if there is one, else empty; which of its 10 sets isn't known, so only the book is shown)
function EDM.blank()
    local bk = MSEL.book;
    if not bk then return nil; end
    local fo = (MCR.found and MCR.found.folder) or cfg.mcr_folder;
    for _, set in ipairs(MCR.load()) do
        if set.folder == fo and set.book == bk then
            for i = 1, 20 do if set.m[i] and (set.m[i].title or '') ~= '' then return nil; end end   -- (named: it'd have been found)
        end
    end
    local m = {};
    for i = 1, 20 do m[i] = { title = '', lines = {} }; end
    return { book = bk, set = nil, m = m, blank = true };
end
-- (the rows' boxes are drawn where their own buttons say, not where the window is: while editing, each button is moved
--  off screen too, and put back only while its window is still open - a closed window's buttons are gone)
EDM.bp = {};
function EDM.park_buttons(w)
    for _, b in ipairs(M.buttons(w)) do
        local ob = b.obj;
        if ob and not EDM.bp[ob] then EDM.bp[ob] = { x = b.x, y = b.y, win = w.addr, name = w.name }; end
        if ob and (b.x ~= -4000 or b.y ~= -4000) then
            ashita.memory.write_uint16(ob + 0x2A, 65536 - 4000);
            ashita.memory.write_uint16(ob + 0x2C, 65536 - 4000);
        end
    end
end
-- (in the line menu the rows' buttons stay where they are - the game finds its way back by them - but at no size, so
--  their boxes aren't seen; their size comes back when you're on the rows again, or the window closes)
EDM.shr = {};
function EDM.shrink(w)
    for _, b in ipairs(M.buttons(w)) do
        local ob = b.obj;
        if ob and not EDM.shr[ob] then EDM.shr[ob] = { w = b.w, h = b.h, win = w.addr, name = w.name }; end
        if ob and (b.w ~= 0 or b.h ~= 0) then ashita.memory.write_uint16(ob + 0x2E, 0); ashita.memory.write_uint16(ob + 0x30, 0); end
    end
end
function EDM.unshrink()
    for ob, v in pairs(EDM.shr) do
        local w = M.open[v.win];
        if w and w.name == v.name then
            pcall(function() ashita.memory.write_uint16(ob + 0x2E, v.w); ashita.memory.write_uint16(ob + 0x30, v.h); end);
        end
    end
    EDM.shr = {};
end
function EDM.restore_buttons()
    for ob, v in pairs(EDM.bp) do
        local w = M.open[v.win];
        if w and w.name == v.name and not w.closing then
            pcall(function()
                ashita.memory.write_uint16(ob + 0x2A, (v.x < 0) and (v.x + 65536) or v.x);
                ashita.memory.write_uint16(ob + 0x2C, (v.y < 0) and (v.y + 65536) or v.y);
            end);
        end
    end
    EDM.bp = {};
end
function MCR.gameui(hide)                                            -- (2.7.6-2.8.2 hid the game's bar through VanaCore: that's undone once;
    if MCR.hidden == false then return; end                          --  now ours just covers it, so nothing of the game's is switched off)
    MCR.hidden = false;
    pcall(function() vana.gameui.show('macro_bar'); end);
end
pcall(ffi.cdef, 'int16_t GetAsyncKeyState(int vKey);');
pcall(ffi.cdef, [[
typedef struct { uint16_t wButtons; uint8_t bLeftTrigger; uint8_t bRightTrigger; int16_t sThumbLX, sThumbLY, sThumbRX, sThumbRY; } CCM_XPAD;
typedef struct { uint32_t dwPacketNumber; CCM_XPAD Gamepad; } CCM_XSTATE;
uint32_t XInputGetState(uint32_t dwUserIndex, CCM_XSTATE* pState);
]]);
function MCR.held()                                                  -- Ctrl (1) / Alt (2) held, or a controller trigger (0)
    local k = nil;
    pcall(function()
        if bit.band(ffi.C.GetAsyncKeyState(0x11), 0x8000) ~= 0 then k = 1;
        elseif bit.band(ffi.C.GetAsyncKeyState(0x12), 0x8000) ~= 0 then k = 2; end
    end);
    if k then return k; end
    if MCR.xi == nil then
        MCR.xi = false;
        for _, n in ipairs({ 'xinput1_4', 'xinput1_3', 'xinput9_1_0' }) do
            local ok, lib = pcall(ffi.load, n);
            if ok and lib then MCR.xi = lib; break; end
        end
    end
    if MCR.xi then
        pcall(function()
            local st = MCR.xst or ffi.new('CCM_XSTATE'); MCR.xst = st;
            for i = 0, 3 do
                if MCR.xi.XInputGetState(i, st) == 0 then                -- (left trigger: the Ctrl bar, right: the Alt bar)
                    if st.Gamepad.bLeftTrigger > 60 then k = 1; break; end
                    if st.Gamepad.bRightTrigger > 60 then k = 2; break; end
                end
            end
        end);
    end
    return k;
end

-- An event's question with a few answers (the game's "query" box: "Enter the residential area?  Yes. / No."). Its text
-- is read from the box (the list's text pointer: the question, then one line an answer); the panel shows it in the new
-- style over the game's box. The game's own cursor is followed - your controller moves it as always - and confirming
-- is the game's own, so the answer sent is the game's. (Home Points and Survival Guides have their own list.)
QRY = { seen = {} };
function QRY.text(w)
    -- (the box's list keeps its text inside itself: the question, then each answer, one after another - and the same lines
    --  again further on. The number of answers is at +0x24. Found from the log: "Enter the residential area?" "Yes." "No."
    --  at +0x855, and again at +0xE71)
    local mp = rd32(w.addr + 0x0C);
    if mp < 0x10000 then return nil; end
    local blob = MCR.read(mp, 0x1000);
    if not blob or #blob < 0x40 then return nil; end
    local nopt = blob:byte(0x25) + blob:byte(0x26) * 256;
    if nopt < 1 or nopt > 8 then return nil, nopt, nil; end
    local toks = {};
    for st, s_, en in blob:gmatch('()([\32-\126][\32-\126]+)()') do toks[#toks + 1] = { st, s_, en }; end
    local function group(i)                                          -- question + answers, close together, at token i
        if i + nopt > #toks then return nil; end
        for k = i + 1, i + nopt do if toks[k][1] - toks[k - 1][3] > 3 then return nil; end end
        local g = {};
        for k = i, i + nopt do g[#g + 1] = toks[k][2]; end
        return g, table.concat(g, '\0');
    end
    for i = 1, #toks do
        local g, sig = group(i);
        if g and #g[1] >= 3 then
            for k = i + nopt + 1, #toks do                           -- (the same lines again: it's the question, not stray text)
                local g2, sig2 = group(k);
                if sig2 == sig then return g, nopt + 1, blob:sub(math.max(1, toks[i][1] - 16), math.min(#blob, toks[i + nopt][3] + 48)); end
            end
        end
    end
    return {}, nopt + 1, nil;
end
-- An event's question as the game keeps it in the box's list: "question" 07 0B "answer" 07 "answer" ... 7F; the number
-- of answers shown at +0x24, the one picked at +0x30 and the first one in view at +0x32 (0 = the first) - found from
-- the log while scrolling Sweepstox's lists. When an answer is left out by the game (more answers in the text than
-- it shows), which one isn't known: the game's own box then.
function QRY.marked(w)
    local mp = rd32(w.addr + 0x0C);
    if mp < 0x10000 then return nil; end
    local blob = MCR.read(mp, 0x4000);                               -- (the list can be bigger since a game update: read well past it)
    if not blob or #blob < 0x40 then return nil; end
    local shown = blob:byte(0x25) + blob:byte(0x26) * 256;
    -- (the box's text space can still hold the last question too: each question in it is tried, and the one whose
    --  answers come to what the game shows is taken)
    local first = nil;
    local at = 0x40;
    while true do
        local p = blob:find('\7\11', at, true);
        if not p then break; end
        local mq = QRY.marked_at(blob, p, shown, mp);
        first = first or mq;
        if #mq.opts == shown or QRY.hide(mq) then return mq, shown; end
        at = p + 2;
    end
    -- (the question itself is always in the box's list, as the game draws it: +0x36 its length, +0x38 one character a
    --  2-byte value, each 0x20 less than its letter. The answers aren't there - for questions known by their words,
    --  they're known here)
    do
        local gt = QRY.gtitle(blob);
        if gt then
            local im = QRY.items_menu(gt, shown, mp);
            if im then return im, shown; end
            for _, k in ipairs(QRY.KNOWN) do
                if gt:sub(1, #k[1]) == k[1] then
                    local opts = {}; for i, o in ipairs(k[2]) do opts[i] = o; end
                    local mq = { title = gt, opts = opts, shown = shown, mp = mp, mainbox = k.main };
                    if k.card and QRY.item_ev == QRY.ev then mq.card = QRY.last_item; end
                    if #opts == shown or QRY.hide(mq) then return mq, shown; end
                end
            end
            local zm = QRY.zone_match(gt, shown, mp);               -- (any other question: the zone's own text file)
            if zm then return zm, shown; end
            QRY.dump_box(w, mp, gt, shown);                          -- (not shown: the box's memory to the log, to find how it keeps its rows)
        end
    end
    local ev = QRY.ev;
    local mbox = ev and (ev.event == 20056 or ev.event == 6001) and os.clock() - ev.t < 600;
    if mbox and not ev.box then ev.box = w.addr; end                 -- (the event's first box: its main menu)
    if mbox and shown >= 2 then                                      -- (the Mystery Box's text not in the box's own list: looked for further off)
        local ok_, mq = pcall(QRY.seek, w, mp, shown);
        if ok_ and mq then return mq, shown; end
        -- (not found: its main menu is known - the first box of the event, with the tally from the event's 8th number)
        if ev.box == w.addr and (shown == 4 or shown == 5) then
            local opts = { 'Open the box and profit!', 'Listen to the explanation.', 'Inquire about my daily tally.', 'Peek at some possibilities.', 'Nothing right now.' };
            local mq = { title = ('Whatcha gonna do? (%d tally)'):format(ev.p[8] or 0), opts = opts, shown = shown, mp = mp, mainbox = true };
            if QRY.hide(mq) then return mq, shown; end
        end
        -- (and the dial list: the next box after "Open the box and profit!" was picked there - its dials in the box's
        --  fixed order, those the event marks hidden left out; used only if that comes to what the game shows)
        if ev.mainaddr and not ev.mainclosed and ev.mainaddr ~= w.addr then
            local mw_ = M.open[ev.mainaddr];
            if not mw_ or mw_.closing or mw_.name ~= 'query' then ev.mainclosed = true; end
        end
        if ev.box ~= w.addr and ev.mainpick == 1 and ev.mainclosed and (ev.dialbox == nil or ev.dialbox == w.addr) then
            ev.dialbox = w.addr;
            local opts = { 'I got cold feet, so none.', 'Dial 1 (Materials): 10 tally.', 'Dial 2 (Food): 10 tally.', 'Dial 3 (Medicine): 10 tally.',
                           'Dial 4 (Sundries 1): 10 tally.', 'Dial 5 (Sundries 2): 10 tally.', 'Special dial: 50 tally.', 'Adoulin dial: 0 tally.',
                           'Pictlogica dial: 0 tally.', '@', '@', '@', 'Wanted dial: 0 tally.', '@', '@' };
            local mq = { title = ('So, what dial ya gonna pick? (%d tally)'):format(ev.p[8] or 0), opts = opts, shown = shown, mp = mp };
            if QRY.hide(mq) then return mq, shown; end
        end
    end
    return first, shown;
end
-- The question's text isn't always in the box's own list (seen with Priztrix's box): then it's looked for in memory
-- reachable from the box (pointers, a few steps deep), by its marks - the question, 07 0B, the answers, 7F - and
-- only a text whose answers come to what the game shows is taken. Where it was found is kept (the steps from the box)
-- and tried first next time; each box is searched only once.
QRY.found = {};
function QRY.seek_ok(mq)                                             -- (only the Mystery Box's own questions: other old text lies about too)
    local t = mq.title or '';
    return t:find('Whatcha gonna do?', 1, true) ~= nil or t:find('what dial ya gonna pick', 1, true) ~= nil;
end
function QRY.seek(w, mp, shown)
    local key = w.addr .. ':' .. mp;
    local f = QRY.found[key];
    if f ~= nil then
        if not f then return nil; end
        local blob = MCR.read(f.at, 0x1000);
        if blob then
            local at = 1;
            while true do
                local p = blob:find('\7\11', at, true);
                if not p then break; end
                local mq = QRY.marked_at(blob, p, shown, mp);
                if QRY.seek_ok(mq) and (#mq.opts == shown or QRY.hide(mq)) then return mq; end
                at = p + 2;
            end
        end
        return nil;
    end
    QRY.found[key] = false;
    local function follow(path)                                      -- (the address a kept path leads to now)
        local a_ = (path[1] == 'w') and w.addr or mp;
        for i = 2, #path do
            local b4 = MCR.read(a_ + path[i], 4);                    -- (read safely: an old path can lead anywhere)
            if not b4 or #b4 < 4 then return nil; end
            local v = b4:byte(1) + b4:byte(2) * 256 + b4:byte(3) * 65536 + b4:byte(4) * 16777216;
            if v < 0x01000000 or v >= 0x7FFF0000 then return nil; end
            a_ = v;
        end
        return a_;
    end
    local tries = {};
    if QRY.path then local a_ = follow(QRY.path); if a_ then tries[1] = { a_, QRY.path }; end end
    local seen, queue, n = {}, { { w.addr, { 'w' } }, { mp, { 'L' } } }, 0;
    local function test(addr, path)
        local blob = MCR.read(addr, 0x1000);
        if not blob then return nil, nil; end
        local at = 1;
        while true do
            local p = blob:find('\7\11', at, true);
            if not p then break; end
            local mq = QRY.marked_at(blob, p, shown, mp);
            if QRY.seek_ok(mq) and (#mq.opts == shown or QRY.hide(mq)) then return mq, blob; end
            at = p + 2;
        end
        return nil, blob;
    end
    for _, t in ipairs(tries) do
        local mq = test(t[1], t[2]);
        if mq then QRY.found[key] = { at = t[1] }; return mq; end
    end
    while #queue > 0 and n < 1500 do
        local qq = table.remove(queue, 1);
        n = n + 1;
        local mq, blob = test(qq[1], qq[2]);
        if mq then
            QRY.found[key] = { at = qq[1] };
            QRY.path = qq[2];
            local ps = {}; for i = 2, #qq[2] do ps[#ps + 1] = ('%X'):format(qq[2][i]); end
            M.note('qseek' .. os.clock(), ('question text found further off: %s>%s after %d places: "%s"'):format(qq[2][1], table.concat(ps, '>'), n, mq.title));
            return mq;
        end
        if blob and #qq[2] < 5 then
            for off = 0, math.min(#blob, 0x200) - 4, 4 do
                local p_ = blob:byte(off + 1) + blob:byte(off + 2) * 256 + blob:byte(off + 3) * 65536 + blob:byte(off + 4) * 16777216;
                if p_ >= 0x01000000 and p_ < 0x7FFF0000 and not seen[p_] then
                    seen[p_] = true;
                    local np = {}; for i, v in ipairs(qq[2]) do np[i] = v; end
                    np[#np + 1] = off;
                    queue[#queue + 1] = { p_, np };
                end
            end
        end
    end
    M.note('qseek' .. os.clock(), ('question text not found (%d places searched)'):format(n));
    return nil;
end
QRY.KNOWN = {
    { 'What can I assist you with?', { 'Check/Exchange points.', 'Learn about the campaign.', 'Nothing.' } },   -- (the Greeter Moogle)
    { 'Proceed with exchange?', { 'Yes.', 'No.' }, card = true },                                                           -- (its confirm)
    { 'View which item?', { '50-point items.', '200-pt. items.', '300-pt. items.', '500-pt. items.', '750-pt. items.',
                            '1000-pt. items.', '1500-pt. items.', '1500-pt. items.', 'Back.' } },
    { 'Whatcha gonna do?', { 'Open the box and profit!', 'Listen to the explanation.', 'Inquire about my daily tally.',
                             'Peek at some possibilities.', 'Nothing right now.' }, main = true },              -- (the Mystery Box)
    { 'So, what dial ya gonna pick?', { 'I got cold feet, so none.', 'Dial 1 (Materials): 10 tally.', 'Dial 2 (Food): 10 tally.',
        'Dial 3 (Medicine): 10 tally.', 'Dial 4 (Sundries 1): 10 tally.', 'Dial 5 (Sundries 2): 10 tally.', 'Special dial: 50 tally.',
        'Adoulin dial: 0 tally.', 'Pictlogica dial: 0 tally.', '@', '@', '@', 'Wanted dial: 0 tally.', '@', '@' } },   -- (its dials: the
                                                                     --  ones the event marks hidden left out - its question, with your
                                                                     --  tally, read from the game, so a new tally doesn't matter)
};
-- An event's update (in 0x05C: eight numbers from +0x04). The Greeter Moogle's item lists come this way: first the
-- items (item numbers, two to a number), then which of its places to hide, the price and your points.
function QRY.update(d)
    local function u(o, n) local v = 0; for i = n - 1, 0, -1 do v = v * 256 + (d:byte(o + i + 1) or 0); end return v; end
    if #d < 0x24 then return; end
    do local nums = {}; for i = 0, 7 do nums[i + 1] = u(0x04 + i * 4, 4); end QRY.upd_nums = { p = nums, t = os.clock() }; end
    local ids = {};
    for i = 0, 15 do
        local v = u(0x04 + i * 2, 2);
        if v == 0 then break; end
        ids[#ids + 1] = v;
    end
    local named = #ids > 0;
    for _, id in ipairs(ids) do
        local ok_, nm = pcall(function() local r = AshitaCore:GetResourceManager():GetItemById(id); return r and r.Name and r.Name[1]; end);
        if not ok_ or not nm or nm == '' then named = false; break; end
    end
    if named then QRY.upd_items = { ids = ids, t = os.clock() };
    elseif u(0x04, 4) == 0 and u(0x08, 4) == 0 then QRY.upd_price = { mask = u(0x0C, 4), price = u(0x10, 4), points = u(0x14, 4), t = os.clock() }; end
end
function QRY.item_line(id)                                           -- ("Chocobo masque." - the item's name as the game writes it in a line)
    local nm = nil;
    pcall(function()
        local r = AshitaCore:GetResourceManager():GetItemById(id);
        local ls = r and r.LogNameSingular;
        nm = (type(ls) == 'table' or type(ls) == 'userdata') and ls[1] or nil;
        if not nm or nm == '' then nm = r and r.Name and r.Name[1]; end
    end);
    if not nm or nm == '' then return nil; end
    nm = nm:gsub('^%l', string.upper);
    return nm .. '.';
end
function QRY.card_alone(id, nat)                                     -- (the card with no panel round it: in a window of its own, empty
    imgui.SetNextWindowPos({ 0, 0 }, ImGuiCond_Always);              --  and see-through - its text sizes need one - so no stray
    imgui.SetNextWindowSize({ 1, 1 }, ImGuiCond_Always);             --  'Debug' window appears)
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    UI.pushed = 2;
    imgui.Begin('##ccm_qcard', { true }, win_flags());
    UI.began = true;
    UI.tip_scale = 1.35;
    item_tooltip(id, 0, 0, nat and { nat[1], nat[2], nat[2] } or nil);
    UI.tip_scale = nil;
    imgui.End();
    UI.began = false;
    imgui.PopStyleVar(2);
    UI.pushed = 0;
    return true;
end
function QRY.card_wanted()                                           -- (the exchange's message, the game's item card up: ours instead)
    return cfg.query ~= false and QRY.last_item ~= nil and QRY.item_ev ~= nil and QRY.item_ev == QRY.ev
        and M.find('rem4li2') ~= nil and M.find('iteminfo') ~= nil;
end
function QRY.items_menu(gt, shown, mp)                               -- the Greeter Moogle's "300-pt. items (3300 pts.):" list
    local pts = gt:match('^(%d+)%-pt%. items') or gt:match('^(%d+)%-point items');
    local I, P = QRY.upd_items, QRY.upd_price;
    -- (the items sent in this conversation - after its event began - still stand when the list comes back, e.g. after
    --  No on the exchange; the price sent with them must be this list's)
    local ev0 = QRY.ev and QRY.ev.t or 0;
    if not pts or not I or I.t < ev0 then return nil; end
    if not P or P.t < I.t or P.price ~= tonumber(pts) then return nil; end
    local opts = {};
    for i, id in ipairs(I.ids) do
        local l = QRY.item_line(id);
        if not l then return nil; end
        opts[i] = l;
    end
    opts[#opts + 1] = 'Back.';
    if #opts ~= shown then return nil; end
    return { title = gt, opts = opts, shown = shown, mp = mp, ids = I.ids };
end
do
-- EVM: just enough of the game's event script machine to know what an NPC's question hides. The zone's event file
-- (file 5820 + zone; 84991 + zone - 256 past 255): blocks per actor (its server id), each with its events' offsets,
-- immediate data and byte code. From the event's start, with the server's 8 numbers in zone work 2-9, the arithmetic,
-- jumps, calls, bit fields and tables run; everything else is stepped over by its length. At each question (0x24, or
-- 0xD4 0/2) whose message is the one on screen, the hidden-options mask (and the work values its message numbers come
-- from) are taken. An earlier question (a menu before this one) is answered every way it can be, and only an answer
-- every way agrees on is used. Opcode lengths and meanings: GordianXI (MIT), from XiEvents.
EVM = EVM or { files = {} };
local band, bor, bxor, bnot, lshift, rshift, arshift = bit.band, bit.bor, bit.bxor, bit.bnot, bit.lshift, bit.rshift, bit.arshift;
EVM.FIXED = {
    [0x00]=1,[0x01]=3,[0x02]=8,[0x03]=5,[0x04]=3,[0x05]=3,[0x06]=3,[0x07]=5,[0x08]=5,[0x09]=5,[0x0A]=5,[0x0B]=3,[0x0C]=3,[0x0D]=5,[0x0E]=5,[0x0F]=5,[0x10]=5,[0x11]=5,[0x12]=3,[0x13]=5,
    [0x14]=5,[0x15]=5,[0x16]=7,[0x17]=7,[0x18]=7,[0x19]=5,[0x1A]=3,[0x1B]=1,[0x1C]=3,[0x1D]=3,[0x1E]=5,[0x20]=2,[0x21]=1,[0x22]=2,[0x23]=1,[0x24]=7,[0x25]=1,[0x26]=1,[0x27]=7,[0x28]=7,
    [0x29]=7,[0x2A]=6,[0x2B]=7,[0x2C]=13,[0x2D]=13,[0x2E]=1,[0x2F]=6,[0x30]=1,[0x32]=3,[0x33]=2,[0x34]=3,[0x35]=3,[0x36]=7,[0x37]=9,[0x38]=3,[0x39]=3,[0x3A]=7,[0x3B]=11,[0x3C]=7,[0x3D]=7,
    [0x3E]=7,[0x3F]=7,[0x40]=9,[0x41]=9,[0x42]=1,[0x43]=2,[0x44]=5,[0x45]=17,[0x48]=3,[0x49]=7,[0x4A]=9,[0x4B]=7,[0x4C]=1,[0x4D]=1,[0x4E]=6,[0x4F]=3,[0x50]=13,[0x51]=13,[0x52]=15,[0x53]=13,
    [0x54]=13,[0x55]=15,[0x56]=5,[0x57]=3,[0x58]=1,[0x5B]=15,[0x5D]=5,[0x5E]=5,[0x61]=2,[0x62]=17,[0x63]=3,[0x64]=11,[0x65]=11,[0x66]=15,[0x67]=5,[0x68]=1,[0x69]=4,[0x6A]=7,[0x6B]=9,[0x6C]=9,
    [0x6D]=7,[0x6E]=7,[0x6F]=1,[0x70]=1,[0x73]=11,[0x74]=2,[0x76]=5,[0x77]=5,[0x78]=1,[0x7B]=5,[0x7C]=6,[0x7D]=3,[0x7F]=1,[0x80]=5,[0x81]=6,[0x82]=7,[0x83]=3,[0x84]=1,[0x85]=1,[0x86]=6,
    [0x87]=2,[0x88]=2,[0x89]=3,[0x8A]=1,[0x8B]=25,[0x8D]=5,[0x8E]=1,[0x8F]=1,[0x90]=1,[0x91]=3,[0x92]=6,[0x93]=3,[0x94]=6,[0x95]=3,[0x96]=1,[0x97]=5,[0x98]=1,[0x99]=5,[0x9A]=1,[0x9B]=1,
    [0x9C]=3,[0x9E]=2,[0x9F]=17,[0xA0]=15,[0xA1]=15,[0xA2]=15,[0xA3]=15,[0xA4]=2,[0xA5]=2,[0xA8]=6,[0xA9]=3,[0xAA]=17,[0xAD]=12,[0xAF]=8,[0xB0]=12,[0xB1]=4,[0xB5]=4,[0xB8]=27,[0xB9]=8,[0xBA]=13,
    [0xBB]=17,[0xBC]=15,[0xBD]=15,[0xBE]=3,[0xC0]=3,[0xC1]=5,[0xC3]=7,[0xC4]=12,[0xC5]=17,[0xC6]=15,[0xC7]=15,[0xC8]=7,[0xC9]=1,[0xCD]=17,[0xCE]=15,[0xCF]=15,[0xD0]=17,[0xD1]=15,[0xD2]=15,[0xD3]=6,
    [0xD5]=17,[0xD6]=15,[0xD7]=15,[0xD9]=2,
};
local function rng(t, a, b, n) for i = a, b do if t[i] == nil then t[i] = n; end end return t; end
EVM.SUB = {
    [0x1F]={[0]=8,[1]=2}, [0x31]={[0]=10,[1]=2}, [0x46]={[0]=2,[1]=2,[2]=4}, [0x47]={[0]=10,[1]=2}, [0x5A]={[0]=8,[1]=2},
    [0x59]={[0]=4,[1]=8,[2]=4,[3]=8,[4]=8,[5]=7,[6]=6,[7]=4,[8]=8},
    [0x5C]=rng(rng({[0xA0]=6,[0xA1]=6}, 0x80, 0x87, 6), 0, 7, 4),
    [0x5F]={[0]=2,[1]=2,[2]=6,[3]=16,[4]=16,[5]=18,[6]=18,[7]=14},
    [0x60]=rng({[0]=4,[1]=4,[2]=6}, 3, 0xFF, 2),
    [0x71]={[0]=2,[1]=2,[2]=2,[3]=4,[0x10]=4,[0x11]=4,[0x13]=4,[0x12]=6,[0x20]=16,[0x21]=2,[0x30]=4,[0x31]=4,[0x32]=6,[0x40]=4,[0x41]=8,[0x50]=4,[0x51]=2,[0x52]=4,[0x53]=2,[0x54]=10,[0x55]=4},
    [0x72]={[0]=4,[1]=6}, [0x75]={[0]=4,[1]=2,[2]=2}, [0x79]={[0]=10,[1]=12,[2]=10},
    [0x7E]={[0]=6,[1]=6,[2]=6,[3]=16,[4]=6,[5]=6,[6]=18,[7]=8,[8]=6}, [0x7A]={[0]=6,[1]=7,[2]=6,[3]=2,[4]=8,[5]=6},
    [0x8C]={[0]=8,[1]=2,[2]=12,[3]=10,[4]=10,[5]=14},
    [0x9D]={[0]=8,[1]=8,[2]=6,[3]=8,[4]=8,[5]=8,[6]=8,[7]=6,[8]=23,[9]=9,[0xA]=10,[0xB]=10,[0xC]=8,[0xD]=10,[0xE]=10,[0xF]=10,[0x10]=10},
    [0xA6]={[0]=2,[1]=2,[2]=4}, [0xA7]={[0]=2,[1]=4},
    [0xAB]=rng({[0x11]=4,[0x14]=4,[0x15]=4,[0x16]=4,[0x17]=4,[0x18]=4,[0x19]=2,[0x1A]=2,[0x1B]=6,[0x1C]=6}, 0, 0x13, 2),
    [0xAC]={[0]=4,[1]=4,[2]=6,[3]=6,[4]=8}, [0xAE]={[0]=6,[1]=8,[2]=8,[3]=8,[4]=8,[5]=10,[6]=6,[7]=10,[8]=10},
    [0xB2]={[0]=4,[1]=2}, [0xB3]={[0]=4,[1]=14,[2]=2,[3]=4,[4]=4,[5]=18,[6]=4,[7]=4,[8]=2,[9]=4},
    [0xB4]={[0]=20,[1]=6,[2]=6,[3]=2,[4]=6,[5]=3,[6]=3,[7]=4,[8]=2,[9]=4,[0xA]=4,[0xB]=2,[0xC]=4,[0xD]=2,[0xE]=2,[0xF]=6,[0x10]=6,[0x11]=6,[0x12]=6,[0x13]=20,[0x14]=12,[0x15]=2},
    [0xB6]=rng({[0xB]=20,[0xC]=4,[0xD]=14,[0xE]=16,[0xF]=4,[0x10]=2,[0x11]=4,[0x12]=2,[0x13]=2,[0x14]=6,[0x15]=6}, 0, 0x0A, 4),
    [0xB7]={[0]=10,[1]=8,[2]=8,[3]=8,[4]=8}, [0xBF]={[0]=8,[0x20]=10,[0x40]=10,[0x60]=8},
    [0xC2]=rng({[0]=2,[1]=4,[2]=6}, 3, 0xFF, 2),
    [0xCC]={[0]=10,[1]=10,[3]=10,[2]=14,[0x10]=6,[0x11]=4,[0x20]=4},
    [0xD4]={[0]=8,[1]=8,[2]=8,[3]=6,[4]=12,[5]=12}, [0xD8]={[0]=6,[1]=8,[2]=8,[3]=8,[4]=12},
};
local function u16(s, o) local a, b = s:byte(o + 1, o + 2); return (a or 0) + (b or 0) * 256; end
local function u32(s, o) local a, b, c, d = s:byte(o + 1, o + 4); return (a or 0) + (b or 0) * 256 + (c or 0) * 65536 + (d or 0) * 16777216; end
local function s32(v) v = v % 4294967296; if v >= 2147483648 then v = v - 4294967296; end return v; end
function EVM.parse(d)
    local cnt = u32(d, 0);
    if cnt <= 0 or cnt > 100000 or 4 + 4 * cnt > #d then return nil, 'bad block count'; end
    local blocks, pos = {}, 4 + 4 * cnt;
    for i = 0, cnt - 1 do
        local size = u32(d, 4 + 4 * i);
        if size < 16 or pos + size > #d then return nil, 'bad block size'; end
        local b = d:sub(pos + 1, pos + size);
        pos = pos + size;
        local actor, ec = u32(b, 0), u32(b, 4);
        local o = 8;
        local offs, ids = {}, {};
        for k = 0, ec - 1 do offs[k + 1] = u16(b, o + 2 * k); end
        o = o + 2 * ec;
        for k = 0, ec - 1 do ids[k + 1] = u16(b, o + 2 * k); end
        o = o + 2 * ec;
        local rc = u32(b, o); o = o + 4;
        local refs = {};
        for k = 0, rc - 1 do refs[k] = s32(u32(b, o + 4 * k)); end
        o = o + 4 * rc;
        local cs = u32(b, o); o = o + 4;
        local blk = { actor = actor, offs = offs, ids = ids, refs = refs, nrefs = rc, code = b:sub(o + 1, o + cs) };
        blocks[#blocks + 1] = blk;
        blocks[actor] = blocks[actor] or blk;
    end
    return blocks;
end
function EVM.start_of(blk, ev)
    local at = nil;
    for i, id in ipairs(blk.ids) do if id == ev then at = blk.offs[i]; end end
    if not at then for i, id in ipairs(blk.ids) do if id == 0xFFFE then at = blk.offs[i]; end end end
    return at;
end
function EVM.len(code, pc)
    local op = code:byte(pc + 1);
    if not op then return 0; end
    local n = EVM.FIXED[op];
    if n then return n; end
    local t = EVM.SUB[op];
    local sub = code:byte(pc + 2);
    return (t and sub and t[sub]) or 0;
end
-- one run: st = { pc, loc, zone, z17, mem, js }; returns 'query', 'end' or 'abort'
local function newstate(pc, params)
    local st = { pc = pc, loc = {}, zone = {}, z17 = {}, mem = {}, js = {}, tbl = {} };
    for i = 0, 7 do st.zone[2 + i] = s32(params[i + 1] or 0); end
    return st;
end
local function copy(st)
    local n = { pc = st.pc, loc = {}, zone = {}, z17 = {}, mem = {}, js = {}, tbl = {} };
    for _, k in ipairs({ 'loc', 'zone', 'z17', 'mem', 'js', 'tbl' }) do for a, v in pairs(st[k]) do n[k][a] = v; end end
    return n;
end
function EVM.run(blk, start, params, want, opts)
    opts = opts or {};
    local code, refs, nrefs = blk.code, blk.refs, blk.nrefs;
    local results, budget, forks = {}, { steps = opts.steps or 400000 }, { n = 0 };
    local function getk(st, key)
        if band(key, 0x8000) ~= 0 then local i = band(key, 0x7FFF); return (i < nrefs) and refs[i] or 0; end
        if key < 2048 then return st.loc[key] or 0; end
        if key < 4352 then return (key >= 4096) and (st.zone[key - 4096] or 0) or 0; end
        if key < 4608 then return st.mem[key - 4352] or 0; end
        if key < 6144 then return (key >= 5888) and (st.z17[key - 5888] or 0) or 0; end
        return 0;
    end
    local function setk(st, key, v)
        if band(key, 0x8000) ~= 0 then return; end
        v = s32(v);
        if key < 2048 then st.loc[key] = v;
        elseif key < 4352 then if key >= 4096 then st.zone[key - 4096] = v; end
        elseif key < 4608 then st.mem[key - 4352] = v;
        elseif key < 6144 then if key >= 5888 then st.z17[key - 5888] = v; end end
    end
    local function walk(st, depth)
        local pending = nil;                                         -- (a question that isn't ours, waiting for its answer)
        while true do
            budget.steps = budget.steps - 1;
            if budget.steps <= 0 then return 'abort'; end
            local pc = st.pc;
            local op = code:byte(pc + 1);
            if not op then return 'end'; end
            local function C16(o) return u16(code, pc + o); end
            local function W(o, sh) return getk(st, C16(o) + (sh or 0)); end
            local function S(o, v, sh) setk(st, C16(o) + (sh or 0), v); end
            local n = EVM.len(code, pc);
            if op == 0x00 or op == 0x21 or op == 0x26 then return 'end';
            elseif op == 0x01 then st.pc = C16(1);
            elseif op == 0x02 then
                local kind = band(code:byte(pc + 6) or 0, 0x0F);
                local a, b = W(1), W(3);
                local j;
                if kind == 0 then j = a ~= b; elseif kind == 1 or kind == 7 then j = a == b; elseif kind == 2 then j = a <= b;
                elseif kind == 3 then j = a >= b; elseif kind == 4 then j = a < b; elseif kind == 5 then j = a > b;
                elseif kind == 6 or kind == 9 then j = band(a, b) == 0; elseif kind == 8 then j = bor(a, b) == 0;
                elseif kind == 10 then j = band(bnot(a), b) == 0; else j = true; end
                if j then st.pc = C16(6); else st.pc = pc + 8; end
            elseif op == 0x03 then S(1, W(3)); st.pc = pc + 5;
            elseif op == 0x05 then S(1, 1); st.pc = pc + 3;
            elseif op == 0x06 then S(1, 0); st.pc = pc + 3;
            elseif op == 0x07 then S(1, W(1) + W(3)); st.pc = pc + 5;
            elseif op == 0x08 then S(1, W(1) - W(3)); st.pc = pc + 5;
            elseif op == 0x09 then S(1, bor(W(1), lshift(1, band(W(3), 31)))); st.pc = pc + 5;
            elseif op == 0x0A then S(1, band(W(1), bnot(lshift(1, band(W(3), 31))))); st.pc = pc + 5;
            elseif op == 0x0B then S(1, W(1) + 1); st.pc = pc + 3;
            elseif op == 0x0C then S(1, W(1) - 1); st.pc = pc + 3;
            elseif op == 0x0D then S(1, band(W(1), W(3))); st.pc = pc + 5;
            elseif op == 0x0E then S(1, bor(W(1), W(3))); st.pc = pc + 5;
            elseif op == 0x0F then S(1, bxor(W(1), W(3))); st.pc = pc + 5;
            elseif op == 0x10 then S(1, lshift(W(1), band(W(3), 31))); st.pc = pc + 5;
            elseif op == 0x11 then S(1, arshift(W(1), band(W(3), 31))); st.pc = pc + 5;
            elseif op == 0x12 or op == 0x13 then return 'abort';     -- (a random number: what the game showed can't be known)
            elseif op == 0x14 then S(1, W(1) * W(3)); st.pc = pc + 5;
            elseif op == 0x15 then local a, b = W(1), W(3); S(1, (a ~= 0 and b ~= 0) and ((a / b >= 0) and math.floor(a / b) or math.ceil(a / b)) or 0); st.pc = pc + 5;
            elseif op == 0x19 then local a, b = W(1), W(3); S(1, b); S(3, a); st.pc = pc + 5;
            elseif op == 0x1A then
                if #st.js >= 8 then return 'abort'; end
                st.js[#st.js + 1] = pc + 3; st.pc = C16(1);
            elseif op == 0x1B then
                if #st.js > 0 then st.pc = table.remove(st.js); else return 'end'; end
            elseif op == 0x3C or op == 0x3D then
                local bt = W(3);
                if rshift(bt, 5) < W(5) then
                    local word, flag = W(1, rshift(bt, 5)), lshift(1, band(bt, 31));
                    S(1, (op == 0x3C) and bor(word, flag) or band(word, bnot(flag)), rshift(bt, 5));
                end
                st.pc = pc + 7;
            elseif op == 0x3E then
                local bt = W(3);
                if band(W(1, rshift(bt, 5)), lshift(1, band(bt, 31))) ~= 0 then st.pc = pc + 7; else st.pc = C16(5); end
            elseif op == 0x3F then local a, b = W(3), W(5); S(1, (a ~= 0 and b ~= 0) and math.fmod(a, b) or 0); st.pc = pc + 7;
            elseif op == 0x40 or op == 0x41 then
                local from, to = W(1), W(3);
                local mask = 0;
                for x = 0, 31 do if x >= from and x <= to then mask = bor(mask, lshift(1, x)); end end
                if op == 0x40 then S(5, bor(band(bnot(mask), W(5)), band(mask, lshift(W(7), band(from, 31)))));
                else S(7, rshift(band(mask, W(5)), band(from, 31))); end
                st.pc = pc + 9;
            elseif op == 0x43 and (code:byte(pc + 2) or 0) == 1 then   -- (waits for the server's new numbers: the latest it sent)
                if opts.update then for i = 0, 7 do st.zone[2 + i] = s32(opts.update[i + 1] or 0); end end
                st.pc = pc + 2;
            elseif op == 0x9D then
                local sub = code:byte(pc + 2) or 0;
                local function key_at(p) return u16(code, p); end
                if sub == 0x00 or sub == 0x0A then
                    local tb, idx = C16(2), W(6);
                    if sub == 0x0A then local bd = W(8); if bd ~= 0 and bd <= idx then idx = 0; end end
                    S(4, getk(st, key_at(tb + 2 * idx)));
                    st.pc = pc + ((sub == 0) and 8 or 10);
                elseif sub == 0x05 or sub == 0x0F then
                    local tb, idx = C16(2), W(6);
                    if sub == 0x0F then local bd = W(8); if bd ~= 0 and bd <= idx then idx = 0; end end
                    setk(st, key_at(tb + 2 * idx), W(4));
                    st.pc = pc + ((sub == 5) and 8 or 10);
                elseif sub == 0x02 or sub == 0x0C then st.tbl[W(4)] = C16(2); st.pc = pc + ((sub == 2) and 6 or 8);
                elseif sub == 0x03 or sub == 0x0D then
                    local t0, idx = st.tbl[W(2)], W(6);
                    if sub == 0x0D then local bd = W(8); if bd ~= 0 and bd <= idx then idx = 0; end end
                    if t0 then S(4, getk(st, key_at(t0 + 2 * idx))); end
                    st.pc = pc + ((sub == 3) and 8 or 10);
                elseif sub == 0x07 then
                    if #st.js >= 8 then return 'abort'; end
                    st.js[#st.js + 1] = pc + 6; st.pc = key_at(C16(2) + 2 * W(4));
                elseif n > 0 then st.pc = pc + n;
                else return 'abort'; end
            elseif op == 0x24 or (op == 0xD4 and ((code:byte(pc + 2) or 9) == 0 or code:byte(pc + 2) == 2)) then
                local o = (op == 0x24) and 1 or 2;
                local msg, dflt, mask = W(o), W(o + 2), W(o + 4);
                if msg == want then
                    local params = {};
                    for i = 0, 7 do params[i] = st.zone[2 + i] or 0; end
                    for i = 0, 31 do params[8 + i] = st.z17[i] or 0; end
                    results[#results + 1] = { mask = band(mask, 0xFFFFFFFF), dflt = dflt, params = params };
                    return 'query';
                end
                pending = { msg = msg, n = opts.count and opts.count(msg) or 0 };
                st.pc = pc + n;
            elseif op == 0x25 or op == 0x7F then
                if pending then                                      -- (answered each way it can be: each branch goes on)
                    local cnt = math.min(pending.n, 24);
                    if cnt <= 0 or depth >= 3 then return 'abort'; end
                    for ch = 0, cnt - 1 do
                        forks.n = forks.n + 1;
                        if forks.n > (opts.forks or 80) then return 'abort'; end
                        local b2 = copy(st);
                        b2.zone[0] = ch; b2.pc = pc + 1;
                        walk(b2, depth + 1);
                    end
                    return 'end';
                end
                st.pc = pc + 1;
            elseif n > 0 then st.pc = pc + n;
            else return 'abort'; end
        end
    end
    local why = walk(newstate(start, params), 0);
    return results, why;
end
-- (what the box hides: the masks every way to it agree on, or nil)
function EVM.mask_for(blocks, actor, ev, params, want, opts)
    local blk = blocks[actor];
    local start = blk and EVM.start_of(blk, ev);
    if not start then
        for _, b in ipairs(blocks) do local s_ = EVM.start_of(b, ev); if s_ and b.actor ~= 0x7FFFFFF0 then blk, start = b, s_; break; end end
    end
    if not start then return nil, 'event not found'; end
    local R, why = EVM.run(blk, start, params, want, opts);
    if #R == 0 then return nil, 'question not reached (' .. tostring(why) .. ')'; end
    local m = R[1].mask;
    for _, r in ipairs(R) do if r.mask ~= m then return nil, 'masks differ'; end end
    return R[1];
end
end
-- The zone's own text: the game's data file with every line its events can say (file 6420 + zone, or for Adoulin's
-- zones 85591 + zone - 256: a 4-byte header, its low 28 bits the size and bit 28 "each byte XOR 0x80"; then the
-- offsets of each line, the first of them telling how many; each line's bytes to the next). A question is one line
-- with its answers after it: "question" 07 0B "answer" 07 "answer" ... 7F - the same shape as in the box's memory.
-- So a box whose title (its glyphs) is a question in the file has its answers from there, when they aren't in memory.
QRY.zt = {};
QRY.ELEM = { 'Fire', 'Ice', 'Wind', 'Earth', 'Lightning', 'Water', 'Light', 'Dark' };   -- (the EF 1F..26 marks)
function QRY.zone_file(zone)
    if zone < 256 then return 6420 + zone; end
    return 85591 + (zone - 256);
end
function QRY.zone_now()
    local z = QRY.ev and QRY.ev.zone;
    if not z or z == 0 then pcall(function() z = AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0); end); end
    return z;
end
function QRY.xor80(b)
    local ok, r = pcall(function()
        local n = #b;
        local buf = ffi.new('uint8_t[?]', n);
        ffi.copy(buf, b, n);
        for i = 0, n - 1 do buf[i] = bit.bxor(buf[i], 0x80); end
        return ffi.string(buf, n);
    end);
    if ok and r then return r; end
    if not QRY.XT then QRY.XT = {}; for i = 0, 255 do QRY.XT[string.char(i)] = string.char(bit.bxor(i, 0x80)); end end
    return (b:gsub('.', QRY.XT));
end
function QRY.zt_clean(t)                                             -- (a line's text as we show it; nil when it has a part we can't know)
    t = t:gsub('\x0C.%[([^%]]*)%]', function(alts) return (alts:match('^([^/]*)')) or ''; end);   -- (one of two wordings, by the event: the first)
    if t:find('\x7F[^1]') or t:find('\x0C', 1, true) or t:find('\n', 1, true) then return nil; end   -- (a name or number filled in by the
    t = t:gsub('\xEF([\x1F-\x26])', function(c) local k = c:byte() - 0x1E; return '\1' .. string.char(48 + k) .. QRY.ELEM[k]; end);   --  event; a part that depends)
    t = t:gsub('\xEF\x27', '\2'):gsub('\xEF%(', '\3');
    t = t:gsub('\7', ' '):gsub('\x7F.', ''):gsub('[\4-\31\127-\255]', ''):gsub('  +', ' '):gsub('^%s+', ''):gsub('%s+$', '');
    return t;
end
function QRY.zt_menu(line, no)
    local p = line:find('\7\11', 1, true);
    if not p then return nil; end
    local title = line:sub(1, p - 1);
    local e = line:find('\x7F1', p + 2, true) or line:find('%z', p + 2) or (#line + 1);   -- (7F 31 00 07 ends the line)
    local opts, bad = {}, false;
    for o in (line:sub(p + 2, e - 1) .. '\7'):gmatch('([^\7]*)\7') do
        local c = QRY.zt_clean(o);
        if c == nil then bad = true; c = '?'; end
        opts[#opts + 1] = c;
    end
    local tc = QRY.zt_clean(title);
    local prefix = nil;
    if tc == nil then                                                -- (a question with a name in it: known by what comes before it)
        local q = title:find('[\x7F\x0C\n]');
        prefix = q and QRY.zt_clean(title:sub(1, q - 1)) or nil;
        if prefix and #prefix < 6 then prefix = nil; end
    end
    if (tc == nil or tc == '') and not prefix then return nil; end
    local raw = {};
    for o in (line:sub(p + 2, e - 1) .. '\7'):gmatch('([^\7]*)\7') do raw[#raw + 1] = o; end
    return { title = tc, prefix = prefix, opts = opts, bad = bad, no = no, raw = raw };
end
function QRY.zt_parse(d)
    local function u32(o) local a, b, c, e_ = d:byte(o + 1, o + 4); return a + b * 256 + c * 65536 + e_ * 16777216; end
    local h = u32(0);
    local size, flag = bit.band(h, 0x0FFFFFFF), bit.band(h, 0x10000000) ~= 0;
    if size < 8 or #d < 4 + size then return nil, ('odd size %d (%d bytes)'):format(size, #d); end
    local b = d:sub(5, 4 + size);
    if flag then b = QRY.xor80(b); end
    local function bu32(o) local a, b_, c, e_ = b:byte(o + 1, o + 4); return a + b_ * 256 + c * 65536 + e_ * 16777216; end
    local first = bu32(0);
    if first < 4 or first > #b or first % 4 ~= 0 then return nil, 'odd first offset ' .. first; end
    local n = first / 4;
    local offs = {};
    for i = 1, n do offs[i] = bu32((i - 1) * 4); if offs[i] > #b then return nil, 'offset out of the file'; end end
    local menus = { count = {} };
    local at = 1;
    while true do
        local p = b:find('\7\11', at, true);
        if not p then break; end
        local lo, hi = 1, n;                                         -- (which line it's in: the last offset before it)
        while lo < hi do local mid = math.floor((lo + hi + 1) / 2); if offs[mid] < p then lo = mid; else hi = mid - 1; end end
        local o, e = offs[lo], (lo < n) and offs[lo + 1] or #b;
        local m = QRY.zt_menu(b:sub(o + 1, e), lo - 1);
        if m then menus[#menus + 1] = m; menus.count = menus.count or {}; menus.count[lo - 1] = #m.raw; end
        at = e + 1;
    end
    return menus, ('%d lines, %d with answers'):format(n, #menus);
end
function QRY.zonetext(zone)
    local c = QRY.zt[zone];
    if c then return c.menus; end
    c = { menus = {} }; QRY.zt[zone] = c;
    local ok, err = pcall(function()
        local idx = QRY.zone_file(zone);
        local path = nil;
        pcall(function() path = AshitaCore:GetResourceManager():GetFilePath(idx); end);
        if not path or path == '' then error('no file for dat ' .. idx); end
        local f = io.open(path, 'rb');
        if not f then error('could not open ' .. path); end
        local d = f:read('*a'); f:close();
        local menus, what = QRY.zt_parse(d);
        if not menus then error(path .. ': ' .. tostring(what)); end
        c.menus, c.path = menus, path;
        M.note('zonetext' .. zone, ('zone %d text: %s (%s)'):format(zone, path, what));
    end);
    if not ok then M.note('zonetext' .. zone, ('zone %d text: not read (%s)'):format(zone, tostring(err))); end
    return c.menus;
end
-- (an answer's text with the event's numbers in it: 0A n a number, 0C n [a/b] the wording picked by number n, 01 a
--  named thing (an item, key item, zone) from a number; a number we can't know shows as ...)
function QRY.zt_render(t, P)
    local function num(n) if n < 8 then return P[n]; end local v = P[n]; return (v and v ~= 0) and v or nil; end
    local bad = false;
    t = t:gsub('\x0C(.)%[([^%]]*)%]', function(c, alts)
        local v = num(c:byte()) or 0;
        local L = {}; for a in (alts .. '/'):gmatch('([^/]*)/') do L[#L + 1] = a; end
        return L[v + 1] or L[1] or '';
    end);
    t = t:gsub('\x01(.)(.)', function(len, kind)                   -- (the tag's body follows: marked here, read below)
        return '\x01' .. len .. kind;
    end);
    local out, i = {}, 1;
    while i <= #t do
        local c = t:byte(i);
        if c == 0x0A then
            local v = num(t:byte(i + 1) or 0);
            out[#out + 1] = v and DLV.gs(v) or '...';
            i = i + 2;
        elseif c == 0x01 then                                        -- (01 len kind, then (len^80) value bytes^80, a closing byte)
            local len, kind = (t:byte(i + 1) or 0), string.char(t:byte(i + 2) or 0);
            local j = i + 3;
            local sl = bit.bxor(t:byte(j) or 0x80, 0x80);
            local v = 0;
            for k = sl, 1, -1 do v = v * 256 + bit.bxor(t:byte(j + k) or 0x80, 0x80); end
            local id = num(v);
            local name = nil;
            pcall(function()
                local rm = AshitaCore:GetResourceManager();
                if kind == '#' and id then local r = rm:GetItemById(id); name = r and r.Name and r.Name[1]; end
                if kind == '3' and id then name = rm:GetString('keyitems.names', id); end
                if kind == '8' and id then name = rm:GetString('zones.names', id); end
            end);
            if not name or name == '' then bad = true; name = '...'; end
            out[#out + 1] = name;
            i = i + 1 + len + 1;
        elseif c == 0x7F then
            local nx = t:byte(i + 1) or 0;
            if nx == 0x31 then break; end
            local w = ({ [0x34] = 3, [0x35] = 3, [0x36] = 3, [0x80] = 3, [0x84] = 3, [0x86] = 3, [0x8C] = 3, [0x92] = 3, [0x38] = 4 })[nx] or 2;
            i = i + w;
        elseif c == 0xEF then
            local k = (t:byte(i + 1) or 0) - 0x1E;
            if QRY.ELEM[k] then out[#out + 1] = '\1' .. string.char(48 + k) .. QRY.ELEM[k]; end
            i = i + 2;
        elseif c < 0x20 then i = i + 1;
        else out[#out + 1] = string.char(c); i = i + 1; end
    end
    local r = table.concat(out):gsub('  +', ' '):gsub('^%s+', ''):gsub('%s+$', '');
    return r, bad;
end
-- (the event's own script, run up to this question: which answers it hides, and its numbers)
QRY.evs = {};
function QRY.script_for(zone)
    local c = QRY.evs[zone];
    if c ~= nil then return c or nil; end
    QRY.evs[zone] = false;
    local ok, err = pcall(function()
        local idx = (zone < 256) and (5820 + zone) or (84991 + zone - 256);
        local path = AshitaCore:GetResourceManager():GetFilePath(idx);
        if not path or path == '' then error('no file for dat ' .. idx); end
        local f = io.open(path, 'rb'); if not f then error('could not open ' .. path); end
        local d = f:read('*a'); f:close();
        local B, why = EVM.parse(d);
        if not B then error(why); end
        QRY.evs[zone] = B;
        M.note('evscript' .. zone, ('zone %d event scripts: %s (%d blocks)'):format(zone, path, #B));
    end);
    if not ok then M.note('evscript' .. zone, ('zone %d event scripts: not read (%s)'):format(zone, tostring(err))); end
    return QRY.evs[zone] or nil;
end
QRY.evm_cache = {};
function QRY.script_mask(zone, m, menus)
    if cfg.evscript == false then return nil; end
    local ev = QRY.ev;
    if not ev or not ev.uid or not ev.event or os.clock() - ev.t > 900 then return nil; end
    local key = ('%d:%08X:%d:%d:%s'):format(zone, ev.uid, ev.event, m.no, table.concat(ev.p, ','));
    local c = QRY.evm_cache[key];
    if c ~= nil then return c or nil; end
    QRY.evm_cache[key] = false;
    local B = QRY.script_for(zone);
    if not B then return nil; end
    local upd = (QRY.upd_nums and QRY.upd_nums.t >= ev.t) and QRY.upd_nums.p or nil;
    local okr, r, why = pcall(EVM.mask_for, B, ev.uid, ev.event, ev.p, m.no, { update = upd, count = function(no) return menus.count[no] or 0; end });
    if not okr then why = r; r = nil; end
    M.note('evm' .. key, ('event %d of %08X, question line %d: %s'):format(ev.event, ev.uid, m.no, r and ('mask %08X'):format(r.mask) or ('no mask (' .. tostring(why) .. ')')));
    QRY.evm_cache[key] = r or false;
    return r;
end
function QRY.zone_match(gt, shown, mp)
    if cfg.zonetext == false then return nil; end
    local zone = QRY.zone_now();
    if not zone then return nil; end
    local menus = QRY.zonetext(zone);
    -- (first: the event's script says what's hidden - exact, numbers and all)
    for _, m in ipairs(menus) do
        local hit = (m.title ~= nil and m.title == gt) or (m.prefix and gt:sub(1, #m.prefix) == m.prefix);
        if hit then
            local r = QRY.script_mask(zone, m, menus);
            if r then
                local vis, anybad = {}, false;
                for i, raw in ipairs(m.raw) do
                    if bit.band(r.mask, bit.lshift(1, i - 1)) == 0 and raw ~= '' then
                        local txt, bad = QRY.zt_render(raw, r.params);
                        if txt ~= '' and txt ~= '@' then vis[#vis + 1] = txt; if bad then anybad = true; end end
                    end
                end
                if #vis == shown then
                    M.note('zonematch' .. gt .. '#' .. shown, ('question "%s" (%d answers): line %d, its script\'s mask %08X'):format(gt, shown, m.no, r.mask));
                    return { title = gt, opts = vis, shown = shown, mp = mp, zone = zone, line = m.no, vis = vis };
                end
                M.note('zonemask' .. gt .. '#' .. shown, ('question "%s": the script leaves %d answers, the box shows %d'):format(gt, #vis, shown));
            end
        end
    end
    local found, sigs, exact = {}, {}, false;
    for _, m in ipairs(menus) do
        local hit = (m.title ~= nil and m.title == gt);
        if not hit and m.prefix and gt:sub(1, #m.prefix) == m.prefix then hit = true; end
        if hit and not m.bad then
            local mq = { title = gt, opts = {}, shown = shown, mp = mp, zone = zone, line = m.no };
            for i, o in ipairs(m.opts) do mq.opts[i] = o; end
            if #mq.opts == shown or QRY.hide(mq) then
                local sig = table.concat(mq.vis or mq.opts, '\0');
                if not sigs[sig] then sigs[sig] = true; found[#found + 1] = mq; end
            end
        end
    end
    local key = gt .. '#' .. shown;
    if #found == 1 then
        M.note('zonematch' .. key, ('question "%s" (%d answers): line %d of zone %d\'s text'):format(gt, shown, found[1].line, zone));
        return found[1];
    end
    if #found > 1 then M.note('zonematch' .. key, ('question "%s": %d different answer sets in zone %d\'s text: the game\'s box'):format(gt, #found, zone));
    else M.note('zonematch' .. key, ('question "%s" (%d answers): not in zone %d\'s text (%d questions there)'):format(gt, shown, zone, #menus)); end
    return nil;
end
QRY.dumped = {};
function QRY.dump_box(w, mp, gt, shown)
    local key = gt .. '#' .. shown;
    if QRY.dumped[key] or cfg.survey_mem == false then return; end
    QRY.dumped[key] = true;
    pcall(function()
        local function hex(b) return (b:gsub('.', function(c) return ('%02X'):format(c:byte()); end)); end
        local lb = MCR.read(mp, 0x4000);
        local wb = MCR.read(w.addr, 0x400);
        if lb then M.note('qbox' .. key .. 'L', ('query "%s" (%d shown) list %08X: %s'):format(gt, shown, mp, hex(lb))); end
        if wb then M.note('qbox' .. key .. 'W', ('query "%s" window %08X: %s'):format(gt, w.addr, hex(wb))); end
        for _, off in ipairs({ 0x04, 0x08, 0x10, 0x14, 0x18, 0x1C, 0x20, 0x24, 0x28, 0x2C, 0x30, 0x34 }) do   -- (what the window points at)
            local ptr = rd32(w.addr + off);
            if ptr >= FLOOR and ptr ~= mp then
                local pb = MCR.read(ptr, 0x400);
                if pb then M.note('qbox' .. key .. 'P' .. off, ('query "%s" window+%02X -> %08X: %s'):format(gt, off, ptr, hex(pb))); end
            end
        end
    end);
end
function QRY.gtitle(blob)
    if not blob or #blob < 0x40 then return nil; end
    local n = blob:byte(0x37) + blob:byte(0x38) * 256;
    if n < 2 or n > 160 or 0x38 + n * 2 > #blob then return nil; end
    local t = {};
    for i = 0, n - 1 do
        local o = 0x38 + i * 2;
        local v = blob:byte(o + 1) + blob:byte(o + 2) * 256;
        if v > 0x5E then return nil; end
        t[#t + 1] = string.char(v + 0x20);
    end
    local r = table.concat(t):gsub('%s+$', '');
    return (r ~= '') and r or nil;
end
function QRY.marked_at(blob, p, shown, mp)
    local q0 = p - 1;
    while q0 > 0x40 and blob:byte(q0) ~= 0 and blob:byte(q0) ~= 0x7F do q0 = q0 - 1; end
    local function clean(t) return (t:gsub('[\7]', ' '):gsub('[%z\1-\31\127-\255]', ''):gsub('^%s+', ''):gsub('%s+$', '')); end
    local title = clean(blob:sub(q0 + 1, p - 1));
    local e = p + 2;
    while e <= #blob and blob:byte(e) ~= 0 and blob:byte(e) ~= 0x7F do e = e + 1; end
    local opts = {};
    for o in (blob:sub(p + 2, e - 1) .. '\7'):gmatch('([^\7]*)\7') do opts[#opts + 1] = clean(o); end
    return { title = title, opts = opts, shown = shown, mp = mp };
end
-- Answers the game leaves out: "@" lines are unused places (always left out). Then what's known of the NPC: Sweepstox
-- (the Gobbie Mystery Box, event 20056 - its server script passes which dials to hide as the 7th event number, one bit
-- per answer; "Inquire about my daily tally." is the one left out of its first menu). It's used only when what's left
-- is exactly as many answers as the game shows.
function QRY.hide(mq)
    local vis = {};
    for _, o in ipairs(mq.opts) do if o ~= '@' and o ~= '' then vis[#vis + 1] = o; end end
    if #vis == mq.shown then mq.vis = vis; return true; end
    -- (the conquest guards' "What is your business?": the Expeditionary Force lines are left out unless you're in one)
    if mq.title == 'What is your business?' and #vis == 7 and mq.shown == 5 then
        mq.vis = { vis[1], vis[2], vis[5], vis[6], vis[7] }; return true;
    end
    local ev = QRY.ev;
    local box = ev and (ev.event == 20056 or ev.event == 6001) or mq.title:find('Whatcha gonna do', 1, true);   -- (Sweepstox 20056, Priztrix 6001 - the same box)
    if box and ev and os.clock() - ev.t < 600 then
        if mq.title:find('dial', 1, true) then
            vis = {};
            for i, o in ipairs(mq.opts) do
                if o ~= '@' and o ~= '' and bit.band(ev.p[7] or 0, bit.lshift(1, i - 1)) == 0 then vis[#vis + 1] = o; end
            end
        else
            vis = {};
            for _, o in ipairs(mq.opts) do if o ~= '@' and not o:find('daily tally', 1, true) then vis[#vis + 1] = o; end end
        end
        if #vis == mq.shown then mq.vis = vis; return true; end
    end
    return false;
end
function QRY.event(d)                                                -- in 0x032 / 0x034: which event, and (0x034) its 8 numbers
    local function u(o, n) local v = 0; for i = n - 1, 0, -1 do v = v * 256 + (d:byte(o + i + 1) or 0); end return v; end
    local id = d:byte(1);
    local ev = { t = os.clock(), p = {} };
    if id == 0x34 and #d >= 0x30 then
        for i = 0, 7 do ev.p[i + 1] = u(0x08 + i * 4, 4); end
        ev.event = u(0x2C, 2);
        ev.zone = u(0x2A, 2);
        ev.uid = u(0x04, 4);
    elseif id == 0x32 and #d >= 0x10 then
        ev.event = u(0x0C, 2);
        ev.uid = u(0x04, 4);
        ev.zone = u(0x0A, 2);
        for i = 1, 8 do ev.p[i] = 0; end
    end
    QRY.ev = ev;
end
function QRY.pos(q)                                                  -- (the answer picked, 1 = the first; live)
    local h = q.mp and MCR.read(q.mp, 0x34);
    if not h then return nil; end
    return h:byte(0x31) + h:byte(0x32) * 256 + 1;
end
function QRY.parse(w)
    local c = QRY.seen[w.addr];
    if c and os.clock() - c.t < (c.q and 0.5 or 0.15) then return c.q; end   -- (not read yet: soon again - the text can come a moment late)
    local ok, segs, count, raw = pcall(QRY.text, w);
    local q = nil;
    local okm, mq = pcall(QRY.marked, w);
    if okm and mq and mq.shown >= 2 and #mq.opts == mq.shown and mq.title ~= '' then
        q = { title = mq.title, opts = mq.opts, mp = mq.mp, live = true, ids = mq.ids, mainbox = mq.mainbox, wa = w.addr, card = mq.card };
        segs, count = mq.opts, mq.shown;
    elseif okm and mq and QRY.hide(mq) then
        q = { title = mq.title, opts = mq.vis, mp = mq.mp, live = true, mainbox = mq.mainbox, wa = w.addr };
        segs, count = mq.vis, mq.shown;
    elseif okm and mq then
        segs = mq.opts; count = mq.shown;
        if not c then M.note('query_hidden' .. os.clock(), ('query "%s": %d answers in the text, %d shown - one left out by the game: its own box'):format(mq.title, #mq.opts, mq.shown)); end
    elseif ok and segs and count and count >= 3 and #segs >= count then
        local nopt = count - 1;
        if nopt >= 2 and nopt <= 3 and nopt <= w.buttons then
            q = { title = table.concat(segs, ' ', 1, #segs - nopt), opts = {} };
            for i = #segs - nopt + 1, #segs do q.opts[#q.opts + 1] = segs[i]; end
        end
    end
    QRY.first = QRY.first or {};
    if not c then QRY.first[w.addr] = os.clock(); end
    if cfg.qdebug == true and not q and not (QRY.probed or {})[w.addr] and QRY.first[w.addr] and os.clock() - QRY.first[w.addr] > 0.3 and (QRY.probes or 0) < 4 then
        QRY.probed = QRY.probed or {}; QRY.probed[w.addr] = true;   -- (text not found: where it is, to the log - a moment after it opens)
        QRY.probes = (QRY.probes or 0) + 1;
        pcall(QRY.probe, w);
    end
    if not c then
        local hex = raw and (raw:sub(1, 240):gsub('.', function(ch) return ('%02X'):format(ch:byte()); end)) or '-';
        M.note('query' .. w.addr .. os.clock(), ('query: count %s, read %s, lines [%s] %s; text %s'):format(tostring(count), tostring(ok),
            (ok and segs) and table.concat(segs, ' | ') or tostring(segs), q and 'shown' or 'left to the game', hex));
    end
    QRY.seen[w.addr] = { t = os.clock(), q = q };
    return q;
end
function QRY.probe(w, words)                                        -- where the question's text is: readable memory near the box, searched
    local mp = rd32(w.addr + 0x0C);                                  --  for a question mark or a Yes / No line, with the path to each
    local seen, queue, n, out = {}, { { w.addr, 'w' }, { mp, 'L' } }, 0, {};
    local marks = {};
    while #queue > 0 and n < 1500 do
        local qq = table.remove(queue, 1);
        local blob = MCR.read(qq[1], (qq[2] == 'L' or qq[2] == 'w') and 0x4000 or 0x1000);
        n = n + 1;
        if blob and #marks < 12 then                                 -- (any question text - question 07 0B answers - with where it is)
            local at = 1;
            while #marks < 12 do
                local p = blob:find('\7\11', at, true);
                if not p then break; end
                local q0 = math.max(1, p - 48);
                local t_ = blob:sub(q0, math.min(#blob, p + 60)):gsub('[%z\1-\31\127-\255]', '|');
                marks[#marks + 1] = ('%s+%X "%s"'):format(qq[2], p - 1, t_);
                at = p + 2;
            end
        end
        if blob then
            for st, s_ in blob:gmatch('()([%w%p ][%w%p ]+)') do
                local hit = false;
                if words then for _, wd in ipairs(words) do if s_:find(wd, 1, true) then hit = true; break; end end
                else hit = s_:find('?', 1, true) or s_:match('^Yes') or s_:match('^No%.') or s_:match('^No$') or s_:lower():find('residential', 1, true); end
                if #out < 40 and hit then
                    out[#out + 1] = ('%s+%X "%s"'):format(qq[2], st - 1, s_:sub(1, 60));
                end
            end
            local depth = select(2, qq[2]:gsub('>', ''));
            if depth < 4 then
                for off = 0, math.min(#blob, 0x200) - 4, 4 do
                    local p_ = blob:byte(off + 1) + blob:byte(off + 2) * 256 + blob:byte(off + 3) * 65536 + blob:byte(off + 4) * 16777216;
                    if p_ >= 0x01000000 and p_ < 0x7FFF0000 and not seen[p_] then
                        seen[p_] = true; queue[#queue + 1] = { p_, qq[2] .. '>' .. ('%X'):format(off) };
                    end
                end
            end
        end
    end
    local hdr = MCR.read(mp, 0x40);
    local hx = hdr and (hdr:gsub('.', function(ch) return ('%02X'):format(ch:byte()); end)) or '-';
    M.note('qprobe' .. os.clock(), ('query texts (%d places): %s ;; list header %s'):format(n, table.concat(out, ' ; '), hx));
    pcall(function()                                                 -- (the list's text as the game lays it out: each character
        local d_ = MCR.read(mp + 0x40, 0x700);                       --  less 0x20, two bytes each - its raw bytes and a reading)
        if not d_ then return; end
        local hx2 = d_:gsub('.', function(ch) return ('%02X'):format(ch:byte()); end);
        local rd = {};
        for i = 1, #d_ - 1, 2 do
            local v = d_:byte(i) + d_:byte(i + 1) * 256;
            rd[#rd + 1] = (v >= 1 and v <= 0x5E) and string.char(v + 0x20) or ((v == 0) and '_' or ('{' .. v .. '}'));
        end
        M.note('qglyph' .. os.clock(), ('list +40 raw %s ;; read %s'):format(hx2, table.concat(rd)));
    end);
    M.note('qmarks' .. os.clock(), ('question marks (07 0B) found: %s'):format((#marks > 0) and table.concat(marks, ' ; ') or 'none'));
    -- (a deeper look: every pointer anywhere in the box and its list, two steps on, for the question's words or marks)
    pcall(function()
        local function g(t) return (t:gsub('.', function(c) return string.char(c:byte() - 0x20, 0); end)); end
        local words = { '\7\11', 'assist you', 'Whatcha', 'Exchange points', 'Nothing.', 'Yes.', g('Nothing'), g('Check/Exchange'), g('Learn about'), g('Open the box') };
        local hits, seen2, reads = {}, {}, 0;
        local q2 = { { w.addr, 'w', 0x1000 }, { mp, 'L', 0x4000 } };
        local qi = 1;
        while qi <= #q2 and reads < 6000 and #hits < 16 do
            local it = q2[qi]; qi = qi + 1;
            local b_ = MCR.read(it[1], it[3]);
            reads = reads + 1;
            if b_ then
                for _, wd in ipairs(words) do
                    local p = b_:find(wd, 1, true);
                    if p and #hits < 16 then
                        local t_ = b_:sub(math.max(1, p - 40), math.min(#b_, p + 70)):gsub('[%z\1-\31\127-\255]', '|');
                        hits[#hits + 1] = ('%s+%X [%s] "%s"'):format(it[2], p - 1, (wd == '\7\11') and 'mark' or wd:gsub('%z', ''):gsub('.', function(c) local v = c:byte(); return (v < 0x60) and string.char(v + 0x20) or c; end), t_);
                    end
                end
                local depth = select(2, it[2]:gsub('>', ''));
                if depth < 2 then
                    for off = 0, #b_ - 4, 4 do
                        local v = b_:byte(off + 1) + b_:byte(off + 2) * 256 + b_:byte(off + 3) * 65536 + b_:byte(off + 4) * 16777216;
                        if v >= 0x01000000 and v < 0x7FFF0000 and not seen2[v] then
                            seen2[v] = true; q2[#q2 + 1] = { v, it[2] .. '>' .. ('%X'):format(off), 0x1000 };
                        end
                    end
                end
            end
        end
        M.note('qdeep' .. os.clock(), ('deep look (%d places): %s'):format(reads, (#hits > 0) and table.concat(hits, ' ; ') or 'nothing'));
    end);
end
-- the Mog House door ("mogdoor": "Which area do you want to exit to?"). Its text is looked for in its list like a
-- question's (a line ending in "?", then the answers right after it); if it isn't there, the answers the game shows
-- for it are used. The game's cursor is followed, as with any question.
-- "Select an area to exit to." in each city (as the game lists them; from your screenshots). A city not here: the game's box.
QRY.AREAS = {};
for _, z in ipairs({ 243, 244, 245, 246 }) do                        -- (Jeuno: Ru'Lude Gardens, Upper / Lower / Port Jeuno)
    QRY.AREAS[z] = { "Ru'Lude Gardens.", 'Upper Jeuno.', 'Lower Jeuno.', 'Port Jeuno.', 'Mog Garden.' };
end
QRY.DOOR = { 'Stay in your room.', 'Area you entered from.', 'Change floors.', 'Select an area to exit to.' };
function QRY.door(w)
    local c = QRY.seen[w.addr];
    if c and os.clock() - c.t < 0.5 then return c.q; end
    local q = nil;
    pcall(function()
        local mp = rd32(w.addr + 0x0C);
        local blob = (mp >= 0x10000) and MCR.read(mp, 0x1000) or nil;
        if not blob then return; end
        local toks = {};
        for st, s_, en in blob:gmatch('()([\32-\126][\32-\126][\32-\126]+)()') do toks[#toks + 1] = { st, s_, en }; end
        for i, t in ipairs(toks) do
            if t[2]:sub(-1) == '?' then
                local opts = {};
                for k = i + 1, math.min(#toks, i + w.buttons) do
                    if toks[k][1] - toks[k - 1][3] > 3 then break; end
                    opts[#opts + 1] = toks[k][2];
                end
                if #opts >= 2 then q = { title = t[2], opts = opts }; return; end
            end
        end
    end);
    if not q then
        q = { title = 'Which area do you want to exit to?', opts = QRY.DOOR, fallback = true };
        QRY.probed = QRY.probed or {};
        if cfg.qdebug == true and c and not QRY.probed[w.addr] and (QRY.probes or 0) < 4 then   -- (where its text really is, to the log: /cmenu qdebug)
            QRY.probed[w.addr] = true; QRY.probes = (QRY.probes or 0) + 1; pcall(QRY.probe, w);
        end
    end
    q.head = 'MOG HOUSE';
    if not c then M.note('door' .. w.addr .. os.clock(), ('mog house door: %s [%s]'):format(q.fallback and 'text not found, the usual answers' or 'text read', table.concat(q.opts, ' | '))); end
    QRY.seen[w.addr] = { t = os.clock(), q = q };
    return q;
end
function QRY.want()                                                  -- (a question to show: Ashita's windows are shown during its event)
    if cfg.query == false or WARP.ev then return false; end
    local w = M.open[M.focus or 0];
    if w and w.name == 'mogdoor' and cfg.moogle ~= false then return true; end
    if not w or w.name ~= 'query' then return false; end
    local ok, q = pcall(QRY.parse, w);
    return ok and q ~= nil;
end
function QRY.draw(w, q)
    local s = PSCALE();
    local sw, sh = screen();
    local RH = math.floor(28 * s);
    local HEAD = math.floor(58 * s);
    local FOOT = math.floor(26 * s);
    local W = math.floor(340 * s);
    local VIS = math.min(#q.opts, 8);                                -- (a long list: 8 in view, round the picked one)
    local H = math.floor(HEAD + VIS * RH + FOOT + 6 * s);
    local cur = q.live and QRY.pos(q) or w.cursor;
    if q.mainbox and QRY.ev then QRY.ev.mainpick = cur; QRY.ev.mainaddr = q.wa; end   -- (the Mystery Box's main menu: what's picked there)
    q.off = q.off or 0;
    if cur then
        if cur <= q.off then q.off = cur - 1; elseif cur > q.off + VIS then q.off = cur - VIS; end
    end
    q.off = math.max(0, math.min(#q.opts - VIS, q.off));
    local nat = M.to_screen(w.rect);
    local x, y;
    if nat then
        W = math.max(W, math.floor(nat[3] - nat[1] + 24 * s));
        x = math.floor((nat[1] + nat[3]) / 2 - W / 2);
        y = math.floor(nat[4] + 8 * s - H);
    else
        x, y = math.floor((sw - W) / 2), math.floor(sh * 0.62);
    end
    x = math.max(4, math.min(sw - W - 4, x));
    y = math.max(4, math.min(sh - H - 4, y));
    imgui.SetNextWindowPos({ x, y }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ W + 8, H + 8 }, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    UI.pushed = 2;
    local opened = imgui.Begin('##ccm_query', { true }, win_flags());
    UI.began = true;
    if opened then
        local dl = imgui.GetWindowDrawList();
        local hov_win = imgui.IsWindowHovered();
        local mx, my = mouse();
        DL.RF(dl, x, y, x + W, y + H, U4(0.035, 0.030, 0.050, 1), 10 * s);
        panel(dl, x, y, x + W, y + H, 1, s);
        local who = nil;
        pcall(function()
            local ti = (GMT.talk and os.clock() - GMT.talk[2] < 30) and GMT.talk[1] or nil;
            if ti then who = AshitaCore:GetMemoryManager():GetEntity():GetName(ti); end
        end);
        local tk = font(12 * s); caps(dl, x + 16 * s, y + 10 * s, q.head or ((who and who ~= '') and who:upper() or 'CHOOSE'), C.acc, 2.5 * s, 1); unfont(tk);
        tk = font(16 * s);
        local t = q.title;
        while tw(t) > W - 32 * s and #t > 4 do t = t:sub(1, #t - 1); end
        text(dl, x + 16 * s, y + 27 * s, t, C.text, 1);
        unfont(tk);
        local hover = nil;
        tk = font(14.5 * s);
        for r = 1, VIS do
            local i = q.off + r;
            local o = q.opts[i];
            local rx, ry, rw = x + 16 * s, y + HEAD + (r - 1) * RH, W - 32 * s;
            local hv = hov_win and not UI.move and inside(mx, my, rx, ry, rx + rw, ry + RH);
            if hv then hover = i; end
            if i == cur then
                local p1, p2 = col(C.pink, 0.34), U4(C.vio[1], C.vio[2], C.vio[3], 0.0);
                DL.RFM(dl, rx, ry + 1, rx + rw, ry + RH - 1, p1, p2, p2, p1);
                DL.RF(dl, rx, ry + 4, rx + 2.5 * s, ry + RH - 4, col(C.pink, 1), 2);
            elseif hv then DL.RF(dl, rx, ry + 1, rx + rw, ry + RH - 1, U4(1, 1, 1, 0.06), 4 * s); end
            ETEXT(dl, rx + 12 * s + ((i == cur) and 3 * s or 0), ry + (RH - imgui.GetTextLineHeight()) / 2, o, (i == cur) and C.text or { 0.84, 0.82, 0.92, 1 }, 1);
        end
        unfont(tk);
        if #q.opts > VIS then                                        -- (where in the list: a thin bar)
            local tx0, ty0, ty1 = x + W - 8 * s, y + HEAD, y + HEAD + VIS * RH;
            DL.RF(dl, tx0, ty0, tx0 + 2 * s, ty1, U4(1, 1, 1, 0.06), 2);
            local h_ = (ty1 - ty0) * VIS / #q.opts;
            local o_ = (ty1 - ty0 - h_) * q.off / math.max(1, #q.opts - VIS);
            DL.RF(dl, tx0, ty0 + o_, tx0 + 2 * s, ty0 + o_ + h_, mix(C.pink, C.vio, 0.5, 0.9), 2);
        end
        tk = font(12 * s);
        text(dl, x + 16 * s, y + H - 22 * s, 'Up / Down, then Confirm.  Cancel: back.', C.dim, 1);
        unfont(tk);
        if hover and not UI.move and imgui.IsMouseClicked(0) then
            if hover == cur then M.act(w.addr, nil, KEY.ok); elseif not q.live then M.act(w.addr, hover, nil); end
        end
        local sh = hover or cur;                                     -- (a list of items: the card of the one picked / under the mouse)
        if q.ids and cur and q.ids[cur] then QRY.last_item, QRY.item_ev = q.ids[cur], QRY.ev; end
        UI.tip_scale = 1.35;
        if q.ids and sh and q.ids[sh] then item_tooltip(q.ids[sh], mx, my, { x, y + H + 6 * s, y - 6 * s });
        elseif q.card then item_tooltip(q.card, mx, my, { x, y + H + 6 * s, y - 6 * s }); end   -- (its confirm: the item it's for)
        UI.tip_scale = nil;
    end
    imgui.End();
    UI.began = false;
    imgui.PopStyleVar(2);
    UI.pushed = 0;
    return true;
end

-- The Moogle's Delivery Box. Receive: the game's "post1" (8 slots) and "post2" (Take / Drop / Return); Send: "delivery"
-- (8 slots, OK / Cancel) and "stringdl" (the recipient, typed in the game's own field - left showing). What's in each
-- slot comes from the server's delivery box lines (0x04B: slot, item, how many, from / to whom). The panel covers the
-- game's boxes and follows their cursor, so the controller works them as always; a click puts the game's cursor there
-- and presses Confirm, so everything done is the game's own.
DLV = { box = { [1] = {}, [2] = {} } };
function DLV.packet(d)                                               -- in 0x04B
    if #d < 0x14 then return; end
    local function u(o, n) local v = 0; for i = n - 1, 0, -1 do v = v * 256 + (d:byte(o + i + 1) or 0); end return v; end
    local cmd, boxno, slot, res = u(4, 1), u(5, 1), u(6, 1), u(0x0C, 1);
    if boxno ~= 1 and boxno ~= 2 then return; end
    local B = DLV.box[boxno];
    if slot > 7 then return; end
    if (cmd == 0x0A or cmd == 0x0B or cmd == 0x09) and res == 1 then B[slot] = nil; return; end   -- (taken, dropped, returned)
    if #d < 0x58 then return; end
    local stat, item, stack = u(0x10, 4), u(0x30, 2), u(0x38, 4);
    if item == 0 or stat == 0 then                                   -- (0xFFFF is gil)
        if cmd == 0x06 or cmd == 0x01 or cmd == 0x0C then B[slot] = nil; end
        return;
    end
    B[slot] = { id = item, count = (stack > 0 and (stack < 100000 or item == 0xFFFF)) and stack or 1, who = d:sub(0x15, 0x24):gsub('%z.*', ''), stat = stat,
                ext = d:sub(0x3D, 0x3D + 27), t = os.clock() };
end
function DLV.out(d)                                                  -- out 0x04D: opening the box again starts it fresh
    local cmd = d:byte(5) or 0;
    if cmd == 0x0D or cmd == 0x0E then DLV.box = { [1] = {}, [2] = {} }; end
end
function DLV.name(id)
    local nm = '?';
    pcall(function() local r = AshitaCore:GetResourceManager():GetItemById(id); nm = (r and r.Name and r.Name[1]) or '?'; end);
    return nm;
end
-- two gold coins, one behind the other (gil)
function DLV.coins(dl, cx, cy, r, s)
    local function coin(x, y, a)
        DL.CF(dl, x + 1.5 * s, y + 2 * s, r, U4(0, 0, 0, 0.35 * a), 28);               -- (shadow)
        DL.CF(dl, x, y, r, U4(0.62, 0.42, 0.08, a), 28);                             -- (rim)
        DL.CF(dl, x, y, r * 0.84, U4(0.98, 0.78, 0.22, a), 28);                      -- (face)
        DL.C(dl, x, y, r * 0.62, U4(0.80, 0.56, 0.10, 0.9 * a), 24, 1.4 * s);        -- (inner ring)
        DL.CF(dl, x - r * 0.32, y - r * 0.34, r * 0.22, U4(1, 1, 0.85, 0.65 * a), 12); -- (shine)
        local tk = font(math.max(9, r * 0.9));
        text(dl, x - tw('G') / 2, y - imgui.GetTextLineHeight() / 2, 'G', { 0.62, 0.40, 0.06, 1 }, a);
        unfont(tk);
    end
    -- (your coin picture: images\gil_coin.png - two of it; drawn from the size made for it, so it stays sharp small)
    local R = r * 1.05;
    local want = 2 * R;
    local nm = 'gil_coin.png';
    for _, n in ipairs({ 32, 48, 64, 96, 128 }) do if n >= want * 1.15 then nm = ('gil_coin_%d.png'):format(n); break; end end
    local t = tex(nm) or tex('gil_coin.png');
    if t then
        local function pic(x, y, a)
            DL.CF(dl, x + 1.5 * s, y + 2 * s, R * 0.98, U4(0, 0, 0, 0.35 * a), 28);
            image(dl, t, x - R, y - R, x + R, y + R, a);
        end
        pic(cx - r * 0.45, cy - r * 0.30, 0.95);
        pic(cx + r * 0.45, cy + r * 0.30, 1);
        return;
    end
    coin(cx - r * 0.45, cy - r * 0.30, 0.9);
    coin(cx + r * 0.45, cy + r * 0.30, 1);
end
-- a slot's card: the item's own tooltip; for gil, the coins, how much, and from / to whom
function DLV.tip(e, mx, my, x, y, W, H, s, mode)
    if e.id ~= 0xFFFF then item_tooltip(e.id, mx, my, { x, y + H + 6 * s, y - 6 * s }, e.ext); return; end
    local fg = imgui.GetForegroundDrawList();
    local sw, sh = screen();
    local CW, CH = math.floor(240 * s), math.floor(((e.who or '') ~= '') and 78 or 60) * s;
    CH = math.floor(CH);
    local cx, cy = x, y + H + 6 * s;
    if cy + CH > sh - 4 then cy = y - 6 * s - CH; end
    cx = math.max(4, math.min(sw - CW - 4, cx));
    for i = 3, 1, -1 do DL.RF(fg, cx - i * 2, cy - i * 2 + 3, cx + CW + i * 2, cy + CH + i * 2 + 3, U4(0, 0, 0, 0.08), 9 * s + i * 2); end
    DL.RF(fg, cx, cy, cx + CW, cy + CH, U4(0.045, 0.040, 0.065, 0.97), 9 * s);
    DL.R(fg, cx, cy, cx + CW, cy + CH, U4(0.62, 0.40, 1.0, 0.45), 9 * s, 0, 1);
    local p1, p2 = col(C.gold, 0.9), col(C.pink, 0.9);
    DL.RFM(fg, cx + 10 * s, cy, cx + CW - 10 * s, cy + 2, p1, p2, p2, p1);
    DLV.coins(fg, cx + 32 * s, cy + 32 * s, 19 * s, s);
    local tk = font(11 * s); caps(fg, cx + 64 * s, cy + 10 * s, 'GIL', C.acc, 2.2 * s, 1); unfont(tk);
    tk = font(18 * s); text(fg, cx + 64 * s, cy + 24 * s, DLV.gs(e.count or 0) .. ' G', C.gold, 1); unfont(tk);
    if (e.who or '') ~= '' then
        tk = font(12 * s);
        text(fg, cx + 14 * s, cy + CH - 22 * s, ((mode == 'recv') and 'From ' or 'To ') .. e.who, C.muted, 1);
        unfont(tk);
    end
end
-- square cells: the item's icon large, how many in a corner, its name (short) below
function DLV.cell(dl, cx, cy, CS, e, mode, s, hv)
    DL.RF(dl, cx, cy, cx + CS, cy + CS, U4(0.115, 0.105, 0.155, 0.92), 8 * s);
    local t1, t2 = U4(1, 1, 1, 0.05), U4(1, 1, 1, 0);
    DL.RFM(dl, cx + 1, cy + 1, cx + CS - 1, cy + CS * 0.5, t1, t1, t2, t2);
    DL.R(dl, cx, cy, cx + CS, cy + CS, hv and U4(1, 1, 1, 0.30) or U4(0.62, 0.40, 1.0, 0.18), 8 * s, 0, 1);
    if not e then
        local tk = font(18 * s); text(dl, cx + (CS - tw('+')) / 2, cy + CS / 2 - 11 * s, (mode == 'send') and '+' or '', C.dim, 1); unfont(tk);
        return;
    end
    local is = math.floor(CS * 0.48);
    local ix, iy = cx + (CS - is) / 2, cy + 8 * s;
    if e.id == 0xFFFF then DLV.coins(dl, cx + CS / 2, iy + is / 2, is * 0.40, s);
    else
        image(dl, item_icon(e.id), ix, iy, ix + is, iy + is, 1);
    end
    local tk = font(10.5 * s);
    if e.count > 1 then
        local cs = (e.id == 0xFFFF) and tostring(e.count) or ('x' .. e.count);
        text(dl, cx + CS - 5 * s - tw(cs), cy + 4 * s, cs, (e.id == 0xFFFF) and C.gold or C.acc, 1);
    end
    local nm = (e.id == 0xFFFF) and 'Gil' or DLV.name(e.id);
    while tw(nm) > CS - 8 * s and #nm > 3 do nm = nm:sub(1, #nm - 1); end
    text(dl, cx + (CS - tw(nm)) / 2, cy + CS - 30 * s, nm, C.text, 1);
    local wh = (e.who ~= '') and e.who or '';
    if mode == 'send' then wh = (e.stat == 3) and 'sent' or ((e.stat == 5) and 'back' or ((e.stat == 1) and 'ready' or wh)); end
    while tw(wh) > CS - 8 * s and #wh > 3 do wh = wh:sub(1, #wh - 1); end
    text(dl, cx + (CS - tw(wh)) / 2, cy + CS - 16 * s, wh, (mode == 'send' and e.stat == 3) and C.good or C.dim, 1);
    unfont(tk);
end
function DLV.frame(x, y, W, H, s)                                    -- the panel's window, over the game's boxes
    imgui.SetNextWindowPos({ x, y }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ W + 8, H + 8 }, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    UI.pushed = 2;
    local opened = imgui.Begin('##ccm_delivery', { true }, win_flags());
    UI.began = true;
    return opened;
end
function DLV.unframe()
    imgui.End();
    UI.began = false;
    imgui.PopStyleVar(2);
    UI.pushed = 0;
end
function DLV.gil()
    local g = 0;
    pcall(function() g = AshitaCore:GetMemoryManager():GetInventory():GetContainerItem(0, 0).Count or 0; end);
    return g;
end
function DLV.gs(n) return tostring(n):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', ''); end
function DLV.where(cover, W, H)
    local sw, sh = screen();
    local x, y = 40, 60;
    if cover then x, y = math.floor(cover[1]), math.floor(cover[2]); end
    return math.max(4, math.min(sw - W - 4, x)), math.max(4, math.min(sh - H - 4, y));
end
function DLV.union(...)
    local r = nil;
    for _, w in ipairs({ ... }) do
        local q = w and M.to_screen(w.rect);
        if q then r = r and { math.min(r[1], q[1]), math.min(r[2], q[2]), math.max(r[3], q[3]), math.max(r[4], q[4]) } or q; end
    end
    return r;
end
-- Receive: follows the game's cursor (post1's slots, post2's Take / Drop / Return)
function DLV.draw(mode, slots, acts)
    if mode == 'send' then return DLV.send(slots, acts); end
    local s = PSCALE();
    local B = DLV.box[1];
    local P, HEAD, CS, G = math.floor(14 * s), math.floor(34 * s), math.floor(88 * s), math.floor(6 * s);
    local GW = 4 * CS + 3 * G;
    local BH = math.floor(30 * s);
    local W = GW + 2 * P;
    local H = HEAD + 2 * CS + G + 10 * s + BH + 30 * s;
    local cover = DLV.union(slots, acts);
    if cover then W = math.max(W, math.floor(cover[3] - cover[1] + 4)); H = math.max(H, math.floor(cover[4] - cover[2] + 4)); end
    local x, y = DLV.where(cover, W, H);
    if DLV.frame(x, y, W, H, s) then
        local dl = imgui.GetWindowDrawList();
        local hov_win = imgui.IsWindowHovered();
        local mx, my = mouse();
        DL.RF(dl, x, y, x + W, y + H, U4(0.035, 0.030, 0.050, 1), 10 * s);
        panel(dl, x, y, x + W, y + H, 1, s);
        local tk = font(12 * s); caps(dl, x + P, y + 12 * s, 'DELIVERY BOX  -  RECEIVE', C.acc, 2.2 * s, 1);
        local gs = DLV.gs(DLV.gil()) .. ' G'; text(dl, x + W - P - tw(gs), y + 11 * s, gs, C.gold, 1); unfont(tk);
        local cur = (M.focus == slots.addr) and slots.cursor or nil;
        local hover, show = nil, nil;
        local gx = x + (W - GW) / 2;
        for i = 1, 8 do
            local e = B[i - 1];
            local cx, cy = gx + ((i - 1) % 4) * (CS + G), y + HEAD + math.floor((i - 1) / 4) * (CS + G);
            local hv = hov_win and not UI.move and inside(mx, my, cx, cy, cx + CS, cy + CS);
            if hv then hover = i; end
            DLV.cell(dl, cx, cy, CS, e, 'recv', s, hv);
            if i == cur then sel_frame(dl, cx, cy, cx + CS, cy + CS, 8 * s, 1); end
            if e and (hv or (i == cur and not hover)) then show = e; end
        end
        local btns = { { 'Take', 1 }, { 'Drop', 2 }, { 'Return', 3 } };
        local bw = math.floor((GW - 2 * G) / 3);
        local by = y + HEAD + 2 * CS + G + 10 * s;
        local click_btn = nil;
        for k, b in ipairs(btns) do
            local bx = gx + (k - 1) * (bw + G);
            local on = acts and M.focus == acts.addr and acts.cursor == b[2];
            local hv = hov_win and not UI.move and inside(mx, my, bx, by, bx + bw, by + BH);
            local c_ = (k == 1) and C.pink or C.vio;
            DL.RF(dl, bx, by, bx + bw, by + BH, col(c_, (on or hv) and 0.45 or 0.18), BH / 2);
            DL.R(dl, bx, by, bx + bw, by + BH, col(c_, 0.8), BH / 2, 0, 1);
            if on then sel_frame(dl, bx, by, bx + bw, by + BH, BH / 2, 1); end
            local t1 = font(13 * s); text(dl, bx + (bw - tw(b[1])) / 2, by + (BH - imgui.GetTextLineHeight()) / 2, b[1], C.text, 1); unfont(t1);
            if hv and imgui.IsMouseClicked(0) then click_btn = b; end
        end
        local boxgil = 0;                                            -- (the gil waiting in the box, all slots added up)
        for i = 0, 7 do local e = B[i]; if e and e.id == 0xFFFF then boxgil = boxgil + (e.count or 0); end end
        tk = font(11.5 * s);
        if boxgil > 0 then
            local bgs = 'In box: ' .. DLV.gs(boxgil) .. ' G';
            local t2 = font(13 * s);
            local bx_ = x + W - P - tw(bgs);
            DLV.coins(dl, bx_ - 18 * s, y + H - 15 * s, 9 * s, s);
            text(dl, bx_, y + H - 23 * s, bgs, C.gold, 1);
            unfont(t2);
            text(dl, x + P, y + H - 22 * s, 'Slot, then Take / Drop / Return.', C.dim, 1);
        else
            text(dl, x + P, y + H - 22 * s, 'Pick a slot, then Take, Drop or Return.  Cancel: back.', C.dim, 1);
        end
        unfont(tk);
        if show then DLV.tip(show, mx, my, x, y, W, H, s, 'recv'); end
        if hov_win and not UI.move then
            if click_btn and acts then M.act(acts.addr, click_btn[2], KEY.ok);
            elseif hover and imgui.IsMouseClicked(0) then M.act(slots.addr, hover, KEY.ok); end
            if imgui.IsMouseClicked(1) then M.act(nil, nil, KEY.cancel); end
        end
    end
    DLV.unframe();
    return true;
end
-- Send: ChadcoreMenu's own (the game's boxes are covered and left alone). The recipient is typed in the panel; an item
-- or gil goes into a slot with the server's own "put this in the outgoing box" request (0x04D Set: slot, inventory
-- slot - 0 for gil - how many, and to whom), Send sends what's ready (0x04D Send), Square / X on a sent one takes it
-- back (Cancel). These are the requests the game makes itself; the server checks each and its answer (0x04B) fills the
-- slots - the game's own boxes take the same answers.
function DLV.pk(cmd, slot, inv, count, name)
    local p = { 0, 0, 0, 0, cmd, (cmd == 0x0C) and 0xFF or 2, (slot == nil) and 0xFF or slot, (inv == nil) and 0xFF or inv };
    local c = (count == nil) and 0xFFFFFFFF or count;
    for i = 0, 3 do p[#p + 1] = math.floor(c / 256 ^ i) % 256; end
    for _ = 1, 4 do p[#p + 1] = 0; end
    name = name or '';
    for i = 1, 16 do p[#p + 1] = (i <= 15) and (name:byte(i) or 0) or 0; end
    local ok = pcall(function() AshitaCore:GetPacketManager():AddOutgoingPacket(0x4D, p); end);
    M.note('dlv' .. os.clock(), ('delivery request %X slot %s inv %s count %s to "%s": %s'):format(cmd, tostring(slot), tostring(inv), tostring(count), name, ok and 'sent' or 'failed'));
    return ok;
end
function DLV.first_free()
    for i = 0, 7 do if not DLV.box[2][i] and not (UI.dlv.wait or {})[i] then return i; end end
    return nil;
end
function DLV.put(inv, count, id)                                     -- an item / gil into the next free slot, for the recipient
    local st = UI.dlv;
    local to = (st.to[1] or ''):gsub('%s', '');
    if to == '' then st.msg = 'Type who it\'s for first.'; return; end
    local slot = (st.slot ~= nil and not DLV.box[2][st.slot]) and st.slot or DLV.first_free();
    if not slot then st.msg = 'All 8 slots are in use.'; return; end
    if DLV.pk(0x02, slot, inv, count, to) then
        st.wait = st.wait or {}; st.wait[slot] = { id = id, count = count, t = os.clock() };
        st.msg = nil;
    end
end
function DLV.send_ready()
    local n = 0;
    for i = 0, 7 do local e = DLV.box[2][i]; if e and e.stat == 1 then DLV.pk(0x03, i, nil, nil, nil); n = n + 1; end end
    UI.dlv.msg = (n == 0) and 'Nothing ready to send.' or nil;
end
function DLV.items()
    local out = {};
    for _, e in ipairs(trade_inv()) do
        local fl = 0;
        pcall(function() local r = AshitaCore:GetResourceManager():GetItemById(e.id); fl = tonumber(r and r.Flags) or 0; end);
        e.ex = bit.band(fl, 0x4000) ~= 0;
        out[#out + 1] = e;
    end
    return out;
end
function DLV.pad(acts)                                               -- the controller in the Send panel
    local st = UI.dlv;
    for _, act in ipairs(acts) do
        if st.amt then
            local A = st.amt;
            local big = (A.gil and 10000) or 10;
            if act == 'up' then A.n = math.min(A.max, A.n + 1); A.typed = false;
            elseif act == 'down' then A.n = math.max(1, A.n - 1); A.typed = false;
            elseif act == 'right' then A.n = math.min(A.max, A.n + big); A.typed = false;
            elseif act == 'left' then A.n = math.max(1, A.n - big); A.typed = false;
            elseif act == 'tabr' then A.n = A.max;
            elseif act == 'tabl' then A.n = 1;
            elseif act == 'ok' then DLV.put(A.inv, A.n, A.id); st.amt, st.pick = nil, nil;
            elseif act == 'back' then st.amt = nil; end
        elseif st.pick then
            local L = DLV.items();
            local n = math.max(1, #L);
            if act == 'up' then st.pick = (st.pick > 1) and (st.pick - 1) or n;
            elseif act == 'down' then st.pick = (st.pick < n) and (st.pick + 1) or 1;
            elseif act == 'left' or act == 'tabl' then st.pick = math.max(1, st.pick - 8);
            elseif act == 'right' or act == 'tabr' then st.pick = math.min(n, st.pick + 8);
            elseif act == 'ok' then DLV.choose(L[st.pick]);
            elseif act == 'back' then st.pick = nil; end
        else
            -- 0: the recipient; 1-8: slots; 9 Gil, 10 Send, 11 Close
            local c = st.cur or 0;
            if act == 'left' then if c >= 1 and c <= 8 then c = (c - 1) % 4 == 0 and c or c - 1; elseif c > 9 then c = c - 1; end
            elseif act == 'right' then if c >= 1 and c <= 8 then c = (c % 4 == 0) and c or c + 1; elseif c >= 9 and c < 11 then c = c + 1; end
            elseif act == 'up' then if c >= 5 and c <= 8 then c = c - 4; elseif c >= 1 and c <= 4 then c = 0; elseif c >= 9 then c = 5; elseif c == 0 then c = 9; end
            elseif act == 'down' then if c == 0 then c = 1; elseif c >= 1 and c <= 4 then c = c + 4; elseif c >= 5 and c <= 8 then c = 9; else c = 0; end
            elseif act == 'ok' then st.cur = c; DLV.activate(c); c = st.cur;
            elseif act == 'sort' then local e = (c >= 1 and c <= 8) and DLV.box[2][c - 1]; if e and e.stat == 3 then DLV.pk(0x04, c - 1, nil, nil, nil); end
            elseif act == 'back' then M.act(nil, nil, KEY.cancel); end
            st.cur = c;
        end
    end
end
function DLV.choose(e)
    if not e then return; end
    local st = UI.dlv;
    if (st.to[1] or ''):gsub('%s', '') == '' then st.msg = 'Type who it\'s for first.'; st.pick = nil; return; end
    if e.count > 1 then st.amt = { inv = e.idx, id = e.id, n = e.count, max = e.count, typed = false };
    else DLV.put(e.idx, 1, e.id); st.pick = nil; end
end
function DLV.activate(c)
    local st = UI.dlv;
    if c == 0 then st.typing = true; st.focus_to = true;
    elseif c >= 1 and c <= 8 then
        local e = DLV.box[2][c - 1];
        if not e and not (st.wait or {})[c - 1] then
            if (st.to[1] or ''):gsub('%s', '') == '' then st.msg = 'Type who it\'s for first.'; st.cur = 0; return; end
            st.slot = c - 1; st.pick = 1;
        elseif e and e.stat == 1 then DLV.pk(0x03, c - 1, nil, nil, nil); end
    elseif c == 9 then
        if (st.to[1] or ''):gsub('%s', '') == '' then st.msg = 'Type who it\'s for first.'; return; end
        local g = DLV.gil();
        if g > 0 then st.slot = nil; st.amt = { inv = 0, id = 0xFFFF, n = math.min(g, 1000), max = g, typed = false, gil = true }; end
    elseif c == 10 then DLV.send_ready();
    elseif c == 11 then M.act(nil, nil, KEY.cancel); end
end
function DLV.send(dv, sd)
    local s = PSCALE();
    DLV.to = DLV.to or { '' };
    UI.dlv = UI.dlv or { cur = 1 };
    local st = UI.dlv;
    st.to = DLV.to;                                                  -- (the name stays for the next time)
    if st.addr ~= dv.addr then st.addr, st.pick, st.amt, st.wait, st.msg, st.cur = dv.addr, nil, nil, {}, nil, 0; end
    for k, v in pairs(st.wait or {}) do if DLV.box[2][k] or os.clock() - v.t > 4 then st.wait[k] = nil; end end
    local B = DLV.box[2];
    local P, HEAD, CS, G = math.floor(14 * s), math.floor(34 * s), math.floor(88 * s), math.floor(6 * s);
    local GW = 4 * CS + 3 * G;
    local TO = math.floor(32 * s);
    local BH = math.floor(30 * s);
    local W = GW + 2 * P;
    local H = HEAD + TO + 10 * s + 2 * CS + G + 10 * s + BH + 32 * s;
    local cover = DLV.union(dv, sd, M.find('money'));
    if cover then W = math.max(W, math.floor(cover[3] - cover[1] + 4)); H = math.max(H, math.floor(cover[4] - cover[2] + 4)); end
    local x, y = DLV.where(cover, W, H);
    local opened = DLV.frame(x, y, W, H, s);
    if opened then
        local dl = imgui.GetWindowDrawList();
        local hov_win = imgui.IsWindowHovered();
        local mx, my = mouse();
        DL.RF(dl, x, y, x + W, y + H, U4(0.035, 0.030, 0.050, 1), 10 * s);
        panel(dl, x, y, x + W, y + H, 1, s);
        local tk = font(12 * s); caps(dl, x + P, y + 12 * s, 'DELIVERY BOX  -  SEND', C.acc, 2.2 * s, 1);
        local gil = DLV.gil();
        local gs = DLV.gs(gil) .. ' G'; text(dl, x + W - P - tw(gs), y + 11 * s, gs, C.gold, 1); unfont(tk);
        local gx = x + (W - GW) / 2;
        local click = nil;
        -- the recipient
        local ty = y + HEAD;
        tk = font(12.5 * s); text(dl, gx, ty + (TO - imgui.GetTextLineHeight()) / 2, 'To', C.muted, 1); unfont(tk);
        local fx0, fx1 = gx + 34 * s, gx + GW;
        local fon = (st.cur == 0 and not st.pick and not st.amt) or st.typing;
        DL.RF(dl, fx0, ty + 2, fx1, ty + TO - 2, U4(0.09, 0.08, 0.13, 1), 6 * s);
        DL.R(dl, fx0, ty + 2, fx1, ty + TO - 2, fon and col(C.pink, 0.9) or U4(0.62, 0.40, 1.0, 0.35), 6 * s, 0, 1);
        tk = font(14 * s);
        local typed = false;
        local okin = false;
        if imgui.InputText and imgui.SetCursorScreenPos and imgui.PushItemWidth then
            pcall(imgui.SetCursorScreenPos, { fx0 + 8 * s, ty + (TO - imgui.GetTextLineHeight()) / 2 - 3 * s });
            local pw = pcall(imgui.PushItemWidth, fx1 - fx0 - 16 * s);
            local pc = ImGuiCol_FrameBg and imgui.PushStyleColor and pcall(imgui.PushStyleColor, ImGuiCol_FrameBg, { 0, 0, 0, 0 });
            okin = pcall(function()
                if st.focus_to then st.focus_to = nil; if imgui.SetKeyboardFocusHere then imgui.SetKeyboardFocusHere(0); end end
                local done = imgui.InputText('##ccm_dlv_to', st.to, 16, ImGuiInputTextFlags_EnterReturnsTrue or 0);
                if done and ImGuiInputTextFlags_EnterReturnsTrue then st.cur = 1; end
                typed = imgui.IsItemActive and imgui.IsItemActive() or false;
            end);
            if pc then pcall(imgui.PopStyleColor, 1); end
            if pw then pcall(imgui.PopItemWidth); end
        end
        if not okin then                                             -- (no text box here: /cmenu to <name>)
            local nm = (st.to[1] ~= '') and st.to[1] or 'type: /cmenu to <name>';
            text(dl, fx0 + 8 * s, ty + (TO - imgui.GetTextLineHeight()) / 2, nm, (st.to[1] ~= '') and C.text or C.dim, 1);
        end
        unfont(tk);
        st.typing = typed or false;
        if fon and not typed then sel_frame(dl, fx0, ty + 2, fx1, ty + TO - 2, 6 * s, 1); end
        -- the slots
        local hover, show = nil, nil;
        local sy = ty + TO + 10 * s;
        for i = 1, 8 do
            local e = B[i - 1] or ((st.wait or {})[i - 1] and { id = st.wait[i - 1].id, count = st.wait[i - 1].count, who = '...', stat = 0 });
            local cx, cy = gx + ((i - 1) % 4) * (CS + G), sy + math.floor((i - 1) / 4) * (CS + G);
            local hv = hov_win and not UI.move and inside(mx, my, cx, cy, cx + CS, cy + CS);
            if hv then hover = i; end
            DLV.cell(dl, cx, cy, CS, e, 'send', s, hv);
            if st.cur == i and not st.pick and not st.amt then sel_frame(dl, cx, cy, cx + CS, cy + CS, 8 * s, 1); end
            if e and (hv or (st.cur == i and not hover)) then show = e; end
        end
        -- Gil / Send / Close
        local btns = { { 'Gil', 9 }, { 'Send', 10 }, { 'Close', 11 } };
        local bw = math.floor((GW - 2 * G) / 3);
        local by = sy + 2 * CS + G + 10 * s;
        for k, b in ipairs(btns) do
            local bx = gx + (k - 1) * (bw + G);
            local on = st.cur == b[2] and not st.pick and not st.amt;
            local hv = hov_win and not UI.move and inside(mx, my, bx, by, bx + bw, by + BH);
            local c_ = (k == 2) and C.pink or ((k == 1) and C.gold or C.vio);
            DL.RF(dl, bx, by, bx + bw, by + BH, col(c_, (on or hv) and 0.45 or 0.18), BH / 2);
            DL.R(dl, bx, by, bx + bw, by + BH, col(c_, 0.8), BH / 2, 0, 1);
            if on then sel_frame(dl, bx, by, bx + bw, by + BH, BH / 2, 1); end
            local t1 = font(13 * s);
            local lx = bx + (bw - tw(b[1])) / 2;
            if b[2] == 9 then lx = lx + 12 * s; DLV.coins(dl, lx - 17 * s, by + BH / 2, 9 * s, s); end
            text(dl, lx, by + (BH - imgui.GetTextLineHeight()) / 2, b[1], C.text, 1); unfont(t1);
            if hv and imgui.IsMouseClicked(0) then click = b[2]; end
        end
        tk = font(11.5 * s);
        local foot = st.msg or (st.typing and 'Type the name, then Enter.' or 'Confirm: add / send.  Square / X on a sent one: take it back.  Cancel: close.');
        text(dl, x + P, y + H - 22 * s, foot, st.msg and C.pink or C.dim, 1);
        unfont(tk);
        if show then DLV.tip(show, mx, my, x, y, W, H, s, 'send'); end
        if hov_win and not UI.move and not st.pick and not st.amt then
            if click then st.cur = click; DLV.activate(click);
            elseif hover and imgui.IsMouseClicked(0) then st.cur = hover; DLV.activate(hover);
            elseif hover and imgui.IsMouseClicked(1) then local e = B[hover - 1]; if e and e.stat == 3 then DLV.pk(0x04, hover - 1, nil, nil, nil); end
            elseif imgui.IsMouseClicked(0) and inside(mx, my, fx0, ty, fx1, ty + TO) then st.cur = 0; end
        end
    end
    DLV.unframe();
    if opened and (st.pick or st.amt) then DLV.picker(x + W + 8 * s, y, s); end
    return true;
end
function DLV.picker(x, y, s)                                         -- your Inventory to pick from, then how many
    local st = UI.dlv;
    local sw, sh = screen();
    local L = DLV.items();
    local RH, P, HEAD = math.floor(26 * s), math.floor(12 * s), math.floor(34 * s);
    local page = 12;
    local W = math.floor(300 * s);
    local H = HEAD + page * RH + 30 * s + (st.amt and 60 * s or 0);
    if x + W > sw - 4 then x = math.max(4, x - W - 8 * s - (W + 8 * s)); end
    imgui.SetNextWindowPos({ x, y }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ W + 8, H + 8 }, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    UI.pushed = 2;
    local opened = imgui.Begin('##ccm_dlvpick', { true }, win_flags());
    UI.began = true;
    if opened then
        local dl = imgui.GetWindowDrawList();
        local hov_win = imgui.IsWindowHovered();
        local mx, my = mouse();
        DL.RF(dl, x, y, x + W, y + H, U4(0.035, 0.030, 0.050, 1), 10 * s);
        panel(dl, x, y, x + W, y + H, 1, s);
        local tk = font(12 * s); caps(dl, x + P, y + 12 * s, st.amt and (st.amt.gil and 'SEND GIL' or 'HOW MANY') or 'PICK AN ITEM', C.acc, 2.2 * s, 1); unfont(tk);
        local cur = math.max(1, math.min(#L, st.pick or 1));
        if st.pick then st.pick = cur; end
        st.poff = st.poff or 0;
        if cur <= st.poff then st.poff = cur - 1; elseif cur > st.poff + page then st.poff = cur - page; end
        st.poff = math.max(0, math.min(math.max(0, #L - page), st.poff));
        local hover = nil;
        tk = font(13.5 * s);
        for r = 1, math.min(page, #L - st.poff) do
            local i = st.poff + r;
            local e = L[i];
            local ry = y + HEAD + (r - 1) * RH;
            local hv = hov_win and not UI.move and not st.amt and inside(mx, my, x + 6 * s, ry, x + W - 6 * s, ry + RH);
            if hv then hover = i; end
            if i == cur and not st.amt then
                local p1, p2 = col(C.pink, 0.34), U4(C.vio[1], C.vio[2], C.vio[3], 0.0);
                DL.RFM(dl, x + 6 * s, ry + 1, x + W - 6 * s, ry + RH - 1, p1, p2, p2, p1);
            elseif hv then DL.RF(dl, x + 6 * s, ry + 1, x + W - 6 * s, ry + RH - 1, U4(1, 1, 1, 0.06), 4 * s); end
            local is = RH - 6 * s;
            image(dl, item_icon(e.id), x + P, ry + 3 * s, x + P + is, ry + 3 * s + is, e.ex and 0.5 or 1);
            local nm = e.name;
            while tw(nm) > W - 2 * P - is - 60 * s and #nm > 3 do nm = nm:sub(1, #nm - 1); end
            text(dl, x + P + is + 8 * s, ry + (RH - imgui.GetTextLineHeight()) / 2, nm, e.ex and C.dim or C.text, 1);
            local rt = e.ex and 'Ex' or ((e.count > 1) and ('x' .. e.count) or '');
            local t2 = font(11.5 * s); text(dl, x + W - P - tw(rt), ry + (RH - imgui.GetTextLineHeight()) / 2, rt, C.acc, 1); unfont(t2);
        end
        unfont(tk);
        if st.amt then
            local A = st.amt;
            local ay = y + HEAD + page * RH + 6 * s;
            DL.RF(dl, x + P, ay, x + W - P, ay + 48 * s, U4(0.09, 0.08, 0.13, 1), 6 * s);
            tk = font(20 * s);
            local ns = A.gil and (DLV.gs(A.n) .. ' G') or (tostring(A.n) .. ' / ' .. A.max);
            local nx = x + (W - tw(ns)) / 2 + (A.gil and 18 * s or 0);
            if A.gil then DLV.coins(dl, nx - 24 * s, ay + 24 * s, 14 * s, s); end
            text(dl, nx, ay + 12 * s, ns, A.gil and C.gold or C.text, 1);
            unfont(tk);
        end
        tk = font(11 * s);
        text(dl, x + P, y + H - 20 * s, st.amt and 'Up / Down, Left / Right: more or less.  Type a number.  Confirm.' or 'Confirm: pick.  Cancel: back.', C.dim, 1);
        unfont(tk);
        if hov_win and not UI.move then
            if hover and imgui.IsMouseClicked(0) then st.pick = hover; DLV.choose(L[hover]);
            elseif st.amt and imgui.IsMouseClicked(0) then DLV.put(st.amt.inv, st.amt.n, st.amt.id); st.amt, st.pick = nil, nil; end
            if imgui.IsMouseClicked(1) then if st.amt then st.amt = nil; else st.pick = nil; end end
            local wh = imgui.GetIO().MouseWheel or 0;
            if wh ~= 0 then
                if st.amt then st.amt.n = math.max(1, math.min(st.amt.max, st.amt.n + ((wh > 0) and 1 or -1) * (st.amt.gil and 1000 or 1)));
                elseif st.pick then st.pick = math.max(1, math.min(#L, st.pick + ((wh > 0) and -1 or 1))); end
            end
        end
    end
    imgui.End();
    UI.began = false;
    imgui.PopStyleVar(2);
    UI.pushed = 0;
end

-- An NPC's shop. "shopmain": Buy / Sell; "shop": what they sell (the server's list, 0x03C: price, item, its place in
-- the shop - 19 a packet). The panel shows the game's list as it scrolls (its first row and count are in the list's
-- numbers) and follows its cursor; buying - how many, paying - is the game's own.
SHP = { items = {}, t = -10 };
function SHP.packet(d)
    local function u(o, n) local v = 0; for i = n - 1, 0, -1 do v = v * 256 + (d:byte(o + i + 1) or 0); end return v; end
    if #d < 8 then return; end
    if u(4, 2) == 0 then SHP.items = {}; end
    local n = math.floor((#d - 8) / 12);
    for i = 0, n - 1 do
        local o = 8 + i * 12;
        local price, item, idx = u(o, 4), u(o + 4, 2), u(o + 6, 1);
        if item ~= 0 then SHP.items[idx + 1] = { id = item, price = price, shopidx = idx, skill = u(o + 8, 2), info = u(o + 10, 2) }; end
    end
    SHP.t = os.clock();
end
-- (Buy only - Sell opens the same list window with your items, in the game's own order: that one's the game's. It's the
--  shop's list when Buy was picked on the shop's Buy / Sell, and the game's list holds as many as the server sent)
function SHP.mode_of(w)
    if SHP.mode_addr ~= w.addr then SHP.mode_addr, SHP.mode = w.addr, SHP.last_main; end
    return SHP.mode;
end
function SHP.buy_ok(w)
    local smw = M.find('shopmain') or M.find('guildsho');
    if not smw then return false; end
    if SHP.mode_addr ~= w.addr then SHP.mode_addr, SHP.mode = w.addr, SHP.last_main; end
    if SHP.mode ~= 1 then return false; end
    local lf = list_fields(w);
    local n = #SHP.list();
    return n > 0 and lf ~= nil and lf[6] == n;
end
-- Sell: the same list window with your Inventory, in its own order (slot by slot); used when that comes to exactly as
-- many as the game lists. What the shop pays comes when the game asks (0x03D: price, slot), and is shown from then.
SHP.prices = {};
function SHP.inv()
    local all, unworn, c3, c4, c5 = {}, {}, {}, {}, {};
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        local res = AshitaCore:GetResourceManager();
        for i = 1, 80 do
            local it = inv:GetContainerItem(0, i);
            if it and (it.Id or 0) ~= 0 and it.Id ~= 65535 then
                local r = res:GetItemById(it.Id);
                local fl = tonumber(r and r.Flags) or 0;
                local e = { id = it.Id, idx = i, count = it.Count or 1, nosale = bit.band(fl, 0x1000) ~= 0 or bit.band(fl, 0x4000) ~= 0,
                            worn = (it.Flags or 0) == 5, type = tonumber(r and r.Type) or 0, slots = tonumber(r and r.Slots) or 0 };
                all[#all + 1] = e;
                if not e.worn then unworn[#unworn + 1] = e; end
                local ns, ex, rare = bit.band(fl, 0x1000) ~= 0, bit.band(fl, 0x4000) ~= 0, bit.band(fl, 0x8000) ~= 0;
                if not e.worn and not ns then c3[#c3 + 1] = e; end
                if not e.worn and not ns and not ex then c4[#c4 + 1] = e; end
                if not e.worn and not ns and not ex and not rare then c5[#c5 + 1] = e; end
            end
        end
    end);
    return all, unworn, c3, c4, c5;
end
-- The game's Sell order (worked out from your full list and your inventory): first the usable items and crystals
-- (item numbers 4096-8191) by number; then gear (weapons, armor) by the slot it goes in - body, back, hands, legs,
-- then the rest - and within a slot the higher number first; then everything else by number. The same item twice:
-- the lower inventory slot first. (A pick that doesn't match is still stopped before anything sells.)
SHP.SLOT_ORDER = { [32] = 1, [32768] = 2, [64] = 3, [128] = 4 };
function SHP.sort(L)
    local function grp(e)
        if e.id >= 4096 and e.id <= 8191 and e.type ~= 4 and e.type ~= 5 then return 1; end
        if e.type == 4 or e.type == 5 then return 2; end
        return 3;
    end
    local function slotkey(e)
        local s_ = e.slots or 0;
        if SHP.SLOT_ORDER[s_] then return SHP.SLOT_ORDER[s_]; end
        local b = 0; while s_ > 1 do s_ = math.floor(s_ / 2); b = b + 1; end
        return 10 + b;
    end
    local out = {};
    for i, e in ipairs(L) do out[i] = e; end
    table.sort(out, function(a, b)
        local ga, gb = grp(a), grp(b);
        if ga ~= gb then return ga < gb; end
        if ga == 2 then
            local sa, sb = slotkey(a), slotkey(b);
            if sa ~= sb then return sa < sb; end
            if a.id ~= b.id then return a.id > b.id; end
        elseif a.id ~= b.id then return a.id < b.id; end
        return a.idx < b.idx;
    end);
    return out;
end
-- (some shops list your items just as they sit in your Inventory, slot by slot, others in the sorted order above. Which
--  one a shop uses is learned from the game's own price request as you move its cursor - the first time the row it asks
--  about is the other order's, the panel switches to that order for this NPC and remembers it)
function SHP.who()
    local who = '';
    pcall(function() local ti = GMT.talk and GMT.talk[1]; if ti then who = AshitaCore:GetMemoryManager():GetEntity():GetName(ti) or ''; end end);
    return who;
end
function SHP.order_now()
    cfg.sellorder = cfg.sellorder or {};
    local w = SHP.who();
    return cfg.sellorder[w] or cfg.sellorder_default or 'sort';
end
function SHP.sell_list(w)
    local lf = list_fields(w);
    if not lf then return nil; end
    -- (the game lists only what it'd let you sell: the first of these that comes to its count is taken)
    local all, unworn, c3, c4, c5 = SHP.inv();
    for k, L in ipairs({ all, unworn, c3, c4, c5 }) do
        if #L == lf[6] then
            if SHP.sell_kind ~= k then SHP.sell_kind = k; M.note('shopsell', ('sell list: game %d = way %d'):format(lf[6], k)); end
            SHP.sell_raw = L;
            return (SHP.order_now() == 'slot') and L or SHP.sort(L);
        end
    end
    if not SHP.sell_noted then SHP.sell_noted = true; M.note('shopsell', ('sell list: game %d, inventory %d / %d / %d / %d / %d: left to the game'):format(lf[6], #all, #unworn, #c3, #c4, #c5)); end
    return nil;
end
-- (what the shop pays for the item the cursor rests on: the same price request the game makes when you pick it, only
--  while the list itself has the focus - the game makes its own again when you pick, and that one is what a sale uses)
function SHP.ask(e)
    local now = os.clock();
    if e.nosale or e.worn or SHP.prices[e.id] then SHP.ask_at = nil; return; end
    if SHP.ask_idx ~= e.idx then SHP.ask_idx, SHP.ask_at = e.idx, now + 0.35; return; end
    if not SHP.ask_at or now < SHP.ask_at then return; end
    SHP.ask_at = nil;
    local c = e.count or 1;
    pcall(function()
        AshitaCore:GetPacketManager():AddOutgoingPacket(0x84, { 0, 0, 0, 0, c % 256, math.floor(c / 256) % 256, 0, 0,
            e.id % 256, math.floor(e.id / 256), e.idx, 0 });
    end);
end
-- (the game asks the price of the item you picked (0x084: count, item, slot): if the panel was up and that isn't the
--  row it had highlighted, the request is stopped - and so is the sale that would follow (0x085 sells what was last
--  priced) - and the panel isn't used for selling again this session)
-- (buying / a guild: the game's own request carries the amount picked on the panel - for that item only, and never
--  more than you can: a shop buy 0x083 (amount, shop's list place), a guild buy 0x0AA / guild sell 0x0AC (item,
--  inventory place, amount))
function SHP.amount_out(e)
    local wn = SHP.want_n;
    if not wn or os.clock() - wn.t > 120 then return; end
    local d = e.data_modified or e.data;
    local function u(o, n) local v = 0; for i = n - 1, 0, -1 do v = v * 256 + (d:byte(o + i + 1) or 0); end return v; end
    local n = wn.n;
    if e.id == 0x083 and wn.kind == 'buy' then
        local si = u(0x0A, 2);
        local it = SHP.items[si + 1];
        if not it or it.id ~= wn.id then return; end
        if it.price > 0 then n = math.min(n, math.floor(DLV.gil() / it.price)); end
        if n < 1 then return; end
        e.data_modified = d:sub(1, 4) .. string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, 0) .. d:sub(9);
    elseif (e.id == 0x0AA and wn.kind == 'gbuy') or (e.id == 0x0AC and wn.kind == 'gsell') then
        if u(4, 2) ~= wn.id then return; end
        if e.id == 0x0AC then
            local slot = u(6, 1);
            pcall(function() local it = AshitaCore:GetMemoryManager():GetInventory():GetContainerItem(0, slot); n = math.min(n, (it and it.Id == wn.id) and (it.Count or 0) or 0); end);
        end
        n = math.min(n, 255);
        if n < 1 then return; end
        e.data_modified = d:sub(1, 7) .. string.char(n) .. d:sub(9);
    else
        return;
    end
    M.note('shopamt' .. os.clock(), ('%s: amount set to %d for item %d'):format(wn.kind, n, wn.id));
    SHP.want_n = nil;
end
function SHP.check_out(e)
    local d = e.data_modified or e.data;
    if e.id == 0x085 then
        if SHP.block85 then e.blocked = true; msg('That sale was stopped (the Sell list was out of step with the game\'s - it is fixed now; pick the item again). Nothing was sold.'); end
        SHP.want_n = nil;                                            -- (sold: the amount is used up)
        return;
    end
    local slot = d:byte(0x0B) or 0;
    local item = (d:byte(0x09) or 0) + (d:byte(0x0A) or 0) * 256;
    local wn = SHP.want_n;                                           -- (the amount picked on the panel, for that item in that slot)
    if wn and (wn.kind or 'sell') == 'sell' and os.clock() - wn.t < 120 and wn.slot == slot and wn.id == item then
        local have = 0;
        pcall(function() local it = AshitaCore:GetMemoryManager():GetInventory():GetContainerItem(0, slot); if it and it.Id == item then have = it.Count or 0; end end);
        local n = math.min(wn.n, have);
        if n >= 1 then
            e.data_modified = d:sub(1, 4) .. string.char(n % 256, math.floor(n / 256) % 256, 0, 0) .. d:sub(9);
            d = e.data_modified;
            M.note('sellamt' .. os.clock(), ('price request for slot %d item %d set to %d'):format(slot, item, n));
        end
    end
    local hl = SHP.sell_hl;
    if not hl or os.clock() - hl.t > 1.5 then SHP.block85 = false; return; end
    if (slot ~= hl.slot or item ~= hl.id) and hl.row and SHP.sell_raw then
        local alt = (SHP.order_now() == 'slot') and 'sort' or 'slot';
        local AL = (alt == 'slot') and SHP.sell_raw or SHP.sort(SHP.sell_raw);
        local ae = AL[hl.row];
        if ae and ae.idx == slot and ae.id == item then          -- (the other order: switch to it; this request (and a sale right after) still stopped)
            cfg.sellorder = cfg.sellorder or {};
            cfg.sellorder[SHP.who()] = alt; cfg.sellorder_default = alt; pcall(save);
            e.blocked = true;
            SHP.block85 = true;
            SHP.sell_hl = nil;
            M.note('sellcheck' .. os.clock(), ('game picked slot %d item %d (row %d): this shop lists in %s order - switched'):format(slot, item, hl.row, alt));
            return;
        end
    end
    if slot ~= hl.slot or item ~= hl.id then
        e.blocked = true;
        SHP.block85, SHP.sell_off = true, true;
        M.note('sellcheck' .. os.clock(), ('game picked slot %d item %d, the panel had slot %d item %d: stopped, panel off'):format(slot, item, hl.slot, hl.id));
        msg('The Sell list didn\'t match the game\'s, so that sale was stopped. Sell uses the game\'s own list from now on.');
    else
        SHP.block85 = false;
        M.note('sellcheck' .. os.clock(), ('game picked slot %d item %d: matches the panel'):format(slot, item));
    end
end
-- Selling more than one: the panel's own "how many" (like Trade's) in place of the game's box. Confirm closes the game's
-- box, waits a moment (the game re-asks the price of the item when its list is back), then asks the price for that
-- many of the highlighted item (0x084) and, when the server answers for that slot, sells it (0x085) - the game's own
-- two steps. Cancel just closes the game's box.
-- The game's "how many" box (itemctrl): its amount and the most there is are in its list numbers (6th / 5th). The panel
-- draws them like Trade's picker; the controller still works the game's box, and - / + / OK press its own keys, so
-- the sale is the game's as always (then its Sell / Cancel).
function SHP.mirror(ic)
    -- (from the log: the 5th list number is the amount - it starts at the whole stack - and the 6th the least, 1)
    local lf = list_fields(ic);
    if not lf or (lf[5] or 0) < 1 or (lf[5] or 0) > 99999 then return nil; end
    local hl = SHP.sell_hl;
    local id = hl and hl.id;
    if SHP.mbox ~= ic.addr then SHP.mbox, SHP.mmax = ic.addr, lf[5]; end
    local mx = SHP.mmax or lf[5];
    pcall(function() local it = AshitaCore:GetMemoryManager():GetInventory():GetContainerItem(0, hl.slot); if it and it.Id == id and (it.Count or 0) > 0 then mx = it.Count; end end);
    return { id = id, name = id and DLV.name(id) or 'How many?', n = lf[5], max = math.max(mx, lf[5]), unit = id and SHP.prices[id] or nil, kind = 'item' };
end
function SHP.mirror_step(d)
    if not SHP.mbox then return; end
    M.act(SHP.mbox, nil, (d > 0) and KEY.up or KEY.down);
end
function SHP.mirror_done(ok)
    if not SHP.mbox then return; end
    M.act(SHP.mbox, nil, ok and KEY.ok or KEY.cancel);
end
function SHP.have(id)                                                -- (how many of an item in your Inventory, all stacks)
    local n = 0;
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        for i = 1, 80 do local it = inv:GetContainerItem(0, i); if it and it.Id == id then n = n + (it.Count or 0); end end
    end);
    return n;
end
function SHP.stack(id)
    local n = 1;
    pcall(function() local r = AshitaCore:GetResourceManager():GetItemById(id); n = tonumber(r and r.StackSize) or 1; end);
    return math.max(1, n);
end
function SHP.pick_open(ic)
    if SHP.pick or SHP.sell_q or SHP.pick_closed == ic.addr then return; end
    local kind = SHP.kind;
    if kind == 'sell' then
        local hl = SHP.sell_hl;
        local e = nil;
        for _, it in ipairs(SHP.inv()) do if hl and it.idx == hl.slot and it.id == hl.id then e = it; end end
        if not e or (e.count or 1) <= 1 then return; end
        SHP.pick = { id = e.id, name = DLV.name(e.id), n = e.count, max = e.count, unit = SHP.prices[e.id], slot = e.idx, kind = 'item', sk = 'sell', typed = false, box = ic.addr };
        return;
    end
    local P = SHP.picked;
    if not P or not P.id or P.id == 0 then return; end
    local mx;
    if kind == 'gsell' then
        mx = SHP.have(P.id);
        if (P.stock or 0) > 0 then mx = math.min(mx, P.stock); end   -- (what the guild still wants)
    else
        mx = SHP.stack(P.id);
        if P.price and P.price > 0 then mx = math.min(mx, math.floor(DLV.gil() / P.price)); end
        if kind == 'gbuy' and P.stock then mx = math.min(mx, P.stock); end
    end
    mx = math.min(mx, (kind == 'buy') and 99999 or 255);
    if mx < 1 then return; end
    SHP.pick = { id = P.id, name = DLV.name(P.id), n = (kind == 'gsell') and mx or 1, max = mx, unit = P.price, shopidx = P.shopidx,
                 kind = 'item', sk = kind, buy = (kind == 'buy' or kind == 'gbuy'), typed = false, box = ic.addr };
end
function SHP.pick_step(d)
    local P = SHP.pick;
    if not P then return; end
    P.n = math.max(1, math.min(P.max, P.n + d)); P.typed = false;
end
-- (OK: the game's own box is confirmed and its Sell / Cancel comes up showing that many; when you say Sell, the game asks
--  the price of what it'll sell and sells it (0x084 then 0x085) - the amount in that request is set to yours, for that
--  item in that slot only. Cancel: the game's box is cancelled.)
function SHP.pick_done(ok)
    local P = SHP.pick;
    SHP.pick = nil;
    if not P then return; end
    SHP.pick_closed = P.box;
    if ok then
        SHP.want_n = { id = P.id, slot = P.slot, n = math.max(1, math.min(P.max, P.n)), unit = P.unit, t = os.clock(), kind = P.sk, shopidx = P.shopidx };
        M.act(P.box, nil, KEY.ok);
    else
        SHP.want_n = nil;
        M.act(P.box, nil, KEY.cancel);
    end
end
function SHP.sell_run()                                              -- (each frame: the queued sale's steps)
    local q = SHP.sell_q;
    if not q then return; end
    local now = os.clock();
    if now - q.t > 5 then SHP.sell_q = nil; M.note('sellq', 'no answer from the server: nothing sold'); return; end
    if not q.asked and now >= q.at then
        local it = nil;                                              -- (still that item in that slot?)
        pcall(function() it = AshitaCore:GetMemoryManager():GetInventory():GetContainerItem(0, q.slot); end);
        if not it or it.Id ~= q.id or (it.Count or 0) < q.n then SHP.sell_q = nil; msg('That item changed: nothing was sold.'); return; end
        q.asked = true;
        pcall(function()
            AshitaCore:GetPacketManager():AddOutgoingPacket(0x84, { 0, 0, 0, 0, q.n % 256, math.floor(q.n / 256) % 256, 0, 0,
                q.id % 256, math.floor(q.id / 256), q.slot, 0 });
        end);
        M.note('sellq' .. now, ('asked the price of %d x item %d (slot %d)'):format(q.n, q.id, q.slot));
    end
end
function SHP.sold(d)                                                 -- in 0x03D
    local function u(o, n) local v = 0; for i = n - 1, 0, -1 do v = v * 256 + (d:byte(o + i + 1) or 0); end return v; end
    if #d < 0x0A then return; end
    local slot, id = u(8, 1), nil;                                    -- (kept by item: the same item, the same price)
    pcall(function() local it = AshitaCore:GetMemoryManager():GetInventory():GetContainerItem(0, slot); id = it and it.Id; end);
    local q = SHP.sell_q;
    local wn = SHP.want_n;
    local ours = (q and q.asked and slot == q.slot and id == q.id) or (wn and wn.slot == slot and wn.id == id);   -- (a "that many" price isn't the price of one)
    if id and id ~= 0 and not ours then SHP.prices[id] = u(4, 4); SHP.last_sale = { id = id, price = u(4, 4), slot = slot, t = os.clock() }; end
    if q and q.asked and slot == q.slot and id == q.id then
        SHP.sell_q = nil;
        pcall(function() AshitaCore:GetPacketManager():AddOutgoingPacket(0x85, { 0, 0, 0, 0, 1, 0, 0, 0 }); end);
        M.note('sellq' .. os.clock(), ('sold %d x item %d'):format(q.n, q.id));
        msg(('Sold %d x %s.'):format(q.n, DLV.name(q.id)));
    end
end
-- the game's "Buy / Cancel" (shopbuy) and "Sell / Cancel" (shopsell) after an item is picked: like the other menus,
-- following the game's cursor; the item and its price above
function SHP.confirm(w, sell)
    local s = PSCALE();
    local P = SHP.picked;
    local wb = SHP.want_n;
    if not sell and wb and wb.kind ~= 'sell' and os.clock() - wb.t < 120 then
        P = { id = wb.id, n = wb.n, price = wb.unit and wb.unit * wb.n or nil };
    end
    if sell then                                                     -- (selling: what the game will sell - the amount picked on the panel, or one)
        local wn = SHP.want_n;
        local hl = SHP.sell_hl;
        if wn and os.clock() - wn.t < 120 then
            local unit = SHP.prices[wn.id] or wn.unit;
            P = { id = wn.id, n = wn.n, price = unit and unit * wn.n or nil };
        elseif hl then
            P = { id = hl.id, n = 1, price = SHP.prices[hl.id] };
        else
            local L_ = SHP.last_sale;
            P = (L_ and os.clock() - L_.t < 30) and { id = L_.id, price = L_.price, n = 1 } or nil;
        end
    end
    local rows = { { sell and 'Sell' or 'Buy', '' }, { 'Cancel', '' } };
    local cur = math.max(1, math.min(2, w.cursor));
    local nm = P and (((P.n or 1) > 1 and (P.n .. ' x ') or '') .. DLV.name(P.id)) or (sell and 'Sell it?' or 'Buy it?');
    local sub = nm .. ((P and P.price) and ('  -  ' .. DLV.gs(P.price) .. ' G') or '');
    local native = cfg.follow and M.to_screen(w.rect) or nil;
    local x, y = native and native[1] or 40, native and (native[2] - 70 * s) or 700;
    local foot = (cur == 1) and (sell and ((P and P.price) and ('You get ' .. DLV.gs(P.price) .. ' G.') or 'Sell it to them.') or 'Pay and take it.') or 'Back to the list.';
    local clicked, wd = list_panel('shopbuy', x, y, math.floor(360 * s), sell and 'SELL' or 'BUY', sub, rows, cur,
        { focused = (M.focus == w.addr), foot = foot });
    if M.focus ~= w.addr then return; end
    if clicked then M.act(w.addr, clicked, KEY.ok); end
    if wd ~= 0 then local to = cur + wd; if to >= 1 and to <= 2 then M.act(w.addr, to, nil); end end
end
function SHP.list()
    if M.find('guildsho') then return SHP.gitems or {}; end          -- (a guild's shop: its own list)
    local out = {};
    for i = 1, 256 do local e = SHP.items[i]; if e then out[#out + 1] = e; end end
    return out;
end
-- A guild's shop (craft guilds and the like: "guildsho" for Buy / Sell): what it sells comes as 0x083 - up to 30 a
-- packet (item, how many it has, the most it holds, price), the last one marked 0x80 - in the order it lists them.
SHP.gitems, SHP.gsell = {}, {};
function SHP.gpacket(d, sellist)                                     -- (0x085: what the guild buys from you - the same layout)
    if #d < 0xF6 then return; end
    local function u(o, n) local v = 0; for i = n - 1, 0, -1 do v = v * 256 + (d:byte(o + i + 1) or 0); end return v; end
    local n, stat = u(0xF4, 1), u(0xF5, 1);
    if stat == 0x40 or stat == 0x80 then if sellist then SHP.gsell = {}; else SHP.gitems = {}; end end
    local T = sellist and SHP.gsell or SHP.gitems;
    for i = 0, math.min(30, n) - 1 do
        local o = 4 + i * 8;
        local item = u(o, 2);
        if item ~= 0 then T[#T + 1] = { id = item, stock = u(o + 2, 1), max = u(o + 3, 1), price = u(o + 4, 4), guildsell = sellist or nil }; end
    end
    SHP.t = os.clock();
end
function SHP.main(w)                                                 -- Buy / Sell
    local s = PSCALE();
    local rows = { { 'Buy', '>' }, { 'Sell', '>' } };
    local cur = math.max(1, math.min(2, w.cursor));
    if M.focus == w.addr then SHP.last_main = cur; SHP.mode_addr = nil; end   -- (which one opens the list next: 1 Buy, 2 Sell - the
                                                                     --  list window can come back at the same address)
    local native = cfg.follow and M.to_screen(w.rect) or nil;
    local x, y = native and native[1] or 400, native and (native[2] - 60 * s) or 600;
    local who = '';
    pcall(function() local ti = GMT.talk and GMT.talk[1]; if ti then who = AshitaCore:GetMemoryManager():GetEntity():GetName(ti) or ''; end end);
    local clicked, wd = list_panel('shopmain', x, y, math.floor(240 * s), (w.name == 'guildsho') and 'GUILD SHOP' or 'SHOP', (who ~= '') and who or 'Buy or sell?', rows, cur,
        { focused = (M.focus == w.addr), foot = (cur == 1) and 'What they have for sale.' or 'Sell them your items.' });
    if M.focus ~= w.addr then return; end
    if clicked then M.act(w.addr, clicked, KEY.ok); end
    if wd ~= 0 then local to = cur + wd; if to >= 1 and to <= 2 then M.act(w.addr, to, nil); end end
end
-- Bazaar > Set Prices: the game's "shop" list again, with your inventory in it (slot order) and each item's bazaar
-- price; the game's own box still takes the price you type.
function SHP.bz_price(slot)
    local p = 0;
    pcall(function() p = AshitaCore:GetMemoryManager():GetInventory():GetContainerItem(0, slot).Price or 0; end);
    if p == 0 then pcall(function() local c = vana.game.container(0); p = (c and c[slot] and c[slot].price) or 0; end); end
    return p;
end
function SHP.bz_out(e)
    if not UI.bzp_drawn or not SHP.picked or SHP.bz_off then return; end
    local d = e.data_modified or e.data;
    local slot = d:byte(0x05) or -1;
    local price = (d:byte(0x09) or 0) + (d:byte(0x0A) or 0) * 256 + (d:byte(0x0B) or 0) * 65536 + (d:byte(0x0C) or 0) * 16777216;
    if slot == SHP.picked.idx then
        M.note('bzset' .. os.clock(), ('bazaar price %d on slot %d (%s): matches the panel'):format(price, slot, DLV.name(SHP.picked.id)));
        return;
    end
    e.blocked = true;                                                -- (the game's row isn't ours: no price set, the game's list from now on)
    SHP.bz_off = true;
    M.note('bzset' .. os.clock(), ('bazaar price %d on slot %d, the panel had slot %d (%s): STOPPED, the game\'s list from now on'):format(price, slot, SHP.picked.idx, DLV.name(SHP.picked.id)));
    msg('That price was not set: the Set Prices list was out of step with the game\'s. The game\'s own list is used from now on - set the price again there.');
end
function SHP.bazaar_prices(w)
    SHP.bz_ok = false;
    local all = SHP.inv();
    local lf = list_fields(w);
    if not lf or lf[6] ~= #all then
        if SHP.bz_noted ~= w.addr then SHP.bz_noted = w.addr; M.note('bzprices' .. os.clock(), ('bazaar prices: game list %s, inventory %d: left to the game'):format(tostring(lf and lf[6]), #all)); end
        return false;
    end
    if SHP.bz_off then return false; end                           -- (a price once went to another row than ours: the game's list)
    for _, e in ipairs(all) do e.bzprice = SHP.bz_price(e.idx); end
    local L = SHP.sort(all);                                         -- (the game's order here is its Sell order: usable items by number first)
    SHP.bz_ok = SHP.draw(w, L, nil, true);
    return SHP.bz_ok;
end
function SHP.draw(w, sell, gsell, bz)                                -- what they sell (or, sell: your items; gsell: what a guild buys; bz: your bazaar prices)
    local s = PSCALE();
    local L = sell or SHP.list();
    if gsell then
        L = { { select = true, id = 0 } };
        for _, e in ipairs(SHP.gsell) do L[#L + 1] = e; end
    end
    SHP.kind = gsell and 'gsell' or (sell and 'sell' or (M.find('guildsho') and 'gbuy' or 'buy'));
    local lf = list_fields(w);
    local top = (lf and lf[5]) or 0;
    if top < 0 or top > 1000 then top = 0; end
    if SHP.draw_addr ~= w.addr then SHP.draw_addr, SHP.last_cur, SHP.vtop = w.addr, nil, nil; end
    local cur = (M.focus == w.addr) and (top + w.cursor) or nil;
    if cur then SHP.last_cur = cur; elseif SHP.last_cur then cur = SHP.last_cur; end   -- (how many / confirm up: the row stays lit)
    local VIS = 10;
    -- (the game's list can be taller than 10 rows - then the panel scrolls itself so the picked row stays in view)
    if w.buttons <= 10 then SHP.vtop = top;
    else
        SHP.vtop = SHP.vtop or 0;
        if cur then if cur <= SHP.vtop then SHP.vtop = cur - 1; elseif cur > SHP.vtop + VIS then SHP.vtop = cur - VIS; end end
        SHP.vtop = math.max(0, math.min(math.max(0, #L - VIS), SHP.vtop));
    end
    top = SHP.vtop;
    local P, HEAD, RH = math.floor(14 * s), math.floor(52 * s), math.floor(30 * s);
    local W = math.floor(470 * s);
    local H = HEAD + VIS * RH + 34 * s;
    local sw, sh = screen();
    local nat = M.to_screen(w.rect);
    local x, y = nat and math.floor(nat[1]) or 40, nat and math.floor(nat[2]) or 60;
    local ic = M.find('itemctrl');                                   -- (the game's "how many" box: selling, the panel's own picker
    local mirror = nil;                                              --  takes its place)
    if bz then ic = M.find('moneyctr'); end                          -- (the bazaar's price box: the game's own, the panel moves clear of it)
    if ic and not bz and not (sell and SHP.sell_off) then
        SHP.pick_open(ic);
        mirror = SHP.pick;
        if mirror then M.hide(ic, 'park'); end
    end
    if not mirror then
        local icr = ic and M.to_screen(ic.rect);
        if icr then x = math.floor(icr[3] + 10 * s); if bz then y = math.floor(icr[2]) - math.floor(H * 0.5); end end   -- (beside the price box)
    end
    x = math.max(4, math.min(sw - W - 4, x)); y = math.max(4, math.min(sh - H - 4, y));
    imgui.SetNextWindowPos({ x, y }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ W + 8, H + 8 }, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    UI.pushed = 2;
    local opened = imgui.Begin('##ccm_npcshop', { true }, win_flags());
    UI.began = true;
    if opened then
        local dl = imgui.GetWindowDrawList();
        local hov_win = imgui.IsWindowHovered();
        local mx, my = mouse();
        DL.RF(dl, x, y, x + W, y + H, U4(0.035, 0.030, 0.050, 1), 10 * s);
        panel(dl, x, y, x + W, y + H, 1, s);
        local who = '';
        pcall(function() local ti = GMT.talk and GMT.talk[1]; if ti then who = AshitaCore:GetMemoryManager():GetEntity():GetName(ti) or ''; end end);
        local tk = font(12 * s); caps(dl, x + P, y + 10 * s, bz and 'BAZAAR  -  SET PRICES' or (sell and 'SHOP  -  SELL' or (M.find('guildsho') and 'GUILD SHOP' or 'SHOP')), C.acc, 2.5 * s, 1); unfont(tk);
        local gil = DLV.gil();
        tk = font(16 * s); text(dl, x + P, y + 25 * s, bz and 'Your items' or ((who ~= '') and who or 'For sale'), C.text, 1); unfont(tk);
        tk = font(13 * s);
        local gs = DLV.gs(gil) .. ' G';
        local gx = x + W - P - tw(gs);
        DLV.coins(dl, gx - 16 * s, y + 33 * s, 8 * s, s);
        text(dl, gx, y + 26 * s, gs, C.gold, 1);
        unfont(tk);
        local hover, show = nil, nil;
        for r = 1, VIS do
            local i = top + r;
            local e = L[i];
            if e and e.select then                                   -- (a guild's "Select from your inventory.")
                local ry = y + HEAD + (r - 1) * RH;
                if i == cur then
                    local p1, p2 = col(C.pink, 0.34), U4(C.vio[1], C.vio[2], C.vio[3], 0.0);
                    DL.RFM(dl, x + 8 * s, ry + 1, x + W - 8 * s, ry + RH - 1, p1, p2, p2, p1);
                    SHP.picked = nil;
                end
                local t1 = font(14 * s); text(dl, x + P + 8 * s, ry + (RH - imgui.GetTextLineHeight()) / 2, 'Select from your inventory.', C.acc, 1); unfont(t1);
            elseif e then
                local ry = y + HEAD + (r - 1) * RH;
                local hv = hov_win and not UI.move and inside(mx, my, x + 8 * s, ry, x + W - 8 * s, ry + RH);
                if hv then hover = r; end
                if i == cur then
                    local p1, p2 = col(C.pink, 0.34), U4(C.vio[1], C.vio[2], C.vio[3], 0.0);
                    DL.RFM(dl, x + 8 * s, ry + 1, x + W - 8 * s, ry + RH - 1, p1, p2, p2, p1);
                    DL.RF(dl, x + 8 * s, ry + 4, x + 10.5 * s, ry + RH - 4, col(C.pink, 1), 2);
                elseif hv then DL.RF(dl, x + 8 * s, ry + 1, x + W - 8 * s, ry + RH - 1, U4(1, 1, 1, 0.06), 4 * s); end
                local is = RH - 6 * s;
                image(dl, item_icon(e.id), x + P + 4 * s, ry + 3 * s, x + P + 4 * s + is, ry + 3 * s + is, 1);
                local t1 = font(14 * s);
                local stk = (e.stock ~= nil) and ('x' .. e.stock .. '    ') or '';   -- (a guild: how many it has / wants)
                if e.guildsell then local have = SHP.have(e.id); stk = ('have ' .. have .. '    '); end
                local ps = sell and ((((e.count > 1) and ('x' .. e.count .. '    ') or '')) .. (SHP.prices[e.id] and (DLV.gs(SHP.prices[e.id]) .. ' G') or '')) or (stk .. DLV.gs(e.price) .. ' G');
                if bz then ps = (((e.count > 1) and ('x' .. e.count .. '    ') or '')) .. (((e.bzprice or 0) > 0) and (DLV.gs(e.bzprice) .. ' G') or 'not for sale'); end
                local t2 = font(12.5 * s); local pw = tw(ps); unfont(t2);
                local nm = DLV.name(e.id);
                while tw(nm) > W - 2 * P - is - pw - 24 * s and #nm > 3 do nm = nm:sub(1, #nm - 1); end
                local nc = (sell and not bz and (e.nosale or e.worn)) and C.dim or ((i == cur) and C.text or { 0.86, 0.84, 0.94, 1 });
                text(dl, x + P + is + 12 * s, ry + (RH - imgui.GetTextLineHeight()) / 2, nm, nc, 1);
                unfont(t1);
                t2 = font(12.5 * s);
                local pc = sell and ((SHP.prices[e.id] and C.gold) or C.acc) or ((e.price > gil or e.stock == 0) and C.dim or C.gold);
                if bz then pc = ((e.bzprice or 0) > 0) and C.gold or C.dim; end
                text(dl, x + W - P - tw(ps), ry + (RH - imgui.GetTextLineHeight()) / 2, ps, pc, 1);
                unfont(t2);
                if hv or (i == cur and not hover) then show = e; end
                if i == cur then SHP.picked = { id = e.id, price = sell and SHP.prices[e.id] or e.price, sell = (sell and not bz) and true or false, idx = e.idx, count = e.count,
                    shopidx = e.shopidx, stock = e.stock, guildsell = e.guildsell }; end
                if sell and i == cur then SHP.sell_hl = { slot = e.idx, id = e.id, t = os.clock(), row = i }; end
            end
        end
        if #L > VIS then                                             -- (where in the list)
            local tx0, ty0, ty1 = x + W - 5 * s, y + HEAD, y + HEAD + VIS * RH;
            DL.RF(dl, tx0, ty0, tx0 + 2 * s, ty1, U4(1, 1, 1, 0.06), 2);
            local h_ = (ty1 - ty0) * VIS / #L;
            local o_ = (ty1 - ty0 - h_) * top / math.max(1, #L - VIS);
            DL.RF(dl, tx0, ty0 + o_, tx0 + 2 * s, ty0 + o_ + h_, mix(C.pink, C.vio, 0.5, 0.9), 2);
        end
        tk = font(11.5 * s);
        text(dl, x + P, y + H - 22 * s, bz and ('%d items.  Confirm: set its price (0 takes it out of your bazaar).  Cancel: back.'):format(#L) or (sell and ('%d items.  Confirm: sell.  Grey: they won\'t buy it.  Cancel: back.'):format(#L) or ('%d items.  Confirm: buy.  Cancel: back.'):format(#L)), C.dim, 1);
        unfont(tk);
        if mirror then draw_trade_pick(x, y + HEAD, W, s, mirror, SHP.pick_step, SHP.pick_done, true);   -- (how many: like Trade's)
        elseif show then item_tooltip(show.id, mx, my, { x + W + 8 * s, y, y }, nil, sell and 0 or nil, sell and show.idx or nil); end
        if hov_win and not UI.move then
            if hover and imgui.IsMouseClicked(0) then M.act(w.addr, hover, (top + hover == cur) and KEY.ok or nil); end
            if imgui.IsMouseClicked(1) then M.act(nil, nil, KEY.cancel); end
            local wh = imgui.GetIO().MouseWheel or 0;
            if cfg.wheel and wh ~= 0 then M.act(w.addr, nil, (wh > 0) and KEY.up or KEY.down); end
        end
    end
    imgui.End();
    UI.began = false;
    imgui.PopStyleVar(2);
    UI.pushed = 0;
    return true;
end

local function draw_inspect(w)
    local s = PSCALE();
    local P = math.floor(16 * s);
    local cell, gap = math.floor(52 * s), math.floor(6 * s);
    local GW = 4 * cell + 3 * gap;
    local W = GW + 2 * P;
    local HEAD = math.floor(66 * s);
    local tk;
    local bz = INSM.bazaar and math.abs(INSM.t - INS.t) < 3;
    local msgn = (bz and UI.ins and UI.ins.msgn) or 0;               -- (the message's lines, measured inside the window last frame:
    local H = HEAD + 10 * s + GW + 12 * s + 26 * s + (bz and (34 * s) or 0) + msgn * 16 * s + P;   --  font calls outside one open ImGui's Debug box)
    local sw, sh = screen();
    local native = cfg.follow and M.to_screen(w.rect) or nil;
    local x, y = place('ins', W, H, native, 'left', math.floor((sw - W) / 2), math.floor(sh * 0.3));
    local now = os.clock();
    UI.ins = UI.ins or {};
    if UI.ins.t0 == nil then UI.ins.cur, UI.ins.auto = bz and 17 or 1, true; end   -- (each time it opens: on View Wares if they
    UI.ins.t0 = UI.ins.t0 or now;                                                  --  have a bazaar, else on the main hand)
    if UI.ins.auto and bz and UI.ins.cur == 1 and now - UI.ins.t0 < 1.5 then UI.ins.cur = 17; end   -- (their bazaar info came a moment late)
    UI.ins.bz = bz;
    local k = cfg.anim and ease((now - UI.ins.t0) / 0.22) or 1;
    local a = k;
    y = y + math.floor((1 - k) * 12 * s);
    local focused = (M.focus == w.addr);
    -- who: the name from the bazaar packet, else the entity the gear came from, else your target
    local name = (math.abs(INSM.t - INS.t) < 3 and INSM.name ~= '' and INSM.name) or nil;
    if not name then pcall(function() name = AshitaCore:GetMemoryManager():GetEntity():GetName(INS.index or 0); end); end
    if not name or name == '' then
        pcall(function()
            local ti = AshitaCore:GetMemoryManager():GetTarget():GetTargetIndex(0);
            name = AshitaCore:GetMemoryManager():GetEntity():GetName(ti);
        end);
    end
    name = name or '';

    imgui.SetNextWindowPos({ x, y }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ W + 8, H + 8 }, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    UI.pushed = 2;
    local opened = imgui.Begin('##ccm_inspect', { true }, win_flags());
    UI.began = true;
    if opened then
        local dl = imgui.GetWindowDrawList();
        x, y = drag('ins', x, y, x, y, x + W, y + HEAD);
        UI.ins.rect = { x, y, W, H };
        local hov_win = imgui.IsWindowHovered();
        local mx, my = mouse();
        panel(dl, x, y, x + W, y + H, a, s);
        lock_button(dl, x + W - P - 16 * s, y + 4 * s, s, a, hov_win);
        -- header: their job emblem, name, jobs
        local jn = JOBS[INS.job or 0];
        local js = 46 * s;
        local jx, jy = x + P, y + (HEAD - js) / 2 + 2 * s;
        DL.CF(dl, jx + js / 2, jy + js / 2, js * 0.55, col(C.vio, 0.10 * a), 32);
        if not (jn and image(dl, tex('jobs\\' .. jn:lower() .. '.png'), jx, jy, jx + js, jy + js, a)) then
            DL.C(dl, jx + js / 2, jy + js / 2, js * 0.42, col(C.acc, 0.6 * a), 32, 1.5);
        end
        local tx = jx + js + 12 * s;
        tk = font(12 * s); caps(dl, tx, y + 12 * s, 'CHECK', C.acc, 2.5 * s, a); unfont(tk);
        tk = font(20 * s); text(dl, tx, y + 26 * s, name, C.text, a); unfont(tk);
        tk = font(12 * s);
        local js_ = '';
        if jn and (INS.lv or 0) > 0 then
            js_ = ('%s%d'):format(jn, INS.lv);
            if JOBS[INS.sjob or 0] and (INS.slv or 0) > 0 then js_ = js_ .. ('/%s%d'):format(JOBS[INS.sjob], INS.slv); end
        elseif INS.t > 0 then js_ = 'Anon'; end
        if js_ ~= '' then text(dl, x + W - P - 24 * s - tw(js_), y + 10 * s, js_, C.muted, a); end
        unfont(tk);
        local ly = y + HEAD - 2;
        DL.RFM(dl, x + P, ly, x + W - P, ly + 1, U4(1, 1, 1, 0.0), U4(1, 1, 1, 0.10 * a), U4(1, 1, 1, 0.10 * a), U4(1, 1, 1, 0.0));

        -- the gear, 4 x 4 as the game lays it out
        local gx0, gy0 = x + P, y + HEAD + 10 * s;
        local cur = (UI.ins.cur or 1) <= 16 and UI.ins.cur or nil;
        local hover = nil;
        for b = 1, 16 do
            local c_, r_ = (b - 1) % 4, math.floor((b - 1) / 4);
            local cx0, cy0 = gx0 + c_ * (cell + gap), gy0 + r_ * (cell + gap);
            local cx1, cy1 = cx0 + cell, cy0 + cell;
            local slot = GRID[b];
            local id = INS.gear[slot];
            local hov = hov_win and not UI.move and inside(mx, my, cx0, cy0, cx1, cy1);
            if hov then hover = b; end
            DL.RF(dl, cx0, cy0, cx1, cy1, U4(0.115, 0.105, 0.155, 0.92 * a), 7 * s);
            local t1, t2 = U4(1, 1, 1, 0.05 * a), U4(1, 1, 1, 0);
            DL.RFM(dl, cx0 + 1, cy0 + 1, cx1 - 1, cy0 + cell * 0.5, t1, t1, t2, t2);
            DL.R(dl, cx0, cy0, cx1, cy1, hov and U4(1, 1, 1, 0.30 * a) or U4(0.62, 0.40, 1.0, 0.18 * a), 7 * s, 0, 1);
            if id then
                local is = cell * 0.74;
                local ix, iy = cx0 + (cell - is) / 2, cy0 + (cell - is) / 2;
                if not image(dl, item_icon(id), ix, iy, ix + is, iy + is, a) then
                    local tk2 = font(11 * s); text(dl, cx0 + 6 * s, cy0 + cell / 2 - 6 * s, '?', C.muted, a); unfont(tk2);
                end
            else
                local tk2 = font(10 * s);
                local lab = SLOTS[slot] or '';
                text(dl, cx0 + (cell - tw(lab)) / 2, cy0 + cell / 2 - 6 * s, lab, C.dim, a);
                unfont(tk2);
            end
            if cur == b then sel_frame(dl, cx0, cy0, cx1, cy1, 7 * s, focused and a or a * 0.5); end
        end
        local cy = gy0 + GW + 12 * s;
        -- the linkshell: its pearl in the linkshell's own colour, and its name
        tk = font(14 * s);
        if INS.ls then
            local lc = INS.lscol or C.acc;
            DL.CF(dl, x + P + 7 * s, cy + 8 * s, 8 * s, col(lc, 0.20 * a), 16);
            DL.CF(dl, x + P + 7 * s, cy + 8 * s, 5 * s, col(lc, a), 16);
            DL.CF(dl, x + P + 5.5 * s, cy + 6.5 * s, 1.6 * s, U4(1, 1, 1, 0.7 * a), 8);
            text(dl, x + P + 22 * s, cy, INS.ls, C.text, a);
        else
            text(dl, x + P, cy, (INS.t > 0) and 'No linkshell' or 'Linkshell: --', C.dim, a);
        end
        unfont(tk);
        cy = cy + 26 * s;
        -- the bazaar: View Wares (the game's own button, so the game opens their bazaar) and their message
        if bz then
            local bx0, by0, bx1, by1 = x + P, cy, x + W - P, cy + 26 * s;
            local hv = hov_win and not UI.move and inside(mx, my, bx0, by0, bx1, by1);
            local on = (UI.ins.cur == 17);
            local pulse = 0.5 + 0.5 * math.sin(now * 3.2);           -- (it glows: they have a bazaar)
            for g = 1, 4 do
                local e_ = g * 2.5 * s;
                DL.R(dl, bx0 - e_, by0 - e_, bx1 + e_, by1 + e_, col(C.pink, (0.34 - g * 0.07) * (0.5 + pulse) * a), 8 * s + e_, 0, 2.5 * s);
            end
            DL.RF(dl, bx0, by0, bx1, by1, (hv or on) and col(C.pink, 0.45 * a) or col(C.pink, (0.16 + 0.12 * pulse) * a), 8 * s);
            DL.R(dl, bx0, by0, bx1, by1, col(C.pink, (on and 1 or 0.7) * a), 8 * s, 0, on and 2 or 1);
            tk = font(13 * s); caps(dl, (bx0 + bx1) / 2 - caps_w('VIEW WARES', 3 * s) / 2, by0 + 6 * s, 'VIEW WARES', C.text, 3 * s, a); unfont(tk);
            if hv and imgui.IsMouseClicked(0) then UI.ins.cur = 17; M.act(w.addr, 17, KEY.ok); end
            cy = cy + 34 * s;
            tk = font(13 * s);
            local msgl = (INSM.msg and INSM.msg ~= '') and wrap(INSM.msg, W - 2 * P) or {};
            UI.ins.msgn = #msgl;
            for _, ln in ipairs(msgl) do text(dl, x + P, cy, ln, C.muted, a); cy = cy + 16 * s; end
            unfont(tk);
        end
        -- the item under the mouse, or the game's cursor: the item card under the panel
        local show = hover or cur;
        local sid = show and INS.gear[GRID[show]] or nil;
        if sid then item_tooltip(sid, mx, my, { x, y + H + 6 * s, y - 6 * s }, INS.ext and INS.ext[GRID[show]]); end
        -- mouse: a slot moves the game's cursor there; right-click = close (back)
        if hov_win and not UI.move then
            if hover and imgui.IsMouseClicked(0) then UI.ins.cur, UI.ins.auto = hover, false; end
            if imgui.IsMouseClicked(1) then M.act(nil, nil, KEY.cancel); end
        end
    end
    imgui.End();
    UI.began = false;
    imgui.PopStyleVar(2);
    UI.pushed = 0;
end

-- Another player's bazaar (View Wares from Check). The game's list ("shop": 10 rows a page, with "money" and "iteminfo"
-- beside it) is replaced by a panel with each item's icon, name, how many and price, your gil, and the item card
-- (augments too) under it. The server sends the wares in packet 0x105, one per item (after LandSandBoat / XiPackets:
-- price u32 at 0x04, count u32 at 0x08, item u16 at 0x0E, bag slot u8 at 0x10, the item's extra data from 0x11).
-- The game's own list keeps running underneath and follows the controller as always; the panel follows its cursor,
-- and buying is the game's own (its confirm prompt is left as it is).
local BAZ = { items = {}, t = -10, n = 0 };
function BAZ.packet(id, d)
    local function b(o) return d:byte(o + 1) or 0; end
    local function u16(o) return b(o) + b(o + 1) * 256; end
    local function u32(o) return u16(o) + u16(o + 2) * 65536; end
    local now = os.clock();
    if id == 0x105 then
        if now - BAZ.t > 1.5 then BAZ.items, BAZ.n, BAZ.t0 = {}, 0, now; end   -- (a new bazaar: the list comes in a burst)
        BAZ.t = now;
        local price, count, item, slot = u32(0x04), u32(0x08), u16(0x0E), b(0x10);
        if item == 0 or item == 65535 or count == 0 then
            if BAZ.items[slot] then BAZ.items[slot] = nil; BAZ.n = BAZ.n - 1; end
        else
            if BAZ.items[slot] == nil then BAZ.n = BAZ.n + 1; end
            BAZ.items[slot] = { slot = slot, id = item, count = count, price = price, ext = d:sub(0x12, 0x12 + 23) };
        end
        BAZ.logged = false;
    elseif id == 0x106 then                                           -- (a purchase went through or not: noted for the survey)
        pcall(function() M.note('bazaar', ('buy result %d'):format(u32(0x04))); end);
    end
end
function BAZ.rows()                                                   -- in the game's order: by bag slot
    local r = {};
    for _, it in pairs(BAZ.items) do r[#r + 1] = it; end
    table.sort(r, function(p, q) return p.slot < q.slot; end);
    if not BAZ.logged and #r > 0 then
        BAZ.logged = true;
        local t_ = {};
        for _, it in ipairs(r) do t_[#t_ + 1] = ('%d:%d x%d %dg'):format(it.slot, it.id, it.count, it.price); end
        pcall(function() M.note('bazaar', table.concat(t_, ' ')); end);
    end
    return r;
end
function BAZ.gil_str(n) return tostring(math.floor(n or 0)):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '') .. ' G'; end
function BAZ.my_gil()
    local g = 0;
    pcall(function() local it = AshitaCore:GetMemoryManager():GetInventory():GetContainerItem(0, 0); g = (it and it.Count) or 0; end);
    return g;
end
-- buying: how many (like the trade window's picker), then the server's own bazaar purchase (packet 0x106: the item's
-- bazaar slot at 0x04, how many at 0x08; after LandSandBoat). The server checks the price, your gil and the stock as usual.
function BAZ.open_pick(it)
    local st = UI.baz;
    local info = item_info(it.id);
    local afford = (it.price > 0) and math.floor(BAZ.my_gil() / it.price) or it.count;
    local mx = math.min(it.count, afford);
    if mx < 1 then msg('Bazaar: not enough gil for ' .. ((info and info.name) or 'that') .. '.'); return; end
    st.pick = { kind = 'item', slot = it.slot, id = it.id, name = info and info.name or ('Item ' .. it.id), max = mx, n = 1,
                unit = it.price, buy = true };
end
function BAZ.pick_step(d)
    local P = UI.baz and UI.baz.pick;
    if P then P.n = math.max(1, math.min(P.max, P.n + d)); P.typed = true; end
end
function BAZ.pick_done(ok)
    local st = UI.baz;
    local P = st and st.pick;
    if st then st.pick = nil; end
    if not ok or not P or P.n < 1 then return; end
    local p = {};
    for i = 1, 0x0C do p[i] = 0; end
    p[0x04 + 1] = P.slot;
    for b = 0, 3 do p[0x08 + b + 1] = bit.band(bit.rshift(P.n, b * 8), 0xFF); end
    local sent, err = pcall(function() AshitaCore:GetPacketManager():AddOutgoingPacket(0x106, p); end);
    M.note('bazaar', ('buy slot %d x%d (%s) %s'):format(P.slot, P.n, P.name or '?', sent and 'sent' or ('FAILED ' .. tostring(err))));
    if not sent then msg('Bazaar: could not send the purchase (' .. tostring(err) .. ').'); end
end
function BAZ.pad(acts)                                               -- the controller, while the bazaar is up
    local st = UI.baz;
    if st == nil then return; end
    local rows = BAZ.rows();
    for _, act in ipairs(acts) do
        if st.pick then
            if act == 'up' then BAZ.pick_step(1);
            elseif act == 'down' then BAZ.pick_step(-1);
            elseif act == 'right' then BAZ.pick_step(10);
            elseif act == 'left' then BAZ.pick_step(-10);
            elseif act == 'tabr' then BAZ.pick_step(100);
            elseif act == 'tabl' then BAZ.pick_step(-100);
            elseif act == 'ok' then BAZ.pick_done(true);
            elseif act == 'back' then BAZ.pick_done(false); end
        else
            local n = math.max(1, #rows);
            if act == 'up' then st.cur = (st.cur > 1) and (st.cur - 1) or n;
            elseif act == 'down' then st.cur = (st.cur < n) and (st.cur + 1) or 1;
            elseif act == 'left' or act == 'tabl' then st.cur = math.max(1, st.cur - 10);
            elseif act == 'right' or act == 'tabr' then st.cur = math.min(n, st.cur + 10);
            elseif act == 'ok' then if rows[st.cur] then BAZ.open_pick(rows[st.cur]); end
            elseif act == 'back' then M.act(nil, nil, KEY.cancel); end
        end
    end
end
function BAZ.draw(w)
    local s = PSCALE();
    local rows = BAZ.rows();
    UI.baz = UI.baz or {};
    local st = UI.baz;
    local page = 10;
    st.cur = math.max(1, math.min(math.max(1, #rows), st.cur or 1));
    st.off = st.off or 0;
    if st.cur < st.off + 1 then st.off = st.cur - 1; elseif st.cur > st.off + page then st.off = st.cur - page; end
    st.off = math.max(0, math.min(math.max(0, #rows - page), st.off));
    local top, cur = st.off, st.cur;
    local now = os.clock();
    local P = math.floor(16 * s);
    local HEAD = math.floor(52 * s);
    local RH = math.floor(34 * s);
    local W = math.floor(400 * s);
    local name = (math.abs(INSM.t - INS.t) < 10 and INSM.name ~= '' and INSM.name) or nil;
    if not name then pcall(function() name = AshitaCore:GetMemoryManager():GetEntity():GetName(INS.index or 0); end); end
    name = (name and name ~= '') and name or 'Bazaar';
    local msgt = (INSM.msg and INSM.msg ~= '' and math.abs(INSM.t - INS.t) < 10) and INSM.msg or nil;
    local msgn = msgt and (st.msgn or 1) or 0;                       -- (its lines: measured inside the window, last frame -
    local MH = (msgn > 0) and (msgn * 16 * s + 8 * s) or 0;          --  font calls outside one open ImGui's Debug box)
    local FOOT = math.floor(58 * s);
    local H = HEAD + MH + page * RH + FOOT;
    local sw, sh = screen();
    local x, y;
    local ir = UI.ins and UI.ins_drawn and UI.ins.rect or nil;
    if ir and ir[1] + ir[3] + 14 * s + W < sw - 4 then x, y = ir[1] + ir[3] + 14 * s, ir[2];      -- (beside the Check panel)
    elseif ir and ir[1] - 14 * s - W > 4 then x, y = ir[1] - 14 * s - W, ir[2];
    else
        local native = cfg.follow and M.to_screen(w.rect) or nil;
        x, y = native and native[1] or 40, native and native[2] or 120;
    end
    x, y = saved_pos('baz', x, y, W, H);
    st.t0 = st.t0 or now;
    local k = cfg.anim and ease((now - st.t0) / 0.2) or 1;
    local focused = (M.focus == w.addr) and not st.pick;
    local a = k * (focused and 1 or 0.8);
    y = y + math.floor((1 - k) * 10 * s);

    imgui.SetNextWindowPos({ x, y }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ W + 8, H + 8 }, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    UI.pushed = 2;
    local opened = imgui.Begin('##ccm_bazaar', { true }, win_flags());
    UI.began = true;
    if opened then
        local dl = imgui.GetWindowDrawList();
        x, y = drag('baz', x, y, x, y, x + W, y + HEAD);
        local hov_win = imgui.IsWindowHovered();
        local mx, my = mouse();
        panel(dl, x, y, x + W, y + H, a, s);
        lock_button(dl, x + W - 26 * s, y + 8 * s, s, a, hov_win);
        local tk = font(12 * s); caps(dl, x + P, y + 10 * s, 'BAZAAR', C.acc, 2.5 * s, a); unfont(tk);
        tk = font(18 * s); text(dl, x + P, y + 24 * s, name, C.text, a); unfont(tk);
        tk = font(12 * s);
        local cnt = (#rows > 0) and (('%d-%d / %d'):format(top + 1, math.min(#rows, top + page), #rows)) or 'loading';
        text(dl, x + W - P - 18 * s - tw(cnt), y + 30 * s, cnt, C.dim, a);
        unfont(tk);
        local cy = y + HEAD;
        if msgt then
            tk = font(12.5 * s);
            local msgl = wrap(msgt, W - 2 * P);
            if #msgl > 2 then msgl = { msgl[1], msgl[2] .. '...' }; end
            st.msgn = #msgl;
            for i_, ln in ipairs(msgl) do if i_ <= msgn then text(dl, x + P, cy, ln, C.muted, a); cy = cy + 16 * s; end end
            unfont(tk);
            cy = y + HEAD + MH;
        end
        DL.RFM(dl, x + P, cy - 3 * s, x + W - P, cy - 2 * s, U4(1, 1, 1, 0.0), U4(1, 1, 1, 0.10 * a), U4(1, 1, 1, 0.10 * a), U4(1, 1, 1, 0.0));
        local ly0 = cy;
        local gil = BAZ.my_gil();
        -- the selection bar, gliding to the cursor
        local vis_cur = cur - top;
        local target = ly0 + (vis_cur - 1) * RH;
        st.y = (st.y == nil or not cfg.anim) and target or lerp(st.y, target, math.min(1, 0.35 * 60 * (UI.dt or 0.016)));
        if vis_cur >= 1 and vis_cur <= page and rows[cur] then
            local by = st.y;
            local p1, p2 = col(C.pink, (focused and 0.34 or 0.2) * a), U4(C.vio[1], C.vio[2], C.vio[3], 0.0);
            DL.RFM(dl, x + 8 * s, by + 1, x + W - 8 * s, by + RH - 1, p1, p2, p2, p1);
            DL.RF(dl, x + 8 * s, by + 3, x + 10.5 * s, by + RH - 3, col(C.pink, a), 2);
            local ar = tex('sel_arrow.png');
            local asz = 23 * s * 0.62;
            local bob = cfg.anim and math.sin(now * 5) * 1.5 * s or 0;
            image(dl, ar, x - asz * 0.55 + bob, by + (RH - asz) / 2, x + asz * 0.45 + bob, by + (RH + asz) / 2, a);
        end
        local hover = nil;
        for vi = 1, page do
            local i = top + vi;
            local it = rows[i];
            local yy = ly0 + (vi - 1) * RH;
            local is = RH - 8 * s;
            local ix = x + P + 4 * s;
            if it then
                if hov_win and not UI.move and not st.pick and inside(mx, my, x + 6 * s, yy, x + W - 6 * s, yy + RH) then hover = i; end
                if hover == i and i ~= cur then DL.RF(dl, x + 8 * s, yy + 1, x + W - 8 * s, yy + RH - 1, U4(1, 1, 1, 0.05 * a), 4 * s); end
                local info = item_info(it.id);
                local dear = it.price > gil;
                DL.RF(dl, ix, yy + 4 * s, ix + is, yy + 4 * s + is, U4(1, 1, 1, 0.06 * a), 5 * s);
                image(dl, item_icon(it.id), ix, yy + 4 * s, ix + is, yy + 4 * s + is, a);
                local tx = ix + is + 10 * s + ((i == cur) and 3 * s or 0);
                tk = font(15 * s);
                local nm = info and info.name or ('Item ' .. it.id);
                local nc = (i == cur) and C.text or (info and info.rare and C.gold or C.muted);
                local ty = yy + (RH - imgui.GetTextLineHeight()) / 2;
                text(dl, tx, ty, nm, nc, a);
                local nx = tx + tw(nm);
                unfont(tk);
                tk = font(12 * s);
                if it.count > 1 then text(dl, nx + 6 * s, ty + 3 * s, 'x' .. it.count, C.acc, a); end
                local ps = BAZ.gil_str(it.price) .. ((it.count > 1) and ' ea' or '');
                text(dl, x + W - P - 6 * s - tw(ps), ty + 2 * s, ps, dear and C.bad or C.gold, a * (dear and 0.8 or 1));
                unfont(tk);
            else
                DL.RF(dl, ix, yy + 4 * s, ix + is, yy + 4 * s + is, U4(1, 1, 1, 0.025 * a), 5 * s);
            end
        end
        -- the foot: your gil, and how it works
        local fy = ly0 + page * RH + 8 * s;
        DL.RF(dl, x + P, fy, x + W - P, fy + 26 * s, U4(1, 1, 1, 0.04 * a), 6 * s);
        DL.CF(dl, x + P + 13 * s, fy + 13 * s, 6 * s, col(C.gold, a), 16);
        DL.CF(dl, x + P + 11.5 * s, fy + 11.5 * s, 2 * s, U4(1, 1, 1, 0.6 * a), 8);
        tk = font(12 * s); caps(dl, x + P + 26 * s, fy + 7 * s, 'YOUR GIL', C.muted, 2 * s, a); unfont(tk);
        tk = font(15 * s);
        local gs = BAZ.gil_str(gil);
        text(dl, x + W - P - 10 * s - tw(gs), fy + 4 * s, gs, C.gold, a);
        unfont(tk);
        tk = font(12 * s);
        text(dl, x + P, fy + 32 * s, 'Confirm: buy (how many).  Left / Right: a page.  Cancel: back.', C.dim, a);
        unfont(tk);
        -- the item under the mouse, or the cursor: its card under the panel (above when there's no room)
        local show = (not st.pick) and rows[hover or cur] or nil;
        if show then item_tooltip(show.id, mx, my, { x, y + H + 6 * s, y - 6 * s }, show.ext); end
        -- mouse: a row picks it, a click on the picked row buys; the wheel moves; right-click backs out
        if hov_win and not UI.move and not st.pick then
            if hover and imgui.IsMouseClicked(0) then
                if hover == cur then BAZ.open_pick(rows[cur]); else st.cur = hover; end
            end
            if imgui.IsMouseClicked(1) then M.act(nil, nil, KEY.cancel); end
            local wheel = imgui.GetIO().MouseWheel or 0;
            if cfg.wheel and wheel ~= 0 and #rows > 0 then st.cur = math.max(1, math.min(#rows, st.cur + ((wheel > 0) and -1 or 1))); end
        end
        if st.pick then draw_trade_pick(x, y + HEAD, W, s, st.pick, BAZ.pick_step, BAZ.pick_done, true); end   -- (inside: always on top)
    end
    imgui.End();
    UI.began = false;
    imgui.PopStyleVar(2);
    UI.pushed = 0;
    st.rect = { x, y, W, H };
end

-- The swap menu: every piece in your Inventory and Mog Wardrobes 1-8 that fits the slot, next to the equipment panel.
-- Tabs pick the bag (ALL, INV, W1-W8). A click equips it with the game's own /equip command (it takes the piece
-- from whichever bag it's in), so it doesn't depend on the game's item list.
local EQCMD = { [0] = 'main', 'sub', 'range', 'ammo', 'head', 'body', 'hands', 'legs', 'feet', 'neck', 'waist', 'ear1', 'ear2', 'ring1', 'ring2', 'back' };
UI.sw = { bag = 0, off = 0, slot = nil, flash = nil };
local function swap_items(slot, bagsel)
    local job, lv = 0, 0;
    pcall(function() local pl = AshitaCore:GetMemoryManager():GetPlayer(); job, lv = pl:GetMainJob(), pl:GetMainJobLevel(); end);
    local res = AshitaCore:GetResourceManager();
    local out = {};
    for b = 1, #BAGS do
        if bagsel == 0 or bagsel == b then
            for _, e in ipairs(candidates(BAGS[b][1], slot).all) do
                local r = nil;
                pcall(function() r = res:GetItemById(e.id); end);
                local nm = (r and r.Name and r.Name[1]) or '?';
                local ilv = (r and tonumber(r.Level)) or 0;
                local can = r ~= nil and bit.band(tonumber(r.Jobs) or 0, bit.lshift(1, job)) ~= 0 and ilv <= lv;
                out[#out + 1] = { id = e.id, name = nm, bag = b, idx = e.idx, worn = e.worn, can = can, lv = ilv, count = e.count };
            end
        end
    end
    table.sort(out, function(p, q)
        if p.can ~= q.can then return p.can; end
        if p.lv ~= q.lv then return p.lv > q.lv; end
        if p.name ~= q.name then return p.name < q.name; end
        return p.bag < q.bag;
    end);
    return out;
end
-- Equip a piece the way gear-swap addons (luashitacast) do: the game's own equip request, packet 0x50
-- (its bag slot, the equipment slot, the bag). Works with the equipment menu open, from any bag.
local function equip_piece(slot, it)
    local ok = pcall(function()
        local packet = { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
        packet[5] = it.idx;
        packet[6] = slot;
        packet[7] = BAGS[it.bag][1];
        AshitaCore:GetPacketManager():AddOutgoingPacket(0x50, packet);
    end);
    M.note('swap', ('%s: %s (%s slot %d) %s'):format(SLOTN[slot] or '?', it.name, BAGS[it.bag][2], it.idx or -1, ok and 'sent' or 'FAILED'));
    if not ok then                                                   -- (no packet manager: the text command, as a last resort)
        local cmd = ('/equip %s "%s"'):format(EQCMD[slot] or 'main', it.name);
        pcall(function() AshitaCore:GetChatManager():QueueCommand(1, cmd); end);
    end
    GEAR.at = 0;                                                     -- (look at the gear again next frame)
end
-- the swap list opens on the bag the piece you're wearing is in, with the cursor on that piece
local function swap_sync(slot, force)
    if UI.sw.slot == slot and not force then return; end
    UI.sw.slot, UI.sw.off, UI.sw.cur = slot, 0, nil;
    UI.sw.bag = 0;
    if UI.sw.pinned and BAGS[UI.sw.pinned] then UI.sw.bag = UI.sw.pinned; return; end   -- (the bag picked in the game's Storage)
    pcall(function()
        local g = gear()[slot];
        if g and g.bag then for b = 1, #BAGS do if BAGS[b][1] == g.bag then UI.sw.bag = b; end end end
    end);
end

----------------------------------------------------------------------------------------------------
-- Controller: while one of ChadcoreMenu's own panels has the controller (the swap list, Magic, Abilities, Items, Key
-- Items), its d-pad, confirm, cancel and L1 / R1 (LB / RB) go to the panel and are kept from the game. The arrow keys,
-- Enter, Escape and Page Up / Down do the same on the keyboard. Confirm and cancel are learned from the game's own
-- menus: the button that opens a menu is confirm, the one that backs out is cancel.
----------------------------------------------------------------------------------------------------
local PAD = { q = {}, held = nil, held_t = 0, rep_t = 0, last = nil, last_t = 0, seen = {} };
UI.pad_owner = nil;
local function pad_push(act)
    local now = os.clock();
    if PAD.seen[act] and now - PAD.seen[act] < 0.07 then return; end   -- (each press can arrive twice)
    PAD.seen[act] = now;
    PAD.q[#PAD.q + 1] = act;
    UI.pad_t = now;
end
local function pad_hold(dir)
    local now = os.clock();
    if dir == nil then PAD.held = nil; return; end
    if PAD.held ~= dir then pad_push(dir); PAD.held, PAD.held_t, PAD.rep_t = dir, now, now; end
end
function PAD.take()                                                  -- (the presses since last frame, plus a held d-pad repeating)
    local q = PAD.q;
    PAD.q = {};
    local now = os.clock();
    if PAD.held and now - PAD.held_t > 0.35 and now - PAD.rep_t > 0.09 then PAD.rep_t = now; q[#q + 1] = PAD.held; UI.pad_t = now; end
    return q;
end
local function pad_id(kind, api)
    local v = cfg['pad_' .. kind];
    if type(v) == 'string' and v:sub(1, 1) == api then return v; end
    if kind == 'ok' then return (api == 'd') and 'd49' or 'x12'; end
    return (api == 'd') and 'd50' or 'x13';
end

local function draw_swap(slot, worn_id, active, padcur)
    local s = PSCALE();
    local SW_ = UI.sw;
    swap_sync(slot);
    local items = swap_items(slot, SW_.bag);
    local W = math.floor(320 * s);
    local RH = math.floor(30 * s);
    local HEAD = math.floor(44 * s);
    local TABS = math.floor(26 * s);
    local NROWS = 12;
    local H = HEAD + TABS + NROWS * RH + math.floor(30 * s);
    local x, y;
    if UI.charbox then x, y = UI.charbox[1] + UI.charbox[3] + 10 * s, UI.charbox[2]; else x, y = 600, 120; end
    local sw, sh = screen();
    x, y = saved_pos('swap', x, y, W, H);
    SW_.off = math.max(0, math.min(math.max(0, #items - NROWS), SW_.off));
    local now = os.clock();
    SW_.t0 = SW_.t0 or now;
    local k = cfg.anim and ease((now - SW_.t0) / 0.18) or 1;
    local a = k * (active and 1 or 0.55);
    UI.list_pick = nil;
    imgui.SetNextWindowPos({ x, y }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ W + 8, H + 8 }, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    UI.pushed = 2;
    local opened = imgui.Begin('##ccm_swap', { true }, win_flags());
    UI.began = true;
    if opened then
        local dl = imgui.GetWindowDrawList();
        x, y = drag('swap', x, y, x, y, x + W, y + HEAD);
        local hov_win = imgui.IsWindowHovered() and active;
        local mx, my = mouse();
        panel(dl, x, y, x + W, y + H, a, s);
        local tk = font(12 * s);
        caps(dl, x + 16 * s, y + 10 * s, 'SWAP', C.acc, 2.5 * s, a);
        lock_button(dl, x + W - 26 * s, y + 8 * s, s, a, hov_win);
        unfont(tk);
        tk = font(16 * s);
        text(dl, x + 16 * s, y + 22 * s, SLOTN[slot] or '', C.text, a);
        unfont(tk);
        tk = font(12 * s);
        local cnt = (#items > 0) and (('%d-%d / %d'):format(SW_.off + 1, math.min(#items, SW_.off + NROWS), #items)) or 'nothing fits';
        text(dl, x + W - 16 * s - tw(cnt), y + 28 * s, cnt, C.dim, a);
        unfont(tk);
        -- bag tabs: ALL, INV, W1-W8
        local tabs = { { 0, 'ALL', 'Every bag' } };
        for b = 1, #BAGS do tabs[#tabs + 1] = { b, BAGS[b][3], BAGS[b][2] }; end
        local tw_ = (W - 24 * s - (#tabs - 1) * 2 * s) / #tabs;
        local ty0 = y + HEAD;
        for i, t in ipairs(tabs) do
            local tx0 = x + 12 * s + (i - 1) * (tw_ + 2 * s);
            local sel = (SW_.bag == t[1]);
            local hv = hov_win and not UI.move and inside(mx, my, tx0, ty0, tx0 + tw_, ty0 + 18 * s);
            DL.RF(dl, tx0, ty0, tx0 + tw_, ty0 + 18 * s, sel and col(C.pink, 0.30 * a) or U4(1, 1, 1, (hv and 0.10 or 0.04) * a), 5 * s);
            if sel then DL.R(dl, tx0, ty0, tx0 + tw_, ty0 + 18 * s, col(C.pink, 0.8 * a), 5 * s, 0, 1); end
            local tk3 = font(10 * s);
            text(dl, tx0 + (tw_ - tw(t[2])) / 2, ty0 + 3 * s, t[2], sel and C.text or C.muted, a);
            unfont(tk3);
            if hv then
                pcall(imgui.SetTooltip, t[3]);
                if imgui.IsMouseClicked(0) then SW_.bag, SW_.off = t[1], 0; end
            end
        end
        -- rows
        local ry0 = y + HEAD + TABS;
        local hover = nil;
        tk = font(14.5 * s);
        for i = 1, NROWS do
            local it = items[SW_.off + i];
            if it == nil then break; end
            local yy = ry0 + (i - 1) * RH;
            local hv = hov_win and not UI.move and inside(mx, my, x + 6 * s, yy, x + W - 6 * s, yy + RH);
            if hv then hover = SW_.off + i; end
            local on = (it.id == worn_id);
            if padcur == SW_.off + i then                            -- (the controller's cursor)
                local p1, p2 = col(C.pink, 0.40 * a), U4(C.vio[1], C.vio[2], C.vio[3], 0.0);
                DL.RFM(dl, x + 8 * s, yy + 1, x + W - 8 * s, yy + RH - 1, p1, p2, p2, p1);
                local ar = tex('sel_arrow.png');
                local asz = 14 * s;
                local bob = cfg.anim and math.sin(now * 5) * 1.5 * s or 0;
                image(dl, ar, x - asz * 0.55 + bob, yy + (RH - asz) / 2, x + asz * 0.45 + bob, yy + (RH + asz) / 2, a);
            end
            if on then
                local p1, p2 = col(C.pink, 0.30 * a), U4(C.vio[1], C.vio[2], C.vio[3], 0.0);
                DL.RFM(dl, x + 8 * s, yy + 1, x + W - 8 * s, yy + RH - 1, p1, p2, p2, p1);
                DL.RF(dl, x + 8 * s, yy + 4, x + 10.5 * s, yy + RH - 4, col(C.pink, a), 2);
            elseif hv then
                DL.RF(dl, x + 8 * s, yy + 1, x + W - 8 * s, yy + RH - 1, U4(1, 1, 1, 0.07 * a), 4 * s);
            end
            if SW_.flash and SW_.flash.id == it.id and now - SW_.flash.t < 0.6 then
                local f = 1 - (now - SW_.flash.t) / 0.6;
                DL.RF(dl, x + 8 * s, yy + 1, x + W - 8 * s, yy + RH - 1, col(C.pink, 0.35 * f * a), 4 * s);
            end
            local is = RH - 6 * s;
            image(dl, item_icon(it.id), x + 18 * s, yy + 3 * s, x + 18 * s + is, yy + 3 * s + is, it.can and a or a * 0.45);
            local tx = x + 18 * s + is + 8 * s;
            local c_ = on and C.text or (it.can and (hv and C.text or { 0.84, 0.82, 0.92, 1 }) or C.dim);
            text(dl, tx, yy + (RH - imgui.GetTextLineHeight()) / 2, it.name, c_, a);
            local tag = on and 'ON' or (it.worn and 'WORN' or BAGS[it.bag][3]);
            local tk2 = font(11 * s);
            local tgw = tw(tag) + 10 * s;
            local tgx = x + W - 16 * s - tgw;
            local tgc = on and C.pink or (it.worn and C.vio or C.acc);
            DL.RF(dl, tgx, yy + RH / 2 - 7 * s, tgx + tgw, yy + RH / 2 + 7 * s, col(tgc, 0.14 * a), 6 * s);
            text(dl, tgx + 5 * s, yy + RH / 2 - 6.5 * s, tag, tgc, a);
            unfont(tk2);
        end
        unfont(tk);
        if #items > NROWS then                                       -- scroll bar
            local tx0, t0, t1 = x + W - 6 * s, ry0, ry0 + NROWS * RH;
            DL.RF(dl, tx0, t0, tx0 + 2 * s, t1, U4(1, 1, 1, 0.06 * a), 2);
            local h_ = (t1 - t0) * NROWS / #items;
            local o_ = (t1 - t0 - h_) * SW_.off / math.max(1, #items - NROWS);
            DL.RF(dl, tx0, t0 + o_, tx0 + 2 * s, t0 + o_ + h_, mix(C.pink, C.vio, 0.5, 0.9 * a), 2);
        end
        tk = font(12 * s);
        text(dl, x + 16 * s, y + H - 22 * s, padcur and 'Confirm: equip   Cancel: back   Left / Right: bag' or 'Click: equip   Wheel: scroll   Grey: not for your job', C.dim, a);
        unfont(tk);
        if padcur and items[padcur] then UI.list_pick = items[padcur].id; end
        if hover then UI.list_pick = items[hover].id; end
        if hov_win and not UI.move then
            if hover and imgui.IsMouseClicked(0) then
                local it = items[hover];
                equip_piece(slot, it);
                SW_.flash = { id = it.id, t = now };
            end
            local wheel = imgui.GetIO().MouseWheel or 0;
            if wheel ~= 0 then SW_.off = SW_.off + ((wheel > 0) and -3 or 3); end
        end
    end
    imgui.End();
    UI.began = false;
    imgui.PopStyleVar(2);
    UI.pushed = 0;
end


----------------------------------------------------------------------------------------------------
-- Magic / Abilities / Items / Key Items: ChadcoreMenu's own panels, built from your character's data (like the swap
-- menu). Mouse: click one of those in the main menu. Keyboard / pad: the game's own window opens as always and this
-- panel opens beside it. /cmenu magic | abilities | items | keyitems opens one by itself (bind it to a key).
----------------------------------------------------------------------------------------------------
-- Blue Magic: set spells. Done the way Ashita's own blusets addon does it (GPL): the game's own function that the
-- Set Spells screen uses (it queues the packet properly), and the set spells / blue points read from the game's memory.
pcall(ffi.cdef, 'typedef uint8_t (__cdecl *ccm_equipex_t)(uint8_t isSubJob, uint16_t jobType, uint16_t index, uint8_t id);');
local BLU = { ok = nil };
function BLU.init()
    if BLU.ok ~= nil then return BLU.ok; end
    BLU.ok = false;
    local o = ashita.memory.find('FFXiMain.dll', 0, 'C1E1032BC8B0018D????????????B9????????F3A55F5E5B', 10, 0);
    local pt = ashita.memory.find('FFXiMain.dll', 0, 'A1????????33C98A4E5E33D28A565D5F5E8950148948185B83C414C20400', 1, 0);
    local eq = ashita.memory.find('FFXiMain.dll', 0, '8B0D????????81EC9C00000085C95356570F??????????8B', 0, 0);
    if (o or 0) == 0 or (pt or 0) == 0 or (eq or 0) == 0 then M.note('blu', 'blue magic functions not found'); return false; end
    BLU.offset = ffi.cast('uint32_t*', o);
    BLU.points = ffi.cast('uint8_t***', pt);
    BLU.equipex = ffi.cast('ccm_equipex_t', eq);
    BLU.ok = true;
    return true;
end
function BLU.main() local j = 0; pcall(function() j = AshitaCore:GetMemoryManager():GetPlayer():GetMainJob(); end); return j == 16; end
function BLU.sub() local j = 0; pcall(function() j = AshitaCore:GetMemoryManager():GetPlayer():GetSubJob(); end); return j == 16; end
function BLU.spells()                                                -- the 20 set-spell slots (spell id - 512, 0 = empty)
    local out = {};
    if not BLU.init() then return out; end
    pcall(function()
        local ptr = ashita.memory.read_uint32(AshitaCore:GetPointerManager():Get('inventory'));
        if ptr == 0 then return; end
        ptr = ashita.memory.read_uint32(ptr);
        if ptr == 0 then return; end
        local base = ptr + BLU.offset[0] + (BLU.main() and 0x04 or 0xA0);
        for i = 0, 19 do out[i + 1] = ashita.memory.read_uint8(base + i); end
    end);
    return out;
end
function BLU.points_used_max()
    local used, max = nil, nil;
    if not BLU.init() then return nil, nil; end
    pcall(function() used, max = BLU.points[0][0][0x14], BLU.points[0][0][0x18]; end);
    return tonumber(used), tonumber(max);
end
function BLU.set(slot, id)                                           -- slot 1-20, id = spell id - 512 (0 = unset)
    if not BLU.init() then msg('Blue magic: could not reach the game\'s set-spell function.'); return; end
    local ok, err = pcall(function() BLU.equipex(BLU.main() and 0 or 1, 0x1000, slot - 1, id); end);
    M.note('blu', ('slot %d -> %d %s'):format(slot, id, ok and 'sent' or ('FAILED ' .. tostring(err))));
end

-- A chain of the game's own menu steps: { { window, button } ... } - each step waits for that window to have the focus,
-- puts the game's cursor on the button and presses OK. Used to open the game's merit categories from the Status panel.
UI.chain = nil;
function start_chain(steps, label)
    UI.chain = { steps = steps, i = 1, t = os.clock(), at = 0, label = label };
    M.note('chain', 'start ' .. (label or ''));
end
local function chain_tick()
    local C_ = UI.chain;
    if C_ == nil then return; end
    local now = os.clock();
    if now - C_.t > 3 then M.note('chain', 'stopped at step ' .. C_.i .. ' (' .. tostring(C_.steps[C_.i] and C_.steps[C_.i][1]) .. ')'); UI.chain = nil; return; end
    local st = C_.steps[C_.i];
    if st == nil then M.note('chain', 'done ' .. (C_.label or '')); UI.chain = nil; return; end
    if now < C_.at then return; end
    local fw = M.open[M.focus or 0];
    if fw and fw.name == st[1] then
        local btn = st[2];
        if type(btn) == 'function' then btn = btn(fw); end
        M.act(fw.addr, btn, KEY.ok);
        C_.i, C_.at = C_.i + 1, now + 0.2;
    end
end
-- after switching the merit mode: check with the game that it really switched
local function verify_tick()
    local V = UI.verify;
    if V == nil or UI.chain or os.clock() < V.at then return; end
    UI.verify = nil;
    local on = nil;
    pcall(function() on = AshitaCore:GetMemoryManager():GetPlayer():GetIsLimitModeEnabled(); end);
    on = (on == true or on == 1);
    if on == V.want then
        M.note('limitmode', 'switched to ' .. (on and 'limit points' or 'experience'));
        msg('Now earning ' .. (on and 'limit points.' or 'experience points.'));
    else
        cfg.merit2_flip = not cfg.merit2_flip; save();             -- (it picked the mode you already had: the other option next time)
        M.note('limitmode', 'did not switch; next time the other option');
        msg('The mode did not change. Press Earning once more (it will pick the other option).');
    end
end
-- the special rows' actions ('@...' instead of a command)
local function special_action(cmd)
    local eb, ei, es = cmd:match('^@equipuse:(%d+):(%d+):(%d+)$');
    if eb then                                                       -- (usable gear that isn't on: put it on)
        eb, ei, es = tonumber(eb), tonumber(ei), tonumber(es);
        local bi = nil;
        for b_, d in ipairs(BAGS) do if d[1] == eb then bi = b_; end end
        local nm = '?';
        pcall(function() local it = AshitaCore:GetMemoryManager():GetInventory():GetContainerItem(eb, ei); local r_ = AshitaCore:GetResourceManager():GetItemById(it.Id); nm = (r_ and r_.Name and r_.Name[1]) or '?'; end);
        if bi then
            equip_piece(es, { idx = ei, bag = bi, name = nm });
            msg(('Put on %s: use it from this list once it is ready.'):format(nm));
            UI.br.cache = {};
        end
        return;
    end
    if cmd == '@blustage' and UI.browse then UI.browse.stage = 'bluset'; return; end
    local mb, mi, md, mn = cmd:match('^@move:(%d+):(%d+):(%d+):(%d+)$');
    if mb then                                                       -- move a stack between bags: the game's own request, packet 0x29
        mb, mi, md, mn = tonumber(mb), tonumber(mi), tonumber(md), tonumber(mn);
        local ok = pcall(function()
            AshitaCore:GetPacketManager():AddOutgoingPacket(0x29, { 0, 0, 0, 0, bit.band(mn, 0xFF), bit.band(bit.rshift(mn, 8), 0xFF), 0, 0, mb, md, mi, 0x52 });
        end);
        M.note('move', ('%d x%d from bag %d slot %d to bag %d %s'):format(mn, mn, mb, mi, md, ok and 'sent' or 'FAILED'));
        UI.br.cache = {};
        return;
    end
    local uslot = cmd:match('^@bluunset:(%d+)$');
    if uslot then BLU.set(tonumber(uslot), 0); return; end
    local sid = cmd:match('^@bluset:(%d+)$');
    if sid then
        sid = tonumber(sid);
        local set = BLU.spells();
        for i, v in ipairs(set) do if v == sid then BLU.set(i, 0); return; end end   -- (already set: unset it)
        for i, v in ipairs(set) do if v == 0 then BLU.set(i, sid); return; end end
        msg('Blue magic: every slot is full - unset one first.');
        return;
    end
    local mgn = cmd:match('^@mgtab:(%d)$');
    if mgn and UI.browse then                                        -- a kind of magic from the action menu's Magic: its spells
        UI.browse.stage = 'list';
        UI.br.tab.magic = tonumber(mgn);
        UI.br.cur['magic:' .. mgn] = 1;
        return;
    end
    local tabn = cmd:match('^@abtab:(%d)$');
    if tabn and UI.browse then                                       -- a category of the combat Abilities menu: its list
        UI.browse.stage = 'list';
        UI.br.tab.abilities = tonumber(tabn);
        UI.br.cur['abilities:' .. tabn] = 1;
        return;
    end
    if cmd == '@ranged' then
        pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/ra <t>'); end);
        M.note('browse', '/ra <t>');
        if close_browse then close_browse(); end
        return;
    end
    if cmd == '@limitmode' then
        local on = nil;
        pcall(function() on = AshitaCore:GetMemoryManager():GetPlayer():GetIsLimitModeEnabled(); end);
        on = (on == true or on == 1);
        -- the mode screen has two options; its cursor starts on the mode you have, so the other one switches
        -- (cfg.merit2_flip: learned the other way round, if checking showed that)
        local pick = function(w) local other = (w.cursor == 1) and 2 or 1; if cfg.merit2_flip then return (other == 1) and 2 or 1; end return other; end;
        local fw = M.open[M.focus or 0];
        local nm = fw and fw.name or '';
        if nm == 'statcom2' then start_chain({ { 'statcom2', 7 }, { 'merit1', 2 }, { 'merit2', pick } }, 'merit mode');
        elseif nm == cfg.main_name then start_chain({ { cfg.main_name, 1 }, { 'statcom2', 7 }, { 'merit1', 2 }, { 'merit2', pick } }, 'merit mode');
        else msg('Open the main menu first, then Earning.'); return; end
        UI.verify = { want = not on, at = os.clock() + 1.5 };
        UI.browse = nil;
        return;
    end
    if cmd == '@meritcat' then
        local fw = M.open[M.focus or 0];
        local nm = fw and fw.name or '';
        if nm == 'statcom2' then start_chain({ { 'statcom2', 7 }, { 'merit1', 1 } }, 'merit categories');
        elseif nm == cfg.main_name then start_chain({ { cfg.main_name, 1 }, { 'statcom2', 7 }, { 'merit1', 1 } }, 'merit categories');
        else msg('Open the main menu first, then Merit categories.'); return; end
        UI.browse = nil;                                             -- (the game's merit screens take over; Status comes back after)
    end
end
-- closing one of these panels: it stays closed while the game window it opened beside is still there, and that game
-- window is backed out of too (as closing a menu in the game would)
UI.dismissed = {};
function close_browse()
    local B = UI.browse;
    if B and B.via == 'game' then
        if B.gw_addr then UI.dismissed[B.gw_addr] = B.gw_name or true; end
        UI.close_game = { kind = B.kind, tries = 6, at = 0 };
    end
    UI.browse = nil;
end
BROWSE_KIND = { ['Status'] = 'status', ['Magic'] = 'magic', ['Abilities'] = 'abilities', ['Items'] = 'items', ['Key Items'] = 'keyitems' };
local BROWSE_TITLE = { status = 'STATUS', magic = 'MAGIC', abilities = 'ABILITIES', items = 'ITEMS', keyitems = 'KEY ITEMS' };
local ELEMC = { [0] = { 1.00, 0.36, 0.30 }, { 0.50, 0.85, 1.00 }, { 0.40, 0.95, 0.50 }, { 1.00, 0.85, 0.30 },
                { 0.80, 0.50, 1.00 }, { 0.35, 0.50, 1.00 }, { 1.00, 1.00, 0.95 }, { 0.45, 0.40, 0.55 } };
local MAGIC_TABS = { { 1, 'WHITE' }, { 2, 'BLACK' }, { 3, 'SUMMON' }, { 4, 'NINJA' }, { 5, 'SONG' }, { 6, 'BLUE' }, { 7, 'GEO' }, { 8, 'TRUST' } };
local ITEM_BAGS = { { 0, 'INV', 'Inventory' }, { 1, 'SAFE', 'Mog Safe' }, { 9, 'SAFE2', 'Mog Safe 2' }, { 2, 'STORE', 'Storage' },
                    { 4, 'LOCKR', 'Mog Locker' }, { 5, 'SATCH', 'Mog Satchel' }, { 6, 'SACK', 'Mog Sack' }, { 7, 'CASE', 'Mog Case' },
                    { 3, 'TEMP', 'Temporary Items' }, { 8, 'W1', 'Mog Wardrobe' }, { 10, 'W2', 'Mog Wardrobe 2' }, { 11, 'W3', 'Mog Wardrobe 3' },
                    { 12, 'W4', 'Mog Wardrobe 4' }, { 13, 'W5', 'Mog Wardrobe 5' }, { 14, 'W6', 'Mog Wardrobe 6' }, { 15, 'W7', 'Mog Wardrobe 7' },
                    { 16, 'W8', 'Mog Wardrobe 8' } };
UI.br = { tab = {}, off = {}, sel = {}, cur = {}, cache = {} };
local function rname(r) return (r and r.Name and r.Name[1]) or nil; end
local function rdesc(r) return clean((r and r.Description and r.Description[1]) or ''); end
-- who a spell / ability goes on: an enemy -> <t>, a party member -> <stpc>, else yourself
local function target_for(r)
    local t = tonumber(r and (r.Targets or r.ValidTargets)) or 0;
    if bit.band(t, 0x20) ~= 0 then return '<t>'; end
    if bit.band(t, 0x04) ~= 0 or bit.band(t, 0x08) ~= 0 then return '<stpc>'; end
    return '<me>';
end
local function job_lv()
    local j, l, sj, sl = 0, 0, 0, 0;
    pcall(function() local pl = AshitaCore:GetMemoryManager():GetPlayer(); j, l, sj, sl = pl:GetMainJob(), pl:GetMainJobLevel(), pl:GetSubJob(), pl:GetSubJobLevel(); end);
    return j, l, sj, sl;
end
local function cached(key, secs, fn)
    local c = UI.br.cache[key];
    local now = os.clock();
    if c and now - c.at < secs then return c.v; end
    local ok, v = pcall(fn);
    v = ok and v or {};
    UI.br.cache[key] = { at = now, v = v };
    return v;
end
-- rows: { name, right, color dot, icon id, dim, cmd, desc }
local function magic_rows(tabid)
    local all = cached('magic', 3, function()
        local out = {};
        local pl = AshitaCore:GetMemoryManager():GetPlayer();
        local res = AshitaCore:GetResourceManager();
        local j, l, sj, sl = job_lv();
        for id = 1, 1023 do
            local has = false;
            pcall(function() has = pl:HasSpell(id); end);
            if has then
                local r = res:GetSpellById(id);
                local nm = rname(r);
                if nm and nm ~= '' then
                    local lr = r.LevelRequired;
                    local need, needs = nil, nil;
                    pcall(function() need = tonumber(lr[j + 1]); needs = tonumber(lr[sj + 1]); end);
                    local can = (need and need > 0 and need <= l) or (needs and needs > 0 and needs <= sl);
                    local typ = tonumber(r.Type) or 0;
                    if typ == 8 then can = true; end                -- (trusts)
                    if can then
                        local lvl = nil;
                        if need and need > 0 and need <= l then lvl = need; end
                        if needs and needs > 0 and needs <= sl and (lvl == nil or needs < lvl) then lvl = needs; end
                        out[#out + 1] = { id = id, type = typ, name = nm, mp = tonumber(r.ManaCost) or 0, elem = tonumber(r.Element), r = r, lv = lvl };
                    end
                end
            end
        end
        table.sort(out, function(p, q) return p.id < q.id; end);
        return out;
    end);
    local rc = nil;
    pcall(function() rc = AshitaCore:GetMemoryManager():GetRecast(); end);
    local mp = 0;
    pcall(function() mp = AshitaCore:GetMemoryManager():GetParty():GetMemberMP(0) or 0; end);
    local rows, have = {}, {};
    for _, e in ipairs(all) do
        have[e.type] = true;
        if e.type == tabid then
            local left = 0;
            pcall(function() left = (rc and rc:GetSpellTimer(e.id)) or 0; end);
            local right = (left > 0) and (('%ds'):format(math.ceil(left / 60))) or ((e.mp > 0) and ('MP ' .. e.mp) or '');
            local ready = not (left > 0 or e.mp > mp);
            rows[#rows + 1] = { e.name, right, ELEMC[e.elem] or (ready and { 0.40, 1.0, 0.55, 1 } or nil), nil, not ready,
                ('/ma "%s" %s'):format(e.name, target_for(e.r)), rdesc(e.r), spell = e.id, ready = ready, glow = ready, n = #rows + 1, lv = e.lv };
        end
    end
    table.sort(rows, function(p, q)                                  -- (castable now first, with a glowing dot; each group in the
        if p.ready ~= q.ready then return p.ready; end               --  game's order)
        return p.n < q.n;
    end);
    return rows, have;
end
local keyitem_rows;
local function ability_rows(tabid)
    local all = cached('abil', 3, function()
        local out = {};
        local pl = AshitaCore:GetMemoryManager():GetPlayer();
        local res = AshitaCore:GetResourceManager();
        for id = 1, 255 do                                           -- weapon skills
            local has = false;
            pcall(function() has = pl:HasWeaponSkill(id); end);
            if has then
                local r = res:GetAbilityById(id);
                local nm = rname(r);
                if nm and nm ~= '' then out[#out + 1] = { tab = 2, name = nm, r = r, cmd = ('/ws "%s" <t>'):format(nm) }; end
            end
        end
        -- job abilities and pet commands: the game's ability ids from 0x200 (Ashita's numbering). The game only marks the
        -- ones your main / sub job can use at your levels. (Asking for id - 0x200 as well used to add wrong ones: those
        -- bits are weapon skills; it's only used if nothing at all answers to the real ids.)
        -- (the game's menu headings - Sambas, Waltzes, Steps, Phantom Roll, Blood Pact: Rage... - count as abilities too, but
        --  aren't ones you can use: left out, as tCrossBar does)
        local HEADINGS = { [567] = true, [603] = true, [609] = true, [636] = true, [684] = true, [694] = true, [695] = true, [710] = true,
                           [711] = true, [712] = true, [725] = true, [735] = true, [763] = true, [775] = true, [869] = true, [891] = true, [892] = true };
        local cand = { d = {}, o = {} };
        local nd, no = 0, 0;
        for id = 0x200, 0x7FF do
            local r = nil;
            pcall(function() r = res:GetAbilityById(id); end);
            local nm = rname(r);
            if r and tonumber(r.Id) and tonumber(r.Id) ~= id then id = tonumber(r.Id); end
            if nm and nm ~= '' and not HEADINGS[id] then
                local typ = tonumber(r.Type) or -1;
                for _, v in ipairs({ { 'd', id }, { 'o', id - 0x200 } }) do
                    local pet, ja = false, false;
                    pcall(function() pet = pl:HasPetCommand(v[2]); end);
                    if not pet and (typ == 2 or typ == 6 or typ == 7) then pcall(function() pet = pl:HasAbility(v[2]); end); end
                    if not pet then pcall(function() ja = pl:HasAbility(v[2]); end); end
                    local L = cand[v[1]];
                    if (pet or ja) and id >= 0x600 then              -- (from 0x600 the game's ids are traits: listed on their own)
                        local dup = false;
                        for _, e in ipairs(L) do if e.tab == 5 and e.name == nm then dup = true; end end
                        if not dup then L[#L + 1] = { tab = 5, name = nm, r = r }; end
                    elseif pet then L[#L + 1] = { tab = 3, name = nm, r = r, cmd = ('/pet "%s" <t>'):format(nm) };
                    elseif ja then L[#L + 1] = { tab = 1, name = nm, r = r, cmd = ('/ja "%s" %s'):format(nm, target_for(r)) }; end
                    if (pet or ja) then if v[1] == 'd' then nd = nd + 1; else no = no + 1; end end
                end
            end
        end
        local use = (nd > 0) and cand.d or cand.o;
        local n_ja, n_pet = 0, 0;
        for _, e in ipairs(use) do out[#out + 1] = e; if e.tab == 1 then n_ja = n_ja + 1; elseif e.tab == 3 then n_pet = n_pet + 1; end end
        local pc_ok, pc_err = 0, nil;
        M.note('abilities_ids', ('by real id %d, by id-0x200 %d: using %s'):format(nd, no, (nd > 0) and 'real ids' or 'id-0x200'));
        M.note('abilities', ('job abilities %d, pet commands %d (pet check worked %d times%s)'):format(n_ja, n_pet, pc_ok, pc_err and (', error: ' .. pc_err) or ''));
        return out;
    end);
    if tabid == 4 then                                               -- General: ranged attack, your mounts, dismount
        local rows = {};
        local ranged = false;
        pcall(function() local g = gear(); ranged = (g[2] ~= nil) or (g[3] ~= nil); end);
        rows[#rows + 1] = { 'Ranged Attack', ranged and '' or 'no ranged', nil, nil, not ranged, '/ra <t>', 'Shoot or throw at your target with your ranged weapon or ammo.' };
        -- your mounts: the mount key items (the block from id 3072, each starting with a note mark), in the game's order.
        -- The name the game's mount list shows is the key item's, without the mark and "companion" / "whistle"
        -- (a few differ in the game data: MOUNT_FIX).
        local MOUNT_FIX = { cyakko = 'Gyokko' };
        local mounts = {};
        for _, k in ipairs(keyitem_rows()) do
            local id = tonumber(k.id) or -1;
            if id >= 3072 and id < 3400 and (k.raw or ''):byte(1) and (k.raw or ''):byte(1) >= 0x80 then
                local m = (k[1] or ''):gsub('^[^%a]+', ''):gsub('%s+[Cc]ompanion$', ''):gsub('%s+[Ww]histle$', '');
                m = MOUNT_FIX[m:lower()] or m;
                if m ~= '' then mounts[#mounts + 1] = { id, (m:gsub('^%l', string.upper)) }; end
            end
        end
        table.sort(mounts, function(p, q) return p[1] < q[1]; end);
        for _, m in ipairs(mounts) do
            rows[#rows + 1] = { 'Mount: ' .. m[2], '', nil, nil, false, ('/mount "%s"'):format(m[2]), 'Call your ' .. m[2] .. ' to ride.' };
        end
        rows[#rows + 1] = { 'Dismount', '', nil, nil, false, '/dismount', 'Get off your mount.' };
        return rows, { [4] = true };
    end
    local rc = nil;
    pcall(function() rc = AshitaCore:GetMemoryManager():GetRecast(); end);
    local timers = {};
    if rc then for i = 0, 31 do pcall(function() local tid, t = rc:GetAbilityTimerId(i), rc:GetAbilityTimer(i); if (t or 0) > 0 then timers[tid] = t; end end); end end
    local tp = 0;
    pcall(function() tp = AshitaCore:GetMemoryManager():GetParty():GetMemberTP(0) or 0; end);
    local rows, have = {}, {};
    for _, e in ipairs(all) do
        have[e.tab] = true;
        if e.tab == tabid then
            local tid = tonumber(e.r.RecastTimerId or e.r.TimerId);
            local left = tid and timers[tid] or 0;
            local right = (left > 0) and (('%ds'):format(math.ceil(left / 60))) or ((e.tab == 2) and 'WS' or '');
            local row = { e.name, right, nil, nil, left > 0 or (e.tab == 2 and tp < 1000), e.cmd, rdesc(e.r) };
            if e.tab == 5 then row = { e.name, 'TRAIT', nil, nil, false, nil, rdesc(e.r) };
            elseif e.tab ~= 2 then
                row.sp = (tid == 0 and e.tab == 1);                                 -- (the 1-hour ability: recast timer 0)
                row.ready = (left <= 0);
                if row.ready then row[3], row.glow = row.sp and { 1.0, 0.30, 0.28, 1 } or { 0.40, 1.0, 0.55, 1 }, true; end
                if left > 59 * 60 and row.sp then row[2] = ('%d:%02d'):format(math.floor(left / 3600), math.floor(left / 60) % 60); end
            end
            row.n = #rows + 1;
            rows[#rows + 1] = row;
        end
    end
    if tabid == 1 or tabid == 3 then                                 -- (ready ones first, each group in the game's order)
        table.sort(rows, function(p, q)
            if (p.ready == true) ~= (q.ready == true) then return p.ready == true; end
            return p.n < q.n;
        end);
    end
    return rows, have;
end
local function item_rows(tabi)
    local bag = ITEM_BAGS[tabi][1];
    return cached('items' .. bag, 0.5, function()
        local rows = {};
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        local res = AshitaCore:GetResourceManager();
        for i = 1, 80 do
            local it = inv:GetContainerItem(bag, i);
            if it and (it.Id or 0) ~= 0 and it.Id ~= 65535 then
                local r = res:GetItemById(it.Id);
                local nm = rname(r) or '?';
                rows[#rows + 1] = { nm, ((it.Count or 1) > 1) and ('x' .. it.Count) or ((it.Flags == 5) and 'WORN' or ''), nil, it.Id, false,
                    ('/item "%s" <me>'):format(nm), rdesc(r), id = it.Id, bag = bag, idx = i, count = it.Count or 1, lv = r and tonumber(r.Level) };
            end
        end
        return rows;
    end), nil;
end
keyitem_rows = function()
    return cached('ki', 5, function()
        local rows = {};
        local pl = AshitaCore:GetMemoryManager():GetPlayer();
        local res = AshitaCore:GetResourceManager();
        local dump = {};
        for id = 0, 4095 do
            local has = false;
            pcall(function() has = pl:HasKeyItem(id); end);
            if has then
                local nm, nb, na = nil, nil, nil;
                pcall(function() nm = res:GetString('keyitems.names', id); end);
                pcall(function() nb = res:GetString('keyitems.names', id - 1); na = res:GetString('keyitems.names', id + 1); end);
                dump[#dump + 1] = ('%5d  %-40s | id-1: %-32s | id+1: %s'):format(id, tostring(nm), tostring(nb), tostring(na));
                if nm and nm ~= '' then
                    local shown = clean(nm):gsub('^%s+', '');
                    rows[#rows + 1] = { shown, '', nil, nil, false, nil, '', id = id, raw = nm };
                end
            end
        end
        -- chadcoremenu-keyitems.txt: what the game says you have (to check names line up), once per change
        local sig = #dump .. ':' .. (dump[1] or '') .. (dump[#dump] or '');
        if sig ~= UI.ki_sig then
            UI.ki_sig = sig;
            pcall(function()
                local f = io.open(addon.path .. 'chadcoremenu-keyitems.txt', 'w');
                if f then f:write(('ChadcoreMenu %s key items  %s\n'):format(addon.version, os.date()) .. table.concat(dump, '\n') .. '\n'); f:close(); end
            end);
        end
        table.sort(rows, function(p, q) return p[1] < q[1]; end);
        return rows;
    end), nil;
end

-- An item as a floating tooltip card in the new look, beside the mouse (drawn over everything)
-- anchor (optional): { x, y below the item, y above the item } - the card goes right under the item, or just above
-- it when there's no room below
item_tooltip = function(id, mx, my, anchor, ext, bag, idx)
    local info = item_info(id);
    if info == nil then return; end
    local s = PSCALE() * (UI.tip_scale or 1);      -- (UI.tip_scale: a bigger card where there's room, e.g. an NPC's item list)
    local fg = imgui.GetForegroundDrawList();
    local sw, sh = screen();
    local W = math.floor(300 * s);
    local tk = font(13 * s);
    local lines = wrap(info.desc, W - 32 * s);
    local jl = wrap(info.jobs, W - 32 * s);
    local al = {};
    for _, a_ in ipairs(aug_lines(ext, id, bag, idx) or {}) do for _, w_ in ipairs(wrap(a_, W - 32 * s)) do al[#al + 1] = w_; end end
    unfont(tk);
    local H = math.floor((58 + #lines * 16 + #jl * 15 + 14 + ((#al > 0) and (#al * 16 + 6) or 0)) * s);
    local x, y = mx + 22 * s, my + 8 * s;
    if anchor then
        x, y = anchor[1], anchor[2];
        if y + H > sh - 4 then y = anchor[3] - H; end
    else
        if x + W > sw - 4 then x = mx - W - 16 * s; end
        if y + H > sh - 4 then y = sh - H - 4; end
    end
    if x + W > sw - 4 then x = sw - W - 4; end
    x, y = math.max(4, x), math.max(4, y);
    local ac = info.rare and C.gold or (info.ex and C.acc or { 0.45, 0.70, 1.0, 1 });
    for i = 3, 1, -1 do DL.RF(fg, x - i * 2, y - i * 2 + 3, x + W + i * 2, y + H + i * 2 + 3, U4(0, 0, 0, 0.08), 10 * s + i * 2); end
    DL.RF(fg, x, y, x + W, y + H, U4(0.045, 0.040, 0.065, 0.97), 9 * s);
    DL.R(fg, x, y, x + W, y + H, U4(0.62, 0.40, 1.0, 0.45), 9 * s, 0, 1);
    local p1, p2 = col(C.pink, 0.9), col(C.vio, 0.9);
    DL.RFM(fg, x + 10 * s, y, x + W - 10 * s, y + 2, p1, p2, p2, p1);
    DL.RF(fg, x + 6 * s, y + 12 * s, x + 8.5 * s, y + H - 12 * s, col(ac, 1), 2);
    local is = 34 * s;
    DL.RF(fg, x + 16 * s, y + 12 * s, x + 16 * s + is, y + 12 * s + is, U4(1, 1, 1, 0.06), 6 * s);
    image(fg, item_icon(id), x + 16 * s, y + 12 * s, x + 16 * s + is, y + 12 * s + is, 1);
    local tx = x + 16 * s + is + 10 * s;
    tk = font(15.5 * s);
    text(fg, tx, y + 10 * s, info.name, { 0.62, 1.0, 0.70, 1 }, 1);
    local px = tx + tw(info.name) + 8 * s;
    unfont(tk);
    tk = font(10.5 * s);
    for _, pill in ipairs({ { info.rare, 'RARE', C.gold }, { info.ex, 'EX', C.acc } }) do
        if pill[1] and px + tw(pill[2]) + 12 * s < x + W - 8 * s then
            local pw = tw(pill[2]) + 10 * s;
            DL.RF(fg, px, y + 13 * s, px + pw, y + 26 * s, col(pill[3], 0.18), 6 * s);
            text(fg, px + 5 * s, y + 13.5 * s, pill[2], pill[3], 1);
            px = px + pw + 4 * s;
        end
    end
    unfont(tk);
    tk = font(12.5 * s);
    local sub = info.races .. ((info.lv ~= '') and ('   ' .. info.lv) or '');
    text(fg, tx, y + 30 * s, sub, C.muted, 1);
    unfont(tk);
    tk = font(13 * s);
    local yy = y + 54 * s;
    for _, ln in ipairs(lines) do ETEXT(fg, x + 16 * s, yy, ln, C.text, 1); yy = yy + 16 * s; end
    if #al > 0 then                                                  -- (augments, in their own colour)
        yy = yy + 4 * s;
        for _, ln in ipairs(al) do text(fg, x + 16 * s, yy, ln, { 0.45, 0.85, 1.0, 1 }, 1); yy = yy + 16 * s; end
        yy = yy + 2 * s;
    end
    unfont(tk);
    tk = font(12 * s);
    yy = yy + 2 * s;
    for _, ln in ipairs(jl) do text(fg, x + 16 * s, yy, ln, C.acc, 0.9); yy = yy + 15 * s; end
    unfont(tk);
end

-- Status: Profile, Jobs, Combat / Magic / Crafting skills, Merits - all from your character's data
local STATUS_TABS = { { 1, 'PROFILE', 'Profile' }, { 2, 'JOBS', 'Job levels' }, { 3, 'COMBAT', 'Combat skills' },
                      { 4, 'MAGIC', 'Magic skills' }, { 5, 'CRAFT', 'Crafting skills' }, { 6, 'MERITS', 'Merit points' } };
local JOBNAMES = { 'Warrior', 'Monk', 'White Mage', 'Black Mage', 'Red Mage', 'Thief', 'Paladin', 'Dark Knight', 'Beastmaster', 'Bard',
                   'Ranger', 'Samurai', 'Ninja', 'Dragoon', 'Summoner', 'Blue Mage', 'Corsair', 'Puppetmaster', 'Dancer', 'Scholar', 'Geomancer', 'Rune Fencer' };
local COMBAT_SK = { { 1, 'Hand-to-Hand' }, { 2, 'Dagger' }, { 3, 'Sword' }, { 4, 'Great Sword' }, { 5, 'Axe' }, { 6, 'Great Axe' }, { 7, 'Scythe' },
                    { 8, 'Polearm' }, { 9, 'Katana' }, { 10, 'Great Katana' }, { 11, 'Club' }, { 12, 'Staff' }, { 25, 'Archery' },
                    { 26, 'Marksmanship' }, { 27, 'Throwing' }, { 28, 'Guard' }, { 29, 'Evasion' }, { 30, 'Shield' }, { 31, 'Parrying' },
                    { 22, 'Automaton Melee' }, { 23, 'Automaton Archery' }, { 24, 'Automaton Magic' } };
local MAGIC_SK = { { 32, 'Divine Magic' }, { 33, 'Healing Magic' }, { 34, 'Enhancing Magic' }, { 35, 'Enfeebling Magic' }, { 36, 'Elemental Magic' },
                   { 37, 'Dark Magic' }, { 38, 'Summoning Magic' }, { 39, 'Ninjutsu' }, { 40, 'Singing' }, { 41, 'String Instrument' },
                   { 42, 'Wind Instrument' }, { 43, 'Blue Magic' }, { 44, 'Geomancy' }, { 45, 'Handbell' } };
local CRAFT_SK = { { 0, 'Fishing' }, { 1, 'Woodworking' }, { 2, 'Smithing' }, { 3, 'Goldsmithing' }, { 4, 'Clothcraft' },
                   { 5, 'Leathercraft' }, { 6, 'Bonecraft' }, { 7, 'Alchemy' }, { 8, 'Cooking' }, { 9, 'Synergy' } };
local CRAFT_RANK = { [0] = 'Amateur', 'Recruit', 'Initiate', 'Novice', 'Apprentice', 'Journeyman', 'Craftsman', 'Artisan', 'Adept', 'Veteran', 'Expert' };
local RACES = { 'Hume', 'Hume', 'Elvaan', 'Elvaan', 'Tarutaru', 'Tarutaru', 'Mithra', 'Galka' };
local NATIONS = { [0] = 'San d\'Oria', 'Bastok', 'Windurst' };
local function pget(fn) local ok, v = pcall(fn); if ok then return v; end return nil; end
-- a skill's level and whether it's capped (the game's skill entry: a table, an object, or a raw number with the cap bit)
local function skill_of(v)
    if v == nil then return nil, false; end
    if type(v) == 'number' then return bit.band(v, 0x7FFF), bit.band(v, 0x8000) ~= 0; end
    local lv = pget(function() return v:GetSkill(); end) or pget(function() return v.Skill; end);
    local cap = pget(function() return v:IsCapped(); end) or pget(function() return v.Capped; end);
    local rank = pget(function() return v:GetRank(); end) or pget(function() return v.Rank; end);
    return tonumber(lv), cap == true or cap == 1, tonumber(rank);
end
local function status_rows(tabid)
    local rows = {};
    local mm = AshitaCore:GetMemoryManager();
    local pl = pget(function() return mm:GetPlayer(); end);
    if pl == nil then return rows; end
    local j, l, sj, sl = job_lv();
    if tabid == 1 then
        local nm = pget(function() return mm:GetParty():GetMemberName(0); end) or '';
        local function add(k, v, d) rows[#rows + 1] = { k, (v ~= nil and tostring(v) ~= '') and tostring(v) or '--', nil, nil, false, nil, d or '' }; end
        add('Name', nm);
        add('Main job', JOBS[j] and (('%s  Lv.%d'):format(JOBNAMES[j] or JOBS[j], l)) or nil);
        add('Support job', (JOBS[sj] and sl > 0) and (('%s  Lv.%d'):format(JOBNAMES[sj] or JOBS[sj], sl)) or 'None');
        add('Race', RACES[pget(function() return pl:GetRace(); end) or 0]);
        local nat = pget(function() return pl:GetNation(); end);
        add('Nation', NATIONS[nat or -1]);
        local rank = pget(function() return pl:GetRank(); end);
        add('Rank', (rank and rank > 0) and rank or nil);
        local tid = pget(function() return pl:GetTitle(); end);
        local tname = tid and (pget(function() return AshitaCore:GetResourceManager():GetString('titles.names', tid); end)
            or pget(function() return AshitaCore:GetResourceManager():GetString('titles', tid); end)) or nil;
        add('Title', tname and clean(tname) or nil);
        local ec, en = pget(function() return pl:GetExpCurrent(); end), pget(function() return pl:GetExpNeeded(); end);
        add('Experience', (ec and en) and (('%d / %d'):format(ec, en)) or nil, (ec and en and en > 0) and (('%d to the next level'):format(en - ec)) or '');
        add('Max HP / MP', (pget(function() return pl:GetHPMax(); end) or '--') .. ' / ' .. (pget(function() return pl:GetMPMax(); end) or '--'));
        local gil = pget(function() return mm:GetInventory():GetContainerItem(0, 0).Count; end);
        add('Gil', gil and (tostring(gil):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')) or nil);
    elseif tabid == 2 then
        for jid = 1, 22 do
            local lv = pget(function() return pl:GetJobLevel(jid); end) or 0;
            local jp = pget(function() return pl:GetJobPointsSpent(jid); end) or 0;
            local right = (lv > 0) and ('Lv.' .. lv .. ((jp > 0) and ('   JP ' .. jp) or '')) or '--';
            local tag = (jid == j) and '  (main)' or ((jid == sj) and '  (support)' or '');
            rows[#rows + 1] = { (JOBNAMES[jid] or JOBS[jid]) .. tag, right, nil, nil, lv == 0, nil, '' };
        end
    elseif tabid == 3 or tabid == 4 then
        for _, sk in ipairs((tabid == 3) and COMBAT_SK or MAGIC_SK) do
            local lv, cap = skill_of(pget(function() return pl:GetCombatSkill(sk[1]); end));
            if lv and lv > 0 then
                rows[#rows + 1] = { sk[2], tostring(lv) .. (cap and '  CAP' or ''), cap and { 1.0, 0.80, 0.42 } or nil, nil, false, nil,
                    cap and 'Capped for your level.' or '' };
            end
        end
        if #rows == 0 then rows[1] = { 'No skills to show', '', nil, nil, true, nil, '' }; end
    elseif tabid == 5 then
        for _, sk in ipairs(CRAFT_SK) do
            local lv, cap, rank = skill_of(pget(function() return pl:GetCraftSkill(sk[1]); end));
            rows[#rows + 1] = { sk[2], (lv or 0) > 0 and (tostring(lv) .. ((rank and CRAFT_RANK[rank]) and ('  ' .. CRAFT_RANK[rank]) or '')) or '0',
                cap and { 1.0, 0.80, 0.42 } or nil, nil, (lv or 0) == 0, nil, cap and 'Capped for your rank.' or '' };
        end
    elseif tabid == 6 then
        local mp, mx = pget(function() return pl:GetMeritPoints(); end), pget(function() return pl:GetMeritPointsMax(); end);
        local lp = pget(function() return pl:GetLimitPoints(); end);
        local lmode = pget(function() return pl:GetIsLimitModeEnabled(); end);
        rows[#rows + 1] = { 'Merit points', (mp and mx) and (('%d / %d'):format(mp, mx)) or '--', nil, nil, false, nil, '' };
        rows[#rows + 1] = { 'Limit points', lp and (('%d / 10000'):format(lp)) or '--', nil, nil, false, nil, 'Points toward your next merit.' };
        local lon = (lmode == true or lmode == 1);
        if l >= 75 then
            rows[#rows + 1] = { 'Earning: ' .. (lon and 'Limit points' or 'Experience') .. '  >', 'SWITCH', { 1.0, 0.36, 0.62 }, nil, false, '@limitmode',
                'Switch to earning ' .. (lon and 'experience points.' or 'limit points (merits).') };
        else
            rows[#rows + 1] = { 'Earning', lon and 'Limit points' or 'Experience', nil, nil, false, nil, 'You can switch to limit points at level 75.' };
        end
        rows[#rows + 1] = { 'Merit categories  >', 'OPEN', { 1.0, 0.36, 0.62 }, nil, false, '@meritcat', 'Open the game\'s merit categories to spend your merit points.' };
        local jpn = pget(function() return pl:GetJobPoints(j); end);
        if jpn and jpn > 0 then rows[#rows + 1] = { 'Job points (' .. (JOBS[j] or '?') .. ')', tostring(jpn), nil, nil, false, nil, '' }; end
    end
    return rows;
end

-- The Status list's page panel: ChadcoreMenu's own page for the entry picked (Profile, Job Levels, skills, crafts, merits),
-- beside the list; the game's own window for that page is hidden. Pages ChadcoreMenu doesn't have are left to the game.
MYROOM.PAGES = { [1] = 1, [2] = 2, [4] = 3, [5] = 4, [6] = 5, [11] = 6 };
MYROOM.PAGE_WINS = { profile = true, joblevel = true, btlskill = true, mgcskill = true, trdskill = true };
-- the two Currencies pages: packets 0x113 and 0x118, field by field (after LandSandBoat / atom0s XiPackets)
CURRENCY = { [1] = {
    { 'i', "Conquest Points (San d'Oria)" },
    { 'i', 'Conquest Points (Bastok)' },
    { 'i', 'Conquest Points (Windurst)' },
    { 'H', "Beastmen's Seals Stored" },
    { 'H', "Kindred's Seals Stored" },
    { 'H', "Kindred's Crests Stored" },
    { 'H', "High Kindred's Crests Stored" },
    { 'H', "Sacred Kindred's Crests Stored" },
    { 'H', 'Ancient Beastcoins Stored' },
    { 'H', 'Valor Points' },
    { 'H', 'Scylds' },
    { 'i', 'Guild Points (Fishing)' },
    { 'i', 'Guild Points (Woodworking)' },
    { 'i', 'Guild Points (Smithing)' },
    { 'i', 'Guild Points (Goldsmithing)' },
    { 'i', 'Guild Points (Weaving)' },
    { 'i', 'Guild Points (Leathercraft)' },
    { 'i', 'Guild Points (Bonecraft)' },
    { 'i', 'Guild Points (Alchemy)' },
    { 'i', 'Guild Points (Cooking)' },
    { 'i', 'Cinders' },
    { 'B', 'Synergy Fewell (Fire)' },
    { 'B', 'Synergy Fewell (Ice)' },
    { 'B', 'Synergy Fewell (Wind)' },
    { 'B', 'Synergy Fewell (Earth)' },
    { 'B', 'Synergy Fewell (Lightning)' },
    { 'B', 'Synergy Fewell (Water)' },
    { 'B', 'Synergy Fewell (Light)' },
    { 'B', 'Synergy Fewell (Dark)' },
    { 'i', 'Ballista Points' },
    { 'i', 'Fellow Points' },
    { 'H', "Chocobucks (San d'Oria Team)" },
    { 'H', 'Chocobucks (Bastok Team)' },
    { 'H', 'Chocobucks (Windurst Team)' },
    { 'H', 'Daily Tally' },
    { 'i', 'Research Marks' },
    { 'B', 'Wizened Tunnel Worms' },
    { 'B', 'Wizened Morion Worms' },
    { 'B', 'Wizened Phantom Worms' },
    { 'pad', 1 },
    { 'i', 'Moblin Marbles' },
    { 'H', 'Infamy' },
    { 'H', 'Prestige' },
    { 'i', 'Legion Points' },
    { 'i', 'Sparks Of Eminence' },
    { 'i', 'Shining Stars' },
    { 'i', 'Imperial Standing' },
    { 'i', 'Assault Points (Leujaoam Sanctum)' },
    { 'i', 'Assault Points (M.J.T.G.)' },
    { 'i', 'Assault Points (Lebros Cavern)' },
    { 'i', 'Assault Points (Periqia)' },
    { 'i', 'Assault Points (Ilrusi Atoll)' },
    { 'i', 'Tokens' },
    { 'i', 'Zeni' },
    { 'i', 'Jettons' },
    { 'i', 'Therion Ichor' },
    { 'i', 'Allied Notes' },
    { 'H', 'Copper Aman Vouchers Stored' },
    { 'H', 'Login Points' },
    { 'i', 'Cruor' },
    { 'i', 'Resistance Credits' },
    { 'i', 'Dominion Notes' },
    { 'B', 'Echelon Battle Trophies (5th)' },
    { 'B', 'Echelon Battle Trophies (4th)' },
    { 'B', 'Echelon Battle Trophies (3rd)' },
    { 'B', 'Echelon Battle Trophies (2nd)' },
    { 'B', 'Echelon Battle Trophies (1st)' },
    { 'B', 'Cave Conservation Points' },
    { 'B', 'Imperial Army Id Tags' },
    { 'B', 'OP Credits' },
    { 'i', 'Traverser Stones' },
    { 'i', 'Voidstones' },
    { 'i', "Kupofried's Corundums" },
    { 'B', 'Moblin Pheromone Sacks' },
    { 'pad', 1 },
    { 'B', "Rem's Tale Ch. 1 Stored" },
    { 'B', "Rem's Tale Ch. 2 Stored" },
    { 'B', "Rem's Tale Ch. 3 Stored" },
    { 'B', "Rem's Tale Ch. 4 Stored" },
    { 'B', "Rem's Tale Ch. 5 Stored" },
    { 'B', "Rem's Tale Ch. 6 Stored" },
    { 'B', "Rem's Tale Ch. 7 Stored" },
    { 'B', "Rem's Tale Ch. 8 Stored" },
    { 'B', "Rem's Tale Ch. 9 Stored" },
    { 'B', "Rem's Tale Ch. 10 Stored" },
    { 'bits', 9, 'Bloodshed Plans Stored' },
    { 'bits', 9, 'Umbrage Plans Stored' },
    { 'bits', 9, 'Ritualistic Plans Stored' },
    { 'bits', 9, 'Tutelary Plans Stored' },
    { 'bits', 9, 'Primacy Plans Stored' },
    { 'bits', 19, false },
    { 'H', 'Reclamation Marks' },
    { 'pad', 2 },
    { 'i', 'Unity Accolades' },
    { 'H', 'Fire Crystals Stored' },
    { 'H', 'Ice Crystals Stored' },
    { 'H', 'Wind Crystals Stored' },
    { 'H', 'Earth Crystals Stored' },
    { 'H', 'Lightning Crystals Stored' },
    { 'H', 'Water Crystals Stored' },
    { 'H', 'Light Crystals Stored' },
    { 'H', 'Dark Crystals Stored' },
    { 'H', 'Deeds' },
    { 'pad', 2 },
}, [2] = {
    { 'i', 'Bayld' },
    { 'H', 'Kinetic Units' },
    { 'B', 'Coalition Imprimaturs' },
    { 'B', 'Mystical Canteens' },
    { 'i', 'Obsidian Fragments' },
    { 'H', 'Lebondopt Wings Stored' },
    { 'H', 'Pulchridopt Wings Stored' },
    { 'i', 'Mweya Plasm Corpuscles' },
    { 'B', 'Ghastly Stones Stored' },
    { 'B', 'Ghastly Stones +1 Stored' },
    { 'B', 'Ghastly Stones +2 Stored' },
    { 'B', 'Verdigris Stones Stored' },
    { 'B', 'Verdigris Stones +1 Stored' },
    { 'B', 'Verdigris Stones +2 Stored' },
    { 'B', 'Wailing Stones Stored' },
    { 'B', 'Wailing Stones +1 Stored' },
    { 'B', 'Wailing Stones +2 Stored' },
    { 'B', 'Snowslit Stones Stored' },
    { 'B', 'Snowslit Stones +1 Stored' },
    { 'B', 'Snowslit Stones +2 Stored' },
    { 'B', 'Snowtip Stones Stored' },
    { 'B', 'Snowtip Stones +1 Stored' },
    { 'B', 'Snowtip Stones +2 Stored' },
    { 'B', 'Snowdim Stones Stored' },
    { 'B', 'Snowdim Stones +1 Stored' },
    { 'B', 'Snowdim Stones +2 Stored' },
    { 'B', 'Snoworb Stones Stored' },
    { 'B', 'Snoworb Stones +1 Stored' },
    { 'B', 'Snoworb Stones +2 Stored' },
    { 'B', 'Leafslit Stones Stored' },
    { 'B', 'Leafslit Stones +1 Stored' },
    { 'B', 'Leafslit Stones +2 Stored' },
    { 'B', 'Leaftip Stones Stored' },
    { 'B', 'Leaftip Stones +1 Stored' },
    { 'B', 'Leaftip Stones +2 Stored' },
    { 'B', 'Leafdim Stones Stored' },
    { 'B', 'Leafdim Stones +1 Stored' },
    { 'B', 'Leafdim Stones +2 Stored' },
    { 'B', 'Leaforb Stones Stored' },
    { 'B', 'Leaforb Stones +1 Stored' },
    { 'B', 'Leaforb Stones +2 Stored' },
    { 'B', 'Duskslit Stones Stored' },
    { 'B', 'Duskslit Stones +1 Stored' },
    { 'B', 'Duskslit Stones +2 Stored' },
    { 'B', 'Dusktip Stones Stored' },
    { 'B', 'Dusktip Stones +1 Stored' },
    { 'B', 'Dusktip Stones +2 Stored' },
    { 'B', 'Duskdim Stones Stored' },
    { 'B', 'Duskdim Stones +1 Stored' },
    { 'B', 'Duskdim Stones +2 Stored' },
    { 'B', 'Duskorb Stones Stored' },
    { 'B', 'Duskorb Stones +1 Stored' },
    { 'B', 'Duskorb Stones +2 Stored' },
    { 'B', 'Pellucid Stones Stored' },
    { 'B', 'Fern Stones Stored' },
    { 'B', 'Taupe Stones Stored' },
    { 'H', 'Mellidopt Wings Stored' },
    { 'H', 'Escha Beads' },
    { 'i', 'Escha Silt' },
    { 'i', 'Potpourri' },
    { 'i', 'Hallmarks' },
    { 'i', 'Total Hallmarks' },
    { 'i', 'Badges Of Gallantry' },
    { 'i', 'Crafter Points' },
    { 'B', 'Fire Crystals Set' },
    { 'B', 'Ice Crystals Set' },
    { 'B', 'Wind Crystals Set' },
    { 'B', 'Earth Crystals Set' },
    { 'B', 'Lightning Crystals Set' },
    { 'B', 'Water Crystals Set' },
    { 'B', 'Light Crystals Set' },
    { 'B', 'Dark Crystals Set' },
    { 'B', 'Mweya Plasm (SR01) Set' },
    { 'B', 'Mweya Plasm (SR02) Set' },
    { 'B', 'Mweya Plasm (SR03) Set' },
    { 'B', 'Liquefaction Spheres Set' },
    { 'B', 'Induration Spheres Set' },
    { 'B', 'Detonation Spheres Set' },
    { 'B', 'Scission Spheres Set' },
    { 'B', 'Impaction Spheres Set' },
    { 'B', 'Reverberation Spheres Set' },
    { 'B', 'Transfixion Spheres Set' },
    { 'B', 'Compression Spheres Set' },
    { 'B', 'Fusion Spheres Set' },
    { 'B', 'Distortion Spheres Set' },
    { 'B', 'Fragmentation Spheres Set' },
    { 'B', 'Gravitation Spheres Set' },
    { 'B', 'Light Spheres Set' },
    { 'B', 'Darkness Spheres Set' },
    { 'pad', 3 },
    { 'i', 'Silver Aman Vouchers Stored' },
    { 'i', 'Domain Points' },
    { 'i', 'Domain Points Earned Today' },
    { 'i', 'Mog Segments' },
    { 'i', 'Gallimaufry' },
    { 'H', 'IS Accolades' },
    { 'pad', 2 },
    { 'i', 'Temenos Units' },
    { 'i', 'Apollyon Units' },
} };
MYROOM.cur = { data = {}, t = {}, asked = {} };
function MYROOM.cur_packet(k, d)                                     -- the server's currencies: one row per currency, in its order
    local o = 4;
    local rows = {};
    local bitbase, bitpos = nil, 0;
    local function byte(i) return d:byte(i + 1) or 0; end
    for idx, f in ipairs(CURRENCY[k]) do
        local ty = f[1];
        if ty == 'bits' then
            if bitbase == nil then bitbase, bitpos = o, 0; end
            local v = 0;
            for b = 0, f[2] - 1 do
                local bp = bitpos + b;
                if bit.band(byte(bitbase + math.floor(bp / 8)), bit.lshift(1, bp % 8)) ~= 0 then v = v + 2 ^ b; end
            end
            bitpos = bitpos + f[2];
            if f[3] then rows[#rows + 1] = { f[3], v }; end
            local nx = CURRENCY[k][idx + 1];
            if nx == nil or nx[1] ~= 'bits' then o = bitbase + math.ceil(bitpos / 8); bitbase = nil; end
        elseif ty == 'pad' then o = o + f[2];
        else
            local v;
            if ty == 'B' then v = byte(o); o = o + 1;
            elseif ty == 'H' then v = byte(o) + byte(o + 1) * 256; o = o + 2;
            else
                v = byte(o) + byte(o + 1) * 256 + byte(o + 2) * 65536 + byte(o + 3) * 16777216; o = o + 4;
                if ty == 'i' and v >= 2147483648 then v = v - 4294967296; end
            end
            rows[#rows + 1] = { f[2], v };
        end
    end
    MYROOM.cur.data[k], MYROOM.cur.t[k] = rows, os.clock();
end
function MYROOM.cur_ask(k)                                           -- (the same request the game makes for its Currencies window)
    local now = os.clock();
    if (MYROOM.cur.asked[k] or -10) > now - 4 then return; end
    MYROOM.cur.asked[k] = now;
    pcall(function() AshitaCore:GetPacketManager():AddOutgoingPacket((k == 1) and 0x10F or 0x115, { 0, 0, 0, 0, 0, 0, 0, 0 }); end);
end
-- a Currencies page: every currency and how many, a page at a time; while it's open (the game's window, "evitem", hidden)
-- the controller scrolls it
function MYROOM.curpage(k, rect, live)
    local s = PSCALE();
    UI.curpage = UI.curpage or { cur = 1, off = 0 };
    local st = UI.curpage;
    if st.k ~= k then st.k, st.cur, st.off = k, 1, 0; end
    if not MYROOM.cur.data[k] or os.clock() - (MYROOM.cur.t[k] or -100) > 30 then MYROOM.cur_ask(k); end
    local all = MYROOM.cur.data[k] or {};
    local NV = 18;
    local n = #all;
    st.cur = math.max(1, math.min(math.max(1, n), st.cur));
    if st.cur < st.off + 1 then st.off = st.cur - 1; elseif st.cur > st.off + NV then st.off = st.cur - NV; end
    st.off = math.max(0, math.min(math.max(0, n - NV), st.off));
    local rows = {};
    for i = st.off + 1, math.min(n, st.off + NV) do
        local v = all[i][2];
        local vs = tostring(math.floor(v)):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', ''):gsub('^%-,', '-');
        rows[#rows + 1] = { all[i][1], vs, nil, v == 0 };
    end
    if n == 0 then rows[1] = { 'Asking the server...', '', nil, true }; end
    local W = math.floor(420 * s);
    local x = rect[1] - W - 10 * s;
    local sw = screen();
    if x < 4 then x = math.min(sw - W - 4, rect[1] + rect[3] + 10 * s); end
    local foot = live and 'Up / Down: scroll.  Left / Right: a page.  Cancel: back.' or 'Confirm to scroll through them.';
    local clicked, wd = list_panel('curpage', x, rect[2], W, 'CURRENCIES', (k == 1) and 'Currencies' or 'Currencies 2', rows,
        live and (st.cur - st.off) or nil, { focused = live, foot = foot, min_rows = NV, scroll = { st.off, n, NV },
                                              on_cancel = function() if live then M.act(nil, nil, KEY.cancel); end end });
    if clicked and live then st.cur = st.off + clicked; end
    if wd ~= 0 then st.cur = math.max(1, math.min(math.max(1, n), st.cur + wd)); if not live then st.off = math.max(0, math.min(math.max(0, n - NV), st.off + wd)); end end
end
function MYROOM.cur_pad(acts)
    local st = UI.curpage;
    if not st then return; end
    local n = #(MYROOM.cur.data[st.k or 1] or {});
    for _, act in ipairs(acts) do
        if act == 'up' then st.cur = (st.cur > 1) and (st.cur - 1) or math.max(1, n);
        elseif act == 'down' then st.cur = (st.cur < n) and (st.cur + 1) or 1;
        elseif act == 'left' or act == 'tabl' then st.cur = math.max(1, st.cur - 18);
        elseif act == 'right' or act == 'tabr' then st.cur = math.min(math.max(1, n), st.cur + 18);
        elseif act == 'back' then M.act(nil, nil, KEY.cancel); end
    end
end
function MYROOM.page(i, rect)
    if i == 7 or i == 8 then return MYROOM.curpage(i - 6, rect, UI.curpage_live); end   -- (Currencies, Currencies 2)
    local tab = MYROOM.PAGES[i];
    if tab == nil then return; end
    local s = PSCALE();
    local sr = status_rows(tab);
    local rows = {};
    for k, r in ipairs(sr) do rows[k] = { r[1], r[2], nil, r[5] }; end
    local W = math.floor(380 * s);
    local x = rect[1] - W - 10 * s;
    local sw = screen();
    if x < 4 then x = math.min(sw - W - 4, rect[1] + rect[3] + 10 * s); end
    local names = { 'Profile', 'Job levels', '', 'Combat skills', 'Magic skills', 'Crafting skills', '', '', '', '', 'Merit points' };
    local foot = (tab == 6) and 'Confirm opens the merit categories.' or nil;
    local foot2 = (tab == 6) and 'Click SWITCH / OPEN, or confirm the list for the merit categories.' or foot;
    local clicked = list_panel('statpage', x, rect[2], W, 'STATUS', names[i] or '', rows, nil, { focused = false, foot = foot2 });
    if clicked and sr[clicked] and sr[clicked][6] then special_action(sr[clicked][6]); end   -- (Earning: switch / Merit categories: open)
end

-- Sorting the lists: the game's order (castable / ready first), A-Z, or by level (low to high). Kept per menu.
local SORT_MODES = { magic = { 'default', 'az', 'level' }, abilities = { 'default', 'az' }, items = { 'default', 'az', 'level' },
                     keyitems = { 'default', 'az' }, trade = { 'default', 'az', 'level' } };
local SORT_NAME = { default = 'GAME', az = 'A-Z', level = 'LEVEL' };
function sort_next(kind)
    local m = SORT_MODES[kind]; if not m then return; end
    local cur = cfg['sort_' .. kind] or 'default';
    local i = 1; for j, v in ipairs(m) do if v == cur then i = j; end end
    cfg['sort_' .. kind] = m[(i % #m) + 1]; save();
end
function sort_rows(kind, rows, name_of, lv_of)
    local mode = cfg['sort_' .. kind] or 'default';
    if mode == 'default' or not SORT_MODES[kind] then return rows; end
    local pinned, rest = {}, {};
    for i, r in ipairs(rows) do r._i = i; if r.pin then pinned[#pinned + 1] = r; else rest[#rest + 1] = r; end end
    table.sort(rest, function(p, q)
        if mode == 'level' then
            local lp, lq = lv_of(p) or 999, lv_of(q) or 999;
            if lp ~= lq then return lp < lq; end
        end
        local np, nq = (name_of(p) or ''):lower(), (name_of(q) or ''):lower();
        if np ~= nq then return np < nq; end
        return p._i < q._i;
    end);
    for _, r in ipairs(rest) do pinned[#pinned + 1] = r; end
    return pinned;
end
-- whether you have a pet out (avatar, automaton, wyvern, jug pet, charmed monster, luopan): your entity's pet index
function pet_out()
    local out = false;
    local ok = pcall(function()
        local mm = AshitaCore:GetMemoryManager();
        local me = mm:GetParty():GetMemberTargetIndex(0);
        local pi = mm:GetEntity():GetPetTargetIndex(me);
        out = (pi ~= nil and pi > 0 and pi ~= me);
    end);
    if not ok then M.note('pet', 'pet check not available: pet commands always shown'); return true; end
    return out;
end
-- The Mog House storage, the way the game lays it out: the bag you picked on the left, your Inventory on the right.
-- Confirm moves an item across (a stack asks how many: type it, or the d-pad), Left / Right switch sides, L1 / R1 change
-- the bag on the left. Moves are the game's own move request (packet 0x29), the same as TAKE / STORE.
local MOGX_BAGS = { 1, 9, 2, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16 };
local function bag_name(bag) for _, b in ipairs(ITEM_BAGS) do if b[1] == bag then return b[3]; end end return 'Bag ' .. bag; end
local function bag_rows(bag)
    local rows = {};
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        local res = AshitaCore:GetResourceManager();
        for i = 1, 80 do
            local it = inv:GetContainerItem(bag, i);
            if it and (it.Id or 0) ~= 0 and it.Id ~= 65535 then
                local r = res:GetItemById(it.Id);
                local worn = (it.Flags or 0) == 5;
                rows[#rows + 1] = { (r and r.Name and r.Name[1]) or '?', worn and 'WORN' or (((it.Count or 1) > 1) and ('x' .. it.Count) or ''), it.Id, worn or (it.Flags or 0) ~= 0,
                    bag = bag, idx = i, count = it.Count or 1, id = it.Id, lv = r and tonumber(r.Level), locked = (it.Flags or 0) ~= 0 };
            end
        end
    end);
    if sort_rows then rows = sort_rows('items', rows, function(r) return r[1]; end, function(r) return r.lv; end); end
    return rows;
end
local function bag_space(bag)
    local n, max = 0, 80;
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        for i = 1, 80 do local it = inv:GetContainerItem(bag, i); if it and (it.Id or 0) ~= 0 and it.Id ~= 65535 then n = n + 1; end end
        max = tonumber(inv:GetContainerCountMax(bag)) or 80;
    end);
    return n, max;
end
local function mogx_move(r, n, dst)
    pcall(function()
        AshitaCore:GetPacketManager():AddOutgoingPacket(0x29, { 0, 0, 0, 0, bit.band(n, 0xFF), bit.band(bit.rshift(n, 8), 0xFF), 0, 0, r.bag, dst, r.idx, 0x52 });
    end);
    M.note('move', ('%d of item %d from bag %d slot %d to bag %d'):format(n, r.id or 0, r.bag, r.idx, dst));
end
local function mogx_pick(r, dst)
    local X = UI.mogx;
    if not r or r.locked then if r and r.locked then msg('That item is in use (worn or in your bazaar).'); end return; end
    if r.count > 1 then X.pick = { kind = 'item', id = r.id, name = r[1], max = r.count, n = r.count, row = r, dst = dst }; return; end
    mogx_move(r, 1, dst);
end
local function mogx_step(d) local P = UI.mogx.pick; if P then P.n = math.max(0, math.min(P.max, P.n + d)); P.typed = true; end end
local function mogx_done(ok)
    local P = UI.mogx.pick;
    UI.mogx.pick = nil;
    if ok and P and P.n > 0 then mogx_move(P.row, P.n, P.dst); end
end
local function draw_mogx(B)
    local s = PSCALE();
    UI.mogx = UI.mogx or { side = 'l', cur = { l = 1, r = 1 }, off = { l = 0, r = 0 } };
    local X = UI.mogx;
    if X.for_t ~= B.t0 then X.for_t, X.bag, X.side, X.cur, X.off, X.pick = B.t0, B.mog, 'l', { l = 1, r = 1 }, { l = 0, r = 0 }, nil; end
    local L, R = bag_rows(X.bag), bag_rows(0);
    local NV = 16;
    -- the controller
    for _, act in ipairs(UI.br.acts or {}) do
        local P = X.pick;
        if P then
            if act == 'up' then mogx_step(1); elseif act == 'down' then mogx_step(-1);
            elseif act == 'right' then mogx_step(10); elseif act == 'left' then mogx_step(-10);
            elseif act == 'tabr' then mogx_step(100); elseif act == 'tabl' then mogx_step(-100);
            elseif act == 'ok' then mogx_done(true); elseif act == 'back' then mogx_done(false); end
        else
            local list = (X.side == 'l') and L or R;
            local n = math.max(1, #list);
            local c = X.cur[X.side];
            if act == 'up' then c = (c > 1) and (c - 1) or n;
            elseif act == 'down' then c = (c < n) and (c + 1) or 1;
            elseif act == 'left' then X.side = 'l';
            elseif act == 'right' then X.side = 'r';
            elseif act == 'tabl' or act == 'tabr' then             -- (the bag on the left)
                local i = 1; for j, b in ipairs(MOGX_BAGS) do if b == X.bag then i = j; end end
                i = i + ((act == 'tabl') and -1 or 1);
                if i < 1 then i = #MOGX_BAGS elseif i > #MOGX_BAGS then i = 1 end
                X.bag, X.cur.l, X.off.l = MOGX_BAGS[i], 1, 0;
            elseif act == 'sort' then sort_next('items');
            elseif act == 'ok' then mogx_pick(list[c], (X.side == 'l') and 0 or X.bag);
            elseif act == 'back' then close_browse(); return; end
            X.cur[X.side] = c;
        end
    end
    local function window(side, list, x, y, W, title, sub)
        local c = math.max(1, math.min(math.max(1, #list), X.cur[side]));
        X.cur[side] = c;
        if c < X.off[side] + 1 then X.off[side] = c - 1; elseif c > X.off[side] + NV then X.off[side] = c - NV; end
        X.off[side] = math.max(0, math.min(math.max(0, #list - NV), X.off[side]));
        local vis = {};
        for i = X.off[side] + 1, math.min(#list, X.off[side] + NV) do vis[#vis + 1] = list[i]; end
        if #vis == 0 then vis[1] = { 'Empty', '', nil, true }; end
        local on = (X.side == side) and not X.pick;
        local clicked, wd, rect = list_panel('mog' .. side, x, y, W, title, sub, vis, on and (c - X.off[side]) or nil,
            { icons = true, focused = on, min_rows = NV, scroll = { X.off[side], #list, NV },
              pill = { 'SORT ' .. (({ default = 'GAME', az = 'A-Z', level = 'LEVEL' })[cfg.sort_items or 'default']), function() sort_next('items'); end },
              on_cancel = function() if X.pick then mogx_done(false); else close_browse(); end end,
              foot = (side == 'l') and 'Confirm: to Inventory.  L1 / R1: other bags.' or 'Confirm: into the bag on the left.' });
        if clicked and not X.pick then
            X.side, X.cur[side] = side, X.off[side] + clicked;
            mogx_pick(list[X.cur[side]], (side == 'l') and 0 or X.bag);
        end
        if wd ~= 0 and not X.pick then X.cur[side] = math.max(1, math.min(#list, X.cur[side] + wd)); end
        if on and list[c] and list[c].id and rect then              -- (the item card, under the window)
            UI.tip_id, UI.tip_at, UI.tip_ext, UI.tip_bi = list[c].id, { rect[1], rect[2] + rect[4] + 6 * s, rect[2] - 6 * s }, item_extra(list[c].bag, list[c].idx), { list[c].bag, list[c].idx };
        end
        return rect;
    end
    local W = math.floor(300 * s);
    local nl, ml = bag_space(X.bag);
    local nr, mr = bag_space(0);
    local lr = window('l', L, 40, 110, W, 'STORAGE', ('%s   %d / %d'):format(bag_name(X.bag), nl, ml));
    local rx = lr and (lr[1] + lr[3] + 10 * s) or (40 + W + 10 * s);
    window('r', R, rx, lr and lr[2] or 110, W, 'INVENTORY', ('Inventory   %d / %d'):format(nr, mr));
    if X.pick and lr then draw_trade_pick(lr[1], lr[2], W, s, X.pick, mogx_step, mogx_done); end
    return true;
end
local function draw_browser(B, anchor)
    if B.kind == 'items' and not B.mog and B.gw_name == 'bank' then  -- (the Mog House's own list, its bag not caught: by its count)
        local gwin = B.gw_addr and M.open[B.gw_addr] or nil;
        local gc = nil;
        pcall(function() local mp = rd32(gwin.addr + 0x0C); if mp >= FLOOR then gc = rd16(mp + 0x20); end end);
        local found = nil;
        if gc then for _, b in ipairs(MOGX_BAGS) do if not found and select(1, bag_space(b)) == gc then found = b; end end end
        B.mog = found or 5;                                          -- (never the plain Items list here: it would use items)
        M.note('mog', ('bag by count %s -> %d'):format(tostring(gc), B.mog));
    end
    if B.mog and B.kind == 'items' then return draw_mogx(B); end
    local s = PSCALE();
    local kind = B.kind;
    local tabs, rows, have = nil, {}, nil;
    local tabkey = (B.stage == 'bluset') and 'bluset' or kind;       -- (each page keeps its own tab)
    local tab = UI.br.tab[tabkey];
    if kind == 'magic' and B.stage == 'menu' then                    -- Magic from the action menu: the kinds of magic you have
        local _, hv = magic_rows(-1);
        local KINDS = { { 1, 'White Magic', 'Healing, enhancing, divine.' }, { 2, 'Black Magic', 'Elemental, dark, enfeebling.' },
                        { 3, 'Summoning Magic', 'Call an avatar.' }, { 4, 'Ninjutsu', 'Ninja tools.' }, { 5, 'Songs', 'Bard songs.' },
                        { 6, 'Blue Magic', 'Your set blue magic.' }, { 7, 'Geomancy', 'Geocolures and indicolures.' }, { 8, 'Trust', 'Call your Trusts.' } };
        local KC = { { 0.95, 0.95, 1.0, 1 }, { 0.75, 0.45, 1.0, 1 }, { 1.0, 0.75, 0.35, 1 }, { 0.55, 0.65, 0.85, 1 }, { 1.0, 0.85, 0.45, 1 },
                     { 0.40, 0.65, 1.0, 1 }, { 0.40, 0.95, 0.65, 1 }, { 1.0, 0.55, 0.75, 1 } };
        for _, k_ in ipairs(KINDS) do
            if hv and hv[k_[1]] then
                rows[#rows + 1] = { k_[2], '>', KC[k_[1]], nil, false, '@mgtab:' .. k_[1], k_[3] };
            end
        end
        if #rows == 0 then rows[1] = { 'No magic right now', '', nil, nil, true, nil, 'Nothing you can cast on this job.' }; end
    elseif kind == 'magic' and B.stage == 'bluset' then              -- Blue Magic: set spells
        tabs = { { 1, 'SET', 'Set spells' }, { 2, 'LEARNED', 'Learned blue magic' } };
        tab = (tab == 2) and 2 or 1;
        local set = BLU.spells();
        local where = {};
        for i, v in ipairs(set) do if v > 0 then where[v] = i; end end
        local res = AshitaCore:GetResourceManager();
        local function nm(id) local r = nil; pcall(function() r = res:GetSpellById(id + 512); end); return rname(r) or ('Spell ' .. id), r; end
        if tab == 1 then
            for i = 1, 20 do
                local v = set[i] or 0;
                if v > 0 then
                    local n, r = nm(v);
                    rows[#rows + 1] = { n, 'slot ' .. i, ELEMC[tonumber(r and r.Element)], nil, false, '@bluunset:' .. i, 'Confirm: unset it.' };
                else
                    rows[#rows + 1] = { '(empty)', 'slot ' .. i, nil, nil, true, nil, 'Set a spell from the Learned tab.' };
                end
            end
        else
            local pl = AshitaCore:GetMemoryManager():GetPlayer();
            local learned = {};
            for id = 512, 1023 do
                local has = false;
                pcall(function() has = pl:HasSpell(id); end);
                if has then
                    local r = nil; pcall(function() r = res:GetSpellById(id); end);
                    if r and (tonumber(r.Type) == 6) then learned[#learned + 1] = { id = id - 512, name = rname(r) or '?', r = r }; end
                end
            end
            table.sort(learned, function(p, q)                       -- (set spells first)
                local ps, qs = where[p.id] ~= nil, where[q.id] ~= nil;
                if ps ~= qs then return ps; end
                return p.name < q.name;
            end);
            for _, e in ipairs(learned) do
                local isset = where[e.id] ~= nil;
                rows[#rows + 1] = { e.name, isset and 'SET' or '', ELEMC[tonumber(e.r.Element)], nil, false, '@bluset:' .. e.id,
                    isset and 'Confirm: unset it.' or 'Confirm: set it in the first empty slot.' };
            end
        end
    elseif kind == 'magic' then
        _, have = magic_rows(-1);
        tabs = {};
        for _, t in ipairs(MAGIC_TABS) do if have[t[1]] then tabs[#tabs + 1] = { t[1], t[2] }; end end
        if #tabs == 0 then tabs = { { 1, 'WHITE' } }; end
        local okt = false; for _, t in ipairs(tabs) do if t[1] == tab then okt = true; end end
        if not okt then tab = tabs[1][1]; end
        rows = magic_rows(tab);
        if tab == 6 and (BLU.main() or BLU.sub()) then                -- Blue: set spells first (only those can be cast), then Set Spells
            local set = BLU.spells();
            local isset = {};
            for _, v in ipairs(set) do if v > 0 then isset[v] = true; end end
            local top, rest = {}, {};
            for _, r in ipairs(rows) do
                local id = r.spell and (r.spell - 512);
                if id and isset[id] then top[#top + 1] = r; else r[5] = true; rest[#rest + 1] = r; end
            end
            rows = { { 'Set Spells  >', 'SET', { 1.0, 0.36, 0.62 }, nil, false, '@blustage', 'Choose which blue magic is set.', pin = true } };
            for _, r in ipairs(top) do rows[#rows + 1] = r; end
            for _, r in ipairs(rest) do rows[#rows + 1] = r; end
        end
    elseif kind == 'abilities' and B.stage == 'menu' then             -- the combat Abilities menu (from the action menu)
        local petout = pet_out();
        rows = {
            { 'Job Abilities', '>', nil, nil, false, '@abtab:1', 'Your job abilities.' },
            { 'Weapon Skills', '>', nil, nil, false, '@abtab:2', 'Your weapon skills (1000 TP).' },
            { 'Ranged Attack', '', nil, nil, false, '@ranged', 'Shoot or throw at your target.' },
            { 'Mount', '>', nil, nil, false, '@abtab:4', 'Call one of your mounts.' },
            petout and { 'Pet Commands', '>', nil, nil, false, '@abtab:3', 'Blood pacts, Ready and other pet commands.' } or nil,
        };
    elseif kind == 'abilities' then
        _, have = ability_rows(-1);
        local j_, _, sj_ = job_lv();
        tabs = { { 1, 'ABILITIES' } };
        if pet_out() then tabs[#tabs + 1] = { 3, 'PET' }; end          -- (pet commands only while a pet is out)
        tabs[#tabs + 1] = { 2, 'WEAPON SKILLS' };
        if have and have[5] then tabs[#tabs + 1] = { 5, 'TRAITS' }; end
        tabs[#tabs + 1] = { 4, 'GENERAL' };
        tab = tab or 1;
        do local okt = false; for _, t in ipairs(tabs) do if t[1] == tab then okt = true; end end if not okt then tab = 1; end end
        rows = ability_rows(tab);
    elseif kind == 'status' then
        tabs = STATUS_TABS;
        tab = tab or 1;
        rows = status_rows(tab);
    elseif kind == 'items' and B.usable then                          -- (Items in the action menu: only what you can use now)
        tabs = { { 1, 'USABLE', 'Usable items' } };
        tab = 1;
        rows = cached('usable', 0.5, function()
            local out = {};
            pcall(function()
                local inv = AshitaCore:GetMemoryManager():GetInventory();
                local res = AshitaCore:GetResourceManager();
                local function usable(r)                             -- (the game's "can use" flag, or gear with charges)
                    return r and (bit.band(tonumber(r.Flags) or 0, 0x0200) ~= 0 or (tonumber(r.MaxCharges) or 0) > 0);
                end
                local seen = {};
                -- the gear you have on that can be used (enchanted gear: rings, earrings, wings...), from whichever bag it's in
                for slot = 0, 15 do
                    local e = inv:GetEquippedItem(slot);
                    if e ~= nil and (e.Index or 0) ~= 0 then
                        local bag, idx = bit.rshift(bit.band(e.Index, 0xFF00), 8), bit.band(e.Index, 0xFF);
                        local it = inv:GetContainerItem(bag, idx);
                        if it and (it.Id or 0) ~= 0 and it.Id ~= 65535 then
                            local r = res:GetItemById(it.Id);
                            if usable(r) and not seen[bag * 256 + idx] then
                                seen[bag * 256 + idx] = true;
                                local nm = rname(r) or '?';
                                local lbl = ench_label(ext_string(it.Extra), it.Id, bag, idx);
                                out[#out + 1] = { nm, lbl and ('WORN ' .. lbl) or 'WORN', nil, it.Id, false, ('/item "%s" %s'):format(nm, target_for(r)), rdesc(r),
                                    id = it.Id, bag = bag, idx = idx, count = 1, lv = tonumber(r.Level), worn = true };
                            end
                        end
                    end
                end
                -- the rest: usable things in your Inventory, and usable gear in your Inventory and Mog Wardrobes (gear has to be
                -- put on before it can be used: confirm puts it on, then use it once it's ready)
                for _, bag in ipairs({ 0, 8, 10, 11, 12, 13, 14, 15, 16 }) do
                    for i = 1, 80 do
                        local it = inv:GetContainerItem(bag, i);
                        if it and (it.Id or 0) ~= 0 and it.Id ~= 65535 and not seen[bag * 256 + i] then
                            local r = res:GetItemById(it.Id);
                            local slots = r and tonumber(r.Slots) or 0;
                            if usable(r) and (bag == 0 or slots ~= 0) then
                                local nm = rname(r) or '?';
                                if slots ~= 0 then                   -- (gear not on: put it on first)
                                    local slot, cands = 0, {};       -- (rings / earrings: an empty one of the two, else the second)
                                    for b_ = 0, 15 do if bit.band(slots, bit.lshift(1, b_)) ~= 0 then cands[#cands + 1] = b_; end end
                                    slot = cands[#cands] or 0;
                                    for _, c_ in ipairs(cands) do
                                        local e_ = inv:GetEquippedItem(c_);
                                        if e_ == nil or (e_.Index or 0) == 0 then slot = c_; break; end
                                    end
                                    local wn = WARDROBE[bag];
                                    out[#out + 1] = { nm, wn and ('W' .. wn .. '  equip') or 'equip', nil, it.Id, false,
                                        ('@equipuse:%d:%d:%d'):format(bag, i, slot), 'Put it on first (it can be used once it is ready).  ' .. rdesc(r),
                                        id = it.Id, bag = bag, idx = i, count = 1, lv = tonumber(r.Level) };
                                else
                                    out[#out + 1] = { nm, ((it.Count or 1) > 1) and ('x' .. it.Count) or '', nil, it.Id, false,
                                        ('/item "%s" %s'):format(nm, target_for(r)), rdesc(r), id = it.Id, bag = 0, idx = i, count = it.Count or 1, lv = tonumber(r.Level) };
                                end
                            end
                        end
                    end
                end
            end);
            return out;
        end);
    elseif kind == 'items' then
        tabs = {};
        for i, b in ipairs(ITEM_BAGS) do tabs[#tabs + 1] = { i, b[2], b[3] }; end
        tab = tab or 1;
        -- (opened from the game's item list: the tab of the bag it shows, matched by its item count; again whenever the
        --  game's list changes bag)
        local gwin = B.gw_addr and M.open[B.gw_addr] or nil;
        if B.mog and not B.mog_set then                              -- (picked in the Mog House storage menu: that bag)
            B.mog_set = true;
            for i, b in ipairs(ITEM_BAGS) do if b[1] == B.mog then tab = i; UI.br.sel[kind] = nil; end end
            M.note('items', 'mog house pick: ' .. tostring(B.mog));
        end
        if gwin and not B.mog then
            local gc = nil;
            pcall(function()
                local mp = rd32(gwin.addr + 0x0C);
                if mp >= FLOOR and rd16(mp + 0x18) > 0 then gc = rd16(mp + 0x20); end
            end);
            if gc and gc >= 0 and gc ~= B.gcount then
                local function n_in(bag)
                    local n = 0;
                    pcall(function()
                        local inv = AshitaCore:GetMemoryManager():GetInventory();
                        for i = 1, 80 do local it = inv:GetContainerItem(bag, i); if it and (it.Id or 0) ~= 0 and it.Id ~= 65535 then n = n + 1; end end
                    end);
                    return n;
                end
                local best = nil;
                if B.gcount ~= nil and n_in(ITEM_BAGS[tab][1]) == gc then best = tab; end
                if not best then for i, b in ipairs(ITEM_BAGS) do if n_in(b[1]) == gc then best = i; break; end end end
                B.gcount = gc;
                if best then
                    if best ~= tab then UI.br.sel[kind] = nil; end
                    tab = best;
                    M.note('items', ('game list has %d: %s'):format(gc, ITEM_BAGS[best][3]));
                end
            end
        end
        rows = item_rows(tab);
        if B.mog then                                                -- (Mog House: confirm takes it out, or puts it in the picked bag)
            local name_of = function(bag) for _, b in ipairs(ITEM_BAGS) do if b[1] == bag then return b[3]; end end return '?'; end
            local out = {};
            for i, r in ipairs(rows) do
                local dst = (r.bag == 0) and B.mog or 0;
                local nr = { r[1], r[2], r[3], r[4], r[5], ('@move:%d:%d:%d:%d'):format(r.bag, r.idx, dst, r.count),
                    ((dst == 0) and 'Confirm: take it out (to Inventory).' or ('Confirm: put it in ' .. name_of(dst) .. '.')) .. '  ' .. (r[7] or ''),
                    id = r.id, bag = r.bag, idx = r.idx, count = r.count };
                if B.mog == 0 then nr[6] = r[6]; nr[7] = r[7]; end
                out[i] = nr;
            end
            rows = out;
        end
    else
        rows = keyitem_rows();
    end
    if B.stage ~= 'menu' then UI.br.tab[tabkey] = tab; end
    local sortable = SORT_MODES[kind] and B.stage ~= 'menu' and B.stage ~= 'bluset' and not (kind == 'abilities' and tab == 4);
    if sortable then
        local copy = {}; for i, r in ipairs(rows) do copy[i] = r; end
        rows = sort_rows(kind, copy, function(r) return r[1]; end, function(r) return r.lv; end);
    end
    local key = kind .. ':' .. ((B.stage == 'menu') and 'menu' or ((B.stage == 'bluset') and ('bluset' .. tab) or tostring(tab))) .. ':' .. tostring(cfg['sort_' .. kind] or 'default');
    local W = math.floor(((kind == 'items' or kind == 'status') and 400 or 340) * s);
    local RH = math.floor(((kind == 'items') and 30 or 25) * s);
    local HEAD = math.floor(44 * s);
    local TABS = tabs and math.floor(((#tabs > 7) and 46 or 26) * s) or 0;
    local NROWS = (B.stage == 'menu') and math.max(1, #rows) or 14;   -- (the combat Abilities menu: just its rows)
    local CARD = math.floor(((kind == 'items') and 50 or 64) * s);
    local H = HEAD + TABS + NROWS * RH + CARD + math.floor(12 * s);
    local sw, sh = screen();
    local x, y;
    if anchor then x, y = anchor[1] - W - 12 * s, anchor[2]; else x, y = sw - W - 290 * s, 110; end
    if x < 4 and anchor then x = anchor[1] + anchor[3] + 12 * s; end
    -- (each menu keeps its own place, apart for the main menu's and the action menu's: Magic from the main menu and
    --  Magic from the action menu can sit in different spots; the first time, the old shared spot is used)
    local pk = 'br_' .. (B.mog and 'mog' or (B.from_act and 'act' or 'cmd')) .. '_' .. kind .. ((B.stage == 'menu') and '_menu' or '');
    B.pk = pk;
    if (tonumber(cfg[pk .. '_x']) or -1) < 0 and (tonumber(cfg.browse_x) or -1) >= 0 then
        x, y = saved_pos('browse', x, y, W, H);
    else
        x, y = saved_pos(pk, x, y, W, H);
    end
    local off = math.max(0, math.min(math.max(0, #rows - NROWS), UI.br.off[key] or 0));
    local now = os.clock();
    local k = cfg.anim and ease((now - (B.t0 or now)) / 0.18) or 1;
    local a = k;
    imgui.SetNextWindowPos({ x, y }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ W + 8, H + 8 }, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    UI.pushed = 2;
    local opened = imgui.Begin('##ccm_browse', { true }, win_flags());
    UI.began = true;
    if opened then
        local dl = imgui.GetWindowDrawList();
        local hov_win = imgui.IsWindowHovered();
        local mx, my = mouse();
        x, y = drag(pk, x, y, x, y, x + W, y + HEAD);
        panel(dl, x, y, x + W, y + H, a, s);
        local tk = font(12 * s);
        caps(dl, x + 16 * s, y + 10 * s, BROWSE_TITLE[kind], C.acc, 2.5 * s, a);
        lock_button(dl, x + W - 50 * s, y + 8 * s, s, a, hov_win);
        unfont(tk);
        local subt = '';
        if tabs then for _, t in ipairs(tabs) do if t[1] == tab then subt = t[3] or (t[2]:sub(1, 1) .. t[2]:sub(2):lower()); end end
            if B.stage == 'bluset' then
                local u, m = BLU.points_used_max();
                if u and m and m > 0 then subt = subt .. ('   BP %d / %d'):format(u, m); end
            end
        elseif B.stage == 'menu' then subt = (kind == 'magic') and 'Pick a kind of magic' or 'Combat';
        else subt = 'Key items'; end
        tk = font(16 * s); text(dl, x + 16 * s, y + 22 * s, subt, C.text, a); unfont(tk);
        tk = font(12 * s);
        local cnt = (#rows > 0) and (('%d-%d / %d'):format(off + 1, math.min(#rows, off + NROWS), #rows)) or 'none';
        text(dl, x + W - 16 * s - tw(cnt), y + 28 * s, cnt, C.dim, a);
        if sortable then                                             -- sort: a click (or X / Square) changes it
            local lab = 'SORT ' .. SORT_NAME[cfg['sort_' .. kind] or 'default'];
            local tk5 = font(10 * s);
            local pw = tw(lab) + 14 * s;
            local px1 = x + W - 24 * s - tw(cnt);
            local px0, py0 = px1 - pw, y + 26 * s;
            local hv = hov_win and not UI.move and inside(mx, my, px0, py0, px1, py0 + 16 * s);
            DL.RF(dl, px0, py0, px1, py0 + 16 * s, hv and col(C.pink, 0.40 * a) or U4(1, 1, 1, 0.07 * a), 6 * s);
            DL.R(dl, px0, py0, px1, py0 + 16 * s, col(C.vio, 0.6 * a), 6 * s, 0, 1);
            text(dl, px0 + 7 * s, py0 + 2 * s, lab, hv and C.text or C.acc, a);
            unfont(tk5);
            if hv and imgui.IsMouseClicked(0) then sort_next(kind); end
        end
        unfont(tk);
        do                                                           -- close (x)
            local cx0, cy0 = x + W - 26 * s, y + 10 * s;
            local hv = hov_win and inside(mx, my, cx0, cy0, cx0 + 16 * s, cy0 + 16 * s);
            DL.L(dl, cx0 + 4 * s, cy0 + 4 * s, cx0 + 12 * s, cy0 + 12 * s, hv and col(C.pink, a) or col(C.muted, a), 1.5);
            DL.L(dl, cx0 + 12 * s, cy0 + 4 * s, cx0 + 4 * s, cy0 + 12 * s, hv and col(C.pink, a) or col(C.muted, a), 1.5);
            if hv and imgui.IsMouseClicked(0) then close_browse(); end
        end
        if tabs then                                                 -- tabs, wrapping onto a second line when there are many
            local per = (#tabs > 7) and math.ceil(#tabs / 2) or #tabs;
            local tw_ = (W - 24 * s - (per - 1) * 2 * s) / per;
            for i, t in ipairs(tabs) do
                local rr, cc = math.floor((i - 1) / per), (i - 1) % per;
                local tx0, ty0 = x + 12 * s + cc * (tw_ + 2 * s), y + HEAD + rr * 21 * s;
                local sel = (t[1] == tab);
                local hv = hov_win and not UI.move and inside(mx, my, tx0, ty0, tx0 + tw_, ty0 + 18 * s);
                DL.RF(dl, tx0, ty0, tx0 + tw_, ty0 + 18 * s, sel and col(C.pink, 0.30 * a) or U4(1, 1, 1, (hv and 0.10 or 0.04) * a), 5 * s);
                if sel then DL.R(dl, tx0, ty0, tx0 + tw_, ty0 + 18 * s, col(C.pink, 0.8 * a), 5 * s, 0, 1); end
                local tk3 = font(10 * s);
                local lab = t[2];
                while tw(lab) > tw_ - 4 * s and #lab > 2 do lab = lab:sub(1, #lab - 1); end
                text(dl, tx0 + (tw_ - tw(lab)) / 2, ty0 + 3 * s, lab, sel and C.text or C.muted, a);
                unfont(tk3);
                if hv and imgui.IsMouseClicked(0) then UI.br.tab[tabkey] = t[1]; UI.br.sel[kind] = nil; end
            end
        end
        local ry0 = y + HEAD + TABS;
        local hover = nil;
        do                                                           -- (item cards go under the menu, or over it, where there's more room)
            local sw_, sh_ = screen();
            if (sh_ - (y + H)) >= y then UI.tip_side = { x, y + H + 6 * s, y - 6 * s };
            else UI.tip_side = { x, sh_ + 1, y - 6 * s }; end           -- (past the bottom: the card goes above)
        end
        -- the controller: up / down move, left / right and L1 / R1 change tab, confirm uses, cancel closes
        local cur = UI.br.cur[key];
        if UI.pad_owner == 'browse' then
            cur = math.max(1, math.min(math.max(1, #rows), cur or 1));
            for _, act in ipairs(UI.br.acts or {}) do
                if act == 'sort' then if sortable then sort_next(kind); end
                elseif act == 'up' then cur = (cur > 1) and (cur - 1) or #rows;
                elseif act == 'down' then cur = (cur < #rows) and (cur + 1) or 1;
                elseif (act == 'left' or act == 'right' or act == 'tabl' or act == 'tabr') and tabs then
                    local ti = 1;
                    for i, t in ipairs(tabs) do if t[1] == tab then ti = i; end end
                    ti = ti + ((act == 'left' or act == 'tabl') and -1 or 1);
                    if ti < 1 then ti = #tabs elseif ti > #tabs then ti = 1 end
                    UI.br.tab[tabkey] = tabs[ti][1]; UI.br.sel[kind] = nil; cur = 1;
                elseif act == 'ok' and rows[cur] then
                    if kind == 'items' and not B.usable then
                        if UI.br.sel[kind] == cur and rows[cur][6] and rows[cur][6]:sub(1, 1) == '@' then
                            special_action(rows[cur][6]); UI.br.sel[kind] = nil;
                            UI.br.flash = { k = key, i = cur, t = now };
                        elseif UI.br.sel[kind] == cur and rows[cur][6] then
                            local cmd = rows[cur][6];
                            pcall(function() AshitaCore:GetChatManager():QueueCommand(1, cmd); end);
                            UI.br.flash = { k = key, i = cur, t = now };
                            M.note('browse', cmd);
                        else
                            UI.br.sel[kind] = cur;
                        end
                    elseif rows[cur][6] and rows[cur][6]:sub(1, 1) == '@' then
                        special_action(rows[cur][6]);
                    elseif rows[cur][6] then
                        local cmd = rows[cur][6];
                        pcall(function() AshitaCore:GetChatManager():QueueCommand(1, cmd); end);
                        UI.br.flash = { k = key, i = cur, t = now };
                        M.note('browse', cmd);
                        if B.via == 'game' then close_browse(); end
                    end
                elseif act == 'back' then
                    if kind == 'items' and UI.br.sel[kind] then UI.br.sel[kind] = nil;
                    elseif B.menu and B.stage == 'list' then B.stage = 'menu';
                    elseif B.stage == 'bluset' then B.stage = nil;
                    else
                        close_browse();
                    end
                end
            end
            UI.br.acts = nil;
            if cur < off + 1 then off = cur - 1; elseif cur > off + NROWS then off = cur - NROWS; end
            UI.br.cur[key] = cur;
        end
        local sel = UI.br.sel[kind];
        tk = font(14.5 * s);
        for i = 1, NROWS do
            local r = rows[off + i];
            if r == nil then break; end
            local yy = ry0 + (i - 1) * RH;
            local hv = hov_win and not UI.move and inside(mx, my, x + 6 * s, yy, x + W - 6 * s, yy + RH);
            if hv then hover = off + i; UI.row_at = UI.tip_side; end
            local picked = (kind == 'items' and sel == off + i);
            if UI.pad_owner == 'browse' and cur == off + i then      -- (the controller's cursor)
                local p1, p2 = col(C.pink, (picked and 0.55 or 0.36) * a), U4(C.vio[1], C.vio[2], C.vio[3], 0.0);
                DL.RFM(dl, x + 8 * s, yy + 1, x + W - 8 * s, yy + RH - 1, p1, p2, p2, p1);
                local ar = tex('sel_arrow.png');
                local asz = 14 * s;
                local bob = cfg.anim and math.sin(now * 5) * 1.5 * s or 0;
                image(dl, ar, x - asz * 0.55 + bob, yy + (RH - asz) / 2, x + asz * 0.45 + bob, yy + (RH + asz) / 2, a);
                if kind == 'items' and r[4] then UI.tip_id, UI.tip_at, UI.tip_ext, UI.tip_bi = r[4], UI.tip_side, (r.bag and r.idx) and item_extra(r.bag, r.idx) or nil, { r.bag, r.idx }; end
            end
            if picked then
                local p1, p2 = col(C.pink, 0.30 * a), U4(C.vio[1], C.vio[2], C.vio[3], 0.0);
                DL.RFM(dl, x + 8 * s, yy + 1, x + W - 8 * s, yy + RH - 1, p1, p2, p2, p1);
                DL.RF(dl, x + 8 * s, yy + 4, x + 10.5 * s, yy + RH - 4, col(C.pink, a), 2);
            elseif hv then
                DL.RF(dl, x + 8 * s, yy + 1, x + W - 8 * s, yy + RH - 1, U4(1, 1, 1, 0.07 * a), 4 * s);
            end
            if UI.br.flash and UI.br.flash.k == key and UI.br.flash.i == off + i and now - UI.br.flash.t < 0.6 then
                DL.RF(dl, x + 8 * s, yy + 1, x + W - 8 * s, yy + RH - 1, col(C.pink, 0.35 * (1 - (now - UI.br.flash.t) / 0.6) * a), 4 * s);
            end
            local tx = x + 18 * s;
            if r[4] then
                local is = RH - 6 * s;
                image(dl, item_icon(r[4]), tx, yy + 3 * s, tx + is, yy + 3 * s + is, a);
                tx = tx + is + 8 * s;
            elseif r[3] then
                if r.glow then                                       -- (ready: a soft pulsing glow)
                    local pl_ = 0.5 + 0.5 * math.sin(now * 3.4 + (off + i) * 0.7);
                    DL.CF(dl, tx + 4 * s, yy + RH / 2, (7 + 2 * pl_) * s, col(r[3], (0.10 + 0.12 * pl_) * a), 16);
                end
                DL.CF(dl, tx + 4 * s, yy + RH / 2, 5 * s, col(r[3], 0.18 * a), 12);
                DL.CF(dl, tx + 4 * s, yy + RH / 2, 3 * s, col(r[3], 0.95 * a), 12);
                tx = tx + 16 * s;
            else
                DL.CF(dl, tx + 3 * s, yy + RH / 2, 1.5 * s, col(C.dim, a), 8);
                tx = tx + 12 * s;
            end
            local c_ = r[5] and C.dim or ((hv or picked) and C.text or { 0.84, 0.82, 0.92, 1 });
            if r.sp then                                             -- (the 1-hour ability: red, larger)
                local tks = font(19 * s);
                text(dl, tx, yy + (RH - imgui.GetTextLineHeight()) / 2, r[1], r[5] and { 0.62, 0.30, 0.30, 1 } or { 1.0, 0.36, 0.33, 1 }, a);
                unfont(tks);
            else
                text(dl, tx, yy + (RH - imgui.GetTextLineHeight()) / 2, r[1], c_, a);
            end
            if r[2] and r[2] ~= '' then
                local tk2 = font(11.5 * s);
                text(dl, x + W - 18 * s - tw(r[2]), yy + (RH - imgui.GetTextLineHeight()) / 2, r[2], (r[2] == 'WORN') and C.pink or C.acc, a);
                unfont(tk2);
            end
        end
        unfont(tk);
        if #rows > NROWS then
            local tx0, t0, t1 = x + W - 6 * s, ry0, ry0 + NROWS * RH;
            DL.RF(dl, tx0, t0, tx0 + 2 * s, t1, U4(1, 1, 1, 0.06 * a), 2);
            local h_ = (t1 - t0) * NROWS / #rows;
            local o_ = (t1 - t0 - h_) * off / math.max(1, #rows - NROWS);
            DL.RF(dl, tx0, t0 + o_, tx0 + 2 * s, t0 + o_ + h_, mix(C.pink, C.vio, 0.5, 0.9 * a), 2);
        end
        -- the card: the hovered row (items: the picked one, with a USE button)
        local cy0 = y + H - CARD - 8 * s;
        DL.RF(dl, x + 10 * s, cy0, x + W - 10 * s, cy0 + CARD, U4(0, 0, 0, 0.30 * a), 8 * s);
        local show = hover or ((UI.pad_owner == 'browse') and cur) or (kind == 'items' and sel) or nil;
        if kind == 'items' then show = sel; if hover and rows[hover] and rows[hover][4] then
            local hr = rows[hover];
            UI.tip_id, UI.tip_at, UI.tip_ext, UI.tip_bi = hr[4], UI.row_at, (hr.bag and hr.idx) and item_extra(hr.bag, hr.idx) or nil, { hr.bag, hr.idx };
        end end
        local r = show and rows[show] or nil;
        if r and kind == 'items' then
            tk = font(15 * s); text(dl, x + 22 * s, cy0 + 12 * s, r[1], { 0.62, 1.0, 0.70, 1 }, a); unfont(tk);
            tk = font(12 * s); text(dl, x + 22 * s, cy0 + 32 * s, r[2] ~= '' and r[2] or 'Picked', C.dim, a); unfont(tk);
        elseif r then
            tk = font(15 * s); text(dl, x + 22 * s, cy0 + 8 * s, r[1], { 0.62, 1.0, 0.70, 1 }, a); unfont(tk);
            tk = font(12.5 * s);
            local lines = wrap(r[7] or '', W - 44 * s - ((kind == 'items') and 90 * s or 0));
            for i = 1, math.min((kind == 'items') and 4 or 2, #lines) do text(dl, x + 22 * s, cy0 + (26 + (i - 1) * 15) * s, lines[i], C.text, a); end
            unfont(tk);
        else
            tk = font(12.5 * s);
            if kind == 'abilities' and tab == 3 and #rows == 0 then
                local tk4 = font(12.5 * s);
                text(dl, x + 22 * s, ry0 + 8 * s, 'No pet commands right now (call your pet first).', C.dim, a);
                unfont(tk4);
            end
            local hint_ = (kind == 'status') and 'Left / Right or L1 / R1: pages.' or (UI.pad_owner == 'browse') and ((kind == 'items' and not B.usable) and 'Confirm: pick, again: use.  Cancel: back.' or 'Confirm: use.  Cancel: back.  L1 / R1: tabs.') or (kind == 'items') and (B.mog and 'Click an item, then TAKE / STORE.' or (B.usable and 'Click an item to use it.' or 'Hover: details.  Click an item, then USE.')) or (kind == 'keyitems' and 'Hover a key item.' or 'Click to use it.  Grey: on recast / not enough.');
            text(dl, x + 22 * s, cy0 + CARD / 2 - 8 * s, hint_, C.dim, a);
            unfont(tk);
        end
        if kind == 'items' and sel and rows[sel] then                -- USE
            local bx1, by0 = x + W - 22 * s, cy0 + 10 * s;
            local bx0, by1 = bx1 - 70 * s, by0 + 26 * s;
            local hv = hov_win and inside(mx, my, bx0, by0, bx1, by1);
            DL.RF(dl, bx0, by0, bx1, by1, hv and col(C.pink, 0.45 * a) or col(C.pink, 0.22 * a), 7 * s);
            DL.R(dl, bx0, by0, bx1, by1, col(C.pink, 0.9 * a), 7 * s, 0, 1);
            local blab = B.mog and ((rows[sel].bag == 0) and 'STORE' or 'TAKE') or 'USE';
            local tk3 = font(12 * s); caps(dl, (bx0 + bx1) / 2 - caps_w(blab, 3 * s) / 2, by0 + 6 * s, blab, C.text, 3 * s, a); unfont(tk3);
            if hv and imgui.IsMouseClicked(0) and rows[sel][6] and rows[sel][6]:sub(1, 1) == '@' then
                special_action(rows[sel][6]); UI.br.sel[kind] = nil;
            elseif hv and imgui.IsMouseClicked(0) then
                local cmd = rows[sel][6];
                pcall(function() AshitaCore:GetChatManager():QueueCommand(1, cmd); end);
                UI.br.flash = { k = key, i = sel, t = now };
                M.note('browse', cmd);
            end
        end
        if hov_win and not UI.move then
            if hover and imgui.IsMouseClicked(0) then
                if kind == 'items' and not B.usable then UI.br.sel[kind] = hover;
                elseif rows[hover][6] and rows[hover][6]:sub(1, 1) == '@' then
                    special_action(rows[hover][6]);
                elseif rows[hover][6] then
                    local cmd = rows[hover][6];
                    pcall(function() AshitaCore:GetChatManager():QueueCommand(1, cmd); end);
                    UI.br.flash = { k = key, i = hover, t = now };
                    M.note('browse', cmd);
                end
            end
            if imgui.IsMouseClicked(1) then
                if B.menu and B.stage == 'list' then B.stage = 'menu';
                elseif B.stage == 'bluset' then B.stage = nil;
                else close_browse(); end
            end
            local wheel = imgui.GetIO().MouseWheel or 0;
            if wheel ~= 0 then off = off + ((wheel > 0) and -3 or 3); end
        end
        UI.br.off[key] = math.max(0, math.min(math.max(0, #rows - NROWS), off));
    end
    imgui.End();
    UI.began = false;
    imgui.PopStyleVar(2);
    UI.pushed = 0;
end

----------------------------------------------------------------------------------------------------
-- Every frame
----------------------------------------------------------------------------------------------------
-- runs a panel; on an error ImGui's stacks are put straight (fonts, window, style) and the game's window stays
local function guarded(where, fn, ...)
    UI.began, UI.pushed, fonts.depth = false, 0, 0;
    UI.tip_scale = nil;
    UI.pwhere, UI.pmul = where, tonumber(cfg['sz_' .. where]) or 1;
    local ok, err = pcall(fn, ...);
    UI.pwhere, UI.pmul = nil, nil;
    if not ok then
        errlog(where, err);
        for _ = 1, (fonts.depth or 0) do pcall(imgui.PopFont); end
        pcall(imgui.SetWindowFontScale, 1);
        if UI.began then pcall(imgui.End); end
        if (UI.pushed or 0) > 0 then pcall(imgui.PopStyleVar, UI.pushed); end
        UI.began, UI.pushed, fonts.depth = false, 0, 0;
    end
    for k in pairs(FSTACK) do FSTACK[k] = nil; end
    FS = 1;
    return ok;
end
local last = os.clock();
----------------------------------------------------------------------------------------------------
-- Settings: ChadcoreMenu's own settings panel (/cmenu settings, or "ChadcoreMenu" in the game's Config menu).
-- Three pages (L1 / R1 or Left / Right on a page's title): General, Look, Menus. Up / Down pick a line, Left / Right
-- change it, Confirm toggles or runs it, Cancel closes. With the mouse: click a line to change it (right-click closes).
-- Every change is saved at once.
----------------------------------------------------------------------------------------------------
SET = { open = false, tab = 1, cur = 1 };
SET.THEMES = {
    { 'YunaUI',  { 1.00, 0.36, 0.62 }, { 0.62, 0.40, 1.00 }, { 0.74, 0.66, 0.95 }, { 0.86, 0.24, 0.86 } },
    { 'Crimson', { 1.00, 0.30, 0.32 }, { 0.78, 0.16, 0.38 }, { 1.00, 0.64, 0.64 }, { 0.90, 0.20, 0.30 } },
    { 'Ocean',   { 0.26, 0.76, 1.00 }, { 0.26, 0.42, 1.00 }, { 0.64, 0.82, 1.00 }, { 0.20, 0.60, 0.95 } },
    { 'Emerald', { 0.30, 0.95, 0.60 }, { 0.16, 0.66, 0.56 }, { 0.62, 0.95, 0.78 }, { 0.20, 0.80, 0.50 } },
    { 'Gold',    { 1.00, 0.76, 0.30 }, { 0.95, 0.50, 0.20 }, { 1.00, 0.86, 0.56 }, { 0.95, 0.60, 0.20 } },
    { 'Silver',  { 0.86, 0.86, 0.94 }, { 0.55, 0.58, 0.72 }, { 0.85, 0.87, 0.96 }, { 0.70, 0.70, 0.82 } },
};
SET.BGS = {
    { 'Violet night', { 0.068, 0.066, 0.088 } },
    { 'Black',        { 0.030, 0.030, 0.034 } },
    { 'Navy',         { 0.050, 0.070, 0.120 } },
    { 'Slate',        { 0.110, 0.115, 0.130 } },
    { 'Wine',         { 0.110, 0.050, 0.070 } },
};
function SET.apply()                                                 -- (the colours picked, into the palette every panel draws with)
    local th = SET.THEMES[1];
    for _, t in ipairs(SET.THEMES) do if t[1] == cfg.theme then th = t; end end
    for i = 1, 3 do C.pink[i], C.vio[i], C.acc[i], C.mag[i] = th[2][i], th[3][i], th[4][i], th[5][i]; end
    local bg = SET.BGS[1];
    for _, b in ipairs(SET.BGS) do if b[1] == cfg.panel_bg then bg = b; end end
    for i = 1, 3 do C.pbg[i] = bg[2][i]; end
end
pcall(SET.apply);
function SET.names(L) local o = {}; for i, t in ipairs(L) do o[i] = t[1]; end return o; end
-- each line: { kind, key, label, what it does, extra }  (kinds: bool, num { min, max, step, fmt }, pick { names }, run fn)
SET.PAGES = {
    { 'General', {
        { 'run',  nil,      'Refresh UI',       'Reloads ChadcoreMenu: for when a menu or the macro bars get stuck. (Or click the logo.)', function() SET.refresh(); end },
        { 'num',  'scale',  'Size',             'How big every panel is.', { 0.6, 2.0, 0.05, function(v) return math.floor(v * 100 + 0.5) .. '%'; end } },
        { 'num',  'alpha',  'Opacity',          'How solid the panels are.', { 0.5, 1.0, 0.05, function(v) return math.floor(v * 100 + 0.5) .. '%'; end } },
        { 'bool', 'follow', 'Game window spots', 'Panels sit where the game\'s own windows would (off: where you dragged them).' },
        { 'bool', 'locked', 'Lock panels',      'Panels can\'t be dragged.' },
        { 'bool', 'anim',   'Animations',       'Panels slide in, the cursor glides.' },
        { 'bool', 'hint',   'Hints',            'The picked command\'s description under the main menu.' },
        { 'bool', 'pad',    'Controller in panels', 'The d-pad and buttons drive ChadcoreMenu\'s own panels.' },
        { 'bool', 'clicks', 'Mouse clicks',     'Clicking a panel works the game\'s menu.' },
        { 'bool', 'wheel',  'Mouse wheel',      'The wheel moves the cursor.' },
        { 'bool', 'settings_row', 'UI Settings in main menu', 'This panel as the last line of the main menu.' },
        { 'bool', 'logo',   'Logo in main menu', 'The animated Chadbrowick logo at the bottom of the main menu.' },
        { 'bool', 'hide_buttons', 'Hide old menus completely', 'Also move the game\'s menu buttons out of sight (off: only the windows, as before).' },
        { 'run',  nil,      'Teach a menu',     'Open an old-style menu of the game\'s, then pick this: type what its rows say and it is drawn in the new style from then on.', function() SET.toggle(false); TCH.on = true; msg('Teach: open the game\'s menu (or it is up already) and the form appears. /cmenu teach again cancels.'); end },
        { 'run',  nil,      'Reset panel sizes', 'Every panel back to the normal size (unlock the panels, then drag a corner to resize one).', function()
            for k in pairs(cfg) do if type(k) == 'string' and k:match('^sz_') then cfg[k] = nil; end end
            msg('Every panel is back to its normal size.');
        end },
        { 'run',  nil,      'Reset panel spots', 'Every panel back in its own place.', function()
            for k in pairs(cfg) do if type(k) == 'string' and k:match('_[xy]$') and type(cfg[k]) == 'number' then cfg[k] = -1; end end
            cfg.follow = true; msg('Every panel is back in its own place.');
        end },
        { 'run',  nil,      'Relearn controller buttons', 'Confirm / Cancel are learned again from how you use the game\'s menus.', function()
            cfg.pad_ok, cfg.pad_back = '', ''; msg('Controller buttons: learned again as you use the game\'s menus.');
        end },
    } },
    { 'Look', {
        { 'pick', 'theme',    'Colour theme',  'The highlight colours of every panel.', SET.names(SET.THEMES) },
        { 'pick', 'panel_bg', 'Background',    'The panels\' background colour.', SET.names(SET.BGS) },
    } },
    { 'Menus', {
        { 'bool', 'main',      'Main menu',            'The main menu (Commands).' },
        { 'bool', 'char',      'Status / Equipment',   'The character and equipment panel.' },
        { 'bool', 'list',      'Equipment swap list',  'The list of gear next to the equipment panel.' },
        { 'bool', 'browse',    'Magic / Abilities / Items', 'The spell, ability and item panels.' },
        { 'bool', 'action',    'Action menu',          'The menu on a target (Attack, Magic...).' },
        { 'bool', 'chat',      'Chat menu',            'Say, Tell, Party... from the action menu.' },
        { 'bool', 'linkshell', 'Linkshell list',       'Commands > Linkshell: your linkshells and pearls.' },
        { 'bool', 'inspect',   'Check',                'Checking another player.' },
        { 'bool', 'trade',     'Trade',                'Trading players and NPCs.' },
        { 'bool', 'bazaar',    'Bazaar',               'Another player\'s bazaar.' },
        { 'bool', 'treasure',  'Treasure pool',        'Lot / pass, and Treasure in the action menu.' },
        { 'bool', 'macro',     'Macro bars',           'The Ctrl / Alt macro bars.' },
        { 'bool', 'macro_force', 'Force macro bar',    'Show the macro bar on Ctrl / Alt even when the game does not bring it up.' },
        { 'bool', 'zonetext',  'NPC questions',        'Answer boxes read from the game\'s own text files when the words are not in memory.' },
        { 'bool', 'lnk_swap',  'Swap linkpearl order',  'If picking a linkpearl opens the other one, turn this on (or /cmenu lsswap).' },
        { 'bool', 'evscript',  'NPC scripts',          'Read each NPC\'s own event script to know which answers its menu shows (the exact list, no guessing).' },
        { 'bool', 'teach',     'Taught menus',         'Menus you have taught (Teach a menu, or /cmenu teach) drawn in the new style.' },
        { 'bool', 'quests',    'Quests',               'The Quests screens: your quests by region and the Records of Eminence.' },
        { 'bool', 'mirror',    'Mirror all other menus', 'Any other menu of the game\'s: its words read as the game draws them, shown in the new style.' },
        { 'bool', 'teach_auto', 'Other game menus',    'Any other list menu of the game\'s drawn in the new style, its words from the game\'s own files.' },
        { 'bool', 'warp',      'Home Points / Guides', 'Home Points and Survival Guides.' },
        { 'bool', 'warp_map',  'Warp map card',        'The map beside the place picked.' },
        { 'bool', 'statcmd',   'Status screen list',   'Profile, Job Levels... Job Points.' },
        { 'bool', 'merits',    'Merit Points',         'The Merit Points screens.' },
        { 'bool', 'moogle',    'Moogle menus',         'The Moogle in your Mog House and !mog.' },
        { 'bool', 'mogcont',   'Mog House storage',    'The storage bags list.' },
        { 'bool', 'storage',   'Storage picker',       'Inventory / Wardrobe picker.' },
        { 'bool', 'delivery',  'Delivery Box',         'Receive and send.' },
        { 'bool', 'npcshop',   'NPC shops',            'Buy / Sell at NPC and guild shops.' },
        { 'bool', 'shopsell',  'Shop Sell list',       'Your items with prices when selling.' },
        { 'bool', 'npcmenu',   'Custom NPC menus',     'Server menus (EXP Guide, Hunter...).' },
        { 'bool', 'query',     'Questions',            'Yes / No and other event questions.' },
    } },
};
-- Refresh: ChadcoreMenu reloaded (the game's windows given back, then everything set up again) - for when something
-- has got stuck. Ashita's windows are made visible first, in case an event left them hidden.
function SET.refresh()
    pcall(function() AshitaCore:GetGuiManager():SetVisible(true); end);
    pcall(function() vana.gameui.show('macro_bar'); end);
    pcall(save);
    msg('Refreshing the UI...');
    pcall(function() AshitaCore:GetChatManager():QueueCommand(1, '/addon reload chadcoremenu'); end);
end
function SET.get(r)
    local v = cfg[r[2]];
    if r[1] == 'bool' then return v ~= false; end
    if r[1] == 'num' then return tonumber(v) or r[5][1]; end
    if r[1] == 'pick' then return v or r[5][1]; end
end
function SET.change(r, dir)                                          -- (dir: 1 forward / right, -1 back / left, 0 confirm)
    if r[1] == 'run' then if dir == 0 then r[5](); end
    elseif r[1] == 'bool' then cfg[r[2]] = not SET.get(r);
        if r[2] == 'macro' then pcall(function() MCR.fails, MCR.tried, MCR.sets = 0, nil, nil; end); end
        if r[2] == 'hide_buttons' and cfg.hide_buttons == false then pcall(M.unpark, nil); end
    elseif r[1] == 'num' then
        local lo, hi, st = r[5][1], r[5][2], r[5][3];
        local v = SET.get(r) + ((dir == 0) and 1 or dir) * st;
        if dir == 0 and v > hi + 1e-6 then v = lo; end
        cfg[r[2]] = math.floor(math.max(lo, math.min(hi, v)) * 100 + 0.5) / 100;
    elseif r[1] == 'pick' then
        local L, at = r[5], 1;
        for i, n in ipairs(L) do if n == SET.get(r) then at = i; end end
        at = ((at - 1 + ((dir == 0) and 1 or dir)) % #L) + 1;
        cfg[r[2]] = L[at];
        SET.apply();
    end
    pcall(save);
end
function SET.toggle(on)
    if on == nil then on = not SET.open; end
    SET.open = on;
    if on then SET.cur = SET.cur or 1; UI.settings = nil; end      -- (its slide-in again)
end
function SET.pad(acts)
    local P = SET.PAGES[SET.tab][2];
    for _, act in ipairs(acts) do
        local n = #P + 1;                                            -- (the last line: Close)
        if act == 'up' then SET.cur = (SET.cur > 1) and (SET.cur - 1) or n;
        elseif act == 'down' then SET.cur = (SET.cur < n) and (SET.cur + 1) or 1;
        elseif SET.cur > #P and act == 'ok' then SET.toggle(false); return;
        elseif SET.cur > #P then
        elseif act == 'left' then SET.change(P[SET.cur], -1);
        elseif act == 'right' then SET.change(P[SET.cur], 1);
        elseif act == 'ok' then SET.change(P[SET.cur], 0);
        elseif act == 'tabl' or act == 'tabr' then
            SET.tab = ((SET.tab - 1 + ((act == 'tabr') and 1 or -1)) % #SET.PAGES) + 1; SET.cur = 1; P = SET.PAGES[SET.tab][2];
        elseif act == 'back' then SET.toggle(false); return; end
    end
end
function SET.draw()
    local s = PSCALE();
    local page = SET.PAGES[SET.tab];
    local P = page[2];
    SET.cur = math.max(1, math.min(#P + 1, SET.cur));
    local rows = {};
    for i, r in ipairs(P) do
        local v = SET.get(r);
        local shown = '';
        if r[1] == 'bool' then shown = v and 'ON' or 'OFF';
        elseif r[1] == 'num' then shown = '< ' .. r[5][4](v) .. ' >';
        elseif r[1] == 'pick' then shown = '< ' .. v .. ' >';
        elseif r[1] == 'run' then shown = '>'; end
        rows[i] = { r[3], shown, nil, r[1] == 'bool' and not v };
    end
    rows[#P + 1] = { 'Close', 'X' };
    local tabs = {};
    for i, p in ipairs(SET.PAGES) do tabs[i] = (i == SET.tab) and ('[' .. p[1] .. ']') or p[1]; end
    local sw, sh = screen();
    local W = math.floor(380 * s);
    local x, y = math.floor((sw - W) / 2), math.floor(sh * 0.18);
    local clicked, wd = list_panel('settings', x, y, W, 'CHADCOREMENU ' .. addon.version, table.concat(tabs, '   '), rows, SET.cur,
        { focused = true, foot = (P[SET.cur] and P[SET.cur][4] or 'Close the settings.') .. '   L1 / R1: pages', on_cancel = function() SET.toggle(false); end });
    if clicked and clicked > #P then SET.toggle(false); return;
    elseif clicked then SET.cur = clicked; SET.change(P[clicked], 0); end
    if wd ~= 0 then SET.cur = math.max(1, math.min(#P + 1, SET.cur + wd)); end
    -- (the page names in the title line: click one to go there)
    pcall(function()
        if imgui.IsMouseClicked(0) then
            local mx, my = mouse();
            local px, py = saved_pos('settings', x, y, W, 10);
            if my >= py + 20 * s and my <= py + 40 * s and mx >= px + 16 * s then
                local tk = font(15 * s);
                local cx = px + 16 * s;
                for i = 1, #tabs do
                    local w_ = tw(tabs[i]);
                    if mx >= cx and mx <= cx + w_ then SET.tab, SET.cur = i, 1; end
                    cx = cx + w_ + tw('   ');
                end
                unfont(tk);
            end
        end
    end);
end
pcall(function() vana.gameui.add('config_menu', 'ChadcoreMenu', function() SET.toggle(true); end); end);


----------------------------------------------------------------------------------------------------
-- Quests (the main menu's Quests): the game's "quest00" screen and everything under it, drawn by ChadcoreMenu from
-- what the server sends - the quest log (0x056: one 32-byte set of bits a region, which quests are under way and
-- which done), the Records of Eminence (0x111: the 30 objectives taken on, each with its progress; 0x112: which
-- are done) and the currencies (0x113: Sparks, Accolades, Deeds) - and the game's own words for them (questdata.lua
-- and roedata.lua next to this file, read out of its data files). The panel keeps its own place in the menus; the
-- game's screen stays on its first page underneath, and only Cancel at the top goes to it. The quest log comes
-- at login and when you zone: until it has, the regions are the game's own screen.
----------------------------------------------------------------------------------------------------
QST = { log = {}, roe = nil, done = {}, cur = {}, st = nil, asked = 0 };
QST.REGIONS = { { 'sd', 0x50, 0x90 }, { 'bs', 0x58, 0x98 }, { 'ws', 0x60, 0xA0 }, { 'jn', 0x68, 0xA8 }, { 'ot', 0x70, 0xB0 }, { 'fr', 0x78, 0xB8 },
                { 'at', 0x80, 0xC0, 16 }, { 'wog', 0x88, 0xC8 }, { 'aby', 0xE0, 0xE8 }, { 'ad', 0xF0, 0xF8 }, { 'wc', 0x100, 0x108 } };
function QST.packet(id, d)
    local function u(o, n) local v = 0; for i = n - 1, 0, -1 do v = v * 256 + (d:byte(o + i + 1) or 0); end return v; end
    if id == 0x056 and #d >= 0x26 then
        local t = u(0x24, 2);
        QST.log[t] = d:sub(5, 0x24);
        QST.log_t = os.clock();
        M.note('questlog' .. t, ('quest log type %04X received (%d bytes)'):format(t, #d));
    elseif id == 0x111 and #d >= 0x7C then
        local L = {};
        for i = 0, 29 do
            local v = u(0x04 + i * 4, 4);
            local qid = v % 4096;
            if qid ~= 0 then L[#L + 1] = { id = qid, p = math.floor(v / 4096) }; end
        end
        QST.roe, QST.roe_t = L, os.clock();
        M.note('roelog', ('Records received: %d objectives (%d bytes)'):format(#L, #d));
    elseif id == 0x112 and #d >= 0x88 then
        QST.done[u(0x84, 4)] = d:sub(5, 4 + 128);
    elseif id == 0x113 and #d >= 0xFC then
        local function i32(o) local v = u(o, 4); if v >= 2147483648 then v = v - 4294967296; end return v; end
        QST.cur = { sparks = i32(0x74), accolades = i32(0xE4), deeds = i32(0xF8), t = os.clock() };
        M.note('curlog', ('currencies received: sparks %d accolades %d deeds %d (%d bytes)'):format(QST.cur.sparks, QST.cur.accolades, QST.cur.deeds, #d));
    elseif id == 0x113 or id == 0x111 or id == 0x112 then
        M.note('shortpk' .. id, ('packet %03X shorter than expected: %d bytes'):format(id, #d));
    end
end
function QST.ask()                                                   -- (the Records and the currencies asked of the server: they come at once)
    if os.clock() - QST.asked < 15 then return; end
    QST.asked = os.clock();
    pcall(function() AshitaCore:GetPacketManager():AddOutgoingPacket(0x112, { 0, 0, 0, 0, 0, 0, 0, 0 }); end);
    pcall(function() AshitaCore:GetPacketManager():AddOutgoingPacket(0x10F, { 0, 0, 0, 0 }); end);
end
function QST.data()
    if QST.D == nil then
        QST.D = false;
        local ok, q = pcall(dofile, addon.path .. 'questdata.lua');
        local ok2, r = pcall(dofile, addon.path .. 'roedata.lua');
        if ok and type(q) == 'table' and ok2 and type(r) == 'table' then QST.D = { q = q, roe = r };
        else M.note('questdata', 'questdata.lua / roedata.lua not read: ' .. tostring(ok and r or q)); end
    end
    return QST.D or nil;
end
function QST.bits(str, i)                                            -- (bit i of a string of bytes)
    local b = str and str:byte(math.floor(i / 8) + 1);
    return b ~= nil and bit.band(b, bit.lshift(1, i % 8)) ~= 0;
end
function QST.region_quests(r, mode)                                  -- (the quests of a region under way (cur) or done)
    local D = QST.data(); if not D then return nil; end
    local names = D.q[r[1]]; if not names then return nil; end
    local cur, done = QST.log[r[2]], QST.log[r[3]];
    if not cur and not done then return nil; end
    local lim = (r[4] or 32) * 8;
    local out = {};
    for i = 0, lim - 1 do
        local c, dn = QST.bits(cur, i), QST.bits(done, i);
        local want = (mode == 'done') and dn or (c and not dn);
        if want and names[i] then out[#out + 1] = { no = i, name = names[i][1], about = names[i][2] }; end
    end
    return out;
end
function QST.roe_done(id)
    local chunk = QST.done[math.floor(id / 1024)];
    return QST.bits(chunk, id % 1024);
end
function QST.done_count()
    local n = 0;
    for _, chunk in pairs(QST.done) do
        for i = 1, #chunk do local b = chunk:byte(i); while b > 0 do n = n + bit.band(b, 1); b = bit.rshift(b, 1); end end
    end
    return n;
end
function QST.active(id) for _, e in ipairs(QST.roe or {}) do if e.id == id then return e; end end return nil; end
function QST.open(w)
    QST.st = { addr = w.addr, page = 'main', cur = 1, off = 0, stack = {} };
    QST.ask();
end
function QST.push(page, extra)
    local st = QST.st;
    st.stack[#st.stack + 1] = { page = st.page, cur = st.cur, off = st.off, mode = st.mode, region = st.region, cat = st.cat };
    st.page, st.cur, st.off = page, 1, 0;
    for k, v in pairs(extra or {}) do st[k] = v; end
end
function QST.pop()
    local st = QST.st;
    local top = table.remove(st.stack);
    if not top then return false; end
    st.page, st.cur, st.off, st.mode, st.region, st.cat = top.page, top.cur, top.off, top.mode, top.region, top.cat;
    return true;
end
function QST.gs(n) return DLV.gs(n or 0); end
function QST.rows()                                                  -- (the page's rows, its title line and foot; .enter(i) acts on a row)
    local st, D = QST.st, QST.data();
    local R = { rows = {}, title = 'QUESTS', sub = '', foot = nil };
    if st.page == 'main' then
        local nroe = #(QST.roe or {});
        local haslog = next(QST.log) ~= nil;
        R.sub = 'Quests and Records of Eminence';
        R.rows = { { 'Current quests', haslog and '>' or 'zone once first', nil, not haslog }, { 'Completed quests', haslog and '>' or 'zone once first', nil, not haslog },
                   { 'Eminence: current objectives', QST.roe and (nroe .. ' / 30') or '>' }, { 'Eminence: objective list', '>' },
                   { 'Game\'s own screen', '>' } };
        local c = QST.cur;
        R.foot = ('Sparks %s   Accolades %s   Deeds %s   Objectives done %d'):format(c.sparks and QST.gs(c.sparks) or '-', c.accolades and QST.gs(c.accolades) or '-', c.deeds and QST.gs(c.deeds) or '-', QST.done_count());
        R.enter = function(i)
            if (i == 1 or i == 2) and not haslog then msg('Your quest log comes from the server when you zone: zone once (or log out and in), then open Quests again.'); return; end
            if i == 1 then QST.push('regions', { mode = 'cur' });
            elseif i == 2 then QST.push('regions', { mode = 'done' });
            elseif i == 3 then QST.push('roe');
            elseif i == 4 then QST.push('cats', { cat = 100512 });
            elseif i == 5 then QST.off_addr = st.addr; QST.st = nil; end
        end
    elseif st.page == 'regions' then
        R.sub = (st.mode == 'done') and 'Completed quests: where' or 'Current quests: where';
        for _, r in ipairs(QST.REGIONS) do
            local L = QST.region_quests(r, st.mode);
            local nm = D and D.q[r[1]] and D.q[r[1]].name or r[1];
            R.rows[#R.rows + 1] = { nm, L and tostring(#L) or '-', nil, L == nil or #L == 0 };
        end
        R.enter = function(i) local L = QST.region_quests(QST.REGIONS[i], st.mode); if L and #L > 0 then QST.push('quests', { region = i }); end end
    elseif st.page == 'quests' then
        local r = QST.REGIONS[st.region];
        local L = QST.region_quests(r, st.mode) or {};
        R.sub = ((D and D.q[r[1]].name) or '') .. ': ' .. ((st.mode == 'done') and 'Completed' or 'Current');
        for _, e in ipairs(L) do R.rows[#R.rows + 1] = { e.name, '' }; end
        local e = L[st.cur];
        R.foot = e and (e.about or ''):match('^[^\n]*') or nil;
        R.tip = e and e.about or nil;
        R.enter = function() end
    elseif st.page == 'roe' then
        if not QST.roe then QST.ask(); end
        R.title, R.sub = 'RECORDS OF EMINENCE', ('Current objectives  (%d of 30)'):format(#(QST.roe or {}));
        for _, e in ipairs(QST.roe or {}) do
            local q = D and D.roe.q[e.id];
            local tgt = q and q[2] or 0;
            R.rows[#R.rows + 1] = { q and q[1] or ('Objective ' .. e.id), (tgt > 0) and (e.p .. ' / ' .. tgt) or tostring(e.p), bar = (tgt > 0) and (e.p / tgt) or nil };
        end
        if #R.rows == 0 then R.rows[1] = { QST.roe and 'No objectives taken on.' or 'Waiting for the server...', '', nil, true }; end
        local e = (QST.roe or {})[st.cur]; local q = e and D and D.roe.q[e.id];
        R.tip = q and q[3] or nil;
        R.enter = function() end
    elseif st.page == 'cats' then
        local c = D and D.roe.c[st.cat];
        R.title = 'RECORDS OF EMINENCE';
        R.sub = (c and c[1] ~= '') and c[1] or 'Objective list';
        for _, ch in ipairs(c and c[2] or {}) do
            if ch >= 100000 then
                local sub = D.roe.c[ch];
                if sub and sub[1] ~= '' then R.rows[#R.rows + 1] = { sub[1], '>', kind = 'cat', ref = ch }; end
            else
                local q = D.roe.q[ch];
                if q then
                    local a = QST.active(ch);
                    local right = a and ((q[2] > 0) and (a.p .. ' / ' .. q[2]) or 'taken on') or (QST.roe_done(ch) and 'done' or '');
                    R.rows[#R.rows + 1] = { q[1], right, nil, QST.roe_done(ch) and not a, kind = 'q', ref = ch, bar = a and q[2] > 0 and (a.p / q[2]) or nil };
                end
            end
        end
        local row = R.rows[st.cur];
        local q = row and row.kind == 'q' and D.roe.q[row.ref];
        R.tip = q and q[3] or nil;
        R.foot = 'To take an objective on or drop it, use the game\'s own screen (Quests > Game\'s own screen).';
        R.enter = function(i) local r_ = R.rows[i]; if r_ and r_.kind == 'cat' then QST.push('cats', { cat = r_.ref }); end end
    end
    return R;
end
function QST.draw(w)
    local s = PSCALE();
    local st = QST.st;
    if not st or st.addr ~= w.addr then QST.open(w); st = QST.st; end
    local R = QST.rows();
    local n = #R.rows;
    st.cur = math.max(1, math.min(math.max(1, n), st.cur));
    local VIS = 12;
    if st.cur <= st.off then st.off = st.cur - 1; elseif st.cur > st.off + VIS then st.off = st.cur - VIS; end
    st.off = math.max(0, math.min(math.max(0, n - VIS), st.off));
    local rows = {};
    for i = 1, math.min(VIS, n - st.off) do rows[i] = R.rows[st.off + i]; end
    local foot = R.foot or ((n > VIS) and ('%d of %d.  Up / Down, Confirm: open.  Cancel: back.'):format(st.cur, n) or 'Confirm: open.  Cancel: back.');
    local nat = cfg.follow and M.to_screen(w.rect) or nil;
    local x, y = nat and nat[1] or 60, nat and nat[2] or 120;
    local clicked, wd, box = list_panel('quests', x, y, math.floor(420 * s), R.title, R.sub, rows, st.cur - st.off,
        { focused = (M.focus == w.addr), foot = foot, min_rows = math.min(VIS, math.max(5, n)), on_cancel = function() QST.back(); end });
    if R.tip and R.tip ~= '' and box then                            -- (what the highlighted one is about, beside the panel)
        pcall(QST.tip, R.tip, box, s);
    end
    if clicked then
        local i = st.off + clicked;
        if i == st.cur then QST.enter(R, i); else st.cur = i; end
    end
    if wd ~= 0 then st.cur = math.max(1, math.min(n, st.cur + wd)); end
    return true;
end
function QST.tip(txt, box, s)
    local x, y = box[1] + box[3] + 8 * s, box[2];
    local W = math.floor(300 * s);
    imgui.SetNextWindowPos({ x - 4, y - 4 }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ W + 8, math.floor(420 * s) }, ImGuiCond_Always);   -- (room enough: the panel inside is as tall as its text)
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    UI.pushed = 2;
    local opened = imgui.Begin('##ccm_questtip', { true }, win_flags());
    UI.began = true;
    if opened then
        local dl = imgui.GetWindowDrawList();
        local lines = {};
        local tk = font(13 * s);
        for para in (txt .. '\n'):gmatch('([^\n]*)\n') do
            local line = '';
            for word in para:gmatch('%S+') do
                local try = (line == '') and word or (line .. ' ' .. word);
                if tw(try) > W - 24 * s and line ~= '' then lines[#lines + 1] = line; line = word; else line = try; end
            end
            lines[#lines + 1] = line;
            if #lines > 18 then break; end
        end
        local lh = imgui.GetTextLineHeight();
        local H = math.floor(16 * s + #lines * (lh + 2 * s));
        panel(dl, x, y, x + W, y + H, 1, s);
        for i, l in ipairs(lines) do text(dl, x + 12 * s, y + 8 * s + (i - 1) * (lh + 2 * s), l, C.muted, 1); end
        unfont(tk);
    end
    imgui.End();
    UI.began = false;
    imgui.PopStyleVar(2);
    UI.pushed = 0;
end
function QST.enter(R, i) if R.enter then R.enter(i); end end
function QST.back()
    if not QST.st then return; end
    if not QST.pop() then QST.off_addr = QST.st.addr; QST.st = nil; M.act(nil, nil, KEY.cancel); end   -- (the game's screen closes: not ours again till then)
end
function QST.pad(acts)
    local st = QST.st;
    if not st then return; end
    for _, act in ipairs(acts) do
        local R = QST.rows(); local n = #R.rows;
        if act == 'up' then st.cur = (st.cur > 1) and (st.cur - 1) or math.max(1, n);
        elseif act == 'down' then st.cur = (st.cur < n) and (st.cur + 1) or 1;
        elseif act == 'tabl' then st.cur = math.max(1, st.cur - 12);
        elseif act == 'tabr' then st.cur = math.min(math.max(1, n), st.cur + 12);
        elseif act == 'ok' then QST.enter(R, st.cur);
        elseif act == 'back' then QST.back(); end
    end
end
----------------------------------------------------------------------------------------------------
-- Teach mode: a list menu of the game's that ChadcoreMenu doesn't know, drawn in the new style once you've said what
-- its rows say. /cmenu teach (or "Teach this menu" in the settings) with the old menu up opens a form: a title and one
-- line per row the game draws. Save keeps it (cfg.taught, by the window's name and its number of rows), and from then
-- on that menu is drawn like the rest, the game's own rows doing the work underneath - its cursor, its greying out.
-- Menus whose rows are data (prices, items, points) can't be taught: those need their own source.
----------------------------------------------------------------------------------------------------
TCH = { on = false, st = nil };
TCH.NEVER = { inline = true, logwindo = true, logwin2 = true, chatctrl = true, mcr1long = true, mcr2long = true, targetwi = true,
              gmtell = true, query = true, buff = true, partywin = true, netstat = true, helpwind = true, titlewin = true, chdummy = true };
function TCH.rows(w)                                                 -- (the rows the game draws, top to bottom - as SMALLMENU)
    local b = {};
    for _, x in ipairs(M.buttons(w)) do
        if (x.h or 0) >= 12 and (x.y or 0) > -1000 and (x.shape ~= 0 or x.user ~= 0) and x.no >= 1 and x.no <= w.buttons then b[#b + 1] = x; end
    end
    table.sort(b, function(p_, q_) if p_.y ~= q_.y then return p_.y < q_.y; end return p_.no < q_.no; end);
    return b;
end
function TCH.key(w, b) return w.name .. ':' .. #b; end
function TCH.candidate()                                             -- (the focused window of the game's that nothing of ours took)
    local w = M.open[M.focus or 0];
    if not w or w.closing or TCH.NEVER[w.name] then return nil; end
    local h = M.hidden[w.addr];
    if h and h.seen == M.frame then return nil; end
    local b = TCH.rows(w);
    if #b < 1 or #b > 40 then return nil; end
    return w, b;
end
function TCH.taught(w, b)
    local t = cfg.taught and cfg.taught[TCH.key(w, b)];
    if not t or type(t.rows) ~= 'table' or #t.rows ~= #b then return nil; end
    return t;
end
-- The game's own words for its menus (menulabels.lua next to this file: every window's row labels, title and help
-- lines, read out of the game's data files). A menu that's a single column of labelled rows is drawn in the new
-- style without being taught; anything else (a grid, rows the game fills in) is offered in the teach form, filled in.
function TCH.labels()
    if TCH.LAB == nil then
        TCH.LAB = false;
        local ok, t = pcall(dofile, addon.path .. 'menulabels.lua');
        if ok and type(t) == 'table' then TCH.LAB = t; else M.note('menulabels', 'menulabels.lua not read: ' .. tostring(t)); end
    end
    return TCH.LAB or nil;
end
-- (rows added to the game's menus by VanaCore itself, after the game's own: its Config menu entries, in its order)
TCH.EXTRA = { configwi = { 'VanaCore', 'HUD', 'FPS Graph', 'Game Stats', 'ChadcoreMenu' } };
function TCH.known(w, b)                                             -- (the game's labels for these rows; .missing = how many it lacks)
    local L = TCH.labels();
    local m = L and L[w.name];
    if not m then return nil; end
    local rows, hints, missing = {}, {}, 0;
    local top = 0; for k in pairs(m) do if type(k) == 'number' and k > top then top = k; end end
    for i, x in ipairs(b) do
        local e = m[x.no];
        if e then rows[i], hints[i] = e[1], e[2];
        else
            local ex = TCH.EXTRA[w.name];
            local lab = ex and x.no > top and ex[x.no - top];
            if lab then rows[i] = lab; else rows[i] = ''; missing = missing + 1; end
        end
    end
    return { title = (m.t or w.name):upper(), rows = rows, hints = hints, auto = true, missing = missing };
end
function TCH.auto(w, b)
    if cfg.teach_auto == false then return nil; end
    local t = TCH.known(w, b);
    if not t or t.missing > 0 then
        if t and TCH.noted ~= TCH.key(w, b) then TCH.noted = TCH.key(w, b); M.note('teach_miss' .. os.clock(), ('%s: %d of %d rows without a label in the game\'s files (buttons %s): teach it'):format(w.name, t.missing, #b, (function() local o = {}; for i, x in ipairs(b) do o[i] = tostring(x.no); end return table.concat(o, ','); end)())); end
        return nil;
    end
    for i = 2, #b do if b[i].x ~= b[1].x then return nil; end end  -- (one column of rows: a list, not a grid of settings)
    return t;
end
function TCH.draw_taught(w, b, t)                                    -- (a taught menu: the new style over the game's rows)
    local items = {};
    for i = 1, #b do items[i] = { t.rows[i] ~= '' and t.rows[i] or ('Row ' .. i), t.hints and t.hints[i] or nil }; end
    return SMALLMENU(w, 'taught_' .. w.name, (t.title and t.title ~= '') and t.title or w.name:upper(), t.sub or '', items);
end
function TCH.start(w, b)
    local t = TCH.taught(w, b) or (cfg.taught and cfg.taught[TCH.key(w, b)]) or TCH.known(w, b);
    local st = { addr = w.addr, name = w.name, n = #b, title = { (t and t.title) or w.name:upper() }, rows = {}, focus = 1 };
    for i = 1, #b do st.rows[i] = { (t and t.rows and t.rows[i]) or '' }; end
    st.known = (t ~= nil) and not t.auto;
    TCH.st = st;
end
function TCH.save()
    local st = TCH.st;
    if not st then return; end
    cfg.taught = cfg.taught or {};
    local rows = {};
    for i = 1, st.n do rows[i] = (st.rows[i][1] or ''):gsub('^%s+', ''):gsub('%s+$', ''); end
    cfg.taught[st.name .. ':' .. st.n] = { title = (st.title[1] or ''):gsub('^%s+', ''):gsub('%s+$', ''), rows = rows };
    pcall(save);
    M.note('teach' .. os.clock(), ('taught %s (%d rows): %s'):format(st.name, st.n, table.concat(rows, ' | ')));
    msg(('Learned the %s menu (%d rows). It is drawn in the new style from now on.'):format(st.name, st.n));
    TCH.st, TCH.on = nil, false;
end
function TCH.forget()
    local st = TCH.st;
    if st and cfg.taught then cfg.taught[st.name .. ':' .. st.n] = nil; pcall(save); msg(('Forgot the %s menu: the game\'s own again.'):format(st.name)); end
    TCH.st, TCH.on = nil, false;
end
function TCH.form()                                                  -- the form: a title, a line per row, Save / Cancel / Forget
    local st = TCH.st;
    if not st then return; end
    local s = PSCALE();
    local sw, sh = screen();
    local W, RH, P = math.floor(400 * s), math.floor(26 * s), math.floor(14 * s);
    local HEAD = math.floor(44 * s);
    local H = HEAD + (st.n + 1) * RH + math.floor(44 * s) + P;
    local x, y = saved_pos('teach', math.floor((sw - W) / 2), math.floor(sh * 0.15), W, H);
    imgui.SetNextWindowPos({ x - 4, y - 4 }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ W + 8, H + 8 }, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    UI.pushed = 2;
    local opened = imgui.Begin('##ccm_teach', { true }, win_flags());
    UI.began = true;
    if opened then
        local dl = imgui.GetWindowDrawList();
        local mx, my = mouse();
        local clk = imgui.IsMouseClicked(0);
        panel(dl, x, y, x + W, y + H, 1, s);
        local tk = font(11 * s);
        caps(dl, x + P, y + 8 * s, 'TEACH THIS MENU', C.acc, 2.2 * s, 1);
        unfont(tk);
        tk = font(13 * s);
        text(dl, x + P, y + 22 * s, ('%s - %d rows.  Type what each row says, then Save.'):format(st.name, st.n), C.dim, 1);
        unfont(tk);
        local function field(i, label, buf, ry)
            tk = font(13 * s);
            text(dl, x + P, ry + (RH - imgui.GetTextLineHeight()) / 2, label, (st.focus == i) and C.pink or C.dim, 1);
            unfont(tk);
            local fx0, fx1 = x + P + 60 * s, x + W - P;
            DL.RF(dl, fx0, ry + 2, fx1, ry + RH - 2, U4(0.08, 0.07, 0.11, 0.9), 5 * s);
            DL.R(dl, fx0, ry + 2, fx1, ry + RH - 2, (st.focus == i) and col(C.pink, 0.8) or U4(0.62, 0.40, 1.0, 0.3), 5 * s, 0, 1);
            if imgui.InputText and imgui.SetCursorScreenPos and imgui.PushItemWidth then
                pcall(imgui.SetCursorScreenPos, { fx0 + 6 * s, ry + (RH - imgui.GetTextLineHeight()) / 2 - 2 * s });
                local pw = pcall(imgui.PushItemWidth, fx1 - fx0 - 12 * s);
                local pc = ImGuiCol_FrameBg and imgui.PushStyleColor and pcall(imgui.PushStyleColor, ImGuiCol_FrameBg, { 0, 0, 0, 0 });
                pcall(function()
                    if st.focus_to == i then st.focus_to = nil; if imgui.SetKeyboardFocusHere then imgui.SetKeyboardFocusHere(0); end end
                    local done = imgui.InputText('##ccm_tch' .. i, buf, 48, ImGuiInputTextFlags_EnterReturnsTrue or 0);
                    if done and ImGuiInputTextFlags_EnterReturnsTrue then st.focus_to = (i < st.n + 1) and (i + 1) or nil; end   -- (Enter: the next line)
                    if imgui.IsItemActive and imgui.IsItemActive() then st.focus = i; st.typing = M.frame; end
                end);
                if pc then pcall(imgui.PopStyleColor, 1); end
                if pw then pcall(imgui.PopItemWidth); end
            else
                tk = font(13 * s); text(dl, fx0 + 6 * s, ry + (RH - imgui.GetTextLineHeight()) / 2, buf[1] or '', C.text, 1); unfont(tk);
            end
            if clk and inside(mx, my, fx0, ry, fx1, ry + RH) then st.focus = i; st.focus_to = i; end
        end
        local ry = y + HEAD;
        field(0, 'Title', st.title, ry); ry = ry + RH;
        for i = 1, st.n do field(i, 'Row ' .. i, st.rows[i], ry); ry = ry + RH; end
        -- the buttons
        local by = ry + 8 * s;
        local BW, BH = math.floor(90 * s), math.floor(26 * s);
        local function button(label, bx, hot)
            local hv = inside(mx, my, bx, by, bx + BW, by + BH);
            DL.RF(dl, bx, by, bx + BW, by + BH, hot and col(C.pink, hv and 0.55 or 0.35) or U4(0.62, 0.40, 1.0, hv and 0.35 or 0.18), 6 * s);
            DL.R(dl, bx, by, bx + BW, by + BH, hv and U4(1, 1, 1, 0.35) or U4(0.62, 0.40, 1.0, 0.3), 6 * s, 0, 1);
            tk = font(13 * s);
            text(dl, bx + (BW - tw(label)) / 2, by + (BH - imgui.GetTextLineHeight()) / 2, label, C.text, 1);
            unfont(tk);
            return clk and hv;
        end
        if button('Save', x + P, true) then TCH.save(); end
        if button('Cancel', x + P + BW + 10 * s) then TCH.st, TCH.on = nil, false; end
        if st.known and button('Forget', x + W - P - BW) then TCH.forget(); end
    end
    imgui.End();
    UI.began = false;
    imgui.PopStyleVar(2);
    UI.pushed = 0;
end
function TCH.frame()                                                 -- (each frame, after every other panel)
    UI.teach_drawn = false;
    if cfg.teach == false then return; end
    local w, b = TCH.candidate();
    if TCH.st then                                                   -- (the form is up: it follows the window it was opened on)
        local fw = M.open[TCH.st.addr];
        if not fw or fw.closing then TCH.st = nil; TCH.on = false;
        else guarded('teach', TCH.form); UI.teach_drawn = true; return; end
    end
    if not w then
        if TCH.on and M.frame % 30 == 0 then end
        return;
    end
    local t = TCH.taught(w, b) or TCH.auto(w, b);
    if TCH.on and not TCH.st then TCH.start(w, b); guarded('teach', TCH.form); UI.teach_drawn = true; return; end
    if t then
        UI.small_ok = false;
        guarded('taught_' .. w.name, function() UI.small_ok = TCH.draw_taught(w, b, t); end);
        if UI.small_ok then M.hide(w, 'park'); end
    end
end

local function frame()
    M.frame = M.frame + 1;
    local now = os.clock();
    UI.dt = math.min(0.1, now - last);
    last = now;
    if not M.init() then M.open = {}; M.hidden = {}; return; end
    if not cfg.enabled then
        if next(M.hidden) ~= nil then M.scan(); M.release(true); end
        return;
    end
    M.scan();
    pcall(track_worn);
    if cfg.survey then pcall(M.survey); end
    M.run_queue();
    local visible = true;
    pcall(function() visible = AshitaCore:GetFontManager():GetVisible(); end);
    -- (an NPC's event hides the interface - and with it Ashita's own windows - though its menu is up: while the Home Point /
    --  Survival Guide list is up, ChadcoreMenu's windows are shown anyway, and then left to Ashita again)
    local warp_on = (WARP.ev and M.find('query') and cfg.warp ~= false) or QRY.want() or QRY.card_wanted();
    if warp_on then
        if not visible then visible = true; end
        pcall(function()
            local gm = AshitaCore:GetGuiManager();
            if not gm:GetVisible() then
                if UI.gui_forced and UI.gui_ok ~= false then         -- (it was put back to hidden since last frame: can't be shown -
                    UI.gui_ok = false;                               --  then the game's own menus stay, so nothing is picked unseen)
                    M.note('warp_gui' .. os.clock(), 'Ashita keeps its windows hidden during the event: the game menus are used');
                elseif UI.gui_forced == nil then
                    UI.gui_forced = true; UI.gui_fixup = true; M.note('warp_gui' .. os.clock(), 'interface hidden by the event: showing the list anyway');
                end
                if UI.gui_ok ~= false then gm:SetVisible(true); end
            end
        end);
    else
        UI.gui_forced, UI.gui_ok = nil, nil;                         -- (Ashita hides / shows its windows again itself)
        -- (after an event where they were shown by force: once the game's interface is back, Ashita's windows must be
        --  too - if they stay hidden, they're shown again, so nothing is left hidden till a reload)
        if UI.gui_fixup then
            UI.gui_fix_t = UI.gui_fix_t or now;
            if visible and now - UI.gui_fix_t > 1.0 then
                pcall(function()
                    local gm = AshitaCore:GetGuiManager();
                    if not gm:GetVisible() then gm:SetVisible(true); M.note('warp_gui' .. os.clock(), 'after the event: Ashita\'s windows shown again'); end
                end);
                UI.gui_fixup, UI.gui_fix_t = nil, nil;
            elseif not visible then UI.gui_fix_t = now; end
        end
    end
    if not visible then M.release(true); return; end

    -- your own hide list (/cmenu hide): those game windows stay out of sight; they keep working underneath
    if (cfg.always_hide or '') ~= '' then
        local set = {};
        for _, n in ipairs(split(cfg.always_hide)) do set[n] = true; end
        for _, w in ipairs(M.wins) do if set[w.name] then M.hide(w, 'park'); end end
    end

    -- the main menu
    local mw = cfg.main and M.find(cfg.main_name) or nil;
    if mw and not mw.closing and cfg.trace then pcall(M.trace, mw); end
    if UI.learn and mw and not mw.closing then                       -- /cmenu learn: each press of Down shows the next command
        local L = UI.learn;
        if L.last ~= mw.cursor then
            L.last = mw.cursor;
            if #L.seq >= 2 and mw.cursor == L.seq[1] then             -- back at the first one: that's every command
                cfg.main_order = table.concat(L.seq, ','); save();
                M.ord = {}; UI.main.warned = true; UI.learn = nil;
                msg(('Learned the main menu: %d commands. (/cmenu learn reset to forget)'):format(#L.seq));
            else
                local dup = false;
                for _, v in ipairs(L.seq) do if v == mw.cursor then dup = true; end end
                if dup then
                    UI.learn = { seq = {}, last = nil };
                    msg('That went back up: start again from Status and press only Down.');
                else
                    L.seq[#L.seq + 1] = mw.cursor;
                end
            end
        end
    end
    if mw and not mw.closing and mw.buttons > 0 then
        if guarded('main', draw_main, mw) then M.hide(mw, cfg.main_hide); end
    else
        UI.main.t0, UI.main.y = nil, nil;
        UI.mainbox = nil;
    end

    -- the action menu on a target
    -- (the game keeps its action menu open, unseen, when you're not using it - e.g. while you're in the main menu: it's
    --  only shown from when it has the focus until the main menu takes it or nothing has it)
    local aw = cfg.action and M.find('playermo') or nil;
    if aw and M.focus == aw.addr then UI.act_live = true;
    elseif not aw or M.focus == 0 or (mw and M.focus == mw.addr) then UI.act_live = false; end
    if aw and not aw.closing and aw.buttons > 0 and UI.act_live and UI.browse and UI.browse_drawn then
        M.hide(aw, cfg.act_hide or 'park');                          -- (its Magic / Abilities / Items list is up: the action menu steps aside)
        if UI.act then UI.act.t0 = nil; end
    elseif aw and not aw.closing and aw.buttons > 0 and UI.act_live then
        UI.act_skip = false;
        if guarded('action', draw_action, aw) and not UI.act_skip then M.hide(aw, cfg.act_hide or 'park'); end
    elseif UI.act then
        UI.act.t0, UI.act.y = nil, nil;
    end

    -- the Mog House storage menu (View House)
    local mcw = (cfg.mogcont ~= false) and M.find('mogcont') or nil;
    if mcw and M.focus == mcw.addr and mcw.buttons > 0 then
        if guarded('mogcont', draw_mogcont, mcw) then M.hide(mcw, 'park'); end
    end

    -- the Moogle's menu, and its Storage list (the same bags as View House)
    local myw = (cfg.moogle ~= false) and M.find('myroom') or nil;
    if myw and not myw.closing and myw.buttons > 0 then              -- (under its sub-menus: the game's stays hidden, ours steps aside)
        if M.focus ~= myw.addr then if UI.myroom_ok then M.hide(myw, 'park'); end
        else UI.myroom_ok = guarded('myroom', MYROOM.draw, myw); if UI.myroom_ok then M.hide(myw, 'park'); end end
    else UI.myroom_ok = nil; end
    local scw = nil;                                                 -- (the Status screen's list - the focused one if there are two; not while
    if cfg.statcmd ~= false then                                     --  ChadcoreMenu's own Status pages are up)
        for _, w in ipairs(M.wins) do if w.name == 'statcom2' and (scw == nil or w.addr == M.focus) then scw = w; end end   -- (its status reads 'closing' even while it's up)
    end
    if scw then
        M.note('statcmd', ('list %08X status %X focus %s buttons %d browse %s/%s drawn %s'):format(scw.addr, scw.status or 0, tostring(M.focus == scw.addr), scw.buttons,
            tostring(UI.browse and UI.browse.kind), tostring(UI.browse and UI.browse.via), tostring(UI.browse_drawn)));
    end
    if scw and scw.buttons > 0 and not (UI.browse and UI.browse_drawn) then
        local fw_ = M.open[M.focus or 0];
        local page_up = fw_ and MYROOM.PAGE_WINS and MYROOM.PAGE_WINS[fw_.name];   -- (one of ChadcoreMenu's pages, opened from the list)
        UI.curpage_live = (fw_ and fw_.name == 'evitem' and (UI.statcmd_cur == 7 or UI.statcmd_cur == 8)) and true or false;
        if UI.curpage_live then page_up = true; end
        if M.focus == scw.addr or page_up then
            UI.statcmd_ok = guarded('statcmd', MYROOM.status, scw) and UI.statcmd_drew;
            if UI.statcmd_ok then
                M.hide(scw, 'park');
                for _, w in ipairs(M.wins) do if MYROOM.PAGE_WINS[w.name] or (UI.curpage_live and w.name == 'evitem') then M.hide(w, 'nodraw'); end end   -- (top-left "Menu content": VanaCore moves those; only left undrawn)
            end
            M.note('statcmd2', UI.statcmd_ok and 'drawn, game list hidden' or ('not drawn (buttons seen: ' .. tostring(UI.statcmd_n) .. ')'));
        elseif UI.statcmd_ok then M.hide(scw, 'park'); end
    else UI.statcmd_ok = nil; UI.curpage_live = false; end
    -- Merit Points: its first choice and the categories (the game's points box and description folded in)
    if cfg.merits ~= false then
        for _, w in ipairs(M.wins) do
            if w.name == 'merit1' and w.buttons == 2 then
                if M.focus == w.addr then UI.merit1_ok = guarded('merit1', MYROOM.merit1, w); end
                if UI.merit1_ok then M.hide(w, 'park'); end
            elseif w.name == 'meritcat' and w.buttons > 0 and cfg.meritcat_on == true then
                -- (these sit in VanaCore's "Menu content", which VanaCore moves every frame: moving them off screen too fought
                --  it and crashed the game - so they're only left undrawn, their place never touched)
                if M.focus == w.addr then UI.meritcat_ok = guarded('meritcat', MYROOM.meritcat, w); end
                if UI.meritcat_ok then
                    M.hide(w, 'nodraw');
                    for _, w2 in ipairs(M.wins) do if w2.name == 'meritinf' or w2.name == 'bluehelp' then M.hide(w2, 'nodraw'); end end
                end
            end
        end
        if not M.find('merit1') then UI.merit1_ok = nil; end
        if not M.find('meritcat') then UI.meritcat_ok = nil; end
    end
    for _, nm_ in ipairs({ 'shopbuy', 'shopsell' }) do
        local cw_ = (cfg.npcshop ~= false) and M.find(nm_) or nil;
        if cw_ and cw_.buttons == 2 and M.focus == cw_.addr then
            if guarded(nm_, SHP.confirm, cw_, nm_ == 'shopsell') then M.hide(cw_, 'park'); end
        end
    end
    local smw = (cfg.npcshop ~= false) and (M.find('shopmain') or M.find('guildsho')) or nil;
    if smw and smw.buttons == 2 and M.focus == smw.addr then
        if guarded('shopmain', SHP.main, smw) then M.hide(smw, 'park'); end
    end
    UI.qst_drawn = false;                                             -- Quests (the main menu's): our own screens over the game's
    local qsw = (cfg.quests ~= false) and M.find('quest00') or nil;
    if qsw and not qsw.closing and QST.off_addr ~= qsw.addr then
        local q1 = M.find('quest01');
        if not q1 or q1.closing then                                 -- (the game still on its first page: ours; one of its own lists up: the game's)
            UI.qst_drawn = guarded('quests', QST.draw, qsw);
            if UI.qst_drawn then M.hide(qsw, 'park'); UI.qst_w = qsw; end
        end
        if QST.noted ~= qsw.addr then                                -- (once an opening: why it was or wasn't ours)
            QST.noted = qsw.addr;
            M.note('quests' .. os.clock(), ('quest00 %08X: drawn %s, quest01 %s, data %s, log types %d, roe %s, focus %08X, pad %s'):format(qsw.addr, tostring(UI.qst_drawn),
                q1 and (q1.closing and 'closing' or 'up') or 'none', tostring(QST.data() ~= nil), (function() local n = 0; for _ in pairs(QST.log) do n = n + 1; end return n; end)(),
                QST.roe and #QST.roe or 'none', M.focus or 0, tostring(cfg.pad)));
        end
    elseif qsw then
        if QST.noted ~= qsw.addr then QST.noted = qsw.addr; M.note('quests' .. os.clock(), ('quest00 %08X left to the game: closing %s, off %s'):format(qsw.addr, tostring(qsw.closing), tostring(QST.off_addr == qsw.addr))); end
    else QST.st = nil; if QST.off_addr and not M.open[QST.off_addr] then QST.off_addr = nil; end end
    local mpw = (cfg.moogle ~= false and cfg.delivery ~= false) and M.find('mogpost') or nil;
    if mpw and mpw.buttons == 2 and M.focus == mpw.addr then
        if guarded('mogpost', MYROOM.mogpost, mpw) then M.hide(mpw, 'park'); end
    end
    local lkw = (cfg.linkshell ~= false) and M.find('link5') or nil;
    if lkw and not lkw.closing then
        LNK.ok_now = false;
        guarded('linkshell', LNK.draw, lkw);
        if LNK.ok_now then
            M.hide(lkw, 'park');
            local h6 = M.find('link6'); if h6 then M.hide(h6, 'park'); end
            if LNK.hid ~= lkw.addr then                              -- (once: is the game's list really out of sight)
                LNK.hid = lkw.addr;
                M.note('lnkhide' .. os.clock(), ('link5 %08X rect %d,%d draw %d; link6 %s'):format(lkw.addr, rd16(lkw.addr + 0x3A), rd16(lkw.addr + 0x3C),
                    rd8(lkw.addr + 0x69), h6 and ('%08X rect %d,%d draw %d'):format(h6.addr, rd16(h6.addr + 0x3A), rd16(h6.addr + 0x3C), rd8(h6.addr + 0x69)) or '-'));
            end
        end
    end
    local l12 = (cfg.linkshell ~= false) and M.find('link12') or nil;   -- the member list
    if l12 and not l12.closing then
        UI.lnkm_ok = false;
        guarded('linklist', function() UI.lnkm_ok = LNKM.draw(l12); end);
        if UI.lnkm_ok then M.hide(l12, 'park'); local h6 = M.find('link6'); if h6 then M.hide(h6, 'park'); end end
    end
    local l4 = (cfg.linkshell ~= false) and (M.find('link4') or M.find('link13')) or nil;
    if l4 and not l4.closing and M.focus ~= l4.addr then local l13 = M.find('link13'); if l13 and M.focus == l13.addr then l4 = l13; end end
    if l4 and not l4.closing and LNK.picked_at ~= l4.addr then         -- (the pearl picked on our list: its linkshell, for checking)
        LNK.picked_at = l4.addr;
        LNK.picked_ls = LNK.sel and LNK.sel.lsid or nil;
    end
    if l4 and not l4.closing and M.focus == l4.addr then
        LNK.sub_ok = false;
        guarded('linksub', LNK.sub, l4);
        if LNK.sub_ok then M.hide(l4, 'park'); end
    end
    for nm_, def in pairs(SMALL) do                                   -- (small menus of the game's: SMALL above)
        local sw_ = M.find(nm_);
        if sw_ and not sw_.closing and (M.focus == sw_.addr or def.always) and cfg['small_' .. nm_] ~= false then
            UI.small_ok = false;
            guarded(nm_, function() UI.small_ok = SMALLMENU(sw_, nm_, def[1], def[2], def[3]); end);
            if UI.small_ok then M.hide(sw_, def.mode or 'park', def.keep); end
        end
    end
    UI.med_drawn = false;
    local mdw = (cfg.macro ~= false) and M.find('macro') or nil;
    if mdw and not mdw.closing and mdw.buttons == 9 then
        guarded('macroed', MED.draw, mdw);
        if UI.med_drawn then M.hide(mdw, 'nodraw', true); pcall(EDM.shrink, mdw); UI.med_w = mdw; end
    end
    UI.esed_drawn = false;
    local edw = (cfg.macro ~= false) and M.find('mcresed') or nil;
    if edw and not edw.closing then
        guarded('eqset', ESED.draw, edw);
        if UI.esed_drawn then M.hide(edw, 'nodraw', true); pcall(ESED.shrink, edw);
        elseif next(ESED.shr) then ESED.unshrink(true); end
    elseif next(ESED.shr) then ESED.unshrink(false); end
    UI.esel_drawn = false;
    local esw = (cfg.macro ~= false) and M.find('mcres20') or nil;
    local esm_ = M.find('mcresmn');
    if esw and not esw.closing and (M.focus == esw.addr or (esm_ and M.focus == esm_.addr)) then   -- (still shown under its options)
        guarded('eqsel', ESEL.draw, esw);
        if UI.esel_drawn then M.hide(esw, 'park'); UI.esel_w = esw; end
    end
    UI.msel_drawn = false;
    local msw = (cfg.macro ~= false) and M.find('mcrselec') or nil;
    local mop_ = M.find('mcrselop');
    if msw and not msw.closing and (M.focus == msw.addr or (mop_ and M.focus == mop_.addr)) then   -- (still shown under its options)
        guarded('mcrsel', MSEL.draw, msw);
        if UI.msel_drawn then
            M.hide(msw, 'park'); UI.msel_w = msw;
            local fk = (M.focus == msw.addr) and 'list' or 'options';
            if MSEL.hid ~= msw.addr .. fk then                       -- (once each way: is the game's list out of sight)
                MSEL.hid = msw.addr .. fk;
                M.note('mselhide' .. os.clock(), ('mcrselec (%s focused) rect %d,%d draw %d'):format(fk, rd16(msw.addr + 0x3A), rd16(msw.addr + 0x3C), rd8(msw.addr + 0x69)));
            end
        end
    end
    local mxw = (cfg.moogle ~= false) and M.find('mogext') or nil;
    if mxw and mxw.buttons == 3 and M.focus == mxw.addr then
        if guarded('mogext', MYROOM.mogext, mxw) then M.hide(mxw, 'park'); end
    end
    local jcw = (cfg.moogle ~= false) and M.find('jobchang') or nil;
    if jcw and not jcw.closing and jcw.buttons == 2 then
        if M.focus ~= jcw.addr then if UI.jobchang_ok then M.hide(jcw, 'park'); end
        else UI.jobchang_ok = guarded('jobchang', MYROOM.jobchange, jcw); if UI.jobchang_ok then M.hide(jcw, 'park'); end end
    else UI.jobchang_ok = nil; end
    for _, w in ipairs(M.wins) do                                    -- (the job list: "jobcselu" and its kin)
        if cfg.moogle ~= false and w.name:sub(1, 7) == 'jobcsel' and not w.closing and w.buttons >= 20 then
            if guarded('jobgrid', MYROOM.jobgrid, w) then M.hide(w, 'park'); end
        end
    end
    pcall(SHP.sell_run);
    if SHP.pick and not M.open[SHP.pick.box] then SHP.pick = nil; end   -- (the game's box went: the picker too)
    if SHP.pick_closed and not M.open[SHP.pick_closed] then SHP.pick_closed = nil; end

    -- the Delivery Box (Receive: post1 + post2; Send: delivery + stringdl)
    UI.dlv_drawn = false;
    if not M.find('delivery') then UI.dlv = nil; end
    if cfg.moogle ~= false and cfg.delivery ~= false then
        local p1, p2, dv, sd = M.find('post1'), M.find('post2'), M.find('delivery'), M.find('stringdl');
        if p1 and p2 and p1.buttons >= 8 and (M.focus == p1.addr or M.focus == p2.addr) then
            if guarded('delivery', DLV.draw, 'recv', p1, p2) then M.hide(p1, 'nodraw'); M.hide(p2, 'nodraw'); end
        elseif dv and dv.buttons >= 10 then
            UI.dlv_drawn = guarded('delivery', DLV.draw, 'send', dv, sd);
            if UI.dlv_drawn then
                M.hide(dv, 'nodraw'); if sd then M.hide(sd, 'nodraw'); end
                local mw2 = M.find('money'); if mw2 then M.hide(mw2, 'nodraw'); end
            end
        end
    end
    local stw = (cfg.moogle ~= false) and M.find('storage') or nil;
    if stw and M.focus == stw.addr and stw.buttons == 15 then
        if guarded('mogstorage', draw_mogcont, stw) then M.hide(stw, 'park'); end
    end
    local st2 = (cfg.moogle ~= false) and M.find('storage2') or nil;
    if st2 and M.focus == st2.addr and st2.buttons == #MOGC_AWAY then
        if guarded('mogstorage2', draw_mogcont, st2, MOGC_AWAY) then M.hide(st2, 'park'); end
    end

    -- the chat menu
    local cw_ = (cfg.chat ~= false) and M.find('chatctrl') or nil;
    if cw_ and not cw_.closing and cw_.buttons > 0 then
        if guarded('chat', draw_chat, cw_) then M.hide(cw_, 'park'); end
    end

    -- Home Point / Survival Guide
    UI.warp_drawn = false;
    local qw_ = nil;
    for _, w in ipairs(M.wins) do if w.name == 'query' and not w.closing then qw_ = w; end end
    if qw_ then UI.warp_seen = now; end
    if WARP.ev and not qw_ and now - (UI.warp_seen or 0) > 1.5 and now - WARP.ev.t > 1.5 then WARP.ev = nil; end
    if WARP.ev and qw_ and cfg.warp ~= false and UI.gui_ok ~= false then
        if WARP.closing then                                         -- (sent / backing out: close the game's menus)
            if now >= (WARP.close_at or 0) and WARP.closing > 0 and M.focus ~= 0 then
                M.act(nil, nil, KEY.cancel); WARP.closing = WARP.closing - 1; WARP.close_at = now + 0.2;
            end
            if WARP.closing <= 0 and now > (WARP.close_at or 0) + 0.8 then WARP.ev = nil; end
        else
            UI.warp_drawn = guarded('warp', draw_warp, qw_);
            if UI.warp_note ~= qw_.addr then                         -- (once a box: what happened, to the log)
                UI.warp_note = qw_.addr;
                local gv, fv = '?', '?';
                pcall(function() gv = tostring(AshitaCore:GetGuiManager():GetVisible()); fv = tostring(AshitaCore:GetFontManager():GetVisible()); end);
                M.note('warpdraw' .. os.clock(), ('warp list: drawn %s, %d places, gui %s, fonts %s, box %d answers'):format(tostring(UI.warp_drawn), #(WARP.rows or {}), gv, fv, qw_.buttons or -1));
            end
        end
        for _, w in ipairs(M.wins) do if w.name == 'query' then M.hide(w); end end
    end

    -- an event's question with a few answers (Yes / No and the like)
    UI.qry_on = false;
    if cfg.query ~= false and qw_ and not UI.warp_drawn and not WARP.ev and M.focus == qw_.addr and UI.gui_ok ~= false then
        local okq, q_ = pcall(QRY.parse, qw_);
        if okq and q_ then
            UI.qry_on = true;
            if guarded('query', QRY.draw, qw_, q_) then
                M.hide(qw_);
                if q_.ids or q_.card then for _, w in ipairs(M.wins) do if w.name == 'iteminfo' then M.hide(w, 'park'); end end end   -- (ours shows instead)
            end
        end
    end
    -- (the exchange's message after its confirm: the game's item card still up - ours in its place)
    if not UI.qry_on and QRY.card_wanted() then
        local iw = M.find('iteminfo');
        if iw then
            local nat = M.to_screen(iw.rect);
            local okt = guarded('qcard', QRY.card_alone, QRY.last_item, nat);
            if okt then M.hide(iw, 'park'); end
        end
    end

    -- the Mog House door
    local mdw = (cfg.query ~= false and cfg.moogle ~= false) and M.find('mogdoor') or nil;
    -- ("Select an area" / "Change floors" open their own list in the same box - its page number moves on from the one it
    --  opened with; that list's names aren't known yet, so it's the game's own box then)
    local dpage = nil;
    if mdw then local lf = list_fields(mdw); dpage = lf and lf[2]; end
    if mdw and QRY.door_addr ~= mdw.addr then QRY.door_addr, QRY.door_page, QRY.door_probed = mdw.addr, dpage, nil; end
    local zone_ = 0;
    pcall(function() zone_ = AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0) or 0; end);
    local alist = mdw and QRY.AREAS[zone_];
    if mdw and dpage and QRY.door_page and dpage == QRY.door_page + 1 and M.focus == mdw.addr and alist and #alist == mdw.buttons then   -- (the area list: the page after the first)
        if guarded('mogdoor', QRY.draw, mdw, { title = 'Which area do you want to exit to?', opts = alist, head = 'MOG HOUSE' }) then M.hide(mdw); end
    elseif mdw and dpage ~= QRY.door_page and M.focus == mdw.addr then
        if not QRY.door_probed and (QRY.probes or 0) < 6 then
            QRY.door_probed = true; QRY.probes = (QRY.probes or 0) + 1;
            pcall(QRY.probe, mdw, { 'Bastok', "San d'Oria", 'Windurst', 'Jeuno', 'Port ', 'Mog ', 'floor', 'Markets', 'Mines', 'Waters', 'Woods', 'Walls' });
        end
    elseif mdw and M.focus == mdw.addr and mdw.buttons >= 2 then
        local okd, q_ = pcall(QRY.door, mdw);
        if okd and q_ and guarded('mogdoor', QRY.draw, mdw, q_) then M.hide(mdw); end
    end

    -- the server's own NPC menus (EXP Guide (S) and the like): the game's small "gmtell" box
    UI.gmt_drawn, UI.gmt_w = false, nil;
    do
        local gw = nil;
        local old_open = false;
        for _, w in ipairs(M.wins) do
            if w.name == 'gmtell' then
                if w.addr == GMT.old then old_open = true;            -- (the box just answered, still closing: not the next one)
                elseif not w.closing then gw = w; end
            end
        end
        if not old_open then GMT.old = nil; end
        if gw and cfg.npcmenu ~= false and #GMT.opts > 0 then
            if GMT.addr == nil and now - GMT.t < 3 then GMT.addr = gw.addr; end   -- (a new box: ours if the menu line came just before it)
            if GMT.addr == gw.addr then
                GMT.run(gw);
                if not GMT.sent then UI.gmt_drawn = guarded('npcmenu', GMT.draw, gw); else UI.gmt_drawn = true; end
                if UI.gmt_drawn and not GMT.sent then GMT.hl = { opt = GMT.opts[GMT.cur or 1], t = now }; end   -- (the row on the panel, kept for the answer)
                UI.gmt_w = gw;
                if UI.gmt_drawn then M.hide(gw); end
            end
        end
        if gw == nil and GMT.addr and now - GMT.t > 1 then GMT.addr = nil; GMT.opts = {}; end   -- (closed: forgotten)
    end

    -- editing macros: the game's two rows in the macro bars' style
    do
        local e1, e2 = M.find('mcr1edlo'), M.find('mcr2edlo');
        if not e1 and not e2 and EDM.closed_t and os.clock() - EDM.closed_t > 3 and not M.find('mcrledit') and not M.find('macro') then
            EDM.st, EDM.closed_t = {}, nil;                          -- (left the editing for good: the next book is looked for anew)
        end
        if cfg.macro ~= false and (e1 or e2) then
            local s1 = e1 and EDM.set(e1, 1) or nil;
            local s2 = e2 and EDM.set(e2, 2) or nil;
            local set = s1 or s2;
            if not set and next(EDM.bp) then EDM.restore_buttons(); end   -- (not drawn by us now: the game's boxes back)
            if not set and next(EDM.shr) then EDM.unshrink(); end
            if set then
                for half, ew in ipairs({ e1 or false, e2 or false }) do
                    if ew and not ew.closing then
                        MCR.wid = 'e' .. half;
                        local lbw = M.find('mcrbedit');
                        local inline_ = lbw and M.focus == lbw.addr;  -- (in the line menu: the game goes back to the rows by where
                        local st_ = EDM.st[half] or EDM.st[3 - half];
                        local lset = MCR.live(ew, st_ and st_.chain, set);   -- (names as they are in memory now)
                        if lset ~= set then EDM.live_addr, EDM.live_set = MCR.follow_addr(ew, st_.chain), set; end
                        if M.focus == ew.addr then EDM.slot = (half - 1) * 10 + math.max(1, math.min(10, ew.cursor)); end
                        if guarded('mcredit', MCR.draw, ew, half, lset) then   --  their buttons are - so they're left in place meanwhile)
                            if inline_ then
                                if next(EDM.bp) then EDM.restore_buttons(); end
                                M.unpark(ew.addr);
                                M.hide(ew, 'nodraw', true);
                                pcall(EDM.shrink, ew);
                            else
                                if next(EDM.shr) then EDM.unshrink(); end
                                M.hide(ew, 'park');                  -- (moved off screen: its draw switch alone left it showing)
                                pcall(EDM.park_buttons, ew);         -- (and its boxes, which are drawn where their buttons are)
                            end
                        elseif next(EDM.bp) then EDM.restore_buttons(); end
                        MCR.wid = nil;
                    end
                end
            end
            EDM.open = true;
            if set and not set.blank and os.clock() - (EDM.reread or 0) > 1.0 then   -- (the set's file read again every second: a
                EDM.reread = os.clock();                             --  macro you just changed shows as soon as the game has saved it)
                pcall(MCR.reread, set);
            end
            if set and not EDM.vhid then                             -- (the rows' boxes are the macro bar's art: VanaCore's switch for
                EDM.vhid = true;                                     --  it hides them while editing; back on when done)
                pcall(function() vana.gameui.hide('macro_bar'); end);
            end
        elseif EDM.open then                                         -- (closed: the macro files may have changed - read again)
            EDM.open = false;
            EDM.closed_t = os.clock();
            EDM.restore_buttons();
            EDM.unshrink();
            MCR.sets = nil;
            MCR.last_blob = nil;                                     -- (the bars: their names checked again against the new files)
            if EDM.vhid then EDM.vhid = false; pcall(function() vana.gameui.show('macro_bar'); end); end
        end
    end
    -- the macro bars (Ctrl / Alt)
    MCR.gameui(false);
    pcall(MCRF.tick);
    if cfg.macro ~= false then
        local mw_, half_, any_ = nil, nil, {};
        for _, w in ipairs(M.wins) do
            -- (up while you hold Ctrl / Alt: then it has the focus. The game keeps the window about after you let go, and its
            --  "closing" mark isn't to be trusted for it, so the focus decides - or, when the game left it without the focus,
            --  the key / trigger still being held)
            if (w.name == 'mcr1long' or w.name == 'mcr2long') and w.buttons == 10 then
                local h_ = (w.name == 'mcr1long') and 1 or 2;
                any_[#any_ + 1] = { w, h_ };
                if M.focus == w.addr then mw_, half_ = w, h_; end
            end
        end
        if not mw_ and #any_ > 0 then
            local k = MCR.held();
            if k then
                for _, e_ in ipairs(any_) do if k == 0 or e_[2] == k then mw_, half_ = e_[1], e_[2]; end end
                if mw_ then
                    local fw = M.open[M.focus or 0];
                    M.note('macro_nofocus', ('%s up without the focus (focus: %s %08X): shown while held'):format(mw_.name, fw and fw.name or '?', M.focus or 0));
                end
            end
        end
        if mw_ then
            local okm, set_ = pcall(MCR.active, mw_, half_);
            if not okm then errlog('macro', set_); set_ = nil; end
            if set_ then set_ = MCR.live(mw_, MCR.chain, set_); end
            if set_ and guarded('macro', MCR.draw, mw_, half_, set_) then M.hide(mw_, 'nodraw', true); MCR.lrect = mw_.rect; MCR.remembered(); end   -- (its buttons left alone: moving
                                                                     --  them kept the game from bringing the bar up again on Ctrl / Alt)
            MCR.miss = nil;
        elseif cfg.macro_force ~= false and MCR.remembered() then
            -- (the force check: Ctrl / Alt / a trigger held and the game's bar didn't come up - VanaCore sometimes leaves it down until
            --  you engage. Ours is drawn anyway from the set last seen, and the game is asked once to show its bar again)
            local k = MCR.held();
            if k then M.note('macro_held', ('held %d, no bar from the game; pad owner %s, chat %s'):format(k, tostring(UI.pad_owner), tostring(M.chat_open()))); end
            if k and not UI.pad_owner and not M.chat_open() then
                MCR.miss = MCR.miss or os.clock();
                if os.clock() - MCR.miss > 0.12 then
                    if not MCR.poked then MCR.poked = true; MCR.hidden = nil; MCR.gameui(false);
                        M.note('macro_force', 'Ctrl/Alt held, no bar from the game: drawn from the last set'); end
                    local h_ = (k == 2) and 2 or 1;
                    local set_ = MCR.remembered();
                    if set_ and guarded('macro', MCR.draw, { addr = 0, rect = MCR.lrect, cursor = MCRF.cur, ghost = true }, h_, set_) then
                        MCRF.on_t, MCRF.half = os.clock(), h_;
                    end
                end
            else MCR.miss = nil; MCR.poked = nil; end
        end
    end

    -- the treasure pool (opened from Treasure in the action menu)
    UI.tre_drawn = false;
    if UI.tre then UI.tre_drawn = guarded('treasure', TRE.draw) and UI.tre ~= nil; end

    -- Trade with an NPC
    local tw_ = cfg.trade and M.find('handover') or nil;
    UI.trade_drawn = false;
    if tw_ and not tw_.closing then
        if UI.trade == nil then                                      -- (just opened: who it's with)
            local idx, sid, nm = 0, 0, nil;
            pcall(function()
                idx = AshitaCore:GetMemoryManager():GetTarget():GetTargetIndex(0) or 0;
                local en = AshitaCore:GetMemoryManager():GetEntity();
                sid, nm = en:GetServerId(idx) or 0, en:GetName(idx);
            end);
            UI.trade = { npc_idx = idx, npc_id = sid, npc_name = nm, npc = (idx > 0 and sid >= 0x01000000), items = {}, order = {}, gil = 0, cur = 1, off = 0 };
            M.note('trade', ('opened with %s (index %d, id %d) %s'):format(tostring(nm), idx, sid, UI.trade.npc and 'npc' or 'player / unknown: game window'));
        end
        local T_ = UI.trade;
        if T_.closing then                                           -- (sent: close the game's trade window)
            if now >= (T_.close_at or 0) and T_.closing > 0 and M.focus ~= 0 then
                M.act(tw_.addr, 10, KEY.ok); T_.closing = T_.closing - 1; T_.close_at = now + 0.25;   -- (its Cancel box, then OK)
            end
            if T_.closing <= 0 and now > (T_.close_at or 0) + 0.8 then T_.closing = nil; end   -- (still open after all that: the panel again)
            for _, w in ipairs(M.wins) do                            -- (stays hidden while it closes)
                if w.name == 'handover' or w.name == 'itemctrl' or w.name == 'money' or w.name == 'iteminfo' or w.name == 'inventor' then M.hide(w); end
            end
        elseif T_.npc then
            UI.trade_drawn = guarded('trade', draw_trade, tw_);
            if UI.trade_drawn then
                for _, w in ipairs(M.wins) do
                    if w.name == 'handover' or w.name == 'itemctrl' or w.name == 'money' or w.name == 'iteminfo' or w.name == 'inventor' then M.hide(w); end
                end
            end
        end
    else
        UI.trade = nil;
    end

    -- Check on another player
    local iw_ = cfg.inspect and M.find('inspect') or nil;
    if iw_ and not iw_.closing and iw_.buttons >= 16 then
        UI.ins_drawn = guarded('inspect', draw_inspect, iw_);
        if UI.ins_drawn then
            M.hide(iw_, 'park');
            for _, w in ipairs(M.wins) do if w.name == 'comment' or w.name == 'iteminfo' then M.hide(w); end end
        end
    else
        UI.ins_drawn = false;
        if UI.ins then UI.ins.t0 = nil; end
    end

    -- another player's bazaar (View Wares): the game's "shop" list, when the server sent bazaar wares for it
    local bw_ = M.find('shop');                                      -- (the same window: a bazaar, or an NPC's shop - each its own switch)
    UI.baz_drawn = false;
    if bw_ and not bw_.closing then
        if UI.baz_addr ~= bw_.addr then UI.baz_addr, UI.baz_open, UI.baz = bw_.addr, now, nil; end
        if BAZ.n > 0 and BAZ.t >= UI.baz_open - 1.5 then              -- (an NPC's shop has no bazaar wares: left to the game)
            UI.baz_drawn = (cfg.bazaar ~= false) and guarded('bazaar', BAZ.draw, bw_) or false;
            if UI.baz_drawn then
                M.hide(bw_, 'park');
                for _, w in ipairs(M.wins) do if w.name == 'money' or w.name == 'iteminfo' then M.hide(w); end end
            end
        elseif cfg.bazaar ~= false and M.find('bazaar') and not M.find('shopmain') and not M.find('guildsho') then   -- (Bazaar > Set Prices: your own items)
            UI.bzp_drawn = guarded('bazaarprices', SHP.bazaar_prices, bw_) and SHP.bz_ok;
            if UI.bzp_drawn then
                M.hide(bw_, M.find('moneyctr') and 'nodraw' or 'park', M.find('moneyctr') ~= nil);   -- (its price box up: the list only not drawn, the game lays it out then)
                for _, w in ipairs(M.wins) do if w.name == 'money' or w.name == 'iteminfo' then M.hide(w); end end
            end
        elseif M.find('shopmain') and SHP.mode_of(bw_) == 2 and not SHP.info_done and M.focus == bw_.addr then
            -- (once: each inventory item with its kind, slots and skill - to work out the game's Sell order)
            SHP.info_done = true;
            pcall(function()
                local im = AshitaCore:GetMemoryManager():GetInventory();
                local rm = AshitaCore:GetResourceManager();
                local out = {};
                for i = 1, 80 do
                    local it = im:GetContainerItem(0, i);
                    if it and (it.Id or 0) ~= 0 and it.Id ~= 65535 then
                        local r = rm:GetItemById(it.Id);
                        local function f(k) local ok, v = pcall(function() return r[k]; end); return ok and tostring(v) or '?'; end
                        out[#out + 1] = ('%d|%d|%s|T%s|S%s|K%s|F%s|L%s'):format(i, it.Id, (r and r.Name and r.Name[1]) or '?', f('Type'), f('Slots'), f('Skill'), f('Flags'), f('Level'));
                    end
                end
                M.note('sellinfo' .. os.clock(), 'inventory: ' .. table.concat(out, ' ; '));
            end);
        elseif cfg.selldump == true and M.find('shopmain') and SHP.mode_of(bw_) == 2 and SHP.dumped ~= bw_.addr and M.focus == bw_.addr and now - UI.baz_open > 0.6 then   -- (the search's done: off)
            -- (Sell's list, to the log once: the list's memory and your inventory by slot - to find the game's own order)
            SHP.dumped = bw_.addr;
            pcall(function()
                local mp = rd32(bw_.addr + 0x0C);
                local hx = function(b) return b and (b:gsub('.', function(ch) return ('%02X'):format(ch:byte()); end)) or '-'; end;
                local inv = {};
                local im = AshitaCore:GetMemoryManager():GetInventory();
                for i = 1, 80 do local it = im:GetContainerItem(0, i); if it and (it.Id or 0) ~= 0 then inv[#inv + 1] = ('%d:%d'):format(i, it.Id); end end
                M.note('selldump' .. os.clock(), ('sell list window %08X list %08X: %s ;; inventory %s'):format(bw_.addr, mp, hx(MCR.read(mp, 0x800)), table.concat(inv, ' ')));
                M.note('selldumpw' .. os.clock(), ('sell window: %s'):format(hx(MCR.read(bw_.addr, 0x200))));
                -- (and where a row-by-row list of your inventory slots is: every slot number in it, each once, as many as rows)
                local set, n = {}, 0;
                for i = 1, 80 do local it = im:GetContainerItem(0, i); if it and (it.Id or 0) ~= 0 then set[i] = true; n = n + 1; end end
                local lf = list_fields(bw_);
                local rows = (lf and lf[6]) or n;
                local seen, queue, cnt, hits = {}, { { bw_.addr, 'w' }, { mp, 'L' } }, 0, {};
                while #queue > 0 and cnt < 900 and #hits < 6 do
                    local q = table.remove(queue, 1);
                    local b = MCR.read(q[1], 0x1000);
                    cnt = cnt + 1;
                    if b then
                        for _, wd in ipairs({ 1, 2, 4 }) do
                            for off = 0, #b - wd * rows, wd do
                                local ok, used = true, {};
                                for k = 0, rows - 1 do
                                    local v = 0;
                                    for t = wd - 1, 0, -1 do v = v * 256 + b:byte(off + k * wd + t + 1); end
                                    if not set[v] or used[v] then ok = false; break; end
                                    used[v] = true;
                                end
                                if ok then
                                    local first = {};
                                    for k = 0, math.min(rows, 16) - 1 do local v = 0; for t = wd - 1, 0, -1 do v = v * 256 + b:byte(off + k * wd + t + 1); end first[#first + 1] = v; end
                                    hits[#hits + 1] = ('%s+%X w%d: %s'):format(q[2], off, wd, table.concat(first, ','));
                                    break;
                                end
                            end
                        end
                        local depth = select(2, q[2]:gsub('>', ''));
                        if depth < 3 then
                            for off = 0, math.min(#b, 0x200) - 4, 4 do
                                local p_ = b:byte(off + 1) + b:byte(off + 2) * 256 + b:byte(off + 3) * 65536 + b:byte(off + 4) * 16777216;
                                if p_ >= 0x01000000 and p_ < 0x7FFF0000 and not seen[p_] then seen[p_] = true; queue[#queue + 1] = { p_, q[2] .. '>' .. ('%X'):format(off) }; end
                            end
                        end
                    end
                end
                M.note('selldumpf' .. os.clock(), ('sell rows (%d rows, %d places): %s'):format(rows, cnt, (#hits > 0) and table.concat(hits, ' ; ') or 'not found'));
            end);
        elseif cfg.npcshop ~= false and cfg.shopsell ~= false and not SHP.sell_off and M.find('shopmain') and SHP.mode_of(bw_) == 2 and SHP.sell_list(bw_) then
            -- (selling: your items in slot order - checked against what the game asks the price of when you pick: if they
            --  ever differ, that sale is stopped and the game's own list is used from then on)
            if guarded('npcshop', SHP.draw, bw_, SHP.sell_list(bw_)) then
                M.hide(bw_, 'park');
                for _, w in ipairs(M.wins) do if w.name == 'money' or w.name == 'iteminfo' then M.hide(w); end end
            end
        elseif cfg.npcshop ~= false and M.find('guildsho') and SHP.mode_of(bw_) == 2 and #SHP.gsell > 0 and (list_fields(bw_) or {})[6] == #SHP.gsell + 1 then
            if guarded('npcshop', SHP.draw, bw_, nil, true) then     -- (a guild: what it buys from you)
                M.hide(bw_, 'park');
                for _, w in ipairs(M.wins) do if w.name == 'money' or w.name == 'iteminfo' then M.hide(w); end end
            end
        elseif cfg.npcshop ~= false and SHP.buy_ok(bw_) then          -- (an NPC's shop: what they sell)
            if guarded('npcshop', SHP.draw, bw_) then
                M.hide(bw_, 'park');
                for _, w in ipairs(M.wins) do if w.name == 'money' or w.name == 'iteminfo' then M.hide(w); end end
            end
        end
    else
        UI.baz_addr, UI.baz = nil, nil;
    end

    -- Status / Equipment
    local eq, parts = nil, {};
    if cfg.char then
        local names = {};
        names[cfg.equip_name] = 'equip';
        for _, n in ipairs(split(cfg.status_names)) do names[n] = names[n] or 'status'; end
        for _, w in ipairs(M.wins) do
            local kind = names[w.name];
            if kind then
                parts[#parts + 1] = w;
                if kind == 'equip' then eq = w; end
            end
        end
    end
    -- the full panel: the Equipment screen, or the Status screen on its own (other screens that show the game's gil or
    -- item info, like the Items menu, keep their own boxes; ChadcoreMenu shows items there as tooltips instead)
    if eq == nil then
        local has_persona, has_list = false, M.find('inventor') ~= nil;
        for _, w in ipairs(parts) do if w.name == 'persona' or w.name == 'statcom' or w.name == 'status' then has_persona = true; end end
        if not has_persona or has_list then parts = {}; end
    end
    if #parts > 0 then                                               -- (the game's merit screens: the Status panel steps aside)
        for _, w in ipairs(M.wins) do
            if not w.closing and (w.name:sub(1, 5) == 'merit' or w.name == 'levmerit') then parts, eq = {}, nil; M.note('char', 'hidden: merit window ' .. w.name); break; end
        end
    end
    if #parts > 0 and eq == nil and M.find('statcom2') then         -- (a page of the Status list ChadcoreMenu doesn't redraw - Currencies, Unity,
        local fw_ = M.open[M.focus or 0];                            --  Play Time... - has the focus: the panel steps aside so it shows)
        local mine = { statcom2 = true, persona = true, level = true, money = true, iteminfo = true, statcom = true, status = true };
        if UI.curpage_live then mine.evitem = true; end
        if fw_ and not mine[fw_.name] and not (MYROOM.PAGE_WINS and MYROOM.PAGE_WINS[fw_.name]) then
            parts = {}; M.note('char', 'hidden: status page ' .. fw_.name);
        end
    end
    if #parts > 0 then
        local union = nil;
        for _, w in ipairs(parts) do
            local r = M.to_screen(w.rect);
            if r then
                if union == nil then union = { r[1], r[2], r[3], r[4] };
                else union = { math.min(union[1], r[1]), math.min(union[2], r[2]), math.max(union[3], r[3]), math.max(union[4], r[4]) }; end
            end
        end
        local pn = {};
        for _, w in ipairs(parts) do pn[#pn + 1] = w.name .. '/' .. string.format('%X', w.status or 0); end
        local okc = guarded('char', draw_char, eq, cfg.follow and union or nil);
        M.note('char', (okc and 'shown over ' or 'FAILED (see chadcoremenu-errors.txt) over ') .. table.concat(pn, ','));
        if okc then
            for _, w in ipairs(parts) do M.hide(w); end
            local extra = {};
            for _, n in ipairs(split(cfg.extra_hide)) do extra[n] = true; end
            for _, w in ipairs(M.wins) do if extra[w.name] then M.hide(w); end end
        end
    else
        UI.char.t0 = nil;
        UI.sw.pinned = nil;                                          -- (the equipment screen closed: back to the worn piece's bag)
        UI.charbox = nil;
        if M.find(cfg.equip_name) then M.note('char', 'equip open but the panel is off (/cmenu char on)'); end
    end

    -- the storage picker (first: when it closes, the bag it was on is the one the item list now shows)
    local sw_ = cfg.storage and M.find('mnstorag') or nil;
    if sw_ then
        if not UI.store_open then UI.store_open = true; UI.store_first = sw_.cursor; end
        if guarded('storage', draw_storage, sw_) then M.hide(sw_); end
    elseif UI.store_open then
        UI.store_open = false;                                       -- (the picker closed: its last cursor is the bag now shown)
        if UI.store_cur then
            UI.bag = UI.store_cur; M.note('bag', 'now ' .. BAGS[UI.store_cur][2]);
            UI.sw.pinned = UI.store_cur;                             -- (the swap list follows the bag you picked)
            UI.sw.bag, UI.sw.cur, UI.sw.off = UI.store_cur, nil, 0;
        end
        UI.storage = nil;
    end
    -- Controller: learn confirm / cancel from the game's menus, and decide which panel (if any) has the controller now
    do
        local now = os.clock();
        local prev_open = UI.prev_open or {};
        -- (only from inside the game's main menu: a button that opens a window from it is confirm, one that comes back
        --  to it from a window that closed is cancel; the buttons that open or close the main menu itself don't count)
        if UI.pad_owner == nil and PAD.last and now - PAD.last_t < 0.4 and M.focus ~= UI.prev_focus2
            and now - (M.auto_t or -10) > 0.6 and not UI.chain and not UI.close_game then
            local fw = M.open[M.focus or 0];
            local was = UI.prev_name2;
            if fw and was == cfg.main_name and fw.name ~= cfg.main_name and not prev_open[fw.addr] and cfg.pad_ok ~= PAD.last then
                cfg.pad_ok = PAD.last; if cfg.pad_back == PAD.last then cfg.pad_back = ''; end save(); M.note('pad', 'confirm = ' .. PAD.last);
            elseif fw and fw.name == cfg.main_name and was and was ~= cfg.main_name and UI.prev_focus2 and not M.open[UI.prev_focus2] and cfg.pad_back ~= PAD.last then
                cfg.pad_back = PAD.last; if cfg.pad_ok == PAD.last then cfg.pad_ok = ''; end save(); M.note('pad', 'cancel = ' .. PAD.last);
            end
        end
        local op = {};
        for a in pairs(M.open) do op[a] = true; end
        local fw2 = M.open[M.focus or 0];
        UI.prev_open, UI.prev_focus2, UI.prev_name2 = op, M.focus, fw2 and fw2.name or nil;
        local iwf = M.find('inventor');
        local owner = nil;
        if cfg.pad then
            if UI.tre_drawn and UI.tre then owner = 'treasure';
            elseif UI.dlv_drawn and UI.dlv and not UI.dlv.typing then owner = 'delivery';
            elseif SHP.pick then owner = 'sellamt';
            elseif UI.msel_drawn and UI.msel_w and M.focus == UI.msel_w.addr then owner = 'mcrsel';
            elseif UI.med_drawn and UI.med_w and M.focus == UI.med_w.addr then owner = 'macroed';
            elseif UI.esel_drawn and UI.esel_w and M.focus == UI.esel_w.addr then owner = 'eqsel';
            elseif UI.browse and UI.browse_drawn then owner = 'browse';
            elseif UI.ins_drawn and iw_ and M.focus == iw_.addr then owner = 'inspect';
            elseif UI.trade_drawn and tw_ and M.focus == tw_.addr then owner = 'trade';
            elseif UI.baz_drawn and bw_ and M.focus == bw_.addr then owner = 'bazaar';
            elseif UI.curpage_live and UI.statcmd_ok then owner = 'currency';
            elseif UI.warp_drawn then owner = 'warp';
            elseif UI.gmt_drawn and UI.gmt_w and M.focus == UI.gmt_w.addr then owner = 'npcmenu';
            elseif UI.qst_drawn and UI.qst_w and M.focus == UI.qst_w.addr then owner = 'quest';
            elseif UI.mir_drawn and MIR.w and M.focus == MIR.w then owner = 'mirror';
            elseif UI.act_self and aw and M.focus == aw.addr and UI.act_live then owner = 'selfmenu';
            elseif not UI.act_self and aw and M.focus == aw.addr and UI.act_live and not UI.act_skip and UI.actg and (UI.actg.n or 0) > 0
                and UI.actg.win == aw.addr then owner = 'actgame';
            elseif cfg.char and cfg.list and eq and iwf and M.focus == iwf.addr and UI.eq_slot ~= nil then owner = 'swap';
            elseif UI.main.addr and M.focus == UI.main.addr and M.open[UI.main.addr] and cfg.settings_row ~= false and UI.main.ngame
                and (UI.main.setsel or UI.main.gcur == UI.main.ngame) then owner = 'mainset'; end   -- (the main menu's last row / UI Settings)
        end
        if SET.open then owner = 'settings'; end                     -- (the settings panel: over everything)
        if TCH.st then owner = 'teach'; end                          -- (the teach form: the pad kept from the game's menu under it)
        if owner ~= UI.pad_owner then PAD.q, PAD.held = {}, nil; end
        UI.pad_owner = owner;
        local acts = owner and PAD.take() or {};
        if not owner then PAD.q = {}; end
        UI.br.acts = (owner == 'browse') and acts or {};             -- (never left over: an old Cancel would close the next menu)
        if owner == 'selfmenu' then                                  -- the action menu on yourself
            UI.selfm = UI.selfm or { cur = 1 };
            for _, act in ipairs(acts) do
                local n = #(UI.own_rows or SELF_ROWS);
                if act == 'up' then UI.selfm.cur = (UI.selfm.cur > 1) and (UI.selfm.cur - 1) or n;
                elseif act == 'down' then UI.selfm.cur = (UI.selfm.cur < n) and (UI.selfm.cur + 1) or 1;
                elseif act == 'ok' then
                    if os.clock() - (UI.selfm.ft or 0) > 0.3 then
                        M.note('selfm_ok' .. os.clock(), ('action menu: confirm on row %d (%s)'):format(UI.selfm.cur, tostring(((UI.own_rows or SELF_ROWS)[UI.selfm.cur] or {})[1])));
                        self_exec(UI.selfm.cur, KEY.ok);
                    end
                elseif act == 'right' then self_exec(UI.selfm.cur, KEY.right);
                elseif act == 'back' then M.act(nil, nil, KEY.cancel); end
            end
        end
        if owner == 'warp' then                                      -- Home Point / Survival Guide: the columns
            local n, rpc = WARP.n or 1, WARP.rpc or 1;
            for _, act in ipairs(acts) do
                local c = WARP.cur or 1;
                if act == 'up' then c = (c > 1) and (c - 1) or n;
                elseif act == 'down' then c = (c < n) and (c + 1) or 1;
                elseif act == 'left' or act == 'tabl' then c = (c - rpc >= 1) and (c - rpc) or c;
                elseif act == 'right' or act == 'tabr' then c = math.min(n, c + rpc);
                elseif act == 'ok' then warp_pick(c);
                elseif act == 'back' then if WARP.pending then WARP.pending = nil; else WARP.closing, WARP.close_at = 8, 0; end end
                if c ~= WARP.cur then WARP.pending = nil; end
                WARP.cur = c;
            end
        end
        if owner == 'settings' then SET.pad(acts); end
        if owner == 'mcrsel' then MSEL.pad(acts, UI.msel_w); end
        if owner == 'macroed' then MED.pad(acts, UI.med_w); end
        if owner == 'eqsel' then ESEL.pad(acts, UI.esel_w); end
        if owner == 'mainset' then                                   -- (the game's own main menu, with UI Settings below its last command)
            local ma, ng, ord_ = UI.main.addr, UI.main.ngame, UI.main.ord;
            for _, act in ipairs(acts) do
                if UI.main.setsel then
                    if act == 'up' then UI.main.setsel = false;
                    elseif act == 'down' then UI.main.setsel = false; M.act(ma, to_button(ord_, 1), nil);
                    elseif act == 'ok' then SET.toggle(true);
                    elseif act == 'back' then UI.main.setsel = false; M.act(nil, nil, KEY.cancel); end
                else
                    if act == 'down' then UI.main.setsel = true;
                    elseif act == 'up' then M.act(ma, to_button(ord_, math.max(1, ng - 1)), nil);
                    elseif act == 'ok' then M.act(ma, to_button(ord_, ng), KEY.ok);
                    elseif act == 'back' then M.act(nil, nil, KEY.cancel); end
                end
            end
        end
        pcall(TCH.frame);                                            -- (menus you've taught, and the teach form)
        if not UI.teach_drawn then local okm, erm = pcall(MIR.frame); if not okm then errlog('mirror', erm); MIR.block = nil; end end
        if SET.open then guarded('settings', SET.draw); end
        if owner == 'teach' then for _, act in ipairs(acts) do if act == 'back' then TCH.st, TCH.on = nil, false; end end end
        if owner == 'quest' then QST.pad(acts); end
        if owner == 'mirror' then MIR.pad(acts); end
        pcall(MIR.ok_check);
        if owner == 'treasure' then TRE.pad(acts); end
        if owner == 'delivery' then DLV.pad(acts); end
        if owner == 'sellamt' then
            for _, act in ipairs(acts) do
                if act == 'up' then SHP.pick_step(1); elseif act == 'down' then SHP.pick_step(-1);
                elseif act == 'right' then SHP.pick_step(10); elseif act == 'left' then SHP.pick_step(-10);
                elseif act == 'tabr' then SHP.pick_step(100); elseif act == 'tabl' then SHP.pick_step(-100);
                elseif act == 'ok' then SHP.pick_done(true); break;
                elseif act == 'back' then SHP.pick_done(false); break; end
            end
        end
        if owner == 'actgame' then                                   -- the action menu on a target, with Treasure below the game's commands
            local A = UI.actg;
            local ord, n = A.ord or {}, #(A.ord or {});
            for _, act in ipairs(acts) do
                local c = A.cur or 1;
                if act == 'down' then
                    if A.tr then A.tr = false; if ord[1] then M.act(aw.addr, ord[1], nil); A.cur = 1; end
                    elseif c >= n then A.tr = true;
                    else M.act(aw.addr, ord[c + 1], nil); A.cur = c + 1; end
                elseif act == 'up' then
                    if A.tr then A.tr = false; if ord[n] then M.act(aw.addr, ord[n], nil); A.cur = n; end
                    elseif c <= 1 then A.tr = true;
                    else M.act(aw.addr, ord[c - 1], nil); A.cur = c - 1; end
                elseif act == 'ok' then
                    if A.tr then TRE.open(); else M.act(aw.addr, ord[c], KEY.ok); end
                elseif act == 'right' then
                    if not A.tr then M.act(aw.addr, ord[c], KEY.right); end
                elseif act == 'back' then M.act(nil, nil, KEY.cancel); end
            end
        end
        if owner == 'npcmenu' and not GMT.sent then GMT.pad(acts, UI.gmt_w); end
        if owner == 'bazaar' then BAZ.pad(acts); end
        if owner == 'currency' then MYROOM.cur_pad(acts); end                 -- a bazaar: its list, and how many to buy
        if owner == 'trade' then                                     -- Trade: your items / the trade window, and the amount picker
            local T_ = UI.trade;
            for _, act in ipairs(acts) do
                if T_.pick then
                    local gil = T_.pick.kind == 'gil';
                    if act == 'up' then trade_pick_step(1);
                    elseif act == 'down' then trade_pick_step(-1);
                    elseif act == 'right' then trade_pick_step(gil and 100 or 10);
                    elseif act == 'left' then trade_pick_step(gil and -100 or -10);
                    elseif act == 'tabr' then trade_pick_step(gil and 10000 or 100);
                    elseif act == 'tabl' then trade_pick_step(gil and -10000 or -100);
                    elseif act == 'ok' then trade_pick_done(true);
                    elseif act == 'back' then trade_pick_done(false); end
                elseif T_.focus == 'box' then
                    local nb = #(T_.box or {});
                    if act == 'up' then T_.bcur = (T_.bcur > 1) and (T_.bcur - 1) or nb;
                    elseif act == 'down' then T_.bcur = (T_.bcur < nb) and (T_.bcur + 1) or 1;
                    elseif act == 'left' or act == 'tabl' then T_.focus = 'list';
                    elseif act == 'ok' then trade_box_pick(T_.box and T_.box[T_.bcur]);
                    elseif act == 'back' then T_.closing, T_.close_at = 4, 0; end
                elseif act == 'sort' then sort_next('trade');
                else
                    local nl = math.max(1, #(T_.inv or {}));
                    if act == 'up' then T_.cur = (T_.cur > 1) and (T_.cur - 1) or nl;
                    elseif act == 'down' then T_.cur = (T_.cur < nl) and (T_.cur + 1) or 1;
                    elseif act == 'right' or act == 'tabr' then T_.focus = 'box';
                    elseif act == 'ok' then local e = T_.inv and T_.inv[T_.cur]; if e then trade_open_pick('item', e); end
                    elseif act == 'back' then T_.closing, T_.close_at = 4, 0; end
                end
            end
        end
        if owner == 'inspect' then                                   -- Check: the d-pad moves over the 4 x 4 gear, then View Wares
            local c = UI.ins.cur or 1;
            if #acts > 0 then UI.ins.auto = false; end
            for _, act in ipairs(acts) do
                if c == 17 then
                    if act == 'up' then c = 12 + (UI.ins.col or 0) + 1;
                    elseif act == 'down' then c = (UI.ins.col or 0) + 1;        -- (round to the top row)
                    elseif act == 'ok' then M.act(iw_.addr, 17, KEY.ok); end
                else
                    local cc, rr = (c - 1) % 4, math.floor((c - 1) / 4);
                    if act == 'up' then c = (rr > 0) and (c - 4) or (UI.ins.bz and 17 or (c + 12));
                    elseif act == 'down' then c = (rr < 3) and (c + 4) or (UI.ins.bz and 17 or (c - 12));
                    elseif act == 'left' then c = (cc > 0) and (c - 1) or (c + 3);
                    elseif act == 'right' then c = (cc < 3) and (c + 1) or (c - 3); end
                    if c ~= 17 then UI.ins.col = (c - 1) % 4; end
                end
                if act == 'back' then M.act(nil, nil, KEY.cancel); end
            end
            if c == 17 and not UI.ins.bz then c = 13 + (UI.ins.col or 0); end
            UI.ins.cur = c;
        end
        if owner == 'swap' then                                      -- the swap list: up / down, left / right bag, confirm equips, cancel back
            if not UI.sw.padded then swap_sync(UI.eq_slot, true); end   -- (each time the list opens: on the worn piece's bag)
            UI.sw.padded = true;
            local items = swap_items(UI.eq_slot, UI.sw.bag);
            if UI.sw.cur == nil then
                UI.sw.cur = 1;
                local worn = nil;
                pcall(function() local g = gear()[UI.eq_slot]; worn = g and g.id; end);
                for i, it in ipairs(items) do if it.id == worn then UI.sw.cur = i; end end
            end
            for _, act in ipairs(acts) do
                local n = #items;
                if act == 'up' and n > 0 then UI.sw.cur = (UI.sw.cur > 1) and (UI.sw.cur - 1) or n;
                elseif act == 'down' and n > 0 then UI.sw.cur = (UI.sw.cur < n) and (UI.sw.cur + 1) or 1;
                elseif act == 'left' or act == 'right' or act == 'tabl' or act == 'tabr' then
                    local b = UI.sw.bag + (((act == 'left') or (act == 'tabl')) and -1 or 1);
                    if b < 0 then b = #BAGS elseif b > #BAGS then b = 0 end
                    UI.sw.bag, UI.sw.cur, UI.sw.off = b, 1, 0;
                    items = swap_items(UI.eq_slot, UI.sw.bag);
                elseif act == 'ok' and items[UI.sw.cur] then
                    local it = items[UI.sw.cur];
                    equip_piece(UI.eq_slot, it);
                    UI.sw.flash = { id = it.id, t = now };
                    M.act(nil, nil, KEY.cancel);                     -- (back to the gear grid, as the game does)
                elseif act == 'back' then
                    M.act(nil, nil, KEY.cancel);
                end
            end
            UI.sw.cur = math.max(1, math.min(math.max(1, #items), UI.sw.cur));
            if UI.sw.cur < UI.sw.off + 1 then UI.sw.off = UI.sw.cur - 1; elseif UI.sw.cur > UI.sw.off + 12 then UI.sw.off = UI.sw.cur - 12; end
        else
            if UI.sw.padded then UI.sw.cur = nil; end
            UI.sw.padded = false;
        end
        -- after a spell / ability was used from the game's own window: back out of the game's windows
        local cg = UI.close_game;
        if cg then
            local set = {};
            for _, n in ipairs(split(cfg['win_' .. cg.kind])) do set[n] = true; end
            if cg.kind == 'magic' then set.magic = true; end             -- (the action menu's own Magic window)
            local still = false;
            for _, w in ipairs(M.wins) do if set[w.name] then still = true; end end
            local fwc = M.open[M.focus or 0];
            if not still or cg.tries <= 0 or not (fwc and set[fwc.name]) then UI.close_game = nil;
            elseif now >= cg.at then M.act(nil, nil, KEY.cancel); cg.tries = cg.tries - 1; cg.at = now + 0.15; end
        end
    end

    -- the Mog House storage menu ("mogcont"): the bag picked there (its buttons on screen, top to bottom, are these bags)
    do
        local MOG_BAGS = { 1, 9, 2, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16 };
        local mc = M.find('mogcont') or M.find('storage');
        local away = false;
        if not mc then mc = M.find('storage2'); away = mc ~= nil; end     -- (away from home: no Storage row)
        if away then MOG_BAGS = { 1, 9, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16 }; end
        if mc then                                                   -- (its status changes while the bag's list is up: open is enough)
            if M.focus == mc.addr then UI.mog_cur = mc.cursor; end
            if UI.mog_prev == mc.addr and M.focus ~= mc.addr and UI.mog_cur then
                local rank = nil;
                pcall(function()
                    local bs = M.buttons(mc);
                    table.sort(bs, function(p, q) return p.y < q.y; end);
                    local n = 0;
                    for _, b in ipairs(bs) do if b.w > 40 then n = n + 1; if b.no == UI.mog_cur then rank = n; end end end
                end);
                UI.mog_pick = rank and MOG_BAGS[rank] or nil;
                M.note('mog', ('picked button %s -> bag %s'):format(tostring(UI.mog_cur), tostring(UI.mog_pick)));
            end
        else
            UI.mog_cur, UI.mog_pick = nil, nil;
        end
        UI.mog_prev = M.focus;
    end

    -- Magic / Abilities / Items / Key Items
    UI.browse_drawn_prev = UI.browse_drawn;
    if not UI.browse then UI.browse_drawn = false; end
    if cfg.browse then
        -- learn the game's window for each: the window that takes the focus right after the main menu, on that command
        local fnow = M.focus;
        if UI.prev_focus and fnow ~= UI.prev_focus and mw and UI.prev_focus == mw.addr and fnow ~= mw.addr then
            local kind = BROWSE_KIND[UI.main.label or ''];
            local fw = M.open[fnow or 0];
            local NEVER = { equip = true, persona = true, money = true, iteminfo = true, playermo = true, menuwind = true, mnstorag = true,
            inline = true, logwindo = true, logwin2 = true, chatctrl = true, mcr1long = true, mcr2long = true, targetwi = true, gmtell = true, query = true };   -- (the chat line and other windows that can take the focus: never a menu's)
            if fw and kind then                                      -- (a window another kind already has isn't learned again)
                for _, k2 in ipairs({ 'status', 'magic', 'abilities', 'items', 'keyitems' }) do
                    if k2 ~= kind then for _, n in ipairs(split(cfg['win_' .. k2])) do if n == fw.name then NEVER[fw.name] = true; end end end
                end
            end
            if kind and fw and fw.name ~= '' and not NEVER[fw.name] then
                local set = {};
                for _, n in ipairs(split(cfg['win_' .. kind])) do set[n] = true; end
                if not set[fw.name] then
                    set[fw.name] = true;
                    local out = {}; for n in pairs(set) do out[#out + 1] = n; end
                    cfg['win_' .. kind] = table.concat(out, ','); save();
                    M.note('learn', kind .. ' = ' .. fw.name);
                end
            end
        end
        UI.prev_focus = fnow;
        -- the game's own window for one of them is open: our panel opens beside it
        local gw, gkind = nil, nil;
        for _, kind in ipairs({ 'status', 'magic', 'abilities', 'items', 'keyitems' }) do
            local set = {};
            for _, n in ipairs(split(cfg['win_' .. kind])) do set[n] = true; end
            -- (only a game window that has the focus: the game keeps some of them open, unseen, when no menu is up - an idle
            --  item list must not open a panel or take the controller)
            local fw_ = M.open[M.focus or 0];
            if fw_ and set[fw_.name] and UI.dismissed[fw_.addr] ~= fw_.name and UI.dismissed[fw_.addr] ~= true then gw, gkind = fw_, kind; end
            if gw and gkind == 'status' and cfg.statcmd ~= false and gw.name == 'statcom2' then gw, gkind = nil, nil; end
            if gw and gkind ~= 'status' and M.find('statcom2') then gw, gkind = nil, nil; end   -- (a page opened from the Status list - Currencies
                                                                                              --  is the game's "evitem", like Key Items - is the game's)
            if gw then break; end
        end
        if not gw and UI.act_live then                               -- (the action menu's own Magic window: "magic")
            local fw_ = M.open[M.focus or 0];
            if fw_ and fw_.name == 'magic' and UI.dismissed[fw_.addr] ~= fw_.name and UI.dismissed[fw_.addr] ~= true then gw, gkind = fw_, 'magic'; end
        end
        for a, nm in pairs(UI.dismissed) do                          -- (forgotten once that window isn't the focused one any more)
            local w_ = M.open[a];
            if not w_ or M.focus ~= a or (type(nm) == 'string' and w_.name ~= nm) then UI.dismissed[a] = nil; end
        end
        if gw and M.find(cfg.equip_name) then gw = nil; end
        if gw and (M.find('handover') or M.find('delivery') or M.find('post1')) then gw = nil; end              -- (a trade's item list: never the Items menu, it would use the item)           -- (the equipment screen has its own item list: not the Items menu)
        if UI.close_game or UI.chain then gw = nil; end
        if gw and (UI.browse == nil or UI.browse.via == 'game') then
            if UI.browse == nil or UI.browse.kind ~= gkind then
                UI.browse = { kind = gkind, via = 'game', t0 = os.clock(), from_act = UI.act_live and true or nil };
                if gkind == 'items' and UI.mog_pick then UI.browse.mog = UI.mog_pick; end   -- (from the Mog House storage menu)
                if gkind == 'items' and not UI.mog_pick and UI.act_live then UI.browse.usable = true; end   -- (from the action menu)
                if gw.name == 'abiselec' then UI.browse.stage, UI.browse.menu = 'menu', true; end   -- (from the action menu: its own first page)
                if gkind == 'magic' and UI.act_live then UI.browse.stage, UI.browse.menu = 'menu', true; end   -- (Magic from the action menu: kinds first)
            end
            UI.browse.anchor = M.to_screen(gw.rect);
            UI.browse.gw_addr, UI.browse.gw_name = gw.addr, gw.name;
        elseif UI.browse and UI.browse.via == 'game' and not gw then
            UI.browse = nil;
        end
        if UI.browse and UI.browse.via == 'main' and not mw then UI.browse = nil; end   -- (the main menu closed: so does it)
        if UI.browse then
            local anchor = UI.browse.anchor;
            if UI.browse.via ~= 'game' and UI.mainbox and mw then anchor = UI.mainbox; end
            UI.tip_id, UI.tip_at, UI.tip_ext, UI.tip_bi = nil, nil, nil, nil;
            local gw_hide = (UI.browse.via == 'game') and gw or nil;
            local drew = guarded('browse', draw_browser, UI.browse, anchor);
            UI.browse_drawn = drew and UI.browse ~= nil;
            if drew and gw_hide and UI.pad_owner == 'browse' then
                local also = (UI.browse and UI.browse.kind == 'status') and { level = true, profile = true, joblevel = true, btlskill = true,
                    mgcskill = true, trdskill = true, levmerit = true } or { itmsortw = true };
                for _, w in ipairs(M.wins) do if w.name == gw_hide.name or also[w.name] then M.hide(w); end end
            end
            if drew and UI.browse and UI.browse.kind == 'status' then   -- (opened from the main menu too: the game's Status list goes, however it came)
                local st_ = {};
                for _, n in ipairs(split(cfg.win_status)) do st_[n] = true; end
                st_.statcom2 = true;
                for _, w in ipairs(M.wins) do if st_[w.name] then M.hide(w, 'park'); end end
            end
            if UI.tip_id then
                local mx, my = mouse();
                guarded('tooltip', function()
                    UI.began, UI.pushed = false, 0;
                    imgui.SetNextWindowPos({ -10000, -10000 }, ImGuiCond_Always);
                    imgui.SetNextWindowSize({ 4, 4 }, ImGuiCond_Always);
                    local o = imgui.Begin('##ccm_tipfont', { true }, win_flags());   -- (a window to push the font in)
                    UI.began = true;
                    if o then item_tooltip(UI.tip_id, mx, my, UI.tip_at, UI.tip_ext, UI.tip_bi and UI.tip_bi[1], UI.tip_bi and UI.tip_bi[2]); end
                    imgui.End(); UI.began = false;
                end);
            end
        end
    end

    -- the swap menu, next to the equipment panel (the game's own item list is hidden while you browse the slots, and
    -- shown again as soon as it's in use, so the keyboard / pad still work it as always)
    local iw = M.find('inventor');
    if cfg.char and cfg.list and eq and UI.eq_slot ~= nil and UI.charbox then
        local worn = nil;
        pcall(function() local g = gear()[UI.eq_slot]; worn = g and g.id; end);
        local padded = (UI.pad_owner == 'swap');
        local active = padded or not (iw and M.focus == iw.addr);
        if guarded('swap', draw_swap, UI.eq_slot, worn, active, padded and UI.sw.cur or nil) and iw and active then M.hide(iw); end
    else
        UI.sw.t0 = nil;
        UI.list_pick = nil;
    end
    pcall(chain_tick);
    pcall(verify_tick);
    M.release(false);
end

----------------------------------------------------------------------------------------------------
-- /cmenu windows: what's open right now (to find a window's id), drawn as a small list
----------------------------------------------------------------------------------------------------
local function list_windows()
    if not M.init() then msg('Menus not found: ' .. tostring(M.err)); return; end
    M.scan();
    if #M.wins == 0 then msg('No game windows are open. Open a menu, then try again (bind it to a key for a macro).'); return; end
    msg(('%d window(s) open (the focused one marked *):'):format(#M.wins));
    for _, w in ipairs(M.wins) do
        print(('  %s %-10s buttons %2d  cursor %2d  rect %d,%d %d,%d%s'):format(w.addr == M.focus and '*' or ' ', w.name,
            w.buttons, w.cursor, w.rect[1], w.rect[2], w.rect[3], w.rect[4], M.hidden[w.addr] and '  (hidden by ChadcoreMenu)' or ''));
    end
end

----------------------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------------------
ashita.events.register('load', 'ccm_load', function()
    load_fonts();
    msg('ChadcoreMenu ' .. addon.version .. ' by ChadBrowick loaded.  /cmenu for help.');
end);
ashita.events.register('unload', 'ccm_unload', function()
    pcall(function() M.scan(); end);
    pcall(M.release, true);
    pcall(M.unpark, nil);
    pcall(save);
    pcall(function() vana.gameui.remove('config_menu'); end);
    if EDM and EDM.vhid then pcall(function() vana.gameui.show('macro_bar'); end); end
    if EDM then pcall(function() M.scan(); EDM.restore_buttons(); EDM.unshrink(); ESED.unshrink(true); end); end
end);

----------------------------------------------------------------------------------------------------
-- The mirror: any of the game's menus nothing else here draws. The game draws its interface's letters one square
-- at a time from its font sheet (1024 wide: a letter is 16 x 8 of it in 1024ths, in character order from the space,
-- 64 to a row - "Config", "Back", "Help Desk" read back from a capture of the Help Desk). Each frame the letters
-- inside the menu are read as the game draws them, put on its rows (its buttons) by where they are, and our panel
-- shows them; the game's own drawing of that window is held back. Its buttons still do the work.
----------------------------------------------------------------------------------------------------
MIR = { cur = {}, block = nil, noted = {}, EXTRA = { [102] = ':', [722] = "'" } };   -- (two the font keeps further on, read from the Quests screen)
function MIR.dpup(e)
    if (e.vertex_stream_zero_stride or 0) ~= 28 or (e.primitive_count or 0) ~= 2 or not e.vertex_stream_zero_data then return; end
    local f = ffi.cast('const float*', e.vertex_stream_zero_data);
    local x0, y0 = f[0], f[1];
    local b = MIR.block;
    if b and x0 >= b[1] and x0 < b[3] and y0 >= b[2] and y0 < b[4] then e.blocked = true; end
    local u0, v0, u1, v1 = f[5], f[6], f[26], f[27];
    local du, dv = (u1 - u0) * 1024, (v1 - v0) * 1024;
    if du > 15.9 and du < 16.1 and dv > 7.9 and dv < 8.1 and #MIR.cur < 4000 then
        local col, row = math.floor(u0 * 64 + 0.5), math.floor(v0 * 128 + 0.5);
        local idx = row * 64 + col;
        local ch = (idx >= 0 and idx <= 94) and string.char(idx + 32) or (MIR.EXTRA[idx] or ('{' .. idx .. '}'));
        local c = ffi.cast('const uint32_t*', e.vertex_stream_zero_data)[4];
        MIR.cur[#MIR.cur + 1] = { x = x0, y = y0, ch = ch, col = tonumber(c) or 0 };
    end
end
function MIR.text(G)                                                 -- (letters of one line, left to right, spaces where they're apart)
    table.sort(G, function(a, b) return a.x < b.x; end);
    local out, lx, lc = {}, nil, nil;
    for _, g in ipairs(G) do
        if lx and math.abs(g.x - lx) < 2 and g.ch == lc then goto skip; end   -- (the same letter drawn twice: its shadow)
        if lx and g.x - lx > 14 and out[#out] ~= ' ' then out[#out + 1] = ' '; end
        lc = g.ch;
        out[#out + 1] = g.ch;
        lx = g.x;
        ::skip::
    end
    return (table.concat(out):gsub('^%s+', ''):gsub('%s+$', ''):gsub('  +', ' '));
end
function MIR.lines(G)                                                -- (letters into lines by height)
    table.sort(G, function(a, b) return a.y < b.y; end);
    local L = {};
    for _, g in ipairs(G) do
        local l = L[#L];
        if l and math.abs(g.y - l.y) <= 4 then l.g[#l.g + 1] = g; else L[#L + 1] = { y = g.y, g = { g } }; end
    end
    for _, l in ipairs(L) do l.text = MIR.text(l.g); end
    return L;
end
function MIR.read(w)                                                 -- (the window's rows as the game wrote them, or nil)
    local r = w.rect;                                                -- (the game draws in its own coordinates: the window's own)
    if not r then return nil; end
    local inside = {};
    for _, g in ipairs(MIR.prev or {}) do
        if g.x >= r[1] - 4 and g.x < r[3] and g.y >= r[2] - 4 and g.y < r[4] then inside[#inside + 1] = g; end
    end
    if #inside == 0 then
        local g1 = (MIR.prev or {})[1];
        return nil, ('no letters in it (%d letters this frame%s; window %d,%d %d,%d)'):format(#(MIR.prev or {}), g1 and (', first at %d,%d'):format(g1.x, g1.y) or '', r[1], r[2], r[3], r[4]);
    end
    local B = {};
    for _, x in ipairs(M.buttons(w)) do
        if (x.h or 0) >= 12 and (x.y or 0) > -1000 and (x.shape ~= 0 or x.user ~= 0) and x.no >= 1 and x.no <= w.buttons then
            x.sr = { x.x, x.y, x.x + x.w, x.y + x.h }; B[#B + 1] = x;
        end
    end
    if #B == 0 then return nil, 'no rows'; end
    table.sort(B, function(p_, q_) if p_.y ~= q_.y then return p_.y < q_.y; end return p_.x < q_.x; end);
    local rows, head = {}, {};
    for i = 1, #B do rows[i] = { g = {}, right = {} }; end
    for _, g in ipairs(inside) do
        local cx, cy = g.x + 6, g.y + 8;
        local hit = nil;
        for i, b in ipairs(B) do
            if cx >= b.sr[1] - 2 and cx <= b.sr[3] + 2 and cy >= b.sr[2] - 3 and cy <= b.sr[4] + 3 then hit = i; break; end
        end
        if hit then rows[hit].g[#rows[hit].g + 1] = g;
        else
            for i, b in ipairs(B) do                                 -- (to the right of a row, on its line: its value)
                if cy >= b.sr[2] - 3 and cy <= b.sr[4] + 3 and cx > b.sr[3] then hit = i; break; end
            end
            if hit then rows[hit].right[#rows[hit].right + 1] = g; else head[#head + 1] = g; end
        end
    end
    local filled = 0;
    for i, rw in ipairs(rows) do rw.b = B[i]; end
    for i, rw in ipairs(rows) do
        local lastx = nil; for _, g in ipairs(rw.g) do if not lastx or g.x > lastx then lastx = g.x; end end
        local firstr = nil; for _, g in ipairs(rw.right) do if not firstr or g.x < firstr then firstr = g.x; end end
        if lastx and firstr and firstr - lastx < 16 then             -- (a label running past its row's box: one text)
            for _, g in ipairs(rw.right) do rw.g[#rw.g + 1] = g; end
            rw.right = {};
        end
        rw.text = MIR.text(rw.g); rw.rtext = MIR.text(rw.right);
        if rw.text ~= '' then filled = filled + 1; end
    end
    -- (a row's words kept from earlier frames: the one under the game's cursor is drawn another way - lit - and isn't
    --  always read; the rows the game leaves empty - spare places in a long list - aren't shown, except the cursor's)
    MIR.cache = MIR.cache or {};
    local C_ = MIR.cache[w.addr];
    if not C_ or C_.name ~= w.name then C_ = { name = w.name }; MIR.cache[w.addr] = C_; end
    for _, rw in ipairs(rows) do
        local k = rw.b.no;
        if rw.text ~= '' then C_[k] = { rw.text, rw.rtext }; elseif C_[k] then rw.text, rw.rtext = C_[k][1], (rw.rtext ~= '') and rw.rtext or C_[k][2]; end
    end
    filled = 0;
    local kept = {};
    for _, rw in ipairs(rows) do
        if rw.text ~= '' then filled = filled + 1; end
        if rw.text ~= '' or rw.rtext ~= '' or rw.b.no == w.cursor then kept[#kept + 1] = rw; end
    end
    if filled < 2 and #rows > 1 then return nil, ('%d of %d rows with words'):format(filled, #rows); end
    rows = kept;
    local hl = MIR.lines(head);
    return { rows = rows, head = hl, rect = r };
end
function MIR.unpark()                                                -- (the copied menu's buttons back where the mouse can reach them)
    if MIR.parked then pcall(M.unpark, MIR.parked); MIR.parked = nil; end
end
function MIR.frame()
    UI.mir_drawn = false;
    local ok_, err_ = pcall(MIR.frame2);
    if not UI.mir_drawn then MIR.unpark(); end
    if not ok_ then error(err_, 0); end
end
function MIR.frame2()
    if cfg.mirror == false then MIR.block = nil; return; end
    local w, b = TCH.candidate();
    if not w or TCH.taught(w, b) or TCH.auto(w, b) or TCH.st then
        local fw = M.open[M.focus or 0];
        if fw and not w and MIR.cnote ~= fw.addr then
            MIR.cnote = fw.addr;
            local h = M.hidden[fw.addr];
            M.note('mirrorc' .. os.clock(), ('%s: not a candidate (hidden by us this frame %s, rows %d)'):format(fw.name, tostring(h and h.seen == M.frame), #(TCH.rows(fw))));
        end
        MIR.block = nil; MIR.w = nil; return;
    end
    local R, why = MIR.read(w);
    if not R then
        if MIR.w == w.addr and MIR.keep and (os.clock() - MIR.keep.t < 0.3 or (MIR.parked == w.addr and MIR.keep.nb == w.buttons)) then
            R = MIR.keep.R;                                          -- (a frame with no letters, or its buttons moved away by us: the last)
        else
            local nk = w.name .. ':' .. w.buttons;
            if not MIR.noted[nk] or (type(MIR.noted[nk]) == 'number' and os.clock() - MIR.noted[nk] > 2 and (MIR.nfail or 0) < 12) then
                MIR.noted[nk] = os.clock(); MIR.nfail = (MIR.nfail or 0) + 1;
                M.note('mirror' .. w.name .. os.clock(), ('%s: not mirrored (%s)'):format(w.name, tostring(why)));
            end
            MIR.block = nil; MIR.w = nil; return;
        end
    end
    if not (MIR.keep and MIR.keep.R == R) then MIR.keep = { R = R, t = os.clock(), nb = w.buttons }; end
    MIR.w = w.addr;
    -- (the controller in use: the game's buttons moved off screen as on every other panel - with the mouse resting
    --  on one, the game takes Confirm for that one, or for none; the mouse moved again: they're put back)
    do
        local mx, my = imgui.GetMousePos();
        if mx ~= MIR.mx or my ~= MIR.my then MIR.mx, MIR.my, MIR.mouse_t = mx, my, os.clock(); end
        if (UI.pad_t or 0) > (MIR.mouse_t or 0) and cfg.hide_buttons ~= false then
            if MIR.parked ~= w.addr then MIR.unpark(); M.note('mirrorpark' .. os.clock(), w.name .. ': controller - its buttons moved off screen'); end
            pcall(M.park_buttons, w); MIR.parked = w.addr;
        elseif MIR.parked then MIR.unpark(); end
    end
    local key = w.name .. ':' .. w.buttons .. ':ok';
    if not MIR.noted[key] then
        MIR.noted[key] = true;
        local t = {}; for i, rw in ipairs(R.rows) do t[i] = rw.b.no .. '=' .. rw.text .. ((rw.rtext ~= '') and (' [' .. rw.rtext .. ']') or ''); end
        local h = {}; for i, l in ipairs(R.head) do h[i] = l.text; end
        M.note('mirror' .. w.name .. os.clock(), ('%s mirrored: %s ;; head: %s'):format(w.name, table.concat(t, ' | '), table.concat(h, ' / ')));
    end
    local ok = guarded('mirror_' .. w.name, MIR.draw, w, R);
    if ok then
        UI.mir_drawn = true;
        local r = R.rect;
        MIR.block = { r[1] - 40, r[2] - 20, r[3] + 10, r[4] + 10 };  -- (the game's own drawing of it held back: frame, rows, its arrow)
    else MIR.block = nil; end
end
function MIR.curno(w)                                                -- (the game's cursor, or the row we just moved it to)
    if MIR.pc and MIR.pc.w == w.addr and os.clock() - MIR.pc.t < 0.35 then return MIR.pc.no; end
    return w.cursor;
end
function MIR.press_note(id, okid, backid)                            -- (which button did what on a copied menu: for the survey)
    MIR.npress = (MIR.npress or 0) + 1;
    if MIR.npress > 40 then return; end
    local w = M.open[M.focus or 0];
    M.note('mirrorpad' .. os.clock(), ('pad %s on %s (cursor %s; confirm is %s, cancel is %s)'):format(id, w and w.name or '?', tostring(w and w.cursor), okid, backid));
end
function MIR.ok_pressed()                                            -- (Confirm on a copied menu goes to the game itself; if
    MIR.okt, MIR.okw = os.clock(), M.focus;
    UI.pad_t = os.clock();                          --  nothing happened, it's pressed for it a moment later)
end
function MIR.ok_check()
    if not MIR.okt or os.clock() - MIR.okt < 0.3 then return; end
    local t0 = MIR.okt;
    local wa = MIR.okw; MIR.okt, MIR.okw = nil, nil;
    if MIR.sel_t and MIR.sel_t >= t0 - 0.05 then M.note('mirrorok' .. os.clock(), 'confirm reached the game (VanaCore saw it)'); return; end
    local w = M.open[wa or 0];
    if w and M.focus == wa and not w.closing then
        M.note('mirrorok' .. os.clock(), ('%s: confirm did nothing in the game; pressed for it on button %s'):format(w.name, tostring(MIR.curno(w))));
        M.act(wa, MIR.curno(w), KEY.ok);
    else M.note('mirrorok' .. os.clock(), 'confirm went to the game'); end
end
function MIR.pad(acts)                                               -- (the controller on a mirrored menu: its rows, in our order)
    local w, K = M.open[MIR.w or 0], MIR.keep;
    if not w or not K or not K.R or #K.R.rows == 0 then return; end
    local rows, n = K.R.rows, #K.R.rows;
    local cn, c = MIR.curno(w), nil;
    for i, rw in ipairs(rows) do if rw.b.no == cn then c = i; end end
    local moved = false;
    for _, act in ipairs(acts) do
        if act == 'up' then c = (c and c > 1) and (c - 1) or n; moved = true;
        elseif act == 'down' then c = (c and c < n) and (c + 1) or 1; moved = true;
        elseif act == 'ok' then M.act(w.addr, rows[c or 1].b.no, KEY.ok); MIR.pc = nil; return;
        elseif act == 'back' then M.act(nil, nil, KEY.cancel); MIR.pc = nil; return;
        elseif act == 'left' or act == 'right' then M.act(w.addr, nil, (act == 'left') and KEY.left or KEY.right); return; end
    end
    if moved and c then
        MIR.pc = { w = w.addr, no = rows[c].b.no, t = os.clock() };
        M.act(w.addr, rows[c].b.no, nil);
    end
end
function MIR.draw(w, R)
    local s = PSCALE();
    local rows, cur = {}, 1;
    for i, rw in ipairs(R.rows) do
        local off = (rw.b.status == 5);
        rows[i] = { (rw.text ~= '') and rw.text or '-', (rw.rtext ~= '') and rw.rtext or (off and 'n/a' or ''), nil, off };
        if rw.b.no == MIR.curno(w) then cur = i; end
    end
    local title = (R.head[1] and R.head[1].text) or w.name:upper();
    local sub = {}; for i = 2, #R.head do sub[#sub + 1] = R.head[i].text; end
    local W = math.floor(320 * s);
    for _, r_ in ipairs(rows) do W = math.max(W, math.floor((#r_[1] + #(r_[2] or '')) * 8.5 * s + 90 * s)); end   -- (by length: no font outside a window)
    local nat = M.to_screen(R.rect);
    local x, y = nat and nat[1] or R.rect[1], nat and nat[2] or R.rect[2];
    local clicked, wd = list_panel('mirror', x, y, math.min(W, math.floor(700 * s)), title, table.concat(sub, '  '), rows, cur,
        { focused = (M.focus == w.addr), min_rows = math.min(#rows, 3) });
    if M.focus ~= w.addr then return true; end
    if clicked then MIR.pc = nil; M.act(w.addr, R.rows[clicked].b.no, (clicked == cur) and KEY.ok or nil); end
    if wd ~= 0 then local to = cur + wd; if to >= 1 and to <= #rows then MIR.pc = { w = w.addr, no = R.rows[to].b.no, t = os.clock() }; M.act(w.addr, R.rows[to].b.no, nil); end end
    return true;
end
pcall(function()                                                     -- (what VanaCore sees the Help Desk menus do: for the survey)
    if vana == nil or vana.gameui == nil or vana.gameui.on == nil then return; end
    for _, mn in ipairs({ 'faqsub', 'faqmain', 'guide00', 'scresult' }) do
        pcall(vana.gameui.on, mn, '*', function(e)
            if e.event == 'select' then
                MIR.sel_t = os.clock();
                local wd_ = '?'; for _, rw in ipairs((MIR.keep and MIR.keep.R and MIR.keep.R.rows) or {}) do if rw.b.no == e.item then wd_ = rw.text; end end
                M.note('mirrorsel' .. os.clock(), ('gameui %s: select item %s = "%s"'):format(tostring(e.menu), tostring(e.item), wd_));
            end
            if e.event == '9' or e.event == 9 or e.event == 32 or e.event == '32' then return; end
            MIR.ng = (MIR.ng or 0) + 1;
            if MIR.ng <= 60 then M.note('mirrorui' .. os.clock(), ('gameui %s: %s item %s key %s'):format(tostring(e.menu), tostring(e.event), tostring(e.item), tostring(e.key))); end
        end);
    end
end);
pcall(function() ashita.events.register('d3d_dpup', 'ccm_mirror', function(e) if cfg.mirror ~= false then pcall(MIR.dpup, e); end end); end);
TPROBE = nil;
ashita.events.register('d3d_present', 'ccm_present', function()
    MIR.prev, MIR.cur = MIR.cur, {};                                 -- (this frame's letters, as the game drew them, for the panels)
    if TPROBE then                                                   -- (the text probe: three frames, then the log)
        TPROBE.frames = TPROBE.frames + 1;
        if TPROBE.frames >= 1 then
            local P = TPROBE; TPROBE = nil;
            pcall(function() ashita.events.unregister('d3d_dpup', 'ccm_tprobe'); end);
            local h = {}; for k, v in pairs(P.hist) do h[#h + 1] = k .. '=' .. v; end
            M.note('tprobe' .. os.clock(), ('text probe: %d draws in 3 frames: %s'):format(P.calls, table.concat(h, ' ')));
            for i, sm in ipairs(P.samples) do M.note('tprobes' .. i .. os.clock(), sm); end
            for i = 1, #P.quads, 200 do                              -- (the quads, 200 a line: x,y,w,h,u0,v0,u1,v1 - u / v in 1024ths)
                M.note('tprobeq' .. i .. os.clock(), table.concat(P.quads, ' ', i, math.min(#P.quads, i + 199)));
            end
            msg('Text probe done (' .. P.calls .. ' draws).');
        end
    end
    local ok, err = pcall(frame);
    if not ok then
        errlog('frame', err);
        pcall(function() M.release(true); end);
    end
end);

local HELP = {
    { '/cmenu',                 'this help' },
    { '/cmenu on | off',        'ChadcoreMenu on or off (off = the game\'s own menus)' },
    { '/cmenu settings',        'the settings panel (also in the game\'s Config menu)' },
    { '/cmenu refresh',         'reload ChadcoreMenu when something is stuck (or click the logo)' },
    { '/cmenu lsswap',          'swap the two linkpearls if picking one opens the other' },
    { '/cmenu teach',           'teach an old menu: type what its rows say, it is drawn in the new style from then on' },
    { '/cmenu forget',          'forget every taught menu' },
    { '/cmenu main on | off',   'the main menu' },
    { '/cmenu char on | off',   'the Status / Equipment panel' },
    { '/cmenu clicks on | off', 'mouse clicks drive the game\'s menus' },
    { '/cmenu lock | unlock',   'lock the panels, or let them be dragged by their tops (also the lock icon)' },
    { '/cmenu resetpos',        'every panel back in its own place' },
    { '/cmenu scale 1.1',       'size (0.6 - 2)' },
    { '/cmenu windows',         'list the game windows open now (their ids)' },
    { '/cmenu hide <id>',       'also hide that window with the character panel' },
    { '/cmenu unhide <id>',     'stop hiding it' },
    { '/cmenu mainid <id>',     'the main menu\'s window id (default menuwind)' },
    { '/cmenu statusids <ids>',    'which windows make up the Status screen (comma list)' },
    { '/cmenu labels a,b,...',  'your own main menu names (empty = built-in)' },
    { '/cmenu status | magic | abilities | items | keyitems', 'open or close that panel (bind it to a key)' },
    { '/cmenu trade on | off',  'trading an NPC: the own trade list (pick items, then TRADE)' },
    { '/cmenu inspect on | off', 'the Check window on another player (gear, linkshell, bazaar)' },
    { '/cmenu warpmap on | off | game', 'the map card in the Home Point / Survival Guide menus (game: the game\'s own maps)' },
    { '/cmenu delivery on | off', 'the Moogle\'s Delivery Box (Receive / Send) in the new style' },
    { '/cmenu query on | off',   'event questions with a few answers (Yes / No and the like) in the new style' },
    { '/cmenu macro on | off',   'the Ctrl / Alt macro bars (names and lines from your macro files)' },
    { '/cmenu treasure on | off', 'Treasure in the action menu while anything is in the pool (lot / pass)' },
    { '/cmenu npcmenu on | off',  'the server\'s own NPC menus (EXP Guide (S) and the like) in the Home Point style' },
    { '/cmenu warpmap zoom | whole', 'that map zoomed in round the spot, or the whole map' },
    { '/cmenu warpmap test', 'check every place\'s map; the report goes in chadcoremenu-survey.txt' },
    { '/cmenu hide [id] / unhide <id>', 'keep a game window hidden all the time (no id: the list, and what\'s open now)' },
    { '/cmenu bazaar on | off', 'another player\'s bazaar (View Wares) in the new look' },
    { '/cmenu browse on | off', 'the own Magic / Abilities / Items / Key Items panels' },
    { '/cmenu pad',             'controller: shows the confirm / cancel buttons (on | off | reset | ok <id> | back <id>)' },
    { '/cmenu learn',           'teach it the main menu\'s order (press Down through it once)' },
    { '/cmenu learn reset',     'forget the learned order' },
    { '/cmenu dump',            'write the open windows\' buttons to chadcoremenu-dump.txt' },
    { '/cmenu hidemode draw | move | both', 'how the game\'s windows are hidden (add main to set the main menu\'s)' },
    { '/cmenu reset',           'back to the defaults' },
};
local function onoff(v, cur) if v == 'on' then return true elseif v == 'off' then return false end return not cur end
-- (a button's let-go goes where its press went: kept from the game if the press was - the game acts on a let-go it
--  never saw the press of (a Check became Chat) - and given to the game if the press was the game's: holding Up into
--  the main menu's last line, a kept let-go left the game repeating Up)
local PADB = {};
function MCRF.pad(id, act, down)                               -- (the pad with our macro bar up: D-pad and confirm are its)
    if not down then if PADB[id] == 'mcrf' then PADB[id] = nil; return true; end return false; end
    if not MCRF.active() then return false; end
    if PADB[id] == 'mcrf' then return true; end
    if not act then return false; end
    PADB[id] = 'mcrf';
    if act == 'up' then MCRF.step(-1); elseif act == 'down' then MCRF.step(1);
    elseif act == 'left' then MCRF.cur = (MCRF.cur + 8) % 10 + 1; elseif act == 'right' then MCRF.cur = MCRF.cur % 10 + 1;
    elseif act == 'ok' then MCRF.run(MCRF.cur); end
    return true;
end
ashita.events.register('dinput_button', 'ccm_pad_d', function(e)    -- PlayStation and other DirectInput pads
    local b, st = e.button, e.state or 0;
    if b ~= 32 and st >= 128 then PAD.last, PAD.last_t = 'd' .. b, os.clock(); end
    local id = 'd' .. b;
    local up = (b == 32) and (st < 0 or st > 36000) or (b ~= 32 and st < 128);
    do
        local act = nil;
        if b == 32 then act = ({ [0] = 'up', [9000] = 'right', [18000] = 'down', [27000] = 'left' })[st];
        elseif id == pad_id('ok', 'd') then act = 'ok'; end
        if MCRF.pad(id, act, not up) then e.blocked = true; return; end
    end
    if up then
        if b == 32 then pad_hold(nil); end
        local pb = PADB[id];                                         -- (each let-go can come twice: both kept)
        if pb then
            local now_ = os.clock();
            pb.rel = pb.rel or now_;
            if now_ - pb.rel < 0.3 then e.blocked = true; else PADB[id] = nil; end
        end
        return;
    end
    local pbp = PADB[id];
    if pbp and (pbp.rel or os.clock() - (pbp.t or 0) > 0.25) then PADB[id] = nil; pbp = nil; end   -- (a new press: a let-go
    if pbp and not UI.pad_owner then e.blocked = true; return; end  --  isn't always reported; only a quick repeat is the same press)
    if not UI.pad_owner then return; end
    if UI.pad_owner == 'mirror' then MIR.press_note(id, pad_id('ok', 'd'), pad_id('back', 'd')); end
    if UI.pad_owner == 'mirror' and (id == pad_id('ok', 'd') or id == pad_id('back', 'd')) then UI.pad_t = os.clock(); return; end   -- (a copied menu: Confirm / Cancel the game's own;
                                                                     --  up / down ours - the game's own don't move this one's cursor)
    if b == 32 then                                                  -- the D-pad (an angle, in hundredths of a degree)
        local dir = nil;
        if st == 0 or st == 4500 or st == 31500 then dir = 'up';
        elseif st == 9000 then dir = 'right';
        elseif st == 18000 or st == 13500 or st == 22500 then dir = 'down';
        elseif st == 27000 then dir = 'left'; end
        pad_hold(dir);
        if dir then e.blocked = true; PADB[id] = PADB[id] or { t = os.clock() }; end
    elseif id == pad_id('ok', 'd') then pad_push('ok'); e.blocked = true; PADB[id] = PADB[id] or { t = os.clock() };
    elseif id == pad_id('back', 'd') then pad_push('back'); e.blocked = true; PADB[id] = PADB[id] or { t = os.clock() };
    elseif b == 52 or b == 53 then pad_push((b == 52) and 'tabl' or 'tabr'); e.blocked = true; PADB[id] = PADB[id] or { t = os.clock() };
    elseif b == 48 then pad_push('sort'); e.blocked = true; PADB[id] = PADB[id] or { t = os.clock() }; end     -- (Square: sort)
end);
ashita.events.register('xinput_button', 'ccm_pad_x', function(e)    -- Xbox (XInput) pads
    local b, st = e.button, e.state or 0;
    if b > 3 and st ~= 0 then PAD.last, PAD.last_t = 'x' .. b, os.clock(); end
    local id = 'x' .. b;
    do
        local act = (b <= 3) and ({ [0] = 'up', 'down', 'left', 'right' })[b] or ((id == pad_id('ok', 'x')) and 'ok' or nil);
        if MCRF.pad(id, act, st ~= 0) then e.blocked = true; return; end
    end
    if st == 0 then
        if b <= 3 then pad_hold(nil); end
        local pb = PADB[id];                                         -- (each let-go can come twice: both kept)
        if pb then
            local now_ = os.clock();
            pb.rel = pb.rel or now_;
            if now_ - pb.rel < 0.3 then e.blocked = true; else PADB[id] = nil; end
        end
        return;
    end
    local pbp = PADB[id];
    if pbp and (pbp.rel or os.clock() - (pbp.t or 0) > 0.25) then PADB[id] = nil; pbp = nil; end   -- (a new press: a let-go
    if pbp and not UI.pad_owner then e.blocked = true; return; end  --  isn't always reported; only a quick repeat is the same press)
    if not UI.pad_owner then return; end
    if UI.pad_owner == 'mirror' then MIR.press_note(id, pad_id('ok', 'x'), pad_id('back', 'x')); end
    if UI.pad_owner == 'mirror' and (id == pad_id('ok', 'x') or id == pad_id('back', 'x')) then UI.pad_t = os.clock(); return; end   -- (a copied menu: Confirm / Cancel the game's own;
                                                                     --  up / down ours - the game's own don't move this one's cursor)
    if b <= 3 then                                                   -- D-pad: 0 up, 1 down, 2 left, 3 right
        pad_hold(({ [0] = 'up', 'down', 'left', 'right' })[b]); e.blocked = true; PADB[id] = PADB[id] or { t = os.clock() };
    elseif id == pad_id('ok', 'x') then pad_push('ok'); e.blocked = true; PADB[id] = PADB[id] or { t = os.clock() };
    elseif id == pad_id('back', 'x') then pad_push('back'); e.blocked = true; PADB[id] = PADB[id] or { t = os.clock() };
    elseif b == 8 or b == 9 then pad_push((b == 8) and 'tabl' or 'tabr'); e.blocked = true; PADB[id] = PADB[id] or { t = os.clock() };
    elseif b == 14 then pad_push('sort'); e.blocked = true; PADB[id] = PADB[id] or { t = os.clock() }; end       -- (X: sort)
end);
local KEYS = { [0xC8] = 'up', [0xD0] = 'down', [0xCB] = 'left', [0xCD] = 'right', [0x1C] = 'ok', [0x9C] = 'ok', [0x01] = 'back',
               [0xC9] = 'tabl', [0xD1] = 'tabr' };
local KHELD = {};
MCRF.keys = { [0x02] = 1, [0x03] = 2, [0x04] = 3, [0x05] = 4, [0x06] = 5, [0x07] = 6, [0x08] = 7, [0x09] = 8, [0x0A] = 9, [0x0B] = 10,
              [0xC8] = 'up', [0xD0] = 'down', [0xCB] = 'left', [0xCD] = 'right', [0x1C] = 'ok', [0x9C] = 'ok' };

-- (for building Home Point / Survival Guide menus: the game's event packets go to the survey file - which event, its
--  parameters, and what was picked - so the menus' options can be worked out)
local function ev_log(dir, id, d)
    if not cfg.survey then return; end
    pcall(function()
        local hex = (d:sub(1, math.min(#d, 0x60)):gsub('.', function(c) return ('%02X'):format(c:byte()); end));
        M.note('event' .. dir .. id .. os.clock(), ('%s 0x%03X len %d: %s'):format(dir, id, #d, hex));
    end);
end
ashita.events.register('packet_out', 'ccm_pout', function(e)
    if e.id == 0x05B or e.id == 0x05C or e.id == 0x01A then ev_log('out', e.id, e.data_modified or e.data); end
    if e.id == 0x01A then pcall(function()                           -- (talking to someone: who, for an NPC menu's title)
        local d = e.data_modified or e.data;
        if d:byte(0x0B) == 0 and d:byte(0x0C) == 0 then GMT.talk = { d:byte(0x09) + d:byte(0x0A) * 256, os.clock() }; end
    end); end
    if e.id == 0x083 or e.id == 0x084 or e.id == 0x085 then ev_log('out', e.id, e.data_modified or e.data); end
    if e.id == 0x084 or e.id == 0x085 then pcall(SHP.check_out, e); end
    if e.id == 0x083 or e.id == 0x0AA or e.id == 0x0AC then ev_log('out', e.id, e.data_modified or e.data); pcall(SHP.amount_out, e); end
    if e.id == 0x04D then ev_log('out', e.id, e.data_modified or e.data); end
    if e.id == 0x04D then pcall(DLV.out, e.data_modified or e.data); end
    if e.id == 0x0B6 then local okg, errg = pcall(GMT.out, e); if not okg then errlog('menu answer', errg); end end
    if e.id == 0x10A then pcall(SHP.bz_out, e); end                  -- (a bazaar price being set: for the row our list had lit?)
end);
ashita.events.register('packet_in', 'ccm_pin', function(e)
    if e.id == 0x032 or e.id == 0x033 or e.id == 0x034 or e.id == 0x05C or e.id == 0x052 then ev_log('in', e.id, e.data_modified or e.data); end
    if e.id == 0x034 and cfg.warp ~= false then pcall(WARP.packet, e.data_modified or e.data); end
    if e.id == 0x032 or e.id == 0x034 then pcall(QRY.event, e.data_modified or e.data); end
    if e.id == 0x05C then pcall(QRY.update, e.data_modified or e.data); end
    if e.id == 0x08C then pcall(MYROOM.merit_packet, e.data_modified or e.data); end
    if e.id == 0x03D then pcall(SHP.sold, e.data_modified or e.data); end
    if e.id == 0x083 then local okg2, errg2 = pcall(SHP.gpacket, e.data_modified or e.data); if not okg2 then errlog('guild packet', errg2); end end
    if e.id == 0x085 then local okg3, errg3 = pcall(SHP.gpacket, e.data_modified or e.data, true); if not okg3 then errlog('guild packet', errg3); end end
    if e.id == 0x082 or e.id == 0x083 or e.id == 0x084 or e.id == 0x085 then ev_log('in', e.id, e.data_modified or e.data); end
    if e.id == 0x03C then local oks, errs = pcall(SHP.packet, e.data_modified or e.data); if not oks then errlog('shop packet', errs); end end
    if e.id == 0x03C or e.id == 0x03D or e.id == 0x03E or e.id == 0x03F then ev_log('in', e.id, e.data_modified or e.data); end
    if e.id == 0x04B then ev_log('in', e.id, e.data_modified or e.data); end
    if e.id == 0x04B then local okd, errd = pcall(DLV.packet, e.data_modified or e.data); if not okd then errlog('delivery packet', errd); end end
    if e.id == 0x0D2 or e.id == 0x0D3 or e.id == 0x00A then local okt, errt = pcall(TRE.packet, e.id, e.data_modified or e.data); if not okt then errlog('treasure packet', errt); end end
    if e.id == 0x017 and cfg.npcmenu ~= false then pcall(GMT.packet, e.data_modified or e.data); end
    if e.id == 0x113 or e.id == 0x118 then pcall(MYROOM.cur_packet, (e.id == 0x113) and 1 or 2, e.data_modified or e.data); end
    if e.id == 0x056 or e.id == 0x111 or e.id == 0x112 or e.id == 0x113 then pcall(QST.packet, e.id, e.data_modified or e.data); end
    if e.id == 0x105 or e.id == 0x106 then
        local okb, errb = pcall(BAZ.packet, e.id, e.data_modified or e.data);
        if not okb then errlog('bazaar packet', errb); end
        return;
    end
    if e.id ~= 0x0C9 and e.id ~= 0x0CA then return; end
    local ok, err = pcall(INS.packet, e.id, e.data_modified or e.data);
    if not ok then errlog('check packet', err); end
end);
ashita.events.register('key_data', 'ccm_kb', function(e)
    local k = e.key;
    if MCRF.active() and (MCRF.keys[k] or (KHELD[k] == 'mcrf')) then   -- (our macro bar up in place of the game's)
        e.blocked = true;
        if not e.down then KHELD[k] = nil; return; end
        if KHELD[k] then return; end
        KHELD[k] = 'mcrf';
        local a_ = MCRF.keys[k];
        if type(a_) == 'number' then MCRF.run(a_);
        elseif a_ == 'up' then MCRF.step(-1);
        elseif a_ == 'down' then MCRF.step(1);
        elseif a_ == 'left' then MCRF.cur = (MCRF.cur + 8) % 10 + 1;
        elseif a_ == 'right' then MCRF.cur = MCRF.cur % 10 + 1;
        elseif a_ == 'ok' then MCRF.run(MCRF.cur); end
        return;
    end
    if TCH.st then                                                   -- (the teach form: Enter, arrows and Esc are for typing)
        if k == 0x01 and e.down then TCH.st, TCH.on = nil, false; end
        if KEYS[k] then e.blocked = true; end
        return;
    end
    if not e.down then
        if KHELD[k] then KHELD[k] = nil; e.blocked = true; if KEYS[k] == PAD.held then pad_hold(nil); end end
        return;
    end
    if UI.pad_owner == 'mirror' and (KEYS[k] == 'ok' or KEYS[k] == 'back') then UI.pad_t = os.clock(); return; end   -- (a copied menu: the keys to the game)
    local P_ = (UI.pad_owner == 'trade' and UI.trade) and UI.trade.pick or nil;
    if not P_ and UI.pad_owner == 'bazaar' and UI.baz and UI.baz.pick then P_ = UI.baz.pick; end
    if not P_ and UI.pad_owner == 'browse' and UI.mogx and UI.mogx.pick and UI.browse and UI.browse.mog then P_ = UI.mogx.pick; end
    if not P_ and UI.pad_owner == 'delivery' and UI.dlv and UI.dlv.amt then P_ = UI.dlv.amt; end
    if not P_ and UI.pad_owner == 'sellamt' and SHP.pick then P_ = SHP.pick; end
    if P_ then                                                       -- (the amount picker: type the number; Backspace takes a digit off)
        local DIG = { [0x02] = 1, [0x03] = 2, [0x04] = 3, [0x05] = 4, [0x06] = 5, [0x07] = 6, [0x08] = 7, [0x09] = 8, [0x0A] = 9, [0x0B] = 0,
                      [0x4F] = 1, [0x50] = 2, [0x51] = 3, [0x4B] = 4, [0x4C] = 5, [0x4D] = 6, [0x47] = 7, [0x48] = 8, [0x49] = 9, [0x52] = 0 };
        local dg = DIG[k];
        if dg ~= nil or k == 0x0E then
            e.blocked = true;
            if KHELD[k] then return; end
            KHELD[k] = true;
            local cur = P_.typed and P_.n or 0;
            if k == 0x0E then cur = math.floor(cur / 10); else cur = cur * 10 + dg; end
            P_.n, P_.typed = math.min(P_.max, cur), true;
            return;
        end
    end
    if not UI.pad_owner or KEYS[k] == nil then return; end
    local okio, typing = pcall(function() return imgui.GetIO().WantTextInput; end);
    if okio and typing then return; end
    if KHELD[k] then e.blocked = true; return; end
    KHELD[k] = true;
    local act = KEYS[k];
    if act == 'up' or act == 'down' or act == 'left' or act == 'right' then pad_hold(act); else pad_push(act); end
    e.blocked = true;
end);

ashita.events.register('command', 'ccm_command', function(e)
    local args = e.command:args();
    local c0 = #args > 0 and args[1]:lower() or '';
    if not (c0 == '/cmenu' or c0 == '/chadcore' or c0 == '/chadcoremenu') then return; end
    e.blocked = true;
    local sub = (args[2] or ''):lower();
    local rest = table.concat(args, ' ', 3);
    if sub == '' or sub == 'help' then
        msg('ChadcoreMenu ' .. addon.version .. ' by ChadBrowick' .. (M.ok and '' or ('  (menus: ' .. tostring(M.err or 'not found yet') .. ')')));
        for _, h in ipairs(HELP) do print(('  %-28s %s'):format(h[1], h[2])); end
    elseif sub == 'on' or sub == 'off' then
        cfg.enabled = (sub == 'on'); save(); msg('ChadcoreMenu ' .. (cfg.enabled and 'on.' or 'off: the game\'s own menus are back.'));
    elseif sub == 'textprobe' then                                    -- (how the game draws its interface's text: a few frames of it, to the log)
        TPROBE = { frames = 0, calls = 0, hist = {}, samples = {}, quads = {}, full = true };
        pcall(function()
            ashita.events.register('d3d_dpup', 'ccm_tprobe', function(e)
                local P = TPROBE;
                if not P then return; end
                P.calls = P.calls + 1;
                local k = ('pt%d st%d'):format(e.primitive_type or -1, e.vertex_stream_zero_stride or -1);
                P.hist[k] = (P.hist[k] or 0) + 1;
                if P.full and (e.vertex_stream_zero_stride or 0) == 28 and (e.primitive_count or 0) == 2 and #P.quads < 3000 and e.vertex_stream_zero_data then
                    pcall(function()                                 -- (every quad: its place on screen and its part of the texture)
                        local f = ffi.cast('const float*', e.vertex_stream_zero_data);
                        local x0, y0, x1, y1 = f[0], f[1], f[7 * 3 + 0], f[7 * 3 + 1];
                        local u0, v0, u1, v1 = f[5], f[6], f[7 * 3 + 5], f[7 * 3 + 6];
                        P.quads[#P.quads + 1] = ('%d,%d,%d,%d,%d,%d,%d,%d'):format(math.floor(x0), math.floor(y0), math.floor(x1 - x0 + 0.5), math.floor(y1 - y0 + 0.5),
                            math.floor(u0 * 1024 + 0.5), math.floor(v0 * 1024 + 0.5), math.floor(u1 * 1024 + 0.5), math.floor(v1 * 1024 + 0.5));
                    end);
                end
                if #P.samples < 60 and e.vertex_stream_zero_data then
                    pcall(function()
                        local st = e.vertex_stream_zero_stride or 0;
                        local f = ffi.cast('const float*', e.vertex_stream_zero_data);
                        local u = ffi.cast('const uint32_t*', e.vertex_stream_zero_data);
                        local vs = {};
                        for v = 0, math.min(3, (e.primitive_count or 1) + 1) do
                            local o = v * st / 4;
                            local fl = {};
                            for j = 0, st / 4 - 1 do fl[#fl + 1] = ('%.3f'):format(f[o + j]); end
                            vs[#vs + 1] = table.concat(fl, ',') .. (' c%08X'):format(tonumber(u[o + 4]) or 0);
                        end
                        P.samples[#P.samples + 1] = ('pt%d n%d st%d: %s'):format(e.primitive_type or -1, e.primitive_count or -1, st, table.concat(vs, ' | '));
                    end);
                end
            end);
        end);
        msg('Text probe: recording the game\'s interface draws for a moment.');
    elseif sub == 'lsswap' then
        cfg.lnk_swap = not (cfg.lnk_swap == true); save();
        msg('Linkpearl order ' .. ((cfg.lnk_swap == true) and 'swapped.' or 'back to normal.') .. ' Open Linkshell again to see it.');
    elseif sub == 'teach' then
        if TCH.st or TCH.on then TCH.st, TCH.on = nil, false; msg('Teach: cancelled.');
        else TCH.on = true; msg('Teach: with one of the game\'s old menus up, the form appears. Type what its rows say, then Save.'); end
    elseif sub == 'forget' then
        local n_ = 0; for k in pairs(cfg.taught or {}) do n_ = n_ + 1; end
        cfg.taught = {}; save(); msg(('Forgot %d taught menus.'):format(n_));
    elseif sub == 'qdebug' then
        cfg.qdebug = not (cfg.qdebug == true); save();
        msg('Question-box memory search to the log: ' .. (cfg.qdebug and 'on (can hitch a moment)' or 'off'));
    elseif sub == 'refresh' or sub == 'reload' then
        SET.refresh();
    elseif sub == 'settings' or sub == 'config' or sub == 'set' then
        SET.toggle();
    elseif sub == 'shop' then
        cfg.npcshop = onoff(args[3], cfg.npcshop ~= false); save();
        msg('NPC shops in the new style: ' .. (cfg.npcshop and 'on' or 'off (the game\'s own)'));
    elseif sub == 'to' then
        DLV.to = DLV.to or { '' };
        DLV.to[1] = (args[3] or ''):sub(1, 15);
        msg('Delivery Box: sending to ' .. ((DLV.to[1] ~= '') and DLV.to[1] or '(nobody)') .. '.');
    elseif sub == 'delivery' then
        cfg.delivery = onoff(args[3], cfg.delivery ~= false); save();
        msg('Delivery Box in the new style: ' .. (cfg.delivery and 'on' or 'off (the game\'s own)'));
    elseif sub == 'query' then
        cfg.query = onoff(args[3], cfg.query ~= false); save();
        msg('Event questions (Yes / No and the like): ' .. (cfg.query and 'on' or 'off (the game\'s box)'));
    elseif sub == 'macro' then
        cfg.macro = onoff(args[3], cfg.macro ~= false); save();
        MCR.fails, MCR.tried, MCR.sets = 0, nil, nil;
        msg('Macro bars: ' .. (cfg.macro and 'on' or 'off (the game\'s own)'));
    elseif sub == 'treasure' then
        cfg.treasure = onoff(args[3], cfg.treasure ~= false); save();
        msg('Treasure in the action menu: ' .. (cfg.treasure and 'on' or 'off'));
    elseif sub == 'npcmenu' then
        cfg.npcmenu = onoff(args[3], cfg.npcmenu ~= false); save();
        msg('NPC menus from the server (EXP Guide and the like): ' .. (cfg.npcmenu and 'on' or 'off (the game\'s box)'));
    elseif sub == 'action' or sub == 'inspect' or sub == 'bazaar' or sub == 'moogle' or sub == 'statcmd' or sub == 'merits' or sub == 'trade' or sub == 'chat' or sub == 'warp' or sub == 'list' or sub == 'storage' or sub == 'main' or sub == 'char' or sub == 'clicks' or sub == 'wheel' or sub == 'anim' or sub == 'hint' then
        cfg[sub] = onoff((args[3] or ''):lower(), cfg[sub]); save(); msg(sub .. ': ' .. (cfg[sub] and 'on' or 'off'));
    elseif sub == 'hide' or sub == 'unhide' then                     -- your own hide list
        local id = (args[3] or ''):lower();
        local set, out = {}, {};
        for _, n in ipairs(split(cfg.always_hide or '')) do set[n] = true; end
        if id == '' then
            local names = {};
            for n in pairs(set) do names[#names + 1] = n; end
            table.sort(names);
            msg('Always hidden: ' .. ((#names > 0) and table.concat(names, ', ') or 'nothing') .. '.  /cmenu hide <id> adds one, /cmenu unhide <id> takes it off.');
            local open = {};
            for _, w in ipairs(M.wins) do if w.buttons > 0 and w.rect[1] > -3000 then open[#open + 1] = w.name; end end
            if #open > 0 then msg('Game windows open right now: ' .. table.concat(open, ', ')); end
        else
            if sub == 'hide' then set[id] = true; else set[id] = nil; end
            for n in pairs(set) do out[#out + 1] = n; end
            table.sort(out);
            cfg.always_hide = table.concat(out, ','); save();
            msg((sub == 'hide') and ('"' .. id .. '" is hidden from now on (it still works underneath).') or ('"' .. id .. '" shows again.'));
        end
    elseif sub == 'gameui' then                                      -- (what VanaCore's own interface API can hide / catch: into the survey)
        local n = GAMEUI_LOG();
        msg(('vana.gameui knows %s elements. The list is in chadcoremenu-survey.txt (GAMEUI lines).'):format(tostring(n)));
    elseif sub == 'meritcat' then
        cfg.meritcat_on = onoff((args[3] or ''):lower(), cfg.meritcat_on == true); save();
        msg('Merit Categories in the new look: ' .. (cfg.meritcat_on and 'on' or 'off'));
    elseif sub == 'warpmap' then
        local v = (args[3] or ''):lower();
        if v == 'test' then WMAP.test();
        else
            if v == 'game' then cfg.warp_map = 'game';
            elseif v == 'zoom' or v == 'whole' then cfg.warp_zoom = (v == 'zoom');
            else cfg.warp_map = onoff(v, cfg.warp_map ~= false and cfg.warp_map ~= 'off'); end
            save();
            msg('Teleport map card: ' .. ((cfg.warp_map == false) and 'off' or ((cfg.warp_map == 'game') and 'on (the game\'s own maps)' or 'on'))
                .. ((cfg.warp_zoom == false) and ', whole map' or ', zoomed in'));
        end
    elseif sub == 'lock' or sub == 'unlock' or sub == 'move' then
        if sub == 'move' then cfg.locked = not cfg.locked; else cfg.locked = (sub == 'lock'); end
        save();
        msg(cfg.locked and 'Menus locked.' or 'Menus unlocked: drag any ChadcoreMenu panel by its top.  /cmenu lock when done.');
    elseif sub == 'follow' or sub == 'resetpos' then
        for _, k in ipairs({ 'main', 'char', 'swap', 'browse', 'storage', 'act', 'ins', 'baz', 'trade', 'tradebox', 'chat' }) do cfg[k .. '_x'], cfg[k .. '_y'] = -1, -1; end
        for k in pairs(cfg) do if type(k) == 'string' and k:match('^br_.*_[xy]$') then cfg[k] = -1; end end
        cfg.follow = true; save(); msg('Every panel is back in its own place.');
    elseif sub == 'scale' then
        local v = tonumber(args[3]);
        if v then cfg.scale = math.max(0.6, math.min(2, v)); save(); end
        msg('Scale: ' .. tostring(cfg.scale));
    elseif sub == 'windows' or sub == 'list' then
        list_windows();
    elseif sub == 'hide' or sub == 'unhide' then
        local id = (args[3] or ''):lower();
        if id == '' then msg('Which one? /cmenu windows lists the ids.'); return; end
        local set, out = {}, {};
        for _, n in ipairs(split(cfg.extra_hide)) do set[n] = true; end
        set[id] = (sub == 'hide') or nil;
        for n in pairs(set) do out[#out + 1] = n; end
        cfg.extra_hide = table.concat(out, ','); save();
        msg('Hidden with the character panel: ' .. (cfg.extra_hide ~= '' and cfg.extra_hide or '(none)'));
    elseif sub == 'statusids' then
        if rest ~= '' then cfg.status_names = rest:lower():gsub('%s', ''); save(); end
        msg('Status screen windows: ' .. cfg.status_names .. '   equipment: ' .. cfg.equip_name);
    elseif sub == 'mainid' then
        if args[3] then cfg.main_name = args[3]:lower(); save(); end
        msg('Main menu id: ' .. cfg.main_name);
    elseif sub == 'labels' then
        cfg.labels = rest; save(); UI.main.warned = false;
        msg(rest == '' and 'Main menu: built-in names.' or ('Main menu: ' .. #split(rest) .. ' names set.'));
    elseif sub == 'hidemode' then
        local m = (args[3] or ''):lower();
        local which = 'hide_mode';
        if m == 'main' then which, m = 'main_hide', (args[4] or ''):lower(); end
        if m == 'draw' or m == 'move' or m == 'both' then pcall(M.release, true); cfg[which] = m; save(); end
        msg('Hide mode: ' .. cfg.hide_mode .. '   main menu: ' .. cfg.main_hide);
    elseif sub == 'status' or sub == 'magic' or sub == 'abilities' or sub == 'items' or sub == 'keyitems' or sub == 'ki' then
        local kind = (sub == 'ki') and 'keyitems' or sub;
        if UI.browse and UI.browse.kind == kind then close_browse(); else UI.browse = { kind = kind, via = 'cmd', t0 = os.clock() }; end
    elseif sub == 'browse' then
        cfg.browse = onoff((args[3] or ''):lower(), cfg.browse); save(); msg('Own Magic / Abilities / Items / Key Items panels: ' .. (cfg.browse and 'on' or 'off'));
    elseif sub == 'pad' then
        local w2 = (args[3] or ''):lower();
        if w2 == 'on' or w2 == 'off' then cfg.pad = (w2 == 'on'); save();
        elseif w2 == 'reset' then cfg.pad_ok, cfg.pad_back = '', ''; save();
        elseif (w2 == 'ok' or w2 == 'back') and args[4] then cfg['pad_' .. w2] = args[4]:lower(); save(); end
        msg(('Controller: %s   confirm %s / %s   cancel %s / %s   (last button pressed: %s)'):format(cfg.pad and 'on' or 'off',
            pad_id('ok', 'd'), pad_id('ok', 'x'), pad_id('back', 'd'), pad_id('back', 'x'), tostring(PAD.last)));
    elseif sub == 'survey' then
        cfg.survey = onoff((args[3] or ''):lower(), cfg.survey); save(); M.sv = { lines = 0, known = {}, at = 0 };
        msg('Survey to chadcoremenu-survey.txt: ' .. (cfg.survey and 'on' or 'off'));
    elseif sub == 'trace' then
        cfg.trace = onoff((args[3] or ''):lower(), cfg.trace); save(); M.tr = { lines = 0 };
        msg('Trace to chadcoremenu-dump.txt: ' .. (cfg.trace and 'on' or 'off'));
    elseif sub == 'learn' then
        if (args[3] or ''):lower() == 'reset' then
            cfg.main_order = ''; save(); M.ord = {}; UI.learn = nil; UI.main.warned = false;
            msg('Forgot the learned order: it is read from the game again.');
        else
            UI.learn = { seq = {}, last = nil };
            msg('Open the main menu with the cursor on Status, then press Down once per command until it comes back to Status.');
        end
    elseif sub == 'dump' then
        local ok, err = pcall(function()
            if not M.init() then error(tostring(M.err)); end
            M.scan();
            local out = { 'ChadcoreMenu ' .. addon.version .. '  ' .. os.date(), ('menu area %d,%d %d,%d  focus %08X'):format(M.area[1], M.area[2], M.area[3], M.area[4], M.focus or 0) };
            for _, w in ipairs(M.wins) do
                out[#out + 1] = ('\n== %s  addr %08X  buttons %d  cursor %d  rect %d,%d %d,%d  draw %d'):format(w.name, w.addr, w.buttons, w.cursor,
                    w.rect[1], w.rect[2], w.rect[3], w.rect[4], rd8(w.addr + 0x69));
                for _, b in ipairs(M.buttons(w)) do
                    out[#out + 1] = ('   no %2d  x %4d y %4d  w %3d h %3d  shape %08X user %08X status %08X'):format(b.no, b.x, b.y, b.w, b.h, b.shape, b.user, b.status);
                end
                local o = M.order(w);
                out[#out + 1] = '   order: ' .. (o and table.concat(o, ',') or '(none)');
            end
            out[#out + 1] = '\nlearned main order: ' .. (cfg.main_order ~= '' and cfg.main_order or '(none)');
            local f = assert(io.open(addon.path .. 'chadcoremenu-dump.txt', 'w'));
            f:write(table.concat(out, '\n') .. '\n'); f:close();
            M.tr = { lines = 0, opened = true };                     -- (the trace goes on under it)
        end);
        msg(ok and 'Wrote chadcoremenu-dump.txt in the chadcoremenu folder.' or ('Dump failed: ' .. tostring(err)));
    elseif sub == 'reset' then
        pcall(M.release, true); settings.reset(); msg('Back to the defaults.');
    else
        msg('Unknown: ' .. sub .. '  (/cmenu for help)');
    end
end);
