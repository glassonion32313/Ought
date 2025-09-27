#!/usr/bin/env python3
"""
Deployment script for FlashLoan Arbitrage contract
"""

import json
import sys
import os
from pathlib import Path
from web3 import Web3
from eth_account import Account
from dotenv import load_dotenv
import subprocess

# Add parent directory to path
sys.path.append(str(Path(__file__).parent.parent))

from scanner.utils.config import Config
from scanner.utils.logger import Logger

class ContractDeployer:
    def __init__(self, network: str = "base-sepolia"):
        """Initialize deployer"""
        load_dotenv()
        
        self.network = network
        self.is_mainnet = "mainnet" in network.lower()
        
        # Setup Web3
        rpc_url = os.getenv(f"{network.upper()}_RPC_URL") or os.getenv("RPC_URLS", "").split(",")[0]
        self.w3 = Web3(Web3.HTTPProvider(rpc_url))
        
        # Setup account
        self.account = Account.from_key(os.getenv("PRIVATE_KEY"))
        
        # Paths
        self.contract_path = Path(__file__).parent.parent / "contracts" / "FlashLoanArbitrage.sol"
        self.build_path = Path(__file__).parent.parent / "out"
        
    def compile_contracts(self):
        """Compile contracts using Foundry"""
        print("Compiling contracts...")
        
        result = subprocess.run(
            ["forge", "build", "--optimize", "--optimizer-runs", "200"],
            capture_output=True,
            text=True
        )
        
        if result.returncode != 0:
            print(f"Compilation failed: {result.stderr}")
            sys.exit(1)
            
        print("Contracts compiled successfully!")
        
    def deploy_proxy(self):
        """Deploy UUPS proxy and implementation"""
        print(f"Deploying to {self.network}...")
        
        # Load compiled contract
        contract_json_path = self.build_path / "FlashLoanArbitrage.sol" / "FlashLoanArbitrage.json"
        
        with open(contract_json_path, 'r') as f:
            contract_data = json.load(f)
            
        bytecode = contract_data['bytecode']['object']
        abi = contract_data['abi']
        
        # Deploy implementation
        Contract = self.w3.eth.contract(abi=abi, bytecode=bytecode)
        
        # Build deployment transaction
        min_profit = self.w3.toWei(0.01, 'ether')  # 0.01 ETH minimum profit
        
        constructor = Contract.constructor()
        
        tx = constructor.build_transaction({
            'from': self.account.address,
            'nonce': self.w3.eth.get_transaction_count(self.account.address),
            'gas': 3000000,
            'gasPrice': self.w3.eth.gas_price,
            'chainId': self.w3.eth.chain_id
        })
        
        # Sign and send transaction
        signed_tx = self.account.sign_transaction(tx)
        tx_hash = self.w3.eth.send_raw_transaction(signed_tx.rawTransaction)
        
        print(f"Deployment transaction sent: {tx_hash.hex()}")
        
        # Wait for confirmation
        receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash)
        
        if receipt['status'] == 1:
            contract_address = receipt['contractAddress']
            print(f"Contract deployed at: {contract_address}")
            
            # Initialize contract
            contract = self.w3.eth.contract(address=contract_address, abi=abi)
            
            init_tx = contract.functions.initialize(min_profit).build_transaction({
                'from': self.account.address,
                'nonce': self.w3.eth.get_transaction_count(self.account.address),
                'gas': 200000,
                'gasPrice': self.w3.eth.gas_price,
                'chainId': self.w3.eth.chain_id
            })
            
            signed_init_tx = self.account.sign_transaction(init_tx)
            init_tx_hash = self.w3.eth.send_raw_transaction(signed_init_tx.rawTransaction)
            
            init_receipt = self.w3.eth.wait_for_transaction_receipt(init_tx_hash)
            
            if init_receipt['status'] == 1:
                print(f"Contract initialized successfully!")
                
                # Save deployment info
                self.save_deployment_info(contract_address, abi)
                
                # Verify contract
                if not self.is_mainnet:
                    self.verify_contract(contract_address)
                    
                return contract_address
            else:
                print("Initialization failed!")
                return None
        else:
            print("Deployment failed!")
            return None
            
    def verify_contract(self, address: str):
        """Verify contract on Basescan"""
        print(f"Verifying contract at {address}...")
        
        api_key = os.getenv("BASESCAN_API_KEY", "")
        
        if not api_key:
            print("BASESCAN_API_KEY not set, skipping verification")
            return
            
        result = subprocess.run(
            [
                "forge", "verify-contract",
                address,
                "FlashLoanArbitrage",
                "--chain", self.network,
                "--etherscan-api-key", api_key,
                "--compiler-version", "0.8.19",
                "--num-of-optimizations", "200"
            ],
            capture_output=True,
            text=True
        )
        
        if result.returncode == 0:
            print("Contract verified successfully!")
        else:
            print(f"Verification failed: {result.stderr}")
            
    def save_deployment_info(self, address: str, abi: list):
        """Save deployment information"""
        deployment_info = {
            "network": self.network,
            "address": address,
            "abi": abi,
            "deployer": self.account.address,
            "timestamp": self.w3.eth.get_block('latest')['timestamp']
        }
        
        output_file = Path(__file__).parent / f"deployment_{self.network}.json"
        
        with open(output_file, 'w') as f:
            json.dump(deployment_info, f, indent=2)
            
        print(f"Deployment info saved to {output_file}")
        
        # Update .env with contract address
        env_file = Path(__file__).parent.parent / ".env"
        
        if env_file.exists():
            with open(env_file, 'a') as f:
                f.write(f"\n# Deployed contract address for {self.network}\n")
                f.write(f"CONTRACT_ADDRESS={address}\n")

def main():
    """Main deployment function"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Deploy FlashLoan Arbitrage Contract")
    parser.add_argument("--network", default="base-sepolia", help="Network to deploy to")
    parser.add_argument("--verify", action="store_true", help="Verify contract after deployment")
    
    args = parser.parse_args()
    
    deployer = ContractDeployer(args.network)
    
    # Compile contracts
    deployer.compile_contracts()
    
    # Deploy
    contract_address = deployer.deploy_proxy()
    
    if contract_address:
        print(f"\n✅ Deployment successful!")
        print(f"Contract address: {contract_address}")
        print(f"Network: {args.network}")
    else:
        print("\n❌ Deployment failed!")
        sys.exit(1)

if __name__ == "__main__":
    main()
