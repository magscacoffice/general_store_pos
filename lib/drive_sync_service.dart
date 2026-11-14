import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'db_helper.dart';
import 'windows/pos_windows.dart';

class DriveSyncService {
  DriveSyncService._();

  static const String _folderName = 'Khan Baba POS';
  static const String _androidServerClientId =
      '707319476515-a91qi9iv86kb825ttdv6oo4gp2nqe3vi.apps.googleusercontent.com';
  static const String _windowsClientId =
      '707319476515-viu9eqvkacootsu2eooa4eon2oeheab2.apps.googleusercontent.com';
  // Desktop OAuth client secrets are embedded in installed-app binaries by
  // design; they are not confidential. Supply through the Windows build secret.
  static const String _windowsClientSecret =
      String.fromEnvironment('GOOGLE_WINDOWS_CLIENT_SECRET');
  static const List<String> _scopes = [
    'https://www.googleapis.com/auth/drive.file',
  ];
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const Duration _requestTimeout = Duration(seconds: 25);

  static Future<void>? _initialization;
  static StreamSubscription<List<ConnectivityResult>>? _connectivity;
  static Timer? _pollTimer;
  static GoogleSignInAccount? _androidAccount;
  static bool _syncing = false;
  static bool get isSyncing => _syncing;
  static String? lastSyncAt;
  static String? lastError;
  static String status = 'Cloud sync not connected';

  static Future<void> initialize() {
    return _initialization ??= _initialize();
  }

  static Future<void> _initialize() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final savedDrivePrimary =
            await _secureStorage.read(key: 'drive_primary_mode');
        DBHelper.drivePrimaryMode = savedDrivePrimary == 'true';
        if (DBHelper.drivePrimaryMode) {
          await DBHelper.stopAutoSync();
        }
      } catch (error) {
        // Fail closed: never resume Firestore automatically if the saved
        // provider choice cannot be read after an app restart.
        DBHelper.drivePrimaryMode = true;
        lastError = error.toString();
        status = 'Cloud sync paused: saved Google Drive setting could not be read';
        debugPrint('Drive provider setting could not be restored: $error');
      }
      try {
        await GoogleSignIn.instance.initialize(
          serverClientId: _androidServerClientId,
        );
        try {
          _androidAccount =
              await GoogleSignIn.instance.attemptLightweightAuthentication();
        } catch (error) {
          debugPrint('Drive sign-in restore skipped: $error');
        }
      } catch (error) {
        lastError = error.toString();
        status = 'Google Drive sign-in is not ready';
        debugPrint('Drive sign-in initialization deferred: $error');
      }
    }
  }

  static Future<String> _deviceId() async {
    var id = await _secureStorage.read(key: 'drive_device_id');
    if (id == null || id.isEmpty) {
      final random = Random.secure();
      final bytes = List<int>.generate(24, (_) => random.nextInt(256));
      id = base64Url.encode(bytes).replaceAll('=', '');
      await _secureStorage.write(key: 'drive_device_id', value: id);
    }
    return id;
  }

  static String _base64Url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static Future<String?> _androidAccessToken({required bool prompt}) async {
    await initialize();
    var account = _androidAccount;
    if (account == null) {
      try {
        account = await GoogleSignIn.instance.attemptLightweightAuthentication();
      } catch (_) {}
    }
    if (account == null && prompt) {
      account = await GoogleSignIn.instance.authenticate();
    }
    if (account == null) return null;
    _androidAccount = account;

    var authorization =
        await account.authorizationClient.authorizationForScopes(_scopes);
    if (authorization == null && prompt) {
      authorization =
          await account.authorizationClient.authorizeScopes(_scopes);
    }
    return authorization?.accessToken;
  }

  static Future<String> _windowsAccessToken({required bool prompt}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final access = await _secureStorage.read(key: 'drive_access_token');
    final expiry = int.tryParse(
          await _secureStorage.read(key: 'drive_access_expires_at') ?? '',
        ) ??
        0;
    if (access != null && expiry > now + 60000) return access;

    final refresh = await _secureStorage.read(key: 'drive_refresh_token');
    if (refresh != null && refresh.isNotEmpty) {
      _requireWindowsClientSecret();
      final response = await http
          .post(
            Uri.https('oauth2.googleapis.com', '/token'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'client_id': _windowsClientId,
              'client_secret': _windowsClientSecret,
              'refresh_token': refresh,
              'grant_type': 'refresh_token',
            },
          )
          .timeout(_requestTimeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await _saveWindowsTokens(data, keepRefreshToken: refresh);
        return data['access_token'].toString();
      }
      await _secureStorage.delete(key: 'drive_access_token');
      if (!prompt) {
        throw Exception(
          'Google Drive authorization expire ho gayi. Cloud Sync screen se dobara Connect karein.',
        );
      }
    }

    if (!prompt) {
      throw Exception('Google Drive connect nahi hai. Pehle Connect Google Drive karein.');
    }
    return _authorizeWindows();
  }

  static Future<void> _saveWindowsTokens(
    Map<String, dynamic> data, {
    String? keepRefreshToken,
  }) async {
    final access = data['access_token']?.toString();
    if (access == null || access.isEmpty) {
      throw Exception('Google ne access token return nahi kiya.');
    }
    final seconds = int.tryParse(data['expires_in']?.toString() ?? '') ?? 3600;
    await _secureStorage.write(key: 'drive_access_token', value: access);
    await _secureStorage.write(
      key: 'drive_access_expires_at',
      value: (DateTime.now().millisecondsSinceEpoch + seconds * 1000).toString(),
    );
    final refresh = data['refresh_token']?.toString() ?? keepRefreshToken;
    if (refresh != null && refresh.isNotEmpty) {
      await _secureStorage.write(key: 'drive_refresh_token', value: refresh);
    }
  }

  static void _requireWindowsClientSecret() {
    if (_windowsClientSecret.isEmpty) {
      throw Exception(
        'Windows Google OAuth client secret configure nahi hai. GitHub repository secret GOOGLE_WINDOWS_CLIENT_SECRET add karke Windows app dobara build karein.',
      );
    }
  }

  static Future<String> _authorizeWindows() async {
    _requireWindowsClientSecret();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://127.0.0.1:${server.port}/';
    final random = Random.secure();
    final verifier = _base64Url(
      List<int>.generate(64, (_) => random.nextInt(256)),
    );
    final challenge = _base64Url(
      sha256.convert(utf8.encode(verifier)).bytes,
    );
    final state = _base64Url(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    final authorizationUri = Uri.https(
      'accounts.google.com',
      '/o/oauth2/v2/auth',
      {
        'client_id': _windowsClientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': _scopes.join(' '),
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
        'access_type': 'offline',
        'prompt': 'consent',
      },
    );

    try {
      final launched = await launchUrl(
        authorizationUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw Exception('Default browser open nahi ho saka.');
      }
      final request = await server.first.timeout(const Duration(minutes: 3));
      final query = request.uri.queryParameters;
      final code = query['code'];
      if (query['state'] != state || code == null || code.isEmpty) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..headers.contentType = ContentType.html
          ..write('<html><body>Google Drive connection failed. You can close this tab.</body></html>');
        await request.response.close();
        throw Exception(query['error_description'] ?? query['error'] ?? 'Google authorization failed.');
      }
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write('<html><body><h3>Khan Baba POS connected.</h3><p>You can return to the POS application.</p></body></html>');
      await request.response.close();

      final tokenResponse = await http
          .post(
            Uri.https('oauth2.googleapis.com', '/token'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'client_id': _windowsClientId,
              'client_secret': _windowsClientSecret,
              'code': code,
              'code_verifier': verifier,
              'grant_type': 'authorization_code',
              'redirect_uri': redirectUri,
            },
          )
          .timeout(_requestTimeout);
      if (tokenResponse.statusCode != 200) {
        throw Exception(
          'Google token exchange failed (${tokenResponse.statusCode}): ${tokenResponse.body}',
        );
      }
      final data = jsonDecode(tokenResponse.body) as Map<String, dynamic>;
      await _saveWindowsTokens(data);
      return data['access_token'].toString();
    } finally {
      await server.close(force: true);
    }
  }

  static Future<String> _accessToken({required bool prompt}) async {
    if (Platform.isWindows) {
      return _windowsAccessToken(prompt: prompt);
    }
    if (Platform.isAndroid) {
      final token = await _androidAccessToken(prompt: prompt);
      if (token == null || token.isEmpty) {
        throw Exception(
          'Google Drive access nahi mila. Connect Google Drive par dobara tap karein.',
        );
      }
      return token;
    }
    throw UnsupportedError('Google Drive sync is supported on Android and Windows.');
  }

  static Future<Map<String, dynamic>> _api(
    String token,
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final request = http.Request(method, uri)
      ..headers.addAll({
        'Authorization': 'Bearer $token',
        if (body != null) 'Content-Type': 'application/json; charset=utf-8',
        ...?headers,
      });
    if (body != null) request.body = body is String ? body : jsonEncode(body);
    final streamed = await request.send().timeout(_requestTimeout);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Google Drive API error (${response.statusCode}): ${response.body}',
      );
    }
    if (response.body.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  static Future<String> _ensureFolder(String token) async {
    final query = "name = '$_folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
    final result = await _api(
      token,
      'GET',
      Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': query,
        'spaces': 'drive',
        'pageSize': '100',
        'fields': 'files(id,name,mimeType)',
      }),
    );
    final files = result['files'] as List? ?? [];
    if (files.isNotEmpty) return files.first['id'].toString();
    final created = await _api(
      token,
      'POST',
      Uri.https('www.googleapis.com', '/drive/v3/files', {
        'fields': 'id,name',
      }),
      body: {
        'name': _folderName,
        'mimeType': 'application/vnd.google-apps.folder',
      },
    );
    return created['id'].toString();
  }

  static Future<List<Map<String, dynamic>>> _listFiles(
    String token,
    String folderId,
  ) async {
    final files = <Map<String, dynamic>>[];
    String? pageToken;
    do {
      final query = "'$folderId' in parents and trashed = false";
      final params = <String, String>{
        'q': query,
        'spaces': 'drive',
        'pageSize': '1000',
        'fields': 'nextPageToken,files(id,name,mimeType,modifiedTime)',
        if (pageToken != null) 'pageToken': pageToken,
      };
      final result = await _api(
        token,
        'GET',
        Uri.https('www.googleapis.com', '/drive/v3/files', params),
      );
      for (final item in (result['files'] as List? ?? [])) {
        if (item is Map) files.add(Map<String, dynamic>.from(item));
      }
      pageToken = result['nextPageToken']?.toString();
    } while (pageToken != null && pageToken.isNotEmpty);
    return files;
  }

  static Future<Map<String, dynamic>> _readJsonFile(
    String token,
    String fileId,
  ) async {
    final response = await http
        .get(
          Uri.https('www.googleapis.com', '/drive/v3/files/$fileId', {
            'alt': 'media',
          }),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(_requestTimeout);
    if (response.statusCode != 200) {
      throw Exception(
        'Cloud data read failed (${response.statusCode}): ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw const FormatException('Cloud JSON file is invalid.');
    return Map<String, dynamic>.from(decoded);
  }

  static Future<void> _uploadJsonFile(
    String token,
    String folderId,
    String name,
    Map<String, dynamic> payload,
    List<Map<String, dynamic>> existingFiles,
  ) async {
    final existing = existingFiles.where((file) => file['name'] == name).toList();
    final content = jsonEncode(payload);
    if (existing.isNotEmpty) {
      final id = existing.first['id'].toString();
      final response = await http
          .patch(
            Uri.https('www.googleapis.com', '/upload/drive/v3/files/$id', {
              'uploadType': 'media',
            }),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: content,
          )
          .timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Cloud file update failed (${response.statusCode}): ${response.body}',
        );
      }
      return;
    }

    final metadata = await _api(
      token,
      'POST',
      Uri.https('www.googleapis.com', '/drive/v3/files', {'fields': 'id,name'}),
      body: {
        'name': name,
        'mimeType': 'application/json',
        'parents': [folderId],
      },
    );
    final id = metadata['id']?.toString();
    if (id == null || id.isEmpty) {
      throw Exception('Google Drive file ID return nahi hui.');
    }
    final response = await http
        .patch(
          Uri.https('www.googleapis.com', '/upload/drive/v3/files/$id', {
            'uploadType': 'media',
          }),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: content,
        )
        .timeout(_requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Cloud file upload failed (${response.statusCode}): ${response.body}',
      );
    }
  }

  static String _snapshotHash(Map<String, dynamic> data) =>
      sha256.convert(utf8.encode(jsonEncode(data))).toString();

  static Future<void> connectAndSync() async {
    status = 'Connecting to Google Drive...';
    lastError = null;
    try {
      final token = await _accessToken(prompt: true);
      if (Platform.isAndroid && !DBHelper.drivePrimaryMode) {
        // Migrate any pending Firebase business data before making Drive primary.
        // Stop its background listener during the Drive cutover, but keep local
        // writes queued so a failed Drive attempt can safely resume Firestore.
        await DBHelper.syncAllData(requireComplete: true);
        await DBHelper.stopAutoSync();
        for (var attempt = 0; attempt < 3; attempt++) {
          await _runSync(token);
          final pending = await DBHelper.getPendingSyncCount();
          if (pending == 0) break;
          if (attempt == 2) {
            throw StateError(
              'Firebase outbox mein $pending pending change(s) hain. Google Drive primary mode activate nahi kiya gaya.',
            );
          }
          await DBHelper.syncAllData(requireComplete: true);
        }
        final remaining = await DBHelper.getPendingSyncCount();
        if (remaining > 0) {
          throw StateError('Firebase outbox abhi bhi $remaining changes pending rakhta hai.');
        }
        // Persist the choice before exposing the in-memory gate. If storage
        // fails, the catch block restores Firestore auto-sync.
        await _secureStorage.write(key: 'drive_primary_mode', value: 'true');
        DBHelper.drivePrimaryMode = true;
        await DBHelper.stopAutoSync();
      } else {
        await _runSync(token);
      }
      await _secureStorage.write(key: 'drive_sync_enabled', value: 'true');
      startAutoSync();
    } catch (error) {
      lastError = error.toString();
      status = 'Google Drive connection needs attention';
      if (Platform.isAndroid && !DBHelper.drivePrimaryMode) {
        DBHelper.startAutoSync();
      }
      startAutoSync();
      rethrow;
    }
  }

  static Future<void> syncNow() async {
    if (_syncing) return;
    try {
      final token = await _accessToken(prompt: false);
      await _runSync(token);
    } catch (error) {
      lastError = error.toString();
      status = 'Sync needs attention';
      rethrow;
    }
  }

  static Future<String> _createWindowsPreMergeBackup(String sourceDeviceId) async {
    final cashierBillIds = await PosWindows.closeSaleWindowsForRestore();
    var databaseClosed = false;
    try {
      final databasePath = await DBHelper.getDatabaseFilePath();
      final databaseDirectory = await DBHelper.getDatabaseDirectory();
      final currentDatabase = File(databasePath);
      if (!await currentDatabase.exists()) {
        throw FileSystemException('Windows master database file not found.', databasePath);
      }
      await DBHelper.closeDatabase();
      databaseClosed = true;
      final backupName =
          'before_drive_merge_${sourceDeviceId}_${DateTime.now().microsecondsSinceEpoch}.db';
      final backupPath = p.join(databaseDirectory, backupName);
      await currentDatabase.copy(backupPath);
      await DBHelper.database;
      databaseClosed = false;
      return backupName;
    } finally {
      if (databaseClosed) {
        try {
          await DBHelper.database;
        } catch (_) {}
      }
      for (final billId in cashierBillIds) {
        try {
          await PosWindows.openSale(billId: billId);
        } catch (error) {
          debugPrint('Could not reopen cashier window after Drive safety backup: $error');
        }
      }
    }
  }

  static Future<void> _runSync(String token) async {
    if (_syncing) return;
    _syncing = true;
    lastError = null;
    status = 'Preparing store data...';
    try {
      final folderId = await _ensureFolder(token);
      final deviceId = await _deviceId();
      final localData = await DBHelper.exportDriveSnapshot();
      final localHash = _snapshotHash(localData);
      final localEnvelope = {
        'schemaVersion': 2,
        'deviceId': deviceId,
        'snapshotHash': localHash,
        'data': localData,
        'uploadedAt': DateTime.now().toUtc().toIso8601String(),
      };
      var files = await _listFiles(token, folderId);
      await _uploadJsonFile(
        token,
        folderId,
        'device_$deviceId.json',
        localEnvelope,
        files,
      );
      files = await _listFiles(token, folderId);
      final masterFile = files.where((file) => file['name'] == 'master_snapshot.json').toList();

      if (Platform.isWindows) {
        status = 'Merging device records into Windows master...';
        final processed = <String, dynamic>{};
        final preMergeBackups = <String, dynamic>{};
        if (masterFile.isNotEmpty) {
          final previousMaster = await _readJsonFile(token, masterFile.first['id'].toString());
          final map = previousMaster['processedSnapshots'];
          if (map is Map) processed.addAll(Map<String, dynamic>.from(map));
          final backups = previousMaster['preMergeBackups'];
          if (backups is Map) preMergeBackups.addAll(Map<String, dynamic>.from(backups));
        }
        var safetyBackupCreated = false;
        for (final file in files.where((file) =>
            (file['name']?.toString() ?? '').startsWith('device_') &&
            file['name'] != 'device_$deviceId.json')) {
          final envelope = await _readJsonFile(token, file['id'].toString());
          final sourceId = envelope['deviceId']?.toString() ?? '';
          final sourceHash = envelope['snapshotHash']?.toString() ?? '';
          final sourceData = envelope['data'];
          if (sourceId.isEmpty || sourceHash.isEmpty || sourceData is! Map) continue;
          if (_snapshotHash(Map<String, dynamic>.from(sourceData)) != sourceHash) {
            throw const FormatException('Device cloud snapshot checksum mismatch.');
          }
          // Do not reconcile an unchanged device snapshot on every poll.
          // This avoids repeated backups and keeps already-approved conflicts closed.
          if (processed[sourceId] == sourceHash) continue;
          final priorBackup = preMergeBackups[sourceId]?.toString();
          final databaseDirectory = await DBHelper.getDatabaseDirectory();
          final priorBackupPath = priorBackup == null
              ? null
              : (p.isAbsolute(priorBackup) ? priorBackup : p.join(databaseDirectory, priorBackup));
          if (priorBackupPath == null || !await File(priorBackupPath).exists()) {
            // Store only the filename in Drive; do not expose the Windows
            // user's local profile path in the shared cloud manifest.
            preMergeBackups[sourceId] = await _createWindowsPreMergeBackup(sourceId);
            safetyBackupCreated = true;
          }
          final merged = await DBHelper.mergeDriveSnapshot(
            envelope,
            sourceDeviceId: sourceId,
            snapshotHash: sourceHash,
          );
          if (merged) {
            processed[sourceId] = sourceHash;
          } else {
            processed.remove(sourceId);
          }
        }
        final conflicts = await DBHelper.getDriveSyncConflictCount();
        final masterData = await DBHelper.exportDriveSnapshot();
        final masterEnvelope = {
          'schemaVersion': 2,
          'masterDeviceId': deviceId,
          'processedSnapshots': processed,
          'preMergeBackups': preMergeBackups,
          'data': masterData,
          'snapshotHash': _snapshotHash(masterData),
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        };
        await _uploadJsonFile(
          token,
          folderId,
          'master_snapshot.json',
          masterEnvelope,
          files,
        );
        status = conflicts > 0
            ? 'Master synced; $conflicts conflict(s) need review'
            : 'Windows master synced successfully';
        if (safetyBackupCreated) status += '. Windows safety backup saved before first device merge.';
      } else {
        if (masterFile.isEmpty) {
          status = 'Device backup uploaded. Waiting for Windows master sync.';
        } else {
          final master = await _readJsonFile(token, masterFile.first['id'].toString());
          final processed = master['processedSnapshots'];
          final approvedHash = processed is Map
              ? processed[deviceId]?.toString()
              : null;
          final masterHash = master['snapshotHash']?.toString() ?? '';
          final masterData = master['data'];
          if (masterData is! Map ||
              (masterHash.isNotEmpty &&
                  _snapshotHash(Map<String, dynamic>.from(masterData)) != masterHash)) {
            throw const FormatException('Windows master snapshot checksum mismatch.');
          }
          if (approvedHash == localHash) {
            await DBHelper.mergeDriveSnapshot(
              master,
              sourceDeviceId: 'windows-master',
              snapshotHash: masterHash.isEmpty ? 'master' : masterHash,
              applyMasterState: true,
              detectConflicts: false,
            );
            status = 'Windows master changes downloaded';
          } else {
            // Do not alter Android data until Windows has processed this exact
            // device snapshot. This keeps the migration hash stable and avoids
            // replacing local stock before reconciliation is approved.
            status = 'Local backup uploaded. Windows master review is pending.';
          }
        }
      }
      lastSyncAt = DateTime.now().toIso8601String();
      await _secureStorage.write(key: 'drive_last_sync_at', value: lastSyncAt);
    } finally {
      _syncing = false;
    }
  }

  static void startAutoSync() {
    if (Platform.isAndroid) {
      unawaited(_startAndroidAutoSync());
    } else if (Platform.isWindows) {
      unawaited(_startWindowsAutoSync());
    }
  }

  static Future<void> _startAndroidAutoSync() async {
    try {
      if (await _secureStorage.read(key: 'drive_sync_enabled') != 'true') return;
      if (!DBHelper.drivePrimaryMode) {
        // Existing paired devices upgrade themselves safely: finish the final
        // Firestore migration, complete a Drive upload, then persist Drive-only
        // business-data sync without requiring the user to pair again.
        await connectAndSync();
        return;
      }
      _attachAutoSync();
    } catch (error) {
      lastError = error.toString();
      status = 'Google Drive migration/sync needs attention';
      debugPrint('Android Drive auto-sync initialization failed: $error');
    }
  }

  static Future<void> _startWindowsAutoSync() async {
    final refresh = await _secureStorage.read(key: 'drive_refresh_token');
    final access = await _secureStorage.read(key: 'drive_access_token');
    if ((refresh == null || refresh.isEmpty) &&
        (access == null || access.isEmpty)) return;
    _attachAutoSync();
  }

  static void _attachAutoSync() {
    if (_connectivity != null) return;
    _connectivity = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        unawaited(syncNow().catchError((Object error) {
          debugPrint('Drive auto-sync deferred: $error');
        }));
      }
    });
    // Connectivity events only report network changes. Poll periodically too,
    // so a device already online notices changes uploaded by the other device.
    _pollTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      unawaited(syncNow().catchError((Object error) {
        debugPrint('Drive periodic sync deferred: $error');
      }));
    });
    unawaited(() async {
      try {
        final results = await Connectivity().checkConnectivity();
        if (results.any((result) => result != ConnectivityResult.none)) {
          await syncNow();
        }
      } catch (error) {
        debugPrint('Drive initial auto-sync deferred: $error');
      }
    }());
  }

  static Future<void> stopAutoSync() async {
    await _connectivity?.cancel();
    _connectivity = null;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  static Future<void> restoreStatus() async {
    lastSyncAt = await _secureStorage.read(key: 'drive_last_sync_at');
    if (!kIsWeb && Platform.isWindows) {
      // Windows remains usable as a local POS even when cloud sync is unavailable.
      try {
        final connectivity = await Connectivity().checkConnectivity();
        final online = connectivity.any(
          (result) => result != ConnectivityResult.none,
        );
        final refresh = await _secureStorage.read(key: 'drive_refresh_token');
        final access = await _secureStorage.read(key: 'drive_access_token');
        final hasCredentials = (refresh != null && refresh.isNotEmpty) ||
            (access != null && access.isNotEmpty);
        if (!online) {
          status = lastSyncAt == null
              ? 'Windows local POS ready — internet unavailable; cloud sync paused'
              : 'Windows local POS ready — internet unavailable; last successful sync: $lastSyncAt';
        } else if (!hasCredentials) {
          status = 'Windows local POS ready — Google Drive is not connected';
        } else {
          status = lastSyncAt == null
              ? 'Windows local POS ready — Google Drive connection found; initial sync pending'
              : 'Google Drive credentials saved — last successful sync: $lastSyncAt';
        }
      } catch (error) {
        lastError = error.toString();
        status = 'Windows local POS ready — connection status unavailable; local data remains available';
      }
      return;
    }
    if (lastSyncAt != null) status = 'Last successful sync: $lastSyncAt';
  }

  static Future<void> disconnect() async {
    await stopAutoSync();
    await _secureStorage.delete(key: 'drive_access_token');
    await _secureStorage.delete(key: 'drive_access_expires_at');
    await _secureStorage.delete(key: 'drive_refresh_token');
    await _secureStorage.delete(key: 'drive_sync_enabled');
    // Keep Drive as the sole business-data provider after disconnect. Local
    // POS operations continue, and Firestore is not silently re-enabled.
    if (Platform.isAndroid) {
      await GoogleSignIn.instance.signOut();
      _androidAccount = null;
    }
    status = 'Cloud sync disconnected';
  }
}
