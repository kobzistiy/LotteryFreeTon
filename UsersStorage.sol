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
 *     • 200 — Invalid referral id
 */
contract UsersStorage is ArrayUtil {

    /*************
     * CONSTANTS *
     *************/

    /**************
     * STRUCTURES *
     **************/
    struct UserInfo {
        uint64 userId;
        uint64 referralId;
    }
    

    /*************
     * VARIABLES *
     *************/
    address private _rootAddress;
    mapping(address => UserInfo) _userDB;
    address[] private            _userKeys;

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
        require(msg.sender == _rootAddress, 100, "Method only for root");
        _;
    }

    modifier validReferralId(uint64 referrerId) {
        require(referrerId == 0 || (referrerId >= 0 && referrerId < _userKeys.length), 200, "Invalid referral id");
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
    function getUsersCount() public view returns (uint64 usersCount) { return uint64(_userKeys.length); }

    function getUsers(uint64 offset, uint64 limit) public view returns (
        address[] users,
        uint64[]  userIds,
        uint64[]  referals,
        uint64   totalLength
    ) {
        uint64 endIndex = _getEndIndex(offset, limit, _userKeys.length);
        for (uint64 i = offset; i < endIndex; i++) {
            UserInfo info = _userDB[_userKeys[i]];
            users.push(_userKeys[i]);
            userIds.push(info.userId);
            referals.push(info.referralId);
        }
        return (users, userIds, referals, uint64(users.length));
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
    function dispatchWithReferral(address sender, uint128 value, uint64 referralId) external onlyRoot validReferralId(referralId) {
        optional(UserInfo) info = _userDB.fetch(sender);
        uint64 userId = 0;
        UserInfo i;
        if (info.hasValue()) {
            i = info.get();
        } else {
            i = UserInfo(uint64(_userKeys.length), referralId);
            _userDB[sender] = i;
            _userKeys.push(sender);
            userId = i.userId;
        }
        address referral = sender;
        if (i.referralId > 0) {
          referral = _userKeys[i.referralId];
        }
        LotteryInterface(_rootAddress).onReceiveReferralAddress{value: 0, flag: 128}(sender, value, referral, userId);
    }

    /***********
     * PRIVATE *
     ***********/
}