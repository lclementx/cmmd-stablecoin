// SPDX-License-Identifier: GPL-3.0-or-later
//0xE42d0b39B4862462ECA4cC7f30da6680b9b86d32
pragma solidity 0.8.7;

import "./SafeMathInt.sol";
import "./SafeMath.sol";

interface ICMMD {
    function totalSupply() external view returns (uint256);

    function rebase(uint256 epoch, int256 supplyDelta) external returns (uint256);
}

interface IOracle {
    function getData() external returns (uint256, bool);
}

/**
 * @title CMMD Monetary Supply Policy
 * @dev This is an implementation of the CMMD Ideal Money protocol.
 *
 *      This component regulates the token supply of the CMMD ERC20 token in response to
 *      market oracles.
 */
contract CMMDPolicy {
    event LogRebase(
        uint256 indexed epoch,
        uint256 exchangeRate,
        uint256 cpi,
        int256 requestedSupplyAdjustment,
        uint256 timestampSec
    );

    ICMMD public cmmd;

    // Provides the current CPI, as an 18 decimal fixed point number.
    IOracle public cpiOracle;
       
    // Provides the current CPI, as an 18 decimal fixed point number.
    IOracle public marketOracle;

    // CPI value at the time of launch, as an 18 decimal fixed point number.
    uint256 private baseCpi;

    // If the current exchange rate is within this fractional distance from the target, no supply
    // update is performed. Fixed point number--same format as the rate.
    // (ie) abs(rate - targetRate) / targetRate < deviationThreshold, then no supply change.
    // DECIMALS Fixed point number.
    uint256 public deviationThreshold;

    // The number of rebase cycles since inception
    uint256 public epoch;

    uint256 private constant DECIMALS = 18;

    // Due to the expression in computeSupplyDelta(), MAX_RATE * MAX_SUPPLY must fit into an int256.
    // Both are 18 decimals fixed point numbers.
    uint256 private constant MAX_RATE = 10**6 * 10**DECIMALS;
    // MAX_SUPPLY = MAX_INT256 / MAX_RATE
    uint256 private constant MAX_SUPPLY = uint256(type(int256).max) / MAX_RATE;

    // DECIMALS decimal fixed point numbers.
    // Used in computation of  (Upper-Lower)/(1-(Upper/Lower)/2^(Growth*delta))) + Lower
    int256 public rebaseFunctionLowerPercentage;
    int256 public rebaseFunctionUpperPercentage;
    int256 public rebaseFunctionGrowth;

    int256 private constant ONE = int256(10**DECIMALS);

    /**
     * @notice Initiates a new rebase operation, provided the minimum time period has elapsed.
     * @dev Changes supply with percentage of:
     *  (Upper-Lower)/(1-(Upper/Lower)/2^(Growth*NormalizedPriceDelta))) + Lower
     */
    function rebase() public {
        epoch = epoch + 1;

        uint256 cpi;
        bool cpiValid;
        (cpi, cpiValid) = cpiOracle.getData();
        require(cpiValid);

        uint256 targetRate = SafeMath.div(SafeMath.mul(cpi,10**DECIMALS),(baseCpi));

        uint256 exchangeRate;
        bool rateValid;
        (exchangeRate, rateValid) = marketOracle.getData();
        require(rateValid);

        if (exchangeRate > MAX_RATE) {
            exchangeRate = MAX_RATE;
        }

        int256 supplyDelta = computeSupplyDelta(exchangeRate, targetRate);

        if (supplyDelta > 0 && cmmd.totalSupply() + (uint256(supplyDelta)) > MAX_SUPPLY) {
            supplyDelta = int256(MAX_SUPPLY - (cmmd.totalSupply()));
        }

        uint256 supplyAfterRebase = cmmd.rebase(epoch, supplyDelta);
        assert(supplyAfterRebase <= MAX_SUPPLY);
        emit LogRebase(epoch, exchangeRate, cpi, supplyDelta, block.timestamp);
    }

    /**
     * @notice Sets the reference to the CPI oracle.
     * @param cpiOracle_ The address of the cpi oracle contract.
     */
    function setCpiOracle(IOracle cpiOracle_) public {
        cpiOracle = cpiOracle_;
    }

     /**
     * @notice Sets the reference to the Market oracle.
     * @param marketOracle_ The address of the market oracle contract.
     */
    function setMarketOracle(IOracle marketOracle_) public {
        marketOracle = marketOracle_;
    }


    function setRebaseFunctionGrowth(int256 rebaseFunctionGrowth_) public {
        require(rebaseFunctionGrowth_ >= 0);
        rebaseFunctionGrowth = rebaseFunctionGrowth_;
    }

    function setRebaseFunctionLowerPercentage(int256 rebaseFunctionLowerPercentage_)
        public
    {
        require(rebaseFunctionLowerPercentage_ <= 0);
        rebaseFunctionLowerPercentage = rebaseFunctionLowerPercentage_;
    }

    function setRebaseFunctionUpperPercentage(int256 rebaseFunctionUpperPercentage_)
        public
    {
        require(rebaseFunctionUpperPercentage_ >= 0);
        rebaseFunctionUpperPercentage = rebaseFunctionUpperPercentage_;
    }

    /**
     * @notice Sets the deviation threshold fraction. If the exchange rate given by the market
     *         oracle is within this fractional distance from the targetRate, then no supply
     *         modifications are made. DECIMALS fixed point number.
     * @param deviationThreshold_ The new exchange rate threshold fraction.
     */
    function setDeviationThreshold(uint256 deviationThreshold_) public {
        deviationThreshold = deviationThreshold_;
    }

    /**
     * @dev ZOS upgradable contract initialization method.
     *      It is called at the time of contract creation to invoke parent class initializers and
     *      initialize the contract's state variables.
     */
    function initialize(
        ICMMD cmmd_,
        uint256 baseCpi_
    ) public {

        // deviationThreshold = 0.05e18 = 5e16
        deviationThreshold = 5 * 10**(DECIMALS - 2);

        rebaseFunctionGrowth = int256(3 * (10**DECIMALS));
        rebaseFunctionUpperPercentage = int256(10 * (10**(DECIMALS - 2))); // 0.1
        rebaseFunctionLowerPercentage = int256((-10) * int256(10**(DECIMALS - 2))); // -0.1

        epoch = 0;

        cmmd = cmmd_;
        baseCpi = baseCpi_;
    }

    /**
     * Computes the percentage of supply to be added or removed:
     * Using the function in https://github.com/ampleforth/AIPs/blob/master/AIPs/aip-5.md
     * @param normalizedRate value of rate/targetRate in DECIMALS decimal fixed point number
     * @return The percentage of supply to be added or removed.
     */
    function computeRebasePercentage(
        int256 normalizedRate,
        int256 lower,
        int256 upper,
        int256 growth
    ) public pure returns (int256) {
        int256 delta;

        delta = SafeMathInt.sub(normalizedRate,ONE);

        // Compute: (Upper-Lower)/(1-(Upper/Lower)/2^(Growth*delta))) + Lower

        int256 exponent = SafeMathInt.div(SafeMathInt.mul(growth,delta),ONE);
        // Cap exponent to guarantee it is not too big for twoPower
        if (exponent > SafeMathInt.mul(ONE,100)) {
            exponent = SafeMathInt.mul(ONE,100);
        }
        if (exponent < SafeMathInt.mul(ONE,-100)) {
            exponent = SafeMathInt.mul(ONE,-100);
        }

        int256 pow = SafeMathInt.twoPower(exponent, ONE); // 2^(Growth*Delta)
        if (pow == 0) {
            return lower;
        }
        int256 numerator = SafeMathInt.sub(upper,lower); //(Upper-Lower)
        int256 intermediate = SafeMathInt.div(SafeMathInt.mul(upper,ONE),lower);
        intermediate = SafeMathInt.div(SafeMathInt.mul(intermediate,ONE),pow);
        int256 denominator = SafeMathInt.sub(ONE,intermediate); // (1-(Upper/Lower)/2^(Growth*delta)))

        int256 rebasePercentage = (SafeMathInt.div(SafeMathInt.mul(numerator,ONE),denominator)) + lower;
        return rebasePercentage;
    }

    /**
     * @return Computes the total supply adjustment in response to the exchange rate
     *         and the targetRate.
     */
    function computeSupplyDelta(uint256 rate, uint256 targetRate) internal view returns (int256) {
        if (withinDeviationThreshold(rate, targetRate)) {
            return 0;
        }
        int256 targetRateSigned = int256(targetRate);
        int256 normalizedRate = SafeMathInt.div(SafeMathInt.mul(int256(rate),ONE),targetRateSigned);
        int256 rebasePercentage = computeRebasePercentage(
            normalizedRate,
            rebaseFunctionLowerPercentage,
            rebaseFunctionUpperPercentage,
            rebaseFunctionGrowth
        );

        return SafeMathInt.div(SafeMathInt.mul(int256(cmmd.totalSupply()),rebasePercentage),(ONE));
    }

    /**
     * @param rate The current exchange rate, an 18 decimal fixed point number.
     * @param targetRate The target exchange rate, an 18 decimal fixed point number.
     * @return If the rate is within the deviation threshold from the target rate, returns true.
     *         Otherwise, returns false.
     */
    function withinDeviationThreshold(uint256 rate, uint256 targetRate)
        internal
        view
        returns (bool)
    {
        uint256 absoluteDeviationThreshold = SafeMath.div(SafeMath.mul(targetRate,deviationThreshold),10**DECIMALS);  

        return
            (rate >= targetRate && SafeMath.sub(rate,targetRate) < absoluteDeviationThreshold) ||
            (rate < targetRate && SafeMath.sub(targetRate,rate) < absoluteDeviationThreshold);
    }

}
