import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/background.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerBackground(); // lets a banner Save create its entry while the app is closed
  runApp(const ProviderScope(child: CukupApp()));
}
