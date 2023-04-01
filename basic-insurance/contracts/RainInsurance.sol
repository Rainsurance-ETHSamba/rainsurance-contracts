// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RainInsurance {

    struct Policy {
        uint256 startDate;
        uint256 endDate;
        string lat;
        string long;
        uint256 precipitation;
        uint256 insuredAmount;
        uint256 premiumAmount;
    }
    
    IERC20 public usdcToken;
    uint256 private counter;
    mapping(uint256 /* policyId */=> address) public policyHolders;
    mapping(uint256 /* policyId */ => Policy) public policies;
    mapping(address => uint256) public claims;
    address payable owner;

    constructor(address token) {
        usdcToken = IERC20(token);
        owner = payable(msg.sender);
    }

    function applyForPolicy(Policy memory policy) public payable {
        require(policy.premiumAmount > 0, "Premium amount must be greater than 0");
        require(policy.insuredAmount > 0, "Insured amount must be greater than 0");
        
        bool success = usdcToken.transferFrom(msg.sender, address(this), policy.premiumAmount);
        require(success, "Premium collection failed");

        counter += 1;
        policyHolders[counter] = msg.sender;
        policies[counter] = policy;
    }

    function handleClaim(uint256 policyId) public {
        require(policies[policyId].insuredAmount > 0, "Must have a policy");
        claims[msg.sender] += policies[policyId].insuredAmount;
    }

    function aproveClaim(uint256 policyId) public {
        address policyHolder = policyHolders[policyId];
        require(msg.sender == owner, "Only owner can aprove claims");
        require(claims[policyHolder] > 0, "Policy holder must have a claim");

        bool success = usdcToken.transfer(policyHolder, claims[policyHolder]);
        require(success, "Claim payment failed");

        claims[policyHolder] = 0;
        delete policies[policyId];
        delete policyHolders[policyId];
    }

    function getPolicy(uint256 policyId) public view returns (Policy memory) {
        return policies[policyId];
    }

    function getClaim(address policyHolder) public view returns (uint256) {
        return claims[policyHolder];
    }

    function getRiskPoolBalance() public view returns (uint256) {
        return usdcToken.balanceOf(address(this));
    }

}