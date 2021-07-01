// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.4;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenSaleContract is Ownable, ReentrancyGuard {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    address payable private _wallet;
    IERC20 private _token;

    AirdropConfig private _airdropConfig;
    uint private _airdropCount;
    uint256 private _airdropTokenCount;

    uint256 private _totalReferralTokenCount;
    TokenSaleConfig private _tokenSaleConfig;

    mapping (address => uint256) _addressAirdropCount;

    event TokenSale(address indexed from, address indexed to, bool indexed isFree, uint256 tokens, uint256 weiAmount);

    constructor (address payable wallet, IERC20 token) {
        _wallet = wallet;
        _token = token;
    }

    /* Token Airdrop */
    function claimAirdrop(address referralAddress) public nonReentrant {
        require(_airdropConfig.IsActive == true, "Airdrop is inactive");
        require(_airdropConfig.MaxAirdropCount == 0 || _airdropCount < _airdropConfig.MaxAirdropCount, "Max. Airdrop limit reached");
        require(_airdropConfig.MaxAirdropTokenCount == 0 || _airdropTokenCount < _airdropConfig.MaxAirdropTokenCount, "Max. Airdrop Token limit reached");
        require(_addressAirdropCount[msg.sender] == 0, "You have already claimed Airdrop");

        if(msg.sender != referralAddress && 
            _addressAirdropCount[referralAddress] != 0 && 
            referralAddress != 0x0000000000000000000000000000000000000000){
                uint256 airdropReferralTokenCount =_airdropConfig.ReferralTokenCount;
                
                _addressAirdropCount[referralAddress] = _addressAirdropCount[referralAddress].add(airdropReferralTokenCount);
                _airdropTokenCount = _airdropTokenCount.add(airdropReferralTokenCount);
                deliverTokens(referralAddress, airdropReferralTokenCount);
                                
                emit TokenSale(address(this), referralAddress, true, airdropReferralTokenCount, 0);
        }
        
        uint256 airdropTokenCount =_airdropConfig.TokenCount;
        _addressAirdropCount[msg.sender] = _addressAirdropCount[msg.sender].add(airdropTokenCount);
        _airdropTokenCount = _airdropTokenCount.add(airdropTokenCount);
        _airdropCount = _airdropCount.add(1);
        deliverTokens(msg.sender, airdropTokenCount);

        emit TokenSale(address(this), msg.sender, true, airdropTokenCount, 0);
    }

    function sendTokensToMultipleAccounts(TokenTransferDetail[] memory tokenTransferDetails, bool isAirdrop) public onlyOwner{
        for(uint i = 0; i < tokenTransferDetails.length; i++){
            TokenTransferDetail memory tokenTransferDetail = tokenTransferDetails[i];

            if(isAirdrop){
                _addressAirdropCount[tokenTransferDetail.BeneficiaryAccount] = _addressAirdropCount[tokenTransferDetail.BeneficiaryAccount].add(tokenTransferDetail.TokenCount);
                _airdropTokenCount = _airdropTokenCount.add(tokenTransferDetail.TokenCount);
                _airdropCount = _airdropCount.add(1);
            }

            deliverTokens(tokenTransferDetail.BeneficiaryAccount, tokenTransferDetail.TokenCount);
            emit TokenSale(address(this), tokenTransferDetail.BeneficiaryAccount, true, tokenTransferDetail.TokenCount, 0);
        }
    }

    function modifyAirdropConfig(bool isActive, uint256 tokenCount, uint256 referralTokenCount, uint256 maxAirdropCount, uint256 maxAirdropTokenCount) public onlyOwner  {
        _airdropConfig.IsActive = isActive;
        _airdropConfig.TokenCount = tokenCount;
        _airdropConfig.ReferralTokenCount = referralTokenCount;
        _airdropConfig.MaxAirdropCount = maxAirdropCount;
        _airdropConfig.MaxAirdropTokenCount = maxAirdropTokenCount;
    }

    function modifyAirdropStatus(bool isActive) public onlyOwner {
        _airdropConfig.IsActive = isActive;
    }

    function getAirdropCount() public view onlyOwner returns (uint256){
        return _airdropCount;
    }

    struct AirdropConfig{
        // Is Airdrop Active
        bool IsActive;

        // Number of Tokens to be transferred to the Buyer while claiming Airdrop
        uint256 TokenCount;

        // Number of Tokens to be Transferred to the Referred for Airdrop
        uint256 ReferralTokenCount;

        // Maximum number of Airdrops that can be performed
        uint256 MaxAirdropCount;

        // Maximum number of Tokens to be distributes using Airdrop
        uint256 MaxAirdropTokenCount;
    }
    /* EOF: Token Airdrop */

    /* Token Sale */
    receive () external payable {
        buyTokens(_msgSender(), address(0));
    }

    function buyTokens(address beneficiary, address referralAddress) public nonReentrant payable {
        uint256 weiAmount = msg.value;

        /* Validate Request */
        require(_tokenSaleConfig.IsActive == true, "Token Sales is Inactive");
        require(beneficiary != address(0), "Invalid Beneficiary Address");
        require(weiAmount != 0, "Received Amount is 0");

        /* Get number of Tokens to be Transferred */
        uint256 tokensCount = weiAmount.div(_tokenSaleConfig.Price).mul(1 ether);
        if(_tokenSaleConfig.PurchaseBonusWei != 0 && _tokenSaleConfig.PurchaseBonusTokenCount != 0 && weiAmount >= _tokenSaleConfig.PurchaseBonusWei){
            tokensCount = tokensCount.add(_tokenSaleConfig.PurchaseBonusTokenCount);
        }

        if(referralAddress != address(0) && 
            referralAddress != 0x0000000000000000000000000000000000000000 &&
            referralAddress != msg.sender){
            uint256 referralTokenCount = getReferralTokenCount(tokensCount);
            _totalReferralTokenCount = _totalReferralTokenCount.add(referralTokenCount);
            deliverTokens(referralAddress, referralTokenCount);
            emit TokenSale(address(this), referralAddress, true, referralTokenCount, 0);
        }
        
        /* Process Purchase */
        deliverTokens(beneficiary, tokensCount);
        emit TokenSale(address(this), msg.sender, false, tokensCount, weiAmount);
        forwardFunds(weiAmount);
    }

    function getReferralTokenCount(uint256 boughtTokenCount) internal view returns (uint256) {
        uint256 tokenCount;
        if(_tokenSaleConfig.ReferralPercentage == 0)
            return tokenCount;
        else{
            tokenCount = boughtTokenCount * _tokenSaleConfig.ReferralPercentage / 100;

            // Check the maximum tokens that can be sent to the referral
            if(_tokenSaleConfig.ReferralTokenCountCap != 0){
                if(tokenCount > _tokenSaleConfig.ReferralTokenCountCap){
                    tokenCount = _tokenSaleConfig.ReferralTokenCountCap;
                }
            }
            
            // Check the total referral token count reached the Cap
            if(_tokenSaleConfig.TotalReferralTokenCountCap != 0){
                if(_totalReferralTokenCount.add(tokenCount) > _tokenSaleConfig.TotalReferralTokenCountCap){
                    tokenCount = _tokenSaleConfig.TotalReferralTokenCountCap - _totalReferralTokenCount;
                }
            }
        }

        return tokenCount;
    }

    function getTotalReferralTokenCount() public view onlyOwner returns(uint256){
        return _totalReferralTokenCount;
    }

    function forwardFunds(uint256 weiAmount) internal {
        _wallet.transfer(weiAmount);
    }

    function modifyWallet(address payable newWallet) public onlyOwner{
        _wallet = newWallet;
    }

    function modifyTokenSaleConfig(bool isActive, uint256 price, uint referralPercentage, uint256 referralTokenCountCap, uint256 totalReferralTokenCountCap, uint256 purchaseBonusWei, uint256 purchaseBonusTokenCount) public onlyOwner{
        _tokenSaleConfig.IsActive = isActive;
        _tokenSaleConfig.Price = price;
        _tokenSaleConfig.ReferralPercentage = referralPercentage;
        _tokenSaleConfig.ReferralTokenCountCap = referralTokenCountCap;
        _tokenSaleConfig.TotalReferralTokenCountCap = totalReferralTokenCountCap;
        _tokenSaleConfig.PurchaseBonusWei = purchaseBonusWei;
        _tokenSaleConfig.PurchaseBonusTokenCount = purchaseBonusTokenCount;
    }

    function modifyTokenSaleStatus(bool isActive) public onlyOwner {
        _tokenSaleConfig.IsActive = isActive;
    }

    struct TokenSaleConfig{
        // Is Airdrop Active
        bool IsActive;
        
        // Price of Token
        uint256 Price;

        // Token Count for Referrals
        uint ReferralPercentage;

        // Referral Token Count Cap (for each Transaction)
        uint256 ReferralTokenCountCap;

        // Total Referral Token Count Cap
        uint256 TotalReferralTokenCountCap;

        // Minimum purchase wei Amount for Bonus Tokens
        uint256 PurchaseBonusWei;

        // Bonus Tokens Count
        uint256 PurchaseBonusTokenCount;
    }
    /* EOF: Token Sale */

    function withdrawTokens(uint256 tokenAmount) public onlyOwner{
        deliverTokens(owner(),tokenAmount);
    }

    function withdrawAllTokens() public onlyOwner{
        deliverTokens(owner(), _token.balanceOf(address(this)));
    }
    function deliverTokens(address beneficiary, uint256 tokenAmount) internal {
        _token.safeTransfer(beneficiary, tokenAmount);
    }

    struct TokenTransferDetail{
        address BeneficiaryAccount;
        uint256 TokenCount;
    }
}