pragma ton-solidity ^0.47.0;
pragma AbiHeader expire;
pragma AbiHeader pubkey;
pragma AbiHeader time;

import '../tnft-interfaces/NftInterfaces/INftBase/ITokenTransferCallback.sol';
import '../tnft-interfaces/NftInterfaces/INftBase/NftBase.sol';
import '../tnft-interfaces/NftInterfaces/INftBase/INftBase.sol';
import '../tnft-interfaces/NftInterfaces/INftBase/structures/ICallbackParamsStructure.sol';
import '../tnft-interfaces/NftInterfaces/INftBaseApproval/IApproval.sol';
import '../tnft-interfaces/NftInterfaces/INftBaseApproval/INftBaseApproval.sol';
import '../tnft-interfaces/NftInterfaces/IRoyalty/IRoyalty.sol';
import './errors/OffersErrors.sol';


contract Sell is ITokenTransferCallback, IApproval, ICallbackParamsStructure {

    uint constant REQUIRED_STEPS = 2;

    uint256 _ownerPubkey;
    uint128 _marketFeeValue;
    address _marketOwnerAddr;

    uint128 _price;
    address _addrNft;

    bool public _paused = true;
    uint public _steps = 0;

    address _addrOwner;

    mapping(address => uint128) _royalty;

    event sellConfirmed(address nftAddr, address buyerAddr);

    constructor(
        uint256 ownerPubkey,
        address addrNft,
        uint128 marketFeeValue,
        address addrOwner,
        uint128 price,
        address marketOwnerAddr
    ) public {
        require(_price > marketFeeValue);
        tvm.accept();

        _ownerPubkey = ownerPubkey;
        _addrNft = addrNft;
        _addrOwner = addrOwner;
        _price = price;
        _marketOwnerAddr = marketOwnerAddr;
        _royalty[address(this)] = marketFeeValue;
    }

    function _checkSteps() private {
        if (_steps == REQUIRED_STEPS) {
            _paused = false;
        }
    }

    function _genRoyaltyMapping() private returns(mapping(address => CallbackParams) callbacks) {
        TvmCell empty;
        for ((address addr, uint128 value) : _royalty) {
            CallbackParams cp = CallbackParams(value, empty);
            callbacks[addr] = cp;
        }
    }

    function _distribute() private {
        for ((address addr, uint128 value) : _royalty) {
            uint128 feeValue = math.muldiv(_price, value, 100);
            addr.transfer({value: feeValue, bounce: true});
        }

        _addrOwner.transfer({value: 0, flag: 128, bounce: true});
    }

    function getRoyalty() private {
        IRoyalty(_addrNft).getRoyalty{callback: Sell.onGetRoyalty}();
    }

    function onGetRoyalty(mapping(address => uint128) royalty) external onlyNft {
        tvm.accept();
        tvm.rawReserve(msg.value, 1);

        for ((address addr, uint128 value) : royalty) {
            _royalty[addr] = value;
        }

        _steps++;
        _checkSteps();
        _addrOwner.transfer({value: 0, flag: 128, bounce: true});
    }

    function buyToken() external isActive {
        require(msg.value >= _price, OffersErrors.not_enough_value_to_buy);
        require(msg.sender != _addrOwner, OffersErrors.buyer_is_my_owner);
        tvm.accept();

        _paused = true;
        mapping(address => CallbackParams) callbacks = _genRoyaltyMapping();
        INftBase(_addrNft).transferOwnership{value: msg.value, bounce: true}(_marketOwnerAddr, msg.sender, callbacks);
    }

    receive() external {
        require(msg.value >= _price, OffersErrors.not_enough_value_to_buy);
        require(msg.sender != _addrOwner, OffersErrors.buyer_is_my_owner);
        require(!_paused);
        tvm.accept();
   
        _paused = true;
        mapping(address => CallbackParams) callbacks = _genRoyaltyMapping();
        INftBase(_addrNft).transferOwnership{value: msg.value, bounce: true}(_marketOwnerAddr, msg.sender, callbacks);    
    }

    function cancelOrder() external isActive {
        require(msg.value > 0.15 ton);
        require(msg.sender == _addrOwner);
        tvm.accept();
        tvm.rawReserve(msg.value, 1);

        _paused = true;
        INftBaseApproval(_addrNft).returnOwnership{value: 0, flag: 128, bounce: true}();
    }

    function setApprovalCallback(TvmCell payload) external onlyNft override {
        tvm.accept();
        tvm.rawReserve(msg.value, 1);

        _steps++;
        _checkSteps();
        getRoyalty();
        _addrOwner.transfer({value: 0, flag: 128, bounce: true});

        payload; // disable warnings
    }

    function tokenTransferCallback(
        address oldOwner,
        address newOwner,
        address tokenRoot,
        address sendGasToAddr,
        TvmCell payload
    ) external onlyNft override {
        
        emit sellConfirmed(_addrNft, newOwner);
        destruct(_marketOwnerAddr);
    
    }

    function resetApprovalCallback() external onlyNft override {
        destruct(_addrOwner);
    }

    function destruct(address destAddr) private {
        selfdestruct(destAddr);
    }

    function getOfferInfo() public view returns(
        uint128 price,
        address addrNft,
        address addrOwner
    ){
        return (
            _price,
            _addrNft,
            _addrOwner
        );
    }

    modifier isActive {
        require(!_paused);
        _;
    }

    modifier onlyNft {
        require(msg.sender == _addrNft);
        _;
    }

}