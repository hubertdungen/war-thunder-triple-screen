# [Guide + open-source tool] Mixed-resolution triple monitors in War Thunder without NVIDIA Surround

Hi everyone,

I wanted to run War Thunder across three independent monitors: a native
2560x1440 centre and two physical 1920x1080 side displays, without NVIDIA
Surround.

The good news is that War Thunder already accepts a real 7680x1440 Windowed
surface once NVIDIA DSR/DLDSR exposes 2560x1440 on the two side displays. The
remaining problem was the normal Windows frame: the title bar consumed vertical
space, the game had to be positioned manually, and it never landed exactly on
the complete virtual desktop.

On my setup the requested 7680x1440 client was inside a 7686x1469 outer window,
positioned at x=-2518, with the rendered client starting 26 pixels below the top.
The exact borderless target is x=-2560, y=0, width=7680, height=1440.

I therefore built **War Thunder Triple Screen**, a small open-source external
Windows wrapper.

Download:
https://github.com/hubertdungen/war-thunder-triple-screen/releases

Source and documentation:
https://github.com/hubertdungen/war-thunder-triple-screen

## What it does

- detects the three-monitor row, coordinates, resolutions, refresh rates, and
  primary display automatically;
- checks that all target monitors use 100% Windows scaling (mixed scaling makes
  the wide Windowed surface grow or crop incorrectly);
- can temporarily select an already exposed 2560x1440 DSR/DLDSR mode on each
  physical 1080p side display;
- backs up and atomically updates War Thunder's normal `config.blk`;
- starts only through the official War Thunder launcher/BattlEye flow;
- waits for `aces.exe`, removes the normal title bar and frame, and applies the
  exact complete-desktop rectangle;
- uses bounded stabilization in case the game changes its window during startup;
- restores any temporary Windows display-mode changes after the game closes;
- includes a separate one-click **Fix Current Window** mode that can be run while
  War Thunder is already open. That mode changes no config or display settings.

## What it deliberately does not do

No DLL injection, DirectX hook, game-memory access, executable patching, gameplay
modification, BattlEye bypass, service, driver, stealth, or obfuscation. It is
plain-text PowerShell using the normal config file and top-level Windows APIs.
No independent tool can promise an anti-cheat outcome, so please read the source
and security notes before deciding whether to use it.

## Mixed 1440p + 1080p setup

1. Keep NVIDIA Surround disabled.
2. In NVIDIA Control Panel, enable the 1.78x DSR/DLDSR factor that exposes
   2560x1440 on each native 1920x1080 side display.
3. Set the centre to native 2560x1440 and both sides to effective 2560x1440.
4. Set Windows Scale to **100% on all three displays**. This is required; mixed
   100%/125% scaling breaks the wide Windowed geometry.
5. Align the three displays in one horizontal row with the centre as primary.
6. Close War Thunder and run `Run-WarThunderTripleScreen.cmd`, or start the game
   normally and run `Fix-Current-WarThunder-Window.cmd` to correct the existing
   window.

This is one very wide camera/render surface, not three separately projected
cameras. Far-edge stretching and wide HUD placement remain game limitations.
7680x1440 is roughly 11.1 million pixels per frame, so there is a real GPU cost.

This tool is the third game-specific result of the same mixed-resolution setup:

- X4 Foundations guide + tool:
  https://www.reddit.com/r/X4Foundations/comments/1vfqbe5/guide_opensource_tool_mixedresolution_triple/
- Star Citizen guide + external wrapper:
  https://www.reddit.com/r/u_huberkenobi/comments/1vglj65/guide_opensource_tool_mixedresolution_triple/

The project was built and tested with Codex as a development assistant. The
initial 7680x1440 result is verified on Windows 11 with a native 1440p centre and
two 1080p side monitors using NVIDIA DSR/DLDSR. Other layouts and sanitized logs
are welcome.

