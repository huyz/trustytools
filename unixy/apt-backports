#!/usr/bin/env bash
# Analyze installed packages vs available backports and print an actionable report.
# Designed for Ubuntu systems with APT/dpkg tools.
#
# Usage:
#   apt-backports [--include-not-installed] [--debug]
#
# 2026-06-09 Written by GPT 5.3-codex & Claude Sonnet 4.6


# Check for bash 4 for `readarray`, associatve arrays, etc.
[ "${BASH_VERSINFO:-0}" -ge 4 ] || { echo "${BASH_SOURCE[0]}: ERROR: bash v4+ required." >&2; exit 1; }

#### Preamble (v2025-08-22)

set -euo pipefail
shopt -s failglob
# shellcheck disable=SC2329
function trap_err { echo "$(basename "${BASH_SOURCE[0]}"): ERR signal on line $(caller)" >&2; }
trap trap_err ERR
trap exit INT  # So that ^C will stop the entire script, not just the current subprocess
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

# shellcheck disable=SC2034
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
script=${BASH_SOURCE[0]}
while [[ -L "$script" ]]; do
    script=$(readlink "$script")
done
# shellcheck disable=SC2034
SCRIPT_DIR=$(dirname "$script")

##############################################################################
#### Prerequisites

for cmd in apt-cache apt-config aptitude dpkg-query dpkg awk sort uniq sed; do
	if ! command -v "$cmd" >/dev/null 2>&1; then
		echo "$SCRIPT_NAME: missing required command: $cmd" >&2
		exit 1
	fi
done

#### Utils

DEBUG=0
debug() {
	if [[ "$DEBUG" -eq 1 ]]; then
		echo "[debug] $*" >&2
	fi
}

debug_cmd() {
	if [[ "$DEBUG" -eq 1 ]]; then
		"$@"
	fi
}

#### Usage

usage() {
	cat <<'EOF'
Usage: apt-backports [--include-not-installed] [--debug]

Reports package state with respect to *-backports repositories.

Default behavior:
  - Focus on packages that are currently installed.
  - Also report virtual package names that are satisfiable by installed providers.

Options:
  --include-not-installed   Also include packages with backports that are not installed.
  --debug                   Print step-by-step diagnostics to stderr.
  -h, --help                Show this help.
EOF
}

include_not_installed=0
while (($# > 0)); do
	case "$1" in
		--include-not-installed)
			include_not_installed=1
			shift
			;;
		--debug)
			DEBUG=1
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "$SCRIPT_NAME: unknown argument: $1" >&2
			usage >&2
			exit 2
			;;
	esac
done

##############################################################################
#### Main

debug "Options: include_not_installed=$include_not_installed debug=$DEBUG"

declare -A INSTALLED_VERSION
declare -A INSTALLED_SET
while IFS=$'\t' read -r pkg ver; do
	[[ -n "$pkg" ]] || continue
	INSTALLED_SET["$pkg"]=1
	INSTALLED_VERSION["$pkg"]="$ver"
done < <(dpkg-query -W -f='${binary:Package}\t${Version}\n' 2>/dev/null || true)

declare -a INSTALLED_PKGS
mapfile -t INSTALLED_PKGS < <(printf '%s\n' "${!INSTALLED_SET[@]}" | sort)

debug "Installed package count: ${#INSTALLED_PKGS[@]}"
if [[ "$DEBUG" -eq 1 && ${#INSTALLED_PKGS[@]} -gt 0 ]]; then
	debug "Installed package sample (first 10):"
	printf '%s\n' "${INSTALLED_PKGS[@]:0:10}" | sed 's/^/[debug]   /' >&2
    printf '[debug]   …\n' >&2
fi

if [[ ${#INSTALLED_PKGS[@]} -eq 0 ]]; then
	echo "$SCRIPT_NAME: no installed packages found via dpkg-query." >&2
	exit 1
fi

# Extract all package names available in any backports archive.
# aptitude search '~Abackports' is more comprehensive than parsing dumpavail
# because it handles packages where the Filename field lacks 'backports' but
# the archive label is correct (e.g. packages pinned via Release files).
declare -a BACKPORTS_PKGS
mapfile -t BACKPORTS_PKGS < <(
	# aptitude output: columns are state, package-name, version, description
	# The -F format string '%p' gives just the package name.
	aptitude search -F '%p' '~Abackports' 2>/dev/null |
	sed 's/[[:space:]].*//' |
	sort -u
)

debug "Backports package count from aptitude search: ${#BACKPORTS_PKGS[@]}"
if [[ "$DEBUG" -eq 1 ]]; then
	debug "Raw aptitude search line count:"
	_ap_count=$(aptitude search -F '%p' '~Abackports' 2>/dev/null | wc -l || true)
	debug "  \`aptitude search '~Abackports'\` returned ${_ap_count:-0} lines"
	if [[ ${#BACKPORTS_PKGS[@]} -gt 0 ]]; then
		debug "Backports package sample (first 10):"
		printf '%s\n' "${BACKPORTS_PKGS[@]:0:10}" | sed 's/^/[debug]   /' >&2
        printf '[debug]   …\n' >&2
	fi
fi

if [[ ${#BACKPORTS_PKGS[@]} -eq 0 ]]; then
	echo "No packages with backports entries were found in apt metadata."
	echo "Check that your apt lists are up to date and a *-backports source is enabled."
	if [[ "$DEBUG" -eq 1 ]]; then
		debug "APT policy excerpt for backports (if any):"
		apt-cache policy | sed -n '/backports/,+3p' | sed 's/^/[debug] /' >&2 || true
	fi
	exit 0
fi

get_candidate() {
	local pkg=$1
	apt-cache policy "$pkg" 2>/dev/null | awk '/^  Candidate:/ {print $2; exit}' || true
}

get_installed_origin_line() {
    local pkg=$1
    apt-cache policy "$pkg" 2>/dev/null |
    awk '
        /^ ***/ {in_installed=1; next}
        in_installed && /^[[:space:]]+[0-9]+[[:space:]]+((https?|file):|\/var\/lib\/dpkg\/status)/ {print; exit}
        in_installed && NF==0 {exit}
    ' || true
}

get_backports_versions() {
  local pkg=$1
  apt-cache policy "$pkg" 2>/dev/null |
  awk '
    # Installed line in version table: *** <version> <priority>
    /^[[:space:]]+\*\*\*[[:space:]]+/ {
      ver=$2
      next
    }

    # Version row: <version> <priority>
    # Keep this strict so we do not match source lines.
    /^[[:space:]]+[^[:space:]]+[[:space:]]+[0-9]+[[:space:]]*$/ {
      ver=$1
      next
    }

    # Source/origin row for current version context
    /^[[:space:]]+[0-9]+[[:space:]].*backports/ && ver != "" {
      print ver
    }
  ' | sort -u || true
}

get_backports_suites() {
	local pkg=$1
	apt-cache policy "$pkg" 2>/dev/null |
	sed -n 's/.* \([^ /]*-backports\)\/.*/\1/p' |
	sort -u
}

get_virtual_providers() {
	local pkg=$1
	apt-cache showpkg "$pkg" 2>/dev/null |
	awk '
		/^Reverse Provides:/ {flag=1; next}
		flag && NF==0 {exit}
		flag && NF>0 {print $1}
	' |
	sort -u
}

highest_version_from_list() {
	local best=""
	local v
	for v in "$@"; do
		[[ -n "$v" ]] || continue
		if [[ -z "$best" ]] || dpkg --compare-versions "$v" gt "$best"; then
			best=$v
		fi
	done
	printf '%s\n' "$best"
}

join_by_comma() {
	local IFS=', '
	echo "$*"
}

declare -a TARGET_PKGS
declare -a ALL_VIRTUAL_WITH_BACKPORTS
mapfile -t ALL_VIRTUAL_WITH_BACKPORTS < <(
	for pkg in "${BACKPORTS_PKGS[@]}"; do
		if ! apt-cache show "$pkg" >/dev/null 2>&1; then
			echo "$pkg"
		fi
	done | sort -u
)

for pkg in "${BACKPORTS_PKGS[@]}"; do
	if [[ -n "${INSTALLED_SET[$pkg]:-}" ]]; then
		TARGET_PKGS+=("$pkg")
	elif [[ $include_not_installed -eq 1 ]]; then
		TARGET_PKGS+=("$pkg")
	fi
done

debug "Target package count after installed/not-installed filter: ${#TARGET_PKGS[@]}"
if [[ "$DEBUG" -eq 1 && ${#TARGET_PKGS[@]} -gt 0 ]]; then
	debug "Target package sample (first 10):"
	printf '%s\n' "${TARGET_PKGS[@]:0:10}" | sed 's/^/[debug]   /' >&2
    printf '[debug]   …\n' >&2
fi

declare -a RELEVANT_VIRTUALS
for vpkg in "${ALL_VIRTUAL_WITH_BACKPORTS[@]}"; do
	mapfile -t providers < <(get_virtual_providers "$vpkg")
	if [[ ${#providers[@]} -eq 0 ]]; then
		continue
	fi
	for pr in "${providers[@]}"; do
		if [[ -n "${INSTALLED_SET[$pr]:-}" ]]; then
			RELEVANT_VIRTUALS+=("$vpkg")
			break
		fi
	done
done

mapfile -t RELEVANT_VIRTUALS < <(printf '%s\n' "${RELEVANT_VIRTUALS[@]:-}" | sed '/^$/d' | sort -u)

debug "Virtual package names with backports entries: ${#ALL_VIRTUAL_WITH_BACKPORTS[@]}"
debug "Relevant virtual package names with installed providers: ${#RELEVANT_VIRTUALS[@]}"
if [[ "$DEBUG" -eq 1 && ${#RELEVANT_VIRTUALS[@]} -gt 0 ]]; then
	debug "Relevant virtual sample (first 10):"
	printf '%s\n' "${RELEVANT_VIRTUALS[@]:0:10}" | sed 's/^/[debug]   /' >&2
fi

newer_backport_count=0
already_on_backports_count=0
installed_no_newer_count=0
not_installed_count=0
virtual_count=0
actionable_count=0

declare -a ACTIONABLE_PACKAGES=()

echo
echo "================================================================="
echo "Installed Packages vs Backports Report"
echo "================================================================="
echo

if [[ ${#TARGET_PKGS[@]} -eq 0 && ${#RELEVANT_VIRTUALS[@]} -eq 0 ]]; then
	echo "No installed packages with backports entries were found."
	echo "Try 'sudo apt update' and verify that a *-backports source is enabled."
	if [[ "$DEBUG" -eq 1 ]]; then
		debug "Reason breakdown:"
		debug "  Installed package count: ${#INSTALLED_PKGS[@]}"
		debug "  Backports package count: ${#BACKPORTS_PKGS[@]}"
		debug "  Target package count: ${#TARGET_PKGS[@]}"
		debug "  Relevant virtual count: ${#RELEVANT_VIRTUALS[@]}"
		if [[ ${#BACKPORTS_PKGS[@]} -gt 0 ]]; then
			_probe_pkg="${BACKPORTS_PKGS[0]}"
			debug "Policy probe for first backports package: ${_probe_pkg}"
			apt-cache policy "${_probe_pkg}" | sed 's/^/[debug] /' >&2 || true
		fi
	fi
	exit 0
fi

if [[ ${#TARGET_PKGS[@]} -gt 0 ]]; then
	echo "Per-package analysis (real packages)"
	echo "-----------------------------------------------------------------"

	mapfile -t TARGET_PKGS < <(printf '%s\n' "${TARGET_PKGS[@]}" | sort -u)

	for pkg in "${TARGET_PKGS[@]}"; do
		installed_ver="${INSTALLED_VERSION[$pkg]:-}"
		installed=no

		echo
		debug "Analyzing package: $pkg"
		if [[ -n "$installed_ver" ]]; then
			installed=yes
		fi

		candidate_ver=$(get_candidate "$pkg")
		origin_line=$(get_installed_origin_line "$pkg")
		mapfile -t bp_versions < <(get_backports_versions "$pkg")
		mapfile -t bp_suites < <(get_backports_suites "$pkg")
		highest_bp=$(highest_version_from_list "${bp_versions[@]:-}")

		is_installed_from_backports=no
		if [[ "$origin_line" == *backports* ]]; then
			is_installed_from_backports=yes
		fi

		state=""
		explanation=""
		action=""

		if [[ "$installed" == no ]]; then
			state="not-installed"
			explanation="Package is not currently installed, but a backports build exists."
			((not_installed_count++))
		elif [[ -n "$highest_bp" ]] && dpkg --compare-versions "$highest_bp" gt "$installed_ver"; then
			state="newer-backport-available"
			explanation="Installed version is older than the newest version seen in backports."
			action="$pkg"
			ACTIONABLE_PACKAGES+=("$pkg")
			((actionable_count++))
			((newer_backport_count++))
		elif [[ "$is_installed_from_backports" == yes ]]; then
			state="installed-from-backports"
			explanation="Installed package already comes from a backports archive."
			((already_on_backports_count++))
		else
			state="no-newer-backport"
			explanation="Package is installed, but no backports version newer than installed was found."
			((installed_no_newer_count++))
		fi

		echo "Package: $pkg"
		echo "  Type: real package"
		echo "  Installed: $installed"
		if [[ "$installed" == yes ]]; then
			echo "  Installed version: $installed_ver"
			if [[ -n "$origin_line" ]]; then
				echo "  Installed origin: $origin_line"
			fi
		fi
		echo "  Candidate version: ${candidate_ver:-unknown}"
		if [[ ${#bp_versions[@]} -gt 0 ]]; then
			echo "  Backports versions: $(join_by_comma "${bp_versions[@]}")"
			echo "  Newest backports version: $highest_bp"
		else
			echo "  Backports versions: none parsed"
		fi
		if [[ ${#bp_suites[@]} -gt 0 ]]; then
			echo "  Backports suites: $(join_by_comma "${bp_suites[@]}")"
		fi
		echo "  State: $state"
		echo "  Explanation: $explanation"
		if [[ -n "$action" ]]; then
			echo "  Action: could be upgraded via backports targeting (see summary)."
		fi
		debug "Result for $pkg: state=$state installed=${installed_ver:-none} candidate=${candidate_ver:-unknown} highest_backports=${highest_bp:-none}"
	done || true
fi

if [[ ${#RELEVANT_VIRTUALS[@]} -gt 0 ]]; then
	echo
	echo "Per-package analysis (virtual package names)"
	echo "-----------------------------------------------------------------"

	for vpkg in "${RELEVANT_VIRTUALS[@]}"; do
		mapfile -t providers < <(get_virtual_providers "$vpkg")
		declare -a installed_providers=()
		for pr in "${providers[@]}"; do
			if [[ -n "${INSTALLED_SET[$pr]:-}" ]]; then
				installed_providers+=("$pr=${INSTALLED_VERSION[$pr]}")
			fi
		done

		mapfile -t vp_bp_versions < <(get_backports_versions "$vpkg")
		mapfile -t vp_bp_suites < <(get_backports_suites "$vpkg")

		echo
		echo "Package: $vpkg"
		echo "  Type: virtual package"
		echo "  Installed: virtual names are not directly installed"
		echo "  Providers installed: $(join_by_comma "${installed_providers[@]:-none}")"
		if [[ ${#vp_bp_versions[@]} -gt 0 ]]; then
			echo "  Backports versions: $(join_by_comma "${vp_bp_versions[@]}")"
		else
			echo "  Backports versions: none parsed"
		fi
		if [[ ${#vp_bp_suites[@]} -gt 0 ]]; then
			echo "  Backports suites: $(join_by_comma "${vp_bp_suites[@]}")"
		fi
		echo "  State: virtual-satisfied-by-installed-provider"
		echo "  Explanation: dependency satisfaction comes from installed provider package(s), not from the virtual name itself."
		((virtual_count++))
	done || true
fi

echo
echo "================================================================="
echo "Summary"
echo "================================================================="
echo "Installed packages with newer backport available : $newer_backport_count"
echo "Installed packages already from backports        : $already_on_backports_count"
echo "Installed packages without newer backport        : $installed_no_newer_count"
if [[ $include_not_installed -eq 1 ]]; then
	echo "Backports packages that are not installed        : $not_installed_count"
fi
echo "Relevant virtual package names                   : $virtual_count"

if (( actionable_count > 0 )); then
	mapfile -t ACTIONABLE_PACKAGES < <(printf '%s\n' "${ACTIONABLE_PACKAGES[@]:-}" | sed '/^$/d' | sort -u)
	actionable_count=${#ACTIONABLE_PACKAGES[@]}
	debug "Actionable package count: ${actionable_count}"

    # Prefer suite from first known backports package, then global apt policy, then os-release codename.
    default_suite="${BACKPORTS_PKGS[0]:-}"
    detected_suite=""

    if [[ -n "$default_suite" ]]; then
        mapfile -t _pkg_suites < <(get_backports_suites "$default_suite")
        detected_suite="${_pkg_suites[0]:-}"
    fi

    if [[ -z "$detected_suite" ]]; then
        mapfile -t _policy_suites < <(
            apt-cache policy 2>/dev/null |
            sed -n 's/.* \([^ /]*-backports\)\/.*/\1/p' |
            sort -u
        )
        detected_suite="${_policy_suites[0]:-}"
    fi

    if [[ -z "$detected_suite" && -r /etc/os-release ]]; then
        os_codename="$(
            awk -F= '
                /^(UBUNTU_CODENAME|VERSION_CODENAME)=/ {
                    gsub(/"/, "", $2)
                    print $2
                    exit
                }
            ' /etc/os-release
        )"
        if [[ -n "$os_codename" ]]; then
            detected_suite="${os_codename}-backports"
        fi
    fi

	echo
	echo "Actionable conclusion"
	echo "-----------------------------------------------------------------"
	echo "These installed packages appear to have newer versions in backports:"
	printf '  - %s\n' "${ACTIONABLE_PACKAGES[@]}"
	echo
    if [[ -n "$detected_suite" ]]; then
        echo "Review and upgrade explicitly (recommended dry run first):"
        echo "  sudo apt --dry-run install -t $detected_suite ${ACTIONABLE_PACKAGES[*]}"
        echo "If the simulation looks correct, run without --dry-run:"
        echo "  sudo apt install -t $detected_suite ${ACTIONABLE_PACKAGES[*]}"
    else
        echo "WARNING: Could not auto-detect backports suite name." >&2
        echo "Review and upgrade explicitly (recommended dry run first):"
        echo "  sudo apt --dry-run install -t <codename>-backports ${ACTIONABLE_PACKAGES[*]}"
        echo "If the simulation looks correct, run without --dry-run:"
        echo "  sudo apt install -t <codename>-backports ${ACTIONABLE_PACKAGES[*]}"
    fi
	echo
	echo "Tip: backports are opt-in by design, so explicit -t targeting is expected."
else
	echo
	echo "Actionable conclusion"
	echo "-----------------------------------------------------------------"
	echo "No installed package was found where a newer backports version is available."
	echo "Recommended checks:"
	echo "  1) sudo apt update"
	echo "  2) Confirm your Ubuntu backports source is enabled"
	echo "  3) Re-run this script"
fi

if [[ "$DEBUG" -eq 1 ]]; then
	debug "Run completed"
fi
