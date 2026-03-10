// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.26;
pragma abicoder v2;

interface IStargateRouter {
    struct lzTxObj {
        uint256 dstGasForCall;
        uint256 dstNativeAmount;
        bytes dstNativeAddr;
    }

    function swap(
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        address payable _refundAddress,
        uint256 _amountLD,
        uint256 _minAmountLD,
        lzTxObj memory _lzTxParams,
        bytes calldata _to,
        bytes calldata _payload
    ) external payable;
}

interface IERC20 {
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract StargateCrossChainSwap {
    
    /**
        startgate router
        1. BSC testnet :                0xB606AaA7E2837D4E6FC1e901Ba74045B29D2EB36
        2. ETH (arb) sepolia testnet :  0x2a4C2F5ffB0E0F2dcB3f9EBBd442B8F77ECDB9Cc
    **/
    address private stargateRouter  = 0xB606AaA7E2837D4E6FC1e901Ba74045B29D2EB36;
    address private bscContractXFAN = 0x183391E01036A95Faf817752d3D9366EBb9c8F43;

    // 10102, 1-USCC(arb sepolia), 2-USDT(BSC)
    function swap(uint16 _dstChainId, uint256 _srcPoolId, uint256 _dstPoolId, 
        uint256 _amountLD, uint256 _minAmountLD) public payable {

        address usdtTokenAddress = 0x3253a335E7bFfB4790Aa4C25C4250d206E9b9773;
        IERC20(usdtTokenAddress).transferFrom(msg.sender, address(this), _amountLD);

        // 10102 - BSC (Sepolia arb)
        if (_dstChainId == 10102){
            // Approve Stargate router to spend USDT
            IERC20(usdtTokenAddress).approve(stargateRouter, _amountLD);

            // Call Stargate router to perform the cross-chain swap
            IStargateRouter(stargateRouter).swap{
                value: msg.value
            }(
                _dstChainId,            // send to Fuji (use LayerZero chainId)
                _srcPoolId,             // pool ID for USDT (this may vary by network)
                _dstPoolId,             // pool ID for USDT on destination chain
                payable(msg.sender),    // refund adddress. extra gas (if any) is returned to this address
                _amountLD,              // quantity to swap in LD, (local decimals)
                _minAmountLD,           // the min qty you would accept in LD (local decimals)
                IStargateRouter.lzTxObj(0, 0, "0x"),  // 0 additional gasLimit increase, 0 airdrop, at 0x address
                abi.encodePacked(bscContractXFAN),    // the address to send the tokens to on the destination
                bytes("")               // bytes param, if you wish to send additional payload you can abi.encode() them here
            );
        }
        //else{
        //    IERC20(usdtTokenAddress).transfer(bscContract, _amountLD);
        //}
    }
}

