//SPDX-License-Identifier: Unlicense
pragma experimental ABIEncoderV2;
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";


contract StakingCon {
    using SafeMath for uint256;

    //一天的秒数
    uint private secondsForOneDay = 86400;//86400;

    //时区调整
    uint private timeZoneDiff = 28800;

    //admin control
    //contract owner address
    address private _owner;
    address private _admin;

    //contract swith
    bool private _swithOn = false;

    //IERC FLT token Obj
    address public _fltTokenContract;
    IERC20 private _cfltTokenContract;

    //fltTokenContract
    address public _filTokenContract;

    struct maxMiningPowerType{
        uint256 canSell;
        uint256 canNotSell;
    }
    //mine pool info struct 
    struct minePool{
        IERC20      tokenInterface;             
        address     tokenAddress;               
        uint        expireType;                 
        uint        actionType;         

        maxMiningPowerType      maxMiningPower;
        address     earlyRedeemFundAccount;       
        address     redeemFundAccount;        
        address     minerAccount;
        uint256     stakingPrice;      
        uint256     tokenRate;          
        uint256     FILRate;       
        uint        tokenPrecision;

        address     recievePaymentAccount;
        uint256     miniPurchaseAmount;
        uint256     hasSoldOutToken;
        uint        lockInterval;
        uint256[]   poolThredhold;
        uint[]    serviceFeePercent;
    }   

    struct minePoolWrapper{
        minePool mPool;
        bool    isEntity;
    }

    //minepool map
    mapping(uint => minePoolWrapper) public minePoolMap;

    mapping(address => userOrder[]) public userData;

    //miner info
    struct minerInfoList{
        uint[] info;
        address minerAddress;
        bool isEntity;
    }

    // minerInterest 
    mapping(address => minerInfoList) public minerInterest;

    address[] public minerPool;
    
    /** 
    * struct for hold the ratio info
    */
    struct ratioStruct {
        uint256 ostakingPrice;     
        uint  oserviceFeePercent;  
        uint256 oActiveInterest;

        uint256 oFrozenInterest;
        uint256 oHasReceiveInterest;
        uint256 oNeedToPayGasFee;   
        uint256 admineUpdateTime;
    }

    /**
     * @dev user order for mine
    */
    struct userOrder {
        address user;              
        uint256 amount;           
        uint    poolID;             
        bool    status;            
        uint256 cfltamount;        
        uint256 createTime;         
        address targetminer;       
        ratioStruct ratioInfo;
        uint    lastProfitEnd;     
        uint256 lastProfitPerGiB;  
        uint    stopDayTime;       
        uint  isPremium;      

    }

    /**
        add map for recording the user's vip level
     */
    struct userPremiumLevelInfoType {
        address userAddr;
        uint  levelIndex;
        uint256 levelThredholdValue;
        uint  levelServerFee;
    }
    mapping(address => userPremiumLevelInfoType) public userPremiumLevelInfo;

    //event
    event OwnershipTransferred(
        address     owner,       
        address     newOwner   
    );

    /**
     * @dev event for output some certain info about user order
    */

    //minePool mPool
    event eventUserStaking(
        address     user,
        uint        orderID,
        uint256     amount,
        uint        poolID,
        uint256     cfltamount,
        address     tokenAddress,        
        uint        expireType,    
        uint        actionType,          
        uint        serviceFeePercent   
    );

    /**
     * @dev event for redeem operating when expiring
    */
    event eventRedeem(address user,uint orderID,uint256 fee,bool isExpire,address mPool);

    /**
     * @dev event for withdraw operating
    */
    event eventWithDraw(address user,uint poolID,uint orderID,uint256 profitAmount);

    //parameters : HFIL token, 
    constructor() {
        _owner = msg.sender;
    }

    //used for add admin control 
    modifier onlyOwner() { // Modifier
        require(
            msg.sender == _owner,
            "Only onwer can call this."
        );
        _;
    }

    //used for add admin control 
    modifier ownerAndAdmin() { // Modifier
        require(
            msg.sender == _owner || msg.sender == _admin,
            "Only onwer or admin can call this."
        );
        _;
    }

    //used for add admin control 
    modifier onlyAdmin() { // Modifier
        require(
            msg.sender == _admin,
            "Only admin can call this."
        );
        _;
    }

    //lock the contract for safing 
    modifier swithOn() { // Modifier
        require(
            _swithOn,
            "swith is off"
        );
        _;
    }

    //owner set a admin permission
    function setAdmin(address newAdminUser) external onlyOwner{
        _admin = newAdminUser;
    }

    //switch on or off the contract 
    function swithOnContract(bool op) external ownerAndAdmin{
        _swithOn = op;
    }

    // transfer current owner to a new owner account
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
    
    //===================================user operate ==================================================
    //stake for user

    function stake(uint256 amount,uint poolID) public swithOn returns(bool){
        //todo user need to be checked 
        require(minePoolMap[poolID].isEntity,"current pool does not exist");
        require(minePoolMap[poolID].mPool.actionType == 1,"current pool action type mismatch");

        minePool memory localPool = minePoolMap[poolID].mPool;

        require(localPool.recievePaymentAccount != address(0), "there is no such miner address in the contract" );
        
        // ((minFILAmount / 10**18) * tokenRate / FilRate)* tokenPrecision 
        uint256 miniTokenAmount = localPool.miniPurchaseAmount.mul(10**minePoolMap[poolID].mPool.tokenPrecision).mul(localPool.tokenRate).div(localPool.FILRate).div(10**18);
        require(miniTokenAmount <= amount, "input amount must be larger than min amount" );
        address minerAddr = localPool.recievePaymentAccount;

        uint256 power = convertTokenToPower(amount,poolID);
       
        uint isPremiumLatest  = 0;
        if (userData[msg.sender].length > 0){
            isPremiumLatest = userData[msg.sender][userData[msg.sender].length - 1].isPremium;
        }else{
            //if current use is a new one ,just init a level info 
            userPremiumLevelInfo[msg.sender] = userPremiumLevelInfoType({
                userAddr:               msg.sender,    
                levelIndex:             isPremiumLatest,
                levelThredholdValue:    localPool.poolThredhold[isPremiumLatest],
                levelServerFee:         localPool.serviceFeePercent[isPremiumLatest]
            });
        }
        //calculate the server fee level
        uint calcuResult = checkisPremium(amount ,minePoolMap[poolID].mPool.poolThredhold);
        if (isPremiumLatest < calcuResult ){
            isPremiumLatest = calcuResult;

            //record the users level premium info, only update when isPremiumLatest has changed
            
            userPremiumLevelInfo[msg.sender] = userPremiumLevelInfoType({
                userAddr:               msg.sender,    
                levelIndex:             isPremiumLatest,
                levelThredholdValue:    localPool.poolThredhold[isPremiumLatest],
                levelServerFee:         localPool.serviceFeePercent[isPremiumLatest]
            });
        }

        ratioStruct memory ratioInfo;
        ratioInfo.ostakingPrice    = localPool.stakingPrice.mul(localPool.tokenRate).div(localPool.FILRate);
        ratioInfo.oserviceFeePercent = localPool.serviceFeePercent[isPremiumLatest];

        userData[msg.sender].push(
            userOrder({
                user:               msg.sender,
                amount :            amount,
                status :            false,
                cfltamount :        power,
                poolID :            poolID,
                createTime :        block.timestamp,
                targetminer :       minerAddr ,
                ratioInfo  :        ratioInfo,
                lastProfitEnd :     0,
                lastProfitPerGiB :  0,
                stopDayTime :       0,
                isPremium   :       isPremiumLatest
            })
        );

        require(minePoolMap[poolID].mPool.maxMiningPower.canSell >= power ,"the current pool have no enough token to be selled");

        minePoolMap[poolID].mPool.maxMiningPower.canSell = minePoolMap[poolID].mPool.maxMiningPower.canSell.sub(power);

        require(minePoolMap[poolID].mPool.tokenInterface.transferFrom(msg.sender,address(this),amount),"failed to transfer token to contract account for staking");//minerAddress

        minePoolMap[poolID].mPool.hasSoldOutToken = minePoolMap[poolID].mPool.hasSoldOutToken.add(amount);

        emit eventUserStaking(
            msg.sender,
            userData[msg.sender].length - 1,
            amount,
            poolID,
            power,
            localPool.tokenAddress, 
            localPool.expireType, 
            localPool.actionType,    
            ratioInfo.oserviceFeePercent
        );
        return true;
    }

    function redeem(uint orderID, bool withdrawType) public swithOn returns(bool){

        require(userData[msg.sender].length > 0,"cannot find this user from contract for redeem");
        //calculate the rules
        userOrder memory uOrder = userData[msg.sender][orderID];

        require(minePoolMap[uOrder.poolID].isEntity,"no pool can be found");
        
        uint curDayTime = convertToDayTime(block.timestamp);
        uint userCreateDayTime = convertToDayTime(uOrder.createTime);
        //currentTime - createTime
        uint curSubDayTime = curDayTime.sub(userCreateDayTime);

        require(userData[msg.sender][orderID].stopDayTime == 0,"you have redeem already");
        require(minePoolMap[uOrder.poolID].mPool.actionType == 1,"only support redeem");
        
        if (curSubDayTime < minePoolMap[uOrder.poolID].mPool.expireType){
            minePoolMap[uOrder.poolID].mPool.maxMiningPower.canSell = minePoolMap[uOrder.poolID].mPool.maxMiningPower.canSell.add(uOrder.cfltamount);
        }

        userData[msg.sender][orderID].cfltamount = 0;
        //if file pool no any check
        if (minePoolMap[uOrder.poolID].mPool.tokenAddress == _fltTokenContract && _fltTokenContract != address(0)){
            require(IERC20(_fltTokenContract).transfer(msg.sender,uOrder.amount),"failed to redeem from file pool in contract");
            // require(IERC20(_fltTokenContract).transferFrom(minePoolMap[uOrder.poolID].mPool.redeemFundAccount,msg.sender,uOrder.amount),"failed to redeem from file pool in contract");
            userData[msg.sender][orderID].stopDayTime = curDayTime;

            emit eventRedeem(msg.sender,orderID,0,false,_fltTokenContract);
            return true;
        }

        require(curSubDayTime >= minePoolMap[uOrder.poolID].mPool.lockInterval ,"not allow redeem within frozen days");
        
        require(uOrder.ratioInfo.admineUpdateTime > 0,"cannot redeem because no fee update");
        uint updateDayTime = convertToDayTime(userData[msg.sender][orderID].ratioInfo.admineUpdateTime);
        updateDayTime = updateDayTime.sub(userCreateDayTime);

        if(curSubDayTime >= minePoolMap[uOrder.poolID].mPool.lockInterval && curSubDayTime < minePoolMap[uOrder.poolID].mPool.expireType){
            require(updateDayTime >= minePoolMap[uOrder.poolID].mPool.lockInterval.sub(1) ,"not allow redeem because update fee has not come for LOCK days"); 
        }else if (curSubDayTime >= minePoolMap[uOrder.poolID].mPool.expireType){
            require(updateDayTime >= minePoolMap[uOrder.poolID].mPool.expireType.sub(1) ,"not allow redeem because update fee has not come for EXP days");    
        }

        uint256 lastForTransfer = 0 ;
        bool isExpire = false;
        uint256 diffGas = 0;
        if (curSubDayTime >= minePoolMap[uOrder.poolID].mPool.expireType){
            lastForTransfer = userData[msg.sender][orderID].amount;
            userData[msg.sender][orderID].stopDayTime = curSubDayTime;
            isExpire = true;

        }else{
            //((gasFIL /10**18 )* tokenRate / FILRate) * 10 ** tokenPrecision 
            uint256 partialCalc = uOrder.ratioInfo.oNeedToPayGasFee.mul(minePoolMap[uOrder.poolID].mPool.tokenRate).mul(10**minePoolMap[uOrder.poolID].mPool.tokenPrecision);
            diffGas = partialCalc.div(minePoolMap[uOrder.poolID].mPool.FILRate).div(10**18) ;
      
            if (userData[msg.sender][orderID].amount > diffGas ){
                lastForTransfer = userData[msg.sender][orderID].amount.sub(diffGas);
            }

            userData[msg.sender][orderID].stopDayTime = curDayTime;
        }

        require(lastForTransfer > 0,"not enough for paying for gas diff");
        address forEvent = address(0);
        if (withdrawType ){
            minePoolMap[uOrder.poolID].mPool.tokenInterface.transferFrom(minePoolMap[uOrder.poolID].mPool.redeemFundAccount,msg.sender,lastForTransfer);
            forEvent = minePoolMap[uOrder.poolID].mPool.tokenAddress;
        }else {
            uint256 remainPower =convertTokenToPower(userData[msg.sender][orderID].amount,uOrder.poolID) ;
            require(_fltTokenContract != address(0),"no flt contract in the system");
            require(IERC20(_fltTokenContract).transfer(msg.sender,remainPower),"failed to redeem from contract address");
            forEvent = _fltTokenContract;
        }

        emit eventRedeem(msg.sender,orderID,diffGas,isExpire,forEvent);
        return true;
    }

    function getProfit(uint plID,uint orderID) public swithOn returns ( bool ){
        require(userData[msg.sender].length > 0,"cannot find this user from contract for withdraw");
        require(userData[msg.sender][orderID].poolID == plID, "pool id does not match with current order");
        require(_filTokenContract != address(0),"has not set fil token contract");

        require(userData[msg.sender][orderID].ratioInfo.oActiveInterest > 0, "no TotalInterest for withdrawing");

        require(userData[msg.sender][orderID].ratioInfo.oActiveInterest > userData[msg.sender][orderID].ratioInfo.oHasReceiveInterest, "you have gotten all the interest about this order");

        uint256 interestShouldSend = userData[msg.sender][orderID].ratioInfo.oActiveInterest.sub(userData[msg.sender][orderID].ratioInfo.oHasReceiveInterest);

        require(IERC20(_filTokenContract).transferFrom(minePoolMap[plID].mPool.redeemFundAccount,msg.sender,interestShouldSend),"failed to withdraw profit for current");
        userData[msg.sender][orderID].ratioInfo.oHasReceiveInterest = userData[msg.sender][orderID].ratioInfo.oActiveInterest;

        emit eventWithDraw( msg.sender,plID,orderID,interestShouldSend);

        return true;

    }//end function

    //===================================admin operate==================================================

    //add contract to contract and also add pool amount 
    struct updateMineInput{
        uint        poolID;            
        address     contr;      
        address     redeemCon;             
        address     earlyRedeemFundAccount;    
        address     minerAccount;
        address     recievePaymentAccount;    
        uint        expiration;             

        uint256     maxMiningPower;         
        uint256     stakingPrice;            
 
        uint256     tokenRate;
        uint256     FILRate;
        uint        tokenPrecision;

        uint        actionType;
        uint256     miniPurchaseAmount;
        uint256     hasSoldOutToken;
        uint        lockInterval;
    }
    function updateMinePool(
        updateMineInput memory updateParas,
        uint256[] memory poolThredhold,
        uint[] memory serviceFeePercent
    ) public ownerAndAdmin swithOn returns (bool){
        //update the amount of a certain contract
        if (minePoolMap[updateParas.poolID].isEntity){
            //an old one
            require(isContract(updateParas.contr),"not the correct token contract address");
            if (updateParas.actionType > 0){
                require(updateParas.actionType == 1 || updateParas.actionType == 2,"need to set actionType correctly");
                minePoolMap[updateParas.poolID].mPool.actionType = updateParas.actionType;
            }

            if (updateParas.maxMiningPower > 0 ){
                minePoolMap[updateParas.poolID].mPool.maxMiningPower.canSell = updateParas.maxMiningPower; 
            }

            if (updateParas.expiration > 0){
                minePoolMap[updateParas.poolID].mPool.expireType = updateParas.expiration;
            }
            
            if (updateParas.stakingPrice > 0){
                minePoolMap[updateParas.poolID].mPool.stakingPrice = updateParas.stakingPrice;
            }

            if (updateParas.tokenRate > 0 ){
                minePoolMap[updateParas.poolID].mPool.tokenRate = updateParas.tokenRate;
            }

            if (updateParas.FILRate > 0 ){
                minePoolMap[updateParas.poolID].mPool.FILRate = updateParas.FILRate;
            }

            if (updateParas.tokenPrecision > 0 ){
                minePoolMap[updateParas.poolID].mPool.tokenPrecision = updateParas.tokenPrecision;
            }

            if (updateParas.miniPurchaseAmount > 0){
                minePoolMap[updateParas.poolID].mPool.miniPurchaseAmount = updateParas.miniPurchaseAmount;
            }

            if (updateParas.hasSoldOutToken > 0){
                minePoolMap[updateParas.poolID].mPool.hasSoldOutToken = updateParas.hasSoldOutToken;
            }

            if (updateParas.lockInterval > 0){
                minePoolMap[updateParas.poolID].mPool.lockInterval = updateParas.lockInterval;
            }

            if (updateParas.contr != address(0)){
                minePoolMap[updateParas.poolID].mPool.tokenAddress = updateParas.contr;
                minePoolMap[updateParas.poolID].mPool.tokenInterface = IERC20(minePoolMap[updateParas.poolID].mPool.tokenAddress);
            }
            
            if (updateParas.redeemCon != address(0)){
                minePoolMap[updateParas.poolID].mPool.redeemFundAccount = updateParas.redeemCon;
            }

            if (updateParas.earlyRedeemFundAccount != address(0)){
                minePoolMap[updateParas.poolID].mPool.earlyRedeemFundAccount = updateParas.earlyRedeemFundAccount;
            }
            
            if (updateParas.minerAccount != address(0)){
                minePoolMap[updateParas.poolID].mPool.minerAccount = updateParas.minerAccount;
            }            
            
            if (updateParas.recievePaymentAccount != address(0)){
                minePoolMap[updateParas.poolID].mPool.recievePaymentAccount = updateParas.recievePaymentAccount;
            }

            if (poolThredhold.length > 0){
                minePoolMap[updateParas.poolID].mPool.poolThredhold = poolThredhold;
            }

            if (serviceFeePercent.length > 0) {
                minePoolMap[updateParas.poolID].mPool.serviceFeePercent = serviceFeePercent;
            }
        }else{
            //a  new one 
            //need to set ratio and maxMiningPower
            require(updateParas.maxMiningPower>0,"this pool is new please add maxMiningPower for it");
            require(updateParas.contr != address(0),"this pool is new please add token adress for it");
            require(updateParas.stakingPrice > 0,"need to set stakingPrice ");
            // require(updateParas.serviceFeePercent > 0,"need to set serviceFeePercent ");

            require(updateParas.FILRate > 0,"need to set FILRate");
            require(updateParas.tokenRate > 0,"need to set tokenRate");
            require(updateParas.tokenPrecision > 0,"need to set tokenPrecision");

            require(updateParas.actionType == 1 || updateParas.actionType == 2,"need to set actionType correctly");
            require(updateParas.miniPurchaseAmount > 0,"need to set miniPurchaseAmount");
            require(poolThredhold.length > 0, "need to set levelThredhold for defi");
            minePoolMap[updateParas.poolID].mPool.poolThredhold = poolThredhold;

            require(serviceFeePercent.length > 0, "need to set levelServiceFeePercent for defi");
            minePoolMap[updateParas.poolID].mPool.serviceFeePercent = serviceFeePercent;

            // require(updateParas.lockInterval > 0,"need to set lockInterval");

            minePoolMap[updateParas.poolID].mPool.maxMiningPower.canSell = updateParas.maxMiningPower;
            minePoolMap[updateParas.poolID].mPool.stakingPrice = updateParas.stakingPrice; // fil / G 
            minePoolMap[updateParas.poolID].mPool.FILRate = updateParas.FILRate;
            minePoolMap[updateParas.poolID].mPool.tokenRate = updateParas.tokenRate;

            minePoolMap[updateParas.poolID].mPool.tokenAddress = updateParas.contr;
            minePoolMap[updateParas.poolID].mPool.tokenInterface = IERC20(updateParas.contr);
            minePoolMap[updateParas.poolID].isEntity = true;
            minePoolMap[updateParas.poolID].mPool.redeemFundAccount = updateParas.redeemCon;
            minePoolMap[updateParas.poolID].mPool.earlyRedeemFundAccount = updateParas.earlyRedeemFundAccount;
            minePoolMap[updateParas.poolID].mPool.expireType = updateParas.expiration;
            minePoolMap[updateParas.poolID].mPool.minerAccount = updateParas.minerAccount;
            minePoolMap[updateParas.poolID].mPool.recievePaymentAccount = updateParas.recievePaymentAccount;

            minePoolMap[updateParas.poolID].mPool.actionType = updateParas.actionType;
            minePoolMap[updateParas.poolID].mPool.miniPurchaseAmount = updateParas.miniPurchaseAmount;
            minePoolMap[updateParas.poolID].mPool.lockInterval = updateParas.lockInterval;
            minePoolMap[updateParas.poolID].mPool.tokenPrecision = updateParas.tokenPrecision;

        }
        return true;

    }

    struct updateUserOrderType {
        address userAddress;
        uint    orderID;
        uint    updateTime;
        uint256 activeInterest;
        uint256 FrozenInterest;
        uint256 needToPayGasFee;
    }

    function updateOrderFee(updateUserOrderType[] memory updateOrders) public ownerAndAdmin swithOn returns (bool){
        require(updateOrders.length > 0, "please input the right data for updateOrderFee");
        for (uint i = 0 ;i < updateOrders.length;i++){
   
            if (userData[updateOrders[i].userAddress].length > 0 && userData[updateOrders[i].userAddress][updateOrders[i].orderID].stopDayTime == 0 ){
                if (userData[updateOrders[i].userAddress][updateOrders[i].orderID].user == address(0)){
                    continue;
                }
       
                uint    cDayTime    = convertToDayTime(userData[updateOrders[i].userAddress][updateOrders[i].orderID].createTime);
                uint256 poolIDForex = userData[updateOrders[i].userAddress][updateOrders[i].orderID].poolID;
                if (updateOrders[i].updateTime > 0 && convertToDayTime(updateOrders[i].updateTime) < cDayTime.add(minePoolMap[poolIDForex].mPool.expireType).sub(1)){
                    userData[updateOrders[i].userAddress][updateOrders[i].orderID].ratioInfo.admineUpdateTime = updateOrders[i].updateTime;
                    userData[updateOrders[i].userAddress][updateOrders[i].orderID].ratioInfo.oActiveInterest = updateOrders[i].activeInterest;
                    userData[updateOrders[i].userAddress][updateOrders[i].orderID].ratioInfo.oFrozenInterest = updateOrders[i].FrozenInterest;
                    userData[updateOrders[i].userAddress][updateOrders[i].orderID].ratioInfo.oNeedToPayGasFee = updateOrders[i].needToPayGasFee;
                }
                else if (convertToDayTime(updateOrders[i].updateTime) >= cDayTime.add(minePoolMap[poolIDForex].mPool.expireType).sub(1)){

                    minePoolMap[poolIDForex].mPool.maxMiningPower.canSell = minePoolMap[poolIDForex].mPool.maxMiningPower.canSell.add(userData[updateOrders[i].userAddress][updateOrders[i].orderID].cfltamount);
                    userData[updateOrders[i].userAddress][updateOrders[i].orderID].cfltamount = 0;
                }
            }
        }

        return true;
    }

    //add flt token contract;
    function addFLTTokenContract(address fltToken) public ownerAndAdmin swithOn returns (bool){
        _fltTokenContract = fltToken;
        return true;
    }

    //add fil token contract for profit;
    function addFILTokenContract(address filTokenCon) public ownerAndAdmin swithOn returns (bool){
        _filTokenContract = filTokenCon;
        return true;
    }

    //pledge for active the selling power;
    // function inputFLTForActivePower(uint poolID,uint256 amount) public swithOn returns (bool){

    //     require(minePoolMap[poolID].isEntity,"current pool does not exist");

    //     require(msg.sender == minePoolMap[poolID].mPool.minerAccount,"user has not registered on the contract");
    //     require(_fltTokenContract != address(0),"need to set the file contract first");
    //     require(IERC20(_fltTokenContract).transferFrom(msg.sender,address(this),amount),"failed to transfer flt from user to contract");
    //     minePoolMap[poolID].mPool.maxMiningPower.canSell += amount;
    //     require(minePoolMap[poolID].mPool.maxMiningPower.canNotSell >= amount,"canNotSell not enough for activating");
    //     minePoolMap[poolID].mPool.maxMiningPower.canNotSell -= amount;
    //     return true;
    // }

    // //miner get tokens from certain pool with flt 
    function minerRetrieveToken(uint poolID,uint256 amount) public swithOn returns (bool){

        require(minePoolMap[poolID].isEntity,"current pool does not exist");

        require(msg.sender == minePoolMap[poolID].mPool.minerAccount,"user has not registered on the contract");

        require(minePoolMap[poolID].mPool.actionType == 1,"only staking pool can retrieval token ");

        require(amount <= minePoolMap[poolID].mPool.hasSoldOutToken,"not enough token to be back for miner");
        minePoolMap[poolID].mPool.hasSoldOutToken = minePoolMap[poolID].mPool.hasSoldOutToken.sub(amount);

        uint256 getPower = convertTokenToPower(amount,poolID);
        require(IERC20(_fltTokenContract).transferFrom(msg.sender,address(this),getPower),"failed to transfer file from user to contract");
        require(minePoolMap[poolID].mPool.tokenInterface.transfer(msg.sender,amount),"failed to transfer flt from user to contract");

        return true;        
    }

    //miner get tokens from certain pool with flt 
    // function minerRetrieveFILE(uint poolID,uint256 amount) public swithOn returns (bool){

    //     require(minePoolMap[poolID].isEntity,"current pool does not exist");

    //     require(msg.sender == minePoolMap[poolID].mPool.minerAccount,"user has not registered on the contract");

    //     require(minePoolMap[poolID].mPool.actionType == 1,"only staking pool can retrieval token ");

    //     require(minePoolMap[poolID].mPool.maxMiningPower.canSell >= amount,"not enough file to retrieve");

    //     minePoolMap[poolID].mPool.maxMiningPower.canSell = minePoolMap[poolID].mPool.maxMiningPower.canSell.sub(amount);

    //     require(IERC20(_fltTokenContract).transfer(msg.sender,amount),"failed to transfer FILE from contract");

    //     return true;

    // }

    //===================================tool function==================================================
    //check if address is contract
    function isContract(address _addr) view private  returns (bool){
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }

    //convert current time to day time
    function convertToDayTime(uint forConvertTime) internal returns (uint){
        return forConvertTime.add(timeZoneDiff).div(secondsForOneDay);
    }

    //check if it is Premium

    function checkisPremium(uint256 amount,uint256[] memory levelThredhold) internal returns (uint){
        
        uint isPrem = 0;
        for (uint i = 0;i <levelThredhold.length ; i++){
            // powerToToken = levelThredhold[i].mul(stakingPrice).mul(tokenToFILRate).div(10**18).div(10**18);
            if (amount >= levelThredhold[i]){
                isPrem = i;
            }
        }
        return isPrem;
    }

    //convert token to power
   
    function convertTokenToPower(uint256 amount, uint poolID) internal returns (uint256){
        // (( (tokenamount / (10**precision)) / (tokenRate / FILRate) ) / (stakingPrice / 10**18)) * (10**18)
        return amount.div(10**minePoolMap[poolID].mPool.tokenPrecision).mul(10**18).mul(10**18).mul(minePoolMap[poolID].mPool.FILRate).div(minePoolMap[poolID].mPool.tokenRate).div(minePoolMap[poolID].mPool.stakingPrice);
    }

    //adjust time for test
    // function adjustDayTime(uint dayTime, uint TimeZone) internal returns (bool){

    //     secondsForOneDay = dayTime;
    //     timeZoneDiff = TimeZone;
    //     return true ;
    // }

    // function adjustUserOrder(userOrder memory uOrder,uint orderID) public returns(bool){
    //     // userData[user][orderID].createTime = createTime;
    //     require(userData[uOrder.user].length >0 ,"no current user data");
    //     userData[uOrder.user][orderID] = uOrder;
    // }

}