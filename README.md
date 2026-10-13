# OffWorkNow · 下班啦

English | [简体中文](README.zh-CN.md)

A little companion for counting down to the end of your workday, drinking water, and clocking out. macOS includes a menu bar utility and a persistent desktop pet; iOS includes an in-app companion and countdown. Both platforms share `WorkdayCore` for schedules, `Decimal` earnings estimates, clock-out records, overtime calculations, and hydration tracking. No third-party runtime dependencies, accounts, or network requests.

## App language

Both macOS and iOS support English and Simplified Chinese. On macOS, open Settings → General → Language; on iOS, open Settings → Language. Choose Follow System, 简体中文, or English. The choice is saved immediately and updates open views without restarting, independently of other settings drafts. Other system languages fall back to English. Salary remains denominated in CNY; the optional Chinese spoken-time feature still uses a Chinese voice.

## What's available

The single-frame custom animation issue is fixed: after you configure the grid of an imported sprite sheet, the app automatically calculates the regular animation frame count and reserves drinking frames separately. Existing configurations with only one frame show an explanation and a one-click correction; save to apply it. Turn off automatic mode to set the frame count manually.

The latest animation update adds a girl with a bun hairstyle. Six companions each have 6 actions × 6 frames, totaling **216 frames**. The office worker hums and sways, while the cat, dog, fish, and fox spirit dance to music. On the desktop, **click to change actions, double-click to change companions, and drag to reposition**. Playing the drinking animation manually does not add a hydration record. [Full action list](docs/PET_ANIMATIONS.md) · [Music animation preview](docs/assets/pets-music.gif).

October 13, 2026 update: added the fox spirit and drinking animations for five companions, double-click companion switching, custom PNG sprite-sheet imports, a calendar on launch, daily reports, local history, and three monthly line charts.

- The app opens the workday journal (收工日记). Reopen it from Daily Report (每日报表) in the menu bar panel. The calendar shows hand-drawn happy, resigned, or crying faces based on overtime; select a date to see water intake, earnings, and overtime messages. See [Daily report definitions](docs/DAILY_REPORTS.md).
- Settings → General → Custom Sprite Sheet (设置 → 通用 → 自定义序列帧) supports PNG grids, active frame counts, frame rates, loop modes, drinking frame ranges, and previews. Save to apply changes. See [Custom companions](docs/CUSTOM_PETS.md).
- Double-click the pet animation to cycle through companions; drag to move it. Recording a drink plays a dedicated animation: cats and dogs use bowls, the worker and fox spirit use cups, and the fish puffs its cheeks.
- Recorded dates remain in daily report history. Clocking out freezes report earnings and overtime, while the main panel continues to show scheduled earnings. Hiding earnings also applies to reports and charts. Dates not recorded by older versions cannot be recovered.
- The latest recorded validation passed **59 macOS core tests** and the iOS build; 150 animation frames and 6 report icons were verified to load. The sandbox grants read-only access to user-selected files for PNG imports.

[Fox spirit artwork](docs/assets/fox-portrait.png) · [Fox animations](docs/assets/fox-actions.gif) · [Drinking animations](docs/assets/pets-drinking.gif) · [Daily report with demo data](docs/assets/daily-report.png)

- Menu bar countdown, earnings, or icon-only mode; a popover panel and separate settings drafts.
- Desktop companions: **Off-Work Cat, Slacking Dog, Office Worker, Goldfish, Fox Spirit, and Bun-Haired Girl**. Japanese manga and watercolor artwork created with imagegen. Each companion has 4 action sets × 6 frames, plus 6 drinking frames and 6 headphone/music frames. Random actions include purring/arching, tail wagging/barking/bowing, frantic work/daydreaming/thinking, swimming/blowing bubbles, and fox tail swaying. Companions celebrate clock-out and pause when Reduce Motion is enabled or the computer sleeps.
- Pets display the countdown or elapsed overtime. Drag to reposition; the position is saved locally. General settings let you switch companions, hide the pet, or turn off always-on-top. Display changes trigger a check that the pet remains on screen.
- **Clock Out (打卡下班)** becomes available after work begins on a working day. It records the local time, stops that day's hourly, end-of-work, and overtime reminders, and freezes overtime. The next day resets the clock-out state automatically. Undo an accidental clock-out with confirmation in the panel; future events resume without replaying past ones.
- **Configurable overtime reminders, every 5 minutes by default**: until you clock out, notifications occur at interval multiples after the scheduled end time, such as 5, 10, and 15 minutes. Desktop messages alternate between playful prompts asking why you are still working and encouraging you to go home. Overtime reminders can be disabled; pausing health reminders does not affect them.
- **Hydration tracking**: each Drink a Cup (喝一杯水) click records one cup. The default is **500 ml per cup**, configurable as an integer from 1–2000 ml. View today's cup count and total volume, and undo the last cup. Records retain the cup size used at the time, so changing settings does not change previous totals. Tracking also works on days off and resets at the start of each calendar day in the work time zone. There is no prescribed daily hydration goal.
- Work time zone, weekdays, lunch breaks, date overrides, and flexible start times by date; hourly health reminders, optional Chinese speech, and end-of-work notifications on working days.
- Three earnings calculation methods, hidden earnings, notification permission guidance, native launch at login, and local settings reset.

Clock-out is a personal local record; it does not submit attendance to an employer. The main panel estimates earnings from the planned schedule. Daily reports freeze earnings at clock-out and **do not calculate overtime pay**. Reports retain daily hydration, estimated earnings, and overtime history.

The desktop has three layers: a hand-drawn water cup with the cup count and clickable digital time at the top, the pet animation in the middle, and an image-based Clock Out button at the bottom. The bottom button appears only after the scheduled end time on a working day when you have not clocked out, including the moment the countdown reaches zero and during overtime. It disappears after clock-out; reserved space prevents the pet from jumping. Click the time to open settings, drag the pet to move it, and right-click the cup to undo the last drink. Overtime displays as `+HH:MM:SS`; after clock-out, the actual clock-out time is shown. Overtime reminders use system notifications.

Actual SwiftUI renders of all six companions: [Light](docs/assets/pets-light.png) · [Dark](docs/assets/pets-dark.png) · [Frame animation preview](docs/assets/pets-actions.gif). See [PET_ART.md](docs/PET_ART.md) for artwork and action details.

## Running and installing on macOS

To create a drag-to-Applications installer, run `./scripts/build-dmg.sh` from the project directory. It produces a Release DMG for Apple Silicon and Intel. See [DMG.md](docs/DMG.md) for installation and distribution signing.

Requires macOS 13 or later. Built using Xcode 26.5 on Apple Silicon.

1. Open **`OffWorkNow.xcodeproj`**, select the **`OffWorkNow`** scheme and `My Mac`, then press ⌘R.
2. The local Debug build is **`build/下班啦.app`**, with ad-hoc signing. Double-click it or run `open 'build/下班啦.app'`.
3. The workday journal and daily reports appear on launch. Enable notifications explicitly in Notifications and Preferences → Reminders (通知与偏好设置 → 提醒). Closing the journal window leaves the desktop pet and menu bar running.
4. Install in a fixed location: quit the development copy, copy the `.app` to `~/Applications` or Applications using Finder, launch it there, and then enable launch at login. Avoid running the older 下班小助手, an Xcode copy, and the new app simultaneously; multiple instances can show duplicate menu items, pets, or reminders.
5. There is no persistent Dock icon. Open settings or quit from the menu bar panel. Clicking outside or pressing Escape closes the panel. Closing settings cancels the draft without quitting the app.

macOS controls the menu bar position; hold Command to drag it. Use icon-only mode when space is limited. The initial work time zone is taken from the system and does not automatically change when you travel. Defaults are Monday–Friday, 09:00–18:00, with lunch from 12:00–13:00 and monthly salary left blank.

Rebuild locally:

```sh
./scripts/build-app.sh
open 'build/下班啦.app'
```

This script creates a Debug app for the host architecture: arm64 on Apple Silicon or x86_64 on Intel. The bundle ID remains `com.workdaybuddy.app`, and core source names are retained to reduce migration work. Product display names and built artifacts use 下班啦. macOS App Sandbox is enabled, and the system stores preferences in the app container. Preference migration from older non-sandboxed development builds requires testing on a real machine; automatic access to an existing salary across containers is not guaranteed.

Ad-hoc signing is not App Store distribution signing, and the app is not notarized. Moving, downloading, or using it on another machine may trigger Gatekeeper prompts. See [Distribution and installation](docs/APP_STORE.md) for the App Store workflow.

## iOS companion target

Select the **`OffWorkNow-iOS`** scheme in the same project. Requires iOS 16 or later and supports iPhone/iPad. Run on an installed simulator; physical devices require your own Team in Signing & Capabilities.

iOS supports all six built-in animated companions, custom sprite sheets, the launch calendar and daily reports, countdowns, earnings estimates, schedule/lunch/weekday/time-zone/date-override settings, clock-out, overtime duration and rotating messages, and hydration tracking with configurable cup sizes. Data stays on that device; **there is no cross-device sync**. There is no floating pet across other apps or Widget extension.

- End-of-work notifications require explicit user authorization and schedule working-day events for the next **7 days**. Opening the app or saving settings rebuilds the schedule. iOS manages these local notifications in the background. Clocking out cancels that day's pending end-of-work notification.
- Overtime messages appear inside the app. iOS does not run the pet, speech, or a continuous timer every 5 minutes in the background, and does not promise background notifications at that interval. Hourly health reminders/speech, desktop always-on-top, and launch at login are currently macOS features.
- The iOS Simulator target has compiled successfully. Simulator interaction, physical-device notifications, and App Store acceptance remain unverified.

## Schedule and earnings calculations

Settings use drafts, centralized validation, and explicit saving. A blank monthly salary differs from zero. Amounts range from CNY 0–10,000,000 with up to two decimal places; standard thousands separators are supported, and calculations use `Decimal`. Overnight shifts are unsupported, and at least one regular working day is required. With lunch enabled, start < lunch start < lunch end < finish. Date overrides take precedence over weekdays; holidays and compensatory working days are not detected automatically.

Daily pay Q uses one of three mutually exclusive methods:

| Method | Daily pay |
|---|---|
| Fixed monthly paid days (default 21.75, configurable from 1–31) | Monthly salary ÷ paid days |
| Scheduled working days in the current month | Monthly salary ÷ working days calculated from weekdays and date overrides in the calendar month; a zero count shows an explanation |
| Custom daily pay | Entered daily amount; monthly salary is retained but not used |

`Today's estimated earnings = Q × elapsed effective working seconds / total effective working seconds`. The app recalculates from the current absolute time instead of accumulating rounded amounts; rounding to cents happens only for display. Earnings and progress pause during lunch while the countdown continues. Earnings are zero before work, capped after work, and zero on days off. The fixed-day method does not guarantee that a calendar month's total equals the monthly salary. Sleep and shutdown do not subtract planned working time.

Example: 21750 / 21.75 gives daily pay of 1000. A 09:00–18:00 schedule with lunch removed contains 8 working hours. Earnings are 375 at 12:30 and 625 at 15:00, with 62.5% progress and 3 hours remaining. At 18:00, earnings cap at 1000. Subsequent overtime reminders do not increase earnings.

Hiding earnings applies to the menu bar, panel, and settings preview. Notifications, speech, and logs never include salary. Saving a new schedule recalculates the whole day's estimate; segmented earnings are not recorded. Resetting defaults requires confirmation, clears the draft salary/date overrides and preferences, and disables launch at login. It does not reset system notification authorization or delete local clock-out and today's hydration records.

The regular start time defaults to 09:00 and can be changed in schedule settings. Override individual dates using Today's Start · Flexible Adjustment (今日上班 · 弹性调整) in the menu bar panel, or add/remove date overrides in settings. Other dates are unaffected. The day's start must precede its finish. Only overlapping lunch time is deducted; a 13:30 start does not deduct 12:00–13:00 lunch. Changes immediately recalculate earnings, progress, and hourly reminders.

Overtime reminder intervals are configured in reminder settings as integers from 1–240 minutes, defaulting to 5. Changes schedule future events only. Already-occurring overlapping events are deduplicated by their shared identifier, and past reminders are not replayed.

All times use a Gregorian calendar in the configured work time zone. Nonexistent daylight-saving times use the next valid time; repeated times use the first occurrence. Working duration uses actual elapsed intervals. A notice appears when the work and system time zones differ. Overtime ends at the end of that calendar day in the work time zone and does not carry across midnight.

## macOS reminders, permissions, and limitations

`ReminderCoordinator` manages hourly, end-of-work, and overtime events with a single timer for the next event. Events are reserved persistently before delivery, with separate notification/speech states to prevent duplicates after restarts or clock changes. Settings changes reschedule future events. Reserving before delivery can miss an event if the process exits midway; the design prioritizes avoiding duplicates.

- Hourly reminders fire only at full hours within effective working periods. A full hour at work start or lunch end is eligible; lunch start is excluded, and the scheduled finish sends only the end-of-work notification.
- Launching within 10 seconds after a full hour may deliver that hourly reminder. Missed end-of-work and overtime events are not replayed. Wake skips past events; the next overtime reminder remains aligned to scheduled finish + an integer multiple of the interval.
- Pause for one hour uses a real `Date`; pausing until work ends is also supported. Pausing affects only hourly reminders and does not enable a disabled hourly setting. End-of-work and overtime reminders remain active. Clocking out stops all regular reminders for that day.
- Each of three health message categories has six messages. The app first selects evenly among enabled categories, then picks a message without consecutive repeats. With all categories disabled, it uses a gentle rest message. Test reminders are clearly labeled and do not affect the real schedule.
- Other features work if notifications are denied. Enable them in System Settings → Notifications → 下班啦. Focus modes, notification style, and sound are controlled by the system. The settings URL may open the general Notifications page on some OS versions.
- Chinese speech is off by default and independent of notification permission. It is used only for hourly reminders, requires an available system Chinese voice and a verifiably unlocked console session, and does not download voices, read the screen, or require additional accessibility permissions. If session state cannot be determined reliably, speech remains silent; settings explain this behavior.
- Quitting clears the app's pending notifications and stops reminders. There is no background daemon, forced wake, or sleep prevention. The system may delay or silence submitted notifications; precise delivery or withdrawal of already-delivered notifications is not guaranteed.

Launch at login uses `SMAppService.mainApp`, reports the actual registration state, and registers only when settings are saved. Failures are explained inline; when system approval is needed, a Login Items shortcut is provided. Installation at a fixed location and correct signing affect registration. Launch after an actual login remains unverified. No user login item was registered during development validation.

## Tests, source, and privacy

```sh
xcodebuild -project OffWorkNow.xcodeproj -scheme OffWorkNow \
  -destination 'platform=macOS' -derivedDataPath build/OffWorkNowDerivedData \
  test CODE_SIGN_IDENTITY=-
swift test --scratch-path build/swift-package
xcodebuild -project OffWorkNow.xcodeproj -scheme OffWorkNow-iOS \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/OffWorkNowIOSDerivedData \
  build CODE_SIGNING_ALLOWED=NO
```

The latest recorded Xcode macOS build and **all 59 core tests passed**, along with the iOS Simulator build. See [Validation records](docs/VALIDATION.md) for tests and pending manual checks, and [Requirements mapping](docs/REQUIREMENTS.md). The Xcode 26 XCTest runtime requires macOS 14 or later; the app still targets macOS 13, whose real-device compatibility remains unverified.

- `WorkdayCore`: cross-platform logic for work/earnings, settings migration, Clock, reminder scheduling, Checkout, and Hydration.
- `Sources/WorkdayBuddy`: macOS lifecycle, menu bar, desktop pet, welcome screen, settings, and system services.
- `Sources/OffWorkNowIOS`: iOS companion app and settings.
- `Sources/SharedUI/PetAvatar.swift`: frame playback and random actions. `PetArtwork.swift` caches transparent sprite sheets; `PetControls.swift` provides compact image buttons.
- `Resources/Assets.xcassets`: original cat and clock icons in macOS/iPhone/iPad/App Store sizes. Icon generation scripts are development tools only; the app does not depend on Pillow.
- `Configuration`: Info.plist files for both platforms, macOS sandbox entitlements, privacy manifest, and App Store export configuration.
- `scripts/archive-app-store.sh`: creates an archive when a developer account is available; does not upload or publish it.

Local UserDefaults stores schedules, salary, reminder deduplication, the most recent clock-out, today's hydration details, and historical daily reports. Copies of custom PNGs are stored in Application Support/OffWorkNow/CustomPets. There is no encryption, upload, or third-party analytics SDK; monthly salary is not logged. Settings include `schemaVersion`; new fields receive defaults, and damaged configurations are recovered with an explanation. Daily reports store summaries separately, retain history across days, and preserve damaged data with a warning. No calendar, location, contacts, screen recording, or accessibility permissions are required. PNG import reads only files explicitly selected by the user. The privacy manifest declares required reason `CA92.1` for UserDefaults.

To quit, choose Quit in the menu bar panel or right-click the pet and choose Quit OffWorkNow (退出下班啦). To uninstall, disable and save launch at login, quit, and delete the `.app`; App Store installations can also use system app management. Sandbox data may remain. If you want to remove it, quit first and manage `~/Library/Containers/com.workdaybuddy.app` in Finder, taking care to avoid other app containers. The older development command `defaults delete com.workdaybuddy.app` may not clear the new container's data. Uninstalling does not automatically reset system notification authorization.
