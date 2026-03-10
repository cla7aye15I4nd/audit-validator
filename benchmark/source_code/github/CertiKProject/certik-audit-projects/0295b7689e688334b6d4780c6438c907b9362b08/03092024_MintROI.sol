// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

enum ROIType {
    ATM, // active reward
    STM, // passive reward
    ACCUMALATOR, // queue games reward
    DIRECT // instant mint
}    

interface IXFAN {
    function mintXFAN(address sender, uint256 amount, ROIType roiType) external;
}

contract MintROI is Pausable, Ownable, ReentrancyGuard {

    IXFAN private XFAN;
    
    struct Capital {
        uint256 capitalId;
        uint256 amount;
        uint256 claimedAmount;        
        uint256 startTime;
        uint256 lastClaimTime;
        uint256 claimROI;
        uint256 maxClaimCount;
        uint256 claimCount; 
        ROIType roiType;
    }

    struct CapitalUnclaimed {
        uint256 capitalId;
        uint256 amount;
        uint256 claimedAmount;        
        uint256 startTime;
        uint256 lastClaimTime;
        uint256 claimROI;
        uint256 maxClaimCount;
        uint256 claimCount; 
        ROIType roiType;
        uint256 pendingClaimAmount;
        uint256 pendingClaimCount;
    }

    struct User {
        Capital[] capitals;
        mapping(ROIType => uint256) accumulatedROI; // store diffrent type roi total claimed
        bool isMinting;
    }
    
    mapping(address => User) private users;
    uint256 private constant releaseInterval = 1 minutes;
    uint256 private capitalCounter; // unique capitalId
    uint256 private _atmBalance = 0;
    uint256 private _stmBalance = 0;
    address private _mainContract;

    event CapitalAdded(address indexed user, uint256 capitalId, uint256 amount, uint256 startTime, ROIType roiType);
    event CapitalRemoved(address indexed user, uint256 capitalId);
    event DividendClaimed(address indexed user, uint256 amount);
    event LogEventMessage(string message, address requestor);    
    event LogEventMessageV1(string message, uint256 balance, uint256 amount);
    event LogCalculateUnclaimedROI(uint256 claimAmount, bool isClaimedCompleted);

    constructor() Ownable(msg.sender){
        capitalCounter = 0;
    }  

    function updateMainContract(address _contract) external onlyOwner{
        XFAN = IXFAN(_contract); // XFAN contract
        _mainContract = _contract;
    }

    function getMainContract() external view returns (address){
        return _mainContract;
    }        

    function addCapital(
        address _to, 
        uint256 _amount, 
        uint256 _maxClaimCount, 
        uint256 _roi, 
        ROIType _roiType
    ) public whenNotPaused {
        require(msg.sender == _mainContract || msg.sender == owner(), "access denied");
        require(_to != address(0), "Invalid address"); // Check for zero address
        require(_amount > 0, "Amount must be greater than zero");
        require(_maxClaimCount > 0, "Max claim count must be greater than zero");
        require(_roi <= 10000, "ROI must be within a valid range"); // decline over 100%

        uint256 ts = block.timestamp;
        User storage user = users[_to];
        
        capitalCounter++;
        user.capitals.push(Capital({
            capitalId: capitalCounter,
            amount: _amount,
            claimedAmount: 0,
            startTime: ts,
            lastClaimTime: ts,
            claimROI: _roi, // Store as 250 which is equivalent to 2.5%, release it every interval
            maxClaimCount: _maxClaimCount, // max release count, example 50 minutes = 50
            claimCount: 0,
            roiType: _roiType
        }));
        
        if (_roiType == ROIType.ATM) { 
            _atmBalance += _amount; 
        }else if (_roiType == ROIType.STM) { 
            _stmBalance += _amount; 
        }

        emit CapitalAdded(_to, capitalCounter, _amount, ts, _roiType);
    }

    function batchAddCapital(
        address[] calldata _to, 
        uint256[] calldata _amounts, 
        uint256[] calldata _maxClaimCounts, 
        uint256[] calldata _rois, 
        ROIType[] calldata _roiTypes
    ) public onlyOwner {
        require(_to.length == _amounts.length && _to.length == _maxClaimCounts.length 
            && _to.length == _rois.length && _to.length == _roiTypes.length, 
            "Input arrays length mismatch");

        for (uint256 i = 0; i < _to.length; i++) {         
            addCapital(_to[i], _amounts[i], _maxClaimCounts[i], _rois[i], _roiTypes[i]);
        }
    }

    function calculateUnclaimedROI(address userAddress, ROIType _roiType) internal returns (uint256 unclaimed, bool isClaimFinish) {
        User storage user = users[userAddress];
        uint256 totalUnclaimed = 0;
        bool isClaimedCompleted = false;

        for (uint256 i = 0; i < user.capitals.length; i++) {
            Capital storage capital = user.capitals[i];
            if (capital.roiType == _roiType) {
                uint256 timeElapsed = block.timestamp - capital.lastClaimTime;
                uint256 intervalsElapsed = timeElapsed / releaseInterval;
                uint256 remainingClaims = capital.maxClaimCount - capital.claimCount;
                if (intervalsElapsed >= remainingClaims) {
                    intervalsElapsed = remainingClaims;
                }
                capital.claimCount += intervalsElapsed;

                uint256 unclaimedROI = (((capital.amount * capital.claimROI) / 10000 ) * intervalsElapsed);

                if (capital.claimCount >= capital.maxClaimCount){
                    unclaimedROI = capital.amount - capital.claimedAmount;
                    isClaimedCompleted = true;
                }                  
                
                capital.lastClaimTime += intervalsElapsed * releaseInterval;
                capital.claimedAmount += unclaimedROI;
                totalUnclaimed += unclaimedROI;
            }
        }
        return (totalUnclaimed, isClaimedCompleted);
    }

    function getPendingCapitals(address userAddress, ROIType _roiType) public view returns (CapitalUnclaimed[] memory) {
        User storage user = users[userAddress];
        CapitalUnclaimed[] memory maturedCapitals = new CapitalUnclaimed[](user.capitals.length);
    
        for (uint256 i = 0; i < user.capitals.length; i++) {
            Capital storage capital = user.capitals[i];
            if (capital.roiType == _roiType) {           
                uint256 timeElapsed = block.timestamp - capital.lastClaimTime;
                uint256 intervalsElapsed = timeElapsed / releaseInterval;
                uint256 remainingClaims = capital.maxClaimCount - capital.claimCount;

                if (intervalsElapsed >= remainingClaims) {
                    intervalsElapsed = remainingClaims;
                }            

                uint256 unclaimedROI = (((capital.amount * capital.claimROI) / 10000 ) * intervalsElapsed);
                if (capital.claimCount + intervalsElapsed >= capital.maxClaimCount){
                    unclaimedROI = capital.amount - capital.claimedAmount;
                }

                maturedCapitals[i] = CapitalUnclaimed({
                    capitalId: capital.capitalId,
                    amount: capital.amount,
                    claimedAmount: capital.claimedAmount,
                    startTime: capital.startTime,
                    lastClaimTime: capital.lastClaimTime,
                    claimROI: capital.claimROI,
                    maxClaimCount: capital.maxClaimCount,
                    claimCount: capital.claimCount,
                    roiType: capital.roiType,
                    pendingClaimAmount: unclaimedROI,
                    pendingClaimCount: intervalsElapsed
                });
            }
        }
        return maturedCapitals;
    }

    function _countROI(address userAddress, ROIType _roiType) public view returns (uint256) {
        uint256 roiCount = 0;
        User storage user = users[userAddress];
        for (uint256 i = 0; i < user.capitals.length; i++) {
            if (user.capitals[i].roiType == _roiType) {
                roiCount++;
            }
        }
        return roiCount;
    }    

    function calculateBalanceROI(address userAddress, ROIType _roiType) external view returns (uint256) {
        User storage user = users[userAddress];
        uint256 totalUnclaimedROI = 0;

        for (uint256 i = 0; i < user.capitals.length; i++) {
            Capital storage capital = user.capitals[i];

            if (capital.roiType == _roiType){
                uint256 unclaimedROI = capital.amount - capital.claimedAmount;
                totalUnclaimedROI += unclaimedROI;
            }
        }
        return totalUnclaimedROI;
    }

    function claimDividend(ROIType _roiType) public whenNotPaused nonReentrant {
        User storage user = users[msg.sender];
        require(user.capitals.length > 0, "No minting record found");
        require(!user.isMinting, "mint in progress");

        user.isMinting = true;
        (uint256 unclaimed, bool isClaimEnd) = calculateUnclaimedROI(msg.sender, _roiType);

        emit LogCalculateUnclaimedROI(unclaimed, isClaimEnd);

        if (unclaimed > 0)
        {            
            user.accumulatedROI[_roiType] += unclaimed; // update total claimed roi with type

            if (isClaimEnd){
                removeCapital(0);
            }

            if (_roiType == ROIType.ATM){
                 if (_atmBalance >= unclaimed){
                    _atmBalance -= unclaimed;
                 }
            }else if (_roiType == ROIType.STM){
                if (_stmBalance >= unclaimed){
                    _stmBalance -= unclaimed;
                }
            }
            XFAN.mintXFAN(msg.sender, unclaimed, _roiType);
        }
        emit DividendClaimed(msg.sender, unclaimed);
        user.isMinting = false;
    }

    function removeCapital(uint256 deleteId) private {
        User storage user = users[msg.sender];
        require(user.capitals.length > 0, "No minting record found");

        for (uint256 i = user.capitals.length; i > 0; i--) { //Traverse the array from the back to the front to prevent index out of bounds when deleting elements.
             uint256 index = i - 1;
             uint256 _capitalId = user.capitals[index].capitalId;
             
            if (user.capitals[index].claimCount >= user.capitals[index].maxClaimCount || _capitalId == deleteId) { // Replace the current element with the last element of the array, and then delete the last element.
                if (index != user.capitals.length - 1) {
                    user.capitals[index] = user.capitals[user.capitals.length - 1];
                }else{
                }
                user.capitals.pop();
                emit CapitalRemoved(msg.sender, _capitalId);
                if (user.capitals.length == 0 || _capitalId == deleteId){
                    break;
                }
            }
        }
    }

    function getUserInfo(address user) public view returns (Capital[] memory, uint256, uint256, uint256) {
        User storage u = users[user];
        uint256 accumulatedATM = u.accumulatedROI[ROIType.ATM];
        uint256 accumulatedSTM = u.accumulatedROI[ROIType.STM];
        uint256 accumulatedACCUMALATOR = u.accumulatedROI[ROIType.ACCUMALATOR];
        return (u.capitals, accumulatedATM, accumulatedSTM, accumulatedACCUMALATOR);
    }

    function getTotalUnclaimedROI(ROIType _roiType) public view returns (uint256){
        if (_roiType == ROIType.ATM){
            return _atmBalance;
        }else if (_roiType == ROIType.STM){
            return _stmBalance;
        }
        return 0;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}