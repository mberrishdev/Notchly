# Project settings

Values that live in `project.yml`, `Notchly/Info.plist`, and
`Notchly/Notchly.entitlements`, and why each one is set the way it is.

## Target

| Setting | Value | Why |
| --- | --- | --- |
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.mberrish.Notchly` | |
| `MACOSX_DEPLOYMENT_TARGET` | `26.0` | Lets the code drop every availability guard. |
| `ARCHS` | `arm64` | Apple Silicon only. |
| `SWIFT_VERSION` | `6.0` | |
| `SWIFT_STRICT_CONCURRENCY` | `complete` | Everything user-facing is `@MainActor`; the few pure helpers reachable off it are marked `nonisolated`. |
| `ENABLE_APP_SANDBOX` | `NO` | Custom widgets can be granted shell access, and the launcher reads other apps' bundles. |
| `ENABLE_HARDENED_RUNTIME` | `YES` | |
| `GENERATE_INFOPLIST_FILE` | `NO` | The plist is checked in, not synthesized. |

Versions live in `project.yml` as `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`. Don't
edit `project.pbxproj` directly — it is overwritten on the next `xcodegen generate`.

## Info.plist

| Key | Value | Why |
| --- | --- | --- |
| `LSUIElement` | `true` | Accessory app: no Dock tile, no menu bar of its own. |
| `LSApplicationCategoryType` | `public.app-category.utilities` | |
| `NSAppleEventsUsageDescription` | (see file) | Shown when the Now Playing widget first asks Music or Spotify what is playing. Without it macOS kills the process instead of prompting. |

## Entitlements

| Key | Why |
| --- | --- |
| `com.apple.security.automation.apple-events` | Required under the hardened runtime to send Apple events to Music and Spotify. |

Notchly asks for nothing else. In particular it does **not** request Accessibility
access: the global shortcut goes through Carbon's `RegisterEventHotKey`, which doesn't
need it. The one feature that would — synthesising media keys for players that can't be
scripted — degrades quietly if the access isn't there.

## Resources

`Notchly/Resources/ExampleWidgets` is added to the target as a **folder reference**, not
a group. Each example is a self-contained directory that has to survive into the bundle
with its structure intact, so it can be copied into the user's widgets folder on first
launch.

## Regenerating the project

```bash
xcodegen generate
```

Needed after adding, removing, or moving a source file. The app icon is generated too:

```bash
swift scripts/generate-icon.swift
```
