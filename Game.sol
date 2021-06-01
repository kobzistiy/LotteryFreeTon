pragma ton-solidity ^0.42.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;

import 'interfaces/LotteryInterface.sol';
import 'utils/MessageUtil.sol';
import 'utils/TextUtil.sol';

struct GameInfo {
    uint128 depositAmount;
    uint128 rewardAmount;
    uint64  depositCount;
    uint32  minCount;
    uint32  gameChance;
}

/**
 * Error codes
 *     • 100 — Method only for root
 */
contract Game is MessageUtil,
                  TextUtil {
    /*************
     * CONSTANTS *
     *************/


    /**************
     * STRUCTURES *
     **************/


    /*************
     * VARIABLES *
     *************/
    address private _rootAddress;
    mapping(address => uint128) _deposits;
    uint128   private _depositAmount;
    uint64    private _depositCount;
    uint32    private _minCount;
    uint32    private _gameChance;

    /*************
     * MODIFIERS *
     *************/
    modifier accept {
        tvm.accept();
        _;
    }

    modifier onlyRoot {
        require(msg.sender == _rootAddress, 100, "Method only for root");
        _;
    }

    /***************
     * CONSTRUCTOR *
     ***************/
    constructor(
        address rootAddress,
        uint32 minCount,
        uint32 gameChance
    ) public {
        _rootAddress = rootAddress;
        _minCount = minCount;
        _gameChance = gameChance;
        _saveText();
        LotteryInterface(_rootAddress).returnChange{value: 0, flag: 64}();
    }



    /***********
     * GETTERS *
     ***********/
    function getRootAddress() public view returns (address rootAddress) { return _rootAddress; }
    function getInfo() public view returns (GameInfo info) { 
      return GameInfo(
        _depositAmount,
        address(this).balance,
        _depositCount,
        _minCount,
        _gameChance
      );
    }

    function getDeposits() public view returns (
        address[] owners,
        uint128[] deposits,
        uint64    totalLength
    ) {
        optional(address, uint128) client = _deposits.min();
        while (client.hasValue()) {
            (address addr, uint128 reward) = client.get();
            owners.push(addr);
            deposits.push(reward);
            client = _deposits.next(addr);
        }
        return (owners, deposits, _depositCount);
    }



    /************
     * EXTERNAL *
     ************/
    function deposit(address sender, uint128 reward) external onlyRoot {
        if (_deposits.exists(sender)) {
          _deposits[sender] += reward;
        } else {
          _deposits[sender] = reward;
          _depositCount++;
        }
        _depositAmount += reward;
        if (_depositCount >= _minCount) {
         uint32 chance = rnd.next(uint32(100));
          if (chance < _gameChance) {
            int rndReward = rnd.next(_depositAmount);
            optional(address, uint128) client = _deposits.min();
            while (client.hasValue()) {
                (address addr, uint128 value) = client.get();
                rndReward -= value;
                if (rndReward <= 0) {
                  LotteryInterface(_rootAddress).onGameOver{value: 0.1e9, flag: 1}(addr, address(this).balance, _depositAmount, _depositCount);
                  addr.transfer({value: 0, flag: 128, body: _getTransferBody(TEXT_REWARD)});
                  break;
                }
                client = _deposits.next(addr);
            }
          }
        }
    }


    /***********
     * RECEIVE *
     ***********/

    /***********
     * PRIVATE *
     ***********/


}