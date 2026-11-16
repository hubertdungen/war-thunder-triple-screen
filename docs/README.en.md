# War Thunder Triple Screen

[Português](../README.md)

**Download:** https://github.com/hubertdungen/war-thunder-triple-screen/releases

**Source:** https://github.com/hubertdungen/war-thunder-triple-screen

An external wrapper that runs War Thunder across a row of three monitors with different physical resolutions, without NVIDIA Surround. It was built for the tested local setup: a 2560×1440 centre monitor and 1920×1080 side monitors.

## Local diagnosis

War Thunder was configured for `7680 x 1440`, but Windows exposed:

```text
[ 1920×1080 ][ 2560×1440 ][ 1920×1080 ] = 6400×1440
```

At the same time, `7680×1440` showed up as a super-resolution mode tied to the centre monitor. The game therefore created a window of about 7680 px on a desktop of only 6400 px. The overflow at the sides is real, not just FOV distortion.

The intended result needs the driver to expose 2560×1440 on **each** side monitor:

```text
[ 2560×1440 effective ][ 2560×1440 native ][ 2560×1440 effective ]
                              = 7680×1440
```

The side panels stay physically 1080p; NVIDIA downscales the 1440p image to the panel.

## Safety

The wrapper:

- reads the monitors and modes offered by Windows/the driver;
- can temporarily select a 2560×1440 mode that **already exists** on the side monitors;
- saves and restores the previous resolution, refresh rate and position;
- makes an atomic backup of `config.blk` before writing the resolution;
- opens only the official launcher;
- removes the window frame and positions the window through the normal Windows APIs.

It does not inject DLLs, read or write game memory, modify executables, hook DirectX or try to bypass BattlEye. This lowers the risk but is not an official approval from Gaijin/BattlEye.

## NVIDIA setup (once)

On the author's PC, an inspection on 5 August 2026 showed that both side monitors still **did not expose 2560×1440** to Windows. Before the first run:

1. keep NVIDIA Surround off;
2. in the NVIDIA Control Panel, enable the DSR/DLDSR factor that adds 2560×1440 to the 1920×1080 side monitors (usually 1.78×);
3. keep Windows scaling at 100% on all three monitors;
4. there is no need to leave the side monitors at 1440p by hand: the wrapper can enable and restore that mode during the session.

If the driver does not advertise the mode, the wrapper stops with an explicit message. It does not force a mode that the monitor or driver rejects.

## Usage

Close War Thunder first, then run:

```text
Run-WarThunderTripleScreen.cmd
```

The script detects the local installation, prepares the row, updates `config.blk`, opens the launcher and waits for the game window. When you quit War Thunder it restores the previous display layout.

If War Thunder is already open at `7680×1440` Windowed and you only need to remove the border and fix the position, run:

```text
Fix-Current-WarThunder-Window.cmd
```

This mode attaches to the existing window and corrects it to `x=-2560`, `y=0`, `7680×1440` in the reference layout. It does not change `config.blk`, does not change monitor resolutions and does not open another launcher.

Diagnosis without changing anything:

```powershell
.\WarThunderTripleScreen.ps1 -DryRun
```

Recover the monitor layout after an abrupt interruption:

```powershell
.\WarThunderTripleScreen.ps1 -RestoreDisplay
```

Restore the most recent `config.blk` backup:

```powershell
.\WarThunderTripleScreen.ps1 -RestoreConfig
```

The main options are in `WarThunderTripleScreen.ini`. Logs go to `logs`.

## Limitations

This is one very wide surface, not three independent cameras. The periphery may show geometric stretching and the HUD may sit far out. 7680×1440 is about 11.1 million pixels per frame.

## References

- X4 guide used as a base: https://www.reddit.com/r/X4Foundations/comments/1vfqbe5/guide_opensource_tool_mixedresolution_triple/
- BattlEye information published by Gaijin support: https://support.gaijin.net/hc/en-us/articles/21638218281362-BattlEye-anti-cheat-troubleshooting

<p align="center"><a href="https://dlforge.dungenlabs.com"><img src="branding/dlforge-logo.svg#gh-light-mode-only" alt="DL Forge" width="120"><img src="branding/dlforge-logo-negative.svg#gh-dark-mode-only" alt="DL Forge" width="120"></a></p>
