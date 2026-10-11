# Native CEF transport (experimental)

`XToolsBridge.asi` replaces `diagnostics/cef_family_server.py` for an **already configured** X-Tools CEF installation. It retains the existing JavaScript adapter and file protocol; it does not add native CEF hooks or recognize additional dialog types. A new launcher installation still needs the existing React/JavaScript integration.

The 32-bit DLL is loaded from the game directory by the experimental Lua script. `DllMain` creates no threads. Lua calls `XTBridgeStart` after SA-MP is available. The module pins itself for process lifetime, so script reloads cannot unload code under its worker. All HTTP and file operations run in that worker; it never calls GTA or Lua. The listener binds only `127.0.0.1:18766`. Startup failure is reported via status (`-1` configuration, `-2` worker failure, `-3` port occupied), and the bridge does not replace another listener.

Configuration: `moonloader/X-TOOL/cef-bridge/transport.json`, with the existing 48-character hexadecimal `token`. Password delivery uses memory only, expires within four seconds, and is delivered once to the matching CEF session. Snapshot fields are allowlisted; input/password dialog styles are excluded. Explicit captures have a 20-minute policy and an 8 MiB file cap. Existing private captures are left in place.

## Build and test

Use the official portable Zig 0.13.0 Windows x86_64 compiler. Archive SHA-256:
`d859994725ef9402381e557c60bb57497215682e355204d754ee3df75ee3c158`.

```
python tools/build_cef_native.py --zig <path-to-zig.exe>
python tools/build_cef_family_dev.py
python tests/test_cef_native.py
```

The test host loads the real x86 DLL in a temporary directory, uses a separate port, and shuts down the worker explicitly. It does not load GTA. JSON parsing uses vendored nlohmann/json v3.11.3 under its included MIT license. The C++ runtime is linked statically; the module uses the Windows Universal CRT supplied with Windows 10/11. No compiler or Python installation is needed on the player's PC.

## Install / rollback

Close GTA and stop the old `cef_family_server.py` helper if still running. From PowerShell:

```
./tools/install_cef_native.ps1 -GameDirectory 'D:\Launcher\Advance Games'
```

The installer requires an existing CEF configuration, preserves backups, copies the DLL and experimental Lua artifact, verifies hashes, and disables `launcher.json` (the Python launch configuration). It does not modify launcher JavaScript. It does not include the standalone test host in the game.

For rollback, close GTA, restore the Lua and optional prior ASI from matching `.before-native-*.bak` files, restore `launcher.json` from its backup, and remove the newly installed ASI if none existed before. Do not hot-unload the bridge in GTA.

Native tests do not establish in-game stability. Verify `/sp`, background `/offst`, `/family`, and login in a fresh launcher session before releasing. The ordinary non-CEF release remains unchanged.
