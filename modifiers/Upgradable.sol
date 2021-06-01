pragma ton-solidity ^0.42.0;

abstract contract Upgradable {
    /*
     * Set code
     */

    function upgrade(TvmCell newcode) public virtual {
        require(msg.pubkey() == tvm.pubkey(), 100);
        tvm.accept();
        tvm.commit();
        tvm.setcode(newcode);
        tvm.setCurrentCode(newcode);
        onCodeUpgrade();
    }

    function onCodeUpgrade() internal virtual;
}