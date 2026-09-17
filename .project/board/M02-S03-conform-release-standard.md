---
id: M02-S03
type: story
title: Conform release script to the standard
status: done
priority: P2
notion: "3a4ea0aa-87b0-81ab-a683-cacaf3afb520"
ghProjectItem: "PVTI_lAHOD4_w5c4BjzHmzg7aZF0"
github: ""
parent: "[[M02-signed-release-distribution]]"
---

`scripts/release.sh` predates the cross-project release standard (`/release-setup`)
and deviates from it in four ways: it is one-shot rather than staged, it takes the
version as a required argument instead of reading `MARKETING_VERSION` from the
manifest, it writes to `build/release/` instead of `dist/`, and it has no `--dry-run`
or `--help`. The pipeline works — this story is about making it the same shape as
every other project's, so the user doesn't relearn a second dialect.

Behavior must not regress: the Developer ID signing, DMG packaging, notarization,
stapling and the Gatekeeper verification are already proven and stay exactly as they
are. This is a restructuring of the interface around them, not a rewrite of the
pipeline. M02-S02's CI workflow depends on the credential contract
(`NOTARY_PROFILE`, `ASC_KEY_PATH`/`ASC_KEY_ID`/`ASC_ISSUER_ID`) — it must survive
unchanged.

- [x] Stages run individually (`test`, `archive`, `export`, `package`, `notarize`, `staple`, `verify`) and in order via `all`, each gated by its predecessor's output file so re-runs are safe
- [x] `--dry-run` prints every command without touching the network, Apple, or the keychain, and works from a clean checkout
- [x] `--help` documents prerequisites, one-time credential setup, and where the artifact lands
- [x] Version is read from `MARKETING_VERSION` and never written by the script; an explicit override remains available for test builds
- [x] Artifacts land in a gitignored `dist/`, named `AI-usage-<version>.dmg`
- [x] The credential contract and every existing verification step behave exactly as before

## Plan

> No child Task files: like M02-S01 (and every M01 story), this is one
> coherent unit of work — a single script and a single README section —
> sized for direct implementation, not a breakdown.

### Approach

**Restructure `scripts/release.sh` from one linear pipeline into eight
functions (`stage_test`, `stage_archive`, `stage_export`, `stage_package`,
`stage_notarize`, `stage_staple`, `stage_verify`, plus `all` as pure
expansion) behind a subcommand dispatcher, moving every existing check to
the stage bucket it already conceptually belongs to.** No signing,
notarization or verification *logic* changes — every `xcodebuild`,
`codesign`, `hdiutil`, `notarytool`, `stapler` and `spctl` invocation from
the current script is preserved verbatim, just relocated into a named
function. This is the load-bearing constraint of the whole plan: the diff
should read as "moved code into functions and changed where version/output
come from," never as "changed what a check verifies."

Key decisions, each with the alternative rejected:

- **Version comes from `MARKETING_VERSION` via a grep/sort-uniq extraction
  over `project.pbxproj`** (adapted directly from
  `~/Projects/Claude Code swap/Scripts/release.sh`'s
  `extract_marketing_version`, just pointed at this repo's pbxproj path),
  failing loudly if the six occurrences ever disagree. Rejected: reading it
  with `agvtool` or `xcodebuild -showBuildSettings` — both shell out to a
  much slower `xcodebuild` invocation just to read one string that `grep`
  gets in milliseconds, and `-showBuildSettings` needs a resolved
  scheme/destination that not every stage has reason to compute.
- **`--version X.Y.Z` is a flag override, not a positional argument**,
  validated with the same `^[0-9]+\.[0-9]+(\.[0-9]+)?$` regex the script
  already uses, and it prints a stderr warning every time it's used
  ("real releases must come from MARKETING_VERSION"). This satisfies the
  standard's "override allowed for test builds only, must not be how real
  releases get their number" — a flag that's easy to forget you passed
  is exactly the failure mode the warning exists to catch.
- **Build number keeps today's derivation, unchanged: `git rev-list --count
  HEAD` by default, `--build N` overrides it (replacing the old positional
  2nd argument).** M02-S01 chose this deliberately for determinism and
  monotonicity without a state file; nothing about conforming the
  *interface* to the standard calls that into question, and the acceptance
  criteria only ask about *version*, not build. Rejected: reading
  `CURRENT_PROJECT_VERSION` from the manifest the way the sibling project's
  `extract_current_project_version` does — that field is a static `1` in
  this project's pbxproj (never hand-maintained), so reading it would
  silently stop the build number from incrementing, a real regression.
- **Intermediate build products live under a version-namespaced
  `dist/work/<version>/`** (`AIUsage.xcarchive`, `export/`, `.tested`,
  `notarize-result.json`, `.stapled`); only the final
  `dist/AI-usage-<version>.dmg` sits at the top level. This is the one
  structural idea neither prior-art script needed: because `--version` can
  make two different invocations resolve two different version strings,
  an *unnamespaced* work directory would let a stale archive built under
  one version silently satisfy a later stage's gate check computed under a
  different version — a real metadata/filename mismatch bug. Namespacing by
  version makes that class of bug structurally impossible: a gate check for
  version B simply never sees an artifact that was only ever built for
  version A. Rejected: a single flat `dist/work/`, matching the sibling
  script — fine for that project (no override exists there), wrong here.
- **Keychain-touching checks move from "always, upfront" to "only in the
  stage that needs them," skipped entirely under `--dry-run`.** The
  Developer ID identity check (`security find-identity`) moves into
  `stage_export` (that's when signing actually happens); the notarization
  credential probe (`xcrun notarytool history`) moves into
  `stage_notarize`. Consequence: `scripts/release.sh test` or `archive` now
  run with zero keychain interaction, which they never needed anyway.
  **To avoid regressing the "missing credentials fail in under a second,
  before any build work" guarantee for a full run**, `main()` resolves and
  validates notarization credentials once, up front, whenever `notarize` is
  anywhere in the resolved stage list (i.e. for `all` or any explicit chain
  that includes it) — *before* dispatching to the first stage — so `all`
  still fails in seconds on a bad profile instead of after minutes of
  test/archive/export/package. `stage_notarize` also re-validates
  credentials itself when reached, so it stays correct when invoked alone;
  running the same cheap check twice inside one `all` invocation is an
  accepted, deliberate simplicity trade — not a bug to dedupe.
  Tool-*existence* checks (`command -v xcodebuild hdiutil codesign spctl
  ditto`, `xcrun --find notarytool/stapler`) touch nothing and stay global
  and unconditional (dry-run included), same as today.
- **DMG stays DMG** (not the sibling project's zip) — dictated by AC5
  directly, and the current, twice-shipped format is exactly what stays
  proven. A DMG can hold a staple ticket directly, so (unlike the zip flow,
  which must notarize-then-staple the `.app` and re-zip separately for
  distribution) one file threads through package → notarize → staple →
  verify unchanged, matching today's script exactly.
- **All "does this actually work for a consumer" checks — mount content,
  `spctl --assess` on a synthetic-quarantine copy — stay in `verify`, the
  last stage.** But the codesign/hardened-runtime check right after export,
  and the DMG's own signature/`hdiutil verify` check right after packaging,
  **stay put in `export`/`package` respectively**, not moved to `verify`.
  Moving them would be a real regression: a badly-signed export would
  currently fail in seconds; deferring that discovery to the final `verify`
  stage would let a broken export waste a full notarization round-trip
  (minutes) before anyone found out.
- **JSON parsing stays `python3 -c`, not `jq`** (the sibling project uses
  `jq`). macOS ships `python3`; introducing a `jq` dependency for a
  restructuring story that must not change behavior is unjustified risk.
- **Shebang changes from `#!/bin/bash` to `#!/usr/bin/env bash`** — the
  standard's literal requirement; zero behavioral effect on this Mac, just
  explicit conformance.
- **Multiple stage names may be chained in one invocation**
  (`scripts/release.sh export package`), matching the sibling script's
  `main()` loop exactly — cheap to support, useful for resuming a run after
  fixing something mid-pipeline, not required by the acceptance criteria
  but harmless prior art to keep consistent.

### Files to touch

- `scripts/release.sh` — full rewrite into the staged form described below.
  Stays executable (`chmod +x`).
- `.gitignore` — add `dist/` in the "# Build artifacts" block:

  ```
  # Build artifacts
  build/
  dist/
  DerivedData/
  ```
- `README.md` — replace the entire `## 📦 Release` section (between
  `## 🚀 Getting started` and `## 🏗️ How it works`) with:

  ````markdown
  ## 📦 Release

  `scripts/release.sh` turns a checkout into a signed, notarized DMG anyone
  can install with Gatekeeper's blessing — the same script runs here and in
  CI (see M02-S02). It reads the version straight from the Xcode project
  (`MARKETING_VERSION`) and never edits it; bumping the version for a real
  release is always its own commit, made before cutting the release.

  ### One-time setup

  The Developer ID signing certificate must already be in your keychain.
  Notarization needs its own credentials, stored once — either an Apple ID
  app-specific password:

      xcrun notarytool store-credentials "AI-usage-notary" \
        --apple-id "<your-apple-id-email>" \
        --team-id "KGVLNXZJNX" \
        --password "<app-specific password from appleid.apple.com>"

  or an App Store Connect API key, stored the same way:

      xcrun notarytool store-credentials "AI-usage-notary" \
        --key "<path-to-AuthKey.p8>" \
        --key-id "<key-id>" \
        --issuer "<issuer-id>"

  Either works through the profile above. To skip the keychain profile
  entirely (e.g. in CI), export `ASC_KEY_PATH`, `ASC_KEY_ID` and
  `ASC_ISSUER_ID` with the same API key values instead.

  ### Cutting a release

      scripts/release.sh all

  runs every stage in order and produces `dist/AI-usage-<version>.dmg` —
  tested, archived, signed with the Developer ID identity, packaged with an
  `/Applications` symlink, notarized and stapled. `<version>` comes from
  `MARKETING_VERSION`, never from the command line.

  Each stage also runs on its own, gated by the previous stage's output so
  any of them can be re-run in isolation:

      scripts/release.sh test
      scripts/release.sh archive
      scripts/release.sh export
      scripts/release.sh package
      scripts/release.sh notarize
      scripts/release.sh staple
      scripts/release.sh verify

  `scripts/release.sh --dry-run all` prints every command the pipeline would
  run without touching the network, Apple, or the keychain — safe on a
  clean checkout with nothing set up. `scripts/release.sh --help` documents
  every flag and prerequisite.

  ```mermaid
  flowchart LR
      T[xcodebuild test] --> A[xcodebuild archive]
      A --> B[xcodebuild -exportArchive<br/>Developer ID signing]
      B --> C[hdiutil create<br/>DMG + Applications symlink]
      C --> D[notarytool submit --wait]
      D --> E[stapler staple]
      E --> F[stapler validate + spctl --assess]
  ```
  ````
- Do **not** touch: `AI usage.xcodeproj/project.pbxproj` (no version bump,
  no scheme changes), `scripts/ExportOptions.plist` (unchanged, still
  referenced by path from the export stage), any file under `AI usage/`
  (app source), `.project/board/M02-S01-release-script.md` /
  `M02-S04-lower-deployment-target.md` (closed items — their `build/release`
  references are historical record, not to be retconned).

### Steps

Every step is independently checkable; later steps depend on earlier ones.
`REPO_ROOT`/`SCRIPT_DIR` resolution, the "is this a valid checkout"
sanity check, `DEVELOPER_DIR` default, and the `cleanup()` EXIT trap
(`STAGING_DIR`/`MOUNT_DIR`/`DMG_ATTACHED`/`SCRATCH_DIR`/`NOTARY_ERROR_FILE`)
all carry over from the current script unchanged — they're not tied to any
one stage.

1. **Foundation + CLI skeleton.** Shebang → `#!/usr/bin/env bash`. Add
   constants `DIST_DIR="$REPO_ROOT/dist"`, `STAGE_ORDER=(test archive export
   package notarize staple verify)`. Add `extract_marketing_version()`
   (grep `MARKETING_VERSION = [^;]*;` from `"AI usage.xcodeproj/project.pbxproj"`,
   `sort -u`, fail if more than one distinct value, `sed` out the value —
   adapt directly from the sibling project's `extract_marketing_version`).
   Add version/build resolution: `--version`/`--build` flags override,
   else `extract_marketing_version` / `git rev-list --count HEAD`; validate
   with the existing regexes; a `--version` use always prints the stderr
   warning. Compute `WORK_DIR="$DIST_DIR/work/$VERSION"` and the other
   per-run paths (`ARCHIVE_PATH`, `EXPORT_DIR`, `EXPORTED_APP`,
   `TESTED_MARKER="$WORK_DIR/.tested"`, `DMG_PATH="$DIST_DIR/AI-usage-$VERSION.dmg"`,
   `SUBMISSION_JSON="$WORK_DIR/notarize-result.json"`,
   `STAPLED_MARKER="$WORK_DIR/.stapled"`) once version is known. Write
   `usage()`/`help()` covering: the 8 stage names with one-line
   descriptions, `--dry-run`/`--version`/`--build`/`-h`/`--help`, the
   version/output-location sentence, and the full credential-setup text
   (reuse the current script's `print_notary_setup` content — same
   function, called from both `--help` and the notarize credential
   failure path, so the two can never drift apart). Parse argv in one loop
   (flags and stage names in any order, matching the sibling script's
   `main()`); expand any `all` into `STAGE_ORDER`; reject unknown
   stage/flag names with usage + exit 1; keep global tool-existence checks
   (`command -v git xcodebuild hdiutil codesign spctl ditto xcrun python3
   xattr grep tee readlink security`, `xcrun --find notarytool/stapler`,
   `PlistBuddy -x`) unconditional. Then: if `notarize` is anywhere in the
   resolved stage list and `--dry-run` is not set, call
   `resolve_notary_auth_args` (see step 6) before the dispatch loop starts;
   finally loop over the resolved stages calling `"stage_$s"`.
   Verify: `scripts/release.sh --help` prints the full text; `bash -n
   scripts/release.sh` passes; `scripts/release.sh bogus-stage` fails fast
   with usage; `scripts/release.sh` (no args) prints usage and exits 1.
2. **`stage_test`.** No gate (first stage). Real run: `mkdir -p
   "$WORK_DIR"`; `xcodebuild test -project "AI usage.xcodeproj" -scheme "AI
   usage" -destination 'platform=macOS' -only-testing:"AI usageTests"`;
   on success `touch "$TESTED_MARKER"`. Dry run: print both commands,
   `return 0` before anything else, no gate check. Does not clear anything
   downstream (a fresh test run never invalidates an existing archive).
   Verify: `scripts/release.sh test` exits 0 and creates
   `dist/work/<version>/.tested` (all M01 tests are green per M01's
   closure).
3. **`stage_archive`.** Gate: `$TESTED_MARKER` exists, else fail with "run
   `scripts/release.sh test` first". Clears downstream: `rm -rf
   "$EXPORT_DIR"`, `rm -f "$DMG_PATH" "$SUBMISSION_JSON"
   "$STAPLED_MARKER"`. Real run: `rm -rf "$ARCHIVE_PATH"`; `xcodebuild
   archive -project "AI usage.xcodeproj" -scheme "AI usage" -configuration
   Release -archivePath "$ARCHIVE_PATH" MARKETING_VERSION="$VERSION"
   CURRENT_PROJECT_VERSION="$BUILD"`; then the existing `PlistBuddy`
   version/build proof against the archived Info.plist (fail if either
   doesn't match) — identical logic to the current script.
   Verify: `scripts/release.sh test archive` produces the `.xcarchive`;
   `PlistBuddy -c 'Print :CFBundleShortVersionString'` /
   `:CFBundleVersion` on it match `$VERSION`/`$BUILD`; `git status`/`git
   diff -- "AI usage.xcodeproj/project.pbxproj"` clean before and after.
4. **`stage_export`.** Gate: `$ARCHIVE_PATH` exists, else fail with "run
   `archive` first". Clears downstream: `rm -f "$DMG_PATH"
   "$SUBMISSION_JSON" "$STAPLED_MARKER"`. Real run: `rm -rf
   "$EXPORT_DIR"`; `xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH"
   -exportPath "$EXPORT_DIR" -exportOptionsPlist
   "$SCRIPT_DIR/ExportOptions.plist"`; check `$EXPORTED_APP` exists; *then*
   (real run only) `security find-identity -v -p codesigning` grep-checked
   for `"$SIGNING_IDENTITY"` (fail fast if absent), followed by `codesign
   --verify --deep --strict --verbose=2 "$EXPORTED_APP"` and the
   Authority/`flags=0x10000(runtime)` grep on `codesign -dvv` output — all
   identical to the current script's step 8, just run here instead of
   globally.
   Verify: `scripts/release.sh export` (after step 3) produces `dist/work/<version>/export/AI usage.app`;
   both codesign checks pass; confirm `scripts/release.sh export` on a
   machine/session with no signing identity fails within seconds with the
   custom message, not a raw `xcodebuild` error (can defer this specific
   sub-check to step 11 if easier to arrange there).
5. **`stage_package`.** Gate: `$EXPORTED_APP` exists, else fail with "run
   `export` first". Clears downstream: `rm -f "$SUBMISSION_JSON"
   "$STAPLED_MARKER"`. Real run: fresh `STAGING_DIR="$(mktemp -d
   "${TMPDIR:-/tmp}/ai-usage-dmg.XXXXXX")"`; `ditto "$EXPORTED_APP"
   "$STAGING_DIR/$APP_NAME"`; `ln -s /Applications
   "$STAGING_DIR/Applications"`; `mkdir -p "$DIST_DIR"`; `rm -f
   "$DMG_PATH"`; `hdiutil create -volname "AI usage" -srcfolder
   "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"`; check `-s "$DMG_PATH"`;
   `codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"`;
   `codesign --verify --verbose=2 "$DMG_PATH"`; `hdiutil verify
   "$DMG_PATH"` — identical to the current script's DMG block, just
   pointed at `$DIST_DIR`/`$DMG_PATH` instead of `build/release`.
   Verify: `scripts/release.sh package` produces
   `dist/AI-usage-<version>.dmg`, non-trivially sized; both codesign/hdiutil
   checks on the DMG pass.
6. **`stage_notarize`.** Gate: `-s "$DMG_PATH"`, else fail with "run
   `package` first". Add `resolve_notary_auth_args()` (sets a global
   `AUTH_ARGS` array): identical logic to the current script's lines
   146–176 — ASC three-var priority check (all-or-none-set), keychain
   file-exists check for `ASC_KEY_PATH`, else `NOTARY_PROFILE` default
   `AI-usage-notary`, probed via `xcrun notarytool history "${AUTH_ARGS[@]}"`,
   printing `print_notary_setup` and exiting 1 on any failure. Real run:
   clear `rm -f "$STAPLED_MARKER"`; `xcrun notarytool submit "$DMG_PATH"
   "${AUTH_ARGS[@]}" --wait --timeout 2h --output-format json | tee
   "$SUBMISSION_JSON"` (pipefail-safe exit code capture); parse
   `status`/`id` via the existing `json_field` python3 helper; on non-
   `Accepted` fetch and `cat` the notarytool log, then fail — identical to
   the current script's lines 248–272.
   Verify (safe to run for real, no submission involved): `NOTARY_PROFILE=does-not-exist
   scripts/release.sh notarize` (no `ASC_*` set) exits non-zero within a
   few seconds with the exact `print_notary_setup` text, before any
   `notarytool submit` call.
7. **`stage_staple`.** Gate: `$SUBMISSION_JSON` exists and its `status`
   field (via `json_field`) is `Accepted`, else fail with "run `notarize`
   first". Real run: `xcrun stapler staple "$DMG_PATH"`; `xcrun stapler
   validate "$DMG_PATH"`; `touch "$STAPLED_MARKER"`.
8. **`stage_verify`.** Gate: `$STAPLED_MARKER` exists, else fail with "run
   `staple` first". Real run, identical to the current script's steps
   12: mount `$DMG_PATH` read-only to a fresh `mktemp -d` mountpoint,
   confirm `"$MNT/$APP_NAME"` is a directory and `"$MNT/Applications"` is a
   symlink resolving to `/Applications`, detach; then `ditto` a fresh
   scratch copy of `$EXPORTED_APP`, `xattr -w com.apple.quarantine
   "0083;$(printf '%x' "$(date +%s)");Safari;"` on it, `spctl --assess
   --type execute --verbose=4` on the scratch copy, grep for `accepted`
   and `source=Notarized Developer ID`. No output file (last stage).
9. **README.** Replace `## 📦 Release` with the block in Files to touch.
   Verify: Mermaid renders; every command/profile name/env var matches the
   script's actual defaults exactly (copy-paste must work verbatim).
10. **Dry-run proof, from as clean a state as practical** (e.g. `rm -rf
    dist` first): `scripts/release.sh --dry-run all` prints all eight
    stages' commands in order and exits 0, touching neither `dist/` nor
    the network/keychain (confirm via `git status`/`ls dist 2>&1` showing
    nothing created, and no keychain-prompt/notarytool network activity).
    Also run `scripts/release.sh --dry-run notarize` alone and confirm it
    does *not* call `xcrun notarytool history`.
11. **Individual real-stage proof, no notarization involved**: `test` →
    `archive` → `export` → `package` in sequence, confirming each one's
    gate check fails correctly when run alone from a clean `dist/` (e.g.
    `rm -rf dist && scripts/release.sh export` fails with "run archive
    first" before touching Xcode), and each marker/artifact appears where
    step 2–5 say it should. This is also where to confirm `export`'s
    identity-check fail-fast (temporarily irrelevant if the identity is
    always present on this Mac — if so, just confirm the check's grep
    logic by inspection plus the fact `export` currently succeeds).
12. **The one real end-to-end run.** Notarization submissions are
    permanent in the user's Apple account and this Mac's `notarytool
    history` already has several — spend exactly one more:
    `scripts/release.sh --version 0.0.2-test all` (a version override
    keeps it obviously a test artifact in Apple's history, same pattern as
    the existing `9.9.9` entry from M02-S01). Confirm: notarization
    `status: Accepted`, `stapler validate` passes, the Gatekeeper
    assessment on the quarantined scratch copy reports `accepted` and
    `source=Notarized Developer ID` — the same proof M02-S01 already
    established, now reproduced through the new staged entry points.
13. **Final hygiene.** `git status`/`git diff -- "AI usage.xcodeproj/project.pbxproj"`
    clean; `git status` shows `dist/` untracked-and-ignored (`git check-ignore
    -v dist` reports the new `.gitignore` line); `scripts/release.sh
    --help`'s credential instructions and defaults match what steps 6/12
    actually used, verbatim.

### Test plan

Mapped to the acceptance criteria checklist:

- **AC1 (stages run individually and via `all`, gated by predecessor
  output)**: Steps 2–8 build the eight functions; step 11 proves each
  gate rejects a missing predecessor from a clean `dist/`; step 12's `all`
  run proves the full chain end to end.
- **AC2 (`--dry-run`: prints everything, touches nothing, works from a
  clean checkout)**: Step 10, run against a `dist/`-free tree.
- **AC3 (`--help` documents prerequisites, credential setup, artifact
  location)**: Step 1's verify clause plus a manual read of the final
  `usage()`/`help()` text (step 13's verbatim check).
- **AC4 (version from `MARKETING_VERSION`, never written, override for
  test builds)**: Step 3's `PlistBuddy` reads plus the pbxproj diff check;
  step 12 uses `--version 0.0.2-test` and step 13 confirms the pbxproj is
  still untouched afterward.
- **AC5 (artifacts in gitignored `dist/`, named `AI-usage-<version>.dmg`)**:
  Step 5 produces the file at that exact path; step 13's `git
  check-ignore` confirms it's ignored.
- **AC6 (credential contract + every existing verification step unchanged)**:
  Step 6's fail-fast-with-bad-profile check (same behavior as M02-S01's
  original proof, same message); step 12's real run exercises the actual
  `NOTARY_PROFILE`/`ASC_KEY_*` resolution end to end; every codesign/
  spctl/stapler check from the original script reappears in steps 4, 5, 8
  with identical commands and identical pass criteria.

**Do not run a second real `notarize`/`all` invocation beyond step 12** —
each submission is permanent in the Apple account's history and this Mac
already has several from M02-S01/S04. If step 12 fails for a reason
unrelated to this restructuring (e.g. a transient network error), re-running
`scripts/release.sh notarize` alone (same DMG, already packaged) is fine;
re-running the *entire* `all` chain a second time is not something this
story needs and should be avoided.

### Risks / open questions

- **Versioned `dist/work/<version>/` is new** (neither prior-art script
  needed it — the sibling has no `--version` override to guard against).
  Flagging explicitly so a reviewer recognizes it as a deliberate fix for a
  real staleness hazard, not scope creep.
- **Keychain-touching checks are now stage-scoped instead of global.** A
  bare `scripts/release.sh archive` no longer touches the keychain at all
  (it never needed to) — a beneficial behavior change, not a regression,
  but worth calling out since it's the one place this plan deliberately
  changes *when* an existing check runs, not just *where its code lives*.
  The fail-fast guarantee itself is preserved for `all`/any chain including
  `notarize`, via the pre-dispatch hook in step 1.
- **Keychain ACL prompts** (same risk M02-S01 already flagged): the first
  time `codesign`/`notarytool` touch the signing identity or stored profile
  in a new process context, macOS can pop an interactive "Allow" dialog.
  If step 11 or 12 hangs despite passing gates, a one-time interactive
  "Always Allow" click unblocks future automated runs.
- **`build/release/` from prior real runs (1.0.0, 1.0.1) is simply
  orphaned**, not migrated — still covered by the existing wholesale
  `build/` gitignore entry, no cleanup required, but worth knowing it's
  there if someone goes looking for old artifacts.
- **M02-S02 (not yet planned) will need the new invocation shape** (e.g.
  `scripts/release.sh all`, or explicit stage chaining) instead of the old
  `scripts/release.sh <version>` — nothing to fix now (no CI workflow file
  exists yet, confirmed: no `.github/workflows/` directory in this repo),
  just a heads-up for whoever plans that story next.
- **Quoting discipline for `"AI usage"`/`"AI usage.app"`** (space in the
  name) must hold through every relocated command — not a new risk, but
  worth double-checking line by line during the rewrite since it's a real,
  proven failure mode for shell scripts touching this project.
- **`--help`'s credential-setup text and `print_notary_setup`'s
  failure-path text must stay the exact same function/heredoc** — if
  Codex duplicates the text instead of sharing it, the two will drift the
  first time either one is edited later. Flagged in step 1 and re-checked
  in step 13.

### Codex handoff

Branch: `build/conform-release-standard` (create from `main`, which is
clean and up to date with `origin/main` as of planning).

```
codex exec -m gpt-5.6-sol -c model_reasoning_effort=ultra -s danger-full-access \
  "Read AGENTS.md, then implement the plan in .project/board/M02-S03-conform-release-standard.md on branch build/conform-release-standard."
```

(`-s danger-full-access` is required: Codex's `workspace-write` sandbox
keeps `.git` read-only, so `git switch`/`git commit` fail without it — see
`.project/memory/codex-sandbox-git.md`. This story also needs real keychain
and network access for the codesign/notarytool checks in steps 6, 10–12,
which full access covers too.)
