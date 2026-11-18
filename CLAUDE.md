# Wegweiser – eigenes Addon für WoW Forever

Dan baut ein eigenes Addon. Es ersetzt ForeverDB, ForeverDB_Helper,
ForeverDungeonMap und Gathercraft. AutoLayer und ForeverThreat bleiben getrennt.

## Spiel
- Client: WoW Forever (Classic-Basis), `## Interface: 16001`, Sprache `deDE`.
- Pfad: `A:\Games\Battle.net\World of Warcraft\_forever_\Interface\AddOns\Wegweiser`
- Forever blockt `COMBAT_LOG_EVENT_UNFILTERED` für Addons.
- Prüfen vor dem Spiel (Python-Paket `lupa` mit LuaJIT/Lua 5.1 ist installiert):
  - `python Werkzeuge/Test/syntax.py .` – Syntax aller Lua-Dateien
  - `python Werkzeuge/Test/laden.py .` – lädt das Addon in einer nachgebauten WoW-API
    (`mockwow.lua`), feuert Ereignisse, öffnet alle Reiter, klickt alle Knöpfe. Muss "KEINE FEHLER" zeigen.
  - Neue Funktionen: Szene in `laden.py` ergänzen. Die Nachbildung ersetzt keinen Test im Spiel.

## Regeln
- Alles, was der Spieler sieht, ist **Deutsch**.
- Namen in Code und Dateien dürfen deutsch sein (wie bisher).
- Jede Lua-Datei beginnt mit `local ADDON, WW = ...`.
- Keine globalen Variablen außer: `Wegweiser`, `WegweiserDB`, `WegweiserCharDB`,
  `Wegweiser_Umschalten`, Frame-Namen mit Präfix `Wegweiser`, `SLASH_WEGWEISER*`, `BINDING_*`.
- API-Aufrufe, die es im Classic-Client vielleicht nicht gibt, mit `if X then` oder `pcall` absichern.
- **Forever hat `GetItemInfo` und `GetItemIcon` nicht** (nur `C_Item.*`). Immer `WW.GetItemInfo(...)` und
  `WW.GetItemIcon(id)` aus Kern.lua benutzen. `/ww api` zeigt im Spiel, welche weiteren Funktionen fehlen.
  `mockwow.lua` lässt fehlende Funktionen (Liste `__FEHLT`) wie im Spiel abstürzen – dort ergänzen, was `/ww api` meldet.
- Daten in `Daten\` nie von Hand ändern. Sie kommen aus `Werkzeuge\Daten-aktualisieren.ps1`.
- Quellenangabe "Daten von ForeverDB.net" muss bleiben (GPL-3.0 7(b)).

## Aufbau
| Datei | Inhalt |
|---|---|
| `Kern.lua` | API-Hilfen für Forever (neue API zuerst, alte als Ersatz): `WW.GetItemInfo`, `WW.GetItemIcon`, `WW.SpellName`, `WW.QuestLogEintraege`/`QuestLogEintrag`/`QuestLogAnzahl`, `WW.QuestErledigt`, `WW.QuestWaehlen`, `WW.Fertigkeiten`, `WW.Alt`, `WW.Neu`; dazu `WW:Event`, `WW:BeimStart`, `WW.db`/`WW.charDb`, `WW.standardDB`, `WW.Geld`, `WW.ItemName`, `WW.ItemID`, `WW.HaendlerPreis`, `WW:Befehl`, `WW.f` (Farbe) |
| `Uebersetzung.lua` | `WW.beruf` (en→de), `WW.berufEn`, `WW.DungeonName(id)` |
| `Fenster.lua` | Hauptfenster, `WW:Reiter(schluessel, titel, reihenfolge, bauen, eltern)` (mit `eltern` = Unterreiter; Panel ist `WW.UNTER_HOEHE` hoch, Höhe mit `p:GetHeight()` lesen), `WW:Oeffnen(schluessel)` (auch Unterreiter), `WW:AktiverReiter()`, UI-Bausteine `WW.UI.*` (`liste.itemKlick = true`: Linksklick öffnet Item-Details, Rechtsklick das Menü "Mehr Information"; `UI.Menue`, `UI.ItemMenue(id)`), Minimap-Knopf |
| `Module\Items.lua` | Reiter "Items": ohne Suchtext die eigenen Items (Taschen, Bank, angelegt), Suche, "Wofür ist das?". `WW:ItemZeigen(id)` öffnet die Details, trägt den Namen in die Suche ein, Knopf "Zurück". `WW:ItemUnterMaus()` für die Taste `WEGWEISER_ITEMINFO`. Rechtsklick in Blizzards AH-Ergebnissen: `AH.MerkeZeile` (HookScript auf der Zeile über der Preiszelle) |
| `Module\Auktion.lua` | Reiter "Auktionshaus": Scan, Preise, Farben, `WW.AH.*`. Tagespreise für die Grafik in `WW.db.ahTage[Realm|Fraktion][itemID] = "tag:min,..."` (30 Tage, `AH.Grafikdaten`, Grafik `UI.PreisGrafik` in den Item-Details). Kategorie-Knopf für Schnäppchen/Zu teuer/Verkaufen (`AH.Kategorien`: Blizzards `AuctionCategories` nur gelesen, sonst eigene Liste; `markt.kategorie` = "Name" oder "Name/Unter", `AH.KategoriePasst`). Filter-Fenster für Schnäppchen (`AH.FilterPasst`: Seltenheit `markt.q[0..5]`, `weissAus`, `stufeVon/Bis`, `nutzbar`). Knopf "Wegweiser" unten an Blizzards AH legt das Fenster rechts daneben (`WW:OeffnenAn`, `WW:Abdocken`; Schließen dockt ab) |
| `Module\AuktionHandel.lua` | Kaufen ("Schnäppchen") und Einstellen eigener Items ("Zu teuer") aus dem AH-Reiter: jeder Schritt ein Klick (suchen, Preis holen, kaufen), Grenzen: Schnäppchen-Preis, Summe der Suche, 1/4 des Golds; Einstellen 1 Silber unter dem günstigsten, nie unter dem üblichen Preis. Ansicht "Verkaufen" (`AH.VerkaufListe`): alle ungebundenen Taschen-Items, Untergrenze `e.boden` = max(80 % vom üblichen Preis, Händlerpreis nach Abzug und Kaution), unter der Grenze wird zur Grenze eingestellt. Ein Vorgang gilt nur in seiner Ansicht (`op.ansicht`). `WW.AHHandel.*` |
| `Module\Handwerk.lua` | Reiter "Handwerk": Gewinn pro Rezept (Zutaten zum günstigsten Preis, Ertrag = AH-Mindestpreis nach Gebühren oder Händler), Händler-Kaufpreise in `WW.db.haendlerKauf`, `WW.Handwerk.*` |
| `Module\Haendler.lua` | Knopf am Händlerfenster: verkauft graue Items und "AH lohnt nicht" (rot, nur mit sicherem Verlauf). Zwei Klicks, langsam, stoppt bei Handel/Post/Bank. `WW.Haendler.*` |
| `Module\Dungeon.lua` | Dungeon-Karte, Dungeon-Quests, `WW:DungeonKarteUmschalten()` |
| `Module\Sammeln.lua` | Kräuter/Erz/Kürschnern/Angelorte auf Welt- und Minikarte (Angeln: Schwärme und "Open water" = Forever-Angelplätze, Farbe nach `zones[m].fish`: grün ab Gebietsstufe, gelb bis 50 darunter, rot; keine eigenen Fundorte); Rundweg durch Kräuter/Erz auf der Weltkarte (`WW.SammelRoute`, Haken "Rundweg") |
| `Module\Inventar.lua` | Taschen/Bank/Ausrüstung aller Charaktere in `WW.db.inventar`, Reiter "Inventar" |
| `Module\Quests.lua` | Quest-Belohnungen für die eigene Klasse (Upgrade, selten, "Gut für"), Reiter "Quests" |
| `Module\Urteil.lua` | "Behalten oder Müll?" mit Grund: gemerkt (Alt+Rechtsklick, `WW.db.urteil.merken`), Quest (Log, Startitem, Quest in Stufe ± 5), Beruf (Zutat für Rezept, das noch Punkte gibt; Rezept-Item nicht gelernt), Müll (gebunden + Klasse kann es nie tragen; bekanntes Rezept). Gelernte Rezepte aus dem Berufsfenster in `WW.charDb.rezepte`. Tooltip-Zeile, Zeichen Q/B/+ am Taschenplatz, Unterreiter "Behalten" in den Einstellungen (nur Schalter); die Liste mit Grund steht im Inventar (`es.spalten = "behalten"`, `U.Einordnen`). Händler-Knopf und AH-Rand fragen `WW.Urteil.Pruefen` |
| `Module\Entzaubern.lua` | Classic-Entzauber-Tabelle (Stufe, Qualität, Waffe/Rüstung), Erwartungswert aus AH-Preisen der Materialien, nötige Verzauberkunst. `WW.Entzaubern.*`; Urteil "Entzaubern" nur mit genug Verzauberkunst und Preisen |
| `Module\Twinks.lua` | Twinks (gleicher Realm, gleiche Fraktion): Berufe/Rezepte je Charakter in `WW.db.inventar[Realm][Name].berufe/.rezepte`, `twinkAus`; Urteil "für Twinks"; Knopf am Briefkasten hängt Items an (Senden klickt Dan), `/ww twink Name` |
| `Module\Muell.lua` | Knopf an der Tasche: löscht das billigste Müll-Item (grau oder Urteil "Müll", nie blau+, nie geschützt); Taschenwert (Müll beim Händler, AH lohnt) |
| `Module\Fluege.lua` | Flugmeister auf der Weltkarte (auch unentdeckt), Flugzeit im Tooltip, Timer im Flug, Reiter "Flüge" |
| `Module\Schiffe.lua` | Fahrplan-Timer für Schiffe und Zeppeline (Eichung am Steg, `WW.db.fahrplan`) |
| `Module\Angeln.lua` | Angel-Modus: beim Angeln Effekte laut, Musik/Umgebung aus, automatisch plündern; Werte in `WW.db.angeln.gesichert`, danach zurück; Warnton bei Wurf ohne Fang; Angel-Taste (Bindung `CLICK WegweiserAngelKnopf:LeftButton`, sicherer Knopf wirft aus; während des Wurfs per `SetOverrideBinding` = `INTERACTTARGET` mit `SoftTargetInteract` 3, nur außerhalb des Kampfs); `WW.Angeln.*` |
| `Module\Einstellungen.lua` | Hauptreiter "Einstellungen" ist nur ein Behälter. Unterreiter: Allgemein (Datenstand, Neu laden, Quellen, Anzeige, Händler, Angeln), Tooltip, Behalten (Urteil.lua), Sammeln (Sammeln.lua), Flüge (Fluege.lua) |

Gespeicherte Daten (lesbar nach Logout oder /reload):
`A:\Games\Battle.net\World of Warcraft\_forever_\WTF\Account\<KONTO>\SavedVariables\Wegweiser.lua` (`<KONTO>` = der einzige Ordner in `WTF\Account` außer `SavedVariables`)

## Daten (Namensräume)
- `WW.quelle.fdb` – ForeverDB: `items`, `professions`, `recipes`, `names`, `recipeInfo`,
  `searchItemNames` (englisch), `gatherData`, `qcQuests`, `qcNpc`, `qcObj`, `qcItem`, `meta`
- `WW.quelle.helper` – ForeverDB_Helper: `dungeons`, `dataMeta`
- `WW.quelle.fdm` – ForeverDungeonMap: `data` (Dungeon-Quests), `dungeons`, `curated`,
  `curatedDungeons`, `guideMapData` (Karten), `classicItems`, `genericDrops`
- `WW.quelle.gc` – Gathercraft: `nodeNames.deDE[objektID]`
- `WW.quelle.ziele[Instanz][Quest]` – Questziele im Dungeon, `WW.quelle.zielNamen` (siehe "Questziele im Dungeon")
- `WW.datenStand` – Stand der Kopie
- Karten-Bilder: `Interface\AddOns\Wegweiser\Daten\Karten\<file>`

## Updates für andere Spieler (GitHub)
- `.github/workflows/release.yml` läuft jede Nacht, bei Änderung an `Wegweiser.toc` und von Hand.
- Ablauf: `Werkzeuge/Quellen-holen.ps1` (ForeverDB-Zip von foreverdb.net/downloads, Gathercraft vom
  GitHub-Release, ForeverDungeonMap aus `Quellen/ForeverDungeonMap`) → `Daten-aktualisieren.ps1 -AddOns … -Streng`
  → Tests → `Werkzeuge/Release-vorbereiten.ps1` → Tag + BigWigs-Packager (GitHub-Release, CurseForge/Wago mit Secrets).
- Release-Regel: Version in der .toc ohne Tag → `vX.Y.Z`; sonst neue Daten → `vX.Y.Z-JJJJMMTThhmm`.
  Fingerabdruck der Daten in `Werkzeuge/daten-stand.txt` (schreibt nur der Roboter).
- `Daten/` bleibt in `.gitignore`; der Roboter merkt es mit `git add -f` nur für den Packager vor.
- Pfade in den PowerShell-Skripten mit `/`, sie laufen auch auf Linux (PowerShell 7).
- Tests dürfen keine festen Datenwerte erwarten (Dropchancen ändern sich mit jedem ForeverDB-Update),
  sonst bleibt jedes nächtliche Release hängen.
- `Quellen/ForeverDungeonMap` von Hand erneuern, siehe `Quellen/LIESMICH.md`.

## Questziele im Dungeon
- `Ziele\Dungeon.lua` (in Git, nicht in `Daten\`) erzeugt `Werkzeuge\Dungeon-Ziele.py` aus dem cMaNGOS-Dump
  (`ClassicDB_1_12_1_*.sql.gz` von https://github.com/cmangos/classic-db, Ordner `Full_DB`, GPL-3.0):
  `python -I Werkzeuge/Dungeon-Ziele.py <Pfad zum .sql.gz>`. Den Dump nicht ins Addon legen.
- Umrechnung Welt -> Kartenbild: affiner Fit an die Boss-Orte aus `FDM_Karten.lua` (mind. 3 Bosse mit genau einem Spawn).
  Ohne Boss-Orte (Burg Schattenfang, Todesminen, Scharlachrotes Kloster, Zul'Farrak) gibt es keine Ziele.
- Nur Quests, die im Reiter "Dungeons" zum Dungeon gehören (`instance = N` in FDM-Daten). Bosse bekommen keine Ziel-Punkte.
