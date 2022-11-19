// SPDX-License-Identifier: GPL-3.0-or-later
//0xb31fFa2e5d501F9f606Ff4A5F3E5E281394f7C60 - CPI
//0xAbDcbD8bf2f8084eE388Eabf7c4ce6cf6D658F6B - Market
pragma solidity 0.8.7;

interface IOracle {
    function getData() external view returns (uint256, bool);
    function pushReport(uint256) external;
}

/**
 *
 * @notice Provides a value onchain that's aggregated from a whitelisted set of
 *         providers.
 */
contract Oracle is IOracle {
    struct Report {
        uint256 timestamp;
        uint256 payload;
    }

    // Addresses of providers authorized to push reports.
    address[] public providers;

    // Reports indexed by provider address. Report[0].timestamp > 0
    // indicates provider existence.
    mapping(address => Report[2]) public providerReports;

    event ProviderAdded(address provider);
    event ProviderRemoved(address provider);
    event ProviderReportPushed(address indexed provider, uint256 payload, uint256 timestamp);
    event PrintData(uint price);

    // The minimum number of providers with valid reports to consider the
    // aggregate report valid.
    uint256 public minimumProviders = 1;

    /**
     * @notice Contract state initialization.

     * @param minimumProviders_ The minimum number of providers with valid
     *                          reports to consider the aggregate report valid.
     */
    function init(
        uint256 minimumProviders_
    ) internal {
        require(minimumProviders_ > 0);
        minimumProviders = minimumProviders_;    
    }

    /**
     * @notice Sets the minimum number of providers with valid reports to
     *         consider the aggregate report valid.
     * @param minimumProviders_ The new minimum number of providers.
     */
    function setMinimumProviders(uint256 minimumProviders_) public {
        require(minimumProviders_ > 0);
        minimumProviders = minimumProviders_;
    }

    /**
     * @notice Pushes a report for the calling provider.
     * @param payload is expected to be 18 decimal fixed point number.
     */
    function pushReport(uint256 payload) public override {
        address providerAddress = msg.sender;
        Report[2] storage reports = providerReports[providerAddress];

        reports[0].timestamp = block.timestamp;
        reports[0].payload = payload;

        reports[1].timestamp = block.timestamp;
        reports[1].payload = payload;

        emit ProviderReportPushed(providerAddress, payload, block.timestamp);
    }

    /**
     * @notice Invalidates the reports of the calling provider.
     */
    function purgeReports() public {
        address providerAddress = msg.sender;
        require(providerReports[providerAddress][0].timestamp > 0);
        providerReports[providerAddress][0].timestamp = 1;
        providerReports[providerAddress][1].timestamp = 1;
    }

    /**
     * @notice Allows me to push a report and return the data
     * @return Price for now, don't need to do any calculation
     */
    function getData() public view override returns (uint256, bool) {
        uint256 reportsCount = providers.length;
        uint256 latestReport = 0;

        for (uint256 i = 0; i < reportsCount; i++) {
            address providerAddress = providers[i];
            latestReport = providerReports[providerAddress][1].payload;
        }

        return (latestReport, true);
    }

    function printData() public {
        uint256 reportsCount = providers.length;
        uint256[] memory validReports = new uint256[](reportsCount);
        uint256 size = 0;
        uint256 latestReport = 0;
        
         for (uint256 i = 0; i < reportsCount; i++) {
            address providerAddress = providers[i];
            Report[2] memory reports = providerReports[providerAddress];
            latestReport = providerReports[providerAddress][1].payload;
        }

        emit PrintData(latestReport);
    }

    /**
     * @notice Authorizes a provider.
     * @param provider Address of the provider.
     */
    function addProvider(address provider) public {
        providers.push(provider);
        providerReports[provider][0].timestamp = 1;
        emit ProviderAdded(provider);
    }

    /**
     * @notice Revokes provider authorization.
     * @param provider Address of the provider.
     */
    function removeProvider(address provider) public {
        delete providerReports[provider];
        for (uint256 i = 0; i < providers.length; i++) {
            if (providers[i] == provider) {
                if (i + 1 != providers.length) {
                    providers[i] = providers[providers.length - 1];
                }
                providers.pop();
                emit ProviderRemoved(provider);
                break;
            }
        }
    }

    /**
     * @return The number of authorized providers.
     */
    function providersSize() public view returns (uint256) {
        return providers.length;
    }
}
