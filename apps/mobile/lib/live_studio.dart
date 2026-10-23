import 'dart:convert';
import 'package:domain/domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hedrion_api_client/hedrion_api_client.dart';
import 'main.dart';
import 'sqlite_persistence.dart';
import 'studio_theme.dart';
import 'initial_route.dart';

class LiveStudio extends StatefulWidget {
  const LiveStudio({super.key});
  @override
  State<LiveStudio> createState() => _LiveStudioState();
}

class _LiveStudioState extends State<LiveStudio> {
  final initialLocation = creatorInitialRoute(
    Uri.base,
    fallback: kIsWeb
        ? '/'
        : WidgetsBinding.instance.platformDispatcher.defaultRouteName,
  );
  final client = HedrionApiClient(
    const String.fromEnvironment(
      'HEDRION_API_URL',
      defaultValue: 'http://localhost:8080',
    ),
  );
  final storage = const FlutterSecureStorage();
  AssetRepository? repository;
  OfflineAssetRepository? offline;
  SqliteOfflinePersistence? persistence;
  bool restoring = true, busy = false, register = false;
  String? error;
  final email = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController();
  @override
  void initState() {
    super.initState();
    client.onSessionChanged = persistSession;
    restore();
  }

  Future<void> persistSession() async {
    if (kIsWeb) {
      return;
    }
    if (client.token == null) {
      await storage.delete(key: 'hedrion-session');
      return;
    }
    await storage.write(
      key: 'hedrion-session',
      value: jsonEncode({
        'token': client.token,
        'refreshToken': client.refreshToken,
        'user': client.user,
      }),
    );
  }

  Future<void> restore() async {
    try {
      if (kIsWeb) {
        try {
          await client.refresh();
          await configure();
        } on DomainException catch (e) {
          if (e.error.code != ErrorCode.unauthenticated) {
            error = errorMessage(e.error);
          }
        }
      } else {
        final saved = await storage.read(key: 'hedrion-session');
        if (saved != null) {
          final data = jsonDecode(saved) as Map<String, dynamic>;
          client.token = data['token'] as String?;
          client.refreshToken = data['refreshToken'] as String?;
          client.user = data['user'] as Map<String, dynamic>?;
          if (client.user != null) {
            await configure();
          }
        }
      }
    } catch (_) {
      error = 'Sačuvana sesija nije dostupna. Prijavite se ponovo.';
    }
    if (mounted) {
      setState(() => restoring = false);
    }
  }

  Future<void> configure() async {
    final remote = ApiAssetRepository(client);
    if (!kIsWeb) {
      final owner = UserId(client.user!['id'] as String);
      persistence = SqliteOfflinePersistence(owner.value);
      offline = OfflineAssetRepository(remote, persistence!, ownerId: owner);
      await offline!.initialize();
      repository = offline;
    } else {
      repository = remote;
    }
  }

  Future<void> authenticate() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (register) {
        await client.register(
          email.text.trim(),
          password.text,
          name.text.trim(),
        );
      } else {
        await client.login(email.text.trim(), password.text);
      }
      await configure();
      if (!kIsWeb) {
        await storage.write(
          key: 'hedrion-session',
          value: jsonEncode({
            'token': client.token,
            'refreshToken': client.refreshToken,
            'user': client.user,
          }),
        );
      }
    } on DomainException catch (e) {
      error = errorMessage(e.error);
    } catch (_) {
      error = 'Prijava nije uspela. Proverite podatke i pokušajte ponovo.';
    }
    if (mounted) {
      setState(() => busy = false);
    }
  }

  Future<void> logout() async {
    try {
      await client.logout();
    } catch (_) {
      client.token = null;
      client.user = null;
    }
    if (!kIsWeb) {
      await storage.delete(key: 'hedrion-session');
    }
    await persistence?.close();
    persistence = null;
    offline = null;
    if (mounted) {
      setState(() => repository = null);
    }
  }

  @override
  void dispose() {
    client.close();
    email.dispose();
    password.dispose();
    name.dispose();
    persistence?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (repository != null) {
      return HedrionStudio(
        key: ValueKey(client.user!['id']),
        repository: repository,
        api: client,
        offline: offline,
        onLogout: logout,
        initialLocation: initialLocation,
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Hedrion · Prijava',
      theme: studioTheme(),
      home: Scaffold(
        body: restoring
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(30),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Icon(
                              Icons.view_in_ar_rounded,
                              color: accent,
                              size: 48,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'hedrion',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              register
                                  ? 'Otvori svoj 3D studio'
                                  : 'Dobro došao u svoj studio',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: muted),
                            ),
                            const SizedBox(height: 30),
                            if (register) ...[
                              TextField(
                                controller: name,
                                decoration: const InputDecoration(
                                  labelText: 'Ime za prikaz',
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],
                            TextField(
                              controller: email,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(
                                labelText: 'E-mail',
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: password,
                              obscureText: true,
                              autofillHints: const [AutofillHints.password],
                              decoration: const InputDecoration(
                                labelText: 'Lozinka',
                              ),
                              onSubmitted: (_) {
                                if (!busy) {
                                  authenticate();
                                }
                              },
                            ),
                            const SizedBox(height: 10),
                            if (error != null)
                              Text(
                                error!,
                                style: const TextStyle(
                                  color: Color(0xffffa49e),
                                ),
                              ),
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: busy ? null : authenticate,
                              child: Text(
                                busy
                                    ? 'Sačekajte…'
                                    : register
                                    ? 'Registruj se'
                                    : 'Prijavi se',
                              ),
                            ),
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => setState(() => register = !register),
                              child: Text(
                                register
                                    ? 'Već imam nalog'
                                    : 'Napravi novi nalog',
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Isti nalog, modeli i poslovi na telefonu i vebu. Generisanje zahteva internet.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: muted,
                                fontSize: 11,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
