// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface GLPpool {
    function getMinPrice(address _token) external view returns (uint256);
    function getMaxPrice(address _token) external view returns (uint256);
}

interface GLPmanager {
    function getAum(bool maximise) external view returns (uint256);
}

contract GLPPrice {

     using SafeMath for uint256;
     IERC20 WETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
     IERC20 WBTC = IERC20(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
     IERC20 USDC = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
     IERC20 DAI = IERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);
     IERC20 UNI = IERC20(0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0);
     IERC20 FRAX = IERC20(0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F);
     IERC20 LINK = IERC20(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4);
     IERC20 USDT = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);

     IERC20 public GLP = IERC20(0x4277f8F2c384827B5273592FF7CeBd9f2C1ac258);
     GLPmanager public GLPm = GLPmanager(0x321F653eED006AD1C29D174e17d96351BDe22649);
     address GLPpool_add = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
     GLPpool pool = GLPpool(GLPpool_add);

     function getGLPprice() public view returns (uint256){
        uint256 total_supply = GLP.totalSupply();
        uint256 aum = GLPm.getAum(true); 
        return aum.mul(100000).div(total_supply).div(100000);
     }

     function getPrice(address _token) public view returns (uint256){
         return pool.getMinPrice(_token);
     }
     function geAum() public view returns (uint256){
         return GLPm.getAum(true);
     }
}