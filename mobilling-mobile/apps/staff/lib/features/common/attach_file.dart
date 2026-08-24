import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

/// One attachment chosen by the person using the app.
class Attachment {
  const Attachment({
    required this.path,
    required this.name,
    required this.bytes,
  });

  final String path;
  final String name;

  /// Size on disk, for the caller's own limit check.
  final int bytes;

  /// `1.4 MB`, for showing beside the file name.
  String get readableSize {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
    return '$bytes B';
  }
}

/// Ask for a receipt, a slip or a fault photo.
///
/// Three ways in, because all three are real: the slip is in your hand (the
/// camera), you photographed it earlier (the library), or someone emailed you
/// a PDF (the file browser). The camera comes first — recording an expense
/// from a phone exists precisely because the paper is in front of you.
///
/// Returns null when the sheet is dismissed or the picker cancelled.
Future<Attachment?> pickAttachment(
  BuildContext context, {

  /// Extensions the endpoint accepts, for the file-browser branch.
  List<String> allowedExtensions = const ['pdf', 'jpg', 'jpeg', 'png'],

  /// Offer the file browser at all. Off where the API only takes an image.
  bool allowFiles = true,
}) async {
  final source = await showModalBottomSheet<_Source>(
    context: context,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
    builder: (sheetContext) {
      final scheme = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_camera_outlined, color: scheme.primary),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(sheetContext, _Source.camera),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                Icons.photo_library_outlined,
                color: scheme.onSurfaceVariant,
              ),
              title: const Text('Choose a photo'),
              onTap: () => Navigator.pop(sheetContext, _Source.gallery),
            ),
            if (allowFiles) ...[
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.folder_outlined,
                  color: scheme.onSurfaceVariant,
                ),
                title: const Text('Choose a file'),
                subtitle: Text(
                  allowedExtensions.join(', ').toUpperCase(),
                  style: Theme.of(sheetContext).textTheme.labelSmall,
                ),
                onTap: () => Navigator.pop(sheetContext, _Source.file),
              ),
            ],
            const SizedBox(height: Spacing.sm),
          ],
        ),
      );
    },
  );

  if (source == null) return null;

  switch (source) {
    case _Source.camera:
    case _Source.gallery:
      final picked = await ImagePicker().pickImage(
        source: source == _Source.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        // A 12MP receipt photo is ~4MB and every endpoint here caps at 5MB;
        // this keeps it well under while staying readable.
        imageQuality: 80,
        maxWidth: 2000,
      );
      if (picked == null) return null;
      return Attachment(
        path: picked.path,
        name: picked.name,
        bytes: await File(picked.path).length(),
      );

    case _Source.file:
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
      );
      final file = result?.files.singleOrNull;
      if (file?.path == null) return null;
      return Attachment(path: file!.path!, name: file.name, bytes: file.size);
  }
}

enum _Source { camera, gallery, file }
