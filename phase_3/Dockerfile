# Use official lightweight NGINX base image
FROM nginx:alpine

# Set container metadata & maintainer information
LABEL maintainer="sysadmins@techville.edu" \
	version="1.0.0" \
	description="TechVille System Health Dashboard Container"

# Declare application environment variables
ENV APP_TITLE="TechVille System Health Dashboard" \
	APP_VERSION="1.0.0" \
	MAINTAINER="sysadmins" \
	REFRESH_RATE="30"

# Set working directory inside container
WORKDIR /usr/share/nginx/html

# Copy baseline asset into image build context for self-containment
COPY index.html /usr/share/nginx/html/index.html

# Expose HTTP web port
EXPOSE 80

# Configure automated container health check
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost:80/ || exit 1

# Start NGINX in the foreground
CMD ["nginx", "-g", "daemon off;"]
