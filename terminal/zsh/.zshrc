setopt autocd interactivecomments histignorealldups sharehistory
bindkey -e

autoload -Uz colors && colors
PROMPT='%F{green}╭─%f %F{cyan}%n%f %F{magenta}%~%f%(?.. %F{red}✗%f)\n%F{green}╰─%f %F{yellow}❯%f '
RPROMPT='%F{8}%D{%H:%M}%f'

# Corvantium uses a small, self-contained prompt and does not source the
# machine-wide autocomplete plugin paths that can be missing on some systems.
