import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// The app font must work with no internet: every Nunito weight the theme uses
/// has to load from the bundled google_fonts/ assets, never from the network.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every Nunito weight used by the theme loads from bundled assets',
      () async {
    GoogleFonts.config.allowRuntimeFetching = false;
    addTearDown(() => GoogleFonts.config.allowRuntimeFetching = true);
    for (final weight in [
      FontWeight.w400,
      FontWeight.w500,
      FontWeight.w700,
      FontWeight.w800,
    ]) {
      GoogleFonts.nunito(fontWeight: weight);
    }
    // Completes only if every font loaded; a missing asset would throw here
    // because runtime fetching is switched off.
    await expectLater(GoogleFonts.pendingFonts(), completes);
  });
}
