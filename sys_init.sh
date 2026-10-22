#!/bin/bash
# Filename: sys_init.sh
# The purpose of this file is to interactively create and configure
# a new user account for the project.

# ------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------

# Generic logging helper functions.
log_info() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] \e[32m[INFO]\e[0m $1"
}

log_warn() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] \e[33m[WARN]\e[0m $1"
}

log_error() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] \e[31m[ERROR]\e[0m $1" >&2
}

# Helper function to check command success.
run_cmd() {
    local DESCRIPTION="$1"

    if "${@:2}"; then
        log_info "Successfully $DESCRIPTION."
    else
        log_error "Failed to $DESCRIPTION."
        exit 1
    fi
}


# ------------------------------------------------------------
# 1. Check for root privileges
# ------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    log_error "This script must be executed with root privileges (use sudo)."
    exit 1
fi


# ------------------------------------------------------------
# 2. Set up logging
# ------------------------------------------------------------

LOG_FILE="/var/log/sys_init.log"

# Make sure the log file exists.
touch "$LOG_FILE" 2>/dev/null

if [[ $? -ne 0 ]]; then
    log_error "Could not create $LOG_FILE."
    exit 1
fi

# Set permissions so normal users cannot modify the log.
chmod 640 "$LOG_FILE"

# Redirect standard output and standard error to the log file.
# tee allows the output to still be displayed on the terminal.
# Each stream is labelled and timestamped separately for easier verification.
exec > >(while IFS= read -r LINE || [[ -n "$LINE" ]]; do
    printf '[%s] [STDOUT] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$LINE" | tee -a "$LOG_FILE"
done) 2> >(while IFS= read -r LINE || [[ -n "$LINE" ]]; do
    printf '[%s] [STDERR] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$LINE" | tee -a "$LOG_FILE" >&2
done)

# Append a starting message to the log.
echo "========================================" >> "$LOG_FILE"
echo "sys_init.sh started: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"


# ------------------------------------------------------------
# 3. Ask administrator for username
# ------------------------------------------------------------

while true; do
    if ! read -r -p "Enter the new username: " USERNAME; then
        log_error "Input ended unexpectedly."
        exit 1
    fi

    if [[ -z "$USERNAME" ]]; then
        log_error "Username cannot be empty."
        continue
    fi

    # Check that the username contains acceptable characters.
    if [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        log_error "Invalid username. Use lowercase letters, numbers, _ or -."
        continue
    fi

    # Check if the user already exists.
    if id "$USERNAME" &>/dev/null; then
        log_error "User '$USERNAME' already exists."
        continue
    fi

    break
done


# ------------------------------------------------------------
# 4. Ask administrator for primary group
# ------------------------------------------------------------

while true; do
    if ! read -r -p \
        "Enter the primary group (sysadmins/developers/auditors): " \
        PRIMARY_GROUP; then
        log_error "Input ended unexpectedly."
        exit 1
    fi

    # Check that the group exists.
    if [[ ! "$PRIMARY_GROUP" =~ ^(sysadmins|developers|auditors)$ ]] || ! getent group "$PRIMARY_GROUP" &>/dev/null; then
        log_error "Group '$PRIMARY_GROUP' does not exist or is not an allowed project group."
        log_error "Please run initial_setup.sh first or enter a valid group."
        continue
    fi

    break
done


# ------------------------------------------------------------
# 5. Ask for secondary groups
# ------------------------------------------------------------

# If secondary groups were entered, check that they exist.
while true; do
    if ! read -r -p \
        "Enter secondary groups (comma-separated, or press Enter for none): " \
        SECONDARY_GROUPS; then
        log_error "Input ended unexpectedly."
        exit 1
    fi

    GROUP_LIST=()
    VALID_GROUPS=true
    if [[ -n "$SECONDARY_GROUPS" ]]; then
        IFS=',' read -ra RAW_GROUP_LIST <<< "$SECONDARY_GROUPS"
        declare -A SEEN_GROUPS=()
        for GROUP in "${RAW_GROUP_LIST[@]}"; do
            GROUP="${GROUP//[[:space:]]/}"
            if [[ -z "$GROUP" ]]; then
                log_error "Empty secondary-group entry. Please try again."
                VALID_GROUPS=false
                break
            fi
            if [[ ! "$GROUP" =~ ^(sysadmins|developers|auditors)$ ]] || ! getent group "$GROUP" &>/dev/null; then
                log_error "Secondary group '$GROUP' does not exist or is not an allowed project group."
                VALID_GROUPS=false
                break
            fi
            if [[ "$GROUP" == "$PRIMARY_GROUP" ]]; then
                log_error "Primary group should not also be a secondary group."
                VALID_GROUPS=false
                break
            fi
            if [[ -n "${SEEN_GROUPS[$GROUP]+present}" ]]; then
                log_error "Secondary group '$GROUP' was entered more than once."
                VALID_GROUPS=false
                break
            fi
            SEEN_GROUPS["$GROUP"]=1
            GROUP_LIST+=("$GROUP")
        done
    fi
    if [[ "$VALID_GROUPS" == true ]]; then
        SECONDARY_GROUPS="$(IFS=,; printf '%s' "${GROUP_LIST[*]}")"
        break
    fi
done


# ------------------------------------------------------------
# 6. Ask for the initial password
# ------------------------------------------------------------

while true; do

    if ! read -r -s -p "Enter the initial password: " PASSWORD; then
        echo
        log_error "Password input ended unexpectedly."
        exit 1
    fi
    echo

    if ! read -r -s -p "Confirm the initial password: " PASSWORD_CONFIRM; then
        echo
        unset PASSWORD PASSWORD_CONFIRM
        log_error "Password confirmation input ended unexpectedly."
        exit 1
    fi
    echo

    if [[ -z "$PASSWORD" ]]; then
        log_error "Password cannot be empty."
        continue
    fi

    if [[ "$PASSWORD" != "$PASSWORD_CONFIRM" ]]; then
        log_error "Passwords do not match."
        continue
    fi

    if [[ ${#PASSWORD} -lt 8 ]]; then
        log_error "Password must be at least 8 characters."
        continue
    fi

    break
done


# ------------------------------------------------------------
# 7. Create the new user
# ------------------------------------------------------------

log_info "Creating user '$USERNAME'..."

if [[ -n "$SECONDARY_GROUPS" ]]; then

    run_cmd "create user '$USERNAME'" \
        useradd -m -g "$PRIMARY_GROUP" -G "$SECONDARY_GROUPS" \
        -s /bin/bash "$USERNAME"

else

    run_cmd "create user '$USERNAME'" \
        useradd -m -g "$PRIMARY_GROUP" \
        -s /bin/bash "$USERNAME"

fi


# ------------------------------------------------------------
# 8. Set the initial password
# ------------------------------------------------------------

log_info "Setting initial password for '$USERNAME'."

if echo "$USERNAME:$PASSWORD" | chpasswd 2>> "$LOG_FILE"; then
    log_info "Initial password assigned successfully."
else
    log_error "Failed to set the password."
    userdel -r "$USERNAME" &>/dev/null
    exit 1
fi

# Clear the password variables from memory.
unset PASSWORD
unset PASSWORD_CONFIRM


# ------------------------------------------------------------
# 9. Force password change on first login
# ------------------------------------------------------------

run_cmd "force password change for '$USERNAME'" \
    chage -d 0 "$USERNAME"


# ------------------------------------------------------------
# 10. Customize the user's .bashrc file
# ------------------------------------------------------------

USER_HOME="/home/$USERNAME"
BASHRC="$USER_HOME/.bashrc"

if [[ ! -f "$BASHRC" ]]; then
    log_error "Could not find $BASHRC."
    userdel -r "$USERNAME" &>/dev/null || log_error "Could not remove incomplete account '$USERNAME'."
    exit 1
fi

# Add aliases and a customized shell prompt.
if cat >> "$BASHRC" <<'EOF'

# Custom settings added by sys_init.sh
alias ll='ls -alF'
alias la='ls -A'
alias ..='cd ..'

PS1='\[\e[36m\]\u@\h\[\e[0m\]:\[\e[32m\]\w\[\e[0m\]\$ '
EOF
then
    log_info "Custom aliases and prompt added to $BASHRC."
else
    log_error "Failed to update $BASHRC."
    userdel -r "$USERNAME" &>/dev/null || log_error "Could not remove incomplete account '$USERNAME'."
    exit 1
fi

# Make sure the new user owns the .bashrc file.
if ! chown "$USERNAME:$PRIMARY_GROUP" "$BASHRC"; then
    log_error "Failed to set ownership of $BASHRC."
    userdel -r "$USERNAME" &>/dev/null || log_error "Could not remove incomplete account '$USERNAME'."
    exit 1
fi


# ------------------------------------------------------------
# 11. Verify the account
# ------------------------------------------------------------

log_info "Verifying the new account..."

if ! id "$USERNAME"; then
    log_error "User verification failed."
    userdel -r "$USERNAME" &>/dev/null || log_error "Could not remove incomplete account '$USERNAME'."
    exit 1
fi

ACTUAL_PRIMARY_GROUP="$(id -gn "$USERNAME")"
ACTUAL_SHELL="$(getent passwd "$USERNAME" | cut -d: -f7)"
ACTUAL_HOME="$(getent passwd "$USERNAME" | cut -d: -f6)"
if [[ "$ACTUAL_PRIMARY_GROUP" != "$PRIMARY_GROUP" || "$ACTUAL_SHELL" != "/bin/bash" || ! -d "$ACTUAL_HOME" ]]; then
    log_error "Primary group, login shell, or home-directory verification failed."
    userdel -r "$USERNAME" &>/dev/null || log_error "Could not remove incomplete account '$USERNAME'."
    exit 1
fi
if [[ "$(stat -c '%U:%G' "$BASHRC")" != "$USERNAME:$PRIMARY_GROUP" ]]; then
    log_error ".bashrc ownership verification failed."
    userdel -r "$USERNAME" &>/dev/null || log_error "Could not remove incomplete account '$USERNAME'."
    exit 1
fi

echo
log_info "Password aging information:"

if ! chage -l "$USERNAME"; then
    log_error "Could not retrieve password aging information."
    userdel -r "$USERNAME" &>/dev/null || log_error "Could not remove incomplete account '$USERNAME'."
    exit 1
fi


# ------------------------------------------------------------
# 12. Finish
# ------------------------------------------------------------

echo
log_info "User provisioning completed successfully."
log_info "Username: $USERNAME"
log_info "Primary group: $PRIMARY_GROUP"
log_info "Secondary groups: ${SECONDARY_GROUPS:-none}"
log_info "Log file: $LOG_FILE"

echo "sys_init.sh completed: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"

exit 0
