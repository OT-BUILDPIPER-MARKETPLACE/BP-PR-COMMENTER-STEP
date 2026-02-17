#!/bin/bash

source /opt/buildpiper/shell-functions/functions.sh
source /opt/buildpiper/shell-functions/log-functions.sh
source /opt/buildpiper/shell-functions/str-functions.sh
source /opt/buildpiper/shell-functions/file-functions.sh

build_login_scm() {
  local JSON_FILE="/bp/data/environment_build"

  [[ -f "$JSON_FILE" ]] || { logErrorMessage "JSON file not found"; return 1; }
  [[ -n "$FERNET_KEY" ]] || { logErrorMessage "FERNET_KEY not set"; return 1; }

  SCM_URL=$(jq -r '.git_repo.git_url | sub("^https?://"; "")' "$JSON_FILE")
  SCM_PROJECT=$(echo "$SCM_URL" | cut -d'/' -f2)
  BRANCH=$(jq -r '.git_repo.branch_name' "$JSON_FILE")
  if [[ -z "$SCM_URL" || "$SCM_URL" == "null" ]]; then
  logErrorMessage "git_url not found in JSON"
  exit 1
  fi

  if [[ -z "$BRANCH" || "$BRANCH" == "null" ]]; then
    logErrorMessage "branch_name not found in JSON"
    exit 1
  fi

  if [[ -z "$SCM_PROJECT" || "$SCM_PROJECT" == "null" ]]; then
    logErrorMessage "SCM_PROJECT could not be derived"
    exit 1
  fi

  while read -r cred; do

    NAME=$(jq -r '.name' <<<"$cred")
    ENC_USER=$(jq -r '.username' <<<"$cred")
    ENC_PASS=$(jq -r '.password' <<<"$cred")

    SCM_USERNAME=$(python3 - <<PY
from cryptography.fernet import Fernet
import os
print(Fernet(os.environ["FERNET_KEY"].encode()).decrypt(b"$ENC_USER").decode())
PY
)

    SCM_PASSWORD=$(python3 - <<PY
from cryptography.fernet import Fernet
import os
print(Fernet(os.environ["FERNET_KEY"].encode()).decrypt(b"$ENC_PASS").decode())
PY
)

    export SCM_USERNAME
    export SCM_PASSWORD
    export SCM_PROJECT
    export SCM_URL
    export BRANCH

    check_branch

  done < <(jq -c '
    if (.git_repo.credential | type) == "array" then
      .git_repo.credential[]
    else
      .git_repo.credential
    end
  ' "$JSON_FILE")
}

check_branch() {
  COUNT=$(git ls-remote https://$SCM_USERNAME:$SCM_PASSWORD@$SCM_URL $BRANCH 2>/dev/null | wc -l)

  if [ "$COUNT" -ge 1 ]; then
   logInfoMessage "--------------------------------------------------"
    logInfoMessage "Branch '$BRANCH' exists and credentials are valid"
    logInfoMessage "-------------------------------------------------"
    return 0
    
  else
    logErrorMessage "---------------------------------------------------------"
    logErrorMessage "Either branch '$BRANCH' not found or credentials invalid"
    logErrorMessage "---------------------------------------------------------"
    exit 1
  fi
}