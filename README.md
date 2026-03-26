# 📊 Data Analytics Showcase: BIDLI Holding Reporting

> **Autor:** [Rudolf Munzig] · Junior Controller / Reporting Analyst  
> **Stack:** MS SQL Server · Power Query · Power Pivot · Excel · GitHub

---

## O projektu

Tento repozitář je simulací reálného Business Intelligence řešení navrženého pro holdingovou skupinu s pěti divizemi (Reality, Energie, Development, Technologie, Finance). Projekt demonstruje kompletní datovou pipeline — od modelování SQL databáze přes ETL transformace v Power Query až po interaktivní finanční dashboard.

Cílem není jen „ukázat práci s Excelem" — cílem je ukázat, že rozumím tomu, **jaká data holdingová firma potřebuje, kde vznikají a jak je efektivně zpracovat**. Součástí modelu je věrohodná simulace intercompany fakturace, zakázkové marže i nákladové struktury divize FVE.

Architektura je připravena na integraci s ostrými daty systému POHODA díky mapování na standardní SQL strukturu účetního deníku.

---

## 🛠 Technologický stack

| Technologie | Využití v projektu |
|---|---|
| ![SQL](https://img.shields.io/badge/MS%20SQL%20Server-CC2927?style=flat&logo=microsoftsqlserver&logoColor=white) | Datový model, Views, finanční logika |
| ![PowerQuery](https://img.shields.io/badge/Power%20Query-217346?style=flat&logo=microsoftexcel&logoColor=white) | ETL pipeline, M-Language transformace |
| ![PowerPivot](https://img.shields.io/badge/Power%20Pivot-185ABD?style=flat&logo=microsoftexcel&logoColor=white) | Relační model, DAX míry |
| ![Excel](https://img.shields.io/badge/Excel-217346?style=flat&logo=microsoftexcel&logoColor=white) | Interaktivní dashboard, slicery |
| ![GitHub](https://img.shields.io/badge/GitHub-181717?style=flat&logo=github&logoColor=white) | Verzování, dokumentace, showcase |

---

## 🏗 Architektura řešení

```
┌─────────────────────┐     SQL Views      ┌──────────────────────┐
│   MS SQL Server     │ ─────────────────► │   Power Query (ETL)  │
│                     │                    │                      │
│  dim_spolecnosti    │   v_pl_statement   │  Transformace typů   │
│  dim_strediska      │   v_marze_projektu │  RAG status (R/A/G)  │
│  dim_zakazky        │   v_nakladovost_.. │  Null handling       │
│  fct_uctovani       │                    │  Query Folding ✓     │
└─────────────────────┘                    └──────────┬───────────┘
         ▲                                            │
         │                                            ▼
   Pohoda ERP                              ┌──────────────────────┐
   (integrace                              │  Power Pivot Model   │
    připravena)                            │                      │
                                           │  Relace tabulek      │
                                           │  DAX míry            │
                                           └──────────┬───────────┘
                                                      │
                                                      ▼
                                           ┌──────────────────────┐
                                           │  Excel Dashboard     │
                                           │                      │
                                           │  P&L per divize      │
                                           │  Marže projektů      │
                                           │  KPI Energie / FVE   │
                                           │  Interaktivní slicery│
                                           └──────────────────────┘
```

**Datový model** je postaven na hvězdicovém schématu (Star Schema) — průmyslovém standardu pro analytické BI systémy, nativně podporovaném v Power BI i Power Pivot.

---

## 💼 Business přínos pro BIDLI holding

### ⚡ Automatizace reportingu
Měsíční P&L report pro CFO holdingu vznikne jedním kliknutím na **Aktualizovat vše** — žádné manuální kopírování z Pohody, žádné riziko překlepu. Data se načítají přímo ze SQL Serveru.

### 📈 Sledování marží u FVE a developerských projektů
- **Divize Energie:** pohled `v_nakladovost_energie` sleduje podíl materiálu (FV panely) a subdodávek na celkových nákladech — klíčové pro řízení v době volatility cen komponentů.
- **Developerské projekty:** pohled `v_marze_projektu` porovnává plánovanou marži s aktuální skutečností průběžně — ne až po dokončení projektu.

### 🔗 Připravenost na systém POHODA
Tabulka `fct_uctovani` mapuje na standardní strukturu účetních dokladů SQL verze Pohody (VydFaktura, PrijFaktura, UcetniZapis). Přechod z demo dat na ostrou databázi = úprava connection stringu a ověření konzistence čísel.

### 🏢 Intercompany transparentnost
Flag `je_intercompany` umožňuje zobrazit holding jako konsolidovaný celek (IC pohyby vyloučeny) nebo jako skupinu autonomních entit — v jednom datovém modelu, bez duplikace reportů.

---

## 📁 Soubory v repozitáři

```
📦 bidli-reporting-showcase
 ├── 📄 BIDLI_01_ModelovaData.sql      # SQL skript: tvorba tabulek, demo data, 3 Views
 ├── 📄 BIDLI_02_PowerQuery.pq         # M-Language kód pro Power Query (Excel / Power BI)
 ├── 📄 BIDLI_Metodika_Interna.pdf    # Interní metodika: datový model, logika Views, návod
 └── 📄 README.md                      # Tento soubor
```

| Soubor | Co obsahuje | Pro koho |
|---|---|---|
| `BIDLI_01_ModelovaData.sql` | Kompletní SQL skript pro MS SQL Server: 4 tabulky, 28 věrohodných transakcí (Reality, FVE, Development), 3 analytické Views s komentáři ke každému řádku | SQL developer, DBA, IT |
| `BIDLI_02_PowerQuery.pq` | M-Language kód pro 4 Power Query dotazy včetně ukázky přímého připojení na Pohoda ERP | BI developer, Analyst |
| `BIDLI_Metodika_Interna.pdf` | 6-sekční metodická dokumentace: datový model, business logika Views, integrační postup, návod pro uživatele | Controller, CFO, HR |

---

## 🚀 Jak spustit

```sql
-- 1. Spusť v SQL Server Management Studio (SSMS) nebo Azure Data Studio
USE master;
-- Spusť celý soubor BIDLI_01_ModelovaData.sql
-- Vytvoří databázi BIDLI_Showcase, naplní ji daty a Views

-- 2. Ověř výsledky
USE BIDLI_Showcase;
SELECT * FROM dbo.v_pl_statement;
SELECT * FROM dbo.v_marze_projektu;
SELECT * FROM dbo.v_nakladovost_energie;
```

```
3. Excel: Data → Získat data → Ze serveru SQL Server
   Server: localhost  |  Databáze: BIDLI_Showcase
   Vyber Views → Načíst do datového modelu Power Pivot
```

---

## 📬 Kontakt

Projekt byl vytvořen jako součást přihlášky na pozici **Junior Controller / Reporting Analyst** ve společnosti **BIDLI holding**.

> *„Dobrý controller nejen reportuje čísla — rozumí tomu, odkud přišla a co znamenají."*

---

<p align="center">
  <sub>Vytvořeno s využitím MS SQL Server · Power Query · AI-asistovaného vývoje (Claude by Anthropic)</sub>
</p>
