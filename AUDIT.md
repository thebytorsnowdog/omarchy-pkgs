# Packaging security audit

Audit of `thebytorsnowdog/omarchy-pkgs` at `7aa734313d2e03ca1c676b09863b47f00a571d3f` on 10 October 2026. That commit is `master`. It is behind `omacom/omarchy-pkgs`. An earlier draft of this note named `8084e2c2` and treated that omacom commit as this repository's master. The findings below were checked again on `7aa73431`.

No package was built. The review is static. No CVE identifier is used. No published advisory was matched to a component and version in this tree.

## Scope and method

Security and packaging hygiene only. Transport, pins, checksums, install hooks, permissions, and CI downloads that run with credentials. Kernel patch bodies are out of scope except where a `PKGBUILD` declares them as sources.

Method:

1. Checked out `origin/master` at `7aa73431`.
2. Read each `PKGBUILD` cited below, and ran `tests/pinned-sources.sh`. It reported 66 git sources, each with `#commit=` or `#tag=`.
3. Searched `.github/workflows` for `rclone-current` and for `actions/checkout`, `actions/upload-artifact`, `actions/download-artifact`, and `actions/github-script` tags.
4. For each remote file a pull request pins or checksums, downloaded it over HTTPS on 29 October 2026 and hashed it. Local checksums are `sha256sum` or `b2sum` of the files in this tree. rclone's zip hash also matches `https://downloads.rclone.org/v1.75.2/SHA256SUMS`.

Severity, from the evidence in this tree:

- **High.** The recipe installs or executes code that can change with no checksum, and that code is user shell config or a binary run next to publish credentials.
- **Medium.** A root-installed or remotely fetched input is `SKIP`, or a tag or action ref can move, and the effect is one package or the CI trust boundary.
- **Low.** An in-tree patch is `SKIP` while its main git source is already pinned to a commit.

`pkgrel` is bumped only where the pin can change which bytes a future build archives, `omarchy-zsh` and `omarchy-audio-tuner`. Checksum-only edits leave `pkgrel` alone, because the installed files do not change when the sums match. This repository does not rebuild a recipe until `pkgver` or `pkgrel` moves, so those checksums take effect on the next build of that package.

## What was checked

- 177 `pkgbuilds/*/PKGBUILD` files are in the tree. The files named in the findings were read.
- 45 `*.install` files and 8 `*.hook` files.
- 11 workflows under `.github/workflows/`.
- `tests/pinned-sources.sh`.
- There is no `.SRCINFO` in the tree.

## Findings

### 1. omarchy-zsh installs shell config from a moving branch

- **Severity.** High.
- **File.** `pkgbuilds/omarchy-zsh/PKGBUILD`
- **Evidence.** `source` contains `omadots.tar.gz::https://github.com/omacom-io/omadots/archive/refs/heads/master.tar.gz` with sha256 `SKIP`. `package()` copies `omadots-master/config/shell/` into `/usr/share/omarchy-zsh/shell`. On 29 October 2026, `master` was `556354683664f4143776296d76df75c0fa29059a`. The commit tarball's sha256 is `a9a043d4fcff6debf4899d92d56c632a5072de6259d5eed06189e19c5ef9ae2f`, and it contains `config/shell/`.
- **Why it matters.** The next build archives whatever `master` is that day. Nothing in this repository changes when that branch moves, and makepkg will not reject a substituted tarball.
- **Fix.** https://github.com/thebytorsnowdog/omarchy-pkgs/pull/2

### 2. The publish job runs a floating rclone binary next to the R2 keys

- **Severity.** High.
- **File.** `.github/workflows/publish.yml`
- **Evidence.** The publish log step downloads `https://downloads.rclone.org/rclone-current-linux-amd64.zip`, unzips `*/rclone`, and runs it. That step sets `RCLONE_CONFIG_R2_ACCESS_KEY_ID` and `RCLONE_CONFIG_R2_SECRET_ACCESS_KEY`. `promote.yml` and `release-rc.yml` are not in this tree. The v1.75.2 linux-amd64 zip sha256 is `349ac8fba6ff65d6247043f1750cdcb518ec5d500ef91463a10d37c0ccdf3702`, confirmed against the vendor `SHA256SUMS` and a local download on 29 October 2026.
- **Why it matters.** `rclone-current` is a name that moves. The job will execute whatever zip that URL serves, with the bucket credentials in the environment.
- **Fix.** https://github.com/thebytorsnowdog/omarchy-pkgs/pull/6

### 3. First-party GitHub Actions use floating tags

- **Severity.** Medium.
- **Files.** All 11 workflows under `.github/workflows/`. 29 `uses:` lines.
- **Evidence.** `actions/checkout@v4`, `actions/upload-artifact@v4`, `actions/download-artifact@v4`, and `actions/github-script@v7` are tags. `approve-pr.yml` has `actions: write`. `publish.yml` holds the R2 credentials. `track-branches.yml` is in this tree and uses the same floating tags. The git objects for those four tags are commits, resolved on 29 October 2026 to `11d5960a326750d5838078e36cf38b85af677262`, `ea165f8d65b6e75b540449e92b4886f43607fa02`, `d3f86a106a0bac45b974a628896c90dbdf5c8093`, and `f28e40c7f34bde8b3046d885e986cb6290c5673b`. `mitchellh/vouch` and `peter-evans/create-pull-request` in the same workflows are already commit-pinned.
- **Why it matters.** A moved tag changes the code that runs inside those jobs. This review did not observe a malicious action at those tags. The weakness is the mutable ref.
- **Fix.** https://github.com/thebytorsnowdog/omarchy-pkgs/pull/4

### 4. omarchy-audio-tuner follows a git tag

- **Severity.** Medium.
- **File.** `pkgbuilds/omarchy-audio-tuner/PKGBUILD`
- **Evidence.** `source=("git+https://github.com/omacom-io/omarchy-audio-tuner.git#tag=v$pkgver")` and `sha256sums=('SKIP')`. `v0.1.0` is a lightweight tag of `af7d91c4fac4c798bfeea358d64151c7496b3c33`. `git ls-remote` on 29 October 2026 returned that commit and no peeled tag object. `package()` installs `measure`, `fit`, `generate`, `compare`, and `omarchy-audio-tuner` from that clone. `tests/pinned-sources.sh` allows `#tag=`.
- **Why it matters.** A moved tag changes the tools the package installs. A git source cannot carry a real checksum, so the commit is the pin.
- **Fix.** https://github.com/thebytorsnowdog/omarchy-pkgs/pull/9

### 5. hyprland-protocols tarball is SKIP

- **Severity.** Medium.
- **File.** `pkgbuilds/hyprland-preview-share-picker/PKGBUILD`
- **Evidence.** The second source is `https://github.com/hyprwm/hyprland-protocols/archive/3a5c2bda1c1a4e55cc1330c782547695a93f05b2.tar.gz` with sha256 `SKIP`. `prepare()` symlinks that tree into the build. The downloaded tarball's sha256 is `00b2f15b8f383da4b6d111333c184a599ed5a9f51111243d0a88ddf7d7e498fb`. The commit is in the URL. makepkg does not check that the bytes match the git object.
- **Why it matters.** A substituted archive at that URL is what the build compiles.
- **Fix.** https://github.com/thebytorsnowdog/omarchy-pkgs/pull/5

### 6. Dell XPS touchpad helpers are SKIP

- **Severity.** Medium.
- **File.** `pkgbuilds/dell-xps-touchpad-haptics/PKGBUILD`
- **Evidence.** Six local sources, all `sha256sums=('SKIP' ...)`. `package()` installs the udev rule, `dell-xps-touchpad-haptics`, `dell-xps-touchpad-haptics-daemon` at mode `755`, and the systemd unit. The sha256 of each file was recomputed from this tree and matches pull request 1.
- **Why it matters.** Those files run as root via udev and systemd. Git records them. makepkg's integrity check does not.
- **Fix.** https://github.com/thebytorsnowdog/omarchy-pkgs/pull/1

### 7. qcom-firmware-extract is SKIP

- **Severity.** Medium.
- **File.** `pkgbuilds/qcom-firmware-extract/PKGBUILD`
- **Evidence.** `sha256sums=('SKIP' 'SKIP')` for `qcom-firmware-extract` and `README.package.md`. `package()` installs the script to `/usr/bin/qcom-firmware-extract` at mode `755`. The script copies firmware into `/usr/lib/firmware/updates` and can rebuild the boot image. Both sha256 values were recomputed from this tree.
- **Why it matters.** The script is root-operated package content with no makepkg checksum.
- **Fix.** https://github.com/thebytorsnowdog/omarchy-pkgs/pull/3

### 8. The aarch64 pkgbase shim is SKIP

- **Severity.** Medium.
- **File.** `pkgbuilds/linux-aarch64-pkgbase-shim/PKGBUILD`
- **Evidence.** `sha256sums=('SKIP' 'SKIP' 'SKIP')` for the hook, `linux-aarch64-pkgbase-shim`, and the README. `package()` installs the script to `/usr/share/libalpm/scripts/` at mode `755` and the hook under `/usr/share/libalpm/hooks/`. The script reads the pacman transaction from stdin and writes kernel metadata. The three sha256 values were recomputed from this tree.
- **Why it matters.** alpm hook scripts run as root during install and upgrade.
- **Fix.** https://github.com/thebytorsnowdog/omarchy-pkgs/pull/8

### 9. intel-ipu7-camera local sources are SKIP

- **Severity.** Medium.
- **File.** `pkgbuilds/intel-ipu7-camera/PKGBUILD`
- **Evidence.** `sha256sums` is 32 `SKIP` entries. The first five sources are `git+https://...#commit=`. Those stay `SKIP` because makepkg requires that for git. The other 27 are local patches, `camera-sleep-hook`, udev rules, and systemd units. `intel-ipu7-camera.install` runs `chmod 755` on `/usr/lib/systemd/system-sleep/camera-sleep-hook`. Each local sha256 was recomputed from this tree.
- **Why it matters.** The hook and udev rules run as root. The patches change the camera drivers this package builds. Git records the files. makepkg does not bind them.
- **Fix.** https://github.com/thebytorsnowdog/omarchy-pkgs/pull/7

### 10. The FocalTech libfprint patch is SKIP

- **Severity.** Low.
- **File.** `pkgbuilds/libfprint-git/PKGBUILD`
- **Evidence.** `source` is a git snapshot at commit `6f9479c3d55f847c1b3769f28ceb99227f9858cf`, `SKIP` as makepkg requires for git, and `focaltech_moc-add-pid-0xA97A.patch`, also `SKIP`. The aarch64 patch `aurora-apple-sep.patch` already has a b2sum. The FocalTech patch b2sum is `ebde45efd5306bd00e8f18e894da5ed4a1c3d1cff88ca7dd50893b2193cd0a262ae737af200d935271a5c85dcd7567c7d8b3b8a89d1b0870fa6e9e854115a2cb`.
- **Why it matters.** The patch is applied to the fingerprint library. A dirty-tree edit would still satisfy makepkg.
- **Fix.** https://github.com/thebytorsnowdog/omarchy-pkgs/pull/10

## Looked at, and left without a pull request

- **Claude Code licence page.** `pkgbuilds/claude-code/PKGBUILD` sets `sha256sums=('SKIP')` for `https://code.claude.com/docs/en/legal-and-compliance.md` and checksums the linux binaries. The page URL is unversioned. A checksum would fail the next build when that page changes. There is no versioned URL in the recipe to pin instead. No pull request.
- **omarchy-nvim plugin sync.** `pkgbuilds/omarchy-nvim/PKGBUILD` downloads `https://github.com/LazyVim/starter/archive/refs/heads/main.tar.gz`. `build()` then runs `nvim --headless "+Lazy! sync"` and `"+qa!" || true`. That fetches plugins during the build and keeps going if nvim returns non-zero. This review did not run nvim. Pinning every plugin is a new lockfile, which is outside a reversible checksum or pin. No pull request.
- **Git tags that also carry a non-SKIP checksum.** `gtk2`, `limine-mkinitcpio-hook`, `limine-snapper-sync`, and `omarchy-power-profiles-daemon` use `git+...#tag=` with a b2 or sha256 that is not `SKIP`. makepkg was not run, so this review did not confirm whether that sum is enforced on a git checkout. Replacing the tag with a commit without that proof could fail the build. `ollama` is not in this tree. No pull request.
- **walker and rustdesk cargo flags.** `pkgbuilds/walker/PKGBUILD` runs `cargo build --release`. `pkgbuilds/rustdesk/PKGBUILD` runs `cargo build` without `--locked` or `--frozen`. The source tarballs are checksummed. This review did not confirm that `Cargo.lock` is missing or stale, so `--locked` was not added.
- **Signed patches.** `linux-omarchy-muqss`, `linux-omarchy-eevdf`, and `linux-omarchy-bore` pair patches as `file.patch{,.sig}` and set `validpgpkeys` to the Torvalds, Kroah-Hartman, and Wilczynski keys. `linux-omarchy` in this tree has no `.patch` sources and no `validpgpkeys` array. `linux-omarchy-aarch64` and `linux-n1x` are not in this tree. `dropbox`, `spotify`, and `vi` set `validpgpkeys`. Spotify's `prepare()` checks the deb against the signed `Release` file. That pattern was left as it is. `helium-browser-bin` is not in this tree.
- **World-writable build directories.** `helpers/docker-helpers.sh` `make_dir_writable` runs `chmod -R 777`. `release-rc.yml` is not in this tree. A tighter mode was not shown to keep the builder image user able to write. No pull request.
- **asdcontrol sudoers.** `pkgbuilds/asdcontrol/asdcontrol.sudoers` denies `/usr/bin/asdcontrol` and then allows `%wheel` a `NOPASSWD` rule limited to `--detect` and a percentage on `hiddev` nodes. The rule is narrow. No pull request.
- **pull_request_target.** `approve-pr.yml` and `auto-merge-pr.yml` use `pull_request_target`. This review did not find a checkout of the pull request tree in those workflows.
- **import-gpg-keys.sh.** `build/import-gpg-keys.sh` curls any URL in `/build/gpg-keys.txt` into `gpg --import` and warns on failure. The only writer in this tree is `tests/build-isolation.sh`, which creates an empty file.

## What this review did not read

- The bodies of the 526 `*.patch` files. 150 are under `pkgbuilds/linux-omarchy-bore`, 149 under `pkgbuilds/linux-omarchy-muqss`, 149 under `pkgbuilds/linux-omarchy-eevdf`, and 19 under `pkgbuilds/uboot-asahi`. Packaging metadata for the sources named above was checked. Patch contents were not reviewed for code defects.
- The 448 `*.sig` files and 12 `*.asc` files, beyond the packages named above.
- The trees of pinned upstream git snapshots. Only the `PKGBUILD` pin was reviewed, plus the install scripts cited above.
- Line-by-line reading of every `PKGBUILD`. There are 177. Files named in the findings were read.
- A full `makepkg` build of any package.
- setuid and setgid bits. This recheck did not repeat that census.
