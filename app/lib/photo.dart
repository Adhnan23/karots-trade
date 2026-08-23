import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'core.dart';

/// Photos are resized and re-compressed on the way in so a phone full of
/// products stays small enough to back up in one file.
Future<Uint8List?> pickPhoto(BuildContext c) async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    final f = await FilePicker.pickFile(type: FileType.image);
    return f == null ? null : await f.readAsBytes();
  }

  final src = await showModalBottomSheet<ImageSource>(
    context: c,
    builder: (_) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.photo_camera, size: 32, color: C.products),
          title: Text(t('Take photo'), style: const TextStyle(fontSize: 18)),
          onTap: () => Navigator.pop(c, ImageSource.camera),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library, size: 32, color: C.customers),
          title: Text(t('Choose from gallery'), style: const TextStyle(fontSize: 18)),
          onTap: () => Navigator.pop(c, ImageSource.gallery),
        ),
      ]),
    ),
  );
  if (src == null) return null;
  final x = await ImagePicker()
      .pickImage(source: src, maxWidth: 800, maxHeight: 800, imageQuality: 60);
  return x == null ? null : await x.readAsBytes();
}

/// Product thumbnail with a friendly placeholder when there is no photo.
class Photo extends StatelessWidget {
  final Uint8List? bytes;
  final double size;

  /// Fills its parent instead of drawing at [size] — used by product cards.
  final bool fill;
  const Photo(this.bytes, {this.size = 56, this.fill = false, super.key});

  @override
  Widget build(BuildContext context) {
    if (fill) {
      return bytes == null
          ? Container(
              color: C.products.withValues(alpha: 0.10),
              child: const Icon(Icons.inventory_2, size: 46, color: C.products))
          : Image.memory(bytes!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => Container(
                  color: Colors.black12, child: const Icon(Icons.broken_image)));
    }
    return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: bytes == null
            ? Container(
                width: size,
                height: size,
                color: C.products.withValues(alpha: 0.12),
                child: Icon(Icons.inventory_2, size: size * 0.5, color: C.products))
            : Image.memory(bytes!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => Container(
                    width: size,
                    height: size,
                    color: Colors.black12,
                    child: Icon(Icons.broken_image, size: size * 0.5))));
  }
}
