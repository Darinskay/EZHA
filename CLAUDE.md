# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

EZHA is a native iOS nutrition tracking app built with SwiftUI (iOS 18.5, Swift 5.0). Users log meals via photo, text, or saved foods. An AI service (Supabase Edge Functions calling OpenAI) estimates macros from photos/text. All data is stored in Supabase with RLS.

## Build & Run

- **IDE**: Xcode (open `EZHA.xcodeproj`)
- **Dependencies**: Swift Package Manager — the sole external dependency is the Supabase Swift SDK
- **Build**: `xcodebuild -scheme EZHA -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build`
- **No test suite yet** — test targets (EzhaTests, EzhaUITests) exist but contain no tests

## Architecture

**Pattern**: MVVM + Repository

```
EZHA/
├── EZHAApp.swift              # @main entry, SessionManager injection, OAuth URL handling
├── Models/                    # Codable structs mapping to Supabase tables
├── Views/                     # SwiftUI views
├── ViewModels/                # @MainActor classes with @Published state
├── Services/                  # Repositories (data access) + utilities
├── Theme.swift                # AppColors, gradients, Color extensions
└── Info.plist                 # Supabase credentials & OAuth config
```

### Key Architectural Decisions

- **All ViewModels** are `@MainActor final class` with `@Published` properties and `async` methods.
- **Repositories** are lightweight structs with static methods. They all use `SupabaseConfig.client` for DB access and `SupabaseConfig.currentUserId()` for the authenticated user.
- **Cross-view communication** uses `NotificationCenter` with custom names defined in `Services/Notifications.swift` (e.g., `foodEntrySaved`, `dayReset`, `activeDateChanged`, `switchToTodayTab`).
- **Auth flow**: `SessionManager` (EnvironmentObject) manages Supabase auth state. `RootView` conditionally shows `AuthLandingView` or `MainTabView`.
- **AI analysis**: `AIAnalysisService` invokes Supabase Edge Functions, supporting both streaming and non-streaming responses. Returns `MacroEstimate` with optional per-item breakdown.

### Data Flow for Logging a Meal

1. User opens `AddLogSheet` (photo/text) or `LogMealSheet` (saved food) or `MealQuickLogSheet` (saved meal)
2. ViewModel calls `AIAnalysisService` or computes macros from `SavedFood`
3. User reviews/edits estimates
4. ViewModel calls `FoodEntryRepository` to insert entry + items
5. Posts `foodEntrySaved` notification
6. `TodayViewModel` refreshes daily totals

## Supabase Backend

- **Schema**: `supabase/schema.sql` — 7 tables, all with RLS enabled
- **Migrations**: `supabase/migrations/` — applied in order
- **Tables**: `profiles`, `daily_targets`, `food_entries`, `food_entry_items`, `daily_summaries`, `saved_foods`, `saved_meal_ingredients`
- **Storage**: `food-images` bucket — images stored at `food-images/{user_id}/{entry_id}.jpg`
- **Config**: Supabase URL, anon key, and OAuth redirect are read from Info.plist keys (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_OAUTH_REDIRECT_URL`, `SUPABASE_OAUTH_CALLBACK_SCHEME`)

## Conventions

- **Swift ↔ DB mapping**: All models use `CodingKeys` to map camelCase Swift properties to snake_case database columns.
- **Saved foods** support two unit types: `per_100g` (macros scale linearly with grams) and `per_serving` (fixed macros per serving). `SavedFood.macros(for:)` handles the calculation.
- **Saved meals** (`is_meal = true` in `saved_foods`) have associated `saved_meal_ingredients` that scale proportionally via `SavedMealIngredient.scaled(to:)`.
- **Image processing**: `StorageService` resizes to max 1400px and compresses to 75% JPEG quality before upload.
- **Token refresh**: `SupabaseConfig.currentSession()` proactively refreshes tokens within a 5-minute buffer before expiry.
- **Theme colors**: Use `Color.appPrimary` (magenta) and `Color.appSecondary` (indigo). Gradients via `LinearGradient.purpleGradient`.

## Documentation

Additional context in `docs/`:
- `ai_estimation_contract.md` — AI request/response payload format
- `food_entries.md` — food_entries and food_entry_items schema details
- `backend-setup.md` — Supabase setup (bucket, env vars, SQL)
