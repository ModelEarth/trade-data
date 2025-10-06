#!/usr/bin/env python3
"""
Ensure all trade.csv files have proper trade_id header.

This script scans all trade.csv files in the repository and ensures they have
the correct header format with trade_id as the first column. It can validate
or fix headers across all year/country/flow combinations.

Usage:
    python scripts/ensure_trade_id_header.py --check        # Check headers only
    python scripts/ensure_trade_id_header.py --fix          # Fix missing/incorrect headers
    python scripts/ensure_trade_id_header.py --year 2019    # Process specific year only
"""

import argparse
import csv
from pathlib import Path
import sys


EXPECTED_HEADER = ['trade_id', 'year', 'region1', 'region2', 'industry1', 'industry2', 'amount']


def find_trade_csv_files(base_dir: Path, year: str = None) -> list[Path]:
    """Find all trade.csv files in the repository structure."""
    if year:
        pattern = f"year/{year}/**/trade.csv"
    else:
        pattern = "year/**/trade.csv"

    return sorted(base_dir.glob(pattern))


def check_header(csv_file: Path) -> tuple[bool, list[str]]:
    """
    Check if CSV file has correct header.

    Returns:
        (is_correct, actual_header)
    """
    try:
        with open(csv_file, 'r', encoding='utf-8') as f:
            reader = csv.reader(f)
            actual_header = next(reader)
            return actual_header == EXPECTED_HEADER, actual_header
    except Exception as e:
        print(f"Error reading {csv_file}: {e}", file=sys.stderr)
        return False, []


def fix_header(csv_file: Path, dry_run: bool = False) -> bool:
    """
    Fix the header of a CSV file if needed.

    Returns:
        True if file was modified, False otherwise
    """
    is_correct, actual_header = check_header(csv_file)

    if is_correct:
        return False

    if dry_run:
        print(f"Would fix: {csv_file}")
        print(f"  Current: {actual_header}")
        print(f"  Expected: {EXPECTED_HEADER}")
        return True

    # Read all rows
    try:
        with open(csv_file, 'r', encoding='utf-8') as f:
            reader = csv.reader(f)
            next(reader)  # Skip current header
            rows = list(reader)

        # Write with correct header
        with open(csv_file, 'w', encoding='utf-8', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(EXPECTED_HEADER)
            writer.writerows(rows)

        print(f"Fixed: {csv_file}")
        return True

    except Exception as e:
        print(f"Error fixing {csv_file}: {e}", file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser(
        description='Ensure all trade.csv files have proper trade_id header'
    )
    parser.add_argument(
        '--check',
        action='store_true',
        help='Check headers without modifying files'
    )
    parser.add_argument(
        '--fix',
        action='store_true',
        help='Fix incorrect headers'
    )
    parser.add_argument(
        '--year',
        type=str,
        help='Process only specified year (e.g., 2019)'
    )

    args = parser.parse_args()

    if not args.check and not args.fix:
        parser.error('Must specify either --check or --fix')

    base_dir = Path(__file__).parent.parent
    csv_files = find_trade_csv_files(base_dir, args.year)

    if not csv_files:
        print("No trade.csv files found")
        return 0

    print(f"Found {len(csv_files)} trade.csv file(s)")
    print()

    correct_count = 0
    incorrect_count = 0
    fixed_count = 0

    for csv_file in csv_files:
        relative_path = csv_file.relative_to(base_dir)

        if args.check:
            is_correct, actual_header = check_header(csv_file)
            if is_correct:
                correct_count += 1
                print(f"✓ {relative_path}")
            else:
                incorrect_count += 1
                print(f"✗ {relative_path}")
                print(f"  Current: {actual_header}")
                print(f"  Expected: {EXPECTED_HEADER}")

        elif args.fix:
            was_fixed = fix_header(csv_file, dry_run=False)
            if was_fixed:
                fixed_count += 1
                incorrect_count += 1
            else:
                correct_count += 1

    print()
    print(f"Summary:")
    print(f"  Correct: {correct_count}")
    print(f"  Incorrect: {incorrect_count}")
    if args.fix:
        print(f"  Fixed: {fixed_count}")

    return 1 if incorrect_count > 0 else 0


if __name__ == '__main__':
    sys.exit(main())
