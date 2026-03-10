// SPDX-License-Identifier: None
pragma solidity ^0.4.26;

library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        assert(c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }

    function toString(
        uint256 _i
    ) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
}

contract Ownable {
    address public owner;

    constructor() public {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "forbidden");
        _;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        if (newOwner != address(0)) {
            owner = newOwner;
        }
    }
}

interface IMWEngine {
    function isMWEngine() external view returns (bool supported);

    function outputs(
        address sender,
        address receiver,
        uint256 amount
    )
        external
        view
        returns (address[] receivers, uint256[] amounts, uint256 upfront);
}

contract ERC20Basic {
    uint256 public _totalSupply;

    function totalSupply() public constant returns (uint256);

    function balanceOf(address who) public constant returns (uint256);

    function transfer(address to, uint256 value) public;

    event Transfer(address indexed from, address indexed to, uint256 value);
}

contract ERC20 is ERC20Basic {
    function allowance(
        address owner,
        address spender
    ) public constant returns (uint256);

    function transferFrom(address from, address to, uint256 value) public;

    function approve(address spender, uint256 value) public;

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

contract BasicToken is Ownable, ERC20Basic {
    using SafeMath for uint256;

    mapping(address => uint256) public balances;

    // additional variables for use if transaction fees ever became necessary
    uint256 public basisPointsRate = 0;
    uint256 public maximumFee = 0;

    // fee-rule-engine for use when needed.
    // applicable only when basisPointsRate and maximumFee are 0.
    address public mwEngine;

    /**
     * @dev Fix for the ERC20 short address attack.
     */
    modifier onlyPayloadSize(uint256 size) {
        require(!(msg.data.length < size + 4), "invalid payload");
        _;
    }

    function transfer(
        address _to,
        uint256 _value
    ) public onlyPayloadSize(2 * 32) {
        _transfer(msg.sender, _to, _value);
    }

    function _transfer(address _from, address _to, uint256 _value) internal {
        /*
         * Use Fees Distribution Contract
         */
        if (mwEngine != address(0x0)) {
            address[] memory outputs;
            uint256[] memory amounts;
            uint256 upfront;

            // output addresses and amount
            (outputs, amounts, upfront) = IMWEngine(mwEngine).outputs(
                _from,
                _to,
                _value
            );
            _value = _value.add(upfront);
            require(balances[_from] >= _value, "low balance");
            balances[_from] = balances[_from].sub(_value);

            // validate outputs and amounts
            require(
                outputs.length == amounts.length,
                "incompatible outputs amounts"
            );

            uint256 aggregate = 0;
            // update balance accordingly
            for (uint256 i = 0; i < outputs.length; i++) {
                if (amounts[i] > 0) {
                    aggregate = aggregate.add(amounts[i]);
                    balances[outputs[i]] = balances[outputs[i]].add(amounts[i]);
                    emit Transfer(_from, outputs[i], amounts[i]);
                }
            }

            // total outputs should be equals to input _value
            require(aggregate == _value, "invalid value to outputs amounts");
        }
        /*
         * Else Use Default General Transfer & Fees
         */
        else {
            require(balances[_from] >= _value, "low balance");
            balances[_from] = balances[_from].sub(_value);

            uint256 fee = (_value.mul(basisPointsRate)).div(10000);
            if (fee > maximumFee) {
                fee = maximumFee;
            }
            uint256 sendAmount = _value.sub(fee);
            balances[_to] = balances[_to].add(sendAmount);
            if (fee > 0) {
                balances[owner] = balances[owner].add(fee);
                emit Transfer(_from, owner, fee);
            }
            emit Transfer(_from, _to, sendAmount);
        }
    }

    function balanceOf(
        address _owner
    ) public constant returns (uint256 balance) {
        return balances[_owner];
    }
}

/**
 * @title Standard ERC20 token
 *
 * @dev Implementation of the basic standard token.
 * @dev https://github.com/ethereum/EIPs/issues/20
 */
contract StandardToken is BasicToken, ERC20 {
    mapping(address => mapping(address => uint256)) public allowed;

    uint256 public constant MAX_UINT = 2 ** 256 - 1;

    /**
     * @dev Transfer tokens from one address to another
     * @param _from address The address which you want to send tokens from
     * @param _to address The address which you want to transfer to
     * @param _value uint the amount of tokens to be transferred
     */
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) public onlyPayloadSize(3 * 32) {
        uint256 _allowance = allowed[_from][msg.sender];

        // Check is not needed because sub(_allowance, _value) will already throw if this condition is not met
        // if (_value > _allowance) throw;
        if (_allowance < MAX_UINT) {
            allowed[_from][msg.sender] = _allowance.sub(_value);
        }

        require(_value > _allowance, "not permitted");

        /*
         * Use Fees Distribtuion Contract
         */
        if (mwEngine != address(0x0)) {
            address[] memory outputs;
            uint256[] memory amounts;
            uint256 upfront;
            (outputs, amounts, upfront) = IMWEngine(mwEngine).outputs(
                _from,
                _to,
                _value
            );
            _value = _value.add(upfront);
            require(balances[msg.sender] >= _value, "low balance");
            balances[msg.sender] = balances[msg.sender].sub(_value);
            uint256 aggregate = 0;
            require(
                outputs.length == amounts.length,
                "incompatible outputs amounts"
            );
            for (uint256 i = 0; i < outputs.length; i++) {
                aggregate = aggregate.add(amounts[i]);
                balances[outputs[i]] = balances[outputs[i]].add(amounts[i]);
                emit Transfer(msg.sender, outputs[i], amounts[i]);
            }
            require(aggregate == _value, "invalid value to outputs amounts");
        }
        /*
         * Else Use Default General Transfer & Fees
         */
        else {
            require(balances[msg.sender] >= _value, "low balance");
            uint256 fee = (_value.mul(basisPointsRate)).div(10000);
            if (fee > maximumFee) {
                fee = maximumFee;
            }
            uint256 sendAmount = _value.sub(fee);
            balances[_from] = balances[_from].sub(_value);
            balances[_to] = balances[_to].add(sendAmount);
            if (fee > 0) {
                balances[owner] = balances[owner].add(fee);
                emit Transfer(_from, owner, fee);
            }
            emit Transfer(_from, _to, sendAmount);
        }
    }

    /**
     * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
     * @param _spender The address which will spend the funds.
     * @param _value The amount of tokens to be spent.
     */
    function approve(
        address _spender,
        uint256 _value
    ) public onlyPayloadSize(2 * 32) {
        // To change the approve amount you first have to reduce the addresses`
        //  allowance to zero by calling `approve(_spender, 0)` if it is not
        //  already 0 to mitigate the race condition described here:
        //  https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
        require(
            !((_value != 0) && (allowed[msg.sender][_spender] != 0)),
            "not allowed"
        );

        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
    }

    function allowance(
        address _owner,
        address _spender
    ) public constant returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }
}

/**
 * @title Pausable
 * @dev emergency stop mechanism.
 */
contract Pausable is Ownable {
    event Pause();
    event Unpause();

    bool public paused = false;

    modifier whenNotPaused() {
        require(!paused, "paused");
        _;
    }

    modifier whenPaused() {
        require(paused, "not paused");
        _;
    }

    function pause() public onlyOwner whenNotPaused {
        paused = true;
        emit Pause();
    }

    function unpause() public onlyOwner whenPaused {
        paused = false;
        emit Unpause();
    }
}

contract BlackList is Ownable, BasicToken {
    uint8 DEFAULT = 0;
    uint8 BLACKLISTED = 1;
    uint8 WHITELISTED = 2;

    bool public onlyWhitelisted = true;

    mapping(address => uint8) public status;

    modifier isPermitted(address _address) {
        require(status[_address] != BLACKLISTED, "blacklisted");
        require(
            (onlyWhitelisted && status[_address] == WHITELISTED) ||
                !onlyWhitelisted,
            "not whitelisted"
        );
        _;
    }

    function setWhitelisting(bool byDefault) public onlyOwner {
        onlyWhitelisted = byDefault;
    }

    function requirePermission(
        address _address
    ) public view isPermitted(_address) returns (bool) {
        return true;
    }

    mapping(address => bool) public _blacklisters;

    modifier onlyBlackLister() {
        require(_blacklisters[msg.sender], "forbidden");
        _;
    }

    constructor() public {
        _blacklisters[owner] = true;
    }

    function setBlacklister(
        address _blacklister,
        bool _enabled
    ) public onlyOwner {
        _blacklisters[_blacklister] = _enabled;
    }

    /////// Getters to allow the same blacklist to be used also by other contracts (including upgraded ones) ///////
    function getBlackListStatus(
        address _user
    ) external constant returns (uint8) {
        return status[_user];
    }

    function getOwner() external constant returns (address) {
        return owner;
    }

    function addBlackList(address _user) public onlyBlackLister {
        status[_user] = BLACKLISTED;
        emit SetBlackList(_user, true);
    }

    function addWhiteList(address _user) public onlyBlackLister {
        status[_user] = WHITELISTED;
        emit SetWhiteList(_user, true);
    }

    function removeBlackList(address _user) public onlyBlackLister {
        status[_user] = DEFAULT;
        emit SetBlackList(_user, false);
    }

    function removeWhiteList(address _user) public onlyBlackLister {
        status[_user] = DEFAULT;
        emit SetWhiteList(_user, false);
    }

    function destroyBlackFunds(
        address _blackListedUser
    ) public onlyBlackLister {
        require(status[_blackListedUser] == BLACKLISTED, "not blacklisted");
        uint256 dirtyFunds = balanceOf(_blackListedUser);
        balances[_blackListedUser] = 0;
        _totalSupply -= dirtyFunds;
        emit DestroyedBlackFunds(_blackListedUser, dirtyFunds);
    }

    event DestroyedBlackFunds(address _blackListedUser, uint256 _balance);
    event SetBlackList(address _user, bool blacklisted);
    event SetWhiteList(address _user, bool whitelisted);
}

contract FeeAble is Ownable, BasicToken {
    address public feeAdmin;

    modifier onlyFeeAdmin() {
        require(msg.sender == feeAdmin, "forbidden");
        _;
    }

    constructor() public {
        feeAdmin = owner;
    }

    function changeFeeAdmin(address _feeAdmin) public onlyOwner {
        feeAdmin = _feeAdmin;
    }
}

contract Issuable is Ownable, BasicToken {
    address public issuer;

    // Called when new token are issued
    event Issue(uint256 amount, address destination);

    modifier onlyIssuer() {
        require(msg.sender == issuer, "forbidden");
        _;
    }

    constructor() public {
        issuer = owner;
    }

    function changeIssuer(address _issuer) public onlyOwner {
        issuer = _issuer;
    }

    // Issue a new amount of tokens
    // these tokens are deposited into the owner address
    //
    // @param _amount Number of tokens to be issued
    function issue(
        uint256 amount,
        address destination
    ) public onlyIssuer onlyPayloadSize(2 * 32) {
        require(
            _totalSupply + amount > _totalSupply,
            "invalid supply + amount"
        );
        require(
            balances[destination] + amount > balances[destination],
            "invalid balance + amount"
        );

        balances[destination] += amount;
        _totalSupply += amount;

        emit Issue(amount, destination);
    }

    // Redeem tokens.
    // These tokens are withdrawn from the owner address
    // if the balance must be enough to cover the redeem
    // or the call will fail.
    // @param _amount Number of tokens to be issued
    function redeem(uint256 amount) public onlyIssuer {
        require(_totalSupply >= amount, "invalid amount");
        require(balances[issuer] >= amount, "invalid amount");

        _totalSupply -= amount;
        balances[issuer] -= amount;
        emit Redeem(amount);
    }

    // Called when tokens are redeemed
    event Redeem(uint256 amount);
}

contract UpgradedStandardToken is StandardToken {
    // those methods are called by the legacy contract
    // and they must ensure msg.sender to be the contract address
    function transferByLegacy(address from, address to, uint256 value) public;

    function transferFromByLegacy(
        address sender,
        address from,
        address spender,
        uint256 value
    ) public;

    function approveByLegacy(
        address from,
        address spender,
        uint256 value
    ) public;
}

contract ADC is Pausable, StandardToken, BlackList, Issuable, FeeAble {
    string public name;
    string public symbol;
    uint256 public decimals;

    address public upgradedAddress;
    bool public deprecated;
    mapping(address => uint256) public nonces;

    // bytes4(keccak256(abi.encodePacked("transfer:permit:mcoin")))
    string DOMAIN_PERMIT_HASH = "0xface0377";

    //  The contract can be initialized with a number of tokens
    //  All the tokens are deposited to the owner address
    //
    // @param _balance Initial supply of the contract
    // @param _name Token Name
    // @param _symbol Token symbol
    // @param _decimals Token decimals
    constructor(
        uint256 _initialSupply,
        string _name,
        string _symbol,
        uint256 _decimals
    ) public {
        _totalSupply = _initialSupply;
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        balances[owner] = _initialSupply;
        deprecated = false;
    }

    // managed issuance
    function issue(uint256 amount, address destination) public onlyIssuer {
        require(deprecated != true, "deprecated");
        super.issue(amount, destination);
    }

    function redeem(uint256 amount) public onlyIssuer {
        require(deprecated != true, "deprecated");
        super.redeem(amount);
    }

    function batchTransferBySigs(
        address[] spenders,
        address[] tos,
        uint256[] values,
        bytes32[] r,
        bytes32[] s,
        uint8[] v
    ) public whenNotPaused {
        uint256 count = spenders.length;
        require(
            tos.length == count &&
                values.length == count &&
                r.length == count &&
                s.length == count &&
                v.length == count,
            "invalid args"
        );
        for (uint256 i = 0; i < count; i++) {
            transferBySig(spenders[i], tos[i], values[i], r[i], s[i], v[i]);
        }
    }

    function transferBySig(
        address spender,
        address to,
        uint256 value,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) public whenNotPaused isPermitted(spender) isPermitted(to) {
        require(deprecated == false, "inactive");
        bytes32 permitHash = keccak256(
            bytes(
                string(
                    abi.encodePacked(
                        DOMAIN_PERMIT_HASH,
                        ":",
                        nonces[spender].toString()
                    )
                )
            )
        );
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 ethSigHash = keccak256(abi.encodePacked(prefix, permitHash));
        require(spender == ecrecover(ethSigHash, v, r, s), "invalid signature");

        nonces[spender]++;
        super._transfer(spender, to, value);
    }

    function batchTransfer(
        address[] _targets,
        uint256[] _values
    ) public whenNotPaused isPermitted(msg.sender) {
        require(deprecated == false, "inactive");
        require(_targets.length == _values.length, "invalid args");
        for (uint256 i = 0; i < _targets.length; i++) {
            requirePermission(_targets[i]);
            super._transfer(msg.sender, _targets[i], _values[i]);
        }
    }

    // Forward ERC20 methods to upgraded contract if this one is deprecated
    function transfer(
        address _to,
        uint256 _value
    ) public whenNotPaused isPermitted(msg.sender) isPermitted(_to) {
        if (deprecated) {
            return
                UpgradedStandardToken(upgradedAddress).transferByLegacy(
                    msg.sender,
                    _to,
                    _value
                );
        } else {
            return super.transfer(_to, _value);
        }
    }

    // Forward ERC20 methods to upgraded contract if this one is deprecated
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) public whenNotPaused isPermitted(_from) isPermitted(_to) {
        if (deprecated) {
            return
                UpgradedStandardToken(upgradedAddress).transferFromByLegacy(
                    msg.sender,
                    _from,
                    _to,
                    _value
                );
        } else {
            return super.transferFrom(_from, _to, _value);
        }
    }

    // Forward ERC20 methods to upgraded contract if this one is deprecated
    function balanceOf(address who) public constant returns (uint256) {
        if (deprecated) {
            return UpgradedStandardToken(upgradedAddress).balanceOf(who);
        } else {
            return super.balanceOf(who);
        }
    }

    // Forward ERC20 methods to upgraded contract if this one is deprecated
    function approve(
        address _spender,
        uint256 _value
    ) public onlyPayloadSize(2 * 32) {
        if (deprecated) {
            return
                UpgradedStandardToken(upgradedAddress).approveByLegacy(
                    msg.sender,
                    _spender,
                    _value
                );
        } else {
            return super.approve(_spender, _value);
        }
    }

    // Forward ERC20 methods to upgraded contract if this one is deprecated
    function allowance(
        address _owner,
        address _spender
    ) public constant returns (uint256 remaining) {
        if (deprecated) {
            return StandardToken(upgradedAddress).allowance(_owner, _spender);
        } else {
            return super.allowance(_owner, _spender);
        }
    }

    // deprecate current contract in favour of a new one
    function deprecate(address _upgradedAddress) public onlyOwner {
        deprecated = true;
        upgradedAddress = _upgradedAddress;
        emit Deprecate(_upgradedAddress);
    }

    // deprecate current contract if favour of a new one
    function totalSupply() public constant returns (uint256) {
        if (deprecated) {
            return StandardToken(upgradedAddress).totalSupply();
        } else {
            return _totalSupply;
        }
    }

    function setMWEngine(address _mwEngine) public onlyFeeAdmin {
        require(
            basisPointsRate == 0 && maximumFee == 0,
            "forbidden: using basisPoint and maximumFee"
        );
		
		if(_mwEngine != address(0x0)) {
			require(IMWEngine(_mwEngine).isMWEngine(), "forbidden: invalid interface");
		}
		
        mwEngine = _mwEngine;
        emit SetMWEngine(_mwEngine);
    }

    function setParams(
        uint256 newBasisPoints,
        uint256 newMaxFee
    ) public onlyFeeAdmin {
        require(mwEngine == address(0x0), "forbidden: using fee engine");

        // Ensure transparency by hardcoding limit beyond which fees can never be added
        require(newBasisPoints < 20, "invalid: newBasisPoints >= 20");
        require(newMaxFee < 50, "invalid: newMaxFee >= 50");

        basisPointsRate = newBasisPoints;
        maximumFee = newMaxFee.mul(10 ** decimals);

        emit Params(basisPointsRate, maximumFee);
    }

    // Called if contract ever adds fees
    event Params(uint256 feeBasisPoints, uint256 maxFee);

    // Called if contract ever adds mw engine
    event SetMWEngine(address mwEngine);

    // Called when contract is deprecated
    event Deprecate(address newAddress);
}