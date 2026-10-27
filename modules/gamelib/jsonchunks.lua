-- Reassembles a JSON message the server sent in parts (sendExtendedJson in the
-- server's data/lib/core/extended_json.lua). The server cannot send one string
-- over 8192 bytes, so a long list arrives as several messages, each the same
-- message carrying a slice of one list plus `part` and `parts`.
--
--   local assembled = JsonChunks.receive(OPCODE, data, 'items')
--   if assembled then ... end
--
-- Answers the whole message once its last part is in, and nil before that. A
-- message with no `part` field is not chunked and comes straight back.
JsonChunks = {}

local pending = {}

function JsonChunks.receive(channel, data, listKey)
    if type(data.part) ~= 'number' or type(data.parts) ~= 'number' then
        return data
    end

    local slice = type(data[listKey]) == 'table' and data[listKey] or {}

    -- Part 1 always starts over, so a sequence cut off by a reconnect or a
    -- newer request cannot leave stale entries in front of the next one.
    if data.part == 1 then
        pending[channel] = {}
    end

    local list = pending[channel]
    if not list then
        return nil
    end
    for _, entry in ipairs(slice) do
        list[#list + 1] = entry
    end

    if data.part < data.parts then
        return nil
    end

    pending[channel] = nil
    data[listKey] = list
    data.part = nil
    data.parts = nil
    return data
end
