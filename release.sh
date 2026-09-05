#!/bin/bash
# ShellCraft Release Script
# Automates: version bump → build → sign → notarize → package → tag → publish
#
# Usage:
#   ./release.sh                    # Interactive: prompts for version bump type
#   ./release.sh --bump patch       # Non-interactive: auto-selects bump type
#   ./release.sh --dry-run          # Preview without executing
#   ./release.sh --skip-notarize    # Skip notarization (testing)

set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────────────────

SCHEME="ShellCraft"
PROJECT="ShellCraft.xcodeproj"
PROJECT_YML="project.yml"
TEAM_ID="N9DRSTM2U6"
NOTARY_PROFILE="ShellCraft"
# Notarization auth, resolved in preflight. Preferred: the App Store Connect
# API key already in ~/.secrets-macbook-pro.env (APP_STORE_CONNECT_API_KEY_PATH,
# _KEY_ID, _ISSUER_ID), which needs no Apple ID password and nothing in the
# macOS Keychain. Fallback: the notarytool keychain profile above, which only
# exists on a Mac where `notarytool store-credentials` was run once.
NOTARY_ARGS=()
EXPORT_OPTIONS="ExportOptions.plist"
RELEASES_DIR="Releases"
SPARKLE_VERSION="2.9.6"
SPARKLE_TOOLS_DIR="${HOME}/.cache/sparkle/${SPARKLE_VERSION}"
APPCAST_PATH="${RELEASES_DIR}/appcast.xml"
FEED_URL="https://github.com/omarshahine/ShellCraft/releases/latest/download/appcast.xml"
BUILD_DIR="build"
ARCHIVE_PATH="${BUILD_DIR}/${SCHEME}.xcarchive"
EXPORT_PATH="${BUILD_DIR}/export"

# ─── Colors ─────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ─── CLI Argument Parsing ───────────────────────────────────────────────────────

DRY_RUN=false
SKIP_NOTARIZE=false
BUMP_TYPE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-notarize)
            SKIP_NOTARIZE=true
            shift
            ;;
        --bump)
            BUMP_TYPE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --bump TYPE        Version bump type: patch, minor, major, or custom"
            echo "  --dry-run          Preview version changes without executing"
            echo "  --skip-notarize    Skip notarization step (for testing)"
            echo "  -h, --help         Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# ─── Helper Functions ───────────────────────────────────────────────────────────

info()    { echo -e "${BLUE}▸${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
error()   { echo -e "${RED}✗${NC} $1"; }
header()  { echo -e "\n${BOLD}═══ $1 ═══${NC}\n"; }

cleanup() {
    local exit_code=$?
    if [[ -d "${BUILD_DIR}" && "${DRY_RUN}" == false ]]; then
        info "Cleaning up build artifacts..."
        rm -rf "${BUILD_DIR}"
    fi
    if [[ $exit_code -ne 0 ]]; then
        echo ""
        error "Release failed. See output above for details."
    fi
}

trap cleanup EXIT

# ─── Step 1: Preflight Checks ──────────────────────────────────────────────────

preflight_checks() {
    header "Preflight Checks"

    # Required tools
    local missing=()
    for tool in xcodegen gh xcrun xcodebuild ditto; do
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$tool")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing[*]}"
        echo "  Install with: brew install ${missing[*]}"
        exit 1
    fi
    success "All required tools available"

    # Developer ID signing capability
    # With CODE_SIGN_STYLE=Automatic and signingStyle=automatic in ExportOptions.plist,
    # Xcode can use cloud-managed Developer ID signing even without a local cert in
    # find-identity. The real gate is xcodebuild -exportArchive — if signing fails there,
    # we get a clear error. We just check for a valid team membership here.
    if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
        success "Local Developer ID Application certificate found"
    elif security find-certificate -a -c "Developer ID" /Users/"$(whoami)"/Library/Keychains/login.keychain-db &>/dev/null; then
        success "Developer ID signing available (Xcode managed)"
    else
        warn "No Developer ID certificate found — export may use Xcode cloud signing"
        echo "  If export fails, install a Developer ID Application certificate from:"
        echo "  https://developer.apple.com/account/resources/certificates/list"
    fi

    # Notarytool credentials: ASC API key first, keychain profile second.
    if [[ "${SKIP_NOTARIZE}" == false ]]; then
        if [[ -n "${APP_STORE_CONNECT_API_KEY_PATH:-}" && -n "${APP_STORE_CONNECT_API_KEY_ID:-}" \
              && -n "${APP_STORE_CONNECT_API_ISSUER_ID:-}" && -f "${APP_STORE_CONNECT_API_KEY_PATH}" ]]; then
            NOTARY_ARGS=(--key "${APP_STORE_CONNECT_API_KEY_PATH}" \
                         --key-id "${APP_STORE_CONNECT_API_KEY_ID}" \
                         --issuer "${APP_STORE_CONNECT_API_ISSUER_ID}")
            if xcrun notarytool history "${NOTARY_ARGS[@]}" >/dev/null 2>&1; then
                success "Notarytool: App Store Connect API key (${APP_STORE_CONNECT_API_KEY_ID})"
            else
                error "App Store Connect API key is set but notarytool rejected it"
                echo "  Check that the key has the Developer role or notarization access."
                exit 1
            fi
        elif ! xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" 2>/dev/null | head -1 | grep -q "Successfully"; then
            # Try another way to check — the profile might exist but have no history
            if ! security find-generic-password -l "com.apple.gk.notary-${NOTARY_PROFILE}" &>/dev/null 2>&1; then
                warn "Notarytool keychain profile '${NOTARY_PROFILE}' not found"
                echo ""
                echo "  To fix this, run:"
                echo "  xcrun notarytool store-credentials \"${NOTARY_PROFILE}\" \\"
                echo "    --apple-id YOUR_APPLE_ID \\"
                echo "    --team-id ${TEAM_ID}"
                echo ""
                echo "  Or use --skip-notarize to skip notarization."
                exit 1
            fi
            NOTARY_ARGS=(--keychain-profile "${NOTARY_PROFILE}")
            success "Notarytool keychain profile '${NOTARY_PROFILE}' found"
        else
            NOTARY_ARGS=(--keychain-profile "${NOTARY_PROFILE}")
            success "Notarytool keychain profile '${NOTARY_PROFILE}' found"
        fi
    else
        warn "Skipping notarization check (--skip-notarize)"
    fi

    # Sparkle signing key. Checked here so a missing key fails in seconds
    # rather than after a full archive-and-notarize cycle.
    if [[ -z "${SPARKLE_PRIVATE_KEY:-}" ]]; then
        error "SPARKLE_PRIVATE_KEY is not set"
        echo "  Every published build has to be signed with the EdDSA key whose"
        echo "  public half is baked into ShellCraft/Info.plist, or installed"
        echo "  copies will reject the update."
        echo ""
        echo "  It lives in ~/.secrets-macbook-pro.env — open a new shell, or:"
        echo "  source ~/.secrets-macbook-pro.env"
        exit 1
    fi
    success "Sparkle signing key present"

    # Git state
    if [[ -n "$(git status --porcelain)" ]]; then
        error "Working directory is not clean. Commit or stash changes first."
        git status --short
        exit 1
    fi
    success "Git working directory clean"

    local branch
    branch=$(git branch --show-current)
    if [[ "$branch" != "main" ]]; then
        error "Not on main branch (currently on '${branch}'). Switch to main first."
        exit 1
    fi
    success "On main branch"
}

# ─── Step 2: Version Prompt ────────────────────────────────────────────────────

prompt_version() {
    header "Version"

    # Parse current version from project.yml
    CURRENT_VERSION=$(grep 'MARKETING_VERSION:' "${PROJECT_YML}" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
    CURRENT_BUILD=$(grep 'CURRENT_PROJECT_VERSION:' "${PROJECT_YML}" | head -1 | sed 's/.*: *\([0-9]*\)/\1/')

    info "Current version: ${CURRENT_VERSION} (build ${CURRENT_BUILD})"

    # Parse version components
    IFS='.' read -ra VERSION_PARTS <<< "${CURRENT_VERSION}"
    local major="${VERSION_PARTS[0]:-0}"
    local minor="${VERSION_PARTS[1]:-0}"
    local patch="${VERSION_PARTS[2]:-}"

    # Calculate bump options
    if [[ -z "$patch" ]]; then
        # Two-part version (e.g., 1.0)
        PATCH_VERSION="${major}.${minor}.1"
    else
        # Three-part version (e.g., 1.0.1)
        PATCH_VERSION="${major}.${minor}.$((patch + 1))"
    fi
    MINOR_VERSION="${major}.$((minor + 1))"
    MAJOR_VERSION="$((major + 1)).0"
    NEW_BUILD=$((CURRENT_BUILD + 1))

    if [[ -z "${BUMP_TYPE}" ]]; then
        echo ""
        echo "  1) patch  → ${PATCH_VERSION}"
        echo "  2) minor  → ${MINOR_VERSION}"
        echo "  3) major  → ${MAJOR_VERSION}"
        echo "  4) custom"
        echo ""
        read -rp "  Select bump type [1-4]: " choice
        case $choice in
            1) BUMP_TYPE="patch" ;;
            2) BUMP_TYPE="minor" ;;
            3) BUMP_TYPE="major" ;;
            4) BUMP_TYPE="custom" ;;
            *) error "Invalid choice"; exit 1 ;;
        esac
    fi

    case "${BUMP_TYPE}" in
        patch)  NEW_VERSION="${PATCH_VERSION}" ;;
        minor)  NEW_VERSION="${MINOR_VERSION}" ;;
        major)  NEW_VERSION="${MAJOR_VERSION}" ;;
        custom)
            read -rp "  Enter version: " NEW_VERSION
            ;;
        *)
            error "Invalid bump type: ${BUMP_TYPE}. Use: patch, minor, major, custom"
            exit 1
            ;;
    esac

    echo ""
    info "New version: ${BOLD}${NEW_VERSION}${NC} (build ${NEW_BUILD})"
    echo ""

    if [[ "${DRY_RUN}" == true ]]; then
        success "Dry run complete. Would release v${NEW_VERSION} (build ${NEW_BUILD})"
        exit 0
    fi

    read -rp "  Proceed with release v${NEW_VERSION}? [y/N] " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        info "Aborted."
        exit 0
    fi
}

# ─── Step 3: Update Version ────────────────────────────────────────────────────

update_version() {
    header "Update Version"

    sed -i '' "s/MARKETING_VERSION: .*/MARKETING_VERSION: \"${NEW_VERSION}\"/" "${PROJECT_YML}"
    sed -i '' "s/CURRENT_PROJECT_VERSION: .*/CURRENT_PROJECT_VERSION: ${NEW_BUILD}/" "${PROJECT_YML}"

    success "Updated ${PROJECT_YML}: v${NEW_VERSION} (build ${NEW_BUILD})"
}

# ─── Step 4: Regenerate Xcode Project ──────────────────────────────────────────

regenerate_project() {
    header "Regenerate Xcode Project"

    info "Running xcodegen..."
    xcodegen generate --quiet

    # Icon Composer sed fix (required — see CLAUDE.md)
    sed -i '' 's|lastKnownFileType = folder; name = ShellCraft.icon; path = ShellCraft/ShellCraft.icon; sourceTree = SOURCE_ROOT;|lastKnownFileType = folder.iconcomposer.icon; path = ShellCraft.icon; sourceTree = "<group>";|' "${PROJECT}/project.pbxproj"

    success "Xcode project regenerated with icon fix"
}

# ─── Step 5: Build Archive ─────────────────────────────────────────────────────

build_archive() {
    header "Build Archive"

    info "Archiving ${SCHEME} (Release)..."

    local xcpretty_cmd="cat"
    if command -v xcpretty &>/dev/null; then
        xcpretty_cmd="xcpretty"
    fi

    xcodebuild archive \
        -project "${PROJECT}" \
        -scheme "${SCHEME}" \
        -configuration Release \
        -destination "generic/platform=macOS" \
        -archivePath "${ARCHIVE_PATH}" \
        DEVELOPMENT_TEAM="${TEAM_ID}" \
        CODE_SIGN_STYLE=Automatic \
        2>&1 | $xcpretty_cmd

    if [[ ! -d "${ARCHIVE_PATH}" ]]; then
        error "Archive failed — ${ARCHIVE_PATH} not found"
        echo "  Check the build log above for errors."
        exit 1
    fi

    success "Archive created: ${ARCHIVE_PATH}"
}

# ─── Step 6: Export Archive ─────────────────────────────────────────────────────

export_archive() {
    header "Export Archive"

    info "Exporting with Developer ID signing..."

    local xcpretty_cmd="cat"
    if command -v xcpretty &>/dev/null; then
        xcpretty_cmd="xcpretty"
    fi

    xcodebuild -exportArchive \
        -archivePath "${ARCHIVE_PATH}" \
        -exportPath "${EXPORT_PATH}" \
        -exportOptionsPlist "${EXPORT_OPTIONS}" \
        2>&1 | $xcpretty_cmd

    local app_path="${EXPORT_PATH}/${SCHEME}.app"
    if [[ ! -d "$app_path" ]]; then
        error "Export failed — ${app_path} not found"
        exit 1
    fi

    # Verify code signing
    info "Verifying code signature..."
    if codesign --verify --deep --strict "$app_path" 2>&1; then
        success "Code signature valid"
    else
        error "Code signature verification failed"
        exit 1
    fi

    local sign_info
    sign_info=$(codesign -dvv "$app_path" 2>&1 | grep "Authority=" | head -1)
    info "Signed by: ${sign_info#Authority=}"
}

# ─── Step 7: Notarize ──────────────────────────────────────────────────────────

notarize() {
    if [[ "${SKIP_NOTARIZE}" == true ]]; then
        warn "Skipping notarization (--skip-notarize)"
        return
    fi

    header "Notarize"

    local app_path="${EXPORT_PATH}/${SCHEME}.app"
    local zip_path="${BUILD_DIR}/${SCHEME}-notarize.zip"

    info "Creating zip for notarization..."
    ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"

    info "Submitting to Apple notary service (this may take a few minutes)..."
    local submit_output
    submit_output=$(xcrun notarytool submit "$zip_path" \
        "${NOTARY_ARGS[@]}" \
        --wait \
        2>&1)
    echo "$submit_output"

    if echo "$submit_output" | grep -q "status: Accepted"; then
        success "Notarization accepted"
    else
        error "Notarization failed"
        # Try to fetch the log for details
        local submission_id
        submission_id=$(echo "$submit_output" | grep "id:" | head -1 | awk '{print $NF}')
        if [[ -n "$submission_id" ]]; then
            echo ""
            info "Fetching notarization log..."
            xcrun notarytool log "$submission_id" \
                "${NOTARY_ARGS[@]}" \
                2>&1 || true
        fi
        exit 1
    fi

    info "Stapling notarization ticket..."
    xcrun stapler staple "$app_path"
    success "Notarization ticket stapled"

    info "Validating stapled ticket..."
    xcrun stapler validate "$app_path"
    success "Stapled ticket validated"
}

# ─── Step 8: Package ───────────────────────────────────────────────────────────

package() {
    header "Package"

    mkdir -p "${RELEASES_DIR}"

    local app_path="${EXPORT_PATH}/${SCHEME}.app"
    local release_zip="${RELEASES_DIR}/${SCHEME}-${NEW_VERSION}.zip"

    info "Creating release zip..."
    ditto -c -k --sequesterRsrc --keepParent "$app_path" "$release_zip"

    local size
    size=$(du -h "$release_zip" | cut -f1 | xargs)
    success "Release package: ${release_zip} (${size})"

    RELEASE_ZIP_PATH="$release_zip"
}

# ─── Step 8b: Sign for Sparkle and Build the Appcast ───────────────────────────

ensure_sparkle_tools() {
    if [[ -x "${SPARKLE_TOOLS_DIR}/bin/sign_update" ]]; then
        return
    fi
    info "Fetching Sparkle ${SPARKLE_VERSION} tools..."
    mkdir -p "${SPARKLE_TOOLS_DIR}"
    local tarball="${SPARKLE_TOOLS_DIR}/sparkle.tar.xz"
    curl -fsSL -o "$tarball" \
        "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
    tar xf "$tarball" -C "${SPARKLE_TOOLS_DIR}"
    success "Sparkle tools cached in ${SPARKLE_TOOLS_DIR}"
}

sign_and_appcast() {
    header "Sparkle Signature & Appcast"

    ensure_sparkle_tools

    # sign_update reads the key from stdin, so it never reaches the process
    # table and never touches the login keychain.
    local signature
    signature=$(printf '%s' "${SPARKLE_PRIVATE_KEY}" \
        | "${SPARKLE_TOOLS_DIR}/bin/sign_update" -f - -p "${RELEASE_ZIP_PATH}")
    if [[ -z "$signature" ]]; then
        error "Sparkle signing produced no signature"
        exit 1
    fi
    success "Signed ${RELEASE_ZIP_PATH##*/}"

    local length pubdate download_url notes_url
    length=$(stat -f%z "${RELEASE_ZIP_PATH}")
    pubdate=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")
    download_url="https://github.com/omarshahine/ShellCraft/releases/download/v${NEW_VERSION}/${RELEASE_ZIP_PATH##*/}"
    notes_url="https://github.com/omarshahine/ShellCraft/releases/tag/v${NEW_VERSION}"

    # A single-item appcast. Sparkle only ever needs the newest build it should
    # offer, and keeping one item means the feed cannot drift out of step with
    # what the release actually shipped.
    cat > "${APPCAST_PATH}" <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>ShellCraft</title>
        <link>${FEED_URL}</link>
        <description>Updates for ShellCraft</description>
        <language>en</language>
        <item>
            <title>${NEW_VERSION}</title>
            <pubDate>${pubdate}</pubDate>
            <sparkle:version>${NEW_BUILD}</sparkle:version>
            <sparkle:shortVersionString>${NEW_VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
            <sparkle:releaseNotesLink>${notes_url}</sparkle:releaseNotesLink>
            <enclosure url="${download_url}"
                       length="${length}"
                       type="application/octet-stream"
                       sparkle:edSignature="${signature}" />
        </item>
    </channel>
</rss>
APPCAST

    # Prove the feed parses before it is published; a malformed appcast silently
    # stops every installed copy from ever seeing another update.
    if ! xmllint --noout "${APPCAST_PATH}" 2>/dev/null; then
        error "Generated appcast is not well-formed XML"
        exit 1
    fi
    success "Appcast written and validated: ${APPCAST_PATH}"
}

# ─── Step 9: Commit and Tag ────────────────────────────────────────────────────

commit_and_tag() {
    header "Commit & Tag"

    info "Staging version changes..."
    git add "${PROJECT_YML}" "${PROJECT}/"

    info "Committing..."
    git commit -m "$(cat <<EOF
Bump version to ${NEW_VERSION} (build ${NEW_BUILD})

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
    )"
    success "Committed version bump"

    info "Creating tag v${NEW_VERSION}..."
    # Annotated, with a message: the global gitconfig sets tag.gpgsign, which
    # turns a lightweight `git tag` into a signed annotated tag and then dies
    # with "fatal: no tag message?" when there is no TTY (v1.1, 2026-09-05).
    git tag -a "v${NEW_VERSION}" -m "${SCHEME} v${NEW_VERSION}"
    success "Tag v${NEW_VERSION} created"

    info "Pushing to origin..."
    git push origin main
    git push origin "v${NEW_VERSION}"
    success "Pushed to origin with tag"
}

# ─── Step 10: Create GitHub Release ────────────────────────────────────────────

create_release() {
    header "GitHub Release"

    info "Creating release v${NEW_VERSION} on GitHub..."

    gh release create "v${NEW_VERSION}" "${RELEASE_ZIP_PATH}" "${APPCAST_PATH}" \
        --title "ShellCraft v${NEW_VERSION}" \
        --generate-notes \
        --notes-start-tag "$(git tag --sort=-v:refname | head -2 | tail -1 2>/dev/null || echo "")" \
        --verify-tag

    success "GitHub release created!"

    local release_url
    release_url=$(gh release view "v${NEW_VERSION}" --json url -q '.url')
    echo ""
    echo -e "  ${BOLD}${release_url}${NC}"
    echo ""
}

# ─── Main ───────────────────────────────────────────────────────────────────────

main() {
    echo ""
    echo -e "${BOLD}ShellCraft Release Script${NC}"
    echo ""

    if [[ "${DRY_RUN}" == false ]]; then
        preflight_checks
    fi
    prompt_version
    # prompt_version exits early if --dry-run
    update_version
    regenerate_project
    build_archive
    export_archive
    notarize
    package
    sign_and_appcast
    commit_and_tag
    create_release

    header "Done"
    success "ShellCraft v${NEW_VERSION} released successfully!"
}

main
