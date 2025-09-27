#!/bin/bash

# Base Chain Flashloan Arbitrage System - Complete Setup Script
# Compatible with Kali Linux and other Debian-based systems
# Modified to remove sudo for non-root VMs

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

# Install system dependencies (without sudo)
install_system_deps() {
    log_info "Installing system dependencies (without sudo)..."
    
    apt update || log_warning "apt update failed (may require sudo, skipping)"
    
    # Essential build tools and libraries
    apt install -y \
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
        liblzma-dev || log_warning "Some packages may require sudo, skipping..."
    
    log_success "System dependencies step completed (may not have installed everything)"
}

# Install Node.js (required for Foundry) (without sudo)
install_nodejs() {
    log_info "Installing Node.js..."
    
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node --version | cut -d'v' -f2)
        log_warning "Node.js $NODE_VERSION already installed"
    else
        curl -fsSL https://deb.nodesource.com/setup_18.x | bash - || log_warning "Node.js setup script requires sudo, skipping"
        apt install -y nodejs || log_warning "Node.js installation may require sudo, skipping"
        log_success "Node.js installed (or skipped)"
    fi
}

# Install Python 3.11 via pyenv
install_python311() {
    log_info "Setting up Python 3.11..."
    
    if ! command -v pyenv &> /dev/null; then
        log_info "Installing pyenv..."
        curl https://pyenv.run | bash
        
        export PYENV_ROOT="$HOME/.pyenv"
        export PATH="$PYENV_ROOT/bin:$PATH"
        eval "$(pyenv init --path)"
        eval "$(pyenv init -)"
        
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
    
    if ! pyenv versions | grep -q "3.11.7"; then
        log_info "Installing Python 3.11.7..."
        pyenv install 3.11.7
    fi
    
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
        export PATH="$HOME/.foundry/bin:$PATH"
        echo 'export PATH="$HOME/.foundry/bin:$PATH"' >> ~/.bashrc
        ~/.foundry/bin/foundryup
        log_success "Foundry installed"
    fi
}

# Create project structure
create_project_structure() {
    log_info "Creating project structure..."
    
    mkdir -p contracts/interfaces
    mkdir -p scanner/{core,utils}
    mkdir -p deploy
    mkdir -p test
    
    log_success "Project structure created"
}

# Setup Python environment
setup_python_env() {
    log_info "Setting up Python virtual environment..."
    
    python --version
    python -m venv venv
    source venv/bin/activate
    pip install --upgrade pip setuptools==69.5.1 wheel
    
    log_success "Python virtual environment created"
}

# Install Python dependencies
install_python_deps() {
    log_info "Installing Python dependencies..."
    
    source venv/bin/activate
    
    cat > requirements.txt << 'EOF'
web3==6.15.1
eth-account==0.11.0
eth-abi==4.2.1
hexbytes>=0.1.0,<0.4.0
aiohttp==3.9.1
websockets==12.0
python-dotenv==1.0.0
numpy==1.26.2
cryptography>=41.0.0
asyncio-throttle==1.0.2
tenacity==8.2.3
pytest>=7.4.0
pytest-asyncio>=0.21.0
EOF
    
    pip install -r requirements.txt
    log_success "Python dependencies installed"
}

# Initialize Foundry project
init_foundry() {
    log_info "Initializing Foundry project..."
    
    export PATH="$HOME/.foundry/bin:$PATH"
    
    if [ ! -f "foundry.toml" ]; then
        forge init --no-git 
    fi
    
    forge install OpenZeppelin/openzeppelin-contracts-upgradeable --no-git 
    forge install OpenZeppelin/openzeppelin-contracts --no-git
    
    log_success "Foundry project initialized"
}

# Create configuration files
create_config_files() {
    log_info "Creating configuration files..."
    
    cat > .env.example << 'EOF'
# Your .env settings here
EOF

    cat > foundry.toml << 'EOF'
# Your foundry.toml settings here
EOF

    cat > .gitignore << 'EOF'
venv/
out/
cache/
broadcast/
*.log
__pycache__/
EOF

    log_success "Configuration files created"
}

# Test installation
test_installation() {
    log_info "Testing installation..."
    
    source venv/bin/activate
    python -c "
import web3
import eth_account
import aiohttp
import numpy
print('Python dependencies: OK')
print(f'Web3.py version: {web3.__version__}')
"
    
    export PATH="$HOME/.foundry/bin:$PATH"
    forge --version
    
    log_success "All tests passed!"
}

# Main installation function
main() {
    log_info "Starting Base Chain Flashloan Arbitrage System setup..."
    
    check_root
    
    install_system_deps
    install_nodejs
    install_python311
    install_foundry
    create_project_structure
    setup_python_env
    install_python_deps
    init_foundry
    create_config_files
    test_installation
    
    log_success "Setup completed successfully!"
    echo
    log_info "Next steps:"
    echo "1. Copy .env.example to .env and configure your settings:"
    echo "   cp .env.example .env"
    echo "2. Activate the virtual environment:"
    echo "   source venv/bin/activate"
    echo "3. Add Foundry and pyenv paths to your shell if not already:"
    echo "   export PYENV_ROOT=\"$HOME/.pyenv\""
    echo "   export PATH=\"$PYENV_ROOT/bin:\$PATH\""
    echo "   eval \"\$(pyenv init --path)\""
    echo "   eval \"\$(pyenv init -)\""
    echo "   export PATH=\"$HOME/.foundry/bin:\$PATH\""
    echo "4. Test your setup manually if needed."
}

main "$@"
