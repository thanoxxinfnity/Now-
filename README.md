# Mugen AI

Chat, research and **build real Android apps from your phone**. Mugen is a Flutter app:

- **Providers** - NVIDIA NIM, Google Gemini, OpenRouter, plus any OpenAI-compatible custom endpoint. Models are fetched live (new Gemini codenames appear on their own) and split into **Free** and **Paid**; tick any model as paid/free yourself.
- **Chat vs. build** - normal conversation stays conversation. Ask for an app and Mugen announces it, lists what it understood, streams the code into copy-boxes, and can export a `.zip`.
- **GitHub Actions APK builds** - with your GitHub token Mugen creates a repo, pushes the code, watches the Actions run, and hands you the APK download link. A failed build is read back by the AI and fixed automatically (up to 3 tries).
- **Live research** - toggle the globe in the composer to ground answers in fresh web results with sources.
- **Background work** - jobs run in a foreground service isolate, so chats and builds keep going after you swipe the app away; history is stored on disk.
- **Mugen CLI hub** - browse the [CLI-Anything](https://github.com/HKUDS/CLI-Anything) registry and run any CLI on a GitHub Actions runner from your phone.

UI language is inspired by the Craft Anything design system (dark canvas/card/field surfaces, 4-6-8 radii, one blue accent); no code was copied.

## Get the APK
Every push builds `MugenAI.apk` via GitHub Actions - see the **Releases** page (or the workflow's artifacts).

## First run
1. Settings -> paste an API key for NVIDIA / Gemini / OpenRouter (or add a custom endpoint) -> *Load models*.
2. Settings -> GitHub: classic token with `repo` + `workflow` scopes -> *Verify*.
3. Pick a model in the composer and start chatting. Say *"ek todo app bana do"* to build.

## Develop
```
flutter pub get
flutter test
flutter run
```
