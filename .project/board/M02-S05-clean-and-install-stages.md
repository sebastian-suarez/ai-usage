---
id: M02-S05
type: story
title: Clean and install stages
status: done
priority: P2
branch: ""
ghProjectItem: "PVTI_lAHOD4_w5c4BjzHmzg7aZLs"
github: "https://github.com/sebastian-suarez/ai-usage/issues/11"
---

The cross-project release standard (`/release-setup`) now requires two stages this
script doesn't have, and the gap is visible on disk: `build/` is 118 MB, `dist/` holds
13 MB of leftovers from a `9.9.10` test run, and this project has accumulated several
`~/Library/Developer/Xcode/DerivedData/AI_usage-*` directories. Nothing guarantees a
release is built from source rather than from whatever a previous run left behind.

**`clean`** wipes `dist/`, `build/` and this project's DerivedData — never all of
DerivedData, which belongs to every other project on the machine. `all` runs it first,
so every release starts from a wiped state. After a successful run only the finished
artifact remains in `dist/`; intermediates, staging dirs and mounts are gone, on
failure paths too.

**`install`** replaces the `/Applications` copy with the artifact just built — never a
rebuild. Stop the running app by PID (`osascript … to quit` can hang for a minute on a
freshly signed build), `rm -rf` the old bundle rather than copying over it, `ditto` the
new one in, then read `CFBundleShortVersionString` back from the installed copy and
assert it matches. It stays out of `all`: publishing and installing locally are
different intentions. Note that writing to `/Applications` may prompt for
authorization — if the environment refuses, print the commands rather than forcing it.

- [x] `clean` removes `dist/`, `build/` and this project's DerivedData only, is safe to run alone, and never touches tracked files
- [x] `all` begins with `clean`, so a release cannot inherit stale intermediates
- [x] After a successful run `dist/` contains the artifact and nothing else; failure paths leave no half-written artifact
- [x] `install` replaces the `/Applications` copy from the built artifact and asserts the installed version matches
- [x] `install` is not part of `all`, and `--dry-run` covers both new stages
- [x] README documents both stages

## Plan

> No child Task files. Like M02-S01 and M02-S03, this is one coherent unit of
> work — two new functions in one script plus the README section that documents
> them — sized for direct implementation, not a breakdown.

> **State of the machine at planning time (2026-07-21).** The mess the description
> above cites has already been deleted by hand: there is no `build/`, no `dist/`,
> and no `~/Library/Developer/Xcode/DerivedData/AI_usage-*` folder. `/Applications`
> contains no `AI usage.app` either — the first `install` will be a *first* install,
> not a replacement, and must handle that. Do not write code that assumes any of
> those paths exist. What *is* still true: PID 1324 is running the app from
> `…/AI usage/build/review-s03/Build/Products/Release/AI usage.app/Contents/MacOS/AI usage`,
> a path that no longer exists on disk — a live example of the stray-copy problem
> this story exists to stop.

> **Why this story matters more than disk space.** The trigger was Spotlight
> offering ~8 hits for "AI usage.app". Every DerivedData tree, every `build/`
> subdirectory and every `dist/work/<version>/export/` holds a real, indexable,
> launchable `.app` bundle, so each build multiplies the number of app copies the
> user can accidentally launch. Deleting build trees is the fix; `clean` and the
> post-`all` prune are how it stays fixed.

### Approach

**Add two stages to `scripts/release.sh` — `clean` at the front of the pipeline
and `install` outside it — and make the pipeline self-contained by pointing
every `xcodebuild` invocation at a DerivedData directory inside the tree `clean`
already deletes.** No signing, notarization, packaging or verification logic
changes: `stage_export`, `stage_package`, `stage_notarize`, `stage_staple` and
`stage_verify` keep every `codesign`, `hdiutil`, `notarytool`, `stapler` and
`spctl` invocation they have today, byte for byte. v1.0.2 was built, notarized
and published from this script hours ago; the diff must read as "added two
stages and a `-derivedDataPath` flag", never as "changed how the release is
signed or proven".

Decisions, each with the alternative rejected:

- **DerivedData is handled from *both* ends, not one.** The `/release-setup`
  macOS recipe offers two routes and frames them as alternatives; here they solve
  two *different* producers, and neither alone satisfies the acceptance criteria:
  - Route A, `-derivedDataPath "$REPO_ROOT/build/DerivedData"` on the two
    `xcodebuild` invocations that take `-project` (`stage_test`, `stage_archive`),
    contains everything the *release script* builds. **Verified during planning:**
    a full `xcodebuild test` with that flag exits 0 with the ad-hoc signing flags
    intact, and afterwards `~/Library/Developer/Xcode/DerivedData/` contains no
    `AI_usage-*` folder at all — even `ModuleCache.noindex` and `SDKStatCaches.noindex`
    relocate under the given path. The run produced 206 MB under `build/`,
    including `build/DerivedData/Build/Products/Debug/AI usage.app` and
    `…/AI usageUITests-Runner.app` — two more indexable app bundles that `rm -rf build/`
    now removes deterministically.
  - Route B, deleting `~/Library/Developer/Xcode/DerivedData/AI_usage-*`, is the
    only thing that removes what **Xcode.app itself** creates. The README tells
    users to open the project in Xcode and press ⌘R; the IDE ignores the script's
    `-derivedDataPath` entirely. Most of the ~950 MB the user deleted by hand, and
    most of the duplicate Spotlight hits, came from the IDE, not from this script.
  Route A alone would leave AC1's "this project's DerivedData" unmet for the
  common case. Route B alone would leave the script itself writing into the shared
  DerivedData root every run, so `clean` would keep having to reach outside the
  repo to undo the script's own mess. Doing both makes release builds
  self-contained *and* gives `clean` a way to sweep the IDE's cache.
- **Route B identifies its targets by `WorkspacePath`, not by the glob.** Each
  DerivedData project folder contains an `info.plist` with a `WorkspacePath` key
  holding the absolute path of the `.xcodeproj` it was built from — confirmed on
  this machine for the three unrelated projects currently there (`Race_engineer-…`,
  `Claude_Code_swap-…`). A folder is deleted only when that value equals
  `"$REPO_ROOT/$PROJECT"` exactly. The `AI_usage-*` glob narrows the candidates;
  the plist match is what authorizes the `rm -rf`. Rejected: trusting the glob
  alone — the name is derived from the project's *name*, so a same-named project
  in another directory (a second clone, a worktree, a scratchpad copy — the
  `Claude_Code_swap-*` folders above show exactly that pattern happening on this
  machine) would be silently destroyed. Also rejected: asking `xcodebuild
  -showBuildSettings` for the authoritative path — several seconds per run, needs
  a resolved scheme and destination, and breaks the standard's "`clean` alone must
  be safe and instant".
- **Candidates that match the glob but not the workspace are reported, never
  deleted.** A folder left over from this project at an *older path* is
  indistinguishable from a different project of the same name, so `clean` prints
  the path and the workspace it belongs to and moves on. The user gets an exact
  `rm -rf` target to run by hand if they want it. Rejected: deleting on a name
  match with a `--force` escape hatch — a destructive default with a flag to
  disarm it is the wrong way round for a shared directory owned by every project
  on the machine.
- **"Only the artifact survives" is enforced at the end of a successful `all`
  run, not inside `stage_verify`.** After `all`, `dist/work/<version>/` is removed
  so `dist/` holds only `AI-usage-<version>.dmg`. Two reasons it lives in `main()`
  rather than in the last stage: `stage_verify` must stay byte-identical (it is
  release-proving logic and the story's constraint forbids touching it), and every
  stage gate in this script reads a file its predecessor wrote — a prune inside
  `verify` would break `scripts/release.sh verify` as a standalone re-check for
  everyone. Explicit partial chains (`export package`, `notarize staple verify`)
  therefore keep their intermediates and stay re-runnable exactly as today; only
  the complete, self-declared `all` run prunes. That is also literally what AC3
  asks for ("after a successful run"). Rejected: pruning after any chain ending in
  `verify` — one rule fewer, but it silently disarms the "any stage re-runs safely
  on its own" property the previous story was built around.
- **`install` sources the app from the DMG in `dist/`, not from
  `dist/work/<version>/export/`.** This is what makes the prune above safe:
  `all` then `install` works because the artifact is the only input. It also
  matches the standard exactly — the DMG is what a consumer receives, so installing
  from it is the closest local equivalent to a real install, and there is no code
  path in which `install` can rebuild anything. Rejected: gating `install` on
  `$STAPLED_MARKER`/`$EXPORTED_APP`, which would make `install` impossible after
  the very run that produced the release.
- **`install` fails *before* it touches anything when `/Applications` is not
  writable.** Order is: check the artifact exists → probe `/Applications` for real
  write access (`mktemp -d` there, then `rmdir`) → mount the DMG → stop the running
  app → `rm -rf` → `ditto` → detach → assert. The probe is the point: a POSIX `-w`
  test can pass while TCC or an agent sandbox still denies the write, and
  discovering that *after* deleting the installed bundle is precisely the
  half-replaced install the standard warns about. On refusal the stage prints the
  exact commands for the user to run in Terminal and exits non-zero, having changed
  nothing. Rejected: escalating with `sudo` or `osascript … with administrator
  privileges` — a release script must never silently acquire privileges, and an
  agent cannot answer the prompt anyway.
- **The running copy is stopped by PID, with an anchored pattern.**
  `pgrep -f '^/Applications/AI usage\.app/Contents/MacOS/'` → `kill` (TERM) → wait
  up to 5 s → `kill -9` → fail if anything survives. `osascript … to quit` is
  banned: `.project/memory` and the macOS recipe both record it hanging for a
  minute on a freshly signed build (AppleEvent timeout −1712). The app is
  `LSUIElement = YES` — no Dock icon, no window — so nothing that looks at the Dock
  or at windows can detect it; a PID signal is indifferent to that. The `^` anchor
  is a guard, not decoration: **verified during planning** that it does not match
  PID 1324, which is running the same app from a `build/` path, while an unanchored
  pattern does. `install` must only ever stop the copy it is about to replace.
- **Other running copies are reported, never killed.** After a successful install,
  any process whose command line contains `AI usage.app/Contents/MacOS/` but does
  not start with `/Applications/` gets a one-line note naming its PID and path.
  That is the user's cue that a stale build-tree copy is still in the menu bar
  (PID 1324 today). Killing them is out of scope — `install` owns the
  `/Applications` copy and nothing else.
- **The version assertion is a hard failure; the build number is a warning.**
  `CFBundleShortVersionString` read back from the installed bundle must equal
  `$VERSION` or the stage fails — that assertion is the entire point of the stage.
  `CFBundleVersion` is compared too but only warns, because `BUILD` is derived from
  `git rev-list --count HEAD` in the *current* checkout while the DMG may have been
  built at an earlier commit (it will differ in step 11's proof run, which uses the
  CI-built 1.0.2 artifact). A hard failure there would punish the normal case.
- **`codesign --verify` after install is a hard failure; `spctl --assess` is
  informational.** `codesign --verify --deep --strict` proves `ditto` produced an
  intact bundle — a real integrity check, worth failing on. `spctl` is printed with
  its verdict but never fails the stage: the macOS recipe notes that an app
  installed to `/Applications` carries no quarantine flag, so this path does not
  exercise Gatekeeper the way `verify` does with a synthetic quarantine copy, and
  a signed-but-not-yet-notarized DMG (the only kind that can be produced locally
  under this story's guardrail) would make it fail for a reason that says nothing
  about the install. Notarization is proven in `verify`, on the artifact, once.
- **`clean` and `install` join a single ordered stage list.** `PIPELINE_STAGES`
  becomes the one source of truth for stage order and rank; `STAGE_ORDER` (what
  `all` expands to) is the same list minus `install`. `stage_rank`'s hand-written
  `case` block, which already duplicates `STAGE_ORDER` today, is replaced by a
  lookup over `PIPELINE_STAGES`. Rejected: adding two more arms to the `case` block
  — it would leave three parallel lists to keep in sync, which is the exact drift
  the release standard exists to prevent. The argument parser's `case` arm keeps an
  explicit literal list (bash `case` patterns cannot be built from an array); it
  gets a comment pointing at `PIPELINE_STAGES` and both must be updated together.
- **`install` ranks after `verify`, so `verify install` chains in order and `all
  install` is still rejected** (`all` must be used by itself — unchanged rule).
  `clean install` is accepted by the ordering rule and then fails cleanly on the
  missing artifact; that is an acceptable, self-explanatory footgun, not worth a
  special case.
- **`--dry-run clean` enumerates the DerivedData candidates for real.** It reads
  `info.plist` and prints `[dry-run] rm -rf <path>` for folders it would delete and
  the skip line for the rest. This is a local, read-only inspection — no network,
  no credential, no external service — and it is the only way a user can confirm a
  destructive glob is aimed correctly *before* running it. Rejected: printing an
  opaque "would scan DerivedData" line, which makes the one genuinely dangerous
  command in the script unauditable.
- **CI needs no change.** `.github/workflows/release.yml` calls
  `scripts/release.sh all` and nothing else; `clean` is a no-op on a fresh runner,
  `-derivedDataPath` writes into the ephemeral workspace, and the post-`all` prune
  removes `dist/work/` *before* the `gh release create "$GITHUB_REF_NAME" dist/*.dmg`
  step — which makes that glob unambiguous rather than breaking it. Do not edit the
  workflow file in this story.

### Files to touch

- `scripts/release.sh` — all script changes. Stays executable, keeps
  `#!/usr/bin/env bash` and `set -euo pipefail`.
- `README.md` — the `## 📦 Release` section: stage list, the Mermaid flowchart,
  and a new subsection on installing locally.

Explicitly **not** touched: `.github/workflows/release.yml` (see above),
`scripts/ExportOptions.plist`, `AI usage.xcodeproj/project.pbxproj`, `.gitignore`
(`build/`, `dist/` and `DerivedData/` are already ignored — verify with
`git check-ignore -v build/DerivedData` rather than editing).

### Steps

**1. Add the path globals and wire `-derivedDataPath` into the two project-scoped
`xcodebuild` invocations.**

In the constants block near the top:

```bash
# Xcode derives this from the project's name; the WorkspacePath check below is
# what actually authorizes deletion, so this only narrows the candidate list.
readonly DERIVED_DATA_PREFIX="AI_usage"
```

Declare `BUILD_DIR=""`, `DERIVED_DATA_PATH=""` and `DERIVED_DATA_ROOT=""` with the
other globals, and set them in `resolve_release_metadata()` next to `DIST_DIR`:

```bash
BUILD_DIR="$REPO_ROOT/build"
DERIVED_DATA_PATH="$BUILD_DIR/DerivedData"
DERIVED_DATA_ROOT=""
if [[ -n "${HOME:-}" && -d "${HOME:-}" ]]; then
    DERIVED_DATA_ROOT="$HOME/Library/Developer/Xcode/DerivedData"
fi
```

An empty `HOME` must leave `DERIVED_DATA_ROOT` empty, never
`/Library/Developer/Xcode/DerivedData`.

Add `-derivedDataPath "$DERIVED_DATA_PATH"` to **both branches** (dry-run and real)
of `stage_test`'s `xcodebuild test` and `stage_archive`'s `xcodebuild archive`.
Leave the ad-hoc signing overrides (`CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=-
DEVELOPMENT_TEAM=`) exactly where they are — they are build-setting overrides and
are independent of where DerivedData lives. Do **not** add the flag to
`xcodebuild -exportArchive`: it is invoked without `-project`, has no project
context, and needs no DerivedData.

*Verify:* `scripts/release.sh --dry-run all` prints the flag in the test and
archive commands and nowhere else.

**2. Add `remove_project_derived_data()`.**

```bash
remove_project_derived_data() {
    local project_path="$REPO_ROOT/$PROJECT"
    local candidate
    local name
    local workspace

    if [[ -z "$DERIVED_DATA_ROOT" || ! -d "$DERIVED_DATA_ROOT" ]]; then
        return 0
    fi

    for candidate in "$DERIVED_DATA_ROOT/$DERIVED_DATA_PREFIX"-*; do
        [[ -d "$candidate" ]] || continue                      # unmatched glob stays literal
        name="${candidate##*/}"
        [[ "$name" =~ ^AI_usage-[A-Za-z0-9]+$ ]] || continue
        [[ "${candidate%/*}" == "$DERIVED_DATA_ROOT" ]] || continue

        workspace=""
        if [[ -f "$candidate/info.plist" ]]; then
            workspace="$("$PLIST_BUDDY" -c 'Print :WorkspacePath' "$candidate/info.plist" 2>/dev/null || true)"
        fi

        if [[ "$workspace" == "$project_path" ]]; then
            if [[ "$DRY_RUN" -eq 1 ]]; then
                dry_command rm -rf "$candidate"
            else
                rm -rf "$candidate"
                echo "Removed Xcode DerivedData: $candidate"
            fi
        else
            echo "Leaving '$candidate' in place (built from '${workspace:-an unknown workspace}')." >&2
        fi
    done
}
```

Every one of those four guards is load-bearing: the `-d` test handles bash's
literal unmatched glob, the regex rejects any name carrying a `/`, a space or a
`..`, the parent check rejects anything that escaped the root, and the
`WorkspacePath` equality is the actual authorization. `$DERIVED_DATA_ROOT` itself
must never be an `rm -rf` argument.

*Verify* with decoys, before `stage_clean` exists — create
`~/Library/Developer/Xcode/DerivedData/AI_usage-decoyaaaaaaaaaaaaaaaaaaaaaa` with an
`info.plist` whose `WorkspacePath` is `/tmp/somewhere/AI usage.xcodeproj`, and
`AI_usage-mineaaaaaaaaaaaaaaaaaaaaaaaa` with `WorkspacePath` set to this repo's
real `.xcodeproj` path. Source the script (`BASH_SOURCE` guard makes that safe),
set the globals by hand, and call the function: the second must be deleted, the
first must survive with its skip line printed, and the three real project folders
already in that directory (`Race_engineer-…`, `Claude_Code_swap-…`) must be
untouched. Delete any surviving decoy afterwards.

**3. Add `stage_clean()`.**

```bash
stage_clean() {
    log "clean"

    [[ -n "$REPO_ROOT" && "$REPO_ROOT" != "/" ]] || \
        fail "refusing to clean: the repository root was not resolved"
    [[ -n "$DIST_DIR" && -n "$BUILD_DIR" ]] || \
        fail "refusing to clean: output directories were not resolved"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        dry_command rm -rf "$DIST_DIR"
        dry_command rm -rf "$BUILD_DIR"
        remove_project_derived_data
        return 0
    fi

    rm -rf "$DIST_DIR"
    rm -rf "$BUILD_DIR"
    remove_project_derived_data
    echo "Cleaned $DIST_DIR, $BUILD_DIR and this project's Xcode DerivedData."
}
```

`clean` has no predecessor gate, reads no credential and touches nothing outside
those three locations. Note in the code comment that it deletes previously built
DMGs too — `dist/` is a build output, not an archive.

*Verify:* `git status --porcelain` is byte-identical before and after
`scripts/release.sh clean` on a dirty-free tree, and the command completes in well
under a second.

**4. Register `clean` in the stage table.**

Replace the `STAGE_ORDER` declaration and `stage_rank()` with:

```bash
# Single source of truth for stage order. `all` runs every stage except install.
PIPELINE_STAGES=(clean test archive export package notarize staple verify install)
readonly PIPELINE_STAGES
STAGE_ORDER=(clean test archive export package notarize staple verify)
readonly STAGE_ORDER

stage_rank() {
    local index=0
    local candidate

    for candidate in "${PIPELINE_STAGES[@]}"; do
        if [[ "$candidate" == "$1" ]]; then
            printf '%s\n' "$index"
            return 0
        fi
        index=$((index + 1))
    done

    fail "unknown stage '$1'"
}
```

Add `clean` and `install` to the argument parser's stage `case` arm
(`clean|test|archive|export|package|notarize|staple|verify|install)`) with a
comment tying it to `PIPELINE_STAGES`, and add both names to `usage()`'s
`Stages:` line.

*Verify:* `scripts/release.sh --dry-run clean` runs; `scripts/release.sh test clean`
is rejected with "release stages must be requested in pipeline order";
`scripts/release.sh all clean` is rejected with "all must be used by itself";
`scripts/release.sh clean clean` is rejected as a repeat; `scripts/release.sh bogus`
still prints usage and "unknown stage or option 'bogus'".

**5. Prune the intermediates after a successful `all`.**

Set a `run_is_all=1` local in `main()` inside the existing
`if [[ "${stages[0]}" == "all" ]]` branch, and after the stage-dispatch loop:

```bash
if [[ "$run_is_all" -eq 1 ]]; then
    prune_intermediates
fi
```

```bash
prune_intermediates() {
    [[ -n "$WORK_DIR" && -n "$DIST_DIR" && -n "$VERSION" ]] || return 0

    if [[ "$DRY_RUN" -eq 1 ]]; then
        dry_command rm -rf "$WORK_DIR"
        dry_shell "rmdir '$DIST_DIR/work' 2>/dev/null || true"
        return 0
    fi

    rm -rf "$WORK_DIR"
    rmdir "$DIST_DIR/work" 2>/dev/null || true
    echo
    echo "Removed the release intermediates under $DIST_DIR/work."
    echo "Only the artifact remains: $DMG_PATH"
}
```

Reaching that line means every stage succeeded — `set -e` plus the `cleanup` trap
exit before it otherwise. `rmdir` (not `rm -rf`) on the shared `work` parent so a
concurrent version's directory is never destroyed.

*Verify* in step 11 with a real `--dry-run all` (prints both commands) and by
inspecting `dist/` after the archive/export/package proof — see there for why a
real `all` must not be run.

**6. Add the install support globals, helpers and cleanup handling.**

New globals, declared with the others and used only by `install`:

```bash
INSTALL_MOUNT_DIR=""
INSTALL_DMG_ATTACHED=0
INSTALL_PROBE_DIR=""
INSTALL_INCOMPLETE_TARGET=""
```

Extend `cleanup()` with blocks mirroring the existing `MOUNT_DIR` handling: detach
`INSTALL_MOUNT_DIR` when attached, `rm -rf` it when not, `rmdir`
`INSTALL_PROBE_DIR` if it survived, and — only on a non-zero exit — `rm -rf
"$INSTALL_INCOMPLETE_TARGET"` guarded by
`[[ "$INSTALL_INCOMPLETE_TARGET" == "/Applications/$APP_NAME" ]]`, printing what it
removed and that the previous version is gone. Separate globals rather than reusing
`MOUNT_DIR`/`DMG_ATTACHED` so a `verify install` chain cannot leak the first
stage's mountpoint. Use `rmdir` for the probe: nothing under `/Applications` gets
`rm -rf` except the app bundle itself.

Add `pgrep` to `validate_environment`'s required-tool list.

`print_install_manual_steps()` — an **unquoted** heredoc (it interpolates
`$DMG_PATH` and `$APP_NAME`, so runtime shell variables inside it must be written
`\$MNT`):

```
Cannot write to /Applications from this environment. Nothing was changed.
Run these commands in Terminal as the logged-in user:

  MNT=$(mktemp -d /tmp/ai-usage-install.XXXXXX)
  hdiutil attach -readonly -nobrowse -mountpoint "$MNT" "<dmg path>"
  pkill -f '^/Applications/AI usage\.app/Contents/MacOS/' || true
  rm -rf "/Applications/AI usage.app"
  ditto "$MNT/AI usage.app" "/Applications/AI usage.app"
  hdiutil detach "$MNT"
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
      "/Applications/AI usage.app/Contents/Info.plist"
```

`stop_installed_app()` — anchored `pgrep`, TERM, poll ≤ 5 s in 0.1 s steps, then
KILL, then fail if anything survives. Report the PIDs it signals. No running copy
is a normal, non-fatal outcome. **Never write `pgrep … && fail …` as a bare
statement**: under `set -e` a failing AND-list aborts the script, so every such
check must be an `if` block.

`report_stray_copies()` — for each PID from `pgrep -f 'AI usage\.app/Contents/MacOS/'`,
read `ps -o command= -p "$pid"`, skip anything starting with `/Applications/`, and
print a note naming the PID and path. Always returns 0.

**7. Add `stage_install()`.**

Real path, in this order (each step must not run if an earlier one failed):

```bash
target="/Applications/$APP_NAME"
[[ -s "$DMG_PATH" ]] || fail "release artifact was not found at '$DMG_PATH'; run 'scripts/release.sh all' first"
if [[ -e "$target" && ! -d "$target" ]]; then
    fail "'$target' exists but is not an app bundle; remove it by hand first"
fi
# writability preflight — before anything is stopped or deleted
if [[ ! -w /Applications ]]; then print_install_manual_steps >&2; fail "/Applications is not writable"; fi
INSTALL_PROBE_DIR="$(mktemp -d /Applications/.ai-usage-install.XXXXXX 2>/dev/null)" || {
    print_install_manual_steps >&2
    fail "could not write to /Applications; nothing was changed"
}
rmdir "$INSTALL_PROBE_DIR"; INSTALL_PROBE_DIR=""
# mount before stopping the app, so a bad DMG costs nothing
INSTALL_MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ai-usage-install.XXXXXX")"
hdiutil attach -readonly -nobrowse -mountpoint "$INSTALL_MOUNT_DIR" "$DMG_PATH" >/dev/null
INSTALL_DMG_ATTACHED=1
[[ -d "$INSTALL_MOUNT_DIR/$APP_NAME" ]] || fail "mounted disk image does not contain '$APP_NAME'"
stop_installed_app
INSTALL_INCOMPLETE_TARGET="$target"
rm -rf "$target"
ditto "$INSTALL_MOUNT_DIR/$APP_NAME" "$target"
INSTALL_INCOMPLETE_TARGET=""          # the copy completed; a later assertion failure
                                      # leaves the bundle in place for inspection
hdiutil detach "$INSTALL_MOUNT_DIR" >/dev/null
INSTALL_DMG_ATTACHED=0
[[ -f "$target/Contents/Info.plist" ]] || fail "install did not produce '$target'"
installed_version="$("$PLIST_BUDDY" -c 'Print :CFBundleShortVersionString' "$target/Contents/Info.plist")" || \
    fail "could not read the installed app's version"
[[ "$installed_version" == "$VERSION" ]] || \
    fail "installed app reports version '$installed_version', expected '$VERSION'"
```

then the build-number warning (non-fatal), `codesign --verify --deep --strict
--verbose=2 "$target"` (fatal), `spctl --assess --type execute --verbose=4
"$target"` captured and printed with a warning instead of a failure on rejection,
`report_stray_copies`, and a final `Installed: <target> (<version>)` line. When no
previous copy existed, say so — a first install is normal, not an anomaly.

The `--dry-run` branch prints every one of those commands via `dry_command`/
`dry_shell` with `<temporary-install-mount>` and `<pids>` placeholders, in the same
order, and must not mount, signal, delete, copy or probe anything.

**8. Register `install` in the parser and `usage()`** — already added to
`PIPELINE_STAGES` in step 4 and deliberately absent from `STAGE_ORDER`.

*Verify:* `scripts/release.sh --dry-run install` prints the full command list;
`scripts/release.sh --dry-run all` never mentions `stage_install`;
`scripts/release.sh --dry-run verify install` runs both in that order;
`scripts/release.sh --dry-run install verify` is rejected as out of order.

**9. Update `help()`.**

Add to the stage list, keeping the existing two-space/column layout:

```
  clean      remove dist/, build/ and this project's Xcode DerivedData
  …
  all        run every stage above in order, starting with clean
  install    replace /Applications/AI usage.app with the built DMG (not in all)
```

and add short paragraphs stating that: `all` begins with `clean`, so a release
never inherits stale intermediates and Xcode's own cache for this project is
cleared too (the next Xcode build recompiles); a successful `all` leaves only
`dist/AI-usage-<version>.dmg`, so individual stages cannot be re-run afterwards
without rebuilding; and `install` needs write access to `/Applications`, printing
manual commands and changing nothing if it is denied. Keep every existing line of
`help()` and the shared `print_notary_setup` heredoc untouched.

**10. Update the README's `## 📦 Release` section.**

- Insert `scripts/release.sh clean` at the head of the per-stage command list.
- Add one sentence after the `all` paragraph: `all` starts with `clean` (wiping
  `dist/`, `build/` and this project's Xcode DerivedData) and finishes by removing
  `dist/work/`, so the only thing left behind is the DMG.
- Replace the flowchart with the version below — note every label is quoted, which
  the `/Applications` node needs to avoid being parsed as a shape delimiter:

  ````markdown
  ```mermaid
  flowchart LR
      CL["clean<br/>dist/ + build/ + DerivedData"] --> T["xcodebuild test"]
      T --> A["xcodebuild archive"]
      A --> E["xcodebuild -exportArchive<br/>Developer ID signing"]
      E --> P["hdiutil create<br/>DMG + Applications symlink"]
      P --> N["notarytool submit --wait"]
      N --> S["stapler staple"]
      S --> V["stapler validate + spctl --assess"]
      V --> D[("dist/AI-usage-version.dmg")]
      D -. "scripts/release.sh install" .-> I["/Applications/AI usage.app"]
  ```
  ````

- Add a short `### Installing the build you just made` subsection: what `install`
  does (mounts the DMG in `dist/`, stops the running copy by PID, removes the old
  bundle, `ditto`s the new one in, reads the version back and asserts it), that it
  is deliberately not part of `all`, that it never rebuilds, and that it prints
  manual commands and changes nothing if `/Applications` is not writable. Mention
  that the installed copy carries no quarantine flag, so `verify` — not `install` —
  is what proves Gatekeeper will accept the release.

Human-first prose, `why` before `how`, per AGENTS.md's documentation style.

**11. Prove it locally, in this order.**

> **Guardrail: never run `notarize`, and never run a bare `all` without
> `--dry-run`.** This Mac has a live `AI-usage-notary` keychain profile, so a real
> run would fire an actual Apple submission that is permanent in the account's
> history. `clean`, `test`, `archive`, `export`, `package`, `install` and any
> `--dry-run` are all safe.

```bash
scripts/release.sh --help                       # both new stages documented
scripts/release.sh --dry-run all                # clean first, install absent, prune printed
scripts/release.sh --dry-run clean
scripts/release.sh --dry-run install
scripts/release.sh clean                        # real; then check git status is unchanged
scripts/release.sh test archive export package  # real; proves -derivedDataPath end to end
ls ~/Library/Developer/Xcode/DerivedData/       # no AI_usage-* folder must appear
ls dist dist/work/1.0.2                         # intermediates present: a partial chain keeps them
scripts/release.sh clean                        # wipe the locally signed, unnotarized DMG
gh release download v1.0.2 --pattern 'AI-usage-1.0.2.dmg' --dir dist   # the CI-notarized artifact
scripts/release.sh install                      # real install from that DMG
```

The published v1.0.2 release carries `AI-usage-1.0.2.dmg` and `MARKETING_VERSION`
is `1.0.2`, so the downloaded artifact lands at exactly the path `install` expects
and is genuinely notarized — which is what makes the `spctl` line meaningful and
the version assertion honest. Downloading a published asset is read-only; do not
create, edit or publish any release. Expect the build-number warning to fire (the
DMG was built at the v1.0.2 tag, `main` has since advanced) — that is the designed
behavior, not a defect. Run `install` a second time to prove the replace path with
a previous copy present, and confirm it reports stopping the PID it started.

Leave `/Applications/AI usage.app` installed afterwards; that is the stage working,
not a side effect to undo. Do not kill PID 1324 — `report_stray_copies` flagging it
is the expected output, and quitting it is the user's call.

**12. Final read-through before committing.** `git diff` over `stage_export`,
`stage_package`, `stage_notarize`, `stage_staple` and `stage_verify` must be empty
except for nothing at all — if any of those five functions changed, revert that
hunk. Check every new `"$VARIABLE"` is quoted (the `AI usage` space is a proven
failure mode in this repo), that no new bare `cmd && fail …` statement exists, and
that `bash -n scripts/release.sh` parses. Commit in small conventional commits with
`Board: M02-S05` in the body.

### Test plan

Mapped to the acceptance criteria checklist:

- **AC1 — `clean` removes `dist/`, `build/` and this project's DerivedData only,
  is safe alone, never touches tracked files.** Step 2's decoy test is the proof
  that "only" holds: a same-named folder belonging to another workspace survives,
  the one pointing at this checkout is deleted, and the three unrelated project
  folders already in that directory are untouched. Step 3's `git status --porcelain`
  comparison proves no tracked file moves. Step 11's real `clean` proves it runs
  alone from any state, including the current one where none of the three targets
  exist.
- **AC2 — `all` begins with `clean`.** Step 4 puts `clean` at index 0 of
  `STAGE_ORDER`; step 11's `--dry-run all` shows it as the first stage executed,
  before `test`.
- **AC3 — after a successful run `dist/` holds the artifact and nothing else;
  failure paths leave no half-written artifact.** Step 5's `prune_intermediates`,
  shown by `--dry-run all` in step 11 (a real `all` is barred by the notarization
  guardrail). The failure half is already carried by the existing
  `INCOMPLETE_DIR`/`INCOMPLETE_FILE` trap machinery, which step 12 confirms is
  unchanged; step 6 extends the same pattern to `install` with
  `INSTALL_INCOMPLETE_TARGET`, so a `ditto` that dies mid-copy leaves no partial
  bundle in `/Applications`.
- **AC4 — `install` replaces the `/Applications` copy from the built artifact and
  asserts the version.** Step 11 installs the notarized 1.0.2 DMG and then runs
  `install` a second time against an existing copy, exercising both the first-install
  and the replace path plus the PID stop. The assertion is proven negatively too:
  temporarily point `--version` at a value the DMG does not carry
  (`scripts/release.sh --version 9.9.10 install` against the 1.0.2 DMG) and confirm
  it fails on the missing artifact path rather than installing anything — and, to
  prove the version check itself, re-run `install` after copying the 1.0.2 DMG to
  `dist/AI-usage-9.9.10.dmg`; it must fail with "installed app reports version
  '1.0.2', expected '9.9.10'" and leave the bundle in place. Delete that stray file
  afterwards with `scripts/release.sh clean`.
- **AC5 — `install` is not part of `all`, and `--dry-run` covers both new stages.**
  Step 8's four dry-run invocations: `install` absent from `--dry-run all`, present
  and complete in `--dry-run install`, orderable after `verify`, rejected before it.
  Step 11 runs `--dry-run clean` and `--dry-run install` from a state where `dist/`,
  `build/` and DerivedData do not exist, proving both work from a clean checkout.
- **AC6 — README documents both stages.** Step 10, checked by reading the rendered
  section: `clean` in the stage list and in the `all` description, the flowchart
  showing `clean` first and `install` branching off the artifact, and the new
  install subsection.

### Risks / open questions

- **The `AI_usage-*` glob is the one genuinely dangerous line in this story.** Four
  independent guards stand between it and an `rm -rf` (directory test, anchored
  regex, parent-equality, `WorkspacePath` match), and `$DERIVED_DATA_ROOT` is never
  itself an argument to `rm`. The decoy test in step 2 exists specifically so a
  reviewer can see the negative case pass. Treat any simplification of those guards
  as a regression.
- **A same-named project at a different path is only skipped, never cleaned.** If
  the user later finds `AI_usage-*` folders that `clean` refuses to delete, they are
  either from an older path of this project or from a genuinely different project —
  the skip line names the workspace so the user can decide. This is deliberate; the
  alternative is a glob that can eat another project's cache.
- **`clean` now wipes Xcode's own cache for this project, so the next IDE build
  recompiles from scratch.** Releases are rare and correctness beats a warm cache,
  but it will be noticeable the first time. Documented in `--help` and the README
  rather than hidden behind a flag.
- **Every `all` run now compiles from zero** (`clean` removes
  `build/DerivedData`). Measured during planning: a full test build from an empty
  DerivedData took roughly a minute and produced 206 MB. That cost is the point of
  the stage.
- **A partial chain that stops before `verify` still leaves a complete-looking DMG
  in `dist/`** — for example an `all` run that fails at `notarize` leaves a signed
  but unnotarized `AI-usage-<version>.dmg`. The stage gates make it unusable to the
  script (`staple` demands an accepted submission JSON), but a human browsing
  `dist/` could mistake it for a release. Pre-existing behavior, unchanged by this
  story, called out so a reviewer does not read it as a new defect.
- **`install` cannot be proven against a notarized artifact without the network.**
  Step 11 downloads the published v1.0.2 DMG precisely because the local guardrail
  forbids notarizing. If that download is unavailable, run `install` against a
  locally packaged DMG instead and expect the `spctl` line to report a rejection —
  which is why it is a warning rather than a failure. Say so explicitly in the
  implementation report rather than describing `install` as fully proven.
- **Keychain ACL prompts** (same standing risk as M02-S01/S03): the first
  `codesign` in a new process context can raise an "Allow" dialog that no script can
  dismiss. If step 11's `package` stalls with no output, one interactive "Always
  Allow" click unblocks it.
- **`/Applications` write access in the Codex sandbox is the open unknown.**
  `-s danger-full-access` should permit it and the POSIX check currently passes for
  this user, but TCC can still refuse. If the probe trips, that *is* the designed
  behavior — report the printed manual commands and treat AC4 as proven only by the
  dry-run plus whatever the user runs by hand. Do not work around it with `sudo`.
- **PID 1324 is running from a deleted path.** `report_stray_copies` should flag it
  during step 11. Leave it running; it is live evidence the reporting works and the
  user has not asked for it to be quit.

### Codex handoff

Branch: `build/clean-and-install-stages` (created from `main` during planning;
`main` is clean and matches `origin/main`).

```
codex exec -m gpt-5.6-sol -c model_reasoning_effort=ultra -s danger-full-access \
  "Read AGENTS.md, then implement the plan in .project/board/M02-S05-clean-and-install-stages.md on branch build/clean-and-install-stages."
```

(`-s danger-full-access` is required: Codex's `workspace-write` sandbox mounts
`.git` read-only, so `git switch`/`git commit` fail without it — see
`.project/memory/codex-sandbox-git.md`. This story additionally needs write access
to `~/Library/Developer/Xcode/DerivedData` and `/Applications`, plus keychain and
network access for the `package` and `gh release download` steps, none of which
`workspace-write` allows.)

**Do not run `scripts/release.sh notarize`, and do not run `all` without
`--dry-run`** — the live `AI-usage-notary` profile would make it a real, permanent
Apple submission.
