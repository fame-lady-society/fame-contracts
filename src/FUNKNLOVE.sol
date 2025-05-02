// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/*                                                                                                                                                            
                                 +#+                                                                    
                  #+##################                                                                  
            #############+++-----+###    --                           ################                  
   --+++#######+++-----------..--+### --                              ###--+++#+######                  
   -++##++--------------------.--+## ++  ++ --                      ++ ##---------+###                  
    ++#+-------------------------###+++  +  ++                        ###---------+###      ---         
     +##---------------------++++##+                                  ###---------+##    ##             
    ++##+---------+++##############           +### ######### #####    ###--------+###  ########+  --    
     ###+--------+######++++++#+####################################  ###--------+## ###+-++#####+++    
     +##+--------+####++   ####++++-++###+-+---+###+-----+#+----++### ##+----..--+####+--------++###+   
    -+##---------+############+------+###+-----+###----------------#####+-------+###+----------+####+   
   --###---------+###+++---###+------####+-----+###----------------+####-----.--+#+----------+####+     
     ###+------------------###------+####------####----------------+####------------------+#####        
    ++##-------------------###------+####-----+####------+###------+###+----------------+###+           
    ++##------------------+###------####+-----+###+-----+####------+###+--------------+####             
     +##------------++########-----+####+-----+###+-----+####------+###----------------+###             
     ###-.--------############-.---+####------+###+-----#####------####-----------------###+            
    +###---------+####+    ##+.----+####------+###------#####------####--------##--------###            
     ###---------+###+     ##+-------+--------+###-----+####+-----+###+--------###-------+###           
     ###---------+###      ###----------------###+-----+####+-----+###--------+###+-------+###          
     ###---------+###      ###+---------+-----###+-----+####------+###--------+####+------++###         
     +##---------++###      ####+----+###+++++##############------####--------+#####-------+###         
     ###---------++###      +########################################+--------### ##+-------+###        
     ###------+++#####+       ++######+   ###################  ##################  ##+++++++++###       
     ###--++#######++++                    ###++++#+++++++###         +++++######  ##############+      
     #########++                            ##+++++++++++++##                                 +++++     
     #####+         ####                    ##++++#####++++##                                           
          ###############                   ##+++######+++###                        ++                 
     ############++++###                   ###+++### ##+++###           +      ############             
    +####++++++++++++###                   ##################      ##############++++++++#####          
      ###+++++++++++###                   #########  ##########   #####++++####++++++++++++####         
      ####++++++++++###              ############ ############## ###++++++###++++++++++++++++###        
     ++###++++++++++###            ####++++++++######++++++++### ##++++++###++++++++##+++++++####       
     +####++++++++++##            ###+++++++++++++####++++++++## ##++++++##+++++++#####+++++++###       
      ####+++++++++###          ###++++++++++++++++###++++++++#####+++++##+++++++#######+++++++##       
      ####+++++++++###         ###++++++++##++++++++###+++++++####+++++##+++++++######+++++++++###      
      ###++++++++++###        ###+++++++######+++++++##+++++++###++++++##+++++++##+++++++++++++###      
      ###++++++++++##         ##++++++++######+++++++##+++++++###+++++##++++++++++++++++++++######      
      ###++++++++++##        ###+++++++#### ##+++++++###++++++##++++++##++++++++++++++++#######         
      ###+++++++++###        ###++++++####  ##+++++++###+++++++#+++++###+++++++++++++#########          
      ###+++++++++###        ##+++++++###   ##++++++++##+++++++++++++###+++++++++######## #####         
      ###+++++++++###        ##+++++++###   ##++++++++###+++++++++++####++++++++#####   ####+###        
      ###+++++++++##+        ##+++++++###   ##+++++++####+++++++++++####++++++++###    ####+++####      
      ###++++++++####       +##+++++++###  ###+++++++####++++++++++#####+++++++++########+++++++####    
      ###++++++++###    #######++++++++######++++++++#####+++++++++######++++++++++###+++++++++++###+   
      ###++++++++##########+++##++++++++####++++++++######+++++++++## ####++++++++++++++++++++++####    
      ##+++++++++####+++++++++##+++++++++++++++++++###  ##++++++++###  ####+++++++++++++++++++#####     
     ###++++++++++++++++++++++###+++++++++++++++++###   ###+++++++###   ####+++++++++++++++++####       
     ###+++++++++++++++++++++#####++++++++++++++####    ###++++++####     ####++++++++++++#####         
     ###+++++++++++++++++++++#######++++++++++#####     #############      ######++++++######           
     ###+++++++++++++++++#######+################         ##+#++###++         ############              
     ##++++++#################+#    ##########+                                  ##+++                  
    ##################++#              + +++                                                            
   +####+++#                                                                                            
                                                                                                        
*/

/**
 *
 *
 * @title FUNKNLOVE.sol
 * @author 0xflick
 * @notice This contract is a community effort of the fame lady society
 * @dev This contract is an efficient ERC1155 contract that allows users to mint a token.
 *
 */
import {ERC1155} from "solady/tokens/ERC1155.sol";
import {OwnableRoles} from "solady/auth/OwnableRoles.sol";

contract FUNKNLOVE is ERC1155, OwnableRoles {
    // The FLS Exodus Road donation address (see https://etherscan.io/address/0x31535f40ef8a583d7Ba7372586759a6666a45a6D#internaltx for donation history)
    address public constant FLS_EXODUS_ROAD_DONATION_ADDRESS = 0x31535f40ef8a583d7Ba7372586759a6666a45a6D;
    // The Fame Lady Society multisig wallet at vault.fameladysociety.eth
    address public constant FLS_VAULT_ADDRESS = 0xCDF3e235A04624d7f23909EbBaD008Db2c54e1cF;

    uint64 private START_TIME;
    uint64 private END_TIME;

    enum Tier {
        BRONZE,
        SILVER,
        GOLD
    }

    struct MintRequest {
        uint32 bronze;
        uint32 silver;
        uint32 gold;
    }

    uint256 private BRONZE_MINT_PRICE = 0.00333 ether;
    uint256 private SILVER_MINT_PRICE = 0.022 ether;
    uint256 private GOLD_MINT_PRICE = 0.1 ether;

    // ERC721 identifiers
    string constant NAME = "Funk N' Love";
    string constant SYMBOL = "FUNKNLOVE";

    // Supply
    uint256 private BRONZE_SUPPLY;
    uint256 private SILVER_SUPPLY;
    uint256 private GOLD_SUPPLY;
    uint256 private constant GIVEAWAY_ROLE = _ROLE_0;
    uint256 private constant WITHDRAW_ROLE = _ROLE_1;
    // Base URI for token metadata
    string private BASE_URI;

    // Free airdrop limit
    uint256 private freeMintLimit = 33;

    constructor(uint64 _startTime, uint64 _endTime, string memory _baseURI) {
        START_TIME = _startTime;
        END_TIME = _endTime;
        BASE_URI = _baseURI;
        _initializeOwner(msg.sender);
        _grantRoles(FLS_VAULT_ADDRESS, WITHDRAW_ROLE);
    }

    function name() public pure returns (string memory) {
        return NAME;
    }

    function symbol() public pure returns (string memory) {
        return SYMBOL;
    }

    function totalSupply() public view returns (uint256) {
        return BRONZE_SUPPLY + SILVER_SUPPLY + GOLD_SUPPLY;
    }

    error InvalidTier();

    function mintPrice(Tier tier) public view returns (uint256) {
        if (tier == Tier.BRONZE) {
            return BRONZE_MINT_PRICE;
        } else if (tier == Tier.SILVER) {
            return SILVER_MINT_PRICE;
        } else if (tier == Tier.GOLD) {
            return GOLD_MINT_PRICE;
        }
        revert InvalidTier();
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        return BASE_URI;
    }

    function setBaseURI(string memory newBaseURI) external onlyOwner {
        BASE_URI = newBaseURI;
    }

    error MintMustNotBeStarted();

    function setStartTime(uint64 newStartTime) external onlyOwner {
        if (START_TIME < uint64(block.timestamp)) revert MintMustNotBeStarted();
        START_TIME = newStartTime;
    }

    error MintMustNotBeEnded();

    function setEndTime(uint64 newEndTime) external onlyOwner {
        if (END_TIME < uint64(block.timestamp)) revert MintMustNotBeEnded();
        END_TIME = newEndTime;
    }

    function getStartTime() external view returns (uint64) {
        return START_TIME;
    }

    function getEndTime() external view returns (uint64) {
        return END_TIME;
    }

    function isMintOpen() external view returns (bool) {
        return uint64(block.timestamp) >= START_TIME && uint64(block.timestamp) <= END_TIME;
    }

    function getBronzePrice() external view returns (uint256) {
        return BRONZE_MINT_PRICE;
    }

    function getBronzeSupply() external view returns (uint256) {
        return BRONZE_SUPPLY;
    }

    function getSilverPrice() external view returns (uint256) {
        return SILVER_MINT_PRICE;
    }

    function getSilverSupply() external view returns (uint256) {
        return SILVER_SUPPLY;
    }

    function getGoldPrice() external view returns (uint256) {
        return GOLD_MINT_PRICE;
    }

    function getGoldSupply() external view returns (uint256) {
        return GOLD_SUPPLY;
    }

    error MintMustBeGreaterThanZero();
    error WrongPayment();

    modifier enoughPayment(MintRequest memory mintRequest) {
        uint256 total = mintRequest.bronze + mintRequest.silver + mintRequest.gold;
        if (total == 0) revert MintMustBeGreaterThanZero();

        uint256 cost = mintRequest.bronze * BRONZE_MINT_PRICE + mintRequest.silver * SILVER_MINT_PRICE
            + mintRequest.gold * GOLD_MINT_PRICE;
        if (msg.value != cost) revert WrongPayment();
        _;
    }

    error PublicMintNotStarted();
    error PublicMintEnded();

    /**
     * @notice Public mint function
     * @dev Public mint function that allows users to mint tokens
     * @param mintRequest The mint request containing the number of tokens to mint for each tier.
     */
    function publicMint(MintRequest memory mintRequest) external payable enoughPayment(mintRequest) {
        if (uint64(block.timestamp) < START_TIME) revert PublicMintNotStarted();
        if (uint64(block.timestamp) > END_TIME) revert PublicMintEnded();
        if (mintRequest.bronze > 0) {
            _mint(msg.sender, 0, uint256(mintRequest.bronze), "");
        }
        if (mintRequest.silver > 0) {
            _mint(msg.sender, 1, uint256(mintRequest.silver), "");
        }
        if (mintRequest.gold > 0) {
            _mint(msg.sender, 2, uint256(mintRequest.gold), "");
        }
    }

    error FreeMintLimitReached();
    /**
     * @notice Airdrop mint function
     * @dev This function is only intended to be used by the mint team to mint tokens (bronze only) for giveaways.
     * The GIVEAWAY_ROLE is set to Blü
     */

    function airdropMint(address to, uint256 amount) external onlyRoles(GIVEAWAY_ROLE) {
        if (freeMintLimit < amount) revert FreeMintLimitReached();
        freeMintLimit -= amount;
        _mint(to, 0, amount, "");
    }

    error FailedToSendEther();
    error MintNotEnded();

    /**
     * @notice Withdraw function
     * @dev This function is only intended to be used after the mint has ended. Anyone can call this function to
     * donate the mint proceeds to the FLS Exodus Road donation address. The FLS_DONATION_ADDRESS is set to the
     * FLS Exodus Road donation address that has been verified by the Fame Lady Society team and used for more
     * than two years of donations.
     */
    function withdrawFLSExodusRoadDonation() external {
        if (uint64(block.timestamp) < END_TIME) revert MintNotEnded();
        (bool success,) = FLS_EXODUS_ROAD_DONATION_ADDRESS.call{value: address(this).balance}("");
        if (!success) revert FailedToSendEther();
    }

    /**
     * @notice Emergency withdraw function
     * @dev This function is only intended to be used in case of emergency. During the normal course of
     * operations the contract should only allow a single lump sum withdrawal after the mint has ended.
     * The Fame Lady Society multisig wallet at vault.fameladysociety.eth is the only address that should
     * have the WITHDRAW_ROLE.
     */
    function emergencyWithdraw() external onlyRoles(WITHDRAW_ROLE) {
        (bool success,) = FLS_VAULT_ADDRESS.call{value: address(this).balance}("");
        if (!success) revert FailedToSendEther();
    }

    function _useBeforeTokenTransfer() internal view virtual override returns (bool) {
        return true;
    }
    /**
     * @notice Overrides the ERC1155 _beforeTokenTransfer function
     * @dev This function is used to update the supply of the token
     */

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override {
        if (from == address(0)) {
            for (uint256 i = 0; i < ids.length; i++) {
                if (ids[i] == 0) {
                    BRONZE_SUPPLY += amounts[i];
                } else if (ids[i] == 1) {
                    SILVER_SUPPLY += amounts[i];
                } else if (ids[i] == 2) {
                    GOLD_SUPPLY += amounts[i];
                }
            }
        } else if (to == address(0)) {
            for (uint256 i = 0; i < ids.length; i++) {
                if (ids[i] == 0) {
                    BRONZE_SUPPLY -= amounts[i];
                } else if (ids[i] == 1) {
                    SILVER_SUPPLY -= amounts[i];
                } else if (ids[i] == 2) {
                    GOLD_SUPPLY -= amounts[i];
                }
            }
        }
    }
}
