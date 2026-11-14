import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const int _installedWindowsBuild =
    int.fromEnvironment('APP_BUILD_NUMBER', defaultValue: 1);

class WindowsPosUpdate {
  final int buildNumber;
  final String tag;
  final String title;
  final String notes;
  final Uri packageUri;
  final Uri checksumUri;
  final int fileSizeBytes;

  const WindowsPosUpdate({
    required this.buildNumber,
    required this.tag,
    required this.title,
    required this.notes,
    required this.packageUri,
    required this.checksumUri,
    required this.fileSizeBytes,
  });
}

class WindowsPosUpdateService {
  static const _releasesUrl =
      'https://api.github.com/repos/magscacoffice/general_store_pos/releases?per_page=100';

  static Future<WindowsPosUpdate?> checkForUpdate() async {
    final response = await http.get(
      Uri.parse(_releasesUrl),
      headers: const {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw HttpException('Windows update check failed (${response.statusCode}).');
    }

    final releases = jsonDecode(response.body) as List<dynamic>;
    final candidates = <Map<String, dynamic>>[];
    for (final value in releases) {
      if (value is! Map<String, dynamic> ||
          value['draft'] == true ||
          value['prerelease'] == true) {
        continue;
      }
      final tag = value['tag_name']?.toString() ?? '';
      if (RegExp(r'^windows-v[0-9.]+-build[0-9]+$').hasMatch(tag)) {
        candidates.add(value);
      }
    }
    candidates.sort((a, b) {
      final aBuild = _buildNumber(a['tag_name']?.toString() ?? '');
      final bBuild = _buildNumber(b['tag_name']?.toString() ?? '');
      return bBuild.compareTo(aBuild);
    });
    if (candidates.isEmpty) return null;

    final release = candidates.first;
    final tag = release['tag_name']?.toString() ?? '';
    final build = _buildNumber(tag);
    if (build <= _installedWindowsBuild) return null;

    final assets = (release['assets'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    Uri? packageUri;
    Uri? checksumUri;
    var fileSizeBytes = 0;
    for (final asset in assets) {
      final name = asset['name']?.toString();
      final url = asset['browser_download_url']?.toString();
      if (url == null) continue;
      if (name == 'khan-baba-pos-windows.zip') {
        packageUri = Uri.tryParse(url);
        fileSizeBytes = (asset['size'] as num?)?.toInt() ?? 0;
      }
      if (name == 'khan-baba-pos-windows.zip.sha256') checksumUri = Uri.tryParse(url);
    }
    if (packageUri == null || checksumUri == null) return null;

    return WindowsPosUpdate(
      buildNumber: build,
      tag: tag,
      title: release['name']?.toString() ?? 'Khan Baba POS Windows update',
      notes: release['body']?.toString() ?? '',
      packageUri: packageUri,
      checksumUri: checksumUri,
      fileSizeBytes: fileSizeBytes,
    );
  }

  static int _buildNumber(String tag) {
    final match = RegExp(r'-build([0-9]+)$').firstMatch(tag);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  static Future<Directory> _updateDirectory() async {
    final local = Platform.environment['LOCALAPPDATA'];
    final base = local != null && local.isNotEmpty
        ? Directory(p.join(local, 'KhanBabaPOS', 'Updates'))
        : Directory(p.join((await getApplicationSupportDirectory()).path, 'Updates'));
    await base.create(recursive: true);
    return base;
  }

  static String _ps(String value) => "'${value.replaceAll("'", "''")}'";

  static String _formatSize(int bytes) {
    if (bytes <= 0) return 'Size unavailable';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static Future<void> downloadStageAndRestart(
    WindowsPosUpdate update, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (!Platform.isWindows) throw UnsupportedError('Windows update sirf Windows par available hai.');
    final updateDir = await _updateDirectory();
    final zipFile = File(p.join(updateDir.path, 'khan-baba-pos-windows-${update.buildNumber}.zip'));
    final checksumResponse = await http.get(update.checksumUri)
        .timeout(const Duration(seconds: 30));
    if (checksumResponse.statusCode != 200) {
      throw HttpException('Windows package checksum download nahi ho saka.');
    }
    final match = RegExp(r'^([a-fA-F0-9]{64})').firstMatch(checksumResponse.body.trim());
    if (match == null) throw const FormatException('Windows package checksum file invalid hai.');
    final expected = match.group(1)!.toLowerCase();

    final client = HttpClient();
    try {
      final request = await client.getUrl(update.packageUri)
          .timeout(const Duration(seconds: 30));
      final response = await request.close().timeout(const Duration(minutes: 8));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Windows package download failed (${response.statusCode}).');
      }
      final sink = zipFile.openWrite();
      final digestSink = AccumulatorSink<Digest>();
      final converter = sha256.startChunkedConversion(digestSink);
      final total = response.contentLength > 0
          ? response.contentLength
          : update.fileSizeBytes;
      var received = 0;
      onProgress?.call(received, total);
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          converter.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
        converter.close();
        await sink.flush();
        await sink.close();
      } catch (_) {
        await sink.close();
        if (await zipFile.exists()) await zipFile.delete();
        rethrow;
      }
      if (digestSink.events.isEmpty ||
          digestSink.events.single.toString().toLowerCase() != expected) {
        await zipFile.delete();
        throw const FormatException('Windows update ZIP checksum match nahi hua. File install nahi ki gayi.');
      }
    } finally {
      client.close(force: true);
    }

    final stage = Directory(p.join(updateDir.path, 'stage-${update.buildNumber}'));
    if (await stage.exists()) await stage.delete(recursive: true);
    await stage.create(recursive: true);
    final extract = await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        "Expand-Archive -LiteralPath ${_ps(zipFile.path)} -DestinationPath ${_ps(stage.path)} -Force",
      ],
      runInShell: false,
    );
    if (extract.exitCode != 0) {
      throw ProcessException('powershell.exe', const ['Expand-Archive'],
          extract.stderr.toString(), extract.exitCode);
    }

    final executable = Platform.resolvedExecutable;
    final appDirectory = p.dirname(executable);
    final exeName = p.basename(executable);
    if (!await File(p.join(stage.path, exeName)).exists()) {
      throw const FormatException('Downloaded Windows package mein POS executable nahi mila.');
    }

    final script = File(p.join(updateDir.path, 'install-windows-update.ps1'));
    await script.writeAsString('''
\$ErrorActionPreference = 'Stop'
\$target = ${_ps(appDirectory)}
\$staging = ${_ps(stage.path)}
\$exeName = ${_ps(exeName)}
\$processId = \$args[0]
\$log = ${_ps(p.join(updateDir.path, 'update-install.log'))}
try {
  while (Get-Process -Id \$processId -ErrorAction SilentlyContinue) {
    Start-Sleep -Seconds 1
  }
  Get-ChildItem -LiteralPath \$staging -Force | ForEach-Object {
    Copy-Item -LiteralPath \$_.FullName -Destination \$target -Recurse -Force
  }
  if (-not (Test-Path (Join-Path \$target \$exeName))) {
    throw 'Updated POS executable was not found after copying.'
  }
  Start-Process -FilePath (Join-Path \$target \$exeName) -WorkingDirectory \$target
  Add-Content -LiteralPath \$log -Value "Installed Windows update build ${update.buildNumber} at \$(Get-Date -Format o)"
} catch {
  Add-Content -LiteralPath \$log -Value "Update failed at \$(Get-Date -Format o): \$_"
  if (Test-Path (Join-Path \$target \$exeName)) {
    Start-Process -FilePath (Join-Path \$target \$exeName) -WorkingDirectory \$target
  }
}
''', flush: true);

    await Process.start(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        script.path,
        pid.toString(),
      ],
      mode: ProcessStartMode.detached,
    );
  }

  static Future<void> checkAndPrompt(
    BuildContext context, {
    bool manual = false,
  }) async {
    WindowsPosUpdate? update;
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
          const SnackBar(content: Text('Windows ke liye koi naya stable update available nahi hai.')),
        );
      }
      return;
    }

    final availableUpdate = update;
    final updateDir = await _updateDirectory();
    final promptFile = File(p.join(updateDir.path, 'last-prompted-build.txt'));
    if (!manual && await promptFile.exists()) {
      final last = int.tryParse((await promptFile.readAsString()).trim()) ?? 0;
      if (last >= availableUpdate.buildNumber) return;
    }

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.system_update_alt, size: 36),
        title: const Text('Khan Baba POS Windows update available'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(availableUpdate.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('Installed build: $_installedWindowsBuild  •  New build: ${availableUpdate.buildNumber}'),
                Text('Download size: ${_formatSize(availableUpdate.fileSizeBytes)}'),
                if (availableUpdate.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(availableUpdate.notes, maxLines: 10, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 10),
                const Text('Update app files replace karega, lekin local SQLite database aur settings app folder se bahar rehte hain aur preserve rahenge. App update ke baad restart hogi.'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Later'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.download),
            label: const Text('Download & Install'),
          ),
        ],
      ),
    );

    if (accepted != true || !context.mounted) {
      // Remember an explicit "Later" choice, but allow another automatic
      // attempt after a failed download or a dismissed dialog.
      if (accepted == false) {
        await promptFile.writeAsString(
          availableUpdate.buildNumber.toString(),
          flush: true,
        );
      }
      return;
    }

    final progress = ValueNotifier<double>(0);
    final progressText = ValueNotifier<String>('Preparing secure download...');
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Downloading Windows update'),
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
      await downloadStageAndRestart(
        availableUpdate,
        onProgress: (received, total) {
          if (total > 0) {
            progress.value = (received / total).clamp(0.0, 1.0).toDouble();
            progressText.value = 'Downloaded ${_formatSize(received)} of ${_formatSize(total)}';
          } else {
            progress.value = -1;
            progressText.value = 'Downloaded ${_formatSize(received)}';
          }
        },
      );
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      progress.dispose();
      progressText.dispose();
      exit(0);
    } catch (error) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Windows update install nahi ho saki: $error')),
        );
      }
      progress.dispose();
      progressText.dispose();
    }
  }
}
