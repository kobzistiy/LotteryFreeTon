pragma ton-solidity ^0.42.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;

import 'interfaces/LotteryInterface.sol';
import 'utils/ArrayUtil.sol';

/**
 * Error codes
 *     • 100 — Method only for owner
 *     • 101 — Method only for root
 */
contract GamesHistory is ArrayUtil {
                  
    /*************
     * CONSTANTS *
     *************/

    /**************
     * STRUCTURES *
     **************/
    struct GameInfo {
        address game;
        address winner;
        uint128 reward;
        uint128 amount;
        uint64  count;
    }

    /*************
     * VARIABLES *
     *************/
    address   private _rootAddress;
    GameInfo[] private _games;

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

    modifier onlyRoot {
        require(msg.sender == _rootAddress, 101, "Method only for root");
        _;
    }



    /***************
     * CONSTRUCTOR *
     ***************/
    constructor(
        address rootAddress
    ) public accept {
        _rootAddress = rootAddress;
    }



    /***********
     * GETTERS *
     ***********/
    function getRootAddress() public view returns (address rootAddress) { return _rootAddress; }
    function getGamesCount() public view returns (uint64 gamesCount) { return uint64(_games.length); }

    function getGames(uint64 offset, uint64 limit) public view returns (
        address[] games,
        address[] winners,
        uint128[] rewards,
        uint128[] amounts,
        uint64[]  counts,
        uint64    totalLength
    ) {
        GameInfo[] gamesArr = _games;
        uint64 endIndex = _getEndIndex(offset, limit, gamesArr.length);
        for (uint64 i = offset; i < endIndex; i++) {
            GameInfo game = gamesArr[i];
            games.push(game.game);
            winners.push(game.winner);
            rewards.push(game.reward);
            amounts.push(game.amount);
            counts.push(game.count);
        }
        return (games, winners, rewards, amounts, counts, uint64(games.length));
    }


    /***********************
     * PUBLIC * ONLY OWNER *
     ***********************/

    function setRoot(address rootAddress) public onlyOwner accept {
        _rootAddress = rootAddress;
    }
    
    /************
     * EXTERNAL *
     ************/
    function save(address game, address winner, uint128 reward, uint128 amount, uint64 count) external onlyRoot {
        GameInfo _game = GameInfo(game, winner, reward, amount, count);
        _games.push(_game);
        LotteryInterface(_rootAddress).returnChange{value: 0, flag: 128}();
    }

    /***********
     * PRIVATE *
     ***********/

}