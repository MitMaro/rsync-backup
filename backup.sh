#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

EXIT_CODE_INVALID_STATE=2
EXIT_CODE_INVALID_ARGUMENT=3

BACKUP_DATE="$(date '+%Y-%m-%d')"
APP_ROOT="${HOME}/.local/rsync-backup"
LOG_FILE_PATH="${APP_ROOT}/logs/backup-${BACKUP_DATE}.log"
PRINT_USAGE=true
RSYNC_DRY_RUN_ARGUMENTS=( --dry-run --itemize-changes )
RSYNC_VERBOSE_ARGUMENTS=( --verbose )
RSYNC_LOG_FILE_ARGUMENTS=( --log-file="${LOG_FILE_PATH}" )
RSYNC_RELATIVE_ARGUMENTS=( --relative )
GIT_REPO="https://github.com/MitMaro/rsync-backup.git"

# define variables
index=1
verbose=false
log_to_file=false
identifier="$(hostname)"
ssh_user="$(whoami)"
ssh_server=

declare -a rsync_sources=()
declare -a rsync_exclude_file=()
declare -a rsync_include_file=()
declare -a rsync_dry_run=()
declare -a rsync_verbose=()
declare -a rsync_log_file=()
declare -a ssh_port=()
declare -a ssh_ident=()

self="$(basename "$0")"
script_path="$PWD/$self"

reset_colors() {
	C_RESET=''
	C_LOG_DATE=''
	C_HIGHLIGHT=''
	C_INFO=''
	C_VERBOSE=''
	C_WARNING=''
	C_ERROR=''
}

# only enable colors when supported
if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	C_RESET="\033[0m"
	C_LOG_DATE="\033[0;36m"
	C_HIGHLIGHT="\033[1;34m"
	C_INFO="\033[0;32m"
	C_VERBOSE="\033[0;36m"
	C_WARNING="\033[1;33m"
	C_ERROR="\033[0;31m"
else
	reset_colors
fi

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

	if [[ -n "${3-}" && "${3-}" != "false" ]]; then
		>&2 usage
	fi

	if [[ -n ${err} ]]; then
		exit "$err"
	fi
}

		install() {
	INSTALL_FILE_LOCATION="${BACKUP_INSTALL_LOCATION-"$HOME/backup.sh"}"
	INSTALL_LOCATION="$(dirname "$INSTALL_FILE_LOCATION")"

	if [[ -e "$INSTALL_FILE_LOCATION" ]]; then
		error "$INSTALL_FILE_LOCATION already exists" ${EXIT_CODE_INVALID_STATE} false
		return
	fi

	git clone "$GIT_REPO" "$INSTALL_LOCATION/backup"

	cat <<- FILE > "$INSTALL_FILE_LOCATION"
		#!/usr/bin/env bash

		export BACKUP_SERVER_IP=
		export BACKUP_IDENTIFIER=
		export BACKUP_SSH_USER=root
		export BACKUP_IDENT_FILE="$HOME/.ssh/id_ed25519"
		export BACKUP_PATHS=(
		)

		source "$(realpath "$INSTALL_LOCATION/backup/backup.sh")"
	FILE

	chmod +x "$INSTALL_FILE_LOCATION"
	message "A backup script at '$INSTALL_FILE_LOCATION' has been created. Please update the config."

	if [[ -e /etc/cron.d/backup ]]; then
		message "/etc/cron.d/backup already exists, skipping setting up con"
	else
		echo "0 */4 * * * root $INSTALL_FILE_LOCATION" > /etc/cron.d/backup
		message "The script has been configured to run using cron. See /etc/cron.d/backup."
	fi
}

check_update() {
	git_root="$(dirname "${PWD}/${BASH_SOURCE[0]}")/backup"
#	git_root="/home/mitmaro/code/active/rsync-backup/test/backup/"

	if ! git -C "$git_root" rev-parse 2> /dev/null; then
		message "Script not installed using Git, skipping update"
		return
	fi

	current_hash="$(git -C "$git_root" rev-parse HEAD)"

	git -C "$git_root" fetch origin 2> /dev/null
	git -C "$git_root" reset --hard origin/master &> /dev/null

	if [[ "$current_hash" != "$(git -C "$git_root" rev-parse HEAD)" ]]; then
		message "Script has been updated. Restarting..."
		exec "$script_path"
	fi
}

sync() {
	# parse arguments
	while (($#)); do
		case "$1" in
			-v|--verbose)
				verbose=true
				rsync_verbose=( "${RSYNC_VERBOSE_ARGUMENTS[@]}" )
				;;
			--no-color)
				reset_colors
				;;
			--dry-run)
				verbose=true
				rsync_dry_run=( "${RSYNC_DRY_RUN_ARGUMENTS[@]}" )
				;;
			--relative)
				rsync_relative=( "${RSYNC_RELATIVE_ARGUMENTS[@]}" )
				;;
			-h|--help)
				usage
				exit 0
				;;
			--log-to-file)
				message "Logging to ${LOG_FILE_PATH}"
				reset_colors # no colors for log files
				rsync_log_file=( "${RSYNC_LOG_FILE_ARGUMENTS[@]}" )
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
				ssh_port=( -p "$2" )
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
				ssh_ident=( -i "$2")
				shift
				;;
			--exclude-file)
				rsync_exclude_file=( --exclude-from="$2" )
				shift
				;;
			--include-file)
				rsync_include_file=( --include-from="$2" )
				shift
				;;
			--)
				shift
				break 2
				;;
			--*)
				error "Unexpected argument: $(highlight "$1")" ${EXIT_CODE_INVALID_ARGUMENT} ${PRINT_USAGE}
				;;
			*)
				rsync_sources[$index]="$1"
				((++index))
				;;
		esac
		shift
	done

	# anything left should be treated as sources
	while (($#)); do
		rsync_sources[$index]="$1"
		((++index))
		shift
	done

	if ${log_to_file}; then
		mkdir -p "${APP_ROOT}/logs" || error "Error creating ${APP_ROOT}/logs"
		touch "${LOG_FILE_PATH}" || error "Error creating ${LOG_FILE_PATH}"
	fi

	# check for required commands
	command -v rsync &> /dev/null \
		|| error "rsync command wasn't found; please install and ensure it's on the PATH" ${EXIT_CODE_INVALID_STATE}

	command -v ssh &> /dev/null \
		|| error "ssh command wasn't found; please install and ensure it's on the PATH" ${EXIT_CODE_INVALID_STATE}

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
	ssh -q -o 'BatchMode=yes' -o 'ConnectTimeout 10'  "${ssh_ident[@]}" "${ssh_port[@]}" "${ssh_connect}" exit > /dev/null \
		|| error "SSH connection to '${ssh_connect}' failed."

	verbose_message "Creating backup directory"
	# shellcheck disable=SC2029
	ssh "${ssh_ident[@]}" "${ssh_port[@]}" "${ssh_connect}" "mkdir -p '${target}/${identifier}'" \
		|| error "Could not create ${target}/${identifier} on ${ssh_server}"

	rsync_ssh_command=( ssh "${ssh_ident[@]}" "${ssh_port[@]}" )

	# shellcheck disable=SC2145
	rsync \
		"${rsync_dry_run[@]}" \
		"${rsync_verbose[@]}" \
		"${rsync_log_file[@]}" \
		--progress \
		--archive \
		--compress \
		--human-readable \
		--delete \
		--delete-excluded \
		"${rsync_relative[@]}" \
		"${rsync_include_file[@]}" \
		"${rsync_exclude_file[@]}" \
		--rsh="${rsync_ssh_command[@]}" \
		"${rsync_sources[@]}" \
		"${ssh_connect}:${target}/${identifier}"

	# shellcheck disable=SC2181
	if [[ "$?" -eq "0" ]]; then
		message "Sync complete"
	else
		error "Sync incomplete"
	fi
}

main() {
	if [[ "${1-}" == "install" ]]; then
		install
		return
	fi

	check_update

	[[ -z "${BACKUP_IDENTIFIER-}" ]] \
		&& error "Empty BACKUP_IDENTIFIER environment variable provided" ${EXIT_CODE_INVALID_ARGUMENT} false

	[[ -z "${BACKUP_SERVER_IP-}" ]] \
		&& error "Empty BACKUP_SERVER_IP environment variable provided" ${EXIT_CODE_INVALID_ARGUMENT} false

	SSH_USER="${BACKUP_SSH_USER:-root}"
	IDENT_FILE="${BACKUP_IDENT_FILE:-"/root/.ssh/id_ed25519"}"
	IDENTIFIER="$BACKUP_IDENTIFIER"
	IP="$BACKUP_SERVER_IP"

	if [[ -z "${BACKUP_PATHS-}" ]]; then
		BACKUP_PATHS=()
	fi

	SCRIPT="$(realpath "$0")"
	BACKUP_PATHS+=( "$SCRIPT" )

	# backup README if it exists
	if [[ -e "$HOME/README.md" ]]; then
		BACKUP_PATHS+=( "$HOME/README.md" )
	fi

	BACKUP_PATHS+=( "$HOME/.ssh" )
	BACKUP_PATHS+=( "/etc/cron.d/backup" )

	for p in "${BACKUP_PATHS[@]}"; do
		sync --verbose --relative --log-to-file --ssh-server "$IP" --identifier "$IDENTIFIER" --ssh-user "$SSH_USER" --ssh-ident "$IDENT_FILE" --target /root/backups/ "$@" "$p"
	done
}

main "$@"
