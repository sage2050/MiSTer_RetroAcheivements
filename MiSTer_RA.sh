#!/usr/bin/env bash
# MiSTer_RetroAchievements_local.sh - Bootstrap the mister-fpga-retroachievements
# toolkit directly on the MiSTer. Run this from a MiSTer shell session.
#
# What it does:
#   1. Downloads odelot's latest Main_MiSTer binary + every published core
#      .rbf for systems he supports; auto-discovered from GitHub at install time.
#   2. Copies the modified binary, cores, achievement.wav, a placeholder
#      retroachievements.cfg, .mgl launchers, and the manifest into place.
#   3. Appends an [RA_*] section to /media/fat/MiSTer.ini to load RA cores with the RA main.
#
# Usage:
#   ./MiSTer_RetroAchievements_local.sh [options]
#
# Flags:
#   -v, --verbose   Print each file operation as it runs
#   -n, --dry-run   Download and stage files locally but skip all writes
#   -h, --help      Show usage and exit
#
# Environment variables (optional):
#   STAGING_DIR    Local working directory  (default: /tmp/ra_staging)
#
# Project: https://github.com/sage2050/MiSTer_RetroAchievements
# License: MIT

set -eu

# ─────────────────────────────────────────────
# Flag parsing
# ─────────────────────────────────────────────

VERBOSE=0
DRY_RUN=0

usage() {
  cat <<USAGE
Usage: ./MiSTer_RetroAchievements_local.sh [options]

Options:
  -v, --verbose   Print each file operation as it runs
  -n, --dry-run   Download and stage files locally but skip all writes
  -h, --help      Show this help and exit
USAGE
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    -v|--verbose) VERBOSE=1 ;;
    -n|--dry-run) DRY_RUN=1 ;;
    -h|--help)    usage ;;
    *) echo "ERR: Unknown option '$1'. Use --help for usage." >&2; exit 1 ;;
  esac
  shift
done

# ─────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────

SCRIPT_VERSION="0.3.0"

STAGING_DIR="${STAGING_DIR:-/tmp/ra_staging}"
FAT="/media/fat"

GITHUB_USER="odelot"
GITHUB_API="https://api.github.com"

echo "MiSTer_RetroAchievements_local.sh v${SCRIPT_VERSION}"
echo "Staging: $STAGING_DIR"
[ "$DRY_RUN" = "1" ] && echo "Mode:    DRY RUN — no files will be written"
[ "$VERBOSE" = "1" ] && echo "Mode:    VERBOSE — file operations will be printed"
echo

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────

require_tool() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERR: missing required tool '$1'" >&2; exit 1; }
}

require_tool curl
require_tool unzip

mkdir -p "$STAGING_DIR/cores" "$STAGING_DIR/main"

# MiSTer's CA certificate bundle is outdated — skip SSL verification.
# All downloads are from GitHub over HTTPS; the risk is acceptable on a
# trusted local network where MITM attacks are unlikely.
CURL="curl -k"

# Copy a file into place, respecting dry-run and verbose flags.
local_put() {
  local src="$1"
  local dest="$2"
  [ "$VERBOSE" = "1" ] && echo "    [cp] $src -> $dest"
  if [ "$DRY_RUN" = "1" ]; then
    echo "    [dry-run] skipping: $dest"
    return 0
  fi
  cp "$src" "$dest"
}

# Create a directory if it doesn't exist.
local_mkdir() {
  local path="$1"
  [ "$VERBOSE" = "1" ] && echo "    [mkdir] $path"
  if [ "$DRY_RUN" = "1" ]; then
    echo "    [dry-run] skipping mkdir: $path"
    return 0
  fi
  mkdir -p "$path"
}

# Extract a single JSON string value using grep + sed (no jq dependency).
json_string() {
  local key="$1"
  local file="$2"
  grep -oE "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$file" \
    | head -1 \
    | sed -E 's/.*"([^"]*)".*/\1/'
}

# Extract the first download URL ending in a given extension from a JSON file.
json_download_url() {
  local ext="$1"
  local file="$2"
  grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*'"${ext}"'"' "$file" \
    | head -1 \
    | sed -E 's/.*"([^"]*)".*/\1/'
}

# ─────────────────────────────────────────────
# Step 0: Preflight — verify we are on a MiSTer
# ─────────────────────────────────────────────

# Read the existing manifest once upfront for both main binary and core tag checks.
existing_manifest_path="$FAT/_RA_Cores/.manifest"
existing_manifest=""
if [ -f "$existing_manifest_path" ]; then
  existing_manifest="$existing_manifest_path"
  echo "  Found existing manifest"
fi

echo "== Step 0: Verifying environment =="

if [ ! -d "$FAT" ]; then
  echo "ERR: $FAT not found. Is this running on a MiSTer?" >&2
  exit 1
fi

echo "  OK — $FAT is accessible"

# ─────────────────────────────────────────────
# Step 1: Download the latest odelot/Main_MiSTer release
# ─────────────────────────────────────────────

echo "== Step 1: Downloading odelot/Main_MiSTer =="

$CURL -sSL -o "$STAGING_DIR/main_release.json" \
  "$GITHUB_API/repos/$GITHUB_USER/Main_MiSTer/releases/latest"

if grep -q '"message"' "$STAGING_DIR/main_release.json"; then
  api_msg="$(json_string "message" "$STAGING_DIR/main_release.json")"
  echo "ERR: GitHub API error fetching Main_MiSTer release: $api_msg" >&2
  exit 1
fi

main_download_url="$(json_download_url ".zip" "$STAGING_DIR/main_release.json")"
main_tag="$(json_string "tag_name" "$STAGING_DIR/main_release.json")"

[ -n "$main_download_url" ] || {
  echo "ERR: No .zip asset found on the latest Main_MiSTer release." >&2
  exit 1
}

echo "  Release tag: $main_tag"

# Check the installed main binary tag from the manifest fetched above.
installed_main_tag="$(grep '^# main_tag=' "$existing_manifest" 2>/dev/null | cut -d= -f2 | head -1)"

if [ -n "$installed_main_tag" ] && [ "$installed_main_tag" = "$main_tag" ]; then
  echo "  MiSTer_RA already at $main_tag — skipping binary download"
  MAIN_BINARY=""
  MAIN_WAV=""
  # Download the zip solely to extract retroachievements.cfg.
  echo "  Downloading zip for cfg extraction..."
  $CURL --progress-bar -L -o "$STAGING_DIR/main.zip" "$main_download_url"
  unzip -o "$STAGING_DIR/main.zip" -d "$STAGING_DIR/main" >/dev/null
  MAIN_CFG="$(find "$STAGING_DIR/main" -maxdepth 3 -type f -name retroachievements.cfg | head -1)"
else
  echo "  Downloading binary zip..."
  $CURL --progress-bar -L -o "$STAGING_DIR/main.zip" "$main_download_url"
  unzip -o "$STAGING_DIR/main.zip" -d "$STAGING_DIR/main" >/dev/null

  MAIN_BINARY="$(find "$STAGING_DIR/main" -maxdepth 3 -type f -name MiSTer | head -1)"
  MAIN_WAV="$(find "$STAGING_DIR/main" -maxdepth 3 -type f -name achievement.wav | head -1)"
  MAIN_CFG="$(find "$STAGING_DIR/main" -maxdepth 3 -type f -name retroachievements.cfg | head -1)"

  [ -n "$MAIN_BINARY" ] || {
    echo "ERR: MiSTer binary not found inside the downloaded zip." >&2
    exit 1
  }
fi

# ─────────────────────────────────────────────
# Step 2: Discover and download all odelot/*_MiSTer cores
# ─────────────────────────────────────────────

echo "== Step 2: Discovering odelot/*_MiSTer cores =="

$CURL -sSL -o "$STAGING_DIR/repos.json" \
  "$GITHUB_API/users/$GITHUB_USER/repos?per_page=100&type=public"

if grep -q '"message"' "$STAGING_DIR/repos.json"; then
  api_msg="$(json_string "message" "$STAGING_DIR/repos.json")"
  echo "ERR: GitHub API error: $api_msg" >&2
  exit 1
fi

core_repos="$(
  grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]*_MiSTer"' "$STAGING_DIR/repos.json" \
    | sed -E 's/.*"([^"]*)".*/\1/' \
    | grep -v '^Main_MiSTer$' \
  || true
)"

if [ -z "$core_repos" ]; then
  echo "  No *_MiSTer repos found in user listing — trying GitHub search API..."
  $CURL -sSL -o "$STAGING_DIR/repos_search.json" \
    "$GITHUB_API/search/repositories?q=user:${GITHUB_USER}+MiSTer+in:name&per_page=100"
  if grep -q '"message"' "$STAGING_DIR/repos_search.json"; then
    api_msg="$(json_string "message" "$STAGING_DIR/repos_search.json")"
    echo "ERR: GitHub search API error: $api_msg" >&2
    exit 1
  fi
  core_repos="$(
    grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]*MiSTer[^"]*"' "$STAGING_DIR/repos_search.json" \
      | sed -E 's/.*"([^"]*)".*/\1/' \
      | grep -v '^Main_MiSTer$' \
    || true
  )"
fi

[ -n "$core_repos" ] || {
  echo "ERR: No odelot/*_MiSTer core repos found. Check that the GitHub API is reachable and that $GITHUB_USER has public repos." >&2
  exit 1
}

echo "  Found cores: $(echo "$core_repos" | tr '\n' ' ')"

# Use the manifest already read above for core tag comparisons.
if [ -n "$existing_manifest" ]; then
  echo "  Found existing manifest — will skip cores already at latest tag"
else
  echo "  No existing manifest — all cores will be downloaded"
fi

installed_tag() {
  local repo="$1"
  [ -n "$existing_manifest" ] || return 0
  grep "^${repo}|" "$existing_manifest" 2>/dev/null | cut -d'|' -f5 | head -1
}

manifest_lines=""
skipped_cores=""
core_tags_file="$STAGING_DIR/core_tags.txt"
: > "$core_tags_file"

for repo in $core_repos; do
  echo "-- $repo --"

  $CURL -sSL -o "$STAGING_DIR/rel_${repo}.json" \
    "$GITHUB_API/repos/$GITHUB_USER/$repo/releases/latest"

  if grep -q '"message"[[:space:]]*:[[:space:]]*"Not Found"' "$STAGING_DIR/rel_${repo}.json"; then
    echo "  No releases yet — skipping"
    continue
  fi

  release_tag="$(json_string "tag_name" "$STAGING_DIR/rel_${repo}.json")"
  rbf_url="$(json_download_url ".rbf" "$STAGING_DIR/rel_${repo}.json")"

  zip_url=""
  if [ -z "$rbf_url" ]; then
    zip_url="$(json_download_url ".zip" "$STAGING_DIR/rel_${repo}.json")"
  fi

  if [ -z "$rbf_url" ] && [ -z "$zip_url" ]; then
    echo "  No .rbf or .zip asset found — skipping"
    skipped_cores="${skipped_cores}${repo} (no asset)\n"
    old_entry="$([ -n "$existing_manifest" ] && grep "^${repo}|" "$existing_manifest" 2>/dev/null || true)"
    [ -n "$old_entry" ] && manifest_lines="${manifest_lines}${old_entry}\n"
    continue
  fi

  core_name="${repo%_MiSTer}"
  staged_rbf="$STAGING_DIR/cores/${core_name}.rbf"

  current_tag="$(installed_tag "$repo")"
  if [ -n "$current_tag" ] && [ "$current_tag" = "$release_tag" ]; then
    echo "  Already at $release_tag — skipping download"
    echo "${core_name}=${release_tag}" >> "$core_tags_file"
    if [ -n "$rbf_url" ]; then
      asset_filename="$(basename "$rbf_url")"
    else
      asset_filename="$(basename "$zip_url")"
    fi
    manifest_lines="${manifest_lines}${repo}|${core_name}|/media/fat/_Console|${core_name}_*.rbf|${release_tag}|${asset_filename}
"
    continue
  fi

  if [ -n "$rbf_url" ]; then
    asset_filename="$(basename "$rbf_url")"
    echo "  Downloading $asset_filename..."
    $CURL --progress-bar -L -o "$staged_rbf" "$rbf_url"
  else
    asset_filename="$(basename "$zip_url")"
    echo "  Downloading $asset_filename (zip)..."
    $CURL --progress-bar -L -o "$STAGING_DIR/${repo}.zip" "$zip_url"
    unzip -o "$STAGING_DIR/${repo}.zip" -d "$STAGING_DIR/${repo}" >/dev/null
    rbf_inside="$(find "$STAGING_DIR/${repo}" -maxdepth 4 -type f -name '*.rbf' | head -1)"
    if [ -z "$rbf_inside" ]; then
      echo "  ERR: No .rbf found inside $asset_filename" >&2
      skipped_cores="${skipped_cores}${repo} (no .rbf inside zip)\n"
      old_entry="$([ -n "$existing_manifest" ] && grep "^${repo}|" "$existing_manifest" 2>/dev/null || true)"
      [ -n "$old_entry" ] && manifest_lines="${manifest_lines}${old_entry}\n"
      continue
    fi
    cp "$rbf_inside" "$staged_rbf"
  fi

  echo "  Staged ${core_name}.rbf  (tag: $release_tag)"
  echo "${core_name}=${release_tag}" >> "$core_tags_file"

  manifest_lines="${manifest_lines}${repo}|${core_name}|/media/fat/_Console|${core_name}_*.rbf|${release_tag}|${asset_filename}
"
done

# ─────────────────────────────────────────────
# Step 3: Install RA cores and supporting files
# ─────────────────────────────────────────────

echo "== Step 3: Installing _RA_Cores payload =="

local_mkdir "$FAT/_RA_Cores"
local_mkdir "$FAT/_RA_Cores/Cores"

# Install the modified MiSTer binary only if it's new or updated.
if [ -n "$MAIN_BINARY" ]; then
  local_put "$MAIN_BINARY" "$FAT/MiSTer_RA"
  chmod +x "$FAT/MiSTer_RA"
  echo "  Installed MiSTer_RA  (tag: $main_tag)"
else
  echo "  MiSTer_RA already at $main_tag — skipping"
fi

# Install the achievement sound effect if bundled in the release.
if [ -n "$MAIN_WAV" ]; then
  local_put "$MAIN_WAV" "$FAT/achievement.wav"
  echo "  Installed achievement.wav"
fi

# Install the config only if one doesn't already exist.
CREDENTIALS_SET=0
CFG_JUST_IMPORTED=0
if [ ! -f "$FAT/retroachievements.cfg" ]; then
  if [ -n "$MAIN_CFG" ]; then
    local_put "$MAIN_CFG" "$FAT/retroachievements.cfg"
    echo "  Installed retroachievements.cfg"
    CFG_JUST_IMPORTED=1
  else
    echo "  WARN: retroachievements.cfg not found in the Main_MiSTer release — skipping" >&2
  fi
else
  echo "  retroachievements.cfg already present — leaving untouched"
fi

# Prompt for credentials. If the cfg was just imported always prompt.
# For an existing cfg, only prompt if a field is blank.
PROMPT_CREDS=0
if [ "$CFG_JUST_IMPORTED" = "1" ]; then
  PROMPT_CREDS=1
elif [ -f "$FAT/retroachievements.cfg" ]; then
  cfg_username="$(grep '^username=' "$FAT/retroachievements.cfg" | cut -d= -f2 | tr -d '[:space:]')"
  cfg_password="$(grep '^password=' "$FAT/retroachievements.cfg" | cut -d= -f2 | tr -d '[:space:]')"
  if [ -z "$cfg_username" ] || [ -z "$cfg_password" ]; then
    PROMPT_CREDS=1
  else
    echo "  Credentials already set — leaving untouched"
    CREDENTIALS_SET=1
  fi
fi

if [ "$PROMPT_CREDS" = "1" ]; then
  echo
  printf "  RetroAchievements credentials are not set. Enter them now? [y/n]: "
  read -r enter_creds
  if [ "$enter_creds" = "y" ] || [ "$enter_creds" = "Y" ]; then
    printf "  Username: "
    read -r ra_username
    printf "  Password: "
    read -rs ra_password
    echo
    sed -i'' "s/^username=.*/username=${ra_username}/" "$FAT/retroachievements.cfg"
    sed -i'' "s/^password=.*/password=${ra_password}/" "$FAT/retroachievements.cfg"
    echo "  Credentials saved to retroachievements.cfg"
    CREDENTIALS_SET=1
  else
    echo "  Skipping — remember to edit /media/fat/retroachievements.cfg before launching a game."
  fi
fi

# Install cores and generate .mgl launchers.
for rbf_file in "$STAGING_DIR"/cores/*.rbf; do
  [ -f "$rbf_file" ] || continue
  remote_name="$(basename "$rbf_file")"
  core_name="${remote_name%.rbf}"

  core_release_tag="$(grep "^${core_name}=" "$core_tags_file" | cut -d= -f2 | head -1)"
  current_tag="$(installed_tag "${core_name}_MiSTer")"

  if [ -f "$FAT/_RA_Cores/Cores/$remote_name" ] && [ -n "$current_tag" ] && [ "$current_tag" = "$core_release_tag" ]; then
    echo "  Cores/$remote_name already at $core_release_tag — skipping"
  else
    local_put "$rbf_file" "$FAT/_RA_Cores/Cores/$remote_name"
    echo "  Installed Cores/$remote_name  (tag: $core_release_tag)"
  fi

  mgl_name="${core_name}.mgl"
  if [ -f "$FAT/_RA_Cores/$mgl_name" ]; then
    echo "  _RA_Cores/$mgl_name already exists — skipping"
  else
    if [ "$DRY_RUN" = "0" ]; then
      cat > "$FAT/_RA_Cores/$mgl_name" <<EOF
<mistergamedescription>
    <rbf>_RA_Cores/Cores/$core_name</rbf>
    <setname same_dir="1">RA_$core_name</setname>
</mistergamedescription>
EOF
    fi
    [ "$VERBOSE" = "1" ] && echo "    [write] $FAT/_RA_Cores/$mgl_name"
    [ "$DRY_RUN" = "1" ] && echo "    [dry-run] skipping: $FAT/_RA_Cores/$mgl_name"
    echo "  Installed _RA_Cores/$mgl_name"
  fi
done

# Write the install manifest.
if [ "$DRY_RUN" = "0" ]; then
  {
    echo "# main_tag=$main_tag"
    echo "# repo|basename|stock_folder|stock_pattern|release_tag|rbf_source_name"
    printf "%s" "$manifest_lines"
  } > "$FAT/_RA_Cores/.manifest"
fi
echo "  Wrote .manifest"

# ─────────────────────────────────────────────
# Step 4: Append RA core config to MiSTer.ini
# ─────────────────────────────────────────────

echo "== Step 4: Updating MiSTer.ini =="

if [ ! -f "$FAT/MiSTer.ini" ]; then
  echo "  ERR: $FAT/MiSTer.ini not found — skipping" >&2
elif grep -q "^\[RA_\*\]" "$FAT/MiSTer.ini"; then
  echo "  [RA_*] block already present — leaving untouched"
else
  if [ "$DRY_RUN" = "0" ]; then
    cat >> "$FAT/MiSTer.ini" <<'EOF'

[RA_*]
main=MiSTer_RA
EOF
  fi
  [ "$DRY_RUN" = "1" ] && echo "    [dry-run] skipping append to MiSTer.ini"
  echo "  Appended [RA_*] block to MiSTer.ini"
fi

# ─────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────

echo "== Cleaning up staging directory =="
rm -rf "$STAGING_DIR"
echo "  Removed $STAGING_DIR"

# ─────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────

cat <<EOF

== Install complete ==
EOF

if [ -n "$skipped_cores" ]; then
  echo "  WARNING: the following cores had errors and were skipped:"
  printf "  %b" "$skipped_cores" | sed 's/^/  /'
fi

if [ "$CREDENTIALS_SET" = "1" ]; then
  cat <<EOF
Next steps:
  1. Reboot the MiSTer so the new MiSTer.ini settings take effect.

  2. Launch a game on a supported system to confirm achievements load.
EOF
else
  cat <<EOF
Next steps:
  1. Edit /media/fat/retroachievements.cfg and fill in your
     RetroAchievements username and password before launching any games.
     (Use your real account password — not a Web API key. The rcheevos client
     only sends it on first login, then caches a session token.)

  2. Reboot the MiSTer so the new MiSTer.ini settings take effect.

  3. Launch a game on a supported system to confirm achievements load.
EOF
fi

echo
printf "Reboot now? [y/n]: "
read -r do_reboot
if [ "$do_reboot" = "y" ] || [ "$do_reboot" = "Y" ]; then
  echo "Rebooting..."
  reboot
else
  echo "Remember to reboot before launching any RA-enabled games."
fi
