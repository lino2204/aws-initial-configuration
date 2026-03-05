FROM alpine:3.19

# Install AWS CLI and utilities
RUN apk add --no-cache \
    aws-cli \
    bash \
    curl \
    jq \
    git \
    make

# Set working directory
WORKDIR /workspace

# Copy bootstrap script and Makefile
COPY bootstrap.sh ./
COPY Makefile ./

# Make bootstrap script executable
RUN chmod +x bootstrap.sh

# Create entrypoint script
RUN echo '#!/bin/bash' > /entrypoint.sh && \
    echo 'set -e' >> /entrypoint.sh && \
    echo 'exec "$@"' >> /entrypoint.sh && \
    chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["make", "help"]