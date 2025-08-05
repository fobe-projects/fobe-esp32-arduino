#!/bin/bash -e

VERSION=`grep version= platform.txt | sed 's/version=//g'`

PWD=`pwd`
FOLDERNAME=`basename $PWD`
THIS_SCRIPT_NAME=`basename $0`
PACKAGE_FILES="
    $FOLDERNAME/boards.txt
    $FOLDERNAME/variants
    $FOLDERNAME/CMakeLists.txt
    $FOLDERNAME/idf_component.yml
    $FOLDERNAME/Kconfig.projbuild
    $FOLDERNAME/package.json
    $FOLDERNAME/platform.txt
    $FOLDERNAME/programmers.txt
    $FOLDERNAME/cores
    $FOLDERNAME/libraries
    $FOLDERNAME/tools/espota.exe
    $FOLDERNAME/tools/espota.py
    $FOLDERNAME/tools/gen_esp32part.py
    $FOLDERNAME/tools/gen_esp32part.exe
    $FOLDERNAME/tools/gen_insights_package.py
    $FOLDERNAME/tools/gen_insights_package.exe
    $FOLDERNAME/tools/partitions
    $FOLDERNAME/tools/ide-debug
    $FOLDERNAME/tools/pioarduino-build.py
"

mkdir -p build
rm -f build/$FOLDERNAME-$VERSION.tar.bz2
rm -f build/framework-arduinoesp32@$VERSION.zip
rm -f build/package_fobe_index.json

cd ..
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    tar -s "/$FOLDERNAME/$VERSION/g" \
        -cjf $FOLDERNAME-$VERSION.tar.bz2 \
        $PACKAGE_FILES
else
    # Linux
    tar --transform "s|$FOLDERNAME|$VERSION|g" \
        -cjf $FOLDERNAME-$VERSION.tar.bz2 \
        $PACKAGE_FILES
fi
cd -


mv ../$FOLDERNAME-$VERSION.tar.bz2 ./build/

cd ..
zip -r framework-arduinoesp32@$VERSION.zip \
    $PACKAGE_FILES
cd -
mv ../framework-arduinoesp32@$VERSION.zip ./build/

echo ""
echo "Package for Arduino BSP"
echo "Path: `pwd`/build/$FOLDERNAME-$VERSION.tar.bz2"
echo checksum: SHA-256:`sha256sum ./build/$FOLDERNAME-$VERSION.tar.bz2 | awk '{print $1}'`
echo size: `wc -c ./build/$FOLDERNAME-$VERSION.tar.bz2 | awk '{print $1}'` bytes
echo ""
echo "Package for PlatformIO"
echo "Path: `pwd`/build/framework-arduinoesp32@$VERSION.zip"
echo checksum: SHA-256:`sha256sum ./build/framework-arduinoesp32@$VERSION.zip | awk '{print $1}'`
echo size: `wc -c ./build/framework-arduinoesp32@$VERSION.zip | awk '{print $1}'` bytes

# Generate package_fobe_index.json based on template
echo ""
echo "Generating package_fobe_index.json..."

ARCHIVE_FILE="$FOLDERNAME-$VERSION.tar.bz2"
ARCHIVE_CHECKSUM=`sha256sum ./build/$ARCHIVE_FILE | awk '{print $1}'`
ARCHIVE_SIZE=`wc -c ./build/$ARCHIVE_FILE | awk '{print $1}'`

# Use sed to replace placeholders in template
sed -e "s|\"version\": \"\"|\"version\": \"$VERSION\"|g" \
    -e "s|\"url\": \"\"|\"url\": \"https://github.com/fobe-projects/fobe-esp32-arduino/releases/download/$VERSION/$ARCHIVE_FILE\"|g" \
    -e "s|\"archiveFileName\": \"\"|\"archiveFileName\": \"$ARCHIVE_FILE\"|g" \
    -e "s|\"checksum\": \"\"|\"checksum\": \"SHA-256:$ARCHIVE_CHECKSUM\"|g" \
    -e "s|\"size\": \"\"|\"size\": \"$ARCHIVE_SIZE\"|g" \
    package/package_esp32_index.template.json > build/package_fobe_index.json

echo "Generated: `pwd`/build/package_fobe_index.json"
echo "Version: $VERSION"
echo "Archive: $ARCHIVE_FILE"
echo "Checksum: SHA-256:$ARCHIVE_CHECKSUM"
echo "Size: $ARCHIVE_SIZE bytes"

