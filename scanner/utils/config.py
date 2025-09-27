#!/usr/bin/env python3
"""
Configuration management for arbitrage system
"""

import os
from typing import List, Optional
from dotenv import load_dotenv

class Config:
    def __init__(self, env_file: str = ".env"):
        """Initialize configuration from environment"""
        load_dotenv(env_file)
        
        # RPC Configuration
        self.rpc_urls = os.getenv("RPC_URLS", "").split(",")
        self.ws_rpc_url = os.getenv("WS_RPC_URL", "wss://base-mainnet.g.alchemy.com/v2/YOUR_KEY")
        
        # Account Configuration
        self.private_key = os.getenv("PRIVATE_KEY", "")
        
        # Contract Configuration
        self.contract_address = os.getenv("CONTRACT_ADDRESS", "")
        
        # Token Configuration
        token_list_env = os.getenv("TOKEN_LIST", "")
        self.token_list = token_list_env.split(",") if token_list_env else [
            "0x4200000000000000000000000000000000000006",  # WETH
            "0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA",  # USDbC
            "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",  # USDC
            "0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb",  # DAI
        ]
        
        # Profit Configuration
        self.min_profit_threshold = int(os.getenv("MIN_PROFIT_THRESHOLD", "10000000000000000"))  # 0.01 ETH
        self.max_gas_price_gwei = int(os.getenv("MAX_GAS_PRICE_GWEI", "100"))
        
        # Features
        self.use_gpu = os.getenv("USE_GPU", "false").lower() == "true"
        self.enable_mempool_monitoring = os.getenv("ENABLE_MEMPOOL", "false").lower() == "true"
        
        # Logging
        self.log_level = os.getenv("LOG_LEVEL", "INFO")
        self.log_file = os.getenv("LOG_FILE", "arbitrage.log")
        
        # Network
        self.chain_id = int(os.getenv("CHAIN_ID", "8453"))  # Base mainnet
        self.network = os.getenv("NETWORK", "base-mainnet")
        
    def validate(self) -> bool:
        """Validate configuration"""
        if not self.rpc_urls or not self.rpc_urls[0]:
            raise ValueError("RPC_URLS not configured")
            
        if not self.private_key:
            raise ValueError("PRIVATE_KEY not configured")
            
        if not self.contract_address:
            raise ValueError("CONTRACT_ADDRESS not configured")
            
        return True
        
    def update(self, key: str, value: any):
        """Update configuration value"""
        setattr(self, key, value)
        
    def to_dict(self) -> dict:
        """Convert configuration to dictionary"""
        return {
            key: value for key, value in self.__dict__.items()
            if not key.startswith('_')
        }
