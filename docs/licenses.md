# Licence i neizabrani eksperimentalni kandidati

Konkretan AI model još nije izabran. Aktivni fake provider ne učitava spoljašnje
težine niti zahteva GPU/cloud biblioteku. Ispod su samo sačuvani nalazi prethodnog
pregleda eksperimentalnih kandidata; njihov unos nije odluka da se koriste.

Izvori su provereni 21. oktobra 2026. Evidencija opisuje pročitane uslove;
potpun audit tačnih commit-a, težina i prepakovanog GPU image-a ostaje obaveza
pre produkcione distribucije. Licenca jednog repozitorijuma ne određuje automatski
licence svih njegovih zavisnosti niti prava nad korisničkim ulazima i izlazima.

| Neizabrani eksperimentalni kandidat | Provereni izvor i nalaz |
|---|---|
| Pixal3D | [LICENSE](https://github.com/TencentARC/Pixal3D/blob/master/LICENSE): MIT za objavljeni Tencent sadržaj |
| Pixal3D komponente drugih autora | [NOTICE](https://github.com/TencentARC/Pixal3D/blob/master/NOTICE): zadržavaju posebne uslove originalnih autora |
| TRELLIS.2 | [LICENSE](https://github.com/microsoft/TRELLIS.2/blob/main/LICENSE): MIT za taj repozitorijum |
| NVIDIA nvdiffrast | [LICENSE.txt](https://github.com/NVlabs/nvdiffrast/blob/main/LICENSE.txt): NVIDIA uslovi uključuju ograničenja nekomercijalne istraživačke/evaluacione upotrebe |
| NVIDIA nvdiffrec | [LICENSE.txt](https://github.com/NVlabs/nvdiffrec/blob/main/LICENSE.txt): NVIDIA uslovi uključuju ograničenja nekomercijalne istraživačke/evaluacione upotrebe |
| Tačan skup model weights i dodatnih komponenti | Nije zaključan stvarnim GPU image-om; proveriti izabrane revizije i sve licence pre distribucije |

Za konkretnu isporuku sačuvati potpune LICENSE/NOTICE fajlove za tačne uključene
verzije i potrebne atribucije. Ne predstavljati ceo AI lanac kao bezuslovno
komercijalno licenciran. Odvojeno proveriti uslove model weights, MoGe/DINO
komponenata i svih instalacionih paketa iz stvarnog image-a.

Hedrion fake kocka i njen PNG nastaju iz sopstvenog programskog koda; nisu
preuzeti tuđi model ili tekstura. Autor javnog modela bira CC BY, CC0 ili sva
prava zadržana, ali takav izbor ne može dodeliti prava koja sam autor nema.
Objavljivanje zahteva potvrdu prava i moderatorsko odobrenje, a postupak prijave
spornih radova dostupan je na javnoj stranici `/report`.
