-- Item links in chat.
--
-- Ctrl+Alt+left click on an item drops "[Name#id]" into the chat input. The id
-- is a handle to a frozen snapshot the server took of that item
-- (OTSERV data/item_share/item_share.lua). The message carries nothing else:
-- chat text is refused above 255 bytes server-side (protocolgame.cpp:1058),
-- which is far less than a rolled item's tooltip.
--
-- Every client that receives such a line draws the name in its rarity colour
-- and asks for the snapshot by id when its own player hovers it. The id is
-- stripped before drawing, so only "[Name]" is ever on screen -- but it stays
-- in the raw text, which means copying a line and pasting it re-posts a
-- working link.

-- Must match ItemShare.OPCODE on the server.
local SHARE_OPCODE = 69

-- The name cannot contain "[", "]" or "#" -- the server strips all three
-- before it mints the token (sanitizeName), so this can never run past the end
-- of one link into the next.
local TOKEN_PATTERN = '%[([^%[%]#]+)#(%x+)%]'

-- The rarity is the FIRST character of the id rather than a field of its own.
-- It has to be readable by clients that never saw the share happen, and this
-- way it costs no extra round trip and no extra bytes in a 255-byte budget.
local function rarityOfId(id)
    return tonumber(id:sub(1, 1)) or 0
end

local nextRequestId = 0
local pendingShare = {}
local pendingFetch = {}

-- id -> payload. A snapshot never changes once minted, so a link hovered twice
-- costs one request, not two.
local snapshotCache = {}
local hoveredId = nil

local function rarityColor(id)
    local tooltip = modules.game_itemtooltip
    if not tooltip then
        return nil
    end
    return tooltip.getRarityColor(rarityOfId(id))
end

-- Braces delimit the colour markup, so anything the player typed that looks
-- like one would split the line in the wrong place.
local function plainChunk(chunk, color)
    chunk = chunk:gsub('[{}]', '')
    if chunk == '' then
        return ''
    end
    return string.format('{%s, %s}', chunk, color)
end

-- For anywhere that draws a chat line as plain text with no hover behind it --
-- the floating message over a character's head being the one that matters.
-- There the id cannot do anything except sit there, so "[The Avenger +6#33]"
-- becomes "[The Avenger +6]". The chat window keeps the full token; that is
-- where the hover lives.
function stripLinkIds(text)
    if not text or not text:find('#', 1, true) then
        return text
    end

    return (text:gsub(TOKEN_PATTERN, '[%1]'))
end

-- Returns nil when the line holds no link, so callers keep their existing
-- plain-text path for the overwhelming majority of messages.
--
-- hoverable is what separates the two surfaces. Chat wraps each link in a
-- text-event so the hover handler can fetch the item's snapshot; a screen label
-- has no such handler, so it takes the colour and skips the wrapper rather than
-- registering words nothing listens to.
local function buildMarkup(text, baseColor, hoverable)
    if not text or not text:find('#', 1, true) then
        return nil
    end

    baseColor = baseColor or '#FFFFFF'

    local parts = {}
    local links = {}
    local pos = 1
    local found = false

    while true do
        local startPos, endPos, name, id = text:find(TOKEN_PATTERN, pos)
        if not startPos then
            break
        end
        found = true

        if startPos > pos then
            parts[#parts + 1] = plainChunk(text:sub(pos, startPos - 1), baseColor)
        end

        local display = '[' .. name .. ']'
        local color = rarityColor(id) or baseColor

        if hoverable then
            -- The 0x01 prefix is the "no underline" marker the text-event
            -- parser strips before it stores the word (uiwidgettext.cpp:430),
            -- so the hover handler still receives the clean display text.
            parts[#parts + 1] = string.format('{[text-event]%s%s[/text-event], %s}',
                string.char(1), display, color)
        else
            parts[#parts + 1] = string.format('{%s, %s}', display, color)
        end

        -- Keyed by what is drawn, because that is all the hover event hands
        -- back. Two links to items with the identical name in ONE line will
        -- therefore both open the second one's tooltip.
        links[display] = id

        pos = endPos + 1
    end

    if not found then
        return nil
    end

    if pos <= #text then
        parts[#parts + 1] = plainChunk(text:sub(pos), baseColor)
    end

    return { markup = table.concat(parts), links = links }
end

-- Chat: coloured and hoverable.
function buildChatMarkup(text, baseColor)
    return buildMarkup(text, baseColor, true)
end

-- Screen labels: the rarity colour, no hover. Use this instead of stripLinkIds
-- wherever the surface can render coloured markup -- it does the same stripping
-- as part of building the display text, and keeps the colour that would
-- otherwise be thrown away with the id.
function buildScreenMarkup(text, baseColor)
    return buildMarkup(text, baseColor, false)
end

local function showSnapshot(entry)
    local tooltip = modules.game_itemtooltip
    if tooltip then
        tooltip.showSharedTooltip(entry.payload, entry.clientId, entry.count)
    end
end

local function requestSnapshot(id)
    local cached = snapshotCache[id]
    if cached then
        showSnapshot(cached)
        return
    end

    local protocolGame = g_game.getProtocolGame()
    if not protocolGame then
        return
    end

    nextRequestId = nextRequestId + 1
    pendingFetch[nextRequestId] = id
    protocolGame:sendExtendedOpcode(SHARE_OPCODE, string.format('FETCH|%d|%s', nextRequestId, id))
end

-- Wired by the console onto any label that carries links (see addTabText).
function onChatLinkHover(label, text, hovered)
    local links = label and label.shareLinks
    if not links then
        return
    end

    local id = links[text]
    if not id then
        return
    end

    if not hovered then
        if hoveredId == id then
            hoveredId = nil
            local tooltip = modules.game_itemtooltip
            if tooltip then
                tooltip.hideSharedTooltip()
            end
        end
        return
    end

    hoveredId = id
    requestSnapshot(id)
end

-- Called from UIItem:onMouseRelease. Returns whether the click was consumed,
-- so a slot that holds nothing shareable still falls through to look/use.
-- Every rejection below says why. They used to return false in silence, which
-- made a refused Ctrl+Alt+click indistinguishable from the feature being
-- broken: no link appeared and nothing explained it, so there was no way to
-- tell an unlinkable item from a module that never loaded.
local function refuse(reason)
    local textmessage = modules.game_textmessage
    if textmessage and textmessage.displayFailureMessage then
        textmessage.displayFailureMessage(reason)
    end
    return false
end

function shareItem(widget)
    if not g_game.isOnline() or not widget then
        return false
    end

    local item = widget:getItem()
    if not item then
        return false
    end

    local tooltip = modules.game_itemtooltip
    if not tooltip then
        return refuse('Item links need the item tooltip module.')
    end

    -- Same addressing the hover tooltip uses: an item is named by its inventory
    -- slot or its container slot, never by map coordinates (describeTarget in
    -- itemtooltip.lua). Anything on the ground, in a trade window or in a shop
    -- answers nil here and cannot be linked.
    local source, a, b = tooltip.describeItemTarget(item)
    if not source then
        return refuse('You can only link items in your inventory or an open container.')
    end

    local protocolGame = g_game.getProtocolGame()
    if not protocolGame then
        return false
    end

    nextRequestId = nextRequestId + 1
    pendingShare[nextRequestId] = true
    protocolGame:sendExtendedOpcode(SHARE_OPCODE,
        string.format('SHARE|%d|%s|%d|%d', nextRequestId, source, a, b))
    return true
end

local function onShared(reqId, rest)
    if not pendingShare[reqId] then
        return
    end
    pendingShare[reqId] = nil

    -- Empty tail: the server answered but could not resolve or describe the
    -- item. Said out loud rather than dropped, because from the player's side
    -- it is identical to the click doing nothing at all.
    if rest == '' then
        refuse('The server could not describe that item.')
        return
    end

    local id, name = rest:match('^(%x+)|(.+)$')
    if not id then
        refuse('The item link the server sent could not be read.')
        return
    end

    local console = modules.game_console
    if not console or not console.insertTextEditText then
        refuse('Item links need the chat console module.')
        return
    end

    console.insertTextEditText(string.format('[%s#%s] ', name, id))
end

local function onFetched(reqId, rest)
    local id = pendingFetch[reqId]
    if not id then
        return
    end
    pendingFetch[reqId] = nil

    local clientId, count, payload = rest:match('^(%d+)|(%d+)|(.*)$')
    if not clientId or payload == '' then
        -- Expired or unknown link. Leave the cursor alone rather than popping
        -- an empty frame under it.
        return
    end

    local entry = {
        payload = payload,
        clientId = tonumber(clientId),
        count = tonumber(count),
    }
    snapshotCache[id] = entry

    -- The pointer may have moved on while the reply was in flight.
    if hoveredId == id then
        showSnapshot(entry)
    end
end

local function onShareData(_protocol, opcode, buffer)
    if opcode ~= SHARE_OPCODE then
        return
    end

    local reqId, rest = buffer:match('^SHARED|(%d+)|(.*)$')
    if reqId then
        onShared(tonumber(reqId), rest)
        return
    end

    reqId, rest = buffer:match('^FETCHED|(%d+)|(.*)$')
    if reqId then
        onFetched(tonumber(reqId), rest)
    end
end

local function onGameEnd()
    pendingShare = {}
    pendingFetch = {}
    snapshotCache = {}
    hoveredId = nil
end

function init()
    ProtocolGame.registerExtendedOpcode(SHARE_OPCODE, onShareData)
    connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
    ProtocolGame.unregisterExtendedOpcode(SHARE_OPCODE)
    disconnect(g_game, { onGameEnd = onGameEnd })
    onGameEnd()
end
