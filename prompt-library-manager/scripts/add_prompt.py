import json
import argparse
import os

def main():
    parser = argparse.ArgumentParser(description="Add a new prompt to prompts.json")
    parser.add_argument("--category", required=True, help="Category of the prompt")
    parser.add_argument("--title", required=True, help="Title of the prompt")
    parser.add_argument("--text", required=True, help="Text of the prompt")
    parser.add_argument("--variables", nargs="*", help="List of variables", default=[])

    args = parser.parse_args()

    # Path is relative to the root of the repo
    prompts_path = os.path.join(os.path.dirname(__file__), "..", "..", "prompts.json")

    try:
        with open(prompts_path, "r") as f:
            prompts = json.load(f)
    except FileNotFoundError:
        prompts = []

    new_prompt = {
        "category": args.category,
        "title": args.title,
        "text": args.text,
        "variables": args.variables
    }

    prompts.append(new_prompt)

    with open(prompts_path, "w") as f:
        json.dump(prompts, f, indent=4)

    print(f"Added new prompt: {args.title}")

if __name__ == "__main__":
    main()
