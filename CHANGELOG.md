# Changelog

## [1.3.0](https://github.com/andrewtryder/sunsethue-macos/compare/v1.2.0...v1.3.0) (2026-08-21)


### Features

* add local notifications and unify app UI ([9e342eb](https://github.com/andrewtryder/sunsethue-macos/commit/9e342eb0e2c5cf5349d0200776de4a7b835640c0))
* add local notifications and unify app UI ([ff16fb1](https://github.com/andrewtryder/sunsethue-macos/commit/ff16fb16684ccc0d34bf73ad6fbf71c201b3feb2))
* add place search and polish location sidebar UX ([3161f5d](https://github.com/andrewtryder/sunsethue-macos/commit/3161f5dae1e9bb22fa34a6f424541e4b78d31795))
* app-owned refresh and read-only widget ([7123f47](https://github.com/andrewtryder/sunsethue-macos/commit/7123f478ddc4b3de55e1e7bebd7c831577ff9f6c))
* **diagnostics:** add refresh activity recorder, background status, and storage observability ([bbe13d2](https://github.com/andrewtryder/sunsethue-macos/commit/bbe13d2e541d96174c90f17a381aff3d8979e0d9))
* **forecast:** add multi-day forecast sections, opportunity highlights, and DST-safe relative day formatting ([a083120](https://github.com/andrewtryder/sunsethue-macos/commit/a0831200c596acf8d66f584eeb3e6c10eae2ba1b))
* initial SunsetHue macOS app with unsigned DMG releases ([baf6b49](https://github.com/andrewtryder/sunsethue-macos/commit/baf6b49cd605ef8bb59c55b25bbb553f7afa77e8))
* **locations:** add location reordering, menu bar context actions, and per-location notification rules ([6bbc6c2](https://github.com/andrewtryder/sunsethue-macos/commit/6bbc6c25d6d3c4c52a39850b218e6d369758987f))
* make app own API key and refresh; widget read-only ([9178ab3](https://github.com/andrewtryder/sunsethue-macos/commit/9178ab39a223b8655aff1a484e54bac433f2f362))
* redesign widgets with Next Events and polish app UX ([df0c10f](https://github.com/andrewtryder/sunsethue-macos/commit/df0c10f921c9d5af3eaa84218069756fb33cff8e))
* redesign widgets with Next Events and polish app UX ([9314818](https://github.com/andrewtryder/sunsethue-macos/commit/9314818d651e65699d6e93e85249f379c1e0986d))
* refine menu bar popover presentation and refresh coordinator race handling ([f897ff7](https://github.com/andrewtryder/sunsethue-macos/commit/f897ff73be81d11f15b69ceea9f32e8f95516fb8))
* stabilize main branch, add background forecast refresh, and ensure authoritative cache persistence ([5fbde33](https://github.com/andrewtryder/sunsethue-macos/commit/5fbde3326cd14cd04ea6d3935467033737c586f8))


### Bug Fixes

* **ci:** pass SwiftPM --sanitize flags instead of -Xlinker ([e1995d3](https://github.com/andrewtryder/sunsethue-macos/commit/e1995d365fe271c29fcff110bcfc9689a257f879))
* **diagnostics:** accurately resolve launch-at-login status in diagnostics ([732acf2](https://github.com/andrewtryder/sunsethue-macos/commit/732acf2e4b54edc983ebc17a82bed59b802faeff))
* disambiguate settings status foregroundStyle colors ([9fd0628](https://github.com/andrewtryder/sunsethue-macos/commit/9fd06283e702e1246972603913ebfef5a148d35b))
* eliminate legacy App Group probing to prevent macOS privacy prompts ([b14d310](https://github.com/andrewtryder/sunsethue-macos/commit/b14d3102a90bb229f9725893e6795f5556b2cc59))
* fetch minimum 2-day operational forecast horizon to prevent post-sunset rollover gaps ([7be76ef](https://github.com/andrewtryder/sunsethue-macos/commit/7be76efb30819fabdd04272c7a047eb1815797e4))
* harden per-location notifications, diagnostics, and multi-day presentation ([a871e2b](https://github.com/andrewtryder/sunsethue-macos/commit/a871e2b4786d3b31bd891f108502cdde13bbfccf))
* replace manual settings button in CommandGroup with SettingsLink to prevent duplicate menu items ([f036480](https://github.com/andrewtryder/sunsethue-macos/commit/f03648013243ce48cc6da25184edb00d56cb129a))
* resolve menu bar location list collapse and duplicate settings menu item ([d749592](https://github.com/andrewtryder/sunsethue-macos/commit/d749592f2127c579e4050cd93d7dc42e487fdca5))

## [1.1.0](https://github.com/andrewtryder/sunsethue-macos/compare/v1.0.0...v1.1.0) (2026-08-02)


### Features

* initial SunsetHue macOS app with unsigned DMG releases ([baf6b49](https://github.com/andrewtryder/sunsethue-macos/commit/baf6b49cd605ef8bb59c55b25bbb553f7afa77e8))
