# Food Entry Data Model

EZHA supports logging meals via a structured list (name + grams), a free-text description, or a photo. The `food_entries` schema captures the parent entry and the `food_entry_items` table stores per-item rows when list mode is used.

## Schema

```
food_entry: {
  id (string, required),
  created_at (timestamp, required),
  input_type (enum ["photo", "text", "photo+text"], required),
  image_path (string, optional),
  input_text (string, optional),
  user_id (string, required)
}

food_entry_item: {
  id (string, required),
  entry_id (string, required),
  user_id (string, required),
  name (string, required),
  grams (number, required),
  calories (number, required),
  protein (number, required),
  carbs (number, required),
  fat (number, required),
  created_at (timestamp, required)
}
```

## Validation Rules

- `input_type` must be one of `photo`, `text`, or `photo+text`.
- At least one input is required: `image_path`, `input_text`, or list items.
- In list mode, each item must include a `name` and `grams` > 0.
