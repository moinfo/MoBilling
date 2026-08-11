import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mobilling_api/mobilling_api.dart';
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

  messenger.showSnackBar(const SnackBar(
    content: Text('Preparing PDF…'),
    duration: Duration(seconds: 8),
  ));

  try {
    final bytes = await fetch();
    if (bytes.isEmpty) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
          const SnackBar(content: Text('The document came back empty.')));
      return;
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);

    messenger.hideCurrentSnackBar();
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      subject: filename,
    );
  } on ApiException catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}
