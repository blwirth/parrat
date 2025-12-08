import requests
import pandas as pd
import argparse
import yaml
import os

with open("config.yaml", "r") as f:
    config = yaml.safe_load(f)

parser = argparse.ArgumentParser(description='Fetch NPI data from CMS API')
parser.add_argument("--taxonomy_description", type=str, help="Override taxonomy description (e.g., 'Dermatology', 'Cardiology')")
parser.add_argument("--limit", type=int, help="Override limit parameter for pagination. Default is 10, max is 200")
parser.add_argument("--skip", type=int, help="Override skip parameter for pagination. Max skip is 1000 for a total of 1200 records over 6 requests")
args = parser.parse_args()

if args.taxonomy_description:
    config["api_params"]["taxonomy_description"] = args.taxonomy_description
if args.limit is not None:
    config["api_params"]["limit"] = args.limit
if args.skip is not None:
    config["api_params"]["skip"] = args.skip

params_list = []
for key, value in config["api_params"].items():
    if value is not None and value != "":
        params_list.append(f"{key}={value}")

api_params = "&".join(params_list)

def get_nh_npi(api_params):
    base_url = "https://npiregistry.cms.hhs.gov/api/"

    url = f"{base_url}?{api_params}"
    print(f"url: {url}")
    response = requests.get(url)
    data = response.json()

    # Flatten the nested data structure
    flattened_data = []
    for result in data.get("results", []):
        row = {
            "npi": result.get("number"),
            "enumeration_type": result.get("enumeration_type"),
        }
        
        basic = result.get("basic", {})
        row["first_name"] = basic.get("first_name")
        row["last_name"] = basic.get("last_name")
        row["middle_name"] = basic.get("middle_name")
        row["credential"] = basic.get("credential")
        row["sex"] = basic.get("sex")
        row["enumeration_date"] = basic.get("enumeration_date")
        row["status"] = basic.get("status")
        
        taxonomies = result.get("taxonomies", [])
        primary_taxonomy = next((t for t in taxonomies if t.get("primary")), taxonomies[0] if taxonomies else {})
        row["taxonomy_code"] = primary_taxonomy.get("code")
        row["taxonomy_desc"] = primary_taxonomy.get("desc")
        row["taxonomy_license"] = primary_taxonomy.get("license")
        row["taxonomy_state"] = primary_taxonomy.get("state")
        
        addresses = result.get("addresses", [])
        location_address = next((a for a in addresses if a.get("address_purpose") == "LOCATION"), addresses[0] if addresses else {})
        row["address_1"] = location_address.get("address_1")
        row["address_2"] = location_address.get("address_2")
        row["city"] = location_address.get("city")
        row["state"] = location_address.get("state")
        row["postal_code"] = location_address.get("postal_code")
        row["phone"] = location_address.get("telephone_number")
        row["fax"] = location_address.get("fax_number")
        
        flattened_data.append(row)
    
    new_df = pd.DataFrame(flattened_data)
    
    # Ensure NPI is stored as string for consistent comparison
    new_df['npi'] = new_df['npi'].astype(str)
    
    excel_file = "nh_npi.xlsx"
    if os.path.exists(excel_file):
        existing_df = pd.read_excel(excel_file)
        
        existing_df['npi'] = existing_df['npi'].astype(str).str.replace('.0', '', regex=False)
        
        existing_npis = set(existing_df['npi'].values)
        new_npis = set(new_df['npi'].values)
        
        updated_count = len(existing_npis.intersection(new_npis))
        added_count = len(new_npis - existing_npis)
        
        existing_df = existing_df.set_index('npi')
        new_df = new_df.set_index('npi')
        
        updated_df = existing_df.copy()
        
        for npi in new_df.index:
            updated_df.loc[npi] = new_df.loc[npi]
        
        updated_df = updated_df.reset_index()
        
        print(f"Updated {updated_count} existing entries, added {added_count} new entries")
    else:
        updated_df = new_df
        print(f"Created new file with {len(new_df)} entries")
    
    updated_df.to_excel(excel_file, index=False)
    return updated_df

if __name__ == "__main__":
    print(get_nh_npi(api_params))