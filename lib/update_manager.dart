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

  const PosUpdate({
    required this.buildNumber,
    required this.version,
    required this.title,
    required this.notes,
    required this.apkUri,
    required this.checksumUri,
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
    final tag = release['tag_name']?.toString() ?? '';
    final match = RegExp(r'-build(\d+)$').firstMatch(tag);
    if (match == null) return null;

    final buildNumber = int.tryParse(match.group(1)!) ?? 0;
    if (buildNumber <= _installedBuildNumber) return null;

    final assets = (release['assets'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    Uri? apkUri;
    Uri? checksumUri;
    for (final asset in assets) {
      final name = asset['name']?.toString();
      final url = asset['browser_download_url']?.toString();
      if (url == null) continue;
      if (name == 'app-release.apk') apkUri = Uri.tryParse(url);
      if (name == 'app-release.apk.sha256') checksumUri = Uri.tryParse(url);
    }
    if (apkUri == null || checksumUri == null) return null;

    return PosUpdate(
      buildNumber: buildNumber,
      version: release['name']?.toString() ?? tag,
      title: release['name']?.toString() ?? 'Khan Baba POS update',
      notes: release['body']?.toString() ?? '',
      apkUri: apkUri,
      checksumUri: checksumUri,
    );
  }

  static Future<File> downloadAndVerify(PosUpdate update) async {
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
        '${directory.path}${Platform.pathSeparator}khan-baba-pos-update-${update.buildNumber}.apk');
    final client = HttpClient();
    final output = apkFile.openWrite();
    final digestSink = _Sha256DigestSink();
    final digestConverter = sha256.startChunkedConversion(digestSink);
    try {
      final request = await client
          .getUrl(update.apkUri)
          .timeout(const Duration(seconds: 30));
      final response = await request.close().timeout(const Duration(minutes: 5));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('APK download failed (${response.statusCode}).');
      }
      await for (final chunk in response) {
        output.add(chunk);
        digestConverter.add(chunk);
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
          'APK verification failed. The downloaded file was not installed.');
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
  final Set<int> _promptedBuilds = <int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeNotificationsAndCheck();
    });
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
      final initialMessage = await messaging.getInitialMessage();
      await _checkAndPrompt();
      if (initialMessage != null) {
        // The same update check handles a notification that launched the app.
      }
    } catch (_) {
      // Push permission or connectivity must never block normal POS startup.
      await _checkAndPrompt();
    }
  }

  Future<void> _checkAndPrompt() async {
    if (!mounted || _checking || _dialogOpen) return;
    _checking = true;
    try {
      final update = await PosUpdateService.checkForUpdate();
      if (!mounted || update == null || _promptedBuilds.contains(update.buildNumber)) {
        return;
      }
      _promptedBuilds.add(update.buildNumber);
      _dialogOpen = true;
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.system_update_alt, color: Colors.teal, size: 36),
          title: const Text('Khan Baba POS update available'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(update.title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (update.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(update.notes.trim()),
                ],
                const SizedBox(height: 10),
                const Text(
                  'Aapka data download aur update ke dauran delete nahi kiya jayega.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Baad mein'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _downloadAndInstall(update);
              },
              icon: const Icon(Icons.download),
              label: const Text('Update karein'),
            ),
          ],
        ),
      );
      _dialogOpen = false;
    } catch (_) {
      // Update checks are best-effort and must not interrupt sales or login.
    } finally {
      _checking = false;
      _dialogOpen = false;
    }
  }

  Future<void> _downloadAndInstall(PosUpdate update) async {
    if (!mounted) return;
    _dialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 18),
            Expanded(child: Text('Update download aur verify ho rahi hai...')),
          ],
        ),
      ),
    );

    try {
      final apkFile = await PosUpdateService.downloadAndVerify(update);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _dialogOpen = false;
      await PosUpdateService.install(apkFile);
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _dialogOpen = false;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Update install nahi ho saki'),
          content: Text(
            '$error\n\nAgar Android unknown-app installation ki permission mange, Khan Baba POS ke liye Allow karein aur dobara Update karein.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Theek hai'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
