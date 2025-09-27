#!/usr/bin/env python3
"""
Submit arbitrage system to Base mainnet
"""

import sys
import os
import json
from pathlib import Path
from web3 import Web3
from eth_account import Account
from dotenv import load_dotenv

sys.path.append(str(Path(__file__).parent.parent))

from scanner.core.scanner import ArbitrageScanner
from scanner.core.executor import ArbitrageExecutor
from scanner.utils.config import Config
from scanner.utils.logger import Logger

class MainnetSubmitter:
    def __init__(self):
        """Initialize mainnet submitter"""
        load_dotenv()
        self.config = Config()
        self.logger = Logger(self.config)
        
    def validate_mainnet_ready(self) -> bool:
        """Validate system is ready for mainnet"""
        checks = []
        
        # Check contract deployment
        if os.path.exists("deploy/deployment_base-mainnet.json"):
            with open("deploy/deployment_base-mainnet.json", "r") as f:
                deployment = json.load(f)
                self.config.contract_address = deployment["address"]
                checks.append(True)
                self.logger.info(f"Contract found at: {deployment['address']}")
        else:
            self.logger.error("No mainnet deployment found")
            checks.append(False)
            
        # Check account balance
        w3 = Web3(Web3.HTTPProvider(self.config.rpc_urls[0]))
        account = Account.from_key(self.config.private_key)
        balance = w3.eth.get_balance(account.address)
        
        if balance > w3.to_wei(0.1, 'ether'):
            checks.append(True)
            self.logger.info(f"Account balance: {w3.from_wei(balance, 'ether')} ETH")
        else:
            self.logger.error("Insufficient balance for mainnet operations")
            checks.append(False)
            
        # Check contract ownership
        contract_abi = [
            {
                "inputs": [],
                "name": "owner",
                "outputs": [{"type": "address"}],
                "type": "function"
            }
        ]
        
        contract = w3.eth.contract(
            address=Web3.to_checksum_address(self.config.contract_address),
            abi=contract_abi
        )
        
        owner = contract.functions.owner().call()
        if owner.lower() == account.address.lower():
            checks.append(True)
            self.logger.info("Contract ownership verified")
        else:
            self.logger.error("Account is not contract owner")
            checks.append(False)
            
        return all(checks)
        
    async def start_mainnet_bot(self):
        """Start the arbitrage bot on mainnet"""
        if not self.validate_mainnet_ready():
            self.logger.error("Mainnet validation failed!")
            return
            
        self.logger.info("Starting mainnet arbitrage bot...")
        
        # Create scanner and executor
        scanner = ArbitrageScanner(self.config, self.logger)
        executor = ArbitrageExecutor(self.config, self.logger)
        
        # Start both components
        import asyncio
        await asyncio.gather(
            scanner.start(),
            executor.start(scanner.profitable_routes)
        )

def main():
    """Main entry point"""
    import asyncio
    
    submitter = MainnetSubmitter()
    
    print("\n⚠️  WARNING: You are about to start the arbitrage bot on MAINNET!")
    print("This will use real funds and execute real transactions.")
    response = input("\nType 'CONFIRM' to proceed: ")
    
    if response == "CONFIRM":
        try:
            asyncio.run(submitter.start_mainnet_bot())
        except KeyboardInterrupt:
            print("\nShutting down...")
    else:
        print("Mainnet submission cancelled.")

if __name__ == "__main__":
    main()
