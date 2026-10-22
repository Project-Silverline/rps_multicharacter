-- Saved illenium-appearance look for one of the player's own characters,
-- used to dress the preview ped. citizenid = tostring(charId), as in the bridge.
lib.callback.register('rps_multicharacter:getAppearance', function(src, charId)
    charId = tonumber(charId)
    local license = GetPlayerIdentifierByType(src, 'license')
    if not charId or not license then return end
    if GetResourceState('illenium-appearance') ~= 'started' then return end

    local ok, skin = pcall(MySQL.scalar.await, [[
        SELECT s.skin FROM playerskins s
        JOIN characters c ON c.id = ? AND c.license = ?
        WHERE s.citizenid = ? AND s.active = 1
        LIMIT 1
    ]], { charId, license, tostring(charId) })

    if not ok or not skin then return end

    local decoded, appearance = pcall(json.decode, skin)
    return decoded and appearance or nil
end)
