# Custom themes

Custom themes keep Tinycast's token graph intact while allowing separate Light and Dark palettes.
The model lives in `DesignSystem/CustomTheme.swift`; the persisted, observable state lives in
`Features/Settings/CustomThemeStore.swift`.

## Invariants

- `ThemeColor` stores finite sRGB components in the closed range 0...1.
- A theme file is a versioned `tinycast-theme` document. Unknown formats and versions are rejected;
  there is no migration path.
- `Theme.Colors` remains the only consumer-facing token namespace. Views do not read theme fields or
  define theme-specific colors.
- Light and Dark palettes are independent. The active palette follows AppKit's effective appearance,
  including when Tinycast's appearance setting is `System`.
- A gradient has exactly two stops and one angle, and only affects the panel background token.
- Reset removes the custom theme and restores the shipped token values.
- Theme import/export carries only validated JSON and no filesystem paths or executable content.

## Data flow

```text
ColorPicker / file importer
  -> CustomThemeDocument.decode
  -> CustomThemeStore.preview/reset
  -> UserDefaults (bundle-scoped)
  -> Theme.Colors dynamic token resolver
  -> palette and shared surfaces
```

The store is owned by `AppCore` and injected into Settings. `AppCore` also observes its revision so
open surfaces are invalidated during live preview; the resolver itself does not own application
state.
