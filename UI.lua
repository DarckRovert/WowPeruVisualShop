--[[--------------------------------------------------------------------------
  Project Jaina - Tienda de Visuales : INTERFAZ (cliente 3.3.5a)
  Version: 2026-09-02

  Se abre con el boton del minimapa. Sin comandos de chat a proposito.

  Toda la presentacion sale de Catalog.lua. Para agregar un visual nuevo NO
  se toca este archivo: se agrega una linea al catalogo (con su `icon`) y
  aparece solo, paginado incluido.

  POR QUE ICONOS Y NO MODELOS 3D
  Las tarjetas usaban un marco `Model`. No hubo manera: estos M2 de
  Item\\ObjectComponents no traen datos de camara, asi que el marco planta la
  suya y no hay posicion, eje, signo ni escala que los deje encuadrados; se
  probaron las tres cosas por separado y el resultado era siempre el mismo
  cuadro vacio. Se cambio a iconos planos, que es lo que hacen los addons de
  cosmeticos que si funcionan. Los iconos se generan renderizando el propio
  modelo con su textura, asi que la tarjeta ensena lo que de verdad se lleva
  puesto y no un dibujo aparte que se pueda desincronizar.
----------------------------------------------------------------------------]]

local PREFIX  = "WPVS"
local ALT_PREFIX = "WP_VISUAL"
local C       = WowPeruVisualCatalog

local ICON_PATH = "Interface\\AddOns\\ProjectJaina_VisualShop\\iconos\\"
local ICON_FALLBACK = "Interface\\Icons\\Spell_Holy_AuraOfLight"

-- Las alas que se mueven traen una LAMINA: una rejilla de 8x4 con 32 fotogramas
-- de su animacion, renderizados del propio modelo, en casillas de 256 px. La
-- tarjeta va cambiando de casilla con SetTexCoord, que es lo mismo que hace el
-- juego con sus texturas animadas. Las que no tienen animacion propia traen una
-- imagen suelta.
--
-- 256 px por casilla no es capricho: la rejilla virtual de la interfaz es de
-- ~1024 px de ancho, asi que a 1920 de resolucion el icono de 124 unidades se
-- dibuja a unos 232 pixeles reales. Con casillas menores el cliente lo estira.
local COLUMNAS, FILAS = 8, 4
local CICLO_MINIMO = 1.5   -- segundos

-- El precio sale del bonus elegido, no del ala. En las tarjetas que aun no
-- tienes se ensena el mas barato, para no prometer un precio que no es.
local PRECIO_MINIMO = 999
for _, b in pairs(C.bonus) do
    if b.price < PRECIO_MINIMO then PRECIO_MINIMO = b.price end
end

-- Coordenadas de una casilla dentro de la lamina.
local function Casilla(f)
    local fx = f % COLUMNAS
    local fy = math.floor(f / COLUMNAS)
    return fx / COLUMNAS, (fx + 1) / COLUMNAS, fy / FILAS, (fy + 1) / FILAS
end

-- Estado local, alimentado por el servidor.
local state = {
    tokens   = 0,
    owned    = {},   -- [id] = clave del bonus con el que se compro
    active   = 0,
    selected = nil,
    page     = 1,
    chunks   = {},   -- buffer para reensamblar OWN troceado
    expChunks = {},  -- lo mismo para EXP
    -- [id] = momento (GetTime) en que caduca. Se guarda en el reloj LOCAL y no
    -- como "segundos que quedan", asi la cuenta sigue bajando con la ventana
    -- abierta sin tener que pedirle nada al servidor.
    expira   = {},
    finChunks = {},  -- buffer para FIN
    -- [id] = true si la tuvo y ya se le paso. No vuelve a estar en venta.
    caducada = {},
}

--------------------------------------------------------------------------
-- Utilidades
--------------------------------------------------------------------------

local function Talk(msg)
    local pName = UnitName("player")
    if not pName or pName == "" or pName == UNKNOWNOBJECT then return end
    if RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(PREFIX)
        RegisterAddonMessagePrefix(ALT_PREFIX)
    end
    SendAddonMessage(PREFIX, msg, "WHISPER", pName)
end

-- Lo que le queda a un ala, corto, que el hueco de la tarjeta es pequeno.
-- Devuelve nil si ya no queda nada o si el servidor no lo mando (cliente nuevo
-- contra servidor viejo): en ese caso no se ensena cuenta atras y punto.
local function Queda(id)
    local fin = state.expira[id]
    if not fin then return nil end
    local seg = fin - GetTime()
    if seg <= 0 then return nil end
    if seg >= 86400 then return string.format("%d d", math.floor(seg / 86400)) end
    if seg >= 3600  then return string.format("%d h", math.floor(seg / 3600)) end
    return string.format("%d min", math.max(1, math.floor(seg / 60)))
end

local function Backdrop(frame, bg, edge)
    frame:SetBackdrop({
        bgFile   = bg   or "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = edge or "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
end

--------------------------------------------------------------------------
-- Ventana principal
--------------------------------------------------------------------------

local CARD_W, CARD_H = 190, 214
local ICON_SIZE_BONO = 110   -- el icono cede sitio al texto del bonus
local PAD            = 14
local ICON_SIZE      = 124

local shop = CreateFrame("Frame", "ProjectJaina_VisualShopFrame", UIParent)
shop:SetWidth(PAD * 2 + C.columns * CARD_W + (C.columns - 1) * 8)
shop:SetHeight(150 + C.rows * (CARD_H + 10))
shop:SetPoint("CENTER")
shop:SetFrameStrata("DIALOG")
shop:EnableMouse(true)
shop:SetMovable(true)
shop:RegisterForDrag("LeftButton")
shop:SetScript("OnDragStart", shop.StartMoving)
shop:SetScript("OnDragStop", shop.StopMovingOrSizing)
Backdrop(shop)
shop:Hide()

-- Cerrar con ESC.
tinsert(UISpecialFrames, "ProjectJaina_VisualShopFrame")

-- Logo Oficial de Project Jaina (Ratio 1:1 circular)
local logo = shop:CreateTexture(nil, "ARTWORK")
logo:SetSize(42, 42)
logo:SetPoint("TOPLEFT", shop, "TOPLEFT", PAD, -10)
logo:SetTexture("Interface\\AddOns\\ProjectJaina_VisualShop\\Textures\\jaina_logo.tga")
logo:SetBlendMode("BLEND")
shop.logo = logo

local title = shop:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -16)
title:SetText("|cFFD4AF37Project Jaina|r - Tienda de Visuales")

local subtitle = shop:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
subtitle:SetPoint("TOP", title, "BOTTOM", 0, -4)
subtitle:SetText(string.format(
    "Elige un visual y compralo. Se equipa solo. Dura %d dias y solo se puede comprar una vez.",
    C.dias))

local pageLabel = shop:CreateFontString(nil, "OVERLAY", "GameFontNormal")
pageLabel:SetPoint("TOPLEFT", PAD + 90, -22)

local tokenLabel = shop:CreateFontString(nil, "OVERLAY", "GameFontNormal")
tokenLabel:SetPoint("TOPRIGHT", -34, -18)

local close = CreateFrame("Button", nil, shop, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -4, -4)

--------------------------------------------------------------------------
-- Tarjetas
--------------------------------------------------------------------------

local cards = {}

local function BuildCard(index)
    local col = (index - 1) % C.columns
    local row = math.floor((index - 1) / C.columns)

    local card = CreateFrame("Button", "WowPeruVisualCard" .. index, shop)
    card:SetWidth(CARD_W)
    card:SetHeight(CARD_H)
    card:SetPoint("TOPLEFT", PAD + col * (CARD_W + 8), -(76 + row * (CARD_H + 10)))
    Backdrop(card, "Interface\\Buttons\\WHITE8X8", "Interface\\Tooltips\\UI-Tooltip-Border")
    card:SetBackdropColor(0, 0, 0, 0.45)
    card:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    card.name = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.name:SetPoint("TOPLEFT", 8, -8)
    card.name:SetPoint("TOPRIGHT", -8, -8)
    card.name:SetJustifyH("LEFT")
    card.name:SetHeight(26)

    card.cat = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.cat:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -1)
    card.cat:SetJustifyH("LEFT")
    card.cat:SetTextColor(0.55, 0.55, 0.95)

    -- Telon oscuro: los iconos tienen fondo transparente y se leen mucho mejor
    -- sobre algo solido que sobre el mundo.
    card.stage = card:CreateTexture(nil, "BACKGROUND")
    card.stage:SetTexture("Interface\\Buttons\\WHITE8X8")
    card.stage:SetVertexColor(0.05, 0.05, 0.07, 1)
    card.stage:SetPoint("TOPLEFT", 8, -50)
    card.stage:SetPoint("BOTTOMRIGHT", -8, 48)

    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetWidth(ICON_SIZE_BONO)
    card.icon:SetHeight(ICON_SIZE_BONO)
    card.icon:SetPoint("CENTER", card.stage, "CENTER", 0, 0)

    card.cost = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.cost:SetPoint("BOTTOMRIGHT", -8, 30)
    card.cost:SetTextColor(1, 0.82, 0)

    -- Que hace el bonus, escrito en la propia tarjeta. Antes solo salia al
    -- pasar el raton por encima, y una ventaja que pagaste merece verse sin
    -- tener que buscarla.
    card.bono = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.bono:SetPoint("BOTTOMLEFT", 8, 8)
    card.bono:SetPoint("BOTTOMRIGHT", -8, 8)
    card.bono:SetJustifyH("LEFT")
    card.bono:SetHeight(20)

    card:SetScript("OnClick", function(self)
        if self.entry then
            state.selected = self.entry.id
            ProjectJaina_VisualShop_Refresh()
        end
    end)

    card:SetScript("OnEnter", function(self)
        if not self.entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.entry.name)
        GameTooltip:AddLine(self.entry.cat, 0.55, 0.55, 0.95)
        local mio = state.owned[self.entry.id]
        local b = mio and mio ~= "" and C.bonus[mio]
        if b then
            GameTooltip:AddLine("Bonus: " .. b.name, 1, 0.82, 0)
            GameTooltip:AddLine(b.desc, 1, 1, 1)
        end
        if state.active == self.entry.id then
            GameTooltip:AddLine("En uso", 0.25, 1, 0.25)
        elseif mio then
            GameTooltip:AddLine("Ya lo tienes. Clic y luego Equipar.", 1, 1, 1)
        elseif state.caducada[self.entry.id] then
            GameTooltip:AddLine("Proximamente", 0.6, 0.6, 0.6)
        else
            GameTooltip:AddLine(string.format("Desde %d %s, segun el bonus que elijas",
                PRECIO_MINIMO, C.currency.name), 1, 0.82, 0)
        end
        if mio then
            local q = Queda(self.entry.id)
            if q then
                GameTooltip:AddLine("Le queda " .. q, 1, 0.82, 0)
            end
        elseif state.caducada[self.entry.id] then
            GameTooltip:AddLine("Ya las tuviste y se te acabaron. No se pueden volver a comprar.",
                0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine(string.format("Dura %d dias, y solo se puede comprar una vez", C.dias),
                0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Reproduccion de la lamina. Solo cambia la casilla cuando toca cambiarla,
    -- asi que entre fotograma y fotograma no hace nada.
    card:SetScript("OnUpdate", function(self, elapsed)
        local e = self.entry
        if not e or not e.frames or e.frames < 2 then return end

        -- Ira Vengadora dura 367 ms: a su velocidad real serian 43 imagenes por
        -- segundo y no se distinguiria nada. Se le pone un suelo.
        local ciclo = math.max((e.ms or 1500) / 1000, CICLO_MINIMO)
        self.t = ((self.t or 0) + elapsed) % ciclo
        local f = math.floor(self.t / ciclo * e.frames)
        if f ~= self.frame then
            self.frame = f
            self.icon:SetTexCoord(Casilla(f))
        end
    end)

    return card
end

for i = 1, C.perPage do
    cards[i] = BuildCard(i)
end

--------------------------------------------------------------------------
-- Botones inferiores
--------------------------------------------------------------------------

local prev = CreateFrame("Button", nil, shop, "UIPanelButtonTemplate")
prev:SetWidth(110); prev:SetHeight(24)
prev:SetPoint("BOTTOMLEFT", PAD, 14)
prev:SetText("Anterior")
prev:SetScript("OnClick", function()
    if state.page > 1 then state.page = state.page - 1; ProjectJaina_VisualShop_Refresh() end
end)

local next_ = CreateFrame("Button", nil, shop, "UIPanelButtonTemplate")
next_:SetWidth(110); next_:SetHeight(24)
next_:SetPoint("BOTTOMRIGHT", -PAD, 14)
next_:SetText("Siguiente")
next_:SetScript("OnClick", function()
    if state.page < C.PageCount() then state.page = state.page + 1; ProjectJaina_VisualShop_Refresh() end
end)

local action = CreateFrame("Button", nil, shop, "UIPanelButtonTemplate")
action:SetWidth(170); action:SetHeight(24)
action:SetPoint("BOTTOM", 0, 14)

--------------------------------------------------------------------------
-- Panel de eleccion de bonus
--
-- Comprar un ala no es solo pagarla: hay que elegir QUE bonus llevara, y esa
-- eleccion es definitiva. Por eso el boton de comprar abre este panel en vez
-- de cobrar directamente, y el precio sale del bonus, no del ala.
--------------------------------------------------------------------------

local panel = CreateFrame("Frame", "WowPeruVisualBonusFrame", UIParent)
panel:SetWidth(430)
panel:SetHeight(96 + #C.bonusOrder * 34)
panel:SetPoint("CENTER")
panel:SetFrameStrata("FULLSCREEN_DIALOG")
panel:EnableMouse(true)
panel:SetMovable(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
-- Fondo NEGRO Y OPACO. No vale el fondo de dialogo de Blizzard: ese es una
-- textura con su propio dibujo y transparencia, y por debajo seguian viendose
-- las alas de la tienda. Con una textura plana el color manda del todo.
Backdrop(panel, "Interface\\Buttons\\WHITE8X8", "Interface\\Tooltips\\UI-Tooltip-Border")
panel:SetBackdropColor(0.02, 0.02, 0.03, 1)
panel:SetBackdropBorderColor(0.85, 0.72, 0.30, 1)
panel:Hide()
tinsert(UISpecialFrames, "WowPeruVisualBonusFrame")

local pTitulo = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
pTitulo:SetPoint("TOP", 0, -14)

local pAviso = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
pAviso:SetPoint("TOP", pTitulo, "BOTTOM", 0, -4)
pAviso:SetText("Elige el bonus. Queda fijado a estas alas y |cffff8080no se puede cambiar|r.")

local pCerrar = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
pCerrar:SetPoint("TOPRIGHT", -4, -4)

local filas = {}
for i, clave in ipairs(C.bonusOrder) do
    local b = C.bonus[clave]
    local fila = CreateFrame("Button", nil, panel)
    fila:SetWidth(400)
    fila:SetHeight(30)
    fila:SetPoint("TOPLEFT", 14, -(56 + (i - 1) * 34))
    Backdrop(fila, "Interface\\Buttons\\WHITE8X8", "Interface\\Tooltips\\UI-Tooltip-Border")
    fila:SetBackdropColor(0.07, 0.07, 0.09, 1)
    fila:SetBackdropBorderColor(0.35, 0.35, 0.40, 1)

    local nombre = fila:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nombre:SetPoint("LEFT", 10, 0)
    nombre:SetText(b.name)

    local desc = fila:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    desc:SetPoint("LEFT", nombre, "RIGHT", 8, 0)
    desc:SetText(b.desc)

    local precio = fila:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    precio:SetPoint("RIGHT", -10, 0)
    precio:SetTextColor(1, 0.82, 0)
    precio:SetText(string.format("%d %s", b.price, C.currency.name))

    fila.clave, fila.precio, fila.marcoPrecio = clave, b.price, precio
    fila:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1, 0.82, 0, 1)
    end)
    fila:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    end)
    fila:SetScript("OnClick", function(self)
        if state.tokens < self.precio then return end   -- sin saldo no se compra
        Talk(string.format("BUY:%d:%s", panel.visual or 0, self.clave))
        panel:Hide()
    end)
    filas[i] = fila
end

local function AbrirPanelBonus(id)
    local entry = C.byId[id]
    if not entry then return end
    panel.visual = id
    pTitulo:SetText(entry.name)
    for _, fila in ipairs(filas) do
        -- Lo que no puedes pagar se ve apagado y no responde al clic.
        if state.tokens < fila.precio then
            fila:Disable()
            fila.marcoPrecio:SetTextColor(0.6, 0.3, 0.3)
            fila:SetAlpha(0.5)
        else
            fila:Enable()
            fila.marcoPrecio:SetTextColor(1, 0.82, 0)
            fila:SetAlpha(1)
        end
    end
    panel:Show()
end

action:SetScript("OnClick", function()
    local id = state.selected
    if not id then return end
    if state.active == id then
        Talk("OFF")
    elseif state.owned[id] then
        Talk("USE:" .. id)
    elseif state.caducada[id] then
        return                      -- ya no esta en venta
    else
        AbrirPanelBonus(id)
    end
end)

--------------------------------------------------------------------------
-- Pintado
--------------------------------------------------------------------------

function ProjectJaina_VisualShop_Refresh()
    local pages = C.PageCount()
    if state.page > pages then state.page = pages end

    pageLabel:SetText(string.format("Pagina %d / %d", state.page, pages))
    tokenLabel:SetText(string.format("%s: |cffffd200%d|r", C.currency.name, state.tokens))

    local first = (state.page - 1) * C.perPage

    for i = 1, C.perPage do
        local card  = cards[i]
        local entry = C.items[first + i]
        card.entry  = entry

        if not entry then
            card:Hide()
        else
            card:Show()
            card.name:SetText(entry.name)
            card.cat:SetText(entry.cat)

            -- Si el icono trae barras es una ruta completa del cliente (por
            -- ejemplo un icono de hechizo de Blizzard); si no, es uno de los
            -- nuestros, renderizado del modelo.
            if not entry.icon then
                card.icon:SetTexture(ICON_FALLBACK)
            elseif string.find(entry.icon, "\\", 1, true) then
                card.icon:SetTexture(entry.icon)
            else
                card.icon:SetTexture(ICON_PATH .. entry.icon .. ".blp")
            end

            -- Al cambiar de pagina la tarjeta reestrena ala: hay que reiniciar
            -- la reproduccion y encuadrar la primera casilla, o se quedaria
            -- ensenando el recorte del ala anterior.
            card.t, card.frame = 0, nil
            if entry.frames and entry.frames > 1 then
                card.icon:SetTexCoord(Casilla(0))
            else
                card.icon:SetTexCoord(0, 1, 0, 1)
            end

            -- Los que aun no tienes salen apagados, como en cualquier tienda
            -- de cosmeticos: se ve que existen pero se distinguen de los tuyos.
            -- El precio ya no depende del ala sino del BONUS que elijas, asi
            -- que en las que no tienes se ensena desde cuanto sale. En las
            -- compradas se ensena el bonus que llevan pegado.
            local mio = state.owned[entry.id]
            -- En las tuyas el precio sobra y lo que importa es el tiempo, asi
            -- que la cuenta atras va en su hueco.
            local q = mio and Queda(entry.id)
            local cola = q and ("  |cffffd200" .. q .. "|r") or ""
            if state.active == entry.id then
                card.icon:SetVertexColor(1, 1, 1)
                card.cost:SetText("|cff40ff40En uso|r" .. cola)
                card.stage:SetVertexColor(0.06, 0.10, 0.06, 1)
            elseif mio then
                card.icon:SetVertexColor(1, 1, 1)
                card.cost:SetText("|cff40ff40Comprado|r" .. cola)
                card.stage:SetVertexColor(0.05, 0.05, 0.07, 1)
            elseif state.caducada[entry.id] then
                -- La tuvo y se le paso. No vuelve a estar en venta, asi que en
                -- el hueco del precio no va un precio.
                card.icon:SetVertexColor(0.35, 0.35, 0.38)
                card.cost:SetText("|cff909090Proximamente|r")
                card.stage:SetVertexColor(0.05, 0.05, 0.07, 1)
            else
                card.icon:SetVertexColor(0.45, 0.45, 0.50)
                card.cost:SetText(string.format("desde %d %s", PRECIO_MINIMO, C.currency.name))
                card.stage:SetVertexColor(0.05, 0.05, 0.07, 1)
            end

            -- El bonus se pone en el subtitulo, donde antes iba la categoria:
            -- una vez comprada, saber que ventaja lleva importa mas que saber
            -- de que familia es. Y su explicacion va abajo del todo.
            local b = mio and mio ~= "" and C.bonus[mio]
            if b then
                card.cat:SetText("|cffffd200" .. b.name .. "|r")
                card.bono:SetText("|cff9fd8ff" .. b.desc .. "|r")
            else
                card.cat:SetText(entry.cat)
                card.bono:SetText("")
            end

            if state.selected == entry.id then
                card:SetBackdropBorderColor(1, 0.82, 0, 1)
            else
                card:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
            end
        end
    end

    -- 3.3.5a no tiene SetEnabled, hay que usar Enable/Disable.
    if state.page > 1 then prev:Enable() else prev:Disable() end
    if state.page < pages then next_:Enable() else next_:Disable() end

    local id = state.selected
    if not id then
        action:SetText("Elige un visual")
        action:Disable()
    else
        action:Enable()
        if state.active == id then
            action:SetText("Quitar")
        elseif state.owned[id] then
            action:SetText("Equipar")
        elseif state.caducada[id] then
            action:SetText("Proximamente")
            action:Disable()
        else
            action:SetText("Comprar y elegir bonus")
        end
    end
end

--------------------------------------------------------------------------
-- Mensajes del servidor
--------------------------------------------------------------------------

-- El servidor manda lo comprado como "id=bonus", porque cada ala guarda el
-- bonus con el que se compro. Un ala sin bonus (compra antigua) llega con la
-- clave vacia y se trata como comprada pero sin ventaja.
local function ApplyOwnedChunks()
    state.owned = {}
    for _, body in ipairs(state.chunks) do
        for id, bonus in string.gmatch(body, "(%d+)=(%a*)") do
            state.owned[tonumber(id)] = bonus
        end
    end
end

-- El servidor manda aparte, en EXP, los segundos que le quedan a cada una. Se
-- pasan al reloj local para que la cuenta atras siga viva sin volver a pedirla.
local function ApplyExpChunks()
    state.expira = {}
    local ahora = GetTime()
    for _, body in ipairs(state.expChunks) do
        for id, seg in string.gmatch(body, "(%d+)=(%d+)") do
            state.expira[tonumber(id)] = ahora + tonumber(seg)
        end
    end
end

-- Las que tuvo y ya caducaron. Llegan solo como id: no hay nada que contar.
local function ApplyFinChunks()
    state.caducada = {}
    for _, body in ipairs(state.finChunks) do
        for id in string.gmatch(body, "(%d+)") do
            state.caducada[tonumber(id)] = true
        end
    end
end

local ROUTES = {
    TOK = function(rest)
        state.tokens = tonumber(rest) or 0
    end,
    ACT = function(rest)
        state.active = tonumber(rest) or 0
    end,
    OWN = function(rest)
        local part, total, body = string.match(rest, "^(%d+)/(%d+):(.*)$")
        if not part then return end
        part, total = tonumber(part), tonumber(total)
        if part == 1 then state.chunks = {} end
        state.chunks[part] = body
        if part == total then ApplyOwnedChunks() end
    end,
    EXP = function(rest)
        local part, total, body = string.match(rest, "^(%d+)/(%d+):(.*)$")
        if not part then return end
        part, total = tonumber(part), tonumber(total)
        if part == 1 then state.expChunks = {} end
        state.expChunks[part] = body
        if part == total then ApplyExpChunks() end
    end,
    FIN = function(rest)
        local part, total, body = string.match(rest, "^(%d+)/(%d+):(.*)$")
        if not part then return end
        part, total = tonumber(part), tonumber(total)
        if part == 1 then state.finChunks = {} end
        state.finChunks[part] = body
        if part == total then ApplyFinChunks() end
    end,
    MSG = function(rest)
        local kind, text = string.match(rest, "^(%a+):(.*)$")
        local color = (kind == "ok") and "|cff40ff40" or "|cffff5555"
        DEFAULT_CHAT_FRAME:AddMessage(color .. "[Visuales]|r " .. (text or ""))
    end,
    -- Estreno: el servidor lo manda al COMPRAR unas alas, nunca al equipar unas
    -- que ya tenias. Se quita todo de en medio (tienda, panel de bonus y el
    -- consejo que estuviera abierto) para que el destello y las alas se vean.
    FST = function()
        panel:Hide()
        shop:Hide()
        GameTooltip:Hide()
    end,
}

-- Las formas de druida las lleva el SERVIDOR, enganchado a los eventos de aura
-- aplicada y quitada. El cliente no tiene que vigilar nada.
local listener = CreateFrame("Frame")
listener:RegisterEvent("CHAT_MSG_ADDON")
listener:RegisterEvent("PLAYER_ENTERING_WORLD")
listener:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        if RegisterAddonMessagePrefix then
            RegisterAddonMessagePrefix(PREFIX)
            RegisterAddonMessagePrefix(ALT_PREFIX)
        end
        Talk("SYNC")
        return
    end

    local prefix, message = ...
    if prefix ~= PREFIX and prefix ~= ALT_PREFIX then return end

    local verb, rest = string.match(message, "^(%u+):(.*)$")
    local route = verb and ROUTES[verb]
    if route then
        route(rest)
        if shop:IsShown() then ProjectJaina_VisualShop_Refresh() end
    end
end)

--------------------------------------------------------------------------
-- Abrir y cerrar
--
-- Sin comandos de chat: la tienda se abre con el boton del minimapa. No hacen
-- falta tres barras distintas para hacer lo mismo que un clic.
--------------------------------------------------------------------------

local function Toggle()
    if shop:IsShown() then
        shop:Hide()
    else
        Talk("SYNC")
        ProjectJaina_VisualShop_Refresh()
        shop:Show()
    end
end

--------------------------------------------------------------------------
-- Boton del minimapa
--------------------------------------------------------------------------

local DEFAULT_VISUALSHOP_ANGLE = 115
local VISUALSHOP_RADIUS = 80

local function UpdateVisualShopBtnPosition(button, angle)
    local rad = math.rad(angle)
    local x = math.cos(rad) * VISUALSHOP_RADIUS
    local y = math.sin(rad) * VISUALSHOP_RADIUS
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local mini = CreateFrame("Button", "ProjectJaina_VisualShopMinimapButton", Minimap)
mini:SetWidth(31)
mini:SetHeight(31)
mini:SetFrameStrata("MEDIUM")
mini:SetFrameLevel(8)
mini:EnableMouse(true)
mini:SetMovable(true)
mini:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mini:RegisterForDrag("LeftButton", "RightButton")

local icon = mini:CreateTexture(nil, "BACKGROUND")
icon:SetWidth(20)
icon:SetHeight(20)
icon:SetPoint("CENTER", 0, 1)
icon:SetTexture("Interface\\Icons\\Spell_Holy_AuraOfLight")
icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

local border = mini:CreateTexture(nil, "OVERLAY")
border:SetWidth(53)
border:SetHeight(53)
border:SetPoint("TOPLEFT", 0, 0)
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

local wasDragged = false
local dragStartX, dragStartY = 0, 0
local DRAG_THRESHOLD_SQ = 16 -- 4 píxeles de tolerancia física para diferenciar clic de arrastre

local function OnDragUpdate(self)
    local curX, curY = GetCursorPosition()
    if not wasDragged then
        local dx = curX - dragStartX
        local dy = curY - dragStartY
        if (dx * dx + dy * dy) < DRAG_THRESHOLD_SQ then
            return
        end
        wasDragged = true
    end

    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = curX / scale, curY / scale
    local angle = math.deg(math.atan2(cy - my, cx - mx))
    if angle < 0 then angle = angle + 360 end

    ProjectJaina_VisualShopDB = ProjectJaina_VisualShopDB or {}
    ProjectJaina_VisualShopDB.minimapAngle = angle

    UpdateVisualShopBtnPosition(self, angle)
end

mini:SetScript("OnDragStart", function(self)
    wasDragged = false
    dragStartX, dragStartY = GetCursorPosition()
    self:LockHighlight()
    self:SetScript("OnUpdate", OnDragUpdate)
end)

mini:SetScript("OnDragStop", function(self)
    self:UnlockHighlight()
    self:SetScript("OnUpdate", nil)
end)

mini:SetScript("OnClick", function(self, button)
    if wasDragged then
        wasDragged = false
        return
    end
    Toggle()
end)

mini:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Tienda de Visuales")
    GameTooltip:AddLine("Clic para abrir. Arrastra para mover el boton.", 1, 1, 1)
    GameTooltip:Show()
end)
mini:SetScript("OnLeave", function() GameTooltip:Hide() end)

local vsInitFrame = CreateFrame("Frame")
vsInitFrame:RegisterEvent("ADDON_LOADED")
vsInitFrame:RegisterEvent("PLAYER_LOGIN")
vsInitFrame:SetScript("OnEvent", function(self, event, addon)
    if (event == "ADDON_LOADED" and (addon == "ProjectJaina_VisualShop" or addon == "ProjectJaina_VisualShop")) or event == "PLAYER_LOGIN" then
        ProjectJaina_VisualShop_DB = ProjectJaina_VisualShop_DB or ProjectJaina_VisualShopDB or {}
        ProjectJaina_VisualShopDB = ProjectJaina_VisualShop_DB
        local savedAngle = (ProjectJaina_VisualShop_DB and ProjectJaina_VisualShop_DB.minimapAngle) or DEFAULT_VISUALSHOP_ANGLE
        UpdateVisualShopBtnPosition(mini, savedAngle)
    end
end)

UpdateVisualShopBtnPosition(mini, DEFAULT_VISUALSHOP_ANGLE)

-- Comandos Slash
SLASH_WOWPERU_VISUAL1 = "/visualshop"
SLASH_WOWPERU_VISUAL2 = "/tienda"
SLASH_WOWPERU_VISUAL3 = "/alas"
SLASH_WOWPERU_VISUAL4 = "/wpvs"
SlashCmdList["WOWPERU_VISUAL"] = function()
    Toggle()
end

DEFAULT_CHAT_FRAME:AddMessage(
    "|cff40ff40[Tienda de Visuales]|r cargada. Usa /tienda, /visualshop o el botón del minimapa.")
