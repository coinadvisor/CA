pragma solidity ^0.4.18;


/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
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
        assert(b > 0); // Solidity automatically throws when dividing by 0
        uint256 c = a / b;
        assert(a == b * c + a % b); // There is no case in which this doesn't hold
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
}


/**
 * @title ERC20Basic
 * @dev Simpler version of ERC20 interface
 * @dev see https://github.com/ethereum/EIPs/issues/179
 */
contract ERC20Basic {
    uint256 public totalSupply;
    function balanceOf(address who) public view returns (uint256);
    function transfer(address to, uint256 value) public returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
}

/**
 * @title ERC20 interface
 * @dev see https://github.com/ethereum/EIPs/issues/20
 */
contract ERC20 is ERC20Basic {
    function allowance(address owner, address spender) public view returns (uint256);
    function transferFrom(address from, address to, uint256 value) public returns (bool);
    function approve(address spender, uint256 value) public returns (bool);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

/**
 *******************************************************************************
 ********************* Crowd Sale **********************************************
 *******************************************************************************
 */


/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
 */
contract Ownable {
    address public owner;
    
    
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    
    /**
    * @dev The Ownable constructor sets the original `owner` of the contract to the sender
    * account.
    */
    function Ownable() public {
        owner = msg.sender;
    }
    
    
    /**
    * @dev Throws if called by any account other than the owner.
    */
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }
    
    
    /**
    * @dev Allows the current owner to transfer control of the contract to a newOwner.
    * @param newOwner The address to transfer ownership to.
    */
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0));
        OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}


/*
    Controlled CrowdSale
*/
contract ControlledCrowdSale {
    using SafeMath for uint256;
    
    mapping (address => uint256) public deposited;
    mapping (address => bool) public unboundedLimit;
    
    uint256 public maxPerUser = 5 ether;
    uint256 public minPerUser = 1 ether / 1000;
    
    
    modifier controlledDonation() {
        require(msg.value >= minPerUser && msg.value <= maxPerUser);
        deposited[msg.sender] = deposited[msg.sender].add(msg.value);
        require(maxPerUser >= deposited[msg.sender] || unboundedLimit[msg.sender]);
        _;
    }

}


/**
 * @title CoinAdvisorCrowdSale
 * @dev This contract is used for storing funds while a crowdsale
 * is in progress. Supports refunding the money if crowdsale fails,
 * and forwarding it if crowdsale is successful.
 */
contract CoinAdvisorCrowdSale is Ownable, ControlledCrowdSale {
    using SafeMath for uint256;
    enum State { Active, Refunding, Completed }
    
    struct Phase {
        uint expireDate;
        uint256 maxAmount;
        bool maxAmountEnabled;
        uint rate;
        bool locked;
    }

//=== properties =============================================

    Phase[] public phases;
    uint256 lastActivePhase;
    
    State public state;
    uint256 public goal;
    address public beneficiary;
    ERC20 public token;
  
  
//=== events ==================================================
    event CrowdSaleClosed(string message, address crowdSaleClosed);
    event RefundsEnabled();
    event Refunded(address indexed beneficiary, uint256 weiAmount);
    event CrowdSaleStarted(string message, address crowdSaleStarted);


    function CoinAdvisorCrowdSale(address _beneficiary, address _token, uint256 _goal) public {
        require(_beneficiary != address(0));
        beneficiary = _beneficiary;
        token = ERC20(_token);
        phases.push(Phase(0, 0, false, 1000, false));
        lastActivePhase = 0;
        goal = _goal * 1 ether;
        state = State.Active;
    }


    /**
     * 
     *
     */ 
    function isPhaseValid(uint256 index) internal view returns (bool) {
        return phases[index].expireDate <= now && (!phases[index].maxAmountEnabled || phases[index].maxAmount > minPerUser);
    } 
    
    /**
     * 
     *
     */
    function currentPhaseId() internal view returns (uint256) {
        uint256 index = lastActivePhase;
        while(index < phases.length-1 && !isPhaseValid(index)) {
            index = index +1;
        }
        return index;
    }

    /**
     * 
     *
     */
    function currentPhase() public view returns (Phase) {
        return phases[currentPhaseId()];
    }
  
    /**
     * 
     *
     */
    function () controlledDonation public payable {
        uint256 phaseId = currentPhaseId();
        require(isPhaseValid(phaseId));
        
        if (phases[phaseId].maxAmountEnabled) {
            if (phases[phaseId].maxAmount >= msg.value) {
                phases[phaseId].maxAmount = phases[phaseId].maxAmount.sub(msg.value);
            } else {
                phases[phaseId].maxAmount = 0;
                //throw;
            }
        }
        
        require(token.transfer(msg.sender, msg.value.mul(phases[phaseId].rate)));
        lastActivePhase = phaseId;
    }
    
    /**
     * 
     *
     */
    function addPhases(uint expireDate, uint256 maxAmount, bool maxAmountEnabled, uint rate, bool locked) onlyOwner public {
//        for (uint256 i=0; i < _phases.length; i++) {
            phases.push(Phase(expireDate, maxAmount, maxAmountEnabled, rate, locked));
//        }
    }
    
    /**
     * 
     *
     */
    function resetPhases(uint expireDate, uint256 maxAmount, bool maxAmountEnabled, uint rate, bool locked) onlyOwner public {
        require(!currentPhase().locked);
        phases.length = 0;
        lastActivePhase = 0;
        addPhases(expireDate, maxAmount, maxAmountEnabled, rate, locked);
    }
    
    /**
     * 
     *
     */
    function startRefunding() public {
        require(state == State.Active);
        require(!currentPhase().locked);
        require(this.balance < goal);
        state = State.Refunding;
        RefundsEnabled();
    }
    
    /**
     * 
     *
     */
    function forceRefunding() onlyOwner public {
        require(state == State.Active);
        state = State.Refunding;
        RefundsEnabled();
    }
    
    /**
     * 
     *
     */
    function retrieveFounds() onlyOwner public {
        require(state == State.Completed || 
                (state == State.Active && this.balance >= goal));
                
        state = State.Completed;
        beneficiary.transfer(this.balance);
    }
    
    /**
     * 
     *
     */
    function refund(address investor) public {
        require(state == State.Refunding);
        require(deposited[investor] > 0);
        
        uint256 depositedValue = deposited[investor];
        deposited[investor] = 0;
        investor.transfer(depositedValue);
        Refunded(investor, depositedValue);
    }
    
    /**
     * 
     *
     */
    function setUnboundedLimit(address _investor, bool _state) onlyOwner public {
        require(_investor != address(0));
        unboundedLimit[_investor] = _state;
    }

    /**
     * 
     *
     */
    function gameOver() onlyOwner public {
        uint256 i = currentPhaseId();
        require(!isPhaseValid(i));
        retrieveFounds();
        selfdestruct(beneficiary);
    }
    
    
    // detail functions
    
    // function currentTokenPerEtherRate() public view returns (uint) {
    //     return currentPhase().rate;
    // }
    
    function currentState() public view returns (string) {
        if (state == State.Active) {
            return "";
        }
        if (state == State.Completed) {
            return "";
        }
        if (state == State.Refunding) {
            return "";
        }
    }
    
    function tokensInSale() public view returns (uint256) {
        uint256 i = currentPhaseId();
        if (isPhaseValid(i)) {
            return phases[i].maxAmountEnabled ? phases[i].maxAmount : token.balanceOf(this);
        } else {
            return 0;
        }
    }
    
    function salePhaseExpirationDate() public view returns (uint256) {
        uint256 i = currentPhaseId();
        if (isPhaseValid(i)) {
            return phases[i].expireDate;
        } else {
            return 0;
        }
    }
    
    function tokensPerEtherRate() public view returns (uint256) {
        uint256 i = currentPhaseId();
        if (isPhaseValid(i)) {
            return phases[i].rate;
        } else {
            return 0;
        }
    }
    
}


