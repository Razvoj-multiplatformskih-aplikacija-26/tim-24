# Demonstracija sistema

KT2 koristi serverski režim. Pokretanje i demo nalozi su u [README-u](../README.md); detaljna pokrivenost bodovanih tačaka je u [vodiču za odbranu](kt2-defense.md). Za ponovljivu demonstraciju koristiti lokalni fake provider, koji ne troši Modal kredite.

## Priprema

1. U čistom klonu kopirati `.env.example` u `.env` i pokrenuti `docker compose up --build -d`. Sačekati zdrave servise i proveriti `http://localhost:8080/health`.
2. Pokrenuti Android kreatora sa API adresom `http://10.0.2.2:8080`, Windows backoffice i browser backoffice sa `http://localhost:8080`. Browser moderator koristi port 8083. Studio se po potrebi pokreće i u browser-u na 8082.
3. Prijaviti `creator1@hedrion.test` na telefonu, `creator2@hedrion.test` u drugom kreatorskom klijentu i `moderator@hedrion.test` u backoffice-u. Lozinke su u README-u. Demo seed ima po jedan model u svakom stanju za oba kreatora; queued/generating seed zapisi su samo snimci stanja.

## Osnovni serverski tok

1. Na telefonu napraviti nov nacrt. Prikazati lokalnu validaciju kratkog naziva, zatim sačuvati ispravan naziv.
2. Izabrati tekstualni unos, upisati „Mala mesingana mehanička sova“ i zatražiti generisanje. Fake provider mora biti jasno označen. Za slikovni tok otpremiti PNG/JPEG pre generisanja.
3. Osvežiti isti kreatorski nalog u drugom klijentu i pokazati isti serverom sačuvan posao. Zatvaranje/reload klijenta ne prekida posao na serveru.
4. Otvoriti gotov model, rotirati interaktivni GLB pregled i preuzeti GLB. Istorija prikazuje provider i ishod; preview i download dolaze kroz autorizovani API.
5. Predložiti model za objavljivanje uz potvrdu prava, CC BY ili CC0 licencu i izbor preuzimanja. Bez prava ili uz nedozvoljenu kombinaciju licence dobija se isto domensko pravilo lokalno i sa servera.
6. U backoffice-u osvežiti listu. Odobriti jednu prijavu i odbiti drugu sa razlogom. Osvežavanje kreatora prikazuje odluku i razlog; odbijeni privatni GLB ostaje vlasniku.
7. Dva moderatorska klijenta otvaraju istu pending prijavu. Prvi odlučuje; drugi pokušava akciju sa starom revizijom. Zakasneli dobija objašnjenje, a lista se ponovo učitava sa stvarnom odlukom.
8. Ponoviti zahtev sa istim idempotency ključem kroz HTTP proveru i pokazati da ne nastaje drugi posao ili nova potrošnja prijema.

## Prijava, uloge i nedostupan server

1. Pokušati kreatorsku prijavu u backoffice-u: prikazuje se namensko objašnjenje da je potreban moderator/administrator.
2. Pokazati da kreator ne može direktnim HTTP pozivom da odobri ili odbije prijavu, niti da izmeni/obriše tuđi privatni model. `tool/kt2_smoke.dart` pokriva ove pozive bez oslanjanja na skrivena UI dugmad.
3. Zatvoriti i ponovo otvoriti Android i Windows aplikaciju; osvežiti browser. Prijava ostaje kroz secure-storage port odnosno scoped HttpOnly cookie.
4. Odjaviti se i ponoviti restart/reload. Prijava se ne vraća. Studio i backoffice sesije u browser-u ostaju međusobno odvojene.
5. Za kratak test isteka koristiti izolovani server sa malim session TTL-ovima, prijaviti se posle promene podešavanja i sačekati apsolutni rok. Aplikacija prikazuje „Sesija je istekla. Prijavite se ponovo.“ i vraća prijavu. Refresh rotacija ne produžava početni login rok.
6. Zaustaviti samo ovaj API sa `docker compose stop server`, pa osvežiti ekran. UI prikazuje problem veze i mogućnost ponovnog pokušaja; ne ostaje beskrajno u učitavanju. Vratiti ga sa `docker compose start server`.

## Zajednička kvota i promena pravila

Globalna granica zavisi od prijema svih korisnika. PostgreSQL test `two concurrent final-slot claims admit exactly one job; replay costs nothing` priprema 19 prihvaćenih prijema i istovremeno šalje dva različita kreatorska zahteva za poslednje mesto. Prolazi tačno jedan.

Za živi prikaz može se na zasebnoj svežoj demo bazi privremeno smanjiti domain granica, poslati zahteve sa dva kreatora i pokazati razlog odbijanja i osveženo stanje. Ne menjati produkcionu/Modal bazu niti ručno resetovati korisničke kvote radi demonstracije.

[Vodič za odbranu](kt2-defense.md) opisuje promenu maksimalnog naziva na serveru i ponašanje ranije izgrađenog klijenta.

## Javni veb i offline tok

Jaspr pokrenuti po README-u. Pre odobrenja model nije u javnoj biblioteci; posle odobrenja anonimno otvoriti detalj, kategoriju, sitemap i HTML izvor. Privatna izmena naziva ne menja već odobreni snimak. Javne slike i download koriste isti metereni API.

Android offline tok koristi SQLite keš/outbox. Na već učitanom sopstvenom modelu isključiti mrežu, izmeniti naziv/opis/favorit i ponovo pokrenuti aplikaciju. Izmena ostaje. Vraćanje mreže sinhronizuje je; ako drugi klijent izmeni istu reviziju, prikazuje se konflikt koji korisnik rešava izričito.

Za test AVD `Hedrion_Test`, uz `adb` i `flutter` na PATH-u:

```powershell
./tool/test-offline-device.ps1 -DeviceId emulator-5554 -ApiUrl http://10.0.2.2:8080 -HostApiUrl http://127.0.0.1:8080 -WithConflict
```

Skripta kreira zaseban test nalog, izvršava tri procesa aplikacije i stvarno menja mrežu samo imenovanog test emulatora. `finally` vraća mrežu i posle greške. Koristi `--no-uninstall` da sačuva podatke između faza. Posle integracionog testa vratiti obični app entrypoint komandom:

```sh
cd apps/mobile
flutter build apk --debug --dart-define=HEDRION_MODE=api --dart-define=HEDRION_API_URL=http://10.0.2.2:8080
```

## Stvarni Modal rezultati

Pravi SPAR3D, Hunyuan3D 2.1, TRELLIS.2 i Qwen rezultati već imaju zasebne [dokaze i obračun](modal-generation.md). Sačuvane rezultate moguće je prikazati i preuzeti bez novog plaćenog zahteva. Za rutinsku KT2 proveru koristiti fake provider; novi benchmark je stvarno naplativa operacija.

Ovaj dokument je scenario demonstracije. Tačno izvršene provere i preostala ograničenja vodi [izveštaj o proveri](verification.md).
