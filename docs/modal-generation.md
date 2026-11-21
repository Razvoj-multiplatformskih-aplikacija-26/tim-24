# Stvarno generisanje na Modalu

Izabrani modeli i identifikatori:

| Izbor | ID u API-ju | Modal aplikacija | GPU |
|---|---|---|---|
| Fast | `spar3d` | `hedrion-spar3d` | L4 |
| Standard | `hunyuan3d_21` | `hedrion-hunyuan3d` | L40S |
| Quality | `trellis2` | `hedrion-trellis2` | **L40S** |
| Referentna slika iz teksta | `qwen_image_21_turbo` | `hedrion-qwen-image` | L40S |

GPU aplikacije nemaju javni generativni endpoint. Samo privatni
`hedrion-modal-gateway` predaje poslove preko Modal SDK-a. Dart server koristi
HMAC-potpisani HTTP ugovor, odmah prima identifikator posla i proverava završetak.
Izvorna predaja se ne ponavlja automatski posle mrežne greške, kako izgubljen
odgovor ne bi napravio dodatni naplativi posao. Klijenti ne dobijaju Modal/HF tajne.

Za tekstualni unos gateway poziva Qwen, zatim prosleđuje njegov PNG izabranom 3D
modelu. Referentna slika, model, pregled, revizije težina i metrike čuvaju se na
serveru pre prelaska u `ready`. Rezultat ostaje privatan dok ga autor ne predloži
za objavljivanje. Interaktivni prikaz učitava GLB kroz autentifikovani API, a u
renderer prosleđuje bajtove bez tokena. Preuzimanje koristi isti metereni API.

## Priprema i pristup

Svaki `modal_*.py` fajl sadrži pinovane verzije i uputstva za sopstveni deploy i
CPU pripremu težina. CUDA ekstenzije se grade za konkretni GPU; TRELLIS.2 nema
H100 rezervnu konfiguraciju. GPU funkcije imaju ograničene timeout-e i najviše
jedan kontejner po modelu, sa nula stalno toplih kontejnera.

Na Hugging Face nalogu potrebno je odobriti zvanične modele:

- [SPAR3D](https://huggingface.co/stabilityai/stable-point-aware-3d)
- [DINOv3 za TRELLIS.2](https://huggingface.co/facebook/dinov3-vitl16-pretrain-lvd1689m)
- [RMBG-2.0](https://huggingface.co/briaai/RMBG-2.0)

Read token se čuva u Modal Secret `hedrion-huggingface`, ključ `HF_TOKEN`.
Prilikom SPAR deploy-a postaviti `HEDRION_HF_SECRET=hedrion-huggingface`, a za
TRELLIS `HEDRION_HF_SECRET_NAME=hedrion-huggingface`. Samo CPU preuzimanje zahteva
token. `hedrion-worker` sadrži `WORKER_SHARED_SECRET`, identičan lokalnom serveru.
Tajne ne upisivati u izvorni kod, Flutter defines ili rezultate benchmarka.

Qwen 2.1 Turbo koristi istraživačku/nekomercijalnu licencu; SPAR3D Stability
Community licencu; Hunyuan3D 2.1 posebnu Tencent licencu, koja isključuje EU, UK
i Južnu Koreju. Svaki adapter zadržava upstream licence u svom image-u.

## Pokretanje lokalne aplikacije

U gitignored `.env` podesiti `DATABASE_URL`, `POSTGRES_PASSWORD`,
`WORKER_SHARED_SECRET`, `GENERATION_PROVIDER=modal`, `WORKER_URL` iz stvarnog
gateway deploy-a i `ENABLED_GENERATION_MODELS`. Poslednji spisak ograničava i
serversku validaciju i prikaz dostupnosti u aplikaciji.

```powershell
# Iz korena repozitorijuma, nakon instaliranih Flutter/Dart i Docker-a:
./tool/start-live.ps1
# Samo API i baza, bez Flutter web servera:
./tool/start-live.ps1 -ApiOnly
```

Skripta učitava lokalni `.env`, podiže izolovanu PostgreSQL instancu, izvršava
migraciju i čuva logove u `.local/live`. Moderator se jednom kreira pomoću
`services/api/bin/create_moderator.dart` uz vrednosti iz lokalnog okruženja.
Kreator se registruje u studiju. Podrazumevani portovi skripte za klijente su
19082 i 19083; moraju biti prisutni u `CORS_ORIGINS`. Android emulator za API
na host portu 19080 koristi `http://10.0.2.2:19080`.

## Ponovljiv benchmark

`tool/benchmark_live.py` proverava stvarni HTTP tok: registracija, upload ili
tekst, izabrani GPU model, trajni posao, GLB preuzimanje i PNG pregled. Poziv
predstavlja stvarno naplativo generisanje, zato zahteva eksplicitni model:

```powershell
python tool/benchmark_live.py trellis2
python tool/benchmark_live.py hunyuan3d_21 --text
# Samo nameran novi naplativi pokušaj, npr. nakon ispravke obrade slike:
python tool/benchmark_live.py hunyuan3d_21 --run corrected
```

Podaci i rezultati ostaju u `.local/benchmarks/2026-11-14`. Ponovljeni poziv sa
istim modelom/tipom nastavlja prethodni posao umesto automatskog kupovanja novog.
Za slikovni unos očekuje `reference.png` u tom direktorijumu. Rezultati sadrže
merenja inferencije, učitavanja, obrade i ukupnog trajanja; CPU download i izrada
okruženja predstavljaju zasebnu početnu pripremu.

```powershell
python tool/modal_benchmark_report.py --snapshot after
```

Izveštaj koristi zvanični Modal billing CLI. Stvarni iznos po aplikaciji uključuje
pripremu, pokušaje i naplativo vreme kontejnera. Procena uspešne inferencije je
posebno polje i ne predstavlja račun. Krediti se primenjuju na workspace; nema
zasebnih tokena/kredita po modelu. Aktuelni interval obračuna može kasniti.

## Provereni rezultati 14.11.2026.

Qwen-Image 2.1 Turbo generisao je stvarnu 1024×1024 RGBA referentnu sliku mesingane
mehaničke sove na L40S: inferencija 4,525 s, hladno učitavanje 18,426 s, izvršavanje
funkcije 29,336 s, klijentsko ukupno trajanje 35,309 s. Dokaz je lokalni
`qwen-result.json`. Stanje 3D testova i obračun treba čitati iz pojedinačnih
`*.live.json` rezultata i `billing-app-costs.json`, bez pretpostavljanja uspeha
samo na osnovu deploy-a ili prolaznih CPU testova.

DINOv3 zahtev je 14.11.2026. odobren oko 15:47 po lokalnom vremenu. Zatim je
završena CPU priprema i stvarni TRELLIS.2 test na **NVIDIA L40S**. Sva tri modela
su omogućena u lokalnoj konfiguraciji.

| Model | Inferencija | Hladno učitavanje | Ceo worker | Ceo korisnički zahtev |
|---|---:|---:|---:|---:|
| Qwen-Image 2.1 Turbo / L40S | 4,525 s | 18,426 s | 29,336 s | 35,309 s |
| SPAR3D / L4, tekst → 3D | 4,147 s | 43,845 s | 66,100 s | 274,699 s |
| Hunyuan3D 2.1 / L40S, drugi test | 79,154 s | 45,217 s | 176,133 s | 215,207 s |
| TRELLIS.2 / L40S, 512 | 59,026 s | 90,442 s | 160,555 s | 201,431 s |

SPAR ukupno trajanje uključuje Qwen, čekanje slobodnog L4 i server/storage/download.
Hunyuan inferencija uključuje oblik i PBR teksturisanje. Objavljene mere VRAM-a
predstavljaju PyTorch allocator i ne obuhvataju sve native CUDA alokacije.

Stvarni provereni izlazi: SPAR 1.205.068 bajtova / 29.592 trougla, Hunyuan
6.611.432 bajta / 40.000 trouglova, TRELLIS 5.003.540 bajtova / 49.464 trougla.
U pregledaču su provereni prikaz stvarnog GLB-a, rotacija i preuzimanje kroz
dugme aplikacije. Modeli i njihove prave PNG projekcije čuvaju se na serveru.

### Ograničenje kvaliteta Hunyuan rezultata

U oba Hunyuan testa nastala je velika ravna podloga. Popravljena je obrada
skoro-neprovidne Qwen RGBA slike, a zasebno je proverena čista segmentacija;
geometrijski artefakt je ipak ostao. Nije dodat u pregledniku ili Blender
izvozu. Ovo odgovara [prijavljenom upstream problemu #88](https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1/issues/88).
Originalni rezultati su sačuvani, bez proizvoljnog sečenja geometrije ili
predstavljanja kvaliteta kao savršenog. SPAR i TRELLIS rezultati su bez te podloge.

### Trošak

Završni obračun se nalazi u `billing-model-costs.json`/`.csv` i `billing-final.json`
u istom lokalnom direktorijumu. Sadrži **dve Qwen slike, jednu SPAR generaciju,
dva Hunyuan pokušaja i jednu TRELLIS generaciju**, kao i CPU pripremu i gateway.
Trošak pojedinačnog sledećeg zahteva ne treba poistovećivati sa troškom prvog
postavljanja svih okruženja. Krediti i dozvoljeni besplatan mrežni prenos
obračunavaju se na nivou workspace-a.

Poslednji stabilan Modal obračun, 14.11.2026. u 15:56 po lokalnom vremenu:

| Model | Broj GPU generacija | Stvarni GPU trošak | CPU + RAM + GPU, sa pripremom i svim pokušajima |
|---|---:|---:|---:|
| Qwen-Image 2.1 Turbo | 2 | $0,07996089 | $0,14358798 |
| SPAR3D | 1 | $0,03213678 | $0,09790432 |
| Hunyuan3D 2.1 | 2 | $0,31983372 | $0,52537534 |
| TRELLIS.2 | 1 | $0,13433372 | $0,30029555 |
| Privatni gateway | 0 | $0 | $0,00780746 |
| **Ukupno** | **6** | **$0,56626511** | **$1,07497065** |

Ukupno mereno sa mrežnim prenosom je $1,19120615; prenos je pokriven allowance-om.
Trenutni iznos za plaćanje karticom je $0,00. Ovi brojevi su iz stvarnog Modal
billing API-ja, a ne iz procene trajanje × cena GPU-a. Obuhvataju inicijalno
učitavanje, aktivno vreme kontejnera, CPU pripremu i ponovljeni Hunyuan test.
CSV sa vremenima i troškovima je lokalni `benchmark-timings-and-costs.csv`.
