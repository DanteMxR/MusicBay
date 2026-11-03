import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../providers/music_provider.dart';

/// Asks who can see a track or a playlist. Returns null when the user changes their mind.
Future<String?> askVisibility(BuildContext context, {String? current}) {
  const options = [
    ('private', Icons.lock_outline, 'Только для меня'),
    ('unlisted', Icons.link, 'По ссылке'),
    ('public', Icons.public, 'Для всех, с поиском'),
  ];
  return showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (value, icon, title) in options)
            ListTile(
              leading: Icon(icon),
              title: Text(title),
              trailing: value == current ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, value),
            ),
        ],
      ),
    ),
  );
}

/// Asks for a line of text. Returns null when the user changes their mind.
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String label,
  required String action,
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (value) => Navigator.pop(ctx, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: Text(action),
        ),
      ],
    ),
  );
  controller.dispose();
  final text = result?.trim();
  return text == null || text.isEmpty ? null : text;
}

Future<bool> askConfirmation(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Runs a change on the server and tells the user if it did not work.
Future<void> runAndReport(
  BuildContext context,
  Future<void> Function() action, {
  String? done,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    if (done != null) {
      messenger.showSnackBar(SnackBar(content: Text(done)));
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}

/// The actions on a track that only its owner can do. The server refuses the others.
List<Widget> ownTrackActions(BuildContext context, Track track) {
  final music = context.read<MusicProvider>();
  return [
    ListTile(
      leading: const Icon(Icons.edit_outlined),
      title: const Text('Изменить название, артиста и альбом'),
      onTap: () async {
        Navigator.pop(context);
        await showDialog<void>(
          context: context,
          builder: (_) => _EditTrackDialog(track: track, music: music),
        );
      },
    ),
    ListTile(
      leading: const Icon(Icons.visibility_outlined),
      title: const Text('Кто видит трек'),
      onTap: () async {
        final messengerContext = Navigator.of(context).context;
        Navigator.pop(context);
        final visibility = await askVisibility(
          messengerContext,
          current: track.visibility,
        );
        if (visibility == null || !messengerContext.mounted) return;
        await runAndReport(
          messengerContext,
          () => music.updateTrack(track, visibility: visibility),
        );
      },
    ),
    ListTile(
      leading: const Icon(Icons.delete_forever_outlined),
      title: const Text('Удалить с сервера'),
      onTap: () async {
        final messengerContext = Navigator.of(context).context;
        Navigator.pop(context);
        final confirmed = await askConfirmation(
          messengerContext,
          title: 'Удалить трек',
          message: 'Трек «${track.title}» будет удалён с сервера.',
          action: 'Удалить',
        );
        if (!confirmed || !messengerContext.mounted) return;
        await runAndReport(
          messengerContext,
          () => music.deleteOwnTrack(track),
          done: 'Трек удалён',
        );
      },
    ),
  ];
}

class _EditTrackDialog extends StatefulWidget {
  final Track track;
  final MusicProvider music;

  const _EditTrackDialog({required this.track, required this.music});

  @override
  State<_EditTrackDialog> createState() => _EditTrackDialogState();
}

class _EditTrackDialogState extends State<_EditTrackDialog> {
  late final _title = TextEditingController(text: widget.track.title);
  late final _artist = TextEditingController(
    text: widget.track.artistId == null ? '' : widget.track.artist,
  );
  late final _album = TextEditingController(
    text: widget.track.albumTitle ?? '',
  );

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Изменить трек'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Название'),
            ),
            TextField(
              controller: _artist,
              decoration: const InputDecoration(labelText: 'Артист'),
            ),
            TextField(
              controller: _album,
              decoration: const InputDecoration(labelText: 'Альбом'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () async {
            final navigator = Navigator.of(context);
            await runAndReport(
              context,
              () => widget.music.updateTrack(
                widget.track,
                title: _title.text.trim(),
                artist: _artist.text.trim(),
                album: _album.text.trim(),
              ),
            );
            navigator.pop();
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
