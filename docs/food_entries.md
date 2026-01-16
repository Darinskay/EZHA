# Food Entry Data Model

EZHA supports logging meals via text, photo, or both. The `food_entries` schema distinguishes input types through an `input_type` field and requires at least one input (`image_path` or `text_input`).

## Schema

```
food_entry: {
  id (string, required),
  created_at (timestamp, required),
  input_type (enum ["text", "image", "both"], required),
  image_path (string, optional),
  text_input (string, optional),
  user_id (string, required)
}
```

## Validation Rules

- `input_type` must be one of `text`, `image`, or `both`.
- At least one of `image_path` or `text_input` must be present.
- If both `image_path` and `text_input` are missing, the entry is invalid and must result in an error.
