import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

const int _installedBuildNumber =
    int.fromEnvironment('APP_BUILD_NUMBER', defaultValue: 1);

class PosUpdate {
  final int buildNumber;
  final String version;
  final String title;
  final String notes;
  final Uri apkUri;
  final Uri checksumUri;
  final int fileSizeBytes;

  const PosUpdate({
    required this.buildNumber,
    required this.version,
    required this.title,
    required this.notes,
    required this.apkUri,
    required this.checksumUri,
    required this.fileSizeBytes,
  });
}

class _Sha256DigestSink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest value) => digest = value;

  @override
  void close() {}
}

class PosUpdateService {
  static const String _latestReleaseUrl =
      'https://api.github.com/repos/magscacoffice/general_store_pos/releases/latest';

  static Future<PosUpdate?> checkForUpdate() async {
    final response = await http.get(
      Uri.parse(_latestReleaseUrl),
      headers: const {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw HttpException('Update check failed (${response.statusCode}).');
    }

    final release = jsonDecode(response.body) as Map<String, dynamic>;
    if (release['draft'] == true || release['prerelease'] == true) return null;
    final tag = release['tag_name']?.toString() ?? '';
    final match = RegExp(r'-build(\d+).firstMatch(tag);
    if (match == null) return null;

    final buildNumber = int.tryParse(match.group(1)!) ?? 0;
    if (buildNumber <= _installedBuildNumber) return null;

    final assets = (release['assets'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    Uri? apkUri;
    Uri? checksumUri;
    var fileSizeBytes = 0;
    for (final asset in assets) {
      final name = asset['name']?.toString();
      final url = asset['browser_download_url']?.toString();
      if (url == null) continue;
      if (name == 'app-release.apk') {
        apkUri = Uri.tryParse(url);
        fileSizeBytes = (asset['size'] as num?)?.toInt() ?? 0;
      }
      if (name == 'app-release.apk.sha256') checksumUri = Uri.tryParse(url);
    }
    if (apkUri == null || checksumUri == null) return null;

    return PosUpdate(
      buildNumber: buildNumber,
      version: tag,
      title: release['name']?.toString() ?? 'Khan Baba POS update',
      notes: release['body']?.toString() ?? '',
      apkUri: apkUri,
      checksumUri: checksumUri,
      fileSizeBytes: fileSizeBytes,
    );
  }

  static Future<File> downloadAndVerify(
    PosUpdate update, {
    void Function(int received, int total)? onProgress,
  }) async {
    final checksumResponse = await http
        .get(update.checksumUri)
        .timeout(const Duration(seconds: 30));
    if (checksumResponse.statusCode != 200) {
      throw HttpException('APK checksum download failed.');
    }
    final checksumMatch =
        RegExp(r'^([a-fA-F0-9]{64})').firstMatch(checksumResponse.body.trim());
    if (checksumMatch == null) {
      throw const FormatException('APK checksum file is invalid.');
    }
    final expectedChecksum = checksumMatch.group(1)!.toLowerCase();

    final directory = await getTemporaryDirectory();
    final apkFile = File(
      '${directory.path}${Platform.pathSeparator}khan-baba-pos-update-${update.buildNumber}.apk',
    );
    final client = HttpClient();
    final output = apkFile.openWrite();
    final digestSink = _Sha256DigestSink();
    final digestConverter = sha256.startChunkedConversion(digestSink);
    try {
      final request = await client
          .getUrl(update.apkUri)
          .timeout(const Duration(seconds: 30));
      final response = await request.close().timeout(const Duration(minutes: 8));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('APK download failed (${response.statusCode}).');
      }
      final total = response.contentLength > 0
          ? response.contentLength
          : update.fileSizeBytes;
      var received = 0;
      onProgress?.call(received, total);
      await for (final chunk in response) {
        output.add(chunk);
        digestConverter.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      digestConverter.close();
      await output.flush();
      await output.close();
    } catch (_) {
      await output.close();
      if (await apkFile.exists()) await apkFile.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }

    final actualChecksum = digestSink.digest?.toString().toLowerCase();
    if (actualChecksum != expectedChecksum) {
      if (await apkFile.exists()) await apkFile.delete();
      throw const FormatException(
        'APK verification failed. The downloaded file was not installed.',
      );
    }
    return apkFile;
  }

  static Future<void> install(File apkFile) async {
    final result = await OpenFilex.open(
      apkFile.path,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type.toString() != 'ResultType.done') {
      throw Exception(result.message.isEmpty
          ? 'Android installer could not open the APK.'
          : result.message);
    }
  }

  static Future<File> _lastPromptFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}last-android-update-prompted.txt');
  }

  static String _formatSize(int bytes) {
    if (bytes <= 0) return 'Size unavailable';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  static Future<void> checkAndPrompt(
    BuildContext context, {
    bool manual = false,
  }) async {
    PosUpdate? update;
    try {
      update = await checkForUpdate();
    } catch (error) {
      if (manual && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update check failed: $error')),
        );
      }
      return;
    }

    if (!context.mounted) return;
    if (update == null) {
      if (manual) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Koi naya stable Android update available nahi hai.')),
        );
      }
      return;
    }

    final availableUpdate = update;
    final promptFile = await _lastPromptFile();
    if (!manual && await promptFile.exists()) {
      final last = int.tryParse((await promptFile.readAsString()).trim()) ?? 0;
      if (last >= availableUpdate.buildNumber) return;
    }

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.system_update_alt, color: Colors.teal, size: 36),
        title: const Text('Khan Baba POS update available'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(availableUpdate.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('Build: ${availableUpdate.buildNumber}  •  Size: ${_formatSize(availableUpdate.fileSizeBytes)}'),
              if (availableUpdate.notes.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(availableUpdate.notes.trim()),
              ],
              const SizedBox(height: 10),
              const Text(
                'Download verify hone ke baad Android package installer khulega. App data delete nahi kiya jayega.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Baad mein'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.download),
            label: const Text('Update karein'),
          ),
        ],
      ),
    );

    if (accepted != true || !context.mounted) {
      if (accepted == false) {
        await promptFile.writeAsString(availableUpdate.buildNumber.toString(), flush: true);
      }
      return;
    }

    final progress = ValueNotifier<double>(0);
    final progressText = ValueNotifier<String>('Preparing secure download...');
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Downloading Android update'),
        content: ValueListenableBuilder<String>(
          valueListenable: progressText,
          builder: (_, label, __) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(label),
              const SizedBox(height: 12),
              ValueListenableBuilder<double>(
                valueListenable: progress,
                builder: (_, value, __) => LinearProgressIndicator(
                  value: value < 0 ? null : value,
                ),
              ),
            ],
          ),
        ),
      ),
    ));

    try {
      final apkFile = await downloadAndVerify(
        availableUpdate,
        onProgress: (received, total) {
          if (total > 0) {
            progress.value = (received / total).clamp(0.0, 1.0).toDouble();
            progressText.value =
                'Downloaded ${_formatSize(received)} of ${_formatSize(total)}';
          } else {
            progress.value = -1;
            progressText.value = 'Downloaded ${_formatSize(received)}';
          }
        },
      );
      if (!context.mounted) {
        progress.dispose();
        progressText.dispose();
        return;
      }
      Navigator.of(context, rootNavigator: true).pop();
      progress.dispose();
      progressText.dispose();
      // Do not suppress a later automatic prompt if the user cancels the
      // Android package installer. An installed build will stop matching.
      await install(apkFile);
    } catch (error) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update download/install nahi ho saki: $error')),
        );
      }
      progress.dispose();
      progressText.dispose();
    }
  }
}

class UpdateAwareHome extends StatefulWidget {
  final Widget child;

  const UpdateAwareHome({super.key, required this.child});

  @override
  State<UpdateAwareHome> createState() => _UpdateAwareHomeState();
}

class _UpdateAwareHomeState extends State<UpdateAwareHome> {
  bool _checking = false;
  bool _dialogOpen = false;
  Timer? _periodicCheckTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeNotificationsAndCheck();
    });
    _periodicCheckTimer = Timer.periodic(
      const Duration(hours: 24),
      (_) => _checkAndPrompt(),
    );
  }

  Future<void> _initializeNotificationsAndCheck() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus != AuthorizationStatus.denied) {
        await messaging.subscribeToTopic('khan-baba-pos-updates');
      }

      FirebaseMessaging.onMessage.listen((message) {
        if (message.data['type'] == 'app_update' ||
            message.notification != null) {
          _checkAndPrompt();
        }
      });
      FirebaseMessaging.onMessageOpenedApp.listen((_) {
        _checkAndPrompt();
      });
      await messaging.getInitialMessage();
    } catch (_) {
      // Push permission or connectivity must never block normal POS startup.
    }
    await _checkAndPrompt();
  }

  Future<void> _checkAndPrompt() async {
    if (!mounted || _checking || _dialogOpen) return;
    _checking = true;
    _dialogOpen = true;
    try {
      await PosUpdateService.checkAndPrompt(context);
    } finally {
      _checking = false;
      _dialogOpen = false;
    }
  }

  @override
  void dispose() {
    _periodicCheckTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
