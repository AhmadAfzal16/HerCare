import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Runs before every test file. The app font (Nunito) is bundled in
/// google_fonts/, so load it once up front: every test then lays out text with
/// the real app font, and no font finishes loading halfway through a test
/// (which would change text sizes mid-layout).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final weight in [
    FontWeight.w400,
    FontWeight.w500,
    FontWeight.w700,
    FontWeight.w800,
  ]) {
    GoogleFonts.nunito(fontWeight: weight);
  }
  await GoogleFonts.pendingFonts();
  await testMain();
}
