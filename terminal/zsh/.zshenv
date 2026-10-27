export HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/corvantium/zsh_history"
export HISTSIZE=10000
export SAVEHIST=10000
[[ -d "${HISTFILE:h}" ]] || command mkdir -p "${HISTFILE:h}" 2>/dev/null
