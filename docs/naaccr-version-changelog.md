# NAACCR Data Dictionary Version Changelog

Reference document for QA and future version support planning.

## v23 to v24 (Effective January 1, 2024)

Posted July 10, 2023. HLSG approved 23 of 55 change requests.

### New Data Items (6)

| Item # | Name | Notes |
|--------|------|-------|
| 86 | Geocoding Quality Code | Length 1. Quality of geocoding match |
| 87 | Geocoding Quality Code Detail | Length 14. Geocode quality element details |
| 751 | RX Hosp--Recon Breast | Breast reconstruction at reporting hospital |
| 1335 | RX Summ--Recon Breast | Summary breast reconstruction across all facilities |
| 671 | RX Hosp--Surg Prim Site 2023 | New surgery codes for breast, colon, lung, pancreas, thyroid |
| 1291 | RX Summ--Surg Prim Site 2023 | Summary surgery codes for same 5 sites |

### Retired Data Items (5)

- Birthplace
- Place of Death
- Name--Maiden
- LN Status Femoral-Inguinal, Para-aortic, Pelvic
- CRC Checksum

### Revisions

- Brain Molecular Markers [3816]: added codes and updated terminology
- Surgery code tables updated for 5 sites (Breast, Lung, Colon, Thyroid, Pancreas) for diagnosis year 2024+

### Sources

- https://narrative.naaccr.org/mltg-v24_changes/
- https://apps.naaccr.org/data-dictionary/data-dictionary/version=24/chapter-view/
- https://www.naaccr.org/wp-content/uploads/2023/10/2024-Implementation-Guidelines_20231020.pdf

---

## v24 to v25 (Effective January 1, 2025)

Posted May 31, 2024.

### New Data Items

- PTLD (Post Transplant Lymphoproliferative Disorder) [1172] -- prognostic value for pediatric/AYA
- Pediatric Data Collection System (PCDS) -- Toronto Staging Guidelines v2 for pediatric cancer

### Retired Data Items (~30)

Major cleanup effort, primarily pre-Phase radiation data items no longer collected.
Brought the 3-year cumulative retirement total to 76 items.

### XML / Technical Changes

- NAACCR XML Specification v1.8 support (new `dateTime` data type)
- Type changes: `pediatricId` mixed->text, `pdl1` mixed->text, `whiteBloodCellCount` digits->text
- `pediatricIdVersionCurrent` and `pediatricIdVersionOriginal` digits->numeric

### Sources

- https://narrative.naaccr.org/changes-approved-for-2025-registry-data-standards/
- https://apps.naaccr.org/data-dictionary/data-dictionary/version=25/chapter-view/
- https://apps.naaccr.org/data-dictionary/data-dictionary/version=25/chapter-view/change-log/
- https://www.naaccr.org/wp-content/uploads/2025/01/2025-Implementation-Guidelines_20250114.pdf

---

## v25 to v26 (Effective January 1, 2026) -- CURRENT

Posted June 23, 2025. Record Version Code: 260.

### Sex Field Replacement (BREAKING)

**Sex [220] is replaced by Sex Assigned at Birth [225].**

| Aspect | v25 and earlier | v26 |
|--------|-----------------|-----|
| Item Number | 220 | **225** |
| Item Name | Sex | **Sex Assigned at Birth** |
| XML ID | `sex` | **`sexAssignedAtBirth`** |
| Length | 1 | 1 |
| Parent | Patient | Patient |
| Valid Codes | 1=Male, 2=Female, 3=Other, 4=Transsexual, 5=Intersex, 9=Not stated | **1=Male, 2=Female, 9=Unknown** |

Codes 3, 4, 5 removed. Non-binary/transsexual/other with no additional info -> code 9.
Site-based inference: C600-C639 -> 1 (Male), C510-C589 -> 2 (Female).

### New Data Items

| Item # | Name | Notes |
|--------|------|-------|
| -- | RUCA 2020 | Rural-Urban Commuting Area codes (2020 census) |
| -- | URIC 2020 | Urban-Rural Indicator Codes (2020 census) |
| 1176 | Spread Through Air Spaces (STAS) | Lung; associated with increased recurrence risk |
| -- | Microsatellite Instability (MSI) | Corpus Uteri Carcinoma |
| -- | Residual Cancer Burden | Breast cancer, dx 1/1/2026+ |

### Revisions

- Major Salivary Glands staging updated to Version 9 with new Grade Table
- Oropharynx HPV-Associated staging updates
- All possible derived flavors of null codes added (codes A through D)

### Technical

- Edits metafile in EditWriter v6 (EW6), `.smf` format only
- NorthCon 260 conversion utility (CDC) for v25->v26 conversion
- Base dictionary URI: `http://naaccr.org/naaccrxml/naaccr-dictionary-260.xml`

### Sources

- https://apps.naaccr.org/data-dictionary/data-dictionary/version=26/chapter-view/
- https://apps.naaccr.org/data-dictionary/data-dictionary/version=26/chapter-view/change-log/
- https://apps.naaccr.org/data-dictionary/data-dictionary/version=26/data-item-view/item-number=225/
- https://www.naaccr.org/wp-content/uploads/2025/08/2026-Implementation-Guidelines_20250811.pdf
- https://www.naaccr.org/wp-content/uploads/2025/10/2026-Implementation-Guidelines_20251014-2.pdf

---

## Impact on PARRAT

Currently using v25 dictionary (`naaccr-items-v25.json`). For v26 support:

1. Add `naaccr-items-v26.json` dictionary file
2. Update Sex field handling: `sex` (220) -> `sexAssignedAtBirth` (225), valid values 1/2/9 only
3. Add new items (RUCA 2020, URIC 2020, STAS, MSI, Residual Cancer Burden)
4. Support `naaccrRecordVersion` value `260`
5. Update `baseDictionaryUri` default to `naaccr-dictionary-260.xml`

**Note:** The XML structure (NaaccrData/Patient/Tumor hierarchy) is unchanged across all these versions. Field-level changes are additive/subtractive, not structural.
