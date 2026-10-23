# Pravila domena i kvote

Naziv ima 3–60 Unicode znakova posle trimovanja. Opis ima najviše 4000 znakova, a kategorije su `props`, `weapons`, `furniture`, `nature`, `architecture`. Podaci su privatni pri kreiranju. Vlasnik završene generacije može da zatraži objavljivanje; moderator odlučuje o snimku prijave. Odbijanje čuva privatni GLB, a dorada i nova prijava su mogući.

Jedino dozvoljeni prelazi navedeni su u `allowedAssetTransitions`. Obradu obavlja serverski akter; kreator ne može da prijavi uspeh generisanja niti da odobri sopstvenu prijavu. Nevažeće promene revizije daju konflikt.

Globalno se prihvata najviše 20 novih generacija po UTC danu. Prihvatanje, evidencija kvote, posao i prelaz u `queued` pripadaju istoj transakciji. Ranije prihvaćen neuspešan ili otkazan posao i dalje zauzima mesto. Isti idempotency ključ sa istim zahtevom vraća postojeći odgovor. Novi namerni retry troši novo mesto. Dva paralelna zahteva za poslednje mesto ne mogu oba uspeti. Najviše dva `running` posla je nezavisno pravilo raspoređivanja; jedan vlasnik ima najviše jedan aktivan posao.

Prenos fajlova je ograničen na 1.000.000.000 bajtova po UTC danu ukupno: upload, privatni download, anonimni download i slike pregleda. Za poznatu dužinu pre čitanja/serviranja rezerviše se kapacitet. Normalan završetak ili prekid knjiži utrošene bajtove i oslobađa ostatak. Svaki range i ponovljeno preuzimanje računaju se ponovo. Pri prelasku UTC ponoći sledeći segment dobija novu rezervaciju. Bajtovi predati HTTP toku konzervativno se smatraju prenetim; mrežni ACK svakog bajta nije dostupan aplikaciji.

Trajno skladište je ograničeno na 10.000.000.000 bajtova uključujući zadržane verzije, ulazne slike i preglede. Brojač skladišta nema dnevni reset. Rezultat koji ne može da se sačuva ne postaje `ready`. Brisanje oslobađa kapacitet tek posle potvrđenog fizičkog uklanjanja. Posle pada procesa nepoznati fajlovi i nepotvrđeni prenosi konzervativno zauzimaju prostor/kvotu do usaglašavanja.
