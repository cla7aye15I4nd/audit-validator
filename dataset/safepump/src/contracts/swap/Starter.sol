// SPDX-License-Identifier: MIT

pragma solidity =0.7.4;
pragma experimental ABIEncoderV2;

import '../libraries/Ownable.sol';
import '../libraries/SafeERC20.sol';
import '../libraries/EnumerableSet.sol';

contract Starter is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _tokens;
    enum Status {inProgress, ended, rejected}

    Status constant STATUS_DEFAULT = Status.inProgress;

    struct Proposal {
        address beneficiary;
        address baseToken;
        address quoteToken;
        uint256 goalAmount; // goal amount of base token
        uint256 price; // price to base token, 0 if not fixed
        uint256 buyLimit; // 0 if not have limit
        uint256 startBlock;
        uint256 endBlock;
        uint256 soldAmount; // sold amount of base token
        Status status;
        bool isFixedPrice;
        bool hasWhitelist;
    }

    struct UserInfo {
        uint256 purchasedAmount; // amount of base token
        uint256 claimedAmount; // amount of quote token
        bool isClaimed;
    }

    Proposal[] proposals;
    mapping(address => uint256) public tokenOfPid;
    mapping(address => mapping(uint256 => UserInfo)) public users; // address, pid, user info
    mapping(uint256 => EnumerableSet.AddressSet) private whitelists;

    event Purchase(uint256 pid, address baseToken, address account, uint256 amount);
    event Settle(uint256 pid, Status status);
    event Withdraw(uint256 pid, address quoteToken, address account, uint256 amount);

    constructor() Ownable(msg.sender) {}

    function addWhitelist(uint256 _pid, address[] memory _accounts) public onlyOwner returns (bool) {
        require(_accounts.length >= 0, 'Starter: account length is zero');
        Proposal storage proposal = proposals[_pid];
        require(proposal.hasWhitelist, "Starter: proposal doesn't have whitelist");
        for (uint256 i = 0; i < _accounts.length; i++) {
            EnumerableSet.add(whitelists[_pid], _accounts[i]);
        }
        return true;
    }

    function delWhitelist(uint256 _pid, address _account) public onlyOwner returns (bool) {
        require(_account != address(0), 'Starter: account is the zero address');
        Proposal storage proposal = proposals[_pid];
        require(proposal.hasWhitelist, "Starter: proposal doesn't have whitelist");
        return EnumerableSet.remove(whitelists[_pid], _account);
    }

    function getWhitelistLength(uint256 _pid) public view returns (uint256) {
        return EnumerableSet.length(whitelists[_pid]);
    }

    function isInWhitelist(uint256 _pid, address _account) public view returns (bool) {
        return EnumerableSet.contains(whitelists[_pid], _account);
    }

    function createProposal(
        address beneficiary,
        address baseToken,
        address quoteToken,
        uint256 goalAmount,
        uint256 price,
        uint256 buyLimit,
        uint256 startBlock,
        uint256 endBlock,
        bool isFixedPrice,
        bool hasWhitelist
    ) external onlyOwner {
        require(!EnumerableSet.contains(_tokens, quoteToken), 'Starter: quote token is already created');
        EnumerableSet.add(_tokens, quoteToken);
        tokenOfPid[quoteToken] = proposals.length;

        if (isFixedPrice) require(price != 0, 'Stater: fixed price is zero');

        proposals.push(
            Proposal({
                beneficiary: beneficiary,
                baseToken: baseToken,
                quoteToken: quoteToken,
                goalAmount: goalAmount,
                price: price,
                buyLimit: buyLimit,
                startBlock: startBlock,
                endBlock: endBlock,
                soldAmount: 0,
                status: STATUS_DEFAULT,
                isFixedPrice: isFixedPrice,
                hasWhitelist: hasWhitelist
            })
        );
    }

    function purchase(uint256 _pid, uint256 _amount) external canPurchase(_pid) {
        Proposal storage proposal = proposals[_pid];

        IERC20(proposal.baseToken).safeTransferFrom(msg.sender, address(this), _amount);
        users[msg.sender][_pid].purchasedAmount = users[msg.sender][_pid].purchasedAmount.add(_amount);
        if (proposal.buyLimit > 0) {
            require(users[msg.sender][_pid].purchasedAmount <= proposal.buyLimit, 'Starter: can not exceed buy limit');
        }
        proposal.soldAmount = proposal.soldAmount.add(_amount);

        emit Purchase(_pid, proposal.baseToken, msg.sender, _amount);
    }

    function purchaseByETH(uint256 _pid) external payable canPurchase(_pid) {
        Proposal storage proposal = proposals[_pid];
        require(address(proposal.baseToken) == address(0), 'Starter: should call purchase instead');
        uint256 amount = msg.value;

        users[msg.sender][_pid].purchasedAmount = users[msg.sender][_pid].purchasedAmount.add(amount);
        proposal.soldAmount = proposal.soldAmount.add(amount);
        emit Purchase(_pid, proposal.baseToken, msg.sender, amount);
    }

    function settle(uint256 _pid) public onlyOwner {
        Proposal storage proposal = proposals[_pid];
        require(proposal.status == STATUS_DEFAULT, 'Starter: already settled');

        // can be settled in fixed price proposal before end block
        if (!proposal.isFixedPrice) {
            require(block.number >= proposal.endBlock, 'Starter: not ended yet');
        }

        if (!proposal.isFixedPrice) {
            IERC20 quoteToken = IERC20(proposal.quoteToken);
            proposal.price = proposal.soldAmount.mul(10**quoteToken.decimals()).div(
                quoteToken.balanceOf(address(this))
            );
        }
        require(
            IERC20(proposal.quoteToken).balanceOf(address(this)) >= proposal.goalAmount.mul(proposal.price),
            'Starter: balance not enough'
        );
        proposal.status = Status.ended;

        emit Settle(_pid, proposal.status);
    }

    // used by ido investor
    function withdraw(uint256 _pid) external {
        Proposal storage proposal = proposals[_pid];
        require(proposal.status == Status.ended || proposal.status == Status.rejected, 'Starter: proposal in progress');
        uint256 amount = getPendingAmount(_pid, msg.sender);
        if (proposal.status == Status.ended) {
            IERC20(proposal.quoteToken).safeTransfer(msg.sender, amount);
            users[msg.sender][_pid].claimedAmount = users[msg.sender][_pid].claimedAmount.add(amount);
        }
        if (proposal.status == Status.rejected) {
            if (proposal.baseToken == address(0)) {
                msg.sender.transfer(amount);
            }
            IERC20(proposal.baseToken).safeTransfer(msg.sender, amount);
        }
        users[msg.sender][_pid].isClaimed = true;
        emit Withdraw(_pid, proposal.quoteToken, msg.sender, amount);
    }

    // withdraw base token to beneficiary
    function withdrawToken(uint256 _pid) external {
        Proposal storage proposal = proposals[_pid];
        require(msg.sender == proposal.beneficiary, 'Starter: only beneficiary');

        if (proposal.baseToken == address(0)) {
            msg.sender.transfer(proposal.soldAmount);
        } else {
            IERC20(proposal.baseToken).safeTransfer(msg.sender, proposal.soldAmount);
        }

        emit Withdraw(_pid, proposal.baseToken, msg.sender, proposal.soldAmount);
    }

    function getProposalInfo(uint256 _pid) public view returns (Proposal memory) {
        return proposals[_pid];
    }

    function getProposalLength() public view returns (uint256) {
        return proposals.length;
    }

    function getPurchasedAmount(uint256 _pid, address _account) public view returns (uint256) {
        return users[_account][_pid].purchasedAmount;
    }

    function getPendingAmount(uint256 _pid, address _account) public view returns (uint256 amount) {
        if (users[msg.sender][_pid].isClaimed) return 0;
        Proposal memory proposal = proposals[_pid];
        if (proposal.status == Status.inProgress) return 0;

        if (proposal.status == Status.rejected) return users[_account][_pid].purchasedAmount;
        if (proposal.status == Status.ended)
            return
                users[msg.sender][_pid].purchasedAmount.mul(10**IERC20(proposal.quoteToken).decimals()).div(
                    proposal.price
                );
    }

    function rescueTokens(address _token, address _recipient) public onlyOwner {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(_recipient, balance);
    }

    modifier canPurchase(uint256 _pid) {
        Proposal memory proposal = proposals[_pid];

        require(
            block.number >= proposal.startBlock && block.number <= proposal.endBlock,
            'Starter: not in the right time'
        );
        
        require(proposal.status == Status.inProgress, "Starter: proposal ended");

        if (proposal.hasWhitelist) {
            require(isInWhitelist(_pid, msg.sender), 'Starter: msg sender not in the whitelist');
        }
        if (proposal.buyLimit > 0) {
            require(users[msg.sender][_pid].purchasedAmount <= proposal.buyLimit, 'Starter: can not exceed buy limit');
        }
        _;
    }
}
