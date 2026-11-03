import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../providers/music_provider.dart';
import '../services/api_service.dart';
import '../widgets/track_dialogs.dart';

/// The account on the server: its limits, its devices and the quality of sound.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  static const _qualityTitles = {
    'low': 'Низкое, AAC 96 кбит/с',
    'normal': 'Обычное, AAC 192 кбит/с',
    'lossless': 'Без потерь, FLAC',
  };

  late Future<_AccountData> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_AccountData> _load() async {
    final api = context.read<MusicProvider>().api;
    final results = await Future.wait<Object>([
      api.getMe(),
      api.getQuota(),
      api.getDevices(),
    ]);
    return _AccountData(
      results[0] as String,
      results[1] as Quota,
      results[2] as List<Device>,
    );
  }

  String _size(int bytes) {
    final gigabytes = bytes / (1024 * 1024 * 1024);
    if (gigabytes >= 1) return '${gigabytes.toStringAsFixed(1)} ГБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} МБ';
  }

  Future<void> _chooseQuality() async {
    final quality = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final quality in Track.qualities)
              ListTile(
                title: Text(_qualityTitles[quality] ?? quality),
                trailing: quality == Track.preferredQuality
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(ctx, quality),
              ),
          ],
        ),
      ),
    );
    if (quality == null) return;
    Track.preferredQuality = quality;
    await Hive.box('settings').put('stream_quality', quality);
    if (mounted) setState(() {});
  }

  Future<void> _logoutDevice(Device device) async {
    final confirmed = await askConfirmation(
      context,
      title: 'Завершить сеанс',
      message: 'Выйти из аккаунта на устройстве «${device.name}»?',
      action: 'Выйти',
    );
    if (!confirmed || !mounted) return;
    final api = context.read<MusicProvider>().api;
    await runAndReport(context, () => api.logoutDevice(device.id));
    if (mounted) setState(() => _data = _load());
  }

  Future<void> _logout() async {
    final confirmed = await askConfirmation(
      context,
      title: 'Выход',
      message: 'Выйти из аккаунта?',
      action: 'Выйти',
    );
    if (!confirmed || !mounted) return;
    final music = context.read<MusicProvider>();
    Navigator.of(context).pop();
    await music.logout();
  }

  @override
  Widget build(BuildContext context) {
    final serverUrl = context.read<MusicProvider>().serverUrl;

    return Scaffold(
      appBar: AppBar(title: const Text('Аккаунт')),
      body: FutureBuilder<_AccountData>(
        future: _data,
        builder: (context, snapshot) {
          final data = snapshot.data;
          return ListView(
            children: [
              if (snapshot.connectionState == ConnectionState.waiting)
                const LinearProgressIndicator(),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(data?.username ?? 'Аккаунт'),
                subtitle: Text(serverUrl),
              ),
              if (snapshot.hasError)
                ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: Text('${snapshot.error}'),
                ),
              if (data != null) ...[
                ListTile(
                  leading: const Icon(Icons.storage_outlined),
                  title: Text(
                    'Занято ${_size(data.quota.usedBytes)} из ${_size(data.quota.quotaBytes)}',
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(
                      value: data.quota.quotaBytes == 0
                          ? 0
                          : data.quota.usedBytes / data.quota.quotaBytes,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.upload_outlined),
                  title: Text(
                    'Загрузок сегодня: ${data.quota.uploadsToday} из ${data.quota.uploadsPerDay}',
                  ),
                ),
              ],
              ListTile(
                leading: const Icon(Icons.high_quality_outlined),
                title: const Text('Качество звука'),
                subtitle: Text(
                  _qualityTitles[Track.preferredQuality] ??
                      Track.preferredQuality,
                ),
                onTap: _chooseQuality,
              ),
              if (data != null) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('Устройства'),
                ),
                for (final device in data.devices)
                  ListTile(
                    leading: const Icon(Icons.devices_outlined),
                    title: Text(device.name),
                    subtitle: Text(
                      device.current ? 'Это устройство' : device.platform,
                    ),
                    trailing: device.current
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.logout),
                            tooltip: 'Завершить сеанс',
                            onPressed: () => _logoutDevice(device),
                          ),
                  ),
              ],
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Выйти'),
                onTap: _logout,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AccountData {
  final String username;
  final Quota quota;
  final List<Device> devices;

  const _AccountData(this.username, this.quota, this.devices);
}
