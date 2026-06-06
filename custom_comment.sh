#!/bin/bash

source /opt/buildpiper/shell-functions/file-functions.sh
source /opt/buildpiper/shell-functions/log-functions.sh
source /opt/buildpiper/shell-functions/functions.sh

if [ "$DEBUG" = true ]; then
  set -x
fi

TASK_STATUS=0

custom_comment() {

COMMIT_SHA=$(jq -r '.environment_variables.COMMIT_SHA' /bp/execution_dir/$GLOBAL_TASK_ID/cloning_repository_output.json)
REPO_NAME=$(jq -r '.environment_variables.CODEBASE_DIR' /bp/execution_dir/$GLOBAL_TASK_ID/cloning_repository_output.json)
BUILD_NUMBER=$(jq -r '.build_number' /bp/data/environment_build)
TARGET_URL="$DNS_URL/logs?global_task_id=$GLOBAL_TASK_ID"

sleep $SLEEP_DURATION

COMMENT="${CUSTOM_MESSAGE} 

\`\`\`
-----------------------------------------------------------------------------
BUILD NO:- ${BUILD_NUMBER}
BUILDPIPER URL:- ${TARGET_URL} 
-----------------------------------------------------------------------------
\`\`\`"

echo "--------------------------------"
echo "$COMMENT"
echo "--------------------------------"


detect_scm() {
  if [[ "$SCM_URL" == *"github.com"* ]]; then
    SCM_TYPE="github"
  elif [[ "$SCM_URL" == *"bitbucket.org"* ]]; then
    SCM_TYPE="bitbucket"
  else
    logErrorMessage "Unable to detect SCM from SCM_URL=$SCM_URL"
    exit 1
  fi
  logInfoMessage "Detected SCM: $SCM_TYPE"
}

detect_scm

if [ "$SCM_TYPE" = "github" ]; then 
  logInfoMessage "Looking up GitHub PR using commit ${COMMIT_SHA}"

  PR_ID=$(curl -s \
  -H "Authorization: Bearer ${SCM_PASSWORD}" \
  -H "Accept: application/vnd.github.groot-preview+json" \
  "https://api.github.com/repos/${SCM_PROJECT}/${REPO_NAME}/commits/${COMMIT_SHA}/pulls" \
  | jq -r '.[0].number // empty')

logInfoMessage "PR_ID=$PR_ID"

# Step 2: Prepare payload
PAYLOAD=$(jq -n --arg body "$COMMENT" '{body:$body}')

if [[ -n "$PR_ID" ]]; then
  HTTP_CODE=$(curl -s -o response.json -w "%{http_code}" \
    -X POST \
    -H "Authorization: Bearer ${SCM_PASSWORD}" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "https://api.github.com/repos/${SCM_PROJECT}/${REPO_NAME}/issues/${PR_ID}/comments")

  if [[ "$HTTP_CODE" == "201" ]]; then
    logInfoMessage "Comment posted successfully"
  else
    logErrorMessage "Failed to post comment (HTTP $HTTP_CODE)"
    cat response.json
  fi
else
  logErrorMessage "No PR found for commit ${COMMIT_SHA}"
fi

elif [ "$SCM_TYPE" = "bitbucket" ]; then
    logInfoMessage "Looking up Bitbucket PR using commit ${COMMIT_SHA}"

    PR_ID=$(curl -s \
    -u "${SCM_USERNAME}:${SCM_PASSWORD}" \
    "https://api.bitbucket.org/2.0/repositories/${SCM_PROJECT}/${REPO_NAME}/commit/${COMMIT_SHA}/pullrequests" \
    | jq -r '.values[0].id // empty')
    logInfoMessage "PR_ID=$PR_ID"

    PAYLOAD=$(jq -n --arg text "$COMMENT" '{content:{raw:$text}}')

    if [[ -n "$PR_ID" ]]; then
      HTTP_CODE=$(curl -s -o response.json -w "%{http_code}" \
      -X POST \
      -u "${SCM_USERNAME}:${SCM_PASSWORD}" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD" \
      "https://api.bitbucket.org/2.0/repositories/${SCM_PROJECT}/${REPO_NAME}/pullrequests/${PR_ID}/comments")

      if [[ "$HTTP_CODE" == "201" ]]; then
        logInfoMessage "Comment posted successfully"
      else
        logErrorMessage "Failed to post comment (HTTP $HTTP_CODE)"
        cat response.json
      fi
    else
      logErrorMessage "No PR found for commit ${COMMIT_SHA}"
    fi

fi
TASK_STATUS=$?
saveTaskStatus ${TASK_STATUS} ${ACTIVITY_SUB_TASK_CODE}
}

