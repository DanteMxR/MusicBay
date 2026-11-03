import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicbay/models/track.dart';
import 'package:musicbay/providers/music_provider.dart';
import 'package:musicbay/screens/login_screen.dart';
import 'package:musicbay/services/api_service.dart';
import 'package:musicbay/services/library_index_service.dart';
import 'package:musicbay/widgets/track_tile.dart';
import 'package:provider/provider.dart';

class EmptyStore implements SessionStore {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}

  @override
  Future<void> deleteAll() async {}
}

void main() {
  testWidgets('the login screen needs an address of a server', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) =>
            MusicProvider(ApiService(EmptyStore()), LibraryIndexService()),
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    expect(find.text('Адрес сервера'), findsOneWidget);
    expect(find.text('Имя'), findsOneWidget);
    expect(find.text('Пароль'), findsOneWidget);

    await tester.tap(find.text('Войти'));
    await tester.pumpAndSettle();
    expect(find.text('Укажите адрес сервера'), findsOneWidget);

    await tester.tap(find.text('Создать новый аккаунт'));
    await tester.pumpAndSettle();
    expect(find.text('Создать аккаунт'), findsOneWidget);
  });

  group('a track that cannot be played says why', () {
    Future<void> show(WidgetTester tester, String status) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrackTile(
              track: Track(
                id: 'a',
                artist: 'Artist',
                title: 'Tone',
                duration: 5,
                status: status,
              ),
              onTap: () => fail('it must not play'),
            ),
          ),
        ),
      );
    }

    testWidgets('being processed', (tester) async {
      await show(tester, 'processing');
      expect(find.textContaining('обрабатывает'), findsOneWidget);
      await tester.tap(find.byType(TrackTile));
    });

    testWidgets('failed', (tester) async {
      await show(tester, 'failed');
      expect(find.textContaining('не смог'), findsOneWidget);
      await tester.tap(find.byType(TrackTile));
    });
  });
}
