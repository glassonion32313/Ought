// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IBalancerVault {
    function flashLoan(
        address recipient,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    
    function getAmountsOut(uint amountIn, address[] calldata path)
        external view returns (uint[] memory amounts);
}

interface IUniswapV3Router {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    
    function exactInputSingle(ExactInputSingleParams calldata params)
        external payable returns (uint256 amountOut);
}

interface IAerodromeRouter {
    struct Route {
        address from;
        address to;
        bool stable;
    }
    
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract FlashLoanArbitrage is 
    OwnableUpgradeable, 
    ReentrancyGuardUpgradeable, 
    PausableUpgradeable,
    UUPSUpgradeable 
{
    using SafeERC20 for IERC20;
    
    IBalancerVault constant BALANCER_VAULT = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    
    uint256 public minProfitThreshold;
    mapping(address => bool) public authorizedExecutors;
    
    struct ArbitrageParams {
        address tokenIn;
        uint256 amountIn;
        address[] dexRouters;
        bytes[] swapData;
        uint256 expectedProfit;
    }
    
    event ArbitrageExecuted(
        address indexed token,
        uint256 amountIn,
        uint256 profit,
        address indexed executor
    );
    
    event ArbitrageFailed(
        address indexed token,
        uint256 amountIn,
        string reason
    );
    
    event ProfitWithdrawn(
        address indexed token,
        uint256 amount,
        address indexed recipient
    );
    
    modifier onlyAuthorized() {
        require(authorizedExecutors[msg.sender] || msg.sender == owner(), "Not authorized");
        _;
    }
    
    function initialize(uint256 _minProfitThreshold) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        
        minProfitThreshold = _minProfitThreshold;
        authorizedExecutors[msg.sender] = true;
    }
    
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
    
    function executeArbitrage(ArbitrageParams calldata params) 
        external 
        onlyAuthorized 
        whenNotPaused 
        nonReentrant 
    {
        require(params.expectedProfit >= minProfitThreshold, "Profit below threshold");
        
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = params.tokenIn;
        amounts[0] = params.amountIn;
        
        bytes memory userData = abi.encode(params);
        
        BALANCER_VAULT.flashLoan(address(this), tokens, amounts, userData);
    }
    
    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory,
        bytes memory userData
    ) external {
        require(msg.sender == address(BALANCER_VAULT), "Invalid sender");
        
        ArbitrageParams memory params = abi.decode(userData, (ArbitrageParams));
        
        uint256 initialBalance = IERC20(tokens[0]).balanceOf(address(this));
        
        // Execute two-hop arbitrage
        for (uint256 i = 0; i < params.dexRouters.length; i++) {
            _executeSwap(
                params.dexRouters[i],
                params.swapData[i],
                tokens[0],
                amounts[0]
            );
        }
        
        uint256 finalBalance = IERC20(tokens[0]).balanceOf(address(this));
        
        // Verify profit
        if (finalBalance > initialBalance) {
            uint256 profit = finalBalance - initialBalance;
            require(profit >= minProfitThreshold, "Insufficient profit");
            
            // Repay flashloan
            IERC20(tokens[0]).safeTransfer(address(BALANCER_VAULT), amounts[0]);
            
            // Transfer profit to owner
            if (profit > 0) {
                IERC20(tokens[0]).safeTransfer(owner(), profit);
                emit ArbitrageExecuted(tokens[0], amounts[0], profit, tx.origin);
            }
        } else {
            emit ArbitrageFailed(tokens[0], amounts[0], "No profit generated");
            revert("Arbitrage failed");
        }
    }
    
    function _executeSwap(
        address router,
        bytes memory swapData,
        address token,
        uint256 amount
    ) private {
        IERC20(token).safeApprove(router, amount);
        
        (bool success,) = router.call(swapData);
        require(success, "Swap failed");
        
        IERC20(token).safeApprove(router, 0);
    }
    
    function setMinProfitThreshold(uint256 _threshold) external onlyOwner {
        minProfitThreshold = _threshold;
    }
    
    function setAuthorizedExecutor(address executor, bool authorized) external onlyOwner {
        authorizedExecutors[executor] = authorized;
    }
    
    function emergencyWithdraw(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(owner(), balance);
            emit ProfitWithdrawn(token, balance, owner());
        }
    }
    
    function emergencyWithdrawETH() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success,) = owner().call{value: balance}("");
            require(success, "ETH transfer failed");
        }
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    receive() external payable {}
}
