# AI Disclaimer
vibed out with claude sonnet 4.6

# MiSTer FPGA RetroAchievements Installer

Installs [odelot's RetroAchievements-enabled MiSTer binaries](https://github.com/odelot/Main_MiSTer) onto a MiSTer FPGA. Two scripts are provided depending on how you prefer to run it.

> Based on [mister-fpga-retroachievements](https://github.com/manyhats-mike/mister-fpga-retroachievements) by manyhats-mike and [suggestion by smeg-of-lister](https://github.com/manyhats-mike/mister-fpga-retroachievements/issues/1).

---

## Scripts

### `MiSTer_RA.sh` — runs directly on the MiSTer
Place in `/media/fat/Scripts/` and run from the MiSTer's Scripts menu or a shell session. No workstation needed.

### `MiSTer_RetroAchievements.sh` — runs from a workstation
Run from your Linux, macOS, or WSL machine. Transfers files to the MiSTer over FTP. Useful if you prefer not to run scripts directly on the device.

---

## What it does

1. Downloads the latest `odelot/Main_MiSTer` binary and every published RA-enabled core `.rbf` — auto-discovered from GitHub at install time.
2. Installs the modified binary, cores, `achievement.wav`, `retroachievements.cfg`, `.mgl` launchers, and an install manifest.
3. Appends an `[RA_*]` section to `/media/fat/MiSTer.ini` so MiSTer loads the RA binary for supported cores.

On subsequent runs, installed versions are compared against the latest GitHub release tags and only updated if a newer release is available.

Files are placed under `/media/fat/_RA_Cores/` and kept completely separate from your stock setup.

---

## Requirements

Both scripts require:
- `curl`
- `unzip`

The workstation script additionally requires:
- `awk`
- FTP enabled on the MiSTer (on by default)

---

## Usage

### MiSTer_RA.sh (local)

```bash
./MiSTer_RA.sh
```

Prompts for RetroAchievements credentials during install. Offers to reboot at the end.

| Flag | Description |
|------|-------------|
| `-v`, `--verbose` | Print each file operation as it runs |
| `-n`, `--dry-run` | Download and stage files but skip all writes |
| `-h`, `--help` | Show usage and exit |

| Variable | Default | Description |
|----------|---------|-------------|
| `STAGING_DIR` | `/tmp/ra_staging` | Scratch directory (cleaned up after each run) |

### MiSTer_RetroAchievements.sh (workstation)

```bash
./MiSTer_RetroAchievements.sh
```

Prompts for the MiSTer's IP address interactively. Can also be set via environment variable to skip the prompt:

```bash
MISTER_HOST=192.168.1.42 ./MiSTer_RetroAchievements.sh
```

| Flag | Description |
|------|-------------|
| `-v`, `--verbose` | Print each FTP command as it runs |
| `-n`, `--dry-run` | Download and stage files but skip all FTP writes |
| `-h`, `--help` | Show usage and exit |

| Variable | Default | Description |
|----------|---------|-------------|
| `MISTER_HOST` | _(prompted)_ | MiSTer IP address |
| `MISTER_USER` | `root` | FTP username |
| `MISTER_PASS` | `1` | FTP password |
| `STAGING_DIR` | `./staging` | Scratch directory (cleaned up after each run) |

---

## After installation

1. **Fill in your credentials** — the script will prompt during install, or edit `/media/fat/retroachievements.cfg` manually. Use your real account password, not a Web API key.

2. **Reboot the MiSTer** so the updated `MiSTer.ini` settings take effect.

3. **Launch a game** on a supported system to confirm achievements load.

---

## File layout on the MiSTer

```
/media/fat/
├── MiSTer.ini                  ← [RA_*] block appended here
├── MiSTer_RA                   ← odelot's modified MiSTer binary
├── retroachievements.cfg       ← your RA credentials go here
├── achievement.wav             ← unlock sound effect
└── _RA_Cores/
    ├── .manifest               ← installed version tracking
    ├── NES.mgl                 ← .mgl launcher per core
    ├── SNES.mgl
    ├── ...
    └── Cores/
        ├── NES.rbf             ← RA-enabled core binaries
        ├── SNES.rbf
        └── ...
```

---

## Credits

- [odelot](https://github.com/odelot) — RetroAchievements-enabled MiSTer binary and cores
- [manyhats-mike](https://github.com/manyhats-mike/mister-fpga-retroachievements) — original project this is based on
