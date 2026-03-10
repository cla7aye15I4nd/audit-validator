// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// Uncomment this line to use console.log
// import "hardhat/console.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./interfaces/IDataStorage.sol";

contract LRTVault is ReentrancyGuardUpgradeable{
    using SafeERC20 for IERC20;
    IDataStorage public dataStorage;
    address public token;      // LRT Token contract address
    uint256 public totalStakeAmount;
    uint256 public eventId;

    mapping(address => uint256) public stakeAmounts;

    event Deposit(uint256 indexed id,address user,address tokenContract,uint256 depositAmount,uint256 userBalance,uint256 vaultBalance,uint256 createTime);
    event Withdraw(uint256 indexed id,address user,address tokenContract,uint256 withdrawAmount,uint256 userBalance,uint256 vaultBalance,uint256 createTime);
    event MoveToken(address receiver,address tokenContract,uint256 amount,uint256 createTime);
    event UpdateDataStorage(address user,address oldStorage,address currentStorage);

    constructor(address storageContract,address tokenContract) {
        require(storageContract != address(0) && tokenContract != address(0),"Invalid Zero Address");
        dataStorage = IDataStorage(storageContract);
        token = tokenContract;
    }

    function deposit(uint256 amount) external{
        _deposit(msg.sender,amount);
    }

    function _deposit(address account,uint256 amount) internal nonReentrant{
        require(amount >= dataStorage.minDepositMap(address(this)),"Deposit amount too small");
        uint256 beforeBalance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(account, address(this), amount);
        uint256 afterBalance = IERC20(token).balanceOf(address(this));
        amount = afterBalance - beforeBalance;
        stakeAmounts[account] += amount;
        totalStakeAmount += amount;
        emit Deposit(setEventId(),account,token,amount,stakeAmounts[account],totalStakeAmount,block.timestamp);
    }

    function withdraw(uint256 amount) external{
        _withdraw(msg.sender,amount);
    }

    function _withdraw(address account,uint256 amount) internal nonReentrant{
        require(stakeAmounts[account] >= amount,"withdraw amount over balance");
        stakeAmounts[account] -= amount;
        IERC20(token).safeTransfer(account,amount);
        totalStakeAmount -= amount;
        emit Withdraw(setEventId(),account, token, amount, stakeAmounts[account], totalStakeAmount, block.timestamp);
    }

    function moveToken(address receiver,address tokenContract,uint256 amount) external onlyOwner{
        if(token == tokenContract){
            require(IERC20(token).balanceOf(address(this)) - totalStakeAmount >= amount,"Not enough airdrops");
        }else{
            if(amount == type(uint256).max){
                amount = IERC20(tokenContract).balanceOf(address(this));
            }
        }
        IERC20(tokenContract).safeTransfer(receiver,amount);
        emit MoveToken(receiver,tokenContract,amount,block.timestamp);
    }

    function setEventId() internal returns(uint256){
        return eventId++;
    }

    function updateDataStorageContract(address storageContract) external onlyOwner{
        require(storageContract != address(0),"Invalid Zero Address");
        emit UpdateDataStorage(msg.sender,address(dataStorage),storageContract);
        dataStorage = IDataStorage(storageContract);
        require(dataStorage.owner() != address(0),"Invalid Owner Address");
        dataStorage.minDepositMap(address(this));
    }

    modifier onlyOwner()  {
        require(dataStorage.owner() == msg.sender,"Caller is not owner");
        _;
    }
}
