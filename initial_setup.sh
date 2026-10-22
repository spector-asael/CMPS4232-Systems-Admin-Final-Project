#!/bin/bash
# Filename:  initial_setup.sh
# The purpose of this file is to create the initial environment needed for the project

# First, let's define some helper functions that will be used for formatted logging.
# \e[32m = GREEN output
# \e[33m = YELLOW output
# \e[31m = RED output
# \e[0m = RESET colour
# Generic logging helper functions.
log_info() { echo -e "\e[32m[INFO]\e[0m $1"; }
log_warn() { echo -e "\e[33m[WARN]\e[0m $1"; }
log_error() { echo -e "\e[31m[ERROR]\e[0m $1 " >&2; }

# Helper function to check command success and abort on failure 

run_cmd() {
	local DESCRIPTION="$1"
	# ${@:2} slices everything from the 2nd argument onward 
	# Check if both are successful in the if statement
	if "${@:2}"; then
		log_info "Successfully $DESCRIPTION."
	else
		log_error "Failed to $DESCRIPTION."
		exit 1
	fi
}

# Helper function to create team users idempotently with password aging
create_team_user() {
    local USERNAME="$1"
    local PRIMARY_GRP="$2"
    local SECONDARY_GRPS="$3"
    local TEMP_PASS=""
    local TEMP_PASS_CONFIRM=""

    if id "$USERNAME" &>/dev/null; then
        # Keep existing accounts but correct their group memberships to match the defined hierarchy.
        run_cmd "correct group membership for existing user '$USERNAME'" \
            usermod -g "$PRIMARY_GRP" -G "$SECONDARY_GRPS" "$USERNAME"
        log_warn "User '$USERNAME' already exists. Password was not changed."
    else
        # Prompt for an initial password instead of using a hardcoded shared password.
        while true; do
            if ! read -r -s -p "Enter initial password for $USERNAME (minimum 8 characters): " TEMP_PASS; then
                echo
                log_error "Password input ended unexpectedly."
                return 1
            fi
            echo
            if ! read -r -s -p "Confirm initial password for $USERNAME: " TEMP_PASS_CONFIRM; then
                echo
                unset TEMP_PASS TEMP_PASS_CONFIRM
                log_error "Password confirmation input ended unexpectedly."
                return 1
            fi
            echo
            if [[ ${#TEMP_PASS} -lt 8 ]]; then
                log_error "Password must be at least 8 characters."
            elif [[ "$TEMP_PASS" != "$TEMP_PASS_CONFIRM" ]]; then
                log_error "Passwords do not match."
            else
                break
            fi
            unset TEMP_PASS TEMP_PASS_CONFIRM
        done
        unset TEMP_PASS_CONFIRM

        # 1. Create user account
        if ! useradd -m -g "$PRIMARY_GRP" -G "$SECONDARY_GRPS" -s /bin/bash "$USERNAME"; then
            unset TEMP_PASS
            log_error "Failed to create user '$USERNAME'."
            return 1
        fi

        # 2. Assign temporary password
        if ! printf '%s:%s\n' "$USERNAME" "$TEMP_PASS" | chpasswd; then
            unset TEMP_PASS
            userdel -r "$USERNAME" &>/dev/null || log_error "Could not remove incomplete account '$USERNAME'."
            log_error "Failed to set password for '$USERNAME'."
            return 1
        fi
        unset TEMP_PASS

        # 3. Force password reset on initial login (Password Aging)
        if ! chage -d 0 "$USERNAME"; then
            userdel -r "$USERNAME" &>/dev/null || log_error "Could not remove incomplete account '$USERNAME'."
            log_error "Failed to enforce first-login password change for '$USERNAME'."
            return 1
        fi
    fi
}

# 1. First, let's ensure we have the correct privileges.
if [[ $EUID -ne 0 ]]; then 
	log_error "This script must be executed with root priveleges (use sudo)"
	exit 1
fi

# Set up persistent logging with separate, timestamped stdout and stderr records.
LOG_FILE="/var/log/initial_setup.log"
if ! touch "$LOG_FILE"; then
    log_error "Could not create $LOG_FILE."
    exit 1
fi
chmod 640 "$LOG_FILE" || exit 1
exec > >(while IFS= read -r LINE || [[ -n "$LINE" ]]; do
    printf '[%s] [STDOUT] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$LINE" | tee -a "$LOG_FILE"
done) 2> >(while IFS= read -r LINE || [[ -n "$LINE" ]]; do
    printf '[%s] [STDERR] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$LINE" | tee -a "$LOG_FILE" >&2
done)

# 2. Then, let's create the secondary system groups

SYS_GROUPS=("sysadmins" "developers" "auditors")

for GRP in "${SYS_GROUPS[@]}"; do
	if getent group "$GRP" &>/dev/null; then
		log_warn "Group '$GRP' already exists. Skipping creation."
	else 
		run_cmd "create group '$GRP'" groupadd "$GRP"
	fi
done

# 3. Let's now provision shared directories under /srv/ and assign permissions (SGID + 770)
for GRP in "${SYS_GROUPS[@]}"; do
    DIR="/srv/$GRP"

    if [[ ! -d "$DIR" ]]; then
        run_cmd "create directory '$DIR'" mkdir -p "$DIR"
    else
        log_warn "Directory '$DIR' already exists."
    fi

    # Set strict ownership and permissions
    run_cmd "set ownership root:$GRP on '$DIR'" chown root:"$GRP" "$DIR"
    run_cmd "set permissions 2770 on '$DIR'" chmod 2770 "$DIR"
done

# 4. Let's now provision the initial team accounts. We will make 3.

# Member 1: Primary 'sysadmins' | Secondary 'developers' AND 'auditors' (Multiple)
create_team_user "asael" "sysadmins" "developers,auditors" || exit 1

# Member 2: Primary 'developers' | Secondary 'sysadmins' (Single)
create_team_user "teryn" "developers" "sysadmins" || exit 1

# Member 3: Primary 'auditors' | Secondary 'developers' (Single)
create_team_user "renee" "auditors" "developers" || exit 1

# Verify the account hierarchy and the ownership and permissions of each shared directory.
for USERNAME in asael teryn renee; do
    if ! id "$USERNAME"; then
        log_error "Verification failed for user '$USERNAME'."
        exit 1
    fi
done

for GRP in "${SYS_GROUPS[@]}"; do
    DIR="/srv/$GRP"
    ACTUAL_OWNER="$(stat -c '%U' "$DIR")"
    ACTUAL_GROUP="$(stat -c '%G' "$DIR")"
    ACTUAL_MODE="$(stat -c '%a' "$DIR")"
    if [[ "$ACTUAL_OWNER" != "root" || "$ACTUAL_GROUP" != "$GRP" || "$ACTUAL_MODE" != "2770" ]]; then
        log_error "Verification failed for $DIR (owner=$ACTUAL_OWNER group=$ACTUAL_GROUP mode=$ACTUAL_MODE)."
        exit 1
    fi
    log_info "Verified $DIR: owner=root group=$GRP mode=$ACTUAL_MODE."
done

log_info "Environment hierarchy setup completed successfully!"
exit 0
