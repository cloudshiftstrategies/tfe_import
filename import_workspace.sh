#!/usr/bin/env bash

TFE_ORG=DOTCommInfrastructure
GH_ORG=DOTCommInfrastructure
EXES="hub tfe git jq"
# hub can be found at https://github.com/github/hub


print_usage(){
    echo "Usage: $0 -d PROJECT_DIR [-c CREDS_FILE] [-o TFE_ORG] [-g GH_ORG]" 1>&2;
    echo
    echo " -p PROJECT_DIR : Required. relative or absolute path to the project"
    echo " [-c CREDS_FILE] : Optional. json file with credentails to set in TFE. default None"
    echo " [-o TFE_ORG] : Optional. Name of the Terraform enterprise organization. default $TFE_ORG"
    echo " [-g GH_ORG] : Optional. Name of the GitHub user or organization. default: $GH_ORG"
    echo
    echo "Requires that tools: $EXES all be installed and in PATH"
    echo "assumes that user has passwordless github access using ssh keys and TFE_TOKEN env is set"
    echo "assumes that GitHub organization is already linked to TFE organization"
    exit 1;
}

if [ ! $1 ]; then
    usage
fi
while getopts ":p:c:o:g:h" opt; do
    case "${opt}" in
        p)
            PROJECT_DIR=${OPTARG}
            ;;
        c)
            CREDS_FILE=${OPTARG}
            ;;
        o)
            TFE_ORG=${OPTARG}
            ;;
        o)
            GH_ORG=${OPTARG}
            ;;
        h)
            print_usage
            exit 1
            ;;
        *)
            print_usage
            exit 1
            ;;
    esac
done

# Ensure required software is installed
for EXE in $EXES; do
  which hub > /dev/null
  if [ $? -ne 0 ]; then
    echo "ERROR: could not find executable: $EXE in path"
    exit 1
  fi
done

# Validate PROJECT_DIR
if [ ! -n $PROJECT_DIR ]; then
  echo "ERROR: missing required parameter -p PROJECT_DIR $PROJECT_DIR"
  print_usage
  exit 1
fi
if [ ! -d $PROJECT_DIR ]; then
  echo "ERROR: could not find PROJECT_DIR: $PROJECT_DIR"
  exit 1
fi
PROJECT_NAME=`basename $PROJECT_DIR`

# Validate CREDS_FILE
if [ -n $CREDS_FILE ]; then
  if [ ! -f $CREDS_FILE ]; then
    echo "ERROR: could not find CREDS_FILE: $CREDS_FILE"
    exit 1
  fi
  # Check to see if we have valid jason
  cat $CREDS_FILE | jq -e . > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    # jason is invalid
    echo "ERROR: invalid json in CREDS_FILE: $CREDS_FILE"
    exit 1
  fi
fi

set -e
echo "PROJECT_DIR : $PROJECT_DIR"
echo "TFE_ORG : $TFE_ORG"
echo "GH_ORG : $GH_ORG"
echo "PROJECT_NAME: $PROJECT_NAME"
echo "CREDS_FILE: $CREDS_FILE"
echo

IMPORT_DIR=`pwd`
TFE_WORKSPACE=$PROJECT_NAME

# Workspace name must be less than 50 chars
if [ ${#TFE_WORKSPACE} -gt 50 ]; then
    echo "TFE Workspace name must be less than 50 chars"
    echo "$TFE_WORKSPACE is ${#TFE_WORKSPACE} chars long"
    exit 1
fi

# GITHUB
# See if github repo already exists on github, will return error if not
set +e
hub ls-remote git@github.com:$GH_ORG/$PROJECT_NAME.git 2&>1 /dev/null
LS_RESULT=$?
set -e
if [ $LS_RESULT -eq 0 ]; then
    # Github Repo already exits. Delete it
    echo "Deleting existing GitHub repo $GH_ORG/$PROJECT_NAME ..."
    hub delete -y $GH_ORG/$PROJECT_NAME
fi
echo "Creating new private GitHub repo $GH_ORG/$PROJECT_NAME ..."
# Setup the directory
cd $PROJECT_DIR
touch README.md
cp $IMPORT_DIR/templates/gitignore.terraform .gitignore
# Remove the existing git info
if [ -d .git ]; then
  rm -rf .git
fi
# Initialize the repo
hub init > /dev/null
# Add the files and commit
git add . > /dev/null
git commit -m "first commit" > /dev/null
# Create the private repo on github.com
hub create -p $GH_ORG/$PROJECT_NAME > /dev/null
# Do the first push
git push --set-upstream origin master > /dev/null
cd $IMPORT_DIR

# TFE Workspace
# Create a new TFE workspace
if [ `tfe workspace list -tfe-org $TFE_ORG | grep -c $TFE_WORKSPACE` -gt 0 ]; then
    # TFE workspace already exists, delete it
    echo "Deleting existing TFE workspace -tfe-org $TFE_ORG -name $TFE_WORKSPACE ..."
    tfe workspace delete -name $TFE_ORG/$TFE_WORKSPACE
fi
echo "Creating new TFE workspace $TFE_ORG/$TFE_WORKSPACE linked to Github repo $GH_ORG/$PROJECT_NAME ..."
tfe workspace new -name $TFE_ORG/$TFE_WORKSPACE -vcs-id $GH_ORG/$PROJECT_NAME

# Source AWS env vars
if [ -n $CREDS_FILE ]; then
  echo "Reading AWS creds from $CREDS_FILE ..."
  for ROW in $(cat $CREDS_FILE | jq -r '.[] | @base64'); do
    _jq() {
      echo $ROW | base64 --decode | jq -r ${1}
    }
    NAME=$(_jq '.Name')
    VALUE=$(_jq '.Value')
    SENSITIVE=$(_jq '.Sensitive')
    MODE=env-var
    if [ $SENSITIVE == "true" ]; then
      # This is a sensitive variable
      MODE=senv-var
    fi
    # Push ENV variables to workspace
    tfe pushvars -name $TFE_ORG/$TFE_WORKSPACE  -$MODE $NAME=$VALUE -overwrite $NAME
  done
  #tfe pullvars -name $TFE_ORG/$TFE_WORKSPACE -env true
fi

# Move into repo directory
echo "Changing to ./$PROJECT_DIR ..."
cd $PROJECT_DIR

# Create the remote state tf file
echo "Creating tfe_state.tf ..."
cat <<EOF | tee tfe_state.tf
terraform {
  backend "atlas" {
    name = "$TFE_ORG/$TFE_WORKSPACE"
  }
}
EOF

# initialize the workspace
echo "Initializing TF backend (migrates state to TFE) ..."
terraform init -force-copy

# Commit Code
echo "Committing code to GitHub ..."
git add .
# Will return a 1 if no changes, so ignore errors on this command
set +e
git commit -m "first commit"
set -e
git push

# Trigger first run on TFE
echo "Triggering first TFE run. Now go check https://app.terraform.io/app/$TFE_ORG/$TFE_WORKSPACE/runs ..."
tfe pushconfig -name $TFE_ORG/$TFE_WORKSPACE -vcs true
