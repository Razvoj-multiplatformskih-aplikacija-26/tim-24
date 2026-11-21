# Hedrion

AI studio za kreiranje, organizovanje i deljenje statičnih 3D modela za video-igre. Android i browser kreator koriste istu Flutter aplikaciju, nalog, privatnu biblioteku i serverske poslove. Javno deljenje je opciono i zahteva moderatorsko odobrenje.

## Tim

| Ime i prezime | Indeks | GitHub |
|---|---|---|
| Vasilije Stankovic | SI 100/24 | [Vaske10024](https://github.com/Vaske10024) |
| Jovan Petrovic | SI 115/24 | [jpetrovic115si](https://github.com/jpetrovic115si) |

## KT2: pokretanje iz čistog klona

Potreban je Docker sa Compose v2. Iz korena novog klona, u PowerShell-u:

```powershell
Copy-Item .env.example .env
docker compose up --build -d
```

Na Linux/macOS koristiti `cp .env.example .env`, pa istu Compose komandu. Primer sadrži upotrebljive **lokalne razvojne** vrednosti; za ovaj tok ne treba menjati nijednu. Ako `.env` već postoji zbog Modala, sačuvati ga i ne prepisivati ga primerom.

Compose podiže PostgreSQL, Relic **1.2.0** API i privatni CPU fake worker. API pri pokretanju primenjuje migracije i idempotentni seed. Nije potrebno ručno kreirati tabele ili naloge. Seed sadrži **16 modela**, po jedan u svakom od osam stanja za oba kreatora, kao i četiri naloga:

| Uloga | Imejl | Razvojna lozinka |
|---|---|---|
| Kreator 1 | `creator1@hedrion.test` | `HedrionCreator123!` |
| Kreator 2 | `creator2@hedrion.test` | `HedrionCreator123!` |
| Moderator | `moderator@hedrion.test` | `HedrionModerator123!` |
| Administrator | `admin@hedrion.test` | `HedrionAdmin123!` |

Lozinke se u bazu upisuju kao PBKDF2 heševi. Ponovno pokretanje ne prepisuje postojeće naloge i korisničke izmene. Seed `queued`/`generating` modeli su demonstracioni snimci stanja i ne pokreću skrivene poslove; novi eksplicitni zahtev prolazi normalan fake worker tok. Lokalni seed i fake worker ne koriste GPU niti Modal kredite. Stvarno generisanje ostaje dostupno u posebno podešenom Modal režimu.

```powershell
docker compose ps
Invoke-RestMethod http://localhost:8080/health
```

API je na `http://localhost:8080`, baza na `127.0.0.1:55432`, a worker je dostupan samo u Compose mreži. Baza i fajlovi koriste trajne volume-e. `docker compose down` zaustavlja ovaj sistem i zadržava podatke. Ako su portovi zauzeti, podesiti `API_PORT`/`POSTGRES_PORT` u lokalnom `.env`, a klijentu proslediti odgovarajuću API adresu.

## Flutter klijenti nad serverom

Potrebni su Flutter/Dart, Android SDK za emulator i Visual Studio C++ alatke za Windows. Razvojno okruženje je Flutter 3.47.7, Dart 3.13.5 i Android NDK `28.2.13676358`; workspace zahteva Dart 3.10+. Iz korena pokrenuti `flutter pub get`, zatim u zasebnim terminalima:

```sh
cd apps/mobile
flutter run -d <android-device-id> --dart-define=HEDRION_MODE=api --dart-define=HEDRION_API_URL=http://10.0.2.2:8080
# Isti kreator u browser-u:
flutter run -d chrome --web-port 8082 --dart-define=HEDRION_MODE=api --dart-define=HEDRION_API_URL=http://localhost:8080
```

```sh
cd apps/backoffice
flutter run -d windows --dart-define=HEDRION_MODE=api --dart-define=HEDRION_API_URL=http://localhost:8080
# Isti moderator u browser-u:
flutter run -d chrome --web-port 8083 --dart-define=HEDRION_MODE=api --dart-define=HEDRION_API_URL=http://localhost:8080
```

`flutter devices` prikazuje Android identifikator. `10.0.2.2` je adresa hosta iz Android emulatora; fizički telefon koristi dostupnu LAN/HTTPS adresu. Za browser koristiti `localhost` i u UI i u API adresi zbog SameSite cookie-ja. Portovi 8082/8083 pripadaju podrazumevanom CORS spisku. Adrese se menjaju podešavanjem, bez izmene Dart koda.

Backoffice: strelice biraju zapis, Ctrl+Enter odobrava, Ctrl+Backspace otvara odbijanje. Kreatorski nalog se odbija uz objašnjenje da je backoffice namenjen moderatorima i administratorima.

Mobilni i Windows klijent čuvaju sesiju kroz `SessionStorage` port i platformski secure storage. Browser koristi odvojene HttpOnly refresh cookie-je za studio i backoffice. Lozinka se na uređaju ne čuva. Trajanje određuju `SESSION_ACCESS_TTL_SECONDS` i `SESSION_REFRESH_TTL_SECONDS` na serveru; istekla sesija prikazuje objašnjenje i vraća prijavu.

## Struktura

| Putanja | Namena |
|---|---|
| `packages/domain` | Čist Dart domen, ID tipovi, zajednička prava, validatori i kvote |
| `packages/hedrion_contract` | Nezavisni Dart DTO zahtevi, odgovori, stranice i greške |
| `packages/hedrion_mapping` | Zajednički prevod DTO ↔ domen, uključujući greške |
| `packages/blocs` | Zajednički Bloc sa događajima i Equatable stanjima |
| `packages/hedrion_api_client` | VM/browser HTTP adapter, sesijski port, trajni outbox i konflikti |
| `packages/platform_session` | Zajednički adapter platformskog secure storage-a |
| `apps/server` | Relic 1.2.0 server i pokretanje iz okruženja |
| `apps/mobile` | Jedan Flutter kreator za Android i veb |
| `apps/backoffice` | Flutter moderator za Windows i veb |
| `apps/public_web` | Jaspr server-rendered javna biblioteka |
| `services/api` | Serverski servisni sloj: PostgreSQL, auth, kvote, fajlovi i scheduler |
| `services/gpu_worker` | Privatni Python provider bridge i Modal adapteri |

## Pravila i tokovi

1. **Uloge:** kreator upravlja sopstvenim privatnim modelima, moderator/admin odobrava ili odbija prijave. Prava su u domenu, a server identitet učitava samo iz sopstvene sesije. Registracija ne dodeljuje moderatorska prava.
2. **Stanja:** `Asset` koristi `draft`, `queued`, `generating`, `ready`, `pendingReview`, `published`, `failed`, `rejected`. Odbijena prijava čuva privatni rezultat.
3. **Zajednički kapacitet:** najviše 20 prihvaćenih generacija po UTC danu, 1 GB prenosa po UTC danu i 10 GB trajnih fajlova za ceo sistem. Provera i rezervacija su atomske PostgreSQL transakcije. Dva globalna aktivna worker posla i jedan aktivan zahtev po kreatoru su odvojena ograničenja. Odbijena akcija prikazuje razlog i osvežava podatke.
4. **Ugovor:** DTO paket ne uvozi domen, Flutter ni `dart:io`. Mape između domena i DTO-a postoje u jednom paketu. Greška prenosi kod i podatke pravila, a klijent sastavlja poruku iz primljene granice. Nepoznat kod daje razumljivu lokalnu poruku.
5. **Rad bez mreže:** Android čuva keš i outbox u SQLite. Naziv, opis i favorit keširanog sopstvenog modela mogu da se izmene bez mreže, prežive restart i sinhronizuju uz vidljiv konflikt revizije. Generisanje zahteva mrežu.
6. **Javni sadržaj:** Jaspr prikazuje HTML odobrenih snimaka sa autorom, licencom, canonical/OG i sitemap podacima. Privatni modeli nisu deo javnog API-ja. Fajlovi se preuzimaju kroz metereni API.

## Modal i javni veb

Modal adapteri podržavaju SPAR3D (L4), Hunyuan3D 2.1 (L40S), TRELLIS.2 (**isključivo L40S**) i Qwen-Image 2.1 Turbo (L40S). Tekstualni zahtev prvo generiše referentnu sliku kroz Qwen, zatim izabrani 3D model. Interaktivni pregled i download koriste GLB sa servera.

Za postojeći plaćeni tok zadržati lokalni `.env` sa `GENERATION_PROVIDER=modal`, stvarnim `WORKER_URL` gateway-a i odgovarajućom serverskom tajnom. Nad postojećom korisničkom bazom koristiti `SEED_DEMO_DATA=false`; demo seed pripada čistoj KT2 bazi. Klijenti i dalje komuniciraju samo sa Relic API-jem. Podešavanje, stvarna merenja, trošak i poznato Hunyuan ograničenje opisani su u [Modal uputstvu](docs/modal-generation.md). Ne treba ponavljati benchmark radi KT2 demonstracije.

Jaspr javna biblioteka pokreće se zasebno kada je potrebna demonstracija javnog HTML-a:

```powershell
cd apps/public_web
$env:API_ORIGIN = 'http://localhost:8080'
$env:PUBLIC_ORIGIN = 'http://localhost:8081'
$env:STUDIO_ORIGIN = 'http://localhost:8082'
dart run bin/server.dart
```

## KT1 memorijski režim

Za KT1 izostaviti `--dart-define=HEDRION_MODE=api`. Oba Flutter klijenta tada koriste svoje memorijske implementacije, bez servera i GPU-a. Kontrolna lista je u [KT1 dokazima](docs/checkpoint-evidence/kt1.md). API ugovor je u [API dokumentaciji](docs/api.md), demonstracija u [demo scenariju](docs/demo.md), a priprema svih KT2 tačaka i izmena pravila u [vodiču za odbranu](docs/kt2-defense.md).

## Provere i build

Za PostgreSQL integracione testove prvo postaviti `TEST_DATABASE_URL` iz lokalnog `.env`. Testovi koriste zasebnu privremenu šemu, koju zatim brišu; bez promenljive integracioni deo je preskočen i to nije dokaz serverske ispravnosti. PowerShell može učitati samo tu promenljivu bez prikaza tajni:

```powershell
$env:TEST_DATABASE_URL = (Get-Content .env | Where-Object { $_ -match '^TEST_DATABASE_URL=' }) -replace '^TEST_DATABASE_URL=', ''
```

Zatim iz korena:

```sh
dart analyze
dart test packages/domain/test packages/hedrion_contract/test packages/hedrion_mapping/test packages/blocs/test packages/hedrion_api_client/test apps/public_web/test services/api/test
dart run tool/kt2_smoke.dart http://localhost:8080
```

Iz `apps/mobile`:

```sh
flutter test
flutter build apk --debug --dart-define=HEDRION_MODE=api --dart-define=HEDRION_API_URL=http://10.0.2.2:8080
flutter build web --release --dart-define=HEDRION_MODE=api --dart-define=HEDRION_API_URL=http://localhost:8080
```

Iz `apps/backoffice`:

```sh
flutter test
flutter build windows --release --dart-define=HEDRION_MODE=api --dart-define=HEDRION_API_URL=http://localhost:8080
flutter build web --release --dart-define=HEDRION_MODE=api --dart-define=HEDRION_API_URL=http://localhost:8080
```

Zajednički secure-storage adapter ima Flutter testove: iz `packages/platform_session` pokrenuti `flutter test`. Iz `services/gpu_worker` pokrenuti `python -m unittest discover -s tests -v`.

`tool/kt2_smoke.dart` proverava KT2 HTTP tok nad seedovanim fake sistemom i odbija plaćeni provider pre mutacija. Izvršeni rezultati su u [izveštaju o proveri](docs/verification.md). `tool/smoke.dart` dodatno pokriva Jaspr tok uz putanju do PNG slike i moderatorske promenljive okruženja.

[CI](.github/workflows/ci.yml) pokriva analizu, format, PostgreSQL testove i platformske build-ove. [Isporuka](docs/deployment.md) opisuje release komande, mrežu i skladište. Lokalno izvršeni rezultati i ograničenja vode se u [izveštaju o proveri](docs/verification.md).

Za KT2 se ocenjuje stanje koje stigne na GitHub granu `main` do **21.11.2026. u 23:59:59**. Odbrana je **22.11.2026.**; oba člana obrazlažu ceo sistem i izmenu pravila uživo. Lokalni testovi i dokumentacija ne predstavljaju potvrdu da je commit već pushovan ili da je odbrana završena.
