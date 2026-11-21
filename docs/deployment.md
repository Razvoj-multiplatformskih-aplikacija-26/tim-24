# Pokretanje i isporuka

## Lokalni KT2 sistem

Iz korena čistog klona:

```powershell
Copy-Item .env.example .env
docker compose up --build -d
```

Na Linux/macOS prva komanda je `cp .env.example .env`. Docker Compose automatski učitava koreni `.env`. Razvojni primer radi bez izmene; host Dart procesi i Flutter ne učitavaju taj fajl automatski. Postojeći privatni Modal `.env` ne treba prepisivati.

| Komponenta | Lokalna adresa | Pokretanje |
|---|---|---|
| PostgreSQL | `127.0.0.1:55432` | Compose |
| Relic 1.2.0 API | `http://localhost:8080` | Compose |
| CPU fake worker | `http://worker:8091` u Compose mreži | Compose, bez host porta |
| Flutter studio | `http://localhost:8082` | Flutter, API režim |
| Flutter moderator | `http://localhost:8083` | Flutter, API režim |
| Jaspr biblioteka | `http://localhost:8081` | Zaseban Dart proces, po potrebi |

Server čeka zdravu bazu i worker. Pre prihvatanja HTTP zahteva primenjuje `infrastructure/migrations/001_initial.sql`, opciono učitava seed i usklađuje storage evidenciju. `SEED_DEMO_DATA=true` u razvojnom primeru pravi 16 modela, četiri naloga i stvarne male lokalne GLB/PNG primere. `queued` i `generating` seed zapisi služe prikazu stanja i ne pokreću skrivene worker/GPU poslove. Novi eksplicitni zahtev prolazi normalan serverski red i fake worker.

Seed ima trajni marker i izvršava se samo jednom. Restart ne resetuje lozinke, izmene, obrisane modele ni potrošnju. Ako baza već sadrži neki demo imejl bez seed markera, startup odbija da ga preuzme: za tu postojeću bazu koristiti `SEED_DEMO_DATA=false`. Razvojni nalozi i lozinke su u [README-u](../README.md); to su javne lokalne vrednosti.

`docker compose ps` prikazuje zdravstveno stanje, a `docker compose logs server` startup greške. `GET /health` vraća status i Relic verziju. `docker compose down` zaustavlja servise i zadržava bazu i fajlove u imenovanim volume-ima. Za čist test koristiti zaseban Compose project name i slobodne host portove; ne gasiti druge lokalne projekte.

## Konfiguracija

| Promenljiva | Namena |
|---|---|
| `POSTGRES_PASSWORD`, `POSTGRES_PORT` | Lozinka baze i host port; interni DB URL sastavlja Compose |
| `API_PORT` | Host API port; kontejner sluša na 8080 |
| `SEED_DEMO_DATA` | Uključuje lokalne demo podatke; u produkciji isključiti |
| `SESSION_ACCESS_TTL_SECONDS` | Trajanje pristupnog tokena; razvojni Compose primer 900 s |
| `SESSION_REFRESH_TTL_SECONDS` | Trajanje refresh prijave; razvojni primer 2.592.000 s |
| `SECURE_COOKIES` | Razvojni HTTP: `false`; HTTPS isporuka: `true` |
| `CORS_ORIGINS` | Tačno dozvoljena browser porekla, bez wildcard-a |
| `GENERATION_PROVIDER` | `fake` za KT2 bez GPU troška ili `modal` za stvarne modele |
| `WORKER_URL`, `WORKER_SHARED_SECRET` | Privatni provider endpoint i serverska HMAC/Bearer tajna |
| `ENABLED_GENERATION_MODELS` | Omogućeni Modal modeli i validacija njihovog izbora |
| `WORKER_TIMEOUT_SECONDS` | Ograničenje čekanja provider ishoda |

`DATABASE_URL` i `TEST_DATABASE_URL` u primeru su adrese baze za procese na hostu. Compose server koristi servisno ime `postgres`, a ne hostovu loopback adresu. `OBJECT_STORAGE_PATH`, `MIGRATION_FILE` i `SEED_ASSET_PATH` u kontejneru imaju apsolutne putanje iz Compose konfiguracije.

Za nativni host API, nakon izvoza promenljivih u okruženje, pokrenuti iz `apps/server` komandu `dart run bin/server.dart`. Ona koristi isti Relic ulaz i bootstrap kao kontejner. Host fake worker mora imati host adresu `http://127.0.0.1:8091`, a ne Compose ime `worker`. Kompatibilni `services/api/bin/server.dart` prosleđuje isti startup; glavni serverski app je `apps/server`.

## Sesije i mreža

Android i Windows čuvaju sesiju kroz čisti Dart `SessionStorage` port; `SecureSessionStorage` iz `packages/platform_session` je adapter platformskog secure storage-a. Mobilni ključ je `hedrion-session`, a desktop backoffice ključ `hedrion-backoffice-session`. Čuvaju se sesijski podaci, nikada lozinka. Obnova verifikuje identitet na serveru; Android može prikazati sopstveni keš bez mreže.

Browser drži pristupni token u memoriji i rotirajući refresh token u HttpOnly/SameSite=Strict cookie-ju. Studio i backoffice imaju odvojene cookie-je, pa mogu koristiti različite uloge u istom browser-u. Refresh i logout proveravaju dozvoljeno poreklo. Rotacija ne produžava apsolutni rok početne prijave; access rok je ograničen i tim rokom. Odjava opoziva sesiju i briše njen cookie čak i kada je pristupni token već istekao. Istek refresh prijave briše lokalnu sesiju, prikazuje poruku i vraća korisnika na prijavu.

Za lokalni browser koristiti `localhost` i za UI i za API. Kombinacija UI `localhost` i API `127.0.0.1` predstavlja različite sajtove za Strict cookie. Android emulator pristupa host API-ju kroz `10.0.2.2`. API adresa je Flutter `HEDRION_API_URL` define; izvorni kod se ne menja.

Za javnu isporuku postaviti TLS reverse proxy, tačne CORS hostove, `SECURE_COOKIES=true`, jake sopstvene tajne i `SEED_DEMO_DATA=false`. Servisi baze i worker-a ostaju privatni. Flutter dobija samo API adresu. Produkcioni cookie zahteva HTTPS i odgovarajuću topologiju istog sajta; zaštita od XSS-a ostaje obavezna.

## Modal

Stvarni Modal tok koristi isti serverski provider port. U privatnom `.env` postaviti `GENERATION_PROVIDER=modal`, stvarni HTTPS gateway `WORKER_URL`, njegovu `WORKER_SHARED_SECRET` i listu omogućenih modela, pa ponovo pokrenuti server sa tim okruženjem. Compose lokalni worker ostaje jeftin fake servis; Modal zahtev se šalje isključivo iz API-ja.

SPAR3D koristi L4; Hunyuan3D 2.1 i Qwen-Image 2.1 Turbo koriste L40S; TRELLIS.2 koristi **L40S bez H100 zamene**. Pristup težinama, deploy, stvarna merenja i poznato ograničenje Hunyuan geometrije su u [Modal uputstvu](modal-generation.md). Ne ponavljati naplative benchmark-e kao rutinski KT2 test.

## Build

Iz `apps/mobile`:

```sh
flutter build apk --debug --dart-define=HEDRION_MODE=api --dart-define=HEDRION_API_URL=http://10.0.2.2:8080
flutter build web --release --dart-define=HEDRION_MODE=api --dart-define=HEDRION_API_URL=http://localhost:8080
# Za javni Android release koristiti svoj HTTPS API i podešen release potpis:
flutter build appbundle --release --dart-define=HEDRION_MODE=api --dart-define=HEDRION_API_URL=https://api.example.com
```

Iz `apps/backoffice`:

```sh
flutter build windows --release --dart-define=HEDRION_MODE=api --dart-define=HEDRION_API_URL=http://localhost:8080
flutter build web --release --dart-define=HEDRION_MODE=api --dart-define=HEDRION_API_URL=http://localhost:8080
```

Bez `HEDRION_MODE=api` gradi se KT1 memorijski demo. Android NDK je `28.2.13676358` za provereni Flutter 3.47.7. Lokalni HTTP izuzeci koriste se u debug konfiguraciji; javni release koristi HTTPS. Debug potpis i razvojne lozinke nisu produkciona isporuka.

## Trajni podaci i obim provere

Bazu i API object volume uključiti zajedno u backup. Kvota broji stvarne zadržane fajlove i trajne rezervacije; nijedan javni bucket/CDN ne sme zaobići API meterenje. Pre produkcije potreban je zaseban backup/restore drill i nadzor quota/lease događaja. Lokalni Compose je raspored za KT2 na jednom računaru.

Tačno izvršene komande, platformski rezultati i granice provere su u [izveštaju](verification.md). Pripremljen CI nije dokaz da je GitHub workflow već pokrenut. Predaja zahteva commit na GitHub `main` do roka i odbranu oba člana.
