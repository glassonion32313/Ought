#!/bin/bash

# test.sh: Deploy contract to Base Sepolia testnet, test contract and bot, and provide feedback

# Exit on any error
set -euo pipefail

# Define project directory and log/report files
PROJECT_DIR="flashloan-arbitrage-base"
LOG_FILE="$PROJECT_DIR/test.log"
REPORT_FILE="$PROJECT_DIR/test_report.txt"

# Ensure log/report directories exist
mkdir -p "$PROJECT_DIR"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to add to report
report() {
    echo "$1" >> "$REPORT_FILE"
}

# Initialize log and report files
echo "Test Log - $(date)" > "$LOG_FILE"
echo "Test Report - Base Chain Flashloan Arbitrage System - $(date)" > "$REPORT_FILE"

# Check if project directory exists
if [ ! -d "$PROJECT_DIR" ]; then
    log "Error: Project directory $PROJECT_DIR not found. Please run setup.sh first."
    exit 1
fi

# Check if .env exists
if [ ! -f "$PROJECT_DIR/.env" ]; then
    log "Error: .env file not found in $PROJECT_DIR. Copy from .env.example and update values."
    exit 1
fi

# Source environment variables
set -a
source "$PROJECT_DIR/.env"
set +a

# Validate required variables
if [ -z "${BASE_SEPOLIA_RPC_URL:-}" ] || [ -z "${PRIVATE_KEY:-}" ] || [ -z "${BASESCAN_API_KEY:-}" ]; then
    log "Error: Missing required .env variables (BASE_SEPOLIA_RPC_URL, PRIVATE_KEY, BASESCAN_API_KEY)."
    exit 1
fi

cd "$PROJECT_DIR"

report "======================================"
report "Test Report for Base Sepolia Deployment"
report "======================================"
report ""

log "Starting deployment and testing on Base Sepolia..."

# Pre-deployment checks
log "Running pre-deployment checks..."
if ! python3 deploy/predeploy_check.py >> "$LOG_FILE" 2>&1; then
    log "❌ Pre-deployment checks failed"
    report "❌ Pre-deployment checks failed. See $LOG_FILE."
    exit 1
fi
log "✅ Pre-deployment checks passed"
report "✅ Pre-deployment checks passed"

# Compile contracts
log "Compiling contracts..."
if ! forge build --optimize --optimizer-runs 200 >> "$LOG_FILE" 2>&1; then
    log "❌ Contract compilation failed"
    report "❌ Contract compilation failed"
    exit 1
fi
log "✅ Contracts compiled successfully"
report "✅ Contracts compiled successfully"

# Deploy contract
log "Deploying contract to Base Sepolia..."
DEPLOY_OUTPUT=$(python3 deploy/deploy.py --network base-sepolia --verify 2>&1 | tee -a "$LOG_FILE" || true)
CONTRACT_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep -oE "0x[a-fA-F0-9]{40}" | tail -n 1)

if [ -z "$CONTRACT_ADDRESS" ]; then
    log "❌ Deployment failed"
    report "❌ Contract deployment failed"
    exit 1
fi
log "✅ Contract deployed at $CONTRACT_ADDRESS"
report "✅ Contract deployed at: $CONTRACT_ADDRESS"

# Update .env with contract address
if grep -q "^CONTRACT_ADDRESS=" .env; then
    sed -i "s/^CONTRACT_ADDRESS=.*/CONTRACT_ADDRESS=$CONTRACT_ADDRESS/" .env
else
    echo "CONTRACT_ADDRESS=$CONTRACT_ADDRESS" >> .env
fi
report "✅ .env updated with contract address"

# Run Foundry tests with fork
log "Running Foundry tests..."
if ! forge test --fork-url "$BASE_SEPOLIA_RPC_URL" >> "$LOG_FILE" 2>&1; then
    log "❌ Foundry tests failed"
    report "❌ Foundry tests failed"
else
    log "✅ Foundry tests passed"
    report "✅ Foundry tests passed"
fi

# Run Python bot test
log "Running arbitrage bot in testnet mode..."
python3 run_arbitrage.py --testnet --verbose >> "$LOG_FILE" 2>&1 &
BOT_PID=$!
sleep 300 || true   # let bot run 5 min
kill $BOT_PID 2>/dev/null || true
log "✅ Bot test run completed (5 minutes)"
report "✅ Arbitrage bot ran for 5 minutes (see $LOG_FILE for results)"

# Analyze logs
if grep -qi "error" "$LOG_FILE"; then
    report "⚠️ Errors found in log:"
    report "$(grep -i 'error' "$LOG_FILE" | tail -n 5)"
fi

if grep -qi "failed" "$LOG_FILE"; then
    report "⚠️ Failures found in log:"
    report "$(grep -i 'failed' "$LOG_FILE" | tail -n 5)"
fi

report ""
report "======================================"
report "Production Readiness Recommendations"
report "======================================"
report "1. Verify .env variables and balances"
report "2. Add more Foundry fork tests"
report "3. Review scanner.py + executor.py ABI handling"
report "4. Check slippage handling + Balancer Vault address"
report "5. Optimize Python bot performance (GPU if possible)"

log "✅ Test.sh completed successfully"
echo "Review $REPORT_FILE for results and next steps."