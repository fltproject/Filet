pragma solidity ^0.5.0;

// import "./libs/GSN/Context.sol";
// import "./libs/token/ERC20/ERC20Detailed.sol";
// import "./libs/token/ERC20/ERC20.sol";

import "github.com/polynetwork/eth-contracts/contracts/libs/GSN/Context.sol"
import "github.com/polynetwork/eth-contracts/contracts/libs/token/ERC20/ERC20Detailed.sol"
import "github.com/polynetwork/eth-contracts/contracts/libs/token/ERC20/ERC20.sol"

contract FILE is Context, ERC20, ERC20Detailed {
    
    using SafeMath for uint256;
    constructor (string memory name,string memory symbol,uint8 decimals,address marketing,uint256 amount) public ERC20Detailed(name, symbol, decimals) {

        //set owner account
        _owner = msg.sender;
        if (amount > 0 ){
            _mint(marketing, amount );
        }
    }

    address private _owner;
    address private _admin;

    mapping(address => uint256) public minerMap;

    //event
    event OwnershipTransferred(
        address     owner,       
        address     newOwner   
    );

    //used for add admin control 
    modifier onlyOwner() { // Modifier
        require(
            msg.sender == _owner,
            "Only onwer can call this."
        );
        _;
    }

    //used for add admin control 
    modifier onlyAdmin() { // Modifier
        require(
            msg.sender == _admin || msg.sender == _owner,
            "Only admin can call this."
        );
        _;
    }

   /**
     * @dev Set admin permission account (`admin`).
     * Can only be called by the current owner.
     */
    function setAdmin(address admin) public onlyOwner{
        _admin = admin;
    }

   /**
     * @dev Set miner whiteList  (`miner,maxTokenGet `).
     * Can only be called by the current admin account.
     */
    function setMiner(address miner,uint256 maxTokenGet) public onlyAdmin{

        minerMap[miner] = maxTokenGet;
    }

   /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    /**
     * @dev sent miner token (`miner,amount`).
     * Can only be called by the current owner.
     */
    function getFILEForMiner(address miner ,uint256 amount) public onlyOwner returns(bool){

        //check
        require(minerMap[miner] >= amount,"Has exceeded the max amount for token");
        minerMap[miner] = minerMap[miner].sub(amount);
        _mint(miner,amount);
        return true;
    }

    /**
     * @dev mint token for user (`user,amount`).
     * Can only be called by the current owner.
     */
    function mintFILEForUser(address user ,uint256 amount) public onlyOwner returns(bool){

        _mint(user,amount);
        return true;
    }
}