import argparse
import os
import re
import subprocess
import sys

def main():
    parser = argparse.ArgumentParser(description="Add a new prompt to raw_prompts.txt and parse it")
    parser.add_argument("--category", required=True, help="Category of the prompt")
    parser.add_argument("--title", required=True, help="Title of the prompt")
    parser.add_argument("--text", required=True, help="Text of the prompt")

    args = parser.parse_args()

    # Paths
    base_dir = os.path.join(os.path.dirname(__file__), "..", "..")
    raw_prompts_path = os.path.join(base_dir, "raw_prompts.txt")
    parse_script_path = os.path.join(base_dir, "prompt-library-manager", "scripts", "parse_prompts.py")

    with open(raw_prompts_path, "r") as f:
        content = f.read()

    # Count how many prompts there are to determine the next number
    matches = re.findall(r'Prompt (\d+) —', content)
    if matches:
        next_num = max([int(m) for m in matches]) + 1
    else:
        next_num = 1

    category_pattern = r'Part \d+: (.*?)\n'
    existing_categories = re.findall(category_pattern, content)

    append_text = ""

    if not existing_categories or existing_categories[-1].strip() != args.category:
        part_matches = re.findall(r'Part (\d+):', content)
        next_part = max([int(m) for m in part_matches]) + 1 if part_matches else 1
        append_text += f"\nPart {next_part}: {args.category}\n"

    append_text += f"\nPrompt {next_num} — {args.title}\n{args.text}\n"

    with open(raw_prompts_path, "a") as f:
        f.write(append_text)

    print(f"Appended Prompt {next_num} to raw_prompts.txt")

    # Run parse_prompts.py
    print("Running parse_prompts.py...")
    # Change working directory so parse_prompts finds raw_prompts.txt in its CWD
    subprocess.run([sys.executable, "prompt-library-manager/scripts/parse_prompts.py"], cwd=base_dir, check=True)

if __name__ == "__main__":
    main()
