local active = false   -- selection is open (until a character finishes loading)
local cam
local previewPed
local previewToken = 0 -- bumped on every preview so slow loads can't show a stale character
local entries = {}     -- menu index -> { char = row } or { create = true }
local dobRange

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Minutes this machine's clock is ahead of UTC. The date picker sends local
-- midnight as a timestamp, so the server needs this to get the right day.
local function utcOffsetMinutes()
    local ok, y1, mo1, d1, h1, mi1 = pcall(GetLocalTime)
    local ok2, y2, mo2, d2, h2, mi2 = pcall(GetUtcTime)
    if not (ok and ok2 and y1 and y2) then return 0 end

    local offset = (h1 - h2) * 60 + (mi1 - mi2)
    local localDay, utcDay = y1 * 10000 + mo1 * 100 + d1, y2 * 10000 + mo2 * 100 + d2
    if localDay > utcDay then offset = offset + 1440 elseif localDay < utcDay then offset = offset - 1440 end
    return offset
end

local function formatMoney(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local formatted = s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
    return formatted
end

local function describe(char)
    local jobs = exports.rps_core:GetJobs()
    local job = jobs[char.job]
    local grade = job and job.grades[char.job_grade]
    local jobText = job and (grade and ('%s - %s'):format(job.label, grade.label) or job.label) or char.job

    local ok, accounts = pcall(json.decode, char.accounts or '')
    if not ok or type(accounts) ~= 'table' then accounts = {} end

    return ('%s · Born %s · Cash $%s · Bank $%s'):format(
        jobText, char.dob, formatMoney(accounts.cash), formatMoney(accounts.bank))
end

---------------------------------------------------------------------------
-- Scene
---------------------------------------------------------------------------
local function deletePreview()
    if previewPed and DoesEntityExist(previewPed) then DeleteEntity(previewPed) end
    previewPed = nil
end

local function startScene()
    local c = Config.PedCoords
    local h = math.rad(c.w)
    local d = Config.Camera.distance
    -- in front of the ped: GTA headings point along (-sin, cos)
    local camPos = vec3(c.x - math.sin(h) * d, c.y + math.cos(h) * d, c.z + Config.Camera.height)

    -- the player's own ped waits, hidden, by the camera so the area streams in
    local ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, camPos.x, camPos.y, camPos.z, false, false, false)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityInvincible(ped, true)
    RequestCollisionAtCoord(c.x, c.y, c.z)

    if not cam then
        cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', camPos.x, camPos.y, camPos.z,
            0.0, 0.0, 0.0, Config.Camera.fov, false, 0)
    end
    PointCamAtCoord(cam, c.x, c.y, c.z)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)
    DisplayRadar(false)

    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()

    local timeout = GetGameTimer() + 5000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do Wait(0) end
end

local function stopScene()
    previewToken = previewToken + 1
    deletePreview()
    if cam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(cam, false)
        cam = nil
    end
end

-- Saved illenium-appearance look, fetched once per character and cached on the row
local function getAppearance(char)
    if char.appearance == nil then
        char.appearance = GetResourceState('illenium-appearance') == 'started'
            and lib.callback.await('rps_multicharacter:getAppearance', false, char.id) or false
    end
    return char.appearance
end

local function showPreview(char)
    previewToken = previewToken + 1
    local token = previewToken
    if not char then return deletePreview() end

    local appearance = getAppearance(char)
    if token ~= previewToken or not active then return end

    local model = appearance and appearance.model or Config.DefaultModel[char.sex] or Config.DefaultModel.m
    if type(model) == 'string' then model = joaat(model) end
    if not pcall(lib.requestModel, model) then
        appearance = nil
        model = joaat(Config.DefaultModel[char.sex] or Config.DefaultModel.m)
        lib.requestModel(model)
    end
    if token ~= previewToken or not active then return end

    deletePreview()
    local c = Config.PedCoords
    local ped = CreatePed(4, model, c.x, c.y, c.z - 1.0, c.w, false, true)
    SetModelAsNoLongerNeeded(model)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)

    if not (appearance and pcall(function() exports['illenium-appearance']:setPedAppearance(ped, appearance) end)) then
        SetPedDefaultComponentVariation(ped)
    end
    if Config.IdleScenario then TaskStartScenarioInPlace(ped, Config.IdleScenario, 0, true) end

    previewPed = ped
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
local refresh

local function play(id)
    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(0) end
    stopScene()
    -- rps_core spawns the character and fades back in (or illenium-appearance does)
    TriggerEvent('rps_core:client:selectCharacter', id)
end

local function createCharacter()
    local input = lib.inputDialog('New character', {
        { type = 'input', label = 'First name', required = true, min = 2, max = 20 },
        { type = 'input', label = 'Last name', required = true, min = 2, max = 20 },
        { type = 'date', label = 'Date of birth', icon = 'calendar', required = true, format = 'DD/MM/YYYY',
            min = dobRange and dobRange.min, max = dobRange and dobRange.max },
        { type = 'select', label = 'Sex', required = true, options = {
            { value = 'm', label = 'Male' },
            { value = 'f', label = 'Female' },
        } },
    }, { allowCancel = true })

    if input then
        local ok, result = lib.callback.await('rps_core:createCharacter', false, {
            firstname = input[1], lastname = input[2], dob = input[3], tz = utcOffsetMinutes(), sex = input[4],
        })
        -- straight into the new character; illenium-appearance opens its editor
        if ok then return play(result) end
        lib.notify({ description = type(result) == 'string' and result or 'Could not create character', type = 'error' })
    end

    refresh()
end

local function deleteCharacter(char)
    local confirm = lib.alertDialog({
        header = 'Delete character',
        content = ('Permanently delete **%s %s**? This cannot be undone.'):format(char.firstname, char.lastname),
        centered = true,
        cancel = true,
    })

    if confirm == 'confirm' and lib.callback.await('rps_core:deleteCharacter', false, char.id) then
        lib.notify({ description = 'Character deleted', type = 'success' })
    end

    refresh()
end

local function choose(entry, scrollIndex)
    if not entry then return end
    if entry.create then return createCharacter() end
    if scrollIndex == 2 then return deleteCharacter(entry.char) end
    play(entry.char.id)
end

---------------------------------------------------------------------------
-- Menu
---------------------------------------------------------------------------
local function buildMenu(chars, max)
    entries = {}
    local options = {}

    for _, char in ipairs(chars) do
        entries[#entries + 1] = { char = char }
        options[#options + 1] = {
            label = ('%s %s'):format(char.firstname, char.lastname),
            description = describe(char),
            icon = 'user',
            values = { 'Play', 'Delete' },
        }
    end

    for _ = #chars + 1, max do
        entries[#entries + 1] = { create = true }
        options[#options + 1] = { label = 'Empty slot', description = 'Create a new character', icon = 'plus' }
    end

    lib.registerMenu({
        id = 'rps_multicharacter',
        title = ('Characters (%d/%d)'):format(#chars, max),
        position = 'top-right',
        canClose = false,
        options = options,
        onSelected = function(selected)
            local entry = entries[selected]
            CreateThread(function() showPreview(entry and entry.char) end)
        end,
    }, function(selected, scrollIndex)
        local entry = entries[selected]
        CreateThread(function() choose(entry, scrollIndex) end)
    end)
end

function refresh()
    local chars, max, range = lib.callback.await('rps_core:getCharacters', false)
    if not chars then
        lib.notify({ description = 'Could not load your characters. Reconnect to try again.', type = 'error' })
        return false
    end

    dobRange = range
    buildMenu(chars, max)
    lib.showMenu('rps_multicharacter')
    CreateThread(function() showPreview(entries[1] and entries[1].char) end)
    return true
end

local function open()
    if active or exports.rps_core:IsLoaded() then return end
    active = true

    if not IsScreenFadedOut() then
        DoScreenFadeOut(0)
    end

    startScene()
    refresh()
    DoScreenFadeIn(500)
end

---------------------------------------------------------------------------
-- rps_core events
---------------------------------------------------------------------------
AddEventHandler('rps_core:client:openSelection', open)

AddEventHandler('rps_core:client:playerLoaded', function()
    active = false
end)

AddEventHandler('rps_core:client:selectFailed', function()
    lib.notify({ description = 'Could not load that character', type = 'error' })
    startScene()
    refresh()
    DoScreenFadeIn(500)
end)

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(100) end
    open()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    lib.hideMenu(false)
    stopScene()
end)
