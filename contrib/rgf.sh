#!/usr/bin/env bash
# Make fzf work with rg, allowing switching to fzf fuzzy-search mode.
#
# Based on 2023-09-26 https://github.com/junegunn/fzf/blob/76364ea767cca7ca8f6570a049fbb8d3fff751a9/ADVANCED.md#switching-between-ripgrep-mode-and-fzf-mode
# - Instead of starting fzf in the usual rg ... | fzf form, we start fzf with an
# empty input (: | fzf), then we make it start the initial Ripgrep process
# immediately via start:reload binding. This way, fzf owns the initial Ripgrep
# process so it can kill it on the next reload. Otherwise, the process will keep
# running in the background.
# - Filtering is no longer a responsibility of fzf; hence --disabled
# - {q} in the reload command evaluates to the query string on fzf prompt.
# - sleep 0.1 in the reload command is for "debouncing". This small delay will
# reduce the number of intermediate Ripgrep processes while we're typing in a
# query.

# Switch between Ripgrep launcher mode (CTRL-R) and fzf filtering mode (CTRL-Z)
rm -f "${TMP:-/tmp}"/rg-fzf-{r,f}
RG_PREFIX="rg --smart-case -L --line-number --column --no-heading --color=always "
INITIAL_QUERY="${*:-}"
: | fzf --ansi --no-sort --disabled --no-multi \
    --delimiter : \
    \
    --query "$INITIAL_QUERY" \
    --bind "start:reload($RG_PREFIX {q})+unbind(ctrl-r)" \
    --bind "change:reload:sleep 0.1; $RG_PREFIX {q} || true" \
    --bind "ctrl-z:unbind(change,ctrl-z)+change-prompt(2. fzf> )+enable-search+rebind(ctrl-r)+transform-query(echo {q} > ${TMP:-/tmp}/rg-fzf-r; cat ${TMP:-/tmp}/rg-fzf-f)" \
    --bind "ctrl-r:unbind(ctrl-r)+change-prompt(1. ripgrep> )+disable-search+reload($RG_PREFIX {q} || true)+rebind(change,ctrl-z)+transform-query(echo {q} > ${TMP:-/tmp}/rg-fzf-f; cat ${TMP:-/tmp}/rg-fzf-r)" \
    --prompt '1. ripgrep> ' \
    \
    --bind 'enter:become(echo -n {1}:{2}:{3} | pbcopy; echo {1}:{2}:{3})' \
    --bind 'ctrl-/:change-preview-window(right|hidden|)' \
    --bind 'ctrl-f:preview-page-down,ctrl-b:preview-page-up' \
    --bind 'ctrl-y:execute-silent(echo -n {4..} | pbcopy)' \
    --bind 'ctrl-v:execute(vi {1} +"call cursor({2},{3})")' \
    --bind 'ctrl-t:execute-silent(code --goto {1}:{2}:{3})' \
    --bind 'ctrl-o:execute-silent(code --goto {1}:{2}:{3})' \
    \
    --color "hl:-1:underline,hl+:-1:underline:reverse" \
    --header '^Y copy  ^V vi  ^T idea  ^O code  ^R rg  ^Z fzf  ^/ preview  ^F,^B page' \
    --preview-window 'up,60%,+{2}+3/3,~3' \
    --preview "${BAT_CMD-bat} --theme=GitHub --color=always --style=numbers --highlight-line={2} {1}" \

