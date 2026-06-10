# MyBriefing

> Your daily health and productivity command center — built natively for iPhone.

<p align="center">
  <img src="docs/screenshots/home.png" width="19%">
  <img src="docs/screenshots/calendar.png" width="19%">
  <img src="docs/screenshots/workout.png" width="19%">
  <img src="docs/screenshots/progress.png" width="19%">
  <img src="docs/screenshots/food.png" width="19%">
</p>

---

Start every day with a clear picture of what matters. MyBriefing pulls your sleep, mood, workouts, nutrition, and calendar into one focused dashboard — no friction, no noise.

## Features

- **Daily Briefing** — sleep score from HealthKit, mood slider, meal logging, and a workout status card. Swipe left/right through any day.
- **Calendar** — day, 3-day, week, and month views with a live hourly timeline. Long-press to create, move, or resize events. Full EventKit sync.
- **Workout** — split-based schedule (Push / Pull / Legs / Rest) with streak tracking and Calendar sync.
- **Food** — quick-pick meal templates and breakfast/dinner logging with time tracking.
- **Progress** — workout completion, mood trends, and sleep quality over time.
- **Zones** — define up to 3 daily focus zones that appear in the timeline and power the home screen widget.
- **Widget** — live zone timeline with sleep, mood, workout status, and calendar events at a glance.

## Install

```bash
git clone https://github.com/ygujer/MyBriefing.git
open MyBriefing/MyBriefing.xcodeproj
```

Select your development team in **Signing & Capabilities**, then run on a physical device (HealthKit requires real hardware).

## Requirements

- iOS 17+
- Xcode 15+
- Physical device recommended

---

<p align="center">
  <img src="https://img.shields.io/badge/SwiftUI-iOS%2017+-blue?logo=swift&logoColor=white">
  <img src="https://img.shields.io/badge/HealthKit-sleep%20%26%20fitness-red?logo=apple">
  <img src="https://img.shields.io/badge/EventKit-calendar%20sync-green?logo=apple">
  <img src="https://img.shields.io/badge/WidgetKit-home%20screen-orange?logo=apple">
</p>
