# Terraform project import tool

This tool takes a local terraform project and imports it into Terraform enterprise & github


# Usage
```
 -p PROJECT_DIR : Required. relative or absolute path to the project
 [-c CREDS_FILE] : Optional. json file with credentails to set in TFE. default None
 [-o TFE_ORG] : Optional. Name of the Terraform enterprise organization. default cloudshiftstrategies
 [-g GH_ORG] : Optional. Name of the GitHub user or organization. default: peterb154

Requires that tools: hub tfe git jq all be installed and in PATH
assumes that user has passwordless github access using ssh keys and TFE_TOKEN env is set
assumes that GitHub organization is already linked to TFE organization
```

# Example creds file
```json
[
	{"Name": "AWS_ACCESS_KEY_ID", "Value":"ABC123"},
	{"Name": "AWS_SECRET_ACCESS_KEY", "Value": "DEF456", "Sensitive": "true"}
]
```
Note: this project's .gitignore excludes files suffixed with .secrets
