#!/bin/bash
# Disable shellcheck warning about using 'cat' to read a file.
# Disable shellcheck warning about using individual redirections for each command.
# Disable shellcheck warning about $? uses.
# shellcheck disable=SC2002,SC2129,SC2181,SC2319

if [ ! "$GITHUB_EVENT_NAME" == "release" ]; then
    echo "Wrong event '$GITHUB_EVENT_NAME'!"
    exit 1
fi

EVENT_JSON=$(cat "$GITHUB_EVENT_PATH")

action=$(echo "$EVENT_JSON" | jq -r '.action')
if [ ! "$action" == "published" ]; then
    echo "Wrong action '$action'. Exiting now..."
    exit 0
fi

draft=$(echo "$EVENT_JSON" | jq -r '.release.draft')
if [ "$draft" == "true" ]; then
    echo "It's a draft release. Exiting now..."
    exit 0
fi

RELEASE_PRE=$(echo "$EVENT_JSON" | jq -r '.release.prerelease')
RELEASE_TAG=$(echo "$EVENT_JSON" | jq -r '.release.tag_name')
RELEASE_BRANCH=$(echo "$EVENT_JSON" | jq -r '.release.target_commitish')
RELEASE_ID=$(echo "$EVENT_JSON" | jq -r '.release.id')

echo "Event: $GITHUB_EVENT_NAME, Repo: $GITHUB_REPOSITORY, Path: $GITHUB_WORKSPACE, Ref: $GITHUB_REF"
echo "Action: $action, Branch: $RELEASE_BRANCH, ID: $RELEASE_ID"
echo "Tag: $RELEASE_TAG, Draft: $draft, Pre-Release: $RELEASE_PRE"

# Try extracting something like a JSON with a "boards" array/element and "vendor" fields
BOARDS=$(cat "$GITHUB_WORKSPACE/vendor.json" | grep -Pzo '(?s){.*}' | jq -r '.boards[]? // .boards? // empty' | xargs echo -n 2>/dev/null)
PLATFORM_NAME=$(cat "$GITHUB_WORKSPACE/vendor.json" | grep -Pzo '(?s){.*}' | jq -r '.platform_name? // empty' | xargs echo -n 2>/dev/null)
REPOSITORY_URL=$(cat "$GITHUB_WORKSPACE/vendor.json" | grep -Pzo '(?s){.*}' | jq -r '.repository.url? // empty' | xargs echo -n 2>/dev/null)
PACKAGER=$(cat "$GITHUB_WORKSPACE/vendor.json" | grep -Pzo '(?s){.*}' | jq -r '.packager? // empty' | xargs echo -n 2>/dev/null)
MAINTAINER=$(cat "$GITHUB_WORKSPACE/vendor.json" | grep -Pzo '(?s){.*}' | jq -r '.maintainer? // empty' | xargs echo -n 2>/dev/null)
WEBSITE=$(cat "$GITHUB_WORKSPACE/vendor.json" | grep -Pzo '(?s){.*}' | jq -r '.website? // empty' | xargs echo -n 2>/dev/null)
EMAIL=$(cat "$GITHUB_WORKSPACE/vendor.json" | grep -Pzo '(?s){.*}' | jq -r '.email? // empty' | xargs echo -n 2>/dev/null)
CATEGORY=$(cat "$GITHUB_WORKSPACE/vendor.json" | grep -Pzo '(?s){.*}' | jq -r '.category? // empty' | xargs echo -n 2>/dev/null)


SCRIPTS_DIR="./.github/scripts"
OUTPUT_DIR="$GITHUB_WORKSPACE/build"
PACKAGE_NAME="${PACKAGER}-esp32-arduino-$RELEASE_TAG"
PACKAGE_JSON_MERGE="$GITHUB_WORKSPACE/.github/scripts/merge_packages.py"
PACKAGE_JSON_TEMPLATE="$GITHUB_WORKSPACE/package/package_esp32_index.template.json"
PACKAGE_JSON_DEV="package_${PACKAGER}_esp32_dev_index.json"
PACKAGE_JSON_REL="package_${PACKAGER}_esp32_index.json"


if [ -n "${BOARDS}" ]; then
    echo "Releasing board(s): $BOARDS"
fi

if [ -n "${PLATFORM_NAME}" ]; then
    echo "Setting packager: $PLATFORM_NAME"
fi

if [ -n "${REPOSITORY_URL}" ]; then
    echo "Setting repository URL: $REPOSITORY_URL"
fi

if [ -n "${PACKAGER}" ]; then
    echo "Setting packager: $PACKAGER"
fi

if [ -n "${MAINTAINER}" ]; then
    echo "Setting maintainer: $MAINTAINER"
fi

if [ -n "${WEBSITE}" ]; then
    echo "Setting website: $WEBSITE"
fi

if [ -n "${EMAIL}" ]; then
    echo "Setting email: $EMAIL"
fi

if [ -n "${CATEGORY}" ]; then
    echo "Setting category: $CATEGORY"
fi

function get_file_size {
    local file="$1"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        eval "$(stat -s "$file")"
        local res="$?"
        echo "${st_size:?}"
        return $res
    else
        stat --printf="%s" "$file"
        return $?
    fi
}

function git_upload_asset {
    local name
    name=$(basename "$1")
    # local mime=$(file -b --mime-type "$1")
    curl -k -X POST -sH "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/octet-stream" --data-binary @"$1" "https://uploads.github.com/repos/$GITHUB_REPOSITORY/releases/$RELEASE_ID/assets?name=$name"
}

function git_safe_upload_asset {
    local file="$1"
    local name
    local size
    local upload_res

    name=$(basename "$file")
    size=$(get_file_size "$file")

    if ! upload_res=$(git_upload_asset "$file"); then
        >&2 echo "ERROR: Failed to upload '$name' ($?)"
        return 1
    fi

    up_size=$(echo "$upload_res" | jq -r '.size')
    if [ "$up_size" -ne "$size" ]; then
        >&2 echo "ERROR: Uploaded size does not match! $up_size != $size"
        #git_delete_asset
        return 1
    fi
    echo "$upload_res" | jq -r '.browser_download_url'
    return $?
}

function git_upload_to_pages {
    local path=$1
    local src=$2

    if [ ! -f "$src" ]; then
        >&2 echo "Input is not a file! Aborting..."
        return 1
    fi

    local info
    local type
    local message
    local sha=""
    local content=""

    info=$(curl -s -k -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3.object+json" -X GET "https://api.github.com/repos/$GITHUB_REPOSITORY/contents/$path?ref=gh-pages")
    type=$(echo "$info" | jq -r '.type')
    message=$(basename "$path")

    if [ "$type" == "file" ]; then
        sha=$(echo "$info" | jq -r '.sha')
        sha=",\"sha\":\"$sha\""
        message="Updating $message"
    elif [ ! "$type" == "null" ]; then
        >&2 echo "Wrong type '$type'"
        return 1
    else
        message="Creating $message"
    fi

    content=$(base64 -i "$src")
    data="{\"branch\":\"gh-pages\",\"message\":\"$message\",\"content\":\"$content\"$sha}"

    echo "$data" | curl -s -k -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3.raw+json" -X PUT --data @- "https://api.github.com/repos/$GITHUB_REPOSITORY/contents/$path"
}

function git_safe_upload_to_pages {
    local path=$1
    local file="$2"
    local name
    local size
    local upload_res

    name=$(basename "$file")
    size=$(get_file_size "$file")

    if ! upload_res=$(git_upload_to_pages "$path" "$file"); then
        >&2 echo "ERROR: Failed to upload '$name' ($?)"
        return 1
    fi

    up_size=$(echo "$upload_res" | jq -r '.content.size')
    if [ "$up_size" -ne "$size" ]; then
        >&2 echo "ERROR: Uploaded size does not match! $up_size != $size"
        #git_delete_asset
        return 1
    fi
    echo "$upload_res" | jq -r '.content.download_url'
    return $?
}

function merge_package_json {
    local jsonLink=$1
    local jsonOut=$2
    local old_json=$OUTPUT_DIR/oldJson.json
    local merged_json=$OUTPUT_DIR/mergedJson.json
    local error_code=0

    echo "Downloading previous JSON $jsonLink ..."
    curl -L -o "$old_json" "https://github.com/$GITHUB_REPOSITORY/releases/download/$jsonLink?access_token=$GITHUB_TOKEN" 2>/dev/null
    error_code=$?
    if [ $error_code -ne 0 ]; then
        echo "ERROR: Download Failed! $error_code"
        exit 1
    fi

    echo "Creating new JSON ..."
    set +e
    stdbuf -oL python "$PACKAGE_JSON_MERGE" "$jsonOut" "$old_json" > "$merged_json"
    set -e

    set -v
    if [ ! -s "$merged_json" ]; then
        rm -f "$merged_json"
        echo "Nothing to merge"
    else
        rm -f "$jsonOut"
        mv "$merged_json" "$jsonOut"
        echo "JSON data successfully merged"
    fi
    rm -f "$old_json"
    set +v
}

set -e

##
## PACKAGE ZIP
##

mkdir -p "$OUTPUT_DIR"
PKG_DIR="$OUTPUT_DIR/$PACKAGE_NAME"
PACKAGE_ZIP="$PACKAGE_NAME.zip"

echo "Updating submodules ..."
git -C "$GITHUB_WORKSPACE" submodule update --init --recursive > /dev/null 2>&1

mkdir -p "$PKG_DIR/tools"

# Copy all core files to the package folder
echo "Copying files for packaging ..."
if [ -z "${BOARDS}" ]; then
    # Copy all variants
    cp -f  "$GITHUB_WORKSPACE/boards.txt"                   "$PKG_DIR/"
    cp -Rf "$GITHUB_WORKSPACE/variants"                     "$PKG_DIR/"
else
    # Remove all entries not starting with any board code or "menu." from boards.txt
    cat "$GITHUB_WORKSPACE/boards.txt" | grep "^menu\."         >  "$PKG_DIR/boards.txt"
    for board in ${BOARDS} ; do
        cat "$GITHUB_WORKSPACE/boards.txt" | grep "^${board}\." >> "$PKG_DIR/boards.txt"
    done
    # Copy only relevant variant files
    mkdir "$PKG_DIR/variants/"
    board_list=$(cat "${PKG_DIR}"/boards.txt | grep "\.variant=" | cut -d= -f2)
    while IFS= read -r variant; do
        cp -Rf "$GITHUB_WORKSPACE/variants/${variant}"      "$PKG_DIR/variants/"
    done <<< "$board_list"
fi
cp -f  "$GITHUB_WORKSPACE/CMakeLists.txt"                   "$PKG_DIR/"
cp -f  "$GITHUB_WORKSPACE/idf_component.yml"                "$PKG_DIR/"
cp -f  "$GITHUB_WORKSPACE/Kconfig.projbuild"                "$PKG_DIR/"
cp -f  "$GITHUB_WORKSPACE/package.json"                     "$PKG_DIR/"
cp -f  "$GITHUB_WORKSPACE/programmers.txt"                  "$PKG_DIR/"
cp -Rf "$GITHUB_WORKSPACE/cores"                            "$PKG_DIR/"
cp -Rf "$GITHUB_WORKSPACE/libraries"                        "$PKG_DIR/"
cp -f  "$GITHUB_WORKSPACE/tools/espota.exe"                 "$PKG_DIR/tools/"
cp -f  "$GITHUB_WORKSPACE/tools/espota.py"                  "$PKG_DIR/tools/"
cp -f  "$GITHUB_WORKSPACE/tools/gen_esp32part.py"           "$PKG_DIR/tools/"
cp -f  "$GITHUB_WORKSPACE/tools/gen_esp32part.exe"          "$PKG_DIR/tools/"
cp -f  "$GITHUB_WORKSPACE/tools/gen_insights_package.py"    "$PKG_DIR/tools/"
cp -f  "$GITHUB_WORKSPACE/tools/gen_insights_package.exe"   "$PKG_DIR/tools/"
cp -Rf "$GITHUB_WORKSPACE/tools/partitions"                 "$PKG_DIR/tools/"
cp -Rf "$GITHUB_WORKSPACE/tools/ide-debug"                  "$PKG_DIR/tools/"
cp -f  "$GITHUB_WORKSPACE/tools/pioarduino-build.py"        "$PKG_DIR/tools/"

# Remove unnecessary files in the package folder
echo "Cleaning up folders ..."
find "$PKG_DIR" -name '*.DS_Store' -exec rm -f {} \;
find "$PKG_DIR" -name '*.git*' -type f -delete

##
## TEMP WORKAROUND FOR RV32 LONG PATH ON WINDOWS
##
RVTC_NAME="riscv32-esp-elf-gcc"
RVTC_NEW_NAME="esp-rv32"
X32TC_NAME="xtensa-esp-elf-gcc"
X32TC_NEW_NAME="esp-x32"

# Replace tools locations in platform.txt
echo "Generating platform.txt..."
cat "$GITHUB_WORKSPACE/platform.txt" | \
sed "s/version=.*/version=$RELEASE_TAG/g" | \
sed 's/tools\.esp32-arduino-libs\.path\.windows=.*//g' | \
sed 's/{runtime\.platform\.path}.tools.esp32-arduino-libs/\{runtime.tools.esp32-arduino-libs.path\}/g' | \
sed 's/{runtime\.platform\.path}.tools.xtensa-esp-elf-gdb/\{runtime.tools.xtensa-esp-elf-gdb.path\}/g' | \
sed "s/{runtime\.platform\.path}.tools.xtensa-esp-elf/\\{runtime.tools.$X32TC_NEW_NAME.path\\}/g" | \
sed 's/{runtime\.platform\.path}.tools.riscv32-esp-elf-gdb/\{runtime.tools.riscv32-esp-elf-gdb.path\}/g' | \
sed "s/{runtime\.platform\.path}.tools.riscv32-esp-elf/\\{runtime.tools.$RVTC_NEW_NAME.path\\}/g" | \
sed 's/{runtime\.platform\.path}.tools.esptool/\{runtime.tools.esptool_py.path\}/g' | \
sed 's/{runtime\.platform\.path}.tools.openocd-esp32/\{runtime.tools.openocd-esp32.path\}/g' > "$PKG_DIR/platform.txt"

if [ -n "${PLATFORM_NAME}" ]; then
    # Replace the entire name with vendor name in platform.txt
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/^name=.*/name=$PLATFORM_NAME/" "$PKG_DIR/platform.txt"
    else
        sed -i "s/^name=.*/name=$PLATFORM_NAME/" "$PKG_DIR/platform.txt"
    fi
fi

# Update package.json with vendor repository information
if [ -n "${REPOSITORY_URL}" ]; then
    echo "Updating package.json with repository information..."
    if [ -f "$PKG_DIR/package.json" ]; then
        # Use jq to update the repository URL in package.json
        jq --arg url "$REPOSITORY_URL" '.repository.url = $url' "$PKG_DIR/package.json" > "$PKG_DIR/package.json.tmp"
        mv "$PKG_DIR/package.json.tmp" "$PKG_DIR/package.json"
    fi
fi

# Add header with version information
echo "Generating core_version.h ..."
ver_define=$(echo "$RELEASE_TAG" | tr "[:lower:].\055" "[:upper:]_")
ver_hex=$(git -C "$GITHUB_WORKSPACE" rev-parse --short=8 HEAD 2>/dev/null)
echo \#define ARDUINO_ESP32_GIT_VER 0x"$ver_hex" > "$PKG_DIR/cores/esp32/core_version.h"
echo \#define ARDUINO_ESP32_GIT_DESC "$(git -C "$GITHUB_WORKSPACE" describe --tags 2>/dev/null)" >> "$PKG_DIR/cores/esp32/core_version.h"
echo \#define ARDUINO_ESP32_RELEASE_"$ver_define" >> "$PKG_DIR/cores/esp32/core_version.h"
echo \#define ARDUINO_ESP32_RELEASE \""$ver_define"\" >> "$PKG_DIR/cores/esp32/core_version.h"

# Compress package folder
echo "Creating ZIP ..."
pushd "$OUTPUT_DIR" >/dev/null
zip -qr "$PACKAGE_ZIP" "$PACKAGE_NAME"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create $PACKAGE_ZIP ($?)"
    exit 1
fi

# Calculate SHA-256
echo "Calculating SHA sum ..."
PACKAGE_PATH="$OUTPUT_DIR/$PACKAGE_ZIP"
PACKAGE_SHA=$(shasum -a 256 "$PACKAGE_ZIP" | cut -f 1 -d ' ')
PACKAGE_SIZE=$(get_file_size "$PACKAGE_ZIP")
popd >/dev/null
rm -rf "$PKG_DIR"
echo "'$PACKAGE_ZIP' Created! Size: $PACKAGE_SIZE, SHA-256: $PACKAGE_SHA"
echo

# Upload package to release page
echo "Uploading package to release page ..."
PACKAGE_URL=$(git_safe_upload_asset "$PACKAGE_PATH")
echo "Package Uploaded"
echo "Download URL: $PACKAGE_URL"
echo

##
## TEMP WORKAROUND FOR RV32 LONG PATH ON WINDOWS
##
RVTC_VERSION=$(cat "$PACKAGE_JSON_TEMPLATE" | jq -r ".packages[0].platforms[0].toolsDependencies[] | select(.name == \"$RVTC_NAME\") | .version" | cut -d '_' -f 2)
if [[ "$OSTYPE" == "darwin"* ]]; then
    RVTC_VERSION=$(date -j -f '%Y%m%d' "$RVTC_VERSION" '+%y%m')
else
    RVTC_VERSION=$(date -d "$RVTC_VERSION" '+%y%m')
fi
rvtc_jq_arg="\
    (.packages[0].platforms[0].toolsDependencies[] | select(.name==\"$RVTC_NAME\")).version = \"$RVTC_VERSION\" |\
    (.packages[0].platforms[0].toolsDependencies[] | select(.name==\"$RVTC_NAME\")).name = \"$RVTC_NEW_NAME\" |\
    (.packages[0].tools[] | select(.name==\"$RVTC_NAME\")).version = \"$RVTC_VERSION\" |\
    (.packages[0].tools[] | select(.name==\"$RVTC_NAME\")).name = \"$RVTC_NEW_NAME\" |\
    (.packages[0].platforms[0].toolsDependencies[] | select(.name==\"$X32TC_NAME\")).version = \"$RVTC_VERSION\" |\
    (.packages[0].platforms[0].toolsDependencies[] | select(.name==\"$X32TC_NAME\")).name = \"$X32TC_NEW_NAME\" |\
    (.packages[0].tools[] | select(.name==\"$X32TC_NAME\")).version = \"$RVTC_VERSION\" |\
    (.packages[0].tools[] | select(.name==\"$X32TC_NAME\")).name = \"$X32TC_NEW_NAME\""
cat "$PACKAGE_JSON_TEMPLATE" | jq "$rvtc_jq_arg" > "$OUTPUT_DIR/package-rvfix.json"
PACKAGE_JSON_TEMPLATE="$OUTPUT_DIR/package-rvfix.json"

# Update package template with vendor information
echo "Updating package template with vendor information..."
vendor_jq_arg=". "
if [ -n "${PACKAGER}" ]; then
    vendor_jq_arg="$vendor_jq_arg | .packages[0].name = \"$PACKAGER\""
    # Update all packager fields in toolsDependencies and tools
    vendor_jq_arg="$vendor_jq_arg | (.packages[0].platforms[0].toolsDependencies[] | select(.packager == \"esp32\")).packager = \"$PACKAGER\""
fi
if [ -n "${MAINTAINER}" ]; then
    vendor_jq_arg="$vendor_jq_arg | .packages[0].maintainer = \"$MAINTAINER\""
fi
if [ -n "${WEBSITE}" ]; then
    vendor_jq_arg="$vendor_jq_arg | .packages[0].websiteURL = \"$WEBSITE\""
fi
if [ -n "${EMAIL}" ]; then
    vendor_jq_arg="$vendor_jq_arg | .packages[0].email = \"$EMAIL\""
fi
if [ -n "${CATEGORY}" ]; then
    vendor_jq_arg="$vendor_jq_arg | .packages[0].platforms[0].category = \"$CATEGORY\""
fi
if [ -n "${PLATFORM_NAME}" ]; then
    vendor_jq_arg="$vendor_jq_arg | .packages[0].platforms[0].name = \"$PLATFORM_NAME\""
fi
if [ -n "${BOARDS}" ]; then
    # Create boards array from vendor boards by extracting names from boards.txt
    boards_json="["
    first=true
    for board in ${BOARDS}; do
        if [ "$first" = true ]; then
            first=false
        else
            boards_json="$boards_json,"
        fi
        # Extract board name from boards.txt
        board_name=$(cat "$GITHUB_WORKSPACE/boards.txt" | grep "^${board}\.name=" | cut -d= -f2 | head -1)
        if [ -z "$board_name" ]; then
            # Fallback: convert board ID to display name if not found in boards.txt
            board_name=$(echo "$board" | sed 's/_/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')
        fi
        boards_json="$boards_json{\"name\":\"$board_name\"}"
    done
    boards_json="$boards_json]"
    vendor_jq_arg="$vendor_jq_arg | .packages[0].platforms[0].boards = $boards_json"
fi

# Apply vendor updates to template
cat "$PACKAGE_JSON_TEMPLATE" | jq "$vendor_jq_arg" > "$OUTPUT_DIR/package-vendor.json"
PACKAGE_JSON_TEMPLATE="$OUTPUT_DIR/package-vendor.json"

##
## PACKAGE JSON
##

# Construct JQ argument with package data
jq_arg=".packages[0].platforms[0].version = \"$RELEASE_TAG\" | \
    .packages[0].platforms[0].url = \"$PACKAGE_URL\" |\
    .packages[0].platforms[0].archiveFileName = \"$PACKAGE_ZIP\" |\
    .packages[0].platforms[0].size = \"$PACKAGE_SIZE\" |\
    .packages[0].platforms[0].checksum = \"SHA-256:$PACKAGE_SHA\""

# Generate package JSONs
echo "Generating $PACKAGE_JSON_DEV ..."
cat "$PACKAGE_JSON_TEMPLATE" | jq "$jq_arg" > "$OUTPUT_DIR/$PACKAGE_JSON_DEV"
if [ "$RELEASE_PRE" == "false" ]; then
    echo "Generating $PACKAGE_JSON_REL ..."
    cat "$PACKAGE_JSON_TEMPLATE" | jq "$jq_arg" > "$OUTPUT_DIR/$PACKAGE_JSON_REL"
fi

# Figure out the last release or pre-release
echo "Getting previous releases ..."
releasesJson=$(curl -sH "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/$GITHUB_REPOSITORY/releases" 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "ERROR: Get Releases Failed! ($?)"
    exit 1
fi

set +e
prev_release=$(echo "$releasesJson" | jq -e -r ". | map(select(.draft == false and .prerelease == false)) | sort_by(.published_at | - fromdateiso8601) | .[0].tag_name")
prev_any_release=$(echo "$releasesJson" | jq -e -r ". | map(select(.draft == false)) | sort_by(.published_at | - fromdateiso8601)  | .[0].tag_name")
shopt -s nocasematch
if [ "$prev_release" == "$RELEASE_TAG" ]; then
    prev_release=$(echo "$releasesJson" | jq -e -r ". | map(select(.draft == false and .prerelease == false)) | sort_by(.published_at | - fromdateiso8601) | .[1].tag_name")
fi
if [ "$prev_any_release" == "$RELEASE_TAG" ]; then
    prev_any_release=$(echo "$releasesJson" | jq -e -r ". | map(select(.draft == false)) | sort_by(.published_at | - fromdateiso8601)  | .[1].tag_name")
fi
shopt -u nocasematch
set -e

echo "Previous Release: $prev_release"
echo "Previous (any)release: $prev_any_release"
echo

# Merge package JSONs with previous releases
if [ -n "$prev_any_release" ] && [ "$prev_any_release" != "null" ]; then
    echo "Merging with JSON from $prev_any_release ..."
    merge_package_json "$prev_any_release/$PACKAGE_JSON_DEV" "$OUTPUT_DIR/$PACKAGE_JSON_DEV"
fi

if [ "$RELEASE_PRE" == "false" ]; then
    if [ -n "$prev_release" ] && [ "$prev_release" != "null" ]; then
        echo "Merging with JSON from $prev_release ..."
        merge_package_json "$prev_release/$PACKAGE_JSON_REL" "$OUTPUT_DIR/$PACKAGE_JSON_REL"
    fi
fi

# Test the package JSONs

echo "Installing arduino-cli ..."
export PATH="/home/runner/bin:$PATH"
source "${SCRIPTS_DIR}/install-arduino-cli.sh"

# For the Chinese mirror, we can't test the package JSONs as the Chinese mirror might not be updated yet.

echo "Testing $PACKAGE_JSON_DEV install ..."

echo "Installing esp32 ..."
arduino-cli core install ${PACKAGER}:esp32 --additional-urls "file://$OUTPUT_DIR/$PACKAGE_JSON_DEV"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to install esp32 ($?)"
    exit 1
fi

echo "Compiling example ..."
# Get the first board from BOARDS if available, otherwise use esp32
if [ -n "${BOARDS}" ]; then
    FIRST_BOARD=$(echo "${BOARDS}" | awk '{print $1}')
    arduino-cli compile --fqbn ${PACKAGER}:esp32:${FIRST_BOARD} "$GITHUB_WORKSPACE"/libraries/ESP32/examples/CI/CIBoardsTest/CIBoardsTest.ino
else
    arduino-cli compile --fqbn ${PACKAGER}:esp32:esp32 "$GITHUB_WORKSPACE"/libraries/ESP32/examples/CI/CIBoardsTest/CIBoardsTest.ino
fi
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to compile example ($?)"
    exit 1
fi

echo "Uninstalling esp32 ..."
arduino-cli core uninstall ${PACKAGER}:esp32
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to uninstall esp32 ($?)"
    exit 1
fi

echo "Test successful!"

if [ "$RELEASE_PRE" == "false" ]; then
    echo "Testing $PACKAGE_JSON_REL install ..."

    echo "Installing esp32 ..."
    arduino-cli core install ${PACKAGER}:esp32 --additional-urls "file://$OUTPUT_DIR/$PACKAGE_JSON_REL"
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to install esp32 ($?)"
        exit 1
    fi

    echo "Compiling example ..."
    # Get the first board from BOARDS if available, otherwise use esp32
    if [ -n "${BOARDS}" ]; then
        FIRST_BOARD=$(echo "${BOARDS}" | awk '{print $1}')
        arduino-cli compile --fqbn ${PACKAGER}:esp32:${FIRST_BOARD} "$GITHUB_WORKSPACE"/libraries/ESP32/examples/CI/CIBoardsTest/CIBoardsTest.ino
    else
        arduino-cli compile --fqbn ${PACKAGER}:esp32:esp32 "$GITHUB_WORKSPACE"/libraries/ESP32/examples/CI/CIBoardsTest/CIBoardsTest.ino
    fi
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to compile example ($?)"
        exit 1
    fi

    echo "Uninstalling ${PACKAGER}:esp32 ..."
    arduino-cli core uninstall ${PACKAGER}:esp32
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to uninstall ${PACKAGER}:esp32 ($?)"
        exit 1
    fi

    echo "Test successful!"
fi

# Upload package JSONs

echo "Uploading $PACKAGE_JSON_DEV ..."
echo "Download URL: $(git_safe_upload_asset "$OUTPUT_DIR/$PACKAGE_JSON_DEV")"
echo "Pages URL: $(git_safe_upload_to_pages "$PACKAGE_JSON_DEV" "$OUTPUT_DIR/$PACKAGE_JSON_DEV")"
echo
if [ "$RELEASE_PRE" == "false" ]; then
    echo "Uploading $PACKAGE_JSON_REL ..."
    echo "Download URL: $(git_safe_upload_asset "$OUTPUT_DIR/$PACKAGE_JSON_REL")"
    echo "Pages URL: $(git_safe_upload_to_pages "$PACKAGE_JSON_REL" "$OUTPUT_DIR/$PACKAGE_JSON_REL")"
    echo
fi

set +e

##
## DONE
##
echo "DONE!"
