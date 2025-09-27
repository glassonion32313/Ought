#!/usr/bin/env python3
"""
Logging utilities for arbitrage system
"""

import logging
import sys
from datetime import datetime
from typing import Optional

class Logger:
    def __init__(self, config, name: str = "ArbitrageBot"):
        """Initialize logger"""
        self.config = config
        self.name = name
        
        # Create logger
        self.logger = logging.getLogger(name)
        self.logger.setLevel(getattr(logging, config.log_level.upper()))
        
        # Remove existing handlers
        self.logger.handlers = []
        
        # Console handler
        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setLevel(getattr(logging, config.log_level.upper()))
        
        # File handler
        if config.log_file:
            file_handler = logging.FileHandler(config.log_file)
            file_handler.setLevel(logging.INFO)
            
            # Formatter
            formatter = logging.Formatter(
                '%(asctime)s - %(name)s - %(levelname)s - %(message)s',
                datefmt='%Y-%m-%d %H:%M:%S'
            )
            
            file_handler.setFormatter(formatter)
            self.logger.addHandler(file_handler)
            
        # Minimal console output unless verbose
        if config.log_level.upper() == "DEBUG":
            console_formatter = logging.Formatter(
                '%(asctime)s - %(levelname)s - %(message)s',
                datefmt='%H:%M:%S'
            )
        else:
            console_formatter = logging.Formatter('%(message)s')
            
        console_handler.setFormatter(console_formatter)
        self.logger.addHandler(console_handler)
        
    def debug(self, message: str):
        """Debug level logging"""
        self.logger.debug(message)
        
    def info(self, message: str):
        """Info level logging"""
        self.logger.info(message)
        
    def warning(self, message: str):
        """Warning level logging"""
        self.logger.warning(message)
        
    def error(self, message: str):
        """Error level logging"""
        self.logger.error(message)
        
    def critical(self, message: str):
        """Critical level logging"""
        self.logger.critical(message)
        
    def set_level(self, level: str):
        """Change logging level"""
        self.logger.setLevel(getattr(logging, level.upper()))
        for handler in self.logger.handlers:
            handler.setLevel(getattr(logging, level.upper()))
