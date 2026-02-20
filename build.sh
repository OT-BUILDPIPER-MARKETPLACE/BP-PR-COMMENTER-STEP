#!/bin/bash

source /opt/buildpiper/shell-functions/file-functions.sh
source /opt/buildpiper/shell-functions/log-functions.sh
source /opt/buildpiper/shell-functions/functions.sh
source ./git_bulid_login.sh

if [ "$DEBUG" = true ]; then
  set -x
fi

TASK_STATUS=0

CODEBASE_LOCATION="${WORKSPACE}"/"${CODEBASE_DIR}"
logInfoMessage "I'll do processing at [$CODEBASE_LOCATION]"
sleep  $SLEEP_DURATION
cd  "${CODEBASE_LOCATION}"

logInfoMessage "login to SCM"
build_login_scm


RESULT_JSON="/bp/execution_dir/$GLOBAL_TASK_ID/summary.json"
IMAGE_CSV_FILE="/bp/execution_dir/$GLOBAL_TASK_ID/trivy_image.csv"
DOCKER_BUILD_FILE="/bp/execution_dir/$GLOBAL_TASK_ID/build_docker_image_output.json"
GIT_LEAKS_FILE="/bp/execution_dir/$GLOBAL_TASK_ID/cred_scanner_sum.csv"
COMMIT_SHA=$(jq -r '.environment_variables.COMMIT_SHA' /bp/execution_dir/$GLOBAL_TASK_ID/cloning_repository_output.json)
REPO_NAME=$(jq -r '.environment_variables.CODEBASE_DIR' /bp/execution_dir/$GLOBAL_TASK_ID/cloning_repository_output.json)
BUILD_NUMBER=$(jq -r '.build_number' /bp/data/environment_build)

sleep $SLEEP_DURATION


convert_status() {
value=$(echo "$1" | tr '[:upper:]' '[:lower:]')

if [[ "$value" == "true" || "$value" == "successful" ]]; then
    echo "PASS"
  else
    echo "FAIL"
  fi
}

STAGE_REPORT=""
TOTAL_PASS=0
TOTAL_FAIL=0

if [[ -f "$RESULT_JSON" ]]; then

  while read -r stage; do

    STAGE_NAME=$(echo "$stage" | jq -r 'keys[0]')
    STATUS_RAW=$(echo "$stage" | jq -r '.[].status')

    FINAL_STATUS=$(convert_status "$STATUS_RAW")

    if [[ "$FINAL_STATUS" == "PASS" ]]; then
      ((TOTAL_PASS++))
    else
      ((TOTAL_FAIL++))
    fi

    STAGE_REPORT="${STAGE_REPORT}${STAGE_NAME} : ${FINAL_STATUS}\n"

  done < <(jq -c '.[]' "$RESULT_JSON")

else
  STAGE_REPORT="No summary.json found\n"
fi

STAGE_REPORT=$(echo -e "$STAGE_REPORT")



if [[ -f "$GIT_LEAKS_FILE" ]]; then
  TOTAL_LEAKS=$(tail -n 1 "$GIT_LEAKS_FILE")
else
  TOTAL_LEAKS=""
fi

if [[ -f "$DOCKER_BUILD_FILE" ]]; then
  DOCKER_STATUS_RAW=$(jq -r '.result.status' "$DOCKER_BUILD_FILE")
else
  DOCKER_STATUS_RAW="false"
fi

DOCKER_STATUS=$(convert_status "$DOCKER_STATUS_RAW")

if [[ -f "$IMAGE_CSV_FILE" ]]; then
  CRITICAL=$(grep -c '"CRITICAL"' "$IMAGE_CSV_FILE" || true)
  HIGH=$(grep -c '"HIGH"' "$IMAGE_CSV_FILE" || true)
  MEDIUM=$(grep -c '"MEDIUM"' "$IMAGE_CSV_FILE" || true)
  LOW=$(grep -c '"LOW"' "$IMAGE_CSV_FILE" || true)
else
  CRITICAL=""
  HIGH=""
  MEDIUM=""
  LOW=""
fi

COMMENT="CI Report from BUILDPIPER

\`\`\`
------------------------------------------------
Build No : ${BUILD_NUMBER}

Stage Summary
${STAGE_REPORT}
Docker Build     : ${DOCKER_STATUS}
Credential Leaks : ${TOTAL_LEAKS}

Total PASS : ${TOTAL_PASS}
Total FAIL : ${TOTAL_FAIL}

Vulnerability Summary
CRITICAL : ${CRITICAL}
HIGH     : ${HIGH}
MEDIUM   : ${MEDIUM}
LOW      : ${LOW}
------------------------------------------------
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
