# Local AIBot

`Sources/WorkdayCore/AIBot.swift` is the entry point for the app's local automation decisions. It is a Swift value type using Foundation, independent of SwiftUI, AppKit, notifications, storage, and the network. Existing calculation and parsing types remain focused implementation modules behind it.

## Inputs and outputs

- `AIBotContext`: explicit time, settings, checkout, hydration, reminder ledger, and reminder pause. The host owns and persists this state.
- `inspect(context)`: work state, estimated earnings, checkout availability, and the daily report snapshot.
- `handle(event, in: context)`: typed, Codable actions for checkout, startup, or a reminder timer event.
- `nextReminder(in:)` and `upcomingOffwork(in:days:)`: timer and mobile notification planning.
- `importHolidayNotice(_:year:)`: validated holiday and make-up workday overrides plus a per-festival preview.
- `AIBotMessage`: stable source identifier, event time, and Chinese/English title/body variants shared by notifications and sprite chat.

```swift
let bot = AIBot()
let context = AIBotContext(now: clock.now, settings: settings,
    checkout: checkout, hydration: hydration, ledger: ledger, pause: pause)
let actions = bot.handle(.checkout, in: context)
// Host executes, in order: persist checkout, show panel, append the local message.
```

## Host adapters

`AppModel` executes checkout actions. `ReminderCoordinator` schedules native timers, asks the bot whether a reminder is due, reserves its ID in the persisted ledger, and then delivers the same message to chat, speech, and notifications. It rechecks policy before submitting an asynchronous notification. `AssistantStore` owns message history and unread state; SwiftUI owns typing and fade animations. `MobileModel` uses the same snapshot, checkout policy, and offwork planner while retaining its existing notification UI.

Actions describe a decision; they do not execute themselves. The host must apply `recordCheckout` and reserve reminder IDs before another evaluation or asynchronous work. A fresh context then prevents duplicates. Sleeping, locking, process lifecycle, delivery permissions, and file errors remain host responsibilities.

For a future local robot, supply a different host/adapter and add explicit events and actions here. Do not put platform calls, credentials, or an LLM dependency into local policies. The optional OpenRouter conversation service remains separate; proactive reports and reminders never call it.

## Holiday notice import

In Settings, choose a notice year, paste a Chinese notice, parse it, and review the festival dates and make-up workdays. Import merges only recognized dates into the settings draft. Save Settings to apply it; unrelated overrides and past daily reports are preserved.

The regex parser removes parenthetical weekday/lunar descriptions, recognizes numbered festival sections, expands inclusive ranges with omitted months, and handles explicit or implicit year boundaries. Only `放假` and `上班` clauses are imported. Optional leave suggestions are excluded. Invalid dates, conflicting instructions, unrecognized festival sections, and malformed workday lists reject the import. Tests cover the supplied 2022–2026 notices.
