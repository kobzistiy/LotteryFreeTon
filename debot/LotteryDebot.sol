pragma ton-solidity >=0.42.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;

import "Debot.sol";
import "Terminal.sol";
import "Menu.sol";
import "AddressInput.sol";
import "AmountInput.sol";
import "ConfirmInput.sol";
import "Sdk.sol";
import "../modifiers/Upgradable.sol";

interface IMultisig {
    function submitTransaction(
        address  dest,
        uint128 value,
        bool bounce,
        bool allBalance,
        TvmCell payload)
    external returns (uint64 transId);
}

abstract contract Utility {
    function tonsToStr(uint128 nanotons) internal pure returns (string) {
        (uint64 dec, uint64 float) = _tokens(nanotons);
        string floatStr = format("{}", float);
        while (floatStr.byteLength() < 9) {
            floatStr = "0" + floatStr;
        }
        return format("{}.{}", dec, floatStr);
    }

    function _tokens(uint128 nanotokens) internal pure returns (uint64, uint64) {
        uint64 decimal = uint64(nanotokens / 1e9);
        uint64 float = uint64(nanotokens - (decimal * 1e9));
        return (decimal, float);
    }
}

struct LotteryInfo {
    string  version;
    address usersStorage;
    address gamesHistory;
    address gameAddress;
}

struct GameInfo {
    uint128 depositAmount;
    uint128 rewardAmount;
    uint64  depositCount;
    uint32  minCount;
    uint32  gameChance;
}

interface IMsig {
   function sendTransaction(address dest, uint128 value, bool bounce, uint8 flags, TvmCell payload  ) external;
}


interface ILottery {
    function getInfo() external returns (LotteryInfo info);
    function getGameAddress() external returns (address gameAddress);
}

interface IUsersStorage {
    function getUsersCount() external returns (uint64 usersCount);
    function getUsers(uint64 offset, uint64 limit) external returns (
        address[] users,
        uint64[]  userIds,
        uint64[]  referals,
        uint64    totalLength
    );
}

interface IGamesHistory {
    function getGamesCount() external returns (uint64 gamesCount);
    function getGames(uint64 offset, uint64 limit) external returns (
        address[] games,
        address[] winners,
        uint128[] rewards,
        uint128[] amounts,
        uint64[]  counts,
        uint64    totalLength
    );
}

interface IGame {
   function getInfo() external returns (GameInfo info);
   function getDeposits() external returns (
        address[] owners,
        uint128[] deposits,
        uint64    totalLength
    );
}


contract LotteryDebot is Debot, Upgradable, Utility {
    bytes m_icon;

    string  private _version;
    uint32  private constant HISTORY_COUNT    = 3;
    string  private constant RULES_TEXT = "Lottery is a gambling game based on Free Ton smart contracts.\n\n\
There are only two basic rules in the game. To start the draw, the minimum required number of bets must be made. After that, with each next bet, the game round will end with a small probability.\n\n\
The winner is chosen at random. The larger the amount a player has deposited, the more chances he has to win. Several bets can be made within the same round.\n\n\
In the menu, you can find buttons for viewing the history of games and the current state of the round. You can also see the bets made in the current round.";

    address       m_address;  // contract address
    address       m_wallet;  // User wallet address
    address       m_TempAddress;  //
    LotteryInfo   m_lotteryInfo;  //
    GameInfo      m_gameInfo;     //
    uint64        m_gamesCount;   //
    uint64        m_usersCount;   //
    uint32        m_checkAnswerId;
    uint128       m_tons;
    

    function setIcon(bytes icon) public {
        require(msg.pubkey() == tvm.pubkey(), 100);
        tvm.accept();
        m_icon = icon;
    }

    function setLotteryAddress(address lotteryAddress) public {
        require(msg.pubkey() == tvm.pubkey(), 100);
        tvm.accept();
        m_address = lotteryAddress;
    }

    function onError(uint32 sdkError, uint32 exitCode) public {
        Terminal.print(0, format("Operation failed. sdkError {}, exitCode {}", sdkError, exitCode));
        _menu();
    }

    function start() public override {
        _start();
    }

    function _start() private {
        m_checkAnswerId = tvm.functionId(onAddressInput);
        AddressInput.get(tvm.functionId(startChecks), "Which wallet do you want to work with?");
    }
    
    function onAddressInput(uint128 nanotokens) public {
        nanotokens = nanotokens;
        m_wallet = m_TempAddress;
        _getLotteryInfo();
    }

    /// @notice Returns Metadata about DeBot.
    function getDebotInfo() public functionID(0xDEB) override view returns(
        string name, string version, string publisher, string key, string author,
        address support, string hello, string language, string dabi, bytes icon
    ) {
        name = "Lottery DeBot";
        version = _version;
        publisher = "KOBA Labs";
        key = "Lottery game";
        author = "KOBA";
        support = address.makeAddrStd(0, 0x5631c6c20acf4d015ac6580cc7cbf832e3492a7d24bf32b946934b46e3ab863c);
        hello = "Hi, i'm a Lottery DeBot.\n";
        hello.append(RULES_TEXT);
        language = "en";
        dabi = m_debotAbi.get();
        icon = m_icon;
    }

    function getRequiredInterfaces() public view override returns (uint256[] interfaces) {
        return [ Terminal.ID, Menu.ID, AddressInput.ID, ConfirmInput.ID ];
    }

    function startChecks(address value) public {
        m_TempAddress = value;
        Sdk.getAccountType(tvm.functionId(checkStatus), value);
	  }

    function checkStatus(int8 acc_type) public {
        if (!_checkActiveStatus(acc_type, "Wallet")) {
            _start();
            return;
        }
        Sdk.getBalance(m_checkAnswerId, m_TempAddress);
    }

    function _checkActiveStatus(int8 acc_type, string obj) private returns (bool) {
        if (acc_type == -1)  {
            Terminal.print(0, obj + " is inactive");
            return false;
        }
        if (acc_type == 0) {
            Terminal.print(0, obj + " is uninitialized");
            return false;
        }
        if (acc_type == 2) {
            Terminal.print(0, obj + " is frozen");
            return false;
        }
        return true;
    }

//////////////////////// Lottery Info

    function getLotteryInfo(uint32 index) public view {
        index = index;
        _getLotteryInfo();
    }

    function _getLotteryInfo() public view {
        optional(uint256) pubkey;
        ILottery(m_address).getInfo{
            abiVer: 2,
            extMsg: true,
            sign: false,
            pubkey: pubkey,
            time: uint64(now),
            expire: 0,
            callbackId: tvm.functionId(setLotteryInfo),
            onErrorId: tvm.functionId(onError)
        }();
    }

    function setLotteryInfo(LotteryInfo info) public {
        m_lotteryInfo = info;
        _getUsersCount();
    }

    function _getUsersCount() public view {
        optional(uint256) pubkey;
        IUsersStorage(m_lotteryInfo.usersStorage).getUsersCount{
            abiVer: 2,
            extMsg: true,
            sign: false,
            pubkey: pubkey,
            time: uint64(now),
            expire: 0,
            callbackId: tvm.functionId(setUsersCount),
            onErrorId: tvm.functionId(onError)
        }();
    }

    function setUsersCount(uint64 usersCount) public {
        m_usersCount = usersCount;
        _getGamesCount();
    }

    function _getGamesCount() public view {
        optional(uint256) pubkey;
        IGamesHistory(m_lotteryInfo.gamesHistory).getGamesCount{
            abiVer: 2,
            extMsg: true,
            sign: false,
            pubkey: pubkey,
            time: uint64(now),
            expire: 0,
            callbackId: tvm.functionId(setGamesCount),
            onErrorId: tvm.functionId(onError)
        }();
    }

    function setGamesCount(uint64 gamesCount) public {
        m_gamesCount = gamesCount;
        _menu();
    }

//////////////////////// Games History

    function getGamesHistory(uint32 index) public view {
        index = index;
        _getGamesCountForHistory();
    }
    
    function _getGamesCountForHistory() public view {
        optional(uint256) pubkey;
        IGamesHistory(m_lotteryInfo.gamesHistory).getGamesCount{
            abiVer: 2,
            extMsg: true,
            sign: false,
            pubkey: pubkey,
            time: uint64(now),
            expire: 0,
            callbackId: tvm.functionId(_getGamesHistory),
            onErrorId: tvm.functionId(onError)
        }();
    }

    function _getGamesHistory(uint64 gamesCount) public {
        optional(uint256) pubkey;
        m_gamesCount = gamesCount;
        IGamesHistory(m_lotteryInfo.gamesHistory).getGames{
            abiVer: 2,
            extMsg: true,
            sign: false,
            pubkey: pubkey,
            time: uint64(now),
            expire: 0,
            callbackId: tvm.functionId(setGamesHistory),
            onErrorId: tvm.functionId(onError)
        }(m_gamesCount-HISTORY_COUNT, HISTORY_COUNT);
    }

    function setGamesHistory(
        address[] games,
        address[] winners,
        uint128[] rewards,
        uint128[] amounts,
        uint64[]  counts,
        uint64    totalLength
    ) public {
        string Msg = format("Games (TOP-{}):\n\n", HISTORY_COUNT);
        for (uint64 i = 0; i < totalLength; i++) {
            Msg.append(format(
"Game   Address: {}\n\
Winner Address: {}\n\
Reward amount: {}, Deposit amount: {}, Deposits count: {}\n\n",
            games[i], winners[i], tonsToStr(rewards[i]), tonsToStr(amounts[i]), counts[i]));
        }
        Terminal.print(0, Msg);
        _menu();
    }


//////////////////////// Games Info

    function getGameInfo(uint32 index) public {
        index = index;
        m_checkAnswerId = tvm.functionId(_getGameInfo);
        _getGameAddress(tvm.functionId(startChecks));
    }

    function _getGameInfo(uint128 nanotokens) public view {
        nanotokens = nanotokens;
        optional(uint256) pubkey;
        IGame(m_TempAddress).getInfo{
            abiVer: 2,
            extMsg: true,
            sign: false,
            pubkey: pubkey,
            time: uint64(now),
            expire: 0,
            callbackId: tvm.functionId(setGameInfo),
            onErrorId: tvm.functionId(onError)
        }();
    }

    function setGameInfo(GameInfo info) public {
        m_gameInfo = info;
        Terminal.print(0, format( 
"Actual game round info:\n\
Deposit amount: {}\n\
Reward amount: {}\n\
Bets count: {}\n\n\
Terms of play:\n\
Minimum bets for start round: {}\n\
Сhance of round ending after bet: {}%\n\n\
Address actual game (no send tokens!):\n\
{}",
            tonsToStr(m_gameInfo.rewardAmount),
            tonsToStr(m_gameInfo.depositAmount),
            m_gameInfo.depositCount,
            m_gameInfo.minCount,
            m_gameInfo.gameChance,
            m_lotteryInfo.gameAddress
        ));
        _menu();
    }

//////////////////////// Games Deposits

    function getGameDeposits(uint32 index) public {
        index = index;
        m_checkAnswerId = tvm.functionId(_getGameDeposits);
        _getGameAddress(tvm.functionId(startChecks));
    }

    function _getGameDeposits(uint128 nanotokens) public view {
        nanotokens = nanotokens;
        optional(uint256) pubkey;
        IGame(m_TempAddress).getDeposits{
            abiVer: 2,
            extMsg: true,
            sign: false,
            pubkey: pubkey,
            time: uint64(now),
            expire: 0,
            callbackId: tvm.functionId(setGameDeposits),
            onErrorId: tvm.functionId(onError)
        }();
    }

    function setGameDeposits(
        address[] owners,
        uint128[] deposits,
        uint64    totalLength
    ) public {
        string Msg = "Deposits: \n";
        for (uint64 i = 0; i < totalLength; i++) {
            Msg.append(format(
"{}. {} - {}\n",
            i+1, owners[i], tonsToStr(deposits[i])));
        }
        if (totalLength == 0) {
          Msg.append("There are no bets in the current round yet");
        }
        Terminal.print(0, Msg);
        _menu();
    }

//////////////////////// Place Bet

    function placeBet(uint32 index) public {
        index = index;
        AmountInput.get(tvm.functionId(setTons), "How many tokens to send?", 9, 1e9, 100e9);
    }

    function setTons(uint128 value) public {
        m_tons = value;
        string fmt = format("Transaction details:\nRecipient: {}.\nAmount: {} tokens.\nConfirm?", m_address, tonsToStr(value));
        ConfirmInput.get(tvm.functionId(submitTransaction), fmt);
    }

    function onSuccessTransaction(uint64 transId) public {
        transId = transId;
        Terminal.print(0, "The transaction was successful. In a few seconds, the information of the current round will be updated.");
        _menu();
    }

    function submitTransaction(bool value) public {
        if (!value) {
            Terminal.print(0, "Ok, maybe next time.");
            _menu();
            return;
        }
        TvmCell empty;
        optional(uint256) pubkey = 0;
        IMultisig(m_wallet).submitTransaction{
            abiVer: 2,
            extMsg: true,
            sign: true,
            pubkey: pubkey,
            time: uint64(now),
            expire: 0,
            callbackId: tvm.functionId(onSuccessTransaction),
            onErrorId: tvm.functionId(onError)
        }(m_address, m_tons, false, false, empty);
    }

//////////////////////// Service

    function _getGameAddress(uint32 answerId) public view {
        optional(uint256) pubkey;
        ILottery(m_address).getGameAddress{
            abiVer: 2,
            extMsg: true,
            sign: false,
            pubkey: pubkey,
            time: uint64(now),
            expire: 0,
            callbackId: answerId,
            onErrorId: tvm.functionId(onError)
        }();
    }

    function getGameRules(uint32 index) public {
        index = index;
        Terminal.print(0, RULES_TEXT);
        _menu();
    }


//////////////////////// MENU

    function _menu() public {
        string sep = '----------------------------------------';
        Menu.select(
            format(
"Game version: {}({})\n\
Common user count: {}\n\
Number of games completed: {}\n\n\
Main address for send tokens: \
{}",
              _version, m_lotteryInfo.version,
              m_usersCount,
              m_gamesCount,
              m_address
            ),
            sep,
            [
                MenuItem("Read game rules","",tvm.functionId(getGameRules)),
                MenuItem("Update lottery info","",tvm.functionId(getLotteryInfo)),
                MenuItem("Get games history","",tvm.functionId(getGamesHistory)),
                MenuItem("Actual game info","",tvm.functionId(getGameInfo)),
                MenuItem("Actual game deposits","",tvm.functionId(getGameDeposits)),
                MenuItem("Place a bet","",tvm.functionId(placeBet))
            ]
        );
    }


    function onCodeUpgrade() internal override {
        tvm.resetStorage();
        setVer();
    }
    
    function setVer() private {
        _version = "0.1.4";
    }

}
