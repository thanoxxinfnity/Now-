# Handoff prompt for Mugen AI

Copy everything between the lines into the other AI session.

---

You are a senior Flutter / Android engineer. Continue my project **Mugen AI**:
https://github.com/thanoxxinfnity/Now- (branch `ccr-0d91ce21-owf5lm`). Read the repo first (`README.md`, `lib/`, `.github/workflows/build-apk.yml`), then work until everything below is true. Reply in English. Prove every claim: run `flutter analyze` and `flutter test` locally, push, and read the GitHub Actions result before saying something works.

## What Mugen AI is
An Android chat app (Flutter, latest stable 3.50, package `material_ui` imports) that chats normally and, when the user asks, **builds real Android apps**:
1. The user adds an API key for NVIDIA NIM, Google Gemini or OpenRouter, or any number of custom OpenAI-compatible endpoints (name + base URL + optional key). Models are fetched live (`/models`); every model is selectable, and any model ID can be typed by hand. There is NO free/paid split.
2. Chat is OpenAI-compatible streaming (`/chat/completions`, SSE). Gemini uses `https://generativelanguage.googleapis.com/v1beta/openai`.
3. Normal conversation stays conversation. If the user asks for an app, the AI announces it in one line, lists the requirements, and emits the whole project inside `<mugen-project name="..." title="..."><file path="...">...</file></mugen-project>`. The UI streams it into collapsible code "copy boxes" with Copy, Copy all, `.zip` (share sheet) and **Build APK**.
4. Build APK: with the user's GitHub token (classic, scopes `repo` + `workflow`) the app creates a repo, pushes all files in one commit (Git Data API) together with a generated `.github/workflows/build-apk.yml` (creates `android/` with `flutter create`, builds the release APK, publishes a GitHub Release), watches the Actions run, and shows the APK download link. If the build fails, it fetches the failed job log, sends it to the AI, applies the fix and pushes again (max 3 tries).
5. Live research toggle (DuckDuckGo HTML search + page text, sources shown as chips).
6. Background: chats and builds run in a `flutter_foreground_task` isolate (foreground service, persistent notification) so they continue after the app is swiped away. Chats are stored as one JSON file each (history survives kills).
7. "Mugen CLI hub": lists the registry of https://github.com/HKUDS/CLI-Anything (`public_registry.json`) and runs a chosen CLI on a GitHub Actions runner in the user's `mugen-cli-runner` repo, showing the log.
8. UI: dark "studio" look inspired by https://github.com/storytold/craft-anything (canvas #121316, card #1B1C1F, field #222326, border #343436, one blue accent #2D81FF, radii 4/6/8, Figtree font). Do NOT copy its code. All UI text is English.
9. Animations: orb logo, aura background, and original cursed-technique effects (Blue, Red, Hollow Purple, Dismantle, Cleave, Malevolent Shrine) on the home screen, while the AI thinks, and as a full-screen effect when an APK build succeeds. Everything must feel smooth (60 fps, no jank).

## Problems I have right now - fix them
- Model errors: many models fail with 400/422 (unsupported `system` role, `max_tokens`, `temperature`), empty answers, timeouts or rate limits. Make streaming robust: retry with plainer requests, fold system into user, handle `reasoning_content`, `429` with backoff, and show a clear error inside the chat (not only a toast). Test against NVIDIA NIM, Gemini and OpenRouter model lists.
- Install on my Vivo T5x (Android 16) said "package invalid". Build a proper per-ABI release APK (arm64 as `MugenAI.apk`) and sign it with a fixed release keystore stored in GitHub Secrets (`KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`) so the signature is stable across builds. Document how I create the secrets.
- UI taps near the status bar / navigation buttons were not working because the UI was drawn under them. Verify insets on Android 15/16 edge-to-edge (status bar, gesture/3-button navigation bar, keyboard) in every screen, bottom sheet and drawer.
- The AI must be reliable at building apps: improve the system prompt in `lib/prompts.dart` with concrete Flutter build skills (modern APIs, only pure-Dart packages, every import defined, no placeholders, small files) and validate generated projects before pushing (pubspec name matches, `lib/main.dart` exists, every `package:` import is in pubspec, balanced brackets). If validation fails, auto-ask the model to fix it without wasting a GitHub build.
- Add an in-app "Test connection" button per provider and a "Test model" action in the model picker that sends a one-line prompt and shows the exact error text.

## Rules
- Never add free/paid tiers. Never hard-code model lists. Keep unlimited custom endpoints.
- Do not use `permission_handler` or other plugins that need compileSdk 37 or newer.
- Keep tests green; add tests for the parser, request retry logic and project validation.
- Commit in small steps with clear messages, push to the branch above, and report the final APK link from the GitHub Release.
- Do not create a pull request unless I ask.

---
