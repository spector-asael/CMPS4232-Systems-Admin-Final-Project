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
exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)

# Append a starting message to the log.
echo "========================================" >> "$LOG_FILE"
echo "sys_init.sh started: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"


# ------------------------------------------------------------
# 3. Ask administrator for username
# ------------------------------------------------------------

while true; do
    read -r -p "Enter the new username: " USERNAME

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
    read -r -p \
        "Enter the primary group (sysadmins/developers/auditors): " \
        PRIMARY_GROUP

    # Check that the group exists.
    if ! getent group "$PRIMARY_GROUP" &>/dev/null; then
        log_error "Group '$PRIMARY_GROUP' does not exist."
        log_error "Please run initial_setup.sh first or enter a valid group."
        continue
    fi

    break
done


# ------------------------------------------------------------
# 5. Ask for secondary groups
# ------------------------------------------------------------

read -r -p \
    "Enter secondary groups (comma-separated, or press Enter for none): " \
    SECONDARY_GROUPS

# If secondary groups were entered, check that they exist.
if [[ -n "$SECONDARY_GROUPS" ]]; then

    IFS=',' read -ra GROUP_LIST <<< "$SECONDARY_GROUPS"

    for GROUP in "${GROUP_LIST[@]}"; do

        if ! getent group "$GROUP" &>/dev/null; then
            log_error "Secondary group '$GROUP' does not exist."
            exit 1
        fi

        if [[ "$GROUP" == "$PRIMARY_GROUP" ]]; then
            log_error "Primary group should not also be a secondary group."
            exit 1
        fi

    done
fi


# ------------------------------------------------------------
# 6. Ask for the initial password
# ------------------------------------------------------------

while true; do

    read -r -s -p "Enter the initial password: " PASSWORD
    echo

    read -r -s -p "Confirm the initial password: " PASSWORD_CONFIRM
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
    exit 1
fi

# Make sure the new user owns the .bashrc file.
run_cmd "set ownership of $BASHRC" \
    chown "$USERNAME:$PRIMARY_GROUP" "$BASHRC"


# ------------------------------------------------------------
# 11. Verify the account
# ------------------------------------------------------------

log_info "Verifying the new account..."

if ! id "$USERNAME"; then
    log_error "User verification failed."
    exit 1
fi

echo
log_info "Password aging information:"

if ! chage -l "$USERNAME"; then
    log_error "Could not retrieve password aging information."
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
