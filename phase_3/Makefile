# Makefile for TechVille Phase 3 Containerized NGINX Dashboard
# Enforces resource constraints, volume mounts, and port forwarding

IMAGE_NAME    := techville-dashboard:latest
CONTAINER_NAME:= health_dashboard
HOST_PORT     := 8080
CONTAINER_PORT:= 80
MEMORY_LIMIT  := 512m
HOST_VOLUME   := /srv/sysadmins/dashboard
CONTAINER_VOL := /usr/share/nginx/html

.PHONY: all setup build run stop clean logs status restart rebuild help

# Default Target: Runs setup, builds image, and launches container
all: setup build run status

## Run environment pre-flight script
setup:
	@chmod +x docker_setup.sh
	sudo ./docker_setup.sh

## Build custom Docker image using local Dockerfile
build:
	@echo "[+] Building Docker image $(IMAGE_NAME)..."
	sudo docker build -t $(IMAGE_NAME) .

## Deploy container with resource controls and volume mapping
run:
	@echo "[+] Checking if container $(CONTAINER_NAME) is running..."
	@if [ $$(sudo docker ps -q -f name=$(CONTAINER_NAME)) ]; then \
		echo "[!] Container $(CONTAINER_NAME) is already active."; \
	else \
		echo "[+] Launching $(CONTAINER_NAME)..."; \
		sudo docker run -d \
			--name $(CONTAINER_NAME) \
			--restart unless-stopped \
			--memory="$(MEMORY_LIMIT)" \
			-p $(HOST_PORT):$(CONTAINER_PORT) \
			-v $(HOST_VOLUME):$(CONTAINER_VOL) \
			$(IMAGE_NAME); \
	fi

## Stop the running container
stop:
	@echo "[-] Stopping container $(CONTAINER_NAME)..."
	-sudo docker stop $(CONTAINER_NAME)

## Stop and remove container and built image
clean: stop
	@echo "[-] Removing container $(CONTAINER_NAME)..."
	-sudo docker rm $(CONTAINER_NAME)
	@echo "[-] Removing image $(IMAGE_NAME)..."
	-sudo docker rmi $(IMAGE_NAME)

## Restart active container
restart: stop run

## Full cleanup and clean rebuild
rebuild: clean build run

## View real-time container log output
logs:
	sudo docker logs -f $(CONTAINER_NAME)

## Verify running process metrics and HTTP endpoint responsiveness
status:
	@echo "=================================================="
	@echo "            CONTAINER EXECUTION STATUS            "
	@echo "=================================================="
	@sudo docker ps -f name=$(CONTAINER_NAME)
	@echo ""
	@echo "=================================================="
	@echo "             LOCAL HTTP VERIFICATION              "
	@echo "=================================================="
	@curl -I http://localhost:$(HOST_PORT) || echo "[!] Port $(HOST_PORT) check failed."

## Display available Makefile targets
help:
	@echo "Available commands:"
	@echo "  make setup    - Run setup script to prepare directories & permissions"
	@echo "  make build    - Build the custom Docker image"
	@echo "  make run      - Run the container with 512M limit & volume mounts"
	@echo "  make stop     - Stop the running container"
	@echo "  make restart  - Restart the container"
	@echo "  make clean    - Stop & remove container and image"
	@echo "  make status   - Inspect container process state and test HTTP port"
	@echo "  make logs     - View tailing logs of the container"
