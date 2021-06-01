pragma ton-solidity ^0.42.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;

import 'Game.sol';
import 'GamesHistory.sol';
import 'UsersStorage.sol';
import 'interfaces/LotteryInterface.sol';
import 'utils/HexadecimalNumberUtil.sol';
import 'utils/MessageUtil.sol';
import 'utils/TextUtil.sol';
import 'modifiers/TransferValueModifier.sol';
import 'modifiers/Upgradable.sol';

struct LotteryInfo {
    string  version;
    address usersStorage;
    address gamesHistory;
    address gameAddress;
}


/**
 * Error codes
 *     • 100 — Method only for the owner
 *     • 101 — Method only for game
 *     • 102 — Method only for storage
 *     • 200 — Invalid deposit value
 *     • 201 — New game creating
 */
contract Lottery is LotteryInterface, 
                  Upgradable,
                  HexadecimalNumberUtil,
                  TransferValueModifier,
                  MessageUtil,
                  TextUtil {
    /*************
     * CONSTANTS *
     *************/
    uint16  private constant MULTIPLY_DIVIDER          = 1e3;
    uint16  private constant REGULAR_REWARD            = 0.90e3; // 90%
    uint16  private constant REFERRER_PART             = 0.05e3; // 5%
    uint128 private constant DEPLOY_VALUE              = 0.10 ton;
    uint128 private constant STORAGE_TRANSFER          = 0.10 ton;
    uint128 private constant MIN_DEPOSIT               = 1.00 ton;
    uint128 private constant MINIMUM_BALANCE           = 1.00 ton;
    uint128 private constant MINIMUM_REWARD            = 0.50 ton;

    /*************
     * VARIABLES *
     *************/
    TvmCell   private _codeGame;
    address   private _usersStorage;
    address   private _gamesHistory;
    address   private _gameAddress;
    address   private _ownerAddress;
    bool      private _gameReady;
    string    private _version;

    uint32    private _gameChance; //%
    uint32    private _minCount;

    uint64    static  _seed; 

    /*************
     * MODIFIERS *
     *************/
    modifier accept {
        tvm.accept();
        _;
    }

    modifier onlyOwner {
        require(msg.pubkey() == tvm.pubkey(), 100, "Method only for owner");
        _;
    }

    modifier onlyGame {
        require(msg.sender == _gameAddress, 101, "Method only for game");
        _;
    }

    modifier onlyStorage {
        require(msg.sender == _usersStorage, 102, "Method only for storage");
        _;
    }

    modifier validDeposit() {
        require(msg.value >= MIN_DEPOSIT, 200, "Invalid deposit value");
        _;
    }

    modifier gameReady() {
        require(_gameReady, 201, "New game creating");
        _;
    }

    /***************
     * CONSTRUCTOR *
     ***************/
    constructor(TvmCell gameCode, address ownerAddress, address usersStorage, address gamesHistory, uint32 gameChance, uint32 minCount) public accept {
        _codeGame = gameCode;
        _ownerAddress = ownerAddress;
        _usersStorage = usersStorage;
        _gamesHistory = gamesHistory;
        _gameChance = gameChance;
        _minCount = minCount;
        _saveText();
        deployGame();
        setVer();
    }

   /***********
     * GETTERS *
     ***********/
    function getInfo() public view returns (LotteryInfo info) { return LotteryInfo(_version, _usersStorage, _gamesHistory, _gameAddress); }
    function getVersion() public view returns (string version) { return _version; }
    function getGameAddress() public view returns (address gameAddress) { return _gameAddress; }

    function deployGame() private accept {
        TvmCell storageData = tvm.buildEmptyData(rnd.next());
        TvmCell stateInit = tvm.buildStateInit(_codeGame, storageData);
        _gameAddress = new Game{stateInit: stateInit, value: DEPLOY_VALUE, flag: 0}(address(this), _minCount, _gameChance);
        _gameReady = true;
    }

    /***********************
     * PUBLIC * ONLY OWNER *
     ***********************/

    function sendTransaction(address destination, uint128 value) public pure onlyOwner accept validTransferValue(value) {
        destination.transfer(value);
    }

    function setGameCode(TvmCell gameCode) public onlyOwner accept returns (bool res) {
        _codeGame = gameCode;
        return true;
    }
    
    function setParams(address ownerAddress, address usersStorage, address gamesHistory, uint32 gameChance, uint32 minCount) public onlyOwner accept returns (bool res) {
        _ownerAddress = ownerAddress;
        _usersStorage = usersStorage;
        _gamesHistory = gamesHistory;
        _gameChance = gameChance;
        _minCount = minCount;
        return true;
    }
    

    /************
     * EXTERNAL *
     ************/
    function onReceiveReferralAddress(address sender, uint128 value, address referral, uint64 userId) external override onlyStorage {
        if (userId > 0) {
          _newUserConfirmation(sender, userId);
        }
        uint128 reward = _getRegularReward(value);
        if (referral != sender) {
          uint128 referralPayout = _getReferralPayout(value);
          reward -= referralPayout;
          referral.transfer({value: referralPayout, flag: 1, body: _getTransferBody(TEXT_REFERRAL)});
        }
        sender.transfer({value: 0, flag: 1, body: _getTransferBody(TEXT_OK)});
        Game(_gameAddress).deposit{value: reward, flag: 1}(sender, value);
    }

    function onGameOver(address winner, uint128 reward, uint128 amount, uint64 count) external override onlyGame {
      _gameReady = false;
      GamesHistory(_gamesHistory).save{value: STORAGE_TRANSFER}(_gameAddress, winner, reward, amount, count);
      deployGame();
      uint128 rewardOwner = _getRewardValue();
      if (rewardOwner > 0) _ownerAddress.transfer({value: rewardOwner, flag: 0, body: _getTransferBody(TEXT_REWARD)});
    }

    function returnChange() external override {
      //Return of change
    }

    /***********
     * RECEIVE *
     ***********/
    receive() external view validDeposit gameReady {
        address sender = msg.sender;
        uint128 value = uint128(msg.value);
        uint8[] message = _readMessage(msg.data);

        if (_messageIsEqual(message, TEXT_BANK))
          sender.transfer({value: 0, flag: 1, body: _getTransferBody(TEXT_OK)});
        else {
          uint64 referralId = 0;
          if (_messageIsHexadecimalNumber(message)) {
            referralId = _readHexadecimalNumberFromMessage(message);
          }
          UsersStorage(_usersStorage).dispatchWithReferral{value: STORAGE_TRANSFER}(sender, value, referralId);
        }
    }


    /***********
     * PRIVATE *
     ***********/

    function _newUserConfirmation(address sender, uint64 userId) private pure {
        uint8[] message = _getMessageWithHexadecimalNumber(userId);
        sender.transfer({value: 0, flag: 1, body: _getTransferBody(message)});
    }

    function _getRegularReward(uint128 value) internal pure returns (uint128) {
        return math.muldiv(value, REGULAR_REWARD, MULTIPLY_DIVIDER);
    }

    function _getReferralPayout(uint128 value) internal pure returns (uint128) {
        return math.muldiv(value, REFERRER_PART, MULTIPLY_DIVIDER);
    }

    function onCodeUpgrade() internal override {
        setVer();
    }
    
    function setVer() private {
        _version = "0.1.4";
    }

    function _getRewardValue() private pure returns (uint128) {
        uint128 balance = address(this).balance;
        return balance > (MINIMUM_BALANCE + MINIMUM_REWARD) ? balance - MINIMUM_BALANCE : 0;
    }
}