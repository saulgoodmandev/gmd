// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract gmdBTC is ERC20("gmdBTC", "gmdBTC"), Ownable {
    using SafeMath for uint256;
 
    function burn(address _from, uint256 _amount) external onlyOwner  {
        _burn(_from, _amount);
    }

    function mint(address recipient, uint256 _amount) external onlyOwner {
        _mint(recipient, _amount);

    }

}