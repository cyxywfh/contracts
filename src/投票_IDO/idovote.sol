// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;
import "./Ownable.sol";
import './IERC20.sol';
import './SafeMath.sol';
import "./SafeERC20.sol";

interface IDAOMintingPool {
    function getminerVeDao(address who,address lpToken,uint256 poolTypeId) external view returns(uint256);
    function getcalculatestakingAmount() external view returns(uint256);
}
/*
 * 投票 合约 
*/
contract idovoteContract is  Ownable {
    using SafeERC20 for IERC20;
    using SafeMath  for uint256;

    IERC20 public DAOToken;

    IDAOMintingPool  public daoMintingPool;
    uint256    private passingRate;         //通过率，默认80/100   
    uint256    private votingRatio;         //投票率，默认50/100  

    uint256    private minVoteVeDao;

    uint256    private totalStaking;
    //用户信息
    struct peopleInfo{
        uint256     timestamp;
        uint256     veDao;                  // veDao数量                
        bool        bVoted;                 //是否投过这个币的票
        uint256     weight;                 //权重：开始1，正确1次，加0.1，错误一次减0.1  : 默认10，每次增加1，最后/10   
        uint256     peopleVoteIncome;       //用户收益
        bool        bStatus;
    }
    mapping(address => mapping(address=> peopleInfo )) votePeople;
    mapping(address => uint256) voteWeight;
    mapping (address=>address) lastVoteAddress;
    mapping (address=>bool)  lastVoteStatus;
    mapping (address=>uint256) peopleTotalVoteIncome;
    //币投票信息
    struct vcoinInfo{
        uint256     timestamp;              //时间戳
        bool        bOpen;                  //是否开始
        uint256     cpassingRate;           //通过率
        uint256     cvotingRatio;           //投票率
        uint256     voteVeDao;              //总投票数
        uint256     pass;                   //通过数量
        uint256     deny;                   //拒绝数量
        bool        bEnd;                   //是否结束
        bool        bSuccessOrFail;         //通过还是失败
        uint256     daoVoteIncome;          //投票要分配的收益
    }
    mapping(address => vcoinInfo) votecoin;
    
    event SetpassingRate(address who,uint256 _passingRate);
    event SetvotingRatio(address who,uint256 _votingRatio);
    event Vote(address who, address coinAddress,uint256 poolTypeId,bool bStatus);
    event SetVoteCoinEnd(address who,address coinAddress);
    event SetDaoVoteIncome(address who,address coinAddress,uint256 amount);
    event TokeoutVoteIncome(address who,uint256 peopleVoteIncome);



    constructor(IERC20 _DAOToken,IDAOMintingPool _IDAOMintingPool){
        initializeOwner();
        DAOToken            = _DAOToken;
        daoMintingPool = _IDAOMintingPool;
        passingRate = 80;
        votingRatio = 50;
    }
    //设定矿池合约地址
    function setdaoMintingPool(address poolAddr) public onlyOwner {
        require(poolAddr != address(0));
        daoMintingPool = IDAOMintingPool(poolAddr);
    }
    //获取矿池地址
    function getdaoMintingPool() public view returns(address){
        return address(daoMintingPool);
    }
    //设定通过率
    function setpassingRate(uint256 _passingRate) public onlyOwner returns(uint256){
        require(_passingRate>0);
        passingRate = _passingRate;
        emit SetpassingRate(msg.sender,_passingRate);
        return _passingRate;
    }
    //获取通过率
    function getpassingRate() public view returns(uint256){
        return passingRate;
    }
    //设定投票率
    function setvotingRatio(uint256 _votingRatio) public onlyOwner returns(uint256){
        require(_votingRatio>0);
        votingRatio = _votingRatio;
        emit SetvotingRatio(msg.sender,_votingRatio);
        return _votingRatio;
    }
    //获取投票率
    function getvotingRatio() public view returns(uint256){
        return votingRatio;
    }
    //获取币投票信息
    function getvotecoin(address coinAddress) public view returns(vcoinInfo memory){
        require(coinAddress != address(0));
        return votecoin[coinAddress];
    }
    //投票
    //下次投票后，才结算上次投票的收益
    function vote(address coinAddress,uint256 poolTypeId,bool bStatus) public returns(bool) 
    {
        require(coinAddress != address(0));
        require(daoMintingPool.getminerVeDao(msg.sender,address(DAOToken), poolTypeId) >0);
        require(votePeople[msg.sender][coinAddress].bVoted == false);
        require(lastVoteAddress[msg.sender] != coinAddress); //投过后，就不允许再次投票
        
        peopleInfo memory newpeopleInfo = peopleInfo({
            timestamp:          block.timestamp,
            veDao:              daoMintingPool.getminerVeDao(msg.sender,address(DAOToken), poolTypeId),
            bVoted:             true,
            weight:             votePeople[msg.sender][coinAddress].weight,
            peopleVoteIncome:   votePeople[msg.sender][coinAddress].peopleVoteIncome,
            bStatus:            bStatus
        });

        votePeople[msg.sender][coinAddress] =  newpeopleInfo;  
        bool isOk; 
        if( lastVoteAddress[msg.sender] == address(0) )
        {
            votePeople[msg.sender][coinAddress].weight = 10 ; //此处 乘于一个 参数  220425
        }
        else
        {
            isOk = lastVoteStatus[msg.sender] == votecoin[lastVoteAddress[msg.sender]].bSuccessOrFail?true:false;
            if(isOk)
            {
                votePeople[msg.sender][coinAddress].weight = (votePeople[msg.sender][coinAddress].weight).add(1);
                //结算投票后收益
                uint256 peopleVoteIncome  = votePeople[msg.sender][coinAddress].veDao.mul(votePeople[msg.sender][coinAddress].weight);
                peopleVoteIncome = peopleVoteIncome.div(10);
                
                 if( lastVoteStatus[msg.sender] ){
                        peopleVoteIncome = peopleVoteIncome.div(votecoin[coinAddress].pass+daoMintingPool.getminerVeDao(msg.sender,address(DAOToken), poolTypeId));
                }else{
                        peopleVoteIncome = peopleVoteIncome.div(votecoin[coinAddress].deny+daoMintingPool.getminerVeDao(msg.sender,address(DAOToken), poolTypeId));
                }
                votePeople[msg.sender][coinAddress].peopleVoteIncome = peopleVoteIncome;
                //累计用户总投票收益
                peopleTotalVoteIncome[msg.sender] = peopleTotalVoteIncome[msg.sender].add(peopleVoteIncome);

            }else{
                votePeople[msg.sender][coinAddress].weight = (votePeople[msg.sender][coinAddress].weight).sub(1);
            }  
        }    
        //voteVeDao 投票总量
        uint256 voteVeDao = votePeople[msg.sender][coinAddress].veDao;
        voteVeDao = voteVeDao.add(votePeople[msg.sender][coinAddress].veDao.mul(votePeople[msg.sender][coinAddress].weight).div(10));

        vcoinInfo memory newvcoinInfo = vcoinInfo({
            timestamp:          block.timestamp,
            bOpen:              true,
            cpassingRate:       votecoin[coinAddress].cpassingRate,
            cvotingRatio:       votecoin[coinAddress].cvotingRatio,
            pass:               votecoin[coinAddress].pass,
            deny:               votecoin[coinAddress].deny,
            voteVeDao:          voteVeDao,
            bEnd:               votecoin[coinAddress].bEnd,
            bSuccessOrFail:     votecoin[coinAddress].bSuccessOrFail,
            daoVoteIncome:      votecoin[coinAddress].daoVoteIncome
        });
        votecoin[coinAddress] = newvcoinInfo;
        uint256 weight = votePeople[msg.sender][coinAddress].weight;
        if(bStatus){
            votecoin[coinAddress].pass = votecoin[coinAddress].pass.add(voteVeDao.mul(weight).div(10));
        }
        else{
            votecoin[coinAddress].deny = votecoin[coinAddress].deny.add(voteVeDao.mul(weight).div(10));
        }
        totalStaking = daoMintingPool.getcalculatestakingAmount();
        votecoin[coinAddress].cpassingRate = votecoin[coinAddress].pass.mul(100).div( votecoin[coinAddress].pass.add(votecoin[coinAddress].deny));
        votecoin[coinAddress].cvotingRatio = votecoin[coinAddress].voteVeDao.mul(100).div(totalStaking);


        lastVoteAddress[msg.sender] = coinAddress;  //记录这次投票地址
        lastVoteStatus[msg.sender] = bStatus;
        emit Vote(msg.sender,coinAddress,poolTypeId,bStatus);
        return true;
    }
    //管理员设定否票结束
    function setVoteCoinEnd(address coinAddress) public onlyOwner returns(bool){
        require(votecoin[coinAddress].bOpen);
        votecoin[coinAddress].bOpen = false;
        votecoin[coinAddress].bEnd = true;
        votecoin[coinAddress].timestamp = block.timestamp; 
        if(votecoin[coinAddress].cpassingRate >= passingRate &&  votecoin[coinAddress].cvotingRatio >= votingRatio ){
             votecoin[coinAddress].bSuccessOrFail = true;
        }
        else{
             votecoin[coinAddress].bSuccessOrFail = false;
        }
        emit SetVoteCoinEnd(msg.sender,coinAddress);
        return true;
    }
    //管理员设定投票分配收益
    function setDaoVoteIncome(address coinAddress,uint256 amount) public onlyOwner payable returns(address, uint256){
        require(votecoin[coinAddress].timestamp != 0);
        require(amount>0);
        votecoin[coinAddress].daoVoteIncome = amount;
        DAOToken.safeTransferFrom(msg.sender, address(this), amount);  
        emit SetDaoVoteIncome(msg.sender,coinAddress,amount);
        return (coinAddress,amount);
    }
    //查看用户投票收益，
    function viewDaoVoteIncome() public view returns(uint256) {
        return peopleTotalVoteIncome[msg.sender];        
    }
    //提取用户投票收益
    function tokeoutVoteIncome() public returns (uint256){
        require(peopleTotalVoteIncome[msg.sender] > 0 );
        uint256 peopleVoteIncome = peopleTotalVoteIncome[msg.sender];
        peopleTotalVoteIncome[msg.sender] = 0;
        IERC20(DAOToken).safeTransfer(msg.sender,peopleVoteIncome);
        emit TokeoutVoteIncome(msg.sender,peopleVoteIncome);
        return peopleVoteIncome;
    }

}
