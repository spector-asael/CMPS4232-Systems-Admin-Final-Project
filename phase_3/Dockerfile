# Use official lightweight NGINX base image
FROM nginx:alpine

# Set container metadata & maintainer information
LABEL maintainer="sysadmins@techville.edu"

# Declare application environment variables
ENV APP_TITLE="TechVille System Health Dashboard" \
    APP_VERSION="1.0.0" \
    MAINTAINER="sysadmins" \
    REFRESH_RATE="30"

# Set working directory inside container
WORKDIR /usr/share/nginx/html

# Expose HTTP web port
EXPOSE 80

# Start NGINX in the foreground
CMD ["nginx", "-g", "daemon off;"]
