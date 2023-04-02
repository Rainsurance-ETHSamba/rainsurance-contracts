// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

import "hardhat/console.sol";

contract RainInsurance is ChainlinkClient, ConfirmedOwner {

    using Chainlink for Chainlink.Request;

    struct Policy {
        uint256 startDate;
        uint256 endDate;
        string lat;
        string long;
        uint256 precipitation;
        uint256 insuredAmount;
        uint256 premiumAmount;
        uint256 policyId;
    }
    
    IERC20 public usdcToken;
    uint256 private counter;
    mapping(uint256 /* policyId */=> address) public policyHolders;
    mapping(uint256 /* policyId */ => Policy) public policies;
    mapping(address => Policy[]) public addressPolicies;
    mapping(address => uint256) public addressPoliciesCount;
    mapping(bytes32 => uint256) public claims;

    // ChainlinkConsumer
    bytes32 private jobId;
    uint256 private fee;

    event RequestResult(bytes32 indexed requestId, bool result);

    event PolicyCreated(
        uint256 policyId,
        address policyHolder,
        uint256 premiumAmount,
        uint256 insuredAmount
    );

    event ClaimCreated(
        uint256 policyId,
        address policyHolder,
        uint256 insuredAmount
    );

    event ClaimProcessed(
        uint256 indexed policyId,
        address indexed policyHolder,
        uint256 insuredAmount,
        string reason
    );

    constructor(address token) ConfirmedOwner(msg.sender) {
        usdcToken = IERC20(token);

        setChainlinkToken(0x326C977E6efc84E512bB9C30f76E30c160eD06FB);
        setChainlinkOracle(0x40193c8518BB267228Fc409a613bDbD8eC5a97b3);
        jobId = "c1c5e92880894eb6b27d3cae19670aa3";
        fee = (1 * LINK_DIVISIBILITY) / 10; // 0,1 * 10**18 (Varies by network and job)
    }

    /**
     * Create a Chainlink request to retrieve API response, 
     * and find the target data
     */
    function requestData(
            string memory lat,
            string memory long,
            uint256 startdate,
            uint256 enddate,
            uint256 precipitation
    ) public returns (bytes32 requestId) {
        Chainlink.Request memory req = buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfill.selector
        );

        string memory requestUrl = string(abi.encodePacked(
            "https://rainsurance.org/api/weather?startdate=",
            Strings.toString(startdate),
            "&enddate=",
            Strings.toString(enddate),
            "&lat=",
            lat,
            "&long=",
            long,
            "&precipitation=",
            Strings.toString(precipitation)
        ));

        console.log("requestUrl: %s", requestUrl);

        req.add(
            "get",
            requestUrl
        );

        // Sends the request
        return sendChainlinkRequest(req, fee);
    }

    /**
     * Receive the response in the form of uint256
     */
    function fulfill(
        bytes32 _requestId,
        bool _result
    ) public recordChainlinkFulfillment(_requestId) {
        emit RequestResult(_requestId, _result);
        
        Policy memory policy = policies[claims[_requestId]];
        address policyHolder = policyHolders[policy.policyId];

        string memory status = "";

        if(_result) {
            bool success = usdcToken.transfer(policyHolder, policy.insuredAmount);
            require(success, "Claim payment failed");

            _expirePolicy(policy.policyId);

            status = "approved";

        } else {
            status = "rejected";
        }

        emit ClaimProcessed(
            policy.policyId,
            policyHolder,
            policy.insuredAmount,
            status
        );
    }

    /**
     * Allow withdraw of Link tokens from the contract
     */
    function withdrawLink() public onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(
            link.transfer(msg.sender, link.balanceOf(address(this))),
            "Unable to transfer"
        );
    }

    function applyForPolicy(Policy memory policy) public payable {
        require(policy.premiumAmount > 0, "Premium amount must be greater than 0");
        require(policy.insuredAmount > 0, "Insured amount must be greater than 0");
        
        bool success = usdcToken.transferFrom(msg.sender, address(this), policy.premiumAmount);
        require(success, "Premium collection failed");

        counter += 1;
        policyHolders[counter] = msg.sender;
        policies[counter] = policy;
        policies[counter].policyId = counter;

        addressPolicies[msg.sender].push(policies[counter]);
        addressPoliciesCount[msg.sender] += 1;

        emit PolicyCreated(
            counter,
            msg.sender,
            policy.premiumAmount,
            policy.insuredAmount
        );
    }

    function fireClaim(uint256 policyId) public {
        Policy memory policy = policies[policyId];
        require(policy.insuredAmount > 0, "Must have a policy");

        emit ClaimCreated(
            policyId,
            msg.sender,
            policy.insuredAmount
        );

        bytes32 requestId = requestData(policy.lat, policy.long, policy.startDate, policy.endDate, policy.precipitation);

        claims[requestId] = policy.policyId;
    }

    function expirePolicy(uint256 policyId) public onlyOwner {
        _expirePolicy(policyId);
    }

    function _expirePolicy(uint256 policyId) private {
        address policyHolder = policyHolders[policyId];
        delete policies[policyId];
        delete policyHolders[policyId];

        delete addressPolicies[policyHolder];
        addressPoliciesCount[policyHolder] -= 1;
    }

    function getPolicy(uint256 policyId) public view returns (Policy memory) {
        return policies[policyId];
    }

    function getRiskPoolBalance() public view returns (uint256) {
        return usdcToken.balanceOf(address(this));
    }

    function getAllPolicies(address user) public view returns (Policy[] memory ret){
        uint256 count = addressPoliciesCount[user];
        ret = new Policy[](count);
        for (uint i = 0; i < count; i++) {
            if(addressPolicies[user][i].policyId > 0) {
                ret[i] = addressPolicies[user][i];
            } 
        }
        return ret;
    }

    function getAllPolicyIds(address user) public view returns (uint256[] memory ret){
        uint256 count = addressPoliciesCount[user];
        ret = new uint256[](count);
        for (uint i = 0; i < count; i++) {
            if(addressPolicies[user][i].policyId > 0) {
                ret[i] = addressPolicies[user][i].policyId;
            } 
        }
        return ret;
    }

}