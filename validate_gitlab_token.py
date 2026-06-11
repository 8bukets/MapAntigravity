import os
import json
import urllib.request
import urllib.error
import sys

def validate_gitlab_token(token):
    headers = {
        "PRIVATE-TOKEN": token
    }

    # Validate connection and get user info
    print("Validating token...")
    user_url = "https://gitlab.com/api/v4/user"

    try:
        req = urllib.request.Request(user_url, headers=headers)
        with urllib.request.urlopen(req) as response:
            if response.status == 200:
                user_info = json.loads(response.read().decode())
                print(f"Connection successful!")
                print(f"Authenticated as: {user_info.get('username')} ({user_info.get('name')})")
            else:
                print(f"Unexpected error: HTTP {response.status}")
                return False

        # Get collaboration details (projects)
        print("\nFetching collaboration details (projects)...")
        projects_url = "https://gitlab.com/api/v4/projects?membership=true"
        req = urllib.request.Request(projects_url, headers=headers)
        with urllib.request.urlopen(req) as response:
            if response.status == 200:
                projects = json.loads(response.read().decode())
                print(f"Found {len(projects)} projects you are collaborating on:")
                for p in projects:
                    print(f" - {p.get('name')} (Visibility: {p.get('visibility')}, Path: {p.get('path_with_namespace')})")
            else:
                print(f"Failed to fetch projects: HTTP {response.status}")

        return True
    except urllib.error.HTTPError as e:
        if e.code == 401:
            print("Authentication failed: Invalid token.")
        else:
            print(f"HTTP Error {e.code}: {e.reason}")
        return False
    except urllib.error.URLError as e:
        print(f"Network error occurred: {e.reason}")
        return False

if __name__ == "__main__":
    # Get token from environment variable or command-line argument
    if len(sys.argv) > 1:
        TOKEN = sys.argv[1]
    else:
        TOKEN = os.environ.get("GITLAB_TOKEN")

    if not TOKEN:
        print("Error: Please provide a GitLab token.")
        print("Usage: python3 validate_gitlab_token.py <token>")
        print("Or set the GITLAB_TOKEN environment variable.")
        sys.exit(1)

    validate_gitlab_token(TOKEN)
