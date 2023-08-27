#!/bin/sh
# Displays a dependency tree for installed Homebrew formulas

brew leaves --installed-on-request \
    | xargs brew deps --installed --skip-recommended --include-requirements --include-build --include-optional --annotate --tree \
    | sed -E "s/^[[:alnum:]\/_-]+$/$(tput setaf 4)&$(tput sgr0)/" \
    | sed -E "s/^.* \[build\]$/$(tput setaf 2)&$(tput sgr0)/" \
    | sed -E "s/^.* \[optional\]$/$(tput setaf 3)&$(tput sgr0)/"
