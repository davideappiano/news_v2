"""Build a detailed XLSX summary of the BTE use-case status slide.
Each row is a single 'Done' item or 'Prochaine étape' item, so progress
and pending work are itemized rather than crammed into one cell."""
import zipfile
from xml.sax.saxutils import escape

# (UC, Description, Catégorie, Niveau de maturité, Sponsor BTE, Type, Détail)
ROWS = []

def add(uc, desc, cat, mat, sponsor, items_done, items_next):
    for d in items_done:
        ROWS.append((uc, desc, cat, mat, sponsor, "Done", d))
    for n in items_next:
        ROWS.append((uc, desc, cat, mat, sponsor, "Prochaine étape", n))

add(
    "UC1",
    "Compte-rendu de réunion (Seedext) + actions sur opportunités (AgentForce)",
    "Employee Agent",
    "Mature - S2",
    "Jonathan BOUDET (Dir Commercial Business)",
    [
        "Deck synthèse partagé le 20 avril",
        "Transition FDE → ByTel : réunion de passation de pouvoir (analyse approfondie de la mise en œuvre technique d'UC1 prévue le 12 mai)",
        "Vérifier que le JSON envoyé par Seedex soit de moins de 6 Mo",
        "Solution B : envoyer le transcript brut pour génération du plan d'action côté Salesforce - à étudier",
    ],
    [
        "MEP prévue en juillet",
        "À FAIRE : migrer sur la sandbox d'intégration (CI/CD)",
        "PS en cours d'assignation : await",
        "Blocage intégration Seedex / Salesforce - À CONFIRMER CÔTÉ BOUYGUES / SEEDEX",
    ],
)

add(
    "UC2",
    "Sales News Hebdo (Revue d'actualités du portefeuille)",
    "Prompt Template / Agent en Back-office",
    "En incubation",
    "Jonathan BOUDET (Dir Commercial Business)",
    [
        "Corrections apportées au modèle de métadonnées ByTel",
        "Partage des résultats Perplexity par Jonathan",
    ],
    [
        "V2 en cours (démo cette semaine - jeudi ?)",
        "Ré-activer la partie « interne »",
    ],
)

add(
    "UC3",
    "Qualification / Scoring des leads entrants",
    "SDR Agent",
    "Mature - S2",
    "Peter NTendayi M. (Dir BU PME)",
    [
        "Le Testing Center fonctionne avec succès (Arthur, 29 avril) ; résultats des tests volumétriques en attente",
        "Bugs connus documentés : ID à 15 chiffres, colonne $Context.ContactId",
        "Contournement de la limite des 5 triggers trouvé par Arthur Imirzian : trigger configurable via CMT + nouveau champ « Assign To SDR Agent » sur Lead",
    ],
    [
        "Analyse approfondie et examen de la documentation effectués le 27 mai",
        "Séance de Q&R de suivi avec l'équipe informatique de BTE prévue si nécessaire",
        "Documentation de transfert mise à disposition sur Confluence",
        "Étudier la possibilité de recruter un agent chargé de la relation client en vue d'un remplacement à long terme de l'actuel agent SDR",
        "Problème lié à l'EAC et aux alias de messagerie - dossier transmis à un niveau supérieur : en cours",
    ],
)

add(
    "UC4",
    "Synthèse des échanges Iso GP (intégration Genesis Cloud)",
    "",
    "Restarted",
    "Vincent Dubois (Dir. Opérations Clients)",
    [],
    [
        "Connexion Sandbox Genesys",
        "À voir entre Vincent Dubois et Guillaume",
    ],
)

add(
    "UC5",
    "Base de Connaissance IA (Newbiz)",
    "",
    "Stand-by",
    "Vincent De Bruyne / Thibaut Keraval / Christine Martins / Christophe Lenoir / Damien Ligot",
    [],
    [
        "Stand-by",
        "Vérifier avancement vs. ProServ (Olivier BECHA)",
    ],
)

add(
    "UC6",
    "Actions sur contrats stockés dans Salesforce",
    "",
    "Stand-by",
    "Jonathan BOUDET (Dir Commercial - Business)",
    [
        "Pas de Salesforce",
    ],
    [
        "Stand-by",
        "Qualification : pertinence du UC IA vs. chantier Data Quality",
        "STOP !",
    ],
)

add(
    "UC7",
    "Cas d'usage Pardot",
    "",
    "New",
    "",
    [
        "Voir comment mettre l'IA dans Pardot",
    ],
    [
        "Atelier avec expert Pardot chez SF + Bouygues (Caroline)",
    ],
)

HEADERS = ["UC", "Description", "Catégorie", "Niveau de maturité",
           "Sponsor BTE", "Type", "Détail"]

# --- minimal XLSX writer (OOXML) ---
def col_letter(n):  # 1-based
    s = ""
    while n:
        n, r = divmod(n - 1, 26)
        s = chr(65 + r) + s
    return s

def cell_xml(col_idx, row_idx, value):
    ref = f"{col_letter(col_idx)}{row_idx}"
    return f'<c r="{ref}" t="inlineStr"><is><t xml:space="preserve">{escape(str(value))}</t></is></c>'

def build_sheet():
    rows_xml = []
    # header
    rows_xml.append(
        "<row r=\"1\">" + "".join(cell_xml(i + 1, 1, h) for i, h in enumerate(HEADERS)) + "</row>"
    )
    for ri, row in enumerate(ROWS, start=2):
        rows_xml.append(
            f"<row r=\"{ri}\">" + "".join(cell_xml(i + 1, ri, v) for i, v in enumerate(row)) + "</row>"
        )
    cols = (
        "<cols>"
        "<col min=\"1\" max=\"1\" width=\"6\" customWidth=\"1\"/>"
        "<col min=\"2\" max=\"2\" width=\"55\" customWidth=\"1\"/>"
        "<col min=\"3\" max=\"3\" width=\"22\" customWidth=\"1\"/>"
        "<col min=\"4\" max=\"4\" width=\"18\" customWidth=\"1\"/>"
        "<col min=\"5\" max=\"5\" width=\"40\" customWidth=\"1\"/>"
        "<col min=\"6\" max=\"6\" width=\"18\" customWidth=\"1\"/>"
        "<col min=\"7\" max=\"7\" width=\"90\" customWidth=\"1\"/>"
        "</cols>"
    )
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        + cols
        + "<sheetData>" + "".join(rows_xml) + "</sheetData>"
        + "</worksheet>"
    )

WORKBOOK = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
    '<sheets><sheet name="Use Cases BTE" sheetId="1" r:id="rId1"/></sheets>'
    '</workbook>'
)
WB_RELS = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
    'Target="worksheets/sheet1.xml"/>'
    '</Relationships>'
)
ROOT_RELS = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
    'Target="xl/workbook.xml"/>'
    '</Relationships>'
)
CONTENT_TYPES = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/xl/workbook.xml" '
    'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    '<Override PartName="/xl/worksheets/sheet1.xml" '
    'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
    '</Types>'
)

OUT = "BTE_UseCases_Status.xlsx"
with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("[Content_Types].xml", CONTENT_TYPES)
    z.writestr("_rels/.rels", ROOT_RELS)
    z.writestr("xl/workbook.xml", WORKBOOK)
    z.writestr("xl/_rels/workbook.xml.rels", WB_RELS)
    z.writestr("xl/worksheets/sheet1.xml", build_sheet())

print(f"Wrote {OUT} with {len(ROWS)} detail rows")
