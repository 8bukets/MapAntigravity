import json
import os
import re

def slugify(text):
    # Convert to lowercase
    text = text.lower()
    # Replace anything not alphanumeric with hyphens
    text = re.sub(r'[^a-z0-9]+', '-', text)
    # Remove leading and trailing hyphens
    text = text.strip('-')
    # Truncate to max 64 characters per spec
    return text[:64].strip('-')

def create_skills_from_prompts(prompts_file='prompts.json', output_dir='agent-skills'):
    with open(prompts_file, 'r') as f:
        prompts = json.load(f)

    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    for prompt in prompts:
        title = prompt.get('title', 'untitled')
        text = prompt.get('text', '')
        variables = prompt.get('variables', [])

        name = slugify(title)
        if not name:
            continue

        skill_dir = os.path.join(output_dir, name)
        if not os.path.exists(skill_dir):
            os.makedirs(skill_dir)

        # Create SKILL.md
        skill_md_path = os.path.join(skill_dir, 'SKILL.md')

        description = f"Expert prompt for: {title}"
        if len(description) > 1024:
            description = description[:1021] + "..."

        with open(skill_md_path, 'w') as f:
            f.write("---\n")
            f.write(f"name: {name}\n")
            f.write(f"description: \"{description}\"\n")
            f.write("---\n\n")

            f.write(f"# {title}\n\n")
            if variables:
                f.write("## Variables\n")
                f.write("This prompt requires the following variables to be filled in:\n")
                for var in variables:
                    f.write(f"- `[{var}]`\n")
                f.write("\n")

            f.write("## Instructions\n\n")
            f.write(f"```text\n{text}\n```\n")

if __name__ == '__main__':
    create_skills_from_prompts()
    print("Agent Skills successfully generated!")
