# Arhitektura Hedriona

`packages/domain` je čist Dart: nepromenljivi modeli, tipizirani identifikatori, validator naziva i podataka, prelazi stanja i globalne kvote. `packages/blocs` deli jedan pravi `AssetBloc` sa događajima, Equatable stanjima i serijalizovanim komandama. Widgeti prikazuju stanje i šalju događaje.

`apps/mobile` je ista Flutter aplikacija za Android i kreatorski veb. `apps/backoffice` je zaseban Flutter klijent za Windows i veb. KT1 adapteri su zasebne memorijske instance; nemaju zajednički server i promene se gube zatvaranjem aplikacije. U API režimu oba kreatorska klijenta koriste isti nalog, podatke i serverske poslove.

`packages/hedrion_api_client` implementira verzionisani transport i repozitorijumski port. Android offline adapter trajno čuva vlasnikove podatke i outbox kroz SQLite. Offline izmena čuva originalnu reviziju i stabilan identifikator operacije; pri konfliktu je potreban izričit izbor serverske ili lokalne izmene. Generisanje uvek zahteva mrežu.

`packages/hedrion_contract` opisuje zahteve, odgovore, stranice i greške bez uvoza domena, Flutter-a ili `dart:io`. `packages/hedrion_mapping` je jedno mesto za prevod DTO objekata i domena u oba smera. Podaci pravila putuju uz kod greške, a klijent pravi poruku iz primljenih granica. Ekrani koriste `StudioWorkflows` i `ModerationWorkflows`, dok se memorijski ili HTTP adapter bira pri sastavljanju aplikacije.

`apps/server` pokreće native Relic 1.2.0 API; `services/api` je njegov zajednički servisni sloj za PostgreSQL, sesije, fajlove i scheduler. Docker Compose podiže server, bazu i privatni CPU worker, a startup automatski izvršava migraciju i jednokratni demonstracioni seed. Baza čuva metapodatke, prihvaćene poslove, revizije, sesije, snimke prijava, audit, upotrebu i rezervacije. Operacije nad zajedničkim resursima dobijaju PostgreSQL transakcioni advisory lock; to je namerno jednostavno, konzistentno rešenje za MVP, uz ograničenu propusnost. Ugrađeni scheduler koristi trajni red i lease/heartbeat. Prekid klijenta ne otkazuje prihvaćen posao.

`SessionStorage` je čist Dart port, a `packages/platform_session` koristi bezbedno skladište operativnog sistema za Android i Windows. Browser koristi zasebne HttpOnly kolačiće za studio i backoffice. Server podešava trajanje pristupnog tokena i apsolutni rok prijave; osvežavanje tokena ne pomera taj rok. Istek čisti prijavu i vraća korisnika na login sa porukom.

GLB i slike nalaze se u privatnom lokalnom skladištu fajlova odvojenom od baze. MVP lokalni disk predstavlja jedan persistent volume API servisa. Horizontalno pokretanje više API instanci zahteva isti deljeni volume ili zamenu skladišnog adaptera; S3/MinIO adapter još nije uključen. Svi klijentski prenosi prolaze kroz API, uključujući anonimne preglede i preuzimanja.

`services/gpu_worker` sadrži privatni lokalni Python worker i Modal adaptere. Dobija potpisan zahtev i vraća kandidatske bajtove. Dart API proverava format, rezerviše prostor, čuva rezultat i tek onda menja model u `ready`. Podrazumevani Compose fake provider pravi deterministički geometrijski GLB bez GPU troška. Stvarni Modal tok koristi Qwen za tekstualnu referencu, pa SPAR3D, Hunyuan3D 2.1 ili TRELLIS.2; izbor, merenja i ograničenja dokumentovani su u [Modal uputstvu](modal-generation.md). TRELLIS.2 koristi L40S.

`apps/public_web` renderuje stvarni HTML pomoću Jaspr-a. Poziva isključivo javni API, prikazuje odobrene snimke, metapodatke i linkove kroz metered gateway. Nema pristup bazi ni privatnim tokenima.
