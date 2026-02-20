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

get_status() {
  jq -r --arg key "$1" '
    .[]
    | select(has($key))
    | .[$key].status
  ' "$RESULT_JSON" | tail -n 1
}

convert_status() {
  if [[ "$1" == "true" ]]; then
    echo "PASS"
  else
    echo "FAIL"
  fi
}

CLONE_STATUS=$(convert_status "$(get_status "cloning_repository")")
CRED_STATUS=$(convert_status "$(get_status "Cred_Scanning_nr")")
SONAR_STATUS=$(convert_status "$(get_status "sonar_scan")")
TRIVY_FS_STATUS=$(convert_status "$(get_status "trivy-file-syetem-scan")")
TRIVY_IMG_STATUS=$(convert_status "$(get_status "Trivy-Image-Scan")")
SBOM_GEN_STATUS=$(convert_status "$(get_status "Trivy-Sbom-Generate")")
SBOM_SCAN_STATUS=$(convert_status "$(get_status "Trivy-Sbom-Scan")")
IMAGE_LAYER_STATUS=$(convert_status "$(get_status "IMAGE_LAYER_VALIDATOR")")
IMAGE_SIZE_STATUS=$(convert_status "$(get_status "IMAGE_SIZE_VALIDATOR")")

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
---------
Build No : ${BUILD_NUMBER}
Repository Clone : ${CLONE_STATUS}
Credential Scan : ${CRED_STATUS}
Credential Leaks : ${TOTAL_LEAKS}
Sonar Scan : ${SONAR_STATUS}
Trivy FS Scan : ${TRIVY_FS_STATUS}
Docker Build : ${DOCKER_STATUS}
Trivy Image Scan : ${TRIVY_IMG_STATUS}
SBOM Generate : ${SBOM_GEN_STATUS}
SBOM Scan : ${SBOM_SCAN_STATUS}
Image Layer Validator : ${IMAGE_LAYER_STATUS}
Image Size Validator : ${IMAGE_SIZE_STATUS}

Vulnerability Summary
CRITICAL : ${CRITICAL}
HIGH     : ${HIGH}
MEDIUM   : ${MEDIUM}
LOW      : ${LOW}
---------
\`\`\`"

logInfoMessage "--------------------------------"
logInfoMessage "$COMMENT"
logInfoMessage "--------------------------------"


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