pragma solidity ^0.4.24;

import "./SafeMath.sol";
import "./SafeNetToken.sol";

contract Treaties {
    using SafeMath for uint;

    SafeNetToken public token; 

    address public creator;
    bool public creatorInited = false;

    address public wallet;

    uint public walletPercentage = 100;

    address[] public owners;
    address[] public teams;
    address[] public investors;

    mapping (address => bool) public inList;

    uint public tokensInUse = 0;

    mapping (address => uint) public refunds;

    struct Request {
        uint8 id;
        uint8 rType; // 0 - owner, 1 - team, 2 - investor(eth), 3 - investor(fiat), 4 - new percentage
        address beneficiary;
        string treatyHash;
        uint tokensAmount;
        uint ethAmount;
        uint percentage;

        uint8 isConfirmed; // 0 - pending, 1 - declined, 2 - accepted
        address[] ownersConfirm;
    }

    uint8 public requestsCount = 0;
    Request[] public requests;

    modifier onlyOwner() {
        for (uint i = 0; i < owners.length; i++) {
            if (owners[i] == msg.sender) {
                _;
            }
        }
    }   

    event NewRequest(uint8 rType, address beneficiary, string treatyHash, uint tokensAmount, uint ethAmount, uint percentage, uint id);
    event RequestConfirmed(uint id);
    event RequestDeclined(uint id);
    event RefundsCalculated();

    constructor(address _wallet, SafeNetToken _token) public {
        creator = msg.sender;
        token = _token;
        wallet = _wallet;
    }

    function() external payable {
        splitProfit(msg.value);
    }

    // after mint
    function initCreator(uint _tokensAmount) public {
        assert(msg.sender == creator && !creatorInited);

        owners.push(creator);
        assert(token.transfer(creator, _tokensAmount));
        tokensInUse += _tokensAmount;
        inList[creator] = true;
        creatorInited = true;
    }


    function createTreatyRequest(uint8 _rType, string _treatyHash, uint _tokensAmount) public {
        require(_rType <= 1);

        requests.push(Request({
            id: requestsCount,
            rType: _rType,
            beneficiary: msg.sender,
            treatyHash: _treatyHash,
            tokensAmount: _tokensAmount,
            ethAmount: 0,
            percentage: 0,
            isConfirmed: 0,
            ownersConfirm: new address[](0)
            }));
        requestsCount++;

        emit NewRequest(_rType, msg.sender, _treatyHash, _tokensAmount, 0, 0, requests.length - 1);
    }

    function createEthInvestorRequest(uint _tokensAmount) public payable {
        assert(msg.value > 0);

        requests.push(Request({
            rType: 2,
            id: requestsCount,
            beneficiary: msg.sender,
            treatyHash: '',
            tokensAmount: _tokensAmount,
            ethAmount: msg.value,
            percentage: 0,
            isConfirmed: 0,
            ownersConfirm: new address[](0)
            }));
        requestsCount++;

        emit NewRequest(2, msg.sender, "", _tokensAmount, msg.value, 0, requests.length - 1);
    }

    function removeEthInvestorRequest(uint id) public {
        require(id < requests.length);
        assert(requests[id].isConfirmed == 0 && requests[id].rType == 2);
        assert(requests[id].beneficiary == msg.sender);

        requests[id].isConfirmed = 1;
        assert(msg.sender.send(requests[id].ethAmount));
        emit RequestDeclined(id);
    }

    function createFiatInvestorRequest(uint _tokensAmount) public {
        requests.push(Request({
            rType: 3,
            id: requestsCount,
            beneficiary: msg.sender,
            treatyHash: '',
            tokensAmount: _tokensAmount,
            ethAmount: 0,
            percentage: 0,
            isConfirmed: 0,
            ownersConfirm: new address[](0)
            }));
        requestsCount++;

        emit NewRequest(3, msg.sender, "", _tokensAmount, 0, 0, requests.length - 1);
    }

    function createPercentageRequest(uint _percentage) public onlyOwner {
        require(_percentage <= 100);

        requests.push(Request({
            rType: 4,
            id: requestsCount,
            beneficiary: msg.sender,
            treatyHash: '',
            tokensAmount: 0,
            ethAmount: 0,
            percentage: _percentage,
            isConfirmed: 0,
            ownersConfirm: new address[](0)
            }));
        requestsCount++;

        emit NewRequest(4, msg.sender, "", 0, 0, _percentage, requests.length - 1);
    }


    function confirmRequest(uint id) public onlyOwner {
        require(id < requests.length);
        assert(requests[id].isConfirmed == 0);

        uint tokensConfirmed = 0;
        for (uint i = 0; i < requests[id].ownersConfirm.length; i++) {
            assert(requests[id].ownersConfirm[i] != msg.sender);
            tokensConfirmed += token.balanceOf(requests[id].ownersConfirm[i]);
        }

        requests[id].ownersConfirm.push(msg.sender);
        tokensConfirmed += token.balanceOf(msg.sender);

        uint tokensInOwners = 0;
        for (i = 0; i < owners.length; i++) {
            tokensInOwners += token.balanceOf(owners[i]);
        }

        if (tokensConfirmed > tokensInOwners / 2) {
            if (requests[id].rType == 4) {
                walletPercentage = requests[id].percentage;

            } else {
                if (!inList[requests[id].beneficiary]) {
                    if (requests[id].rType == 0) {
                        owners.push(requests[id].beneficiary);
                        token.transfer(creator, requests[id].tokensAmount / 10);
                    }
                    if (requests[id].rType == 1) {
                        teams.push(requests[id].beneficiary);
                    }
                    if (requests[id].rType == 2 || requests[id].rType == 3) {
                        investors.push(requests[id].beneficiary);
                    }
                    inList[requests[id].beneficiary] = true;
                }

                if (requests[id].rType == 2) {
                    assert(wallet.send(requests[id].ethAmount));
                }

                token.transfer(requests[id].beneficiary, requests[id].tokensAmount);
                tokensInUse += requests[id].tokensAmount;
            }

            requests[id].isConfirmed = 2;
            emit RequestConfirmed(id);
        }
    }

    function rejectRequest(uint id) public onlyOwner {
        require(id < requests.length);
        assert(requests[id].isConfirmed == 0);

        for (uint i = 0; i < requests[id].ownersConfirm.length; i++) {
            if (requests[id].ownersConfirm[i] == msg.sender) {
                requests[id].ownersConfirm[i] = requests[id].ownersConfirm[requests[id].ownersConfirm.length - 1];
                requests[id].ownersConfirm.length--;
                break;
            }
        }
    }


    function splitProfit(uint profit) internal {
        uint rest = profit;
        uint refund;
        address addr;
        for (uint i = 0; i < owners.length; i++) {
            addr = owners[i];
            refund = profit.mul(token.balanceOf(addr)).mul(100 - walletPercentage).div(100).div(tokensInUse);
            refunds[addr] += refund;
            rest -= refund;
        }
        for (i = 0; i < teams.length; i++) {
            addr = teams[i];
            refund = profit.mul(token.balanceOf(addr)).mul(100 - walletPercentage).div(100).div(tokensInUse);
            refunds[addr] += refund;
            rest -= refund;
        }
        for (i = 0; i < investors.length; i++) {
            addr = investors[i];
            refund = profit.mul(token.balanceOf(addr)).mul(100 - walletPercentage).div(100).div(tokensInUse);
            refunds[addr] += refund;
            rest -= refund;
        }

        assert(wallet.send(rest));
        emit RefundsCalculated();
    }

    function withdrawRefunds() public {
        assert(refunds[msg.sender] > 0);
        uint refund = refunds[msg.sender];
        refunds[msg.sender] = 0;
        assert(msg.sender.send(refund));
    }

    function getRequestConfirmation(uint id) public view returns (uint tokensConfirmed, uint tokensInOwners) {
        tokensConfirmed = 0;
        for (uint i = 0; i < requests[id].ownersConfirm.length; i++) {
            assert(requests[id].ownersConfirm[i] != msg.sender);
            tokensConfirmed += token.balanceOf(requests[id].ownersConfirm[i]);
        }

        tokensInOwners = 0;
        for (i = 0; i < owners.length; i++) {
            tokensInOwners += token.balanceOf(owners[i]);
        }
    }

    function checkRequestConfirmedBy(uint id, address _addr) public view returns (bool) {
        for (uint i = 0; i < requests[id].ownersConfirm.length; i++) {
            if (_addr == requests[id].ownersConfirm[i]) {
                return true;
            }
        }
        return false;
    }

    function getGroup(address _addr) public view returns (uint) {
        for (uint i = 0; i < owners.length; i++) {
            if (_addr == owners[i]) {
                return 1;
            }
        }
        for (i = 0; i < teams.length; i++) {
            if (_addr == teams[i]) {
                return 2;
            }
        }
        for (i = 0; i < investors.length; i++) {
            if (_addr == investors[i]) {
                return 3;
            }
        }
        return 0;
    }
}
