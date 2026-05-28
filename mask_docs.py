import json
import os

CATALOG_PATH = "target/catalog.json"

if __name__ == '__main__':

    if os.path.exists(CATALOG_PATH):
        with open(CATALOG_PATH, "r") as f:
            data = json.load(f)

        # Loop through all database nodes (tables/views) in the catalog
        for node_id, node_data in data.get("nodes", {}).items():
            if "metadata" in node_data and "owner" in node_data["metadata"]:
                # Check if the owner field exists, and overwrite it safely
                node_data["metadata"]["owner"] = "dev"

        with open(CATALOG_PATH, "w") as f:
            json.dump(data, f, indent=4)

        print("Successfully obfuscated database owner names in dbt documentation!")
    else:
        print("catalog.json not found. Run 'dbt docs generate' first.")
