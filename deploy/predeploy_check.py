#!/usr/bin/env python3
"""
Pre-deployment checks for FlashLoan Arbitrage system
"""

import sys
import os
from pathlib import Path
from web3 import Web3
from eth_account import Account
from dotenv import load_dotenv

def check_environment():
    """Check environment setup"""
    load_dotenv()
    
    checks = {
        "RPC_URLS": False,
        "PRIVATE_KEY": False,
        "Network Connection": False,
        "Account Balance": False,
        "Foundry Installation": False
    }
    
    # Check RPC URLs
    rpc_urls = os.getenv("RPC_URLS", "").split(",")
    if rpc_urls and rpc_urls[0]:
        checks["RPC_URLS"] = True
        
        # Check network connection
        try:
            w3 = Web3(Web3.HTTPProvider(rpc_urls[0]))
            if w3.is_connected():
                checks["Network Connection"] = True
                
                # Check account
                private_key = os.getenv("PRIVATE_KEY", "")
                if private_key:
                    checks["PRIVATE_KEY"] = True
                    account = Account.from_key(private_key)
                    
                    # Check balance
                    balance = w3.eth.get_balance(account.address)
                    if balance > 0:
                        checks["Account Balance"] = True
                        print(f"Account: {account.address}")
                        print(f"Balance: {w3.from_wei(balance, 'ether')} ETH")
        except Exception as e:
            print(f"Connection error: {e}")
            
    # Check Foundry
    import subprocess
    try:
        result = subprocess.run(["forge", "--version"], capture_output=True)
        if result.returncode == 0:
            checks["Foundry Installation"] = True
    except:
        pass
        
    # Print results
    print("\n=== Pre-deployment Checks ===")
    for check, passed in checks.items():
        status = "✅" if passed else "❌"
        print(f"{status} {check}")
        
    # Return overall status
    return all(checks.values())

def main():
    """Run pre-deployment checks"""
    if check_environment():
        print("\n✅ All checks passed! Ready for deployment.")
        sys.exit(0)
    else:
        print("\n❌ Some checks failed. Please fix issues before deployment.")
        sys.exit(1)

if __name__ == "__main__":
    main()
