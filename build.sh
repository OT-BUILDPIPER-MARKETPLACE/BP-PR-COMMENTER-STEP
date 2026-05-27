#!/bin/bash

# ---------------------------------------------------------------
# NOTE: ACTIVITY_SUB_TASK_CODE is managed by the BuildPiper
#       environment. Do NOT override it here to ensure events
#       appear correctly in the UI.
# ---------------------------------------------------------------

source /opt/buildpiper/shell-functions/file-functions.sh
source /opt/buildpiper/shell-functions/log-functions.sh
source /opt/buildpiper/shell-functions/functions.sh
source ./git_bulid_login.sh
source ./custom_comment.sh
source ./report_comment.sh

if [ "$DEBUG" = true ]; then
    set -x
fi

# ---------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------
WORKSPACE="${WORKSPACE:-/bp/workspace}"
CODEBASE_LOCATION="${WORKSPACE}/${CODEBASE_DIR}"

# ---------------------------------------------------------------
# 1. Initialization
# ---------------------------------------------------------------
logInfoMessage "> Starting step: pr_commenter"
logInfoMessage "> Codebase location: ${CODEBASE_LOCATION}"
logInfoMessage "> Action: ${ACTION}"

add_event "INITIALIZATION" "Successful" \
    "PR Commenter step initialized" \
    "Action: ${ACTION} | Codebase: ${CODEBASE_DIR}"

if [ -n "$SLEEP_DURATION" ] && [ "$SLEEP_DURATION" -gt 0 ] 2>/dev/null; then
    logInfoMessage "> Sleeping for ${SLEEP_DURATION} second(s)..."
    sleep "$SLEEP_DURATION"
fi

# ---------------------------------------------------------------
# 2. Input Validation
# ---------------------------------------------------------------
logInfoMessage "> Validating inputs..."

if [ -z "$WORKSPACE" ] || [ -z "$CODEBASE_DIR" ]; then
    logErrorMessage "> WORKSPACE or CODEBASE_DIR is not set — cannot proceed"
    add_event "INPUT_VALIDATION" "Failed" \
        "Required environment variables are missing" \
        "WORKSPACE: ${WORKSPACE:-<unset>} | CODEBASE_DIR: ${CODEBASE_DIR:-<unset>}"
    saveTaskStatus 1 "${ACTIVITY_SUB_TASK_CODE}"
    exit 1
fi

if [ -z "$ACTION" ]; then
    logErrorMessage "> ACTION is not set — allowed values: custom_comment | ci_report"
    add_event "INPUT_VALIDATION" "Failed" \
        "ACTION is not set" \
        "Set ACTION to one of: custom_comment | ci_report"
    saveTaskStatus 1 "${ACTIVITY_SUB_TASK_CODE}"
    exit 1
fi

add_event "INPUT_VALIDATION" "Successful" \
    "All required inputs validated" \
    "Action: ${ACTION} | Codebase: ${CODEBASE_DIR}"

# ---------------------------------------------------------------
# 3. Execution Summary
# ---------------------------------------------------------------
echo ""
echo "> PR Commenter Execution Summary"
printf '+%-30s+%-50s+\n' '------------------------------' '--------------------------------------------------'
printf '| %-28s | %-48s |\n' "Parameter" "Value"
printf '+%-30s+%-50s+\n' '------------------------------' '--------------------------------------------------'
printf '| %-28s | %-48s |\n' "Codebase" "${CODEBASE_DIR}"
printf '+%-30s+%-50s+\n' '------------------------------' '--------------------------------------------------'
printf '| %-28s | %-48s |\n' "Action" "${ACTION}"
printf '+%-30s+%-50s+\n' '------------------------------' '--------------------------------------------------'
echo ""

# ---------------------------------------------------------------
# 4. Workspace Navigation
# ---------------------------------------------------------------
logInfoMessage "> Navigating to codebase directory..."

cd "${CODEBASE_LOCATION}" || {
    logErrorMessage "> Failed to navigate to codebase directory: ${CODEBASE_LOCATION}"
    add_event "WORKSPACE_NAVIGATION" "Failed" \
        "Cannot change to codebase directory" \
        "Path: ${CODEBASE_LOCATION} | Verify WORKSPACE and CODEBASE_DIR"
    saveTaskStatus 1 "${ACTIVITY_SUB_TASK_CODE}"
    exit 1
}

logInfoMessage "> Successfully navigated to: ${CODEBASE_LOCATION}"
add_event "WORKSPACE_NAVIGATION" "Successful" \
    "Navigated to codebase directory" \
    "Path: ${CODEBASE_LOCATION}"

# ---------------------------------------------------------------
# 5. SCM Login
# ---------------------------------------------------------------
logInfoMessage "> Logging into SCM..."

build_login_scm
if [ $? -ne 0 ]; then
    logErrorMessage "> SCM login failed — check credentials configuration"
    add_event "SCM_LOGIN" "Failed" \
        "Failed to authenticate with SCM" \
        "Check SCM credentials in pipeline configuration"
    saveTaskStatus 1 "${ACTIVITY_SUB_TASK_CODE}"
    exit 1
fi

logInfoMessage "> SCM login successful"
add_event "SCM_LOGIN" "Successful" \
    "Successfully authenticated with SCM" \
    "Credentials validated"

# ---------------------------------------------------------------
# 6. Comment Action
# ---------------------------------------------------------------
logInfoMessage "> Executing comment action: ${ACTION}..."

case "$ACTION" in
    custom_comment)
        add_event "COMMENT_ACTION_START" "Successful" \
            "Starting custom comment action" \
            "Action: custom_comment"

        custom_comment
        if [ $? -ne 0 ]; then
            logErrorMessage "> Failed to post custom comment to PR"
            add_event "COMMENT_ACTION_RESULT" "Failed" \
                "Failed to post custom comment" \
                "Action: custom_comment | Check PR number and SCM token"
            saveTaskStatus 1 "${ACTIVITY_SUB_TASK_CODE}"
            exit 1
        fi

        logInfoMessage "> Custom comment posted successfully"
        add_event "COMMENT_ACTION_RESULT" "Successful" \
            "Custom comment posted to PR successfully" \
            "Action: custom_comment"
        ;;

    ci_report)
        add_event "COMMENT_ACTION_START" "Successful" \
            "Starting CI report comment action" \
            "Action: ci_report"

        report_comment
        if [ $? -ne 0 ]; then
            logErrorMessage "> Failed to post CI report comment to PR"
            add_event "COMMENT_ACTION_RESULT" "Failed" \
                "Failed to post CI report comment" \
                "Action: ci_report | Check PR number and report data"
            saveTaskStatus 1 "${ACTIVITY_SUB_TASK_CODE}"
            exit 1
        fi

        logInfoMessage "> CI report comment posted successfully"
        add_event "COMMENT_ACTION_RESULT" "Successful" \
            "CI report comment posted to PR successfully" \
            "Action: ci_report"
        ;;

    *)
        logErrorMessage "> Invalid ACTION: '${ACTION}' — allowed values: custom_comment | ci_report"
        add_event "COMMENT_ACTION_RESULT" "Failed" \
            "Invalid ACTION specified" \
            "Received: '${ACTION}' | Allowed: custom_comment | ci_report"
        saveTaskStatus 1 "${ACTIVITY_SUB_TASK_CODE}"
        exit 1
        ;;
esac

# ---------------------------------------------------------------
# 7. Final Status
# ---------------------------------------------------------------
logInfoMessage "> PR Commenter step completed successfully"
saveTaskStatus 0 "${ACTIVITY_SUB_TASK_CODE}"
exit 0
