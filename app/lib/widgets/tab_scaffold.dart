/**
 * Sekme scaffold widget'ı
 * Ortak AppBar ve logo yapısını sağlar
 */

import 'package:flutter/material.dart';

class TabScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final Widget? floatingActionButton;

  const TabScaffold({
    super.key,
    required this.title,
    required this.body,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            // Logo
            Image.asset(
              'assets/logo_header.png',
              height: 32,
              width: 32,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(Icons.receipt_long);
              },
            ),
            const SizedBox(width: 12),
            Text(title),
          ],
        ),
        elevation: 1,
      ),
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}

