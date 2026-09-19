# Workshop preview tools

This folder is outside `Contents`, so none of these files are distributed with
the Project Zomboid mod.

## Build the GIF

Run `build-preview.cmd`. It reads the 512x512 mod poster from
`Contents\mods\AuthenticZBalloonLift\42\poster.png` and writes
`workshop-preview.gif` to the work root.

The builder uses Lanczos resizing, libimagequant through Sharp, a 256-color
palette, full Floyd-Steinberg dithering, and maximum encoder effort. It creates
two visually identical frames so Steam preserves the GIF format.

The Codex Node.js runtime already contains Sharp. On another machine, install
Node.js, run `npm install` once in this folder, then run `build-preview.cmd`.

## Upload the GIF

Start Steam and sign in, then run `upload-preview.cmd`. It validates the GIF and
uploads it to Project Zomboid Workshop item `3795345529` using app ID `108600`.

The uploader and its binaries now live in the repository-level
`tools/workshop-preview` folder. This folder's upload command forwards to it,
preserving Balloon Lift's defaults. Pass `-CheckOnly` to validate without uploading.

For another mod, use the shared uploader from the repository root:

```powershell
.\tools\workshop-preview\upload-preview.ps1 -PublishedFileId 3499163920 -Preview .\zodiac\artwork\poster.gif -CheckOnly
```

Omit `-CheckOnly` to upload after publishing the mod through Project Zomboid.
The shared uploader requires an explicit Workshop ID and GIF path; `-AppId`
defaults to `108600`. GIF dimensions are no longer restricted to 200x200.
The unchanged uploader binary is [SteamChangePreview](https://github.com/TechnologicNick/SteamChangePreview).
