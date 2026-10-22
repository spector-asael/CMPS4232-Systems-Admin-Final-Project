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
    local TEMP_PASS="ChangeMe123!"

    if id "$USERNAME" &>/dev/null; then
        log_warn "User '$USERNAME' already exists. Skipping user creation."
    else
        # 1. Create user account
        if [[ -n "$SECONDARY_GRPS" ]]; then
            run_cmd "create user '$USERNAME'" \
                useradd -m -g "$PRIMARY_GRP" -G "$SECONDARY_GRPS" -s /bin/bash "$USERNAME"
        else
            run_cmd "create user '$USERNAME'" \
                useradd -m -g "$PRIMARY_GRP" -s /bin/bash "$USERNAME"
        fi

        # 2. Assign temporary password
        run_cmd "set temporary password for '$USERNAME'" \
            bash -c "echo '$USERNAME:$TEMP_PASS' | chpasswd"

        # 3. Force password reset on initial login (Password Aging)
        run_cmd "enforce first-login password change for '$USERNAME'" \
            chage -d 0 "$USERNAME"
    fi
}

# 1. First, let's ensure we have the correct privileges.
if [[ $EUID -ne 0 ]]; then 
	log_error "This script must be executed with root priveleges (use sudo)"
	exit 1
fi

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

# 4. Let's now provision the initial team accounts. 
# Phase 1 correction from feedback: User accounts could be automated (prompted) rather than hard coded.
log_info "Provisioning team accounts interactively..."
while true; do
    read -r -p "Enter team member username (or press Enter to finish): " TEAM_USER
    [[ -z "$TEAM_USER" ]] && break

    # Validate username format
    if [[ ! "$TEAM_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        log_error "Invalid username format. Use lowercase letters, numbers, _ or -."
        continue
    fi

    read -r -p "Enter primary group for $TEAM_USER (sysadmins/developers/auditors): " TEAM_PRIMARY
    if ! getent group "$TEAM_PRIMARY" &>/dev/null; then
        log_error "Group '$TEAM_PRIMARY' does not exist."
        continue
    fi

    read -r -p "Enter secondary groups for $TEAM_USER (comma-separated, or press Enter for none): " TEAM_SECONDARY

    create_team_user "$TEAM_USER" "$TEAM_PRIMARY" "$TEAM_SECONDARY"
done

# Phase 1 correction from feedback: Verifications can also be automated.
log_info "Running automated verification checks..."
for GRP in "${SYS_GROUPS[@]}"; do
    if ! getent group "$GRP" &>/dev/null; then
        log_error "Verification failed: Group '$GRP' does not exist."
        exit 1
    fi
    DIR="/srv/$GRP"
    if [[ ! -d "$DIR" ]]; then
        log_error "Verification failed: Directory '$DIR' does not exist."
        exit 1
    fi
    PERMS=$(stat -c "%a" "$DIR")
    if [[ "$PERMS" != "2770" ]]; then
        log_error "Verification failed: Directory '$DIR' permissions are '$PERMS' (expected 2770)."
        exit 1
    fi
    log_info "Verified group '$GRP' and directory '$DIR' (permissions: $PERMS)."
done

log_info "Environment hierarchy setup and automated verification completed successfully!"
exit 0
