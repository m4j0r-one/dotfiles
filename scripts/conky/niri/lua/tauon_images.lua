require("cairo")
require("cairo_imlib2_helper")

local function file_exists(path)
    local file = io.open(path, "rb")

    if file then
        file:close()
        return true
    end

    return false
end

local function read_current_path(path_file, fallback)
    local file = io.open(path_file, "r")

    if file then
        local path = file:read("*l") or ""
        file:close()

        path = path:gsub("^%s+", ""):gsub("%s+$", "")

        if path ~= "" and file_exists(path) then
            return path
        end
    end

    return fallback
end

local function tauon_is_active()
    local file = io.open(
        "/tmp/tauon_radio_status.conky",
        "r"
    )

    if not file then
        return false
    end

    local content = file:read("*a") or ""
    file:close()

    return not content:lower():find(
        "radio inactive",
        1,
        true
    )
end

function conky_tauon_images()
    if not tauon_is_active() then
        return
    end

    local surface = conky_surface()

    if not surface then
        return
    end

    local cover = read_current_path(
        "/tmp/conky_niri_tauon_cover.path",
        "/tmp/tauon_radio_cover.jpg"
    )

    if not file_exists(cover) then
        return
    end

    local cr = cairo_create(surface)

    -- Gleiche Cover-Größe und Position wie bei Spotify.
    cairo_place_image(
        cover,
        cr,
        10, 68,
        62, 62,
        1.0
    )

    cairo_destroy(cr)
end
