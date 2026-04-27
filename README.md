# AI Disclaimer
vibed out with claude code sonnet 4.6

# MiSTer FPGA RetroAchievements Installer

A workstation-side install script that bootstraps [odelot's RetroAchievements-enabled MiSTer binaries](https://github.com/odelot/Main_MiSTer) onto a MiSTer FPGA over FTP. Run it from your Linux, macOS, or WSL machine — nothing needs to run on the MiSTer itself.

> Based on [mister-fpga-retroachievements](https://github.com/manyhats-mike/mister-fpga-retroachievements) by manyhats-mike. and [suggestion by smeg-of-lister](https://github.com/manyhats-mike/mister-fpga-retroachievements/issues/1)

---

## What it does

1. Downloads the latest `odelot/Main_MiSTer` binary and every published RA-enabled core `.rbf` (NES, SNES, Genesis, SMS, GB, N64, PSX, and any others auto-discovered from GitHub at install time).
2. Uploads the modified binary, cores, `achievement.wav`, a starter `retroachievements.cfg`, `.mgl` launchers, and an install manifest to the MiSTer over FTP.
3. Appends an `[RA_*]` section to `/media/fat/MiSTer.ini` so MiSTer knows to use the RA binary for those cores.

Files are placed under `/media/fat/_RA_Cores/` and left completely separate from your stock setup, so nothing is overwritten.

MiSTer_RA - runs locally on the mister (place in Scripts folder)  
MiSTer_RetroAchievements.sh - runs on remote workstation (will be deprecated when local script is tested more)  

---

## Requirements

- `curl`
- `unzip`
- `awk`
- FTP enabled on the MiSTer (it's on by default)

---

## Usage

```bash
./MiSTer_RetroAchievements.sh
```

The script will prompt for your MiSTer's IP address interactively.

### Flags

| Flag | Description |
|------|-------------|
| `-v`, `--verbose` | Print each FTP command as it runs |
| `-n`, `--dry-run` | Download and stage files locally but skip all FTP writes |
| `-h`, `--help` | Show usage and exit |

### Environment variables

These are all optional. Set them if you want to override the defaults.

| Variable | Default | Description |
|----------|---------|-------------|
| `MISTER_USER` | `root` | FTP username |
| `MISTER_PASS` | `1` | FTP password |
| `STAGING_DIR` | `./staging` | Local working directory for downloaded files |

Example — non-interactive run with a custom password:

```bash
MISTER_PASS=mypassword ./MiSTer_RetroAchievements.sh
```

---

## After installation

1. **Edit `/media/fat/retroachievements.cfg`** on the MiSTer and fill in your RetroAchievements username and password. Use your real account password, not a Web API key — the rcheevos client only sends it on first login and then caches a session token.

2. **Reboot the MiSTer** so the updated `MiSTer.ini` settings take effect.

3. **Launch a game** on a supported system to confirm achievements load.

---

## File layout on the MiSTer

```
/media/fat/
├── MiSTer.ini                  ← [RA_*] block appended here
├── retroachievements.cfg       ← your RA credentials go here
├── achievement.wav             ← unlock sound effect
└── _RA_Cores/
    ├── MiSTer_RA.ra            ← odelot's modified MiSTer binary
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
- [manyhats-mike](https://github.com/manyhats-mike/mister-fpga-retroachievements) — original project this script is based on
