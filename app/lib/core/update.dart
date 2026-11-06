import 'dart:convert';

/// What `version.json` on the release page says about the newest build.
class UpdateInfo {
  const UpdateInfo({required this.build, required this.name, required this.apkUrl, this.notes = ''});
  final int build; // the number after the + in pubspec's version
  final String name; // e.g. 1.0.3
  final String apkUrl;
  final String notes;
}

/// GitHub serves version.json as application/octet-stream, so the download arrives as text (sometimes with a
/// byte-order mark in front). Turns whatever came back into decoded JSON, or null if it is not JSON.
Object? decodeFeed(Object? raw) {
  if (raw is Map) return raw;
  try {
    var text = raw is String ? raw : (raw is List<int> ? utf8.decode(raw) : null);
    if (text == null) return null;
    if (text.startsWith('﻿')) text = text.substring(1);
    return jsonDecode(text);
  } catch (_) {
    return null;
  }
}

/// Parses version.json. Returns null if it is malformed or the APK link is not https.
UpdateInfo? parseUpdate(Object? json) {
  if (json is! Map) return null;
  final build = json['build'];
  final name = json['name'];
  final apk = json['apk'];
  if (build is! int || name is! String || apk is! String || !apk.startsWith('https://')) return null;
  return UpdateInfo(build: build, name: name, apkUrl: apk, notes: json['notes'] is String ? json['notes'] as String : '');
}

/// The update to offer, or null when the phone already has this build or a newer one.
UpdateInfo? newerThan(int currentBuild, UpdateInfo? latest) => latest != null && latest.build > currentBuild ? latest : null;
