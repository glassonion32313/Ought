#!/usr/bin/env python3
"""
Main execution script for the arbitrage system
"""

import asyncio
import argparse
import sys
from pathlib import Path

# Add scanner to path
sys.path.append(str(Path(__file__).parent))

from scanner.core.scanner import ArbitrageScanner
from scanner.core.executor import ArbitrageExecutor
from scanner.utils.config import Config
from scanner.utils.logger import Logger

async def main():
    """Main entry point for arbitrage system"""
    parser = argparse.ArgumentParser(description="Base Chain Flashloan Arbitrage System")
    parser.add_argument("--testnet", action="store_true", help="Run on testnet")
    parser.add_argument("--scan-only", action="store_true", help="Only scan, don't execute")
    parser.add_argument("--gpu", action="store_true", help="Enable GPU acceleration")
    parser.add_argument("--verbose", action="store_true", help="Enable verbose logging")
    
    args = parser.parse_args()
    
    # Initialize configuration
    config = Config()
    
    # Apply command line arguments
    if args.gpu:
        config.use_gpu = True
    if args.verbose:
        config.log_level = "DEBUG"
    if args.testnet:
        config.network = "base-sepolia"
        
    # Validate configuration
    try:
        config.validate()
    except ValueError as e:
        print(f"Configuration error: {e}")
        print("Please check your .env file")
        sys.exit(1)
        
    # Initialize logger
    logger = Logger(config)
    
    logger.info("=" * 50)
    logger.info("Base Chain Flashloan Arbitrage System")
    logger.info("=" * 50)
    logger.info(f"Network: {config.network}")
    logger.info(f"GPU Acceleration: {'Enabled' if config.use_gpu else 'Disabled'}")
    logger.info(f"Min Profit Threshold: {config.min_profit_threshold} wei")
    
    # Create scanner
    scanner = ArbitrageScanner(config, logger)
    
    if args.scan_only:
        logger.info("Running in scan-only mode")
        await scanner.start()
    else:
        # Create executor
        executor = ArbitrageExecutor(config, logger)
        
        # Start both components
        tasks = [
            scanner.start(),
            executor.start(scanner.profitable_routes)
        ]
        
        await asyncio.gather(*tasks)

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nShutting down gracefully...")
    except Exception as e:
        print(f"Fatal error: {e}")
        sys.exit(1)
