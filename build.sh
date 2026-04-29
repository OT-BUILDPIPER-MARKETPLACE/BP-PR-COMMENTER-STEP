#!/bin/bash

source /opt/buildpiper/shell-functions/file-functions.sh
source /opt/buildpiper/shell-functions/log-functions.sh
source /opt/buildpiper/shell-functions/functions.sh
source ./git_bulid_login.sh
source ./custom_comment.sh
source ./report_comment.sh

if [ "$DEBUG" = true ]; then
  set -x
fi

CODEBASE_LOCATION="${WORKSPACE}"/"${CODEBASE_DIR}"
logInfoMessage "I'll do processing at [$CODEBASE_LOCATION]"
sleep  $SLEEP_DURATION
cd  "${CODEBASE_LOCATION}" || {
    logErrorMessage "Failed to navigate to workspace: ${CODEBASE_LOCATION}"
    add_event "WORKSPACE NAVIGATION" "Failed" \
          "Failed to navigate to workspace" \
          "Path: ${CODEBASE_LOCATION}"
    exit 1
}

add_event "WORKSPACE NAVIGATION" "Successful" \
      "Successfully navigated to workspace" \
      "Path: ${CODEBASE_LOCATION}"

add_event "INITIALIZATION" "Successful" \
      "Task initialization completed" \
      "Repository Location: ${CODEBASE_LOCATION}"

logInfoMessage "login to SCM"
build_login_scm
add_event "SCM LOGIN" "Successful" \
      "Successfully logged into SCM" \
      "Credentials validated"

case "$ACTION" in
  custom_comment)
    logInfoMessage "Selected action: $ACTION"
    custom_comment
    add_event "COMMENT ACTION" "Successful" \
          "Custom comment posted successfully" \
          "Action: custom_comment"
    ;;
  ci_report)
    logInfoMessage "Selected action: $ACTION"
    report_comment
    add_event "COMMENT ACTION" "Successful" \
          "CI report comment posted successfully" \
          "Action: ci_report"
    ;;
  *)
    logInfoMessage "Usage: ACTION must be {custom|report}"
    add_event "INITIALIZATION" "Failed" \
          "Invalid ACTION provided" \
          "Usage: ACTION must be {custom|report}"
    exit 1
    ;;
esac

add_event "TASK EXECUTION" "Successful" \
      "PR Commenter task completed successfully" \
      "Action $ACTION processed"
