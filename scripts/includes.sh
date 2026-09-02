#!/bin/bash

ENV_FILE="/.env"
CRON_CONFIG_FILE="${HOME}/crontabs"

#################### Function ####################
########################################
# Print colorful message.
# Arguments:
#     color
#     message
# Outputs:
#     colorful message
########################################
function color() {
    case $1 in
        red)     echo -e "\033[31m$2\033[0m" ;;
        green)   echo -e "\033[32m$2\033[0m" ;;
        yellow)  echo -e "\033[33m$2\033[0m" ;;
        blue)    echo -e "\033[34m$2\033[0m" ;;
        none)    echo "$2" ;;
    esac
}

########################################
# Check storage system connection success.
# Arguments:
#     None
########################################
function check_rclone_connection() {
    # check configuration exists (config file or env vars)
    local RCLONE_CONFIG_FILE=$(rclone config file 2>&1 | grep -o '/[^[:space:]]*rclone\.conf')
    local HAS_CONFIG_FILE=false
    if [[ -f "${RCLONE_CONFIG_FILE}" ]]; then
        grep -c "\[${RCLONE_REMOTE_NAME}\]" "${RCLONE_CONFIG_FILE}" > /dev/null 2>&1 && HAS_CONFIG_FILE=true
    fi

    # Check if remote is configured via env vars (RCLONE_CONFIG_<NAME>_TYPE)
    local REMOTE_NAME_UPPER=$(echo "${RCLONE_REMOTE_NAME}" | tr '[:lower:]' '[:upper:]')
    local HAS_ENV_CONFIG=false
    if [[ -n "$(eval echo \${RCLONE_CONFIG_${REMOTE_NAME_UPPER}_TYPE:-})" ]]; then
        HAS_ENV_CONFIG=true
    fi

    if [[ "${HAS_CONFIG_FILE}" == false && "${HAS_ENV_CONFIG}" == false ]]; then
        color red "rclone configuration information not found"
        color blue "Please configure rclone first, check https://github.com/rodriguestiago0/actualbudget-backup#configure-rclone-%EF%B8%8F-must-read-%EF%B8%8F"
        exit 1
    fi

    # check flags validity
    rclone ${RCLONE_GLOBAL_FLAG} version > /dev/null 2>&1
    if [[ $? != 0 ]]; then
        color red "illegal rclone global flags"
        color blue "Please check https://rclone.org/flags/"
        exit 1
    fi

    # check connection
    local ERROR_COUNT=0

    for RCLONE_REMOTE_X in "${RCLONE_REMOTE_LIST[@]}"
    do
        rclone ${RCLONE_GLOBAL_FLAG} lsd "${RCLONE_REMOTE_X}" > /dev/null
        if [[ $? != 0 ]]; then
            color red "storage system connection may not be initialized, try initializing $(color yellow "[${RCLONE_REMOTE_X}]")"

            rclone ${RCLONE_GLOBAL_FLAG} mkdir "${RCLONE_REMOTE_X}"
            if [[ $? != 0 ]]; then
                color red "storage system connection failure $(color yellow "[${RCLONE_REMOTE_X}]")"

                ((ERROR_COUNT++))
            fi
        fi
    done

    if [[ "${ERROR_COUNT}" -gt 0 ]]; then
        if [[ "$1" == "all" ]]; then
            color red "storage system connection failure exists"
            exit 1
        elif [[ "$1" == "any" ]]; then
            if [[ "${ERROR_COUNT}" -eq "${#RCLONE_REMOTE_LIST[@]}" ]]; then
                color red "all storage system connections failed"
                exit 1
            else
                color yellow "some storage system connections failed, but the backup will continue"
            fi
        fi
    fi
}

########################################
# Check file is exist.
# Arguments:
#     file
########################################
function check_file_exist() {
    if [[ ! -f "$1" ]]; then
        color red "cannot access $1: No such file"
        exit 1
    fi
}

########################################
# Check directory is exist.
# Arguments:
#     directory
########################################
function check_dir_exist() {
    if [[ ! -d "$1" ]]; then
        color red "cannot access $1: No such directory"
        exit 1
    fi
}

########################################
# Export variables from .env file.
# Arguments:
#     None
# Outputs:
#     variables with prefix 'DOTENV_'
# Reference:
#     https://gist.github.com/judy2k/7656bfe3b322d669ef75364a46327836#gistcomment-3632918
########################################
function export_env_file() {
    if [[ -f "${ENV_FILE}" ]]; then
        color blue "find \"${ENV_FILE}\" file and export variables"
        set -a
        source <(cat "${ENV_FILE}" | sed -e '/^#/d;/^\s*$/d' -e 's/\(\w*\)[ \t]*=[ \t]*\(.*\)/DOTENV_\1=\2/')
        set +a
    fi
}

########################################
# Get variables from
#     environment variables,
#     secret file in environment variables,
#     secret file in .env file,
#     environment variables in .env file.
# Arguments:
#     variable name
# Outputs:
#     variable value
########################################
function get_env() {
    local VAR="$1"
    local VAR_FILE="${VAR}_FILE"
    local VAR_DOTENV="DOTENV_${VAR}"
    local VAR_DOTENV_FILE="DOTENV_${VAR_FILE}"
    local VALUE=""

    if [[ -n "${!VAR:-}" ]]; then
        VALUE="${!VAR}"
    elif [[ -n "${!VAR_FILE:-}" ]]; then
        VALUE="$(cat "${!VAR_FILE}")"
    elif [[ -n "${!VAR_DOTENV_FILE:-}" ]]; then
        VALUE="$(cat "${!VAR_DOTENV_FILE}")"
    elif [[ -n "${!VAR_DOTENV:-}" ]]; then
        VALUE="${!VAR_DOTENV}"
    fi

    export "${VAR}=${VALUE}"
}

########################################
# Load rclone secrets from _FILE env vars.
# Reads RCLONE_CONFIG_*_FILE and exports as RCLONE_CONFIG_*
# Arguments:
#     None
########################################
function load_rclone_secrets() {
    for var_name in $(env | grep '^RCLONE_CONFIG_.*_FILE=' | cut -d= -f1); do
        local file_path="${!var_name}"
        local target_var="${var_name%_FILE}"
        if [[ -f "${file_path}" ]]; then
            local value=$(tr -d '\n\r' < "${file_path}")
            export "${target_var}=${value}"
            color yellow "Loaded ${target_var} from file"
        else
            color red "File not found for ${var_name}: ${file_path}"
        fi
    done
}

########################################
# Get RCLONE_REMOTE_LIST variables.
# Arguments:
#     None
# Outputs:
#     variable value
########################################
function get_rclone_remote_list() {
    # RCLONE_REMOTE_LIST
    RCLONE_REMOTE_LIST=()

    local i=0
    local RCLONE_REMOTE_NAME_X_REFER
    local RCLONE_REMOTE_DIR_X_REFER
    local RCLONE_REMOTE_X

    # for multiple
    while true; do
        RCLONE_REMOTE_NAME_X_REFER="RCLONE_REMOTE_NAME_${i}"
        RCLONE_REMOTE_DIR_X_REFER="RCLONE_REMOTE_DIR_${i}"
        get_env "${RCLONE_REMOTE_NAME_X_REFER}"
        get_env "${RCLONE_REMOTE_DIR_X_REFER}"

        if [[ -z "${!RCLONE_REMOTE_NAME_X_REFER}" || -z "${!RCLONE_REMOTE_DIR_X_REFER}" ]]; then
            break
        fi

        RCLONE_REMOTE_X=$(echo "${!RCLONE_REMOTE_NAME_X_REFER}:${!RCLONE_REMOTE_DIR_X_REFER}" | sed 's@\(/*\)$@@')
        RCLONE_REMOTE_LIST=(${RCLONE_REMOTE_LIST[@]} "${RCLONE_REMOTE_X}")

        ((i++))
    done
}

function init_actual_sync_list() {
    ACTUAL_BUDGET_SYNC_ID_LIST=()

    local i=0
    local ACTUAL_BUDGET_SYNC_ID_X_REFER

    # for multiple
    while true; do
        ACTUAL_BUDGET_SYNC_ID_X_REFER="ACTUAL_BUDGET_SYNC_ID_${i}"
        get_env "${ACTUAL_BUDGET_SYNC_ID_X_REFER}"
    
        if [[ -z "${!ACTUAL_BUDGET_SYNC_ID_X_REFER}" ]]; then        
            break
        fi
        
        ACTUAL_BUDGET_SYNC_ID_LIST=(${ACTUAL_BUDGET_SYNC_ID_LIST[@]} ${!ACTUAL_BUDGET_SYNC_ID_X_REFER})

        ((i++))
    done

    for ACTUAL_BUDGET_SYNC_ID_X in "${ACTUAL_BUDGET_SYNC_ID_LIST[@]}"
    do
        color yellow "ACTUAL_BUDGET_SYNC_ID: ${ACTUAL_BUDGET_SYNC_ID_X}"
    done
}

function init_actual_e2e_list(){
    ACTUAL_BUDGET_E2E_PASSWORD_LIST=()

    local i=0
    local ACTUAL_BUDGET_E2E_PASSWORD_X_REFER

    # for multiple
    while true; do
        ACTUAL_BUDGET_E2E_PASSWORD_X_REFER="ACTUAL_BUDGET_E2E_PASSWORD_${i}"
        get_env "${ACTUAL_BUDGET_E2E_PASSWORD_X_REFER}"
    
        if [[ -z "${!ACTUAL_BUDGET_E2E_PASSWORD_X_REFER}" ]]; then        
            break
        fi
        
        ACTUAL_BUDGET_E2E_PASSWORD_LIST=(${ACTUAL_BUDGET_E2E_PASSWORD_LIST[@]} ${!ACTUAL_BUDGET_E2E_PASSWORD_X_REFER})

        ((i++))
    done

    for ACTUAL_BUDGET_E2E_PASSWORD_X in "${ACTUAL_BUDGET_E2E_PASSWORD_LIST[@]}"
    do
        color yellow "ACTUAL_BUDGET_E2E_PASSWORD: *****"
    done
}

function init_actual_env(){
    # ACTUAL BUDGET
    get_env ACTUAL_BUDGET_URL
    ACTUAL_BUDGET_URL="${ACTUAL_BUDGET_URL:-"https://localhost:5006"}"
    color yellow "ACTUAL_BUDGET_URL: ${ACTUAL_BUDGET_URL}"

    get_env ACTUAL_BUDGET_PASSWORD
    ACTUAL_BUDGET_PASSWORD="${ACTUAL_BUDGET_PASSWORD:-""}"
    color yellow "ACTUAL_BUDGET_PASSWORD: *****"

    get_env ACTUAL_BUDGET_SYNC_ID

    if [[ -z "${ACTUAL_BUDGET_SYNC_ID}" ]]; then        
        color red "Invalid sync id"
        exit 1
    fi 
    
    ACTUAL_BUDGET_SYNC_ID_0="${ACTUAL_BUDGET_SYNC_ID}"

    init_actual_sync_list
	
	
	get_env ACTUAL_BUDGET_E2E_PASSWORD
	ACTUAL_BUDGET_E2E_PASSWORD_0="${ACTUAL_BUDGET_E2E_PASSWORD}"
	
	init_actual_e2e_list
}

########################################
# Send webhook notification.
# Arguments:
#     URL
#     custom message template (optional)
#     status message
########################################
function send_webhook() {
    local URL="$1"
    local MESSAGE="$2"
    local STATUS="$3"

    if [[ -z "${URL}" ]]; then
        return
    fi

    local TIMESTAMP=$(date -Iseconds)
    local BODY

    if [[ -n "${MESSAGE}" ]]; then
        BODY=$(echo "${MESSAGE}" | sed \
            -e "s|{message}|${STATUS}|g" \
            -e "s|{service}|actualbudget-backup|g" \
            -e "s|{timestamp}|${TIMESTAMP}|g")
    else
        BODY="{\"service\": \"actualbudget-backup\", \"message\": \"${STATUS}\", \"timestamp\": \"${TIMESTAMP}\"}"
    fi

    curl -s -X POST "${URL}" \
        -H "Content-Type: application/json" \
        -d "${BODY}" \
        || color red "webhook notification failed"
}

########################################
# Send notification on backup status.
# Arguments:
#     status (start / success / failure)
#     detail message
########################################
function send_notification() {
    local STATUS="$1"
    local DETAIL="$2"
    local SUBJECT="Actual Budget Backup ${STATUS}"

    case "${STATUS}" in
        start)
            send_webhook "${WEBHOOK_URL}" "${WEBHOOK_MESSAGE}" "${SUBJECT}: ${DETAIL}"
            ;;
        success)
            send_webhook "${WEBHOOK_URL}" "${WEBHOOK_MESSAGE}" "${SUBJECT}: ${DETAIL}"
            send_webhook "${WEBHOOK_SUCCESS_URL}" "${WEBHOOK_SUCCESS_MESSAGE}" "${SUBJECT}: ${DETAIL}"
            ;;
        failure)
            send_webhook "${WEBHOOK_URL}" "${WEBHOOK_MESSAGE}" "${SUBJECT}: ${DETAIL}"
            send_webhook "${WEBHOOK_ERROR_URL}" "${WEBHOOK_ERROR_MESSAGE}" "${SUBJECT}: ${DETAIL}"
            ;;
    esac
}

########################################
# Arguments:
#     None
# Outputs:
#     environment variables
########################################
function init_env() {
    # export
    export_env_file

    # load rclone secrets from _FILE env vars
    load_rclone_secrets

    # CRON
    get_env CRON
    CRON="${CRON:-"0 0 * * *"}"

    # RCLONE_REMOTE_NAME
    get_env RCLONE_REMOTE_NAME
    RCLONE_REMOTE_NAME="${RCLONE_REMOTE_NAME:-"ActualBudgetBackup"}"
    RCLONE_REMOTE_NAME_0="${RCLONE_REMOTE_NAME}"

    # RCLONE_REMOTE_DIR
    get_env RCLONE_REMOTE_DIR
    RCLONE_REMOTE_DIR="${RCLONE_REMOTE_DIR:-"/ActualBudgetBackup/"}"
    RCLONE_REMOTE_DIR_0="${RCLONE_REMOTE_DIR}"

    # get RCLONE_REMOTE_LIST
    get_rclone_remote_list

    # RCLONE_GLOBAL_FLAG
    get_env RCLONE_GLOBAL_FLAG
    RCLONE_GLOBAL_FLAG="${RCLONE_GLOBAL_FLAG:-""}"

    # BACKUP_KEEP_DAYS
    get_env BACKUP_KEEP_DAYS
    BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-"0"}"

    # RETENTION_COUNT
    get_env RETENTION_COUNT
    RETENTION_COUNT="${RETENTION_COUNT:-"0"}"

    # ZIP_ENABLE
    get_env ZIP_ENABLE
    if [[ "${ZIP_ENABLE^^}" == "FALSE" ]]; then
        ZIP_ENABLE="FALSE"
    else
        ZIP_ENABLE="TRUE"
    fi

    # ZIP_PASSWORD
    get_env ZIP_PASSWORD
    ZIP_PASSWORD="${ZIP_PASSWORD:-""}"

    # ZIP_TYPE
    get_env ZIP_TYPE
    if [[ "${ZIP_TYPE,,}" == "7z" ]]; then
        ZIP_TYPE="7z"
    else
        ZIP_TYPE="zip"
    fi

    # BACKUP_FILE_DATE_FORMAT
    get_env BACKUP_FILE_SUFFIX
    get_env BACKUP_FILE_DATE
    get_env BACKUP_FILE_DATE_SUFFIX
    BACKUP_FILE_DATE="$(echo "${BACKUP_FILE_DATE:-"%Y%m%d"}${BACKUP_FILE_DATE_SUFFIX}" | sed 's/[^0-9a-zA-Z%_-]//g')"
    BACKUP_FILE_DATE_FORMAT="$(echo "${BACKUP_FILE_SUFFIX:-"${BACKUP_FILE_DATE}"}" | sed 's/\///g')"

    # TIMEZONE
    get_env TIMEZONE
    local TIMEZONE_MATCHED_COUNT=$(ls "/usr/share/zoneinfo/${TIMEZONE}" 2> /dev/null | wc -l)
    if [[ "${TIMEZONE_MATCHED_COUNT}" -ne 1 ]]; then
        TIMEZONE="UTC"
    fi

    # BACKUP_ON_START
    get_env BACKUP_ON_START

    # WEBHOOK
    get_env WEBHOOK_URL
    get_env WEBHOOK_MESSAGE
    get_env WEBHOOK_SUCCESS_URL
    get_env WEBHOOK_SUCCESS_MESSAGE
    get_env WEBHOOK_ERROR_URL
    get_env WEBHOOK_ERROR_MESSAGE

    init_actual_env

    color yellow "========================================"
    color yellow "CRON: ${CRON}"

    for RCLONE_REMOTE_X in "${RCLONE_REMOTE_LIST[@]}"
    do
        color yellow "RCLONE_REMOTE: ${RCLONE_REMOTE_X}"
    done

    color yellow "RCLONE_GLOBAL_FLAG: ${RCLONE_GLOBAL_FLAG}"
    color yellow "ZIP_ENABLE: ${ZIP_ENABLE}"
    color yellow "ZIP_PASSWORD: ${#ZIP_PASSWORD} Chars"
    color yellow "ZIP_TYPE: ${ZIP_TYPE}"
    color yellow "BACKUP_FILE_DATE_FORMAT: ${BACKUP_FILE_DATE_FORMAT} (example \"[filename].$(date +"${BACKUP_FILE_DATE_FORMAT}").zip\")"
    color yellow "BACKUP_KEEP_DAYS: ${BACKUP_KEEP_DAYS}"
    color yellow "RETENTION_COUNT: ${RETENTION_COUNT}"

    if [[ -n "${WEBHOOK_URL}" ]]; then
        color yellow "WEBHOOK_URL: configured"
    fi
    if [[ -n "${WEBHOOK_SUCCESS_URL}" ]]; then
        color yellow "WEBHOOK_SUCCESS_URL: configured"
    fi
    if [[ -n "${WEBHOOK_ERROR_URL}" ]]; then
        color yellow "WEBHOOK_ERROR_URL: configured"
    fi

    color yellow "TIMEZONE: ${TIMEZONE}"
    color yellow "========================================"
}
