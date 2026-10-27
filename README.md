# Superclean Dreammachine

Een eerbetoon-speler voor het **Mixcloud-archief van wijlen Hans Prisma** — de show
*Superclean Dreammachine* (181 afleveringen, 2018–2022). De speler kiest telkens een
**willekeurige show** uit het volledige archief en speelt die af via de officiële
Mixcloud-widget. Gemaakt door en voor liefhebbers van Berlin School / elektronische muziek.

> *A shuffle player for the late Hans Prisma's "Superclean Dreammachine" Mixcloud archive.
> Pick a random show from all 181 episodes and let it play. Works in any browser, or as a
> small native macOS app. English readers: the usage steps below are simple enough to follow —
> open the HTML file, or run `app/build.sh` on a Mac.*

---

## Wat het doet

- 🎲 Speelt het **hele archief in willekeurige volgorde** af (shuffle), onthoudt welke shows
  je al hoorde.
- ▶️ **Hervat** waar je gebleven was, onthoudt je **volume** en je **bewaarde nummers**.
- 📜 Toont per show de **tracklist** (uit de Mixcloud-commentaren) met directe **Spotify**-links.
- 🔎 Doorzoekbare, inklapbare lijst van alle shows.

De showlijst en tracklists worden live opgehaald via de **publieke Mixcloud API**; afspelen
gebeurt via de **officiële Mixcloud-widget**. Er wordt **geen audio gehost of gekopieerd** —
alles streamt rechtstreeks van Mixcloud. Je hebt dus een internetverbinding nodig.

## Zo gebruik je het

### 1. In de browser (snelste manier)
Open **`hans-prisma-shuffle.html`** in Chrome, Safari of een andere moderne browser. Klaar.

### 2. Als Mac-app
Een klein, zelfstandig programma *Superclean Dreammachine.app* met eigen icoon in het Dock —
geen browservenster nodig, reageert op de **media-toetsen** van je toetsenbord en toont de
afspeelstatus op het Dock-icoon.

**Vereisten:** macOS + Apple Command Line Tools. Nog niet geïnstalleerd? Eenmalig:

```bash
xcode-select --install
```

**Bouwen en installeren** (download deze map, open Terminal erin en plak):

```bash
bash app/build.sh
```

Dit compileert de app (met `swiftc`, geen Xcode-project nodig), maakt het icoon, signeert
ad-hoc en kopieert *Superclean Dreammachine.app* naar `/Applications`. Start daarna met:

```bash
open "/Applications/Superclean Dreammachine.app"
```

De app laadt `hans-prisma-shuffle.html` **live uit deze map**, dus wijzig je de HTML, dan is
dat meteen zichtbaar (⌘R om te herladen). ⌘Q sluit af; het "Over"-menu toont de versie.

## Hoe het in elkaar zit

| Bestand | Rol |
|---|---|
| `hans-prisma-shuffle.html` | De volledige speler (HTML/CSS/JS, één bestand). |
| `app/main.swift` | Native macOS-wrapper (AppKit + `WKWebView`). |
| `app/makeicon.swift` | Genereert het app-icoon uit Hans' studiofoto. |
| `app/Info.plist` | App-metadata; `build.sh` vult het projectpad in. |
| `app/build.sh` | Bouwt, signeert en installeert de app. |

## In memoriam

Deze speler is gemaakt ter nagedachtenis aan **Hans Prisma** en zijn *Superclean Dreammachine*,
zodat zijn muziekselecties vindbaar en beluisterbaar blijven. 🌌

## Licentie

Code onder de [MIT-licentie](LICENSE). De muziek, opnames en afbeeldingen blijven eigendom
van hun respectieve rechthebbenden; dit project linkt enkel naar Mixcloud en host niets.
