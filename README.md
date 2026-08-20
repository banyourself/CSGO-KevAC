# KevAC

Server-side anti-cheat for CS:GO. Around 45 detectors, a reviewable ban queue, and a
whitelist you can scope to individual checks.

This is the plugin half. It needs the **KevAC extension** to be installed as well, which
lives in **CSGO-KevAC-Extension**. The extension reads a packet that SourcePawn cannot see,
and without it the single best detector in the project does not run.

## Install

Drop the `addons` folder into your `csgo` folder:

```
addons/sourcemod/plugins/KevAC.smx                 the compiled plugin
addons/sourcemod/scripting/KevAC.sp                source
addons/sourcemod/scripting/include/kevac.inc       include, if you compile it yourself
addons/sourcemod/configs/kevac/*.ini               whitelist, cheat cvar list, immunity list
addons/sourcemod/translations/kevac.phrases.txt    all player and admin facing text
addons/sourcemod/gamedata/kevac.games/             signatures and offsets
```

Then install the extension. SourceBans++ is optional, and any action set to `3` falls back
to a normal SourceMod ban when it is missing.

## Can one check catch every cheat?

No, and I would rather say so than oversell it. Cheats split three ways:

**Listener DLLs** register network event listeners. The extension catches these the moment
the client sends its first `CCLCMsg_ListenEvents`, so basically on join, with almost no way
to false positive. This is what people mean when they say an anti-cheat detects DLLs
instantly.

**Netcode, cvar and movement cheats** touch the wire, so the behavioral checks here pick
them up. A few of those are things a real client physically cannot send.

**Visual only cheats** (ESP, chams, anything that just reads memory and draws) send the
server nothing unusual. **You cannot catch these server side.** Not with this, not with any
SourceMod plugin. That is what client anti-cheats are for.

## Actions

Every detector has its own action cvar, same scale for all of them:

| Value | What happens |
|---|---|
| `-1` | off, the check does not run |
| `0` | log it |
| `1` | kick |
| `2` | SourceMod ban |
| `3` | SourceBans++ ban, falls back to SourceMod |

`0` is not silent, it still writes to admin chat. Use `-1` for anything you consider noise.

## How much to trust each detector

The tier decides how high you should set the action. This is the part I care most about,
because banning one innocent regular costs more than missing one cheater.

**Impossible for a real client.** Safe at any action. Angle clamp, because the client hard
clamps pitch to +/-89 and always sends roll 0. Anti duck delay, because `IN_BULLRUSH` in a
usercmd is a straight up cheat flag. Cheat cvar unlock, because `sv_cheats` is replicated, so
a client reporting a value the server did not set has patched its own cvar protection.

**Probably cheating, not provable.** Kick at most. Ghost strafe and synthetic move get fooled
by controller players sending analog movement. Duck macro cadence cannot separate a scroll
wheel from a macro on timing alone. Strafe sync and AHK strafe both break when a client is
lagging, because the server replays backup usercmds and consecutive commands legitimately
carry identical values.

**Heuristics.** Log only. Bhop streaks, scroll cadence, silent strafe, knifebot reaction
time, aimbot snap, triggerbot timing. Knifebot especially: the stab check compares present
time positions against the attacker's rewound view, which is the same geometry as a legit
high ping ghost stab.

Some of these are backed by real captures rather than guesses. The scripted bhop check, for
example, came from comparing a DLL capture against a human scroller: the DLL pressed `+jump`
exactly once per hop on the landing tick, while the human showed 435 of 508 jump edges while
airborne, against 0 of 28 for the DLL.

**Fake lag** gets its own note. It measures what the server received instead of what the
client claims, so it cannot be spoofed. Real packet loss destroys usercmds and leaves gaps in
the numbering, while fake lag only delays them, so the stream stays gapless but arrives in
fat periodic clumps. Strong evidence, still not proof, because a buffering router looks
identical. Off by default.

## Ban waves

`kevac_banwave 1` puts bans into a queue instead of firing them when the audit window closes.
An admin flushes the queue with `sm_kevac_execban confirm` after reviewing it.

This is what makes the middle tier usable. A detector I would normally only trust to kick can
sit at ban level, because a human sees the evidence first. It does not turn a weak detector
into a strong one, it just makes a mistake recoverable.

Detectors named in `kevac_banwave_exempt` skip the queue and ban immediately. Ghost input is
there by default, since a protocol impossibility has nothing for a human to second guess.

The queue is written to disk on every change, so a server crash does not lose it.

## Pre-ban audit capture

Before a ban-grade action lands, KevAC holds it briefly and writes the exact command stream
to a file, including a rolling buffer of the ticks **before** the flag. Without that buffer
the file only holds the aftermath and never the episode that caused the ban.

Ban reasons stay deliberately vague in public. Naming the detector tells a cheater exactly
what to fix. The vector goes to the admin side instead: the queue file, `sm_kevac_banqueue`,
the execban preview, and `KevAC_ban.log`.

## Whitelist

`configs/kevac/whitelist.ini` takes a bare SteamID to exempt someone from everything, or a
SteamID plus detector names to exempt them from just those:

```
STEAM_1:0:111                       everything
STEAM_1:0:222 DuckMacro             only DuckMacro, still bannable elsewhere
STEAM_1:0:333 DuckMacro,AHKStrafe   two of them
```

Names match the detector category as a prefix. Whitelisted hits still log and still alert
admins, it only skips the punishment.

## Commands

```
sm_kevac_execban confirm    flush the ban queue (bare form previews it)
sm_kevac_banqueue           list who is queued
sm_cancelban <target>       cancel a pending pre-ban before it lands
sm_kevac_whitelist          manage whitelist entries
sm_kevac_ext                extension telemetry, useful for checking the detour is alive
```

## Credits

Started from the open source **AntiDLL** by **JDW1337**:
[github.com/JDW1337/AntiDLL/releases](https://github.com/JDW1337/AntiDLL/releases). Not much
of it survives at this point, the detector set, the listener resolver and the extension were
rewritten or added, but credit for the starting point goes to him.

The listener blacklist in the extension is based on a list by **Wend4r**. Some detector ideas
came from **BASH2** (Blacky's Anti-Strafehack), from **Oryx** by shavitush
([github.com/shavitush/Oryx-AC](https://github.com/shavitush/Oryx-AC)) and from
**Little Anti-Cheat** by J-Tanzanite
([github.com/J-Tanzanite/Little-Anti-Cheat](https://github.com/J-Tanzanite/Little-Anti-Cheat)),
though the implementations here are more conservative than any of them.

Thanks to **zwolof** ([github.com/zwolof](https://github.com/zwolof)) as well.

## License

GPL-3.0, see `LICENSE`.
