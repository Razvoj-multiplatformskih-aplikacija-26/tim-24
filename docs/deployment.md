# Pokretanje i isporuka

## Lokalni raspored

| Servis | Lokalna adresa |
|---|---|
| PostgreSQL | `127.0.0.1:55432` |
| Dart API | `http://127.0.0.1:8080` |
| Jaspr biblioteka | `http://localhost:8081` |
| Flutter studio | `http://localhost:8082` |
| Flutter moderator | `http://localhost:8083` |
| Privatni Python worker | `http://127.0.0.1:8091` |

`.env.example` je primer konfiguracije. Procesi ne učitavaju automatski `.env`; izvezite vrednosti kroz shell ili secret manager. Worker i API moraju imati istu nasumičnu `WORKER_SHARED_SECRET` vrednost od najmanje 32 znaka. Baza zahteva sopstvenu lozinku. Flutter dobija samo adresu API-ja, nikada ključ worker-a ili baze.

Docker Compose podiže PostgreSQL sa trajnim imenovanim volume-om. GLB i slike čuvaju se odvojeno u API persistent volume-u; uključiti ga u backup zajedno sa bazom. Pre API-ja pokrenuti migraciju, koja je ponovljiva. `create_moderator.dart` kreira zaseban moderatorski nalog; javna registracija ne može da dodeli privilegije.

## Produkciona mreža

Postaviti TLS reverse proxy, tačne `CORS_ORIGINS`, odvojene hostove za studio, backoffice i javni veb. API/worker/baza ne dobijaju javne interne portove. Android čuva tokene u platformskom secure storage-u. Browser drži pristupni token u memoriji, a sesiju obnavlja preko rotirajućeg HttpOnly/SameSite=Strict cookie-ja; studio i backoffice imaju zasebne cookie-je. Cookie refresh zahteva dozvoljeno poreklo. U produkciji zadržati `SECURE_COOKIES=true`, HTTPS i isti registrabilni domen za browser klijente i API. Lokalno koristiti `localhost` za oba porekla i `SECURE_COOKIES=false`; kombinacija UI `localhost` i API `127.0.0.1` predstavlja različite sajtove za Strict cookie.

Flutter aplikacije koriste `go_router` i podrazumevanu hash strategiju u browser-u; URL iza `#` preživljava osvežavanje bez server rewrite pravila. Ako se uvede path strategija, host mora vraćati odgovarajući `index.html` za privatne studijske rute. Javne `/assets/...` stranice uvek usmeravati na Jaspr, sa stvarnim 404 i HTML odgovorom.

API lokalni fajl storage zahteva jedan deljeni persistent volume. Provera i rezervacije bajtova su u PostgreSQL transakcijama, ali aplikacija ne pokriva sve infrastrukturne računovodstvene bajtove. Potreban je backup/restore drill i nadzor quota/lease događaja. Ne stavljati javni object bucket ili CDN ispred fajlova koji zaobilazi metered API.

## Build komande

Iz `apps/mobile`:

```sh
flutter build apk --release
flutter build appbundle --release
flutter build web --release --dart-define=HEDRION_MODE=api --dart-define=HEDRION_API_URL=https://api.example.com
```

Iz `apps/backoffice`:

```sh
flutter build windows --release
flutter build web --release --dart-define=HEDRION_MODE=api --dart-define=HEDRION_API_URL=https://api.example.com
```

Android projekat koristi `flutter.ndkVersion` (`28.2.13676358` za provereni Flutter 3.47.7); instalirati tu verziju kroz Android SDK Manager. Android API build mora takođe imati `--dart-define=HEDRION_MODE=api` i stvarnu API adresu. Bez define-a isporučuje se KT1 demo. APK debug potpis nije produkcioni potpis; pre store isporuke podesiti keystore, identitet aplikacije i pravo na objavljivanje. Lokalni HTTP izuzeci postoje samo u debug konfiguraciji; release koristiti uz HTTPS.

Za server i Jaspr dovoljan je Dart runtime u odvojenim kontejnerima sa razrešenim workspace zavisnostima; pokretati `dart run bin/server.dart` iz odgovarajućeg paketa. Native executable kompilirati i proveriti na ciljnom Linux sistemu. Ne pokretati Windows binary u Linux kontejneru.

Konkretan AI model i infrastruktura još nisu izabrani. Aktivni lokalni tok koristi zamenljiv provider port i jasno označen fake rezultat. Eksperimentalni materijal za ranije razmatrani model nije obavezan deo instalacije niti izabrana produkciona integracija. Nakon izbora modela proveriti njegov interfejs, zavisnosti, licence i GPU okruženje pre uključivanja. Lokalni fake proverava aplikacioni tok, bez dokaza kvaliteta ili rada stvarne inferencije.
