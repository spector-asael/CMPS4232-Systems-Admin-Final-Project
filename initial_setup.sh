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
        run_cmd "create user '$USERNAME'" \
            useradd -m -g "$PRIMARY_GRP" -G "$SECONDARY_GRPS" -s /bin/bash "$USERNAME"

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

# 4. Let's now provision the initial team accounts. We will make 3.

# Member 1: Primary 'sysadmins' | Secondary 'developers' AND 'auditors' (Multiple)
create_team_user "Asael" "sysadmins" "developers,auditors"

# Member 2: Primary 'developers' | Secondary 'sysadmins' (Single)
create_team_user "Teryn" "developers" "sysadmins"

# Member 3: Primary 'auditors' | Secondary 'developers' (Single)
create_team_user "Renee" "auditors" "developers"

log_info "Environment hierarchy setup completed successfully!"
exit 0
