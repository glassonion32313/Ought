#!/bin/bash

# test.sh: Deploy contract to Base Sepolia testnet, test contract and bot, and provide feedback

# Exit on any error
set -e

# Define project directory and log file
PROJECT_DIR="flashloan-arbitrage-base"
LOG_FILE="$PROJECT_DIR/test.log"
REPORT_FILE="$PROJECT_DIR/test_report.txt"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to add to report
report() {
    echo "$1" >> "$REPORT_FILE"
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
if [ -z "$BASE_SEPOLIA_RPC_URL" ] || [ -z "$PRIVATE_KEY" ] || [ -z "$BASESCAN_API_KEY" ]; then
    log "Error: Required environment variables (BASE_SEPOLIA_RPC_URL, PRIVATE_KEY, BASESCAN_API_KEY) not set in .env"
    exit 1
fi

# Change to project directory
cd "$PROJECT_DIR" || { log "Error: Failed to change to project directory"; exit 1; }

# Initialize log and report files
echo "Test Log - $(date)" > "$LOG_FILE"
echo "Test Report - Base Chain Flashloan Arbitrage System - $(date)" > "$REPORT_FILE"
report "======================================"
report "Test Report for Base Sepolia Deployment"
report "======================================"
report ""
log "Starting deployment and testing on Base Sepolia..."

# Run pre-deployment checks
log "Running pre-deployment checks..."
if ! python3 deploy/predeploy_check.py >> "$LOG_FILE" 2>&1; then
    log "Error: Pre-deployment checks failed. Check $LOG_FILE for details."
    report "❌ Pre-deployment checks failed. See test.log for details."
    report "Recommendation: Verify RPC_URLS, PRIVATE_KEY, and account balance. Ensure sufficient testnet ETH."
    exit 1
fi
log "Pre-deployment checks passed!"
report "✅ Pre-deployment checks passed."

# Compile contracts
log "Compiling contracts..."
if ! forge build --optimize --optimizer-runs 200 >> "$LOG_FILE" 2>&1; then
    log "Error: Contract compilation failed. Check $LOG_FILE for details."
    report "❌ Contract compilation failed."
    report "Recommendation: Check for syntax errors in FlashLoanArbitrage.sol and test/FlashLoanArbitrage.t.sol."
    report "Potential issue: Invalid comment syntax ('#') in test file. Replace with '//'."
    exit 1
fi
log "Contracts compiled successfully!"
report "✅ Contracts compiled successfully."

# Deploy contract to Base Sepolia
log "Deploying contract to Base Sepolia testnet..."
DEPLOY_OUTPUT=$(python3 deploy/deploy.py --network base-sepolia --verify 2>&1 | tee -a "$LOG_FILE")
CONTRACT_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep "Contract address:" | awk '{print $NF}')

if [ -z "$CONTRACT_ADDRESS" ]; then
    log "Error: Contract deployment failed. Check $LOG_FILE for details."
    report "❌ Contract deployment failed."
    report "Recommendation: Ensure sufficient testnet ETH and valid BASE_SEPOLIA_RPC_URL = https://sepolia.base.org, Chain ID 84532."
    exit 1
fi
log "Contract deployed successfully at: $CONTRACT_ADDRESS"
report "✅ Contract deployed at: $CONTRACT_ADDRESS"

# Update .env with contract address
log "Updating .env with contract address..."
if grep -q "^CONTRACT_ADDRESS=" .env; then
    sed -i "s/^CONTRACT_ADDRESS=.*/CONTRACT_ADDRESS=$CONTRACT_ADDRESS/" .env
else
    echo "CONTRACT_ADDRESS=$CONTRACT_ADDRESS" >> .env
fi
report "✅ .env updated with contract address."

# Run Foundry tests
log "Running Foundry test suite..."
if ! forge test --fork-url $BASE_SEPOLIA_RPC_URL >> "$LOG_FILE" 2>&1; then
    log "Warning: Foundry tests failed. Check $LOG_FILE for details."
    report "❌ Foundry tests failed."
    report "Recommendation: Fix syntax errors in test/FlashLoanArbitrage.t.sol (replace '#' with '//')."
    report "Add more tests for flashloan execution and swaps using --fork-url."
else
    log "All Foundry tests passed successfully!"
    report "✅ All Foundry tests passed."
fi

# Run Python bot tests in full mode (scan and execute) on testnet
log "Starting arbitrage bot in full testnet mode for thorough testing..."
if ! python3 run_arbitrage.py --testnet --verbose >> "$LOG_FILE" 2>&1 & then
    log "Error: Failed to start arbitrage bot in test mode. Check $LOG_FILE for details."
    report "❌ Bot test failed."
    report "Recommendation: Check scanner.py for Web3 connection issues or invalid ABI in _encode_swap_data."
    exit 1
else
    BOT_PID=$!
    log "Arbitrage bot started in background (PID: $BOT_PID). Running for 300 seconds to test execution..."
    report "✅ Bot started in full mode (PID: $BOT_PID)."
    sleep 300  # Run for 5 minutes to allow scanning and potential executions
    kill $BOT_PID 2>/dev/null || log "Warning: Bot process already terminated."
    log "Bot test completed."
    report "Bot ran for 300 seconds. Check test.log for scan and execution results."
fi

# Analyze logs for issues
log "Analyzing logs for common issues..."
if grep -qi "error" "$LOG_FILE"; then
    report "⚠️ Errors found in test.log:"
    report "$(grep -i "error" "$LOG_FILE" | tail -n 5)"
    report "Recommendation: Review test.log for specific error messages."
fi
if grep -qi "failed" "$LOG_FILE"; then
    report "⚠️ Failures found in test.log:"
    report "$(grep -i "failed" "$LOG_FILE" | tail -n 5)"
    report "Recommendation: Address failures in contract or bot execution."
fi
if grep -qi "AttributeError" "$LOG_FILE"; then
    report "⚠️ Python AttributeError detected."
    report "Likely cause: Incomplete ABI in scanner.py or executor.py."
    report "Recommendation: Update factory_abi in scanner.py with full Uniswap V2 factory ABI."
fi

# Production readiness recommendations
report ""
report "======================================"
report "Production Readiness Recommendations"
report "======================================"
report ""
report "1. Fix Syntax Errors:"
report "   - Replace '#' with '//' in test/FlashLoanArbitrage.t.sol."
report "   - Add fork tests for flashloan and swap execution."
report "2. Complete ABI Definitions:"
report "   - Fix factory_abi in scanner.py to include proper 'allPairsLength' and 'allPairs'."
report "3. Improve Swap Encoding:"
report "   - Update _encode_swap_data to use web3.eth.abi.encode for actual router calls."
report "4. Add Python Tests:"
report "   - Implement unit tests with pytest for scanner and executor."
report "5. Security Enhancements:"
report "   - Add slippage checks in ArbitrageParams."
report "   - Confirm Balancer Vault address 0xBA12222222228d8Ba445958a75a0704d566BF2C8 on Base Sepolia."
report "6. Performance:"
report "   - Test with USE_GPU=true if CUDA available."
report "7. Once fixed, re-run test.sh and proceed to main.sh."

log "Test script completed! Deployment and tests done on Base Sepolia."
log "Contract address: $CONTRACT_ADDRESS"
log "Logs saved to: $LOG_FILE"
log "Feedback report saved to: $REPORT_FILE"

# Instructions
echo -e "\nReview $REPORT_FILE for feedback and recommendations to make the bot production-ready."
echo "Once fixed, re-run test.sh and then main.sh for live deployment."