pragma solidity ^0.4.16;

import './SafeMath.sol';

contract ERC20 {
	function totalSupply() constant returns (uint totalSupply);
	function balanceOf(address _owner) constant returns (uint balance);
	function transfer(address _to, uint _value) returns (bool success);
	function transferFrom(address _from, address _to, uint _value) returns (bool success);
	function approve(address _spender, uint _value) returns (bool success);
	function allowance(address _owner, address _spender) constant returns (uint remaining);
    // This generates a public event on the blockchain that will notify clients
	event Transfer(address indexed _from, address indexed _to, uint _value);
	event Approval(address indexed _owner, address indexed _spender, uint _value);
}

//Token with owner (admin)
contract OwnedToken {
	address public owner; //contract owner (admin) address
	function OwnedToken () public {
		owner = msg.sender;
	}
	//Check if owner initiate call
    modifier onlyOwner()
    {
        require(msg.sender == owner);
        _;
    }

    /**
     * Transfer ownership
     *
     * @param newOwner The address of the new contract owner
     */
    function transferOwnership(address newOwner) public onlyOwner {
        owner = newOwner;
    }
}

//Contract with name
contract NamedOwnedToken is OwnedToken {
	string public name; //the name for display purposes
	string public symbol; //the symbol for display purposes
	function NamedOwnedToken(string tokenName, string tokenSymbol) public
	{
        name = tokenName;                                   // Set the name for display purposes
        symbol = tokenSymbol;                               // Set the symbol for display purposes
	}

    /**
     * Change name and symbol
     *
     * @param newName The new contract name
     * @param newSymbol The new contract symbol 
     */
    function changeName(string newName, string newSymbol)public onlyOwner {
		name = newName;
		symbol = newSymbol;
    }
}

contract TSBToken is ERC20, NamedOwnedToken {
	using SafeMath for uint256;

    // Public variables of the token

    uint256 public _totalSupply = 0; //Total number of token issued (1 token = 10^decimals)
	uint8 public decimals = 18; //Decimals, each 1 token = 10^decimals

    
    mapping (address => uint256) public balances; // A map with all balances
    mapping (address => mapping (address => uint256)) public allowed; //Implement allowence to support ERC20

    mapping (address => uint256) public paidETH; //The sum have already been paid to token owner
	uint256 public accrueDividendsPerXTokenETH = 0;
	uint256 public tokenPriceETH = 0;

    mapping (address => uint256) public paydCouponsETH;
	uint256 public accrueCouponsPerXTokenETH = 0;
	uint256 public totalCouponsUSD = 0;
	uint256 public MaxCouponsPaymentUSD = 150000;

	mapping (address => uint256) public rebuySum;
	mapping (address => uint256) public rebuyInformTime;


	uint256 public endSaleTime;
	uint256 public startRebuyTime;
	uint256 public reservedSum;
	bool public rebuyStarted = false;

	uint public tokenDecimals;
	uint public tokenDecimalsLeft;

    /**
     * Constructor function
     *
     * Initializes contract
     */
    function TSBToken(
        string tokenName,
        string tokenSymbol
    ) NamedOwnedToken(tokenName, tokenSymbol) public {
		tokenDecimals = 10**uint256(decimals - 5);
		tokenDecimalsLeft = 10**5;
		startRebuyTime = now + 1 years;
		endSaleTime = now;
    }

    /**
     * Internal function, calc dividends to transfer when tokens are transfering to another wallet
     */
	function transferDiv(uint startTokens, uint fromTokens, uint toTokens, uint sumPaydFrom, uint sumPaydTo, uint acrued) internal constant returns (uint, uint) {
		uint sumToPayDividendsFrom = fromTokens.mul(acrued);
		uint sumToPayDividendsTo = toTokens.mul(acrued);
		uint sumTransfer = sumPaydFrom.div(startTokens);
		sumTransfer = sumTransfer.mul(startTokens-fromTokens);
		if (sumPaydFrom > sumTransfer) {
			sumPaydFrom -= sumTransfer;
			if (sumPaydFrom > sumToPayDividendsFrom) {
				sumTransfer += sumPaydFrom - sumToPayDividendsFrom;
				sumPaydFrom = sumToPayDividendsFrom;
			}
		} else {
			sumTransfer = sumPaydFrom;
			sumPaydFrom = 0;
		}
		sumPaydTo = sumPaydTo.add(sumTransfer);
		if (sumPaydTo > sumToPayDividendsTo) {
			uint differ = sumPaydTo - sumToPayDividendsTo;
			sumPaydTo = sumToPayDividendsTo;
			sumPaydFrom = sumPaydFrom.add(differ);
			if (sumPaydFrom > sumToPayDividendsFrom) {
				sumPaydFrom = sumToPayDividendsFrom;
			} 
		}
		return (sumPaydFrom, sumPaydTo);
	}



    /**
     * Internal transfer, only can be called by this contract
     */
    function _transfer(address _from, address _to, uint _value) internal {
        require(_to != address(0));                               // Prevent transfer to 0x0 address. Use burn() instead
        require(balances[_from] >= _value);                // Check if the sender has enough
        require(balances[_to] + _value > balances[_to]); // Check for overflows
		uint startTokens = balances[_from].div(tokenDecimals);
        balances[_from] -= _value;                         // Subtract from the sender
        balances[_to] += _value;                           // Add the same to the recipient

		if (balances[_from] == 0) {
			paidETH[_to] = paidETH[_to].add(paidETH[_from]);
		} else {
			uint fromTokens = balances[_from].div(tokenDecimals);
			uint toTokens = balances[_to].div(tokenDecimals);
			(paidETH[_from], paidETH[_to]) = transferDiv(startTokens, fromTokens, toTokens, paidETH[_from], paidETH[_to], accrueDividendsPerXTokenETH+accrueCouponsPerXTokenETH);
		}
        Transfer(_from, _to, _value);
    }

    /**
     * Transfer tokens
     *
     * Send `_value` tokens to `_to` from your account
     *
     * @param _to The address of the recipient
     * @param _value the amount to send
     */
    function transfer(address _to, uint256 _value) public returns (bool success) {
        _transfer(msg.sender, _to, _value);
        return true;
    }

    /**
     * Balance of tokens
     *
     * @param _owner The address of token wallet
     */
	function balanceOf(address _owner) public constant returns (uint256 balance) {
		return balances[_owner];
	}

    /**
     * Returns total issued tokens number
     *
	*/
	function totalSupply() public constant returns (uint totalSupply) {
		return _totalSupply;
	}


    /**
     * Transfer tokens from other address
     *
     * Send `_value` tokens to `_to` in behalf of `_from`
     *
     * @param _from The address of the sender
     * @param _to The address of the recipient
     * @param _value the amount to send
     */
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
        require(_value <= allowed[_from][msg.sender]);     // Check allowance
        allowed[_from][msg.sender] -= _value;
        _transfer(_from, _to, _value);
        return true;
    }

    /**
     * Set allowance for other address
     *
     * Allows `_spender` to spend no more than `_value` tokens in your behalf
     *
     * @param _spender The address authorized to spend
     * @param _value the max amount they can spend
     */
    function approve(address _spender, uint256 _value) public
        returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        return true;
    }

    /**
     * Check allowance for address
     *
     * @param _owner The address who authorize to spend
     * @param _spender The address authorized to spend
     */
	function allowance(address _owner, address _spender) public constant returns (uint256 remaining) {
		return allowed[_owner][_spender];
	}


	// This notifies clients about the amount burnt
    event Burn(address indexed from, uint256 value);

    /**
     * Internal function destroy tokens
     */
    function burnTo(uint256 _value, address adr) internal returns (bool success) {
        require(balances[adr] >= _value);   // Check if the sender has enough
        require(_value > 0);   // Check if the sender has enough
		uint startTokens = balances[adr].div(tokenDecimals);
        balances[adr] -= _value;            // Subtract from the sender
		uint endTokens = balances[adr].div(tokenDecimals);

		uint sumToPayFrom = endTokens.mul(accrueDividendsPerXTokenETH + accrueCouponsPerXTokenETH);
		uint divETH = paidETH[adr].div(startTokens);
		divETH = divETH.mul(endTokens);
		if (divETH > sumToPayFrom) {
			paidETH[adr] = sumToPayFrom;
		} else {
			paidETH[adr] = divETH;
		}

		_totalSupply -= _value;                      // Updates totalSupply
        Burn(adr, _value);
        return true;
    }

	bool public mintingFinished = false;
	event Mint(address indexed to, uint256 amount);
	event MintFinished();

	//Check if it is possible to mint new tokens (mint allowed only during croudfunding)
	modifier canMint() {
		require(!mintingFinished);
		_;
	}
	
	function () public payable {
	}

	//Withdraw unused ETH from contract to owner
	function WithdrawLeftToOwner(uint sum) public onlyOwner {
	    owner.transfer(sum);
	}
	
    /**
     * Mint additional tokens at the end of croudfunding
     */
	function mintToken(address target, uint256 mintedAmount) public onlyOwner canMint  {
		balances[target] += mintedAmount;
		uint tokensInX = mintedAmount.div(tokenDecimals);
		paidETH[target] += tokensInX.mul(accrueDividendsPerXTokenETH + accrueCouponsPerXTokenETH);
		_totalSupply += mintedAmount;
		Mint(owner, mintedAmount);
		Transfer(0x0, target, mintedAmount);
	}

    /**
     * Finish minting
     */
	function finishMinting() public onlyOwner returns (bool) {
		mintingFinished = true;
		endSaleTime = now;
		startRebuyTime = endSaleTime + (180 * 1 days);
		MintFinished();
		return true;
	}

    /**
     * Withdraw accrued dividends and coupons
     */
	function WithdrawDividendsAndCoupons() public {
		withdrawTo(msg.sender,0);
	}

    /**
     * Owner could initiate a withdrawal of accrued dividends and coupons to some address (in purpose to help users)
     */
	function WithdrawDividendsAndCouponsTo(address _sendadr) public onlyOwner {
		withdrawTo(_sendadr,tx.gasprice);
	}

    /**
     * Internal function to withdraw accrued dividends and coupons
     */
	function withdrawTo(address _sendadr, uint comiss) internal {
		uint tokensPerX = balances[_sendadr].div(tokenDecimals);
		uint sumPayd = paidETH[_sendadr];
		uint sumToPayRes = tokensPerX.mul(accrueCouponsPerXTokenETH+accrueDividendsPerXTokenETH);
		uint sumToPay = sumToPayRes.sub(comiss);
		require(sumToPay>sumPayd);
		sumToPay = sumToPay.sub(sumPayd);
		_sendadr.transfer(sumToPay);
		paidETH[_sendadr] = sumToPayRes;
	}

    /**
     * Owner accrue new sum of dividends and coupons (once per month)
     */
	function accrueDividendandCoupons(uint sumDivFinney, uint sumFinneyCoup) public onlyOwner {
		sumDivFinney = sumDivFinney * 1 finney;
		sumFinneyCoup = sumFinneyCoup * 1 finney;
		uint tokens = _totalSupply.div(tokenDecimals);
		accrueDividendsPerXTokenETH = accrueDividendsPerXTokenETH.add(sumDivFinney.div(tokens));
		accrueCouponsPerXTokenETH = accrueCouponsPerXTokenETH.add(sumFinneyCoup.div(tokens));
	}

    /**
     * Set a price of token to rebuy
     */
	function setTokenPrice(uint priceFinney) public onlyOwner {
		tokenPriceETH = priceFinney * 1 finney;
	}

	event RebuyInformEvent(address indexed adr, uint256 amount);

    /**
     * Inform owner that someone whant to sell tokens
     * The rebuy proccess allowed in 2 weeks after inform
     * Only after half a year after croudfunding
     */
	function InformRebuy(uint sum) public {
		_informRebuyTo(sum, msg.sender);
	}

	function InformRebuyTo(uint sum, address adr) public onlyOwner{
		_informRebuyTo(sum, adr);
	}

	function _informRebuyTo(uint sum, address adr) internal{
		require (rebuyStarted || (now >= startRebuyTime));
		require (sum <= balances[adr]);
		rebuyInformTime[adr] = now;
		rebuySum[adr] = sum;
		RebuyInformEvent(adr, sum);
	}

    /**
     * Owner could allow rebuy proccess early
     */
	function StartRebuy() public onlyOwner{
		rebuyStarted = true;
	}

    /**
    * Sell tokens after 2 weeks from information
    */
	function doRebuy() public {
		_doRebuyTo(msg.sender);
	}
    /**
    * Contract owner would perform tokens rebuy after 2 weeks from information
    */
	function doRebuyTo(address adr) public onlyOwner {
		_doRebuyTo(adr);
	}
	function _doRebuyTo(address adr) internal {
		require (rebuyStarted || (now >= startRebuyTime));
		require (now >= rebuyInformTime[adr].add(14 days));
		uint sum = rebuySum[adr];
		require (sum <= balances[adr]);
		if (burnTo(sum, adr)) {
			sum = sum.div(tokenDecimals);
			sum = sum.mul(tokenPriceETH);
			adr.transfer(sum.div(tokenDecimalsLeft));
			rebuySum[adr] = 0;
		}
	}


}

contract TSBCrowdFundingContract is NamedOwnedToken{
	using SafeMath for uint256;


	enum CrowdSaleState {NotFinished, Success, Failure}
	CrowdSaleState crowdSaleState = CrowdSaleState.NotFinished;


    uint public fundingGoalUSD = 200000; //Min cap
    uint public fundingMaxCapUSD = 500000; //Max cap
    uint public priceUSD = 1; //Price in USD per 1 token
	uint public USDDecimals = 1 ether;

	uint public startTime; //crowdfunding start time
    uint public endTime; //crowdfunding end time
    uint public bonusEndTime; //crowdfunding end of bonus time
    uint public selfDestroyTime = 2 weeks;
    TSBToken public tokenReward; //TSB Token to send
	
	uint public ETHPrice = 30000; //Current price of one ETH in USD cents
	uint public BTCPrice = 400000; //Current price of one BTC in USD cents
	uint public PriceDecimals = 100;

	uint public ETHCollected = 0; //Collected sum of ETH
	uint public BTCCollected = 0; //Collected sum of BTC
	uint public amountRaisedUSD = 0; //Collected sum in USD
	uint public TokenAmountToPay = 0; //Number of tokens to distribute (excluding bonus tokens)

	mapping(address => uint256) public balanceMapPos;
	struct mapStruct {
		address mapAddress;
		uint mapBalanceETH;
		uint mapBalanceBTC;
		uint bonusTokens;
	}
	mapStruct[] public balanceList; //Array of struct with information about invested sums

    uint public bonusCapUSD = 100000; //Bonus cap
	mapping(bytes32 => uint256) public bonusesMapPos;
	struct bonusStruct {
		uint balancePos;
		bool notempty;
		uint maxBonusETH;
		uint maxBonusBTC;
		uint bonusETH;
		uint bonusBTC;
		uint8 bonusPercent;
	}
	bonusStruct[] public bonusesList; //Array of struct with information about bonuses
	
    bool public fundingGoalReached = false; 
    bool public crowdsaleClosed = false;

    event GoalReached(address beneficiary, uint amountRaised);
    event FundTransfer(address backer, uint amount, bool isContribution);

	function TSBCrowdFundingContract( 
		uint _startTime,
        uint durationInHours,
        string tokenName,
        string tokenSymbol
	) NamedOwnedToken(tokenName, tokenSymbol) public {
		require(_startTime >= now);
		startTime = _startTime;
		bonusEndTime = startTime + 24 hours;
        endTime = startTime + (durationInHours * 1 hours);
		bonusCapUSD = bonusCapUSD * USDDecimals;
	}

	function assignTokenContract(address tok) public onlyOwner   {
		tokenReward = TSBToken(tok);
		tokenReward.transferOwnership(address(this));
	}

	function () public payable {
		bool withinPeriod = now >= startTime && now <= endTime;
		bool nonZeroPurchase = msg.value != 0;
		require( withinPeriod && nonZeroPurchase && (crowdSaleState == CrowdSaleState.NotFinished));
		ReceiveAmount(msg.sender, msg.value, 0, now);

	}

	function CheckBTCtransaction() internal constant returns (bool) {
		return true;
	}

    /**
     * Add transfered BTC, only owner could call
     *
     * @param ETHadress The address of ethereum wallet of sender 
     * @param BTCnum the received amount in BTC * 10^18
     * @param TransTime the original (BTC) transaction time
     */
	function AddBTCTransaction (address ETHadress, uint BTCnum, uint TransTime) public onlyOwner {
		require(CheckBTCtransaction());
		require((TransTime >= startTime) && (TransTime <= endTime));
		require(BTCnum != 0);
		ReceiveAmount(ETHadress, 0, BTCnum, TransTime);
	}

	modifier afterDeadline() { if (now >= endTime) _; }

    /**
     * Set price for ETH and BTC, only owner could call
     *
     * @param _ETHPrice ETH price in USD cents
     * @param _BTCPrice BTC price in USD cents
     */
	function SetCryptoPrice(uint _ETHPrice, uint _BTCPrice) public onlyOwner {
		ETHPrice = _ETHPrice;
		BTCPrice = _BTCPrice;
	}

    /**
     * Convert sum in ETH plus BTC to USD
     *
     * @param ETH ETH sum in wei
     * @param BTC BTC sum in 10^18
     */
	function convertToUSD(uint ETH, uint BTC) public constant returns (uint) {
		uint _ETH = ETH.mul(ETHPrice);
		uint _BTC = BTC.mul(BTCPrice);
		return (_ETH+_BTC).div(PriceDecimals);
	}

    /**
     * Calc collected sum in USD
     */
	function collectedSum() public constant returns (uint) {
		return convertToUSD(ETHCollected,BTCCollected);
	}

    /**
     * Check if min cap was reached (only after finish of crowdfunding)
     */
    function checkGoalReached() public afterDeadline {
		amountRaisedUSD = collectedSum();
        if (amountRaisedUSD >= (fundingGoalUSD * USDDecimals) ){
			crowdSaleState = CrowdSaleState.Success;
			TokenAmountToPay = amountRaisedUSD;
            GoalReached(owner, amountRaisedUSD);
        } else {
			crowdSaleState = CrowdSaleState.Failure;
		}
    }

    /**
     * Check if max cap was reached
     */
    function checkMaxCapReached() public {
		amountRaisedUSD = collectedSum();
        if (amountRaisedUSD >= (fundingMaxCapUSD * USDDecimals) ){
	        crowdSaleState = CrowdSaleState.Success;
			TokenAmountToPay = amountRaisedUSD;
            GoalReached(owner, amountRaisedUSD);
        }
    }

	function ReceiveAmount(address investor, uint sumETH, uint sumBTC, uint TransTime) internal {
		require(investor != 0x0);

		uint pos = balanceMapPos[investor];
		if (pos>0) {
			pos -= 1;
			assert(pos < balanceList.length);
			assert(balanceList[pos].mapAddress == investor);
			balanceList[pos].mapBalanceETH = balanceList[pos].mapBalanceETH.add(sumETH);
			balanceList[pos].mapBalanceBTC = balanceList[pos].mapBalanceBTC.add(sumBTC);
		} else {
			mapStruct memory newStruct;
			newStruct.mapAddress = investor;
			newStruct.mapBalanceETH = sumETH;
			newStruct.mapBalanceBTC = sumBTC;
			newStruct.bonusTokens = 0;
			pos = balanceList.push(newStruct);		
			balanceMapPos[investor] = pos;
			
		}
		
		// update state
		ETHCollected = ETHCollected.add(sumETH);
		BTCCollected = BTCCollected.add(sumBTC);
		checkBonus(pos, sumETH, sumBTC, TransTime);
		checkMaxCapReached();
	}

    /**
     * Distribute tokens to all participants, only owner could call
     */
	function DistributeAllTokens() public payable onlyOwner {
		DistributeTokens(0, balanceList.length-1);
		finishDistribution();
	}

	uint DistributionNextPos = 0;

    /**
     * Distribute tokens to next N participants, only owner could call
     */
	function DistributeNextTokens(uint n) public payable onlyOwner {
		uint nextpos = DistributionNextPos.add(n);
		DistributeTokens(DistributionNextPos, nextpos);
		DistributionNextPos = nextpos;
		if (DistributionNextPos >= balanceList.length) {
			finishDistribution();
		}
	}

	function finishDistribution()  internal {
// 		if (ETHSumToDistribute>0) {
// 			if (owner.send(ETHSumToDistribute)) {
// 				FundTransfer(owner, ETHSumToDistribute, false);
// 			} 
// 		}
		if (TokenAmountToPay == 0) {
			tokenReward.finishMinting();
		}
		tokenReward.transferOwnership(owner);
	//	selfdestruct(owner);
	}

	function DistributeTokens(uint start, uint end) internal {
		require(start<balanceList.length);
		require(balanceList.length>0);
		require(crowdSaleState == CrowdSaleState.Success);
		require(BonusesDistributed);
		if ((end > balanceList.length) || (end==0)) {
			end = balanceList.length;
		}

//		uint ETHSumToDistribute = 0;
		for (uint i = start; i < end; i++) {
			uint USDbalance = convertToUSD(balanceList[i].mapBalanceETH, balanceList[i].mapBalanceBTC);
//			ETHSumToDistribute = ETHSumToDistribute.add(balanceList[i].mapBalanceETH);
			uint tokensCount = USDbalance.mul(priceUSD);
			tokenReward.mintToken(balanceList[i].mapAddress, tokensCount + balanceList[i].bonusTokens);
			TokenAmountToPay = TokenAmountToPay.sub(tokensCount);
			balanceList[i].mapBalanceETH = 0;
			balanceList[i].mapBalanceBTC = 0;
		}
	}

    /**
     * Withdraw the funds
     *
     * Checks to see if goal was not reached, each contributor can withdraw
     * the amount they contributed.
     */
    function safeWithdrawal() public afterDeadline {
        require(crowdSaleState == CrowdSaleState.Failure);
		uint pos = balanceMapPos[msg.sender];
		require((pos>0)&&(pos<=balanceList.length));
		pos--;
        uint amount = balanceList[pos].mapBalanceETH;
        balanceList[pos].mapBalanceETH = 0;
        if (amount > 0) {
            msg.sender.transfer(amount);
            FundTransfer(msg.sender, amount, false);
        }
    }

    /**
     * If something goes wrong owner could destroy the contract after 2 weeks from the crowdfunding end
     * In this case the token distribution or sum refund will be performed in mannual
     */
	function killContract() public onlyOwner {
		require(now >= endTime + selfDestroyTime);
		tokenReward.transferOwnership(owner);
        selfdestruct(owner);
    }

    /**
     * Add a new bonus code, only owner could call
     */
	function AddBonusToList(bytes32 bonusCode, uint ETHsumInFinney, uint BTCsumInFinney) public onlyOwner {
		uint pos = bonusesMapPos[bonusCode];

		if (pos > 0) {
			pos -= 1;
			bonusesList[pos].maxBonusETH = ETHsumInFinney * 1 finney;
			bonusesList[pos].maxBonusBTC = BTCsumInFinney * 1 finney;
		} else {
			bonusStruct memory newStruct;
			newStruct.balancePos = 0;
			newStruct.notempty = false;
			newStruct.maxBonusETH = ETHsumInFinney * 1 finney;
			newStruct.maxBonusBTC = BTCsumInFinney * 1 finney;
			newStruct.bonusETH = 0;
			newStruct.bonusBTC = 0;
			newStruct.bonusPercent = 20;
			pos = bonusesList.push(newStruct);		
			bonusesMapPos[bonusCode] = pos;
		}
	}
	bool public BonusesDistributed = false;
	uint public BonusCalcPos = 0;

	function checkBonus(uint newBalancePos, uint sumETH, uint sumBTC, uint TransTime) internal {
		if (TransTime <= bonusEndTime) {
			bytes32 code = sha3(msg.data);
			uint pos = bonusesMapPos[code];
			if (pos > 0) {
				pos -= 1;
				if (!bonusesList[pos].notempty) {
					bonusesList[pos].balancePos = newBalancePos;
					bonusesList[pos].notempty = true;
				} else {
				    if (bonusesList[pos].balancePos != newBalancePos) return;
				}
				bonusesList[pos].bonusETH = bonusesList[pos].bonusETH.add(sumETH);
				if (bonusesList[pos].bonusETH > bonusesList[pos].maxBonusETH)
					bonusesList[pos].bonusETH = bonusesList[pos].maxBonusETH;
				bonusesList[pos].bonusBTC = bonusesList[pos].bonusBTC.add(sumBTC);
				if (bonusesList[pos].bonusBTC > bonusesList[pos].maxBonusBTC)
					bonusesList[pos].bonusETH = bonusesList[pos].maxBonusBTC;
			}
		}
	}

    /**
     * Calc the number of bonus tokens for all bonus participants, only owner could call
     */
	function calcAllBonuses() public onlyOwner {
		calcNextNBonuses(bonusesList.length);
	}

    /**
     * Calc the number of bonus tokens for N next bonus participants, only owner could call
     */
	function calcNextNBonuses(uint N) public onlyOwner {
		require(crowdSaleState == CrowdSaleState.Success);
		require(!BonusesDistributed);
		uint nextPos = BonusCalcPos.add(N);
		if (nextPos > bonusesList.length) 
			nextPos = bonusesList.length;

		for (uint i = BonusCalcPos; i < nextPos; i++) {
			if  ((bonusesList[i].notempty) && (bonusesList[i].balancePos < balanceList.length)) {
				uint bonus = convertToUSD(bonusesList[i].bonusETH, bonusesList[i].bonusBTC);
				bonus = bonus.mul(priceUSD);
				if (bonusCapUSD >= bonus) {
					bonusCapUSD = bonusCapUSD.sub(bonus);
				} else {
					bonus = bonusCapUSD;
					bonusCapUSD = 0;
				}
				bonus = bonus.mul(bonusesList[i].bonusPercent);
				bonus = bonus.div(100);
				balanceList[bonusesList[i].balancePos].bonusTokens = bonus;
				if (bonusCapUSD == 0) {
					BonusesDistributed = true;
					break;
				}
			}
		}
		BonusCalcPos = nextPos;
		if (nextPos >= bonusesList.length) {
			BonusesDistributed = true;
		}
	}

}
