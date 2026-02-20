#!/bin/bash

source /opt/buildpiper/shell-functions/file-functions.sh
source /opt/buildpiper/shell-functions/log-functions.sh
source /opt/buildpiper/shell-functions/functions.sh

if [ "$DEBUG" = true ]; then
  set -x
fi


COMMIT_SHA=$(jq -r '.environment_variables.COMMIT_SHA' /bp/execution_dir/$GLOBAL_TASK_ID/cloning_repository_output.json)
REPO_NAME=$(jq -r '.environment_variables.CODEBASE_DIR' /bp/execution_dir/$GLOBAL_TASK_ID/cloning_repository_output.json)
BUILD_NUMBER=$(jq -r '.build_number' /bp/data/environment_build)
TARGET_URL="$DNS_URL/logs?global_task_id=$GLOBAL_TASK_ID"

sleep $SLEEP_DURATION

custom_comment() {

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
  logWarningMessage "GitHub PR lookup and comment posting is currently under development."
  exit 1

  #PR_ID=$(echo "$RESPONSE" | jq -r '.number // empty')


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

saveTaskStatus ${TASK_STATUS} ${ACTIVITY_SUB_TASK_CODE}