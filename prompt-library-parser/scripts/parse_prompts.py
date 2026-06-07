#!/usr/bin/env python3
import json
import re
import sys
import os

def parse_prompts(filepath):
    if not os.path.exists(filepath):
        print(f"Error: Raw prompts file not found at {filepath}")
        sys.exit(1)

    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    categories = re.split(r'Part \d+: (.*?)\n', content)

    parsed_prompts = []

    for i in range(1, len(categories), 2):
        category_name = categories[i].strip()
        category_content = categories[i+1]

        # Splitting prompts within a category
        prompts_raw = re.split(r'Prompt \d+ — (.*?)\n', category_content)

        for j in range(1, len(prompts_raw), 2):
            prompt_title = prompts_raw[j].strip()
            prompt_text = prompts_raw[j+1].strip()

            # Find variables [VAR_NAME]
            variables = list(set(re.findall(r'\[(.*?)\]', prompt_text)))

            parsed_prompts.append({
                "category": category_name,
                "title": prompt_title,
                "text": prompt_text,
                "variables": variables
            })

    return parsed_prompts

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 parse_prompts.py <input_raw_text> <output_json>")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]

    print(f"Parsing prompts from {input_file}...")
    prompts = parse_prompts(input_file)

    print(f"Writing structured prompts to {output_file}...")
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(prompts, f, indent=4)

    print(f"Successfully parsed {len(prompts)} prompts and saved to {output_file}")

if __name__ == "__main__":
    main()
