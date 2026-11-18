# PhotoCleaner

Native SwiftUI iPhone app (iOS 17+), with two features:

1. **AI Privacy Scanner.** Uses the bundled Core ML model (`PhotoCleaner/ML/NSFW.mlmodel`, LOVOO GmbH, BSD license) to scan photos, screenshots, and 6 sampled frames from each video, all on the device. Flagged items are sorted by confidence and sit behind a Face ID lock. You review each one and choose Keep or Delete. Nothing is ever deleted automatically. Scan results are remembered, so "Scan new items" only checks photos added since the last scan.
2. **Swipe Photo Cleaner.** Swipe left to delete, right to keep, up to skip. Includes undo, progress tracking, date and type filters, and a review screen for everything marked to delete. Your decisions are saved between launches.

The app contains no networking code. Every deletion goes through PhotoKit, which shows iOS's own confirmation alert, and deleted items stay in Recently Deleted for 30 days.

## How it builds (no Mac needed)

- `project.yml` is an XcodeGen spec. The cloud Mac turns it into an Xcode project.
- `.github/workflows/build.yml` runs on every push to `main` and produces an **unsigned** `PhotoCleaner.ipa`. You download it from the run's **Artifacts** section.
- `codemagic.yaml` is an alternative builder that does the same thing.
- On a Windows PC, **Sideloadly** signs the .ipa with a free Apple ID and installs it on the iPhone. With a free Apple ID the app has to be re-signed every 7 days.

## Project layout

```
PhotoCleaner/
  App/            app entry, lifecycle (save + re-lock on background)
  Services/       PhotoKit, Core ML classifier, scan engine, stores, Face ID lock, log
  Views/          Home, Scanner (+ review pager), Swipe (+ filters, deletion review), Settings/Log
  ML/             NSFW.mlmodel + its license
  Resources/      app icon, accent color
```
