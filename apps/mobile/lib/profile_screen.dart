import 'package:flutter/material.dart';
import 'app_connection.dart';
import 'studio_screens.dart';
import 'studio_theme.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final connection = StudioConnection.maybeOf(context);
    final user = connection?.client?.user;
    final offline = connection?.offline;
    return StudioShell(
      title: 'Profil i podešavanja',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Profil i podešavanja',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_outline),
                      title: Text('${user?['displayName'] ?? 'Demo kreator'}'),
                      subtitle: Text(
                        '${user?['email'] ?? 'KT1 · lokalni nalog'}',
                      ),
                    ),
                    const Divider(),
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.dark_mode_outlined),
                      title: Text('Tamna tema'),
                      subtitle: Text(
                        'Prilagođena radu sa modelima i pregledima.',
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.sync),
                      title: Text(
                        user == null
                            ? 'Demonstracioni režim'
                            : 'Privatna biblioteka',
                      ),
                      subtitle: Text(
                        offline == null
                            ? (user == null
                                  ? 'Nezavisni podaci u memoriji.'
                                  : 'Isti nalog i modeli dostupni su na telefonu i vebu.')
                            : '${offline.online ? 'Povezano' : 'Bez mreže'} · ${offline.pendingCount} izmena čeka slanje.',
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (connection?.onLogout != null)
                      OutlinedButton.icon(
                        onPressed: connection!.onLogout,
                        icon: const Icon(Icons.logout),
                        label: const Text('Odjavi se'),
                      ),
                    const SizedBox(height: 10),
                    const Text(
                      'Modeli ostaju privatni dok ne zatražiš objavljivanje i moderator ga odobri.',
                      style: TextStyle(color: muted, height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
