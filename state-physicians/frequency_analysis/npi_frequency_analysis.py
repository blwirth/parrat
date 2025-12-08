#!/usr/bin/env python3
"""
Analyze NPI frequency in the original export file.
Outputs NPI, Name, State, and number of appearances sorted by frequency.
"""

import pandas as pd
import argparse
import os


def analyze_npi_frequency(original_file, final_file, output_file):
    """
    Count how often each NPI appears in the original export file.
    
    Args:
        original_file: Path to original 999993_Physician_Export.xlsx
        final_file: Path to final cleaned file with names
        output_file: Path to output Excel file
    """
    print(f"Reading original export file: {original_file}...")
    original_df = pd.read_excel(original_file)
    
    print(f"Reading final clean file: {final_file}...")
    final_df = pd.read_excel(final_file)
    
    # The original file has 5 NPI columns (paired with licenses)
    npi_columns = [
        'NPIPHYSMAN',
        'NPIPHYSFUP',
        'NPIPHYSPRI',
        'NPIPHYS3',
        'NPIPHYS4'
    ]
    
    print(f"\nCounting NPI occurrences across {len(npi_columns)} columns...")
    
    # Collect all NPIs from all columns
    all_npis = []
    for col in npi_columns:
        # Convert to string and clean
        npis = original_df[col].astype(str).str.strip()
        # Remove NaN strings and blanks
        npis = npis[~npis.isin(['nan', '', 'NaN'])]
        all_npis.extend(npis.tolist())
    
    print(f"Total NPI occurrences (including duplicates): {len(all_npis)}")
    
    # Count frequency of each NPI
    npi_counts = pd.Series(all_npis).value_counts().reset_index()
    npi_counts.columns = ['NPI', 'Appearances']
    
    print(f"Unique NPIs found: {len(npi_counts)}")
    
    # Clean NPIs - remove .0 and convert to string for matching
    npi_counts['NPI'] = npi_counts['NPI'].astype(str).str.replace(r'\.0$', '', regex=True)
    final_df['NPICode'] = final_df['NPICode'].astype(str).str.replace(r'\.0$', '', regex=True)
    
    # Merge with final file to get name and state
    result_df = npi_counts.merge(
        final_df[['NPICode', 'AddressName', 'STATE']],
        left_on='NPI',
        right_on='NPICode',
        how='left'
    )
    
    # Clean up columns
    result_df = result_df[['NPI', 'AddressName', 'STATE', 'Appearances']].copy()
    result_df.columns = ['NPI', 'Provider Name', 'State', 'Appearances']
    
    # Sort by appearances (descending)
    result_df = result_df.sort_values('Appearances', ascending=False).reset_index(drop=True)
    
    # Statistics
    total_in_final = result_df['Provider Name'].notna().sum()
    not_in_final = len(result_df) - total_in_final
    
    print(f"\nMatching with final clean file:")
    print(f"  NPIs in final file: {total_in_final}")
    print(f"  NPIs not in final file: {not_in_final}")
    
    print(f"\nFrequency statistics:")
    print(f"  Max appearances: {result_df['Appearances'].max()}")
    print(f"  Min appearances: {result_df['Appearances'].min()}")
    print(f"  Average appearances: {result_df['Appearances'].mean():.1f}")
    print(f"  Median appearances: {result_df['Appearances'].median():.0f}")
    
    print(f"\nTop 10 most frequent NPIs:")
    for idx, row in result_df.head(10).iterrows():
        name = row['Provider Name'] if pd.notna(row['Provider Name']) else 'Not in final file'
        state = row['State'] if pd.notna(row['State']) else 'N/A'
        print(f"  {row['NPI']}: {name} ({state}) - {row['Appearances']} appearances")
    
    # Save to Excel
    print(f"\nSaving frequency analysis to {output_file}...")
    with pd.ExcelWriter(output_file, engine='openpyxl') as writer:
        result_df.to_excel(writer, index=False, sheet_name='NPI Frequency')
        worksheet = writer.sheets['NPI Frequency']
        
        # Format NPI column as text
        for row_num in range(2, len(result_df) + 2):
            worksheet[f'A{row_num}'].number_format = '@'  # NPI
    
    print(f"\nComplete! Frequency analysis saved to {output_file}")
    print(f"\nSummary:")
    print(f"  Total unique NPIs: {len(result_df)}")
    print(f"  NPIs with provider info: {total_in_final}")
    print(f"  Total records sorted by frequency")
    
    return result_df


if __name__ == "__main__":
    # Get the script's directory to build relative paths
    script_dir = os.path.dirname(os.path.abspath(__file__))
    default_original = os.path.join(script_dir, '..', 'clean_physician_export', '999993_Physician_Export.xlsx')
    default_final = os.path.join(script_dir, '..', 'final_cleanup', '999993_Physician_Export_Final.xlsx')
    default_output = os.path.join(script_dir, 'NPI_Frequency_Analysis.xlsx')
    
    parser = argparse.ArgumentParser(
        description='Analyze NPI frequency in original export file.'
    )
    parser.add_argument(
        'original_file',
        nargs='?',
        default=default_original,
        help='Original export Excel file'
    )
    parser.add_argument(
        'final_file',
        nargs='?',
        default=default_final,
        help='Final cleaned Excel file with provider names'
    )
    parser.add_argument(
        'output_file',
        nargs='?',
        default=default_output,
        help='Output Excel file for frequency analysis'
    )
    
    args = parser.parse_args()
    
    analyze_npi_frequency(args.original_file, args.final_file, args.output_file)

