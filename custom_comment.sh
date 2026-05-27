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
    TARGET_URL="${DNS_URL}/logs?global_task_id=${GLOBAL_TASK_ID}"

    if [ -n "$SLEEP_DURATION" ] && [ "$SLEEP_DURATION" -gt 0 ] 2>/dev/null; then
        sleep "$SLEEP_DURATION"
    fi

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

    # --------------------------------------------------
    # SCM Detection
    # --------------------------------------------------
    detect_scm() {
        if [[ "$SCM_URL" == *"github.com"* ]]; then
            SCM_TYPE="github"
        elif [[ "$SCM_URL" == *"bitbucket.org"* ]]; then
            SCM_TYPE="bitbucket"
        else
            logErrorMessage "Unable to detect SCM from SCM_URL=${SCM_URL}"
            return 1
        fi
        logInfoMessage "Detected SCM: ${SCM_TYPE}"
    }

    detect_scm || return 1

    # --------------------------------------------------
    # GitHub
    # --------------------------------------------------
    if [ "$SCM_TYPE" = "github" ]; then
        logInfoMessage "> Looking up GitHub PR for commit: ${COMMIT_SHA}"

        # SCM_URL is in the form: github.com/<org>/<repo>
        # SCM_PROJECT is the org extracted by git_bulid_login.sh
        GITHUB_API="https://api.github.com"
        GITHUB_TOKEN="${SCM_PASSWORD}"

        # Find PR number associated with this commit
        PR_RESPONSE=$(curl -s \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            -H "Accept: application/vnd.github.v3+json" \
            "${GITHUB_API}/repos/${SCM_PROJECT}/${REPO_NAME}/commits/${COMMIT_SHA}/pulls")

        PR_ID=$(echo "$PR_RESPONSE" | jq -r '.[0].number // empty')

        if [ -z "$PR_ID" ]; then
            logWarningMessage "> No open PR found for commit ${COMMIT_SHA} in ${SCM_PROJECT}/${REPO_NAME}"
            logWarningMessage "> Attempting to post comment via commit comments as fallback..."

            # Fallback: post as a commit comment
            PAYLOAD=$(jq -n --arg body "$COMMENT" '{body: $body}')
            HTTP_CODE=$(curl -s -o /tmp/gh_response.json -w "%{http_code}" \
                -X POST \
                -H "Authorization: token ${GITHUB_TOKEN}" \
                -H "Accept: application/vnd.github.v3+json" \
                -H "Content-Type: application/json" \
                -d "$PAYLOAD" \
                "${GITHUB_API}/repos/${SCM_PROJECT}/${REPO_NAME}/commits/${COMMIT_SHA}/comments")

            if [[ "$HTTP_CODE" == "201" ]]; then
                logInfoMessage "> Commit comment posted successfully (HTTP ${HTTP_CODE})"
                return 0
            else
                logErrorMessage "> Failed to post commit comment (HTTP ${HTTP_CODE})"
                cat /tmp/gh_response.json
                return 1
            fi
        fi

        logInfoMessage "> Found PR #${PR_ID} for commit ${COMMIT_SHA}"

        # Post comment on the PR
        PAYLOAD=$(jq -n --arg body "$COMMENT" '{body: $body}')
        HTTP_CODE=$(curl -s -o /tmp/gh_response.json -w "%{http_code}" \
            -X POST \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            -H "Accept: application/vnd.github.v3+json" \
            -H "Content-Type: application/json" \
            -d "$PAYLOAD" \
            "${GITHUB_API}/repos/${SCM_PROJECT}/${REPO_NAME}/issues/${PR_ID}/comments")

        if [[ "$HTTP_CODE" == "201" ]]; then
            logInfoMessage "> PR comment posted successfully on PR #${PR_ID} (HTTP ${HTTP_CODE})"
            return 0
        else
            logErrorMessage "> Failed to post PR comment on PR #${PR_ID} (HTTP ${HTTP_CODE})"
            cat /tmp/gh_response.json
            return 1
        fi

    # --------------------------------------------------
    # Bitbucket
    # --------------------------------------------------
    elif [ "$SCM_TYPE" = "bitbucket" ]; then
        logInfoMessage "> Looking up Bitbucket PR for commit: ${COMMIT_SHA}"

        PR_ID=$(curl -s \
            -u "${SCM_USERNAME}:${SCM_PASSWORD}" \
            "https://api.bitbucket.org/2.0/repositories/${SCM_PROJECT}/${REPO_NAME}/commit/${COMMIT_SHA}/pullrequests" \
            | jq -r '.values[0].id // empty')

        logInfoMessage "> PR_ID=${PR_ID}"

        PAYLOAD=$(jq -n --arg text "$COMMENT" '{content:{raw:$text}}')

        if [[ -n "$PR_ID" ]]; then
            HTTP_CODE=$(curl -s -o /tmp/bb_response.json -w "%{http_code}" \
                -X POST \
                -u "${SCM_USERNAME}:${SCM_PASSWORD}" \
                -H "Content-Type: application/json" \
                -d "$PAYLOAD" \
                "https://api.bitbucket.org/2.0/repositories/${SCM_PROJECT}/${REPO_NAME}/pullrequests/${PR_ID}/comments")

            if [[ "$HTTP_CODE" == "201" ]]; then
                logInfoMessage "> Comment posted successfully on PR #${PR_ID} (HTTP ${HTTP_CODE})"
                return 0
            else
                logErrorMessage "> Failed to post comment on PR #${PR_ID} (HTTP ${HTTP_CODE})"
                cat /tmp/bb_response.json
                return 1
            fi
        else
            logErrorMessage "> No PR found for commit ${COMMIT_SHA} in ${SCM_PROJECT}/${REPO_NAME}"
            return 1
        fi

    fi

    return 0
}
