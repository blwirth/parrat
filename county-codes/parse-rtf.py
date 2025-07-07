import re
import json

def clean_rtf_text(raw_text):
    """
    Clean RTF text that has formatting codes breaking up words
    Example: SOUTH\expnd-1\expndtw-4  \expnd0\expndtw0 ACWORTH,\expnd-1\expndtw-3  \expnd-1\expndtw-5 NH
    Should become: SOUTH ACWORTH,NH
    """
    # Start with the raw text
    text = raw_text.strip()
    
    # Step 1: Replace formatting codes with a single space
    # Handle the specific pattern: \expnd-1\expndtw-4  \expnd0\expndtw0
    text = re.sub(r'\\expnd-?\d+\\expndtw-?\d+\s*', ' ', text)
    
    # Step 2: Remove any remaining RTF control codes
    text = re.sub(r'\\[a-zA-Z]+\d*\s*', ' ', text)
    
    # Step 3: Clean up spacing
    text = re.sub(r'\s+', ' ', text)
    text = text.strip()
    
    return text

def extract_table_between_bounds(rtf_content):
    """
    Extract the table section between ACWORTH (first) and WORDELL,NH (last)
    """
    # Find the start position (ACWORTH)
    acworth_pos = rtf_content.find('ACWORTH')
    if acworth_pos == -1:
        print("Could not find ACWORTH in the document")
        return ""
    
    # Find the end position (WORDELL,NH)
    wordell_pos = rtf_content.find('WORDELL,NH')
    if wordell_pos == -1:
        print("Could not find WORDELL,NH in the document")
        return ""
    
    if wordell_pos < acworth_pos:
        print("WORDELL appears before ACWORTH - unexpected order")
        return ""
    
    # Extract the section between these bounds
    # Go back a bit from ACWORTH to catch the row start
    table_start = max(0, acworth_pos - 1000)
    # Go forward a bit from WORDELL to catch the complete row
    table_end = min(len(rtf_content), wordell_pos + 1000)
    
    table_section = rtf_content[table_start:table_end]
    
    print(f"Extracted table section: {len(table_section)} characters")
    
    return table_section

def parse_nh_table_data(table_section):
    """
    Parse the NH town data from the extracted table section
    """
    parsed_data = []
    
    # Split by \row to get individual table rows
    rows = table_section.split('\\row')
    
    print(f"Found {len(rows)} potential rows in table section")
    
    for i, row in enumerate(rows):
        # Skip rows that don't contain NH town data
        if ',NH' not in row:
            continue
        
        # Special debugging for SOUTH ACWORTH
        if 'SOUTH' in row and 'ACWORTH' in row:
            print(f"\n=== DEBUGGING SOUTH ACWORTH ROW ===")
            print(f"Raw row content: {row[:500]}...")
        
        # Extract cell contents using a more comprehensive pattern
        # Look for content between charscalex100 and \cell
        # Need to capture everything including RTF codes, then clean it
        cell_pattern = r'\\charscalex100\s+([^}]+?)\\cell'
        cells = re.findall(cell_pattern, row)
        
        if not cells:
            # Try alternative pattern if first one doesn't work
            cell_pattern2 = r'\\charscalex100[^\\]*?([^}]+?)\\cell'
            cells = re.findall(cell_pattern2, row)
        
        # Debug SOUTH ACWORTH specifically
        if 'SOUTH' in row and 'ACWORTH' in row:
            print(f"Found {len(cells)} cells with pattern 1")
            for j, cell in enumerate(cells):
                print(f"  Raw cell {j}: {cell}")
                cleaned = clean_rtf_text(cell)
                print(f"  Cleaned cell {j}: '{cleaned}'")
        
        # Clean up the cell contents using our enhanced cleaner
        cleaned_cells = []
        for cell in cells:
            clean = clean_rtf_text(cell)
            
            # Only keep non-empty meaningful content
            if clean and len(clean) > 0:
                cleaned_cells.append(clean)
        
        # Debug: show what we found for the first few rows
        if i < 5 and len(cleaned_cells) > 0:
            print(f"Row {i} - Found {len(cleaned_cells)} cells: {cleaned_cells}")
        
        # We expect exactly 5 columns: Town Name, ZIP Name, ZIP Code, County, NHSCR Code
        if len(cleaned_cells) >= 5:
            town_name = cleaned_cells[0]
            zip_name = cleaned_cells[1] 
            zip_code = cleaned_cells[2]
            county = cleaned_cells[3]
            nhscr_code = cleaned_cells[4]
            
            # Validate that this looks like real NH town data
            if (town_name.endswith(',NH') and 
                zip_code.isdigit() and len(zip_code) == 5 and
                zip_code.startswith('0')):  # NH ZIP codes start with 0
                
                record = {
                    "townName": town_name,
                    "zipName": zip_name,
                    "zipCode": zip_code,
                    "county": county,
                    "nhscrCode": nhscr_code
                }
                parsed_data.append(record)
                
                # Debug: print first few valid records
                if len(parsed_data) <= 5:
                    print(f"Valid record {len(parsed_data)}: {record}")
    
    return parsed_data

def test_cleaner():
    """
    Test the RTF cleaner with your specific example
    """
    test_text = r"SOUTH\expnd-1\expndtw-4  \expnd0\expndtw0 ACWORTH,\expnd-1\expndtw-3  \expnd-1\expndtw-5 NH"
    cleaned = clean_rtf_text(test_text)
    print(f"Test input: {test_text}")
    print(f"Cleaned output: '{cleaned}'")
    print(f"Expected: 'SOUTH ACWORTH,NH'")
    return cleaned == "SOUTH ACWORTH,NH"

def main():
    input_file = "county-codes/input.rtf"
    output_file = "county-codes/nh_towns.jsonl"
    
    # Test the cleaner first
    print("Testing RTF cleaner...")
    if test_cleaner():
        print("✓ RTF cleaner test passed!")
    else:
        print("✗ RTF cleaner test failed!")
    
    try:
        with open(input_file, 'r', encoding='utf-8', errors='ignore') as f:
            rtf_content = f.read()
        
        print(f"\nRTF file size: {len(rtf_content)} characters")
        
        # Extract the table section between ACWORTH and WORDELL
        table_section = extract_table_between_bounds(rtf_content)
        
        if not table_section:
            print("Could not extract table section")
            return
        
        # Parse the data
        parsed_data = parse_nh_table_data(table_section)
        
        if parsed_data:
            # Remove duplicates while preserving order
            seen = set()
            unique_data = []
            for record in parsed_data:
                key = (record['townName'], record['zipName'], record['zipCode'])
                if key not in seen:
                    seen.add(key)
                    unique_data.append(record)
            
            print(f"\nSuccessfully parsed {len(unique_data)} unique records")
            
            # Write to JSONL file
            with open(output_file, 'w', encoding='utf-8') as f:
                for record in unique_data:
                    f.write(json.dumps(record) + '\n')
            
            print(f"Output written to {output_file}")
            
            # Show first few records
            print("\nFirst 10 records:")
            for i, record in enumerate(unique_data[:10]):
                print(f"{i+1}: {json.dumps(record)}")
        else:
            print("No valid records found")
    
    except FileNotFoundError:
        print(f"Error: Could not find file '{input_file}'")
        print("Please save your RTF content to 'input.rtf'")
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()