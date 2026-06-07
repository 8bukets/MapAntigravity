import json
import re

def parse_prompts(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    categories = re.split(r'Part \d+: (.*?)\n', content)

    parsed_prompts = []

    for i in range(1, len(categories), 2):
        category_name = categories[i].strip()
        category_content = categories[i+1]

        prompts_raw = re.split(r'Prompt \d+ — (.*?)\n', category_content)

        for j in range(1, len(prompts_raw), 2):
            prompt_title = prompts_raw[j].strip()
            prompt_text = prompts_raw[j+1].strip()

            # Find variables [VAR_NAME]
            # Use dict.fromkeys to preserve insertion order and eliminate duplicates
            variables = list(dict.fromkeys(re.findall(r'\[(.*?)\]', prompt_text)))

            parsed_prompts.append({
                "category": category_name,
                "title": prompt_title,
                "text": prompt_text,
                "variables": variables
            })

    return parsed_prompts

if __name__ == "__main__":
    prompts = parse_prompts('raw_prompts.txt')
    with open('prompts.json', 'w') as f:
        json.dump(prompts, f, indent=4)
    print(f"Successfully parsed {len(prompts)} prompts and saved to prompts.json")
