# Arhitektura Hedriona

`packages/domain` je čist Dart: nepromenljivi modeli, tipizirani identifikatori, validator naziva i podataka, prelazi stanja i globalne kvote. `packages/blocs` deli jedan pravi `AssetBloc` sa događajima, Equatable stanjima i serijalizovanim komandama. Widgeti prikazuju stanje i šalju događaje.

`apps/mobile` je ista Flutter aplikacija za Android i kreatorski veb. `apps/backoffice` je zaseban Flutter klijent za Windows i veb. KT1 adapteri su zasebne memorijske instance; nemaju zajednički server i promene se gube zatvaranjem aplikacije. U API režimu oba kreatorska klijenta koriste isti nalog, podatke i serverske poslove.

`packages/hedrion_api_client` implementira verzionisani transport i repozitorijumski port. Android offline adapter trajno čuva vlasnikove podatke i outbox kroz SQLite. Offline izmena čuva originalnu reviziju i stabilan identifikator operacije; pri konfliktu je potreban izričit izbor serverske ili lokalne izmene. Generisanje uvek zahteva mrežu.

`services/api` koristi Shelf i PostgreSQL. Baza čuva metapodatke, prihvaćene poslove, revizije, sesije, snimke prijava, audit, upotrebu i rezervacije. Operacije nad zajedničkim resursima dobijaju PostgreSQL transakcioni advisory lock; to je namerno jednostavno, konzistentno rešenje za MVP, uz ograničenu propusnost. Ugrađeni scheduler koristi trajni red i lease/heartbeat. Prekid klijenta ne otkazuje prihvaćen posao.

GLB i slike nalaze se u privatnom lokalnom skladištu fajlova odvojenom od baze. MVP lokalni disk predstavlja jedan persistent volume API servisa. Horizontalno pokretanje više API instanci zahteva isti deljeni volume ili zamenu skladišnog adaptera; S3/MinIO adapter još nije uključen. Svi klijentski prenosi prolaze kroz API, uključujući anonimne preglede i preuzimanja.

`services/gpu_worker` je zaseban privatni Python proces. Dobija potpisan zahtev i vraća kandidatske bajtove. Dart API proverava format, rezerviše prostor, čuva rezultat i tek onda menja model u `ready`. Fake provider pravi deterministički geometrijski GLB; to nije dokaz rada stvarnog AI modela.

`apps/public_web` renderuje stvarni HTML pomoću Jaspr-a. Poziva isključivo javni API, prikazuje odobrene snimke, metapodatke i linkove kroz metered gateway. Nema pristup bazi ni privatnim tokenima.
