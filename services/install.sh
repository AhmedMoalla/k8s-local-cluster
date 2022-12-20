#!/usr/bin/env bash
set -e

# Storage
longhorn/install.sh

# Certificate management
cert-manager/install.sh

# Vault
vault/install.sh

# Postgres
postgres/install.sh