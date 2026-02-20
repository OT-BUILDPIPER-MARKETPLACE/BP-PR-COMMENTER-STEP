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
cd  "${CODEBASE_LOCATION}"

logInfoMessage "login to SCM"
build_login_scm

case "$ACTION" in
  custom_comment)
    logInfoMessage "Selected action: $ACTION"
    custom_comment
    ;;
  ci_report)
    logInfoMessage "Selected action: $ACTION"
    report_comment
    ;;
  *)
    logInfoMessage "Usage: ACTION must be {custom|report}"
    exit 1
    ;;
esac
