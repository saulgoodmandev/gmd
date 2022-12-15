// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

contract GMvaultMigration is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public gmdUSDCv1 = IERC20(0x4A723DE8aF2be96292dA3F824a96bfA053d4aF66);
    IERC20 public gmdUSDCv2 = IERC20(0x3DB4B7DA67dd5aF61Cb9b3C70501B1BdB24b2C22);
    IERC20 public gmdETHv1 = IERC20(0xc5182E92bf001baE7049c4496caD96662Db1A186);
    IERC20 public gmdETHv2 = IERC20(0x1E95A37Be8A17328fbf4b25b9ce3cE81e271BeB3);
    IERC20 public gmdBTCv1 = IERC20(0xEffaE8eB4cA7db99e954adc060B736Db78928467);
    IERC20 public gmdBTCv2 = IERC20(0x147FF11D9B9Ae284c271B2fAaE7068f4CA9BB619);
    
    
    constructor(){}

    function withdrawTokens(address _tokenAddress) external onlyOwner {
        IERC20 token = IERC20(_tokenAddress);
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    function migrate() external nonReentrant {


        uint256 usdcBalance = gmdUSDCv1.balanceOf(msg.sender);
        uint256 ETHBalance = gmdETHv1.balanceOf(msg.sender);
        uint256 BTCBalance = gmdBTCv1.balanceOf(msg.sender);

        if (usdcBalance > 0) {
            gmdUSDCv1.safeTransferFrom(msg.sender, address(this), usdcBalance);
            gmdUSDCv2.safeTransfer(msg.sender, usdcBalance);
        }

        
        if (ETHBalance > 0) {
            gmdETHv1.safeTransferFrom(msg.sender, address(this), ETHBalance);
            gmdETHv2.safeTransfer(msg.sender, ETHBalance);
        }

        
        if (BTCBalance > 0) {
            gmdBTCv1.safeTransferFrom(msg.sender, address(this), BTCBalance);
            gmdBTCv2.safeTransfer(msg.sender, BTCBalance);
        }

    }



}
