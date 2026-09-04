# Releasing

```bash
# bump core/tauri.conf.json "version", commit, then:
git tag v0.1.0 && git push origin v0.1.0
```

That runs `.github/workflows/release.yml`, which builds on macOS (Apple Silicon and
Intel) and Windows and opens a **draft** GitHub Release with the artefacts attached.
Review it, then publish. `workflow_dispatch` does the same thing without a tag.

**Check `latest.json` before publishing.** A complete-looking asset list is not proof
the updater manifest is complete — the builds share one `latest.json`, and a build can
upload its bundles and still fail to write its entry:

```bash
gh release download vX.Y.Z --pattern latest.json --dir /tmp/rel
python3 -c "import json;print(*json.load(open('/tmp/rel/latest.json'))['platforms'],sep='\n')"
```

Expect `darwin-aarch64`, `darwin-x86_64` and `windows-x86_64`, each with an `-app`,
`-msi` or `-nsis` twin. A missing platform means those users are offered no update at
all, silently. v0.8.0 shipped that way and had to be patched by hand; the matrix now
runs one target at a time so the writes cannot interleave.

Every ordinary CI run also uploads its bundles for 14 days, so a Windows installer is
downloadable from any commit without cutting a release.

## Windows

`tauri build` produces an NSIS installer (`.exe`). Nothing extra is required to
*build* it — CI already does, unsigned.

**Unsigned is the thing to decide.** Windows SmartScreen shows "Windows protected your
PC" and hides the Run button behind *More info*. Most people stop there. Options:

| | Cost | Effect |
| --- | --- | --- |
| Ship unsigned | free | SmartScreen warning on every download |
| OV certificate | ~$200–400/yr | Warning clears once the certificate builds reputation — weeks to months of downloads |
| EV certificate | ~$300–600/yr | Reputation is immediate; requires a hardware token or cloud HSM |

Signing needs a physical token or cloud signing service for EV, which does not fit a
plain GitHub Actions runner without extra setup (Azure Trusted Signing is the usual
answer). Configure it under `bundle.windows` in `core/tauri.conf.json`:
`certificateThumbprint`, `digestAlgorithm`, `timestampUrl`, or a custom `signCommand`.

Notchly needs no elevated permissions, so the installer runs per-user.

## macOS

Unsigned `.app` bundles downloaded from the internet are quarantined: macOS reports
the app as *damaged and should be moved to the Bin*, which is Gatekeeper's misleading
phrasing for "not notarised". Users can bypass it with
`xattr -dr com.apple.quarantine Notchly.app`, but that is not a distribution story.

Proper signing needs an Apple Developer account (\$99/yr) and these repository
secrets. They are **not** declared in `release.yml`: tauri-action runs
`security import` whenever they are present in the environment, and an unset secret is
an empty string, which fails the build. Add the `env:` block back at the same time as
the certificate.

- `APPLE_CERTIFICATE` — base64 of a Developer ID Application `.p12`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_SIGNING_IDENTITY` — e.g. `Developer ID Application: Your Name (TEAMID)`
- `APPLE_ID`, `APPLE_PASSWORD` (an app-specific password), `APPLE_TEAM_ID`

Notchly is not sandboxed and shells out for widget commands, so it is a Developer ID
app distributed outside the Mac App Store. It could not go to the App Store as it
stands: shell access for widgets alone would fail review.

## Updates

The Settings window can check for and install updates through Tauri's updater. Releases
must include updater metadata at the configured GitHub endpoint, and production bundles
must be signed with the private key corresponding to the public key in
`core/tauri.conf.json`. Configure `TAURI_SIGNING_PRIVATE_KEY` and
`TAURI_SIGNING_PRIVATE_KEY_PASSWORD` as GitHub Actions secrets. Generate a keypair with
`npx tauri signer generate`; keep the private key outside the repository.

## iOS

Not a target. See `CONTEXT.md` for the platform-independent domain model.
