import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:hedrion_api_client/hedrion_api_client.dart';
import 'main.dart';
import 'studio_theme.dart';

class LiveBackoffice extends StatefulWidget {
  const LiveBackoffice({super.key});
  @override
  State<LiveBackoffice> createState() => _LiveBackofficeState();
}

class _LiveBackofficeState extends State<LiveBackoffice> {
  final client = HedrionApiClient(
    const String.fromEnvironment(
      'HEDRION_API_URL',
      defaultValue: 'http://localhost:8080',
    ),
    browserScope: 'backoffice',
  );
  final email = TextEditingController(), password = TextEditingController();
  bool busy = false;
  String? error;
  bool authenticated = false;
  bool restoring = true;
  @override
  void initState() {
    super.initState();
    restore();
  }

  Future<void> restore() async {
    if (kIsWeb) {
      try {
        await client.refresh();
        authenticated = ['moderator', 'admin'].contains(client.user?['role']);
      } catch (_) {
        /* No browser refresh session means show login. */
      }
    }
    if (mounted) {
      setState(() => restoring = false);
    }
  }

  Future<void> login() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await client.login(email.text.trim(), password.text);
      if (!['moderator', 'admin'].contains(client.user!['role'])) {
        await client.logout();
        throw const DomainException(DomainError(ErrorCode.forbidden));
      }
      authenticated = true;
    } on DomainException catch (e) {
      error = errorMessage(e.error);
    } catch (_) {
      error = 'Prijava nije uspela.';
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
    }
    if (mounted) {
      setState(() => authenticated = false);
    }
  }

  @override
  void dispose() {
    client.close();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (authenticated) {
      return HedrionBackoffice(
        repository: ApiAssetRepository(client, moderator: true),
        api: client,
        onLogout: logout,
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Hedrion · Moderator',
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
                              Icons.shield_outlined,
                              size: 44,
                              color: accent,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Moderatorski studio',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Prijavite se nalogom sa moderatorskom ulogom.',
                              style: TextStyle(color: muted),
                            ),
                            const SizedBox(height: 26),
                            TextField(
                              controller: email,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'E-mail',
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: password,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Lozinka',
                              ),
                              onSubmitted: (_) {
                                if (!busy) {
                                  login();
                                }
                              },
                            ),
                            if (error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: Text(
                                  error!,
                                  style: const TextStyle(
                                    color: Color(0xffffa49e),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 22),
                            FilledButton(
                              onPressed: busy ? null : login,
                              child: Text(busy ? 'Sačekajte…' : 'Prijavi se'),
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

class BackofficeConnection extends InheritedWidget {
  const BackofficeConnection({
    super.key,
    required super.child,
    this.api,
    this.onLogout,
  });
  final HedrionApiClient? api;
  final VoidCallback? onLogout;
  static BackofficeConnection? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BackofficeConnection>();
  @override
  bool updateShouldNotify(BackofficeConnection oldWidget) =>
      oldWidget.api != api;
}
