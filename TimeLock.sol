pragma solidity ^0.4.25;

library SafeMath {
	function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
		if (a == 0) {
			return 0;
		}
		c = a * b;
		assert(c / a == b);
		return c;
	}

	function div(uint256 a, uint256 b) internal pure returns (uint256) {
		return a / b;
	}

	function sub(uint256 a, uint256 b) internal pure returns (uint256) {
		assert(b <= a);
		return a - b;
	}

	function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
		c = a + b;
		assert(c >= a);
		return c;
	}
}

contract Ownable {
	address public owner;
	address public newOwner;

	event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

	constructor() public {
		owner = msg.sender;
		newOwner = address(0);
	}

	modifier onlyOwner() {
		require(msg.sender == owner, "msg.sender == owner");
		_;
	}

	function transferOwnership(address _newOwner) public onlyOwner {
		require(address(0) != _newOwner, "address(0) != _newOwner");
		newOwner = _newOwner;
	}

	function acceptOwnership() public {
		require(msg.sender == newOwner, "msg.sender == newOwner");
		emit OwnershipTransferred(owner, msg.sender);
		owner = msg.sender;
		newOwner = address(0);
	}
}

contract Authorizable is Ownable {
    mapping(address => bool) public authorized;

    event AuthorizationSet(address indexed addressAuthorized, bool indexed authorization);

    constructor() public {
        authorized[msg.sender] = true;
    }

    modifier onlyAuthorized() {
        require(authorized[msg.sender], "authorized[msg.sender]");
        _;
    }

    function setAuthorized(address addressAuthorized, bool authorization) onlyOwner public {
        emit AuthorizationSet(addressAuthorized, authorization);
        authorized[addressAuthorized] = authorization;
    }

}

contract tokenInterface {
	function balanceOf(address _owner) public constant returns (uint256 balance);
	function transfer(address _to, uint256 _value) public returns (bool);
    function transferFrom(address from, address to, uint256 value) public returns (bool);
	bool public started;
}

contract ERC20_MultiTimelock is Ownable, Authorizable {
    using SafeMath for uint256;

	tokenInterface public tokenContract;

	uint256 public startRelease;
	uint256 public timelock;

	mapping (address => uint256) tkn_amount;
	mapping (address => uint256) tkn_sent;

	mapping (address => uint256) public balanceOf;

	function balanceOf(address _user) public view returns(uint256 balanceLocked) {
	    return tkn_amount[_user].sub(tkn_sent[_user]);
	}

	/***************
	 * START ERC20 IMPLEMENTATION
	 ***************/

 	string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    event Transfer(address indexed from, address indexed to, uint256 value);
    function transfer(address, uint256) public returns (bool) {
        return claim();
    }

	/***************
	 * END ERC20 IMPLEMENTATION
	 ***************/

	constructor(address _tokenAddress, uint256 _timelock) public {
		tokenContract = tokenInterface(_tokenAddress);
		timelock = _timelock;

		name = "AQER Timelock";
        symbol = "AQER-TL";
        decimals = 18;

	}

    //set start time to countdown
	function setRelease(uint256 _time) onlyOwner public {
	    require( startRelease == 0 , "startRelease == 0 ");
	    startRelease = _time;
	}

	//claim
	function claim() private returns (bool) {
	    require( startRelease != 0 , "startRelease != 0 ");
	    require( balanceOf[msg.sender] > 0, "balanceOf[msg.sender] > 0");
	    uint256 endRelease = startRelease.add(timelock);

    	if ( now > startRelease ) {
    		uint256 timeprogress = now.sub(startRelease);
    		uint256 rate = 0;
    		if( now > endRelease) {
    			rate = 1e18;
    		} else {
    			rate =  timeprogress.mul(1e18).div(timelock);
    		}
    	}

		uint256 remaining = tkn_amount[msg.sender].sub(tkn_sent[msg.sender]);
		uint256 tknToSend = remaining.mul(rate).div(1e18);
		tkn_sent[msg.sender] = tkn_sent[msg.sender].add(tknToSend);

		require(tknToSend > 0,"tknToSend > 0");

		tokenContract.transfer(msg.sender, tknToSend);

		//Burn ERC20 Timelock
	    emit Transfer(msg.sender, address(0), tknToSend);
	    totalSupply = totalSupply.sub(tknToSend);

	    return true;
	}

	function () public {
	    claim();
	}

	//deposit
	function depositToken( address _beneficiary, uint256 _amount) onlyAuthorized public {
	    require( tokenContract.transferFrom(msg.sender, this, _amount), "tokenContract.transferFrom(msg.sender, this, _amount)" );

	    balanceOf[_beneficiary] = balanceOf[_beneficiary].add(_amount);

	    totalSupply = totalSupply.add(_amount);
	    emit Transfer(address(0), _beneficiary, _amount);
	}

    //Emergency withdrawl
    function noAccountedWithdraw() onlyOwner public {
        uint256 diff = tokenContract.balanceOf(this).sub(totalSupply);
        tokenContract.transfer(msg.sender, diff);
    }
}
