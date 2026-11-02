#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
xcodebuild -quiet -project Kill9.xcodeproj -scheme Kill9 -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
mkdir -p build/Release
ditto build/DerivedData/Build/Products/Release/Kill9.app build/Release/Kill9.app
/usr/bin/codesign --force --deep --sign - build/Release/Kill9.app
ditto -c -k --sequesterRsrc --keepParent build/Release/Kill9.app build/Kill9-macOS.zip
mkdir -p build/Implementation/Kill9
ditto Kill9 build/Implementation/Kill9/Kill9
ditto Kill9.xcodeproj build/Implementation/Kill9/Kill9.xcodeproj
ditto Tests build/Implementation/Kill9/Tests
ditto Scripts build/Implementation/Kill9/Scripts
cp Package.swift README.md DESIGN_SPEC.md .gitignore build/Implementation/Kill9/
ditto -c -k --sequesterRsrc --keepParent build/Implementation/Kill9 build/Kill9-Implementation.zip
echo "Built build/Release/Kill9.app, build/Kill9-macOS.zip, and build/Kill9-Implementation.zip"
