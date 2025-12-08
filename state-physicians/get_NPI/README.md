# README get_NPI

## Purpose

This script gets NPIs and licenses where available for NH physicians, flattens the output, and returns them in `nh_npi.xlsx` in the root directory. Subsequent runs will update existing records and append new records.

## Installation

1. Clone repo
2. cd into repo
3. `python3 -m venv venv`
4. `source venv/bin/activate`
5. `pip install -r requirements.txt`
6. `python3 get_NPI/get-NH-NPI.py`

## Configuration

### Example Request
`https://npiregistry.cms.hhs.gov/api/?number=&enumeration_type=NPI-1&taxonomy_description=Dermatology&name_purpose=&first_name=&use_first_name_alias=&last_name=&organization_name=&address_purpose=&city=&state=NH&postal_code=&country_code=&limit=&skip=&pretty=&version=2.1`

### Fields

The parameters used in the request to the NPI registry in `config.yaml` can be updated directly or passed as CLI arguments.

Available CLI arguments:
- `--taxonomy_description` - Add the taxonomy description (e.g., 'Dermatology', 'Internal Medicine')
- `--limit` - Override NPI default limit of 10 (max 200)
- `--skip` - Skip parameter for pagination (max 1000)

## Usage

### Examples

- Get first 10 dermatologists
```bash
python3 get-NH-NPI.py --taxonomy_description Dermatology
```

- Get second page of results for internists
```bash
python3 get-NH-NPI.py --taxonomy_description "Internal Medicine" --limit 200 --skip 200
```
The console output will indicate if there are more physicians:

```
Updated 0 existing entries, added 200 new entries
```
The `--skip` parameter can be incremented up to 1000 to obtain a total of 1200 records per query.

### Limits

*Effective 6/25/2024*: To ensure the best experience, NPPES has limited the amount of NPI Registry queries that can be completed per hour. Bulk NPI Registry queries must use the DDS file. NPPES does not publicly define query rates.

## NPPES NPI API Useful Links

- [Version 2.1 Docs](https://npiregistry.cms.hhs.gov/api-page)
- [Demo](https://npiregistry.cms.hhs.gov/demo-api)