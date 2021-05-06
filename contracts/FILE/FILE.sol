pragma solidity ^0.5.0;

import "./libs/GSN/Context.sol";
import "./libs/token/ERC20/ERC20Detailed.sol";
import "./libs/token/ERC20/ERC20.sol";

contract FILE is Context, ERC20, ERC20Detailed {
    
    using SafeMath for uint256;
    uint256  public totalSupplyLimit ;
    address private polyPoxyCon;

    constructor (
        string memory name,
        string memory symbol,
        uint8 decimals,
        address marketing,
        uint256 amount,
        uint256 totalSupplyLimit_,
        address polyPoxyCon_
    ) public ERC20Detailed(name, symbol, decimals) {

        //marketing is not 0
        require(marketing != address(0),"FILE:constructor: marketing is zero address");

        //set the max token supply
        totalSupplyLimit = totalSupplyLimit_;

        //set bridge contract address
        polyPoxyCon = polyPoxyCon_;

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
    modifier onlyOwnerAndAdmin() { // Modifier
        require(
            msg.sender == _admin || msg.sender == _owner,
            "Only admin can call this."
        );
        _;
    }

    //event for setting admin permission account
    event SetAdminEvent(
        address     admin
    );

   /**
     * @dev Set admin permission account (`admin`).
     * Can only be called by the current owner.
     */
    function setAdmin(address admin) external onlyOwner returns (bool){
        require(admin != address(0),"FILE:setAdmin: admin is zero address");
        _admin = admin;
        emit SetAdminEvent(admin);
        return true;
    }

    //event for setting miner whiteList 
    event SetMinerEvent(
        address     miner,
        uint256     maxToken
    );

   /**
     * @dev Set miner whiteList  (`miner,maxTokenGet `).
     * Can only be called by the current admin account.
     */
    //will be governanced by DAO in the future
    function setMiner(address miner,uint256 maxTokenGet) public onlyOwnerAndAdmin returns (bool){
        require(miner != address(0),"FILE:setMiner: miner is zero address");
        minerMap[miner] = maxTokenGet;
        emit SetMinerEvent(miner,maxTokenGet);
        return true ;
    }

   /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    /**
     * @dev sent miner token (`miner,amount`).
     * Can only be called by the current owner.
     */
    function getFILEForMiner(address miner ,uint256 amount) external onlyOwner returns(bool){

        //check
        require(miner != address(0),"FILE:getFILEForMiner: miner is zero address");
        require(minerMap[miner] >= amount,"Has exceeded the max amount for token");

        require(totalSupplyLimit >= totalSupply().add(amount),"FILE::getFILEForMiner: minting has exceeded totalSupplyLimit");

        minerMap[miner] = minerMap[miner].sub(amount);
        _mint(miner,amount);
        return true;
    }

    /**
     * @dev mint token for user (`user,amount`).
     * Can only be called by the current owner.
     */
    function mintFILEForBridge(uint256 amount) external onlyOwner returns(bool){
        require(polyPoxyCon != address(0),"FILE:mintFILEForUser: bridge contract address is zero address");
        require(totalSupplyLimit >= totalSupply().add(amount),"FILE::mintFILEForUser: minting has exceeded totalSupplyLimit");

        _mint(polyPoxyCon,amount);
        return true;
    }
}