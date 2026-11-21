# KT2: priprema odbrane

KT2 se ocenjuje nad stanjem GitHub grane `main` koje je stiglo do **21.11.2026. u 23:59:59**. Odbrana je **22.11.2026.** i oba člana objašnjavaju ceo sistem. Ovaj vodič opisuje šta treba pokazati; potvrđeni lokalni rezultati su odvojeno u [izveštaju o proveri](verification.md).

## Mapa zahteva

| Zahtev | Gde je rešenje | Šta pokazati |
|---|---|---|
| Dart Relic 1.2.0 server | `apps/server`, `services/api/lib/src/http_api.dart` | `/health`, native Relic zahtev/odgovor, pokretanje |
| Baza, migracija i početni podaci | `docker-compose.yml`, `services/api/lib/src/bootstrap.dart`, `infrastructure/migrations`, `infrastructure/seed` | Čist klon, kopiranje neizmenjenog primera, jedna Compose komanda, 16 modela i četiri naloga |
| Ista pravila | `packages/domain/lib/src/rules.dart` | Lokalno i raw HTTP odbijanje istog pravila i koda |
| Pravilo preko drugih korisnika | `validateDailyGenerationQuota`, `services/api/lib/src/database.dart` | Poslednje globalno mesto, dva istovremena različita kreatora, jedan prolaz |
| Zakasneli klijent | `packages/blocs/lib/blocs.dart` | Odbijena mutacija prikazuje razlog i ponovo učitava podatke |
| DTO paket | `packages/hedrion_contract` | Zahtevi/odgovori/greške bez importa domena, Flutter-a i `dart:io` |
| Jedno mapiranje | `packages/hedrion_mapping` | Asset/draft/actor/error u oba smera na serveru i klijentu |
| Stara aplikacija | `ApiErrorDto.details`, `errorFromDto`, `errorMessage` | Server smanji granicu, raniji klijent prikazuje primljenu novu granicu |
| VM/browser HTTP | `packages/hedrion_api_client` | Isti klijent na telefonu, Windowsu i browser-u |
| Izvor podataka iza porta | `AssetRepository`, `StudioWorkflows`, memorijski i HTTP adapteri | Ekran/Bloc poziva poslovnu operaciju, kompozicioni koren bira adapter |
| Uloge i vlasništvo | `validateBackofficeAccess`, `validateModerationAccess`, `validateAssetOwnership` | Pogrešna prijava, creator approve/reject, tuđi write |
| Sesija i bezbedno skladište | `SessionStorage`, `packages/platform_session`, `LiveStudio`, `LiveBackoffice` | Restart/reload, odjava, istek i poruka na svakoj platformi |
| Spoljni servis | `services/api/lib/src/worker_client.dart`, privatni Python/Modal gateway | Samo server ima tajnu; fake proverava tok bez GPU troška |

## Redosled kratke demonstracije

1. Pokrenuti Compose sa čistom razvojnom bazom i neizmenjenim `.env.example`. Pokazati health, četiri naloga i oba kreatora sa svim stanjima.
2. Prijaviti kreatora na emulatoru i moderatora na Windowsu i u browser-u. Napraviti novi model kroz fake worker; pregledati i preuzeti GLB.
3. Poslati prijavu; osvežiti backoffice, odobriti ili odbiti i pokazati promenu kod kreatora.
4. Pokazati trku dva moderatora, isti kod odbijanja i automatski reload zakasnelog klijenta.
5. Pokazati raw HTTP napade za ulogu/vlasništvo i konkurenciju poslednjeg mesta kvote.
6. Pokazati ponovno pokretanje, browser reload i odjavu na svim platformama, zatim kratak konfigurisan rok isteka.
7. Zaustaviti samo API i pokazati konačnu poruku greške veze. Vratiti server.
8. Pokazati promenu pravila i već izgrađen klijent, pa objasniti pakete i alternative.

Detaljan korisnički tok je u [demo scenariju](demo.md). Nije potrebno ponavljati plaćeno Modal generisanje da bi se dokazao KT2.

## Jedna greška od servera do poruke

Primer je naziv od 45 znakova posle serverskog smanjenja maksimuma na 40:

1. HTTP ruta parsira `AssetDraftDto`; zajednički mapper pravi domenski draft.
2. Server poziva isti `validateDraft/validateTitle` iz domena koji koriste klijenti.
3. `DomainError.invalidTitle` sadrži `minLength:3,maxLength:40,actualLength:45`.
4. Zajednički mapper pravi `ApiErrorDto`; server vraća 422 sa kodom i podacima pravila.
5. Stari HTTP klijent dekodira DTO i koristi isti `errorFromDto` → `DomainError` put.
6. Lokalni `errorMessage` sastavlja „Naziv mora imati od 3 do 40 znakova.“ iz podataka servera.
7. Bloc prikazuje razlog i ponovo učitava aktuelnu listu. Nepoznat budući kod ima bezbednu generičku poruku bez tehničkog teksta.

## Izmena pravila uživo i stara verzija

Pre izmene izgraditi i sačuvati klijenta sa postojećom granicom 60; tokom probe ga ne rebuildovati/hot-reloadovati. Mobilni APK ili statički release web build je pogodan.

Debug APK u API režimu izgraditi ovom komandom iz `apps/mobile`.

```powershell
flutter build apk --debug --dart-define=HEDRION_MODE=api --dart-define=HEDRION_API_URL=http://10.0.2.2:8080
```

Sačuvati `build/app/outputs/flutter-apk/app-debug.apk` pre izmene servera. Ako demo API koristi drugi port, ugraditi taj port pri izradi APK-a i zadržati ga pri oba pokretanja servera. Isti test može da se pokaže kroz **Projekti → Nova kolekcija**, jer naziv kolekcije koristi isto zajedničko pravilo kao naziv modela.

1. U `packages/domain/lib/src/rules.dart` promeniti samo `titleMaxLength = 60` u `titleMaxLength = 40`.
2. Pokrenuti relevantne domain testove i prilagoditi očekivanu granicu ako nastavnik traži trajnu izmenu. Za proveru starih klijenata ne menjati mapper niti tekst poruke ručno.
3. Ponovo izgraditi samo server: `docker compose up --build -d server`.
4. U starom klijentu poslati 45 znakova. Lokalna stara provera dozvoljava zahtev, a server ga odbija sa `invalidTitle` i `maxLength:40`; klijent mora prikazati novu granicu.
5. Isti naziv poslati raw HTTP pozivom ispod i uporediti kod/podatke.
6. Posle vežbe vratiti granicu na dogovorenu vrednost, ponovo proveriti testove i izgraditi server. Stvarna nastavnikova izmena ostaje na odbrambenom commitu prema dogovoru.

PowerShell 7 primer direktnog poziva; demo tajne i tokeni se ne ispisuju:

```powershell
$kt2Api = 'http://localhost:8080'
$kt2Session = Invoke-RestMethod -Method Post -Uri "$kt2Api/api/v1/auth/login" -ContentType 'application/json' -Body (@{
    email='creator1@hedrion.test'; password='HedrionCreator123!'
} | ConvertTo-Json)
$kt2Headers = @{ Authorization="Bearer $($kt2Session.token)" }
$kt2Response = Invoke-WebRequest -SkipHttpErrorCheck -Method Post -Uri "$kt2Api/api/v1/assets" -Headers $kt2Headers -ContentType 'application/json' -Body (@{
    title=('A' * 45); description='Provera nove granice'; category='props'
} | ConvertTo-Json)
$kt2Response.StatusCode
$kt2Response.Content
```

Pre smanjenja granice ovaj zahtev kreira model; posle smanjenja daje 422. Primer koristiti na lokalnom demo sistemu.

## Konkurencija i zakasneli klijent

Globalna kvota broji prihvaćene generacije svih korisnika u istom UTC danu. Check i INSERT su unutar PostgreSQL transakcije i istog advisory lock-a. Dva API procesa dele taj lock, tako da odluku ne čuva lokalni UI ili memorijski brojač.

Integracioni test `two concurrent final-slot claims admit exactly one job; replay costs nothing` priprema 19 prijema, paralelno šalje dva zahteva različitih vlasnika i proverava jedan uspeh, jedno quota odbijanje i odsustvo dodatnog prijema pri idempotentnom replay-u. Može se izdvojeno pokrenuti uz `TEST_DATABASE_URL`:

```sh
dart test services/api/test/postgres_integration_test.dart --plain-name "two concurrent final-slot claims admit exactly one job; replay costs nothing"
```

Za živu demonstraciju kroz klijente može se na zasebnoj svežoj demo bazi privremeno smanjiti podrazumevani `limit` u `validateDailyGenerationQuota`. Odbijeni kreator vidi kod i granicu, a podaci se ponovo učitavaju. Failed/cancelled posao i dalje je prihvaćen dnevni prijem; brisanje modela ne vraća kvotu.

Moderatorski konflikt je odvojena demonstracija revizije: oba klijenta učitaju istu pending reviziju, prvi odluku potvrdi, a drugi dobije konflikt i reload. Nemojte pripremu trke raditi nad sačuvanim stvarnim Modal korisničkim podacima.

## Sesije na svakoj platformi

| Platforma | Obnova | Odjava / istek |
|---|---|---|
| Android | KeyStore-backed secure storage iza porta + server provera, SQLite sopstveni keš bez mreže | Brisanje sesijskog bundle-a, poruka pri isteku i prijava |
| Windows backoffice | Platformski secure storage iza istog porta, odvojen aplikacioni ključ | Brisanje credential-a i povratak na prijavu |
| Browser studio/backoffice | Odvojeni HttpOnly refresh cookie-ji, access token samo u memoriji | Opoziv i brisanje izabranog cookie-ja; druga aplikacija ostaje prijavljena |

`SESSION_ACCESS_TTL_SECONDS` određuje trajanje pristupnog tokena, a `SESSION_REFRESH_TTL_SECONDS` apsolutni rok početne prijave. Refresh rotira credential-e, ali ne pomera taj rok; aktivno polling osvežavanje ne produžava prijavu zauvek.

Za demonstraciju smanjiti TTL u **izolovanom razvojnom** okruženju, restartovati server i tek zatim se ponovo prijaviti, jer postojeći sesijski redovi već imaju svoje rokove. Posle isteka pokrenuti akciju/osvežavanje i pokazati namensku poruku i login. Posebno pokazati odjavu nakon isteka access tokena dok refresh još važi: reload ne sme vratiti odjavljenog korisnika.

## Odluke i alternative

| Izbor | Obrazloženje | Razmotrena alternativa |
|---|---|---|
| PostgreSQL transakcija + globalni advisory lock | Jednostavno dokaziva atomskost kvota, revizija i rezervacija na malom opterećenju | Fini row lock-ovi daju veći paralelizam, ali složeniji redosled zaključavanja |
| DTO odvojen od domena, zajednički mapper | Wire promene i projekcije uloga ne ulaze u UI/domain modele | Direktni domain JSON je jednostavniji, ali vezuje server i stare klijente |
| Kod greške + podaci, poruka na klijentu | Nova serverska granica radi i u ranije izgrađenoj aplikaciji | Serverski tekst ne daje istu lokalizovanu lokalnu/server proveru |
| Refresh cookie u browser-u, secure storage na VM-u | Browser JS ne dobija trajni refresh credential; native koristi bezbedno skladište | localStorage bi izložio trajni browser token JavaScript-u |
| Relic server + provider port | Jedan autoritet za pravila i tajne, zamenljiv fake/Modal iza servera | Direktan cloud poziv iz Flutter-a bi izložio tajne i zaobišao prijeme/kvote |
| Snapshot objavljivanja | Kasnija privatna izmena ne menja odobren sadržaj | Živa veza ka privatnom modelu bi objavila neproverenu izmenu |
| Cursor i server provera uloge | Stabilne stranice i dozvoljeni skup podataka bez oslanjanja na UI | Jedna neograničena lista raste bez kontrole; UI skrivanje ne štiti API |

Treći klijent koristi isti ugovor, mapper i HTTP paket. Nove poslovne odluke dodaju se u domen; platformsku sesiju dobija kroz isti port, a server i dalje konačno proverava sveže stanje i identitet.

## Kontrola predaje

- Oba člana umeju da objasne svaku gornju putanju i odbijenu alternativu.
- `.env`, tokeni, stvarne lozinke i lokalni benchmark session fajlovi ostaju gitignored.
- README pokretanje i demo nalozi odgovaraju commitu za predaju.
- Izvršeni testovi i stvarne platformske provere upisani su u `docs/verification.md`; ne označavati neizvršeno kao uspeh.
- Commit je stvarno pushovan na GitHub `main` pre roka. Lokalni HEAD, prolazni testovi i samo pripremljen CI nisu dokaz push-a.
