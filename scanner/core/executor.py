#!/usr/bin/env python3
"""
Arbitrage executor for Base chain
Handles transaction submission and monitoring
"""

import asyncio
import time
from typing import List, Optional, Dict
from decimal import Decimal
from web3 import Web3
from web3.middleware import geth_poa_middleware
from eth_account import Account
import aiohttp

from ..utils.config import Config
from ..utils.logger import Logger

class ArbitrageExecutor:
    def __init__(self, config: Config, logger: Logger):
        self.config = config
        self.logger = logger
        self.account = Account.from_key(config.private_key)
        
        # Initialize Web3 connections with failover
        self.rpc_urls = config.rpc_urls
        self.current_rpc_index = 0
        self.w3 = self._init_web3()
        
        # Contract setup
        self.contract_address = Web3.to_checksum_address(config.contract_address)
        self.contract_abi = self._load_contract_abi()
        self.contract = self.w3.eth.contract(
            address=self.contract_address, 
            abi=self.contract_abi
        )
        
        # Transaction management
        self.nonce = self.w3.eth.get_transaction_count(self.account.address)
        self.pending_txs = {}
        self.max_gas_price = config.max_gas_price_gwei * 10**9
        self.executing = False
        
    def _init_web3(self) -> Web3:
        """Initialize Web3 with current RPC"""
        w3 = Web3(Web3.HTTPProvider(self.rpc_urls[self.current_rpc_index]))
        w3.middleware_onion.inject(geth_poa_middleware, layer=0)
        return w3
        
    def _load_contract_abi(self):
        """Load contract ABI"""
        return [
            {
                "inputs": [
                    {
                        "components": [
                            {"name": "tokenIn", "type": "address"},
                            {"name": "amountIn", "type": "uint256"},
                            {"name": "dexRouters", "type": "address[]"},
                            {"name": "swapData", "type": "bytes[]"},
                            {"name": "expectedProfit", "type": "uint256"}
                        ],
                        "name": "params",
                        "type": "tuple"
                    }
                ],
                "name": "executeArbitrage",
                "outputs": [],
                "type": "function"
            },
            {
                "inputs": [{"name": "token", "type": "address"}],
                "name": "emergencyWithdraw",
                "outputs": [],
                "type": "function"
            },
            {
                "inputs": [],
                "name": "owner",
                "outputs": [{"type": "address"}],
                "type": "function"
            },
            {
                "inputs": [{"name": "_threshold", "type": "uint256"}],
                "name": "setMinProfitThreshold",
                "outputs": [],
                "type": "function"
            },
            {
                "inputs": [],
                "name": "minProfitThreshold",
                "outputs": [{"type": "uint256"}],
                "type": "function"
            },
            {
                "anonymous": False,
                "inputs": [
                    {"indexed": True, "name": "token", "type": "address"},
                    {"indexed": False, "name": "amountIn", "type": "uint256"},
                    {"indexed": False, "name": "profit", "type": "uint256"},
                    {"indexed": True, "name": "executor", "type": "address"}
                ],
                "name": "ArbitrageExecuted",
                "type": "event"
            },
            {
                "anonymous": False,
                "inputs": [
                    {"indexed": True, "name": "token", "type": "address"},
                    {"indexed": False, "name": "amountIn", "type": "uint256"},
                    {"indexed": False, "name": "reason", "type": "string"}
                ],
                "name": "ArbitrageFailed",
                "type": "event"
            },
            {
                "anonymous": False,
                "inputs": [
                    {"indexed": True, "name": "token", "type": "address"},
                    {"indexed": False, "name": "amount", "type": "uint256"},
                    {"indexed": True, "name": "recipient", "type": "address"}
                ],
                "name": "ProfitWithdrawn",
                "type": "event"
            }
        ]

    async def start(self, scanner_queue: asyncio.Queue):
        """Start the executor"""
        self.executing = True
        self.logger.info(f"Starting executor with account {self.account.address}")
        
        tasks = [
            self.execute_routes(scanner_queue),
            self.monitor_transactions(),
            self.update_nonce_periodically()
        ]
        
        await asyncio.gather(*tasks, return_exceptions=True)
        
    async def stop(self):
        """Stop the executor"""
        self.executing = False
        self.logger.info("Stopping executor...")
        
    async def execute_routes(self, scanner_queue: asyncio.Queue):
        """Execute profitable routes from scanner"""
        while self.executing:
            try:
                # Get route from scanner with timeout
                route = await asyncio.wait_for(scanner_queue.get(), timeout=1.0)
                
                # Validate route
                if not await self.validate_route(route):
                    self.logger.debug(f"Route validation failed for {route.token}")
                    continue
                    
                # Execute arbitrage
                tx_hash = await self.execute_arbitrage(route)
                
                if tx_hash:
                    self.logger.info(f"Executed arbitrage: {tx_hash.hex()}")
                    self.pending_txs[tx_hash] = {
                        'route': route,
                        'timestamp': time.time(),
                        'nonce': self.nonce - 1
                    }
                    
            except asyncio.TimeoutError:
                continue
            except Exception as e:
                self.logger.error(f"Execution error: {e}")
                await asyncio.sleep(1)
                
    async def validate_route(self, route) -> bool:
        """Validate arbitrage route before execution"""
        try:
            # Check minimum profit
            if route.net_profit < self.config.min_profit_threshold:
                self.logger.debug(f"Profit too low: {route.net_profit}")
                return False
                
            # Check if route is too old (>30 seconds)
            if time.time() - route.timestamp > 30:
                self.logger.debug("Route too old")
                return False
                
            # Verify token contract exists
            try:
                token_contract = self.w3.eth.contract(
                    address=Web3.to_checksum_address(route.token),
                    abi=[
                        {
                            "inputs": [{"name": "account", "type": "address"}],
                            "name": "balanceOf",
                            "outputs": [{"type": "uint256"}],
                            "type": "function"
                        }
                    ]
                )
                # Just check if we can call the contract
                token_contract.functions.balanceOf(self.contract_address).call()
            except Exception as e:
                self.logger.debug(f"Token contract validation failed: {e}")
                return False
                
            # Simulate transaction (basic check)
            try:
                estimated_gas = self.contract.functions.executeArbitrage((
                    route.token,
                    route.amount_in,
                    route.dex_routers,
                    route.swap_data,
                    route.expected_profit
                )).estimate_gas({'from': self.account.address})
                
                if estimated_gas > 800000:  # Gas limit check
                    self.logger.debug(f"Gas estimate too high: {estimated_gas}")
                    return False
                    
                return True
                
            except Exception as e:
                self.logger.debug(f"Simulation failed: {e}")
                return False
                
        except Exception as e:
            self.logger.error(f"Validation error: {e}")
            return False
            
    async def execute_arbitrage(self, route) -> Optional[bytes]:
        """Execute arbitrage transaction"""
        try:
            # Get current gas price
            gas_price = await self.get_gas_price()
            
            # Prepare transaction
            tx = self.contract.functions.executeArbitrage((
                route.token,
                route.amount_in,
                route.dex_routers,
                route.swap_data,
                route.expected_profit
            )).build_transaction({
                'from': self.account.address,
                'nonce': self.nonce,
                'gas': 600000,  # Conservative gas limit
                'maxFeePerGas': gas_price,
                'maxPriorityFeePerGas': min(2 * 10**9, gas_price // 10),  # 2 gwei or 10% of base
                'chainId': self.config.chain_id
            })
            
            # Estimate gas more precisely
            try:
                gas_estimate = self.w3.eth.estimate_gas(tx)
                tx['gas'] = int(gas_estimate * 1.15)  # 15% buffer
            except Exception as e:
                self.logger.warning(f"Gas estimation failed, using default: {e}")
                
            # Check if gas cost doesn't exceed profit
            gas_cost = tx['gas'] * tx['maxFeePerGas']
            if gas_cost >= route.expected_profit:
                self.logger.debug(f"Gas cost too high: {gas_cost} vs profit {route.expected_profit}")
                return None
                
            # Sign and send transaction
            signed_tx = self.account.sign_transaction(tx)
            tx_hash = self.w3.eth.send_raw_transaction(signed_tx.rawTransaction)
            
            # Increment nonce
            self.nonce += 1
            
            return tx_hash
            
        except Exception as e:
            self.logger.error(f"Transaction execution failed: {e}")
            
            # Try RPC failover on connection issues
            if "connection" in str(e).lower() or "timeout" in str(e).lower():
                await self.switch_rpc()
                
            return None
            
    async def get_gas_price(self) -> int:
        """Get current gas price with limit"""
        try:
            # Get latest block for base fee
            latest_block = self.w3.eth.get_block('latest')
            base_fee = latest_block.get('baseFeePerGas', 0)
            
            if base_fee:
                # EIP-1559 pricing
                gas_price = int(base_fee * 1.5)  # 50% above base fee
            else:
                # Legacy pricing
                gas_price = self.w3.eth.gas_price
                
            # Apply max gas price limit
            return min(gas_price, self.max_gas_price)
            
        except Exception as e:
            self.logger.warning(f"Gas price fetch failed: {e}")
            return min(30 * 10**9, self.max_gas_price)  # Default 30 gwei
            
    async def monitor_transactions(self):
        """Monitor pending transactions"""
        while self.executing:
            try:
                current_time = time.time()
                completed_txs = []
                
                for tx_hash, tx_data in list(self.pending_txs.items()):
                    try:
                        # Check transaction status
                        receipt = self.w3.eth.get_transaction_receipt(tx_hash)
                        
                        if receipt['status'] == 1:
                            profit = await self.calculate_actual_profit(receipt, tx_data['route'])
                            self.logger.info(
                                f"Transaction successful! "
                                f"Profit: {self.w3.from_wei(profit, 'ether'):.6f} ETH "
                                f"Hash: {tx_hash.hex()}"
                            )
                            
                            # Schedule profit withdrawal
                            asyncio.create_task(
                                self.withdraw_profits(tx_data['route'].token)
                            )
                        else:
                            self.logger.warning(f"Transaction failed: {tx_hash.hex()}")
                            
                        completed_txs.append(tx_hash)
                        
                    except Exception as e:
                        # Transaction might still be pending
                        if current_time - tx_data['timestamp'] > 300:  # 5 minutes
                            self.logger.warning(
                                f"Transaction stuck/dropped: {tx_hash.hex()}"
                            )
                            completed_txs.append(tx_hash)
                            
                # Remove completed transactions
                for tx_hash in completed_txs:
                    del self.pending_txs[tx_hash]
                    
                await asyncio.sleep(10)  # Check every 10 seconds
                
            except Exception as e:
                self.logger.error(f"Transaction monitoring error: {e}")
                await asyncio.sleep(30)
                
    async def calculate_actual_profit(self, receipt, route) -> int:
        """Calculate actual profit from transaction receipt"""
        try:
            # Calculate gas cost
            gas_used = receipt['gasUsed']
            gas_price = receipt['effectiveGasPrice']
            gas_cost = gas_used * gas_price
            
            # Parse ArbitrageExecuted event
            try:
                logs = self.contract.events.ArbitrageExecuted().process_receipt(receipt)
                if logs:
                    gross_profit = logs[0]['args']['profit']
                    net_profit = gross_profit - gas_cost
                    return net_profit
            except Exception as e:
                self.logger.debug(f"Event parsing failed: {e}")
                
            # If event parsing fails, return negative gas cost
            return -gas_cost
            
        except Exception as e:
            self.logger.error(f"Profit calculation error: {e}")
            return 0
            
    async def withdraw_profits(self, token: str):
        """Withdraw profits from contract"""
        try:
            # Small delay to ensure state is settled
            await asyncio.sleep(5)
            
            # Check contract balance
            token_contract = self.w3.eth.contract(
                address=Web3.to_checksum_address(token),
                abi=[
                    {
                        "inputs": [{"name": "account", "type": "address"}],
                        "name": "balanceOf",
                        "outputs": [{"type": "uint256"}],
                        "type": "function"
                    }
                ]
            )
            
            balance = token_contract.functions.balanceOf(self.contract_address).call()
            
            if balance > 1000:  # Only withdraw if balance > dust amount
                self.logger.info(f"Withdrawing {self.w3.from_wei(balance, 'ether'):.6f} tokens")
                
                # Build withdrawal transaction
                tx = self.contract.functions.emergencyWithdraw(token).build_transaction({
                    'from': self.account.address,
                    'nonce': self.nonce,
                    'gas': 150000,
                    'maxFeePerGas': await self.get_gas_price(),
                    'maxPriorityFeePerGas': 2 * 10**9,
                    'chainId': self.config.chain_id
                })
                
                # Sign and send
                signed_tx = self.account.sign_transaction(tx)
                tx_hash = self.w3.eth.send_raw_transaction(signed_tx.rawTransaction)
                self.nonce += 1
                
                self.logger.info(f"Withdrawal transaction sent: {tx_hash.hex()}")
                
        except Exception as e:
            self.logger.error(f"Withdrawal error: {e}")
            
    async def update_nonce_periodically(self):
        """Update nonce periodically to stay in sync"""
        while self.executing:
            try:
                # Check nonce every minute
                await asyncio.sleep(60)
                
                actual_nonce = self.w3.eth.get_transaction_count(self.account.address)
                
                if actual_nonce != self.nonce:
                    self.logger.info(f"Nonce sync: {self.nonce} -> {actual_nonce}")
                    self.nonce = actual_nonce
                    
            except Exception as e:
                self.logger.error(f"Nonce update error: {e}")
                await asyncio.sleep(120)  # Wait longer on error
                
    async def switch_rpc(self):
        """Switch to next RPC endpoint"""
        old_index = self.current_rpc_index
        self.current_rpc_index = (self.current_rpc_index + 1) % len(self.rpc_urls)
        
        self.logger.warning(
            f"RPC failover: {self.rpc_urls[old_index]} -> {self.rpc_urls[self.current_rpc_index]}"
        )
        
        try:
            self.w3 = self._init_web3()
            self.contract = self.w3.eth.contract(
                address=self.contract_address,
                abi=self.contract_abi
            )
            
            # Verify connection
            self.w3.eth.get_block('latest')
            self.logger.info("RPC failover successful")
            
        except Exception as e:
            self.logger.error(f"RPC failover failed: {e}")
            
    async def get_account_status(self) -> Dict:
        """Get current account status"""
        try:
            balance = self.w3.eth.get_balance(self.account.address)
            nonce = self.w3.eth.get_transaction_count(self.account.address)
            pending_count = len(self.pending_txs)
            
            return {
                'address': self.account.address,
                'balance_eth': self.w3.from_wei(balance, 'ether'),
                'nonce': nonce,
                'local_nonce': self.nonce,
                'pending_txs': pending_count,
                'rpc_endpoint': self.rpc_urls[self.current_rpc_index]
            }
        except Exception as e:
            self.logger.error(f"Status check error: {e}")
            return {}
            
    async def emergency_stop(self):
        """Emergency stop - cancel all pending transactions"""
        self.logger.critical("EMERGENCY STOP ACTIVATED")
        
        # Stop executing new transactions
        self.executing = False
        
        # Try to cancel pending transactions by sending 0 ETH to self with higher gas
        try:
            for tx_hash, tx_data in self.pending_txs.items():
                cancel_tx = {
                    'from': self.account.address,
                    'to': self.account.address,
                    'value': 0,
                    'nonce': tx_data['nonce'],
                    'gas': 21000,
                    'maxFeePerGas': int(self.max_gas_price * 1.5),
                    'maxPriorityFeePerGas': int(self.max_gas_price * 0.2),
                    'chainId': self.config.chain_id
                }
                
                signed_cancel = self.account.sign_transaction(cancel_tx)
                cancel_hash = self.w3.eth.send_raw_transaction(signed_cancel.rawTransaction)
                
                self.logger.info(f"Cancel transaction sent: {cancel_hash.hex()}")
                
        except Exception as e:
            self.logger.error(f"Emergency stop error: {e}")

async def main():
    """Test executor standalone"""
    from ..utils.config import Config
    from ..utils.logger import Logger
    
    config = Config()
    logger = Logger(config)
    
    executor = ArbitrageExecutor(config, logger)
    
    # Print account status
    status = await executor.get_account_status()
    logger.info(f"Account status: {status}")

if __name__ == "__main__":
    asyncio.run(main())
