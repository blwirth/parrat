#!/usr/bin/env python3
"""
Script to fetch missing provider data from NPI API for NPIs not found in nh_npi.xlsx.
Waits 10 seconds between API calls to respect rate limits.
"""

import pandas as pd
import requests
import argparse
import time
import os
from datetime import datetime


def format_zipcode(postal_code):
    """Format ZIP code with leading zeros and hyphen if 9-digit."""
    if not postal_code:
        return ''
    
    zip_str = str(postal_code).replace('-', '')
    
    if len(zip_str) <= 5:
        return zip_str.zfill(5)
    else:
        zip_str = zip_str.zfill(9)
        return f"{zip_str[:5]}-{zip_str[5:]}"


def format_address_name(first_name, last_name, middle_name):
    """Format address name as: Lname, Fname MName."""
    name_parts = []
    
    if last_name:
        if first_name:
            # Add comma directly to last name (no space before comma)
            name_parts.append(str(last_name) + ',')
            name_parts.append(str(first_name))
        else:
            name_parts.append(str(last_name))
    elif first_name:
        name_parts.append(str(first_name))
    
    if middle_name:
        # Strip trailing period from middle name
        middle = str(middle_name).rstrip('.')
        name_parts.append(middle)
    
    return ' '.join(name_parts) if name_parts else ''


def save_to_excel(df, output_file):
    """Save dataframe to Excel with proper formatting."""
    with pd.ExcelWriter(output_file, engine='openpyxl') as writer:
        df.to_excel(writer, index=False, sheet_name='Sheet1')
        worksheet = writer.sheets['Sheet1']
        
        # Format specific columns as text
        for row_num in range(2, len(df) + 2):
            worksheet[f'A{row_num}'].number_format = '@'  # DOCID (License)
            worksheet[f'B{row_num}'].number_format = '@'  # NPICode
            worksheet[f'K{row_num}'].number_format = '@'  # ZIPCODE
            worksheet[f'L{row_num}'].number_format = '@'  # PHONE
            worksheet[f'M{row_num}'].number_format = '@'  # FAX


def fetch_npi_data(npi):
    """Fetch provider data from NPI API for a single NPI."""
    base_url = "https://npiregistry.cms.hhs.gov/api/"
    url = f"{base_url}?number={npi}&version=2.1"
    
    try:
        response = requests.get(url, timeout=30)
        response.raise_for_status()
        data = response.json()
        
        results = data.get("results", [])
        if not results:
            return None
        
        result = results[0]
        row = {}
        
        # Basic information
        basic = result.get("basic", {})
        row["first_name"] = basic.get("first_name")
        row["last_name"] = basic.get("last_name")
        row["middle_name"] = basic.get("middle_name", "").rstrip('.')  # Strip trailing period
        
        # Taxonomies - prioritize NH state license, then primary taxonomy
        taxonomies = result.get("taxonomies", [])
        
        # First try to find NH taxonomy
        nh_taxonomy = next((t for t in taxonomies if t.get("state") == "NH"), None)
        
        # If no NH taxonomy, use primary taxonomy
        if nh_taxonomy:
            selected_taxonomy = nh_taxonomy
            row["taxonomy_source"] = "NH"  # For logging
        else:
            selected_taxonomy = next((t for t in taxonomies if t.get("primary")), taxonomies[0] if taxonomies else {})
            row["taxonomy_source"] = "Primary" if selected_taxonomy.get("primary") else "First"
        
        row["taxonomy_desc"] = selected_taxonomy.get("desc")
        row["taxonomy_license"] = selected_taxonomy.get("license")
        row["taxonomy_state"] = selected_taxonomy.get("state")
        
        # Addresses
        addresses = result.get("addresses", [])
        location_address = next((a for a in addresses if a.get("address_purpose") == "LOCATION"), addresses[0] if addresses else {})
        row["address_1"] = location_address.get("address_1")
        row["address_2"] = location_address.get("address_2")
        row["city"] = location_address.get("city")
        row["state"] = location_address.get("state")
        row["postal_code"] = location_address.get("postal_code")
        row["phone"] = location_address.get("telephone_number")
        row["fax"] = location_address.get("fax_number")
        
        return row
    
    except requests.exceptions.RequestException as e:
        print(f"    Error fetching NPI {npi}: {e}")
        return None


def fetch_missing_npi_data(input_file, output_file, wait_seconds=10):
    """Fetch missing NPI data and update the Excel file."""
    
    # If output file exists, use it as input to resume progress
    if os.path.exists(output_file):
        print(f"Found existing output file: {output_file}")
        print(f"Resuming from: {output_file}")
        df = pd.read_excel(output_file)
    else:
        print(f"Reading input file: {input_file}...")
        df = pd.read_excel(input_file)
    
    # Identify rows with missing data (where AddressName is blank/NaN)
    missing_mask = df['AddressName'].isna() | (df['AddressName'] == '')
    missing_df = df[missing_mask].copy()
    
    total_missing = len(missing_df)
    total_complete = len(df) - total_missing
    
    print(f"\nStatus:")
    print(f"  Total records: {len(df)}")
    print(f"  Complete (with AddressName): {total_complete}")
    print(f"  Remaining to fetch: {total_missing}")
    
    if total_missing == 0:
        print("\n✓ All records are complete! No data to fetch.")
        return df
    
    print(f"Will wait {wait_seconds} seconds between API calls")
    print(f"Estimated time: {(total_missing * wait_seconds) / 60:.1f} minutes\n")
    
    # Fetch data for each missing NPI
    updated_count = 0
    failed_count = 0
    
    for idx, row in missing_df.iterrows():
        npi = str(row['NPICode'])
        print(f"[{updated_count + failed_count + 1}/{total_missing}] Fetching NPI: {npi}...")
        
        npi_data = fetch_npi_data(npi)
        
        if npi_data:
            # Helper function to check if field is blank
            def is_blank(value):
                return pd.isna(value) or value == ''
            
            # Update the dataframe with fetched data - only if current field is blank
            if npi_data.get('last_name') and is_blank(df.at[idx, 'LASTNAME']):
                df.at[idx, 'LASTNAME'] = npi_data['last_name']
            if npi_data.get('first_name') and is_blank(df.at[idx, 'FIRSTNAME']):
                df.at[idx, 'FIRSTNAME'] = npi_data['first_name']
            if npi_data.get('middle_name') and is_blank(df.at[idx, 'MIDDLENAME']):
                df.at[idx, 'MIDDLENAME'] = npi_data['middle_name']
            
            # Format AddressName only if blank
            if is_blank(df.at[idx, 'AddressName']):
                df.at[idx, 'AddressName'] = format_address_name(
                    npi_data.get('first_name'),
                    npi_data.get('last_name'),
                    npi_data.get('middle_name')
                )
            
            # Update address fields - only if current field is blank
            if npi_data.get('address_1') and is_blank(df.at[idx, 'ADDRESS1']):
                df.at[idx, 'ADDRESS1'] = npi_data['address_1']
            if npi_data.get('address_2') and is_blank(df.at[idx, 'ADDRESS2']):
                df.at[idx, 'ADDRESS2'] = npi_data['address_2']
            if npi_data.get('city') and is_blank(df.at[idx, 'CITY']):
                df.at[idx, 'CITY'] = npi_data['city']
            if npi_data.get('state') and is_blank(df.at[idx, 'STATE']):
                df.at[idx, 'STATE'] = npi_data['state']
            if npi_data.get('postal_code') and is_blank(df.at[idx, 'ZIPCODE']):
                df.at[idx, 'ZIPCODE'] = format_zipcode(npi_data['postal_code'])
            if npi_data.get('phone') and is_blank(df.at[idx, 'PHONE']):
                df.at[idx, 'PHONE'] = npi_data['phone']
            if npi_data.get('fax') and is_blank(df.at[idx, 'FAX']):
                df.at[idx, 'FAX'] = npi_data['fax']
            if npi_data.get('taxonomy_desc') and is_blank(df.at[idx, 'SPECIALTY']):
                df.at[idx, 'SPECIALTY'] = npi_data['taxonomy_desc']
            
            updated_count += 1
            taxonomy_source = npi_data.get("taxonomy_source", "Unknown")
            taxonomy_state = npi_data.get("taxonomy_state", "N/A")
            print(f"    ✓ Found: {df.at[idx, 'AddressName']} (Taxonomy: {taxonomy_source} - {taxonomy_state})")
        else:
            failed_count += 1
            print(f"    ✗ Not found or error")
        
        # Save progress after each API call
        print(f"    Saving progress to {output_file}...")
        save_to_excel(df, output_file)
        
        # Wait between API calls (except for the last one)
        if updated_count + failed_count < total_missing:
            print(f"    Waiting {wait_seconds} seconds...")
            time.sleep(wait_seconds)
    
    print(f"\n{'='*60}")
    print(f"Summary:")
    print(f"  Successfully fetched: {updated_count}")
    print(f"  Failed or not found: {failed_count}")
    print(f"  Total processed: {total_missing}")
    print(f"{'='*60}\n")
    
    # Final save
    print(f"Final save to {output_file}...")
    save_to_excel(df, output_file)
    
    print(f"Complete! File saved to {output_file}")
    
    return df


if __name__ == "__main__":
    # Get the script's directory to build relative paths
    script_dir = os.path.dirname(os.path.abspath(__file__))
    default_input = os.path.join(script_dir, '..', 'lookup_provider_names', '999993_Physician_Export_WithNames.xlsx')
    default_output = os.path.join(script_dir, '999993_Physician_Export_Complete.xlsx')
    
    parser = argparse.ArgumentParser(
        description='Fetch missing NPI data from CMS NPI Registry API.'
    )
    parser.add_argument(
        'input_file',
        nargs='?',
        default=default_input,
        help='Input Excel file'
    )
    parser.add_argument(
        'output_file',
        nargs='?',
        default=default_output,
        help='Output Excel file'
    )
    parser.add_argument(
        '--wait',
        type=int,
        default=10,
        help='Seconds to wait between API calls (default: 10)'
    )
    
    args = parser.parse_args()
    
    fetch_missing_npi_data(args.input_file, args.output_file, args.wait)

