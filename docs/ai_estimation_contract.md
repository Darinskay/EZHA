# AI Estimation Contract

The AI estimation service accepts either or both `image_path` and `text_input`. At least one must be present; otherwise, the request fails.

## Request Payload

```
{
  image_path (string, optional),
  text_input (string, optional)
}
```

If both fields are missing, return the error:

```
Both image_path and text_input are missing. At least one is required.
```

## Response Payload

```
{
  calories (number, required),
  nutrients (object, required),
  ai_estimate_source ("text" | "image" | "combined", required),
  error (string, optional)
}
```

## Behavior Notes

- `ai_estimate_source` must indicate which input(s) supported the estimate.
- If there's an error, other fields can be null or omitted.
- Always display AI-generated nutrition estimates to users with a clear source indicator, and allow users to review, edit, or override estimates before saving entries.
