# speech_to_text_linux

A Linux implementation of the [`speech_to_text`](https://github.com/csdcorp/speech_to_text) plugin.

Linux does not ship a system speech recognition engine, so this package performs recognition
**offline** using the open-source [Vosk](https://alphacephei.com/vosk/) toolkit. Microphone audio is captured through PulseAudio as 16 kHz mono PCM and streamed to Vosk, which produces partial and final results in real time. It means we do not need to use any cloud provider, or expensive AI-based compute.

Vosk is licensed by [Apache 2.0](github.com/alphacep/vosk-api/blob/master/COPYING).

## Usage

This package is a platform implementation of [`speech_to_text`](https://pub.dev/packages/speech_to_text):

```yaml
dependencies:
  speech_to_text: ^7.4.0
  speech_to_text_linux: ^0.0.1
```

No other code changes are needed, once the dependency is present the plugin registers itself as the Linux implementation and the normal `speech_to_text` API works :) 

See [speech_to_text](https://github.com/csdcorp/speech_to_text/blob/main/speech_to_text/README.md).

## Build dependencies

Install the development packages required to build the native plugin:

```bash
# Debian / Ubuntu
sudo apt-get install libgtk-3-dev libpulse-dev unzip

# Fedora
sudo dnf install gtk3-devel pulseaudio-libs-devel unzip

# Arch Linux (based)
sudo pacman -S gtk3 libpulse base-devel unzip
```

## Vosk library and model

No manual Vosk setup is required. At build time the plugin looks for a local `libvosk.so` / `vosk_api.h` and, if none is found, automatically downloads the prebuilt Vosk SDK (x86_64, aarch64, armv7l or riscv64) from the official releases and caches it under `~/.cache/speech_to_text_linux/` (`unzip` must be installed for the extraction). The resolved `libvosk.so` is bundled into the application automatically. At runtime the plugin downloads and caches the small en-US model on first `initialize`.

### Bundling your own Vosk library

You only need to provide Vosk yourself if you want to override the defaults, for example:

* **Bundle or pin a specific `libvosk.so`** (a custom build, or a version other than the auto-downloaded one) - install it to a standard prefix (`/usr/local/lib`,`/usr/local/include`) or set `VOSK_DIR` to the folder containing `libvosk.so` and `vosk_api.h` before building. A locally found library always wins over the auto-download, and it is the copy that gets bundled into your app:

  ```bash
  export VOSK_DIR=/opt/vosk
  ```

  Alternatively pass `-DVOSK_VERSION=<version>` to fetch a different prebuilt release, or `-DVOSK_AUTO_DOWNLOAD=OFF` to forbid downloading entirely (the build the fails unless a local copy is found).
* **Unsupported architecture** - the auto-download only covers the architectures listed above; on anything else the build stops and asks for `VOSK_DIR`.
* **Offline / hermetic CI builds** - with no network at build time, pre-provision the SDK and point `VOSK_DIR` at it (or pre-populate the cache directory).

### Bundling your own model

By default the small en-US model is fetched and cached at runtime. To ship or select a
different model, pass platform options to `initialize`:

```dart
await speech.initialize(
  options: [
    // Use a model you bundle/install yourself; disables the runtime download. you can link this to application storage & such.
    SpeechConfigOption('linux', 'modelPath', '/opt/vosk/vosk-model-small-en-us-0.15'),

    // ...or keep auto-download but fetch a different model:
    SpeechConfigOption('linux', 'modelName', 'vosk-model-small-de-0.15'),
    SpeechConfigOption('linux', 'modelUrl',
         'https://alphacephei.com/vosk/models/vosk-model-small-de-0.15.zip'),

    // ...or disable downloading entirely (initialize fails without a modelPath):
    SpeechConfigOption('linux', 'autoDownloadModel', false),
  ],
);
```

## Notes / Odd Behaviour

* Microphone access is unrestricted under a normal desktop session, so `hasPermission` returns `true`. Sandboxed packaging (Flatpak/Snap) may still require granting microphone access. Which may need to be done via another API? Will need to have a look.
* Vosk does not expose a locale enumeration API; `locales()` reports the locale derived from the configured model (defaulting to `en_US`).

TODO: make it so it gets locale from inputted URL/model, since a different locale can be used per modal? maybe make list, not sure..