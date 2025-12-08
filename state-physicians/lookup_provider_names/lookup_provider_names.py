#!/usr/bin/env python3
"""
Script to add provider names to NPI-License data by looking up NPIs in nh_npi.xlsx.
"""

import pandas as pd
import argparse


def format_address_name(row):
    """Format address name as: Lname, Fname MName (without credential)."""
    name_parts = []
    
    if pd.notna(row.get('last_name')):
        last_name = str(row['last_name'])
        if pd.notna(row.get('first_name')):
            # Add comma directly to last name (no space before comma)
            name_parts.append(last_name + ',')
            name_parts.append(str(row['first_name']))
        else:
            name_parts.append(last_name)
    elif pd.notna(row.get('first_name')):
        name_parts.append(str(row['first_name']))
    
    if pd.notna(row.get('middle_name')):
        # Strip trailing period from middle name
        middle = str(row['middle_name']).rstrip('.')
        name_parts.append(middle)
    
    return ' '.join(name_parts) if name_parts else ''


def lookup_provider_names(input_file, nh_npi_file, output_file):
    """Add provider names to NPI-License data by looking up NPIs."""
    print(f"Reading input file: {input_file}...")
    df = pd.read_excel(input_file)
    
    print(f"Reading NH NPI lookup file: {nh_npi_file}...")
    nh_npi_df = pd.read_excel(nh_npi_file)
    
    df['NPI'] = df['NPI'].astype(str).str.strip()
    nh_npi_df['npi'] = nh_npi_df['npi'].astype(str).str.strip()
    
    print(f"\nLooking up {len(df)} NPIs...")
    
    # Merge with nh_npi data to get all available fields
    result_df = df.merge(
        nh_npi_df[[
            'npi', 'first_name', 'last_name', 'middle_name', 
            'address_1', 'address_2', 'city', 'state', 'postal_code',
            'phone', 'fax', 'taxonomy_desc'
        ]],
        left_on='NPI',
        right_on='npi',
        how='left'
    )
    
    print("Formatting data...")
    
    # Create the output dataframe with exact headers as specified
    final_df = pd.DataFrame()
    
    # Column headers in exact order and format specified
    final_df['DOCID'] = result_df['License']  # License goes in DOCID
    final_df['NPICode'] = result_df['NPI']
    final_df['AddressName'] = result_df.apply(format_address_name, axis=1)
    final_df['LASTNAME'] = result_df['last_name']
    final_df['FIRSTNAME'] = result_df['first_name']
    # Strip trailing period from MIDDLENAME
    final_df['MIDDLENAME'] = result_df['middle_name'].apply(lambda x: str(x).rstrip('.') if pd.notna(x) else x)
    final_df['ADDRESS1'] = result_df['address_1']
    final_df['ADDRESS2'] = result_df['address_2']
    final_df['CITY'] = result_df['city']
    final_df['STATE'] = result_df['state']
    # Convert ZIPCODE to string with proper formatting (5-digit or 9-digit with hyphen)
    def format_zipcode(x):
        if pd.isna(x):
            return ''
        # Convert to string and remove any decimals
        zip_str = str(int(x))
        # Pad with leading zeros
        if len(zip_str) <= 5:
            return zip_str.zfill(5)  # 5-digit ZIP
        else:
            # 9-digit ZIP: format as 12345-1234
            zip_str = zip_str.zfill(9)
            return f"{zip_str[:5]}-{zip_str[5:]}"
    
    final_df['ZIPCODE'] = result_df['postal_code'].apply(format_zipcode)
    # Convert PHONE to string and clean
    final_df['PHONE'] = result_df['phone'].apply(lambda x: str(x) if pd.notna(x) else '')
    # Convert FAX to string and clean
    final_df['FAX'] = result_df['fax'].apply(lambda x: str(x) if pd.notna(x) else '')
    final_df['PATHLOc'] = ''  # Blank
    final_df['PRACTICE'] = ''  # Blank
    final_df['SPECIALTY'] = result_df['taxonomy_desc']
    final_df['SUPRESSLET'] = ''  # Blank
    final_df['ID'] = ''  # Blank (License is now in DOCID)
    final_df['Email'] = ''  # Blank
    final_df['Group Name'] = ''  # Blank
    final_df['NewGroupName'] = ''  # Blank
    final_df['Status'] = ''  # Blank
    final_df['EP-Medicare'] = ''  # Blank
    final_df['EP-Medicaid'] = ''  # Blank
    final_df['LicenseIssueDate'] = ''  # Blank
    
    # Count records with data
    found_count = result_df['last_name'].notna().sum()
    not_found_count = len(result_df) - found_count
    
    print(f"\nLookup Results:")
    print(f"  NPIs found in nh_npi.xlsx: {found_count}")
    print(f"  NPIs not found: {not_found_count}")
    
    if not_found_count > 0:
        print(f"\nNPIs not found in nh_npi.xlsx:")
        missing_npis = result_df[result_df['last_name'].isna()]['NPI'].tolist()
        for npi in missing_npis[:10]:
            print(f"  - {npi}")
        if len(missing_npis) > 10:
            print(f"  ... and {len(missing_npis) - 10} more")
    
    print(f"\nSaving to {output_file}...")
    with pd.ExcelWriter(output_file, engine='openpyxl') as writer:
        final_df.to_excel(writer, index=False, sheet_name='Sheet1')
        worksheet = writer.sheets['Sheet1']
        
        # Format specific columns as text to preserve leading zeros and formatting
        # DOCID (column A), NPICode (column B), ZIPCODE (column K), PHONE (column L), FAX (column M)
        for row in range(2, len(final_df) + 2):
            worksheet[f'A{row}'].number_format = '@'  # DOCID (License)
            worksheet[f'B{row}'].number_format = '@'  # NPICode
            worksheet[f'K{row}'].number_format = '@'  # ZIPCODE
            worksheet[f'L{row}'].number_format = '@'  # PHONE
            worksheet[f'M{row}'].number_format = '@'  # FAX
    
    print(f"\nComplete!")
    print(f"\nSummary:")
    print(f"  Input file: {input_file}")
    print(f"  Lookup file: {nh_npi_file}")
    print(f"  Output file: {output_file}")
    print(f"  Total records: {len(final_df)}")
    print(f"  Records with provider data: {found_count}")
    print(f"  Records missing provider data: {not_found_count}")
    
    return final_df


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description='Add provider names to NPI-License data by looking up NPIs.'
    )
    parser.add_argument(
        'input_file',
        nargs='?',
        default='../clean_physician_export/999993_Physician_Export_Clean.xlsx',
        help='Input Excel file with NPI and License columns'
    )
    parser.add_argument(
        'nh_npi_file',
        nargs='?',
        default='../get_NPI/nh_npi.xlsx',
        help='NH NPI lookup file'
    )
    parser.add_argument(
        'output_file',
        nargs='?',
        default='999993_Physician_Export_WithNames.xlsx',
        help='Output Excel file'
    )
    
    args = parser.parse_args()
    
    lookup_provider_names(args.input_file, args.nh_npi_file, args.output_file)