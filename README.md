# claude-meter

A macOS menu bar app that displays Claude subscription usage.

## Running locally

Requires Xcode 15+ and macOS 14 (Sonoma) or newer. Claude desktop must be installed and signed in — claude-meter reads its cached OAuth token.

**From Xcode:**

```
open ClaudeMeter/ClaudeMeter.xcodeproj
```

Then hit ⌘R. The app has `LSUIElement=true`, so no Dock icon appears — look for the icon in the menu bar (top-right of the screen).

**From the command line:**

```
xcodebuild -project ClaudeMeter/ClaudeMeter.xcodeproj -scheme ClaudeMeter -configuration Debug build
APP=$(xcodebuild -project ClaudeMeter/ClaudeMeter.xcodeproj -scheme ClaudeMeter -configuration Debug -showBuildSettings | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2}')
open "$APP/ClaudeMeter.app"
```

The build lands in DerivedData, not in the repo.

**First launch:** macOS prompts once for Keychain access so claude-meter can read Claude desktop's cached OAuth token. Click Allow. Subsequent launches are silent.
