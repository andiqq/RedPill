This is Red Pill, a 3D OpenGL "Matrix" screensaver for Mac OS X.
Copyright © 2002-2012 mathew <meta@pobox.com>.

## About this fork

This is a fork of the original [lpar/RedPill](https://github.com/lpar/RedPill), modified in 2026 by
Andreas Plagens so that it builds and runs safely on current macOS versions. Problems with this
version belong at [andiqq/RedPill](https://github.com/andiqq/RedPill), not with the original author.

Changes from the original:

- Universal (Apple Silicon and Intel) build for macOS 12 or later, with a new Xcode project.
- Stops rendering when the screensaver is dismissed, even when macOS forgets to tell it to stop.
- Fixed out-of-bounds memory reads in the animation code.
- Sharp rendering on Retina displays, and reliable drawing on modern macOS.
- "Main screen only" now detects the main display correctly.
- The options sheet's OK and Cancel buttons close it again, and About opens this repository.
- Bundle identifier is `eu.plagens.RedPill`, so settings are stored separately from the original.

## Building and installing on a modern Mac

Red Pill builds as a universal (Apple Silicon and Intel) screensaver for macOS 12 or later.

1. Build the Release configuration, either:
   - in Xcode: open `RedPill.xcodeproj` and choose Product > Build For > Profiling
     (a plain Build uses the Debug configuration), then Product > Show Build Folder in Finder
     and open `Products/Release`; or
   - in Terminal: `xcodebuild -project RedPill.xcodeproj -scheme RedPill -configuration Release -derivedDataPath build build`,
     which puts the result in `build/Build/Products/Release`.
2. Double-click `RedPill.saver` (or copy it to `~/Library/Screen Savers`).
3. Pick "RedPill" in System Settings > Screen Saver.

When you replace an installed copy, quit System Settings and run `killall legacyScreenSaver`,
or macOS keeps using the old one.

The bundle is signed ad hoc so it runs on your own Mac. To give it to other people, sign it with a
Developer ID certificate and notarize it, or macOS Gatekeeper will refuse to load it.

The screensaver still uses OpenGL, which Apple has deprecated but which continues to work
(translated to Metal) on current macOS versions.

Red Pill is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
or visit [http://www.fsf.org/](http://www.fsf.org/)

Please note that Apple's terms and conditions on the App Store prohibit distribution of GPL-licensed software.
