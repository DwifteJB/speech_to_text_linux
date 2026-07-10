import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:speech_to_text_linux/speech_to_text_linux.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('speech_to_text_linux');
  const MethodChannel pathProviderChannel =
      MethodChannel('plugins.flutter.io/path_provider');

  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late SpeechToTextLinux plugin;
  late List<MethodCall> log;
  late Object? Function(MethodCall call) responses;

  setUp(() {
    plugin = SpeechToTextLinux();
    log = <MethodCall>[];
    responses = (MethodCall call) => null;
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      log.add(call);
      return responses(call);
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
  });

  Directory mockSupportDirectory() {
    final Directory dir =
        Directory.systemTemp.createTempSync('stt_linux_test');
    messenger.setMockMethodCallHandler(pathProviderChannel,
        (MethodCall call) async {
      if (call.method == 'getApplicationSupportDirectory') {
        return dir.path;
      }
      return null;
    });
    addTearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });
    return dir;
  }

  Directory createCachedModel(Directory supportDir, String modelName) {
    final Directory modelDir = Directory(
        p.join(supportDir.path, 'speech_to_text_linux', modelName));
    Directory(p.join(modelDir.path, 'am')).createSync(recursive: true);
    File(p.join(modelDir.path, 'am', 'final.mdl')).writeAsStringSync('x');
    return modelDir;
  }

  Future<void> emitFromPlatform(String method, Object? arguments) async {
    final ByteData data = const StandardMethodCodec()
        .encodeMethodCall(MethodCall(method, arguments));
    await messenger.handlePlatformMessage(
        channel.name, data, (ByteData? reply) {});
  }

  group('registerWith', () {
    // test that it can register
    test('sets the default platform instance', () {
      SpeechToTextLinux.registerWith();
      expect(SpeechToTextPlatform.instance, isA<SpeechToTextLinux>());
    });
  });

  group('hasPermission', () {
    // test that we can get the permission status from the platform
    test('returns true when the platform grants permission', () async {
      responses = (MethodCall call) => true;
      expect(await plugin.hasPermission(), isTrue);
      expect(log, hasLength(1));
      expect(log.single.method, 'hasPermission');
    });

    // see if we can handle the platform denying permission
    test('returns false when the platform denies permission', () async {
      responses = (MethodCall call) => false;
      expect(await plugin.hasPermission(), isFalse);
    });

    // see if we can handle the platform returning null
    test('returns false when the platform returns null', () async {
      expect(await plugin.hasPermission(), isFalse);
    });

    // can we handle the platform throwing an exception
    test('returns false when the channel throws', () async {
      responses = (MethodCall call) =>
          throw PlatformException(code: 'failed');
      expect(await plugin.hasPermission(), isFalse);
    });
  });

  group('initialize', () {
    // check if passing an explicit modelPath works and skips the download
    test('passes an explicit modelPath and skips the download', () async {
      responses = (MethodCall call) => true;
      final bool result = await plugin.initialize(options: [
        SpeechConfigOption('linux', 'modelPath', '/opt/vosk/model'),
      ]);
      expect(result, isTrue);
      expect(log.single.method, 'initialize');
      final Map<Object?, Object?> params =
          log.single.arguments as Map<Object?, Object?>;
      expect(params['modelPath'], '/opt/vosk/model');
      expect(params['debugLogging'], isFalse);
    });

    // see if debug logging is passed through correctly
    test('passes debugLogging through', () async {
      responses = (MethodCall call) => true;
      await plugin.initialize(debugLogging: true, options: [
        SpeechConfigOption('linux', 'modelPath', '/opt/vosk/model'),
      ]);
      final Map<Object?, Object?> params =
          log.single.arguments as Map<Object?, Object?>;
      expect(params['debugLogging'], isTrue);
    });

    // see if autoDownloadModel being false omits the modelPath parameter
    test('omits modelPath when autoDownloadModel is false', () async {
      responses = (MethodCall call) => true;
      final bool result = await plugin.initialize(options: [
        SpeechConfigOption('linux', 'autoDownloadModel', false),
      ]);
      expect(result, isTrue);
      final Map<Object?, Object?> params =
          log.single.arguments as Map<Object?, Object?>;
      expect(params.containsKey('modelPath'), isFalse);
    });

    // see if autoDownloadModel being true includes the modelPath parameter
    test('ignores options for other platforms and forwards extras', () async {
      responses = (MethodCall call) => true;
      await plugin.initialize(options: [
        SpeechConfigOption('android', 'modelPath', '/android/model'),
        SpeechConfigOption('linux', 'modelPath', '/linux/model'),
        SpeechConfigOption('linux', 'extraOption', 42),
      ]);
      final Map<Object?, Object?> params =
          log.single.arguments as Map<Object?, Object?>;
      expect(params['modelPath'], '/linux/model');
      expect(params['extraOption'], 42);
    });

    // see if we can handle the platform returning null
    test('returns false when the platform reports failure', () async {
      responses = (MethodCall call) => false;
      final bool result = await plugin.initialize(options: [
        SpeechConfigOption('linux', 'modelPath', '/opt/vosk/model'),
      ]);
      expect(result, isFalse);
    });

    // see if we can handle the platform throwing an exception
    test('returns false when the channel throws', () async {
      responses = (MethodCall call) =>
          throw PlatformException(code: 'failed');
      final bool result = await plugin.initialize(options: [
        SpeechConfigOption('linux', 'modelPath', '/opt/vosk/model'),
      ]);
      expect(result, isFalse);
    });

    // see if cached models are used when available, without downloading
    test('uses a cached default model without downloading', () async {
      final Directory supportDir = mockSupportDirectory();
      final Directory modelDir =
          createCachedModel(supportDir, 'vosk-model-small-en-us-0.15');
      responses = (MethodCall call) => true;
      final bool result = await plugin.initialize();
      expect(result, isTrue);
      final Map<Object?, Object?> params =
          log.single.arguments as Map<Object?, Object?>;
      expect(params['modelPath'], modelDir.path);
    });

    // see if cached models are used when available, with a custom modelName
    test('uses a cached model with a custom modelName', () async {
      final Directory supportDir = mockSupportDirectory();
      final Directory modelDir =
          createCachedModel(supportDir, 'my-custom-model');
      responses = (MethodCall call) => true;
      final bool result = await plugin.initialize(options: [
        SpeechConfigOption('linux', 'modelName', 'my-custom-model'),
      ]);
      expect(result, isTrue);
      final Map<Object?, Object?> params =
          log.single.arguments as Map<Object?, Object?>;
      expect(params['modelPath'], modelDir.path);
    });

    // if download fails, check that we return false and don't leave an incomplete model behind
    test('returns false when the model download fails', () async {
      mockSupportDirectory();
      responses = (MethodCall call) => true;
      final bool result = await plugin.initialize(options: [
        SpeechConfigOption(
            'linux', 'modelUrl', 'http://127.0.0.1:9/model.zip'),
      ]);
      expect(result, isFalse);
      expect(log, isEmpty);
    });

    // if a cached model is incomplete, check that we remove it before downloading
    test('removes an incomplete cached model before downloading', () async {
      final Directory supportDir = mockSupportDirectory();
      final Directory modelDir = Directory(p.join(supportDir.path,
          'speech_to_text_linux', 'vosk-model-small-en-us-0.15'));
      modelDir.createSync(recursive: true);
      responses = (MethodCall call) => true;
      final bool result = await plugin.initialize(options: [
        SpeechConfigOption(
            'linux', 'modelUrl', 'http://127.0.0.1:9/model.zip'),
      ]);
      expect(result, isFalse);
      expect(modelDir.existsSync(), isFalse);
    });
  });

  group('listen', () {
    // can we expect the default parameters to be sent to the platform when calling listen
    test('sends default parameters', () async {
      responses = (MethodCall call) => true;
      final bool result = await plugin.listen();
      expect(result, isTrue);
      expect(log.single.method, 'listen');
      final Map<Object?, Object?> params =
          log.single.arguments as Map<Object?, Object?>;
      expect(params['localeId'], isNull);
      expect(params['partialResults'], isTrue);
      expect(params['onDevice'], isFalse);
      expect(params['listenMode'], 0);
      expect(params['sampleRate'], 0);
      expect(params['autoPunctuation'], isFalse);
      expect(params['enableHapticFeedback'], isFalse);
      expect(params['cancelOnError'], isFalse);
    });

    // can we expect the parameters to be sent to the platform when calling listen with a localeId
    test('sends values from SpeechListenOptions', () async {
      responses = (MethodCall call) => true;
      final bool result = await plugin.listen(
        localeId: 'en_US',
        options: SpeechListenOptions(
          partialResults: false,
          onDevice: true,
          listenMode: ListenMode.dictation,
          sampleRate: 44100,
          autoPunctuation: true,
          enableHapticFeedback: true,
          cancelOnError: true,
        ),
      );
      expect(result, isTrue);
      final Map<Object?, Object?> params =
          log.single.arguments as Map<Object?, Object?>;
      expect(params['localeId'], 'en_US');
      expect(params['partialResults'], isFalse);
      expect(params['onDevice'], isTrue);
      expect(params['listenMode'], ListenMode.dictation.index);
      expect(params['sampleRate'], 44100);
      expect(params['autoPunctuation'], isTrue);
      expect(params['enableHapticFeedback'], isTrue);
      expect(params['cancelOnError'], isTrue);
    });

    test('returns false when the platform returns null', () async {
      expect(await plugin.listen(), isFalse);
    });

    test('returns false when the channel throws', () async {
      responses = (MethodCall call) =>
          throw PlatformException(code: 'failed');
      expect(await plugin.listen(), isFalse);
    });
  });

  group('stop and cancel', () {
    // does stop invoking work?
    test('stop invokes the stop method', () async {
      await plugin.stop();
      expect(log.single.method, 'stop');
    });
    
    // does cancel invoking work?
    test('cancel invokes the cancel method', () async {
      await plugin.cancel();
      expect(log.single.method, 'cancel');
    });

    // can we stop and cancel without throwing if the platform throws an exception?
    test('stop swallows channel errors', () async {
      responses = (MethodCall call) =>
          throw PlatformException(code: 'failed');
      await expectLater(plugin.stop(), completes);
    });

    // can cancel swallow channel errors without throwing?
    test('cancel swallows channel errors', () async {
      responses = (MethodCall call) =>
          throw PlatformException(code: 'failed');
      await expectLater(plugin.cancel(), completes);
    });
  });

  // test locales
  group('locales', () {
    test('returns the list from the platform', () async {
      responses =
          (MethodCall call) => <String>['en_US:English (United States)'];
      final List<dynamic> result = await plugin.locales();
      expect(result, ['en_US:English (United States)']);
      expect(log.single.method, 'locales');
    });

    test('returns an empty list when the platform returns null', () async {
      expect(await plugin.locales(), isEmpty);
    });

    test('returns an empty list when the channel throws', () async {
      responses = (MethodCall call) =>
          throw PlatformException(code: 'failed');
      expect(await plugin.locales(), isEmpty);
    });
  });

  group('platform callbacks', () {
    setUp(() async {
      responses = (MethodCall call) => true;
      await plugin.initialize(options: [
        SpeechConfigOption('linux', 'modelPath', '/opt/vosk/model'),
      ]);
    });

    test('textRecognition invokes onTextRecognition', () async {
      final List<String> received = <String>[];
      plugin.onTextRecognition = received.add;
      await emitFromPlatform('textRecognition', '{"resultType":2}');
      expect(received, ['{"resultType":2}']);
    });

    test('notifyError invokes onError', () async {
      final List<String> received = <String>[];
      plugin.onError = received.add;
      await emitFromPlatform('notifyError', '{"errorMsg":"mic"}');
      expect(received, ['{"errorMsg":"mic"}']);
    });

    test('notifyStatus invokes onStatus', () async {
      final List<String> received = <String>[];
      plugin.onStatus = received.add;
      await emitFromPlatform('notifyStatus', 'listening');
      expect(received, ['listening']);
    });

    test('soundLevelChange invokes onSoundLevel', () async {
      final List<double> received = <double>[];
      plugin.onSoundLevel = received.add;
      await emitFromPlatform('soundLevelChange', -42.5);
      expect(received, [-42.5]);
    });

    test('ignores payloads with unexpected types', () async {
      final List<String> texts = <String>[];
      final List<double> levels = <double>[];
      plugin.onTextRecognition = texts.add;
      plugin.onSoundLevel = levels.add;
      await emitFromPlatform('textRecognition', 3);
      await emitFromPlatform('soundLevelChange', 'loud');
      expect(texts, isEmpty);
      expect(levels, isEmpty);
    });

    // for other platforms maybe? this is just to make sure we don't throw if the platform sends a method we don't know about
    test('ignores unknown methods', () async {
      await expectLater(
          emitFromPlatform('somethingElse', 'payload'), completes);
    });
  });
}
