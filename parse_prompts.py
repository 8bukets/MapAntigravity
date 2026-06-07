import json
import re

def parse_prompts(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    categories = re.split(r'Part \d+: (.*?)\n', content)

    # Categories will have elements:
    # categories[0] = ""
    # categories[1] = "Content Creation (Prompts 1–10)"
    # categories[2] = "... prompt texts ..."

    parsed_prompts = []

    for i in range(1, len(categories), 2):
        category_name = categories[i].strip()
        category_content = categories[i+1]

        # Splitting prompts within a category
        # Assumes prompts start with "Prompt X — Title"
        prompts_raw = re.split(r'Prompt \d+ — (.*?)\n', category_content)

        # prompts_raw[0] = "" (or trailing text from before)
        # prompts_raw[1] = "Title"
        # prompts_raw[2] = "... text ..."

        for j in range(1, len(prompts_raw), 2):
            prompt_title = prompts_raw[j].strip()
            prompt_text = prompts_raw[j+1].strip()

            # Find variables [VAR_NAME]
            # Use regex to find all text inside brackets
            variables = list(set(re.findall(r'\[(.*?)\]', prompt_text)))

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
