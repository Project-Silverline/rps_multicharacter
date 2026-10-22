Config = {}

-- Where the selected character stands while you browse (check this in-game).
-- Same format as GetEntityCoords + heading: z is about 1m above the ground.
Config.PedCoords = vec4(-269.4, -955.3, 31.2, 205.0)

-- Camera, relative to the ped: distance in front of it, height, and field of view
Config.Camera = {
    distance = 3.0,
    height = 0.4,
    fov = 40.0,
}

-- Model used when a character has no saved appearance (or illenium-appearance isn't running)
Config.DefaultModel = {
    m = 'mp_m_freemode_01',
    f = 'mp_f_freemode_01',
}

-- Idle animation for the preview ped; nil to stand still
Config.IdleScenario = 'WORLD_HUMAN_STAND_IMPATIENT'
