# Azure Folio source library

Three collections, two plates each. The catalog records titles, credits and sources.

- Doré: public-domain Paradise Lost plates XII and XXVI (1866), downloaded from Wikimedia Commons. These are historical engravings.
- European Summer: original AI-generated Riviera harbour and Sicily illustrations.
- Argentina: original AI-generated Buenos Aires/culture and Patagonia illustrations.

The generated scenes are artistic studies, not documentary photographs or exact architectural reconstructions. `generation-prompts.json` records the exact prompts and built-in image_gen generation mode. No source image or layout is regenerated when changing a palette or selecting artwork.

`tools/azure-folio/build.py` applies deterministic Atkinson dithering and produces exactly two colors per wallpaper. Desktop exports are 3840 × 2400; portrait exports are 1920 × 2400. These export dimensions do not imply new source detail. All art is bundled offline in the immutable Nix package.

Fonts: Inter, IBM Plex Mono and Jacquard 24, distributed under the adjacent SIL Open Font License files. Font files come from the Google Fonts distribution.
