# Backend Setup

## Supabase SQL
- Apply `supabase/schema.sql` in the Supabase SQL editor or via Supabase CLI.
- Ensure RLS is enabled for `profiles`, `food_entries`, and `daily_summaries`.

## Storage
- Create a bucket named `food-images` (private).
- The app stores uploaded meal photos at `food-images/{user_id}/{entry_id}.jpg`.

## Environment
- `SUPABASE_URL`: [PLACEHOLDER] Supabase project URL
- `SUPABASE_ANON_KEY`: [PLACEHOLDER] Supabase anon key
- `SUPABASE_OAUTH_REDIRECT_URL`: [PLACEHOLDER] app scheme callback
- `OPENAI_API_KEY`: [PLACEHOLDER] OpenAI API key for Supabase Edge Functions
- `OPENAI_MODEL`: [PLACEHOLDER] Optional default model (e.g., gpt-4o-mini)
