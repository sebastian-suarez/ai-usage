---
id: M02-S02
type: story
title: Release workflow on tag
status: done
priority: P2
branch: ""
ghProjectItem: "PVTI_lAHOD4_w5c4BjzHmzg7aZCM"
github: "https://github.com/sebastian-suarez/ai-usage/issues/8"
---

A GitHub Actions workflow that runs the M02-S01 script on a macOS runner when a
`v*` tag is pushed, then publishes the resulting DMG as a GitHub release. The
workflow owns only the things CI must do differently from a local run: import
the Developer ID certificate from secrets into a temporary keychain, feed
`notarytool` an App Store Connect API key from secrets, and upload the artifact.
No signing or notarization logic is duplicated — if the two ever disagree, the
script is the one that is right.

Depends on M02-S01. Requires the user to add repository secrets (exported `.p12`
plus password, App Store Connect key/issuer/id) before the first tagged run.

- [x] Pushing a `v*` tag builds, signs, notarizes and staples without manual steps
- [x] The DMG is attached to a GitHub release for that tag
- [x] Signing and notarization go through the M02-S01 script, not a reimplementation
- [x] The temporary keychain and secrets never leak into logs or survive the job
- [x] Required repository secrets are documented in the README

## Status

Reviewed 2026-07-21: the workflow and README are correct. It matches the
M02-S01 script's credential contract (`ASC_KEY_PATH`/`ASC_KEY_ID`/
`ASC_ISSUER_ID` env vars, no keychain profile in CI) and its
`extract_marketing_version` logic exactly; no `xcodebuild`, `codesign`,
`hdiutil`, `notarytool` or `stapler` invocation is reimplemented in the
YAML (the two hits outside the two `scripts/release.sh` calls are a
toolchain-diagnostic `xcodebuild -version` and `-T`/partition-list flag
*values* naming those binaries, not calls to them); the keychain-import
recipe matches the reference recipe exactly, including the
`set-key-partition-list` step and the deliberately-unquoted search-list
word-split; and no step echoes a secret or sets `-x`. Confirmed by running
`scripts/release.sh --help` and `scripts/release.sh --dry-run all` locally
(all 8 `run:` blocks also individually pass `bash -n`) and by re-checking
the live `macos-26` runner image, which still carries Xcode 26.6 (build
17F113) at the exact pinned path — and is *not* the image's default Xcode,
which is what makes the `DEVELOPER_DIR` pin load-bearing rather than
redundant.

Three deviations from the plan's literal YAML block, all correct and kept:
a job-level guard skipping runs triggered by tag **deletion**
(`github.event.deleted == false`) rather than just tag push — without it,
deleting a `v*` tag would still satisfy `if: github.event_name == 'push'`
on every step; `--verify-tag` on `gh release create` (confirmed via
`gh release create --help`: aborts instead of silently recreating a
missing tag against the wrong commit — matters if a tag is deleted while
a long notarization wait is in flight); and `persist-credentials: false`
on checkout, a reasonable least-privilege default since `gh` authenticates
off its own `GITHUB_TOKEN` env var, not git's stored credentials. A fourth,
unflagged but also correct: the tag-check step's `grep | sort -u` gained
`|| true`, matching the script's own `extract_marketing_version` exactly —
the plan's literal block omitted it, which would abort the step with a bare
exit instead of the intended `::error::` message if `MARKETING_VERSION`
were ever absent.

Per the plan's own Test plan, only AC3 and AC5 are fully verifiable by
static inspection today, so only those are checked above. AC1 and AC2 need
a real `v*` tag pushed against real secrets that don't exist yet. AC4 is
half-verified — no echo/`-x` anywhere, and the `if: always()` cleanup step
itself runs on every trigger including `workflow_dispatch` — but proving
the keychain is *actually created and deleted* (not just that the cleanup
step ran) needs the cert-import step, which is skipped outside a real push.
Landing this on `status: blocked`, not `done`.

**What remains**: add the five repository secrets (`DEVELOPER_ID_P12`,
`P12_PASSWORD`, `ASC_KEY_P8`, `ASC_KEY_ID`, `ASC_ISSUER_ID` — table and
encoding instructions in the README's "Releasing from CI" section), then
push a real `v*` tag matching `MARKETING_VERSION`. Once that run goes green
end to end and the draft release has the right DMG attached, publish it by
hand and flip this item to `done`.

## Plan

> **No child Task files.** Same call as M02-S01 and M02-S03 (and every M01
> story): one new workflow file plus one README subsection is a single
> coherent unit of work, not a breakdown.

> **Runner/Xcode risk — resolved before planning, not open.** The concern
> going in was that GitHub-hosted macOS runners might lag Apple's Xcode
> releases badly enough that nothing could build this project's toolchain
> (Xcode 26.6 / Swift 6.3.3, `SWIFT_APPROACHABLE_CONCURRENCY` /
> `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). Verified live against
> `github.com/actions/runner-images` (main branch) on 2026-07-21: the `macos-26`
> label (macOS 26 Arm64, **GA**, not preview) ships seven Xcode versions
> side by side, including **Xcode 26.6 (build 17F113) at
> `/Applications/Xcode_26.6.app`** — an exact match for the local toolchain.
> `macos-latest`/`macos-15` currently resolves to macOS 15.7.7, whose Xcode
> ceiling is only 26.3 — **insufficient, do not use it.** `gh` CLI 2.95.0 is
> also preinstalled on `macos-26` (needed for the publish step). No
> self-hosted runner, no lowering Swift settings, no deferral — the workflow
> below pins `runs-on: macos-26` and pins the exact Xcode via the script's
> own `DEVELOPER_DIR` override (no `sudo xcode-select`, no third-party
> action).

> **This item cannot reach `status: done` from a normal review pass.** AC1
> and AC2 need a real `v*` tag pushed against real repository secrets that
> don't exist yet (the user's explicit "I'll add the secrets after"). See
> Test plan and Risks — the reviewer should land on `blocked`, not `done`,
> with the remaining step spelled out.

> **Guardrail for the implementer: do not run a real (non-`--dry-run`)
> release stage on this Mac during this story.** This checkout already has a
> working `AI-usage-notary` keychain profile from M02-S01/S03/S04's real
> releases. `scripts/release.sh`'s credential fallback means an unguarded
> `scripts/release.sh all` or `scripts/release.sh notarize` run here — with
> no `ASC_*` env vars set — would silently fall through to that *real*
> profile and submit a real, permanent Apple notarization request for no
> reason. This story does not modify `scripts/release.sh` at all; the only
> local invocations it needs are `scripts/release.sh --help` and
> `scripts/release.sh --dry-run all`, purely to cross-check text against the
> script's actual current behavior.

### Approach

**One workflow, `.github/workflows/release.yml`, one job, triggered by
`push: tags: v*` and `workflow_dispatch`.** The job does only what CI must do
differently from a local run — pin the toolchain, materialize secrets into
the filesystem/keychain, check the tag against the manifest, call
`scripts/release.sh` verbatim, publish the result, clean up — and calls the
script for every archive/export/package/notarize/staple/verify action. Not
one `xcodebuild`, `codesign`, `hdiutil`, `notarytool` or `stapler` invocation
lives in the workflow file itself.

Key decisions, each with the alternative rejected:

- **`runs-on: macos-26`, pinned via job-level `env.DEVELOPER_DIR:
  /Applications/Xcode_26.6.app/Contents/Developer`.** Verified above. Rejected:
  `macos-latest` (resolves to an Xcode ceiling of 26.3, can't build this
  project); `sudo xcode-select -s` (works, but mutates global runner state and
  needs `sudo` for no benefit); `maxim-lobanov/setup-xcode` (a third-party
  action doing exactly what one `env:` line already does, given the script
  already reads `DEVELOPER_DIR`). The script's own `validate_environment()`
  already fails loudly if this path ever disappears from the image — no new
  guard needed.
- **One job, straight-line steps gated by per-step `if:
  github.event_name == 'push'` / `== 'workflow_dispatch'`, not two separate
  jobs.** The two trigger paths share checkout, the tag check, and the
  toolchain diagnostic; splitting into a `dry-run` job and a `release` job
  would either duplicate those steps or need a third setup job passing
  outputs between them, for no benefit — nothing here parallelizes.
- **Tag ↔ manifest check is a workflow step, not a script change**, run
  immediately after checkout, before anything secret-related: extract
  `${GITHUB_REF_NAME#v}`, extract `MARKETING_VERSION` from the pbxproj with
  the exact same `grep -o 'MARKETING_VERSION = [^;]*;' | sort -u` +
  consistency check the script's own `extract_marketing_version` already
  uses (so the two can never silently disagree about what "consistent"
  means), fail loudly with `::error::` on either a multi-value manifest or a
  tag/manifest mismatch. This is explicitly the plan's responsibility per
  the task — the script deliberately has no opinion about tags.
- **Credentials materialize into `$RUNNER_TEMP` (a per-job path), not
  `$GITHUB_WORKSPACE`** — never in the checked-out tree, never at risk of
  being swept into any later `git`/artifact step.
- **Certificate import matches the reference doc's recipe exactly**: decode
  → throwaway `security create-keychain` → `security import -T
  /usr/bin/codesign -T /usr/bin/security` → **`security
  set-key-partition-list`** (its absence is the documented cause of
  `codesign` hanging forever on a runner — the single most-cited gotcha for
  this exact recipe) → append to the search list with `security
  list-keychains -d user -s "$KEYCHAIN_PATH" $(security list-keychains -d
  user | tr -d '"')` (deliberately unquoted command substitution — the
  existing list is one quoted path per line and must word-split into
  separate arguments) → `security default-keychain`. `rm -f` the decoded
  `.p12` at the end of the same step rather than deferring it to cleanup,
  since nothing after this step needs the file on disk.
- **Notarization auth via `ASC_KEY_PATH`/`ASC_KEY_ID`/`ASC_ISSUER_ID`
  env vars only** — this is the credential contract M02-S01 already fixed
  and M02-S03 preserved; the workflow's only job is to write the decoded
  `.p8` to `$RUNNER_TEMP/asc_key.p8` and export the three env vars on the
  step that calls the script. No keychain profile exists or is created for
  notarization in CI, matching the task's explicit statement that CI has no
  keychain profile.
- **Publish as a draft, seeded with `gh release create --generate-notes
  --draft`, using the built-in `GITHUB_TOKEN`.** This is the first time this
  exact pipeline will ever run anywhere but the user's own Mac, with
  credentials it has never used before — publishing straight to a
  (private-repo-facing) release on the first several real runs is the kind
  of "pretend the unverified pipeline works" outcome this story was
  explicitly warned against. A draft costs one manual click once the user
  has watched a run succeed, and it preserves exactly the workflow 1.0.0/1.0.1
  already used: `--generate-notes` seeds a reasonable starting point from
  commit history, the user still edits it by hand before publishing.
  Removing `--draft` later, once a few real runs are trusted, is a one-line
  change — flagged in Risks, not decided permanently here. Rejected:
  publish immediately (matches the milestone's long-run "tagging is enough"
  framing, but wrong for an unverified first run); a `CHANGELOG.md`-driven
  notes file (a new maintained artifact/discipline this story doesn't need
  to introduce).
- **No `pull_request` trigger.** The task flagged that adding `.github/`
  means PRs start showing checks — that turns out not to apply here by
  construction, since this workflow listens only to `push: tags: v*` and
  `workflow_dispatch`. Merging this story's own PR adds zero checks to any
  PR, this one included. A lint/build-on-every-PR workflow is a legitimate
  future idea but a different, new workflow file (e.g. `ci.yml`), not part
  of "release workflow on tag."
- **`workflow_dispatch` takes no inputs and always means dry-run.** Simpler
  than a boolean toggle that could accidentally be flipped to trigger a real
  signing run from an arbitrary ref outside the tag/manifest safety check.
  If a manual *real* re-run is ever needed, re-pushing the tag (`git tag -f`
  + `git push -f --tags`, or deleting and re-pushing) is the supported path,
  not this workflow's manual trigger.
- **`timeout-minutes: 150` at the job level** — comfortably above the
  script's own internal `--timeout 2h` on `notarytool submit --wait`, so a
  slow-but-legitimate Apple notarization is the script's own timeout to
  report cleanly (with a fetched log), not GitHub's blunt job-kill with no
  diagnostic.

### Files to touch

- **`.github/workflows/release.yml` — new.** Complete content:

  ````yaml
  name: Release

  on:
    push:
      tags:
        - 'v*'
    workflow_dispatch:

  permissions:
    contents: read

  jobs:
    release:
      runs-on: macos-26
      timeout-minutes: 150
      permissions:
        contents: write
      env:
        DEVELOPER_DIR: /Applications/Xcode_26.6.app/Contents/Developer
      steps:
        - name: Check out repository
          uses: actions/checkout@v4
          with:
            fetch-depth: 0

        - name: Verify tag matches MARKETING_VERSION
          if: github.event_name == 'push'
          run: |
            set -euo pipefail
            TAG_VERSION="${GITHUB_REF_NAME#v}"
            VALUES="$(grep -o 'MARKETING_VERSION = [^;]*;' "AI usage.xcodeproj/project.pbxproj" | sort -u)"
            COUNT="$(printf '%s\n' "$VALUES" | grep -c . || true)"
            if [[ "$COUNT" != "1" ]]; then
              echo "::error::MARKETING_VERSION is not consistent across the project file: $(printf '%s' "$VALUES" | tr '\n' ' ')"
              exit 1
            fi
            MANIFEST_VERSION="$(printf '%s\n' "$VALUES" | sed -E 's/MARKETING_VERSION = (.*);/\1/')"
            if [[ "$TAG_VERSION" != "$MANIFEST_VERSION" ]]; then
              echo "::error::Tag '$GITHUB_REF_NAME' does not match MARKETING_VERSION '$MANIFEST_VERSION' — bump the version and commit before tagging."
              exit 1
            fi
            echo "Tag $GITHUB_REF_NAME matches MARKETING_VERSION $MANIFEST_VERSION"

        - name: Show toolchain versions
          run: |
            sw_vers
            xcodebuild -version

        - name: Dry run (workflow_dispatch only)
          if: github.event_name == 'workflow_dispatch'
          run: scripts/release.sh --dry-run all

        - name: Import Developer ID certificate
          if: github.event_name == 'push'
          env:
            DEVELOPER_ID_P12: ${{ secrets.DEVELOPER_ID_P12 }}
            P12_PASSWORD: ${{ secrets.P12_PASSWORD }}
          run: |
            set -euo pipefail
            KEYCHAIN_PATH="$RUNNER_TEMP/release-signing.keychain-db"
            KEYCHAIN_PASSWORD="$(uuidgen)"
            P12_PATH="$RUNNER_TEMP/developer_id.p12"

            echo "$DEVELOPER_ID_P12" | base64 --decode -o "$P12_PATH"

            security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
            security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
            security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
            security import "$P12_PATH" -k "$KEYCHAIN_PATH" -P "$P12_PASSWORD" \
              -T /usr/bin/codesign -T /usr/bin/security
            security set-key-partition-list -S apple-tool:,apple:,codesign: \
              -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
            security list-keychains -d user -s "$KEYCHAIN_PATH" \
              $(security list-keychains -d user | tr -d '"')
            security default-keychain -s "$KEYCHAIN_PATH"

            rm -f "$P12_PATH"

        - name: Write App Store Connect API key
          if: github.event_name == 'push'
          env:
            ASC_KEY_P8: ${{ secrets.ASC_KEY_P8 }}
          run: |
            set -euo pipefail
            echo "$ASC_KEY_P8" | base64 --decode > "$RUNNER_TEMP/asc_key.p8"
            chmod 600 "$RUNNER_TEMP/asc_key.p8"

        - name: Run scripts/release.sh all
          if: github.event_name == 'push'
          env:
            ASC_KEY_PATH: ${{ runner.temp }}/asc_key.p8
            ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
            ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          run: scripts/release.sh all

        - name: Publish GitHub release (draft)
          if: github.event_name == 'push'
          env:
            GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          run: |
            set -euo pipefail
            gh release create "$GITHUB_REF_NAME" dist/*.dmg \
              --title "$GITHUB_REF_NAME" \
              --generate-notes \
              --draft

        - name: Remove temporary keychain and key material
          if: always()
          run: |
            security delete-keychain "$RUNNER_TEMP/release-signing.keychain-db" 2>/dev/null || true
            rm -f "$RUNNER_TEMP/asc_key.p8" "$RUNNER_TEMP/developer_id.p12"
  ````

  Note for the implementer: the `echo "$SECRET" | base64 --decode` lines
  pipe the value straight into `base64`, never to stdout/the log — this is
  not the "no echo of secret values" hard requirement being violated, it's
  the standard idiom for decoding a secret in CI. Do not add `set -x` to any
  step above; do not add any step that prints `$DEVELOPER_ID_P12`,
  `$P12_PASSWORD`, `$ASC_KEY_P8`, or the contents of the decoded files.

- **`README.md` — insert a new `###` subsection under the existing
  `## 📦 Release` heading, immediately after the current Mermaid flowchart
  (present-day line 95) and before `## 🏗️ How it works` (present-day line
  97).** Exact content:

  ````markdown
  ### Releasing from CI

  Pushing a tag matching `v*` (e.g. `v1.0.2`) runs
  `.github/workflows/release.yml` on a GitHub-hosted `macos-26` runner: it
  checks the tag against `MARKETING_VERSION` (failing loudly on a mismatch),
  imports a Developer ID certificate into a throwaway keychain, runs
  `scripts/release.sh all` with an App Store Connect API key for
  notarization, and attaches the resulting DMG to a **draft** GitHub release
  for that tag — `gh release create --generate-notes --draft` seeds the
  notes from the commit history, but nothing goes public until the draft is
  reviewed and published by hand, same as 1.0.0 and 1.0.1.

  The workflow can also be run manually from the Actions tab
  (`workflow_dispatch`), with no tag needed; that path only runs
  `scripts/release.sh --dry-run all` — safe to trigger any time, touches no
  secrets, no keychain, no network.

  Required repository secrets (Settings → Secrets and variables → Actions →
  New repository secret):

  | Secret | Contents |
  | --- | --- |
  | `DEVELOPER_ID_P12` | Base64 of the exported Developer ID Application certificate + private key (`.p12`) |
  | `P12_PASSWORD` | Password the `.p12` was exported with |
  | `ASC_KEY_P8` | Base64 of the App Store Connect API key (`AuthKey_*.p8`) |
  | `ASC_KEY_ID` | The API key's ID, e.g. `L52B584XJB` |
  | `ASC_ISSUER_ID` | The App Store Connect issuer ID (UUID) — Apple Developer → Users and Access → Integrations → Keys |

  Encode a file for its secret with `base64 -i <file> | pbcopy`, then paste
  directly into the secret's value field.
  ````

- **Do not touch**: `scripts/release.sh`, `scripts/ExportOptions.plist`,
  `AI usage.xcodeproj/project.pbxproj`, any file under `AI usage/` (app
  source), `.gitignore` (nothing new to ignore — CI artifacts never touch
  the checked-out tree).

### Steps

Each step is independently checkable; later steps depend on earlier ones
only in the sense that they land in the same file.

1. **Create `.github/` and `.github/workflows/`, write `release.yml`** with
   the exact content above.
   Verify: `bash -n` cannot check YAML, but every `run:` block is valid
   bash on its own — extract each with a text editor and confirm `bash -n`
   passes on each; the file has no tabs (YAML-illegal) and consistent
   2-space indentation throughout.
2. **Push the branch and confirm GitHub accepts the workflow syntax.**
   GitHub parses every workflow file structurally on push, independent of
   whether any job runs, and annotates the commit/Actions tab with a
   "workflow file issue" if malformed.
   Verify: no such annotation appears after pushing.
3. **Manually trigger `workflow_dispatch` once** (Actions tab → "Release" →
   "Run workflow" → this branch — no MCP tool or `gh` CLI is available in
   this environment to script this; see Risks).
   Verify: the run is green; the "Show toolchain versions" step logs `Xcode
   26.6`; the "Dry run" step's log shows all seven `[dry-run]`-prefixed
   stage traces (identical in shape to the local `scripts/release.sh
   --dry-run all` output already proven in M02-S03); the "Import Developer
   ID certificate" / "Write App Store Connect API key" / "Run
   scripts/release.sh all" / "Publish GitHub release" steps are all skipped
   (grey, not green — confirms the `if:` gating works); "Remove temporary
   keychain and key material" still ran and exited 0.
4. **Add the README subsection** at the exact content and location above.
   Verify: Markdown table renders; every secret name (`DEVELOPER_ID_P12`,
   `P12_PASSWORD`, `ASC_KEY_P8`, `ASC_KEY_ID`, `ASC_ISSUER_ID`) appears
   verbatim in both the workflow file's `secrets.*` references and the
   README table — grep both files for each name and confirm five matches
   each.
5. **Whole-file review pass over `release.yml`**: confirm (a) the only
   `xcodebuild`/`codesign`/`hdiutil`/`notarytool`/`stapler` invocations in
   the entire file are inside the two `scripts/release.sh` calls (AC3); (b)
   no step echoes a secret to stdout and no step sets `-x` (AC4); (c)
   `"AI usage.xcodeproj/project.pbxproj"` is quoted at its one use site.
   Verify: this review itself, with all three checks passing, is the proof.
6. **Confirm `git status` is clean of anything unexpected** (no stray
   `dist/`, no `xcuserdata` changes, no `project.pbxproj` diff — this story
   touches nothing under `AI usage/` or the Xcode project).
   Verify: `git status --porcelain` shows exactly the two new/changed files
   (`README.md`, `.github/workflows/release.yml`).

### Test plan

Mapped to the acceptance criteria checklist. Each is tagged with what's
reachable now versus what's blocked on the user's secrets.

- **AC1 (tag push builds/signs/notarizes/staples without manual steps) —
  partially verifiable now, rest blocked on secrets.** Now: Steps 2–3 prove
  the workflow parses and that the CI environment (runner, pinned Xcode,
  tool availability, `MARKETING_VERSION` extraction, stage sequencing)
  genuinely works, all without secrets — this is everything `--dry-run`
  exercises, including the real, unconditional `validate_environment()`
  checks inside the script. Blocked: the real signing/notarize/staple
  chain has never run on a hosted runner with real credentials; only
  provable once the user adds the five secrets and pushes a real tag.
- **AC2 (DMG attached to a GitHub release for that tag) — blocked on
  secrets.** The publish step's flags/command are verifiable by code review
  now (Step 5); actually producing a release needs a real successful run.
- **AC3 (goes through the M02-S01 script, not a reimplementation) — fully
  verifiable now.** Step 5's review is the complete proof: grep the final
  file for `xcodebuild|codesign|hdiutil|notarytool|stapler` and confirm
  every hit is plain prose/comment or inside a `scripts/release.sh` call.
- **AC4 (keychain and secrets never leak or survive the job) — mostly
  verifiable now, one part blocked.** Now: Step 5's review confirms no
  echo/`-x` anywhere, and Step 3's dry run already proves the `if: always()`
  cleanup step itself runs and exits 0 (harmlessly, nothing to delete yet).
  Blocked: proving the keychain is *actually created and actually deleted*
  (not just that the cleanup step ran) needs a real push run, since the
  cert-import step is skipped on `workflow_dispatch`.
- **AC5 (required secrets documented in the README) — fully verifiable
  now.** Step 4's cross-check between the workflow's `secrets.*` references
  and the README table is the complete proof; needs no live run.

**Recommended review-phase outcome**: AC3 and AC5 pass on inspection; AC1,
AC2 and AC4's behavioral half stay open pending the user's secrets. Land the
item on `status: blocked`, not `done`, with a `## Review` note naming the
exact remaining step (add the five secrets → push a real tag → confirm the
Actions run goes green end to end → confirm the draft release appears with
the right DMG → publish it by hand → then flip to `done`).

### Risks / open questions

- **No MCP tool or `gh` CLI can trigger or poll Actions runs from inside
  this environment.** Checked the live `mcp__github__*` tool list: it covers
  issues/PRs/branches/commits/releases/tags but has no workflow-dispatch or
  run-status tool, and project memory records `gh` CLI is deliberately
  uninstalled here (pushes go over SSH). Step 3's manual trigger and its
  verification must happen via the GitHub web UI by hand, or via
  authenticated `curl` against the REST API using the OAuth token already
  stored for the GitHub MCP server (untested whether its `repo` scope
  covers `actions:write` — check before relying on it).
- **Draft-vs-immediate-publish is a real, reversible decision made here as
  "draft."** Full reasoning in Approach. If the user would rather have the
  very first release publish immediately (matching the milestone's
  "tagging is enough" framing from day one), removing `--draft` from the
  publish step is a one-line change.
- **`stage_test` (which `all` runs first) was not exercised on an actual
  runner during planning — inferred safe, not proven.** Spot-checked
  `ClaudeUsageProviderTests.swift`/`ChatGPTUsageProviderTests.swift`: both
  inject fake credentials, temp files, and a stubbed `/usr/bin/false`
  executable rather than touching the real Keychain or `~/.codex/`, so
  `stage_test` should pass with no user-specific state on the runner. If
  this inference is wrong, it fails at the very first stage, before any
  signing/notarization work — cheap to discover, cheap to fix.
- **`--dry-run` does not execute the real test suite** — `stage_test`'s
  dry-run branch only prints the `xcodebuild test` command (unchanged
  script behavior, confirmed by reading it during planning). So Step 3's
  dry run proves toolchain/tool-existence/version-extraction/control-flow,
  not "tests actually pass in this CI environment." A separate,
  always-real `ci.yml` that runs `scripts/release.sh test` on every
  push/PR would be a reasonable follow-up story, out of scope here.
- **Fresh-clone scheme resolution, now on a second environment.** No
  `.xcscheme` is checked in; M02-S01 already proved the autocreated scheme
  resolves from a genuinely fresh clone on this Mac. CI is also a fresh
  checkout every run, so the same reasoning should hold, but it's the first
  time on a different machine/Xcode installation. If archiving ever fails
  on a scheme-resolution error in CI specifically (and only there), the fix
  is Xcode → Manage Schemes → Shared → commit the resulting `.xcscheme`,
  exactly as M02-S01 already documented.
- **Runner image inventory can change.** If Apple/GitHub ever prune Xcode
  26.6 from the `macos-26` image, `validate_environment()`'s existing
  `[[ -d "$DEVELOPER_DIR" ]]` check already fails loudly with a clear
  message rather than silently building with a different compiler — no new
  guard needed, but worth knowing as the failure mode.
- **Universal/architecture question, checked and closed.** `macos-26` is
  Apple Silicon (arm64), matching the user's own Mac exactly; Xcode
  cross-compiles universal binaries natively regardless of host
  architecture if `ARCHS` requests it, so CI running on the same host
  architecture as every prior successful local release removes risk here
  rather than adding it.
- **Keychain ACL prompts (M02-S01's known risk) do not apply to CI.**
  That risk is specifically about an interactive session; a hosted runner
  has none, and `security set-key-partition-list` is precisely the
  non-interactive substitute — already included above.

### Codex handoff

Branch: `ci/release-workflow` (create from `main`, clean and up to date with
`origin/main` as of planning).

```
codex exec -m gpt-5.6-sol -c model_reasoning_effort=ultra -s danger-full-access \
  "Read AGENTS.md, then implement the plan in .project/board/M02-S02-release-workflow.md on branch ci/release-workflow. Do not run a real (non---dry-run) release stage on this Mac — see the guardrail callout near the top of the plan."
```

(`-s danger-full-access` is required: Codex's `workspace-write` sandbox
keeps `.git` read-only, so `git switch`/`git commit` fail without it — see
`.project/memory/codex-sandbox-git.md`. Unlike M02-S01/M02-S03, this story
does not need real keychain or notarization network access — it only
authors a workflow file and README prose — so the flag is for `.git` access
alone; the local-notary-profile guardrail above still applies regardless.)

## Review

First real tagged run (`v1.0.2`, run
[29886530031](https://github.com/sebastian-suarez/ai-usage/actions/runs/29886530031))
**failed**, 2026-07-22. The five repository secrets are present and worked: tag/manifest
check, certificate import into the throwaway keychain, and the ASC key write all
succeeded, the publish step was correctly skipped, and cleanup ran. The failure is
upstream of all of that, in the very first stage.

1. **`stage_test` cannot run on a CI runner — it demands a development certificate.**
   `xcodebuild test` builds the Debug configuration with `CODE_SIGN_STYLE = Automatic`
   and `DEVELOPMENT_TEAM = KGVLNXZJNX`, so Xcode requires a **"Mac Development"**
   signing identity. CI imports only the **Developer ID Application** certificate, and
   importing a development certificate as well is the wrong fix — it would mean shipping
   a second private key into CI for no distribution purpose. The run died with:

       error: No signing certificate "Mac Development" found: No "Mac Development"
       signing certificate matching team ID "KGVLNXZJNX" with a private key was found.
       (in target 'AI usageTests' ... 'AI usageUITests' ... 'AI usage')
       ** TEST FAILED **

   Fix the test stage so it builds without a development identity. Constraints:
   - **The runner is Apple Silicon**, where every executable needs at least an ad-hoc
     signature to run. A blanket `CODE_SIGNING_ALLOWED=NO` may produce a test host that
     cannot launch — ad-hoc signing (`CODE_SIGN_IDENTITY="-"`) is the usual answer.
     Verify whichever you choose actually executes the tests, don't assume.
   - **Do not weaken the release path.** `archive`/`export` must keep using Developer ID
     signing with the hardened runtime exactly as today. Only the test stage changes.
   - Tests must still genuinely run and still gate the release — skipping them in CI is
     not an acceptable fix.
   - The change must work identically on this Mac, where a development certificate does
     exist. Verify locally with `scripts/release.sh test`.

2. **Re-verify the rest of the pipeline is reachable.** Everything after `test` —
   archive, export, package, notarize, staple, verify, publish — has never executed on a
   runner. Fixing finding 1 will expose whatever is behind it. Expect at least one more
   round; that is normal, not failure.

The `v1.0.2` tag currently points at `50cc154` with no release published. Deleting and
re-pushing it after the fix is safe: the workflow's tag-deletion guard means removing the
tag does not trigger a run. Do not create a `v1.0.3` to dodge the problem.

### Round 2 — 2026-07-22

Finding 1 is **fixed and proven in CI**: run
[29887017751](https://github.com/sebastian-suarez/ai-usage/actions/runs/29887017751) ran all
56 unit tests to completion on the runner. The failure moved one stage down, as anticipated.

3. **`stage_archive` hits the same wall.** `xcodebuild archive` with
   `CODE_SIGN_STYLE = Automatic` resolves a **development** identity even for the Release
   configuration, so it fails in CI with the same error the test stage did:

       ** ARCHIVE FAILED **
       error: No signing certificate "Mac Development" found ... (in target 'AI usage')

   Note the archive's own signature is not what ships — `-exportArchive` re-signs the app
   from scratch using `ExportOptions.plist` (this was M02-S01's explicit reasoning). So the
   archive needs *a* valid signature, not necessarily the distribution one. Two workable
   directions, pick with justification:
   - Archive with manual Developer ID signing (`CODE_SIGN_STYLE=Manual`,
     `CODE_SIGN_IDENTITY="Developer ID Application"`, `DEVELOPMENT_TEAM=KGVLNXZJNX`) — the
     archive then carries the identity it will ship with.
   - Archive ad-hoc, as `stage_test` now does, and let export apply the real identity.

   Constraints, unchanged from finding 1: the **exported** app must still end up signed by
   `Developer ID Application: Sebastian Suarez (KGVLNXZJNX)` with the hardened runtime, and
   `stage_export`'s own post-export verification must keep passing. Whatever you choose must
   work both in CI and on this Mac, where a development certificate exists. Verify locally
   with `scripts/release.sh archive` followed by `scripts/release.sh export`.

4. **Everything after `export` remains unexercised on a runner** — package, notarize,
   staple, verify, publish. Expect the boundary to keep moving; that is the process working.

### Round 3 — root cause, not another patch

Two rounds of per-stage signing overrides have chased the same underlying problem, and the
user called it: **`CODE_SIGN_STYLE = Automatic` is set for every configuration of every
target.** It is tuned for developing on one Mac with a development certificate in the
keychain, and it fights every environment that doesn't have one. Patching stage by stage
(`test`, then `archive`, then whatever comes next) treats symptoms.

5. **Switch the Release configuration to manual Developer ID signing in the project
   itself**, so archiving needs no per-stage override at all.
   - App target, **Release only**: `CODE_SIGN_STYLE = Manual`,
     `CODE_SIGN_IDENTITY = "Developer ID Application"`,
     `DEVELOPMENT_TEAM = KGVLNXZJNX`, no provisioning profile (Developer ID distribution of
     a non-sandboxed app needs none).
   - **Debug stays `Automatic`.** Running from Xcode on this Mac must not change.
   - Reconcile `scripts/ExportOptions.plist`, which currently says
     `signingStyle: automatic`. A manually-signed archive exported with automatic signing is
     inconsistent; decide deliberately and verify the export still produces an app signed by
     `Developer ID Application: Sebastian Suarez (KGVLNXZJNX)` with the hardened runtime.
   - Keep the ad-hoc override `stage_test` gained in round 1 — tests build Debug and must
     still run without any certificate. Remove any *archive* override that becomes redundant.
   - This is a deliberate, permanent change to a tracked project setting. It does not
     conflict with the rule that a *release run* never mutates `project.pbxproj`.

   Verify locally: `scripts/release.sh test`, then `archive`, then `export`, then
   `codesign -dvv` on the exported app for both the Developer ID authority and
   `flags=0x10000(runtime)`. Do not run notarize or anything after it.
