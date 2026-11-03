import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import 'track_dialogs.dart';

/// Music reaches the server only through uploads, so this is how a library gets started.
class UploadButton extends StatelessWidget {
  const UploadButton({super.key});

  Future<void> _upload(BuildContext context) async {
    final music = context.read<MusicProvider>();
    final messenger = ScaffoldMessenger.of(context);

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
    );
    final paths = picked?.paths.whereType<String>().toList() ?? const [];
    if (paths.isEmpty || !context.mounted) return;

    final visibility = await askVisibility(context);
    if (visibility == null) return;

    final done = await music.uploadFiles(
      paths.map(File.new).toList(growable: false),
      visibility,
    );
    final failure = music.lastUploadError;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failure == null
              ? 'Загружено: $done. Трек можно будет слушать после обработки'
              : 'Загружено $done из ${paths.length}. $failure',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicProvider>();
    if (music.uploading) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            value: music.uploadProgress,
          ),
        ),
      );
    }
    return IconButton(
      icon: const Icon(Icons.upload_file),
      tooltip: 'Загрузить музыку',
      onPressed: () => _upload(context),
    );
  }
}
