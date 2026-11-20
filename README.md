# ScreenTime

A KDE Plasma 6 panel widget that tracks how long you spend in each application today and shows a per-app breakdown.

## Screenshots

![Screen Time in a vertical panel, showing 3h 21m of total time](docs/images/widget.png)

*Compact view: total active time for today, shown in the panel.*

![Expanded popup listing apps with percentages and usage bars](docs/images/expanded.png)

*Expanded view: per-app time with usage bars. Click a browser to see time per page title. Lists the top 10 tabs per browser by default.*

## Features

- Total active time for the day shown in the panel
- Per-application breakdown with percentages and usage bars
- Browser windows can be expanded to show time per page title
- Steam games running under Proton, including non-Steam shortcuts, are
  recognised by name
- Pause and reset buttons
- Resets automatically at midnight

## Requirements

- KDE Plasma 6 (Tested on Wayland)
- `kpackagetool6` (part of KDE Frameworks; some distributions package it separately)

## Installation

### From Release Package
Simply run
```sh
kpackagetool6 --type Plasma/Applet --install screentime.plasmoid
```

### Source Build
Clone the repository, `cd` into it, and from the project directory:

```sh
kpackagetool6 --type Plasma/Applet --install .
```

### Add the Widget
Right-click the panel, choose **Add Widgets**, and search for "Screen Time". If it doesn't appear, restart the shell:

```sh
systemctl --user restart plasma-plasmashell
```

As a sanity check once the widget has loaded, run
```sh
kpackagetool6 --type Plasma/Applet --list
```

And check if `io.github.i-9028.screentime` is listed there. The listed name should be the same as the `Id` entry listed in [metadata.json](metadata.json).` 

## Update
From a release package:

```sh
kpackagetool6 --type Plasma/Applet --upgrade screentime.plasmoid
```

From a checkout of this repository,
```sh
kpackagetool6 --type Plasma/Applet --upgrade .
```

Then restart the shell so the new code is loaded:

```sh
systemctl --user restart plasma-plasmashell
```


## Uninstallation
To uninstall, remove the widget from your panel and check the name the applet has (with the sanity check above) and run,
```sh
kpackagetool6 --type Plasma/Applet --remove io.github.i-9028.screentime
```

The name after `--remove` should match the `Id` entry listed in [metadata.json](metadata.json).

Uninstalling does not remove your saved data. To remove it too, run
```sh
rm -r $HOME/.local/share/screentime
```

## Limitations

- Time keeps counting while the screen is locked or you're away, as long as a
  window stays active
- Steam game names come from the install folder, not the store title
- The data for only the current day gets stored, the data for the previous date gets cleared at midnight.
- Only browsers matching a built-in list (Firefox, Chromium, Chrome, Brave, Vivaldi, Edge, Opera, Falkon, LibreWolf, Zen, Floorp, Waterfox, Konqueror) get a per-page breakdown.
- Use a single instance of the widget; two instances would overwrite each other's saved data.

## Frequently Asked Questions (FAQ)

### How do I change the number of browser tabs tracked?
In [contents/ui/main.qml](contents/ui/main.qml), edit the `maxTabs` variable. It is currently set to 10. After editing the repository copy, run the `--upgrade` command above and restart the shell. (The installed copy is in `$HOME/.local/share/plasma/plasmoids/io.github.i-9028.screentime/contents/ui/main.qml`)

### Where is my data stored?
No data leaves your machine, it resides locally in `$HOME/.local/share/screentime/today.dat`. The file is base64-encoded text and contains app names and, for browsers, **page titles, including those from private windows.** You can change the location by editing `dataFile` and `dataDir` in [contents/ui/main.qml](contents/ui/main.qml).


## Planned
- Per-document time breakdown for Calibre’s E-book Viewer and Okular, using the same expandable row as browsers
- Add a separate human-readable version of `today.dat`.

## License
This project is licensed under the [MIT License](LICENSE).
