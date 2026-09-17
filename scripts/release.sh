#!/usr/bin/env bash

set -euo pipefail

readonly APP_NAME="AI usage.app"
readonly PROJECT="AI usage.xcodeproj"
readonly SCHEME="AI usage"
readonly TEAM_ID="KGVLNXZJNX"
readonly SIGNING_IDENTITY="Developer ID Application: Sebastian Suarez (KGVLNXZJNX)"
readonly DEFAULT_NOTARY_PROFILE="notarytool-KGVLNXZJNX"
readonly PLIST_BUDDY="/usr/libexec/PlistBuddy"
# Xcode derives this from the project's name; the WorkspacePath check below is
# what actually authorizes deletion, so this only narrows the candidate list.
readonly DERIVED_DATA_PREFIX="AI_usage"

# Single source of truth for stage order. `all` runs every stage except install.
PIPELINE_STAGES=(clean test archive export package notarize staple verify install)
readonly PIPELINE_STAGES
STAGE_ORDER=(clean test archive export package notarize staple verify)
readonly STAGE_ORDER

DRY_RUN=0
VERSION_OVERRIDE=""
BUILD_OVERRIDE=""
VERSION_OVERRIDE_SET=0
BUILD_OVERRIDE_SET=0
VERSION=""
BUILD=""

SCRIPT_DIR=""
REPO_ROOT=""
DIST_DIR=""
BUILD_DIR=""
DERIVED_DATA_PATH=""
DERIVED_DATA_ROOT=""
WORK_DIR=""
ARCHIVE_PATH=""
EXPORT_DIR=""
EXPORTED_APP=""
TESTED_MARKER=""
DMG_PATH=""
SUBMISSION_JSON=""
NOTARY_LOG=""
STAPLED_MARKER=""

AUTH_ARGS=()
NOTARY_ERROR_FILE=""
STAGING_DIR=""
MOUNT_DIR=""
SCRATCH_DIR=""
DMG_ATTACHED=0
INCOMPLETE_DIR=""
INCOMPLETE_FILE=""
SIGNING_IDENTITY_VALIDATED=0
INSTALL_MOUNT_DIR=""
INSTALL_DMG_ATTACHED=0
INSTALL_PROBE_DIR=""
INSTALL_INCOMPLETE_TARGET=""

JSON_FIELD_SCRIPT='
import json
import sys

try:
    value = json.load(sys.stdin).get(sys.argv[1], "")
except (AttributeError, OSError, TypeError, ValueError):
    sys.exit(1)

print(value)
'
readonly JSON_FIELD_SCRIPT

usage() {
    cat >&2 <<'EOF'
Usage: scripts/release.sh [--dry-run] [--version X.Y.Z] [--build N] <stage>...
       scripts/release.sh --help

Stages: clean test archive export package notarize staple verify install all
EOF
}

fail() {
    echo "Error: $*" >&2
    exit 1
}

print_notary_setup() {
    local profile="${NOTARY_PROFILE:-$DEFAULT_NOTARY_PROFILE}"

    cat <<'EOF'
No notarization credentials found for "AI usage".

Local (one-time setup): store the App Store Connect API key as a keychain
profile notarytool can reuse:
EOF
    printf '  xcrun notarytool store-credentials "%s" \\\n' "$profile"
    cat <<'EOF'
    --key "<path-to-AuthKey.p8>" \
    --key-id "<key-id>" \
    --issuer "<issuer-id>"

To skip the profile entirely (e.g. in CI), export ASC_KEY_PATH, ASC_KEY_ID and
ASC_ISSUER_ID with the same API key values instead.
EOF
}

help() {
    cat <<'EOF'
Usage: scripts/release.sh [--dry-run] [--version X.Y.Z] [--build N] <stage>...
       scripts/release.sh --help

Run stages in this order for a full release:
  clean      remove dist/, build/ and this project's Xcode DerivedData
  test       run the unit test target
  archive    create and validate the versioned Xcode archive
  export     export and verify the Developer ID-signed app
  package    create, sign, and verify the distribution DMG
  notarize   submit the DMG to Apple and require Accepted status
  staple     staple and validate the notarization ticket
  verify     inspect the DMG and run a quarantined Gatekeeper assessment
  all        run every stage above in order, starting with clean
  install    replace /Applications/AI usage.app with the built DMG (not in all)

Multiple distinct stage names may be supplied to resume part of the pipeline.
For safety, all must be used by itself.

All begins with clean, so a release never inherits stale intermediates. It also
clears Xcode's cache for this project, so the next Xcode build recompiles from
scratch. After a successful all, only dist/AI-usage-<version>.dmg remains;
individual stages cannot be re-run without rebuilding their intermediates.

Install needs write access to /Applications. If this environment cannot write
there, it changes nothing and prints the exact commands to run in Terminal.

Options:
  --dry-run       print every stage command without creating artifacts or
                  touching the network, Apple services, or the keychain
  --version X.Y.Z override MARKETING_VERSION for an explicit test
                  build; real releases must use the project version
  --build N       override the default Git-derived build number
  -h, --help      show this help

Prerequisites:
  - macOS with Xcode at DEVELOPER_DIR (defaults to
    /Applications/Xcode.app/Contents/Developer)
  - the Developer ID Application certificate in the login keychain
  - notarization credentials configured by one of the methods below

The release version is read from MARKETING_VERSION in the Xcode project and is
never written by this script. The final artifact is:

  dist/AI-usage-<version>.dmg

The --version override is only for test builds and always emits a warning.

Notarization credential setup:
EOF
    print_notary_setup
}

log() {
    printf '\n=== %s ===\n' "$*"
}

dry_command() {
    local argument

    printf '[dry-run]'
    for argument in "$@"; do
        printf ' %q' "$argument"
    done
    printf '\n'
}

dry_shell() {
    printf '[dry-run] %s\n' "$1"
}

json_field() {
    python3 -c "$JSON_FIELD_SCRIPT" "$1" < "$2"
}

dry_json_field() {
    printf '[dry-run] python3 -c %q %q < %q\n' "$JSON_FIELD_SCRIPT" "$1" "$2"
}

cleanup() {
    local exit_code=$?
    trap - EXIT
    set +e

    if [[ "$DMG_ATTACHED" -eq 1 && -n "$MOUNT_DIR" ]]; then
        if hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1; then
            DMG_ATTACHED=0
        else
            echo "Warning: could not detach '$MOUNT_DIR'; leaving its mountpoint in place." >&2
        fi
    fi

    if [[ "$INSTALL_DMG_ATTACHED" -eq 1 && -n "$INSTALL_MOUNT_DIR" ]]; then
        if hdiutil detach "$INSTALL_MOUNT_DIR" >/dev/null 2>&1; then
            INSTALL_DMG_ATTACHED=0
        else
            echo "Warning: could not detach '$INSTALL_MOUNT_DIR'; leaving its mountpoint in place." >&2
        fi
    fi

    if [[ -n "$NOTARY_ERROR_FILE" ]]; then
        rm -f "$NOTARY_ERROR_FILE"
    fi
    if [[ -n "$STAGING_DIR" ]]; then
        rm -rf "$STAGING_DIR"
    fi
    if [[ -n "$MOUNT_DIR" && "$DMG_ATTACHED" -eq 0 ]]; then
        rm -rf "$MOUNT_DIR"
    fi
    if [[ -n "$INSTALL_MOUNT_DIR" && "$INSTALL_DMG_ATTACHED" -eq 0 ]]; then
        rm -rf "$INSTALL_MOUNT_DIR"
    fi
    if [[ -n "$INSTALL_PROBE_DIR" ]]; then
        rmdir "$INSTALL_PROBE_DIR" 2>/dev/null || true
    fi
    if [[ -n "$SCRATCH_DIR" ]]; then
        rm -rf "$SCRATCH_DIR"
    fi
    if [[ "$exit_code" -ne 0 && -n "$INCOMPLETE_DIR" ]]; then
        rm -rf "$INCOMPLETE_DIR"
    fi
    if [[ "$exit_code" -ne 0 && -n "$INCOMPLETE_FILE" ]]; then
        rm -f "$INCOMPLETE_FILE"
    fi
    if [[ "$exit_code" -ne 0 && \
        "$INSTALL_INCOMPLETE_TARGET" == "/Applications/$APP_NAME" ]]; then
        if rm -rf "$INSTALL_INCOMPLETE_TARGET"; then
            echo "Removed incomplete install at '$INSTALL_INCOMPLETE_TARGET'; the previous installed version is gone." >&2
        else
            echo "Warning: could not remove incomplete install at '$INSTALL_INCOMPLETE_TARGET'." >&2
        fi
    fi

    exit "$exit_code"
}

trap cleanup EXIT

initialize_checkout() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || \
        fail "could not resolve the release script directory"
    readonly SCRIPT_DIR
    REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)" || \
        fail "could not resolve the repository root"
    readonly REPO_ROOT

    [[ "$REPO_ROOT" != "/" && -e "$REPO_ROOT/.git" && \
        -f "$REPO_ROOT/$PROJECT/project.pbxproj" && \
        -f "$SCRIPT_DIR/ExportOptions.plist" ]] || \
        fail "release script is not inside a valid AI Usage checkout"
    cd "$REPO_ROOT"
}

validate_environment() {
    export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
    [[ -d "$DEVELOPER_DIR" ]] || \
        fail "Xcode developer directory not found at '$DEVELOPER_DIR'"

    local tool
    for tool in git xcodebuild hdiutil codesign spctl ditto xcrun python3 xattr grep tee readlink security pgrep; do
        command -v "$tool" >/dev/null 2>&1 || fail "required tool '$tool' was not found"
    done

    [[ -x "$PLIST_BUDDY" ]] || fail "required tool '$PLIST_BUDDY' was not found"
    xcrun --find notarytool >/dev/null 2>&1 || \
        fail "notarytool was not found in '$DEVELOPER_DIR'"
    xcrun --find stapler >/dev/null 2>&1 || \
        fail "stapler was not found in '$DEVELOPER_DIR'"
}

extract_marketing_version() {
    local pbxproj="$REPO_ROOT/$PROJECT/project.pbxproj"
    local values
    local count

    values="$(grep -o 'MARKETING_VERSION = [^;]*;' "$pbxproj" | sort -u || true)"
    count="$(printf '%s\n' "$values" | grep -c . || true)"
    [[ "$count" == "1" ]] || \
        fail "MARKETING_VERSION is not consistent across $pbxproj: $(printf '%s' "$values" | tr '\n' ' ')"

    printf '%s\n' "$values" | sed -E 's/MARKETING_VERSION = (.*);/\1/'
}

resolve_release_metadata() {
    if [[ "$VERSION_OVERRIDE_SET" -eq 1 ]]; then
        VERSION="$VERSION_OVERRIDE"
        echo "Warning: --version overrides MARKETING_VERSION; real releases must come from MARKETING_VERSION." >&2
    else
        VERSION="$(extract_marketing_version)" || return 1
    fi
    [[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || \
        fail "version must use x.y or x.y.z format (received '$VERSION')"

    if [[ "$BUILD_OVERRIDE_SET" -eq 1 ]]; then
        BUILD="$BUILD_OVERRIDE"
    else
        BUILD="$(git rev-list --count HEAD 2>/dev/null)" || \
            fail "could not derive the build number from Git history"
    fi
    [[ "$BUILD" =~ ^[0-9]+$ ]] || \
        fail "build number must contain digits only (received '$BUILD')"

    DIST_DIR="$REPO_ROOT/dist"
    BUILD_DIR="$REPO_ROOT/build"
    DERIVED_DATA_PATH="$BUILD_DIR/DerivedData"
    DERIVED_DATA_ROOT=""
    if [[ -n "${HOME:-}" && -d "${HOME:-}" ]]; then
        DERIVED_DATA_ROOT="$HOME/Library/Developer/Xcode/DerivedData"
    fi
    WORK_DIR="$DIST_DIR/work/$VERSION"
    ARCHIVE_PATH="$WORK_DIR/AIUsage.xcarchive"
    EXPORT_DIR="$WORK_DIR/export"
    EXPORTED_APP="$EXPORT_DIR/$APP_NAME"
    TESTED_MARKER="$WORK_DIR/.tested"
    DMG_PATH="$DIST_DIR/AI-usage-$VERSION.dmg"
    SUBMISSION_JSON="$WORK_DIR/notarize-result.json"
    NOTARY_LOG="$WORK_DIR/notarize-log.json"
    STAPLED_MARKER="$WORK_DIR/.stapled"
}

select_dry_run_auth_args() {
    local asc_value_count=0

    AUTH_ARGS=()
    [[ -n "${ASC_KEY_PATH:-}" ]] && asc_value_count=$((asc_value_count + 1))
    [[ -n "${ASC_KEY_ID:-}" ]] && asc_value_count=$((asc_value_count + 1))
    [[ -n "${ASC_ISSUER_ID:-}" ]] && asc_value_count=$((asc_value_count + 1))

    if [[ "$asc_value_count" -eq 3 ]]; then
        AUTH_ARGS=(--key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
    elif [[ "$asc_value_count" -ne 0 ]]; then
        echo "ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID must be set together." >&2
        echo >&2
        print_notary_setup >&2
        exit 1
    else
        AUTH_ARGS=(--keychain-profile "${NOTARY_PROFILE:-$DEFAULT_NOTARY_PROFILE}")
    fi
}

resolve_notary_auth_args() {
    local asc_value_count=0

    AUTH_ARGS=()
    [[ -n "${ASC_KEY_PATH:-}" ]] && asc_value_count=$((asc_value_count + 1))
    [[ -n "${ASC_KEY_ID:-}" ]] && asc_value_count=$((asc_value_count + 1))
    [[ -n "${ASC_ISSUER_ID:-}" ]] && asc_value_count=$((asc_value_count + 1))

    if [[ "$asc_value_count" -eq 3 ]]; then
        [[ -f "$ASC_KEY_PATH" ]] || {
            echo "App Store Connect API key not found at '$ASC_KEY_PATH'." >&2
            echo >&2
            print_notary_setup >&2
            exit 1
        }
        AUTH_ARGS=(--key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
    elif [[ "$asc_value_count" -ne 0 ]]; then
        echo "ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID must be set together." >&2
        echo >&2
        print_notary_setup >&2
        exit 1
    else
        NOTARY_PROFILE="${NOTARY_PROFILE:-$DEFAULT_NOTARY_PROFILE}"
        AUTH_ARGS=(--keychain-profile "$NOTARY_PROFILE")
    fi

    NOTARY_ERROR_FILE="$(mktemp "${TMPDIR:-/tmp}/ai-usage-notary.XXXXXX")"
    if ! xcrun notarytool history "${AUTH_ARGS[@]}" > /dev/null 2> "$NOTARY_ERROR_FILE"; then
        print_notary_setup >&2
        exit 1
    fi
    rm -f "$NOTARY_ERROR_FILE"
    NOTARY_ERROR_FILE=""
}

require_signing_identity() {
    local signing_identities

    if [[ "$SIGNING_IDENTITY_VALIDATED" -eq 1 ]]; then
        return 0
    fi

    signing_identities="$(security find-identity -v -p codesigning 2>/dev/null)" || \
        fail "could not inspect code-signing identities in the keychain"
    grep -Fq "\"$SIGNING_IDENTITY\"" <<< "$signing_identities" || \
        fail "signing identity '$SIGNING_IDENTITY' was not found in the keychain"
    SIGNING_IDENTITY_VALIDATED=1
}

verify_archive_metadata() {
    local archived_info="$ARCHIVE_PATH/Products/Applications/$APP_NAME/Contents/Info.plist"
    local archived_version
    local archived_build

    [[ -f "$archived_info" ]] || fail "archive did not contain '$APP_NAME'"
    archived_version="$("$PLIST_BUDDY" -c 'Print :CFBundleShortVersionString' "$archived_info")"
    archived_build="$("$PLIST_BUDDY" -c 'Print :CFBundleVersion' "$archived_info")"
    [[ "$archived_version" == "$VERSION" ]] || \
        fail "archive version is '$archived_version', expected '$VERSION'"
    [[ "$archived_build" == "$BUILD" ]] || \
        fail "archive build is '$archived_build', expected '$BUILD'"
}

verify_exported_app_metadata() {
    local exported_info="$EXPORTED_APP/Contents/Info.plist"
    local exported_version
    local exported_build

    [[ -f "$exported_info" ]] || fail "exported app did not contain an Info.plist"
    exported_version="$("$PLIST_BUDDY" -c 'Print :CFBundleShortVersionString' "$exported_info")"
    exported_build="$("$PLIST_BUDDY" -c 'Print :CFBundleVersion' "$exported_info")"
    [[ "$exported_version" == "$VERSION" ]] || \
        fail "exported app version is '$exported_version', expected '$VERSION'"
    [[ "$exported_build" == "$BUILD" ]] || \
        fail "exported app build is '$exported_build', expected '$BUILD'"
}

dry_verify_metadata() {
    local info_plist="$1"

    dry_command "$PLIST_BUDDY" -c 'Print :CFBundleShortVersionString' "$info_plist"
    dry_command "$PLIST_BUDDY" -c 'Print :CFBundleVersion' "$info_plist"
    dry_shell "test '<artifact-version>' = '$VERSION'"
    dry_shell "test '<artifact-build>' = '$BUILD'"
}

source_fingerprint() {
    {
        git rev-parse HEAD
        git diff --binary HEAD --
    } | git hash-object --stdin
}

verify_test_marker() {
    local tested_fingerprint
    local current_fingerprint

    [[ -f "$TESTED_MARKER" ]] || \
        fail "test output was not found; run 'scripts/release.sh test' first"
    tested_fingerprint="$(< "$TESTED_MARKER")"
    current_fingerprint="$(source_fingerprint)"
    [[ -n "$tested_fingerprint" && "$tested_fingerprint" == "$current_fingerprint" ]] || \
        fail "source changed since the last successful test; run 'scripts/release.sh test' again"
}

remove_project_derived_data() {
    local project_path="$REPO_ROOT/$PROJECT"
    local candidate
    local name
    local workspace

    if [[ -z "$DERIVED_DATA_ROOT" || ! -d "$DERIVED_DATA_ROOT" ]]; then
        return 0
    fi

    for candidate in "$DERIVED_DATA_ROOT/$DERIVED_DATA_PREFIX"-*; do
        [[ -d "$candidate" ]] || continue
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

stage_clean() {
    log "clean"

    [[ -n "$REPO_ROOT" && "$REPO_ROOT" != "/" ]] || \
        fail "refusing to clean: the repository root was not resolved"
    [[ -n "$DIST_DIR" && -n "$BUILD_DIR" ]] || \
        fail "refusing to clean: output directories were not resolved"

    # dist/ is a build output, not an archive; clean removes previously built DMGs too.
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

stage_test() {
    local tested_fingerprint

    # Test products need ad-hoc signatures to run on Apple Silicon without a development certificate.
    log "test"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        dry_command mkdir -p "$WORK_DIR"
        dry_command rm -f "$TESTED_MARKER"
        dry_command xcodebuild test \
            -project "$PROJECT" \
            -scheme "$SCHEME" \
            -derivedDataPath "$DERIVED_DATA_PATH" \
            -destination 'platform=macOS' \
            -only-testing:"AI usageTests" \
            CODE_SIGN_STYLE=Manual \
            CODE_SIGN_IDENTITY=- \
            DEVELOPMENT_TEAM=
        dry_command touch "$TESTED_MARKER"
        dry_shell "SOURCE_FINGERPRINT=\$({ git rev-parse HEAD; git diff --binary HEAD --; } | git hash-object --stdin)"
        dry_shell "printf '%s\\n' \"\$SOURCE_FINGERPRINT\" > '$TESTED_MARKER'"
        return 0
    fi

    mkdir -p "$WORK_DIR"
    rm -f "$TESTED_MARKER"
    echo "Running unit tests..."
    xcodebuild test \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        -destination 'platform=macOS' \
        -only-testing:"AI usageTests" \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY=- \
        DEVELOPMENT_TEAM=
    touch "$TESTED_MARKER"
    tested_fingerprint="$(source_fingerprint)"
    printf '%s\n' "$tested_fingerprint" > "$TESTED_MARKER"
}

stage_archive() {
    log "archive"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        dry_command rm -rf "$EXPORT_DIR"
        dry_command rm -f "$DMG_PATH" "$SUBMISSION_JSON" "$NOTARY_LOG" "$STAPLED_MARKER"
        dry_command rm -rf "$ARCHIVE_PATH"
        dry_command xcodebuild archive \
            -project "$PROJECT" \
            -scheme "$SCHEME" \
            -derivedDataPath "$DERIVED_DATA_PATH" \
            -configuration Release \
            -archivePath "$ARCHIVE_PATH" \
            MARKETING_VERSION="$VERSION" \
            CURRENT_PROJECT_VERSION="$BUILD"
        dry_verify_metadata \
            "$ARCHIVE_PATH/Products/Applications/$APP_NAME/Contents/Info.plist"
        return 0
    fi

    verify_test_marker

    rm -rf "$EXPORT_DIR"
    rm -f "$DMG_PATH" "$SUBMISSION_JSON" "$NOTARY_LOG" "$STAPLED_MARKER"
    rm -rf "$ARCHIVE_PATH"
    INCOMPLETE_DIR="$ARCHIVE_PATH"

    echo "Archiving the release build..."
    xcodebuild archive \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        -configuration Release \
        -archivePath "$ARCHIVE_PATH" \
        MARKETING_VERSION="$VERSION" \
        CURRENT_PROJECT_VERSION="$BUILD"

    verify_archive_metadata
    INCOMPLETE_DIR=""
}

stage_export() {
    local signature_details

    log "export"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        dry_verify_metadata \
            "$ARCHIVE_PATH/Products/Applications/$APP_NAME/Contents/Info.plist"
        dry_command rm -f "$DMG_PATH" "$SUBMISSION_JSON" "$NOTARY_LOG" "$STAPLED_MARKER"
        dry_command rm -rf "$EXPORT_DIR"
        if [[ "$SIGNING_IDENTITY_VALIDATED" -eq 0 ]]; then
            dry_shell "SIGNING_IDENTITIES=\$(security find-identity -v -p codesigning)"
            dry_shell "grep -Fq '\"$SIGNING_IDENTITY\"' <<< \"\$SIGNING_IDENTITIES\""
            SIGNING_IDENTITY_VALIDATED=1
        fi
        dry_command xcodebuild -exportArchive \
            -archivePath "$ARCHIVE_PATH" \
            -exportPath "$EXPORT_DIR" \
            -exportOptionsPlist "$SCRIPT_DIR/ExportOptions.plist"
        dry_command codesign --verify --deep --strict --verbose=2 "$EXPORTED_APP"
        dry_shell "codesign -dvv '$EXPORTED_APP'"
        dry_shell "grep -Fq 'Authority=$SIGNING_IDENTITY' <<< \"\$SIGNATURE_DETAILS\""
        dry_shell "grep -Fq 'flags=0x10000(runtime)' <<< \"\$SIGNATURE_DETAILS\""
        return 0
    fi

    [[ -d "$ARCHIVE_PATH" ]] || \
        fail "archive output was not found; run 'scripts/release.sh archive' first"
    verify_archive_metadata

    rm -f "$DMG_PATH" "$SUBMISSION_JSON" "$NOTARY_LOG" "$STAPLED_MARKER"
    rm -rf "$EXPORT_DIR"
    require_signing_identity
    INCOMPLETE_DIR="$EXPORT_DIR"

    echo "Exporting with Developer ID signing..."
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_DIR" \
        -exportOptionsPlist "$SCRIPT_DIR/ExportOptions.plist"

    [[ -d "$EXPORTED_APP" ]] || fail "export did not produce '$EXPORTED_APP'"

    echo "Verifying the app signature and hardened runtime..."
    codesign --verify --deep --strict --verbose=2 "$EXPORTED_APP"
    signature_details="$(codesign -dvv "$EXPORTED_APP" 2>&1)"
    echo "$signature_details"
    grep -Fq "Authority=$SIGNING_IDENTITY" <<< "$signature_details" || \
        fail "exported app is not signed by '$SIGNING_IDENTITY'"
    grep -Fq 'flags=0x10000(runtime)' <<< "$signature_details" || \
        fail "exported app does not have the hardened runtime enabled"
    INCOMPLETE_DIR=""
}

stage_package() {
    log "package"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        dry_verify_metadata "$EXPORTED_APP/Contents/Info.plist"
        dry_command rm -f "$SUBMISSION_JSON" "$NOTARY_LOG" "$STAPLED_MARKER"
        dry_command mkdir -p "$DIST_DIR"
        dry_command rm -f "$DMG_PATH"
        if [[ "$SIGNING_IDENTITY_VALIDATED" -eq 0 ]]; then
            dry_shell "SIGNING_IDENTITIES=\$(security find-identity -v -p codesigning)"
            dry_shell "grep -Fq '\"$SIGNING_IDENTITY\"' <<< \"\$SIGNING_IDENTITIES\""
            SIGNING_IDENTITY_VALIDATED=1
        fi
        dry_shell "STAGING_DIR=\$(mktemp -d '${TMPDIR:-/tmp}/ai-usage-dmg.XXXXXX')"
        dry_command ditto "$EXPORTED_APP" '<temporary-dmg-directory>/AI usage.app'
        dry_command ln -s /Applications '<temporary-dmg-directory>/Applications'
        dry_command hdiutil create \
            -volname "AI usage" \
            -srcfolder '<temporary-dmg-directory>' \
            -ov \
            -format UDZO \
            "$DMG_PATH"
        dry_shell "test -s '$DMG_PATH'"
        dry_command codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
        dry_command codesign --verify --verbose=2 "$DMG_PATH"
        dry_command hdiutil verify "$DMG_PATH"
        return 0
    fi

    [[ -d "$EXPORTED_APP" ]] || \
        fail "export output was not found; run 'scripts/release.sh export' first"
    verify_exported_app_metadata

    rm -f "$SUBMISSION_JSON" "$NOTARY_LOG" "$STAPLED_MARKER"
    mkdir -p "$DIST_DIR"
    rm -f "$DMG_PATH"
    INCOMPLETE_FILE="$DMG_PATH"
    require_signing_identity

    echo "Creating and signing the disk image..."
    STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ai-usage-dmg.XXXXXX")"
    ditto "$EXPORTED_APP" "$STAGING_DIR/$APP_NAME"
    ln -s /Applications "$STAGING_DIR/Applications"
    hdiutil create \
        -volname "AI usage" \
        -srcfolder "$STAGING_DIR" \
        -ov \
        -format UDZO \
        "$DMG_PATH"
    [[ -s "$DMG_PATH" ]] || fail "disk image was not created"
    codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
    codesign --verify --verbose=2 "$DMG_PATH"
    hdiutil verify "$DMG_PATH"
    INCOMPLETE_FILE=""

    echo "Packaged: $DMG_PATH"
}

print_dry_notary_submit() {
    local argument

    printf '[dry-run] xcrun notarytool submit %q' "$DMG_PATH"
    for argument in "${AUTH_ARGS[@]}"; do
        printf ' %q' "$argument"
    done
    printf ' --wait --timeout 2h --output-format json | tee %q\n' "$SUBMISSION_JSON"
}

stage_notarize() {
    local submit_exit_code
    local tee_exit_code
    local pipeline_status=()
    local notary_status
    local notary_id

    log "notarize"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        dry_verify_metadata "$EXPORTED_APP/Contents/Info.plist"
        dry_command xcrun notarytool history "${AUTH_ARGS[@]}"
        dry_command mkdir -p "$WORK_DIR"
        dry_command rm -f "$SUBMISSION_JSON" "$NOTARY_LOG" "$STAPLED_MARKER"
        print_dry_notary_submit
        dry_json_field status "$SUBMISSION_JSON"
        dry_json_field id "$SUBMISSION_JSON"
        dry_shell "test '<notarytool-exit>' = 0"
        dry_shell "test '<tee-exit>' = 0"
        dry_shell "test '<notarization-status>' = Accepted"
        dry_command xcrun notarytool log '<submission-id>' "${AUTH_ARGS[@]}" "$NOTARY_LOG"
        dry_command cat "$NOTARY_LOG"
        return 0
    fi

    [[ -s "$DMG_PATH" ]] || \
        fail "package output was not found; run 'scripts/release.sh package' first"
    [[ -d "$EXPORTED_APP" ]] || \
        fail "exported app was not found; run 'scripts/release.sh package' first"
    verify_exported_app_metadata

    resolve_notary_auth_args
    mkdir -p "$WORK_DIR"
    rm -f "$SUBMISSION_JSON" "$NOTARY_LOG" "$STAPLED_MARKER"

    echo "Submitting the disk image for notarization..."
    set +e
    xcrun notarytool submit "$DMG_PATH" "${AUTH_ARGS[@]}" --wait --timeout 2h --output-format json | \
        tee "$SUBMISSION_JSON"
    pipeline_status=("${PIPESTATUS[@]}")
    submit_exit_code=${pipeline_status[0]}
    tee_exit_code=${pipeline_status[1]}
    set -e

    [[ "$tee_exit_code" -eq 0 ]] || \
        fail "could not write the notarization result to '$SUBMISSION_JSON'"

    notary_status="$(json_field status "$SUBMISSION_JSON" 2>/dev/null || true)"
    notary_id="$(json_field id "$SUBMISSION_JSON" 2>/dev/null || true)"

    if [[ "$submit_exit_code" -ne 0 || "$notary_status" != "Accepted" ]]; then
        if [[ -n "$notary_id" ]]; then
            echo "Notarization submission ID: $notary_id" >&2
            if xcrun notarytool log "$notary_id" "${AUTH_ARGS[@]}" "$NOTARY_LOG" >/dev/null 2>&1; then
                cat "$NOTARY_LOG" >&2
            else
                echo "Could not retrieve the notarization log for submission $notary_id." >&2
            fi
        fi

        if [[ -n "$notary_status" ]]; then
            fail "notarization finished with status '$notary_status'"
        fi
        fail "notarytool did not return a readable submission result"
    fi
}

stage_staple() {
    local notary_status

    log "staple"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        dry_command rm -f "$STAPLED_MARKER"
        dry_json_field status "$SUBMISSION_JSON"
        dry_shell "test '<notarization-status>' = Accepted"
        dry_verify_metadata "$EXPORTED_APP/Contents/Info.plist"
        dry_command xcrun stapler staple "$DMG_PATH"
        dry_command xcrun stapler validate "$DMG_PATH"
        dry_command touch "$STAPLED_MARKER"
        return 0
    fi

    notary_status=""
    if [[ -f "$SUBMISSION_JSON" ]]; then
        notary_status="$(json_field status "$SUBMISSION_JSON" 2>/dev/null || true)"
    fi
    [[ "$notary_status" == "Accepted" ]] || \
        fail "an accepted notarization result was not found; run 'scripts/release.sh notarize' first"
    [[ -s "$DMG_PATH" ]] || \
        fail "notarized disk image was not found; run 'scripts/release.sh notarize' first"
    [[ -d "$EXPORTED_APP" ]] || \
        fail "exported app was not found; run 'scripts/release.sh notarize' first"
    verify_exported_app_metadata

    rm -f "$STAPLED_MARKER"
    echo "Stapling and validating the notarization ticket..."
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
    touch "$STAPLED_MARKER"
}

stage_verify() {
    local scratch_app
    local quarantine_timestamp
    local spctl_output

    log "verify"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        dry_verify_metadata "$EXPORTED_APP/Contents/Info.plist"
        dry_shell "MOUNT_DIR=\$(mktemp -d '${TMPDIR:-/tmp}/ai-usage-mount.XXXXXX')"
        dry_command hdiutil attach -readonly -nobrowse \
            -mountpoint '<temporary-mount-directory>' "$DMG_PATH"
        dry_shell "test -d '<temporary-mount-directory>/$APP_NAME'"
        dry_shell "test -L '<temporary-mount-directory>/Applications'"
        dry_shell "test \"\$(readlink '<temporary-mount-directory>/Applications')\" = /Applications"
        dry_command hdiutil detach '<temporary-mount-directory>'
        dry_shell "SCRATCH_DIR=\$(mktemp -d '${TMPDIR:-/tmp}/ai-usage-gatekeeper.XXXXXX')"
        dry_command ditto "$EXPORTED_APP" '<temporary-gatekeeper-directory>/AI usage.app'
        dry_shell "xattr -w com.apple.quarantine '0083;\$(printf %x \"\$(date +%s)\");Safari;' '<temporary-gatekeeper-directory>/AI usage.app'"
        dry_command spctl --assess --type execute --verbose=4 \
            '<temporary-gatekeeper-directory>/AI usage.app'
        dry_shell "grep -Fq accepted <<< \"\$SPCTL_OUTPUT\""
        dry_shell "grep -Fq 'source=Notarized Developer ID' <<< \"\$SPCTL_OUTPUT\""
        return 0
    fi

    [[ -f "$STAPLED_MARKER" ]] || \
        fail "stapled output was not found; run 'scripts/release.sh staple' first"
    [[ -s "$DMG_PATH" ]] || fail "stapled disk image was not found at '$DMG_PATH'"
    [[ -d "$EXPORTED_APP" ]] || fail "exported app was not found at '$EXPORTED_APP'"
    verify_exported_app_metadata

    echo "Checking the mounted disk image..."
    MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ai-usage-mount.XXXXXX")"
    hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_DIR" "$DMG_PATH" >/dev/null
    DMG_ATTACHED=1
    [[ -d "$MOUNT_DIR/$APP_NAME" ]] || fail "mounted disk image does not contain '$APP_NAME'"
    [[ -L "$MOUNT_DIR/Applications" ]] || \
        fail "mounted disk image does not contain an Applications symlink"
    [[ "$(readlink "$MOUNT_DIR/Applications")" == "/Applications" ]] || \
        fail "Applications symlink does not point to /Applications"
    hdiutil detach "$MOUNT_DIR" >/dev/null
    DMG_ATTACHED=0

    echo "Running the Gatekeeper assessment..."
    SCRATCH_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ai-usage-gatekeeper.XXXXXX")"
    scratch_app="$SCRATCH_DIR/$APP_NAME"
    ditto "$EXPORTED_APP" "$scratch_app"
    quarantine_timestamp="$(printf '%x' "$(date +%s)")"
    xattr -w com.apple.quarantine "0083;$quarantine_timestamp;Safari;" "$scratch_app"

    spctl_output=""
    if ! spctl_output="$(spctl --assess --type execute --verbose=4 "$scratch_app" 2>&1)"; then
        echo "$spctl_output" >&2
        fail "Gatekeeper rejected the notarized app"
    fi
    echo "$spctl_output"
    grep -Fq 'accepted' <<< "$spctl_output" || \
        fail "Gatekeeper output did not report acceptance"
    grep -Fq 'source=Notarized Developer ID' <<< "$spctl_output" || \
        fail "Gatekeeper did not report a notarized Developer ID source"

    echo
    echo "Release ready: $DMG_PATH"
}

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

print_install_manual_steps() {
    cat <<EOF
Cannot write to /Applications from this environment. Nothing was changed.
Run these commands in Terminal as the logged-in user:

  MNT=\$(mktemp -d /tmp/ai-usage-install.XXXXXX)
  hdiutil attach -readonly -nobrowse -mountpoint "\$MNT" "$DMG_PATH"
  pkill -f '^/Applications/AI usage\.app/Contents/MacOS/' || true
  rm -rf "/Applications/$APP_NAME"
  ditto "\$MNT/$APP_NAME" "/Applications/$APP_NAME"
  hdiutil detach "\$MNT"
  $PLIST_BUDDY -c 'Print :CFBundleShortVersionString' \\
      "/Applications/$APP_NAME/Contents/Info.plist"
EOF
}

stop_installed_app() {
    local pattern='^/Applications/AI usage\.app/Contents/MacOS/'
    local pids
    local surviving_pids
    local pid
    local attempt

    pids="$(pgrep -f "$pattern" 2>/dev/null || true)"
    if [[ -z "$pids" ]]; then
        return 0
    fi

    echo "Stopping the installed app (PID(s): ${pids//$'\n'/ })..."
    while IFS= read -r pid; do
        if [[ -n "$pid" ]]; then
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done <<< "$pids"

    for ((attempt = 0; attempt < 50; attempt++)); do
        if ! pgrep -f "$pattern" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.1
    done

    surviving_pids="$(pgrep -f "$pattern" 2>/dev/null || true)"
    if [[ -n "$surviving_pids" ]]; then
        echo "Force-stopping the installed app (PID(s): ${surviving_pids//$'\n'/ })..." >&2
        while IFS= read -r pid; do
            if [[ -n "$pid" ]]; then
                kill -KILL "$pid" 2>/dev/null || true
            fi
        done <<< "$surviving_pids"
        sleep 0.1
    fi

    surviving_pids="$(pgrep -f "$pattern" 2>/dev/null || true)"
    if [[ -n "$surviving_pids" ]]; then
        fail "could not stop the installed app (PID(s): ${surviving_pids//$'\n'/ })"
    fi
}

report_stray_copies() {
    local pattern='AI usage\.app/Contents/MacOS/'
    local pid
    local command

    while IFS= read -r pid; do
        if [[ -z "$pid" ]]; then
            continue
        fi
        command="$(ps -o command= -p "$pid" 2>/dev/null || true)"
        if [[ -z "$command" ]]; then
            continue
        fi
        if [[ "$command" == "/Applications/$APP_NAME/Contents/MacOS/"* ]]; then
            continue
        fi
        echo "Note: another AI usage copy is still running (PID $pid): $command"
    done < <(pgrep -f "$pattern" 2>/dev/null || true)

    return 0
}

stage_install() {
    local target="/Applications/$APP_NAME"
    local installed_version
    local installed_build
    local spctl_output
    local previous_copy=0

    log "install"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        dry_shell "test -s '$DMG_PATH'"
        dry_shell "test ! -e '$target' || test -d '$target'"
        dry_shell "test -w /Applications"
        dry_shell "INSTALL_PROBE_DIR=\$(mktemp -d /Applications/.ai-usage-install.XXXXXX)"
        dry_command rmdir '<temporary-install-probe>'
        dry_shell "INSTALL_MOUNT_DIR=\$(mktemp -d '${TMPDIR:-/tmp}/ai-usage-install.XXXXXX')"
        dry_command hdiutil attach -readonly -nobrowse \
            -mountpoint '<temporary-install-mount>' "$DMG_PATH"
        dry_shell "test -d '<temporary-install-mount>/$APP_NAME'"
        dry_command pgrep -f '^/Applications/AI usage\.app/Contents/MacOS/'
        dry_command kill -TERM '<pids>'
        dry_shell "for ((attempt = 0; attempt < 50; attempt++)); do pgrep -f '^/Applications/AI usage\.app/Contents/MacOS/' >/dev/null || break; sleep 0.1; done"
        dry_command pgrep -f '^/Applications/AI usage\.app/Contents/MacOS/'
        dry_command kill -KILL '<surviving-pids>'
        dry_command sleep 0.1
        dry_shell "SURVIVING_PIDS=\$(pgrep -f '^/Applications/AI usage\.app/Contents/MacOS/' || true)"
        dry_shell "test -z \"\$SURVIVING_PIDS\""
        dry_command rm -rf "$target"
        dry_command ditto "<temporary-install-mount>/$APP_NAME" "$target"
        dry_command hdiutil detach '<temporary-install-mount>'
        dry_shell "test -f '$target/Contents/Info.plist'"
        dry_command "$PLIST_BUDDY" -c 'Print :CFBundleShortVersionString' \
            "$target/Contents/Info.plist"
        dry_shell "test '<installed-version>' = '$VERSION'"
        dry_command "$PLIST_BUDDY" -c 'Print :CFBundleVersion' \
            "$target/Contents/Info.plist"
        dry_shell "test '<installed-build>' = '$BUILD' || echo a build-number warning"
        dry_command codesign --verify --deep --strict --verbose=2 "$target"
        dry_command spctl --assess --type execute --verbose=4 "$target"
        dry_command pgrep -f 'AI usage\.app/Contents/MacOS/'
        dry_shell "ps -o command= -p '<pid>'"
        return 0
    fi

    [[ -s "$DMG_PATH" ]] || \
        fail "release artifact was not found at '$DMG_PATH'; run 'scripts/release.sh all' first"
    if [[ -e "$target" && ! -d "$target" ]]; then
        fail "'$target' exists but is not an app bundle; remove it by hand first"
    fi

    if [[ ! -w /Applications ]]; then
        print_install_manual_steps >&2
        fail "/Applications is not writable"
    fi
    INSTALL_PROBE_DIR="$(mktemp -d /Applications/.ai-usage-install.XXXXXX 2>/dev/null)" || {
        print_install_manual_steps >&2
        fail "could not write to /Applications; nothing was changed"
    }
    rmdir "$INSTALL_PROBE_DIR"
    INSTALL_PROBE_DIR=""

    INSTALL_MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ai-usage-install.XXXXXX")"
    hdiutil attach -readonly -nobrowse -mountpoint "$INSTALL_MOUNT_DIR" "$DMG_PATH" >/dev/null
    INSTALL_DMG_ATTACHED=1
    [[ -d "$INSTALL_MOUNT_DIR/$APP_NAME" ]] || \
        fail "mounted disk image does not contain '$APP_NAME'"

    if [[ -d "$target" ]]; then
        previous_copy=1
    fi
    stop_installed_app
    if [[ "$previous_copy" -eq 1 ]]; then
        echo "Replacing the existing app in /Applications..."
    else
        echo "No previous /Applications copy was found; installing it now..."
    fi

    INSTALL_INCOMPLETE_TARGET="$target"
    rm -rf "$target"
    ditto "$INSTALL_MOUNT_DIR/$APP_NAME" "$target"
    INSTALL_INCOMPLETE_TARGET=""

    hdiutil detach "$INSTALL_MOUNT_DIR" >/dev/null
    INSTALL_DMG_ATTACHED=0
    [[ -f "$target/Contents/Info.plist" ]] || fail "install did not produce '$target'"
    installed_version="$("$PLIST_BUDDY" -c 'Print :CFBundleShortVersionString' \
        "$target/Contents/Info.plist")" || fail "could not read the installed app's version"
    [[ "$installed_version" == "$VERSION" ]] || \
        fail "installed app reports version '$installed_version', expected '$VERSION'"

    installed_build="$("$PLIST_BUDDY" -c 'Print :CFBundleVersion' \
        "$target/Contents/Info.plist" 2>/dev/null || true)"
    if [[ -z "$installed_build" ]]; then
        echo "Warning: could not read the installed app's build number." >&2
    elif [[ "$installed_build" != "$BUILD" ]]; then
        echo "Warning: installed app reports build '$installed_build', current checkout expects '$BUILD'." >&2
    fi

    codesign --verify --deep --strict --verbose=2 "$target"
    spctl_output=""
    if spctl_output="$(spctl --assess --type execute --verbose=4 "$target" 2>&1)"; then
        echo "$spctl_output"
    else
        echo "$spctl_output" >&2
        echo "Warning: Gatekeeper did not accept the installed copy; run the verify stage against the DMG for the release verdict." >&2
    fi

    report_stray_copies
    echo "Installed: $target ($installed_version)"
}

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

main() {
    local requested_stages=()
    local stages=()
    local stage
    local other_stage
    local all_count=0
    local notarize_requested=0
    local run_is_all=0
    local previous_rank=-1
    local current_rank

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -h|--help)
                help
                return 0
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --version)
                [[ "$#" -ge 2 ]] || {
                    usage
                    fail "--version requires a value"
                }
                VERSION_OVERRIDE="$2"
                VERSION_OVERRIDE_SET=1
                shift 2
                ;;
            --build)
                [[ "$#" -ge 2 ]] || {
                    usage
                    fail "--build requires a value"
                }
                BUILD_OVERRIDE="$2"
                BUILD_OVERRIDE_SET=1
                shift 2
                ;;
            all)
                requested_stages+=(all)
                all_count=$((all_count + 1))
                shift
                ;;
            # Keep this literal list in sync with PIPELINE_STAGES.
            clean|test|archive|export|package|notarize|staple|verify|install)
                requested_stages+=("$1")
                shift
                ;;
            *)
                usage
                fail "unknown stage or option '$1'"
                ;;
        esac
    done

    if [[ "${#requested_stages[@]}" -eq 0 ]]; then
        usage
        return 1
    fi
    if [[ "$all_count" -gt 0 && "${#requested_stages[@]}" -ne 1 ]]; then
        fail "all must be used by itself to avoid repeating release stages"
    fi

    for stage in "${requested_stages[@]}"; do
        if [[ "${#stages[@]}" -gt 0 ]]; then
            for other_stage in "${stages[@]}"; do
                [[ "$stage" != "$other_stage" ]] || \
                    fail "stage '$stage' was requested more than once"
            done
        fi
        stages+=("$stage")
    done

    if [[ "${stages[0]}" == "all" ]]; then
        run_is_all=1
        stages=("${STAGE_ORDER[@]}")
    else
        for stage in "${stages[@]}"; do
            current_rank="$(stage_rank "$stage")"
            [[ "$current_rank" -gt "$previous_rank" ]] || \
                fail "release stages must be requested in pipeline order"
            previous_rank="$current_rank"
        done
    fi

    initialize_checkout
    validate_environment
    resolve_release_metadata

    echo "Preparing release $VERSION (build $BUILD)..."

    for stage in "${stages[@]}"; do
        if [[ "$stage" == "notarize" ]]; then
            notarize_requested=1
            break
        fi
    done

    if [[ "$notarize_requested" -eq 1 ]]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            select_dry_run_auth_args
            log "notarization credential preflight"
            dry_command xcrun notarytool history "${AUTH_ARGS[@]}"
        else
            resolve_notary_auth_args
        fi
    fi

    for stage in "${stages[@]}"; do
        "stage_$stage"
    done

    if [[ "$run_is_all" -eq 1 ]]; then
        prune_intermediates
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
