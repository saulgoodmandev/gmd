// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

contract GMD is ERC20("GMD", "GMD"), Ownable , ReentrancyGuard{ 

    constructor() {
        _mint(msg.sender, 50000 * 10 ** decimals());
    }
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    struct UserInfo  {
        uint256 totalMinted;
        uint256 lastInteractionTime;
        uint256 VestPeriod;
    }

    mapping(address => UserInfo) public userInfo;

    uint256 public mintPrice = 1000;
    uint256 public mintCap = 0;
    uint256 public vestingPeriod = 5 days;
    bool public mintOpen = false;
    IERC20 public USDC = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);


    function burn(uint256 _amount) external  {
        _burn(msg.sender, _amount);
    }

    function setMintCap(uint256 _mintCap) external onlyOwner {
        mintCap = _mintCap;
    }

    
    function setMintPrice(uint256 _mintPrice) external onlyOwner {
        require(_mintPrice >= mintPrice, "can't be lower than last mint");
        mintPrice = _mintPrice;
    }

    function setVestingPeriod(uint256 _period) external onlyOwner {
        require(_period >= 3 days &&_period <=5 days, "not in range");
        vestingPeriod = _period;
    }

    function claimableTokens(address _address) external view returns(uint256) {
        uint256 timePass = block.timestamp.sub(userInfo[_address].lastInteractionTime);
        uint256 claimable;
        if (timePass >= userInfo[_address].VestPeriod){
            claimable = userInfo[_address].totalMinted;
        }
        else {
            claimable = userInfo[_address].totalMinted.mul(timePass).div(userInfo[_address].VestPeriod);
        }
        return claimable;
    }


    function setOpenMint(bool _mintOpen) external onlyOwner {
        mintOpen = _mintOpen;
    }

    function recoverTreasuryTokens() external onlyOwner {
        USDC.safeTransfer(owner(), USDC.balanceOf(address(this)));
    }


    function mint(uint256 _amount) external nonReentrant {

        require(_amount <= 2000000000, "max 2000 usdc per tx");
        require(mintOpen, "mint not opened");
        require(USDC.balanceOf(msg.sender) >= _amount, "USDC balance too low");
        uint256 _amountin = _amount.mul(10**12);
        uint256 amountOut = _amountin.mul(1000).div(mintPrice);
        
        require(this.totalSupply().add(amountOut) <= mintCap, "over mint cap");
        userInfo[msg.sender].totalMinted = userInfo[msg.sender].totalMinted.add(amountOut);
        userInfo[msg.sender].lastInteractionTime = block.timestamp;
        userInfo[msg.sender].VestPeriod = vestingPeriod;

        _mint(address(this), amountOut);
        USDC.safeTransferFrom(msg.sender, address(this), _amount);
    }

    function claim() external nonReentrant {

        require(userInfo[msg.sender].totalMinted > 0, "no mint");
        uint256 timePass = block.timestamp.sub(userInfo[msg.sender].lastInteractionTime);
        uint256 claimable;
        if (timePass >= userInfo[msg.sender].VestPeriod){
            claimable = userInfo[msg.sender].totalMinted;
            userInfo[msg.sender].VestPeriod = 0;
        }
        else {
            claimable = userInfo[msg.sender].totalMinted.mul(timePass).div(userInfo[msg.sender].VestPeriod);
            userInfo[msg.sender].VestPeriod = userInfo[msg.sender].VestPeriod.sub(timePass);
            
        }
        userInfo[msg.sender].totalMinted = userInfo[msg.sender].totalMinted.sub(claimable);
        userInfo[msg.sender].lastInteractionTime = block.timestamp;

        this.transfer(msg.sender, claimable);
    }

    function remainingMintableTokens() external view returns(uint256){
        
        return mintCap.sub(this.totalSupply());
    }

    function remainingVestedTime(address _address) external view returns(uint256){
        uint256 timePass = block.timestamp.sub(userInfo[_address].lastInteractionTime);
        if (timePass >= userInfo[_address].VestPeriod){
            return 0;
        }
        else {
            return userInfo[_address].VestPeriod.sub(timePass);
        }
        
    }

}