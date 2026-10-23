# KT1 kontrolna lista za odbranu

Rok iz dostavljenog DOCX-a: kod u `main` do 4. novembra 2026. u 23:59:59. Odbrana zahteva prihvaćenu temu i javni repozitorijum u organizaciji predmeta. Ove administrativne uslove implementacija ne može sama potvrditi.

1. Iz svežeg klona pokrenuti `flutter pub get` u korenu. Pokrenuti mobilni klijent i backoffice bez API-ja/baze/ključeva; podrazumevan je KT1 režim.
2. Pokazati najmanje deset zapisa i svih osam stanja. Izmeniti jedan klijent i pokazati da drugi ima nezavisne podatke.
3. Otvoriti zaseban detalj i formu kreiranja. Naziv od dva znaka prikazuje srpsku domensku grešku. Kreirati validan nacrt i pokrenuti prelaz.
4. Pokazati loading, podatke, prazan rezultat pretrage, komandu za grešku sledećeg zahteva i „Pokušaj ponovo“. Pokazati potvrdu brisanja.
5. Popuniti globalnu memorijsku kvotu i pokušati novu generaciju. Sačuvani nacrt ostaje nacrt; GPU red nije zamena za odbijanje upisa. Pokazati granične bajt-kvote kroz testove domena.
6. U backoffice-u odobriti jednu i odbiti drugu prijavu sa razlogom. Pokazati isti tok na Windows-u i u pregledaču. Pokazati strelice, dve prečice, fokus i sužavanje bez gubitka izbora.
7. Otvoriti izvor `packages/domain` i `packages/blocs`, objasniti port/adapter, promenu stanja i validator. Izmeniti jedno pravilo i pokazati primenu u oba klijenta.
8. Oba člana tima treba da objasne celu implementaciju, rezultate testova i originalni commit predat do roka. Detaljni KT2–KT4 kriterijumi nisu objavljeni u dostavljenim DOCX izvorima.
