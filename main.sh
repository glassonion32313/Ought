#!/bin/bash

# main.sh: Deploy contract to Base mainnet, modify configurations, and set up for live bot execution

# Exit on any error
set -e

# Define project directory and log file
PROJECT_DIR="flashloan-arbitrage-base"
LOG_FILE="$PROJECT_DIR/mainnet.log"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check if project directory exists
if [ ! -d "$PROJECT_DIR" ]; then
    log "Error: Project directory $PROJECT_DIR not found. Please run setup.sh and population scripts first."
    exit 1
fi

# Check if .env file exists
if [ ! -f "$PROJECT_DIR/.env" ]; then
    log "Error: .env file not found. Please create one from .env.example."
    exit 1
fi

# Source .env file
source "$PROJECT_DIR/.env"

# Validate required environment variables
if [ -z "$BASE_RPC_URL" ] || [ -z "$PRIVATE_KEY" ] || [ -z "$BASESCAN_API_KEY" ]; then
    log "Error: Required environment variables (BASE_RPC_URL, PRIVATE_KEY, BASESCAN_API_KEY) not set in .env"
    exit 1
fi

# Change to project directory
cd "$PROJECT_DIR" || { log "Error: Failed to change to project directory"; exit 1; }

# Initialize log file
echo "Mainnet Log - $(date)" > "$LOG_FILE"
log "Starting deployment to Base mainnet..."

# Run pre-deployment checks
log "Running pre-deployment checks..."
if ! python3 deploy/predeploy_check.py >> "$LOG_FILE" 2>&1; then
    log "Error: Pre-deployment checks failed. Check $LOG_FILE for details."
    exit 1
fi
log "Pre-deployment checks passed!"

# Compile contracts
log "Compiling contracts..."
if ! forge build --optimize --optimizer-runs 200 >> "$LOG_FILE" 2>&1; then
    log "Error: Contract compilation failed. Check $LOG_FILE for details."
    exit 1
fi
log "Contracts compiled successfully!"

# Deploy contract to Base mainnet
log "Deploying contract to Base mainnet..."
DEPLOY_OUTPUT=$(python3 deploy/deploy.py --network base-mainnet --verify 2>&1 | tee -a "$LOG_FILE")
CONTRACT_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep "Contract address:" | awk '{print $NF}')

if [ -z "$CONTRACT_ADDRESS" ]; then
    log "Error: Contract deployment failed. Check $LOG_FILE for details."
    exit 1
fi
log "Contract deployed successfully at: $CONTRACT_ADDRESS"

# Update .env with contract address and mainnet settings
log "Updating .env for mainnet..."
if grep -q "^CONTRACT_ADDRESS=" .env; then
    sed -i "s/^CONTRACT_ADDRESS=.*/CONTRACT_ADDRESS=$CONTRACT_ADDRESS/" .env
else
    echo "CONTRACT_ADDRESS=$CONTRACT_ADDRESS" >> .env
fi
sed -i "s/^NETWORK=.*/NETWORK=base-mainnet/" .env
sed -i "s/^CHAIN_ID=.*/CHAIN_ID=8453/" .env
log ".env updated for mainnet operation."

# Validate mainnet readiness
log "Validating mainnet readiness..."
if ! python3 deploy/submit_mainnet.py >> "$LOG_FILE" 2>&1; then
    log "Error: Mainnet readiness validation failed. Check $LOG_FILE for details."
    exit 1
fi
log "Mainnet readiness validated successfully!"

# Prompt for confirmation to go live
log "WARNING: Deployment to mainnet complete. You can now run the bot live."
log "To start the bot, execute: python3 run_arbitrage.py"
read -p "Type 'CONFIRM' to acknowledge and exit: " CONFIRM
if [ "$CONFIRM" != "CONFIRM" ]; then
    log "Script cancelled."
    exit 0
fi

log "Mainnet script completed successfully!"
log "Contract address: $CONTRACT_ADDRESS"
log "Logs saved to: $LOG_FILE"
log "To run the bot live: source .env && python3 run_arbitrage.py"

# Instructions
echo -e "\nThe system is now set up for live operation on mainnet."
echo "Run 'python3 run_arbitrage.py' to start the bot (ensure venv is activated)."