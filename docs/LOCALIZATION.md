# App language / App 内语言

Both platforms support English and Simplified Chinese, with a Follow System option. Unsupported system languages fall back to English. Chinese language variants resolve to Simplified Chinese.

- macOS: Settings → General → Language.
- iOS: Settings → Language.
- The selection is saved immediately in `appLanguage` in local UserDefaults. It is independent of the settings draft: cancelling other edits does not undo the language selection.
- Open views and macOS window/menu titles refresh without recreating settings drafts. Native date controls receive the selected locale. iOS reschedules pending end-of-work notifications in the selected language.
- Work schedules, time zones, clock-out records, hydration records, and report identifiers remain unchanged. Salary is still CNY. The explicit Chinese spoken-time option still uses Chinese speech. Delivered system notifications retain their original text.

## Implementation

`Sources/WorkdayCore/Localization.swift` resolves the language and loads shared JSON catalogs from the Swift package resource bundle. `L10n.text` looks up a key; `L10n.format` substitutes numbered placeholders once, preserving user-supplied placeholder-like text.

`Sources/SharedUI/AppLanguageView.swift` owns the observable language selection, picker, and locale wrapper. Localized views observe the shared store; AppKit-hosted roots and the iOS root receive the selected locale.

Add the same key to `Sources/WorkdayCore/Localization/en.json` and `zh-Hans.json`. Keep `{0}`, `{1}`, and printf placeholders consistent. Avoid caching translated strings in static constants; translate on access so changes apply immediately. Preserve stored enum raw values and date keys, and localize only display labels.

## Validation

- 70 Swift package core tests passed, including language resolution, persistence lookup, runtime switching, schedule compatibility, interpolation, catalog completeness, and placeholder parity.
- macOS Debug and iOS Simulator builds validated.
- Manual verification remains: switch languages with multiple windows open and an unsaved settings draft, relaunch to verify persistence, inspect long English labels and VoiceOver, and confirm pending iOS notification text on a device.


## Assistant and checklist UI audit — 2026-10-19

The macOS AI Assistant tab, assistant section heading, owner label, key-save feedback and usage labels now use the shared catalogs explicitly. The assistant role label in history uses the same `AI 助手` key. Validation messages linking to assistant settings resolve the localized text before applying the link, preserving the link in both languages.

`ReportTaskSection` observes `AppLanguageStore` directly so its title, grouped counts, empty state and tomorrow-continuation message refresh even when task values do not change. Editable rows already observe the same store, keeping save/cancel and completion accessibility labels current without replacing row identity or editing drafts. Task names remain user-authored text and are not translated.

The report preview harness accepts a language as its second argument after the output path, for example `en` or `zh-Hans`. The override uses the process-local volatile argument domain; it does not change the user's saved language preference.


Validation for this audit: 165 existing XCTest cases and four swift-testing cases passed; macOS Debug build succeeded. The actual SwiftUI preview harness rendered [English](assets/daily-report-checklist.png) and [Simplified Chinese](assets/daily-report-checklist-zh.png) using process-only overrides. Group labels and continuation copy changed; task text and completion state stayed the same. Native live-switch testing with a focused text editor remains manual QA.
