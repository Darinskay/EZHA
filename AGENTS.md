# AGENTS.md

## Checklist
- Capture the Yeja MVP scope and user flows at a high level.
- Record the agreed tech stack, data model, and AI estimation contract.
- Define UX principles, naming conventions, and workflow rules for Codex.
- Document dev/testing commands with clear placeholders where needed.
- Validate formatting, placeholders, and section order before summarizing.

## 1. Product Overview (MVP Scope)
- Yeja is an iOS calorie and macronutrient tracker.
- Features user sign up/login (using Supabase Auth).
- Allows users to set daily targets: calories, protein, carbs, fat.
- Daily logging by uploading a food photo or nutrition label photo or plain text. The app obtains an AI-based estimate of calories/macros, editable by the user before saving.
- After submission, displays a table of: Target vs Eaten vs % (plus Remaining).
- All daily entries are stored; users can access historical data (last 60 days).

## 2. Tech Stack (Decisions)
- iOS: Swift + SwiftUI
- Architecture: Lightweight MVVM
- Backend: Supabase (Auth, Postgres, Storage)
- Image uploads are stored in Supabase Storage.
- AI estimation is via server-side function (prefer Supabase Edge Function), which receives an image, queries a vision-capable model, and returns a strict JSON estimate.

## 3. UX / UI Principles
- Follow Apple Human Interface Guidelines.
- Employ modern SwiftUI layouts (good typography, hierarchy, empty states, responsive UX).
- "Trust but verify": Always show the AI estimate and confidence; user may edit before saving.
- Error handling and loading states must be present; use `[PLACEHOLDER]` where not yet implemented.

## 4. Data Model (Schema Sketch)
- Row Level Security (RLS) must be enforced so users only access their own data.

| Table        | Field         | Type                       | Notes                                 |
|--------------|---------------|----------------------------|---------------------------------------|
| profiles     | user_id       | uuid                       | Unique user identifier                |
|              | daily_targets | object                     | calories, protein, carbs, fat         |
|              | timestamps    | timestamptz                |                                       |
| food_entries | id            | uuid                       | Unique entry ID                       |
|              | user_id       | uuid                       | Foreign key to profiles               |
|              | date          | date (YYYY-MM-DD, user tz) | Entry date                            |
|              | calories      | number                     | Estimated/stored value                |
|              | protein       | number                     | Estimated/stored value                |
|              | carbs         | number                     | Estimated/stored value                |
|              | fat           | number                     | Estimated/stored value                |
|              | image_path    | string                     | Path in Supabase Storage              |
|              | ai_confidence | number?                    | [Optional] 0..1 confidence score      |
|              | ai_source     | enum                       | "food_photo" \| "label_photo" \| "unknown" |
|              | created_at    | timestamptz                | Entry timestamp                       |

## 5. AI Estimation Contract
- Strict JSON response format (fields must appear in this order). Only `confidence` is optional (if not calculable); all other fields are required.
- If a required field is missing or an error occurs, return a JSON error object with an explanation.

```json
{
  "calories": number,
  "protein": number,
  "carbs": number,
  "fat": number,
  "confidence": number,
  "source": "food_photo" | "label_photo" | "unknown",
  "notes": string
}
```

```json
{
  "error": "Missing required field: [field_name(s)]"
}
```

- For nutrition label photos: Prioritize parsing the label text.
- For food photos: Estimate based on typical portions; capture assumptions in `notes`.
- All values are estimates and must be user-editable before saving.
- If error handling is incomplete, mark it with `[PLACEHOLDER]` in implementation code.

## 6. Naming Conventions & Code Style
- Swift files: PascalCase (e.g., `TodayView.swift`, `FoodEntry.swift`).
- Types: PascalCase.
- Properties/functions: lowerCamelCase.
- Limit ViewModel size; avoid networking in Views.
- Centralize constants.
- Avoid "God files" (large, monolithic files).

## 7. Repo Workflow Rules for Codex
- Before code changes: scan and summarize impacted files.
- Make small, reviewable diffs.
- Never add secrets (or actual credentials) to the repo; use environment files/Xcode configs; supply `.env.example` with placeholders as needed.
- For new features: add at least basic error handling and show loading states, using `[PLACEHOLDER]` markers if incomplete.
- Prioritize simplicity over over-engineering.

## 8. Dev/Testing Commands
**How to run**
- `[PLACEHOLDER] Document the Xcode scheme and run steps.`

**How to test**
- If no tests yet exist: `[PLACEHOLDER] Add minimal unit/UI test targets in Xcode.`

```shell
# [PLACEHOLDER] Example command(s) if applicable.
```

## Validation Notes
- Sections are ordered per requirements and use Markdown headings.
- Tables and JSON use fenced code blocks and Markdown table syntax.
- Placeholders marked with `[PLACEHOLDER]` for missing configs, error handling, and commands.

