#!/usr/bin/env bash

STATUS_FILE="/tmp/tauon_radio_status.conky"

[[ -r "$STATUS_FILE" ]] || exit 0

# Ohne laufenden Stream kompakt und ohne reservierten Cover-Bereich.
if grep -qi "radio inactive" "$STATUS_FILE"; then
    cat <<'EOF'
${color1}TAUON${alignr 10}${color3}OFF
${voffset 5}${color2}Radio inactive
${color1}No stream active
${voffset 22}${color6}${font conthrax:size=7:bold}PLAY${offset 18}STOP${offset 16}PREV${offset 20}NEXT${alignr 10}${color4}RADIO${font}
EOF
    exit 0
fi

# Bei aktivem Stream dieselbe Textposition wie bei Spotify verwenden.
awk '
NR == 1 {
    line = $0
    gsub(/\$\{goto 112\}/, "${offset 82}", line)
    gsub(/\$\{goto 202\}/, "${alignr 10}", line)
    print line
    next
}

NR == 2 || NR == 3 {
    line = $0
    gsub(/\$\{goto 112\}/, "${offset 82}", line)
    print line
    next
}

NR == 4 {
    line = $0
    gsub(/\$\{goto 14\}/, "", line)
    print line
    next
}

NR == 5 {
    print "${voffset 8}${offset 10}${color6}${font conthrax:size=7:bold}PLAY${offset 18}STOP${offset 16}PREV${offset 20}NEXT${alignr 10}${color4}RADIO${font}"
    next
}

{
    print
}
' "$STATUS_FILE"
