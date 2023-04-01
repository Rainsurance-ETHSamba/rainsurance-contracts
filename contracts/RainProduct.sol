// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.2;

import "@etherisc/gif-interface/contracts/components/Product.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract RainProduct is Product {
    // constants
    bytes32 public constant NAME = "RainProduct";
    bytes32 public constant VERSION = "0.0.1";
    bytes32 public constant POLICY_FLOW = "PolicyDefaultFlow";

    uint256 public constant MULTIPLIER = 10 ** 6; // in cent = multiplier is 10 ** 16
    uint256 public constant MAX_PAYOUT = 5000  * MULTIPLIER;
    uint256 public constant MIN_PAYOUT = 20 * MULTIPLIER;
    uint256 public constant MAX_TOTAL_PAYOUT = 3 * MAX_PAYOUT; // Maximum risk per flight is 3x max payout.

    uint256 public constant MIN_TIME_BEFORE_DEPARTURE = 14 * 24 hours;
    uint256 public constant MAX_TIME_BEFORE_DEPARTURE = 90 * 24 hours;

    string public constant CALLBACK_METHOD_NAME = "oracleCallback";

    struct Risk {
        bytes32 id; // hash over city, start, end
        uint256 startDate;
        uint256 endDate;
        string city;
        string lat;
        string long;
        uint precipitation;
        uint256 estimatedMaxTotalPayout;
        uint256 createdAt;
        uint256 updatedAt;
    }

    struct ApplicationInfo {
        uint256 startDate;
        uint256 endDate;
        string city;
        string lat;
        string long;
        uint precipitation;
        uint256 insuredAmount;
        uint256 premiumAmount;
    }

    // variables
    bytes32 [] private _riskIds;
    mapping(bytes32 /* riskId */ => Risk) private _risks;
    mapping(bytes32 /* riskId */ => EnumerableSet.Bytes32Set /* processIds */) private _policies;
    bytes32[] private _applications;

    uint256 public _oracleId;

    mapping(string => bool) public activePolicy; // TODO: remove

    // events
    event LogRainPolicyCreated(
        bytes32 processId,
        address policyHolder,
        uint256 premiumAmount,
        uint256 insuredAmount
    );
    event LogRainPolicyExpired(string objectName, bytes32 processId);
    event LogRainOracleCallbackReceived(
        uint256 requestId,
        bytes32 processId,
        bytes fireCategory
    );
    event LogRainClaimConfirmed(
        bytes32 processId,
        uint256 claimId,
        uint256 payoutAmount
    );
    event LogRainPayoutExecuted(
        bytes32 processId,
        uint256 claimId,
        uint256 payoutId,
        uint256 payoutAmount
    );

    constructor(
        bytes32 productName,
        address token,
        uint256 oracleId,
        uint256 riskpoolId,
        address registry
    ) Product(productName, token, POLICY_FLOW, riskpoolId, registry) {
        _oracleId = oracleId;
    }

    function decodeApplicationParameterFromData(
        bytes memory data
    ) public pure returns (string memory objectName) {
        return abi.decode(data, (string));
    }

    function encodeApplicationParametersToData(
        string memory objectName
    ) public pure returns (bytes memory data) {
        return abi.encode(objectName);
    }

    function applyForPolicy(
        string memory objectName, // TODO: remove
        uint256 objectValue, // TODO: remove
        ApplicationInfo memory _applicationInfo
    ) external returns (bytes32 processId, uint256 requestId) {

        uint256 premiumAmount = _applicationInfo.premiumAmount;
        uint256 insuredAmount = _applicationInfo.insuredAmount;

        // Validate input parameters
        require(insuredAmount >= MIN_PAYOUT, "ERROR:FDD-001:INVALID_AMOUNT");
        require(insuredAmount <= MAX_PAYOUT, "ERROR:FDD-002:INVALID_AMOUNT");
        require(_applicationInfo.endDate > _applicationInfo.startDate, "ERROR:FDD-003:ARRIVAL_BEFORE_DEPARTURE_TIME");
        // require(
        //     _applicationInfo.startDate >= block.timestamp + MIN_TIME_BEFORE_DEPARTURE,
        //     "ERROR:FDD-012:INVALID_ARRIVAL/DEPARTURE_TIME"
        // );
        // require(
        //     _applicationInfo.startDate <= block.timestamp + MAX_TIME_BEFORE_DEPARTURE,
        //     "ERROR:FDD-005:INVALID_ARRIVAL/DEPARTURE_TIME"
        // );

        require(!activePolicy[objectName], "ERROR:FI-011:ACTIVE_POLICY_EXISTS"); //TODO: remove

        // Create risk if not exists
        bytes32 riskId = keccak256(abi.encode(_applicationInfo.city, _applicationInfo.startDate, _applicationInfo.endDate));
        Risk storage risk = _risks[riskId];

        if(risk.createdAt == 0) {
            risk.id = riskId;
            risk.city = _applicationInfo.city;
            risk.startDate = _applicationInfo.startDate;
            risk.endDate = _applicationInfo.endDate;
            risk.lat = _applicationInfo.lat;
            risk.long = _applicationInfo.long;
            risk.precipitation = _applicationInfo.precipitation;
            risk.createdAt = block.timestamp;
            _riskIds.push(riskId);
        }

        // If this is the first policy for this risk,
        // we "block" this risk by setting risk.estimatedMaxTotalPayout to the maximum.
        // Next application for this risk can only be insured after this one has been underwritten.
        if (risk.estimatedMaxTotalPayout == 0) {
            risk.estimatedMaxTotalPayout = MAX_TOTAL_PAYOUT;
        }

        // Create and underwrite new application
        address policyHolder = msg.sender;
        bytes memory metaData = "";
        bytes memory applicationData = abi.encode(riskId);

        processId = _newApplication(
            policyHolder,
            premiumAmount,
            insuredAmount,
            metaData,
            applicationData
        );

        _applications.push(processId);

        bool success = _underwrite(processId);

        if (success) {
            // Update activ state for object
            activePolicy[objectName] = true; // TODO: remove this code

            EnumerableSet.add(_policies[riskId], processId);

            emit LogRainPolicyCreated(
                processId,
                policyHolder,
                premiumAmount,
                insuredAmount
            );

            // bytes memory queryData = abi.encode(
            //     risk.startDate,
            //     risk.endDate,
            //     risk.lat,
            //     risk.long
            // );

            bytes memory queryData = abi.encode(objectName);

            // trigger rain observation for object id via oracle call
            requestId = _request(
                processId,
                queryData,
                CALLBACK_METHOD_NAME,
                _oracleId
            );

            // EnumerableSet.add(_policies[riskId], processId);

        }

    }

    function expirePolicy(bytes32 processId) external onlyOwner {
        // Get policy data
        IPolicy.Application memory application = _getApplication(processId);
        string memory objectName = decodeApplicationParameterFromData(
            application.data
        );

        // Validate input parameter
        require(activePolicy[objectName], "ERROR:FI-005:EXPIRED_POLICY");

        _expire(processId);
        activePolicy[objectName] = false;

        emit LogRainPolicyExpired(objectName, processId);
    }

    function oracleCallback(
        uint256 requestId,
        bytes32 policyId,
        bytes calldata response
    ) external onlyOracle {
        emit LogRainOracleCallbackReceived(requestId, policyId, response);

        // Get policy data for oracle response
        /*
struct Application {
        ApplicationState state;
        uint256 premiumAmount;
        uint256 sumInsuredAmount;
        bytes data; 
        uint256 createdAt;
        uint256 updatedAt;
    }
*/

        IPolicy.Application memory applicationData = _getApplication(policyId);
        uint256 premium = applicationData.premiumAmount;
        string memory objectName = decodeApplicationParameterFromData(
            applicationData.data
        );
        address payable policyHolder = payable(_getMetadata(policyId).owner);

        // Validate input parameter
        require(activePolicy[objectName], "ERROR:FI-006:EXPIRED_POLICY");

        // Get oracle response data
        bytes1 fireCategory = abi.decode(response, (bytes1));

        // Claim handling based on reponse to greeting provided by oracle
        _handleClaim(policyId, policyHolder, premium, fireCategory);
    }

    function getOracleId() external view returns (uint256 oracleId) {
        return _oracleId;
    }

    function risks() external view returns(uint256) { return _riskIds.length; }
    function getRiskId(uint256 idx) external view returns(bytes32 riskId) { return _riskIds[idx]; }
    function getRisk(bytes32 riskId) external view returns(Risk memory risk) { return _risks[riskId]; }

    function applications() external view returns(uint256 applicationCount) {
        return _applications.length;
    }
    function getApplicationId(uint256 applicationIdx) external view returns(bytes32 processId) {
        return _applications[applicationIdx];
    }

    function policies(bytes32 riskId) external view returns(uint256 policyCount) {
        return EnumerableSet.length(_policies[riskId]);
    }
    function getPolicyId(bytes32 riskId, uint256 policyIdx) external view returns(bytes32 processId) {
        return EnumerableSet.at(_policies[riskId], policyIdx);
    }

    function _handleClaim(
        bytes32 policyId,
        address payable policyHolder,
        uint256 premium,
        bytes1 fireCategory
    ) internal {
        uint256 payoutAmount = _calculatePayoutAmount(premium, fireCategory);

        // no claims handling for payouts == 0
        if (payoutAmount > 0) {
            uint256 claimId = _newClaim(policyId, payoutAmount, "");
            _confirmClaim(policyId, claimId, payoutAmount);

            emit LogRainClaimConfirmed(policyId, claimId, payoutAmount);

            uint256 payoutId = _newPayout(policyId, claimId, payoutAmount, "");
            _processPayout(policyId, payoutId);

            emit LogRainPayoutExecuted(
                policyId,
                claimId,
                payoutId,
                payoutAmount
            );
        }
    }

    function _calculatePayoutAmount(
        uint256 premium,
        bytes1 fireCategory
    ) internal pure returns (uint256 payoutAmount) {
        if (fireCategory == "M") {
            payoutAmount = 5 * premium;
        } else if (fireCategory == "L") {
            payoutAmount = 100 * premium;
        } else {
            // small fires considered below deductible, no payout
            payoutAmount = 0;
        }
    }
}
