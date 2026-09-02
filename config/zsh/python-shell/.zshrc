# BEGIN m4j0r Kitty Fastfetch
# Muss vor dem Powerlevel10k-Instant-Prompt stehen.
if [[ -o interactive ]] \
   && [[ -n "${KITTY_WINDOW_ID:-}" ]] \
   && [[ -z "${M4J0R_FASTFETCH_SHOWN:-}" ]] \
   && command -v fastfetch >/dev/null 2>&1
then
    export M4J0R_FASTFETCH_SHOWN=1
    fastfetch --config "$HOME/.config/fastfetch/kitty-compact.jsonc"
    print
fi
# END m4j0r Kitty Fastfetch

# Virtuelle Python-Umgebung aktivieren, bevor die normale
# m4j0r-ZSH-/Powerlevel10k-Konfiguration geladen wird.
if [[ -n "${M4J0R_PYTHON_VENV:-}" ]] &&
   [[ -f "$M4J0R_PYTHON_VENV/bin/activate" ]]; then

    export VIRTUAL_ENV_DISABLE_PROMPT=1
    source "$M4J0R_PYTHON_VENV/bin/activate"
    unset VIRTUAL_ENV_DISABLE_PROMPT
fi

source "$HOME/.zshrc"
