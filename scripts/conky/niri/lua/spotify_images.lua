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

local function spotify_is_active()
    local status_file = io.open(
        "/tmp/spotify_status_card.conky",
        "r"
    )

    if not status_file then
        return false
    end

    local content = status_file:read("*a") or ""
    status_file:close()

    return not content:lower():find(
        "spotify inaktiv",
        1,
        true
    )
end

function conky_spotify_images()
    if not spotify_is_active() then
        return
    end

    local surface = conky_surface()

    if not surface then
        return
    end

    local cover = read_current_path(
        "/tmp/conky_niri_spotify_cover.path",
        "/tmp/spotify_cover_niri.jpg"
    )

    if not file_exists(cover) then
        return
    end

    local cr = cairo_create(surface)

    -- Nur das Cover zeichnen. Der Karten-Blur kommt einheitlich von Niri.
    cairo_place_image(
        cover,
        cr,
        10, 68,
        62, 62,
        1.0
    )

    cairo_destroy(cr)
end
