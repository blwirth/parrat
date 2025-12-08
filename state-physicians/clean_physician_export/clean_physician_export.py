#!/usr/bin/env python3
"""
Script to transform paired NPI and License columns into individual rows.
Takes an Excel file with paired columns and creates a tidy format with one row per NPI-License pair.
"""

import pandas as pd
import sys
import argparse

def tidy_physician_export(input_file, output_file, use_majority=True):
    """
    Transform paired NPI and License columns into individual rows.
    
    Args:
        input_file: Path to input Excel file
        output_file: Path to output Excel file
        use_majority: If True, keep only majority license for NPIs with multiple licenses
    """
    # Read the input Excel file
    print(f"Reading {input_file}...")
    df = pd.read_excel(input_file)
    
    # Define the column pairs (NPI, License)
    column_pairs = [
        ('NPIPHYSMAN', 'PHYSMANAGI'),
        ('NPIPHYSFUP', 'PHYSFUP'),
        ('NPIPHYSPRI', 'PHYSPRISUR'),
        ('NPIPHYS3', 'PHYS3'),
        ('NPIPHYS4', 'PHYS4')
    ]
    
    # Create a list to store all the transformed rows
    rows = []
    
    # Process each pair of columns
    for npi_col, license_col in column_pairs:
        # Extract non-null pairs
        pair_df = df[[npi_col, license_col]].copy()
        pair_df.columns = ['NPI', 'License']
        
        # Remove rows where both NPI and License are null
        pair_df = pair_df.dropna(how='all')
        
        # Convert to strings and clean
        pair_df['NPI'] = pair_df['NPI'].astype(str).str.strip()
        pair_df['License'] = pair_df['License'].astype(str).str.strip()
        
        # Remove any 'nan' strings that came from converting NaN to string
        pair_df = pair_df.replace('nan', pd.NA)
        
        # Add to the list
        rows.append(pair_df)
    
    # Combine all rows
    print("Combining all pairs into single dataframe...")
    result_df = pd.concat(rows, ignore_index=True)
    
    # Remove any rows where NPI or License is still null
    print(f"Total rows before removing nulls: {len(result_df)}")
    result_df = result_df.dropna(subset=['NPI', 'License'])
    print(f"Total rows after removing nulls: {len(result_df)}")
    
    # Clean strings - remove any .0 from numeric strings and ensure all are strings
    print("Cleaning string values...")
    result_df['NPI'] = result_df['NPI'].str.replace(r'\.0$', '', regex=True)
    result_df['License'] = result_df['License'].str.replace(r'\.0$', '', regex=True)
    
    # Filter out invalid NPIs
    print("Filtering out invalid NPIs...")
    before_filter = len(result_df)
    
    # Remove NPIs with less than 10 digits
    result_df = result_df[result_df['NPI'].str.len() >= 10]
    
    # Remove NPIs that are all 9s
    result_df = result_df[~result_df['NPI'].str.match(r'^9+$')]
    
    after_filter = len(result_df)
    print(f"Removed {before_filter - after_filter} rows with invalid NPIs")
    
    # Count occurrences BEFORE deduplication for majority logic
    print(f"Counting license occurrences for majority logic...")
    license_counts = result_df.groupby(['NPI', 'License']).size().reset_index(name='count')
    
    # Deduplicate on NPI + License combination
    print(f"Deduplicating on NPI + License combination...")
    before_dedup = len(result_df)
    result_df = result_df.drop_duplicates(subset=['NPI', 'License'])
    after_dedup = len(result_df)
    print(f"Removed {before_dedup - after_dedup} duplicate rows")
    
    # Merge the counts back
    result_df = result_df.merge(license_counts, on=['NPI', 'License'], how='left')
    
    # Handle NPIs with multiple licenses using majority logic
    if use_majority:
        print("\nApplying majority license logic...")
        before_majority = len(result_df)
        
        # Find NPIs with multiple licenses
        npi_counts = result_df.groupby('NPI').size()
        npis_with_multiple = npi_counts[npi_counts > 1].index.tolist()
        
        if npis_with_multiple:
            print(f"Found {len(npis_with_multiple)} NPIs with multiple licenses")
            
            rows_to_keep = []
            npis_resolved = 0
            npis_no_majority = 0
            
            # Process each NPI
            for npi in result_df['NPI'].unique():
                npi_rows = result_df[result_df['NPI'] == npi]
                
                if len(npi_rows) == 1:
                    # Only one license, keep it
                    rows_to_keep.append(npi_rows[['NPI', 'License']])
                else:
                    # Multiple licenses - find majority based on occurrence count
                    max_count = npi_rows['count'].max()
                    majority_rows = npi_rows[npi_rows['count'] == max_count]
                    
                    if len(majority_rows) == 1:
                        # Clear majority - keep only the majority license
                        majority_license = majority_rows.iloc[0]['License']
                        total_occurrences = npi_rows['count'].sum()
                        rows_to_keep.append(majority_rows[['NPI', 'License']])
                        npis_resolved += 1
                        print(f"  NPI {npi}: Kept majority license {majority_license} (appeared {max_count} times out of {total_occurrences} total)")
                    else:
                        # No clear majority (tie) - keep one row with blank license
                        tied_licenses = majority_rows['License'].tolist()
                        blank_row = pd.DataFrame({'NPI': [npi], 'License': ['']})
                        rows_to_keep.append(blank_row)
                        npis_no_majority += 1
                        print(f"  NPI {npi}: No clear majority (tie at {max_count} occurrences between: {', '.join(tied_licenses)}), set license to blank")
            
            result_df = pd.concat(rows_to_keep, ignore_index=True)
            after_majority = len(result_df)
            
            print(f"\nMajority logic summary:")
            print(f"  NPIs resolved to single license: {npis_resolved}")
            print(f"  NPIs with no clear majority (license set to blank): {npis_no_majority}")
            print(f"  Rows removed: {before_majority - after_majority}")
        else:
            print("No NPIs with multiple licenses found")
    else:
        # If not using majority logic, just drop the count column
        result_df = result_df[['NPI', 'License']]
    
    # Ensure we only have NPI and License columns
    if 'count' in result_df.columns:
        result_df = result_df[['NPI', 'License']]
    
    # Sort by NPI
    print("\nSorting by NPI...")
    result_df = result_df.sort_values('NPI').reset_index(drop=True)
    
    # Analyze NPIs with multiple licenses
    print("\nAnalyzing NPIs with multiple licenses...")
    npi_license_counts = result_df.groupby('NPI').size()
    npis_with_multiple_licenses = (npi_license_counts > 1).sum()
    total_unique_npis = npi_license_counts.nunique()
    max_licenses = npi_license_counts.max()
    
    # Save to Excel with proper formatting (save as strings to preserve leading zeros)
    print(f"Saving to {output_file}...")
    with pd.ExcelWriter(output_file, engine='openpyxl') as writer:
        result_df.to_excel(writer, index=False, sheet_name='Sheet1')
        # Get the worksheet
        worksheet = writer.sheets['Sheet1']
        # Format NPI and License columns as text to preserve leading zeros
        for row in range(2, len(result_df) + 2):  # Start at 2 (after header)
            worksheet[f'A{row}'].number_format = '@'  # Text format for NPI
            worksheet[f'B{row}'].number_format = '@'  # Text format for License
    
    print(f"Complete! Final dataset has {len(result_df)} rows")
    print(f"\nSummary:")
    print(f"  Input file: {input_file}")
    print(f"  Output file: {output_file}")
    print(f"  Total unique NPI-License pairs: {len(result_df)}")
    print(f"  Total unique NPIs: {len(npi_license_counts)}")
    print(f"  NPIs with multiple licenses: {npis_with_multiple_licenses}")
    print(f"  NPIs with single license: {len(npi_license_counts) - npis_with_multiple_licenses}")
    print(f"  Maximum licenses for a single NPI: {max_licenses}")
    
    return result_df


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description='Transform paired NPI and License columns into individual rows.'
    )
    parser.add_argument(
        'input_file',
        nargs='?',
        default='999993_Physician_Export.xlsx',
        help='Input Excel file (default: 999993_Physician_Export.xlsx)'
    )
    parser.add_argument(
        'output_file',
        nargs='?',
        default='999993_Physician_Export_Clean.xlsx',
        help='Output Excel file (default: 999993_Physician_Export_Clean.xlsx)'
    )
    parser.add_argument(
        '--majority',
        action='store_true',
        default=True,
        help='Use majority license for NPIs with multiple licenses (default: True)'
    )
    parser.add_argument(
        '--no-majority',
        dest='majority',
        action='store_false',
        help='Keep all licenses for NPIs with multiple licenses'
    )
    
    args = parser.parse_args()
    
    tidy_physician_export(args.input_file, args.output_file, use_majority=args.majority)

