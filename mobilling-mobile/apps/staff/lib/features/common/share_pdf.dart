import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Download PDF bytes and hand them to the platform share sheet.
///
/// The share sheet (rather than an in-app viewer) is deliberate: it gives
/// Quick Look / print / save-to-Files / WhatsApp in one gesture, which is what
/// clients actually do with invoices. Files land in the temp directory, so the
/// OS reclaims them — no cache management needed.
Future<void> sharePdf(
  BuildContext context, {
  required Future<Uint8List> Function() fetch,
  required String filename,
}) async {
  final messenger = ScaffoldMessenger.of(context);

  // A spinner beside the words, so the wait reads as progress rather than
  // as a notice the app happened to post.
  messenger.showSnackBar(
    const SnackBar(
      content: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          SizedBox(width: Spacing.sm + 4),
          Text('Preparing PDF…'),
        ],
      ),
      duration: Duration(seconds: 8),
    ),
  );

  try {
    final bytes = await fetch();
    if (bytes.isEmpty) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('The PDF came back empty. Try again in a moment.'),
        ),
      );
      return;
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);

    messenger.hideCurrentSnackBar();
    await Share.shareXFiles([
      XFile(file.path, mimeType: 'application/pdf'),
    ], subject: filename);
  } on ApiException catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}
