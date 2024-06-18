// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "contracts/interfaces/IProtoCor.sol";
import "contracts/interfaces/IPairFactory.sol";
import "contracts/interfaces/IPair.sol";
import "contracts/interfaces/IGauge.sol";
import "contracts/interfaces/ISousChef.sol";
import "contracts/interfaces/IPriceFeed.sol";
import "contracts/interfaces/IGauge.sol";
import "contracts/interfaces/IGaugeFactory.sol";
import "contracts/multipool/ISwap.sol";
import "contracts/oracle/PythPriceFeed.sol";
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "contracts/Constants.sol";

contract SousChef is ISousChef, Constants {
    address public immutable protoCor;
    address public immutable factory;
    address public immutable gaugeFactory;
    address public pyth;
    address public governor;
    uint internal constant DURATION = SECONDS_PER_EPOCH;

    address[] public pools; // all pools viable for incentives
    mapping(address => address) public gauges; // pool => gauge
    mapping(address => address) public poolForGauge; // gauge => pool
    mapping(address => uint256) public weights; // pool => weight
    mapping(uint => mapping(address => uint256)) public votes; // nft => pool => votes
    mapping(uint => address[]) public poolVote; // nft => pools
    mapping(uint => uint) public usedWeights; // nft => total voting weight of user
    mapping(uint => uint) public lastVoted; // nft => timestamp of last vote, to ensure one vote per epoch
    mapping(address => bool) public isGauge;
    mapping(address => bool) public isWhitelisted;
    mapping(address => bool) public isAlive;
    mapping(address => bool) public isNgGauge;

    mapping(address => uint) public boostFactor; // gauge => boostFactor
    mapping(address => bytes32) public priceIds; // token => priceId
    mapping(address => IPriceFeed) public priceFeed; // token => priceFeed

    uint public immutable MAX_BOOST = 5000;

    event GaugeCreated(
        address indexed gauge,
        address creator,
        address indexed pool
    );

    event GaugeKilled(address indexed gauge);
    event GaugeRevived(address indexed gauge);

    event Deposit(
        address indexed lp,
        address indexed gauge,
        uint tokenId,
        uint amount
    );
    event Withdraw(
        address indexed lp,
        address indexed gauge,
        uint tokenId,
        uint amount
    );

    event NotifyReward(
        address indexed sender,
        address indexed reward,
        uint amount
    );

    event DistributeReward(
        address indexed sender,
        address indexed gauge,
        uint amount
    );

    event Whitelisted(address indexed whitelister, address indexed token);

    constructor(
        address _protoCor,
        address _factory,
        address _gaugeFactory,
        address _pyth
    ) {
        protoCor = _protoCor;
        factory = _factory;
        gaugeFactory = _gaugeFactory;
        pyth = _pyth;
        governor = msg.sender;
    }

    // simple re-entrancy check
    uint internal _unlocked = 1;
    modifier lock() {
        require(_unlocked == 1);
        _unlocked = 2;
        _;
        _unlocked = 1;
    }

    modifier onlyNewEpoch(uint _tokenId) {
        // ensure new epoch since last vote
        require(
            (block.timestamp / DURATION) * DURATION > lastVoted[_tokenId],
            "TOKEN_ALREADY_VOTED_THIS_EPOCH"
        );
        _;
    }

    function setGovernor(address _governor) public {
        require(msg.sender == governor);
        require(_governor != address(0));
        governor = _governor;
    }

    function setBoostFactor(address _gauge, uint _boostFactor) public {
        require(msg.sender == governor);
        require(poolForGauge[_gauge] != address(0), "invalid gauge");
        boostFactor[_gauge] = _boostFactor;
    }

    function getGaugeTVL(address _gauge) public view returns (uint) {
        address pool = poolForGauge[_gauge];
        address[] memory tokens;
        if (isNgGauge[_gauge]) {
            tokens = ISwap(_LPTokenToNgPool(pool)).getTokensArray();
        } else {
            tokens[0] = IPair(pool).token0();
            tokens[1] = IPair(pool).token1();
        }
        uint tvl;
        for (uint i = 0; i < tokens.length; i++) {
            uint price = priceFeed[tokens[i]].fetchPrice();
            uint value = (IERC20(tokens[i]).balanceOf(_LPTokenToNgPool(pool)) *
                uint(uint160(price))) / 1e18;
            tvl += value;
        }
        return tvl;
    }

    function calculateTVL() external view returns (uint) {
        uint sum;
        for (uint i = 0; i < pools.length; i++) {
            sum += getGaugeTVL(gauges[pools[i]]);
        }
        return sum;
    }

    function distro() external {
        for (uint i = 0; i < pools.length; i++) {
            IGauge(gauges[pools[i]]).update_period();
        }
    }

    function whitelist(address _token) public {
        require(msg.sender == governor);
        _whitelist(_token);
    }

    function _whitelist(address _token) internal {
        require(!isWhitelisted[_token]);
        isWhitelisted[_token] = true;
        emit Whitelisted(msg.sender, _token);
    }

    function createGauge(
        address _pool,
        bytes32 priceId
    ) external returns (address) {
        require(msg.sender == governor, "Not governor");
        require(gauges[_pool] == address(0x0), "exists");
        address[] memory allowedRewards = new address[](3);
        bool isPair = IPairFactory(factory).isPair(_pool);
        address tokenA;
        address tokenB;

        if (isPair) {
            (tokenA, tokenB) = IPair(_pool).tokens();
            allowedRewards[0] = tokenA;
            allowedRewards[1] = tokenB;

            if (protoCor != tokenA && protoCor != tokenB) {
                allowedRewards[2] = protoCor;
            }
        }

        if (msg.sender != governor) {
            // gov can create for any pool, even non-Stratum pairs
            require(isPair, "!_pool");
            require(
                isWhitelisted[tokenA] && isWhitelisted[tokenB],
                "!whitelisted"
            );
        }

        address _gauge = IGaugeFactory(gaugeFactory).createGauge(
            _pool,
            isPair,
            allowedRewards
        );

        PythPriceFeed _priceFeed = new PythPriceFeed(
            IPyth(pyth),
            priceId,
            90_000
        );

        boostFactor[_gauge] = 1000; // 1x

        priceFeed[_gauge] = _priceFeed;
        gauges[_pool] = _gauge;
        poolForGauge[_gauge] = _pool;
        isGauge[_gauge] = true;
        isAlive[_gauge] = true;
        pools.push(_pool);
        emit GaugeCreated(_gauge, msg.sender, _pool);
        return _gauge;
    }

    function createGaugeNg(
        address _LPToken,
        address[] memory _token,
        bytes32[] memory priceId
    ) external returns (address) {
        require(msg.sender == governor, "Not governor");
        require(gauges[_LPToken] == address(0x0), "exists");
        for (uint256 i = 0; i < _token.length; i++) {
            require(isWhitelisted[_token[i]], "!whitelisted");
        }
        address[] memory allowedRewards = new address[](_token.length + 1);
        for (uint256 i = 0; i < _token.length; i++) {
            allowedRewards[i] = _token[i];
        }
        allowedRewards[_token.length] = protoCor;

        address _gauge = IGaugeFactory(gaugeFactory).createGauge(
            _LPToken,
            true,
            allowedRewards
        );

        isNgGauge[_gauge] = true;

        for (uint i = 0; i < _token.length; i++) {
            if (address(priceFeed[_token[i]]) == address(0)) {
                PythPriceFeed _priceFeed = new PythPriceFeed(
                    IPyth(pyth),
                    priceId[i],
                    86_400
                );
                priceFeed[_token[i]] = _priceFeed;
            }
        }

        boostFactor[_gauge] = 1000; // 1x

        gauges[_LPToken] = _gauge;
        poolForGauge[_gauge] = _LPToken;
        isGauge[_gauge] = true;
        isAlive[_gauge] = true;
        pools.push(_LPToken);
        emit GaugeCreated(_gauge, msg.sender, _LPToken);
        return _gauge;
    }

    function killGauge(address _gauge) external {
        require(msg.sender == governor, "not emergency council");
        require(isAlive[_gauge], "gauge already dead");
        isAlive[_gauge] = false;
        emit GaugeKilled(_gauge);
    }

    function reviveGauge(address _gauge) external {
        require(msg.sender == governor, "not emergency council");
        require(!isAlive[_gauge], "gauge already alive");
        isAlive[_gauge] = true;
        emit GaugeRevived(_gauge);
    }

    function length() external view returns (uint) {
        return pools.length;
    }

    function poolByIndex(uint _index) external view returns (address) {
        return pools[_index];
    }

    function _LPTokenToNgPool(
        address _LPToken
    ) public view returns (address swap) {
        uint allPairsLength = IPairFactory(factory).allPairsLength();
        for (uint i = 0; i < allPairsLength; i++) {
            address pair = IPairFactory(factory).getPairByIndex(i);
            if (IPairFactory(factory).isNg(pair)) {
                (, , , , , , address lpToken) = ISwap(pair).swapStorage();
                if (lpToken == _LPToken) {
                    swap = pair;
                }
            }
        }
        require(swap != address(0));
    }

    uint internal index;
    mapping(address => uint) internal supplyIndex;
    mapping(address => uint) public claimable;

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                from,
                to,
                value
            )
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }
}