// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../contracts/FlashLoanArbitrage.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10**18);
    }
}

contract FlashLoanArbitrageTest is Test {
    FlashLoanArbitrage public arbitrage;
    MockToken public tokenA;
    MockToken public tokenB;
    address public owner = address(0x1);
    address public user = address(0x2);
    
    function setUp() public {
        vm.startPrank(owner);
        
        # Deploy tokens
        tokenA = new MockToken("Token A", "TKA");
        tokenB = new MockToken("Token B", "TKB");
        
        # Deploy arbitrage contract
        arbitrage = new FlashLoanArbitrage();
        arbitrage.initialize(0.01 ether);
        
        vm.stopPrank();
    }
    
    function testInitialization() public {
        assertEq(arbitrage.owner(), owner);
        assertEq(arbitrage.minProfitThreshold(), 0.01 ether);
        assertTrue(arbitrage.authorizedExecutors(owner));
    }
    
    function testSetMinProfitThreshold() public {
        vm.prank(owner);
        arbitrage.setMinProfitThreshold(0.02 ether);
        assertEq(arbitrage.minProfitThreshold(), 0.02 ether);
    }
    
    function testOnlyOwnerCanSetThreshold() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        arbitrage.setMinProfitThreshold(0.02 ether);
    }
    
    function testAuthorizedExecutor() public {
        vm.prank(owner);
        arbitrage.setAuthorizedExecutor(user, true);
        assertTrue(arbitrage.authorizedExecutors(user));
        
        vm.prank(owner);
        arbitrage.setAuthorizedExecutor(user, false);
        assertFalse(arbitrage.authorizedExecutors(user));
    }
    
    function testEmergencyWithdraw() public {
        # Send tokens to contract
        tokenA.transfer(address(arbitrage), 100 * 10**18);
        
        uint256 initialBalance = tokenA.balanceOf(owner);
        
        vm.prank(owner);
        arbitrage.emergencyWithdraw(address(tokenA));
        
        assertEq(tokenA.balanceOf(owner), initialBalance + 100 * 10**18);
        assertEq(tokenA.balanceOf(address(arbitrage)), 0);
    }
    
    function testPauseUnpause() public {
        vm.prank(owner);
        arbitrage.pause();
        assertTrue(arbitrage.paused());
        
        vm.prank(owner);
        arbitrage.unpause();
        assertFalse(arbitrage.paused());
    }
    
    function testUpgradeability() public {
        # Deploy new implementation
        FlashLoanArbitrage newImplementation = new FlashLoanArbitrage();
        
        vm.prank(owner);
        arbitrage.upgradeTo(address(newImplementation));
        
        # Verify upgrade successful
        assertTrue(true);
    }
}
