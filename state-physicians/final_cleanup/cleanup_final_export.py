#!/usr/bin/env python3
"""
Final cleanup script to remove invalid records:
1. Rows with only NPI (all other fields blank) - faulty NPIs
2. Rows with specialty "Pathology, Anatomic Pathology & Clinical Pathology"
"""

import pandas as pd
import argparse
import os


def cleanup_export(input_file, output_file):
    """
    Clean up the final export by removing invalid records.
    
    Args:
        input_file: Path to input Excel file
        output_file: Path to output Excel file
    """
    print(f"Reading input file: {input_file}...")
    df = pd.read_excel(input_file)
    
    initial_count = len(df)
    print(f"Initial record count: {initial_count}")
    
    # Identify rows that are blank except for NPI/NPICode and ID
    # These are the only columns that should always have values
    # Check if all other fields are blank
    columns_to_check = [col for col in df.columns if col not in ['DOCID', 'NPICode', 'ID']]
    
    blank_mask = df[columns_to_check].isna().all(axis=1) | (df[columns_to_check] == '').all(axis=1)
    blank_rows = df[blank_mask]
    
    print(f"\nRows with only NPI (faulty NPIs): {len(blank_rows)}")
    if len(blank_rows) > 0:
        print("  Sample faulty NPIs:")
        for npi in blank_rows['NPICode'].head(5):
            print(f"    - {npi}")
    
    # Remove blank rows
    df = df[~blank_mask].copy()
    print(f"After removing faulty NPIs: {len(df)} records")
    
    # Remove rows with specific pathology specialty
    pathology_specialty = "Pathology, Anatomic Pathology & Clinical Pathology"
    pathology_mask = df['SPECIALTY'] == pathology_specialty
    pathology_rows = df[pathology_mask]
    
    print(f"\nRows with '{pathology_specialty}': {len(pathology_rows)}")
    if len(pathology_rows) > 0:
        print("  Sample NPIs with this specialty:")
        for _, row in pathology_rows[['NPICode', 'AddressName']].head(5).iterrows():
            print(f"    - {row['NPICode']}: {row['AddressName']}")
    
    # Remove pathology rows
    df = df[~pathology_mask].copy()
    print(f"After removing pathology specialty: {len(df)} records")
    
    # Fix AddressName formatting - remove space before comma
    print(f"\nFixing AddressName formatting (removing space before comma)...")
    df['AddressName'] = df['AddressName'].str.replace(r'\s+,', ',', regex=True)
    print(f"AddressName formatting fixed")
    
    # Move ID to DOCID (license should be in DOCID column)
    print(f"\nMoving license from ID to DOCID column...")
    df['DOCID'] = df['ID']
    df['ID'] = ''
    print(f"License moved to DOCID column")
    
    # Clean up licenses (now in DOCID column)
    print(f"\nCleaning up licenses...")
    
    # Count licenses before cleanup (non-empty)
    licenses_before = (df['DOCID'].notna() & (df['DOCID'] != '')).sum()
    
    # Blank licenses that are all 9s
    all_nines_mask = df['DOCID'].astype(str).str.match(r'^9+$', na=False)
    all_nines_count = all_nines_mask.sum()
    if all_nines_count > 0:
        df.loc[all_nines_mask, 'DOCID'] = pd.NA
        print(f"  Blanked {all_nines_count} licenses that were all 9s")
    
    # Blank licenses longer than 8 characters (excluding NaN and empty)
    valid_licenses = df['DOCID'].notna() & (df['DOCID'] != '')
    too_long_mask = valid_licenses & (df['DOCID'].astype(str).str.len() > 8)
    too_long_count = too_long_mask.sum()
    if too_long_count > 0:
        print(f"  Sample licenses > 8 characters:")
        for idx, row in df[too_long_mask][['NPICode', 'DOCID']].head(5).iterrows():
            print(f"    NPI {row['NPICode']}: {row['DOCID']} ({len(str(row['DOCID']))} chars)")
        df.loc[too_long_mask, 'DOCID'] = pd.NA
        print(f"  Blanked {too_long_count} licenses longer than 8 characters")
    
    licenses_after = (df['DOCID'].notna() & (df['DOCID'] != '')).sum()
    licenses_blanked = licenses_before - licenses_after
    print(f"  Total licenses blanked: {licenses_blanked}")
    print(f"  Valid licenses remaining: {licenses_after}")
    
    # Calculate final statistics
    removed_count = initial_count - len(df)
    print(f"\n{'='*60}")
    print(f"Summary:")
    print(f"  Initial records: {initial_count}")
    print(f"  Faulty NPIs removed: {len(blank_rows)}")
    print(f"  Pathology specialty removed: {len(pathology_rows)}")
    print(f"  Total records removed: {removed_count}")
    print(f"  Licenses cleaned (all 9s or >8 chars): {licenses_blanked}")
    print(f"  Final record count: {len(df)}")
    print(f"  Records with valid licenses: {licenses_after}")
    print(f"{'='*60}\n")
    
    # Save to Excel
    print(f"Saving cleaned data to {output_file}...")
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
    
    print(f"Complete! Clean file saved to {output_file}")
    
    return df


if __name__ == "__main__":
    # Get the script's directory to build relative paths
    script_dir = os.path.dirname(os.path.abspath(__file__))
    default_input = os.path.join(script_dir, '..', 'fetch_npi_data', '999993_Physician_Export_Complete.xlsx')
    default_output = os.path.join(script_dir, '999993_Physician_Export_Final.xlsx')
    
    parser = argparse.ArgumentParser(
        description='Clean up final export by removing invalid records.'
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
    
    args = parser.parse_args()
    
    cleanup_export(args.input_file, args.output_file)

