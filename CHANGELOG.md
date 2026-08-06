# Changelog

## 0.1.0-beta — 2026-08-06

- Detect the complete three-monitor primary row and its effective resolutions.
- Validate 100% Windows display scale before touching the game window.
- Promote side displays to a matching driver-exposed mode when requested.
- Back up and atomically update War Thunder's normal `config.blk`.
- Start through the official War Thunder launcher and BattlEye flow.
- Attach safely to an already-running `aces.exe` window.
- Remove the standard title bar and place a real 7680×1440 client area at the
  exact virtual-desktop coordinates.
- Use bounded stabilization instead of an endless resize loop.
- Save and restore temporary Windows display-mode changes.

