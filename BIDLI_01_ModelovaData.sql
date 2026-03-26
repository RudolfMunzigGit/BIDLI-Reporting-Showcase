-- ============================================================
--  BIDLI HOLDING — SHOWCASE PROJEKT
--  Soubor: BIDLI_01_ModelovaData.sql
--  Autor:  Junior Controller / Reporting Analyst (showcase)
--  DB:     Microsoft SQL Server 2019+
--  Verze:  1.0  |  2024
-- ============================================================
--
--  CO TENTO SKRIPT DĚLÁ?
--  ---------------------
--  Vytvoří a naplní datový model pro holding BIDLI se čtyřmi
--  tabulkami (3 dimenzionální + 1 faktová) a třemi SQL Views,
--  které počítají finanční KPI pro management.
--
--  DATOVÝ MODEL (hvězdicové schéma / Star Schema):
--
--    dim_spolecnosti     ← kdo je „plátce" nebo „příjemce" faktury
--    dim_strediska       ← firemní divize a projekty
--    dim_zakazky         ← konkrétní zakázky/projekty
--          ↓ JOIN klíče ↓
--    fct_uctovani        ← všechny účetní pohyby (fakty)
--          ↓ Views ↓
--    v_pl_statement      ← Income Statement (P&L)
--    v_marze_projektu    ← Marže na zakázku
--    v_nakladovost_energie ← KPI pro divizi Energie (FVE)
--
--  PROČ HVĚZDICOVÉ SCHÉMA?
--  Protože dimenze (střediska, zakázky) jsou stabilní číselníky
--  a fct_uctovani je velká tabulka s transakcemi. Tento design
--  je záměrně kompatibilní se strukturou systému Pohoda ERP.
-- ============================================================


-- ============================================================
-- SEKCE 0: PŘÍPRAVA PROSTŘEDÍ
-- ============================================================

-- Pokud databáze neexistuje, vytvoříme ji
-- V reálném prostředí BIDLI by toto bylo "Pohoda_BIDLI" nebo
-- název existující Pohoda databáze
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'BIDLI_Showcase')
BEGIN
    CREATE DATABASE BIDLI_Showcase;
    PRINT 'Databáze BIDLI_Showcase vytvořena.';
END
GO

USE BIDLI_Showcase;
GO

-- Nastavíme CZ locale pro správné zobrazení dat
-- (v reportech pak čísla s desetinnou čárkou)
SET LANGUAGE Czech;
GO


-- ============================================================
-- SEKCE 1: DIMENZIONÁLNÍ TABULKY (DIM = číselníky)
-- ============================================================
-- PROČ DIMENZE?
-- Dimenzionální tabulky jsou "slovníky" – obsahují popisné
-- informace (kdo, co, kde). Jsou malé, mění se zřídka.
-- Bez nich by fct_uctovani obsahovala jen číselné kódy,
-- kterým by nikdo nerozuměl.
-- ============================================================


-- ------------------------------------------------------------
-- DIM 1: dim_spolecnosti
-- Všechny právní entity v holdingu BIDLI
-- Potřebujeme ji pro modelování INTERCOMPANY transakcí –
-- tj. fakturace mezi dceřinými společnostmi navzájem.
-- ------------------------------------------------------------
IF OBJECT_ID('dbo.dim_spolecnosti', 'U') IS NOT NULL
    DROP TABLE dbo.dim_spolecnosti;
GO

CREATE TABLE dbo.dim_spolecnosti (
    spolecnost_id       INT             NOT NULL,   -- PK: primární klíč
    ic                  VARCHAR(10)     NOT NULL,   -- IČO (8 číslic pro CZ)
    nazev               NVARCHAR(100)   NOT NULL,   -- Obchodní název
    zkratka             VARCHAR(10)     NOT NULL,   -- Zkratka pro reporty
    divize              NVARCHAR(50)    NOT NULL,   -- Finance/Reality/Energie/Development/Tech
    je_holding          BIT             NOT NULL,   -- 1 = mateřská, 0 = dcera
    aktivni             BIT             NOT NULL    -- 1 = stále aktivní
    CONSTRAINT PK_dim_spolecnosti PRIMARY KEY (spolecnost_id)
);
GO

-- Naplnění: 5 entit – každá divize BIDLI má vlastní s.r.o.
-- Tato struktura je typická pro CZ holdingovou skupinu
INSERT INTO dbo.dim_spolecnosti VALUES
-- id   IČO          Název                               Zkratka   Divize         Holding  Aktivní
(1,  '12345678', 'BIDLI holding a.s.',                  'BH',     'Holding',      1,       1),
(2,  '23456789', 'BIDLI Reality s.r.o.',                'BR',     'Reality',      0,       1),
(3,  '34567890', 'BIDLI Energie s.r.o.',                'BE',     'Energie',      0,       1),
(4,  '45678901', 'BIDLI Development s.r.o.',            'BD',     'Development',  0,       1),
(5,  '56789012', 'BIDLI Technologies s.r.o.',           'BT',     'Technologie',  0,       1);
GO


-- ------------------------------------------------------------
-- DIM 2: dim_strediska
-- Nákladová a výnosová střediska v rámci holdingu
-- PROČ STŘEDISKA?
-- V systému Pohoda každá faktura nese kód střediska.
-- To umožňuje měřit ziskovost PER ODDĚLENÍ, ne jen celé firmy.
-- Např. prodejní tým vs. servisní tým vs. administrativa.
-- ------------------------------------------------------------
IF OBJECT_ID('dbo.dim_strediska', 'U') IS NOT NULL
    DROP TABLE dbo.dim_strediska;
GO

CREATE TABLE dbo.dim_strediska (
    stredisko_id        INT             NOT NULL,   -- PK
    stredisko_kod       VARCHAR(10)     NOT NULL,   -- Kód dle Pohoda (max 10 znaků)
    nazev               NVARCHAR(100)   NOT NULL,   -- Popis střediska
    spolecnost_id       INT             NOT NULL,   -- FK → dim_spolecnosti
    typ_strediska       VARCHAR(20)     NOT NULL,   -- 'Výnosové'/'Nákladové'/'Smíšené'
    rozpocet_rok        DECIMAL(15,2)   NULL        -- Roční rozpočet v Kč (NULL = nenastaveno)
    CONSTRAINT PK_dim_strediska PRIMARY KEY (stredisko_id),
    CONSTRAINT FK_strediska_spolecnosti FOREIGN KEY (spolecnost_id)
        REFERENCES dbo.dim_spolecnosti(spolecnost_id)
);
GO

INSERT INTO dbo.dim_strediska VALUES
-- id   Kód         Název                              SpolID  Typ           Rozpočet (Kč)
(10, 'BR-PROD',  'Prodej nemovitostí',                  2,    'Výnosové',    8000000.00),
(11, 'BR-PRON',  'Pronájmy portfolia',                  2,    'Výnosové',    3500000.00),
(12, 'BR-ADMIN', 'Administrativa Reality',              2,    'Nákladové',   1200000.00),
(20, 'BE-FVE',   'FVE instalace – projekty',            3,    'Smíšené',     5000000.00),
(21, 'BE-SERV',  'FVE servis a maintenance',            3,    'Výnosové',    1800000.00),
(22, 'BE-NAKUP', 'Nákup komponentů FVE',               3,    'Nákladové',   3200000.00),
(30, 'BD-PROJ',  'Developerské projekty',               4,    'Smíšené',    12000000.00),
(31, 'BD-STAV',  'Stavební náklady',                   4,    'Nákladové',   9000000.00),
(40, 'BT-DEV',   'Vývoj software',                     5,    'Smíšené',    2500000.00),
(41, 'BT-INFRA', 'IT infrastruktura',                  5,    'Nákladové',   800000.00),
(50, 'BH-MGMT',  'Holdingový management',              1,    'Nákladové',   2000000.00);
GO


-- ------------------------------------------------------------
-- DIM 3: dim_zakazky
-- Konkrétní obchodní případy / projekty
-- PROČ ZAKÁZKY?
-- Každá faktura v Pohoda může nést číslo zakázky.
-- Díky tomu víme: kolik stál projekt Vinohrady bytový dům
-- CELKEM – od první faktury za projekt až po poslední.
-- Bez zakázek bychom to museli počítat v Excelu ručně.
-- ------------------------------------------------------------
IF OBJECT_ID('dbo.dim_zakazky', 'U') IS NOT NULL
    DROP TABLE dbo.dim_zakazky;
GO

CREATE TABLE dbo.dim_zakazky (
    zakazka_id          INT             NOT NULL,   -- PK
    zakazka_kod         VARCHAR(20)     NOT NULL,   -- Interní kód zakázky
    nazev               NVARCHAR(150)   NOT NULL,   -- Popis zakázky
    stredisko_id        INT             NOT NULL,   -- FK → dim_strediska
    typ_zakazky         VARCHAR(30)     NOT NULL,   -- 'Prodej RK'/'FVE instalace' atd.
    datum_zahajeni      DATE            NOT NULL,
    datum_ukonceni      DATE            NULL,       -- NULL = zakázka stále běží
    rozpocet_nakladu    DECIMAL(15,2)   NULL,       -- Plánované náklady
    rozpocet_vynosu     DECIMAL(15,2)   NULL,       -- Plánované výnosy
    stav                VARCHAR(15)     NOT NULL    -- 'Aktivní'/'Dokončena'/'Pozastavena'
    CONSTRAINT PK_dim_zakazky PRIMARY KEY (zakazka_id),
    CONSTRAINT FK_zakazky_strediska FOREIGN KEY (stredisko_id)
        REFERENCES dbo.dim_strediska(stredisko_id)
);
GO

INSERT INTO dbo.dim_zakazky VALUES
-- Reality zakázky
(101, 'BR-2024-001', 'Prodej bytu – Vinohrady, Mánesova',    10, 'Prodej RK',
      '2024-01-15', '2024-06-30',  4200000.00,  5800000.00, 'Dokončena'),
(102, 'BR-2024-002', 'Prodej bytu – Žižkov, Seifertova',     10, 'Prodej RK',
      '2024-03-01', '2024-09-15',  3100000.00,  4200000.00, 'Dokončena'),
(103, 'BR-2024-003', 'Pronájem – kancelář Pankrác 420m²',   11, 'Pronájem',
      '2024-01-01',         NULL,    180000.00,   420000.00, 'Aktivní'),
-- Energie / FVE zakázky
(201, 'BE-2024-001', 'FVE instalace – firma Kovárna Žebrák', 20, 'FVE instalace',
      '2024-02-01', '2024-04-30',  850000.00,  1350000.00, 'Dokončena'),
(202, 'BE-2024-002', 'FVE instalace – RD Kladno 15kWp',      20, 'FVE instalace',
      '2024-05-15', '2024-07-31',  280000.00,   420000.00, 'Dokončena'),
(203, 'BE-2024-003', 'FVE servis – smlouva Kovárna 2024',    21, 'FVE servis',
      '2024-05-01',         NULL,   45000.00,    96000.00, 'Aktivní'),
-- Development zakázky
(301, 'BD-2024-001', 'Bytový dům Holešovice – 24 jednotek',  30, 'Residential Dev',
      '2023-09-01', '2025-06-30', 42000000.00, 58000000.00, 'Aktivní'),
(302, 'BD-2024-002', 'Komerční prostor Smíchov 800m²',       30, 'Commercial Dev',
      '2024-01-01', '2025-03-31', 18000000.00, 24500000.00, 'Aktivní'),
-- Technology zakázky (interní – pro ostatní divize)
(401, 'BT-2024-001', 'CRM systém pro BIDLI Reality',         40, 'Interní vývoj',
      '2024-03-01', '2024-12-31',  380000.00,   380000.00, 'Aktivní');  -- IC zakázka
GO


-- ============================================================
-- SEKCE 2: FAKTOVÁ TABULKA (FCT = transakce)
-- ============================================================
-- PROČ FAKTOVÁ TABULKA?
-- fct_uctovani = srdce celého datového modelu.
-- Každý řádek = jeden účetní doklad z Pohoda ERP.
-- Tato tabulka může mít statisíce řádků. Je navržena tak,
-- aby šla efektivně dotazovat pomocí GROUP BY a agregací.
--
-- VAZBA NA POHODA ERP:
-- V Pohoda databázi existují tabulky jako "Vydane_faktury",
-- "Platby", "Doklady". My je v praxi propojujeme přes JOIN
-- a tato tabulka simuluje výsledek takového propojení.
-- ============================================================

IF OBJECT_ID('dbo.fct_uctovani', 'U') IS NOT NULL
    DROP TABLE dbo.fct_uctovani;
GO

CREATE TABLE dbo.fct_uctovani (
    doklad_id           INT             NOT NULL,   -- PK: číslo dokladu
    datum_uctovani      DATE            NOT NULL,   -- Datum zápisu do účetnictví
    datum_splatnosti    DATE            NULL,       -- Datum splatnosti (pokud faktura)
    cislo_dokladu       VARCHAR(20)     NOT NULL,   -- Číslo faktury / dokladu
    typ_dokladu         VARCHAR(20)     NOT NULL,   -- 'VF'=vyd.faktura, 'PF'=přij.faktura, 'INT'=interní
    spolecnost_id       INT             NOT NULL,   -- FK: která naše firma doklad vystavila
    partner_ico         VARCHAR(15)     NULL,       -- IČO externího partnera (dodavatel/odběratel)
    partner_nazev       NVARCHAR(100)   NULL,       -- Název externího partnera
    zakazka_id          INT             NULL,       -- FK: na jakou zakázku (NULL = nezakázkové)
    stredisko_id        INT             NOT NULL,   -- FK: nákladové/výnosové středisko
    ucet_md             VARCHAR(10)     NOT NULL,   -- Účet MÁ DÁTI (dle Účetní osnovy CZ)
    ucet_dal            VARCHAR(10)     NOT NULL,   -- Účet DAL
    castka_bez_dph      DECIMAL(15,2)   NOT NULL,   -- Částka v Kč bez DPH
    sazba_dph           DECIMAL(5,2)    NOT NULL,   -- 0/12/21 (CZ sazby DPH)
    castka_dph          DECIMAL(15,2)   NOT NULL,   -- Vypočtená DPH
    typ_pohybu          VARCHAR(10)     NOT NULL,   -- 'Výnos'/'Náklad'/'Eliminace'
    je_intercompany     BIT             NOT NULL,   -- 1 = interní faktura v rámci holdingu
    popis               NVARCHAR(200)   NULL        -- Textový popis řádku
    CONSTRAINT PK_fct_uctovani PRIMARY KEY (doklad_id),
    CONSTRAINT FK_fct_spolecnosti FOREIGN KEY (spolecnost_id)
        REFERENCES dbo.dim_spolecnosti(spolecnost_id),
    CONSTRAINT FK_fct_zakazky FOREIGN KEY (zakazka_id)
        REFERENCES dbo.dim_zakazky(zakazka_id),
    CONSTRAINT FK_fct_strediska FOREIGN KEY (stredisko_id)
        REFERENCES dbo.dim_strediska(stredisko_id)
);
GO

-- -----------------------------------------------------------------------
-- NAPLNĚNÍ fct_uctovani – modelová data pro 2024
-- Logika účtování:
--   Výnosy: účty 6xx (tržby), záporné castka_bez_dph = snížení výnosu
--   Náklady: účty 5xx (spotřeba, mzdy, odpisy...)
--   DPH:     účet 343 (DPH)
--   Pohledávky: 311 (odběratelé), Závazky: 321 (dodavatelé)
-- -----------------------------------------------------------------------
INSERT INTO dbo.fct_uctovani VALUES

-- ==================================================================
-- REALITY: Prodej bytu Vinohrady (zakázka 101)
-- ==================================================================

-- 1. Výnos z prodeje bytu Vinohrady – rezervační záloha
(1001, '2024-02-01', '2024-02-15', 'VF-2024-0101', 'VF', 2,
 '98765432', 'Novák Jan',  101, 10,
 '311', '604',        -- 311 Pohledávky / 604 Tržby za zboží
 1000000.00, 0.00, 0.00,    -- Prodej pozemku = 0% DPH
 'Výnos', 0, 'Záloha na kupní cenu – byt Vinohrady, Mánesova 12'),

-- 2. Výnos z prodeje bytu Vinohrady – doplatek kupní ceny
(1002, '2024-06-15', '2024-06-30', 'VF-2024-0102', 'VF', 2,
 '98765432', 'Novák Jan', 101, 10,
 '311', '604',
 4800000.00, 0.00, 0.00,    -- Prodej RK osvobozeno od DPH
 'Výnos', 0, 'Doplatek kupní ceny – byt Vinohrady, Mánesova 12'),

-- 3. Provize zprostředkovateli (náklad na zakázku 101)
(1003, '2024-06-15', '2024-07-15', 'PF-2024-0501', 'PF', 2,
 '11122233', 'Reality Partner s.r.o.', 101, 10,
 '518', '321',         -- 518 Ostatní služby / 321 Závazky
 180000.00, 21.00, 37800.00,
 'Náklad', 0, 'Provize za zprostředkování prodeje Vinohrady'),

-- 4. Výnos z prodeje bytu Žižkov
(1004, '2024-09-10', '2024-09-25', 'VF-2024-0201', 'VF', 2,
 '87654321', 'Procházková Marie', 102, 10,
 '311', '604',
 4200000.00, 0.00, 0.00,
 'Výnos', 0, 'Kupní cena – byt Žižkov, Seifertova 45'),

-- 5. Náklady na přípravu dokumentace (Žižkov)
(1005, '2024-04-01', '2024-04-30', 'PF-2024-0502', 'PF', 2,
 '22233344', 'Advokátní kancelář Dvořák', 102, 10,
 '518', '321',
 45000.00, 21.00, 9450.00,
 'Náklad', 0, 'Právní služby – příprava KS Žižkov'),

-- 6. Pronájem kanceláří Pankrác – leden 2024
(1006, '2024-01-31', '2024-02-14', 'VF-2024-0301', 'VF', 2,
 '33344455', 'Consultancy Group a.s.', 103, 11,
 '311', '602',         -- 602 Tržby z prodeje služeb
 35000.00, 21.00, 7350.00,
 'Výnos', 0, 'Nájemné Pankrác leden 2024'),

-- 7. Pronájem kanceláří Pankrác – únor 2024
(1007, '2024-02-29', '2024-03-14', 'VF-2024-0302', 'VF', 2,
 '33344455', 'Consultancy Group a.s.', 103, 11,
 '311', '602',
 35000.00, 21.00, 7350.00,
 'Výnos', 0, 'Nájemné Pankrác únor 2024'),

-- 8. Správa nemovitosti – servisní náklad (Pankrác)
(1008, '2024-01-15', '2024-02-15', 'PF-2024-0503', 'PF', 2,
 '44455566', 'Správa budov Praha s.r.o.', 103, 11,
 '511', '321',         -- 511 Opravy a udržování
 8500.00, 21.00, 1785.00,
 'Náklad', 0, 'Správa budovy Pankrác – leden/únor 2024'),


-- ==================================================================
-- ENERGIE (FVE): Instalace Kovárna Žebrák (zakázka 201)
-- ==================================================================

-- 9. Faktura za instalaci FVE – Kovárna (výnos)
(2001, '2024-04-25', '2024-05-25', 'VF-2024-1001', 'VF', 3,
 '55566677', 'Kovárna Žebrák s.r.o.', 201, 20,
 '311', '602',
 1350000.00, 21.00, 283500.00,
 'Výnos', 0, 'FVE 80kWp + baterie – kompletní dodávka a instalace'),

-- 10. Nákup FV panelů (náklad – materiál)
(2002, '2024-02-10', '2024-03-10', 'PF-2024-1001', 'PF', 3,
 '66677788', 'SolarTech GmbH (DE)', 201, 22,
 '501', '321',         -- 501 Spotřeba materiálu
 520000.00, 0.00, 0.00,   -- Reverse charge (EU dodavatel)
 'Náklad', 0, 'FV panely LONGi 400W × 200ks – nákup DE dodavatel'),

-- 11. Nákup střídačů a baterií (náklad – materiál)
(2003, '2024-02-20', '2024-03-20', 'PF-2024-1002', 'PF', 3,
 '66677789', 'Fronius International GmbH', 201, 22,
 '501', '321',
 180000.00, 0.00, 0.00,   -- Reverse charge
 'Náklad', 0, 'Střídač Fronius Symo 30kW + baterie BYD 30kWh'),

-- 12. Subdodávka elektroinstalace (náklad – služby)
(2004, '2024-03-15', '2024-04-15', 'PF-2024-1003', 'PF', 3,
 '77788899', 'Elektro Novotný s.r.o.', 201, 20,
 '518', '321',
 85000.00, 21.00, 17850.00,
 'Náklad', 0, 'Elektroinstalace, kabeláž, jistící prvky – Kovárna'),

-- 13. FVE Instalace RD Kladno – výnos
(2005, '2024-07-25', '2024-08-25', 'VF-2024-1002', 'VF', 3,
 '88899900', 'Kratochvíl Pavel (OSVČ)', 202, 20,
 '311', '602',
 420000.00, 21.00, 88200.00,
 'Výnos', 0, 'FVE 15kWp – RD Kladno, kompletní realizace'),

-- 14. Nákup materiálu pro RD Kladno
(2006, '2024-05-20', '2024-06-20', 'PF-2024-1004', 'PF', 3,
 '66677788', 'SolarTech GmbH (DE)', 202, 22,
 '501', '321',
 195000.00, 0.00, 0.00,
 'Náklad', 0, 'FV panely + střídač – RD Kladno 15kWp'),

-- 15. FVE servisní smlouva – Kovárna (průběžné výnosy)
(2007, '2024-06-30', '2024-07-14', 'VF-2024-1003', 'VF', 3,
 '55566677', 'Kovárna Žebrák s.r.o.', 203, 21,
 '311', '602',
 8000.00, 21.00, 1680.00,
 'Výnos', 0, 'Servisní paušál FVE Kovárna – Q2 2024'),


-- ==================================================================
-- DEVELOPMENT: Bytový dům Holešovice (zakázka 301)
-- ==================================================================

-- 16. Přijaté zálohy od budoucích vlastníků bytů
(3001, '2024-03-15', NULL, 'VF-2024-2001', 'VF', 4,
 '99900011', 'Koupě bytu – Holešovice klient A', 301, 30,
 '311', '324',         -- 324 Přijaté zálohy (ne výnos, dokud není předáno!)
 1500000.00, 0.00, 0.00,
 'Výnos', 0, 'Rezervační záloha – byt č.5 Holešovice'),

-- 17. Stavební práce – generální dodavatel (klíčový náklad)
(3002, '2024-04-30', '2024-05-30', 'PF-2024-2001', 'PF', 4,
 '10011223', 'Stavby CZ a.s.', 301, 31,
 '042', '321',         -- 042 Nedokončené investice (rozvaha!)
 8500000.00, 21.00, 1785000.00,
 'Náklad', 0, 'Stavební práce – hrubá stavba Q1-Q2 2024'),

-- 18. Projektová dokumentace
(3003, '2024-01-20', '2024-02-20', 'PF-2024-2002', 'PF', 4,
 '20122334', 'Ateliér FORM architekti s.r.o.', 301, 30,
 '042', '321',
 380000.00, 21.00, 79800.00,
 'Náklad', 0, 'Projektová dokumentace – DUR + DSP Holešovice'),

-- 19. Inženýrská činnost / průzkumy
(3004, '2024-02-28', '2024-03-28', 'PF-2024-2003', 'PF', 4,
 '30233445', 'GEO průzkumy s.r.o.', 301, 30,
 '042', '321',
 95000.00, 21.00, 19950.00,
 'Náklad', 0, 'Geologický průzkum + radonové měření'),

-- 20. Komerční prostor Smíchov – náklady na přípravu
(3005, '2024-02-01', '2024-03-01', 'PF-2024-2004', 'PF', 4,
 '40344556', 'Vizualizace 3D Studio s.r.o.', 302, 30,
 '042', '321',
 65000.00, 21.00, 13650.00,
 'Náklad', 0, '3D vizualizace + marketing materiály – Smíchov'),


-- ==================================================================
-- INTERCOMPANY: BIDLI Technologies → ostatní divize
-- PROČ INTERCOMPANY?
-- BIDLI Technologies fakturuje ostatním divizím za IT služby.
-- Toto je legální a časté. Pro KONSOLIDOVANÝ výkaz holdingu
-- ale musíme tyto transakce ELIMINOVAT – aby nám výnos BT
-- a náklad BR/BE/BD nevykazovaly falešně větší obrat.
-- ==================================================================

-- 21. BT fakturuje Reality za CRM systém (výnos BT)
(4001, '2024-09-30', '2024-10-30', 'IC-2024-0001', 'VF', 5,
 '23456789', 'BIDLI Reality s.r.o. (IC)', 401, 40,
 '311', '602',
 190000.00, 21.00, 39900.00,
 'Výnos', 1,           -- je_intercompany = 1 ← KLÍČOVÝ FLAG
 'CRM systém pro BR – licence Q3+Q4 2024 (INTERCOMPANY)'),

-- 22. Reality platí BT za CRM (náklad BR)
(4002, '2024-09-30', '2024-10-30', 'IC-2024-0001', 'PF', 2,
 '56789012', 'BIDLI Technologies s.r.o. (IC)', 401, 12,
 '518', '321',
 190000.00, 21.00, 39900.00,
 'Náklad', 1,          -- je_intercompany = 1
 'CRM systém od BT – náklad BR admin (INTERCOMPANY)'),

-- 23. BT fakturuje Development za IT infrastrukturu
(4003, '2024-10-31', '2024-11-30', 'IC-2024-0002', 'VF', 5,
 '45678901', 'BIDLI Development s.r.o. (IC)', NULL, 41,
 '311', '602',
 45000.00, 21.00, 9450.00,
 'Výnos', 1,
 'IT infrastruktura BH server pro BD (INTERCOMPANY)'),

-- 24. Development platí BT
(4004, '2024-10-31', '2024-11-30', 'IC-2024-0002', 'PF', 4,
 '56789012', 'BIDLI Technologies s.r.o. (IC)', NULL, 31,
 '518', '321',
 45000.00, 21.00, 9450.00,
 'Náklad', 1,
 'IT infrastruktura od BT (INTERCOMPANY)'),


-- ==================================================================
-- MZDOVÉ NÁKLADY: Administrativní / personální
-- (zjednodušeno – v praxi přes mzdový systém)
-- ==================================================================

-- 25. Mzdy – Reality admin Q3 2024
(5001, '2024-09-30', NULL, 'INT-2024-5001', 'INT', 2,
 NULL, NULL, NULL, 12,
 '521', '331',         -- 521 Mzdové náklady / 331 Zaměstnanci
 285000.00, 0.00, 0.00,
 'Náklad', 0, 'Mzdové náklady Reality – administrativní tým Q3'),

-- 26. Mzdy – Energie tým Q3 2024
(5002, '2024-09-30', NULL, 'INT-2024-5002', 'INT', 3,
 NULL, NULL, NULL, 20,
 '521', '331',
 420000.00, 0.00, 0.00,
 'Náklad', 0, 'Mzdové náklady BE – instalační + prodejní tým Q3'),

-- 27. Mzdy – Development Q3 2024
(5003, '2024-09-30', NULL, 'INT-2024-5003', 'INT', 4,
 NULL, NULL, NULL, 30,
 '521', '331',
 380000.00, 0.00, 0.00,
 'Náklad', 0, 'Mzdové náklady BD – projektový a obchodní tým Q3'),

-- 28. Holding – management fee Q3 (náklad holdingngu, výnos sám sobě)
(5004, '2024-09-30', NULL, 'INT-2024-5004', 'INT', 1,
 NULL, NULL, NULL, 50,
 '521', '331',
 680000.00, 0.00, 0.00,
 'Náklad', 0, 'Mzdové náklady – holdingový management Q3 2024');
GO


-- ============================================================
-- SEKCE 3: SQL VIEWS – FINANČNÍ LOGIKA
-- ============================================================
-- PROČ VIEWS A NE PŘÍMÉ DOTAZY?
-- View = uložený dotaz. Výhody:
-- 1) Personalista i CFO zadá: SELECT * FROM v_pl_statement
--    Nemusí znát složitou logiku JOINů a podmínek.
-- 2) Power Query v Excelu se připojí přímo na View – čisté,
--    reprodukovatelné, verzovatelné.
-- 3) Pokud se změní logika výpočtu, opravíme View jednou
--    a všechny reporty se automaticky aktualizují.
-- ============================================================


-- ------------------------------------------------------------
-- VIEW 1: v_pl_statement
-- Income Statement (Výkaz zisku a ztráty) per divize
-- Agreguje výnosy a náklady za celý holding
-- s možností filtru per rok, divize nebo středisko
-- ------------------------------------------------------------
IF OBJECT_ID('dbo.v_pl_statement', 'V') IS NOT NULL
    DROP VIEW dbo.v_pl_statement;
GO

CREATE VIEW dbo.v_pl_statement AS
/*
  LOGIKA VÝPOČTU:
  ---------------
  1. Výnosy = všechny řádky s typ_pohybu = 'Výnos', BEZ intercompany
  2. Náklady = všechny řádky s typ_pohybu = 'Náklad', BEZ intercompany
  3. EBITDA = Výnosy – Přímé náklady (bez mezd, odpisů)
  4. EBIT   = EBITDA – Mzdy (zjednodušení: nemáme odpisy v demo datech)

  CO JE JOIN?
  JOIN = "spoj tabulky na základě společného klíče"
  Zde spojujeme fct_uctovani s dim_spolecnosti,
  abychom k číslu spolecnost_id dostali čitelný název divize.
  Bez JOINu bychom viděli jen "3" místo "Energie".
*/
SELECT
    -- Identifikace
    YEAR(f.datum_uctovani)                          AS rok,
    MONTH(f.datum_uctovani)                         AS mesic,

    -- Dimenze (z JOINovaných tabulek)
    s.divize                                        AS divize,
    s.nazev                                         AS spolecnost,
    st.nazev                                        AS stredisko,

    -- Klasifikace pohybu
    f.typ_pohybu,
    f.ucet_dal                                      AS ucet_vynosu,
    f.ucet_md                                       AS ucet_nakladu,

    -- Finanční hodnoty v Kč
    -- SUM = agregační funkce "sečti vše v dané skupině"
    SUM(
        CASE WHEN f.typ_pohybu = 'Výnos'
             THEN f.castka_bez_dph
             ELSE 0
        END
    )                                               AS vynosy_kc,

    SUM(
        CASE WHEN f.typ_pohybu = 'Náklad'
             THEN f.castka_bez_dph
             ELSE 0
        END
    )                                               AS naklady_kc,

    -- Výsledek hospodaření na řádku (Výnos – Náklad)
    SUM(
        CASE WHEN f.typ_pohybu = 'Výnos'  THEN  f.castka_bez_dph
             WHEN f.typ_pohybu = 'Náklad' THEN -f.castka_bez_dph
             ELSE 0
        END
    )                                               AS vysledek_kc,

    -- Počet dokladů (pro kontrolu úplnosti)
    COUNT(f.doklad_id)                              AS pocet_dokladu

FROM dbo.fct_uctovani f

-- JOIN 1: přidáme název divize a společnosti
INNER JOIN dbo.dim_spolecnosti s
    ON f.spolecnost_id = s.spolecnost_id

-- JOIN 2: přidáme název střediska
INNER JOIN dbo.dim_strediska st
    ON f.stredisko_id = st.stredisko_id

-- KLÍČOVÝ FILTR: vylučujeme intercompany transakce
-- aby se výnosy BT a náklady BR/BD neprojevily 2x
WHERE f.je_intercompany = 0

GROUP BY
    YEAR(f.datum_uctovani),
    MONTH(f.datum_uctovani),
    s.divize,
    s.nazev,
    st.nazev,
    f.typ_pohybu,
    f.ucet_dal,
    f.ucet_md;
GO


-- ------------------------------------------------------------
-- VIEW 2: v_marze_projektu
-- Marže per zakázka (pro developerské projekty a FVE)
--
-- PROČ MARŽE A NE ZISK?
-- Marže (%) = (Výnos – Náklady) / Výnos × 100
-- Zisk (Kč) = absolutní číslo.
-- Marže je relativní – umožňuje srovnávat projekty různé
-- velikosti. FVE za 1 mil a developer za 50 mil.
-- ------------------------------------------------------------
IF OBJECT_ID('dbo.v_marze_projektu', 'V') IS NOT NULL
    DROP VIEW dbo.v_marze_projektu;
GO

CREATE VIEW dbo.v_marze_projektu AS
SELECT
    -- Identifikace zakázky
    z.zakazka_kod,
    z.nazev                                         AS zakazka_nazev,
    z.typ_zakazky,
    z.stav                                          AS stav_zakazky,

    -- Dimenze střediska a divize
    st.nazev                                        AS stredisko,
    sp.divize,

    -- Plánované hodnoty (z dim_zakazky)
    z.rozpocet_vynosu                               AS plan_vynosy_kc,
    z.rozpocet_nakladu                              AS plan_naklady_kc,
    CASE WHEN ISNULL(z.rozpocet_vynosu, 0) = 0
         THEN NULL
         ELSE ROUND(
                (z.rozpocet_vynosu - z.rozpocet_nakladu)
                / z.rozpocet_vynosu * 100,
              2)
    END                                             AS plan_marze_pct,

    -- Skutečné hodnoty (z fct_uctovani, aggregated)
    SUM(CASE WHEN f.typ_pohybu = 'Výnos'
             THEN f.castka_bez_dph ELSE 0 END)      AS skutecnost_vynosy_kc,

    SUM(CASE WHEN f.typ_pohybu = 'Náklad'
             THEN f.castka_bez_dph ELSE 0 END)      AS skutecnost_naklady_kc,

    -- Skutečný zisk / ztráta na zakázce
    SUM(CASE WHEN f.typ_pohybu = 'Výnos'  THEN  f.castka_bez_dph
             WHEN f.typ_pohybu = 'Náklad' THEN -f.castka_bez_dph
             ELSE 0 END)                            AS skutecnost_zisk_kc,

    -- Skutečná marže v procentech (ošetřeno dělení nulou)
    CASE WHEN SUM(CASE WHEN f.typ_pohybu = 'Výnos'
                       THEN f.castka_bez_dph ELSE 0 END) = 0
         THEN NULL
         ELSE ROUND(
                SUM(CASE WHEN f.typ_pohybu = 'Výnos'  THEN  f.castka_bez_dph
                          WHEN f.typ_pohybu = 'Náklad' THEN -f.castka_bez_dph
                          ELSE 0 END)
                /
                SUM(CASE WHEN f.typ_pohybu = 'Výnos'
                         THEN f.castka_bez_dph ELSE 0 END)
                * 100, 2)
    END                                             AS skutecnost_marze_pct,

    -- Odchylka plán vs. skutečnost (v Kč)
    SUM(CASE WHEN f.typ_pohybu = 'Výnos'  THEN  f.castka_bez_dph
             WHEN f.typ_pohybu = 'Náklad' THEN -f.castka_bez_dph
             ELSE 0 END)
    - ISNULL(z.rozpocet_vynosu - z.rozpocet_nakladu, 0) AS odchylka_od_planu_kc,

    -- Časové informace
    z.datum_zahajeni,
    z.datum_ukonceni

FROM dbo.dim_zakazky z

-- LEFT JOIN: chceme i zakázky bez jediné transakce (prázdné projekty)
LEFT JOIN dbo.fct_uctovani f
    ON z.zakazka_id = f.zakazka_id
    AND f.je_intercompany = 0     -- vylučujeme IC pohyby i na zakázkové úrovni

-- JOIN dimenzí
INNER JOIN dbo.dim_strediska st
    ON z.stredisko_id = st.stredisko_id
INNER JOIN dbo.dim_spolecnosti sp
    ON st.spolecnost_id = sp.spolecnost_id

GROUP BY
    z.zakazka_kod, z.nazev, z.typ_zakazky, z.stav,
    st.nazev, sp.divize,
    z.rozpocet_vynosu, z.rozpocet_nakladu,
    z.datum_zahajeni, z.datum_ukonceni;
GO


-- ------------------------------------------------------------
-- VIEW 3: v_nakladovost_energie
-- KPI dashboard pro divizi Energie (FVE instalace)
-- Ukazuje nákladovost = Náklady / Výnosy v procentech
-- + strukturu nákladů: materiál vs. práce vs. admin
-- ------------------------------------------------------------
IF OBJECT_ID('dbo.v_nakladovost_energie', 'V') IS NOT NULL
    DROP VIEW dbo.v_nakladovost_energie;
GO

CREATE VIEW dbo.v_nakladovost_energie AS
SELECT
    z.zakazka_kod,
    z.nazev                                                 AS projekt,
    z.typ_zakazky,

    -- Celkové výnosy projektu
    SUM(CASE WHEN f.typ_pohybu = 'Výnos'
             THEN f.castka_bez_dph ELSE 0 END)              AS celkove_vynosy_kc,

    -- Detailní nákladová struktura podle ÚČTU
    -- Účet 501 = Spotřeba materiálu (panely, střídače...)
    SUM(CASE WHEN f.ucet_md = '501'
             THEN f.castka_bez_dph ELSE 0 END)              AS naklady_material_kc,

    -- Účet 518 = Subdodávky a služby (elektrikáři, projekce...)
    SUM(CASE WHEN f.ucet_md = '518'
             THEN f.castka_bez_dph ELSE 0 END)              AS naklady_subdodavky_kc,

    -- Účet 521 = Mzdy vlastního týmu
    SUM(CASE WHEN f.ucet_md = '521'
             THEN f.castka_bez_dph ELSE 0 END)              AS naklady_mzdy_kc,

    -- Celkové náklady (součet všeho)
    SUM(CASE WHEN f.typ_pohybu = 'Náklad'
             THEN f.castka_bez_dph ELSE 0 END)              AS celkove_naklady_kc,

    -- Hrubý zisk v Kč
    SUM(CASE WHEN f.typ_pohybu = 'Výnos'  THEN  f.castka_bez_dph
             WHEN f.typ_pohybu = 'Náklad' THEN -f.castka_bez_dph
             ELSE 0 END)                                    AS hruby_zisk_kc,

    -- Nákladovost % = Náklady / Výnosy × 100
    -- Zdravá FVE instalace: 55–70% nákladovost → marže 30–45%
    CASE WHEN SUM(CASE WHEN f.typ_pohybu = 'Výnos'
                       THEN f.castka_bez_dph ELSE 0 END) = 0
         THEN NULL
         ELSE ROUND(
                SUM(CASE WHEN f.typ_pohybu = 'Náklad'
                         THEN f.castka_bez_dph ELSE 0 END)
                /
                SUM(CASE WHEN f.typ_pohybu = 'Výnos'
                         THEN f.castka_bez_dph ELSE 0 END)
                * 100, 1)
    END                                                     AS nakladovost_pct,

    -- Podíl materiálu na celkových nákladech (%)
    -- Klíčový KPI: rostoucí ceny panelů = degradace marže
    CASE WHEN SUM(CASE WHEN f.typ_pohybu = 'Náklad'
                       THEN f.castka_bez_dph ELSE 0 END) = 0
         THEN NULL
         ELSE ROUND(
                SUM(CASE WHEN f.ucet_md = '501'
                         THEN f.castka_bez_dph ELSE 0 END)
                /
                SUM(CASE WHEN f.typ_pohybu = 'Náklad'
                         THEN f.castka_bez_dph ELSE 0 END)
                * 100, 1)
    END                                                     AS podil_materialu_pct

FROM dbo.dim_zakazky z
INNER JOIN dbo.fct_uctovani f
    ON z.zakazka_id = f.zakazka_id
INNER JOIN dbo.dim_strediska st
    ON z.stredisko_id = st.stredisko_id
INNER JOIN dbo.dim_spolecnosti sp
    ON st.spolecnost_id = sp.spolecnost_id

-- Filtrujeme pouze divizi Energie
WHERE sp.divize = 'Energie'
  AND f.je_intercompany = 0

GROUP BY
    z.zakazka_kod, z.nazev, z.typ_zakazky;
GO


-- ============================================================
-- SEKCE 4: KONTROLNÍ DOTAZY (spusť pro ověření)
-- ============================================================

PRINT '=== KONTROLA: Počty řádků ===';
SELECT 'dim_spolecnosti' AS tabulka, COUNT(*) AS radku FROM dbo.dim_spolecnosti
UNION ALL SELECT 'dim_strediska',   COUNT(*) FROM dbo.dim_strediska
UNION ALL SELECT 'dim_zakazky',     COUNT(*) FROM dbo.dim_zakazky
UNION ALL SELECT 'fct_uctovani',    COUNT(*) FROM dbo.fct_uctovani;

PRINT '=== KONTROLA: Obrat holdingu bez IC ===';
SELECT
    SUM(CASE WHEN typ_pohybu = 'Výnos'  THEN castka_bez_dph ELSE 0 END) AS celkove_vynosy,
    SUM(CASE WHEN typ_pohybu = 'Náklad' THEN castka_bez_dph ELSE 0 END) AS celkove_naklady
FROM dbo.fct_uctovani
WHERE je_intercompany = 0;

PRINT '=== VIEW: P&L per divize ===';
SELECT divize, SUM(vynosy_kc) AS vynosy, SUM(naklady_kc) AS naklady,
       SUM(vysledek_kc) AS vyledek_hospodareni
FROM dbo.v_pl_statement
GROUP BY divize
ORDER BY divize;

PRINT '=== VIEW: Marže projektů ===';
SELECT zakazka_kod, zakazka_nazev, plan_marze_pct,
       skutecnost_marze_pct, odchylka_od_planu_kc
FROM dbo.v_marze_projektu
ORDER BY divize, zakazka_kod;

PRINT '=== VIEW: Nákladovost Energie ===';
SELECT projekt, nakladovost_pct, podil_materialu_pct, hruby_zisk_kc
FROM dbo.v_nakladovost_energie;

-- ============================================================
-- KONEC SKRIPTU
-- Autor si vyhrazuje právo na rozšíření o:
-- - Cashflow statement (nepřímou metodou)
-- - Rozvaha (Balance Sheet) view
-- - Rolling 12M výpočty (LAG/LEAD window functions)
-- - Variance analysis Plán vs. Skutečnost
-- ============================================================
