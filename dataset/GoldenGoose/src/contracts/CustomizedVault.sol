// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// Uncomment this line to use console.log
// import "hardhat/console.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./interfaces/IDataStorage.sol";
import "./LpToken.sol";

contract CustomizedVault is ReentrancyGuardUpgradeable{
    using SafeERC20 for IERC20;

    IDataStorage public dataStorage;
    LpToken public lpToken;
    address public token;      // U Token contract address
    address private custodian;
    uint256 public eventId;

    mapping(address => uint256) public balanceMap;    // user total share balance
    mapping(address => uint256) public availableShare; // user avalible share balance

    DepositLock[] private depositMap;
    RedeemLock[] private redeemMap;

    struct DepositLock{
        address account;
        uint256 share;
        uint256 createTime;
    }

    struct RedeemLock{
        address account;
        uint256 share;     // lp amount
        uint256 assetAmount;
        uint256 price;       // total USD / total shares
        uint256 createTime;
    }

    event Deposit(uint256 indexed id,address user,uint256 depositAsset,uint256 depositShare,uint256 price,uint256 lockId,uint256 lockTime,uint256 totalShares,uint256 createTime);
    event Withdraw(uint256 indexed id,address user,uint256 withdrawAsset,uint256 withdrawShare,uint256 price,uint256 totalShares,uint256 createTime);
    event Redeem(uint256 indexed id,address user,uint256 redeemAsset,uint256 redeemShare,uint256 price,uint256 lockId,uint256 lockTime,uint256 totalShares,uint256 createTime);

    event UnLockDeposit(uint256 indexed lockId,address user,uint256 share,uint256 createTime);
    event UnLockRedeem(uint256 indexed lockId,address user,uint256 share,uint256 createTime);

    event UpdateCustodian(address user,address oldCustodian,address currentCustodian);
    event UpdateDataStorage(address user,address oldStorage,address currentStorage);
    event CreateLp(address lp);

    constructor(address storageContract,address tokenContract) {
        require(storageContract != address(0) && tokenContract != address(0),"Invalid Zero Address");
        token = tokenContract;
        dataStorage = IDataStorage(storageContract);

        lpToken = new LpToken(tokenContract,strConcat('LpToken-',IERC20Metadata(tokenContract).name()),strConcat('LP-',IERC20Metadata(tokenContract).symbol()),IERC20Metadata(tokenContract).decimals());
        emit CreateLp(address(lpToken));
    }

    function deposit(address account,uint256 amount,uint256 minShare) external onlyOwner{
        _deposit(account,amount,minShare);
    }

    function _deposit(address account,uint256 amount,uint256 minShare) internal nonReentrant{
        require(amount >= dataStorage.minDepositMap(address(this)),"Deposit amount too small");

        uint256 shares = lpToken.mint(amount,minShare);

        balanceMap[account] += shares;

        emit Deposit(setEventId(),account,amount,shares,lpToken.price(),getDepositLockLength(),dataStorage.depositLockTime(),lpToken.totalSupply(),block.timestamp);

        depositMap.push(DepositLock(account,shares,block.timestamp));
    }

    function unLockDeposit(uint256[] memory ids) public{
        for(uint256 i; i<ids.length; i++){
            _unLockDeposit(ids[i]);
        }
    }

    function _unLockDeposit(uint256 id) internal nonReentrant{
        DepositLock memory depositLock= depositMap[id];
        require(depositLock.createTime + dataStorage.depositLockTime() <= block.timestamp,"Lock time not enough");
        require(depositLock.share > 0,"Already unlock");
        emit UnLockDeposit(id,depositLock.account,depositLock.share,block.timestamp);

        availableShare[depositLock.account] += depositLock.share;
        depositLock.share = 0;
        depositMap[id] = depositLock;
    }

    function withdraw(uint256[] memory ids) external {
        for(uint256 i; i<ids.length; i++){
            _withdraw(ids[i]);
        }
    }

    function _withdraw(uint256 id) internal nonReentrant{
        RedeemLock memory redeemLock = redeemMap[id];
        require(redeemLock.createTime + dataStorage.redeemLockTime() <= block.timestamp,"Lock time not enough");
        require(redeemLock.share > 0,"Already withdraw");

        IERC20(token).safeTransfer(redeemLock.account,redeemLock.assetAmount);

        emit Withdraw(setEventId(),redeemLock.account,redeemLock.assetAmount,redeemLock.share,redeemLock.price,lpToken.totalSupply(),block.timestamp);
        emit UnLockRedeem(id,redeemLock.account,redeemLock.share,block.timestamp);

        balanceMap[redeemLock.account] -= redeemLock.share;
        redeemLock.share = 0;
        redeemMap[id] = redeemLock;
    }

    function redeemAndUnLockDeposit(address account,uint256 amount,uint256 minAssetAmount,uint256[] memory ids) external onlyOwner{
        unLockDeposit(ids);
        _redeem(account,amount,minAssetAmount);
    }

    function redeem(address account,uint256 share,uint256 minAssetAmount) external onlyOwner{
        _redeem(account,share,minAssetAmount);
    }

    function _redeem(address account,uint256 share,uint256 minAssetAmount) internal nonReentrant{
        require(availableShare[account] >= share,"Available balance not enough");
        availableShare[account] -= share;

        uint256 assetAmount = lpToken.convertToAssets(share);
        require(assetAmount >= minAssetAmount,"Asset amount error");
        lpToken.burn(share,0);
        emit Redeem(setEventId(),account,assetAmount,share,lpToken.price(),getRedeemLockLength(),dataStorage.redeemLockTime(),lpToken.totalSupply(),block.timestamp);

        redeemMap.push(RedeemLock(account,assetAmount,share,lpToken.price(),block.timestamp));
    }

    function getDepositLockInfo(uint256[] memory ids) public view returns(DepositLock[] memory) {
        DepositLock[] memory list = new DepositLock[](ids.length);
        for(uint256 i; i<ids.length; i++){
            list[i] = depositMap[i];
        }
        return list;
    }

    function getDepositLockLength() public view returns(uint256) {
        return depositMap.length;
    }

    function getRedeemLockInfo(uint256[] memory ids) public view returns(RedeemLock[] memory) {
        RedeemLock[] memory list = new RedeemLock[](ids.length);
        for(uint256 i; i<ids.length; i++){
            list[i] = redeemMap[i];
        }
        return list;
    }

    function getRedeemLockLength() public view returns(uint256) {
        return redeemMap.length;
    }

    function setEventId() internal returns(uint256){
        return eventId++;
    }

    function updateDataStorageContract(address storageContract) external onlyOwner{
        require(storageContract != address(0),"Invalid Zero Address");
        emit UpdateDataStorage(msg.sender,address(dataStorage),storageContract);
        dataStorage = IDataStorage(storageContract);
    }

    function getAvailableAmount(address account,uint256[] memory ids) external view returns(uint256){
        uint256 available = availableShare[account];
        for(uint256 i; i<ids.length; i++){
            DepositLock memory depositLock = depositMap[ids[i]];
            if(account == depositLock.account){
                available += depositMap[ids[i]].share;
            }
        }
        return available;
    }

    modifier onlyOwner()  {
        require(dataStorage.owner() == msg.sender,"Caller is not owner");
        _;
    }

    function strConcat(string memory _a, string memory _b) internal pure returns (string memory){
        bytes memory _ba = bytes(_a);
        bytes memory _bb = bytes(_b);
        string memory ret = new string(_ba.length + _bb.length);
        bytes memory res = bytes(ret);
        uint256 k = 0;
        for (uint256 i = 0; i < _ba.length; i++) res[k++] = _ba[i];
        for (uint256 i = 0; i < _bb.length; i++) res[k++] = _bb[i];
        return string(res);
    }
}
