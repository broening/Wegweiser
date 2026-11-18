"""Erzeugt Ziele/Dungeon.lua: Questziele im Dungeon als Punkte auf den Kartenbildern.

Aufruf (im Ordner Wegweiser):
    python -I Werkzeuge/Dungeon-Ziele.py <Pfad zu ClassicDB_1_12_1_*.sql.gz>

Quelle der Orte: cMaNGOS classic-db (https://github.com/cmangos/classic-db, GPL-3.0), Tabellen creature,
creature_spawn_entry und gameobject. Questziele: Daten/FDB_Quests.lua (ForeverDB, ebenfalls aus cMaNGOS).
Kartenbilder und Boss-Orte: Daten/FDM_Karten.lua.

Umrechnung: Pro Karte eine affine Abbildung Welt (x, y) -> Bild (u, v), angepasst an die Bosse, die auf dem
Bild einen Ort haben und genau einmal im Dungeon stehen (mindestens 3). Karten ohne guten Fit fehlen.

Ausgabe: WW.quelle.ziele[Instanz][Quest] = { "<art><id>[><item>]:<punkte>", ... }
    art: n = Kreatur, o = Objekt; item: das Quest-Item, das sie fallen lassen (fehlt bei Töte-Zielen)
    punkte: je 4 Zeichen Basis 36, u (2) dann v (2), in Tausendstel des Bildes (0..1000)
"""
import gzip, json, os, re, sys

MAX_FIT_FEHLER = 0.01      # größte erlaubte Abweichung eines Bosses (Anteil des Bildes)
MIN_DROP = 5               # Drop-Quellen unter 5 % zählen nicht (außer es gibt keine anderen)
RASTER = 0.02              # Punkte näher als 2 % des Bildes werden zusammengefasst
MAX_PUNKTE = 40            # höchstens so viele Punkte pro Ziel

wurzel = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
dump = sys.argv[1]


def lies(pfad):
    return open(os.path.join(wurzel, pfad), encoding='utf-8').read()


# --- Spawns aus dem Dump -------------------------------------------------------------------------
TUPEL = re.compile(r"\(((?:[^()'\\]|'(?:[^'\\]|\\.)*')*)\)")
FELD = re.compile(r"'(?:[^'\\]|\\.)*'|[^,]+")


def zeilen(rest):
    """Die Tupel eines INSERT ... VALUES als Listen von Feldern (Texte in Anführungszeichen dürfen Kommas enthalten)."""
    for m in TUPEL.finditer(rest):
        yield [t.strip().strip("'") for t in FELD.findall(m.group(1))]


def spawns_lesen(pfad):
    """Gibt spawns[map]['n'|'o'][id] = [(x, y), ...] und beute[item] = {('n', kreatur) | ('o', objekt)} zurück."""
    spawns, offen, eintrag = {}, {}, {}
    offenObj, eintragObj = {}, {}             # Objekte mit id 0 und ihre gameobject_spawn_entry
    lootVonKreatur, lootVonObjekt = {}, {}   # Loot-ID -> [Kreatur/Objekt]
    namen = {'n': {}, 'o': {}}
    kreaturLoot, objektLoot = {}, {}          # Loot-ID -> {Item}

    def dazu(mp, art, i, x, y):
        spawns.setdefault(mp, {'n': {}, 'o': {}})[art].setdefault(i, []).append((x, y))

    with gzip.open(pfad, 'rt', encoding='utf-8', errors='replace') as f:
        for z in f:
            if z.startswith('INSERT INTO `creature` VALUES'):
                for r in zeilen(z[29:]):
                    guid, cid, mp = int(r[0]), int(r[1]), int(r[2])
                    if mp in (0, 1):
                        continue
                    x, y = float(r[4]), float(r[5])
                    if cid == 0:
                        offen[guid] = (mp, x, y)
                    else:
                        dazu(mp, 'n', cid, x, y)
            elif z.startswith('INSERT INTO `gameobject` VALUES'):
                for r in zeilen(z[31:]):
                    guid, oid, mp = int(r[0]), int(r[1]), int(r[2])
                    if mp in (0, 1):
                        continue
                    if oid == 0:   # Objekt steht in gameobject_spawn_entry
                        offenObj[guid] = (mp, float(r[4]), float(r[5]))
                    else:
                        dazu(mp, 'o', oid, float(r[4]), float(r[5]))
            elif z.startswith('INSERT INTO `creature_spawn_entry` VALUES'):
                for r in zeilen(z[41:]):
                    eintrag.setdefault(int(r[0]), []).append(int(r[1]))
            elif z.startswith('INSERT INTO `gameobject_spawn_entry` VALUES'):
                for r in zeilen(z[z.index('VALUES') + 6:]):
                    eintragObj.setdefault(int(r[0]), []).append(int(r[1]))
            elif z.startswith('INSERT INTO `creature_template` VALUES'):
                for r in zeilen(z[38:]):
                    namen['n'][int(r[0])] = r[1].replace("\\'", "'")
                    loot = int(float(r[56]))   # LootId
                    if loot:
                        lootVonKreatur.setdefault(loot, []).append(int(r[0]))
            elif z.startswith('INSERT INTO `gameobject_template` VALUES'):
                for r in zeilen(z[40:]):
                    namen['o'][int(r[0])] = r[3].replace("\\'", "'")
                    if r[1] == '3' and int(float(r[9])):   # Truhe: data1 = Loot-ID
                        lootVonObjekt.setdefault(int(float(r[9])), []).append(int(r[0]))
            elif z.startswith('INSERT INTO `creature_loot_template` VALUES') or \
                    z.startswith('INSERT INTO `gameobject_loot_template` VALUES'):
                ziel = kreaturLoot if z.startswith('INSERT INTO `creature') else objektLoot
                for r in zeilen(z[z.index('VALUES') + 6:]):
                    chance, ref = abs(float(r[2])), int(float(r[4]))
                    if ref >= 0 and chance >= 1:      # keine Verweise, mindestens 1 %
                        ziel.setdefault(int(r[0]), set()).add(int(r[1]))
    for guid, (mp, x, y) in offen.items():
        for cid in eintrag.get(guid, []):
            dazu(mp, 'n', cid, x, y)
    for guid, (mp, x, y) in offenObj.items():
        for oid in eintragObj.get(guid, []):
            dazu(mp, 'o', oid, x, y)
    beute = {}
    for loot, items in kreaturLoot.items():
        for cid in lootVonKreatur.get(loot, []):
            for i in items:
                beute.setdefault(i, set()).add(('n', cid))
    for loot, items in objektLoot.items():
        for oid in lootVonObjekt.get(loot, []):
            for i in items:
                beute.setdefault(i, set()).add(('o', oid))
    return spawns, beute, namen


# --- Kartenbilder und Bosse ----------------------------------------------------------------------
def karten_lesen():
    s = lies('Daten/FDM_Karten.lua')
    karten = {}
    for m in re.finditer(r'\[(\d+)\] = \{ file = "(\w+)"[^\n]*(?:\n\s+bosses = \{([^\n]*)\})?', s):
        bosse = {}
        for bm in re.finditer(r'\[(\d+)\] = \{ ([\d.]+), ([\d.]+) \}', m.group(3) or ''):
            bosse[int(bm.group(1))] = (float(bm.group(2)), float(bm.group(3)))
        karten[int(m.group(1))] = bosse
    return karten


def loese3(A, b):
    M = [A[i][:] + [b[i]] for i in range(3)]
    for c in range(3):
        p = max(range(c, 3), key=lambda r: abs(M[r][c]))
        M[c], M[p] = M[p], M[c]
        if abs(M[c][c]) < 1e-12:
            return None
        for r in range(3):
            if r != c:
                f = M[r][c] / M[c][c]
                for k in range(c, 4):
                    M[r][k] -= f * M[c][k]
    return [M[i][3] / M[i][i] for i in range(3)]


def anpassen(paare):
    AtA = [[0.0] * 3 for _ in range(3)]
    Au, Av = [0.0] * 3, [0.0] * 3
    for (x, y), (u, v) in paare:
        r = (x, y, 1.0)
        for i in range(3):
            for j in range(3):
                AtA[i][j] += r[i] * r[j]
            Au[i] += r[i] * u
            Av[i] += r[i] * v
    pu, pv = loese3(AtA, Au), loese3(AtA, Av)
    if not pu or not pv:
        return None, None
    fehler = max(((pu[0] * x + pu[1] * y + pu[2] - u) ** 2 + (pv[0] * x + pv[1] * y + pv[2] - v) ** 2) ** 0.5
                 for (x, y), (u, v) in paare)
    return (pu, pv), fehler


# --- Questziele ----------------------------------------------------------------------------------
def block(s, name):
    a = s.index(name + ' = {')
    return s[a:s.index('\n}', a)]


def quests_lesen():
    s = lies('Daten/FDB_Quests.lua')
    quests = {int(m.group(1)): m.group(2) for m in re.finditer(r'\[(\d+)\]="((?:[^"\\]|\\.)*)"', block(s, 'ns.qcQuests'))}
    items = {int(m.group(1)): m.group(2) for m in re.finditer(r'\[(\d+)\]="((?:[^"\\]|\\.)*)"', block(s, 'ns.qcItem'))}
    return quests, items


def ziele_von(text, items, beute):
    """Liste von (art, id, item) für die Ziele einer Quest."""
    felder = text.split('|')
    if len(felder) < 12:
        return []
    raus = []
    for teil in felder[11].split(';'):
        m = re.match(r'([coi])(\d+):\d+(?::([\d,]+))?', teil)
        if not m:
            continue
        art, i = m.group(1), int(m.group(2))
        if art == 'c':
            raus.append(('n', i, None))
            for k in (m.group(3) or '').split(','):
                if k.isdigit():
                    raus.append(('n', int(k), None))
        elif art == 'o':
            raus.append(('o', i, None))
        else:
            quellen = re.findall(r'([no])(\d+):([\d.]+)', items.get(i, ''))
            gut = [q for q in quellen if float(q[2]) >= MIN_DROP] or quellen
            schon = set()
            for a, qid, _ in gut:
                schon.add((a, int(qid)))
                raus.append((a, int(qid), i))
            # dazu alle, die es laut Beute-Tabellen fallen lassen (ForeverDB nennt nur die 6 häufigsten Quellen)
            for a, qid in sorted(beute.get(i, ())):
                if (a, qid) not in schon:
                    raus.append((a, qid, i))
    return raus


def dungeon_quests():
    """{Instanz: {Quest}} wie im Reiter "Dungeons": Quests mit instance = N aus FDM_Quests und FDM_Korrekturen."""
    raus = {}
    for datei in ('Daten/FDM_Quests.lua', 'Daten/FDM_Korrekturen.lua'):
        for m in re.finditer(r'^\s*\[(\d+)\] = \{[^\n]*?\binstance = (\d+)', lies(datei), re.M):
            raus.setdefault(int(m.group(2)), set()).add(int(m.group(1)))
    return raus


B36 = '0123456789abcdefghijklmnopqrstuvwxyz'


def b36(n):
    return B36[n // 36] + B36[n % 36]


def punkte_kodieren(liste):
    belegt, raus = set(), []
    for u, v in liste:
        if not (0 <= u <= 1 and 0 <= v <= 1):
            continue
        feld = (int(u / RASTER), int(v / RASTER))
        if feld in belegt:
            continue
        belegt.add(feld)
        raus.append(b36(int(round(u * 1000))) + b36(int(round(v * 1000))))
        if len(raus) >= MAX_PUNKTE:
            break
    return ''.join(raus)


def main():
    spawns, beute, namen = spawns_lesen(dump)
    karten = karten_lesen()
    quests, items = quests_lesen()
    fits = {}
    for mp, bosse in sorted(karten.items()):
        sp = spawns.get(mp, {}).get('n', {})
        paare = [(sp[c][0], uv) for c, uv in bosse.items() if len(sp.get(c, [])) == 1]
        if len(paare) < 3:
            print(f'Karte {mp}: {len(paare)} Bosse mit Ort - ausgelassen')
            continue
        fit, fehler = anpassen(paare)
        if not fit or fehler > MAX_FIT_FEHLER:
            print(f'Karte {mp}: Fit zu ungenau ({fehler}) - ausgelassen')
            continue
        fits[mp] = fit
        print(f'Karte {mp}: {len(paare)} Bosse, größte Abweichung {fehler * 100:.2f} %')

    zuDungeon = dungeon_quests()
    ziele = {}
    for qid in sorted(quests):
        for art, i, item in ziele_von(quests[qid], items, beute):
            for mp, (pu, pv) in fits.items():
                if qid not in zuDungeon.get(mp, ()):
                    continue   # gehört nicht zu diesem Dungeon
                if art == 'n' and i in karten[mp]:
                    continue   # Boss: hat schon eine Nadel
                orte = spawns.get(mp, {}).get(art, {}).get(i)
                if not orte:
                    continue
                uv = [(pu[0] * x + pu[1] * y + pu[2], pv[0] * x + pv[1] * y + pv[2]) for x, y in orte]
                p = punkte_kodieren(uv)
                if p:
                    key = f'{art}{i}' + (f'>{item}' if item else '')
                    eintraege = ziele.setdefault(mp, {}).setdefault(qid, [])
                    if not any(e.startswith(key + ':') for e in eintraege):
                        eintraege.append(f'{key}:{p}')

    zeilen = [
        '-- Erzeugt von Werkzeuge/Dungeon-Ziele.py. Nicht von Hand ändern.',
        '-- Orte: cMaNGOS classic-db (https://github.com/cmangos/classic-db), GPL-3.0. Questziele: ForeverDB.net (GPL-3.0).',
        '-- WW.quelle.ziele[Instanz][Quest] = { "<n|o><id>[><item>]:<punkte>" }, Punkte je 4 Zeichen Basis 36 (u, v in 1/1000).',
        'local ADDON, WW = ...',
        'WW.quelle = WW.quelle or {}',
        'WW.quelle.ziele = {',
    ]
    gesamt = 0
    for mp in sorted(ziele):
        zeilen.append(f'[{mp}] = {{')
        for qid in sorted(ziele[mp]):
            gesamt += 1
            zeilen.append(f'  [{qid}] = {{ ' + ', '.join(json.dumps(e) for e in ziele[mp][qid]) + ' },')
        zeilen.append('},')
    zeilen.append('}')
    # englische Namen der Ziele (Ersatz, wenn das Spiel und ForeverDB keinen Namen liefern)
    benutzt = {'n': set(), 'o': set()}
    for mp in ziele.values():
        for liste in mp.values():
            for e in liste:
                m = re.match(r'([no])(\d+)', e)
                benutzt[m.group(1)].add(int(m.group(2)))
    zeilen.append('WW.quelle.zielNamen = {')
    for art in ('n', 'o'):
        teile = [f'[{i}]={json.dumps(namen[art].get(i, ""), ensure_ascii=False)}' for i in sorted(benutzt[art]) if namen[art].get(i)]
        zeilen.append(f'  {art} = {{ ' + ', '.join(teile) + ' },')
    zeilen.append('}')
    os.makedirs(os.path.join(wurzel, 'Ziele'), exist_ok=True)
    with open(os.path.join(wurzel, 'Ziele', 'Dungeon.lua'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(zeilen) + '\n')
    print(f'{len(ziele)} Dungeons, {gesamt} Quests mit Zielen -> Ziele/Dungeon.lua')


main()
