import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

/// Selecciona y conserva una portada dentro del espacio privado de KRAFT.
///
/// Copiar el archivo evita que un proyecto pierda su imagen si el usuario mueve
/// o borra el original después de elegirlo.
abstract final class ProjectCoverStore {
  static const _imageTypes = XTypeGroup(
    label: 'Imágenes',
    extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'],
  );

  static Future<String?> choose() async {
    final source = await openFile(acceptedTypeGroups: const [_imageTypes]);
    if (source == null) return null;

    final appDirectory = await getApplicationDocumentsDirectory();
    final covers = Directory('${appDirectory.path}/project-covers');
    await covers.create(recursive: true);

    final extension = _extensionFor(source.name);
    final destination = File(
      '${covers.path}/cover-${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    await File(source.path).copy(destination.path);
    return destination.path;
  }

  static Future<void> discard(String? path) async {
    if (path == null || path.startsWith('assets/')) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  static String _extensionFor(String name) {
    final match = RegExp(r'\.([a-zA-Z0-9]+)$').firstMatch(name);
    final extension = match?.group(1)?.toLowerCase();
    return switch (extension) {
      'jpg' || 'jpeg' || 'png' || 'webp' || 'heic' || 'heif' => extension!,
      _ => 'jpg',
    };
  }
}
