// SPDX-License-Identifier: MIT LICENSE
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/** PriceFeed REF
 * https://docs.chain.link/docs/data-feeds/price-feeds/#solidity
 * 
 * Network: Mainnet
 * Aggregator: ETH/USD
 * Address: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
 *
 * Network: Goerli
 * Aggregator: ETH/USD
 * Address: 0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e
 */

interface IDignityToken is IERC20Metadata {
    function mint(address, uint256) external;
}

contract DignityTokenSwap is AccessControl {
    bytes32 public constant OPS_ROLE = keccak256("OPS_ROLE");

    using Strings for uint256;    
    AggregatorV3Interface internal priceFeed;    
    IDignityToken public dignityToken;
      
    // price for StableCoin (in dollar)
    mapping(address => uint256) public tokensMap;
    // price for ETH (in dollar)
    uint public coinPrice;    

    address public dignityWallet;
    bool public paused = false;

    constructor(address _dignityToken, 
        address _stable, 
        uint256 _cost, 
        address _dignityWallet,
        address _ethUsdAddress) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        dignityToken = IDignityToken(_dignityToken);        
        coinPrice = _cost;
        dignityWallet = _dignityWallet;
        addTokenToSupportList(IERC20(_stable), _cost);        
        priceFeed = AggregatorV3Interface(_ethUsdAddress);        
    }

    function addTokenToSupportList(
        IERC20 _paytoken,
        uint256 _payCostPerDT
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {        
        tokensMap[address(_paytoken)] = _payCostPerDT;
    }

    function setPausedState(bool _state) external onlyRole(DEFAULT_ADMIN_ROLE) {
        paused = _state;
    }

    function setDignityWallet(address _addr) external onlyRole(DEFAULT_ADMIN_ROLE) {
      dignityWallet = _addr;
    }

    /**
     *  INPUTS :
     *      PARAMETERS :
     *      GLOBALS :
     *          uint    msg.value               amount of eth to swap for dignity token     
     */
    function swap() public payable {        
        require(!paused, "Swap paused");
        require(msg.value > 0,  "Invalid amount");

        int etherPriceUSD = getLatestPrice();                   // Goerli  eg. 130962000000
        uint8 etherPriceDecimals = priceFeed.decimals();        // uint8 etherPriceDecimals = 8;
        require(etherPriceUSD > 0, "Invalid USD price");
        require(etherPriceDecimals > 0, "Invalid price decimals");

        uint8 etherDecimals = 18;
        uint8 dtDecimals = dignityToken.decimals();
        require(dtDecimals > 0, "Invalid dignity token decimals");
        
        uint256 costUSD = (msg.value * uint256(etherPriceUSD)) / (10**etherPriceDecimals);
        uint256 amount = costUSD / coinPrice;            
        uint256 dtAmount = amount / (10**(etherDecimals-dtDecimals));
        require(dtAmount > 0, "Invalid dignity token swap");
        dignityToken.mint(msg.sender, dtAmount);
    }

    /**
     *  INPUTS :
     *      PARAMETERS :
     *          address _token                  stable coin contract address 
     *          uint256 _amount                 amount of stable coin (in token's decimal)     
     */    
    function swapToken(address _token, uint256 _amount) public {        
        require(!paused, "Swap paused");
        require(tokensMap[_token] > 0, "Token not supported!");
        
        IERC20Metadata paytoken = IERC20Metadata(_token);        
        uint256 cost = tokensMap[_token];   // cost (in token's decimal)       

        uint8 dtDecimals = dignityToken.decimals();                
    	uint256 dtAmount = _amount * 10**dtDecimals / cost;
        require(dtAmount > 0, "Invalid cost");

        paytoken.transferFrom(msg.sender, address(this), _amount);                
        dignityToken.mint(msg.sender, dtAmount);
    }

    function getLatestPrice() public view returns (int) {
        (
            /*uint80 roundID*/,
            int price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();
        return price;
    }

    function withdraw() public onlyRole(OPS_ROLE) {        
        uint256 balance = address(this).balance;        
        payable(dignityWallet).transfer(balance);
    }        

    function withdrawToken(address _token) public onlyRole(OPS_ROLE) {             
        require(tokensMap[_token] > 0, "Token not supported!");

        IERC20 paytoken = IERC20(_token);        
        paytoken.transfer(dignityWallet, paytoken.balanceOf(address(this)));
    }
}
