import argparse
import os
import re
import yaml
import sys

def validate_skill(skill_dir):
    skill_dir = os.path.normpath(skill_dir)
    if not os.path.isdir(skill_dir):
        print(f"Error: {skill_dir} is not a valid directory.")
        return False

    skill_name_dir = os.path.basename(skill_dir)
    skill_md_path = os.path.join(skill_dir, "SKILL.md")

    if not os.path.exists(skill_md_path):
        print(f"Error: SKILL.md not found in {skill_dir}")
        return False

    with open(skill_md_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Extract frontmatter
    # Frontmatter must start with --- on the first line
    # and end with ---
    if not content.startswith('---'):
        print("Error: SKILL.md must start with YAML frontmatter bounded by ---")
        return False

    parts = content.split('---', 2)
    if len(parts) < 3:
        print("Error: SKILL.md frontmatter must be bounded by ---")
        return False

    frontmatter_str = parts[1]

    try:
        frontmatter = yaml.safe_load(frontmatter_str)
    except yaml.YAMLError as e:
        print(f"Error parsing YAML frontmatter: {e}")
        return False

    if not isinstance(frontmatter, dict):
        print("Error: Frontmatter must be a YAML object/dictionary")
        return False

    errors = []

    # Validate 'name'
    if 'name' not in frontmatter:
        errors.append("Missing required field: 'name'")
    else:
        name = str(frontmatter['name'])
        if len(name) < 1 or len(name) > 64:
            errors.append(f"'name' length must be between 1 and 64 characters. Got {len(name)}.")
        if not re.match(r'^[a-z0-9-]+$', name):
            errors.append("'name' may only contain lowercase alphanumeric characters and hyphens.")
        if name.startswith('-') or name.endswith('-'):
            errors.append("'name' must not start or end with a hyphen.")
        if '--' in name:
            errors.append("'name' must not contain consecutive hyphens.")
        if name != skill_name_dir:
            errors.append(f"'name' ('{name}') must match the parent directory name ('{skill_name_dir}').")

    # Validate 'description'
    if 'description' not in frontmatter:
        errors.append("Missing required field: 'description'")
    else:
        desc = str(frontmatter['description']).strip()
        if len(desc) < 1:
            errors.append("'description' must be non-empty.")
        if len(desc) > 1024:
            errors.append(f"'description' length must be max 1024 characters. Got {len(desc)}.")

    # Validate 'compatibility'
    if 'compatibility' in frontmatter and frontmatter['compatibility'] is not None:
        comp = str(frontmatter['compatibility'])
        if len(comp) > 500:
            errors.append(f"'compatibility' length must be max 500 characters. Got {len(comp)}.")

    # Validate 'metadata'
    if 'metadata' in frontmatter and frontmatter['metadata'] is not None:
        meta = frontmatter['metadata']
        if not isinstance(meta, dict):
            errors.append("'metadata' must be a mapping of keys to values.")
        else:
            for k, v in meta.items():
                if not isinstance(k, str) or not isinstance(v, str):
                    errors.append("'metadata' must be a map from string keys to string values.")
                    break

    # Validate 'allowed-tools'
    if 'allowed-tools' in frontmatter and frontmatter['allowed-tools'] is not None:
        tools = frontmatter['allowed-tools']
        if not isinstance(tools, str):
            errors.append("'allowed-tools' must be a space-separated string.")

    if errors:
        print("Validation errors found:")
        for error in errors:
            print(f"- {error}")
        return False

    print(f"Success: {skill_md_path} is valid.")
    return True

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Validate Agent Skills directory.')
    parser.add_argument('skill_dir', type=str, help='Path to the skill directory')
    args = parser.parse_args()

    if validate_skill(args.skill_dir):
        sys.exit(0)
    else:
        sys.exit(1)
