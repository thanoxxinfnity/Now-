# Mugen AI

Chat, research and **build real Android apps from your phone**. Mugen is a Flutter app:

- **Providers** - NVIDIA NIM, Google Gemini, OpenRouter, plus any OpenAI-compatible custom endpoint. Models are fetched live (new model names appear on their own), every model is selectable, and you can also type any model ID by hand. Add as many custom endpoints as you like.
- **Chat vs. build** - normal conversation stays conversation. Ask for an app and Mugen announces it, lists what it understood, streams the code into copy-boxes, and can export a `.zip`.
- **GitHub Actions APK builds** - with your GitHub token Mugen creates a repo, pushes the code, watches the Actions run, and hands you the APK download link. A failed build is read back by the AI and fixed automatically (up to 3 tries).
- **Cursed-technique animations** - blue / red / hollow purple and dismantle / cleave / shrine style effects on the home screen, while the AI is thinking and when an APK build succeeds.
- **Live research** - toggle the globe in the composer to ground answers in fresh web results with sources.
- **Background work** - jobs run in a foreground service isolate, so chats and builds keep going after you swipe the app away; history is stored on disk.
- **Mugen CLI hub** - browse the [CLI-Anything](https://github.com/HKUDS/CLI-Anything) registry and run any CLI on a GitHub Actions runner from your phone.

UI language is inspired by the Craft Anything design system (dark canvas/card/field surfaces, 4-6-8 radii, one blue accent); no code was copied.

## Get the APK
Every push builds the APKs via GitHub Actions - see the **Releases** page (or the workflow's artifacts).

- `MugenAI.apk` - for almost every phone (64-bit ARM). Use this one.
- `MugenAI-32bit.apk` - only for old 32-bit phones.

The release notes say which key signed the APK, its certificate SHA-256, the version code and the SDK levels, and the build fails if the two APKs are not signed alike.

## Stable signing (fixes "package invalid" / "conflicts with an existing package")
Android only installs an update when it is signed with the **same key** as the installed app. Without a key of your own, GitHub signs with a *debug* key that is created fresh on every build, so each new APK looks like a different app and the installer refuses it. A fixed release key fixes that for good.

1. Create the key once (needs `keytool` from any JDK and `openssl`):
   ```
   bash tool/make-keystore.sh ~/mugen-release-key
   ```
   It prints the four values and the certificate SHA-256. **Back the folder up**: if the keystore is lost, installed apps can never be updated, only reinstalled. Never commit it (`*.keystore`, `*.jks` and `key.properties` are git-ignored).
2. Add four repository secrets (GitHub -> Settings -> Secrets and variables -> Actions -> New repository secret), or with the GitHub CLI from inside the repo:
   ```
   gh secret set KEYSTORE_BASE64   < ~/mugen-release-key/KEYSTORE_BASE64.txt
   gh secret set KEYSTORE_PASSWORD < ~/mugen-release-key/PASSWORD.txt
   gh secret set KEY_PASSWORD      < ~/mugen-release-key/PASSWORD.txt
   gh secret set KEY_ALIAS --body mugen
   ```
   | Secret | Value |
   |---|---|
   | `KEYSTORE_BASE64` | the keystore file, base64 on one line (`base64 -w0 file.keystore`) |
   | `KEYSTORE_PASSWORD` | the keystore password |
   | `KEY_ALIAS` | the key alias (`mugen` with the script) |
   | `KEY_PASSWORD` | the key password (same as the keystore password with the script) |
3. Push anything. The build log shows `Release keystore restored`, and the release notes say **Signed with the release key**. Every later build carries the same certificate SHA-256 and installs over the previous one; the version code is the Actions run number, so it always goes up.

Good to know:
- **Once**, uninstall a Mugen AI that was installed from a debug-signed build before installing the first release-signed one (the signatures differ; your chats in the app are lost, so export what you need).
- Without the secrets the build still works, prints a warning and signs with the debug key; the release notes say so. If `KEYSTORE_BASE64` is set but another secret is missing, or the password is wrong, the build **fails** with a clear message instead of shipping a debug-signed APK by accident.
- Local release builds: put the same four names in `android/key.properties` (`KEYSTORE_FILE=/path/to/file.keystore`, `KEYSTORE_PASSWORD=...`, `KEY_ALIAS=...`, `KEY_PASSWORD=...`), or export them as environment variables.
- Apps that Mugen *generates* for you are still debug-signed by their own GitHub workflow (each lives in its own repository), so a newer build of a generated app must also be installed after uninstalling the old one.

## First run
1. Settings -> paste an API key for NVIDIA / Gemini / OpenRouter (or add a custom endpoint) -> *Load models*.
2. Settings -> GitHub: classic token with `repo` + `workflow` scopes -> *Verify*.
3. Pick a model in the composer and start chatting. Say *"ek todo app bana do"* to build.

## Develop
```
flutter pub get
flutter analyze
flutter test
flutter run
```
`flutter test` covers the model request layer (retry, 429 backoff, `reasoning_content`, empty answers, real NVIDIA/OpenRouter model-list fixtures), the project validator, the whole push flow against a fake GitHub / pub.dev / model, and the settings and model-picker widgets. CI also builds a throwaway-signed APK on every push to prove the signing setup.

Before every GitHub build Mugen checks the generated project (pubspec name, `lib/main.dart`, every `package:` import against `dependencies`, imports that point at missing files, listed assets, brackets, placeholders, removed APIs, and the versions on pub.dev), fixes what has one obvious answer, and asks the model to repair the rest, up to two times, so a broken project does not cost a GitHub build.
