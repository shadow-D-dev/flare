# Flare

Flare v0.1 is a keyboard-first application launcher for macOS 14 Sonoma and
newer. It runs in the menu bar and uses native AppKit controls.

## Build and run

Open `Flare.xcodeproj` in Xcode 16 or newer. Select the **Flare** scheme and
**My Mac**, then press **⌘R**. The bolt in the menu bar gives you access to
**Open Flare**, **Refresh Applications**, the **Dark Mode** switch, and **Quit
Flare**.

To build and run from Terminal, use the selected Xcode installation.

```sh
xcodebuild -project Flare.xcodeproj -scheme Flare -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build build
open build/Build/Products/Release/Flare.app
```

The project uses local signing for development builds and has no external
dependencies.

## Use Flare

| Input             | Action                                                              |
| ----------------- | ------------------------------------------------------------------- |
| ⌥ Space (default) | Show or hide the launcher                                           |
| Type              | Filter the application list                                         |
| ↑ or ↓            | Move the selection while keeping focus in the search field          |
| Return            | Open the selected application or bring its running instance forward |
| Escape            | Dismiss the launcher                                                |

Choose **Launcher Shortcut** in the bolt menu to set a different trigger. Press
a key with Command, Control, or Option, or press a function key, then choose
**Save**. The setting takes effect immediately and persists across launches. To
return to **⌥ Space**, choose **Use Default** and then **Save**.

Flare opens 20% of the way from the center to the top of the usable display
under the pointer. A glass droplet fades in as it expands into the search bar,
then reveals the results. On dismissal, the bar holds its opacity for the first
40% of the contraction, then fades over the final 60%. When Reduce Motion is on,
both transitions are immediate.

Flare uses a frosted AppKit backdrop and follows the macOS appearance until you
flip the **Dark Mode** switch in the bolt menu. It remembers your selected mode
across launches.

The **Frosted Icons** switch in the bolt menu applies the frosted style to every
search result. Flare uses its bundled designs where available and styles the
original artwork as results appear. Turn off the switch to see the original
icons. Flare remembers the setting across launches.

An empty search shows the first seven applications in alphabetical order. Try
`saf` for Safari, `vsc` for Visual Studio Code, `chr` for Google Chrome, or
`term` for Terminal. If two applications share a name, Flare shows their paths
beside the names.

## Tests

Press **⌘U** in Xcode or run the shared scheme from Terminal. A temporary build
location also works for checkouts under Desktop, where macOS can restrict the
test runner’s file access.

```sh
xcodebuild -project Flare.xcodeproj -scheme Flare -destination 'platform=macOS' \
  -derivedDataPath "$(mktemp -d /private/tmp/flare-tests.XXXXXX)" test
```

The XCTest target compiles the same indexer, model, and search source files as
Flare. The tests cover installed web app names, ranking, substrings, word
prefixes, fuzzy matching, Unicode folding, empty queries, result limits, and
deterministic ordering of duplicate names.

### Manual macOS checklist

- With Finder or a text editor active, press **⌥ Space** and type immediately.
  Confirm the search field receives the text and the Dock stays free of a Flare
  icon.
- Use **⌥ Space** to open and close Flare repeatedly. Confirm the droplet grows
  into the search bar and the bar fades as it contracts on dismissal. Reopen
  during dismissal and confirm the new panel stays open with an empty search and
  the first row selected.
- Press **↓** and **↑**, then type another character. Confirm that the search
  field keeps focus and the best new result becomes selected.
- Open Calculator with **Return** while it is closed. With another app active,
  open Calculator again and confirm its existing window comes forward.
- Dismiss Flare with **Escape** and by clicking a window or the desktop. Confirm
  the next click or keystroke reaches the expected application.
- Switch apps with **⌘Tab** or switch Spaces while Flare is open. Open it again
  from a full-screen app and confirm the active Space stays in place.
- With two displays, move the pointer between them and open Flare on each.
  Disconnect the external display while Flare is open and check that the panel
  remains usable on the remaining display.
- Check light and dark appearances. Verify text, icons, and the selection remain
  legible. Try Reduce Motion and Reduce Transparency in System Settings.
- Type a query with no matches and press **Return**. Confirm Flare shows the
  empty result message and keeps the field editable.
- On an account without `~/Applications`, start Flare and confirm the system
  application directories still populate the results.
- Install a disposable test app in `~/Applications`, use **Refresh
  Applications**, and confirm it appears. Remove the test app with its result
  still indexed, press **Return**, and check the launch failure message. Refresh
  again and confirm the removed app disappears.
- With another launcher holding **⌥ Space**, start Flare and verify the shortcut
  notice and **Open Flare** fallback in the status menu. Release the shortcut
  and relaunch Flare to verify recovery.
- Set a new launcher shortcut, verify it opens and closes Flare from another
  app, and check that it survives quitting and reopening Flare. Try saving a
  conflicting shortcut and confirm the existing shortcut still works. Restore
  **⌥ Space** with **Use Default**.
- Choose **Quit Flare** from the status menu. Verify the bolt disappears and the
  shortcut is released.

## Architecture and performance

- `AppDelegate` owns the status item, Carbon registration, and serial discovery
  queue. It keeps the app index ready while the launcher is hidden and creates
  the launcher window when opened. A refresh replaces the search snapshot on the
  main thread while the previous snapshot remains available during the scan.
- `ApplicationIndexer` walks `/Applications`, `/System/Applications`,
  `~/Applications`, and `/System/Library/CoreServices/Applications`. It includes
  ordinary subdirectories such as Utilities and finds built-in tools such as
  Desk View and Wireless Diagnostics. Installed Chromium web apps, including
  Helium apps, appear under their bundle filenames and are also searchable by
  their original names. The indexer resolves symlinks and stores app metadata
  and bundled icon paths. `ApplicationIconLoader` decodes 56-pixel bitmaps for
  the current search results on demand.
- `ApplicationSearcher` folds names once per index and ranks exact, prefix,
  substring, word-prefix, and subsequence matches. It keeps only the requested
  top results. Name and canonical path determine ties.
- `LauncherWindowController` owns the nonactivating keyboard panel, table views,
  and a bounded icon cache for each presentation. Dismissal cancels pending icon
  work, clears the cache, and closes the keyboard panel. The temporary
  click-through window finishes the animation before the controller and its
  views are released. AppKit’s field editor handles text input, and
  `NSWorkspace` opens the selected bundle URL asynchronously.

### Measurements

Measured before the Liquid Glass animations were added, on Apple Silicon with
macOS 26.5.2 and 101 indexed applications.

| Metric                  | Result                                                            |
| ----------------------- | ----------------------------------------------------------------- |
| First shortcut reveal   | 163 ms                                                            |
| Warm shortcut reveal    | 33 ms median, 46 ms p95 across 20 reveals                         |
| In-memory search        | 0.040 ms median, 0.051 ms p95 across 2,800 optimized searches     |
| Idle physical footprint | 20.4 MiB before first reveal, 24.1 MiB after interaction          |
| Idle CPU                | About 0.003% of a core over a 3.2-second sample after interaction |

Shortcut timings begin with synthetic Option-Space input and end when
WindowServer reports the panel on screen. The first reveal exceeded the 50 ms
target on this run. The Release build contains both arm64 and x86_64 slices
targeting macOS 14. Desktop verification ran on one Apple Silicon display. Use
the checklist for multi-display behavior and earlier macOS releases.

With 99 indexed apps on the same Mac, switching from eager frosted rendering to
the results cache reduced idle physical footprint from 24.6 to 23.6 MiB after 12
open and close cycles with searches, and from 27.4 to 25.1 MiB after three index
refreshes. Resident size reached about 98 MiB during the run. It includes
resident shared frameworks and file mappings. Use `footprint -p Flare` to
compare against the physical footprint measurements.

In an offscreen benchmark with 111 indexed apps, deferring launcher creation and
decoding icons on demand reduced the physical footprint before first open from
16.1 to 9.4 MiB and resident size from 48.9 to 32.3 MiB. The launcher controller
and panel were released by the first sample 50 ms after each offscreen
dismissal. A live desktop run is needed to measure the animated window and its
backing stores.

## Troubleshooting

- **The launcher shortcut does nothing.** Open the bolt menu and choose
  **Launcher Shortcut** to assign an available combination. **Open Flare** also
  works if macOS rejects the registration. Apple documented Option-only Carbon
  shortcut restrictions in early macOS 15 releases.
  [Apple Developer Forums](https://developer.apple.com/forums/thread/763878)
- **A newly installed app is missing.** Choose **Refresh Applications** and
  verify that the app is an executable `.app` bundle under a scanned folder.
- **An app fails to open.** Refresh the index if the bundle moved or was
  removed. Try opening the bundle from Finder to see any macOS launch message.
  Flare records shortcut and launch error codes under `com.flarelauncher.Flare`
  in Console.
