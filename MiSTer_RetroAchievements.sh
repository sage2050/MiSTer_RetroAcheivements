#!/usr/bin/env bash
# MiSTer_RetroAchievements.sh - Bootstrap the mister-fpga-retroachievements toolkit onto a
# MiSTer FPGA over FTP. Run this from your workstation (Linux, macOS, WSL).
# It does not need to run on the MiSTer itself.
#
# What it does:
#   1. Downloads odelot's latest Main_MiSTer binary + every published core
#      .rbf for systems he supports; auto-discovered from GitHub at install time.
#   2. Uploads the modified binary, cores, achievement.wav, a placeholder
#      retroachievements.cfg, .mgl launchers, and the manifest.
#   4. Appends an [RA_*] section to /media/fat/MiSTer.ini to load RA cores with the RA main.
#
# Usage:
#   ./MiSTer_RetroAchievements.sh [options]
#   The script will prompt for the MiSTer IP address interactively.
#
# Flags:
#   -v, --verbose   Print each FTP command as it runs
#   -n, --dry-run   Stage files locally but skip all FTP writes (safe to test)
#   -h, --help      Show usage and exit
#
# Environment variables (optional):
#   MISTER_USER    FTP username                   (default: root)
#   MISTER_PASS    FTP password                   (default: 1)
#   STAGING_DIR    Local working directory         (default: ./staging)
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
Usage: ./MiSTer_RetroAchievements.sh [options]

The script will prompt for the MiSTer IP address interactively.

Options:
  -v, --verbose   Print each FTP command and curl call as it runs
  -n, --dry-run   Download and stage files locally but skip all FTP writes
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

MISTER_USER="${MISTER_USER:-root}"
MISTER_PASS="${MISTER_PASS:-1}"
STAGING_DIR="${STAGING_DIR:-./staging}"

if [ -z "${MISTER_HOST:-}" ]; then
  printf "MiSTer IP address: "
  read -r MISTER_HOST
  [ -n "$MISTER_HOST" ] || { echo "ERR: IP address cannot be empty." >&2; exit 1; }
fi

GITHUB_USER="odelot"
GITHUB_API="https://api.github.com"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "MiSTer_RetroAchievements.sh v${SCRIPT_VERSION}"
echo "Target:  ftp://${MISTER_USER}@${MISTER_HOST}/"
echo "Staging: $STAGING_DIR"
[ "$DRY_RUN" = "1" ] && echo "Mode:    DRY RUN — no files will be written to the MiSTer"
[ "$VERBOSE" = "1" ] && echo "Mode:    VERBOSE — FTP commands will be printed"
echo

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────

# Abort if a required CLI tool is missing.
require_tool() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERR: missing required tool '$1'" >&2; exit 1; }
}

require_tool curl
require_tool unzip
require_tool awk

mkdir -p "$STAGING_DIR/cores" "$STAGING_DIR/main"

# Build an FTP URL for a given absolute remote path.
# Uses double-slash (ftp://HOST//path) so the path is relative to the
# filesystem root, not to the FTP login home (/root on MiSTer).
ftp_url() {
  printf "ftp://%s//%s" "$MISTER_HOST" "${1#/}"
}

# Internal curl wrapper: adds -v when --verbose is set.
_curl() {
  if [ "$VERBOSE" = "1" ]; then
    curl -v "$@"
  else
    curl -sS "$@"
  fi
}

ftp_get() {
  local remote_path="$1"
  local local_dest="$2"
  [ "$VERBOSE" = "1" ] && echo "    [ftp_get] ${remote_path} -> ${local_dest}"
  _curl --connect-timeout 10 \
    -u "${MISTER_USER}:${MISTER_PASS}" \
    -o "$local_dest" \
    "$(ftp_url "$remote_path")"
}

ftp_put() {
  local local_file="$1"
  local remote_path="$2"
  [ "$VERBOSE" = "1" ] && echo "    [ftp_put] ${local_file} -> ${remote_path}"
  if [ "$DRY_RUN" = "1" ]; then
    echo "    [dry-run] skipping upload: ${remote_path}"
    return 0
  fi
  _curl --connect-timeout 10 \
    -u "${MISTER_USER}:${MISTER_PASS}" \
    -T "$local_file" \
    "$(ftp_url "$remote_path")"
}

ftp_ls() {
  local remote_path="$1"
  [ "$VERBOSE" = "1" ] && echo "    [ftp_ls]  ${remote_path}"
  _curl --connect-timeout 10 \
    -u "${MISTER_USER}:${MISTER_PASS}" \
    "$(ftp_url "$remote_path")"
}

ftp_mkdir() {
  local remote_path="$1"
  [ "$VERBOSE" = "1" ] && echo "    [ftp_mkdir] ${remote_path}"
  if [ "$DRY_RUN" = "1" ]; then
    echo "    [dry-run] skipping mkdir: ${remote_path}"
    return 0
  fi
  # Errors are suppressed because MKD fails harmlessly if the dir exists.
  _curl --connect-timeout 10 \
    -u "${MISTER_USER}:${MISTER_PASS}" \
    --quote "MKD /${remote_path#/}" \
    "$(ftp_url "/")" 2>/dev/null || true
}

ftp_chmod() {
  local remote_path="$1"
  local mode="$2"
  [ "$VERBOSE" = "1" ] && echo "    [ftp_chmod] ${mode} ${remote_path}"
  if [ "$DRY_RUN" = "1" ]; then
    echo "    [dry-run] skipping chmod: ${mode} ${remote_path}"
    return 0
  fi
  _curl -u "${MISTER_USER}:${MISTER_PASS}" \
    --quote "SITE CHMOD ${mode} ${remote_path}" \
    "$(ftp_url "/")" >/dev/null 2>&1 || true
}

# Extract a single JSON string value using grep + sed (no jq dependency).
# Usage: json_string <key> <file>
json_string() {
  local key="$1"
  local file="$2"
  grep -oE "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$file" \
    | head -1 \
    | sed -E 's/.*"([^"]*)".*/\1/'
}

# Extract the first URL ending in a given extension from a JSON file.
# Usage: json_download_url <.ext> <file>
json_download_url() {
  local ext="$1"
  local file="$2"
  grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*'"${ext}"'"' "$file" \
    | head -1 \
    | sed -E 's/.*"([^"]*)".*/\1/'
}

# ─────────────────────────────────────────────
# Step 0: Preflight — verify MiSTer is reachable
# ─────────────────────────────────────────────

echo "== Step 0: Verifying MiSTer connectivity =="

if [ "$DRY_RUN" = "1" ]; then
  echo "  [dry-run] skipping connectivity check"
elif ! ftp_ls "/media/fat/" >/dev/null 2>&1; then
  echo "ERR: Cannot list /media/fat/ on ${MISTER_HOST}." >&2
  echo "     Check that FTP is enabled and that host/user/password are correct." >&2
  exit 1
else
  echo "  OK — connected to ${MISTER_HOST}"
fi

# ─────────────────────────────────────────────
# Step 1: Download the latest odelot/Main_MiSTer release
# ─────────────────────────────────────────────

echo "== Step 1: Downloading odelot/Main_MiSTer =="

curl -sSL -o "$STAGING_DIR/main_release.json" \
  "$GITHUB_API/repos/$GITHUB_USER/Main_MiSTer/releases/latest"

# Check for API errors (rate limiting, bad credentials, etc.)
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

# Check the installed main binary tag from the manifest if one exists.
installed_main_tag=""
tmp_existing_main="$STAGING_DIR/existing_manifest_main.txt"
if ftp_get "/media/fat/_RA_Cores/.manifest" "$tmp_existing_main" 2>/dev/null; then
  installed_main_tag="$(grep '^# main_tag=' "$tmp_existing_main" 2>/dev/null | cut -d= -f2 | head -1)"
fi

if [ -n "$installed_main_tag" ] && [ "$installed_main_tag" = "$main_tag" ]; then
  echo "  MiSTer_RA already at $main_tag — skipping binary download"
  MAIN_BINARY=""
  MAIN_WAV=""
  # Still need the zip for retroachievements.cfg in case it's missing on the MiSTer.
  # Only download if we don't already have it staged from a previous run.
  if [ ! -f "$STAGING_DIR/main.zip" ]; then
    echo "  Downloading zip for cfg extraction..."
    curl --progress-bar -L -o "$STAGING_DIR/main.zip" "$main_download_url"
    unzip -o "$STAGING_DIR/main.zip" -d "$STAGING_DIR/main" >/dev/null
  fi
  MAIN_CFG="$(find "$STAGING_DIR/main" -maxdepth 3 -type f -name retroachievements.cfg | head -1)"
else
  echo "  Downloading binary zip..."
  curl --progress-bar -L -o "$STAGING_DIR/main.zip" "$main_download_url"
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

curl -sSL -o "$STAGING_DIR/repos.json" \
  "$GITHUB_API/users/$GITHUB_USER/repos?per_page=100&type=public"

# Check for API errors (rate limiting, bad credentials, etc.)
if grep -q '"message"' "$STAGING_DIR/repos.json"; then
  api_msg="$(json_string "message" "$STAGING_DIR/repos.json")"
  echo "ERR: GitHub API error: $api_msg" >&2
  exit 1
fi

# Pull every repo ending in _MiSTer, excluding the main binary repo itself.
core_repos="$(
  grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]*_MiSTer"' "$STAGING_DIR/repos.json" \
    | sed -E 's/.*"([^"]*)".*/\1/' \
    | grep -v '^Main_MiSTer$' \
  || true
)"

if [ -z "$core_repos" ]; then
  echo "  No *_MiSTer repos found in user listing — trying GitHub search API..."
  curl -sSL -o "$STAGING_DIR/repos_search.json" \
    "$GITHUB_API/search/repositories?q=user:${GITHUB_USER}+MiSTer+in:name&per_page=100"
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

# Pull the existing manifest from the MiSTer so we can skip cores that are
# already up to date. If none exists yet (first run) this is a no-op.
existing_manifest="$STAGING_DIR/existing_manifest.txt"
if ftp_get "/media/fat/_RA_Cores/.manifest" "$existing_manifest" 2>/dev/null; then
  echo "  Found existing manifest — will skip cores already at latest tag"
else
  echo "  No existing manifest — all cores will be downloaded"
  existing_manifest=""
fi

# Look up the installed tag for a given repo from the manifest.
# Returns empty string if the repo isn't listed.
installed_tag() {
  local repo="$1"
  [ -n "$existing_manifest" ] || return 0
  grep "^${repo}|" "$existing_manifest" 2>/dev/null | cut -d'|' -f5 | head -1
}

manifest_lines=""
skipped_cores=""

for repo in $core_repos; do
  echo "-- $repo --"

  curl -sSL -o "$STAGING_DIR/rel_${repo}.json" \
    "$GITHUB_API/repos/$GITHUB_USER/$repo/releases/latest"

  # Skip repos that have no published releases yet.
  if grep -q '"message"[[:space:]]*:[[:space:]]*"Not Found"' "$STAGING_DIR/rel_${repo}.json"; then
    echo "  No releases yet — skipping"
    continue
  fi

  release_tag="$(json_string "tag_name" "$STAGING_DIR/rel_${repo}.json")"
  rbf_url="$(json_download_url ".rbf" "$STAGING_DIR/rel_${repo}.json")"

  # Fall back to a zip asset if no standalone .rbf is published.
  zip_url=""
  if [ -z "$rbf_url" ]; then
    zip_url="$(json_download_url ".zip" "$STAGING_DIR/rel_${repo}.json")"
  fi

  if [ -z "$rbf_url" ] && [ -z "$zip_url" ]; then
    echo "  No .rbf or .zip asset found — skipping"
    skipped_cores="${skipped_cores}${repo} (no asset)\n"
    # Preserve the previously installed manifest entry so the tag is not lost.
    old_entry="$([ -n "$existing_manifest" ] && grep "^${repo}|" "$existing_manifest" 2>/dev/null || true)"
    [ -n "$old_entry" ] && manifest_lines="${manifest_lines}${old_entry}\n"
    continue
  fi

  # Strip the _MiSTer suffix to get the plain core name (e.g. NES_MiSTer → NES).
  core_name="${repo%_MiSTer}"
  staged_rbf="$STAGING_DIR/cores/${core_name}.rbf"

  # Skip downloading if the installed tag matches the latest release tag.
  current_tag="$(installed_tag "$repo")"
  if [ -n "$current_tag" ] && [ "$current_tag" = "$release_tag" ]; then
    echo "  Already at $release_tag — skipping download"
    # Still need this core in the manifest even if we didn't re-download it.
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
    curl --progress-bar -L -o "$staged_rbf" "$rbf_url"
  else
    asset_filename="$(basename "$zip_url")"
    echo "  Downloading $asset_filename (zip)..."
    curl --progress-bar -L -o "$STAGING_DIR/${repo}.zip" "$zip_url"
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

  manifest_lines="${manifest_lines}${repo}|${core_name}|/media/fat/_Console|${core_name}_*.rbf|${release_tag}|${asset_filename}
"
done

# ─────────────────────────────────────────────
# Step 3: Upload RA cores and supporting files
# ─────────────────────────────────────────────

echo "== Step 3: Uploading _RA_Cores payload =="

ftp_mkdir "/media/fat/_RA_Cores"

# Upload the modified MiSTer binary only if it's new or updated.
if [ -n "$MAIN_BINARY" ]; then
  ftp_put "$MAIN_BINARY" "/media/fat/MiSTer_RA"
  echo "  Uploaded MiSTer_RA  (tag: $main_tag)"
else
  echo "  MiSTer_RA already at $main_tag — skipping"
fi

# Upload the achievement sound effect if it was bundled in the release.
[ -n "$MAIN_WAV" ] && ftp_put "$MAIN_WAV" "/media/fat/achievement.wav" && echo "  Uploaded achievement.wav"

# Upload the config bundled in the Main_MiSTer release, only if one doesn't
# already exist on the MiSTer.
CREDENTIALS_SET=0
CFG_JUST_IMPORTED=0
if ! ftp_ls /media/fat/ 2>/dev/null | grep -qE '\sretroachievements\.cfg$'; then
  if [ -n "$MAIN_CFG" ]; then
    ftp_put "$MAIN_CFG" "/media/fat/retroachievements.cfg"
    echo "  Uploaded retroachievements.cfg"
    CFG_JUST_IMPORTED=1
  else
    echo "  WARN: retroachievements.cfg not found in the Main_MiSTer release — skipping" >&2
  fi
else
  echo "  retroachievements.cfg already present — leaving untouched"
fi

# Prompt for credentials. If the cfg was just imported it will have blank
# fields by design, so skip the blank check and always prompt. For an
# existing cfg, only prompt if a field is actually empty.
tmp_cfg_check="$STAGING_DIR/retroachievements.cfg"
PROMPT_CREDS=0
if [ "$CFG_JUST_IMPORTED" = "1" ]; then
  PROMPT_CREDS=1
elif ftp_get "/media/fat/retroachievements.cfg" "$tmp_cfg_check" 2>/dev/null; then
  cfg_username="$(grep '^username=' "$tmp_cfg_check" | cut -d= -f2 | tr -d '[:space:]')"
  cfg_password="$(grep '^password=' "$tmp_cfg_check" | cut -d= -f2 | tr -d '[:space:]')"
  if [ -z "$cfg_username" ] || [ -z "$cfg_password" ]; then
    PROMPT_CREDS=1
  else
    echo "  Credentials already set — leaving untouched"
    CREDENTIALS_SET=1
  fi
fi

if [ "$PROMPT_CREDS" = "1" ]; then
  # Ensure we have a local copy to edit.
  if [ "$CFG_JUST_IMPORTED" = "0" ]; then
    ftp_get "/media/fat/retroachievements.cfg" "$tmp_cfg_check" 2>/dev/null || true
  else
    cp "$MAIN_CFG" "$tmp_cfg_check"
  fi
  echo
  printf "  RetroAchievements credentials are not set. Enter them now? [y/n]: "
  read -r enter_creds
  if [ "$enter_creds" = "y" ] || [ "$enter_creds" = "Y" ]; then
    printf "  Username: "
    read -r ra_username
    printf "  Password: "
    read -rs ra_password
    echo
    sed -i "s/^username=.*/username=${ra_username}/" "$tmp_cfg_check"
    sed -i "s/^password=.*/password=${ra_password}/" "$tmp_cfg_check"
    ftp_put "$tmp_cfg_check" "/media/fat/retroachievements.cfg"
    echo "  Credentials saved to retroachievements.cfg"
    CREDENTIALS_SET=1
  else
    echo "  Skipping — remember to edit /media/fat/retroachievements.cfg before launching a game."
  fi
fi

# Fetch remote directory listings once so we can check file existence without
# making a separate FTP call for every core.
remote_ra_cores="$(ftp_ls "/media/fat/_RA_Cores/" 2>/dev/null || true)"
remote_cores_dir="$(ftp_ls "/media/fat/_RA_Cores/Cores/" 2>/dev/null || true)"

# Upload each staged core .rbf to _RA_Cores/Cores/ and generate a
# companion .mgl launcher that points MiSTer at the RA variant of the core.
# _RA_Cores is created above; Cores must be created as a separate MKD call
# since FTP cannot create nested directories in a single command.
ftp_mkdir "/media/fat/_RA_Cores/Cores"
echo "  Created _RA_Cores/Cores"
for rbf_file in "$STAGING_DIR"/cores/*.rbf; do
  [ -f "$rbf_file" ] || continue
  remote_name="$(basename "$rbf_file")"
  core_name="${remote_name%.rbf}"

  # Look up this core's release tag from the manifest we just built,
  # rather than relying on $release_tag which may be stale from the last
  # iteration of the download loop.
  core_release_tag="$(echo "$manifest_lines" | grep "^${core_name}_MiSTer|" | cut -d'|' -f5 | head -1)"

  # Upload the core binary only if it isn't already on the MiSTer or the
  # release tag is newer than what's installed.
  current_tag="$(installed_tag "${core_name}_MiSTer")"
  if echo "$remote_cores_dir" | grep -qF "$remote_name" && [ -n "$current_tag" ] && [ "$current_tag" = "$core_release_tag" ]; then
    echo "  Cores/$remote_name already at $core_release_tag — skipping"
  else
    ftp_put "$rbf_file" "/media/fat/_RA_Cores/Cores/$remote_name"
    echo "  Uploaded Cores/$remote_name  (tag: $core_release_tag)"
  fi

  # Upload the .mgl launcher only if it isn't already on the MiSTer.
  # .mgl files don't change between releases so existence is enough to skip.
  mgl_name="${core_name}.mgl"
  if echo "$remote_ra_cores" | grep -qF "$mgl_name"; then
    echo "  _RA_Cores/$mgl_name already exists — skipping"
  else
    tmp_mgl="$(mktemp)"
    cat > "$tmp_mgl" <<EOF
<mistergamedescription>
    <rbf>_RA_Cores/Cores/$core_name</rbf>
    <setname same_dir="1">RA_$core_name</setname>
</mistergamedescription>
EOF
    ftp_put "$tmp_mgl" "/media/fat/_RA_Cores/$mgl_name"
    rm -f "$tmp_mgl"
    echo "  Uploaded _RA_Cores/$mgl_name"
  fi
done

# Build and upload the install manifest (used by update/rollback scripts).
tmp_manifest="$(mktemp)"
{
  echo "# main_tag=$main_tag"
  echo "# repo|basename|stock_folder|stock_pattern|release_tag|rbf_source_name"
  printf "%s" "$manifest_lines"
} > "$tmp_manifest"
ftp_put "$tmp_manifest" "/media/fat/_RA_Cores/.manifest"
rm -f "$tmp_manifest"
echo "  Uploaded .manifest"

# ─────────────────────────────────────────────
# Step 4: Append RA core config to MiSTer.ini
# ─────────────────────────────────────────────

echo "== Step 4: Updating MiSTer.ini =="

tmp_ini="$STAGING_DIR/MiSTer.ini"

if ! ftp_get "/media/fat/MiSTer.ini" "$tmp_ini"; then
  echo "  ERR: Could not download /media/fat/MiSTer.ini — skipping" >&2
else
  if grep -q "^\[RA_\*\]" "$tmp_ini"; then
    echo "  [RA_*] block already present — leaving untouched"
  else
    cat >> "$tmp_ini" <<'EOF'

[RA_*]
main=MiSTer_RA
EOF
    ftp_put "$tmp_ini" "/media/fat/MiSTer.ini"
    echo "  Appended [RA_*] block to MiSTer.ini"
  fi
fi

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
  1. Edit /media/fat/retroachievements.cfg on the MiSTer and fill in your
     RetroAchievements username and password before launching any games.
     (Use your real account password — not a Web API key. The rcheevos client
     only sends it on first login, then caches a session token.)

  2. Reboot the MiSTer so the new MiSTer.ini settings take effect.

  3. Launch a game on a supported system to confirm achievements load.
EOF
fi
