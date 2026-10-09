-- Noctalia v5 port of the m4j0r Shortcuts bar button.
function update()
    noctalia.setUpdateInterval(60000)
    barWidget.setGlyph("keyboard")
    barWidget.setText("")
    barWidget.setGlyphColor("#7dcfff")
    barWidget.setTooltip("Shortcuts · Yazi · Spotify · Niri")
end

function onClick()
    noctalia.togglePanel("m4j0r/shortcuts:panel")
end
