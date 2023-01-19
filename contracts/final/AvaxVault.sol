// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface GLPRouter {
    function unstakeAndRedeemGlp(
        address _tokenOut,
        uint256 _glpAmount,
        uint256 _minOut,
        address _receiver
    ) external returns (uint256);

    function mintAndStakeGlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdg,
        uint256 _minGlp
    ) external returns (uint256);
}

interface rewardRouter {
    function claimFees() external;

    function claimEsGmx() external;

    function stakeEsGmx(uint256 _amount) external;
}

interface GDtoken is IERC20 {
    function mint(address recipient, uint256 _amount) external;

    function burn(address _from, uint256 _amount) external;
}

interface GLPPriceFeed {
    function getGLPprice() external view returns (uint256);

    function getPrice(address _token) external view returns (uint256);
}

interface IWAVAX is IERC20 {
    function deposit() external payable;

    function withdraw(uint256) external;
}

interface IERC20Extented is IERC20 {
    function decimals() external view returns (uint8);
}

contract AvaxVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    uint256 public treasuryMintedGLP = 0;
    uint256 public slippage = 500;
    IWAVAX public WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    IERC20 public USDC = IERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
    IERC20 public WETH = IERC20(0x49D5c2BdFfac6CE2BFdB6640F4F80f226bc10bAB);
    IERC20 public WBTC = IERC20(0x152b9d0FdC40C096757F570A51E494bd4b943E50);
    IERC20 public EsGMX = IERC20(0xFf1489227BbAAC61a9209A08929E4c2a526DdD17);
    IERC20 public fsGLP = IERC20(0x9e295B5B976a184B14aD8cd72413aD846C299660);
    //IERC20 public WAVAX;
    //IERC20 public WBTC;

    //IERC20 public gdWAVAX;
    //IERC20 public gdWBTC;
    GLPRouter public _GLPRouter =
        GLPRouter(0xB70B91CE0771d3f4c81D87660f71Da31d48eB3B3);
    rewardRouter public _RewardRouter =
        rewardRouter(0x82147C5A7E850eA4E28155DF107F2590fD4ba327);
    address poolGLP = 0xD152c7F25db7F4B95b7658323c5F33d176818EE4;
    GLPPriceFeed public priceFeed =
        GLPPriceFeed(0x846ecf0462981CC0f2674f14be6Da2056Fc16bDA);

    uint256 public compoundPercentage = 500;

    uint8 poolCount = 4;

    struct PoolInfo {
        IERC20 lpToken;
        GDtoken GDlptoken;
        uint256 EarnRateSec;
        uint256 totalStaked;
        uint256 lastUpdate;
        uint256 vaultcap;
        uint256 glpFees;
        uint256 APR;
        bool stakable;
        bool withdrawable;
        bool rewardStart;
    }

    // Info of each pool.
    PoolInfo[] public poolInfo;

    constructor(
        GDtoken _gdUSDC,
        GDtoken _gdAVAX,
        GDtoken _gdBTC,
        GDtoken _gdETH
    ) {
        poolInfo.push(
            PoolInfo({
                lpToken: USDC,
                GDlptoken: _gdUSDC,
                totalStaked: 0,
                EarnRateSec: 0,
                lastUpdate: block.timestamp,
                vaultcap: 0,
                stakable: false,
                withdrawable: false,
                rewardStart: false,
                glpFees: 500,
                APR: 1600
            })
        );
        poolInfo.push(
            PoolInfo({
                lpToken: WAVAX,
                GDlptoken: _gdAVAX,
                totalStaked: 0,
                EarnRateSec: 0,
                lastUpdate: block.timestamp,
                vaultcap: 0,
                stakable: false,
                withdrawable: false,
                rewardStart: false,
                glpFees: 250,
                APR: 1600
            })
        );

        poolInfo.push(
            PoolInfo({
                lpToken: WBTC,
                GDlptoken: _gdBTC,
                totalStaked: 0,
                EarnRateSec: 0,
                lastUpdate: block.timestamp,
                vaultcap: 0,
                stakable: false,
                withdrawable: false,
                rewardStart: false,
                glpFees: 250,
                APR: 1600
            })
        );
        poolInfo.push(
            PoolInfo({
                lpToken: WETH,
                GDlptoken: _gdETH,
                totalStaked: 0,
                EarnRateSec: 0,
                lastUpdate: block.timestamp,
                vaultcap: 0,
                stakable: false,
                withdrawable: false,
                rewardStart: false,
                glpFees: 250,
                APR: 1600
            })
        );
    }

    function swapGLPto(
        uint256 _amount,
        address token,
        uint256 min_receive
    ) private returns (uint256) {
        return
            _GLPRouter.unstakeAndRedeemGlp(
                token,
                _amount,
                min_receive,
                address(this)
            );
    }

    function swapGLPout(
        uint256 _amount,
        address token,
        uint256 min_receive
    ) external onlyOwner returns (uint256) {
        require(
            ((fsGLP.balanceOf(address(this)) - _amount) >= GLPbackingNeeded()),
            "below backing"
        );
        return
            _GLPRouter.unstakeAndRedeemGlp(
                token,
                _amount,
                min_receive,
                address(this)
            );
    }

    function swaptoGLP(uint256 _amount, address token)
        private
        returns (uint256)
    {
        IERC20(token).safeApprove(poolGLP, _amount);
        return _GLPRouter.mintAndStakeGlp(token, _amount, 0, 0);
    }

    function treasuryMint(uint256 _amount, address _token) public onlyOwner {
        require(IERC20(_token).balanceOf(address(this)) >= _amount);
        treasuryMintedGLP = treasuryMintedGLP.add(swaptoGLP(_amount, _token));

        IERC20(_token).safeApprove(address(poolGLP), 0);
    }

    function cycleRewardsETHandEsGMX() external onlyOwner {
        _RewardRouter.claimEsGmx();
        _RewardRouter.stakeEsGmx(EsGMX.balanceOf(address(this)));
        _cycleRewardsETH();
    }

    function cycleRewardsETH() external onlyOwner {
        _cycleRewardsETH();
    }

    function _cycleRewardsETH() private {
        _RewardRouter.claimFees();
        uint256 rewards = WAVAX.balanceOf(address(this));
        uint256 compoundAmount = rewards.mul(compoundPercentage).div(1000);
        swaptoGLP(compoundAmount, address(WAVAX));
        WAVAX.transfer(owner(), WAVAX.balanceOf(address(this)));
    }

    function setCompoundPercentage(uint256 _percent) external onlyOwner {
        require(_percent < 900 && _percent > 0, "not in range");
        compoundPercentage = _percent;
    }

    function setGLPFees(uint256 _pid, uint256 _percent) external onlyOwner {
        require(_percent < 1000, "not in range");
        poolInfo[_pid].glpFees = _percent;
    }

    // Unlocks the staked + gained USDC and burns xUSDC
    function updatePool(uint256 _pid) internal {
        uint256 timepass = block.timestamp.sub(poolInfo[_pid].lastUpdate);
        poolInfo[_pid].lastUpdate = block.timestamp;
        uint256 reward = poolInfo[_pid].EarnRateSec.mul(timepass);
        poolInfo[_pid].totalStaked = poolInfo[_pid].totalStaked.add(reward);
    }

    function updateOracle(GLPPriceFeed _newOracle) external onlyOwner {
        priceFeed = _newOracle;
    }

    function updateRouter(GLPRouter _newRouter) external onlyOwner {
        _GLPRouter = _newRouter;
    }

    function updateRewardRouter(rewardRouter _newRouter) external onlyOwner {
        _RewardRouter = _newRouter;
    }

    function currentPoolTotal(uint256 _pid) public view returns (uint256) {
        uint256 reward = 0;
        if (poolInfo[_pid].rewardStart) {
            uint256 timepass = block.timestamp.sub(poolInfo[_pid].lastUpdate);
            reward = poolInfo[_pid].EarnRateSec.mul(timepass);
        }
        return poolInfo[_pid].totalStaked.add(reward);
    }

    function updatePoolRate(uint256 _pid) internal {
        poolInfo[_pid].EarnRateSec = poolInfo[_pid]
            .totalStaked
            .mul(poolInfo[_pid].APR)
            .div(10**4)
            .div(365 days);
    }

    function setPoolCap(uint256 _pid, uint256 _vaultcap) external onlyOwner {
        poolInfo[_pid].vaultcap = _vaultcap;
    }

    function setAPR(uint256 _pid, uint256 _apr) external onlyOwner {
        require(_apr > 500 && _apr < 4000, " apr not in range");
        poolInfo[_pid].APR = _apr;
        if (poolInfo[_pid].rewardStart) {
            updatePool(_pid);
        }
        updatePoolRate(_pid);
    }

    function setOpenVault(uint256 _pid, bool open) external onlyOwner {
        poolInfo[_pid].stakable = open;
    }

    function setOpenAllVault(bool open) external onlyOwner {
        for (uint256 _pid = 0; _pid < poolInfo.length; ++_pid) {
            poolInfo[_pid].stakable = open;
        }
    }

    function startReward(uint256 _pid) external onlyOwner {
        require(!poolInfo[_pid].rewardStart, "already started");
        poolInfo[_pid].rewardStart = true;
        poolInfo[_pid].lastUpdate = block.timestamp;
    }

    function pauseReward(uint256 _pid) external onlyOwner {
        require(poolInfo[_pid].rewardStart, "not started");

        updatePool(_pid);
        updatePoolRate(_pid);
        poolInfo[_pid].rewardStart = false;
        poolInfo[_pid].lastUpdate = block.timestamp;
    }

    function openWithdraw(uint256 _pid, bool open) external onlyOwner {
        poolInfo[_pid].withdrawable = open;
    }

    function openAllWithdraw(bool open) external onlyOwner {
        for (uint256 _pid = 0; _pid < poolInfo.length; ++_pid) {
            poolInfo[_pid].withdrawable = open;
        }
    }

    function setSlippage(uint256 _slippage) external onlyOwner {
        require(_slippage >= 200 && _slippage <= 1000, "not in range");
        slippage = _slippage;
    }

    function checkDuplicate(GDtoken _GDlptoken) internal view returns (bool) {
        for (uint256 i = 0; i < poolInfo.length; ++i) {
            if (poolInfo[i].GDlptoken == _GDlptoken) {
                return false;
            }
        }
        return true;
    }

    function addPool(
        IERC20 _lptoken,
        GDtoken _GDlptoken,
        uint256 _fees,
        uint256 _apr
    ) external onlyOwner {
        require(_fees <= 1000, "out of range. Fees too high");
        require(_apr > 500 && _apr < 4000, " apr not in range");
        require(checkDuplicate(_GDlptoken), "pool already created");
        require(poolCount <= 15, "too many pools");

        poolInfo.push(
            PoolInfo({
                lpToken: _lptoken,
                GDlptoken: _GDlptoken,
                totalStaked: 0,
                EarnRateSec: 0,
                lastUpdate: block.timestamp,
                vaultcap: 0,
                stakable: false,
                withdrawable: false,
                rewardStart: false,
                glpFees: _fees,
                APR: _apr
            })
        );
        poolCount += 1;
    }

    function enterETH(uint256 _pid) external payable nonReentrant {
        require(msg.value > 0, "RewardRouter: invalid msg.value");

        uint256 _amountin = msg.value;
        IERC20 StakedToken = poolInfo[_pid].lpToken;
        require(address(StakedToken) == address(WAVAX), "not avax pool");

        uint256 _amount = _amountin;

        GDtoken GDT = poolInfo[_pid].GDlptoken;

        require(poolInfo[_pid].stakable, "not stakable");
        require(
            (poolInfo[_pid].totalStaked + _amount) <= poolInfo[_pid].vaultcap,
            "cant deposit more than vault cap"
        );

        if (poolInfo[_pid].rewardStart) {
            updatePool(_pid);
        }
        // Gets the amount of USDC locked in the contract
        uint256 totalStakedTokens = poolInfo[_pid].totalStaked;
        // Gets the amount of gdUSDC in existence
        uint256 totalShares = GDT.totalSupply();

        uint256 balanceMultipier = 100000 - poolInfo[_pid].glpFees;
        uint256 amountAfterFee = _amount.mul(balanceMultipier).div(100000);
        // If no gdUSDC exists, mint it 1:1 to the amount put in
        if (totalShares == 0 || totalStakedTokens == 0) {
            GDT.mint(msg.sender, amountAfterFee);
        }
        // Calculate and mint the amount of gdUSDC the USDC is worth. The ratio will change overtime
        else {
            uint256 what = amountAfterFee.mul(totalShares).div(
                totalStakedTokens
            );
            GDT.mint(msg.sender, what);
        }

        poolInfo[_pid].totalStaked = poolInfo[_pid].totalStaked.add(
            amountAfterFee
        );

        updatePoolRate(_pid);
        WAVAX.deposit{value: _amountin}();
        swaptoGLP(_amountin, address(StakedToken));
        StakedToken.safeApprove(address(poolGLP), 0);
    }

    function leaveETH(uint256 _share, uint256 _pid) external nonReentrant {
        GDtoken GDT = poolInfo[_pid].GDlptoken;
        IERC20 StakedToken = poolInfo[_pid].lpToken;

        require(_share <= GDT.balanceOf(msg.sender), "balance too low");
        require(poolInfo[_pid].withdrawable, "withdraw window not opened");

        if (poolInfo[_pid].rewardStart) {
            updatePool(_pid);
        }

        // Gets the amount of gmdUSDC in existence
        uint256 totalShares = GDT.totalSupply();
        // Calculates the amount of USDC the gmdUSDC is worth
        uint256 amountOut = _share.mul(poolInfo[_pid].totalStaked).div(
            totalShares
        );

        poolInfo[_pid].totalStaked = poolInfo[_pid].totalStaked.sub(amountOut);
        updatePoolRate(_pid);
        GDT.burn(msg.sender, _share);

        uint256 amountSendOut = amountOut;

        uint256 percentage = 100000 - slippage;

        uint256 glpPrice = priceFeed.getGLPprice().mul(percentage).div(100000);
        uint256 tokenPrice = priceFeed.getPrice(address(StakedToken));

        uint256 glpOut = amountOut
            .mul(10**12)
            .mul(tokenPrice)
            .div(glpPrice)
            .div(10**30); //amount *glp price after decimals handled
        swapGLPto(glpOut, address(StakedToken), amountSendOut);

        require(address(StakedToken) == address(WAVAX), "not eth pool");
        WAVAX.withdraw(amountSendOut);

        (bool success, ) = payable(msg.sender).call{value: amountSendOut}("");
        require(success, "Failed to send Ether");
    }

    receive() external payable {}

    function enter(uint256 _amountin, uint256 _pid) public nonReentrant {
        require(_amountin > 0, "invalid amount");
        uint256 _amount = _amountin;

        GDtoken GDT = poolInfo[_pid].GDlptoken;
        IERC20 StakedToken = poolInfo[_pid].lpToken;

        uint256 decimalMul = 18 -
            IERC20Extented(address(StakedToken)).decimals();

        //decimals handlin
        _amount = _amountin.mul(10**decimalMul);

        require(
            _amountin <= StakedToken.balanceOf(msg.sender),
            "balance too low"
        );
        require(poolInfo[_pid].stakable, "not stakable");
        require(
            (poolInfo[_pid].totalStaked + _amount) <= poolInfo[_pid].vaultcap,
            "cant deposit more than vault cap"
        );

        if (poolInfo[_pid].rewardStart) {
            updatePool(_pid);
        }

        // Gets the amount of USDC locked in the contract
        uint256 totalStakedTokens = poolInfo[_pid].totalStaked;
        // Gets the amount of gdUSDC in existence
        uint256 totalShares = GDT.totalSupply();

        uint256 balanceMultipier = 100000 - poolInfo[_pid].glpFees;
        uint256 amountAfterFee = _amount.mul(balanceMultipier).div(100000);
        // If no gdUSDC exists, mint it 1:1 to the amount put in
        if (totalShares == 0 || totalStakedTokens == 0) {
            GDT.mint(msg.sender, amountAfterFee);
        }
        // Calculate and mint the amount of gdUSDC the USDC is worth. The ratio will change overtime
        else {
            uint256 what = amountAfterFee.mul(totalShares).div(
                totalStakedTokens
            );
            GDT.mint(msg.sender, what);
        }

        poolInfo[_pid].totalStaked = poolInfo[_pid].totalStaked.add(
            amountAfterFee
        );

        updatePoolRate(_pid);

        StakedToken.safeTransferFrom(msg.sender, address(this), _amountin);

        swaptoGLP(_amountin, address(StakedToken));
        StakedToken.safeApprove(address(poolGLP), 0);
    }

    function leave(uint256 _share, uint256 _pid)
        public
        nonReentrant
        returns (uint256)
    {
        GDtoken GDT = poolInfo[_pid].GDlptoken;
        IERC20 StakedToken = poolInfo[_pid].lpToken;

        require(_share <= GDT.balanceOf(msg.sender), "balance too low");
        require(poolInfo[_pid].withdrawable, "withdraw window not opened");

        if (poolInfo[_pid].rewardStart) {
            updatePool(_pid);
        }

        // Gets the amount of gdUSDC in existence
        uint256 totalShares = GDT.totalSupply();
        // Calculates the amount of USDC the gdUSDC is worth
        uint256 amountOut = _share.mul(poolInfo[_pid].totalStaked).div(
            totalShares
        );

        poolInfo[_pid].totalStaked = poolInfo[_pid].totalStaked.sub(amountOut);
        updatePoolRate(_pid);
        GDT.burn(msg.sender, _share);

        uint256 amountSendOut = amountOut;

        uint256 decimalMul = 18 -
            IERC20Extented(address(StakedToken)).decimals();

        //decimals handlin
        amountSendOut = amountOut.div(10**decimalMul);

        uint256 percentage = 100000 - slippage;

        uint256 glpPrice = priceFeed.getGLPprice().mul(percentage).div(100000);
        uint256 tokenPrice = priceFeed.getPrice(address(StakedToken));

        uint256 glpOut = amountOut
            .mul(10**12)
            .mul(tokenPrice)
            .div(glpPrice)
            .div(10**30); //amount *glp price after decimals handled
        swapGLPto(glpOut, address(StakedToken), amountSendOut);

        StakedToken.safeTransfer(msg.sender, amountSendOut);

        return amountSendOut;
    }

    function displayStakedBalance(address _address, uint256 _pid)
        public
        view
        returns (uint256)
    {
        GDtoken GDT = poolInfo[_pid].GDlptoken;
        uint256 totalShares = GDT.totalSupply();
        // Calculates the amount of USDC the gdUSDC is worth
        uint256 amountOut = GDT
            .balanceOf(_address)
            .mul(currentPoolTotal(_pid))
            .div(totalShares);
        return amountOut;
    }

    function GDpriceToStakedtoken(uint256 _pid) public view returns (uint256) {
        GDtoken GDT = poolInfo[_pid].GDlptoken;
        uint256 totalShares = GDT.totalSupply();
        // Calculates the amount of USDC the gdUSDC is worth
        uint256 amountOut = (currentPoolTotal(_pid)).mul(10**18).div(
            totalShares
        );
        return amountOut;
    }

    function convertDust(address _token) external onlyOwner {
        swaptoGLP(IERC20(_token).balanceOf(address(this)), _token);
        IERC20(_token).safeApprove(address(poolGLP), 0);
    }

    //Recover treasury tokens from contract if needed

    function recoverTreasuryTokensFromGLP(address _token, uint256 GLPamount)
        external
        onlyOwner
    {
        //only allow to recover treasury tokens and not drain the vault
        require(
            ((fsGLP.balanceOf(address(this)) - GLPamount) >=
                GLPbackingNeeded()),
            "below backing"
        );
        treasuryMintedGLP = treasuryMintedGLP.sub(GLPamount);
        swapGLPto(GLPamount, _token, 0);
        IERC20(_token).safeTransfer(
            msg.sender,
            IERC20(_token).balanceOf(address(this))
        );
    }

    function recoverTreasuryTokens(address _token, uint256 _amount)
        external
        onlyOwner
    {
        //cant drain glp
        require(_token != address(fsGLP), "no glp draining");

        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    function totalUSDvault(uint256 _pid) public view returns (uint256) {
        IERC20 StakedToken = poolInfo[_pid].lpToken;
        uint256 tokenPrice = priceFeed.getPrice(address(StakedToken));
        uint256 totalStakedTokens = currentPoolTotal(_pid);
        uint256 totalUSD = tokenPrice.mul(totalStakedTokens).div(10**30);

        return totalUSD;
    }

    function totalUSDvaults() public view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < poolInfo.length; ++i) {
            total = total.add(totalUSDvault(i));
        }

        return total;
    }

    function GLPbackingNeeded() public view returns (uint256) {
        uint256 glpPrice = priceFeed.getGLPprice();

        return totalUSDvaults().mul(10**12).div(glpPrice);
    }

    function GLPinVault() public view returns (uint256) {
        return fsGLP.balanceOf(address(this));
    }
}
