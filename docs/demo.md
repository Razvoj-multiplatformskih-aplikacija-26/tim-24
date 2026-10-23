# Demonstracija celog sistema

1. Pokrenuti KT1 režim na Androidu i Windows/veb backoffice-u po README-u. Pokazati nezavisne memorijske podatke i četiri stanja učitavanja. Kontrolna lista je u `checkpoint-evidence/kt1.md`.
2. Pokrenuti bazu, migraciju, fake worker, API i Jaspr. Kreirati moderatorski nalog lokalnom komandom. Studio i backoffice pokrenuti sa API define-ima.
3. Registrovati kreatora na telefonu; isti nalog prijaviti u browser-u. Otpremiti PNG/JPEG, kreirati nacrt i zatražiti generisanje. Posle osvežavanja drugi uređaj prikazuje isti posao. Zatvaranje klijenta ne prekida serversku obradu. Fake rezultat mora biti jasno označen.
4. Pregledati PNG i preuzeti GLB na obe platforme. Ponoviti isti idempotency ključ kroz API test i dokazati da nema novog posla. Pokazati da drugi korisnik ne može da pročita privatni model ili pozove moderatorski endpoint.
5. Isključiti mrežu Android uređaja, izmeniti naziv/opis/favorit već keširanog modela, zatvoriti i ponovo otvoriti aplikaciju. Izmena i outbox ostaju. Vratiti mrežu i sinhronizovati. Ponoviti uz paralelnu browser izmenu; izabrati serversku verziju ili izričito ponoviti lokalnu preko novije revizije.
6. Zatražiti objavljivanje uz potvrdu prava i licencu. Pre odobrenja javna biblioteka nema model. Moderator odobrava jednu i odbija drugu prijavu sa razlogom. Privatni GLB odbijenog modela ostaje dostupan vlasniku.
7. Anonimno otvoriti javni detalj, kategoriju, `sitemap.xml` i HTML izvor. Privatna izmena naslova ne sme promeniti već odobreni snimak. Javni download i preview koriste isti gateway za kvote.
8. Pokrenuti integracione testove za 19+2 konkurentna zahteva, dnevnu granicu, bajt-rezervacije, dve paralelne obrade i konflikt moderacije. Pravi GPU demonstrirati tek kada stvarna infrastruktura i zavisnosti prođu svoj smoke test.

## Ponovljiv Android offline test

Pripremiti test AVD `Hedrion_Test`, pokrenuti ga i sačekati završetak boot-a. API mora biti dostupan emulatoru i hostu. Iz korena, uz `adb` i `flutter` na PATH-u:

```powershell
./tool/test-offline-device.ps1 -DeviceId emulator-5554 -ApiUrl http://10.0.2.2:8080 -HostApiUrl http://127.0.0.1:8080 -WithConflict
```

Skripta kreira zaseban lokalni test nalog, pokreće tri odvojena procesa aplikacije, stvarno isključuje mrežu samo imenovanog test emulatora, trajno menja naziv/favorit i proverava outbox posle ponovnog pokretanja. Opcija `-WithConflict` paralelno menja isti zapis preko drugog HTTP klijenta, zatim proverava vidljiv konflikt i izričito ponovno slanje lokalne izmene preko nove revizije. `finally` vraća mrežu test emulatora i posle greške. Test nema pristup korisničkim nalozima ili drugim emulatorima.

Test koristi `--no-uninstall` da sačuva instalaciju između faza i isključuje Impeller na ovom test emulatoru. Integracioni build koristi test entrypoint; zatim vratiti običnu aplikaciju komandom `flutter build apk --debug --dart-define=HEDRION_MODE=api --dart-define=HEDRION_API_URL=http://10.0.2.2:8080` iz `apps/mobile`, odnosno prilagoditi port svog API-ja.
