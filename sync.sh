#!/usr/bin/env bash

EXIT_CODE_INVALID_STATE=2
EXIT_CODE_INVALID_ARGUMENT=3
EXIT_CODE_INVALID_STATE=6

reset_colors() {
	C_RESET=''
	C_LOG_DATE=''
	C_HIGHLIGHT=''
	C_VERBOSE=''
	C_INFO=''
	C_WARNING=''
	C_ERROR=''
}

reset_colors

# only enable colors when supported
if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	# Color Constants
	C_RESET="\033[0m"
	C_LOG_DATE="\033[0;36m"
	C_HIGHLIGHT="\033[1;34m"
	C_INFO="\033[0;32m"
	C_VERBOSE="\033[0;36m"
	C_WARNING="\033[1;33m"
	C_ERROR="\033[0;31m"
fi

self="$(basename "$0")"

BACKUP_DATE=$(date '+%Y-%m-%d_%Hh%Mm%Ss')
APP_ROOT="${HOME}/.local/rsync-backup"
LOG_FILE_PATH="$APP_ROOT/logs/backup-${BACKUP_DATE}.log"
PRINT_USAGE=true
RSYNC_DRY_RUN_ARGUMENTS='--dry-run --itemize-changes'
RSYNC_VERBOSE_ARGUMENTS='--verbose'
RSYNC_LOG_FILE_ARGUMENTS="--log-file='${LOG_FILE_PATH}'"
RSYNC_RELATIVE_ARGUMENTS='--relative'

# define variables
index=1
verbose=false
log_to_file=false
rsync_sources=()
identifier="$(hostname)"
rsync_exclude_file=
rsync_include_file=
rsync_dry_run=
rsync_verbose=
rsync_log_file=
ssh_user="$(whoami)"
ssh_server=
ssh_ident=
notify=false

usage() {
	echo -e
	echo -e "rsync backup"
	echo -e
	echo -e "Usage: ${self} [options] <src, [src...]>"
	echo -e
	echo -e "Options:"
	echo -e "  $(highlight "--target, -t")      The directory on the target to copy files. $(highlight "(required)")"
	echo -e
	echo -e "  $(highlight "--ssh-server")      The SSH server. $(highlight "(required)")"
	echo -e
	echo -e "  $(highlight "--identifier, -i")  A unique identifier for this computer. Default: $(highlight "$identifier")"
	echo -e
	echo -e "  $(highlight "--ssh-port")        The SSH connection port."
	echo -e
	echo -e "  $(highlight "--ssh-user")        The SSH user. Default: $(highlight "$ssh_user")"
	echo -e
	echo -e "  $(highlight "--ssh-ident")       The SSH key to use."
	echo -e
	echo -e "  $(highlight "--verbose, -v")     Show more verbose output of actions performed."
	echo -e
	echo -e "  $(highlight "--no-notify")       Disable notifications."
	echo -e
	echo -e "  $(highlight "--no-color")        Disable colored output."
	echo -e
	echo -e "  $(highlight "--dry-run")         Run rsync in dry run mode. Providing this options also assumes $(highlight "--verbose")."
	echo -e
	echo -e "  $(highlight "--relative")        Run rsync using the --relative option, creating full paths on destination."
	echo -e
	echo -e "  $(highlight "--log-to-file")     Log output to a file located inside $(highlight "${APP_ROOT}") instead of to stdout."
	echo -e
	echo -e "  $(highlight "--exclude-file")    An rsync exclude file, used to filter out files."
	echo -e
	echo -e "  $(highlight "--include-file")    An rsync include file, used to include files, even if excluded."
	echo -e
	echo -e "  $(highlight "--help")            Show this usage message and exit."
	echo -e
}

highlight() {
	echo "${C_HIGHLIGHT}$*${C_RESET}"
}

message() {
	message="$(date '+%Y/%m/%d %H:%M:%S')"
	message="[${C_LOG_DATE}${message}${C_RESET}] $*"
	if ${log_to_file}; then
		echo "${message}" >> "${LOG_FILE_PATH}"
	else
		echo -e "${message}"
	fi
}

info_message() {
	message "${C_INFO}   [INFO]${C_RESET} $*"
}

verbose_message() {
	if ${verbose}; then
		message "${C_VERBOSE}[VERBOSE]${C_RESET} $*"
	fi
}

warning() {
	message "${C_WARNING}[WARNING]${C_RESET} $*"
}

error() {
	# use error code provided if set, else last commands error code
	err=${2-$?}

	>&2 message "${C_ERROR}  [ERROR]${C_RESET} ${1}"

	if "${notify}"; then
		notify-send --urgency=critical --app-name="Sync" "Sync Error" "${1}"
	fi

	if [[ ${3} ]]; then
		>&2 usage
	fi

	if [[ -n ${err} ]]; then
		exit "$err"
	fi
}

argument_error() {
	error "Unexpected argument: $(highlight "${@}")" ${EXIT_CODE_INVALID_ARGUMENT} ${PRINT_USAGE}
}

# print usage if nothing provided
[[ "$#" -eq "0" ]] && usage && exit

if command -v notify-send &> /dev/null; then
	notify=true
fi

# parse arguments
while (($#)); do
	case "$1" in
		-v|--verbose)
			verbose=true
			rsync_verbose=${RSYNC_VERBOSE_ARGUMENTS}
			;;
		--no-color)
			reset_colors
			;;
		--dry-run)
			verbose=true
			rsync_dry_run=${RSYNC_DRY_RUN_ARGUMENTS}
			;;
		--relative)
			rsync_relative=${RSYNC_RELATIVE_ARGUMENTS}
			;;
		--no-notify)
			notify=false
			;;
		-h|--help)
			usage
			exit 0
			;;
		--log-to-file)
			message "Logging to ${LOG_FILE_PATH}"
			reset_colors # no colors for log files
			rsync_log_file=${RSYNC_LOG_FILE_ARGUMENTS}
			log_to_file=true
			;;
		-t|--target)
			target="$2"
			shift
			;;
		-i|--identifier)
			identifier="$2"
			shift
			;;
		--ssh-port)
			ssh_port="-p $2"
			shift
			;;
		--ssh-user)
			ssh_user="$2"
			shift
			;;
		--ssh-server)
			ssh_server="$2"
			shift
			;;
		--ssh-ident)
			ssh_ident="-i $2"
			shift
			;;
		--exclude-file)
			rsync_exclude_file="--exclude-from=$2"
			shift
			;;
		--include-file)
			rsync_include_file="--include-from=$2"
			shift
			;;
		--)
			shift
			break 2
			;;
		--*)
			argument_error "$1"
			;;
		*)
			rsync_sources[$index]="$1"
			((++index))
			;;
	esac
	shift
done

# ensure APP_ROOT
verbose_message "Ensuring that ${APP_ROOT} exists"
mkdir -p "${APP_ROOT}" || error "Error creating ${APP_ROOT}"
mkdir -p "${APP_ROOT}/logs" || error "Error creating ${APP_ROOT}/logs"

# check for required commands
command -v rsync &> /dev/null \
	|| error "rsync command wasn't found; please install and ensure it's on the PATH" ${EXIT_CODE_INVALID_STATE}

command -v ssh &> /dev/null \
	|| error "ssh command wasn't found; please install and ensure it's on the PATH" ${EXIT_CODE_INVALID_STATE}

# anything left should be treated as sources
while (($#)); do
	rsync_sources[$index]="$1"
	((++index))
	shift
done

[[ "${#rsync_sources[@]}" -eq "0" ]] \
	&& error "No sources provided" ${EXIT_CODE_INVALID_ARGUMENT} ${PRINT_USAGE}

[[ -z "$identifier" ]] \
	&& error "Empty identifier provided" ${EXIT_CODE_INVALID_ARGUMENT} ${PRINT_USAGE}

[[ -z "$ssh_user" ]] \
	&& error "Empty ssh user provided" ${EXIT_CODE_INVALID_ARGUMENT} ${PRINT_USAGE}

[[ -z "$ssh_server" ]] \
	&& error "Must provide an ssh server" ${EXIT_CODE_INVALID_ARGUMENT} ${PRINT_USAGE}

[[ -z "$target" ]] \
	&& error "Must provide a remote target" ${EXIT_CODE_INVALID_ARGUMENT} ${PRINT_USAGE}

# Create the connection string.
ssh_connect="${ssh_user}@${ssh_server}"

verbose_message "Checking SSH connection"
# shellcheck disable=SC2086
ssh -q -o 'BatchMode=yes' -o 'ConnectTimeout 10' ${ssh_ident} ${ssh_port} ${ssh_connect} exit > /dev/null \
	|| error "SSH connection to '${ssh_connect}' failed."

verbose_message "Creating backup directory"
# shellcheck disable=SC2029
# shellcheck disable=SC2086
ssh ${ssh_ident} ${ssh_port} ${ssh_connect} "mkdir -p ${target}/${identifier}" \
	|| error "Could not create ${target}/${identifier} on ${ssh_server}"

command_sync() {
	# shellcheck disable=SC2086
	rsync \
		${rsync_dry_run} \
		${rsync_verbose} \
		"${rsync_log_file}" \
		--progress \
		--archive \
		--compress \
		--human-readable \
		--delete \
		--delete-excluded \
		${rsync_relative} \
		${rsync_include_file} \
		${rsync_exclude_file} \
		--rsh="ssh ${ssh_ident} ${ssh_port}" \
		"${rsync_sources[@]}" \
		"${ssh_connect}:${target}/${identifier}"

	# shellcheck disable=SC2181
	if [[ "$?" -eq "0" ]]; then
		message "Sync complete"

		if "${notify}"; then
			notify-send --urgency=low --app-name="Sync" "Sync" "Sync completed"
		fi
	else
		error "Sync incomplete"
	fi
}

command_sync
