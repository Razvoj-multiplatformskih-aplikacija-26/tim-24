# Hedrion

AI studio za kreiranje, organizovanje i deljenje statičnih 3D modela za video-igre. Android i browser kreator koriste istu Flutter aplikaciju i, u API režimu, isti nalog, privatnu biblioteku i serverske poslove. Javno deljenje je opciono i zahteva moderatorsko odobrenje.

## Tim

| Ime i prezime | Indeks | GitHub |
|---|---|---|
| Vasilije Stankovic | SI 100/24 | [Vaske10024](https://github.com/Vaske10024) |
| Jovan Petrovic | SI 115/24 | [jpetrovic115si](https://github.com/jpetrovic115si) |

## Šest zahteva predmeta

1. **Uloge:** kreator upravlja svojim privatnim modelima, moderator obrađuje prijave. Server proverava identitet, vlasništvo i ulogu; registracija ne dodeljuje moderatorska prava.
2. **Stanja:** centralni `Asset` ima `draft`, `queued`, `generating`, `ready`, `pendingReview`, `published`, `failed`, `rejected`. Oba Flutter klijenta i server koriste ista domenska pravila; odbijena prijava čuva privatni rezultat.
3. **Zajednička pravila:** najviše 20 prihvaćenih generacija po UTC danu, 1 GB upload+download po UTC danu i 10 GB trajnih fajlova za ceo sistem. Podaci drugih korisnika mogu da odbiju novi upis; provera i rezervacija su atomske PostgreSQL transakcije. Dva aktivna GPU posla su odvojeno pravilo raspoređivanja.
4. **Rad bez mreže:** Android čuva keš i outbox u SQLite. Naziv, opis i favorit sačuvanog sopstvenog modela mogu da se izmene bez mreže, prežive restart i sinhronizuju uz vidljiv konflikt revizije; generisanje zahteva internet.
5. **Posao osoblja:** Windows/veb backoffice ima tabelu, pretragu, status, bočni detalj i odobravanje/odbijanje sa razlogom. Strelice, dve prečice i vidljiv fokus podržavaju tastaturu; uži prozor prelazi u listu uz očuvan izbor.
6. **Javni sadržaj:** zaseban Jaspr veb vraća anonimni HTML odobrenih snimaka sa naslovom, opisom, kategorijom, autorom i licencom, canonical/OG i sitemap podacima. Privatni modeli nisu deo javnog API-ja, a preuzimanje i preview prolaze kroz iste kvote.

## Struktura i režimi

| Putanja | Namena |
|---|---|
| `packages/domain` | Čist Dart domen, ID tipovi, validatori i kvote |
| `packages/blocs` | Zajednički Bloc sa događajima i Equatable stanjima |
| `packages/hedrion_api_client` | HTTP adapter, trajni outbox i konfliktni tok |
| `apps/mobile` | Jedan Flutter kreator za Android i veb |
| `apps/backoffice` | Flutter moderator za Windows i veb |
| `apps/public_web` | Jaspr server-rendered javna biblioteka |
| `services/api` | Dart/Shelf, PostgreSQL, kvote, auth i scheduler |
| `services/gpu_worker` | Privatni Python provider bridge |

**KT1 je podrazumevan:** svaki Flutter klijent ima svoj memorijski repozitorijum sa najmanje deset modela i svim stanjima, kašnjenjem i komandom za grešku sledećeg zahteva. Nisu potrebni baza, internet, prijava ni GPU. **API režim** bira se sa `--dart-define=HEDRION_MODE=api`; oba klijenta tada koriste stvarni server.

**AI stanje:** konkretan model još nije izabran. Zajednički provider interfejs i lokalni deterministički `fake` daju validan GLB i PNG za proveru aplikacionog toka; rezultat je jasno označena demonstracija. Stvarna inferencija i tekst → referentna slika nisu aktivni. Prethodno razmatrani adapteri ostaju isključeni eksperimenti, bez zavisnosti za osnovno pokretanje; videti [AI granicu](docs/ai-provider.md).

## Čist klon i KT1

Lokalno provereno okruženje: Flutter 3.47.7, Dart 3.13.5 i Python 3.12.14 za worker; workspace zahteva Dart 3.10+, a worker Python 3.11+. CI je podešen na Python 3.13. Instalirati Android SDK sa NDK `28.2.13676358` koji traži ova Flutter verzija i Visual Studio C++ alatke za odgovarajuće platforme. Iz korena:

```sh
flutter pub get
```

U zasebnim terminalima:

```sh
cd apps/mobile
flutter run -d <android-device-id>
# Ista kreatorska aplikacija u browser-u:
flutter run -d chrome --web-port 8082
```

```sh
cd apps/backoffice
flutter run -d windows
# Ili isti moderator u browser-u:
flutter run -d chrome --web-port 8083
```

`flutter devices` prikazuje Android identifikator. Backoffice: strelice biraju zapis, Ctrl+Enter odobrava, Ctrl+Backspace otvara odbijanje. KT1 scenariji i četiri stanja su u [kontrolnoj listi](docs/checkpoint-evidence/kt1.md).

## Lokalni API režim

Kopirati vrednosti iz `.env.example` u shell okruženje; aplikacije ne učitavaju `.env` automatski. Primer za PowerShell, sopstvenim lokalnim lozinkama:

```powershell
$env:POSTGRES_PASSWORD = '<lokalna-lozinka>'
docker compose -f infrastructure/docker-compose.yml up -d postgres
$env:DATABASE_URL = 'postgres://hedrion:<lokalna-lozinka>@127.0.0.1:55432/hedrion?sslmode=disable'
$env:WORKER_SHARED_SECRET = '<ista-nasumicna-tajna-od-najmanje-32-znaka>'
$env:WORKER_URL = 'http://127.0.0.1:8091'
$env:OBJECT_STORAGE_PATH = '../../.local/objects'
$env:CORS_ORIGINS = 'http://localhost:8082,http://localhost:8083'
$env:SECURE_COOKIES = 'false' # Samo lokalni HTTP; produkcija koristi HTTPS.
cd services/api
dart run bin/migrate.dart
$env:MODERATOR_EMAIL = 'moderator@example.test'
$env:MODERATOR_PASSWORD = '<lozinka-od-najmanje-12-znakova>'
dart run bin/create_moderator.dart
dart run bin/server.dart
```

Novi terminal, postaviti istu worker tajnu:

```powershell
cd services/gpu_worker
$env:WORKER_SHARED_SECRET = '<ista-tajna-kao-na-API-ju>'
$env:GENERATION_PROVIDER = 'fake'
python -m hedrion_worker.server --port 8091
```

Javni veb, novi terminal:

```powershell
cd apps/public_web
$env:API_ORIGIN = 'http://127.0.0.1:8080'
$env:PUBLIC_ORIGIN = 'http://localhost:8081'
$env:STUDIO_ORIGIN = 'http://localhost:8082'
dart run bin/server.dart
```

Pokrenuti Flutter klijente uz `--dart-define=HEDRION_MODE=api --dart-define=HEDRION_API_URL=http://localhost:8080`. Za browser studio zadržati `--web-port 8082`, a za browser moderator `--web-port 8083`; ti portovi odgovaraju gornjem `CORS_ORIGINS` spisku. Android emulator koristi `http://10.0.2.2:8080`; fizički telefon zahteva dostupnu LAN/HTTPS adresu API-ja i odgovarajući bind/firewall.

Registrovati kreatora u studiju; isti nalog radi na telefonu i vebu. Moderator se prijavljuje prethodno kreiranim nalogom. Primeri API ugovora su u [API dokumentaciji](docs/api.md), a ceo tok u [demo scenariju](docs/demo.md).

## Provere i build

Iz korena:

```sh
dart analyze
dart test packages/domain/test packages/blocs/test packages/hedrion_api_client/test apps/public_web/test services/api/test
```

Za stvarne PostgreSQL integracione testove postaviti `TEST_DATABASE_URL` kao `DATABASE_URL`. Testovi koriste zasebnu privremenu šemu, koju zatim brišu; bez promenljive integracioni deo je preskočen i to nije dokaz serverske ispravnosti.

```sh
cd apps/mobile
flutter test
flutter build apk --debug
flutter build web --release
```

```sh
cd apps/backoffice
flutter test
flutter build windows --release
flutter build web --release
```

```sh
cd services/gpu_worker
python -m unittest discover -s tests -p test_worker.py -v
```

`tool/smoke.dart` proverava stvarni HTTP tok kroz oba kreatorska session-a, worker, preuzimanje, moderatora i Jaspr. Pokrenuti sve servise, postaviti `MODERATOR_EMAIL`/`MODERATOR_PASSWORD`, pa iz korena `dart run tool/smoke.dart <putanja-do-PNG-slike>`.

[CI](.github/workflows/ci.yml) pokriva analizu, format, testove sa PostgreSQL-om i veb/Windows build. [Isporuka](docs/deployment.md) opisuje release komande, TLS, sesije, skladište i preostale spoljašnje uslove. Lokalno izvršeni rezultati i ograničenja vode se u [izveštaju o proveri](docs/verification.md).

Izvorni DOCX dokumenti ostaju neizmenjeni. Detaljna KT2–KT4 pravila nisu priložena; plan prati konačnu specifikaciju i objavljene opšte zahteve. Prihvatanje teme, rok `main` predaje i odbrana oba člana tima ostaju obaveze tima.
