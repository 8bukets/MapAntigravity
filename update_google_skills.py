import os
import subprocess
import shutil
import tempfile
import yaml
import re

REPO_URL = "https://github.com/google/skills"
RAW_PROMPTS_FILE = "raw_prompts.txt"
PARSE_SCRIPT = "parse_prompts.py"
CATEGORY_MARKER = "Part 6: Google Agent Skills"

def parse_frontmatter(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Extract frontmatter between ---
    match = re.search(r'^---\n(.*?)\n---', content, re.DOTALL)
    if not match:
        return None

    frontmatter_text = match.group(1)
    try:
        data = yaml.safe_load(frontmatter_text)
        return data
    except yaml.YAMLError:
        return None

def main():
    print("Cloning repository...")
    with tempfile.TemporaryDirectory() as temp_dir:
        subprocess.run(["git", "clone", "--depth", "1", REPO_URL, temp_dir], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        skills = []
        for root, dirs, files in os.walk(temp_dir):
            for file in files:
                if file == "SKILL.md":
                    file_path = os.path.join(root, file)
                    frontmatter = parse_frontmatter(file_path)
                    if frontmatter and 'name' in frontmatter and 'description' in frontmatter:
                        skills.append(frontmatter)

        if not skills:
            print("No skills found.")
            return

        print(f"Found {len(skills)} skills.")

        # Read existing raw_prompts.txt
        with open(RAW_PROMPTS_FILE, 'r', encoding='utf-8') as f:
            lines = f.readlines()

        # Find where to truncate
        truncate_idx = len(lines)
        for i, line in enumerate(lines):
            if line.startswith("Part 6: Google Agent Skills"):
                truncate_idx = i
                break

        # Keep original content up to Part 6
        original_content = "".join(lines[:truncate_idx]).strip()

        # Generate new Part 6 content
        new_prompts = [
            "\n\nPart 6: Google Agent Skills (Prompts 51–{})".format(50 + len(skills))
        ]

        for idx, skill in enumerate(sorted(skills, key=lambda x: x['name']), start=51):
            name = skill['name']
            description = skill['description'].strip().replace("\n", " ")

            # Format the title nicely
            title = name.replace('-', ' ').title()

            prompt_text = f"""
Prompt {idx} — {title}
You are a Google Cloud and Agent Skills expert.

I need your help utilizing the following skill: {name}
Skill description: {description}

Please provide a detailed guide, execution plan, or code snippet based on my requirements.

My specific task: [SPECIFIC_TASK]
Environment details: [ENVIRONMENT_DETAILS — e.g., "Python SDK", "Google Kubernetes Engine", "Production environment"]

Provide step-by-step instructions and any necessary code or CLI commands."""

            new_prompts.append(prompt_text.strip())

        new_content = original_content + "\n\n" + "\n\n".join(new_prompts) + "\n"

        print("Updating raw_prompts.txt...")
        with open(RAW_PROMPTS_FILE, 'w', encoding='utf-8') as f:
            f.write(new_content)

        print("Running parse_prompts.py...")
        subprocess.run(["python3", PARSE_SCRIPT], check=True)

        print("Automation complete.")

if __name__ == "__main__":
    main()
