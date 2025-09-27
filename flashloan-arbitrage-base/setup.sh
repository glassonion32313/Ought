#!/bin/bash

# Base Chain Flashloan Arbitrage System - Complete Setup Script
# Compatible with Kali Linux and other Debian-based systems

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "Don't run this script as root. Run as regular user."
        exit 1
    fi
}

# Install system dependencies
install_system_deps() {
    log_info "Installing system dependencies..."
    
    sudo apt update
    
    # Essential build tools and libraries
    sudo apt install -y \
        build-essential \
        curl \
        wget \
        git \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        python3-dev \
        python3-pip \
        python3-venv \
        libffi-dev \
        libssl-dev \
        pkg-config \
        libbz2-dev \
        libreadline-dev \
        libsqlite3-dev \
        libncurses5-dev \
        libncursesw5-dev \
        xz-utils \
        tk-dev \
        libxml2-dev \
        libxmlsec1-dev \
        liblzma-dev
    
    log_success "System dependencies installed"
}

# Install Node.js (required for Foundry)
install_nodejs() {
    log_info "Installing Node.js..."
    
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node --version | cut -d'v' -f2)
        log_warning "Node.js $NODE_VERSION already installed"
    else
        # Install Node.js 18.x
        curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
        sudo apt install -y nodejs
        log_success "Node.js installed"
    fi
}

# Install Python 3.11 via pyenv
install_python311() {
    log_info "Setting up Python 3.11..."
    
    # Install pyenv if not present
    if ! command -v pyenv &> /dev/null; then
        log_info "Installing pyenv..."
        curl https://pyenv.run | bash
        
        # Add pyenv to PATH
        export PYENV_ROOT="$HOME/.pyenv"
        export PATH="$PYENV_ROOT/bin:$PATH"
        eval "$(pyenv init --path)"
        eval "$(pyenv init -)"
        
        # Add to shell profile
        echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc
        echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc
        echo 'eval "$(pyenv init --path)"' >> ~/.bashrc
        echo 'eval "$(pyenv init -)"' >> ~/.bashrc
    else
        export PYENV_ROOT="$HOME/.pyenv"
        export PATH="$PYENV_ROOT/bin:$PATH"
        eval "$(pyenv init --path)"
        eval "$(pyenv init -)"
    fi
    
    # Install Python 3.11.7
    if ! pyenv versions | grep -q "3.11.7"; then
        log_info "Installing Python 3.11.7..."
        pyenv install 3.11.7
    fi
    
    # Set local Python version
    pyenv local 3.11.7
    log_success "Python 3.11.7 configured"
}

# Install Foundry (Ethereum development toolchain)
install_foundry() {
    log_info "Installing Foundry..."
    
    if command -v forge &> /dev/null; then
        log_warning "Foundry already installed"
    else
        curl -L https://foundry.paradigm.xyz | bash
        
        # Add foundry to PATH for current session
        export PATH="$HOME/.foundry/bin:$PATH"
        echo 'export PATH="$HOME/.foundry/bin:$PATH"' >> ~/.bashrc
        
        # Update foundry
        ~/.foundry/bin/foundryup
        
        log_success "Foundry installed"
    fi
}

# Create project structure
create_project_structure() {
    log_info "Creating project structure..."
    
    # Create directories
    mkdir -p contracts/interfaces
    mkdir -p scanner/{core,utils}
    mkdir -p deploy
    mkdir -p test
    
    log_success "Project structure created"
}

# Setup Python environment
setup_python_env() {
    log_info "Setting up Python virtual environment..."
    
    # Make sure we're using Python 3.11
    python --version
    
    # Create virtual environment
    python -m venv venv
    source venv/bin/activate
    
    # Upgrade pip and setuptools
    pip install --upgrade pip setuptools==69.5.1 wheel
    
    log_success "Python virtual environment created"
}

# Install Python dependencies with error handling
install_python_deps() {
    log_info "Installing Python dependencies..."
    
    # Activate virtual environment
    source venv/bin/activate
    
    # Create updated requirements.txt
    cat > requirements.txt << 'EOF'
# Core Web3 and Ethereum dependencies
web3==6.15.1
eth-account==0.11.0
eth-abi==4.2.1
hexbytes==1.0.0

# Async HTTP client
aiohttp==3.9.1
websockets==12.0

# Environment and configuration
python-dotenv==1.0.0

# Numerical computing
numpy==1.26.2

# Cryptography
cryptography>=41.0.0

# Additional utilities
asyncio-throttle==1.0.2
tenacity==8.2.3

# Development and testing
pytest>=7.4.0
pytest-asyncio>=0.21.0
EOF
    
    # Install packages one by one to handle errors better
    log_info "Installing core Web3 dependencies..."
    pip install web3==6.15.1 eth-account==0.11.0 python-dotenv==1.0.0
    
    log_info "Installing async dependencies..."
    pip install aiohttp==3.9.1 websockets==12.0
    
    log_info "Installing remaining dependencies..."
    pip install numpy==1.26.2 eth-abi==4.2.1 hexbytes==1.0.0 cryptography
    
    log_info "Installing utility packages..."
    pip install asyncio-throttle==1.0.2 tenacity==8.2.3
    
    log_success "Python dependencies installed"
}

# Initialize Foundry project
init_foundry() {
    log_info "Initializing Foundry project..."
    
    # Add foundry to PATH
    export PATH="$HOME/.foundry/bin:$PATH"
    
    # Initialize if not already done
    if [ ! -f "foundry.toml" ]; then
        forge init --no-git --no-commit
    fi
    
    # Install OpenZeppelin contracts
    forge install OpenZeppelin/openzeppelin-contracts-upgradeable --no-git --no-commit
    forge install OpenZeppelin/openzeppelin-contracts --no-git --no-commit
    
    log_success "Foundry project initialized"
}

# Create configuration files
create_config_files() {
    log_info "Creating configuration files..."
    
    # Create .env.example
    cat > .env.example << 'EOF'
# RPC Configuration
RPC_URLS=https://mainnet.base.org,https://base-mainnet.g.alchemy.com/v2/YOUR_KEY
WS_RPC_URL=wss://base-mainnet.g.alchemy.com/v2/YOUR_KEY
BASE_RPC_URL=https://mainnet.base.org
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org

# Account Configuration
PRIVATE_KEY=your_private_key_here

# Contract Configuration
CONTRACT_ADDRESS=

# Token Configuration
TOKEN_LIST=0x4200000000000000000000000000000000000006,0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA

# Profit Configuration
MIN_PROFIT_THRESHOLD=10000000000000000
MAX_GAS_PRICE_GWEI=100

# Features
USE_GPU=false
ENABLE_MEMPOOL=false

# Logging
LOG_LEVEL=INFO
LOG_FILE=arbitrage.log

# Network
CHAIN_ID=8453
NETWORK=base-mainnet

# API Keys
BASESCAN_API_KEY=your_basescan_api_key_here
EOF

    # Create foundry.toml
    cat > foundry.toml << 'EOF'
[profile.default]
src = "contracts"
out = "out"
libs = ["lib"]
optimizer = true
optimizer_runs = 200
solc = "0.8.19"
eth_rpc_url = "${RPC_URL}"
etherscan_api_key = "${BASESCAN_API_KEY}"

[rpc_endpoints]
base = "${BASE_RPC_URL}"
base_sepolia = "${BASE_SEPOLIA_RPC_URL}"

[etherscan]
base = { key = "${BASESCAN_API_KEY}", url = "https://api.basescan.org/api" }
base_sepolia = { key = "${BASESCAN_API_KEY}", url = "https://api-sepolia.basescan.org/api" }
EOF

    # Create .gitignore
    cat > .gitignore << 'EOF'
# Environment
.env
venv/
__pycache__/
*.pyc
*.pyo
*.pyd
.Python

# Foundry
out/
cache/
broadcast/

# Logs
*.log

# IDE
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db
EOF

    log_success "Configuration files created"
}

# Test installation
test_installation() {
    log_info "Testing installation..."
    
    # Test Python dependencies
    source venv/bin/activate
    python -c "
import web3
import eth_account
import aiohttp
import numpy
print('Python dependencies: OK')
print(f'Web3.py version: {web3.__version__}')
"
    
    # Test Foundry
    export PATH="$HOME/.foundry/bin:$PATH"
    forge --version
    
    log_success "All tests passed!"
}

# Main installation function
main() {
    log_info "Starting Base Chain Flashloan Arbitrage System setup..."
    
    check_root
    
    # Step 1: System dependencies
    install_system_deps
    
    # Step 2: Node.js (required for Foundry)
    install_nodejs
    
    # Step 3: Python 3.11
    install_python311
    
    # Step 4: Foundry
    install_foundry
    
    # Step 5: Project structure
    create_project_structure
    
    # Step 6: Python environment
    setup_python_env
    
    # Step 7: Python dependencies
    install_python_deps
    
    # Step 8: Foundry setup
    init_foundry
    
    # Step 9: Configuration files
    create_config_files
    
    # Step 10: Test everything
    test_installation
    
    # Final instructions
    echo
    log_success "Setup completed successfully!"
    echo
    log_info "Next steps:"
    echo "1. Copy .env.example to .env and configure your settings:"
    echo "   cp .env.example .env"
    echo
    echo "2. Activate the virtual environment:"
    echo "   source venv/bin/activate"
    echo
    echo "3. Add the following to your ~/.bashrc and restart terminal:"
    echo "   export PYENV_ROOT=\"\$HOME/.pyenv\""
    echo "   export PATH=\"\$PYENV_ROOT/bin:\$PATH\""
    echo "   eval \"\$(pyenv init --path)\""
    echo "   eval \"\$(pyenv init -)\""
    echo "   export PATH=\"\$HOME/.foundry/bin:\$PATH\""
    echo
    echo "4. Test the setup:"
    echo "   python deploy/predeploy_check.py"
    echo
    log_warning "Remember to configure your .env file with your private key and RPC URLs before running!"
}

# Run main function
main "$@"