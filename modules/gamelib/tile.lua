function Tile:isTile()
    return true
end

function Tile:isCreature()
    return false
end

function Tile:isLocalPlayer()
    return false
end

function Tile:isNpc()
    return false
end

function Tile:isMonster()
    return false
end

function Tile:isPlayer()
    return false
end

function Tile:isEffect()
    return false
end

function Tile:isMissile()
    return false
end

function Tile:isItem()
    return false
end

function Tile:isContainer()
    return false
end

-- Tile::getTopUseThing reads the ForceUse flag in C++, so it never sees the Lua-only
-- ids in LuaForceUseItemIds (gamelib/thing.lua); check those first, then defer to it.
Tile.cppGetTopUseThing = Tile.cppGetTopUseThing or Tile.getTopUseThing

function Tile:getTopUseThing()
  for _, item in ipairs(self:getItems()) do
    if LuaForceUseItemIds[item:getId()] then
      return item
    end
  end
  return self:cppGetTopUseThing()
end
