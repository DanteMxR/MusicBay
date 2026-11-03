import 'package:flutter/material.dart';

/// The server refuses versions older than its minimum, so nothing else would work here.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.system_update_outlined, size: 64),
              SizedBox(height: 16),
              Text(
                'Сервер больше не поддерживает эту версию приложения. '
                'Обновите MusicBay.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
