import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../core/config.dart';
import '../core/update.dart';

const _channel = MethodChannel('cukup/share');

class AppVersion {
  const AppVersion(this.name, this.build);
  final String name;
  final int build;
}

final appVersionProvider = FutureProvider<AppVersion>((ref) async {
  final p = await PackageInfo.fromPlatform();
  return AppVersion(p.version, int.tryParse(p.buildNumber) ?? 0);
});

/// Checks the release page once per launch. Null means up to date, no feed set, or no connection.
final updateProvider = FutureProvider<UpdateInfo?>((ref) async {
  if (updateFeed.isEmpty) return null;
  try {
    final current = await ref.watch(appVersionProvider.future);
    final res = await Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 8), responseType: ResponseType.plain)).get<Object?>(updateFeed);
    return newerThan(current.build, parseUpdate(decodeFeed(res.data)));
  } catch (_) {
    return null;
  }
});

/// Downloads the update and hands it to the Android installer. Returns a message when something needs the user's attention.
Future<String?> downloadAndInstall(UpdateInfo u, void Function(double) onProgress) async {
  try {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/cukup-update.apk';
    await Dio().download(u.apkUrl, path, onReceiveProgress: (got, total) {
      if (total > 0) onProgress(got / total);
    });
    final r = await _channel.invokeMethod<String>('install', path);
    if (r == 'needs_permission') return 'Allow installs from Cukup on the screen that just opened, come back, and tap Update again.';
    if (r != 'ok') return 'Could not open the installer.';
    return null;
  } catch (_) {
    return 'Download failed. Check your connection and try again.';
  }
}
