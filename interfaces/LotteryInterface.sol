pragma ton-solidity ^0.42.0;

interface LotteryInterface {
    function onReceiveReferralAddress(address sender, uint128 value, address referral, uint64 userId) external;
    function onGameOver(address winner, uint128 reward, uint128 amount, uint64 count) external;
    function returnChange() external;
}