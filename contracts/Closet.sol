// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

contract Closet {
    struct Safe {
        bool empty;
        uint256 amount;
        uint256 timelock;
        uint256 reward;
        address owner;
        address thief;
    }

    struct ByteConstraints {
        uint8 min;
        uint8 max;
    }

    struct LockupConstraints {
        uint256 min;
        uint256 max;
    }

    struct Rates {
        uint16 take;
        uint16 burn;
    }

    uint32 minStake;

    LockupConstraints lockupConstraints;

    ByteConstraints byteConstraints;

    Rates rates;

    mapping(bytes32 => Safe) public safes;

    mapping(address => uint256) public balances;

    event Mounted(address indexed _owner, bytes32 _hash);

    event Cracked(bytes32 indexed _hash, string _secret);

    event Emptied(bytes32 indexed _hash);

    event Unmounted(bytes32 indexed _hash);

    event Redeemed(address indexed _address, uint256 _amount);

    modifier fundingSecured(uint256 _amount) {
        require(
            _amount >= minStake && msg.value >= _amount,
            "Insufficient funds"
        );
        _;
    }

    modifier preLock(uint256 _timelock) {
        require(_timelock > block.timestamp, "Lock expired");
        _;
    }

    modifier postLock(uint256 _timelock) {
        require(block.timestamp >= _timelock, "Not yet unlocked");
        _;
    }

    modifier vacancyCheck(bytes32 _hash) {
        require(safes[_hash].reward == 0, "Occupied safe");
        _;
    }

    modifier safeDetect(Safe storage safe) {
        require(safe.reward != 0, "Invalid secret or address");
        require(!safe.empty, "Safe emptied");
        _;
    }

    modifier onlyOwner(address _owner) {
        require(_owner == msg.sender, "Unauthorized");
        _;
    }

    modifier validByteSize(string memory _secret) {
        uint256 byteSize = bytes(_secret).length;
        require(
            byteSize >= byteConstraints.min && byteSize <= byteConstraints.max,
            "Outside byte range"
        );
        _;
    }

    modifier validKey(string memory _secret, bytes32 _hash) {
        bytes32 hash = keccak256(abi.encodePacked(_secret));
        require(hash == _hash, "Invalid secret or hash");
        _;
    }

    modifier validTimelock(uint256 _timelock) {
        uint256 period = _timelock - block.timestamp;
        require(
            period <= lockupConstraints.max && period >= lockupConstraints.min,
            "Outside time range"
        );
        _;
    }

    modifier validWithdrawal(uint256 amount) {
        uint256 balance = balances[msg.sender];
        require(balance >= amount, "Insufficient funds");
        _;
    }

    function _calculateReward(uint256 _amount) private view returns (uint256) {
        return
            _amount -
            (_amount * (rates.burn / (type(uint16).max))) -
            (_amount * (rates.take / type(uint16).max));
    }

    function hide(
        bytes32 _hash,
        uint256 _amount,
        uint256 _timelock
    ) public payable fundingSecured(_amount) {
        uint256 reward = _calculateReward(_amount);
        _mount(_hash, _amount, _timelock, reward);
    }

    function _mount(
        bytes32 _hash,
        uint256 _amount,
        uint256 _timelock,
        uint256 _reward
    ) private validTimelock(_timelock) vacancyCheck(_hash) {
        safes[_hash] = Safe(
            false,
            _amount,
            _timelock,
            _reward,
            msg.sender,
            address(0)
        );
        balances[msg.sender] += (msg.value - _amount);
        emit Mounted(msg.sender, _hash);
    }

    function crack(string memory _secret) public {
        bytes32 hash = keccak256(abi.encodePacked(_secret));
        Safe storage safe = safes[hash];
        _loot(_secret, hash, safe);
    }

    function _loot(
        string memory _secret,
        bytes32 _hash,
        Safe storage safe
    ) private safeDetect(safe) preLock(safe.timelock) {
        safe.empty = true;
        safe.thief = msg.sender;
        balances[msg.sender] += safe.reward;
        emit Cracked(_hash, _secret);
        emit Emptied(_hash);
    }

    function reveal(string memory _secret, bytes32 _hash)
        public
        validByteSize(_secret)
        validKey(_secret, _hash)
        returns (string memory)
    {
        Safe storage safe = safes[_hash];
        return _dismount(_secret, _hash, safe);
    }

    function _dismount(
        string memory _secret,
        bytes32 _hash,
        Safe storage safe
    )
        private
        onlyOwner(safe.owner)
        safeDetect(safe)
        postLock(safe.timelock)
        returns (string memory)
    {
        safe.empty = true;
        balances[safe.owner] += safe.amount;
        emit Emptied(_hash);
        emit Unmounted(_hash);
        return _secret;
    }

    function withdraw(uint256 amount) public payable validWithdrawal(amount) {
        balances[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
        emit Redeemed(msg.sender, amount);
    }

    function checkBalance() public view returns (uint256) {
        return balances[msg.sender];
    }
}