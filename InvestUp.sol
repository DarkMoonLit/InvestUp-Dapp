// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";


contract InvestUp is IERC721Receiver {

    using Counters for Counters.Counter;
    Counters.Counter private investorId; // counter for number of investors

    IERC721 nft;
    uint tokenId;

    address payable owner;

    mapping(uint => address) investors; // keeps track of investors address
    mapping(address => bool) invested;
    mapping(address => uint) balances; 

    uint public maxInvestors; // total number of investors needed for sale
    uint public price;
    uint public time = 7 days;
    uint public profit = 2; // 200% of collected
    uint public collected; // amount collected from sale 

    bool ended = false;
    bool started = false;
    bool public claimed = true; 

    event Start(address indexed owner, IERC721 nft, uint tokenId);
    event Buy(address indexed buyer, uint amount);
    event End(bool sold, uint amount);
    event Profit(address indexed buyer, uint profit, uint newPrice);

    constructor(address nftContract, uint _tokenId) {
        nft = IERC721(nftContract);
        tokenId = _tokenId;
        owner = payable(msg.sender);
    }

    function startSale(uint _price, uint _maxInvestors) public verifyEnded verifyNotStarted onlyOwner {
        require(_price > 0, "Enter a valid price");
        require(_maxInvestors > 1, "Maximum number of investors has to be greater than 1");
        require((_price + (_maxInvestors * 1 ether)) % 2 == 0, "Decimal error"); // Prevents any decimal values to be assigned
        price = _price;
        started = true;
        maxInvestors = _maxInvestors;
        time = block.timestamp + time;
        nft.safeTransferFrom(msg.sender, address(this), tokenId);
        emit Start(msg.sender, nft, tokenId);
    }

    // allows a user to instantly buy an Nft if no investors is involved
    function buy() public payable verifyEnded verifyTime verifyStarted verifyNotOwner {
        uint id = investorId.current();
        require(id == 0, "Investors have already bought a share of the NFT");
        require(msg.value == price, "Instant selling price needs to be matched");
        ended = true;
        maxInvestors = 0;
        collected = price;
        price = 0;
        time = 0;
        investorId.increment();
        owner = payable(msg.sender);
        (bool sent,) = owner.call{value : msg.value}("");
        require(sent, "payment failed");
        nft.safeTransferFrom(address(this), msg.sender, tokenId);
        emit Buy(msg.sender, collected);

    }
    
    function invest() public payable verifyEnded verifyTime verifyStarted  verifyNotOwner {
        require(!invested[msg.sender], "Already an investor");
        uint id = investorId.current();
        require(id < maxInvestors, "Already reached the maximum investors");
        uint minAmount = calcMinAmount();
        require(msg.value == minAmount, "Invested amount not enough");
        collected += msg.value;
        investorId.increment();
        investors[id] = msg.sender; // adding new investor
        invested[msg.sender] = true; // makes sure that sender is now an investor
        
    }

    function end() public payable verifyEnded verifyStarted onlyOwner {
        
        // runs if sale is a success
        if(collected == price){
           (bool sent,) = owner.call{value: collected}("");
            require(sent, "Transfer of payment failed");
            ended = true;
            claimed = false;
            time = 0;
            emit End(true, collected);

        } else { // runs if sale isn't a sucess
            ended = true;
            price = 0;
            time = 0;
            uint id = investorId.current();
            uint returnAmount = collected / id; // ensures equal amount is returned to each investors
            for(uint i = 0; i < id; i++){ // returns invested amount to each investor
                address user =  investors[i];
                balances[user] += returnAmount;
            }
            nft.safeTransferFrom(address(this), msg.sender, tokenId);
            emit End(false, collected);
        }
    }

    // allows a user to buy the Nft from the investors
    function claimNFT() public payable verifyStarted verifyNotClaimed {
        uint newPrice = 2 * price; // double of collected
        require(msg.value == newPrice, "Incorrect amount sent");
        uint id = investorId.current();
        uint individualProfit = newPrice / id; // id represents number of investors
        for(uint i = 0; i < id; i++){ // returns invested amount with profits to each investor
                address user =  investors[i];
                balances[user] += individualProfit;
            }
        nft.safeTransferFrom(address(this), msg.sender, tokenId);
        claimed = true;
        collected += newPrice;
        emit Profit(msg.sender, profit, newPrice);
    }

    function withdraw() public payable { 
        require(balances[msg.sender] > 0, "No amount to withdraw");
        uint refundAmount = balances[msg.sender];
        balances[msg.sender] = 0;
        (bool sent,) = payable(msg.sender).call{value: refundAmount}("");
        require(sent, "Transfer of balance failed");
    }

    // returns amount needed to invest
    function calcMinAmount() internal view returns (uint) {
        uint minAmount = price / maxInvestors;
        return minAmount;
    }

    function getMinAmount() public view verifyEnded verifyStarted returns (uint) {
        return calcMinAmount();
    }

    function getNewPrice() public view verifyNotClaimed returns (uint) {
        uint newPrice = 2 * price;
        return newPrice;
    }

    modifier verifyEnded {
        require(!ended, "Sale has already ended");
        _;
    }

    modifier verifyNotStarted {
        require(!started, "Nft is already on sale");
        _;
    }

    modifier verifyStarted {
        require(started, "Not on sale");
        _;
    }

    modifier verifyTime {
        require(block.timestamp < time, "Time to buy or invest is over");
        _;
    }

    modifier verifyNotClaimed {
        require(!claimed, "Already claimed");
        _;
    }

    modifier onlyOwner {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier verifyNotOwner {
        require(msg.sender != owner, "Only investor or buyer");
        _;
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata) external override returns (bytes4) {
        return bytes4(this.onERC721Received.selector);
    }

}
